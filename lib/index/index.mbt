// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

///|
/// A combined spatial + name + tag + address index over `GeoEntry` records.
///
/// - Spatial: a uniform lat/lng grid buckets entry IDs for fast bbox queries.
/// - Name: a hash map from lowercased name → entry IDs for exact / prefix
///   lookup. Substring search is a linear scan over the name index.
/// - Tag: a hash map from tag → entry IDs for tag-based filtering.
/// - Address: hash maps for province/city/district → entry IDs.
///
/// The index also owns the canonical entry map (id -> GeoEntry) so that
/// queries can return full records without an extra hop.
///|
/// Coarse grid cell size: 0.5° (~55 km). Used for large-range queries
/// that would otherwise scan hundreds of fine-grid (0.1°) cells.
pub let coarse_cell_size : Double = 0.5

pub(all) struct Index {
  mut entries : @hashmap.HashMap[String, @types.GeoEntry]
  grid : @hashmap.HashMap[Int, Array[String]] // fine grid, cell_size=0.1°
  lng_cells : Int // 360 / cell_size
  coarse_grid : @hashmap.HashMap[Int, Array[String]] // coarse grid, cell_size=0.5°
  coarse_lng_cells : Int // 360 / coarse_cell_size
  mut by_name : @hashmap.HashMap[String, Array[String]]
  mut by_ngram : @hashmap.HashMap[String, Array[String]] // 3-gram substring index
  mut bigram_built : Bool // true once by_bigram has been populated lazily
  by_bigram : @hashmap.HashMap[String, Array[String]] // 2-gram substring index
  by_name_len : @hashmap.HashMap[Int, Array[String]] // code-point length -> ids
  by_tag : @hashmap.HashMap[String, Array[String]]
  by_province : @hashmap.HashMap[String, Array[String]]
  by_city : @hashmap.HashMap[String, Array[String]]
  by_district : @hashmap.HashMap[String, Array[String]]
  cell_size : Double // degrees (fine grid size)
  rtree : RTree // R-tree for sub-linear KNN / range queries
  mut cached_bbox : @types.BBox? // cached combined bbox
  mut cached_center : @types.GeoPoint? // cached centroid
  mut cached_entries : Array[@types.GeoEntry]? // cached entries snapshot
  mut cached_lower_names : Array[String]? // lowercased names aligned with cached_entries
  mut cached_knn_weights : Array[Array[Int]]? // cached mutual-kNN adjacency
  mut cached_knn_k : Int // k value for cached_knn_weights
  mut name_keys_cache : Array[String]? // sorted lowercase name keys for prefix queries
  mut sorted_case_entries : Array[@types.GeoEntry]? // case-sensitive name-sorted entries
  mut geohash_cache_stale : Bool // true when geohash_cache must be rebuilt
  mut geohash_cache : @hashmap.HashMap[String, String] // id -> precision-8 geohash
} derive(Eq, Debug)

pub extend Index with Eq::{ equal, not_equal }
pub extend Index with Debug::{ to_repr }

///|
/// Default grid cell size: 0.1° (~11 km at the equator).
pub let default_cell_size : Double = 0.1

///|
/// Create an empty index with a given grid cell size in degrees.
pub fn Index::new(cell_size? : Double = default_cell_size) -> Index {
  let lng_cells = math_floor(360.0 / cell_size)
  let coarse_lng_cells = math_floor(360.0 / coarse_cell_size)
  {
    entries: @hashmap.HashMap([]),
    grid: @hashmap.HashMap([]),
    lng_cells,
    coarse_grid: @hashmap.HashMap([]),
    coarse_lng_cells,
    by_name: @hashmap.HashMap([]),
    by_ngram: @hashmap.HashMap([]),
    bigram_built: false,
    by_bigram: @hashmap.HashMap([]),
    by_name_len: @hashmap.HashMap([]),
    by_tag: @hashmap.HashMap([]),
    by_province: @hashmap.HashMap([]),
    by_city: @hashmap.HashMap([]),
    by_district: @hashmap.HashMap([]),
    cell_size,
    rtree: RTree::new(),
    cached_bbox: None,
    cached_center: None,
    cached_entries: None,
    cached_lower_names: None,
    cached_knn_weights: None,
    cached_knn_k: -1,
    name_keys_cache: None,
    sorted_case_entries: None,
    geohash_cache_stale: true,
    geohash_cache: @hashmap.HashMap([]),
  }
}

///|
/// Number of entries currently indexed.
pub fn Index::size(self : Index) -> Int {
  self.entries.length()
}

///|
/// Remove all entries and reset every secondary index in one pass.
pub fn Index::clear(self : Index) -> Unit {
  self.entries.clear()
  self.grid.clear()
  self.coarse_grid.clear()
  self.by_name.clear()
  self.by_ngram.clear()
  self.by_bigram.clear()
  self.bigram_built = false
  self.by_name_len.clear()
  self.by_tag.clear()
  self.by_province.clear()
  self.by_city.clear()
  self.by_district.clear()
  self.rtree.clear()
  self.geohash_cache.clear()
  self.cached_bbox = None
  self.cached_center = None
  self.cached_entries = None
  self.cached_lower_names = None
  self.cached_knn_weights = None
  self.name_keys_cache = None
  self.sorted_case_entries = None
  self.geohash_cache_stale = true
  self.sorted_case_entries = None
  self.geohash_cache_stale = true
}

