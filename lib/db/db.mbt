// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

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
  mut created_at : Int64
  mut updated_at : Int64
  mut auto_save : Bool
} derive(Debug)

///| Create an empty in-memory database (no auto-persistence).
pub fn GeoDB::in_memory() -> GeoDB {
  {
    path: None,
    index: @index.Index::new(),
    next_seq: @ref.Ref(0),
    created_at: 0L,
    updated_at: 0L,
    auto_save: false,
  }
}

///| Open (or create) a database backed by a file at `path`. If the file
/// exists and contains valid binary data, its entries and metadata are loaded.
/// If `auto_save` is true, every insert/remove automatically saves to disk.
pub fn GeoDB::open(path : String, auto_save~ : Bool = false) -> GeoDB {
  let now = @persist.file_mtime(path)
  let db = {
    path: Some(path),
    index: @index.Index::new(),
    next_seq: @ref.Ref(0),
    created_at: if now > 0 { now } else { 0L },
    updated_at: now,
    auto_save,
  }
  match @persist.load_entries_from_snapshot(path) {
    Ok(entries) => {
      for e in entries {
        db.index.insert(e)
      }
      // Restore metadata timestamps from snapshot.
      match @persist.load_snapshot(path) {
        Ok((_, created_at, updated_at)) => {
          db.created_at = created_at
          db.updated_at = updated_at
        }
        Err(_) => ()
      }
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

///| Insert (or replace) an entry. Triggers auto-save if enabled.
pub fn GeoDB::insert(self : GeoDB, entry : @types.GeoEntry) -> Unit {
  self.index.insert(entry)
  if self.auto_save {
    ignore(self.save())
  }
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
/// Triggers auto-save if enabled.
pub fn GeoDB::remove(self : GeoDB, id : String) -> @types.GeoEntry? {
  let result = self.index.remove(id)
  if result != None && self.auto_save {
    ignore(self.save())
  }
  result
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

///| Serialize the entire DB to binary Bytes.
pub fn GeoDB::to_bytes(self : GeoDB) -> Bytes {
  @persist.binary_encode_snapshot(self.all(), self.created_at, self.updated_at)
}

///| Replace all entries with those decoded from binary Bytes.
pub fn GeoDB::from_bytes(self : GeoDB, data : Bytes) -> Result[Unit, String] {
  match @persist.binary_decode_snapshot(data) {
    Err(msg) => Err(msg)
    Ok((entries, created_at, updated_at)) => {
      for e in self.all() {
        ignore(self.index.remove(e.id))
      }
      for e in entries {
        self.index.insert(e)
      }
      self.created_at = created_at
      self.updated_at = updated_at
      Ok(())
    }
  }
}

///| Save the DB to its backing file using atomic binary write with metadata.
pub fn GeoDB::save(self : GeoDB) -> Result[Unit, String] {
  match self.path {
    None => Err("no backing path; use save_to(path) instead")
    Some(p) => {
      let now = @persist.file_mtime(p)
      self.updated_at = if now > 0 { now } else { 0L }
      @persist.atomic_save_entries(p, self.all(), self.created_at, self.updated_at)
    }
  }
}

///| Save the DB to a specific file path (also updates the backing path).
pub fn GeoDB::save_to(self : GeoDB, path : String) -> Result[Unit, String] {
  let now = @persist.file_mtime(path)
  self.updated_at = if now > 0 { now } else { 0L }
  match self.path {
    None => self.path = Some(path)
    Some(_) => ()
  }
  @persist.atomic_save_entries(path, self.all(), self.created_at, self.updated_at)
}

///| Create a backup of the current database file.
pub fn GeoDB::backup(self : GeoDB) -> Result[String, String] {
  match self.path {
    None => Err("no backing path to backup")
    Some(p) => @persist.create_backup(p)
  }
}

///| Restore the database from its .bak backup file.
pub fn GeoDB::restore(self : GeoDB) -> Result[Unit, String] {
  match self.path {
    None => Err("no backing path to restore")
    Some(p) => {
      match @persist.restore_from_backup(p) {
        Err(e) => Err(e)
        Ok(_) => {
          match @persist.load_snapshot(p) {
            Err(e) => Err("reload after restore failed: \{e}")
            Ok((entries, created_at, updated_at)) => {
              for e in self.all() {
                ignore(self.index.remove(e.id))
              }
              for e in entries {
                self.index.insert(e)
              }
              self.created_at = created_at
              self.updated_at = updated_at
              Ok(())
            }
          }
        }
      }
    }
  }
}

///| Check database integrity. Returns the metadata on success.
pub fn GeoDB::check(self : GeoDB) -> Result[@persist.DBMeta, String] {
  match self.path {
    None => Err("no backing path to check")
    Some(p) => @persist.check_integrity(p)
  }
}

///| Return database metadata (version, timestamps, entry count).
pub fn GeoDB::metadata(self : GeoDB) -> @persist.DBMeta {
  {
    version: @persist.db_version,
    created_at: self.created_at,
    updated_at: self.updated_at,
    entry_count: self.index.size(),
  }
}

///| Toggle auto-save on/off. Returns the new setting.
pub fn GeoDB::set_auto_save(self : GeoDB, enabled : Bool) -> Bool {
  self.auto_save = enabled
  self.auto_save
}

///| Iterate over all entries.
pub fn GeoDB::iter(self : GeoDB) -> Iter[@types.GeoEntry] {
  self.index.iter()
}

// ---- Tag-based queries ----

///| Find entries that have a specific tag (case-insensitive).
pub fn GeoDB::find_by_tag(
  self : GeoDB,
  tag : String
) -> Array[@types.GeoEntry] {
  self.index.find_by_tag(tag)
}

///| Find entries that have ALL the specified tags (AND logic).
pub fn GeoDB::find_by_all_tags(
  self : GeoDB,
  tags : Array[String]
) -> Array[@types.GeoEntry] {
  self.index.find_by_all_tags(tags)
}

///| Find entries that have ANY of the specified tags (OR logic).
pub fn GeoDB::find_by_any_tags(
  self : GeoDB,
  tags : Array[String]
) -> Array[@types.GeoEntry] {
  self.index.find_by_any_tags(tags)
}

///| List all unique tags in the database.
pub fn GeoDB::list_tags(self : GeoDB) -> Array[String] {
  self.index.list_tags()
}

// ---- Address-based queries ----

///| Find entries by province (case-insensitive).
pub fn GeoDB::find_by_province(
  self : GeoDB,
  province : String
) -> Array[@types.GeoEntry] {
  self.index.find_by_province(province)
}

///| Find entries by city (case-insensitive).
pub fn GeoDB::find_by_city(
  self : GeoDB,
  city : String
) -> Array[@types.GeoEntry] {
  self.index.find_by_city(city)
}

///| Find entries by district (case-insensitive).
pub fn GeoDB::find_by_district(
  self : GeoDB,
  district : String
) -> Array[@types.GeoEntry] {
  self.index.find_by_district(district)
}

///| Find entries by province AND city (case-insensitive).
pub fn GeoDB::find_by_province_city(
  self : GeoDB,
  province : String,
  city : String
) -> Array[@types.GeoEntry] {
  self.index.find_by_province_city(province, city)
}

///| List all unique provinces in the database.
pub fn GeoDB::list_provinces(self : GeoDB) -> Array[String] {
  self.index.list_provinces()
}

///| List all unique cities in the database.
pub fn GeoDB::list_cities(self : GeoDB) -> Array[String] {
  self.index.list_cities()
}

///| List all unique districts in the database.
pub fn GeoDB::list_districts(self : GeoDB) -> Array[String] {
  self.index.list_districts()
}

// ---- Geographic statistics ----

///| Compute the geographic center (average lat/lng) of all entries.
/// Returns (center_point, entry_count) or None if DB is empty.
pub fn GeoDB::compute_center(self : GeoDB) -> (@types.GeoPoint, Int)? {
  let entries = self.all()
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

///| Compute the total bounding box of all entries.
/// Returns (bbox, entry_count) or None if DB is empty.
pub fn GeoDB::compute_bbox(self : GeoDB) -> (@types.BBox, Int)? {
  let entries = self.all()
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
  Some((
    { min_lat, max_lat, min_lng, max_lng },
    entries.length()
  ))
}

///| Compute the great-circle distance between the two farthest entries.
/// Returns (point_a, point_b, distance_km) or None if DB has < 2 entries.
pub fn GeoDB::compute_max_distance(
  self : GeoDB
) -> (@types.GeoPoint, @types.GeoPoint, Double)? {
  let entries = self.all()
  if entries.length() < 2 {
    return None
  }
  let mut max_d = 0.0
  let mut p1 = entries[0].location
  let mut p2 = entries[1].location
  for i in 0..<entries.length() {
    for j in (i + 1)..<entries.length() {
      let d = @geo.haversine(entries[i].location, entries[j].location)
      if d > max_d {
        max_d = d
        p1 = entries[i].location
        p2 = entries[j].location
      }
    }
  }
  Some((p1, p2, max_d))
}

///| Compute region distribution: count entries per province.
/// Returns array of (province, count) sorted by count descending.
pub fn GeoDB::province_distribution(
  self : GeoDB
) -> Array[(String, Int)] {
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
  result.sort_by(fn(a, b) { if a.1 > b.1 { -1 } else if a.1 < b.1 { 1 } else { 0 } })
  result
}

///| Compute city distribution within a province.
/// Returns array of (city, count) sorted by count descending.
pub fn GeoDB::city_distribution(
  self : GeoDB,
  province~ : String = ""
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
  result.sort_by(fn(a, b) { if a.1 > b.1 { -1 } else if a.1 < b.1 { 1 } else { 0 } })
  result
}

///| Compute tag distribution: count entries per tag.
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
  result.sort_by(fn(a, b) { if a.1 > b.1 { -1 } else if a.1 < b.1 { 1 } else { 0 } })
  result
}

///| Generate a human-readable geographic summary of the database.
pub fn GeoDB::summary(self : GeoDB) -> String {
  let entries = self.all()
  let lines : Array[String] = []
  lines.push("=== Geographic Database Summary ===")
  lines.push("Total entries: " + entries.length().to_string())

  match self.compute_center() {
    None => lines.push("Center: N/A (empty)")
    Some((center, _)) =>
      lines.push("Center: (" + center.lat.to_string() + ", " + center.lng.to_string() + ")")
  }

  match self.compute_bbox() {
    None => lines.push("Bounding box: N/A (empty)")
    Some((bbox, _)) => {
      lines.push("Bounding box:")
      lines.push(
        "  SW: (" + bbox.min_lat.to_string() + ", " + bbox.min_lng.to_string() + ")"
      )
      lines.push(
        "  NE: (" + bbox.max_lat.to_string() + ", " + bbox.max_lng.to_string() + ")"
      )
    }
  }

  match self.compute_max_distance() {
    None => lines.push("Max distance: N/A (< 2 entries)")
    Some((_, _, d)) => lines.push("Max distance: " + d.to_string() + " km")
  }

  let provinces = self.list_provinces()
  if provinces.length() > 0 {
    lines.push("Provinces (" + provinces.length().to_string() + "):")
    let prov_dist = self.province_distribution()
    for pair in prov_dist {
      lines.push("  " + pair.0 + ": " + pair.1.to_string() + " entries")
    }
  }

  let tags = self.list_tags()
  if tags.length() > 0 {
    lines.push("Tags (" + tags.length().to_string() + "):")
    let tag_dist = self.tag_distribution()
    for pair in tag_dist {
      lines.push("  " + pair.0 + ": " + pair.1.to_string() + " entries")
    }
  }

  lines.join("\n")
}

// ---- Geofence / advanced query APIs ----

///| Check whether a point lies inside the combined bounding box of all entries.
pub fn GeoDB::contains_point(self : GeoDB, point : @types.GeoPoint) -> Bool {
  self.index.contains_point(point)
}

///| Find entries whose distance to a reference point is within `max_km`.
pub fn GeoDB::find_within_distance(
  self : GeoDB,
  point : @types.GeoPoint,
  max_km : Double
) -> Array[(@types.GeoEntry, Double)] {
  self.index.find_within_distance(point, max_km)
}

///| Find all entries sorted by distance to a reference point.
pub fn GeoDB::find_sorted_by_distance(
  self : GeoDB,
  point : @types.GeoPoint
) -> Array[(@types.GeoEntry, Double)] {
  self.index.find_sorted_by_distance(point)
}

///| Update the location of an existing entry.
pub fn GeoDB::update_location(
  self : GeoDB,
  id : String,
  new_location : @types.GeoPoint
) -> Bool {
  let ok = self.index.update_location(id, new_location)
  if ok && self.auto_save {
    ignore(self.save())
  }
  ok
}

///| Update the name of an existing entry.
pub fn GeoDB::update_name(
  self : GeoDB,
  id : String,
  new_name : String
) -> Bool {
  let ok = self.index.update_name(id, new_name)
  if ok && self.auto_save {
    ignore(self.save())
  }
  ok
}

// ---- Tag management ----

///| Add a tag to an existing entry. Returns true if the entry was found
///| and the tag was not already present.
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
        ignore(self.save())
      }
      true
    }
  }
}

///| Remove a tag from an existing entry. Returns true if the entry was
///| found and the tag was present.
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
        ignore(self.save())
      }
      true
    }
  }
}

