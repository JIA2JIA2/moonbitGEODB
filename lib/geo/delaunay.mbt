// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

/// Delaunay triangulation via the Voronoi dual.
///
/// Given the Voronoi diagram of a point set, the Delaunay triangulation is
/// obtained by connecting every pair of sites whose Voronoi cells share an
/// edge. This is simpler and more reliable than the Bowyer-Watson incremental
/// insertion algorithm, and reuses the existing Voronoi implementation.
///
/// The algorithm:
///   1. Compute the Voronoi diagram (iterative half-plane clipping).
///   2. For each pair of sites, check whether their Voronoi cells share an
///      edge (by testing whether their perpendicular bisector contributes
///      an edge to both clipped polygons).
///   3. The shared-edge pairs are the Delaunay edges.
///   4. Triangulate the Delaunay graph: for each edge (i, j), find a third
///      site k such that (i, j, k) forms a triangle (all three edges are
///      Delaunay edges and the triangle is not super-triangle).
///
/// Complexity: O(n³) worst case for the triangulation step (finding the
/// third vertex for each edge). For moderate data sizes this is acceptable.

///|
/// A single Delaunay triangle, referencing points by index.
pub(all) struct DelaunayTriangle {
  a : Int
  b : Int
  c : Int
} derive(Eq, Debug)

///|
/// A Delaunay edge between two point indices.
pub(all) struct DelaunayEdge {
  a : Int
  b : Int
} derive(Eq, Debug)

///|
/// Compute the Delaunay triangulation of a set of planar points via the
/// Voronoi dual. Returns the list of triangles, each as three indices into
/// the input array. Returns an empty array for fewer than 3 points.
pub fn delaunay_triangulation(
  points : Array[@types.GeoPoint],
) -> Array[DelaunayTriangle] {
  let n = points.length()
  if n < 3 {
    return []
  }
  // Compute bounding box for the Voronoi diagram.
  let (min_lat, max_lat, min_lng, max_lng) = bounds(points)
  let bbox : @types.BBox = { min_lat, max_lat, min_lng, max_lng, }
  // Compute the Voronoi diagram.
  let cells = voronoi_diagram(points, bbox)
  // Build Delaunay edges from Voronoi cell adjacencies.
  // Two sites are Delaunay neighbours iff their Voronoi cells share an edge.
  let edges = delaunay_edges_from_voronoi(cells, n)
  // Triangulate the Delaunay graph.
  triangulate_from_edges(edges, n)
}

///|
/// Compute all Delaunay edges (unique, sorted) for a set of points.
pub fn delaunay_edges(points : Array[@types.GeoPoint]) -> Array[DelaunayEdge] {
  let n = points.length()
  if n < 2 {
    return []
  }
  let (min_lat, max_lat, min_lng, max_lng) = bounds(points)
  let bbox : @types.BBox = { min_lat, max_lat, min_lng, max_lng, }
  let cells = voronoi_diagram(points, bbox)
  delaunay_edges_from_voronoi(cells, n)
}

///|
/// Build Delaunay edges from Voronoi cell adjacencies.
/// Two sites are neighbours iff their Voronoi cells share at least one edge.
fn delaunay_edges_from_voronoi(
  cells : Array[VoronoiCell],
  n : Int,
) -> Array[DelaunayEdge] {
  let edge_set : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  let edges : Array[DelaunayEdge] = []
  // For each pair of cells, check if they share an edge.
  let mut i = 0
  while i < cells.length() {
    let mut j = i + 1
    while j < cells.length() {
      if cells_share_edge(cells[i].polygon, cells[j].polygon) {
        let a = i
        let b = j
        let key = if a < b { "\{a},\{b}" } else { "\{b},\{a}" }
        if !edge_set.contains(key) {
          edge_set[key] = true
          edges.push({ a, b, })
        }
      }
      j = j + 1
    }
    i = i + 1
  }
  edges
}