///|
/// Floor that handles negative numbers correctly (toward -inf).
fn math_floor(x : Double) -> Int {
  let i = x.to_int()
  if x < 0.0 && x != i.to_double() {
    i - 1
  } else {
    i
  }
}

///|
/// Compute the grid cell **integer index** for a geographic point.
/// cell_idx = lat_idx * lng_cells + lng_idx, fully avoids string building.
fn cell_idx(lat : Double, lng : Double, cell_size : Double, lng_cells : Int) -> Int {
  let lat_idx = math_floor((lat + 90.0) / cell_size)
  let lng_idx = math_floor((lng + 180.0) / cell_size)
  lat_idx * lng_cells + lng_idx
}

///|
/// Insert (or replace) an entry. Updates spatial, name, tag, and address indexes.
pub fn Index::insert(self : Index, entry : @types.GeoEntry) -> Unit {
  // Remove old version if present (so stale grid/name slots get cleared).
  if self.entries.contains(entry.id) {
    ignore(self.remove(entry.id))
  }
  self.entries[entry.id] = entry
  // Fine spatial grid.
  let idx = cell_idx(entry.location.lat, entry.location.lng, self.cell_size, self.lng_cells)
  match self.grid.get(idx) {
    None => self.grid[idx] = [entry.id]
    Some(arr) => arr.push(entry.id)
  }
  // Coarse spatial grid for large-range queries.
  let cidx = cell_idx(entry.location.lat, entry.location.lng, coarse_cell_size, self.coarse_lng_cells)
  match self.coarse_grid.get(cidx) {
    None => self.coarse_grid[cidx] = [entry.id]
    Some(arr) => arr.push(entry.id)
  }
  // Name index (lowercased for case-insensitive lookup).
  let name_key = entry.name.to_lower()
  if name_key.length() > 0 {
    match self.by_name.get(name_key) {
      None => self.by_name[name_key] = [entry.id]
      Some(arr) => arr.push(entry.id)
    }
    for gram in name_ngrams(name_key, ngram_size) {
      match self.by_ngram.get(gram) {
        None => self.by_ngram[gram] = [entry.id]
        Some(arr) => arr.push(entry.id)
      }
    }
    if self.bigram_built {
      for gram in name_ngrams(name_key, 2) {
        match self.by_bigram.get(gram) {
          None => self.by_bigram[gram] = [entry.id]
          Some(arr) => arr.push(entry.id)
        }
      }
    }
  }
  let name_len = code_point_len(name_key)
  match self.by_name_len.get(name_len) {
    None => self.by_name_len[name_len] = [entry.id]
    Some(arr) => arr.push(entry.id)
  }
  // Tag index.
  for tag in entry.tags {
    let tag_key = tag.to_lower()
    if tag_key.length() > 0 {
      match self.by_tag.get(tag_key) {
        None => self.by_tag[tag_key] = [entry.id]
        Some(arr) => arr.push(entry.id)
      }
    }
  }
  // Address indexes.
  if entry.address.province.length() > 0 {
    let prov_key = entry.address.province.to_lower()
    match self.by_province.get(prov_key) {
      None => self.by_province[prov_key] = [entry.id]
      Some(arr) => arr.push(entry.id)
    }
  }
  if entry.address.city.length() > 0 {
    let city_key = entry.address.city.to_lower()
    match self.by_city.get(city_key) {
      None => self.by_city[city_key] = [entry.id]
      Some(arr) => arr.push(entry.id)
    }
  }
  if entry.address.district.length() > 0 {
    let dist_key = entry.address.district.to_lower()
    match self.by_district.get(dist_key) {
      None => self.by_district[dist_key] = [entry.id]
      Some(arr) => arr.push(entry.id)
    }
  }
  // R-tree spatial index.
  self.rtree.insert_new(entry.id, entry.location)
  // Invalidate caches.
  self.cached_bbox = None
  self.cached_center = None
  self.cached_entries = None
  self.cached_lower_names = None
  self.cached_knn_weights = None
  self.name_keys_cache = None
  self.sorted_case_entries = None
  self.geohash_cache_stale = true
}