// ---- Fuzzy / Levenshtein search ----

///| Compute the Levenshtein (edit) distance between two strings.
/// A smaller value means the strings are more similar.
pub fn levenshtein_distance(a : String, b : String) -> Int {
  let ca = chars_of(a)
  let cb = chars_of(b)
  let na = ca.length()
  let nb = cb.length()
  if na == 0 { return nb }
  if nb == 0 { return na }
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
    // Swap prev <-> curr.
    let new_prev = curr
    prev = new_prev
    curr = []
    let mut k = 0
    while k <= nb {
      curr.push(0)
      k = k + 1
    }
    i = i + 1
  }
  prev[nb]
}

///| Convert a String to an array of chars (as Int code points).
fn chars_of(s : String) -> Array[Int] {
  let out : Array[Int] = []
  for c in s {
    out.push(c.to_int())
  }
  out
}

///| Minimum of three integers.
fn min3(a : Int, b : Int, c : Int) -> Int {
  let m = if a < b { a } else { b }
  if m < c { m } else { c }
}

///| Find entries whose name is similar to `query` (case-insensitive) within
///| a maximum Levenshtein edit distance. Returns (entry, distance) pairs
///| sorted by ascending distance.
pub fn GeoDB::find_name_fuzzy(
  self : GeoDB,
  query : String,
  max_distance~ : Int = 2
) -> Array[(@types.GeoEntry, Int)] {
  let q = query.to_lower()
  let results : Array[(@types.GeoEntry, Int)] = []
  for e in self.all() {
    let dist = levenshtein_distance(e.name.to_lower(), q)
    if dist <= max_distance {
      results.push((e, dist))
    }
  }
  results.sort_by(fn(a, b) { if a.1 < b.1 { -1 } else if a.1 > b.1 { 1 } else { 0 } })
  results
}

