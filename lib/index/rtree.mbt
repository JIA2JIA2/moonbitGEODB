// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

/// R-tree spatial index (Guttman, 1984).
///
/// A balanced, hierarchical bounding-box index over geographic points. Each
/// leaf node stores entry ids; each internal node stores child bounds and the
/// union bounding box of its subtree. It accelerates:
///   - range queries (`search`) in sub-linear time,
///   - k nearest-neighbour queries (`nearest`) via best-first search.
///
/// Node insertion uses a longest-axis median split (a simple, deterministic
/// variant of the sort-tile split family). Deletion re-inserts underfull
/// segments, keeping the tree balanced and the index exact.

///|
/// A single R-tree node. Leaf nodes hold `entries` (entry ids); internal nodes
/// hold `children` (child node ids). `bbox` is the union of everything below.
pub(all) struct RTreeNode {
  mut bbox : @types.BBox
  is_leaf : Bool
  mut children : Array[Int]
  mut entries : Array[String]
  mut parent : Int?
} derive(Eq, Debug)

///|
/// An incrementally updatable R-tree over entry ids. `points` maps an entry id
/// to its location; `nodes` stores tree nodes by id.
pub(all) struct RTree {
  mut root : Int?
  nodes : @hashmap.HashMap[Int, RTreeNode]
  points : @hashmap.HashMap[String, @types.GeoPoint]
  mut next_id : Int
  max_entries : Int
  min_entries : Int
} derive(Eq, Debug)

///|
/// Create an empty R-tree. `max_entries` controls the fan-out (default 8);
/// the minimum fill is half of that.
pub fn RTree::new(max_entries? : Int = 8) -> RTree {
  let m = if max_entries < 4 { 4 } else { max_entries }
  {
    root: None,
    nodes: @hashmap.HashMap([]),
    points: @hashmap.HashMap([]),
    next_id: 0,
    max_entries: m,
    min_entries: m / 2,
  }
}

///|
/// Number of points currently indexed.
pub fn RTree::size(self : RTree) -> Int {
  self.points.length()
}

///|
/// Whether an entry id is present.
pub fn RTree::contains(self : RTree, id : String) -> Bool {
  self.points.contains(id)
}

///|
/// All indexed entry ids (unordered).
pub fn RTree::ids(self : RTree) -> Array[String] {
  self.points.keys().collect()
}

///|
/// Insert (or replace) the location for an entry id.
pub fn RTree::insert(
  self : RTree,
  id : String,
  point : @types.GeoPoint,
) -> Unit {
  if self.points.contains(id) {
    ignore(self.remove(id))
  }
  self.points[id] = point
  self.insert_entry(id, point)
}

///|
/// Remove an entry id. Returns `true` if it was present.
pub fn RTree::remove(self : RTree, id : String) -> Bool {
  let point = match self.points.get(id) {
    None => return false
    Some(p) => p
  }
  match self.root {
    None => false
    Some(root_id) =>
      match self.find_leaf(root_id, point, id) {
        None => false
        Some(lid) => {
          ignore(self.points.remove(id))
          let leaf = self.nodes.get(lid).unwrap()
          leaf.entries = leaf.entries.iter().filter(fn(x) { x != id }).collect()
          self.nodes[lid] = leaf
          self.condense_tree(lid)
          true
        }
      }
  }
}

///|
/// Return all entry ids whose point lies inside `bbox`.
pub fn RTree::search(self : RTree, bbox : @types.BBox) -> Array[String] {
  let out : Array[String] = []
  match self.root {
    None => out
    Some(root_id) => {
      self.search_node(root_id, bbox, out)
      out
    }
  }
}

