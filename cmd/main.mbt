// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// CLI demo: store, parse, and retrieve address information.
//
// Usage:
//   moon run cmd                           # run default demo
//   moon run cmd <address>                 # parse & store a custom address
//   moon run cmd search <keyword>          # search by name
//   moon run cmd nearby <lat> <lng>        # find nearby within 5km
//   moon run cmd seed [n]                  # seed random Chinese addresses (default 100)
//   moon run cmd save <path>               # persist DB to file
//   moon run cmd load <path>               # load DB from file
//   moon run cmd backup <path>             # backup DB file
//   moon run cmd check <path>              # integrity check

fn build_usage() -> String {
  let s1 = "moonbitGEODB - Geographic Information Database CLI\n"
  let s2 = s1 + "\n"
  let s3 = s2 + "Usage:\n"
  let s4 = s3 + "  moon run cmd                           Run the default demo\n"
  let s5 = s4 + "  moon run cmd <address>                 Parse and store an address\n"
  let s6 = s5 + "  moon run cmd search <keyword>          Search entries by name keyword\n"
  let s7 = s6 + "  moon run cmd nearby <lat> <lng> [km]   Find nearby entries (default 5km)\n"
  let s8 = s7 + "  moon run cmd seed [n]                  Seed random Chinese addresses (default 100)\n"
  let s9 = s8 + "  moon run cmd save <path>               Persist DB to a file\n"
  let s10 = s9 + "  moon run cmd load <path>               Load DB from a file\n"
  let s11 = s10 + "  moon run cmd backup <path>              Create backup of DB file\n"
  let s12 = s11 + "  moon run cmd check <path>               Check DB file integrity\n"
  let s13 = s12 + "  moon run cmd info <path>                Show DB metadata\n"
  let s14 = s13 + "\n"
  let s15 = s14 + "Examples:\n"
  let s16 = s15 + "  moon run cmd\n"
  let s17 = s16 + "  moon run cmd \"北京市海淀区颐和园路5号\"\n"
  let s18 = s17 + "  moon run cmd search \"颐和园\"\n"
  let s19 = s18 + "  moon run cmd seed 500\n"
  let s20 = s19 + "  moon run cmd save geo.db\n"
  s20 + "  moon run cmd load geo.db"
}

fn main {
  let args = @env.args()
  if args.length() <= 1 {
    run_demo()
    return
  }

  let cmd = args.get(1).unwrap_or("")
  if cmd == "help" || cmd == "--help" || cmd == "-h" {
    println(build_usage())
    return
  }

  if cmd == "search" {
    if args.length() < 3 {
      println("Error: search requires a keyword argument")
      println("Usage: moon run cmd search <keyword>")
      return
    }
    run_search(args.get(2).unwrap())
    return
  }

  if cmd == "nearby" {
    if args.length() < 4 {
      println("Error: nearby requires lat, lng, and optional km arguments")
      println("Usage: moon run cmd nearby <lat> <lng> [km]")
      return
    }
    let lat_str = args.get(2).unwrap()
    let lng_str = args.get(3).unwrap()
    let lat = try { @string.parse_double(lat_str) } catch {
      _ => {
        println("Error: invalid latitude: " + lat_str)
        return
      }
    }
    let lng = try { @string.parse_double(lng_str) } catch {
      _ => {
        println("Error: invalid longitude: " + lng_str)
        return
      }
    }
    let km = if args.length() > 4 {
      try { @string.parse_double(args.get(4).unwrap()) } catch {
        _ => 5.0
      }
    } else {
      5.0
    }
    run_nearby(lat, lng, km)
    return
  }

  if cmd == "seed" {
    let n = if args.length() > 2 {
      try { @string.parse_int(args.get(2).unwrap()) } catch {
        _ => 100
      }
    } else {
      100
    }
    run_seed(n)
    return
  }

  if cmd == "save" {
    if args.length() < 3 {
      println("Error: save requires a file path")
      println("Usage: moon run cmd save <path>")
      return
    }
    run_save(args.get(2).unwrap())
    return
  }

  if cmd == "load" {
    if args.length() < 3 {
      println("Error: load requires a file path")
      println("Usage: moon run cmd load <path>")
      return
    }
    run_load(args.get(2).unwrap())
    return
  }

  if cmd == "backup" {
    if args.length() < 3 {
      println("Error: backup requires a file path")
      println("Usage: moon run cmd backup <path>")
      return
    }
    run_backup(args.get(2).unwrap())
    return
  }

  if cmd == "check" {
    if args.length() < 3 {
      println("Error: check requires a file path")
      println("Usage: moon run cmd check <path>")
      return
    }
    run_check(args.get(2).unwrap())
    return
  }

  if cmd == "info" {
    if args.length() < 3 {
      println("Error: info requires a file path")
      println("Usage: moon run cmd info <path>")
      return
    }
    run_info(args.get(2).unwrap())
    return
  }

  // Treat all arguments as an address string.
  let addr_parts : Array[String] = []
  let mut i = 1
  while i < args.length() {
    addr_parts.push(args.get(i).unwrap())
    i = i + 1
  }
  let address_str = addr_parts.join(" ")
  run_parse_and_store(address_str)
}