// ---- Export ----

///| Export all entries as a CSV string (RFC 4180-ish).
/// Columns: id, name, lat, lng, country, province, city, district,
/// street, detail, postal_code, tags (semicolon-separated).
pub fn GeoDB::to_csv(self : GeoDB) -> String {
  let lines : Array[String] = []
  lines.push("id,name,lat,lng,country,province,city,district,street,detail,postal_code,tags")
  for e in self.all() {
    let tag_str = e.tags.join(";")
    let row = [
      escape_csv(e.id),
      escape_csv(e.name),
      e.location.lat.to_string(),
      e.location.lng.to_string(),
      escape_csv(e.address.country),
      escape_csv(e.address.province),
      escape_csv(e.address.city),
      escape_csv(e.address.district),
      escape_csv(e.address.street),
      escape_csv(e.address.detail),
      escape_csv(e.address.postal_code),
      escape_csv(tag_str),
    ].join(",")
    lines.push(row)
  }
  lines.join("\n")
}

///| Escape a value for CSV: wrap in quotes if it contains comma, quote, or newline.
fn escape_csv(s : String) -> String {
  let needs_quote = s.contains(",") || s.contains("\"") || s.contains("\n")
  if !needs_quote {
    return s
  }
  let escaped = s.replace(old="\"", new="\"\"")
  "\"\{escaped}\""
}

