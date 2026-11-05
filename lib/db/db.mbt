// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

///|
/// The main geo database. Wraps an in-memory `Index` with binary persistence,
/// parsing helpers, and a friendlier query API.
///
/// Typical usage:
///   let db = GeoDB::open("geo.db")
///   db.insert(@types.GeoEntry::make("p01", "Tiananmen", ..., ...))
///   let nearby = db.find_nearby(point, radius_km=5.0, limit=10)
///   db.save() // persist to disk in binary format
pub(all) struct GeoDB {
  mut path : String? // file path for save/load; None = in-memory only
  index : @index.Index
  next_seq : @ref.Ref[Int]
  wal_ops : @ref.Ref[Int] // number of records currently in the WAL
  mut created_at : Int64
  mut updated_at : Int64
  mut auto_save : Bool
  mut cached_voronoi : Array[@geo.VoronoiCell]? // cached Voronoi diagram
  mut voronoi_dirty : Bool // true when entries changed
} derive(Debug)

pub extend GeoDB with Debug::{ to_repr }

///|
/// Create an empty in-memory database (no auto-persistence).
pub fn GeoDB::in_memory() -> GeoDB {
  {
    path: None,
    index: @index.Index::new(),
    next_seq: @ref.Ref(0),
    wal_ops: @ref.Ref(0),
    created_at: 0L,
    updated_at: 0L,
    auto_save: false,
    cached_voronoi: None,
    voronoi_dirty: false,
  }
}

///|
/// Open (or create) a database backed by a file at `path`. If the file
/// exists and contains valid binary data, its entries and metadata are loaded.
/// If `auto_save` is true, every insert/remove automatically saves to disk.
pub fn GeoDB::open(path : String, auto_save? : Bool = false) -> GeoDB {
  let now = @persist.file_mtime(path)
  let db = {
    path: Some(path),
    index: @index.Index::new(),
    next_seq: @ref.Ref(0),
    wal_ops: @ref.Ref(0),
    created_at: if now > 0 {
      now
    } else {
      0L
    },
    updated_at: now,
    auto_save,
    cached_voronoi: None,
    voronoi_dirty: false,
  }
  match @persist.load_snapshot(path) {
    Ok((entries, created_at, updated_at)) => {
      db.index.bulk_insert(entries)
      db.created_at = created_at
      db.updated_at = updated_at
    }
    Err(_) => () // treat missing/corrupt file as empty DB
  }
  // Replay the write-ahead log on top of the snapshot.
  let records = @persist.load_wal(path)
  for r in records {
    if r.op == @persist.wal_op_upsert {
      match r.entry {
        Some(e) => db.index.insert(e)
        None => ()
      }
    } else {
      ignore(db.index.remove(r.id))
    }
  }
  db.wal_ops.val = records.length()
  if records.length() > 0 {
    let wal_mtime = @persist.file_mtime(@persist.wal_path(path))
    if wal_mtime > 0 {
      db.updated_at = wal_mtime
    }
  }
  db
}

///|
/// Number of entries currently stored.
pub fn GeoDB::size(self : GeoDB) -> Int {
  self.index.size()
}

///|
/// Generate a unique id (monotonic, scoped to this DB instance).
pub fn GeoDB::gen_id(self : GeoDB, prefix : String) -> String {
  let n = self.next_seq.val
  self.next_seq.val = n + 1
  "\{prefix}\{n}"
}

///|
/// Insert (or replace) an entry. Triggers auto-save if enabled.
pub fn GeoDB::insert(self : GeoDB, entry : @types.GeoEntry) -> Unit {
  self.index.insert(entry)
  self.voronoi_dirty = true
  if self.auto_save {
    self.log_upsert(entry)
  }
}

///|
/// Bulk insert many entries at once. Faster than calling `insert` in a loop
/// because R-tree and helper indexes are updated in one pass without per-entry
/// duplicate checks.
pub fn GeoDB::bulk_insert(self : GeoDB, entries : Array[@types.GeoEntry]) -> Unit {
  self.index.bulk_insert(entries)
  self.voronoi_dirty = true
  if self.auto_save {
    ignore(self.save())
  }
}

///|
/// Insert an entry built from raw parts: id, name, lat, lng, address string.
/// The address string is parsed via `@parser.parse_address`; on failure an
/// empty Address is used. Returns the inserted entry.
pub fn GeoDB::insert_raw(
  self : GeoDB,
  id : String,
  name : String,
  lat : Double,
  lng : Double,
  address_str : String,
) -> @types.GeoEntry {
  let location = @types.GeoPoint::make(lat, lng)
  let address = @parser.parse_address(address_str) catch {
    _ => @types.Address::empty()
  }
  let entry = @types.GeoEntry::make(id, name, address, location)
  self.insert(entry)
  entry
}

///|
/// For a given entry, find its `k` nearest neighbours (excluding itself).
/// Returns (other_entry, distance_km) pairs sorted by ascending distance.
pub fn GeoDB::find_neighbors(
  self : GeoDB,
  id : String,
  k : Int,
) -> Array[(@types.GeoEntry, Double)] {
  match self.get(id) {
    None => []
    Some(target) => {
      let raw = self.index.query_nearest(target.location, k + 1)
      let out : Array[(@types.GeoEntry, Double)] = []
      for pair in raw {
        if pair.0.id == id {
          continue
        }
        if out.length() >= k {
          break
        }
        out.push(pair)
      }
      out
    }
  }
}