///|
/// Return up to `k` nearest (id, distance_km) pairs, sorted ascending by
/// distance. Uses best-first search with a chord-distance (triangle-inequality
/// lower bound) prune, so results are exact but only a fraction of the tree is
/// visited.
pub fn RTree::nearest(
  self : RTree,
  point : @types.GeoPoint,
  k : Int,
) -> Array[(String, Double)] {
  if k <= 0 {
    return []
  }
  let root_id = match self.root {
    None => return []
    Some(r) => r
  }
  let n = self.points.length()
  let kk = if k < n { k } else { n }
  // Min-heap emulation: push negated distance so the smallest bound is greatest
  // (moonbit's PriorityQueue is a max-heap).
  let pq : @priority_queue.PriorityQueue[(Double, Int)] = @priority_queue.PriorityQueue([],
  )
  // Max-heap of the best k candidates: top is the current k-th furthest.
  let best : @priority_queue.PriorityQueue[(Double, String)] = @priority_queue.PriorityQueue([],
  )
  pq.push((0.0, root_id))
  while true {
    let (neg_bound, node_id) = match pq.pop() {
      None => break
      Some(x) => x
    }
    let bound = -neg_bound
    // Stop when the nearest possible point in the queue is further than the
    // current k-th best.
    if best.length() == kk {
      match best.peek() {
        Some((kth, _)) => if bound > kth { break }
        None => ()
      }
    }
    let node = self.nodes.get(node_id).unwrap()
    if node.is_leaf {
      for eid in node.entries {
        let d = @geo.haversine(point, self.point_of(eid))
        if best.length() < kk {
          best.push((d, eid))
        } else {
          match best.peek() {
            Some((kth, _)) =>
              if d < kth {
                ignore(best.pop())
                best.push((d, eid))
              }
            None => ()
          }
        }
      }
    } else {
      for cid in node.children {
        let cb = self.nodes.get(cid).unwrap().bbox
        pq.push((-bbox_chord_distance(point, cb), cid))
      }
    }
  }
  let arr = best.to_array() // descending by distance
  arr.rev_in_place() // ascending
  arr.iter().map(fn(p) { (p.1, p.0) }).collect()
}

///|
/// Core tree insertion; assumes `id` is already stored in `points`.
fn RTree::insert_entry(
  self : RTree,
  id : String,
  point : @types.GeoPoint,
) -> Unit {
  match self.root {
    None => {
      let nid = self.alloc_node_id()
      self.nodes[nid] = {
        bbox: point_bbox(point),
        is_leaf: true,
        children: [],
        entries: [id],
        parent: None,
      }
      self.root = Some(nid)
    }
    Some(_) => {
      let leaf_id = self.choose_leaf(point)
      let leaf = self.nodes.get(leaf_id).unwrap()
      leaf.entries.push(id)
      self.adjust_tree(leaf_id)
    }
  }
}

///|
/// Descend from the root to the leaf whose covering box is enlarged least.
fn RTree::choose_leaf(self : RTree, point : @types.GeoPoint) -> Int {
  let mut cur = self.root.unwrap()
  while true {
    let node = self.nodes.get(cur).unwrap()
    if node.is_leaf {
      break cur
    }
    let mut best_child = node.children[0]
    let mut best_enlarge = 1.7976931348623157e+308
    let mut best_area = 1.7976931348623157e+308
    for c in node.children {
      let cb = self.nodes.get(c).unwrap().bbox
      let ub = bbox_union(cb, point_bbox(point))
      let enlarge = bbox_area(ub) - bbox_area(cb)
      let area = bbox_area(cb)
      if enlarge < best_enlarge || (enlarge == best_enlarge && area < best_area) {
        best_child = c
        best_enlarge = enlarge
        best_area = area
      }
    }
    cur = best_child
  } nobreak {
    abort("choose_leaf: missing leaf")
  }
}