///|
/// Bulk insert: adds many entries at once, deferring R-tree insert and
/// skipping per-entry duplicate checks. ~2-5x faster than calling `insert`
/// in a loop for large N. Assumes entries have distinct ids (last-wins if
/// duplicates exist).
pub fn Index::bulk_insert(self : Index, entries : Array[@types.GeoEntry]) -> Unit {
  // Pre-size the hot maps when loading into an empty index.
  if self.entries.length() == 0 && self.rtree.size() == 0 {
    let cap = entries.length()
    self.entries = @hashmap.HashMap([], capacity=cap)
    self.by_name = @hashmap.HashMap([], capacity=cap)
    self.by_ngram = @hashmap.HashMap([], capacity=cap * 4)
    self.geohash_cache = @hashmap.HashMap([], capacity=cap)
  }
  // Phase 1: HashMap of entries + all non-spatial indexes in one pass.
  for entry in entries {
    if self.entries.contains(entry.id) {
      ignore(self.remove(entry.id))
    }
    self.entries[entry.id] = entry
    // Fine spatial grid.
    let idx = cell_idx(entry.location.lat, entry.location.lng, self.cell_size, self.lng_cells)
    match self.grid.get(idx) {
      None => self.grid[idx] = [entry.id]
      Some(arr) => arr.push(entry.id)
    }
    // Coarse spatial grid for large-range queries.
    let cidx = cell_idx(entry.location.lat, entry.location.lng, coarse_cell_size, self.coarse_lng_cells)
    match self.coarse_grid.get(cidx) {
      None => self.coarse_grid[cidx] = [entry.id]
      Some(arr) => arr.push(entry.id)
    }
    // Name.
    let name_key = entry.name.to_lower()
    if name_key.length() > 0 {
      match self.by_name.get(name_key) {
        None => self.by_name[name_key] = [entry.id]
        Some(arr) => arr.push(entry.id)
      }
      for gram in name_ngrams(name_key, ngram_size) {
        match self.by_ngram.get(gram) {
          None => self.by_ngram[gram] = [entry.id]
          Some(arr) => arr.push(entry.id)
        }
      }
      if self.bigram_built {
        for gram in name_ngrams(name_key, 2) {
          match self.by_bigram.get(gram) {
            None => self.by_bigram[gram] = [entry.id]
            Some(arr) => arr.push(entry.id)
          }
        }
      }
    }
    let name_len = code_point_len(name_key)
    match self.by_name_len.get(name_len) {
      None => self.by_name_len[name_len] = [entry.id]
      Some(arr) => arr.push(entry.id)
    }
    // Tags.
    for tag in entry.tags {
      let tag_key = tag.to_lower()
      if tag_key.length() > 0 {
        match self.by_tag.get(tag_key) {
          None => self.by_tag[tag_key] = [entry.id]
          Some(arr) => arr.push(entry.id)
        }
      }
    }
    // Address.
    if entry.address.province.length() > 0 {
      let prov_key = entry.address.province.to_lower()
      match self.by_province.get(prov_key) {
        None => self.by_province[prov_key] = [entry.id]
        Some(arr) => arr.push(entry.id)
      }
    }
    if entry.address.city.length() > 0 {
      let city_key = entry.address.city.to_lower()
      match self.by_city.get(city_key) {
        None => self.by_city[city_key] = [entry.id]
        Some(arr) => arr.push(entry.id)
      }
    }
    if entry.address.district.length() > 0 {
      let dist_key = entry.address.district.to_lower()
      match self.by_district.get(dist_key) {
        None => self.by_district[dist_key] = [entry.id]
        Some(arr) => arr.push(entry.id)
      }
    }
  }
  // Phase 2: build the R-tree. Use STR sort-then-pack when the tree is empty;
  // otherwise fall back to per-entry insertion (replacing existing ids).
  if self.rtree.size() == 0 {
    let pts : Array[(String, @types.GeoPoint)] = []
    let seen : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
    for entry in entries {
      match seen.get(entry.id) {
        Some(i) => pts[i] = (entry.id, entry.location)
        None => {
          seen[entry.id] = pts.length()
          pts.push((entry.id, entry.location))
        }
      }
    }
    self.rtree.bulk_load(pts)
  } else {
    for entry in entries {
      self.rtree.insert(entry.id, entry.location)
    }
  }
  // Invalidate caches once at the end.
  self.cached_bbox = None
  self.cached_center = None
  self.cached_entries = None
  self.cached_lower_names = None
  self.cached_knn_weights = None
  self.name_keys_cache = None
  self.sorted_case_entries = None
  self.geohash_cache_stale = true
}

///|
/// Remove every occurrence of `id` from `arr` in place, returning whether any
/// element was removed.
fn remove_id_in_place(arr : Array[String], id : String) -> Bool {
  let n = arr.length()
  let mut write = 0
  let mut read = 0
  while read < n {
    let x = arr[read]
    if x != id {
      arr[write] = x
      write = write + 1
    }
    read = read + 1
  }
  if write == n {
    return false
  }
  while arr.length() > write {
    ignore(arr.pop())
  }
  true
}