///|
/// Insert a "name<TAB>lat,lng<TAB>address" record line. Returns the
/// inserted entry, or None if the line could not be parsed.
pub fn GeoDB::insert_record_line(
  self : GeoDB,
  line : String,
) -> @types.GeoEntry? {
  try {
    let parsed = @parser.parse_record_line(line)
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

///|
/// Lookup an entry by id.
pub fn GeoDB::get(self : GeoDB, id : String) -> @types.GeoEntry? {
  self.index.get(id)
}

///|
/// Remove an entry by id. Returns the removed entry if it existed.
/// Triggers auto-save if enabled.
pub fn GeoDB::remove(self : GeoDB, id : String) -> @types.GeoEntry? {
  let result = self.index.remove(id)
  if result != None {
    self.voronoi_dirty = true
    if self.auto_save {
      self.log_delete(id)
    }
  }
  result
}

///|
/// All entries (snapshot array).
pub fn GeoDB::all(self : GeoDB) -> Array[@types.GeoEntry] {
  self.index.to_array()
}

///|
/// Find entries whose name exactly matches (case-insensitive).
pub fn GeoDB::find_by_name(
  self : GeoDB,
  name : String,
) -> Array[@types.GeoEntry] {
  self.index.find_by_name(name)
}

///|
/// Find entries whose name starts with `prefix` (case-insensitive).
pub fn GeoDB::find_name_prefix(
  self : GeoDB,
  prefix : String,
) -> Array[@types.GeoEntry] {
  self.index.find_name_prefix(prefix)
}

///|
/// Find entries whose name contains `needle` (case-insensitive).
pub fn GeoDB::find_name_contains(
  self : GeoDB,
  needle : String,
) -> Array[@types.GeoEntry] {
  self.index.find_name_contains(needle)
}

///|
/// Find all entries inside a bounding box.
pub fn GeoDB::find_in_bbox(
  self : GeoDB,
  bbox : @types.BBox,
) -> Array[@types.GeoEntry] {
  self.index.query_bbox(bbox)
}

///|
/// Find entries within `radius_km` of `point`, sorted by ascending distance.
/// `limit` caps the result count.
pub fn GeoDB::find_nearby(
  self : GeoDB,
  point : @types.GeoPoint,
  radius_km~ : Double,
  limit? : Int = 10,
) -> Array[(@types.GeoEntry, Double)] {
  if limit <= 0 {
    return []
  }
  // The nearest `limit` entries are sufficient: any entry outside that set is
  // farther than all of them, so it cannot enter the top-limit result.
  let raw = self.index.query_nearest(point, limit)
  let out : Array[(@types.GeoEntry, Double)] = []
  for p in raw {
    if p.1 <= radius_km {
      out.push(p)
    }
  }
  out
}

///|
/// k nearest neighbours to `point`. Returns up to `k` (entry, distance_km) pairs.
pub fn GeoDB::find_nearest(
  self : GeoDB,
  point : @types.GeoPoint,
  k : Int,
) -> Array[(@types.GeoEntry, Double)] {
  self.index.query_nearest(point, k)
}

///|
/// Serialize the entire DB to binary Bytes.
pub fn GeoDB::to_bytes(self : GeoDB) -> Bytes {
  @persist.binary_encode_snapshot(self.all(), self.created_at, self.updated_at)
}

///|
/// Replace all entries with those decoded from binary Bytes.
pub fn GeoDB::from_bytes(self : GeoDB, data : Bytes) -> Result[Unit, String] {
  match @persist.binary_decode_snapshot(data) {
    Err(msg) => Err(msg)
    Ok((entries, created_at, updated_at)) => {
      self.index.clear()
      self.index.bulk_insert(entries)
      self.created_at = created_at
      self.updated_at = updated_at
      match self.path {
        Some(p) => {
          @persist.clear_wal(p)
          self.wal_ops.val = 0
        }
        None => ()
      }
      Ok(())
    }
  }
}

///|
/// Number of WAL records after which an automatic full snapshot is written.
let wal_compact_threshold : Int = 1024

///|
fn GeoDB::log_upsert(self : GeoDB, entry : @types.GeoEntry) -> Unit {
  match self.path {
    None => ()
    Some(p) =>
      match @persist.append_wal_upsert(p, entry) {
        Ok(_) => self.after_wal_append(p)
        Err(_) => ignore(self.save())
      }
  }
}

///|
fn GeoDB::log_delete(self : GeoDB, id : String) -> Unit {
  match self.path {
    None => ()
    Some(p) =>
      match @persist.append_wal_delete(p, id) {
        Ok(_) => self.after_wal_append(p)
        Err(_) => ignore(self.save())
      }
  }
}

///|
fn GeoDB::after_wal_append(self : GeoDB, _p : String) -> Unit {
  let n = self.wal_ops.val + 1
  self.wal_ops.val = n
  if n >= wal_compact_threshold {
    ignore(self.save())
  }
}

///|
/// Save the DB to its backing file using atomic binary write with metadata.
pub fn GeoDB::save(self : GeoDB) -> Result[Unit, String] {
  match self.path {
    None => Err("no backing path; use save_to(path) instead")
    Some(p) => {
      let now = @persist.file_mtime(p)
      self.updated_at = if now > 0 { now } else { 0L }
      match @persist.atomic_save_entries(
        p,
        self.all(),
        self.created_at,
        self.updated_at,
      ) {
        Err(e) => Err(e)
        Ok(_) => {
          @persist.clear_wal(p)
          self.wal_ops.val = 0
          Ok(())
        }
      }
    }
  }
}

///|
/// Save the DB to a specific file path (also updates the backing path).
pub fn GeoDB::save_to(self : GeoDB, path : String) -> Result[Unit, String] {
  let now = @persist.file_mtime(path)
  self.updated_at = if now > 0 { now } else { 0L }
  let is_backing = match self.path {
    Some(p) => p == path
    None => true
  }
  match self.path {
    None => self.path = Some(path)
    Some(_) => ()
  }
  match @persist.atomic_save_entries(
    path,
    self.all(),
    self.created_at,
    self.updated_at,
  ) {
    Err(e) => Err(e)
    Ok(_) => {
      @persist.clear_wal(path)
      if is_backing {
        self.wal_ops.val = 0
      }
      Ok(())
    }
  }
}

///|
/// Create a backup of the current database file.
pub fn GeoDB::backup(self : GeoDB) -> Result[String, String] {
  match self.path {
    None => Err("no backing path to backup")
    Some(p) =>
      match self.save() {
        Err(e) => Err("backup failed: \{e}")
        Ok(_) => @persist.create_backup(p)
      }
  }
}

///|
/// Restore the database from its .bak backup file.
pub fn GeoDB::restore(self : GeoDB) -> Result[Unit, String] {
  match self.path {
    None => Err("no backing path to restore")
    Some(p) =>
      match @persist.restore_from_backup(p) {
        Err(e) => Err(e)
        Ok(_) =>
          match @persist.load_snapshot(p) {
            Err(e) => Err("reload after restore failed: \{e}")
            Ok((entries, created_at, updated_at)) => {
              self.index.clear()
              self.index.bulk_insert(entries)
              self.created_at = created_at
              self.updated_at = updated_at
              @persist.clear_wal(p)
              self.wal_ops.val = 0
              Ok(())
            }
          }
      }
  }
}

///|
/// Check database integrity. Returns the metadata on success.
pub fn GeoDB::check(self : GeoDB) -> Result[@persist.DBMeta, String] {
  match self.path {
    None => Err("no backing path to check")
    Some(p) => @persist.check_integrity(p)
  }
}

///|
/// Return database metadata (version, timestamps, entry count).
pub fn GeoDB::metadata(self : GeoDB) -> @persist.DBMeta {
  {
    version: @persist.db_version,
    created_at: self.created_at,
    updated_at: self.updated_at,
    entry_count: self.index.size(),
  }
}

///|
/// Toggle auto-save on/off. Returns the new setting.
pub fn GeoDB::set_auto_save(self : GeoDB, enabled : Bool) -> Bool {
  self.auto_save = enabled
  self.auto_save
}

///|
/// Iterate over all entries.
pub fn GeoDB::iter(self : GeoDB) -> Iter[@types.GeoEntry] {
  self.index.iter()
}

// ---- Tag-based queries ----

///|
/// Find entries that have a specific tag (case-insensitive).
pub fn GeoDB::find_by_tag(self : GeoDB, tag : String) -> Array[@types.GeoEntry] {
  self.index.find_by_tag(tag)
}

///|
/// Find entries that have ALL the specified tags (AND logic).
pub fn GeoDB::find_by_all_tags(
  self : GeoDB,
  tags : Array[String],
) -> Array[@types.GeoEntry] {
  self.index.find_by_all_tags(tags)
}

///|
/// Find entries that have ANY of the specified tags (OR logic).
pub fn GeoDB::find_by_any_tags(
  self : GeoDB,
  tags : Array[String],
) -> Array[@types.GeoEntry] {
  self.index.find_by_any_tags(tags)
}

///|
/// List all unique tags in the database.
pub fn GeoDB::list_tags(self : GeoDB) -> Array[String] {
  self.index.list_tags()
}

// ---- Address-based queries ----

///|
/// Find entries by province (case-insensitive).
pub fn GeoDB::find_by_province(
  self : GeoDB,
  province : String,
) -> Array[@types.GeoEntry] {
  self.index.find_by_province(province)
}

///|
/// Find entries by city (case-insensitive).
pub fn GeoDB::find_by_city(
  self : GeoDB,
  city : String,
) -> Array[@types.GeoEntry] {
  self.index.find_by_city(city)
}

///|
/// Find entries by district (case-insensitive).
pub fn GeoDB::find_by_district(
  self : GeoDB,
  district : String,
) -> Array[@types.GeoEntry] {
  self.index.find_by_district(district)
}

///|
/// Find entries by province AND city (case-insensitive).
pub fn GeoDB::find_by_province_city(
  self : GeoDB,
  province : String,
  city : String,
) -> Array[@types.GeoEntry] {
  self.index.find_by_province_city(province, city)
}

///|
/// List all unique provinces in the database.
pub fn GeoDB::list_provinces(self : GeoDB) -> Array[String] {
  self.index.list_provinces()
}

///|
/// List all unique cities in the database.
pub fn GeoDB::list_cities(self : GeoDB) -> Array[String] {
  self.index.list_cities()
}

///|
/// List all unique districts in the database.
pub fn GeoDB::list_districts(self : GeoDB) -> Array[String] {
  self.index.list_districts()
}

// ---- Geographic statistics ----

///|
/// Compute the geographic center (average lat/lng) of all entries.
/// Returns (center_point, entry_count) or None if DB is empty.
pub fn GeoDB::compute_center(self : GeoDB) -> (@types.GeoPoint, Int)? {
  self.index.compute_center()
}

///|
/// Compute the total bounding box of all entries.
/// Returns (bbox, entry_count) or None if DB is empty.
pub fn GeoDB::compute_bbox(self : GeoDB) -> (@types.BBox, Int)? {
  match self.index.compute_bbox() {
    None => None
    Some(bbox) => Some((bbox, self.index.size()))
  }
}

///|
/// Compute the great-circle distance between the two farthest entries.
/// Returns (point_a, point_b, distance_km) or None if DB has < 2 entries.
pub fn GeoDB::compute_max_distance(
  self : GeoDB,
) -> (@types.GeoPoint, @types.GeoPoint, Double)? {
  let entries = self.all()
  if entries.length() < 2 {
    return None
  }
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  // The farthest pair is always a pair of convex-hull vertices, so only the
  // hull (typically far smaller than the full set) needs pairwise checks.
  let hull = @geo.convex_hull(pts)
  if hull.length() < 2 {
    let p = if hull.length() == 1 { hull[0] } else { pts[0] }
    return Some((p, p, 0.0))
  }
  let mut max_d = 0.0
  let mut p1 = hull[0]
  let mut p2 = hull[1]
  for i in 0..<hull.length() {
    for j in (i + 1)..<hull.length() {
      let d = @geo.haversine(hull[i], hull[j])
      if d > max_d {
        max_d = d
        p1 = hull[i]
        p2 = hull[j]
      }
    }
  }
  Some((p1, p2, max_d))
}

///|
/// Compute region distribution: count entries per province.
/// Returns array of (province, count) sorted by count descending.
pub fn GeoDB::province_distribution(self : GeoDB) -> Array[(String, Int)] {
  let counts : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for e in self.all() {
    let prov = e.address.province
    if prov.length() > 0 {
      let count = counts.get(prov).unwrap_or(0)
      counts[prov] = count + 1
    }
  }
  let result : Array[(String, Int)] = []
  for key in counts.keys() {
    let count = counts.get(key).unwrap_or(0)
    result.push((key, count))
  }
  result.sort_by(fn(a, b) {
    if a.1 > b.1 {
      -1
    } else if a.1 < b.1 {
      1
    } else {
      0
    }
  })
  result
}

///|
/// Compute city distribution within a province.
/// Returns array of (city, count) sorted by count descending.
pub fn GeoDB::city_distribution(
  self : GeoDB,
  province? : String = "",
) -> Array[(String, Int)] {
  let counts : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for e in self.all() {
    if province.length() == 0 || e.address.province == province {
      let city = e.address.city
      if city.length() > 0 {
        let count = counts.get(city).unwrap_or(0)
        counts[city] = count + 1
      }
    }
  }
  let result : Array[(String, Int)] = []
  for key in counts.keys() {
    let count = counts.get(key).unwrap_or(0)
    result.push((key, count))
  }
  result.sort_by(fn(a, b) {
    if a.1 > b.1 {
      -1
    } else if a.1 < b.1 {
      1
    } else {
      0
    }
  })
  result
}

///|
/// Compute tag distribution: count entries per tag.
/// Returns array of (tag, count) sorted by count descending.
pub fn GeoDB::tag_distribution(self : GeoDB) -> Array[(String, Int)] {
  let counts : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for e in self.all() {
    for tag in e.tags {
      let count = counts.get(tag).unwrap_or(0)
      counts[tag] = count + 1
    }
  }
  let result : Array[(String, Int)] = []
  for key in counts.keys() {
    let count = counts.get(key).unwrap_or(0)
    result.push((key, count))
  }
  result.sort_by(fn(a, b) {
    if a.1 > b.1 {
      -1
    } else if a.1 < b.1 {
      1
    } else {
      0
    }
  })
  result
}

///|
/// Generate a human-readable geographic summary of the database.
pub fn GeoDB::summary(self : GeoDB) -> String {
  let entries = self.all()
  let lines : Array[String] = []
  lines.push("=== Geographic Database Summary ===")
  lines.push("Total entries: " + entries.length().to_string())

  match self.compute_center() {
    None => lines.push("Center: N/A (empty)")
    Some((center, _)) =>
      lines.push(
        "Center: (" +
        center.lat.to_string() +
        ", " +
        center.lng.to_string() +
        ")",
      )
  }

  match self.compute_bbox() {
    None => lines.push("Bounding box: N/A (empty)")
    Some((bbox, _)) => {
      lines.push("Bounding box:")
      lines.push(
        "  SW: (" +
        bbox.min_lat.to_string() +
        ", " +
        bbox.min_lng.to_string() +
        ")",
      )
      lines.push(
        "  NE: (" +
        bbox.max_lat.to_string() +
        ", " +
        bbox.max_lng.to_string() +
        ")",
      )
    }
  }

  match self.compute_max_distance() {
    None => lines.push("Max distance: N/A (< 2 entries)")
    Some((_, _, d)) => lines.push("Max distance: " + d.to_string() + " km")
  }

  let prov_dist = self.province_distribution()
  if prov_dist.length() > 0 {
    lines.push("Provinces (" + prov_dist.length().to_string() + "):")
    for pair in prov_dist {
      lines.push("  " + pair.0 + ": " + pair.1.to_string() + " entries")
    }
  }

  let tag_dist = self.tag_distribution()
  if tag_dist.length() > 0 {
    lines.push("Tags (" + tag_dist.length().to_string() + "):")
    for pair in tag_dist {
      lines.push("  " + pair.0 + ": " + pair.1.to_string() + " entries")
    }
  }

  lines.join("\n")
}

// ---- Geofence / advanced query APIs ----

///|
/// Check whether a point lies inside the combined bounding box of all entries.
pub fn GeoDB::contains_point(self : GeoDB, point : @types.GeoPoint) -> Bool {
  self.index.contains_point(point)
}

///|
/// Find entries whose distance to a reference point is within `max_km`.
pub fn GeoDB::find_within_distance(
  self : GeoDB,
  point : @types.GeoPoint,
  max_km : Double,
) -> Array[(@types.GeoEntry, Double)] {
  self.index.find_within_distance(point, max_km)
}

///|
/// Find all entries sorted by distance to a reference point.
pub fn GeoDB::find_sorted_by_distance(
  self : GeoDB,
  point : @types.GeoPoint,
) -> Array[(@types.GeoEntry, Double)] {
  self.index.find_sorted_by_distance(point)
}

///|
/// Update the location of an existing entry.
pub fn GeoDB::update_location(
  self : GeoDB,
  id : String,
  new_location : @types.GeoPoint,
) -> Bool {
  let ok = self.index.update_location(id, new_location)
  if ok && self.auto_save {
    match self.get(id) {
      Some(e) => self.log_upsert(e)
      None => ()
    }
  }
  ok
}

///|
/// Update the name of an existing entry.
pub fn GeoDB::update_name(self : GeoDB, id : String, new_name : String) -> Bool {
  let ok = self.index.update_name(id, new_name)
  if ok && self.auto_save {
    match self.get(id) {
      Some(e) => self.log_upsert(e)
      None => ()
    }
  }
  ok
}

// ---- Tag management ----

///| Add a tag to an existing entry. Returns true if the entry was found

///|
/// and the tag was not already present.
pub fn GeoDB::add_tag(self : GeoDB, id : String, tag : String) -> Bool {
  match self.index.get(id) {
    None => false
    Some(entry) => {
      let lower = tag.to_lower()
      // Check if already present (case-insensitive).
      let mut exists = false
      for t in entry.tags {
        if t.to_lower() == lower {
          exists = true
          break
        }
      }
      if exists {
        return false
      }
      ignore(self.index.remove(id))
      let new_entry = @types.GeoEntry::make(
        entry.id,
        entry.name,
        entry.address,
        entry.location,
      )
      new_entry.tags = entry.tags
      new_entry.tags.push(tag)
      self.index.insert(new_entry)
      if self.auto_save {
        self.log_upsert(new_entry)
      }
      true
    }
  }
}

///| Remove a tag from an existing entry. Returns true if the entry was

///|
/// found and the tag was present.
pub fn GeoDB::remove_tag(self : GeoDB, id : String, tag : String) -> Bool {
  match self.index.get(id) {
    None => false
    Some(entry) => {
      let lower = tag.to_lower()
      let new_tags = entry.tags
        .iter()
        .filter(fn(t) { t.to_lower() != lower })
        .collect()
      if new_tags.length() == entry.tags.length() {
        return false
      }
      ignore(self.index.remove(id))
      let new_entry = @types.GeoEntry::make(
        entry.id,
        entry.name,
        entry.address,
        entry.location,
      )
      new_entry.tags = new_tags
      self.index.insert(new_entry)
      if self.auto_save {
        self.log_upsert(new_entry)
      }
      true
    }
  }
}

// ---- Fuzzy / Levenshtein search ----

///|
/// Compute the Levenshtein (edit) distance between two strings.
/// A smaller value means the strings are more similar.
pub fn levenshtein_distance(a : String, b : String) -> Int {
  levenshtein_distance_chars(chars_of(a), chars_of(b))
}

///|
fn levenshtein_distance_chars(ca : Array[Int], cb : Array[Int]) -> Int {
  let na = ca.length()
  let nb = cb.length()
  if na == 0 {
    return nb
  }
  if nb == 0 {
    return na
  }
  // Use a 2-row DP table to save memory.
  let mut prev : Array[Int] = []
  let mut curr : Array[Int] = []
  let mut j = 0
  while j <= nb {
    prev.push(j)
    curr.push(0)
    j = j + 1
  }
  let mut i = 1
  while i <= na {
    curr[0] = i
    let mut j2 = 1
    while j2 <= nb {
      let cost = if ca[i - 1] == cb[j2 - 1] { 0 } else { 1 }
      curr[j2] = min3(prev[j2] + 1, curr[j2 - 1] + 1, prev[j2 - 1] + cost)
      j2 = j2 + 1
    }
    let new_prev = curr
    curr = prev
    prev = new_prev
    i = i + 1
  }
  prev[nb]
}

///|
/// Convert a String to an array of chars (as Int code points).
fn chars_of(s : String) -> Array[Int] {
  let out : Array[Int] = []
  for c in s {
    out.push(c.to_int())
  }
  out
}

///|
/// Minimum of three integers.
fn min3(a : Int, b : Int, c : Int) -> Int {
  let m = if a < b { a } else { b }
  if m < c {
    m
  } else {
    c
  }
}

///| Find entries whose name is similar to `query` (case-insensitive) within

///| a maximum Levenshtein edit distance. Returns (entry, distance) pairs

///|
/// sorted by ascending distance.
pub fn GeoDB::find_name_fuzzy(
  self : GeoDB,
  query : String,
  max_distance? : Int = 2,
) -> Array[(@types.GeoEntry, Int)] {
  let q = query.to_lower()
  let q_chars = chars_of(q)
  let q_len = q_chars.length()
  let results : Array[(@types.GeoEntry, Int)] = []
  let candidates = self.index.name_length_candidates(q_len, max_distance)
  for e in candidates {
    let name = e.name.to_lower()
    let name_chars = chars_of(name)
    let dist = levenshtein_distance_chars(name_chars, q_chars)
    if dist <= max_distance {
      results.push((e, dist))
    }
  }
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

// ---- Semantic address matching ----

///|
/// Rank stored entries against a free-form address query using the
/// three-level address matcher (exact / partial / none). Entries are
/// compared on their name (which holds the raw address for corpus
/// records); non-matching entries are dropped, then results are sorted
/// by match level and score, strongest first.
pub fn GeoDB::match_addresses(
  self : GeoDB,
  query : String,
  limit? : Int = 10,
) -> Array[(@types.GeoEntry, @parser.MatchResult)] {
  let prepared = @parser.prepare_query(query)
  let results : Array[(@types.GeoEntry, @parser.MatchResult)] = []
  let cache : @hashmap.HashMap[String, @parser.MatchResult] = @hashmap.HashMap([])
  for e in self.all() {
    let r = match cache.get(e.name) {
      Some(r) => r
      None => {
        let (r, _) = @parser.match_address_prepared(prepared, e.name)
        cache[e.name] = r
        r
      }
    }
    match r.level {
      None => ()
      _ => results.push((e, r))
    }
  }
  results.sort_by(fn(a, b) {
    let ra = a.1.level.rank()
    let rb = b.1.level.rank()
    if ra > rb {
      -1
    } else if ra < rb {
      1
    } else if a.1.score > b.1.score {
      -1
    } else if a.1.score < b.1.score {
      1
    } else {
      0
    }
  })
  if results.length() <= limit {
    results
  } else {
    let top : Array[(@types.GeoEntry, @parser.MatchResult)] = []
    let mut i = 0
    while i < limit {
      top.push(results[i])
      i = i + 1
    }
    top
  }
}

// ---- Export ----

///|
/// Export all entries as a CSV string (RFC 4180-ish).
/// Columns: id, name, lat, lng, country, province, city, district,
/// street, detail, postal_code, tags (semicolon-separated).
pub fn GeoDB::to_csv(self : GeoDB) -> String {
  let entries = self.all()
  let sb = StringBuilder(size_hint=entries.length() * 96 + 80)
  sb.write_string(
    "id,name,lat,lng,country,province,city,district,street,detail,postal_code,tags",
  )
  for e in entries {
    sb.write_char('\n')
    sb.write_string(escape_csv(e.id))
    sb.write_char(',')
    sb.write_string(escape_csv(e.name))
    sb.write_char(',')
    sb.write_string(e.location.lat.to_string())
    sb.write_char(',')
    sb.write_string(e.location.lng.to_string())
    sb.write_char(',')
    sb.write_string(escape_csv(e.address.country))
    sb.write_char(',')
    sb.write_string(escape_csv(e.address.province))
    sb.write_char(',')
    sb.write_string(escape_csv(e.address.city))
    sb.write_char(',')
    sb.write_string(escape_csv(e.address.district))
    sb.write_char(',')
    sb.write_string(escape_csv(e.address.street))
    sb.write_char(',')
    sb.write_string(escape_csv(e.address.detail))
    sb.write_char(',')
    sb.write_string(escape_csv(e.address.postal_code))
    sb.write_char(',')
    sb.write_string(escape_csv(e.tags.join(";")))
  }
  sb.to_string()
}

///|
/// Escape a value for CSV: wrap in quotes if it contains comma, quote, or newline.
fn escape_csv(s : String) -> String {
  let mut needs_quote = false
  for c in s {
    if c == ',' || c == '"' || c == '\n' {
      needs_quote = true
      break
    }
  }
  if !needs_quote {
    return s
  }
  let sb = StringBuilder(size_hint=s.length() + 2)
  sb.write_char('"')
  for c in s {
    if c == '"' {
      sb.write_string("\"\"")
    } else {
      sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

// ---- Batch operations ----

///|
/// Insert multiple entries at once. Returns the number of entries inserted.
pub fn GeoDB::insert_batch(
  self : GeoDB,
  entries : Array[@types.GeoEntry],
) -> Int {
  let auto = self.auto_save
  if auto {
    self.auto_save = false
  }
  for e in entries {
    self.index.insert(e)
  }
  self.voronoi_dirty = true
  self.auto_save = auto
  if auto && entries.length() > 0 {
    ignore(self.save())
  }
  entries.length()
}

///|
/// Remove multiple entries by id. Returns the number of entries actually removed.
pub fn GeoDB::remove_batch(self : GeoDB, ids : Array[String]) -> Int {
  let mut n = 0
  for id in ids {
    if self.index.remove(id) != None {
      n = n + 1
    }
  }
  if self.auto_save && n > 0 {
    ignore(self.save())
  }
  n
}

///|
/// Remove all entries from the database.
pub fn GeoDB::clear(self : GeoDB) -> Unit {
  self.index.clear()
  self.voronoi_dirty = true
  if self.auto_save {
    ignore(self.save())
  }
}

// ---- JSON import / export ----

///|
/// Export all entries to a JSON string (array of GeoEntry objects).
/// Uses the MoonBit ToJson derive on GeoEntry for a compact, machine-readable
/// interchange format suitable for web APIs and inter-process data exchange.
pub fn GeoDB::to_json(self : GeoDB) -> String {
  let entries = self.all()
  let parts : Array[String] = []
  for e in entries {
    parts.push(entry_to_json_string(e))
  }
  if parts.length() == 0 {
    "[]"
  } else {
    "[" + parts.join(",") + "]"
  }
}

///|
/// Serialize one entry directly, avoiding an intermediate Json tree.
fn entry_to_json_string(e : @types.GeoEntry) -> String {
  let p = e.location
  "{" +
  "\"id\":\"" +
  escape_json_string(e.id) +
  "\"," +
  "\"name\":\"" +
  escape_json_string(e.name) +
  "\"," +
  "\"address\":" +
  address_to_json_string(e.address) +
  "," +
  "\"location\":{\"lat\":" +
  p.lat.to_string() +
  ",\"lng\":" +
  p.lng.to_string() +
  "}," +
  "\"tags\":" +
  string_array_to_json(e.tags) +
  "}"
}

///|
/// Serialize an address directly, avoiding an intermediate Json tree.
fn address_to_json_string(a : @types.Address) -> String {
  "{" +
  "\"country\":\"" +
  escape_json_string(a.country) +
  "\"," +
  "\"province\":\"" +
  escape_json_string(a.province) +
  "\"," +
  "\"city\":\"" +
  escape_json_string(a.city) +
  "\"," +
  "\"district\":\"" +
  escape_json_string(a.district) +
  "\"," +
  "\"street\":\"" +
  escape_json_string(a.street) +
  "\"," +
  "\"postal_code\":\"" +
  escape_json_string(a.postal_code) +
  "\"," +
  "\"detail\":\"" +
  escape_json_string(a.detail) +
  "\"" +
  "}"
}

///|
/// Split a top-level JSON array into element substrings without building the
/// whole Json tree. Returns [] when the input is not a top-level array.
fn split_top_level_array(json : String) -> Array[String] {
  let out : Array[String] = []
  let n = json.length()
  let mut i = 0
  while i < n {
    let c = json.get_char(i).unwrap()
    if c != ' ' && c != '\n' && c != '\r' && c != '\t' {
      break
    }
    i = i + 1
  }
  if i >= n || json.get_char(i).unwrap() != '[' {
    return out
  }
  i = i + 1
  let mut depth = 0
  let mut in_str = false
  let mut escaped = false
  let mut start = i
  while i < n {
    let c = json.get_char(i).unwrap()
    if in_str {
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        in_str = false
      }
    } else if c == '"' {
      in_str = true
    } else if c == '{' || c == '[' {
      depth = depth + 1
    } else if c == '}' || c == ']' {
      if c == ']' && depth == 0 {
        let part = json[start:i].to_owned()
        if part.trim().length() > 0 {
          out.push(part)
        }
        return out
      }
      depth = depth - 1
    } else if c == ',' && depth == 0 {
      let part = json[start:i].to_owned()
      if part.trim().length() > 0 {
        out.push(part)
      }
      start = i + 1
    }
    i = i + 1
  }
  out
}

///|
/// Import entries from a JSON string (array of GeoEntry objects).
/// Returns the number of entries successfully imported.
/// Entries already present (by id) are replaced.
pub fn GeoDB::import_json(self : GeoDB, json : String) -> Int {
  // Strip outer whitespace.
  let trimmed = json.trim().to_owned()
  if trimmed.length() == 0 || trimmed == "[]" {
    return 0
  }
  // Fast path: parse array elements one at a time so peak memory is bounded
  // by the largest single entry instead of the whole Json tree.
  let parts = split_top_level_array(trimmed)
  if parts.length() > 0 {
    let to_insert : Array[@types.GeoEntry] = []
    for part in parts {
      try {
        let item = @json.parse(part)
        match try_import_json_value(item) {
          None => ()
          Some(entry) => to_insert.push(entry)
        }
      } catch {
        _ => ()
      }
    }
    let n = to_insert.length()
    if n > 0 {
      ignore(self.insert_batch(to_insert))
    }
    return n
  }
  // Fallback: single top-level object / non-array input.
  let j = @json.parse(trimmed) catch { _ => return 0 }
  // Expect an array at top level.
  match j {
    Array(arr) => {
      let to_insert : Array[@types.GeoEntry] = []
      for item in arr {
        match try_import_json_value(item) {
          None => ()
          Some(entry) => to_insert.push(entry)
        }
      }
      let n = to_insert.length()
      if n > 0 {
        ignore(self.insert_batch(to_insert))
      }
      n
    }
    _ => 0
  }
}

///|
/// Attempt to decode a Json value into a GeoEntry. Returns None on failure.
fn try_import_json_value(j : Json) -> @types.GeoEntry? {
  try {
    let e : @types.GeoEntry = @json.from_json(j)
    Some(e)
  } catch {
    _ => None
  }
}

// ---- GeoJSON-style export ----

///|
/// Export all entries as a GeoJSON FeatureCollection string.
/// Each entry becomes a Feature with a Point geometry and an id + name +
/// address + tags properties object. Compliant with RFC 7946.
pub fn GeoDB::to_geojson(self : GeoDB) -> String {
  let entries = self.all()
  let sb = StringBuilder(size_hint=entries.length() * 256 + 64)
  sb.write_string("{\"type\":\"FeatureCollection\",\"features\":[")
  let mut i = 0
  for e in entries {
    if i > 0 {
      sb.write_char(',')
    }
    sb.write_string(
      "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[",
    )
    sb.write_string(e.location.lng.to_string())
    sb.write_char(',')
    sb.write_string(e.location.lat.to_string())
    sb.write_string("]},\"properties\":{\"id\":\"")
    sb.write_string(escape_json_string(e.id))
    sb.write_string("\",\"name\":\"")
    sb.write_string(escape_json_string(e.name))
    sb.write_string("\",\"address\":")
    sb.write_string(address_to_json_string(e.address))
    sb.write_string(",\"tags\":")
    sb.write_string(string_array_to_json(e.tags))
    sb.write_string("}}")
    i = i + 1
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
fn escape_json_string(s : String) -> String {
  let mut needs_escape = false
  for c in s {
    if c == '\\' || c == '"' || c == '\n' || c == '\r' || c == '\t' {
      needs_escape = true
      break
    }
  }
  if !needs_escape {
    return s
  }
  let sb = StringBuilder(size_hint=s.length())
  for c in s {
    match c {
      '\\' => sb.write_string("\\\\")
      '"' => sb.write_string("\\\"")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
fn string_array_to_json(arr : Array[String]) -> String {
  let parts : Array[String] = []
  for s in arr {
    parts.push("\"" + escape_json_string(s) + "\"")
  }
  "[" + parts.join(",") + "]"
}

// ---- Distance & pair queries ----

///|
/// Compute the great-circle distance (km) between two entries by id.
/// Returns None if either id is not found.
pub fn GeoDB::distance_between(
  self : GeoDB,
  id_a : String,
  id_b : String,
) -> Double? {
  match (self.get(id_a), self.get(id_b)) {
    (Some(a), Some(b)) => Some(@geo.haversine(a.location, b.location))
    _ => None
  }
}

// ---- Enhanced search ----

///|
/// Case-sensitive version of `find_name_contains`.
pub fn GeoDB::find_name_contains_case(
  self : GeoDB,
  needle : String,
) -> Array[@types.GeoEntry] {
  let results : Array[@types.GeoEntry] = []
  for e in self.all() {
    if e.name.contains(needle) {
      results.push(e)
    }
  }
  results
}

///|
/// Find entries whose name starts with `prefix` (case-sensitive).
pub fn GeoDB::find_name_prefix_case(
  self : GeoDB,
  prefix : String,
) -> Array[@types.GeoEntry] {
  self.index.find_name_prefix_case(prefix)
}

///|
/// Find entries whose name matches a simple wildcard-like pattern:
///   `*` matches any sequence of characters, `?` matches a single char.
/// The rest of the string is literal (case-insensitive).
/// Returns entries whose name matches the pattern.
pub fn GeoDB::find_name_pattern(
  self : GeoDB,
  pattern : String,
) -> Array[@types.GeoEntry] {
  let p = pattern.to_lower()
  let entries = self.all()
  let names = self.index.lowered_names()
  let results : Array[@types.GeoEntry] = []
  let literal = longest_literal(p)
  if literal.length() >= 3 {
    // A wildcard pattern can only match names containing its longest literal
    // run, so the 3-gram index provides a safe candidate set.
    let candidates = self.index.find_name_contains(literal)
    if candidates.length() == 0 {
      return results
    }
    let ids : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
    for c in candidates {
      ids[c.id] = true
    }
    let mut i = 0
    while i < entries.length() && i < names.length() {
      if ids.contains(entries[i].id) && simple_wildcard_match(names[i], p) {
        results.push(entries[i])
      }
      i = i + 1
    }
    return results
  }
  let mut i = 0
  while i < entries.length() && i < names.length() {
    if simple_wildcard_match(names[i], p) {
      results.push(entries[i])
    }
    i = i + 1
  }
  results
}

///|
/// Longest run of literal (non-wildcard) characters in a pattern.
fn longest_literal(pattern : String) -> String {
  let sb = StringBuilder()
  let mut best = ""
  let mut best_len = 0
  let mut cur_len = 0
  for c in pattern {
    if c == '*' || c == '?' {
      if cur_len > best_len {
        best = sb.to_string()
        best_len = cur_len
      }
      sb.reset()
      cur_len = 0
    } else {
      sb.write_char(c)
      cur_len = cur_len + 1
    }
  }
  if cur_len > best_len {
    best = sb.to_string()
  }
  best
}

///|
/// Simple wildcard matching with `*` (any sequence) and `?` (single char).
fn simple_wildcard_match(text : String, pattern : String) -> Bool {
  // Iterative DP with two pointers and a '*' backtrack point.
  let n = text.length()
  let m = pattern.length()
  let mut i = 0
  let mut j = 0
  let mut star_j = -1
  let mut match_i = 0
  while i < n {
    if j < m && (pattern[j] == '?' || pattern[j] == text[i]) {
      i = i + 1
      j = j + 1
    } else if j < m && pattern[j] == '*' {
      star_j = j
      match_i = i
      j = j + 1
    } else if star_j >= 0 {
      j = star_j + 1
      match_i = match_i + 1
      i = match_i
    } else {
      return false
    }
  }
  while j < m && pattern[j] == '*' {
    j = j + 1
  }
  j == m
}

// ---- Aggregation helpers ----

///|
/// Count how many entries have a specific tag (case-insensitive).
pub fn GeoDB::count_by_tag(self : GeoDB, tag : String) -> Int {
  self.index.find_by_any_tags([tag]).length()
}

///|
/// Compute district distribution: count entries per district.
/// Optionally filtered by province (empty = all).
pub fn GeoDB::district_distribution(
  self : GeoDB,
  province? : String = "",
) -> Array[(String, Int)] {
  let counts : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for e in self.all() {
    let district = e.address.district
    if district.length() == 0 {
      continue
    }
    if province.length() > 0 && e.address.province != province {
      continue
    }
    let count = counts.get(district).unwrap_or(0)
    counts[district] = count + 1
  }
  let result : Array[(String, Int)] = []
  for key in counts.keys() {
    let count = counts.get(key).unwrap_or(0)
    result.push((key, count))
  }
  result.sort_by(fn(a, b) {
    if a.1 > b.1 {
      -1
    } else if a.1 < b.1 {
      1
    } else {
      0
    }
  })
  result
}

///|
/// Compute the centroid (simple mean) of the k most-tagged entries,
/// useful for heat-map visualization. Returns (point, count_of_entries_used).
pub fn GeoDB::centroid_weighted_by_tag(
  self : GeoDB,
  tag : String,
) -> (@types.GeoPoint, Int)? {
  let entries = self.find_by_tag(tag)
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
  Some((@types.GeoPoint::make(sum_lat / n, sum_lng / n), entries.length()))
}

// ---- Update / mutation helpers ----

///|
/// Update the address of an existing entry. Returns true on success.
pub fn GeoDB::update_address(
  self : GeoDB,
  id : String,
  new_address : @types.Address,
) -> Bool {
  match self.index.get(id) {
    None => false
    Some(entry) => {
      ignore(self.index.remove(id))
      let new_entry = @types.GeoEntry::make(
        entry.id,
        entry.name,
        new_address,
        entry.location,
      )
      new_entry.tags = entry.tags
      self.index.insert(new_entry)
      if self.auto_save {
        self.log_upsert(new_entry)
      }
      true
    }
  }
}

///|
/// Update the location of an existing entry (lat + lng separately).
/// Returns true if the entry was found and updated.
pub fn GeoDB::update_coordinates(
  self : GeoDB,
  id : String,
  lat : Double,
  lng : Double,
) -> Bool {
  self.update_location(id, @types.GeoPoint::make(lat, lng))
}

///|
/// Rename (replace the name of) an existing entry. Returns true on success.
pub fn GeoDB::rename(self : GeoDB, id : String, new_name : String) -> Bool {
  self.update_name(id, new_name)
}

// ---- Advanced queries ----

///|
/// Find entries inside a strict bbox AND within a radius_km of the
/// center of that bbox. Useful for "downtown" style queries.
pub fn GeoDB::find_in_bbox_strict(
  self : GeoDB,
  bbox : @types.BBox,
  radius_km~ : Double,
) -> Array[@types.GeoEntry] {
  let center_lat = (bbox.min_lat + bbox.max_lat) / 2.0
  let center_lng = (bbox.min_lng + bbox.max_lng) / 2.0
  let center = @types.GeoPoint::make(center_lat, center_lng)
  let bbox_candidates = self.find_in_bbox(bbox)
  let results : Array[@types.GeoEntry] = []
  for e in bbox_candidates {
    let d = @geo.haversine(center, e.location)
    if d <= radius_km {
      results.push(e)
    }
  }
  results
}

///|
/// Find the `k` closest pairs of entries in the DB.
/// Each pair is returned as (entry_a, entry_b, distance_km).
/// Pairs are sorted by ascending distance; the same pair is reported
/// only once (canonical order by id).
///|
/// Insert a pair into a distance-sorted top-k buffer, returning the current
/// k-th distance (or +inf while the buffer is not full).
fn insert_pair_top_k(
  best : Array[(@types.GeoEntry, @types.GeoEntry, Double)],
  a : @types.GeoEntry,
  b : @types.GeoEntry,
  d : Double,
  k : Int,
) -> Double {
  let inf = 1.7976931348623157e+308
  if best.length() < k {
    best.push((a, b, d))
    if best.length() == k {
      best.sort_by(fn(x, y) {
        if x.2 < y.2 {
          -1
        } else if x.2 > y.2 {
          1
        } else {
          0
        }
      })
      return best[k - 1].2
    }
    return inf
  }
  if d < best[k - 1].2 {
    best[k - 1] = (a, b, d)
    let mut j = k - 1
    while j > 0 && best[j - 1].2 > best[j].2 {
      let tmp = best[j - 1]
      best[j - 1] = best[j]
      best[j] = tmp
      j = j - 1
    }
    return best[k - 1].2
  }
  best[k - 1].2
}

///|
pub fn GeoDB::find_nearest_pairs(
  self : GeoDB,
  k : Int,
) -> Array[(@types.GeoEntry, @types.GeoEntry, Double)] {
  if k <= 0 {
    return []
  }
  let entries = self.all()
  let best : Array[(@types.GeoEntry, @types.GeoEntry, Double)] = []
  let seen : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  let inf = 1.7976931348623157e+308
  let mut cutoff = inf
  for a in entries {
    // Cheap probe: when even the nearest neighbour is farther than the current
    // k-th pair distance, this point cannot contribute to the global top-k.
    let probe = self.index.query_nearest(a.location, 2)
    let mut nearest_d = inf
    for p in probe {
      if p.0.id != a.id {
        nearest_d = p.1
        break
      }
    }
    if nearest_d > cutoff {
      continue
    }
    let neighbors = self.index.query_nearest(a.location, k + 1)
    for pair in neighbors {
      let b = pair.0
      if b.id == a.id {
        continue
      }
      let key = if a.id < b.id {
        a.id + "\u0001" + b.id
      } else {
        b.id + "\u0001" + a.id
      }
      if !seen.contains(key) {
        seen[key] = true
        cutoff = insert_pair_top_k(best, a, b, pair.1, k)
      }
    }
  }
  // If fewer than k pairs exist, the buffer may not be sorted yet.
  best.sort_by(fn(x, y) {
    if x.2 < y.2 {
      -1
    } else if x.2 > y.2 {
      1
    } else {
      0
    }
  })
  best
}

///|
/// Return the distribution of tag co-occurrence pairs across all entries.
/// Each pair is reported once in canonical order (alphabetical).
pub fn GeoDB::tag_pair_distribution(
  self : GeoDB,
) -> Array[((String, String), Int)] {
  let counts : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for e in self.all() {
    let tags = e.tags
    let n = tags.length()
    let mut i = 0
    while i < n {
      let mut j = i + 1
      while j < n {
        let a = tags[i].to_lower()
        let b = tags[j].to_lower()
        // Canonical ordering by string compare.
        let key = if a < b { a + "\u0001" + b } else { b + "\u0001" + a }
        let c = counts.get(key).unwrap_or(0)
        counts[key] = c + 1
        j = j + 1
      }
      i = i + 1
    }
  }
  let result : Array[((String, String), Int)] = []
  for key in counts.keys() {
    let c = counts.get(key).unwrap_or(0)
    let parts = key.split("\u0001").collect()
    if parts.length() == 2 {
      let a = parts[0].to_owned()
      let b = parts[1].to_owned()
      result.push(((a, b), c))
    }
  }
  result.sort_by(fn(a, b) {
    if a.1 > b.1 {
      -1
    } else if a.1 < b.1 {
      1
    } else {
      0
    }
  })
  result
}

// ---- CSV import ----

///|
/// Import entries from a CSV string (the inverse of `to_csv`).
/// Returns the number of entries successfully imported.
/// Expects the same header and column order as `to_csv`.
pub fn GeoDB::import_csv(self : GeoDB, csv : String) -> Int {
  let lines = csv.split("\n").collect()
  if lines.length() == 0 {
    return 0
  }
  // Skip header line.
  let to_insert : Array[@types.GeoEntry] = []
  let mut i = 1
  while i < lines.length() {
    let line = lines[i].to_owned()
    if line.trim().length() == 0 {
      i = i + 1
      continue
    }
    match parse_csv_row(line) {
      None => ()
      Some(entry) => to_insert.push(entry)
    }
    i = i + 1
  }
  let n = to_insert.length()
  if n > 0 {
    ignore(self.insert_batch(to_insert))
  }
  n
}

///|
/// Parse a single CSV row into a GeoEntry. Handles quoted fields.
fn parse_csv_row(line : String) -> @types.GeoEntry? {
  let fields = parse_csv_fields(line)
  if fields.length() < 12 {
    return None
  }
  let id = fields[0]
  let name = fields[1]
  let lat = @string.parse_double(fields[2]) catch { _ => 0.0 }
  let lng = @string.parse_double(fields[3]) catch { _ => 0.0 }
  let country = fields[4]
  let province = fields[5]
  let city = fields[6]
  let district = fields[7]
  let street = fields[8]
  let detail = fields[9]
  let postal_code = fields[10]
  let tag_str = fields[11]
  let tags = if tag_str.length() == 0 {
    []
  } else {
    let parts = tag_str.split(";").collect()
    let out : Array[String] = []
    for p in parts {
      out.push(p.to_owned())
    }
    out
  }
  if id.length() == 0 && name.length() == 0 {
    return None
  }
  let entry_id = if id.length() == 0 {
    let rand = @random.Rand()
    "csv_" + rand.int(limit=1000000).to_string()
  } else {
    id
  }
  let address : @types.Address = {
    country,
    province,
    city,
    district,
    street,
    postal_code,
    detail,
  }
  let entry = @types.GeoEntry::make(
    entry_id,
    name,
    address,
    @types.GeoPoint::make(lat, lng),
  )
  entry.tags = tags
  Some(entry)
}

///|
/// Split a CSV line into fields, handling double-quote escaping.
/// Uses a simple state machine working on the raw string bytes.
fn parse_csv_fields(line : String) -> Array[String] {
  let out : Array[String] = []
  let n = line.length()
  let mut i = 0
  let mut start = 0
  let mut in_quotes = false
  while i < n {
    let c = line[i]
    if in_quotes {
      if c == '"' {
        // Check for escaped quote.
        if i + 1 < n && line[i + 1] == '"' {
          i = i + 2
          continue
        }
        in_quotes = false
        i = i + 1
        start = i
        continue
      }
      i = i + 1
    } else if c == ',' {
      out.push(line[start:i].to_owned())
      i = i + 1
      start = i
    } else if c == '"' {
      if start == i {
        in_quotes = true
      }
      i = i + 1
    } else {
      i = i + 1
    }
  }
  out.push(line[start:n].to_owned())
  out
}

// ---- GeoJSON import ----

///|
/// Import entries from a GeoJSON FeatureCollection string.
/// Returns the number of entries successfully imported.
/// Each Feature must have a Point geometry and properties with id/name.
pub fn GeoDB::import_geojson(self : GeoDB, geojson : String) -> Int {
  let trimmed = geojson.trim().to_owned()
  if trimmed.length() == 0 {
    return 0
  }
  let j = @json.parse(trimmed) catch { _ => return 0 }
  match j {
    Object(obj) => {
      let to_insert : Array[@types.GeoEntry] = []
      // Check for "type": "FeatureCollection" or single "Feature".
      let typ = obj.get("type")
      match typ {
        Some(String(s)) =>
          if s == "FeatureCollection" {
            // Extract features array.
            match obj.get("features") {
              Some(Array(features)) =>
                for feat in features {
                  match try_import_geojson_feature(feat) {
                    None => ()
                    Some(entry) => to_insert.push(entry)
                  }
                }
              _ => ()
            }
          } else if s == "Feature" {
            match try_import_geojson_feature(j) {
              None => ()
              Some(entry) => to_insert.push(entry)
            }
          }
        _ => ()
      }
      let n = to_insert.length()
      if n > 0 {
        ignore(self.insert_batch(to_insert))
      }
      n
    }
    _ => 0
  }
}

///|
/// Attempt to decode a GeoJSON Feature Json value into a GeoEntry.
fn try_import_geojson_feature(j : Json) -> @types.GeoEntry? {
  match j {
    Object(obj) => {
      // Extract coordinates from geometry.
      let mut lng = 0.0
      let mut lat = 0.0
      match obj.get("geometry") {
        Some(Object(geom)) =>
          match geom.get("coordinates") {
            Some(Array(coords)) =>
              if coords.length() >= 2 {
                match coords[0] {
                  Number(v, ..) => lng = v
                  _ => ()
                }
                match coords[1] {
                  Number(v, ..) => lat = v
                  _ => ()
                }
              } else {
                return None
              }
            _ => return None
          }
        _ => return None
      }
      // Extract properties.
      let id = match obj.get("properties") {
        Some(Object(prop)) =>
          match prop.get("id") {
            Some(String(s)) => s
            _ => ""
          }
        _ => ""
      }
      let name = match obj.get("properties") {
        Some(Object(prop)) =>
          match prop.get("name") {
            Some(String(s)) => s
            _ => ""
          }
        _ => ""
      }
      let entry_id = if id.length() == 0 {
        let rand = @random.Rand()
        "gj_" + rand.int(limit=1000000).to_string()
      } else {
        id
      }
      // Try to parse full address from properties if available.
      let address = match obj.get("properties") {
        Some(Object(prop)) =>
          match prop.get("address") {
            Some(addr_json) =>
              try {
                let a : @types.Address = @json.from_json(addr_json)
                a
              } catch {
                _ => @types.Address::empty()
              }
            _ => @types.Address::empty()
          }
        _ => @types.Address::empty()
      }
      // Extract tags.
      let tags = match obj.get("properties") {
        Some(Object(prop)) =>
          match prop.get("tags") {
            Some(Array(arr)) => {
              let out : Array[String] = []
              for item in arr {
                match item {
                  String(s) => out.push(s)
                  _ => ()
                }
              }
              out
            }
            _ => []
          }
        _ => []
      }
      if name.length() == 0 {
        return None
      }
      let entry = @types.GeoEntry::make(
        entry_id,
        name,
        address,
        @types.GeoPoint::make(lat, lng),
      )
      entry.tags = tags
      Some(entry)
    }
    _ => None
  }
}

// ---- Duplicate detection ----

///|
/// Find groups of entries that are likely duplicates (same physical location).
/// Two entries are considered duplicates if they are within `max_distance_km`
/// of each other AND their names have a Levenshtein edit distance <= `max_edit_dist`.
/// Returns an array of groups, where each group contains the duplicate entries.
pub fn GeoDB::find_duplicates(
  self : GeoDB,
  max_distance_km? : Double = 0.1,
  max_edit_dist? : Int = 2,
) -> Array[Array[@types.GeoEntry]] {
  let entries = self.all()
  let visited : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  let groups : Array[Array[@types.GeoEntry]] = []
  for a in entries {
    if visited.get(a.id).unwrap_or(false) {
      continue
    }
    let group : Array[@types.GeoEntry] = [a]
    visited[a.id] = true
    let nearby = self.index.find_within_distance_unsorted(
      a.location,
      max_distance_km,
    )
    for pair in nearby {
      let b = pair.0
      if visited.get(b.id).unwrap_or(false) {
        continue
      }
      let name_dist = levenshtein_distance(
        a.name.to_lower(),
        b.name.to_lower(),
      )
      if name_dist <= max_edit_dist {
        group.push(b)
        visited[b.id] = true
      }
    }
    if group.length() >= 2 {
      groups.push(group)
    }
  }
  groups
}

// ---- Spatial grid clustering ----

///|
/// Cluster entries into grid cells of roughly `cell_size_km` x `cell_size_km`.
/// Returns an array of (cell_key, centroid_point, member_count) sorted by count desc.
/// Useful for heatmap visualization and data analysis.
pub fn GeoDB::cluster_by_grid(
  self : GeoDB,
  cell_size_km? : Double = 1.0,
) -> Array[(String, @types.GeoPoint, Int)] {
  let cells : @hashmap.HashMap[String, Array[@types.GeoEntry]] = @hashmap.HashMap([],
  )
  let entries = self.all()
  for e in entries {
    let key = grid_key(e.location, cell_size_km)
    let bucket = cells.get(key).unwrap_or([])
    bucket.push(e)
    cells[key] = bucket
  }
  let result : Array[(String, @types.GeoPoint, Int)] = []
  for key in cells.keys() {
    let members = cells.get(key).unwrap_or([])
    if members.length() == 0 {
      continue
    }
    let mut sum_lat = 0.0
    let mut sum_lng = 0.0
    for m in members {
      sum_lat = sum_lat + m.location.lat
      sum_lng = sum_lng + m.location.lng
    }
    let n = members.length().to_double()
    let centroid = @types.GeoPoint::make(sum_lat / n, sum_lng / n)
    result.push((key, centroid, members.length()))
  }
  result.sort_by(fn(a, b) {
    if a.2 > b.2 {
      -1
    } else if a.2 < b.2 {
      1
    } else {
      0
    }
  })
  result
}

///|
/// Compute a grid cell key for a geographic point.
fn grid_key(point : @types.GeoPoint, cell_size_km : Double) -> String {
  // Approximate: 1 degree latitude ≈ 111 km.
  // Longitude correction varies by latitude.
  let lat_cells = (point.lat * 111.0 / cell_size_km).to_int()
  let cos_lat = @math.cos(point.lat * 3.141592653589793 / 180.0)
  let lng_cells = (point.lng * 111.0 * cos_lat / cell_size_km).to_int()
  let lat_str = lat_cells.to_string()
  let lng_str = lng_cells.to_string()
  lat_str + "," + lng_str
}

// ---- Distance matrix ----

///|
/// Compute a pairwise Haversine distance matrix for a set of entry IDs.
/// Returns a 2D array where matrix[i][j] is the distance (km) between
/// ids[i] and ids[j]. Missing IDs are treated as having distance 0
/// to all entries. Returns an empty array if no entries are found.
pub fn GeoDB::distance_matrix(
  self : GeoDB,
  ids : Array[String],
) -> Array[Array[Double]] {
  let n = ids.length()
  let locations : Array[@types.GeoPoint?] = []
  for id in ids {
    locations.push(
      match self.get(id) {
        Some(e) => Some(e.location)
        None => None
      },
    )
  }
  let matrix : Array[Array[Double]] = []
  let mut i = 0
  while i < n {
    let row : Array[Double] = []
    let mut j = 0
    while j < n {
      let d = match (locations[i], locations[j]) {
        (Some(a), Some(b)) => @geo.haversine(a, b)
        _ => 0.0
      }
      row.push(d)
      j = j + 1
    }
    matrix.push(row)
    i = i + 1
  }
  matrix
}

// ---- Reverse geocode ----

///|
/// Find the closest entry to a given coordinate.
/// Returns (entry, distance_km) or None if the DB is empty.
pub fn GeoDB::reverse_geocode(
  self : GeoDB,
  lat : Double,
  lng : Double,
) -> (@types.GeoEntry, Double)? {
  let point = @types.GeoPoint::make(lat, lng)
  match self.index.query_nearest(point, 1) {
    [] => None
    arr => Some(arr[0])
  }
}

// ---- Tag combination queries ----

///|
/// Find entries that have ALL of the specified tags (AND logic).
pub fn GeoDB::find_by_tags_all(
  self : GeoDB,
  tags : Array[String],
) -> Array[@types.GeoEntry] {
  if tags.length() == 0 {
    return []
  }
  self.index.find_by_all_tags(tags)
}

///|
/// Find entries that have ANY of the specified tags (OR logic).
pub fn GeoDB::find_by_tags_any(
  self : GeoDB,
  tags : Array[String],
) -> Array[@types.GeoEntry] {
  if tags.length() == 0 {
    return []
  }
  self.index.find_by_any_tags(tags)
}

// ---- Bounding box queries ----

///|
/// Count entries within a bounding box.
pub fn GeoDB::bbox_count(self : GeoDB, bbox : @types.BBox) -> Int {
  let entries = self.find_in_bbox(bbox)
  entries.length()
}

///|
/// Find all entries within a circular region.
pub fn GeoDB::find_within_radius(
  self : GeoDB,
  lat : Double,
  lng : Double,
  radius_km : Double,
) -> Array[@types.GeoEntry] {
  let center = @types.GeoPoint::make(lat, lng)
  let pairs = self.index.find_within_distance_unsorted(center, radius_km)
  let results : Array[@types.GeoEntry] = []
  for p in pairs {
    results.push(p.0)
  }
  results
}

// ---- Density map ----

///|
/// Compute a density map: grid cells with entry counts.
/// Returns array of (cell_key, centroid_lat, centroid_lng, count).
pub fn GeoDB::density_map(
  self : GeoDB,
  cell_size_km? : Double = 1.0,
) -> Array[(String, Double, Double, Int)] {
  let cells : @hashmap.HashMap[String, Array[@types.GeoEntry]] = @hashmap.HashMap([],
  )
  for e in self.all() {
    let key = grid_key(e.location, cell_size_km)
    let bucket = cells.get(key).unwrap_or([])
    bucket.push(e)
    cells[key] = bucket
  }
  let result : Array[(String, Double, Double, Int)] = []
  for key in cells.keys() {
    let members = cells.get(key).unwrap_or([])
    if members.length() == 0 {
      continue
    }
    let mut sum_lat = 0.0
    let mut sum_lng = 0.0
    for m in members {
      sum_lat = sum_lat + m.location.lat
      sum_lng = sum_lng + m.location.lng
    }
    let n = members.length().to_double()
    result.push((key, sum_lat / n, sum_lng / n, members.length()))
  }
  result.sort_by(fn(a, b) {
    if a.3 > b.3 {
      -1
    } else if a.3 < b.3 {
      1
    } else {
      0
    }
  })
  result
}

// ---- Statistics ----

///|
/// Compute the standard deviation of latitudes and longitudes.
pub fn GeoDB::location_stddev(self : GeoDB) -> (Double, Double) {
  let entries = self.all()
  let n = entries.length().to_double()
  if n <= 1.0 {
    return (0.0, 0.0)
  }
  let mut sum_lat = 0.0
  let mut sum_lng = 0.0
  for e in entries {
    sum_lat = sum_lat + e.location.lat
    sum_lng = sum_lng + e.location.lng
  }
  let mean_lat = sum_lat / n
  let mean_lng = sum_lng / n
  let mut var_lat = 0.0
  let mut var_lng = 0.0
  for e in entries {
    let dlat = e.location.lat - mean_lat
    let dlng = e.location.lng - mean_lng
    var_lat = var_lat + dlat * dlat
    var_lng = var_lng + dlng * dlng
  }
  // Population stddev (divide by n, not n-1).
  (@geo.sqrt(var_lat / n), @geo.sqrt(var_lng / n))
}

///|
/// Compute a histogram of entries per province.
pub fn GeoDB::province_histogram(self : GeoDB) -> Array[(String, Int)] {
  let counts : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for e in self.all() {
    let prov = if e.address.province.length() == 0 {
      "Unknown"
    } else {
      e.address.province
    }
    let count = counts.get(prov).unwrap_or(0)
    counts[prov] = count + 1
  }
  let result : Array[(String, Int)] = []
  for key in counts.keys() {
    result.push((key, counts.get(key).unwrap_or(0)))
  }
  result.sort_by(fn(a, b) {
    if a.1 > b.1 {
      -1
    } else if a.1 < b.1 {
      1
    } else {
      0
    }
  })
  result
}

// ---- Path distance ----

///|
/// Compute the total travel distance along an ordered list of entry IDs.
/// Returns the sum of Haversine distances between consecutive entries (km).
/// Missing IDs are skipped (distance to next existing entry is included).
/// Returns 0 if fewer than 2 valid entries exist.
pub fn GeoDB::path_distance(self : GeoDB, ids : Array[String]) -> Double {
  if ids.length() < 2 {
    return 0.0
  }
  let mut total = 0.0
  let mut prev_entry : @types.GeoEntry? = None
  for id in ids {
    match self.get(id) {
      None => ()
      Some(cur) =>
        match prev_entry {
          None => prev_entry = Some(cur)
          Some(prev) => {
            total = total + @geo.haversine(prev.location, cur.location)
            prev_entry = Some(cur)
          }
        }
    }
  }
  total
}

///|
/// Compute the total path distance and return it along with the valid entries.
pub fn GeoDB::path_detail(
  self : GeoDB,
  ids : Array[String],
) -> (Double, Array[@types.GeoEntry]) {
  let valid : Array[@types.GeoEntry] = []
  for id in ids {
    match self.get(id) {
      None => ()
      Some(e) => valid.push(e)
    }
  }
  let total = self.path_distance(ids)
  (total, valid)
}

// ---- Geohash-based queries ----

///|
/// Whether every character belongs to the standard geohash base32 alphabet.
fn is_valid_geohash(hash : String) -> Bool {
  for c in hash {
    let ok = (c >= '0' && c <= '9') ||
      (c >= 'b' && c <= 'h') ||
      (c >= 'j' && c <= 'k') ||
      (c >= 'm' && c <= 'n') ||
      (c >= 'p' && c <= 'z')
    if !ok {
      return false
    }
  }
  true
}

///|
/// Slightly expand a bbox so points exactly on a geohash cell boundary are
/// still candidates for the subsequent exact prefix check.
fn pad_bbox(bbox : @types.BBox) -> @types.BBox {
  let eps = 1.0e-9
  @types.BBox::from_corners(
    @types.GeoPoint::make(bbox.min_lat - eps, bbox.min_lng - eps),
    @types.GeoPoint::make(bbox.max_lat + eps, bbox.max_lng + eps),
  )
}

///|
/// Find all entries whose geohash at given precision starts with the given prefix.
/// Uses the geohash cell bbox to drive a spatial index lookup, then verifies
/// the exact prefix, instead of scanning and re-encoding every entry.
pub fn GeoDB::find_by_geohash_prefix(
  self : GeoDB,
  prefix : String,
  precision? : Int = 6,
) -> Array[@types.GeoEntry] {
  if prefix.length() == 0 || !is_valid_geohash(prefix) {
    return []
  }
  let candidates = self.index.query_bbox(pad_bbox(@geo.geohash_to_bbox(prefix)))
  let results : Array[@types.GeoEntry] = []
  for e in candidates {
    let gh = @geo.geohash_encode(e.location.lat, e.location.lng, precision)
    if gh.length() >= prefix.length() && gh.has_prefix(prefix) {
      results.push(e)
    }
  }
  results
}

///|
/// Find entries whose geohash at given precision exactly matches the given geohash.
pub fn GeoDB::find_by_geohash(
  self : GeoDB,
  geohash : String,
  precision? : Int = 6,
) -> Array[@types.GeoEntry] {
  if geohash.length() == 0 || !is_valid_geohash(geohash) {
    return []
  }
  let candidates = self.index.query_bbox(pad_bbox(@geo.geohash_to_bbox(geohash)))
  let results : Array[@types.GeoEntry] = []
  for e in candidates {
    let gh = @geo.geohash_encode(e.location.lat, e.location.lng, precision)
    if gh == geohash {
      results.push(e)
    }
  }
  results
}

///|
/// Compute the geohash for a given entry.
pub fn GeoDB::entry_geohash(
  self : GeoDB,
  id : String,
  precision? : Int = 6,
) -> String? {
  match self.get(id) {
    None => None
    Some(e) =>
      Some(@geo.geohash_encode(e.location.lat, e.location.lng, precision))
  }
}

// ---- Pagination ----

///|
/// Return all entries with pagination (limit/offset).
pub fn GeoDB::page_all(
  self : GeoDB,
  limit : Int,
  offset? : Int = 0,
) -> Array[@types.GeoEntry] {
  let all_entries = self.all()
  if offset >= all_entries.length() {
    return []
  }
  let end_idx = @cmp.minimum(offset + limit, all_entries.length())
  let result : Array[@types.GeoEntry] = []
  let mut i = offset
  while i < end_idx {
    result.push(all_entries[i])
    i = i + 1
  }
  result
}

///|
/// Return paginated results from a search query.
pub fn GeoDB::page_results(
  _self : GeoDB,
  results : Array[@types.GeoEntry],
  limit : Int,
  offset? : Int = 0,
) -> Array[@types.GeoEntry] {
  if offset >= results.length() {
    return []
  }
  let end_idx = @cmp.minimum(offset + limit, results.length())
  let result : Array[@types.GeoEntry] = []
  let mut i = offset
  while i < end_idx {
    result.push(results[i])
    i = i + 1
  }
  result
}

// ---- Convex hull of entries ----

///|
/// Compute the convex hull of all entries' locations.
/// Returns an array of (lat, lng) points forming the hull.
pub fn GeoDB::convex_hull_all(self : GeoDB) -> Array[@types.GeoPoint] {
  let entries = self.all()
  let points : Array[@types.GeoPoint] = []
  for e in entries {
    points.push(e.location)
  }
  @geo.convex_hull(points)
}

// ---- Address normalization ----

///|
/// Standardize province/city/district names by stripping common suffixes.
/// E.g., "北京市" -> "北京", "海淀区" -> "海淀".
pub fn GeoDB::normalize_address(self : GeoDB, id : String) -> Bool {
  match self.get(id) {
    None => false
    Some(entry) => {
      let new_addr : @types.Address = {
        country: entry.address.country,
        province: strip_admin_suffix(entry.address.province),
        city: strip_admin_suffix(entry.address.city),
        district: strip_admin_suffix(entry.address.district),
        street: entry.address.street,
        postal_code: entry.address.postal_code,
        detail: entry.address.detail,
      }
      self.update_address(id, new_addr)
    }
  }
}

///|
/// Normalize all entries' addresses. Returns the number of entries modified.
pub fn GeoDB::normalize_all_addresses(self : GeoDB) -> Int {
  let entries = self.all()
  let mut n = 0
  for e in entries {
    if self.normalize_address(e.id) {
      n = n + 1
    }
  }
  if self.auto_save && n > 0 {
    ignore(self.save())
  }
  n
}

// ---- Polygon and spatial operations ----

///|
/// Compute the area of the convex hull of all entries, in square kilometers.
pub fn GeoDB::convex_hull_area(self : GeoDB) -> Double {
  let entries = self.all()
  let points : Array[@types.GeoPoint] = []
  for e in entries {
    points.push(e.location)
  }
  let hull = @geo.convex_hull(points)
  @geo.polygon_area(hull)
}

///|
/// Find all entries whose location lies inside the given polygon.
/// Uses ray-casting for point-in-polygon test.
pub fn GeoDB::find_in_polygon(
  self : GeoDB,
  polygon : Array[@types.GeoPoint],
) -> Array[@types.GeoEntry] {
  let results : Array[@types.GeoEntry] = []
  for e in self.all() {
    if @geo.point_in_polygon(e.location, polygon) {
      results.push(e)
    }
  }
  results
}

///|
/// Compute the average nearest-neighbor distance across all entries (km).
/// Useful for assessing spatial clustering vs. dispersion.
pub fn GeoDB::average_nn_distance(self : GeoDB) -> Double {
  let entries = self.all()
  let points : Array[@types.GeoPoint] = []
  for e in entries {
    points.push(e.location)
  }
  @geo.average_nn_distance(points)
}

///|
/// Perform DBSCAN clustering on all entries.
/// `eps_km` is the neighborhood radius in kilometers.
/// `min_points` is the minimum number of points to form a cluster.
/// Returns an array of clusters; each cluster is an array of entry IDs.
/// Noise points (outliers) are excluded from clusters.
pub fn GeoDB::cluster_dbscan(
  self : GeoDB,
  eps_km : Double,
  min_points : Int,
) -> Array[Array[String]] {
  let entries = self.all()
  let n = entries.length()
  if n == 0 { return [] }
  // Build id → index map once for O(1) reverse lookup from R-tree results.
  let id_to_idx : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  let mut mi = 0
  while mi < n {
    id_to_idx[entries[mi].id] = mi
    mi = mi + 1
  }
  let visited : Array[Bool] = []
  let clustered : Array[Bool] = []
  let mut i = 0
  while i < n {
    visited.push(false)
    clustered.push(false)
    i = i + 1
  }
  let clusters : Array[Array[String]] = []
  i = 0
  while i < n {
    if !visited[i] {
      visited[i] = true
      let raw_neighbors = dbscan_range_query_idx(self, entries[i].location, eps_km, id_to_idx)
      if raw_neighbors.length() >= min_points - 1 {
        // Core point — expand cluster. clustered[] doubles as the global
        // "already assigned to a cluster" guard AND the per-cluster queue
        // dedup set, so initial neighbors and expansion-added points can
        // never be enqueued twice or stolen from an earlier cluster.
        clustered[i] = true
        let queue : Array[Int] = []
        for k in raw_neighbors {
          if !clustered[k] {
            clustered[k] = true
            queue.push(k)
          }
        }
        let mut seed = 0
        while seed < queue.length() {
          let j = queue[seed]
          // DBSCAN standard optimization: skip range query for visited points.
          if !visited[j] {
            visited[j] = true
            let j_neighbors = dbscan_range_query_idx(self, entries[j].location, eps_km, id_to_idx)
            if j_neighbors.length() >= min_points - 1 {
              for k in j_neighbors {
                if !clustered[k] {
                  clustered[k] = true
                  queue.push(k)
                }
              }
            }
          }
          seed = seed + 1
        }
        let cluster : Array[String] = [entries[i].id]
        for k in queue {
          cluster.push(entries[k].id)
        }
        clusters.push(cluster)
      }
    }
    i = i + 1
  }
  clusters
}

///|
/// Find all entries within a geohash bounding box, expanded to 3×3 neighborhood.
/// This is more efficient than scanning all entries for small areas.
pub fn GeoDB::find_by_geohash_bbox(
  self : GeoDB,
  hash : String,
  precision? : Int = 6,
) -> Array[@types.GeoEntry] {
  if hash.length() == 0 || !is_valid_geohash(hash) {
    return []
  }
  let neighbors = @geo.geohash_neighbors(hash)
  let prefixes : Array[String] = []
  let mut min_lat = 90.0
  let mut max_lat = -90.0
  let mut min_lng = 180.0
  let mut max_lng = -180.0
  for nh in neighbors {
    if nh.length() >= precision {
      prefixes.push(geohash_prefix_of(nh, precision))
    }
    let b = @geo.geohash_to_bbox(nh)
    if b.min_lat < min_lat {
      min_lat = b.min_lat
    }
    if b.max_lat > max_lat {
      max_lat = b.max_lat
    }
    if b.min_lng < min_lng {
      min_lng = b.min_lng
    }
    if b.max_lng > max_lng {
      max_lng = b.max_lng
    }
  }
  if prefixes.length() == 0 {
    return []
  }
  let bbox : @types.BBox = { min_lat, max_lat, min_lng, max_lng, }
  let candidates = self.index.query_bbox(pad_bbox(bbox))
  let seen : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  let results : Array[@types.GeoEntry] = []
  for e in candidates {
    let gh = @geo.geohash_encode(e.location.lat, e.location.lng, precision)
    let mut matched = false
    for p in prefixes {
      if gh.length() >= p.length() && gh.has_prefix(p) {
        matched = true
        break
      }
    }
    if matched && !seen.contains(e.id) {
      seen[e.id] = true
      results.push(e)
    }
  }
  results
}

///|
/// Get the geohash bounding box for an entry.
pub fn GeoDB::entry_geohash_bbox(
  self : GeoDB,
  id : String,
  precision? : Int = 6,
) -> @types.BBox? {
  match self.entry_geohash(id, precision~) {
    None => None
    Some(h) => Some(@geo.geohash_to_bbox(h))
  }
}

///|
/// Compute the radial density around a center point.
/// Returns an array of (ring_index, entry_count) for concentric rings.
pub fn GeoDB::radial_density(
  self : GeoDB,
  center : @types.GeoPoint,
  ring_size_km : Double,
  num_rings : Int,
) -> Array[(Int, Int)] {
  let results : Array[(Int, Int)] = []
  let entries = self.all()
  let ring_counts : Array[Int] = []
  let mut r = 0
  while r < num_rings {
    ring_counts.push(0)
    r = r + 1
  }
  for e in entries {
    let d = @geo.haversine(center, e.location)
    let ring = (d / ring_size_km).to_int()
    if ring >= 0 && ring < num_rings {
      ring_counts[ring] = ring_counts[ring] + 1
    }
  }
  r = 0
  while r < num_rings {
    results.push((r, ring_counts[r]))
    r = r + 1
  }
  results
}

///|
/// Export all entries as a GeoJSON FeatureCollection with bbox.
pub fn GeoDB::to_geojson_with_bbox(self : GeoDB) -> String {
  let entries = self.all()
  if self.index.geohash_cache_stale {
    self.index.geohash_cache.clear()
    self.index.geohash_cache_stale = false
  }
  let sb = StringBuilder(size_hint=entries.length() * 300 + 96)
  sb.write_string(
    "{\"type\":\"FeatureCollection\",\"totalFeatures\":" +
    entries.length().to_string() +
    ",\"features\":[",
  )
  let mut i = 0
  for e in entries {
    if i > 0 {
      sb.write_char(',')
    }
    let gh = match self.index.geohash_cache.get(e.id) {
      Some(g) => g
      None => {
        let g = @geo.geohash_encode(e.location.lat, e.location.lng, 8)
        self.index.geohash_cache[e.id] = g
        g
      }
    }
    let bbox = @geo.geohash_to_bbox(gh)
    sb.write_string(
      "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[",
    )
    sb.write_string(e.location.lng.to_string())
    sb.write_char(',')
    sb.write_string(e.location.lat.to_string())
    sb.write_string("]},\"properties\":{\"id\":\"")
    sb.write_string(escape_json_string(e.id))
    sb.write_string("\",\"name\":\"")
    sb.write_string(escape_json_string(e.name))
    sb.write_string("\",\"address\":")
    sb.write_string(address_to_json_string(e.address))
    sb.write_string(",\"tags\":")
    sb.write_string(string_array_to_json(e.tags))
    sb.write_string(",\"bbox\":[")
    sb.write_string(bbox.min_lng.to_string())
    sb.write_char(',')
    sb.write_string(bbox.min_lat.to_string())
    sb.write_char(',')
    sb.write_string(bbox.max_lng.to_string())
    sb.write_char(',')
    sb.write_string(bbox.max_lat.to_string())
    sb.write_string("]}}")
    i = i + 1
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
///| R-tree-backed range query for DBSCAN. Returns indices of entries
/// within `eps_km` of the center point (excluding the center itself).
fn dbscan_range_query_idx(
  db : GeoDB,
  center : @types.GeoPoint,
  eps_km : Double,
  id_to_idx : @hashmap.HashMap[String, Int],
) -> Array[Int] {
  let results : Array[Int] = []
  // Entries-only range query: DBSCAN never reads the distances, so skip
  // both the sort and the (entry, distance) tuple packing.
  let members = db.index.find_within_distance_entries(center, eps_km)
  for e in members {
    match id_to_idx.get(e.id) {
      Some(idx) => results.push(idx)
      None => ()
    }
  }
  results
}

///|
fn geohash_prefix_of(s : String, len : Int) -> String {
  let end = if len < s.length() { len } else { s.length() }
  s[:end].to_owned()
}

///|
fn strip_admin_suffix(name : String) -> String {
  let suffixes : Array[String] = [
    "省", "市", "区", "县", "自治州", "特别行政区", "自治区", "盟",
    "地区",
  ]
  for s in suffixes {
    if name.length() > s.length() && name.has_suffix(s) {
      return name[:name.length() - s.length()].to_owned()
    }
  }
  name
}

// ============================================================
// Query enhancements: histograms, spatial join, ring queries
// ============================================================

// ---- Distance / coordinate histograms ----

///| Compute a distance histogram: for each entry, compute its distance to

///| `center`, then bucket those distances into `num_bins` equally-sized bins

///|
/// spanning [0, max_distance_km]. Returns (bin_start_km, bin_end_km, count).
pub fn GeoDB::distance_histogram(
  self : GeoDB,
  center : @types.GeoPoint,
  max_distance_km : Double,
  num_bins? : Int = 10,
) -> Array[(Double, Double, Int)] {
  if num_bins <= 0 || max_distance_km <= 0.0 {
    return []
  }
  let bin_width = max_distance_km / num_bins.to_double()
  let counts : Array[Int] = []
  let mut b = 0
  while b < num_bins {
    counts.push(0)
    b = b + 1
  }
  for e in self.all() {
    let d = @geo.haversine(center, e.location)
    let bin = (d / bin_width).to_int()
    if bin >= num_bins {
      counts[num_bins - 1] = counts[num_bins - 1] + 1
    } else if bin >= 0 {
      counts[bin] = counts[bin] + 1
    }
  }
  let result : Array[(Double, Double, Int)] = []
  b = 0
  while b < num_bins {
    let start = b.to_double() * bin_width
    let end = (b + 1).to_double() * bin_width
    result.push((start, end, counts[b]))
    b = b + 1
  }
  result
}

///|
/// Generic 1D histogram builder over a [lo, hi] range.
fn GeoDB::coord_histogram_helper(
  self : GeoDB,
  extractor : (@types.GeoEntry) -> Double,
  lo : Double,
  hi : Double,
  num_bins : Int,
) -> Array[(Double, Double, Int)] {
  if num_bins <= 0 || hi <= lo {
    return []
  }
  let range = hi - lo
  let bin_width = range / num_bins.to_double()
  let counts : Array[Int] = []
  let mut b = 0
  while b < num_bins {
    counts.push(0)
    b = b + 1
  }
  for e in self.all() {
    let v = extractor(e)
    let bin = ((v - lo) / bin_width).to_int()
    if bin >= num_bins {
      counts[num_bins - 1] = counts[num_bins - 1] + 1
    } else if bin >= 0 {
      counts[bin] = counts[bin] + 1
    }
  }
  let result : Array[(Double, Double, Int)] = []
  b = 0
  while b < num_bins {
    let start = lo + b.to_double() * bin_width
    let end = lo + (b + 1).to_double() * bin_width
    result.push((start, end, counts[b]))
    b = b + 1
  }
  result
}

///| Compute a latitude histogram: bucket all entries by their latitude.

///|
/// Returns (min_lat, max_lat, count) for each bin.
pub fn GeoDB::lat_histogram(
  self : GeoDB,
  num_bins? : Int = 10,
) -> Array[(Double, Double, Int)] {
  self.coord_histogram_helper(
    fn(e : @types.GeoEntry) { e.location.lat },
    -90.0,
    90.0,
    num_bins,
  )
}

///| Compute a longitude histogram: bucket all entries by their longitude.

///|
/// Returns (min_lng, max_lng, count) for each bin.
pub fn GeoDB::lng_histogram(
  self : GeoDB,
  num_bins? : Int = 10,
) -> Array[(Double, Double, Int)] {
  self.coord_histogram_helper(
    fn(e : @types.GeoEntry) { e.location.lng },
    -180.0,
    180.0,
    num_bins,
  )
}

///| Compute a distance distribution summary (min, max, mean, median) of all

///| pairwise distances, or distances from every entry to a fixed center.

///|
/// Returns (count, min_km, max_km, mean_km, median_km).
///|
/// Maximum entry count for exact all-pairs statistics when no center is given.
let distance_summary_exact_limit : Int = 500

///|
/// Number of sampled pairs used above the exact limit.
let distance_summary_sample_pairs : Int = 200000

///|
/// Returns (count, min_km, max_km, mean_km, median_km).
/// With more than `distance_summary_exact_limit` entries and no center,
/// min/max stay exact (R-tree / convex hull) while mean/median are estimated
/// from a deterministic sample to keep memory bounded.
pub fn GeoDB::distance_summary(
  self : GeoDB,
  center? : @types.GeoPoint? = None,
) -> (Int, Double, Double, Double, Double) {
  match center {
    Some(c) => distance_summary_from_center(self, c)
    None => {
      let entries = self.all()
      if entries.length() < 2 {
        return (0, 0.0, 0.0, 0.0, 0.0)
      }
      if entries.length() <= distance_summary_exact_limit {
        distance_summary_exact(entries)
      } else {
        distance_summary_sampled(self, entries)
      }
    }
  }
}

///|
fn distance_summary_from_center(
  db : GeoDB,
  c : @types.GeoPoint,
) -> (Int, Double, Double, Double, Double) {
  let distances : Array[Double] = []
  for e in db.all() {
    distances.push(@geo.haversine(c, e.location))
  }
  summarize_distances(distances)
}

///|
fn distance_summary_exact(
  entries : Array[@types.GeoEntry],
) -> (Int, Double, Double, Double, Double) {
  let distances : Array[Double] = []
  let n = entries.length()
  let mut i = 0
  while i < n {
    let mut j = i + 1
    while j < n {
      distances.push(
        @geo.haversine(entries[i].location, entries[j].location),
      )
      j = j + 1
    }
    i = i + 1
  }
  summarize_distances(distances)
}

///|
/// Iterative quickselect (Hoare partition, middle pivot) returning order
/// statistic k of arr[0..count). Partially reorders arr in place.
fn quickselect_f64(
  arr : FixedArray[Double],
  count : Int,
  k : Int,
) -> Double {
  let mut lo = 0
  let mut hi = count - 1
  while lo < hi {
    let pivot = arr[(lo + hi) / 2]
    let mut i = lo
    let mut j = hi
    while i <= j {
      while arr[i] < pivot {
        i = i + 1
      }
      while arr[j] > pivot {
        j = j - 1
      }
      if i <= j {
        let t = arr[i]
        arr[i] = arr[j]
        arr[j] = t
        i = i + 1
        j = j - 1
      }
    }
    if k <= j {
      hi = j
    } else if k >= i {
      lo = i
    } else {
      break
    }
  }
  arr[k]
}

///|
/// Mean and median of a fixed-size sample in O(count) average time: linear
/// mean pass plus quickselect for the median order statistic(s). The
/// sampled distance summary discards the sample's min/max (they come from
/// the R-tree instead), so the O(k log k) full sort in summarize_distances
/// is pure waste here. Operates in place on an unboxed FixedArray.
fn sample_mean_median(
  samples : FixedArray[Double],
  count : Int,
) -> (Double, Double) {
  if count == 0 {
    return (0.0, 0.0)
  }
  let mut total = 0.0
  let mut k = 0
  while k < count {
    total = total + samples[k]
    k = k + 1
  }
  let mean = total / count.to_double()
  let median = if count % 2 == 1 {
    quickselect_f64(samples, count, count / 2)
  } else {
    let a = quickselect_f64(samples, count, count / 2 - 1)
    let b = quickselect_f64(samples, count, count / 2)
    (a + b) / 2.0
  }
  (mean, median)
}

///|
fn distance_summary_sampled(
  db : GeoDB,
  entries : Array[@types.GeoEntry],
) -> (Int, Double, Double, Double, Double) {
  let n = entries.length()
  let count = n * (n - 1) / 2
  if count <= distance_summary_sample_pairs {
    // The sample budget covers every pair, so exact statistics are cheap.
    return distance_summary_exact(entries)
  }
  let min_d = match db.find_nearest_pairs(1) {
    [] => 0.0
    pairs => pairs[0].2
  }
  let max_d = match db.compute_max_distance() {
    None => 0.0
    Some((_, _, d)) => d
  }
  let target = if count < distance_summary_sample_pairs {
    count
  } else {
    distance_summary_sample_pairs
  }
  // Cache coordinates in unboxed arrays: the sampling loop touches each
  // entry hundreds of times, and boxed Array reads would add up.
  let lat_of : FixedArray[Double] = FixedArray::make(n, 0.0)
  let lng_of : FixedArray[Double] = FixedArray::make(n, 0.0)
  let mut e = 0
  while e < n {
    lat_of[e] = entries[e].location.lat
    lng_of[e] = entries[e].location.lng
    e = e + 1
  }
  // FixedArray sample: no boxed push per draw; only mean/median are needed
  // (min/max already come from the R-tree), so quickselect replaces the
  // full sort.
  let samples : FixedArray[Double] = FixedArray::make(target, 0.0)
  let mut sc = 0
  let mut state : UInt64 = n.to_uint64()
  while sc < target {
    state = (state * (1103515245 : UInt64) + (12345 : UInt64)) &
      (0x7fffffff : UInt64)
    let i = state.to_int() % n
    state = (state * (1103515245 : UInt64) + (12345 : UInt64)) &
      (0x7fffffff : UInt64)
    let j = state.to_int() % n
    if i != j {
      samples[sc] = @geo.haversine(
        @types.GeoPoint::make(lat_of[i], lng_of[i]),
        @types.GeoPoint::make(lat_of[j], lng_of[j]),
      )
      sc = sc + 1
    }
  }
  let (mean, median) = sample_mean_median(samples, target)
  (count, min_d, max_d, mean, median)
}

///|
fn summarize_distances(
  distances : Array[Double],
) -> (Int, Double, Double, Double, Double) {
  let count = distances.length()
  if count == 0 {
    return (0, 0.0, 0.0, 0.0, 0.0)
  }
  distances.sort_by(fn(a, b) {
    if a < b {
      -1
    } else if a > b {
      1
    } else {
      0
    }
  })
  let mut total = 0.0
  let mut min_d = distances[0]
  let mut max_d = distances[0]
  for d in distances {
    total = total + d
    if d < min_d {
      min_d = d
    }
    if d > max_d {
      max_d = d
    }
  }
  let mean = total / count.to_double()
  let median = if count % 2 == 1 {
    distances[count / 2]
  } else {
    (distances[count / 2 - 1] + distances[count / 2]) / 2.0
  }
  (count, min_d, max_d, mean, median)
}

// ---- Ring / buffer-zone query ----

///| Find all entries whose distance from `center` falls within

///| [inner_radius_km, outer_radius_km]. This is an annulus (ring) query,

///| useful for "things between 1km and 5km from here" style searches.

///|
/// Results are sorted by ascending distance.
pub fn GeoDB::find_in_ring(
  self : GeoDB,
  center : @types.GeoPoint,
  inner_radius_km : Double,
  outer_radius_km : Double,
) -> Array[(@types.GeoEntry, Double)] {
  let mut inner = inner_radius_km
  let mut outer = outer_radius_km
  if inner > outer {
    let tmp = inner
    inner = outer
    outer = tmp
  }
  // Fast path: use index range query to get candidates within outer radius,
  // then filter out those inside inner radius. Avoids scanning all entries.
  let candidates = self.index.find_within_distance(center, outer)
  let results : Array[(@types.GeoEntry, Double)] = []
  for (e, d) in candidates {
    if d >= inner {
      results.push((e, d))
    }
  }
  // candidates already sorted ascending, results preserve that order.
  results
}

///| Convenience: find entries within a ring defined by a center point and

///|
/// explicit inner/outer radii. Also returns min/max/mean distance summary.
pub fn GeoDB::ring_query_summary(
  self : GeoDB,
  center : @types.GeoPoint,
  inner_km : Double,
  outer_km : Double,
) -> (Array[(@types.GeoEntry, Double)], Double, Double, Double) {
  let results = self.find_in_ring(center, inner_km, outer_km)
  let n = results.length()
  if n == 0 {
    return (results, 0.0, 0.0, 0.0)
  }
  let mut total = 0.0
  let mut min_d = results[0].1
  let mut max_d = results[0].1
  for p in results {
    total = total + p.1
    if p.1 < min_d {
      min_d = p.1
    }
    if p.1 > max_d {
      max_d = p.1
    }
  }
  (results, min_d, max_d, total / n.to_double())
}

// ---- Spatial join helpers ----

///|
/// Result type for a nearest-neighbor spatial join between two GeoEntry sets.
/// Each pair is (entry_from_db, nearest_external_entry, distance_km).
pub(all) struct SpatialJoinPair {
  left : @types.GeoEntry
  right : @types.GeoEntry
  distance_km : Double
} derive(Debug)

pub extend SpatialJoinPair with Debug::{ to_repr }

///| For every entry in this DB, find the closest entry from the provided

///|
/// `other` set. Returns an array of join pairs sorted by ascending distance.
/// This is the classic "for each point in A, find nearest point in B"
/// spatial join. `other` can be any array of GeoEntry (e.g. loaded from a
/// second DB, parsed from GeoJSON, etc.).
pub fn GeoDB::spatial_join_nearest(
  self : GeoDB,
  other : Array[@types.GeoEntry],
) -> Array[SpatialJoinPair] {
  let results : Array[SpatialJoinPair] = []
  let left_entries = self.all()
  if other.length() == 0 || left_entries.length() == 0 {
    return results
  }
  // Build a temporary R-tree over `other` for O(log m) KNN lookups.
  let temp = build_rtree_for(other)
  for a in left_entries {
    let knn = temp.nearest(a.location, 1)
    if knn.length() > 0 {
      let (rid, d) = knn[0]
      match temp.entries.get(rid) {
        Some(b) => results.push({ left: a, right: b, distance_km: d, })
        None => ()
      }
    }
  }
  results.sort_by(fn(a, b) {
    if a.distance_km < b.distance_km { -1 } else if a.distance_km > b.distance_km { 1 } else { 0 }
  })
  results
}

///| Helper: build a lightweight struct containing both an R-tree and an
///| id→entry map for a small external array of entries, so spatial_join_*
///| can do O(log m) queries against it.
fn build_rtree_for(entries : Array[@types.GeoEntry]) -> TempJoinIndex {
  let tree = @index.RTree::new()
  let map : @hashmap.HashMap[String, @types.GeoEntry] = @hashmap.HashMap([])
  for e in entries {
    tree.insert(e.id, e.location)
    map[e.id] = e
  }
  { rtree: tree, entries: map }
}

///| Lightweight (rtree + entries map) pair used for spatial_join_*.
priv struct TempJoinIndex {
  rtree : @index.RTree
  entries : @hashmap.HashMap[String, @types.GeoEntry]
}

fn TempJoinIndex::nearest(self : TempJoinIndex, point : @types.GeoPoint, k : Int) -> Array[(String, Double)] {
  self.rtree.nearest(point, k)
}

fn TempJoinIndex::search(self : TempJoinIndex, bbox : @types.BBox) -> Array[String] {
  self.rtree.search(bbox)
}

///|
/// Find all pairs (a from DB, b from `other`) whose distance is <= `max_km`.
/// Uses a temporary R-tree over `other` to prune candidates.
pub fn GeoDB::spatial_join_within(
  self : GeoDB,
  other : Array[@types.GeoEntry],
  max_km : Double,
) -> Array[SpatialJoinPair] {
  let results : Array[SpatialJoinPair] = []
  let left_entries = self.all()
  if other.length() == 0 || left_entries.length() == 0 {
    return results
  }
  let temp = build_rtree_for(other)
  for a in left_entries {
    // Build bbox around a to get candidates, then refine with haversine.
    let bbox = @geo.bbox_around(a.location, max_km)
    let cands = temp.search(bbox)
    for rid in cands {
      match temp.entries.get(rid) {
        Some(b) => {
          let d = @geo.haversine(a.location, b.location)
          if d <= max_km {
            results.push({ left: a, right: b, distance_km: d, })
          }
        }
        None => ()
      }
    }
  }
  results.sort_by(fn(a, b) {
    if a.distance_km < b.distance_km { -1 } else if a.distance_km > b.distance_km { 1 } else { 0 }
  })
  results
}

///|
/// For every entry in this DB, find up to `k` closest entries from `other`.
/// Uses a temporary R-tree over `other` for O(log m) per left entry.
pub fn GeoDB::spatial_join_knearest(
  self : GeoDB,
  other : Array[@types.GeoEntry],
  k : Int,
) -> Array[SpatialJoinPair] {
  let results : Array[SpatialJoinPair] = []
  let left_entries = self.all()
  if other.length() == 0 || k <= 0 || left_entries.length() == 0 {
    return results
  }
  let temp = build_rtree_for(other)
  let k_eff = if other.length() < k { other.length() } else { k }
  for a in left_entries {
    let knn = temp.nearest(a.location, k_eff)
    for (rid, d) in knn {
      match temp.entries.get(rid) {
        Some(b) => results.push({ left: a, right: b, distance_km: d, })
        None => ()
      }
    }
  }
  results
}

///| Compute the distance range (min/max/mean/median) of the k nearest

///| neighbors for a given entry. Returns None if the entry has fewer than

///|
/// k neighbors in the DB.
pub fn GeoDB::nearest_neighbors_range(
  self : GeoDB,
  id : String,
  k : Int,
) -> (Int, Double, Double, Double, Double)? {
  match self.get(id) {
    None => None
    Some(target) => {
      let n = self.index.size()
      if n < 2 {
        return None
      }
      // Use R-tree to get k+1 nearest (the +1 accounts for target itself).
      let take = if n - 1 < k { n - 1 } else { k }
      let raw = self.index.query_nearest(target.location, take + 1)
      let dists : Array[Double] = []
      for (e, d) in raw {
        if e.id != id {
          dists.push(d)
        }
      }
      if dists.length() == 0 {
        return None
      }
      // query_nearest returns ascending order, already sorted.
      let n_taken = dists.length()
      let mut total = 0.0
      for d in dists {
        total = total + d
      }
      let median = if n_taken % 2 == 1 {
        dists[n_taken / 2]
      } else {
        (dists[n_taken / 2 - 1] + dists[n_taken / 2]) / 2.0
      }
      Some((n_taken, dists[0], dists[n_taken - 1], total / n_taken.to_double(), median))
    }
  }
}

///|
/// Compute the Voronoi diagram of all entries in the DB.
/// Each cell is returned as a VoronoiCell (site + ordered polygon vertices).
/// Results are cached; the cache is invalidated on insert/remove.
pub fn GeoDB::voronoi(self : GeoDB) -> Array[@geo.VoronoiCell] {
  match self.cached_voronoi {
    Some(cells) => {
      self.voronoi_dirty = false
      cells
    }
    None => {
      let entries = self.all()
      if entries.length() == 0 {
        return []
      }
      let pts : Array[@types.GeoPoint] = []
      for e in entries {
        pts.push(e.location)
      }
      let bbox = self.compute_bbox()
      let cells = match bbox {
        None => []
        Some((b, _)) => @geo.voronoi_diagram(pts, b)
      }
      self.cached_voronoi = Some(cells)
      self.voronoi_dirty = false
      cells
    }
  }
}

///|
/// Compute the Voronoi cell for a specific entry, returned as an ordered
/// polygon (array of GeoPoints). Returns None if the entry is not found or
/// the DB has fewer than 2 entries. Uses a cached Voronoi diagram when
/// available.
pub fn GeoDB::voronoi_cell(
  self : GeoDB,
  id : String,
) -> Array[@types.GeoPoint]? {
  let entries = self.all()
  if entries.length() < 2 {
    return None
  }
  let target = match self.get(id) {
    None => return None
    Some(e) => e
  }
  let cells = self.voronoi()
  for c in cells {
    if c.site.lat == target.location.lat && c.site.lng == target.location.lng {
      return Some(c.polygon)
    }
  }
  None
}

///|
/// Find Voronoi neighbors of an entry: entries whose Voronoi cells share
/// an edge with the cell of `id`. Returns the neighbor ids. Uses a cached
/// Voronoi diagram when available.
pub fn GeoDB::voronoi_neighbors(self : GeoDB, id : String) -> Array[String]? {
  let entries = self.all()
  if entries.length() < 2 {
    return None
  }
  let target = match self.get(id) {
    None => return None
    Some(e) => e
  }
  let cells = self.voronoi()
  let target_poly = match find_voronoi_cell(cells, target.location) {
    None => return None
    Some(c) => c.polygon
  }
  if target_poly.length() < 3 {
    return Some([])
  }
  let neighbors : Array[String] = []
  let seen : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  for c in cells {
    if c.site.lat == target.location.lat && c.site.lng == target.location.lng {
      continue
    }
    if cells_share_edge(target_poly, c.polygon) {
      for e in entries {
        if e.location.lat == c.site.lat && e.location.lng == c.site.lng {
          if !seen.contains(e.id) {
            seen[e.id] = true
            neighbors.push(e.id)
          }
          break
        }
      }
    }
  }
  Some(neighbors)
}

///|
/// Find a Voronoi cell by site location.
fn find_voronoi_cell(
  cells : Array[@geo.VoronoiCell],
  loc : @types.GeoPoint,
) -> @geo.VoronoiCell? {
  for c in cells {
    if c.site.lat == loc.lat && c.site.lng == loc.lng {
      return Some(c)
    }
  }
  None
}

///|
/// Check whether two Voronoi polygons share an edge (they are neighbors).
/// Two polygons share an edge if they share at least two vertices (within
/// tolerance). Uses a hash map for O(|a| + |b|) performance.
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

// ---- Bounding box query + centroid + K-Means ----

///|
/// Convenience: find entries in a rectangular region defined by min/max lat/lng.
/// Delegates to the existing indexed find_in_bbox.
pub fn GeoDB::find_bbox(
  self : GeoDB,
  min_lat : Double,
  max_lat : Double,
  min_lng : Double,
  max_lng : Double,
) -> Array[@types.GeoEntry] {
  self.find_in_bbox({ min_lat, max_lat, min_lng, max_lng, })
}

///|
/// Compute the centroid (planar arithmetic mean lat/lng) of all entries.
/// Returns (0, 0) if the DB is empty.
pub fn GeoDB::centroid(self : GeoDB) -> @types.GeoPoint {
  let entries = self.all()
  if entries.length() == 0 {
    return @types.GeoPoint::make(0.0, 0.0)
  }
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  @geo.centroid(pts)
}

///|
/// Compute the true geographic mean center using a sphere-based
/// 3D-to-lat/lng projection, which is more accurate for global-scale data
/// than the simple arithmetic mean. Returns (0,0) for empty DB.
pub fn GeoDB::geographic_center(self : GeoDB) -> @types.GeoPoint {
  let entries = self.all()
  let n = entries.length()
  if n == 0 {
    return @types.GeoPoint::make(0.0, 0.0)
  }
  let mut sx = 0.0
  let mut sy = 0.0
  let mut sz = 0.0
  for e in entries {
    let lat_r = e.location.lat * 3.14159265358979323846 / 180.0
    let lng_r = e.location.lng * 3.14159265358979323846 / 180.0
    let clat = @math.cos(lat_r)
    sx = sx + clat * @math.cos(lng_r)
    sy = sy + clat * @math.sin(lng_r)
    sz = sz + @math.sin(lat_r)
  }
  let nf = n.to_double()
  let x = sx / nf
  let y = sy / nf
  let z = sz / nf
  let r = @geo.sqrt(x * x + y * y)
  let lng = @math.atan2(y, x) * 180.0 / 3.14159265358979323846
  let lat = @math.atan2(z, r) * 180.0 / 3.14159265358979323846
  @types.GeoPoint::make(lat, lng)
}

///|
/// Compute the centroid for a subset of entries matching a tag.
pub fn GeoDB::centroid_by_tag(self : GeoDB, tag : String) -> @types.GeoPoint {
  let mut sum_lat = 0.0
  let mut sum_lng = 0.0
  let mut count : Int = 0
  for e in self.all() {
    let mut has_tag = false
    for t in e.tags {
      if t == tag {
        has_tag = true
        break
      }
    }
    if has_tag {
      sum_lat = sum_lat + e.location.lat
      sum_lng = sum_lng + e.location.lng
      count = count + 1
    }
  }
  if count == 0 {
    return @types.GeoPoint::make(0.0, 0.0)
  }
  @types.GeoPoint::make(
    sum_lat / count.to_double(),
    sum_lng / count.to_double(),
  )
}

///|
/// Run K-Means clustering on the entries in this DB.
/// Returns k clusters; each cluster contains the member entries.
pub(all) struct DBKMeansCluster {
  id : Int
  center : @types.GeoPoint
  members : Array[@types.GeoEntry]
} derive(Debug)

pub extend DBKMeansCluster with Debug::{ to_repr }

///|
pub fn GeoDB::kmeans(
  self : GeoDB,
  k : Int,
  max_iter? : Int = 100,
) -> Array[DBKMeansCluster] {
  let entries = self.all()
  let n = entries.length()
  if n == 0 {
    return []
  }
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  let clusters = @geo.kmeans(pts, k, max_iter~)
  let result : Array[DBKMeansCluster] = []
  for cl in clusters {
    let members : Array[@types.GeoEntry] = []
    for idx in cl.members {
      members.push(entries[idx])
    }
    result.push({ id: cl.id, center: cl.center, members, })
  }
  result
}

///| Compute the elbow method: run K-Means for k = 1..max_k and return

///|
/// (k, inertia) pairs. The "elbow" in the plot suggests a good k.
pub fn GeoDB::kmeans_elbow(self : GeoDB, max_k : Int) -> Array[(Int, Double)] {
  let entries = self.all()
  if entries.length() == 0 {
    return []
  }
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  let results : Array[(Int, Double)] = []
  let mut k = 1
  let n = entries.length()
  let limit = if max_k > n { n } else { max_k }
  let mut prev_centers : Array[@types.GeoPoint] = []
  while k <= limit {
    let init = if k > 1 && prev_centers.length() > 0 {
      Some(prev_centers)
    } else {
      None
    }
    let clusters = @geo.kmeans(pts, k, init~)
    let inertia = @geo.kmeans_inertia(pts, clusters)
    results.push((k, inertia))
    let centers : Array[@types.GeoPoint] = []
    for c in clusters {
      centers.push(c.center)
    }
    prev_centers = centers
    k = k + 1
  }
  results
}

// ---- Moran's I spatial autocorrelation ----

///| Compute Moran's I for the DB's entry locations using the given

///| numeric attribute values (one per entry). The values array must be

///|
/// the same length as the number of entries.
/// Uses inverse-distance weighting (Haversine).
pub fn GeoDB::morans_i(
  self : GeoDB,
  values : Array[Double],
) -> @geo.MoranIResult? {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  @geo.morans_i(pts, values)
}

///| K-nearest-neighbor-weighted Moran's I.
/// Uses R-tree KNN lookups — true O(n·k·log n), much faster than the
/// O(n²) full-matrix version on large datasets. Weights are row-standardized
/// (1/k per neighbor) so the I value is directly comparable to `morans_i`.
pub fn GeoDB::morans_i_knn(
  self : GeoDB,
  values : Array[Double],
  k? : Int = 8,
) -> @geo.MoranIResult? {
  let entries = self.all()
  let n = entries.length()
  if n < 3 || values.length() != n { return None }
  let nf = n.to_double()
  let k_eff = if k < n - 1 { k } else { n - 1 }
  // Mean-center values.
  let mut sum_v = 0.0
  for v in values { sum_v = sum_v + v }
  let mean_v = sum_v / nf
  let z : Array[Double] = []
  for v in values { z.push(v - mean_v) }
  let mut denom = 0.0
  for zi in z { denom = denom + zi * zi }
  if denom == 0.0 { return None }
  // Directed kNN rows come from the shared lazy cache: same neighbor sets
  // and accumulation order as the previous per-call R-tree queries, so the
  // result is bit-identical while repeat calls skip the n KNN lookups.
  let knn_rows = directed_knn_list(self, entries, k)
  let w = 1.0 / k_eff.to_double()
  let mut num = 0.0
  let mut i = 0
  while i < n {
    let z_i = z[i]
    for j in knn_rows[i] {
      num = num + w * z_i * z[j]
    }
    i = i + 1
  }
  let index = num / denom
  let expected = -1.0 / (nf - 1.0)
  Some({ index, expected, n })
}

///| KNN Moran's I on latitude attribute. True O(n·k·log n).
pub fn GeoDB::morans_i_knn_on_lat(self : GeoDB, k? : Int = 8) -> @geo.MoranIResult? {
  let entries = self.all()
  let vals : Array[Double] = []
  for e in entries { vals.push(e.location.lat) }
  self.morans_i_knn(vals, k~)
}

///| Convenience: compute Moran's I where the attribute value is simply

///| the latitude of each entry. Tests whether entries with similar latitudes

///|
/// tend to cluster together spatially.
pub fn GeoDB::morans_i_on_lat(self : GeoDB) -> @geo.MoranIResult? {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  for e in entries {
    pts.push(e.location)
    vals.push(e.location.lat)
  }
  @geo.morans_i(pts, vals)
}

///|
/// Convenience: compute Moran's I where the attribute is longitude.
pub fn GeoDB::morans_i_on_lng(self : GeoDB) -> @geo.MoranIResult? {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  for e in entries {
    pts.push(e.location)
    vals.push(e.location.lng)
  }
  @geo.morans_i(pts, vals)
}

// ---- Spatial autocorrelation with significance / hotspot analysis ----

///|
fn array_contains_int(arr : Array[Int], target : Int) -> Bool {
  for v in arr {
    if v == target {
      return true
    }
  }
  false
}

///|
/// Raw directed kNN adjacency: `rows[i]` holds up to k neighbor indices
/// (self excluded, R-tree order). Shared by the symmetric mutual-kNN
/// weights (symmetrised from these rows) and the directed 1/k Moran's I.
/// Lazily built and invalidated on insert/remove/clear like
/// cached_knn_weights, so repeated calls skip the n R-tree KNN queries.
fn directed_knn_list(
  db : GeoDB,
  entries : Array[@types.GeoEntry],
  k : Int,
) -> Array[Array[Int]] {
  let n = entries.length()
  if n == 0 {
    return []
  }
  match db.index.cached_directed_knn {
    Some(rows) =>
      if db.index.cached_directed_knn_k == k {
        return rows
      }
    None => ()
  }
  let id_to_idx : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  let mut i = 0
  while i < n {
    id_to_idx[entries[i].id] = i
    i = i + 1
  }
  let k_eff = if k < n - 1 { k } else { n - 1 }
  let rows : Array[Array[Int]] = []
  i = 0
  while i < n {
    let list : Array[Int] = []
    if k_eff > 0 {
      // ask k+1 so we can skip self (always returned first).
      let neighbors = db.index.query_nearest(entries[i].location, k_eff + 1)
      for pair in neighbors {
        if list.length() >= k_eff {
          break
        }
        if pair.0.id == entries[i].id {
          continue
        }
        match id_to_idx.get(pair.0.id) {
          Some(j) => list.push(j)
          None => ()
        }
      }
    }
    rows.push(list)
    i = i + 1
  }
  db.index.cached_directed_knn_k = k
  db.index.cached_directed_knn = Some(rows)
  rows
}

///|
/// Build mutual-kNN binary weights (`Array[Array[Int]]`) using the R-tree
/// index instead of the geo package's O(n²) brute-force version. Each row
/// starts with its own index, followed by the sorted symmetric neighbours.
fn build_knn_weights(
  db : GeoDB,
  entries : Array[@types.GeoEntry],
  k : Int,
) -> Array[Array[Int]] {
  let n = entries.length()
  if n == 0 {
    return []
  }
  match db.index.cached_knn_weights {
    Some(weights) =>
      if db.index.cached_knn_k == k {
        return weights
      }
    None => ()
  }
  let knn = directed_knn_list(db, entries, k)
  // Symmetrise: w_ij = 1 iff j in knn[i] OR i in knn[j].
  let rows : Array[Array[Int]] = []
  let mut r = 0
  while r < n {
    rows.push([])
    r = r + 1
  }
  let mut i = 0
  while i < n {
    for j in knn[i] {
      if !array_contains_int(rows[i], j) {
        rows[i].push(j)
      }
      if !array_contains_int(rows[j], i) {
        rows[j].push(i)
      }
    }
    i = i + 1
  }
  let weights : Array[Array[Int]] = []
  i = 0
  while i < n {
    let extra = rows[i]
    extra.sort()
    let row : Array[Int] = [i]
    for j in extra {
      row.push(j)
    }
    weights.push(row)
    i = i + 1
  }
  db.index.cached_knn_k = k
  db.index.cached_knn_weights = Some(weights)
  weights
}

///| Enhanced global Moran's I with z-score and two-sided p-value, using

///| mutual-kNN binary weights. `values` must have one entry per record

///| (same order as `all()`). Returns None for fewer than 4 entries or

///|
/// zero-variance values.
pub fn GeoDB::morans_i_test(
  self : GeoDB,
  values : Array[Double],
  k? : Int = 5,
) -> @geo.MoranResult? {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  let weights = build_knn_weights(self, entries, k)
  @geo.morans_i_test(pts, values, weights)
}

///| Getis-Ord Gi* hot/cold spot detection over all entries, using

///| mutual-kNN binary weights. `values` must have one entry per record.

///|
/// `threshold` is the |z| cut-off (default 1.96 ≈ 95% confidence).
pub fn GeoDB::getis_ord(
  self : GeoDB,
  values : Array[Double],
  k? : Int = 5,
  threshold? : Double = 1.96,
) -> Array[@geo.GetisResult] {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  let weights = build_knn_weights(self, entries, k)
  @geo.getis_ord_gi_star(pts, values, weights, threshold~)
}

///| Local Moran's I (LISA) cluster typing over all entries, using

///|
/// mutual-kNN binary weights. `values` must have one entry per record.
pub fn GeoDB::lisa(
  self : GeoDB,
  values : Array[Double],
  k? : Int = 5,
  threshold? : Double = 1.96,
) -> Array[@geo.LocalMoranResult] {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  let weights = build_knn_weights(self, entries, k)
  @geo.local_morans(pts, values, weights, threshold~)
}

// ---- Standard Deviation Ellipse ----

///|
/// Compute the Standard Deviation Ellipse for all entries in the DB.
pub fn GeoDB::std_dev_ellipse(self : GeoDB) -> @geo.StdDevEllipse? {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  @geo.std_dev_ellipse(pts)
}

// ---- Delaunay triangulation ----

///|
/// Compute the Delaunay triangulation of all entry locations.
/// Each triangle is returned as three indices into the `all()` array.
pub fn GeoDB::delaunay(self : GeoDB) -> Array[@geo.DelaunayTriangle] {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  @geo.delaunay_triangulation(pts)
}

///|
/// Compute all Delaunay edges (unique, sorted) for the entry locations.
pub fn GeoDB::delaunay_edges(self : GeoDB) -> Array[@geo.DelaunayEdge] {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  @geo.delaunay_edges(pts)
}

// ---- TSP nearest-neighbor heuristic ----

///|
/// A route stop in a TSP solution.
pub(all) struct RouteStop {
  entry : @types.GeoEntry
  cum_distance_km : Double // cumulative distance from start to this stop
} derive(Debug)

pub extend RouteStop with Debug::{ to_repr }

///| Solve a small TSP using the greedy nearest-neighbor heuristic,

///| starting from the entry with id `start_id`. Returns the ordered

///| route plus the total travel distance. The route does NOT return

///|
/// to the start (open tour).
///
/// Returns None if the start id is not found or the DB is empty.
pub fn GeoDB::tsp_nearest(
  self : GeoDB,
  start_id : String,
) -> (Array[RouteStop], Double)? {
  let entries = self.all()
  let n = entries.length()
  if n == 0 {
    return None
  }
  // Find start.
  let start_idx = find_entry_idx(entries, start_id)
  match start_idx {
    None => None
    Some(si) => {
      // Build id → index map for O(1) lookups from R-tree results.
      let id_to_idx : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
      let mut ii = 0
      while ii < n {
        id_to_idx[entries[ii].id] = ii
        ii = ii + 1
      }
      // Track visited.
      let visited : Array[Bool] = []
      let mut vi = 0
      while vi < n {
        visited.push(false)
        vi = vi + 1
      }
      visited[si] = true
      let route : Array[RouteStop] = []
      route.push({ entry: entries[si], cum_distance_km: 0.0, })
      let mut prev_idx = si
      let mut total_dist = 0.0
      let mut step = 1
      while step < n {
        // Ask R-tree for the next 16 nearest neighbors. If some are already
        // visited, skip them. If all visited, ask for more (up to 3 rounds).
        let mut k = 16
        let mut chosen = -1
        let mut chosen_d = 0.0
        let mut rounds = 0
        while chosen < 0 && rounds < 4 {
          let raw = self.index.query_nearest(entries[prev_idx].location, k)
          for (e, d) in raw {
            match id_to_idx.get(e.id) {
              None => ()
              Some(idx) =>
                if !visited[idx] {
                  chosen = idx
                  chosen_d = d
                  break
                }
            }
          }
          k = k * 2
          rounds = rounds + 1
        }
        if chosen < 0 {
          break  // R-tree couldn't find any unvisited (shouldn't happen)
        }
        visited[chosen] = true
        total_dist = total_dist + chosen_d
        route.push({ entry: entries[chosen], cum_distance_km: total_dist, })
        prev_idx = chosen
        step = step + 1
      }
      Some((route, total_dist))
    }
  }
}

///|
/// Helper: find an entry's index by id.
fn find_entry_idx(entries : Array[@types.GeoEntry], id : String) -> Int? {
  let mut i = 0
  while i < entries.length() {
    if entries[i].id == id {
      return Some(i)
    }
    i = i + 1
  }
  None
}

// ---- 2-opt TSP improvement ----

///|
/// 2-opt improvement loop over a route expressed as identity indices into
/// `lat_of`/`lng_of`/`mat`. `mat` holds the symmetric distance matrix when
/// `use_matrix` is true (unused otherwise); `edge[k]` caches the length of
/// the edge between route positions k and k+1. Coordinates and the matrix
/// are indexed by identity and never move, so swaps only permute `route`
/// and the matrix stays valid for the whole run. All arrays here are
/// FixedArray (unboxed native memory): boxed Array reads would dominate the
/// hot O(n²) sweep. The matrix/haversine choice is a predictable branch
/// instead of a runtime-selected closure: MoonBit cannot inline a closure
/// picked by an if-else binding, and the resulting indirect calls also
/// dominate the sweep.
fn tsp_2opt_improve(
  route : FixedArray[Int],
  lat_of : FixedArray[Double],
  lng_of : FixedArray[Double],
  edge : FixedArray[Double],
  mat : FixedArray[Double],
  n : Int,
  use_matrix : Bool,
  max_iterations : Int,
  mat_dim : Int,
) -> Unit {
  // Don't-look bits (Bentley): a position whose full sweep found no
  // improvement is skipped until a swap changes one of its adjacent edges
  // again (swaps wake positions i..j+1). Because a one-directional sweep
  // can miss a candidate whose far endpoint's edge changed, one forced
  // full sweep after the first unproductive round confirms convergence to
  // a true 2-opt local optimum.
  let dont_look : FixedArray[Bool] = FixedArray::make(n, false)
  let mut t = 0
  let mut improved = true
  let mut confirming = false
  while improved && t < max_iterations {
    improved = false
    t = t + 1
    let mut i = 0
    while i < n - 2 {
      if !dont_look[i] {
        let ri = route[i]
        let ri1 = route[i + 1]
        let mut improved_i = false
        let mut j = i + 2
        while j < n - 1 {
          // Try reversing route[i+1 .. j]: replace edges (i,i+1) and (j,j+1)
          // with (i,j) and (i+1,j+1).
          let rj = route[j]
          let rj1 = route[j + 1]
          let d_before = edge[i] + edge[j]
          let d_after = if use_matrix {
            mat[ri * mat_dim + rj] + mat[ri1 * mat_dim + rj1]
          } else {
            @geo.haversine(
              @types.GeoPoint::make(lat_of[ri], lng_of[ri]),
              @types.GeoPoint::make(lat_of[rj], lng_of[rj]),
            ) +
            @geo.haversine(
              @types.GeoPoint::make(lat_of[ri1], lng_of[ri1]),
              @types.GeoPoint::make(lat_of[rj1], lng_of[rj1]),
            )
          }
          if d_after < d_before - 0.000001 {
            // Reverse the sub-path (identities only; coordinates and matrix
            // are indexed by identity and never move).
            let mut lo = i + 1
            let mut hi = j
            while lo < hi {
              let tmp = route[lo]
              route[lo] = route[hi]
              route[hi] = tmp
              lo = lo + 1
              hi = hi - 1
            }
            // Inner edge lengths are permuted (reversed), not changed:
            // new_edge[i+1+j-k] = old_edge[k] for k in [i+1, j-1].
            let mut elo = i + 1
            let mut ehi = j - 1
            while elo < ehi {
              let te = edge[elo]
              edge[elo] = edge[ehi]
              edge[ehi] = te
              elo = elo + 1
              ehi = ehi - 1
            }
            // Patch the two boundary edges.
            let ri2 = route[i]
            let ri12 = route[i + 1]
            let rj2 = route[j]
            let rj12 = route[j + 1]
            if use_matrix {
              edge[i] = mat[ri2 * mat_dim + ri12]
              edge[j] = mat[rj2 * mat_dim + rj12]
            } else {
              edge[i] = @geo.haversine(
                @types.GeoPoint::make(lat_of[ri2], lng_of[ri2]),
                @types.GeoPoint::make(lat_of[ri12], lng_of[ri12]),
              )
              edge[j] = @geo.haversine(
                @types.GeoPoint::make(lat_of[rj2], lng_of[rj2]),
                @types.GeoPoint::make(lat_of[rj12], lng_of[rj12]),
              )
            }
            // Wake every position whose adjacent edges changed.
            let mut w = i
            while w <= j + 1 {
              dont_look[w] = false
              w = w + 1
            }
            improved_i = true
            improved = true
          }
          j = j + 1
        }
        if !improved_i {
          dont_look[i] = true
        }
      }
      i = i + 1
    }
    if improved {
      confirming = false
    } else if !confirming {
      // First unproductive round: clear all bits and re-sweep everything
      // once to confirm convergence (catches long-range candidates that
      // the one-directional sweep may have skipped).
      let mut k = 0
      while k < n {
        dont_look[k] = false
        k = k + 1
      }
      confirming = true
      improved = true
    }
    // confirming && !improved: the forced sweep found nothing -> loop ends.
  }
}

///|
/// Lazy symmetric haversine distance matrix over all entries, indexed by
/// all()-order identity together with the matching coordinate arrays.
/// Built once per DB version and invalidated on insert/remove/clear like
/// the other index caches, so repeated tsp_2opt calls (any start id) skip
/// the O(n²) construction. Only built for n <= 1500 (memory ~8 MB at
/// n=1000); larger DBs return None and callers fall back to on-the-fly
/// haversine.
fn tsp_matrix_cache(
  db : GeoDB,
  entries : Array[@types.GeoEntry],
) -> (FixedArray[Double], FixedArray[Double], FixedArray[Double])? {
  let n = entries.length()
  if n == 0 || n > 1500 {
    return None
  }
  match db.index.cached_dist_matrix {
    Some(c) => return Some(c)
    None => ()
  }
  let lat_of : FixedArray[Double] = FixedArray::make(n, 0.0)
  let lng_of : FixedArray[Double] = FixedArray::make(n, 0.0)
  let mut i = 0
  while i < n {
    lat_of[i] = entries[i].location.lat
    lng_of[i] = entries[i].location.lng
    i = i + 1
  }
  // FixedArray: unboxed native memory; Array[Double] would box every
  // element and turn each write into a heap allocation.
  let mat : FixedArray[Double] = FixedArray::make(n * n, 0.0)
  i = 0
  while i < n {
    let a = @types.GeoPoint::make(lat_of[i], lng_of[i])
    let mut j = i + 1
    while j < n {
      let d = @geo.haversine(a, @types.GeoPoint::make(lat_of[j], lng_of[j]))
      mat[i * n + j] = d
      mat[j * n + i] = d
      j = j + 1
    }
    i = i + 1
  }
  let c = (mat, lat_of, lng_of)
  db.index.cached_dist_matrix = Some(c)
  Some(c)
}

///|
/// Improve a nearest-neighbor TSP route using the 2-opt local search heuristic.
/// Iteratively swaps two edges (reverses a sub-path) whenever it reduces
/// total distance. Returns the improved (route, total_distance).
///
/// `max_iterations` caps the outer loop (default 200) to guarantee termination.
pub fn GeoDB::tsp_2opt(
  self : GeoDB,
  start_id : String,
  max_iterations? : Int = 200,
) -> (Array[RouteStop], Double)? {
  match self.tsp_nearest(start_id) {
    None => None
    Some((route, total)) => {
      let entries = self.all()
      let n = route.length()
      if n < 4 {
        return Some((route, total))
      }
      let all_n = entries.length()
      // Identity = all()-order index: coordinates and the distance matrix
      // are indexed by it and never move, so the matrix cache stays valid
      // across calls (any start id) until a write. Swapping only permutes
      // route. FixedArray everywhere: boxed Array reads would dominate
      // the hot O(n²) sweep.
      let id_to_idx : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
      let mut ii = 0
      while ii < all_n {
        id_to_idx[entries[ii].id] = ii
        ii = ii + 1
      }
      let route_idx : FixedArray[Int] = FixedArray::make(n, 0)
      let mut k0 = 0
      for stop in route {
        match id_to_idx.get(stop.entry.id) {
          Some(idx) => {
            route_idx[k0] = idx
            k0 = k0 + 1
          }
          None => ()
        }
      }
      let use_matrix = all_n <= 1500
      let mat_dim = all_n
      let (mat, lat_of, lng_of) = if use_matrix {
        match tsp_matrix_cache(self, entries) {
          Some(c) => c
          // Unreachable: the cache covers n <= 1500.
          None => (
            FixedArray::make(1, 0.0),
            FixedArray::make(all_n, 0.0),
            FixedArray::make(all_n, 0.0),
          )
        }
      } else {
        // Large DB: on-the-fly coordinates in identity order, no matrix.
        let la : FixedArray[Double] = FixedArray::make(all_n, 0.0)
        let ln : FixedArray[Double] = FixedArray::make(all_n, 0.0)
        let mut t = 0
        while t < all_n {
          la[t] = entries[t].location.lat
          ln[t] = entries[t].location.lng
          t = t + 1
        }
        (FixedArray::make(1, 0.0), la, ln)
      }
      // Adjacent edge lengths, refreshed once per round (O(n) distances,
      // negligible vs the O(n²) sweep) and patched on every accepted swap.
      // This makes d_before a pure array read: 2 fewer distance calls per
      // candidate (half the trig work) compared to recomputing 4 distances.
      let edge : FixedArray[Double] = FixedArray::make(n - 1, 0.0)
      let mut e = 0
      while e < n - 1 {
        edge[e] = if use_matrix {
          mat[route_idx[e] * mat_dim + route_idx[e + 1]]
        } else {
          @geo.haversine(
            @types.GeoPoint::make(lat_of[route_idx[e]], lng_of[route_idx[e]]),
            @types.GeoPoint::make(
              lat_of[route_idx[e + 1]],
              lng_of[route_idx[e + 1]],
            ),
          )
        }
        e = e + 1
      }
      tsp_2opt_improve(
        route_idx,
        lat_of,
        lng_of,
        edge,
        mat,
        n,
        use_matrix,
        max_iterations,
        mat_dim,
      )
      // Rebuild route + compute cumulative distance (entries by identity).
      let new_route : Array[RouteStop] = []
      let mut cum = 0.0
      new_route.push({
        entry: entries[route_idx[0]],
        cum_distance_km: 0.0,
      })
      let mut k = 1
      while k < n {
        let prev = entries[route_idx[k - 1]]
        let cur = entries[route_idx[k]]
        let d = @geo.haversine(prev.location, cur.location)
        cum = cum + d
        new_route.push({ entry: cur, cum_distance_km: cum })
        k = k + 1
      }
      Some((new_route, cum))
    }
  }
}

// ---- IDW spatial interpolation ----

///|
/// Predict an attribute value at a query location using Inverse Distance
/// Weighting over all DB entries. `value_fn` extracts the numeric attribute
/// from each entry (e.g. latitude, a tag-derived value, etc.).
///
/// Returns None if the DB is empty.
pub fn GeoDB::idw_predict(
  self : GeoDB,
  query : @types.GeoPoint,
  value_fn : (@types.GeoEntry) -> Double,
  power? : Double = 2.0,
) -> Double? {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  for e in entries {
    pts.push(e.location)
    vals.push(value_fn(e))
  }
  @geo.idw_interpolate(pts, vals, query, power~)
}

///|
/// IDW restricted to k nearest neighbors (faster for large DBs).
pub fn GeoDB::idw_predict_knn(
  self : GeoDB,
  query : @types.GeoPoint,
  k : Int,
  value_fn : (@types.GeoEntry) -> Double,
  power? : Double = 2.0,
) -> Double? {
  if k <= 0 {
    return None
  }
  let neighbors = self.index.query_nearest(query, k)
  if neighbors.length() == 0 {
    return None
  }
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  for pair in neighbors {
    pts.push(pair.0.location)
    vals.push(value_fn(pair.0))
  }
  @geo.idw_interpolate_knn(pts, vals, query, k, power~)
}

// ---- Concave hull ----

///|
/// Compute the concave hull (alpha-shape) of all entry locations.
pub fn GeoDB::concave_hull(self : GeoDB, alpha : Double) -> Array[@types.GeoPoint] {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  @geo.concave_hull(pts, alpha)
}
// ---- Kriging interpolation ----

///|
/// 普通克里金插值（Ordinary Kriging）。
///
/// 在查询点 q 处，用所有已知点和变异函数模型进行插值。
/// 返回预测值，或 None（当无法计算时）。
/// - `value_fn`: 从 GeoEntry 中提取待插值的数值
/// - `variogram`: 拟合的变异函数模型
pub fn GeoDB::kriging_predict(
  self : GeoDB,
  query : @types.GeoPoint,
  value_fn : (@types.GeoEntry) -> Double,
  variogram : @geo.FittedVariogram,
) -> Double? {
  let entries = self.all()
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  for e in entries {
    pts.push(e.location)
    vals.push(value_fn(e))
  }
  @geo.ordinary_kriging(pts, vals, query, variogram)
}

///|
/// 普通克里金插值（k 近邻版本）。
///
/// 仅使用距离查询点最近的 k 个已知点进行插值。
/// 适合大数据集，避免构建大型方程组。
/// - `value_fn`: 从 GeoEntry 中提取待插值的数值
/// - `variogram`: 拟合的变异函数模型
/// - `k`: 近邻数量（默认 12）
pub fn GeoDB::kriging_predict_knn(
  self : GeoDB,
  query : @types.GeoPoint,
  value_fn : (@types.GeoEntry) -> Double,
  variogram : @geo.FittedVariogram,
  k? : Int = 12,
) -> Double? {
  if k <= 0 {
    return None
  }
  let neighbors = self.index.query_nearest(query, k)
  if neighbors.length() == 0 {
    return None
  }
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  for pair in neighbors {
    pts.push(pair.0.location)
    vals.push(value_fn(pair.0))
  }
  @geo.ordinary_kriging_knn(pts, vals, query, variogram, k~)
}