// ============ Commands ============

fn run_demo() -> Unit {
  println("=== moonbitGEODB Demo ===")
  println("")

  let db = @db.GeoDB::in_memory()

  // Store: 北京市海淀区颐和园路5号
  let entry1 = db.insert_raw(
    "yhy001",
    "颐和园",
    39.9999,
    116.2755,
    "北京市海淀区颐和园路5号"
  )
  println("[STORED] id=" + entry1.id + ", name=" + entry1.name)
  println("         location: (" + entry1.location.lat.to_string() + ", " + entry1.location.lng.to_string() + ")")
  println("         address:  " + entry1.address.to_line())
  println("")

  // Store additional entries for search demo
  ignore(db.insert_raw(
    "taman001",
    "天安门广场",
    39.9055,
    116.3972,
    "北京市东城区东长安街"
  ))
  ignore(db.insert_raw(
    "gugong001",
    "故宫博物院",
    39.9163,
    116.3972,
    "北京市东城区景山前街4号"
  ))
  ignore(db.insert_raw(
    "shanghai001",
    "东方明珠塔",
    31.2397,
    121.4997,
    "上海市浦东新区陆家嘴世纪大道1号"
  ))

  println("Database size: " + db.size().to_string())
  println("")

  // Retrieve: by id
  println("--- Retrieve by ID ---")
  match db.get("yhy001") {
    Some(e) => print_entry(e)
    None => println("(not found)")
  }
  println("")

  // Retrieve: by name (exact)
  println("--- Search by name (exact) ---")
  let results = db.find_by_name("颐和园")
  for e in results {
    print_entry(e)
  }
  println("")

  // Retrieve: by name (contains)
  println("--- Search by keyword '北京' ---")
  let results2 = db.find_name_contains("北京")
  for e in results2 {
    print_entry(e)
  }
  println("")

  // Retrieve: nearby
  println("--- Nearby 颐和园 (5km radius) ---")
  let nearby = db.find_nearby(
    @types.GeoPoint::make(39.9999, 116.2755),
    radius_km=5.0,
    limit=5
  )
  for pair in nearby {
    println("  " + pair.0.id + " (" + pair.0.name + ") - " + pair.1.to_string() + " km")
  }
  println("")

  // Parse-only demonstration
  println("--- Parse-only: '广州市天河区珠江新城华夏路16号' ---")
  let addr = try { @parser.parse_address("广州市天河区珠江新城华夏路16号") } catch {
    _ => @types.Address::empty()
  }
  println("  Country:     " + addr.country)
  println("  Province:    " + addr.province)
  println("  City:        " + addr.city)
  println("  District:    " + addr.district)
  println("  Street:      " + addr.street)
  println("  Detail:      " + addr.detail)
  println("  Postal Code: " + addr.postal_code)
  println("")

  println("Demo complete. Try custom queries:")
  println("  moon run cmd \"上海市浦东新区陆家嘴环路1000号\"")
  println("  moon run cmd search \"故宫\"")
  println("  moon run cmd seed 500       # generate 500 random addresses")
  println("  moon run cmd save geo.db     # persist to disk")
}