///|
/// Remove an entry by id. Returns the removed entry if it existed.
pub fn Index::remove(self : Index, id : String) -> @types.GeoEntry? {
  match self.entries.get(id) {
    None => None
    Some(entry) => {
      ignore(self.entries.remove(id))
      // Drop from fine grid cell.
      let idx = cell_idx(entry.location.lat, entry.location.lng, self.cell_size, self.lng_cells)
      match self.grid.get(idx) {
        Some(arr) =>
          if remove_id_in_place(arr, id) && arr.length() == 0 {
            ignore(self.grid.remove(idx))
          }
        None => ()
      }
      // Drop from coarse grid cell.
      let cidx = cell_idx(entry.location.lat, entry.location.lng, coarse_cell_size, self.coarse_lng_cells)
      match self.coarse_grid.get(cidx) {
        Some(arr) =>
          if remove_id_in_place(arr, id) && arr.length() == 0 {
            ignore(self.coarse_grid.remove(cidx))
          }
        None => ()
      }
      // Drop from name index.
      let name_key = entry.name.to_lower()
      if name_key.length() > 0 {
        match self.by_name.get(name_key) {
          Some(arr) =>
            if remove_id_in_place(arr, id) && arr.length() == 0 {
              ignore(self.by_name.remove(name_key))
            }
          None => ()
        }
        for gram in name_ngrams(name_key, ngram_size) {
          match self.by_ngram.get(gram) {
            Some(arr) =>
              if remove_id_in_place(arr, id) && arr.length() == 0 {
                ignore(self.by_ngram.remove(gram))
              }
            None => ()
          }
        }
        if self.bigram_built {
          for gram in name_ngrams(name_key, 2) {
            match self.by_bigram.get(gram) {
              Some(arr) =>
                if remove_id_in_place(arr, id) && arr.length() == 0 {
                  ignore(self.by_bigram.remove(gram))
                }
              None => ()
            }
          }
        }
      }
      let name_len = code_point_len(name_key)
      match self.by_name_len.get(name_len) {
        Some(arr) =>
          if remove_id_in_place(arr, id) && arr.length() == 0 {
            ignore(self.by_name_len.remove(name_len))
          }
        None => ()
      }
      // Drop from tag indexes.
      for tag in entry.tags {
        let tag_key = tag.to_lower()
        if tag_key.length() > 0 {
          match self.by_tag.get(tag_key) {
            Some(arr) =>
              if remove_id_in_place(arr, id) && arr.length() == 0 {
                ignore(self.by_tag.remove(tag_key))
              }
            None => ()
          }
        }
      }
      // Drop from address indexes.
      if entry.address.province.length() > 0 {
        let prov_key = entry.address.province.to_lower()
        match self.by_province.get(prov_key) {
          Some(arr) =>
            if remove_id_in_place(arr, id) && arr.length() == 0 {
              ignore(self.by_province.remove(prov_key))
            }
          None => ()
        }
      }
      if entry.address.city.length() > 0 {
        let city_key = entry.address.city.to_lower()
        match self.by_city.get(city_key) {
          Some(arr) =>
            if remove_id_in_place(arr, id) && arr.length() == 0 {
              ignore(self.by_city.remove(city_key))
            }
          None => ()
        }
      }
      if entry.address.district.length() > 0 {
        let dist_key = entry.address.district.to_lower()
        match self.by_district.get(dist_key) {
          Some(arr) =>
            if remove_id_in_place(arr, id) && arr.length() == 0 {
              ignore(self.by_district.remove(dist_key))
            }
          None => ()
        }
      }
      ignore(self.rtree.remove(id))
      // Invalidate caches.
      self.cached_bbox = None
      self.cached_center = None
      self.cached_entries = None
      self.cached_lower_names = None
      self.cached_knn_weights = None
      self.name_keys_cache = None
      self.sorted_case_entries = None
  self.geohash_cache_stale = true
      Some(entry)
    }
  }
}

///|
/// Lookup an entry by id.
pub fn Index::get(self : Index, id : String) -> @types.GeoEntry? {
  self.entries.get(id)
}

///|
/// Iterate over all entries. Order is unspecified.
pub fn Index::iter(self : Index) -> Iter[@types.GeoEntry] {
  self.entries.iter().map(fn(p) { p.1 })
}

///|
/// Range query: return all entries whose location lies inside `bbox`.
/// **Adaptive**: picks grid for small bboxes (skip empty cells fast),
/// R-tree for large bboxes (O(log n + k) traversal). Threshold = 64 cells.
pub fn Index::query_bbox(
  self : Index,
  bbox : @types.BBox,
) -> Array[@types.GeoEntry] {
  // Choose the grid that covers the bbox in the fewest cells.
  let fine_dlat = math_floor((bbox.max_lat - bbox.min_lat) / self.cell_size + 1.0)
  let fine_dlng = math_floor((bbox.max_lng - bbox.min_lng) / self.cell_size + 1.0)
  let fine_cells = fine_dlat * fine_dlng
  let coarse_dlat = math_floor((bbox.max_lat - bbox.min_lat) / coarse_cell_size + 1.0)
  let coarse_dlng = math_floor((bbox.max_lng - bbox.min_lng) / coarse_cell_size + 1.0)
  let coarse_cells = coarse_dlat * coarse_dlng
  if fine_cells <= 500 && fine_cells <= coarse_cells * 4 {
    // Prefer the fine grid when it covers only a few more cells: fine
    // buckets are ~25x smaller, so the candidate set shrinks substantially.
    return self.query_bbox_grid(bbox)
  }
  if coarse_cells <= 500 {
    return self.query_bbox_grid_coarse(bbox)
  }
  let ids = self.rtree.search(bbox)
  let result : Array[@types.GeoEntry] = []
  for id in ids {
    match self.entries.get(id) {
      Some(e) =>
        if @geo.bbox_contains(bbox, e.location) {
          result.push(e)
        }
      None => ()
    }
  }
  result
}

///| Grid-based bbox scan (fine 0.1° cells). Skip empty cells fast.
fn Index::query_bbox_grid(
  self : Index,
  bbox : @types.BBox,
) -> Array[@types.GeoEntry] {
  let result : Array[@types.GeoEntry] = []
  let min_lat_idx = math_floor((bbox.min_lat + 90.0) / self.cell_size)
  let max_lat_idx = math_floor((bbox.max_lat + 90.0) / self.cell_size)
  let min_lng_idx = math_floor((bbox.min_lng + 180.0) / self.cell_size)
  let max_lng_idx = math_floor((bbox.max_lng + 180.0) / self.cell_size)
  let mut lat = min_lat_idx
  while lat <= max_lat_idx {
    let base = lat * self.lng_cells
    let mut lng = min_lng_idx
    while lng <= max_lng_idx {
      match self.grid.get(base + lng) {
        Some(ids) =>
          for id in ids {
            match self.entries.get(id) {
              Some(e) =>
                if @geo.bbox_contains(bbox, e.location) {
                  result.push(e)
                }
              None => ()
            }
          }
        None => ()
      }
      lng = lng + 1
    }
    lat = lat + 1
  }
  result
}