// ---- Batch operations ----

///| Insert multiple entries at once. Returns the number of entries inserted.
pub fn GeoDB::insert_batch(
  self : GeoDB,
  entries : Array[@types.GeoEntry]
) -> Int {
  let mut n = 0
  for e in entries {
    self.insert(e)
    n = n + 1
  }
  n
}

///| Remove multiple entries by id. Returns the number of entries actually removed.
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

///| Remove all entries from the database.
pub fn GeoDB::clear(self : GeoDB) -> Unit {
  for e in self.all() {
    ignore(self.index.remove(e.id))
  }
  if self.auto_save {
    ignore(self.save())
  }
}

// ---- JSON import / export ----

///| Export all entries to a JSON string (array of GeoEntry objects).
/// Uses the MoonBit ToJson derive on GeoEntry for a compact, machine-readable
/// interchange format suitable for web APIs and inter-process data exchange.
pub fn GeoDB::to_json(self : GeoDB) -> String {
  let entries = self.all()
  let parts : Array[String] = []
  for e in entries {
    parts.push(e.to_json().stringify())
  }
  if parts.length() == 0 {
    "[]"
  } else {
    "[" + parts.join(",") + "]"
  }
}

///| Import entries from a JSON string (array of GeoEntry objects).
/// Returns the number of entries successfully imported.
/// Entries already present (by id) are replaced.
pub fn GeoDB::import_json(self : GeoDB, json : String) -> Int {
  // Strip outer whitespace.
  let trimmed = json.trim().to_owned()
  if trimmed.length() == 0 || trimmed == "[]" {
    return 0
  }
  // Parse top-level JSON.
  let j = try { @json.parse(trimmed) } catch { _ => return 0 }
  // Expect an array at top level.
  match j {
    Array(arr) => {
      let mut n = 0
      for item in arr {
        match try_import_json_value(item) {
          None => ()
          Some(entry) => {
            self.insert(entry)
            n = n + 1
          }
        }
      }
      if self.auto_save && n > 0 {
        ignore(self.save())
      }
      n
    }
    _ => 0
  }
}

///| Attempt to decode a Json value into a GeoEntry. Returns None on failure.
fn try_import_json_value(j : Json) -> @types.GeoEntry? {
  try {
    let e : @types.GeoEntry = @json.from_json(j)
    Some(e)
  } catch {
    _ => None
  }
}

// ---- GeoJSON-style export ----