///|
/// Recompute the bounding box up the path; split any overfull node.
fn RTree::adjust_tree(self : RTree, start_id : Int) -> Unit {
  let mut cur = start_id
  while true {
    let node = self.nodes.get(cur).unwrap()
    let nb = self.node_bbox(node)
    node.bbox = nb
    self.nodes[cur] = node
    let count = if node.is_leaf {
      node.entries.length()
    } else {
      node.children.length()
    }
    if count <= self.max_entries {
      break
    }
    let new_id = self.split_node(cur)
    match self.nodes.get(cur).unwrap().parent {
      None => {
        let root_id = self.alloc_node_id()
        let root_bbox = bbox_union(
          self.nodes.get(cur).unwrap().bbox,
          self.nodes.get(new_id).unwrap().bbox,
        )
        self.nodes[root_id] = {
          bbox: root_bbox,
          is_leaf: false,
          children: [cur, new_id],
          entries: [],
          parent: None,
        }
        self.root = Some(root_id)
        let c1 = self.nodes.get(cur).unwrap()
        c1.parent = Some(root_id)
        self.nodes[cur] = c1
        let c2 = self.nodes.get(new_id).unwrap()
        c2.parent = Some(root_id)
        self.nodes[new_id] = c2
        break
      }
      Some(pid) => {
        let parent = self.nodes.get(pid).unwrap()
        parent.children.push(new_id)
        self.nodes[pid] = parent
        cur = pid
      }
    }
  }
}

///|
/// Split the overfull node `node_id` into two, returning the new node id.
fn RTree::split_node(self : RTree, node_id : Int) -> Int {
  let node = self.nodes.get(node_id).unwrap()
  let parent = node.parent
  let new_id = self.alloc_node_id()
  if node.is_leaf {
    let bboxes : Array[@types.BBox] = node.entries
      .iter()
      .map(fn(eid) { point_bbox(self.point_of(eid)) })
      .collect()
    let (g1, g2) = split_indices(bboxes)
    let old_entries : Array[String] = []
    let new_entries : Array[String] = []
    for i in g1 {
      old_entries.push(node.entries[i])
    }
    for i in g2 {
      new_entries.push(node.entries[i])
    }
    node.entries = old_entries
    node.bbox = self.bbox_of_entries(old_entries)
    self.nodes[node_id] = node
    self.nodes[new_id] = {
      bbox: self.bbox_of_entries(new_entries),
      is_leaf: true,
      children: [],
      entries: new_entries,
      parent,
    }
  } else {
    let bboxes : Array[@types.BBox] = node.children
      .iter()
      .map(fn(c) { self.nodes.get(c).unwrap().bbox })
      .collect()
    let (g1, g2) = split_indices(bboxes)
    let old_children : Array[Int] = []
    let new_children : Array[Int] = []
    for i in g1 {
      old_children.push(node.children[i])
    }
    for i in g2 {
      new_children.push(node.children[i])
    }
    node.children = old_children
    node.bbox = self.bbox_of_children(old_children)
    self.nodes[node_id] = node
    self.nodes[new_id] = {
      bbox: self.bbox_of_children(new_children),
      is_leaf: false,
      children: new_children,
      entries: [],
      parent,
    }
    for c in new_children {
      let cn = self.nodes.get(c).unwrap()
      cn.parent = Some(new_id)
      self.nodes[c] = cn
    }
  }
  new_id
}

///|
/// Partition bounding boxes into two roughly equal halves, ordered along the
/// longest axis of their union (a deterministic median split).
fn split_indices(bboxes : Array[@types.BBox]) -> (Array[Int], Array[Int]) {
  let n = bboxes.length()
  let mut overall : @types.BBox? = None
  for b in bboxes {
    overall = match overall {
      None => Some(b)
      Some(o) => Some(bbox_union(o, b))
    }
  }
  match overall {
    None => ([], [])
    Some(o) => {
      let axis_lat = o.max_lat - o.min_lat >= o.max_lng - o.min_lng
      let idxs : Array[Int] = []
      let mut i = 0
      while i < n {
        idxs.push(i)
        i = i + 1
      }
      idxs.sort_by(fn(a, b) {
        let ca = axis_center(bboxes[a], axis_lat)
        let cb = axis_center(bboxes[b], axis_lat)
        if ca < cb {
          -1
        } else if ca > cb {
          1
        } else {
          0
        }
      })
      let mid = n / 2
      let g1 : Array[Int] = []
      let g2 : Array[Int] = []
      let mut j = 0
      while j < n {
        if j < mid {
          g1.push(idxs[j])
        } else {
          g2.push(idxs[j])
        }
        j = j + 1
      }
      (g1, g2)
    }
  }
}

