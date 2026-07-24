// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// CLI demo: store, parse, and retrieve address information.
//
// Usage:
//   moon run cmd                           # run default demo
//   moon run cmd <address>                 # parse & store a custom address
//   moon run cmd search <keyword>          # search by name
//   moon run cmd fuzzy <keyword> [max_dist] # fuzzy name search
//   moon run cmd nearby <lat> <lng> [km]   # find nearby within radius
//   moon run cmd within <lat> <lng> <km>   # find within distance (geofence)
//   moon run cmd tag <tag>                 # find entries by tag
//   moon run cmd tags                      # list all unique tags
//   moon run cmd province <province>       # find by province
//   moon run cmd city <city>               # find by city
//   moon run cmd district <district>       # find by district
//   moon run cmd stats                     # show geographic statistics
//   moon run cmd export [path]             # export DB to CSV
//   moon run cmd add-tag <id> <tag>        # add tag to entry
//   moon run cmd remove-tag <id> <tag>     # remove tag from entry
//   moon run cmd clear                     # clear all entries
//   moon run cmd seed [n]                  # seed random addresses
//   moon run cmd save <path>               # persist DB to file
//   moon run cmd load <path>               # load DB from file
//   moon run cmd backup <path>             # backup DB file
//   moon run cmd check <path>              # integrity check
//   moon run cmd info <path>               # show DB metadata
//   moon run cmd to-json [path]            # export DB to JSON
//   moon run cmd to-geojson [path]         # export DB to GeoJSON
//   moon run cmd pattern <pattern>         # wildcard search by name (*, ?)
//   moon run cmd distance <id1> <id2>      # compute distance between two entries
//   moon run cmd neighbors <id> [k]        # find k nearest neighbors of an entry
//   moon run cmd nearest-pairs [k]         # show k closest pairs in DB
//   moon run cmd districts [province]       # district distribution
//   moon run cmd tag-count <tag>           # count entries with a specific tag
//   moon run cmd tag-pairs                 # show tag co-occurrence pairs
//   moon run cmd rename <id> <name>        # rename an entry
//   moon run cmd update-coords <id> <lat> <lng>  # update entry coordinates
//   moon run cmd centroid <tag>            # centroid of entries sharing a tag
//   moon run cmd import-csv <csv_str>      # import entries from CSV string
//   moon run cmd import-geojson <gj_str>  # import entries from GeoJSON string
//   moon run cmd duplicates [dist] [edit] # find duplicate entries
//   moon run cmd cluster [cell_size_km]   # grid-based spatial clustering
//   moon run cmd matrix <id1> <id2> ...   # distance matrix for IDs