///| Export all entries as a GeoJSON FeatureCollection string.
/// Each entry becomes a Feature with a Point geometry and an id + name +
/// address + tags properties object. Compliant with RFC 7946.
pub fn GeoDB::to_geojson(self : GeoDB) -> String {
  let lines : Array[String] = []
  lines.push("{\"type\":\"FeatureCollection\",\"features\":[")
  let entries = self.all()
  let mut i = 0
  for e in entries {
    if i > 0 {
      lines.push(",")
    }
    let props = [
      "\"id\":\"" + escape_json_string(e.id) + "\"",
      "\"name\":\"" + escape_json_string(e.name) + "\"",
      "\"address\":" + e.address.to_json().stringify(),
      "\"tags\":" + string_array_to_json(e.tags),
    ].join(",")
    let feature = "{" +
      "\"type\":\"Feature\"," +
      "\"geometry\":{" +
      "\"type\":\"Point\"," +
      "\"coordinates\":[" + e.location.lng.to_string() + "," + e.location.lat.to_string() + "]" +
      "}," +
      "\"properties\":{" + props + "}" +
      "}"
    lines.push(feature)
    i = i + 1
  }
  lines.push("]}")
  lines.join("")
}

fn escape_json_string(s : String) -> String {
  s.replace(old="\\", new="\\\\")
    .replace(old="\"", new="\\\"")
    .replace(old="\n", new="\\n")
    .replace(old="\r", new="\\r")
    .replace(old="\t", new="\\t")
}

fn string_array_to_json(arr : Array[String]) -> String {
  let parts : Array[String] = []
  for s in arr {
    parts.push("\"" + escape_json_string(s) + "\"")
  }
  "[" + parts.join(",") + "]"
}

// ---- Distance & pair queries ----

///| Compute the great-circle distance (km) between two entries by id.
/// Returns None if either id is not found.
pub fn GeoDB::distance_between(
  self : GeoDB,
  id_a : String,
  id_b : String
) -> Double? {
  match (self.get(id_a), self.get(id_b)) {
    (Some(a), Some(b)) =>
      Some(@geo.haversine(a.location, b.location))
    _ => None
  }
}

///| Find the `k` closest pairs of entries in the database.
/// Each pair is returned as (entry_a, entry_b, distance_km).
/// Pairs are sorted by ascending distance; the same pair is reported
/// only once (canonical order by id).
pub fn GeoDB::find_nearest_pairs(
  self : GeoDB,
  k : Int
) -> Array[(@types.GeoEntry, @types.GeoEntry, Double)] {
  let entries = self.all()
  let pairs : Array[(@types.GeoEntry, @types.GeoEntry, Double)] = []
  let n = entries.length()
  let mut i = 0
  while i < n {
    let mut j = i + 1
    while j < n {
      let a = entries[i]
      let b = entries[j]
      let d = @geo.haversine(a.location, b.location)
      pairs.push((a, b, d))
      j = j + 1
    }
    i = i + 1
  }
  pairs.sort_by(fn(x, y) {
    if x.2 < y.2 { -1 } else if x.2 > y.2 { 1 } else { 0 }
  })
  let out : Array[(@types.GeoEntry, @types.GeoEntry, Double)] = []
  let mut m = 0
  for p in pairs {
    if m >= k { break }
    out.push(p)
    m = m + 1
  }
  out
}

///| For a given entry, find its `k` nearest neighbours (excluding itself).
/// Returns (other_entry, distance_km) pairs sorted by ascending distance.
pub fn GeoDB::find_neighbors(
  self : GeoDB,
  id : String,
  k : Int
) -> Array[(@types.GeoEntry, Double)] {
  match self.get(id) {
    None => []
    Some(target) => {
      let results : Array[(@types.GeoEntry, Double)] = []
      for e in self.all() {
        if e.id == id {
          continue
        }
        let d = @geo.haversine(target.location, e.location)
        results.push((e, d))
      }
      results.sort_by(fn(a, b) {
        if a.1 < b.1 { -1 } else if a.1 > b.1 { 1 } else { 0 }
      })
      let out : Array[(@types.GeoEntry, Double)] = []
      let mut i = 0
      for r in results {
        if i >= k { break }
        out.push(r)
        i = i + 1
      }
      out
    }
  }
}

// ---- Enhanced search ----

///| Case-sensitive version of `find_name_contains`.
pub fn GeoDB::find_name_contains_case(
  self : GeoDB,
  needle : String
) -> Array[@types.GeoEntry] {
  let results : Array[@types.GeoEntry] = []
  for e in self.all() {
    if e.name.contains(needle) {
      results.push(e)
    }
  }
  results
}

///| Find entries whose name starts with `prefix` (case-sensitive).
pub fn GeoDB::find_name_prefix_case(
  self : GeoDB,
  prefix : String
) -> Array[@types.GeoEntry] {
  let results : Array[@types.GeoEntry] = []
  for e in self.all() {
    if e.name.has_prefix(prefix) {
      results.push(e)
    }
  }
  results
}

///| Find entries whose name matches a simple wildcard-like pattern:
///   `*` matches any sequence of characters, `?` matches a single char.
/// The rest of the string is literal (case-insensitive).
/// Returns entries whose name matches the pattern.
pub fn GeoDB::find_name_pattern(
  self : GeoDB,
  pattern : String
) -> Array[@types.GeoEntry] {
  let p = pattern.to_lower()
  let results : Array[@types.GeoEntry] = []
  for e in self.all() {
    let n = e.name.to_lower()
    if simple_wildcard_match(n, p) {
      results.push(e)
    }
  }
  results
}