///|
/// Find the leaf node that should contain `id`.
fn RTree::find_leaf(
  self : RTree,
  node_id : Int,
  point : @types.GeoPoint,
  id : String,
) -> Int? {
  let node = self.nodes.get(node_id).unwrap()
  if node.is_leaf {
    for eid in node.entries {
      if eid == id {
        return Some(node_id)
      }
    }
    return None
  }
  for c in node.children {
    let cb = self.nodes.get(c).unwrap().bbox
    if @geo.bbox_contains(cb, point) {
      match self.find_leaf(c, point, id) {
        Some(l) => return Some(l)
        None => ()
      }
    }
  }
  None
}

///|
/// After a deletion, walk up the tree: drop underfull nodes and shrink the
/// root if it collapses; then re-insert any orphaned entries.
fn RTree::condense_tree(self : RTree, leaf_id : Int) -> Unit {
  let reinsert : Array[String] = []
  let root_id = match self.root {
    None => return
    Some(r) => r
  }
  let mut cur = leaf_id
  while cur != root_id {
    let node = self.nodes.get(cur).unwrap()
    let parent_id = match node.parent {
      None => break
      Some(p) => p
    }
    let count = if node.is_leaf {
      node.entries.length()
    } else {
      node.children.length()
    }
    if count < self.min_entries {
      let parent = self.nodes.get(parent_id).unwrap()
      parent.children = parent.children
        .iter()
        .filter(fn(c) { c != cur })
        .collect()
      self.nodes[parent_id] = parent
      self.collect_entries_drop(cur, reinsert)
    }
    cur = parent_id
  }
  match self.root {
    None => ()
    Some(r) => {
      let rn = self.nodes.get(r).unwrap()
      let rc = if rn.is_leaf {
        rn.entries.length()
      } else {
        rn.children.length()
      }
      if !rn.is_leaf && rc == 1 {
        let only = rn.children[0]
        self.root = Some(only)
        ignore(self.nodes.remove(r))
        let cn = self.nodes.get(only).unwrap()
        cn.parent = None
        self.nodes[only] = cn
      } else if rn.is_leaf && rc == 0 {
        self.root = None
        ignore(self.nodes.remove(r))
      } else {
        rn.bbox = self.node_bbox(rn)
        self.nodes[r] = rn
      }
    }
  }
  for eid in reinsert {
    match self.points.get(eid) {
      Some(p) => self.insert_entry(eid, p)
      None => ()
    }
  }
}

///|
/// Recursively gather every entry id beneath `node_id`, dropping the nodes.
fn RTree::collect_entries_drop(
  self : RTree,
  node_id : Int,
  out : Array[String],
) -> Unit {
  let node = self.nodes.get(node_id).unwrap()
  if node.is_leaf {
    for eid in node.entries {
      out.push(eid)
    }
  } else {
    for c in node.children {
      self.collect_entries_drop(c, out)
    }
  }
  ignore(self.nodes.remove(node_id))
}

///|
/// Recursively collect ids whose points fall within `bbox`.
fn RTree::search_node(
  self : RTree,
  node_id : Int,
  bbox : @types.BBox,
  out : Array[String],
) -> Unit {
  let node = self.nodes.get(node_id).unwrap()
  if node.is_leaf {
    for eid in node.entries {
      if @geo.bbox_contains(bbox, self.point_of(eid)) {
        out.push(eid)
      }
    }
  } else {
    for c in node.children {
      let cb = self.nodes.get(c).unwrap().bbox
      if bbox_overlaps(bbox, cb) {
        self.search_node(c, bbox, out)
      }
    }
  }
}

///|
/// Minimum chord (straight-line) distance from `p` to any point in `bbox`.
/// The chord is a strict lower bound of the great-circle distance, so pruning
/// on it never excludes a genuine nearest neighbour.
fn bbox_chord_distance(p : @types.GeoPoint, b : @types.BBox) -> Double {
  let lat = clamp(p.lat, b.min_lat, b.max_lat)
  let lng = clamp(p.lng, b.min_lng, b.max_lng)
  chord_distance(p, @types.GeoPoint::make(lat, lng))
}