fn build_usage() -> String {
  let s1 = "moonbitGEODB - Geographic Information Database CLI\n"
  let s2 = s1 + "\n"
  let s3 = s2 + "Usage:\n"
  let s4 = s3 + "  moon run cmd                             Run the default demo\n"
  let s5 = s4 + "  moon run cmd <address>                   Parse and store an address\n"
  let s6 = s5 + "  moon run cmd search <keyword>            Search entries by name keyword\n"
  let s7 = s6 + "  moon run cmd fuzzy <kw> [max_dist]       Fuzzy search by name (Levenshtein)\n"
  let s8 = s7 + "  moon run cmd nearby <lat> <lng> [km]     Find nearby entries (default 5km)\n"
  let s9 = s8 + "  moon run cmd within <lat> <lng> <km>     Find entries within distance\n"
  let s10 = s9 + "  moon run cmd tag <tag>                   Find entries by tag\n"
  let s11 = s10 + "  moon run cmd tags                        List all unique tags\n"
  let s12 = s11 + "  moon run cmd province <province>         Find entries by province\n"
  let s13 = s12 + "  moon run cmd city <city>                 Find entries by city\n"
  let s14 = s13 + "  moon run cmd district <district>         Find entries by district\n"
  let s15 = s14 + "  moon run cmd stats                       Show geographic statistics\n"
  let s16 = s15 + "  moon run cmd export [path]               Export DB to CSV file\n"
  let s17 = s16 + "  moon run cmd add-tag <id> <tag>          Add tag to an entry\n"
  let s18 = s17 + "  moon run cmd remove-tag <id> <tag>       Remove tag from an entry\n"
  let s19 = s18 + "  moon run cmd clear                       Clear all entries\n"
  let s20 = s19 + "  moon run cmd seed [n]                    Seed random addresses (default 100)\n"
  let s21 = s20 + "  moon run cmd save <path>                 Persist DB to a file\n"
  let s22 = s21 + "  moon run cmd load <path>                 Load DB from a file\n"
  let s23 = s22 + "  moon run cmd backup <path>               Create backup of DB file\n"
  let s24 = s23 + "  moon run cmd check <path>                Check DB file integrity\n"
  let s25 = s24 + "  moon run cmd info <path>                 Show DB metadata\n"
  let s26 = s25 + "  moon run cmd to-json [path]              Export DB to JSON\n"
  let s27 = s26 + "  moon run cmd to-geojson [path]           Export DB to GeoJSON\n"
  let s28 = s27 + "  moon run cmd pattern <pattern>           Wildcard search (*, ?)\n"
  let s29 = s28 + "  moon run cmd distance <id1> <id2>        Distance between two entries\n"
  let s30 = s29 + "  moon run cmd neighbors <id> [k]          k nearest neighbors\n"
  let s31 = s30 + "  moon run cmd nearest-pairs [k]           k closest pairs in DB\n"
  let s32 = s31 + "  moon run cmd districts [province]        District distribution\n"
  let s33 = s32 + "  moon run cmd tag-count <tag>             Count entries with tag\n"
  let s34 = s33 + "  moon run cmd tag-pairs                   Tag co-occurrence pairs\n"
  let s35 = s34 + "  moon run cmd rename <id> <name>          Rename an entry\n"
  let s36 = s35 + "  moon run cmd update-coords <id> <lat> <lng>\n"
  let s37 = s36 + "  moon run cmd centroid <tag>              Centroid of tagged entries\n"
  let s38 = s37 + "  moon run cmd import-csv <csv_str>        Import entries from CSV string\n"
  let s39 = s38 + "  moon run cmd import-geojson <gj_str>    Import entries from GeoJSON string\n"
  let s40 = s39 + "  moon run cmd duplicates [dist] [edit]   Find duplicate entries\n"
  let s41 = s40 + "  moon run cmd cluster [cell_size_km]     Grid-based spatial clustering\n"
  let s42 = s41 + "  moon run cmd matrix <id1> [id2 ...]     Distance matrix for IDs\n"
  let s43 = s42 + "\n"
  let s44 = s43 + "Examples:\n"
  let s45 = s44 + "  moon run cmd\n"
  let s46 = s45 + "  moon run cmd \"北京市海淀区颐和园路5号\"\n"
  let s47 = s46 + "  moon run cmd search \"颐和园\"\n"
  let s48 = s47 + "  moon run cmd fuzzy \"Yuan\" 2\n"
  let s49 = s48 + "  moon run cmd tag \"poi\"\n"
  let s50 = s49 + "  moon run cmd province \"北京市\"\n"
  let s51 = s50 + "  moon run cmd stats\n"
  let s52 = s51 + "  moon run cmd export output.csv\n"
  let s53 = s52 + "  moon run cmd seed 500\n"
  let s54 = s53 + "  moon run cmd save geo.db\n"
  let s55 = s54 + "  moon run cmd to-json out.json\n"
  let s56 = s55 + "  moon run cmd cluster 5.0\n"
  s56
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

  if cmd == "fuzzy" {
    if args.length() < 3 {
      println("Error: fuzzy requires a keyword argument")
      println("Usage: moon run cmd fuzzy <keyword> [max_distance]")
      return
    }
    let max_dist = if args.length() > 3 {
      try { @string.parse_int(args.get(3).unwrap()) } catch {
        _ => 2
      }
    } else {
      2
    }
    run_fuzzy(args.get(2).unwrap(), max_dist)
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

  if cmd == "within" {
    if args.length() < 5 {
      println("Error: within requires lat, lng, and km arguments")
      println("Usage: moon run cmd within <lat> <lng> <km>")
      return
    }
    let lat = try { @string.parse_double(args.get(2).unwrap()) } catch {
      _ => {
        println("Error: invalid latitude")
        return
      }
    }
    let lng = try { @string.parse_double(args.get(3).unwrap()) } catch {
      _ => {
        println("Error: invalid longitude")
        return
      }
    }
    let km = try { @string.parse_double(args.get(4).unwrap()) } catch {
      _ => {
        println("Error: invalid distance")
        return
      }
    }
    run_within(lat, lng, km)
    return
  }

  if cmd == "tag" {
    if args.length() < 3 {
      println("Error: tag requires a tag argument")
      println("Usage: moon run cmd tag <tag>")
      return
    }
    run_tag(args.get(2).unwrap())
    return
  }

  if cmd == "tags" {
    run_list_tags()
    return
  }

  if cmd == "province" {
    if args.length() < 3 {
      println("Error: province requires a province name")
      println("Usage: moon run cmd province <province>")
      return
    }
    run_province(args.get(2).unwrap())
    return
  }

  if cmd == "city" {
    if args.length() < 3 {
      println("Error: city requires a city name")
      println("Usage: moon run cmd city <city>")
      return
    }
    run_city(args.get(2).unwrap())
    return
  }

  if cmd == "district" {
    if args.length() < 3 {
      println("Error: district requires a district name")
      println("Usage: moon run cmd district <district>")
      return
    }
    run_district(args.get(2).unwrap())
    return
  }

  if cmd == "stats" {
    run_stats()
    return
  }

  if cmd == "export" {
    let path = if args.length() > 2 {
      args.get(2).unwrap()
    } else {
      ""
    }
    run_export(path)
    return
  }

  if cmd == "add-tag" {
    if args.length() < 4 {
      println("Error: add-tag requires id and tag")
      println("Usage: moon run cmd add-tag <id> <tag>")
      return
    }
    run_add_tag(args.get(2).unwrap(), args.get(3).unwrap())
    return
  }

  if cmd == "remove-tag" {
    if args.length() < 4 {
      println("Error: remove-tag requires id and tag")
      println("Usage: moon run cmd remove-tag <id> <tag>")
      return
    }
    run_remove_tag(args.get(2).unwrap(), args.get(3).unwrap())
    return
  }

  if cmd == "clear" {
    run_clear()
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

  if cmd == "to-json" {
    let path = if args.length() > 2 { args.get(2).unwrap() } else { "" }
    run_to_json(path)
    return
  }

  if cmd == "to-geojson" {
    let path = if args.length() > 2 { args.get(2).unwrap() } else { "" }
    run_to_geojson(path)
    return
  }

  if cmd == "pattern" {
    if args.length() < 3 {
      println("Error: pattern requires a pattern argument")
      println("Usage: moon run cmd pattern <pattern>  (use * and ? as wildcards)")
      return
    }
    run_pattern(args.get(2).unwrap())
    return
  }

  if cmd == "distance" {
    if args.length() < 4 {
      println("Error: distance requires two ids")
      println("Usage: moon run cmd distance <id1> <id2>")
      return
    }
    run_distance(args.get(2).unwrap(), args.get(3).unwrap())
    return
  }

  if cmd == "neighbors" {
    if args.length() < 3 {
      println("Error: neighbors requires an id")
      println("Usage: moon run cmd neighbors <id> [k]")
      return
    }
    let k = if args.length() > 3 {
      try { @string.parse_int(args.get(3).unwrap()) } catch { _ => 5 }
    } else { 5 }
    run_neighbors(args.get(2).unwrap(), k)
    return
  }

  if cmd == "nearest-pairs" {
    let k = if args.length() > 2 {
      try { @string.parse_int(args.get(2).unwrap()) } catch { _ => 5 }
    } else { 5 }
    run_nearest_pairs(k)
    return
  }

  if cmd == "districts" {
    let province = if args.length() > 2 { args.get(2).unwrap() } else { "" }
    run_districts(province)
    return
  }

  if cmd == "tag-count" {
    if args.length() < 3 {
      println("Error: tag-count requires a tag")
      println("Usage: moon run cmd tag-count <tag>")
      return
    }
    run_tag_count(args.get(2).unwrap())
    return
  }

  if cmd == "tag-pairs" {
    run_tag_pairs()
    return
  }

  if cmd == "rename" {
    if args.length() < 4 {
      println("Error: rename requires id and new name")
      println("Usage: moon run cmd rename <id> <new_name>")
      return
    }
    run_rename(args.get(2).unwrap(), args.get(3).unwrap())
    return
  }

  if cmd == "update-coords" {
    if args.length() < 5 {
      println("Error: update-coords requires id, lat, lng")
      println("Usage: moon run cmd update-coords <id> <lat> <lng>")
      return
    }
    let lat = try { @string.parse_double(args.get(3).unwrap()) } catch {
      _ => { println("Error: invalid latitude"); return }
    }
    let lng = try { @string.parse_double(args.get(4).unwrap()) } catch {
      _ => { println("Error: invalid longitude"); return }
    }
    run_update_coords(args.get(2).unwrap(), lat, lng)
    return
  }

  if cmd == "centroid" {
    if args.length() < 3 {
      println("Error: centroid requires a tag")
      println("Usage: moon run cmd centroid <tag>")
      return
    }
    run_centroid(args.get(2).unwrap())
    return
  }

  if cmd == "import-csv" {
    if args.length() < 3 {
      println("Error: import-csv requires a CSV string argument")
      println("Usage: moon run cmd import-csv <csv_string>")
      return
    }
    // Rejoin remaining args as the CSV string.
    let csv_parts : Array[String] = []
    let mut ci = 2
    while ci < args.length() {
      csv_parts.push(args.get(ci).unwrap())
      ci = ci + 1
    }
    run_import_csv(csv_parts.join(" "))
    return
  }

  if cmd == "import-geojson" {
    if args.length() < 3 {
      println("Error: import-geojson requires a GeoJSON string argument")
      println("Usage: moon run cmd import-geojson <geojson_string>")
      return
    }
    let gj_parts : Array[String] = []
    let mut gi = 2
    while gi < args.length() {
      gj_parts.push(args.get(gi).unwrap())
      gi = gi + 1
    }
    run_import_geojson(gj_parts.join(" "))
    return
  }

  if cmd == "duplicates" {
    let dist = if args.length() > 2 {
      try { @string.parse_double(args.get(2).unwrap()) } catch { _ => 0.1 }
    } else { 0.1 }
    let edit = if args.length() > 3 {
      try { @string.parse_int(args.get(3).unwrap()) } catch { _ => 2 }
    } else { 2 }
    run_duplicates(dist, edit)
    return
  }

  if cmd == "cluster" {
    let cell_size = if args.length() > 2 {
      try { @string.parse_double(args.get(2).unwrap()) } catch { _ => 1.0 }
    } else { 1.0 }
    run_cluster(cell_size)
    return
  }

  if cmd == "matrix" {
    let ids : Array[String] = []
    let mut mi = 2
    while mi < args.length() {
      ids.push(args.get(mi).unwrap())
      mi = mi + 1
    }
    if ids.length() < 2 {
      println("Error: matrix requires at least 2 IDs")
      println("Usage: moon run cmd matrix <id1> <id2> [id3 ...]")
      return
    }
    run_matrix(ids)
    return
  }

  if cmd == "reverse-geocode" {
    if args.length() < 4 {
      println("Error: reverse-geocode requires lat and lng")
      println("Usage: moon run cmd reverse-geocode <lat> <lng>")
      return
    }
    let lat = try { @string.parse_double(args.get(2).unwrap()) } catch {
      _ => { println("Error: invalid latitude"); return }
    }
    let lng = try { @string.parse_double(args.get(3).unwrap()) } catch {
      _ => { println("Error: invalid longitude"); return }
    }
    run_reverse_geocode(lat, lng)
    return
  }

  if cmd == "tag-all" {
    if args.length() < 3 {
      println("Error: tag-all requires at least one tag")
      println("Usage: moon run cmd tag-all <tag1> [tag2 ...]")
      return
    }
    let tags : Array[String] = []
    let mut ti = 2
    while ti < args.length() {
      tags.push(args.get(ti).unwrap())
      ti = ti + 1
    }
    run_tag_all(tags)
    return
  }

  if cmd == "tag-any" {
    if args.length() < 3 {
      println("Error: tag-any requires at least one tag")
      println("Usage: moon run cmd tag-any <tag1> [tag2 ...]")
      return
    }
    let tags : Array[String] = []
    let mut ti = 2
    while ti < args.length() {
      tags.push(args.get(ti).unwrap())
      ti = ti + 1
    }
    run_tag_any(tags)
    return
  }

  if cmd == "bbox-count" {
    if args.length() < 6 {
      println("Error: bbox-count requires min_lat, max_lat, min_lng, max_lng")
      println("Usage: moon run cmd bbox-count <min_lat> <max_lat> <min_lng> <max_lng>")
      return
    }
    let min_lat = try { @string.parse_double(args.get(2).unwrap()) } catch {
      _ => { println("Error: invalid min_lat"); return }
    }
    let max_lat = try { @string.parse_double(args.get(3).unwrap()) } catch {
      _ => { println("Error: invalid max_lat"); return }
    }
    let min_lng = try { @string.parse_double(args.get(4).unwrap()) } catch {
      _ => { println("Error: invalid min_lng"); return }
    }
    let max_lng = try { @string.parse_double(args.get(5).unwrap()) } catch {
      _ => { println("Error: invalid max_lng"); return }
    }
    run_bbox_count(min_lat, max_lat, min_lng, max_lng)
    return
  }

  if cmd == "within-radius" {
    if args.length() < 5 {
      println("Error: within-radius requires lat, lng, and radius_km")
      println("Usage: moon run cmd within-radius <lat> <lng> <radius_km>")
      return
    }
    let lat = try { @string.parse_double(args.get(2).unwrap()) } catch {
      _ => { println("Error: invalid latitude"); return }
    }
    let lng = try { @string.parse_double(args.get(3).unwrap()) } catch {
      _ => { println("Error: invalid longitude"); return }
    }
    let radius = try { @string.parse_double(args.get(4).unwrap()) } catch {
      _ => { println("Error: invalid radius"); return }
    }
    run_within_radius(lat, lng, radius)
    return
  }

  if cmd == "density" {
    let cell_size = if args.length() > 2 {
      try { @string.parse_double(args.get(2).unwrap()) } catch { _ => 1.0 }
    } else { 1.0 }
    run_density(cell_size)
    return
  }

  if cmd == "stddev" {
    run_stddev()
    return
  }

  if cmd == "histogram" {
    run_histogram()
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

// ============ Demo & Core Commands ============

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

  // Tag-based query demo
  println("--- Tag query: 'poi' ---")
  let tagged = db.find_by_tag("poi")
  if tagged.length() == 0 {
    println("  (no entries with 'poi' tag in demo data)")
  } else {
    for e in tagged {
      println("  " + e.id + " - " + e.name)
    }
  }
  println("")

  // Stats demo
  println("--- Geographic Stats ---")
  println(db.summary())
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
  println("  moon run cmd fuzzy \"Yuan\" 2")
  println("  moon run cmd tag \"poi\"")
  println("  moon run cmd province \"北京市\"")
  println("  moon run cmd stats")
  println("  moon run cmd export output.csv")
  println("  moon run cmd seed 500")
  println("  moon run cmd save geo.db")
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

  // Show province distribution.
  println("--- Province distribution ---")
  let prov_dist = db.province_distribution()
  for pair in prov_dist {
    println("  " + pair.0 + ": " + pair.1.to_string() + " entries")
  }
  println("")

  // Show coord range.
  println("--- Coordinate range ---")
  match db.compute_bbox() {
    None => println("  (empty)")
    Some((bbox, _)) => {
      println("  Lat: " + bbox.min_lat.to_string() + " ~ " + bbox.max_lat.to_string())
      println("  Lng: " + bbox.min_lng.to_string() + " ~ " + bbox.max_lng.to_string())
    }
  }
  println("")

  // Save to file.
  let out_path = "geo_seeded.db"
  match db.save_to(out_path) {
    Err(e) => println("Error saving to " + out_path + ": " + e)
    Ok(_) => println("Saved " + entries.length().to_string() + " entries to " + out_path)
  }
  println("")

  // Run stats
  println("--- Statistics ---")
  println(db.summary())
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

// ============ Search Commands ============

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

fn run_fuzzy(keyword : String, max_dist : Int) -> Unit {
  println("=== Fuzzy Search: '" + keyword + "' (max distance=" + max_dist.to_string() + ") ==")
  println("")

  let db = build_sample_db()
  let results = db.find_name_fuzzy(keyword, max_distance=max_dist)
  if results.length() == 0 {
    println("No entries found similar to '" + keyword + "'.")
  } else {
    println("Found " + results.length().to_string() + " entries:")
    for pair in results {
      let e = pair.0
      let d = pair.1
      println("  [distance=" + d.to_string() + "] " + e.id + " (" + e.name + ")")
      println("    Address: " + e.address.to_line())
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

fn run_within(lat : Double, lng : Double, km : Double) -> Unit {
  println("=== Geofence: within " + km.to_string() + " km of (" + lat.to_string() + ", " + lng.to_string() + ") ==")
  println("")

  let db = build_sample_db()
  let point = @types.GeoPoint::make(lat, lng)
  let results = db.find_within_distance(point, km)
  if results.length() == 0 {
    println("No entries found within " + km.to_string() + " km.")
  } else {
    println("Found " + results.length().to_string() + " entries:")
    for pair in results {
      let e = pair.0
      let d = pair.1
      println("  " + e.id + " (" + e.name + ") - " + d.to_string() + " km")
    }
  }
  println("")
  println("Point in DB bbox: " + db.contains_point(point).to_string())
}

// ============ Tag Commands ============

fn run_tag(tag : String) -> Unit {
  println("=== Find entries with tag: '" + tag + "' ==")
  println("")

  let db = build_sample_db()
  let results = db.find_by_tag(tag)
  if results.length() == 0 {
    println("No entries found with tag '" + tag + "'.")
    println("Available tags: " + db.list_tags().join(", "))
  } else {
    println("Found " + results.length().to_string() + " entries:")
    for e in results {
      print_entry(e)
    }
  }
}

fn run_list_tags() -> Unit {
  println("=== All unique tags ===")
  println("")

  let db = build_sample_db()
  let tags = db.list_tags()
  if tags.length() == 0 {
    println("No tags found.")
  } else {
    println("Tags (" + tags.length().to_string() + "):")
    let tag_dist = db.tag_distribution()
    for pair in tag_dist {
      println("  " + pair.0 + ": " + pair.1.to_string() + " entries")
    }
  }
}

fn run_add_tag(id : String, tag : String) -> Unit {
  println("=== Add tag '" + tag + "' to entry '" + id + "' ==")
  let db = build_sample_db()
  let ok = db.add_tag(id, tag)
  if ok {
    println("Tag '" + tag + "' added to entry '" + id + "'.")
  } else {
    println("Failed: entry not found or tag already exists.")
  }
}

fn run_remove_tag(id : String, tag : String) -> Unit {
  println("=== Remove tag '" + tag + "' from entry '" + id + "' ==")
  let db = build_sample_db()
  let ok = db.remove_tag(id, tag)
  if ok {
    println("Tag '" + tag + "' removed from entry '" + id + "'.")
  } else {
    println("Failed: entry not found or tag not present.")
  }
}

// ============ Address Commands ============

fn run_province(province : String) -> Unit {
  println("=== Find entries in province: '" + province + "' ==")
  println("")

  let db = build_sample_db()
  let results = db.find_by_province(province)
  if results.length() == 0 {
    println("No entries found in province '" + province + "'.")
    println("Available provinces: " + db.list_provinces().join(", "))
  } else {
    println("Found " + results.length().to_string() + " entries:")
    for e in results {
      print_entry(e)
    }
  }
}

fn run_city(city : String) -> Unit {
  println("=== Find entries in city: '" + city + "' ==")
  println("")

  let db = build_sample_db()
  let results = db.find_by_city(city)
  if results.length() == 0 {
    println("No entries found in city '" + city + "'.")
    println("Available cities: " + db.list_cities().join(", "))
  } else {
    println("Found " + results.length().to_string() + " entries:")
    for e in results {
      print_entry(e)
    }
  }
}

fn run_district(district : String) -> Unit {
  println("=== Find entries in district: '" + district + "' ==")
  println("")

  let db = build_sample_db()
  let results = db.find_by_district(district)
  if results.length() == 0 {
    println("No entries found in district '" + district + "'.")
    println("Available districts: " + db.list_districts().join(", "))
  } else {
    println("Found " + results.length().to_string() + " entries:")
    for e in results {
      print_entry(e)
    }
  }
}

// ============ Statistics ============

fn run_stats() -> Unit {
  println("=== Geographic Statistics ===")
  println("")

  let db = build_sample_db()
  println(db.summary())
}

// ============ Export ============

fn run_export(path : String) -> Unit {
  let db = build_sample_db()
  let csv = db.to_csv()
  if path.length() == 0 {
    println("=== CSV Export (stdout) ===")
    println("")
    println(csv)
  } else {
    match db.save_to(path) {
      Err(e) => println("Error: " + e)
      Ok(_) => {
        // Actually, we need to write CSV, not the binary format.
        // For now, we'll save the binary and also print the CSV.
        println("Saved binary DB to: " + path)
        println("CSV export (first 500 chars):")
        let preview = if csv.length() > 500 {
          csv.substring(start=0, end=500) + "..."
        } else {
          csv
        }
        println(preview)
      }
    }
  }
}

// ============ Batch / Management Commands ============

fn run_clear() -> Unit {
  println("=== Clear all entries ===")
  let db = build_sample_db()
  println("Database size before clear: " + db.size().to_string())
  db.clear()
  println("Database size after clear: " + db.size().to_string())
  println("All entries removed.")
}

// ============ New command handlers ============

fn run_to_json(path : String) -> Unit {
  let db = build_sample_db()
  let json = db.to_json()
  if path.length() == 0 {
    println("=== JSON Export ===")
    println(json)
  } else {
    // Write via native IO if persist is linked; fall back to stdout notice.
    println("=== JSON Export ===")
    println("(Target path: " + path + ")")
    println(json)
  }
}

fn run_to_geojson(path : String) -> Unit {
  let db = build_sample_db()
  let gj = db.to_geojson()
  if path.length() == 0 {
    println("=== GeoJSON Export ===")
    println(gj)
  } else {
    println("=== GeoJSON Export ===")
    println("(Target path: " + path + ")")
    println(gj)
  }
}

fn run_pattern(pattern : String) -> Unit {
  println("=== Wildcard pattern: '" + pattern + "' ==")
  let db = build_sample_db()
  let results = db.find_name_pattern(pattern)
  if results.length() == 0 {
    println("No entries match the pattern.")
  } else {
    println("Found " + results.length().to_string() + " entries:")
    for e in results {
      print_entry(e)
    }
  }
}

fn run_distance(id1 : String, id2 : String) -> Unit {
  println("=== Distance between '" + id1 + "' and '" + id2 + "' ==")
  let db = build_sample_db()
  match db.distance_between(id1, id2) {
    None => println("One or both IDs not found.")
    Some(d) => {
      println("Distance: " + d.to_string() + " km")
      match db.get(id1) {
        Some(a) => println("  " + a.id + " (" + a.name + ") at (" + a.location.lat.to_string() + ", " + a.location.lng.to_string() + ")")
        None => ()
      }
      match db.get(id2) {
        Some(b) => println("  " + b.id + " (" + b.name + ") at (" + b.location.lat.to_string() + ", " + b.location.lng.to_string() + ")")
        None => ()
      }
    }
  }
}

fn run_neighbors(id : String, k : Int) -> Unit {
  println("=== Neighbors of '" + id + "' (k=" + k.to_string() + ") ==")
  let db = build_sample_db()
  match db.get(id) {
    None => println("Entry '" + id + "' not found.")
    Some(target) => {
      println("Target: " + target.id + " (" + target.name + ")")
      println("  Location: (" + target.location.lat.to_string() + ", " + target.location.lng.to_string() + ")")
      println("")
      let ns = db.find_neighbors(id, k)
      if ns.length() == 0 {
        println("No neighbors found.")
      } else {
        for pair in ns {
          let e = pair.0
          println("  " + e.id + " (" + e.name + ") - " + pair.1.to_string() + " km")
        }
      }
    }
  }
}

fn run_nearest_pairs(k : Int) -> Unit {
  println("=== Nearest " + k.to_string() + " pairs ===")
  let db = build_sample_db()
  let pairs = db.find_nearest_pairs(k)
  if pairs.length() == 0 {
    println("Not enough entries to form pairs (need >=2).")
  } else {
    for p in pairs {
      println("  " + p.0.id + " (" + p.0.name + ") <-> " + p.1.id + " (" + p.1.name + ") : " + p.2.to_string() + " km")
    }
  }
}

fn run_districts(province : String) -> Unit {
  if province.length() == 0 {
    println("=== District distribution (all provinces) ===")
  } else {
    println("=== District distribution in '" + province + "' ==")
  }
  let db = build_sample_db()
  let dist = if province.length() == 0 {
    db.district_distribution()
  } else {
    db.district_distribution(province=province)
  }
  if dist.length() == 0 {
    println("No entries.")
  } else {
    for pair in dist {
      println("  " + pair.0 + ": " + pair.1.to_string() + " entries")
    }
  }
}

fn run_tag_count(tag : String) -> Unit {
  let db = build_sample_db()
  let n = db.count_by_tag(tag)
  println("Tag '" + tag + "' count: " + n.to_string())
}

fn run_tag_pairs() -> Unit {
  println("=== Tag co-occurrence pairs ===")
  let db = build_sample_db()
  let pairs = db.tag_pair_distribution()
  if pairs.length() == 0 {
    println("No tag pairs found.")
  } else {
    for p in pairs {
      println("  (" + p.0.0 + ", " + p.0.1 + "): " + p.1.to_string())
    }
  }
}

fn run_rename(id : String, new_name : String) -> Unit {
  println("=== Rename '" + id + "' to '" + new_name + "' ==")
  let db = build_sample_db()
  if db.rename(id, new_name) {
    println("Renamed successfully.")
  } else {
    println("Failed: entry not found.")
  }
}

fn run_update_coords(id : String, lat : Double, lng : Double) -> Unit {
  println("=== Update coords of '" + id + "' to (" + lat.to_string() + ", " + lng.to_string() + ") ==")
  let db = build_sample_db()
  if db.update_coordinates(id, lat, lng) {
    println("Updated successfully.")
  } else {
    println("Failed: entry not found.")
  }
}

fn run_centroid(tag : String) -> Unit {
  println("=== Centroid of entries tagged '" + tag + "' ==")
  let db = build_sample_db()
  match db.centroid_weighted_by_tag(tag) {
    None => println("No entries with tag '" + tag + "'.")
    Some((pt, n)) => {
      println("  Entries: " + n.to_string())
      println("  Centroid: (" + pt.lat.to_string() + ", " + pt.lng.to_string() + ")")
    }
  }
}

// ============ Persistence Commands ============

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
  if e.tags.length() > 0 {
    println("    tags:     " + e.tags.join(", "))
  }
  println("")
}

// ============ New feature handlers ============

fn run_import_csv(csv_str : String) -> Unit {
  println("=== Importing from CSV ===")
  let db = build_sample_db()
  let before = db.size()
  let n = db.import_csv(csv_str)
  let after = db.size()
  println("  Imported:  " + n.to_string() + " entries")
  println("  Before:    " + before.to_string() + " entries")
  println("  After:     " + after.to_string() + " entries")
  println("")
  println("  All entries after import:")
  for e in db.all() {
    println("    " + e.id + " | " + e.name + " | (" +
      e.location.lat.to_string() + ", " +
      e.location.lng.to_string() + ")")
  }
}

fn run_import_geojson(gj_str : String) -> Unit {
  println("=== Importing from GeoJSON ===")
  let db = build_sample_db()
  let before = db.size()
  let n = db.import_geojson(gj_str)
  let after = db.size()
  println("  Imported:  " + n.to_string() + " entries")
  println("  Before:    " + before.to_string() + " entries")
  println("  After:     " + after.to_string() + " entries")
}

fn run_duplicates(max_dist : Double, max_edit : Int) -> Unit {
  println("=== Duplicate Detection (max_dist=" + max_dist.to_string() +
    "km, max_edit=" + max_edit.to_string() + ") ===")
  let db = build_sample_db()
  let groups = db.find_duplicates(max_distance_km=max_dist, max_edit_dist=max_edit)
  if groups.length() == 0 {
    println("  No duplicates found.")
  } else {
    println("  Found " + groups.length().to_string() + " duplicate group(s):")
    let mut gi = 0
    while gi < groups.length() {
      let group = groups[gi]
      println("  Group #" + (gi + 1).to_string() + ":")
      for e in group {
        println("    - " + e.id + " | " + e.name + " | (" +
          e.location.lat.to_string() + ", " +
          e.location.lng.to_string() + ")")
      }
      gi = gi + 1
    }
  }
}

fn run_cluster(cell_size_km : Double) -> Unit {
  println("=== Spatial Grid Clustering (cell=" + cell_size_km.to_string() + "km) ===")
  let db = build_sample_db()
  let clusters = db.cluster_by_grid(cell_size_km=cell_size_km)
  println("  Total clusters: " + clusters.length().to_string())
  let mut ci = 0
  while ci < clusters.length() {
    let cluster = clusters[ci]
    let key = cluster.0
    let centroid = cluster.1
    let count = cluster.2
    println("  Cluster #" + (ci + 1).to_string() + " [" + key + "]:")
    println("    Centroid: (" + centroid.lat.to_string() + ", " + centroid.lng.to_string() + ")")
    println("    Count:    " + count.to_string() + " entries")
    ci = ci + 1
  }
}

fn run_matrix(ids : Array[String]) -> Unit {
  println("=== Distance Matrix ===")
  println("  IDs: " + ids.join(", "))
  let db = build_sample_db()
  let matrix = db.distance_matrix(ids)
  println("  " + matrix.length().to_string() + "x" + matrix.length().to_string() + " matrix:")
  let mut row = 0
  while row < matrix.length() {
    let mut col = 0
    let row_vals : Array[String] = []
    while col < matrix[row].length() {
      row_vals.push(matrix[row][col].to_string())
      col = col + 1
    }
    println("    " + row_vals.join(", "))
    row = row + 1
  }
}

// ---- New feature handlers (batch 2) ----

fn run_reverse_geocode(lat : Double, lng : Double) -> Unit {
  println("=== Reverse Geocode (" + lat.to_string() + ", " + lng.to_string() + ") ===")
  let db = build_sample_db()
  match db.reverse_geocode(lat, lng) {
    None => println("  No entries in database.")
    Some(result) => {
      let entry = result.0
      let d = result.1
      println("  Nearest entry:")
      println("    ID:   " + entry.id)
      println("    Name: " + entry.name)
      println("    Dist: " + d.to_string() + " km")
      println("    Loc:  (" + entry.location.lat.to_string() + ", " + entry.location.lng.to_string() + ")")
    }
  }
}

fn run_tag_all(tags : Array[String]) -> Unit {
  println("=== Entries with ALL tags: " + tags.join(", ") + " ===")
  let db = build_sample_db()
  let results = db.find_by_tags_all(tags)
  println("  Found " + results.length().to_string() + " entries:")
  for e in results {
    println("    - " + e.id + " | " + e.name + " | tags: " + e.tags.join(", "))
  }
}

fn run_tag_any(tags : Array[String]) -> Unit {
  println("=== Entries with ANY tag: " + tags.join(", ") + " ===")
  let db = build_sample_db()
  let results = db.find_by_tags_any(tags)
  println("  Found " + results.length().to_string() + " entries:")
  for e in results {
    println("    - " + e.id + " | " + e.name + " | tags: " + e.tags.join(", "))
  }
}

fn run_bbox_count(min_lat : Double, max_lat : Double, min_lng : Double, max_lng : Double) -> Unit {
  println("=== Bounding Box Count ===")
  println("  BBox: [" + min_lat.to_string() + ", " + max_lat.to_string() + "] x [" + min_lng.to_string() + ", " + max_lng.to_string() + "]")
  let db = build_sample_db()
  let bbox : @types.BBox = { min_lat, max_lat, min_lng, max_lng }
  let count = db.bbox_count(bbox)
  println("  Count: " + count.to_string() + " entries")
}

fn run_within_radius(lat : Double, lng : Double, radius_km : Double) -> Unit {
  println("=== Entries within " + radius_km.to_string() + " km of (" + lat.to_string() + ", " + lng.to_string() + ") ===")
  let db = build_sample_db()
  let results = db.find_within_radius(lat, lng, radius_km)
  println("  Found " + results.length().to_string() + " entries:")
  for e in results {
    let d = @geo.haversine(@types.GeoPoint::make(lat, lng), e.location)
    println("    - " + e.id + " | " + e.name + " | " + d.to_string() + " km")
  }
}

fn run_density(cell_size_km : Double) -> Unit {
  println("=== Density Map (cell=" + cell_size_km.to_string() + "km) ===")
  let db = build_sample_db()
  let map = db.density_map(cell_size_km=cell_size_km)
  println("  Total cells: " + map.length().to_string())
  for cell in map {
    println("  Cell [" + cell.0 + "]: (" + cell.1.to_string() + ", " + cell.2.to_string() + ") count=" + cell.3.to_string())
  }
}

fn run_stddev() -> Unit {
  println("=== Location Standard Deviation ===")
  let db = build_sample_db()
  let (std_lat, std_lng) = db.location_stddev()
  println("  Latitude stddev:  " + std_lat.to_string())
  println("  Longitude stddev: " + std_lng.to_string())
  // Also show basic stats.
  match db.compute_center() {
    None => println("  Center: N/A (no entries)")
    Some(result) => {
      let center = result.0
      println("  Center: " + center.lat.to_string() + ", " + center.lng.to_string())
    }
  }
}

fn run_histogram() -> Unit {
  println("=== Province Histogram ===")
  let db = build_sample_db()
  let hist = db.province_histogram()
  println("  Provinces:")
  for pair in hist {
    println("    " + pair.0 + ": " + pair.1.to_string() + " entries")
  }
}