///| Simple wildcard matching with `*` (any sequence) and `?` (single char).
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

///| Count how many entries have a specific tag (case-insensitive).
pub fn GeoDB::count_by_tag(self : GeoDB, tag : String) -> Int {
  let lower = tag.to_lower()
  let mut n = 0
  for e in self.all() {
    for t in e.tags {
      if t.to_lower() == lower {
        n = n + 1
        break
      }
    }
  }
  n
}

///| Compute district distribution: count entries per district.
/// Optionally filtered by province (empty = all).
pub fn GeoDB::district_distribution(
  self : GeoDB,
  province~ : String = ""
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
  result.sort_by(fn(a, b) { if a.1 > b.1 { -1 } else if a.1 < b.1 { 1 } else { 0 } })
  result
}

///| Compute the centroid (simple mean) of the k most-tagged entries,
/// useful for heat-map visualization. Returns (point, count_of_entries_used).
pub fn GeoDB::centroid_weighted_by_tag(self : GeoDB, tag : String) -> (@types.GeoPoint, Int)? {
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

///| Update the address of an existing entry. Returns true on success.
pub fn GeoDB::update_address(
  self : GeoDB,
  id : String,
  new_address : @types.Address
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
        ignore(self.save())
      }
      true
    }
  }
}

///| Update the location of an existing entry (lat + lng separately).
/// Returns true if the entry was found and updated.
pub fn GeoDB::update_coordinates(
  self : GeoDB,
  id : String,
  lat : Double,
  lng : Double
) -> Bool {
  self.update_location(id, @types.GeoPoint::make(lat, lng))
}

///| Rename (replace the name of) an existing entry. Returns true on success.
pub fn GeoDB::rename(self : GeoDB, id : String, new_name : String) -> Bool {
  self.update_name(id, new_name)
}

// ---- Advanced queries ----

///| Find entries inside a strict bbox AND within a radius_km of the
/// center of that bbox. Useful for "downtown" style queries.
pub fn GeoDB::find_in_bbox_strict(
  self : GeoDB,
  bbox : @types.BBox,
  radius_km~ : Double
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

///| Compute all distinct tag-combinations of size 2 (co-occurring tag pairs)
/// and their frequencies. Useful for tag association analysis.
pub fn GeoDB::tag_pair_distribution(self : GeoDB) -> Array[((String, String), Int)] {
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
  result.sort_by(fn(a, b) { if a.1 > b.1 { -1 } else if a.1 < b.1 { 1 } else { 0 } })
  result
}

// ---- CSV import ----

///| Import entries from a CSV string (the inverse of `to_csv`).
/// Returns the number of entries successfully imported.
/// Expects the same header and column order as `to_csv`.
pub fn GeoDB::import_csv(self : GeoDB, csv : String) -> Int {
  let lines = csv.split("\n").collect()
  if lines.length() == 0 {
    return 0
  }
  // Skip header line.
  let mut n = 0
  let mut i = 1
  while i < lines.length() {
    let line = lines[i].to_string()
    if line.trim().length() == 0 {
      i = i + 1
      continue
    }
    match parse_csv_row(line) {
      None => ()
      Some(entry) => {
        self.insert(entry)
        n = n + 1
      }
    }
    i = i + 1
  }
  if self.auto_save && n > 0 {
    ignore(self.save())
  }
  n
}

///| Parse a single CSV row into a GeoEntry. Handles quoted fields.
fn parse_csv_row(line : String) -> @types.GeoEntry? {
  let fields = parse_csv_fields(line)
  if fields.length() < 12 {
    return None
  }
  let id = fields[0]
  let name = fields[1]
  let lat = try { @string.parse_double(fields[2]) } catch { _ => 0.0 }
  let lng = try { @string.parse_double(fields[3]) } catch { _ => 0.0 }
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
      out.push(p.to_string())
    }
    out
  }
  if id.length() == 0 && name.length() == 0 {
    return None
  }
  let entry_id = if id.length() == 0 {
    let rand = @random.Rand::new()
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

///| Split a CSV line into fields, handling double-quote escaping.
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
    } else {
      if c == ',' {
        out.push(line.substring(start=start, end=i).to_string())
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
  }
  out.push(line.substring(start=start, end=n).to_string())
  out
}

// ---- GeoJSON import ----

