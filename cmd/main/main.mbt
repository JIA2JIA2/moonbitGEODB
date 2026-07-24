// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// CLI demo for moonbitGEODB. Inserts sample Chinese landmarks, runs a few
// queries (name lookup, bbox, nearby, kNN), and persists to /tmp/geodb.json.

///| Beijing area landmarks for the demo.
fn sample_entries() -> Array[@types.GeoEntry] {
  [
    @types.GeoEntry::make(
      "tiananmen",
      "Tiananmen Square",
      @types.Address::empty(),
      @types.GeoPoint::make(39.9054, 116.3976)
    ),
    @types.GeoEntry::make(
      "great-wall-badaling",
      "Great Wall (Badaling)",
      @types.Address::empty(),
      @types.GeoPoint::make(40.3587, 116.0169)
    ),
    @types.GeoEntry::make(
      "summer-palace",
      "Summer Palace",
      @types.Address::empty(),
      @types.GeoPoint::make(39.9999, 116.2755)
    ),
    @types.GeoEntry::make(
      "forbidden-city",
      "Forbidden City",
      @types.Address::empty(),
      @types.GeoPoint::make(39.9163, 116.3972)
    ),
    @types.GeoEntry::make(
      "temple-of-heaven",
      "Temple of Heaven",
      @types.Address::empty(),
      @types.GeoPoint::make(39.8822, 116.4066)
    ),
    @types.GeoEntry::make(
      "bird-nest",
      "Bird's Nest Stadium",
      @types.Address::empty(),
      @types.GeoPoint::make(39.9929, 116.3964)
    ),
  ]
}

///| Print a single entry.
fn print_entry(label : String, e : @types.GeoEntry) -> Unit {
  println("  [\{label}] id=\{e.id}  name=\{e.name}")
  println("         lat=\{e.location.lat}, lng=\{e.location.lng}")
}

///| Print an (entry, distance) pair.
fn print_pair(label : String, p : (@types.GeoEntry, Double)) -> Unit {
  let (e, d) = p
  println("  [\{label}] \{e.name}  —  \{d} km")
}

///| Run the demo.
fn run_demo() -> Unit {
  // ---- 1. Create in-memory DB and load samples ----
  let db = @db.GeoDB::in_memory()
  for e in sample_entries() {
    db.insert(e)
  }
  println("== moonbitGEODB demo ==")
  println("Loaded \{db.size()} entries into in-memory DB.")
  println("")

  // ---- 2. Parse a Chinese address ----
  println("-- Address parsing --")
  try {
    let addr = @parser.parse_address("中国,北京,北京,海淀区,中关村大街,100080")
    println("  parsed: country=\{addr.country} province=\{addr.province} " +
      "city=\{addr.city} district=\{addr.district} street=\{addr.street} " +
      "postal=\{addr.postal_code}")
  } catch {
    e => println("  parse failed: \{e}")
  }

  try {
    let pt = @parser.parse_coordinate("39.9054, 116.3976")
    println("  coordinate: lat=\{pt.lat}, lng=\{pt.lng}")
  } catch {
    e => println("  coord parse failed: \{e}")
  }
  println("")

  // ---- 3. Insert via raw API (parses address) ----
  println("-- Insert via raw API --")
  let inserted = db.insert_raw(
    "zhongguancun",
    "Zhongguancun",
    39.9842,
    116.3075,
    "China,Beijing,Beijing,Haidian,Zhongguancun Street,100080"
  )
  print_entry("inserted", inserted)
  println("  DB size now: \{db.size()}")
  println("")

  // ---- 4. Name lookup ----
  println("-- Name lookup (case-insensitive) --")
  let exact = db.find_by_name("summer palace")
  for e in exact {
    print_entry("exact", e)
  }
  let prefix = db.find_name_prefix("great")
  for e in prefix {
    print_entry("prefix", e)
  }
  let sub = db.find_name_contains("palace")
  for e in sub {
    print_entry("contains", e)
  }
  println("")

  // ---- 5. Bounding box query (central Beijing) ----
  println("-- BBox query: central Beijing rectangle --")
  let bbox = @types.BBox::from_corners(
    @types.GeoPoint::make(39.88, 116.39),
    @types.GeoPoint::make(39.92, 116.41)
  )
  let in_bbox = db.find_in_bbox(bbox)
  println("  \{in_bbox.length()} entries inside bbox:")
  for e in in_bbox {
    print_entry("bbox", e)
  }
  println("")

  // ---- 6. Nearby query (within 5 km of Tiananmen) ----
  println("-- Nearby: within 5 km of Tiananmen --")
  let tiananmen = @types.GeoPoint::make(39.9054, 116.3976)
  let nearby = db.find_nearby(tiananmen, radius_km=5.0, limit=10)
  for p in nearby {
    print_pair("nearby", p)
  }
  println("")

  // ---- 7. kNN query (3 nearest to Tiananmen) ----
  println("-- kNN: 3 nearest to Tiananmen --")
  let knn = db.find_nearest(tiananmen, 3)
  for p in knn {
    print_pair("knn", p)
  }
  println("")

  // ---- 8. Persistence: save to /tmp/geodb.json and reopen ----
  println("-- Persistence --")
  let path = "/tmp/geodb.json"
  match db.save_to(path) {
    Err(msg) => println("  save failed: \{msg}")
    Ok(_) =>
      println("  saved \{db.size()} entries to \{path}")
  }
  // Reopen from disk.
  let db2 = @db.GeoDB::open(path)
  println("  reopened from disk: \{db2.size()} entries loaded")
  println("")

  // ---- 9. JSON export of all entries ----
  println("-- JSON export (first 200 chars) --")
  let json_text = db.to_json()
  let preview_len = if json_text.length() < 200 {
    json_text.length()
  } else {
    200
  }
  let preview = json_text.get_view(end=preview_len).unwrap()
  println("  \{preview}...")
  println("")
  println("== demo complete ==")
}

fn main {
  run_demo()
}
