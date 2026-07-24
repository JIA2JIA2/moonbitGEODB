// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

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
pub(all) struct Index {
  entries : @hashmap.HashMap[String, @types.GeoEntry]
  grid : @hashmap.HashMap[String, Array[String]]
  by_name : @hashmap.HashMap[String, Array[String]]
  by_tag : @hashmap.HashMap[String, Array[String]]
  by_province : @hashmap.HashMap[String, Array[String]]
  by_city : @hashmap.HashMap[String, Array[String]]
  by_district : @hashmap.HashMap[String, Array[String]]
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
    by_tag: @hashmap.HashMap([]),
    by_province: @hashmap.HashMap([]),
    by_city: @hashmap.HashMap([]),
    by_district: @hashmap.HashMap([]),
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

///| Insert (or replace) an entry. Updates spatial, name, tag, and address indexes.
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
      // Drop from tag indexes.
      for tag in entry.tags {
        let tag_key = tag.to_lower()
        if tag_key.length() > 0 {
          match self.by_tag.get(tag_key) {
            Some(arr) => {
              let filtered = arr.iter().filter(fn(x) { x != id }).collect()
              if filtered.length() == 0 {
                ignore(self.by_tag.remove(tag_key))
              } else {
                self.by_tag[tag_key] = filtered
              }
            }
            None => ()
          }
        }
      }
      // Drop from address indexes.
      if entry.address.province.length() > 0 {
        let prov_key = entry.address.province.to_lower()
        match self.by_province.get(prov_key) {
          Some(arr) => {
            let filtered = arr.iter().filter(fn(x) { x != id }).collect()
            if filtered.length() == 0 {
              ignore(self.by_province.remove(prov_key))
            } else {
              self.by_province[prov_key] = filtered
            }
          }
          None => ()
        }
      }
      if entry.address.city.length() > 0 {
        let city_key = entry.address.city.to_lower()
        match self.by_city.get(city_key) {
          Some(arr) => {
            let filtered = arr.iter().filter(fn(x) { x != id }).collect()
            if filtered.length() == 0 {
              ignore(self.by_city.remove(city_key))
            } else {
              self.by_city[city_key] = filtered
            }
          }
          None => ()
        }
      }
      if entry.address.district.length() > 0 {
        let dist_key = entry.address.district.to_lower()
        match self.by_district.get(dist_key) {
          Some(arr) => {
            let filtered = arr.iter().filter(fn(x) { x != id }).collect()
            if filtered.length() == 0 {
              ignore(self.by_district.remove(dist_key))
            } else {
              self.by_district[dist_key] = filtered
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

///| Find entries that have a specific tag (case-insensitive).
pub fn Index::find_by_tag(
  self : Index,
  tag : String
) -> Array[@types.GeoEntry] {
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

///| Find entries that have ALL the specified tags (AND logic).
pub fn Index::find_by_all_tags(
  self : Index,
  tags : Array[String]
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
          Some(entry) => {
            if check_all_tags(entry.tags, sorted_tags) {
              result.push(entry)
            }
          }
        }
      }
      result
    }
  }
}

///| Helper: check whether `tags` (already lower-cased) are all present
///| in `entry_tags` (compared case-insensitively).
fn check_all_tags(entry_tags : Array[String], tags : Array[String]) -> Bool {
  for t in tags {
    let mut found = false
    for et in entry_tags {
      if et.to_lower() == t {
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
///| size (so that the most selective tag is checked first).
fn sort_tag_list(tags : Array[String], idx : Index) -> Array[String] {
  let out = tags
  out.sort_by(fn(a, b) {
    let la = match idx.by_tag.get(a) {
      Some(arr) => arr.length()
      None => 0
    }
    let lb = match idx.by_tag.get(b) {
      Some(arr) => arr.length()
      None => 0
    }
    if la < lb { -1 } else if la > lb { 1 } else { 0 }
  })
  out
}

///| Find entries that have ANY of the specified tags (OR logic).
pub fn Index::find_by_any_tags(
  self : Index,
  tags : Array[String]
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
      Some(ids) => {
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
  }
  out
}

///| Find entries by province (case-insensitive).
pub fn Index::find_by_province(
  self : Index,
  province : String
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

///| Find entries by city (case-insensitive).
pub fn Index::find_by_city(
  self : Index,
  city : String
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

///| Find entries by district (case-insensitive).
pub fn Index::find_by_district(
  self : Index,
  district : String
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

///| Find entries by province AND city (case-insensitive).
pub fn Index::find_by_province_city(
  self : Index,
  province : String,
  city : String
) -> Array[@types.GeoEntry] {
  let prov_key = province.to_lower()
  let city_key = city.to_lower()
  match self.by_province.get(prov_key) {
    None => []
    Some(prov_ids) => {
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
}

///| List all unique tags in the index.
pub fn Index::list_tags(self : Index) -> Array[String] {
  let out : Array[String] = []
  for key in self.by_tag.keys() {
    out.push(key)
  }
  out.sort()
  out
}

///| List all unique provinces in the index.
pub fn Index::list_provinces(self : Index) -> Array[String] {
  let out : Array[String] = []
  for key in self.by_province.keys() {
    out.push(key)
  }
  out.sort()
  out
}

///| List all unique cities in the index.
pub fn Index::list_cities(self : Index) -> Array[String] {
  let out : Array[String] = []
  for key in self.by_city.keys() {
    out.push(key)
  }
  out.sort()
  out
}

///| List all unique districts in the index.
pub fn Index::list_districts(self : Index) -> Array[String] {
  let out : Array[String] = []
  for key in self.by_district.keys() {
    out.push(key)
  }
  out.sort()
  out
}

// ---- Geofence / advanced queries ----

///| Check whether a point lies inside the index's combined bounding box.
/// Returns None if the index is empty.
pub fn Index::contains_point(self : Index, point : @types.GeoPoint) -> Bool {
  match self.compute_bbox() {
    None => false
    Some(bbox) => @geo.bbox_contains(bbox, point)
  }
}

///| Compute the combined bounding box of all entries.
pub fn Index::compute_bbox(self : Index) -> @types.BBox? {
  let entries = self.to_array()
  if entries.length() == 0 {
    return None
  }
  let mut min_lat = 90.0
  let mut max_lat = -90.0
  let mut min_lng = 180.0
  let mut max_lng = -180.0
  for e in entries {
    if e.location.lat < min_lat { min_lat = e.location.lat }
    if e.location.lat > max_lat { max_lat = e.location.lat }
    if e.location.lng < min_lng { min_lng = e.location.lng }
    if e.location.lng > max_lng { max_lng = e.location.lng }
  }
  Some({ min_lat, max_lat, min_lng, max_lng })
}

///| Find entries whose distance to a reference point is within `max_km`.
/// Returns (entry, distance_km) pairs sorted by ascending distance.
pub fn Index::find_within_distance(
  self : Index,
  point : @types.GeoPoint,
  max_km : Double
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
  pairs.sort_by(fn(a, b) { if a.1 < b.1 { -1 } else if a.1 > b.1 { 1 } else { 0 } })
  pairs
}

///| Find entries sorted by distance to a reference point (no radius filter).
pub fn Index::find_sorted_by_distance(
  self : Index,
  point : @types.GeoPoint
) -> Array[(@types.GeoEntry, Double)] {
  let pairs : Array[(@types.GeoEntry, Double)] = []
  for e in self.to_array() {
    let d = @geo.haversine(point, e.location)
    pairs.push((e, d))
  }
  pairs.sort_by(fn(a, b) { if a.1 < b.1 { -1 } else if a.1 > b.1 { 1 } else { 0 } })
  pairs
}

///| Update an existing entry's location. Returns true if the entry existed
///| and was updated.
pub fn Index::update_location(
  self : Index,
  id : String,
  new_location : @types.GeoPoint
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
///| and was updated.
pub fn Index::update_name(
  self : Index,
  id : String,
  new_name : String
) -> Bool {
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
