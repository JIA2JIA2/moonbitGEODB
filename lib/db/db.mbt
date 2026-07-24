// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

/// The main geo database. Wraps an in-memory `Index` with persistence,
/// parsing helpers, and a friendlier query API.
///
/// Typical usage:
///   let db = GeoDB::open("geo.db")
///   db.insert(@types.GeoEntry::make("p01", "Tiananmen", ..., ...))
///   let nearby = db.find_nearby(point, radius_km=5.0, limit=10)
///   db.save() // persist to disk
pub(all) struct GeoDB {
  path : String? // file path for save/load; None = in-memory only
  index : @index.Index
  next_seq : @ref.Ref[Int]
} derive(Debug)

///| Create an empty in-memory database (no auto-persistence).
pub fn GeoDB::in_memory() -> GeoDB {
  {
    path: None,
    index: @index.Index::new(),
    next_seq: @ref.Ref(0),
  }
}

///| Open (or create) a database backed by a file at `path`. If the file
/// exists and contains valid JSON, its entries are loaded. Subsequent
/// calls to `save` write back to the same path.
pub fn GeoDB::open(path : String) -> GeoDB {
  let db = { path: Some(path), index: @index.Index::new(), next_seq: @ref.Ref(0) }
  match @persist.load_entries(path) {
    Ok(entries) =>
      for e in entries {
        db.index.insert(e)
      }
    Err(_) => () // treat missing/corrupt file as empty DB
  }
  db
}

///| Number of entries currently stored.
pub fn GeoDB::size(self : GeoDB) -> Int {
  self.index.size()
}

///| Generate a unique id (monotonic, scoped to this DB instance).
pub fn GeoDB::gen_id(self : GeoDB, prefix : String) -> String {
  let n = self.next_seq.val
  self.next_seq.val = n + 1
  "\{prefix}\{n}"
}

///| Insert (or replace) an entry.
pub fn GeoDB::insert(self : GeoDB, entry : @types.GeoEntry) -> Unit {
  self.index.insert(entry)
}

///| Insert an entry built from raw parts: id, name, lat, lng, address string.
/// The address string is parsed via `@parser.parse_address`; on failure an
/// empty Address is used. Returns the inserted entry.
pub fn GeoDB::insert_raw(
  self : GeoDB,
  id : String,
  name : String,
  lat : Double,
  lng : Double,
  address_str : String
) -> @types.GeoEntry {
  let location = @types.GeoPoint::make(lat, lng)
  let address = try @parser.parse_address(address_str) catch {
    _ => @types.Address::empty()
  }
  let entry = @types.GeoEntry::make(id, name, address, location)
  self.insert(entry)
  entry
}

///| Insert a "name<TAB>lat,lng<TAB>address" record line. Returns the
/// inserted entry, or None if the line could not be parsed.
pub fn GeoDB::insert_record_line(
  self : GeoDB,
  line : String
) -> @types.GeoEntry? {
  try {
    let parsed = @parser.parse_record_line(line)
    // Assign a generated id if the parsed entry's id is empty.
    let entry = if parsed.id.length() == 0 {
      let id = self.gen_id("e")
      @types.GeoEntry::make(id, parsed.name, parsed.address, parsed.location)
    } else {
      parsed
    }
    self.insert(entry)
    Some(entry)
  } catch {
    _ => None
  }
}

///| Lookup an entry by id.
pub fn GeoDB::get(self : GeoDB, id : String) -> @types.GeoEntry? {
  self.index.get(id)
}

///| Remove an entry by id. Returns the removed entry if it existed.
pub fn GeoDB::remove(self : GeoDB, id : String) -> @types.GeoEntry? {
  self.index.remove(id)
}

///| All entries (snapshot array).
pub fn GeoDB::all(self : GeoDB) -> Array[@types.GeoEntry] {
  self.index.to_array()
}

///| Find entries whose name exactly matches (case-insensitive).
pub fn GeoDB::find_by_name(self : GeoDB, name : String) -> Array[@types.GeoEntry] {
  self.index.find_by_name(name)
}

///| Find entries whose name starts with `prefix` (case-insensitive).
pub fn GeoDB::find_name_prefix(
  self : GeoDB,
  prefix : String
) -> Array[@types.GeoEntry] {
  self.index.find_name_prefix(prefix)
}

///| Find entries whose name contains `needle` (case-insensitive).
pub fn GeoDB::find_name_contains(
  self : GeoDB,
  needle : String
) -> Array[@types.GeoEntry] {
  self.index.find_name_contains(needle)
}

///| Find all entries inside a bounding box.
pub fn GeoDB::find_in_bbox(
  self : GeoDB,
  bbox : @types.BBox
) -> Array[@types.GeoEntry] {
  self.index.query_bbox(bbox)
}

///| Find entries within `radius_km` of `point`, sorted by ascending distance.
/// `limit` caps the result count.
pub fn GeoDB::find_nearby(
  self : GeoDB,
  point : @types.GeoPoint,
  radius_km~ : Double,
  limit~ : Int = 10
) -> Array[(@types.GeoEntry, Double)] {
  let bbox = @geo.bbox_around(point, radius_km)
  let candidates = self.index.query_bbox(bbox)
  let pairs : Array[(@types.GeoEntry, Double)] = []
  for e in candidates {
    let d = @geo.haversine(point, e.location)
    if d <= radius_km {
      pairs.push((e, d))
    }
  }
  pairs.sort_by(fn(a, b) { if a.1 < b.1 { -1 } else if a.1 > b.1 { 1 } else { 0 } })
  // Take first `limit`.
  let out : Array[(@types.GeoEntry, Double)] = []
  let mut i = 0
  for p in pairs {
    if i >= limit {
      break
    }
    out.push(p)
    i = i + 1
  }
  out
}

///| k nearest neighbours to `point`. Returns up to `k` (entry, distance_km) pairs.
pub fn GeoDB::find_nearest(
  self : GeoDB,
  point : @types.GeoPoint,
  k : Int
) -> Array[(@types.GeoEntry, Double)] {
  self.index.query_nearest(point, k)
}

///| Serialize the entire DB to a JSON string.
pub fn GeoDB::to_json(self : GeoDB) -> String {
  @persist.entries_to_json(self.all())
}

///| Replace all entries with those parsed from a JSON string.
pub fn GeoDB::from_json(self : GeoDB, text : String) -> Result[Unit, String] {
  match @persist.entries_from_json(text) {
    Err(msg) => Err(msg)
    Ok(entries) => {
      // Clear and reload.
      for e in self.all() {
        ignore(self.index.remove(e.id))
      }
      for e in entries {
        self.index.insert(e)
      }
      Ok(())
    }
  }
}

///| Save the DB to its backing file (set via `open`). Returns Err if no
/// path is configured or the write fails.
pub fn GeoDB::save(self : GeoDB) -> Result[Unit, String] {
  match self.path {
    None => Err("no backing path; use save_to(path) instead")
    Some(p) => @persist.save_entries(p, self.all())
  }
}

///| Save the DB to a specific file path (also updates the backing path).
pub fn GeoDB::save_to(self : GeoDB, path : String) -> Result[Unit, String] {
  // We can't mutate `self.path` (immutable struct field), so we just save
  // to the requested path. Future calls to `save` still use the original path.
  @persist.save_entries(path, self.all())
}

///| Iterate over all entries.
pub fn GeoDB::iter(self : GeoDB) -> Iter[@types.GeoEntry] {
  self.index.iter()
}