///|
/// Straight-line chord distance (km) between two points, via the Haversine
/// angular distance: `2R * sin(theta / 2)`.
fn chord_distance(p1 : @types.GeoPoint, p2 : @types.GeoPoint) -> Double {
  let d = @geo.haversine(p1, p2)
  let half = d / (2.0 * @geo.earth_radius_km)
  2.0 * @geo.earth_radius_km * @math.sin(half)
}

///|
/// Allocate the next node id.
fn RTree::alloc_node_id(self : RTree) -> Int {
  let id = self.next_id
  self.next_id = id + 1
  id
}

///|
/// Lookup a stored point.
fn RTree::point_of(self : RTree, id : String) -> @types.GeoPoint {
  self.points.get(id).unwrap()
}

///|
/// The bounding box of a node's contents.
fn RTree::node_bbox(self : RTree, node : RTreeNode) -> @types.BBox {
  if node.is_leaf {
    self.bbox_of_entries(node.entries)
  } else {
    self.bbox_of_children(node.children)
  }
}

///|
/// Union bounding box of a set of entry ids.
fn RTree::bbox_of_entries(self : RTree, entries : Array[String]) -> @types.BBox {
  let mut b : @types.BBox? = None
  for eid in entries {
    let pb = point_bbox(self.point_of(eid))
    b = match b {
      None => Some(pb)
      Some(x) => Some(bbox_union(x, pb))
    }
  }
  match b {
    None => point_bbox(@types.GeoPoint::make(0.0, 0.0))
    Some(x) => x
  }
}

///|
/// Union bounding box of a set of child nodes.
fn RTree::bbox_of_children(self : RTree, children : Array[Int]) -> @types.BBox {
  let mut b : @types.BBox? = None
  for c in children {
    let cb = self.nodes.get(c).unwrap().bbox
    b = match b {
      None => Some(cb)
      Some(x) => Some(bbox_union(x, cb))
    }
  }
  match b {
    None => point_bbox(@types.GeoPoint::make(0.0, 0.0))
    Some(x) => x
  }
}

///|
/// A degenerate point-as-bbox.
fn point_bbox(p : @types.GeoPoint) -> @types.BBox {
  { min_lat: p.lat, max_lat: p.lat, min_lng: p.lng, max_lng: p.lng, }
}

///|
/// Union of two bounding boxes.
fn bbox_union(a : @types.BBox, b : @types.BBox) -> @types.BBox {
  {
    min_lat: min2(a.min_lat, b.min_lat),
    max_lat: max2(a.max_lat, b.max_lat),
    min_lng: min2(a.min_lng, b.min_lng),
    max_lng: max2(a.max_lng, b.max_lng),
  }
}

///|
/// Axis-aligned area (degrees²), sufficient for split/choose heuristics.
fn bbox_area(b : @types.BBox) -> Double {
  (b.max_lat - b.min_lat) * (b.max_lng - b.min_lng)
}

///|
/// Do two bounding boxes overlap?
fn bbox_overlaps(a : @types.BBox, b : @types.BBox) -> Bool {
  a.min_lat <= b.max_lat &&
  a.max_lat >= b.min_lat &&
  a.min_lng <= b.max_lng &&
  a.max_lng >= b.min_lng
}

///|
/// Centre coordinate along the chosen axis.
fn axis_center(b : @types.BBox, use_lat : Bool) -> Double {
  if use_lat {
    (b.min_lat + b.max_lat) / 2.0
  } else {
    (b.min_lng + b.max_lng) / 2.0
  }
}

///|
/// Clamp `x` into `[lo, hi]`.
fn clamp(x : Double, lo : Double, hi : Double) -> Double {
  if x < lo {
    lo
  } else if x > hi {
    hi
  } else {
    x
  }
}

///|
/// Minimum of two doubles.
fn min2(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// Maximum of two doubles.
fn max2(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}