///| Import entries from a GeoJSON FeatureCollection string.
/// Returns the number of entries successfully imported.
/// Each Feature must have a Point geometry and properties with id/name.
pub fn GeoDB::import_geojson(self : GeoDB, geojson : String) -> Int {
  let trimmed = geojson.trim().to_owned()
  if trimmed.length() == 0 {
    return 0
  }
  let j = try { @json.parse(trimmed) } catch { _ => return 0 }
  match j {
    Object(obj) => {
      let mut n = 0
      // Check for "type": "FeatureCollection" or single "Feature".
      let typ = obj.get("type")
      match typ {
        Some(String(s)) => {
          if s == "FeatureCollection" {
            // Extract features array.
            match obj.get("features") {
              Some(Array(features)) => {
                for feat in features {
                  match try_import_geojson_feature(feat) {
                    None => ()
                    Some(entry) => {
                      self.insert(entry)
                      n = n + 1
                    }
                  }
                }
              }
              _ => ()
            }
          } else if s == "Feature" {
            match try_import_geojson_feature(j) {
              None => ()
              Some(entry) => {
                self.insert(entry)
                n = n + 1
              }
            }
          }
        }
        _ => ()
      }
      if self.auto_save && n > 0 {
        ignore(self.save())
      }
      n
    }
    _ => 0
  }
}

