// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

/// A combined spatial + name index over `GeoEntry` records.
///
/// - Spatial: a uniform lat/lng grid buckets entry IDs for fast bbox queries.
/// - Name: a hash map from lowercased name → entry IDs for exact / prefix
///   lookup. Substring search is a linear scan over the name index.
///
/// The index also owns the canonical entry map (id -> GeoEntry) so that
/// queries can return full records without an extra hop.
pub(all) struct Index {
  entries : @hashmap.HashMap[String, @types.GeoEntry]
  grid : @hashmap.HashMap[String, Array[String]]
  by_name : @hashmap.HashMap[String, Array[String]]
  cell_size : Double // degrees
} derive(Eq, Debug)

///| Default grid cell size: 0.1° (~11 km at the equator).
pub let default_cell_size : Double = 0.1

///| Create an empty index with a given grid cell size in degrees.
pub fn Index::new(cell_size~ : Double = default_cell_size) -> Index {
  {
    entries: @hashmap.HashMap([]),
    grid: @hashmap.HashMap([]),
    by_name: @hashmap.HashMap([]),
    cell_size,
  }
}

///| Number of entries currently indexed.
pub fn Index::size(self : Index) -> Int {
  self.entries.length()
}

///| Floor that handles negative numbers correctly (toward -inf).
fn math_floor(x : Double) -> Int {
  let i = x.to_int()
  if x < 0.0 && x != i.to_double() {
    i - 1
  } else {
    i
  }
}

///| Compute the grid cell key for a geographic point.
fn cell_key(lat : Double, lng : Double, cell_size : Double) -> String {
  let lat_idx = math_floor((lat + 90.0) / cell_size)
  let lng_idx = math_floor((lng + 180.0) / cell_size)
  "\{lat_idx},\{lng_idx}"
}

///| Insert (or replace) an entry. Updates both spatial and name indexes.
pub fn Index::insert(self : Index, entry : @types.GeoEntry) -> Unit {
  // Remove old version if present (so stale grid/name slots get cleared).
  if self.entries.contains(entry.id) {
    ignore(self.remove(entry.id))
  }
  self.entries[entry.id] = entry
  // Spatial grid.
  let key = cell_key(entry.location.lat, entry.location.lng, self.cell_size)
  match self.grid.get(key) {
    None => self.grid[key] = [entry.id]
    Some(arr) => arr.push(entry.id)
  }
  // Name index (lowercased for case-insensitive lookup).
  let name_key = entry.name.to_lower()
  if name_key.length() > 0 {
    match self.by_name.get(name_key) {
      None => self.by_name[name_key] = [entry.id]
      Some(arr) => arr.push(entry.id)
    }
  }
}

///| Remove an entry by id. Returns the removed entry if it existed.
pub fn Index::remove(self : Index, id : String) -> @types.GeoEntry? {
  match self.entries.get(id) {
    None => None
    Some(entry) => {
      ignore(self.entries.remove(id))
      // Drop from grid cell.
      let key = cell_key(entry.location.lat, entry.location.lng, self.cell_size)
      match self.grid.get(key) {
        Some(arr) => {
          let filtered = arr.iter().filter(fn(x) { x != id }).collect()
          if filtered.length() == 0 {
            ignore(self.grid.remove(key))
          } else {
            self.grid[key] = filtered
          }
        }
        None => ()
      }
      // Drop from name index.
      let name_key = entry.name.to_lower()
      if name_key.length() > 0 {
        match self.by_name.get(name_key) {
          Some(arr) => {
            let filtered = arr.iter().filter(fn(x) { x != id }).collect()
            if filtered.length() == 0 {
              ignore(self.by_name.remove(name_key))
            } else {
              self.by_name[name_key] = filtered
            }
          }
          None => ()
        }
      }
      Some(entry)
    }
  }
}

///| Lookup an entry by id.
pub fn Index::get(self : Index, id : String) -> @types.GeoEntry? {
  self.entries.get(id)
}

///| Iterate over all entries. Order is unspecified.
pub fn Index::iter(self : Index) -> Iter[@types.GeoEntry] {
  self.entries.iter().map(fn(p) { p.1 })
}

///| Range query: return all entries whose location lies inside `bbox`.
/// Uses the grid to limit the scan to overlapping cells.
pub fn Index::query_bbox(
  self : Index,
  bbox : @types.BBox
) -> Array[@types.GeoEntry] {
  let result : Array[@types.GeoEntry] = []
  let min_lat_idx = math_floor((bbox.min_lat + 90.0) / self.cell_size)
  let max_lat_idx = math_floor((bbox.max_lat + 90.0) / self.cell_size)
  let min_lng_idx = math_floor((bbox.min_lng + 180.0) / self.cell_size)
  let max_lng_idx = math_floor((bbox.max_lng + 180.0) / self.cell_size)
  let mut lat = min_lat_idx
  while lat <= max_lat_idx {
    let mut lng = min_lng_idx
    while lng <= max_lng_idx {
      let key = "\{lat},\{lng}"
      match self.grid.get(key) {
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

///| k nearest-neighbour query. Returns up to `k` (entry, distance_km) pairs
/// sorted by ascending distance. Falls back to a linear scan over all entries;
/// suitable for tens of thousands of records. For larger scale, an R-tree
/// would be appropriate.
pub fn Index::query_nearest(
  self : Index,
  point : @types.GeoPoint,
  k : Int
) -> Array[(@types.GeoEntry, Double)] {
  if k <= 0 {
    return []
  }
  let pairs : Array[(@types.GeoEntry, Double)] = []
  for entry in self.entries.values() {
    let d = @geo.haversine(point, entry.location)
    pairs.push((entry, d))
  }
  pairs.sort_by(fn(a, b) {
    if a.1 < b.1 {
      -1
    } else if a.1 > b.1 {
      1
    } else {
      0
    }
  })
  // Take first k.
  let out : Array[(@types.GeoEntry, Double)] = []
  let mut i = 0
  for p in pairs {
    if i >= k {
      break
    }
    out.push(p)
    i = i + 1
  }
  out
}

///| Exact (case-insensitive) name lookup.
pub fn Index::find_by_name(
  self : Index,
  name : String
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

///| Prefix (case-insensitive) name lookup. Returns entries whose name starts
/// with the given prefix.
pub fn Index::find_name_prefix(
  self : Index,
  prefix : String
) -> Array[@types.GeoEntry] {
  let p = prefix.to_lower()
  if p.length() == 0 {
    return []
  }
  let out : Array[@types.GeoEntry] = []
  for entry in self.entries.values() {
    if entry.name.to_lower().has_prefix(p) {
      out.push(entry)
    }
  }
  out
}

///| Substring (case-insensitive) name lookup.
pub fn Index::find_name_contains(
  self : Index,
  needle : String
) -> Array[@types.GeoEntry] {
  let n = needle.to_lower()
  if n.length() == 0 {
    return []
  }
  let out : Array[@types.GeoEntry] = []
  for entry in self.entries.values() {
    if entry.name.to_lower().contains(n) {
      out.push(entry)
    }
  }
  out
}

///| Return all entries as an array (snapshot copy).
pub fn Index::to_array(self : Index) -> Array[@types.GeoEntry] {
  self.entries.values().collect()
}