fn run_seed(n : Int) -> Unit {
  println("=== Seeding " + n.to_string() + " random Chinese addresses ===")
  println("")

  let db = @db.GeoDB::in_memory()

  let entries = @gen.gen_batch(n)
  for e in entries {
    db.insert(e)
  }

  println("Generated " + entries.length().to_string() + " entries from " + @gen.city_count().to_string() + " cities.")
  println("")

  // Show first 5 entries as samples.
  println("--- Sample entries ---")
  let mut i = 0
  for e in entries {
    if i >= 5 {
      break
    }
    println("  [" + e.id + "] " + e.name)
    println("    " + e.address.to_line())
    println("    lat=" + e.location.lat.to_string() + ", lng=" + e.location.lng.to_string())
    i = i + 1
  }
  if entries.length() > 5 {
    println("  ... and " + (entries.length() - 5).to_string() + " more")
  }
  println("")

  // Show city distribution.
  println("--- Cities used ---")
  let province_counts : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  for e in entries {
    let p = e.address.province
    if p.length() > 0 {
      let count = province_counts.get(p).unwrap_or(0)
      province_counts[p] = count + 1
    }
  }
  for p in province_counts.keys() {
    println("  " + p + ": " + province_counts.get(p).unwrap_or(0).to_string() + " entries")
  }
  println("")

  // Show coord range.
  println("--- Coordinate range ---")
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
  println("  Lat: " + min_lat.to_string() + " ~ " + max_lat.to_string())
  println("  Lng: " + min_lng.to_string() + " ~ " + max_lng.to_string())
  println("")

  // Save to file.
  let out_path = "geo_seeded.db"
  match db.save_to(out_path) {
    Err(e) => println("Error saving to " + out_path + ": " + e)
    Ok(_) => println("Saved " + entries.length().to_string() + " entries to " + out_path)
  }
  println("")

  // Run nearby search as a demo.
  println("--- Nearby Beijing (39.9, 116.4) within 50km ---")
  let beijing = @types.GeoPoint::make(39.9, 116.4)
  let nearby = db.find_nearby(beijing, radius_km=50.0, limit=10)
  if nearby.length() > 0 {
    for pair in nearby {
      println("  " + pair.0.name + " (" + pair.0.id + ") - " + pair.1.to_string() + " km")
    }
  } else {
    println("  No entries found near Beijing.")
  }
}

fn run_parse_and_store(address_str : String) -> Unit {
  println("=== Parse & Store ===")
  println("Input: " + address_str)
  println("")

  let addr = try { @parser.parse_address(address_str) } catch {
    _ => @types.Address::empty()
  }
  println("[PARSED]")
  println("  Country:     " + addr.country)
  println("  Province:    " + addr.province)
  println("  City:        " + addr.city)
  println("  District:    " + addr.district)
  println("  Street:      " + addr.street)
  println("  Detail:      " + addr.detail)
  println("  Postal Code: " + addr.postal_code)
  println("")

  let db = @db.GeoDB::in_memory()
  let new_id = db.gen_id("e")
  let name = if addr.street.length() > 0 { addr.street } else { address_str }
  let entry = db.insert_raw(new_id, name, 0.0, 0.0, address_str)
  println("[STORED] id=" + entry.id)
  print_entry(entry)
  println("")
  println("Database size: " + db.size().to_string())
}

fn run_search(keyword : String) -> Unit {
  println("=== Search: '" + keyword + "' ==")
  println("")

  let db = build_sample_db()
  let results = db.find_name_contains(keyword)
  if results.length() == 0 {
    println("No entries found matching '" + keyword + "'.")
  } else {
    println("Found " + results.length().to_string() + " entries:")
    for e in results {
      print_entry(e)
    }
  }
}

fn run_nearby(lat : Double, lng : Double, km : Double) -> Unit {
  println("=== Nearby search ==")
  println("Center: (" + lat.to_string() + ", " + lng.to_string() + "), radius: " + km.to_string() + " km")
  println("")

  let db = build_sample_db()
  let results = db.find_nearby(
    @types.GeoPoint::make(lat, lng),
    radius_km=km,
    limit=20
  )
  if results.length() == 0 {
    println("No entries found within " + km.to_string() + " km.")
  } else {
    println("Found " + results.length().to_string() + " entries:")
    for pair in results {
      let e = pair.0
      let d = pair.1
      println("  " + e.id + " (" + e.name + ") - " + d.to_string() + " km")
      println("    Address: " + e.address.to_line())
      println("    Location: (" + e.location.lat.to_string() + ", " + e.location.lng.to_string() + ")")
    }
  }
}