///| Attempt to decode a GeoJSON Feature Json value into a GeoEntry.
fn try_import_geojson_feature(j : Json) -> @types.GeoEntry? {
  match j {
    Object(obj) => {
      // Extract coordinates from geometry.
      let mut lng = 0.0
      let mut lat = 0.0
      match obj.get("geometry") {
        Some(Object(geom)) => {
          match geom.get("coordinates") {
            Some(Array(coords)) => {
              if coords.length() >= 2 {
                match coords[0] {
                  Number(v) => lng = v
                  _ => ()
                }
                match coords[1] {
                  Number(v) => lat = v
                  _ => ()
                }
              } else {
                return None
              }
            }
            _ => return None
          }
        }
        _ => return None
      }
      // Extract properties.
      let id = match obj.get("properties") {
        Some(Object(prop)) => {
          match prop.get("id") {
            Some(String(s)) => s
            _ => ""
          }
        }
        _ => ""
      }
      let name = match obj.get("properties") {
        Some(Object(prop)) => {
          match prop.get("name") {
            Some(String(s)) => s
            _ => ""
          }
        }
        _ => ""
      }
      let entry_id = if id.length() == 0 {
        let rand = @random.Rand::new()
        "gj_" + rand.int(limit=1000000).to_string()
      } else {
        id
      }
      // Try to parse full address from properties if available.
      let address = match obj.get("properties") {
        Some(Object(prop)) => {
          match prop.get("address") {
            Some(addr_json) => {
              try {
                let a : @types.Address = @json.from_json(addr_json)
                a
              } catch {
                _ => @types.Address::empty()
              }
            }
            _ => @types.Address::empty()
          }
        }
        _ => @types.Address::empty()
      }
      // Extract tags.
      let tags = match obj.get("properties") {
        Some(Object(prop)) => {
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

///| Find groups of entries that are likely duplicates (same physical location).
/// Two entries are considered duplicates if they are within `max_distance_km`
/// of each other AND their names have a Levenshtein edit distance <= `max_edit_dist`.
/// Returns an array of groups, where each group contains the duplicate entries.
pub fn GeoDB::find_duplicates(
  self : GeoDB,
  max_distance_km~ : Double = 0.1,
  max_edit_dist~ : Int = 2
) -> Array[Array[@types.GeoEntry]] {
  let entries = self.all()
  let n = entries.length()
  let visited : Array[Bool] = []
  let mut i = 0
  while i < n {
    visited.push(false)
    i = i + 1
  }
  let groups : Array[Array[@types.GeoEntry]] = []
  i = 0
  while i < n {
    if visited[i] {
      i = i + 1
      continue
    }
    let a = entries[i]
    let group : Array[@types.GeoEntry] = [a]
    visited[i] = true
    let mut j = i + 1
    while j < n {
      if visited[j] {
        j = j + 1
        continue
      }
      let b = entries[j]
      let d = @geo.haversine(a.location, b.location)
      if d <= max_distance_km {
        let name_dist = levenshtein_distance(
          a.name.to_lower(),
          b.name.to_lower()
        )
        if name_dist <= max_edit_dist {
          group.push(b)
          visited[j] = true
        }
      }
      j = j + 1
    }
    if group.length() >= 2 {
      groups.push(group)
    }
    i = i + 1
  }
  groups
}

// ---- Spatial grid clustering ----

///| Cluster entries into grid cells of roughly `cell_size_km` x `cell_size_km`.
/// Returns an array of (cell_key, centroid_point, member_count) sorted by count desc.
/// Useful for heatmap visualization and data analysis.
pub fn GeoDB::cluster_by_grid(
  self : GeoDB,
  cell_size_km~ : Double = 1.0
) -> Array[(String, @types.GeoPoint, Int)] {
  let cells : @hashmap.HashMap[String, Array[@types.GeoEntry]] =
    @hashmap.HashMap([])
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
  result.sort_by(fn(a, b) { if a.2 > b.2 { -1 } else if a.2 < b.2 { 1 } else { 0 } })
  result
}

///| Compute a grid cell key for a geographic point.
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

///| Compute a pairwise Haversine distance matrix for a set of entry IDs.
/// Returns a 2D array where matrix[i][j] is the distance (km) between
/// ids[i] and ids[j]. Missing IDs are treated as having distance 0
/// to all entries. Returns an empty array if no entries are found.
pub fn GeoDB::distance_matrix(
  self : GeoDB,
  ids : Array[String]
) -> Array[Array[Double]] {
  let n = ids.length()
  let matrix : Array[Array[Double]] = []
  let mut i = 0
  while i < n {
    let row : Array[Double] = []
    let entry_i = self.get(ids[i])
    let mut j = 0
    while j < n {
      let entry_j = self.get(ids[j])
      let d = match (entry_i, entry_j) {
        (Some(a), Some(b)) => @geo.haversine(a.location, b.location)
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

///| Find the closest entry to a given coordinate.
/// Returns (entry, distance_km) or None if the DB is empty.
pub fn GeoDB::reverse_geocode(
  self : GeoDB,
  lat : Double,
  lng : Double
) -> (@types.GeoEntry, Double)? {
  let point = @types.GeoPoint::make(lat, lng)
  let entries = self.all()
  if entries.length() == 0 {
    return None
  }
  let mut best : @types.GeoEntry = entries[0]
  let mut best_d = @geo.haversine(point, best.location)
  let mut i = 1
  while i < entries.length() {
    let d = @geo.haversine(point, entries[i].location)
    if d < best_d {
      best_d = d
      best = entries[i]
    }
    i = i + 1
  }
  Some((best, best_d))
}

// ---- Tag combination queries ----

///| Find entries that have ALL of the specified tags (AND logic).
pub fn GeoDB::find_by_tags_all(
  self : GeoDB,
  tags : Array[String]
) -> Array[@types.GeoEntry] {
  let results : Array[@types.GeoEntry] = []
  if tags.length() == 0 {
    return results
  }
  for e in self.all() {
    let mut match_all = true
    for t in tags {
      if !has_tag(e, t) {
        match_all = false
        break
      }
    }
    if match_all {
      results.push(e)
    }
  }
  results
}

///| Find entries that have ANY of the specified tags (OR logic).
pub fn GeoDB::find_by_tags_any(
  self : GeoDB,
  tags : Array[String]
) -> Array[@types.GeoEntry] {
  let results : Array[@types.GeoEntry] = []
  if tags.length() == 0 {
    return results
  }
  for e in self.all() {
    for t in tags {
      if has_tag(e, t) {
        results.push(e)
        break
      }
    }
  }
  results
}

fn has_tag(entry : @types.GeoEntry, tag : String) -> Bool {
  for t in entry.tags {
    if t.to_lower() == tag.to_lower() {
      return true
    }
  }
  false
}

// ---- Bounding box queries ----

///| Count entries within a bounding box.
pub fn GeoDB::bbox_count(self : GeoDB, bbox : @types.BBox) -> Int {
  let entries = self.find_in_bbox(bbox)
  entries.length()
}

///| Find all entries within a circular region.
pub fn GeoDB::find_within_radius(
  self : GeoDB,
  lat : Double,
  lng : Double,
  radius_km : Double
) -> Array[@types.GeoEntry] {
  let center = @types.GeoPoint::make(lat, lng)
  let results : Array[@types.GeoEntry] = []
  for e in self.all() {
    let d = @geo.haversine(center, e.location)
    if d <= radius_km {
      results.push(e)
    }
  }
  results
}

// ---- Density map ----

///| Compute a density map: grid cells with entry counts.
/// Returns array of (cell_key, centroid_lat, centroid_lng, count).
pub fn GeoDB::density_map(
  self : GeoDB,
  cell_size_km~ : Double = 1.0
) -> Array[(String, Double, Double, Int)] {
  let cells : @hashmap.HashMap[String, Array[@types.GeoEntry]] =
    @hashmap.HashMap([])
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
  result.sort_by(fn(a, b) { if a.3 > b.3 { -1 } else if a.3 < b.3 { 1 } else { 0 } })
  result
}

// ---- Statistics ----

///| Compute the standard deviation of latitudes and longitudes.
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

///| Compute a histogram of entries per province.
pub fn GeoDB::province_histogram(self : GeoDB) -> Array[(String, Int)] {
  let counts : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for e in self.all() {
    let prov = if e.address.province.length() == 0 { "Unknown" } else { e.address.province }
    let count = counts.get(prov).unwrap_or(0)
    counts[prov] = count + 1
  }
  let result : Array[(String, Int)] = []
  for key in counts.keys() {
    result.push((key, counts.get(key).unwrap_or(0)))
  }
  result.sort_by(fn(a, b) { if a.1 > b.1 { -1 } else if a.1 < b.1 { 1 } else { 0 } })
  result
}