///|
/// Triangulate a Delaunay edge graph into triangles.
/// For each edge (a, b), find a third vertex c such that (a, c) and (b, c)
/// are also edges. This gives a triangle.
fn triangulate_from_edges(
  edges : Array[DelaunayEdge],
  n : Int,
) -> Array[DelaunayTriangle] {
  // Build adjacency sets for fast lookup.
  let adj : Array[@hashmap.HashMap[Int, Bool]] = []
  let mut i = 0
  while i < n {
    adj.push(@hashmap.HashMap([]))
    i = i + 1
  }
  for e in edges {
    adj[e.a][e.b] = true
    adj[e.b][e.a] = true
  }
  // Find triangles.
  let tri_set : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  let tris : Array[DelaunayTriangle] = []
  for e in edges {
    let a = e.a
    let b = e.b
    // Find a common neighbour c of both a and b.
    for c_key in adj[a].keys() {
      let c = c_key
      if c != a && c != b && adj[b].contains(c) {
        // Found triangle (a, b, c). Canonical order.
        let (x, y, z) = sort3(a, b, c)
        let key = "\{x},\{y},\{z}"
        if !tri_set.contains(key) {
          tri_set[key] = true
          tris.push({ a: x, b: y, c: z, })
        }
      }
    }
  }
  tris
}

///|
/// Check whether two Voronoi polygons share an edge.
/// They share an edge if they share at least two vertices (within tolerance).
fn cells_share_edge(
  a : Array[@types.GeoPoint],
  b : Array[@types.GeoPoint],
) -> Bool {
  let seen : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  for pa in a {
    let key = "\{pa.lat.to_string()},\{pa.lng.to_string()}"
    seen[key] = true
  }
  let mut shared = 0
  for pb in b {
    let key = "\{pb.lat.to_string()},\{pb.lng.to_string()}"
    if seen.contains(key) {
      shared = shared + 1
      if shared >= 2 {
        return true
      }
    }
  }
  false
}

///|
/// Compute the circumcircle of three planar points.
/// Returns (center, squared_radius).
pub fn circumcircle(
  a : @types.GeoPoint,
  b : @types.GeoPoint,
  c : @types.GeoPoint,
) -> (@types.GeoPoint, Double) {
  let d = 2.0 *
    (
      a.lat * (b.lng - c.lng) +
      b.lat * (c.lng - a.lng) +
      c.lat * (a.lng - b.lng)
    )
  if d.abs() < 0.000000000000001 {
    // Collinear: return a degenerate circle with infinite radius.
    let center = @types.GeoPoint::make(
      (a.lat + b.lat + c.lat) / 3.0,
      (a.lng + b.lng + c.lng) / 3.0,
    )
    return (center, 1.7976931348623157e+308)
  }
  let ux = (
      (a.lat * a.lat + a.lng * a.lng) * (b.lng - c.lng) +
      (b.lat * b.lat + b.lng * b.lng) * (c.lng - a.lng) +
      (c.lat * c.lat + c.lng * c.lng) * (a.lng - b.lng)
    ) /
    d
  let uy = (
      (a.lat * a.lat + a.lng * a.lng) * (c.lat - b.lat) +
      (b.lat * b.lat + b.lng * b.lng) * (a.lat - c.lat) +
      (c.lat * c.lat + c.lng * c.lng) * (b.lat - a.lat)
    ) /
    d
  let center = @types.GeoPoint::make(ux, uy)
  let dx = a.lat - ux
  let dy = a.lng - uy
  let r2 = dx * dx + dy * dy
  (center, r2)
}

///|
/// Min/max bounds of a point set.
fn bounds(points : Array[@types.GeoPoint]) -> (Double, Double, Double, Double) {
  let n = points.length()
  if n == 0 {
    return (0.0, 0.0, 0.0, 0.0)
  }
  let mut min_lat = points[0].lat
  let mut max_lat = points[0].lat
  let mut min_lng = points[0].lng
  let mut max_lng = points[0].lng
  let mut i = 1
  while i < n {
    let p = points[i]
    if p.lat < min_lat {
      min_lat = p.lat
    }
    if p.lat > max_lat {
      max_lat = p.lat
    }
    if p.lng < min_lng {
      min_lng = p.lng
    }
    if p.lng > max_lng {
      max_lng = p.lng
    }
    i = i + 1
  }
  (min_lat, max_lat, min_lng, max_lng)
}

///|
/// Sort three integers.
fn sort3(a : Int, b : Int, c : Int) -> (Int, Int, Int) {
  let (x, y) = if a < b { (a, b) } else { (b, a) }
  let (y2, z) = if y < c { (y, c) } else { (c, y) }
  let x2 = if x < y2 { x } else { y2 }
  (
    x2,
    if x2 == x {
      if y2 == y {
        b
      } else {
        y2
      }
    } else if x2 == y2 {
      a
    } else {
      a
    },
    z,
  )
}