fn run_save(path : String) -> Unit {
  println("=== Save to: " + path + " ===")
  let db = build_sample_db()
  match db.save_to(path) {
    Err(e) => println("Error: " + e)
    Ok(_) => println("Saved " + db.size().to_string() + " entries to " + path)
  }
}

fn run_load(path : String) -> Unit {
  println("=== Load from: " + path + " ===")
  let db = @db.GeoDB::open(path)
  println("Loaded " + db.size().to_string() + " entries from " + path)
  let meta = db.metadata()
  println("  Version: " + meta.version.to_string())
  println("  Created: " + meta.created_at.to_string())
  println("  Updated: " + meta.updated_at.to_string())
  println("")
  println("First 5 entries:")
  let mut i = 0
  for e in db.all() {
    if i >= 5 {
      break
    }
    println("  [" + e.id + "] " + e.name + " - " + e.address.to_line())
    i = i + 1
  }
}

fn run_backup(path : String) -> Unit {
  println("=== Backup: " + path + " ===")
  let db = @db.GeoDB::open(path)
  match db.backup() {
    Err(e) => println("Error: " + e)
    Ok(bak) => {
      println("Backup created: " + bak)
      println("Entries: " + db.size().to_string())
    }
  }
}

fn run_check(path : String) -> Unit {
  println("=== Integrity check: " + path + " ===")
  let db = @db.GeoDB::open(path)
  match db.check() {
    Err(e) => println("FAILED: " + e)
    Ok(meta) => {
      println("OK - Integrity verified")
      println("  Version: " + meta.version.to_string())
      println("  Entry count: " + meta.entry_count.to_string())
      println("  Created at: " + meta.created_at.to_string())
      println("  Updated at: " + meta.updated_at.to_string())
    }
  }
}

fn run_info(path : String) -> Unit {
  println("=== Database info: " + path + " ===")
  let db = @db.GeoDB::open(path)
  let meta = db.metadata()
  println("  File:       " + path)
  println("  Version:    " + meta.version.to_string())
  println("  Entries:    " + meta.entry_count.to_string())
  println("  Created:    " + meta.created_at.to_string())
  println("  Updated:    " + meta.updated_at.to_string())
  println("  Auto-save:  " + db.auto_save.to_string())
  println("")
  println("  Provinces:")
  let provinces = @gen.all_province_names()
  println("    " + provinces.length().to_string() + " provinces in generator")
  println("  Cities:")
  println("    " + @gen.city_count().to_string() + " cities in generator")
}

// ============ Helpers ============

fn build_sample_db() -> @db.GeoDB {
  let db = @db.GeoDB::in_memory()
  ignore(db.insert_raw(
    "yhy001",
    "颐和园",
    39.9999,
    116.2755,
    "北京市海淀区颐和园路5号"
  ))
  ignore(db.insert_raw(
    "taman001",
    "天安门广场",
    39.9055,
    116.3972,
    "北京市东城区东长安街"
  ))
  ignore(db.insert_raw(
    "gugong001",
    "故宫博物院",
    39.9163,
    116.3972,
    "北京市东城区景山前街4号"
  ))
  ignore(db.insert_raw(
    "shanghai001",
    "东方明珠塔",
    31.2397,
    121.4997,
    "上海市浦东新区陆家嘴世纪大道1号"
  ))
  ignore(db.insert_raw(
    "guangzhou001",
    "广州塔",
    23.1066,
    113.3239,
    "广州市海珠区阅江西路222号"
  ))
  db
}

fn print_entry(e : @types.GeoEntry) -> Unit {
  println("  id:       " + e.id)
  println("  name:     " + e.name)
  println("  location: (" + e.location.lat.to_string() + ", " + e.location.lng.to_string() + ")")
  println("  address:  " + e.address.to_line())
  println("    province: " + e.address.province)
  println("    city:     " + e.address.city)
  println("    district: " + e.address.district)
  println("    street:   " + e.address.street)
  println("    detail:   " + e.address.detail)
  println("    postal:   " + e.address.postal_code)
  println("")
}