///| Coarse-grid bbox scan (0.5° cells). Used when the bbox would otherwise
/// cover hundreds of fine cells (typical for DBSCAN range queries).
fn Index::query_bbox_grid_coarse(
  self : Index,
  bbox : @types.BBox,
) -> Array[@types.GeoEntry] {
  let result : Array[@types.GeoEntry] = []
  let min_lat_idx = math_floor((bbox.min_lat + 90.0) / coarse_cell_size)
  let max_lat_idx = math_floor((bbox.max_lat + 90.0) / coarse_cell_size)
  let min_lng_idx = math_floor((bbox.min_lng + 180.0) / coarse_cell_size)
  let max_lng_idx = math_floor((bbox.max_lng + 180.0) / coarse_cell_size)
  let mut lat = min_lat_idx
  while lat <= max_lat_idx {
    let base = lat * self.coarse_lng_cells
    let mut lng = min_lng_idx
    while lng <= max_lng_idx {
      match self.coarse_grid.get(base + lng) {
        Some(ids) =>
          for id in ids {
            match self.entries.get(id) {
              Some(e) =>
                if @geo.bbox_contains(bbox, e.location) {
                  result.push(e)
                }
              None => ()
            }
          }
        None => ()
      }
      lng = lng + 1
    }
    lat = lat + 1
  }
  result
}

///|
/// k nearest-neighbour query. Returns up to `k` (entry, distance_km) pairs
/// sorted by ascending distance. Delegates to the built-in R-tree via
/// best-first search, which is sub-linear for large datasets.
pub fn Index::query_nearest(
  self : Index,
  point : @types.GeoPoint,
  k : Int,
) -> Array[(@types.GeoEntry, Double)] {
  let raw = self.rtree.nearest(point, k)
  let out : Array[(@types.GeoEntry, Double)] = []
  for (id, d) in raw {
    match self.entries.get(id) {
      Some(e) => out.push((e, d))
      None => ()
    }
  }
  out
}

///|
/// Exact (case-insensitive) name lookup.
pub fn Index::find_by_name(
  self : Index,
  name : String,
) -> Array[@types.GeoEntry] {
  let key = name.to_lower()
  match self.by_name.get(key) {
    None => []
    Some(ids) => {
      let out : Array[@types.GeoEntry] = []
      for id in ids {
        match self.entries.get(id) {
          Some(e) => out.push(e)
          None => ()
        }
      }
      out
    }
  }
}

///|
/// Lower bound (first index whose key is >= target) in a sorted key array.
fn lower_bound(keys : Array[String], target : String) -> Int {
  let mut lo = 0
  let mut hi = keys.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if keys[mid][:].lexical_compare(target[:]) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// Return the sorted lowercase name keys, rebuilding the cache on demand.
fn Index::get_sorted_name_keys(self : Index) -> Array[String] {
  match self.name_keys_cache {
    Some(keys) => keys
    None => {
      let keys = self.by_name.keys().collect()
      keys.sort_by(fn(a, b) { a[:].lexical_compare(b[:]) })
      self.name_keys_cache = Some(keys)
      keys
    }
  }
}

///|
/// Prefix (case-insensitive) name lookup. Returns entries whose name starts
/// with the given prefix. Uses a lazily built sorted key index and binary
/// search, so the query is O(log m + k) instead of scanning every entry.
pub fn Index::find_name_prefix(
  self : Index,
  prefix : String,
) -> Array[@types.GeoEntry] {
  let p = prefix.to_lower()
  if p.length() == 0 {
    return []
  }
  let keys = self.get_sorted_name_keys()
  let mut i = lower_bound(keys, p)
  let out : Array[@types.GeoEntry] = []
  while i < keys.length() {
    let key = keys[i]
    if !key.has_prefix(p) {
      break
    }
    match self.by_name.get(key) {
      Some(ids) =>
        for id in ids {
          match self.entries.get(id) {
            Some(e) => out.push(e)
            None => ()
          }
        }
      None => ()
    }
    i = i + 1
  }
  out
}

///|
/// Lower bound (first index whose name is >= target) in name-sorted entries.
fn lower_bound_entries(
  entries : Array[@types.GeoEntry],
  target : String,
) -> Int {
  let mut lo = 0
  let mut hi = entries.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if entries[mid].name[:].lexical_compare(target[:]) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// Return entries sorted by their original-case name, rebuilding on demand.
fn Index::get_sorted_case_entries(self : Index) -> Array[@types.GeoEntry] {
  match self.sorted_case_entries {
    Some(arr) => arr
    None => {
      let base = self.to_array()
      let arr : Array[@types.GeoEntry] = []
      for e in base {
        arr.push(e)
      }
      arr.sort_by(fn(a, b) { a.name[:].lexical_compare(b.name[:]) })
      self.sorted_case_entries = Some(arr)
      arr
    }
  }
}

///|
/// Case-sensitive prefix lookup using a name-sorted cache and binary search.
pub fn Index::find_name_prefix_case(
  self : Index,
  prefix : String,
) -> Array[@types.GeoEntry] {
  if prefix.length() == 0 {
    return self.to_array()
  }
  let entries = self.get_sorted_case_entries()
  let mut i = lower_bound_entries(entries, prefix)
  let out : Array[@types.GeoEntry] = []
  while i < entries.length() {
    let name = entries[i].name
    if !name.has_prefix(prefix) {
      break
    }
    out.push(entries[i])
    i = i + 1
  }
  out
}

///|
/// Number of Unicode code points in a string.
fn code_point_len(s : String) -> Int {
  let mut n = 0
  for _ in s {
    n = n + 1
  }
  n
}

///|
/// Number of code points per n-gram used by the substring index.
let ngram_size : Int = 3

///|
/// Distinct overlapping n-grams (by code point) of a lowercase name.
fn name_ngrams(name : String, size : Int) -> Array[String] {
  let len = name.length()
  let out : Array[String] = []
  if size < 1 || len < size {
    return out
  }
  let mut i = 0
  while i + size <= len {
    let g = name[i:i + size].to_owned()
    let mut dup = false
    for existing in out {
      if existing == g {
        dup = true
        break
      }
    }
    if !dup {
      out.push(g)
    }
    i = i + 1
  }
  out
}

///|
/// Build the 2-gram index on first short-needle query.
fn Index::ensure_bigram_index(self : Index) -> Unit {
  if self.bigram_built {
    return
  }
  self.by_bigram.clear()
  for e in self.to_array() {
    let name_key = e.name.to_lower()
    for gram in name_ngrams(name_key, 2) {
      match self.by_bigram.get(gram) {
        None => self.by_bigram[gram] = [e.id]
        Some(arr) => arr.push(e.id)
      }
    }
  }
  self.bigram_built = true
}

///|
/// Substring (case-insensitive) name lookup using 2-/3-gram indexes.
pub fn Index::find_name_contains(
  self : Index,
  needle : String,
) -> Array[@types.GeoEntry] {
  let n = needle.to_lower()
  if n.length() == 0 {
    return []
  }
let out : Array[@types.GeoEntry] = []
  let use_bigram = n.length() == 2
  if use_bigram {
    self.ensure_bigram_index()
  }
  let grams = if use_bigram {
    name_ngrams(n, 2)
  } else {
    name_ngrams(n, ngram_size)
  }
  if grams.length() == 0 {
    // Too short for n-grams: fall back to the cached lowercase-name scan.
    let entries = self.to_array()
    let names = self.lowered_names()
    let mut i = 0
    while i < entries.length() && i < names.length() {
      if names[i].contains(n) {
        out.push(entries[i])
      }
      i = i + 1
    }
    return out
  }
  // A substring must contain every n-gram, so a missing posting list means
  // no match. Otherwise choose the smallest list as the candidate set.
  let mut best : Array[String]? = None
  for gram in grams {
    let posting = if use_bigram {
      self.by_bigram.get(gram)
    } else {
      self.by_ngram.get(gram)
    }
    match posting {
      None => return []
      Some(ids) =>
        match best {
          None => best = Some(ids)
          Some(cur) =>
            if ids.length() < cur.length() {
              best = Some(ids)
            }
        }
    }
  }
  match best {
    None => ()
    Some(ids) =>
      for id in ids {
        match self.entries.get(id) {
          Some(e) =>
            if e.name.to_lower().contains(n) {
              out.push(e)
            }
          None => ()
        }
      }
  }
  out
}

///|
/// Entries whose lowercased name code-point length is within
/// `[len - max_dist, len + max_dist]`.
pub fn Index::name_length_candidates(
  self : Index,
  len : Int,
  max_dist : Int,
) -> Array[@types.GeoEntry] {
  let out : Array[@types.GeoEntry] = []
  let mut l = len - max_dist
  if l < 0 {
    l = 0
  }
  let upper = len + max_dist
  while l <= upper {
    match self.by_name_len.get(l) {
      Some(ids) =>
        for id in ids {
          match self.entries.get(id) {
            Some(e) => out.push(e)
            None => ()
          }
        }
      None => ()
    }
    l = l + 1
  }
  out
}

///|
/// Return all entries as an array (snapshot copy). Uses a cached snapshot
/// when available; the cache is invalidated on insert/remove.
pub fn Index::to_array(self : Index) -> Array[@types.GeoEntry] {
  match self.cached_entries {
    Some(arr) => arr
    None => {
      let arr = self.entries.values().collect()
      self.cached_entries = Some(arr)
      arr
    }
  }
}

///|
/// Cached lowercase names, aligned index-wise with `to_array()`.
pub fn Index::lowered_names(self : Index) -> Array[String] {
  match self.cached_lower_names {
    Some(names) => names
    None => {
      let entries = self.to_array()
      let names : Array[String] = []
      for e in entries {
        names.push(e.name.to_lower())
      }
      self.cached_lower_names = Some(names)
      names
    }
  }
}

///|
/// Find entries that have a specific tag (case-insensitive).
pub fn Index::find_by_tag(self : Index, tag : String) -> Array[@types.GeoEntry] {
  let key = tag.to_lower()
  match self.by_tag.get(key) {
    None => []
    Some(ids) => {
      let out : Array[@types.GeoEntry] = []
      for id in ids {
        match self.entries.get(id) {
          Some(e) => out.push(e)
          None => ()
        }
      }
      out
    }
  }
}

///|
/// Find entries that have ALL the specified tags (AND logic).
pub fn Index::find_by_all_tags(
  self : Index,
  tags : Array[String],
) -> Array[@types.GeoEntry] {
  if tags.length() == 0 {
    return self.to_array()
  }
  // Lower-case and sort tags by ascending candidate-set size for efficiency.
  let lower_tags = tags.iter().map(fn(t) { t.to_lower() }).collect()
  let sorted_tags = sort_tag_list(lower_tags, self)
  let first_tag = sorted_tags[0]
  match self.by_tag.get(first_tag) {
    None => []
    Some(ids) => {
      let result : Array[@types.GeoEntry] = []
      for id in ids {
        match self.entries.get(id) {
          None => ()
          Some(entry) =>
            if check_all_tags(entry.tags, sorted_tags) {
              result.push(entry)
            }
        }
      }
      result
    }
  }
}

///| Helper: check whether `tags` (already lower-cased) are all present

///|
/// in `entry_tags` (compared case-insensitively).
fn check_all_tags(entry_tags : Array[String], tags : Array[String]) -> Bool {
  let lower : Array[String] = []
  for et in entry_tags {
    lower.push(et.to_lower())
  }
  for t in tags {
    let mut found = false
    for et in lower {
      if et == t {
        found = true
        break
      }
    }
    if !found {
      return false
    }
  }
  true
}

///| Helper: sort a list of lower-cased tags by ascending candidate-set

///|
/// size (so that the most selective tag is checked first).
fn sort_tag_list(tags : Array[String], idx : Index) -> Array[String] {
  let sized : Array[(String, Int)] = []
  for t in tags {
    let n = match idx.by_tag.get(t) {
      Some(arr) => arr.length()
      None => 0
    }
    sized.push((t, n))
  }
  sized.sort_by(fn(a, b) {
    if a.1 < b.1 {
      -1
    } else if a.1 > b.1 {
      1
    } else {
      0
    }
  })
  let out : Array[String] = []
  for p in sized {
    out.push(p.0)
  }
  out
}

///|
/// Find entries that have ANY of the specified tags (OR logic).
pub fn Index::find_by_any_tags(
  self : Index,
  tags : Array[String],
) -> Array[@types.GeoEntry] {
  if tags.length() == 0 {
    return []
  }
  let seen : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  let out : Array[@types.GeoEntry] = []
  for tag in tags {
    let key = tag.to_lower()
    match self.by_tag.get(key) {
      None => ()
      Some(ids) =>
        for id in ids {
          if !seen.contains(id) {
            seen[id] = true
            match self.entries.get(id) {
              Some(e) => out.push(e)
              None => ()
            }
          }
        }
    }
  }
  out
}

///|
/// Find entries by province (case-insensitive).
pub fn Index::find_by_province(
  self : Index,
  province : String,
) -> Array[@types.GeoEntry] {
  let key = province.to_lower()
  match self.by_province.get(key) {
    None => []
    Some(ids) => {
      let out : Array[@types.GeoEntry] = []
      for id in ids {
        match self.entries.get(id) {
          Some(e) => out.push(e)
          None => ()
        }
      }
      out
    }
  }
}

///|
/// Find entries by city (case-insensitive).
pub fn Index::find_by_city(
  self : Index,
  city : String,
) -> Array[@types.GeoEntry] {
  let key = city.to_lower()
  match self.by_city.get(key) {
    None => []
    Some(ids) => {
      let out : Array[@types.GeoEntry] = []
      for id in ids {
        match self.entries.get(id) {
          Some(e) => out.push(e)
          None => ()
        }
      }
      out
    }
  }
}

///|
/// Find entries by district (case-insensitive).
pub fn Index::find_by_district(
  self : Index,
  district : String,
) -> Array[@types.GeoEntry] {
  let key = district.to_lower()
  match self.by_district.get(key) {
    None => []
    Some(ids) => {
      let out : Array[@types.GeoEntry] = []
      for id in ids {
        match self.entries.get(id) {
          Some(e) => out.push(e)
          None => ()
        }
      }
      out
    }
  }
}

///|
/// Find entries by province AND city (case-insensitive).
pub fn Index::find_by_province_city(
  self : Index,
  province : String,
  city : String,
) -> Array[@types.GeoEntry] {
  let prov_key = province.to_lower()
  let city_key = city.to_lower()
  match self.by_province.get(prov_key) {
    None => []
    Some(prov_ids) =>
      match self.by_city.get(city_key) {
        None => []
        Some(city_ids) => {
          // Intersect the two ID sets.
          let city_set : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
          for id in city_ids {
            city_set[id] = true
          }
          let out : Array[@types.GeoEntry] = []
          for id in prov_ids {
            if city_set.contains(id) {
              match self.entries.get(id) {
                Some(e) => out.push(e)
                None => ()
              }
            }
          }
          out
        }
      }
  }
}

///|
/// List all unique tags in the index.
pub fn Index::list_tags(self : Index) -> Array[String] {
  let out : Array[String] = []
  for key in self.by_tag.keys() {
    out.push(key)
  }
  out.sort()
  out
}

///|
/// List all unique provinces in the index.
pub fn Index::list_provinces(self : Index) -> Array[String] {
  let out : Array[String] = []
  for key in self.by_province.keys() {
    out.push(key)
  }
  out.sort()
  out
}

///|
/// List all unique cities in the index.
pub fn Index::list_cities(self : Index) -> Array[String] {
  let out : Array[String] = []
  for key in self.by_city.keys() {
    out.push(key)
  }
  out.sort()
  out
}

///|
/// List all unique districts in the index.
pub fn Index::list_districts(self : Index) -> Array[String] {
  let out : Array[String] = []
  for key in self.by_district.keys() {
    out.push(key)
  }
  out.sort()
  out
}

// ---- Geofence / advanced queries ----

///|
/// Check whether a point lies inside the index's combined bounding box.
/// Returns None if the index is empty.
pub fn Index::contains_point(self : Index, point : @types.GeoPoint) -> Bool {
  match self.compute_bbox() {
    None => false
    Some(bbox) => @geo.bbox_contains(bbox, point)
  }
}

///|
/// Compute the centroid of all entries. Uses a cached value when available;
/// the cache is invalidated on insert/remove.
pub fn Index::compute_center(self : Index) -> (@types.GeoPoint, Int)? {
  match self.cached_center {
    Some(c) => Some((c, self.size()))
    None => {
      let entries = self.to_array()
      if entries.length() == 0 {
        return None
      }
      let mut sum_lat = 0.0
      let mut sum_lng = 0.0
      for e in entries {
        sum_lat = sum_lat + e.location.lat
        sum_lng = sum_lng + e.location.lng
      }
      let n = entries.length().to_double()
      let center = @types.GeoPoint::make(sum_lat / n, sum_lng / n)
      self.cached_center = Some(center)
      Some((center, entries.length()))
    }
  }
}

///|
/// Compute the combined bounding box of all entries. Uses a cached value
/// when available; the cache is invalidated on insert/remove.
pub fn Index::compute_bbox(self : Index) -> @types.BBox? {
  match self.cached_bbox {
    Some(b) => Some(b)
    None => {
      let entries = self.to_array()
      if entries.length() == 0 {
        return None
      }
      let mut min_lat = 90.0
      let mut max_lat = -90.0
      let mut min_lng = 180.0
      let mut max_lng = -180.0
      for e in entries {
        if e.location.lat < min_lat {
          min_lat = e.location.lat
        }
        if e.location.lat > max_lat {
          max_lat = e.location.lat
        }
        if e.location.lng < min_lng {
          min_lng = e.location.lng
        }
        if e.location.lng > max_lng {
          max_lng = e.location.lng
        }
      }
      let b : @types.BBox = { min_lat, max_lat, min_lng, max_lng, }
      self.cached_bbox = Some(b)
      Some(b)
    }
  }
}

///|
/// Find entries whose distance to a reference point is within `max_km`.
/// Returns (entry, distance_km) pairs sorted by ascending distance.
pub fn Index::find_within_distance(
  self : Index,
  point : @types.GeoPoint,
  max_km : Double,
) -> Array[(@types.GeoEntry, Double)] {
  let results = self.find_within_distance_unsorted(point, max_km)
  results.sort_by(fn(a, b) {
    if a.1 < b.1 {
      -1
    } else if a.1 > b.1 {
      1
    } else {
      0
    }
  })
  results
}

///| Like `find_within_distance` but skips the final sort.
/// Callers that don't need sorted results (e.g. DBSCAN range queries)
/// should prefer this for significant O(k·log k) savings per call.
///
/// Uses bbox_around → adaptive grid/R-tree search → haversine refine.
/// The grid path wins for sparse data (skips empty cells); R-tree wins
/// for dense data. See `Index::query_bbox` for the choice logic.
pub fn Index::find_within_distance_unsorted(
  self : Index,
  point : @types.GeoPoint,
  max_km : Double,
) -> Array[(@types.GeoEntry, Double)] {
  let bbox = @geo.bbox_around(point, max_km)
  let candidates = self.query_bbox(bbox)
  let pairs : Array[(@types.GeoEntry, Double)] = []
  for e in candidates {
    let d = @geo.haversine(point, e.location)
    if d <= max_km {
      pairs.push((e, d))
    }
  }
  pairs
}

///| Like `find_within_distance_unsorted` but returns only the entries,
/// skipping the (entry, distance) tuple packing entirely. Callers that
/// only need the member set (e.g. DBSCAN range queries) should prefer
/// this — it avoids allocating a tuple per result.
pub fn Index::find_within_distance_entries(
  self : Index,
  point : @types.GeoPoint,
  max_km : Double,
) -> Array[@types.GeoEntry] {
  let bbox = @geo.bbox_around(point, max_km)
  let candidates = self.query_bbox(bbox)
  let out : Array[@types.GeoEntry] = []
  for e in candidates {
    if @geo.haversine(point, e.location) <= max_km {
      out.push(e)
    }
  }
  out
}

///|
/// Find entries sorted by distance to a reference point (no radius filter).
/// Uses the R-tree index for sub-linear performance.
pub fn Index::find_sorted_by_distance(
  self : Index,
  point : @types.GeoPoint,
) -> Array[(@types.GeoEntry, Double)] {
  let entries = self.to_array()
  let out : Array[(@types.GeoEntry, Double)] = []
  for e in entries {
    out.push((e, @geo.haversine(point, e.location)))
  }
  out.sort_by(fn(a, b) {
    if a.1 < b.1 {
      -1
    } else if a.1 > b.1 {
      1
    } else {
      0
    }
  })
  out
}

///| Update an existing entry's location. Returns true if the entry existed

///|
/// and was updated.
pub fn Index::update_location(
  self : Index,
  id : String,
  new_location : @types.GeoPoint,
) -> Bool {
  match self.entries.get(id) {
    None => false
    Some(entry) => {
      ignore(self.remove(id))
      let new_entry = @types.GeoEntry::make(
        entry.id,
        entry.name,
        entry.address,
        new_location,
      )
      new_entry.tags = entry.tags
      self.insert(new_entry)
      true
    }
  }
}

///| Update an existing entry's name. Returns true if the entry existed

///|
/// and was updated.
pub fn Index::update_name(self : Index, id : String, new_name : String) -> Bool {
  match self.entries.get(id) {
    None => false
    Some(entry) => {
      ignore(self.remove(id))
      let new_entry = @types.GeoEntry::make(
        entry.id,
        new_name,
        entry.address,
        entry.location,
      )
      new_entry.tags = entry.tags
      self.insert(new_entry)
      true
    }
  }
}
