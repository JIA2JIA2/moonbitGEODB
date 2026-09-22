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

///|
fn build_usage() -> String {
  let s1 = "moonbitGEODB - Geographic Information Database CLI\n"
  let s2 = s1 + "\n"
  let s3 = s2 + "Usage:\n"
  let s4 = s3 +
    "  moon run cmd                             Run the default demo\n"
  let s5 = s4 +
    "  moon run cmd <address>                   Parse and store an address\n"
  let s6 = s5 +
    "  moon run cmd search <keyword>            Search entries by name keyword\n"
  let s7 = s6 +
    "  moon run cmd fuzzy <kw> [max_dist]       Fuzzy search by name (Levenshtein)\n"
  let s8 = s7 +
    "  moon run cmd nearby <lat> <lng> [km]     Find nearby entries (default 5km)\n"
  let s9 = s8 +
    "  moon run cmd within <lat> <lng> <km>     Find entries within distance\n"
  let s10 = s9 +
    "  moon run cmd tag <tag>                   Find entries by tag\n"
  let s11 = s10 +
    "  moon run cmd tags                        List all unique tags\n"
  let s12 = s11 +
    "  moon run cmd province <province>         Find entries by province\n"
  let s13 = s12 +
    "  moon run cmd city <city>                 Find entries by city\n"
  let s14 = s13 +
    "  moon run cmd district <district>         Find entries by district\n"
  let s15 = s14 +
    "  moon run cmd stats                       Show geographic statistics\n"
  let s16 = s15 +
    "  moon run cmd export [path]               Export DB to CSV file\n"
  let s17 = s16 +
    "  moon run cmd add-tag <id> <tag>          Add tag to an entry\n"
  let s18 = s17 +
    "  moon run cmd remove-tag <id> <tag>       Remove tag from an entry\n"
  let s19 = s18 +
    "  moon run cmd clear                       Clear all entries\n"
  let s20 = s19 +
    "  moon run cmd seed [n]                    Seed random addresses (default 100)\n"
  let s21 = s20 +
    "  moon run cmd save <path>                 Persist DB to a file\n"
  let s22 = s21 +
    "  moon run cmd load <path>                 Load DB from a file\n"
  let s23 = s22 +
    "  moon run cmd backup <path>               Create backup of DB file\n"
  let s24 = s23 +
    "  moon run cmd check <path>                Check DB file integrity\n"
  let s25 = s24 +
    "  moon run cmd info <path>                 Show DB metadata\n"
  let s26 = s25 +
    "  moon run cmd to-json [path]              Export DB to JSON\n"
  let s27 = s26 +
    "  moon run cmd to-geojson [path]           Export DB to GeoJSON\n"
  let s28 = s27 +
    "  moon run cmd pattern <pattern>           Wildcard search (*, ?)\n"
  let s29 = s28 +
    "  moon run cmd distance <id1> <id2>        Distance between two entries\n"
  let s30 = s29 +
    "  moon run cmd neighbors <id> [k]          k nearest neighbors\n"
  let s31 = s30 +
    "  moon run cmd nearest-pairs [k]           k closest pairs in DB\n"
  let s32 = s31 +
    "  moon run cmd districts [province]        District distribution\n"
  let s33 = s32 +
    "  moon run cmd tag-count <tag>             Count entries with tag\n"
  let s34 = s33 +
    "  moon run cmd tag-pairs                   Tag co-occurrence pairs\n"
  let s35 = s34 + "  moon run cmd rename <id> <name>          Rename an entry\n"
  let s36 = s35 + "  moon run cmd update-coords <id> <lat> <lng>\n"
  let s37 = s36 +
    "  moon run cmd centroid <tag>              Centroid of tagged entries\n"
  let s38 = s37 +
    "  moon run cmd import-csv <csv_str>        Import entries from CSV string\n"
  let s39 = s38 +
    "  moon run cmd import-geojson <gj_str>    Import entries from GeoJSON string\n"
  let s40 = s39 +
    "  moon run cmd duplicates [dist] [edit]   Find duplicate entries\n"
  let s41 = s40 +
    "  moon run cmd cluster [cell_size_km]     Grid-based spatial clustering\n"
  let s42 = s41 +
    "  moon run cmd matrix <id1> [id2 ...]     Distance matrix for IDs\n"
  let s50 = s42 +
    "  moon run cmd ring-query <lat> <lng> <inner_km> <outer_km>  Ring/buffer-zone query\n"
  let s51 = s50 +
    "  moon run cmd distance-histogram <lat> <lng> <max_km> [bins]\n"
  let s52 = s51 +
    "  moon run cmd coord-histogram <lat|lng> [bins]  Coordinate histogram\n"
  let s53 = s52 +
    "  moon run cmd distance-summary [lat] [lng]  Distance distribution summary\n"
  let s54 = s53 +
    "  moon run cmd nn-range <id> [k]           k nearest neighbors distance range\n"
  let s55 = s54 +
    "  moon run cmd voronoi                     Voronoi diagram of all entries\n"
  let s56 = s55 +
    "  moon run cmd voronoi-cell <id>           Voronoi polygon for a single entry\n"
  let s57 = s56 +
    "  moon run cmd voronoi-neighbors <id>      Voronoi neighbors of an entry\n"
  let s58 = s57 +
    "  moon run cmd morans-i-lat                Global Moran's I on latitude\n"
  let s59 = s58 +
    "  moon run cmd morans-i-lng                Global Moran's I on longitude\n"
  let s60 = s59 +
    "  moon run cmd hotspot-lat                 Getis-Ord Gi* hot/cold spots on latitude\n"
  let s61 = s60 +
    "  moon run cmd hotspot-lng                 Getis-Ord Gi* hot/cold spots on longitude\n"
  let s62 = s61 +
    "  moon run cmd lisa-lat                    Local Moran's I (LISA) on latitude\n"
  let s63 = s62 +
    "  moon run cmd lisa-lng                    Local Moran's I (LISA) on longitude\n"
  let s64 = s63 +
    "  moon run cmd delaunay                    Delaunay triangulation of all entries\n"
  let s65 = s64 +
    "  moon run cmd delaunay-edges              Delaunay edges (unique) of all entries\n"
  let s66 = s65 +
    "  moon run cmd kriging <lat> <lng> [k]     Kriging interpolation at query point\n"
  let s67 = s66 + "\n"
  let s68 = s67 + "Examples:\n"
  let s69 = s68 + "  moon run cmd\n"
  let s70 = s69 + "  moon run cmd \"北京市海淀区颐和园路5号\"\n"
  let s71 = s70 + "  moon run cmd search \"颐和园\"\n"
  let s72 = s71 + "  moon run cmd fuzzy \"Yuan\" 2\n"
  let s73 = s72 + "  moon run cmd tag \"poi\"\n"
  let s74 = s73 + "  moon run cmd province \"北京市\"\n"
  let s75 = s74 + "  moon run cmd stats\n"
  let s76 = s75 + "  moon run cmd export output.csv\n"
  let s77 = s76 + "  moon run cmd seed 500\n"
  let s78 = s77 + "  moon run cmd save geo.db\n"
  let s79 = s78 + "  moon run cmd to-json out.json\n"
  let s80 = s79 + "  moon run cmd cluster 5.0\n"
  let s81 = s80 + "  moon run cmd ring-query 39.9 116.4 1.0 5.0\n"
  let s82 = s81 + "  moon run cmd distance-histogram 39.9 116.4 50.0 10\n"
  let s83 = s82 + "  moon run cmd nn-range bj-yiheyuan 5\n"
  let s84 = s83 + "  moon run cmd morans-i-lat\n"
  let s85 = s84 + "  moon run cmd hotspot-lat\n"
  let s86 = s85 + "  moon run cmd lisa-lat\n"
  let s87 = s86 + "  moon run cmd dbscan 50.0 3\n"
  s87
}

///|
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
      @string.parse_int(args.get(3).unwrap()) catch {
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
    let lat = @string.parse_double(lat_str) catch {
      _ => {
        println("Error: invalid latitude: " + lat_str)
        return
      }
    }
    let lng = @string.parse_double(lng_str) catch {
      _ => {
        println("Error: invalid longitude: " + lng_str)
        return
      }
    }
    let km = if args.length() > 4 {
      @string.parse_double(args.get(4).unwrap()) catch {
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
    let lat = @string.parse_double(args.get(2).unwrap()) catch {
      _ => {
        println("Error: invalid latitude")
        return
      }
    }
    let lng = @string.parse_double(args.get(3).unwrap()) catch {
      _ => {
        println("Error: invalid longitude")
        return
      }
    }
    let km = @string.parse_double(args.get(4).unwrap()) catch {
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
    let path = if args.length() > 2 { args.get(2).unwrap() } else { "" }
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
      @string.parse_int(args.get(2).unwrap()) catch {
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
      println(
        "Usage: moon run cmd pattern <pattern>  (use * and ? as wildcards)",
      )
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
      @string.parse_int(args.get(3).unwrap()) catch {
        _ => 5
      }
    } else {
      5
    }
    run_neighbors(args.get(2).unwrap(), k)
    return
  }

  if cmd == "nearest-pairs" {
    let k = if args.length() > 2 {
      @string.parse_int(args.get(2).unwrap()) catch {
        _ => 5
      }
    } else {
      5
    }
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
    let lat = @string.parse_double(args.get(3).unwrap()) catch {
      _ => {
        println("Error: invalid latitude")
        return
      }
    }
    let lng = @string.parse_double(args.get(4).unwrap()) catch {
      _ => {
        println("Error: invalid longitude")
        return
      }
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
      @string.parse_double(args.get(2).unwrap()) catch {
        _ => 0.1
      }
    } else {
      0.1
    }
    let edit = if args.length() > 3 {
      @string.parse_int(args.get(3).unwrap()) catch {
        _ => 2
      }
    } else {
      2
    }
    run_duplicates(dist, edit)
    return
  }

  if cmd == "cluster" {
    let cell_size = if args.length() > 2 {
      @string.parse_double(args.get(2).unwrap()) catch {
        _ => 1.0
      }
    } else {
      1.0
    }
    run_cluster(cell_size)
    return
  }

  if cmd == "dbscan" {
    let eps = if args.length() > 2 {
      @string.parse_double(args.get(2).unwrap()) catch {
        _ => 50.0
      }
    } else {
      50.0
    }
    let min_points = if args.length() > 3 {
      @string.parse_int(args.get(3).unwrap()) catch {
        _ => 3
      }
    } else {
      3
    }
    run_dbscan(eps, min_points)
    return
  }

  if cmd == "addr-match" {
    if args.length() < 4 {
      println("Error: addr-match requires query and candidate text")
      println("Usage: moon run cmd addr-match <query> <candidate>")
      return
    }
    run_addr_match(args.get(2).unwrap(), args.get(3).unwrap())
    return
  }

  if cmd == "addr-eval" {
    let path = if args.length() > 2 {
      args.get(2).unwrap()
    } else {
      "testdata/data.txt"
    }
    let max_records = if args.length() > 3 {
      @string.parse_int(args.get(3).unwrap()) catch {
        _ => 0
      }
    } else {
      0
    }
    run_addr_eval(path, max_records)
    return
  }

  if cmd == "corpus-db" {
    let n = if args.length() > 2 {
      @string.parse_int(args.get(2).unwrap()) catch {
        _ => 1000
      }
    } else {
      1000
    }
    run_corpus_db(n)
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
    let lat = @string.parse_double(args.get(2).unwrap()) catch {
      _ => {
        println("Error: invalid latitude")
        return
      }
    }
    let lng = @string.parse_double(args.get(3).unwrap()) catch {
      _ => {
        println("Error: invalid longitude")
        return
      }
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
      println(
        "Usage: moon run cmd bbox-count <min_lat> <max_lat> <min_lng> <max_lng>",
      )
      return
    }
    let min_lat = @string.parse_double(args.get(2).unwrap()) catch {
      _ => {
        println("Error: invalid min_lat")
        return
      }
    }
    let max_lat = @string.parse_double(args.get(3).unwrap()) catch {
      _ => {
        println("Error: invalid max_lat")
        return
      }
    }
    let min_lng = @string.parse_double(args.get(4).unwrap()) catch {
      _ => {
        println("Error: invalid min_lng")
        return
      }
    }
    let max_lng = @string.parse_double(args.get(5).unwrap()) catch {
      _ => {
        println("Error: invalid max_lng")
        return
      }
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
    let lat = @string.parse_double(args.get(2).unwrap()) catch {
      _ => {
        println("Error: invalid latitude")
        return
      }
    }
    let lng = @string.parse_double(args.get(3).unwrap()) catch {
      _ => {
        println("Error: invalid longitude")
        return
      }
    }
    let radius = @string.parse_double(args.get(4).unwrap()) catch {
      _ => {
        println("Error: invalid radius")
        return
      }
    }
    run_within_radius(lat, lng, radius)
    return
  }

  if cmd == "density" {
    let cell_size = if args.length() > 2 {
      @string.parse_double(args.get(2).unwrap()) catch {
        _ => 1.0
      }
    } else {
      1.0
    }
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

  if cmd == "ring-query" {
    if args.length() < 6 {
      println("Error: ring-query requires lat, lng, inner_km, outer_km")
      println(
        "Usage: moon run cmd ring-query <lat> <lng> <inner_km> <outer_km>",
      )
      return
    }
    let lat = @string.parse_double(args.get(2).unwrap()) catch {
      _ => {
        println("Error: invalid latitude")
        return
      }
    }
    let lng = @string.parse_double(args.get(3).unwrap()) catch {
      _ => {
        println("Error: invalid longitude")
        return
      }
    }
    let inner = @string.parse_double(args.get(4).unwrap()) catch {
      _ => {
        println("Error: invalid inner radius")
        return
      }
    }
    let outer = @string.parse_double(args.get(5).unwrap()) catch {
      _ => {
        println("Error: invalid outer radius")
        return
      }
    }
    run_ring_query(lat, lng, inner, outer)
    return
  }

  if cmd == "distance-histogram" {
    if args.length() < 6 {
      println("Error: distance-histogram requires lat, lng, max_km, [bins]")
      println(
        "Usage: moon run cmd distance-histogram <lat> <lng> <max_km> [bins]",
      )
      return
    }
    let lat = @string.parse_double(args.get(2).unwrap()) catch {
      _ => {
        println("Error: invalid latitude")
        return
      }
    }
    let lng = @string.parse_double(args.get(3).unwrap()) catch {
      _ => {
        println("Error: invalid longitude")
        return
      }
    }
    let max_km = @string.parse_double(args.get(4).unwrap()) catch {
      _ => {
        println("Error: invalid max distance")
        return
      }
    }
    let bins = if args.length() > 5 {
      @string.parse_int(args.get(5).unwrap()) catch {
        _ => 10
      }
    } else {
      10
    }
    run_distance_histogram(lat, lng, max_km, bins)
    return
  }

  if cmd == "coord-histogram" {
    if args.length() < 3 {
      println("Error: coord-histogram requires 'lat' or 'lng'")
      println("Usage: moon run cmd coord-histogram <lat|lng> [bins]")
      return
    }
    let axis = args.get(2).unwrap()
    let bins = if args.length() > 3 {
      @string.parse_int(args.get(3).unwrap()) catch {
        _ => 10
      }
    } else {
      10
    }
    run_coord_histogram(axis, bins)
    return
  }

  if cmd == "distance-summary" {
    let (lat, lng) = if args.length() >= 4 {
      (
        @string.parse_double(args.get(2).unwrap()) catch {
          _ => 0.0
        },
        @string.parse_double(args.get(3).unwrap()) catch {
          _ => 0.0
        },
      )
    } else {
      (0.0, 0.0)
    }
    run_distance_summary(lat, lng, args.length() >= 4)
    return
  }

  if cmd == "nn-range" {
    if args.length() < 3 {
      println("Error: nn-range requires an id")
      println("Usage: moon run cmd nn-range <id> [k]")
      return
    }
    let k = if args.length() > 3 {
      @string.parse_int(args.get(3).unwrap()) catch {
        _ => 5
      }
    } else {
      5
    }
    run_nn_range(args.get(2).unwrap(), k)
    return
  }

  if cmd == "kmeans" {
    if args.length() < 3 {
      println("Error: kmeans requires k")
      println("Usage: moon run cmd kmeans <k> [max_iter]")
      return
    }
    let k = @string.parse_int(args.get(2).unwrap()) catch {
      _ => {
        println("Error: invalid k value")
        return
      }
    }
    let max_iter = if args.length() > 3 {
      @string.parse_int(args.get(3).unwrap()) catch {
        _ => 100
      }
    } else {
      100
    }
    run_kmeans(k, max_iter)
    return
  }

  if cmd == "elbow" {
    let max_k = if args.length() > 2 {
      @string.parse_int(args.get(2).unwrap()) catch {
        _ => 8
      }
    } else {
      8
    }
    run_elbow(max_k)
    return
  }

  if cmd == "centroid-all" {
    run_all_centroid()
    return
  }

  if cmd == "geographic-center" {
    run_geographic_center()
    return
  }

  if cmd == "bbox-query" {
    if args.length() < 6 {
      println("Error: bbox-query requires min_lat max_lat min_lng max_lng")
      println(
        "Usage: moon run cmd bbox-query <min_lat> <max_lat> <min_lng> <max_lng>",
      )
      return
    }
    let min_lat = @string.parse_double(args.get(2).unwrap()) catch {
      _ => {
        println("Error: invalid min_lat")
        return
      }
    }
    let max_lat = @string.parse_double(args.get(3).unwrap()) catch {
      _ => {
        println("Error: invalid max_lat")
        return
      }
    }
    let min_lng = @string.parse_double(args.get(4).unwrap()) catch {
      _ => {
        println("Error: invalid min_lng")
        return
      }
    }
    let max_lng = @string.parse_double(args.get(5).unwrap()) catch {
      _ => {
        println("Error: invalid max_lng")
        return
      }
    }
    run_bbox_query(min_lat, max_lat, min_lng, max_lng)
    return
  }

  if cmd == "moran-i" {
    run_morans_i()
    return
  }

  if cmd == "sde" {
    run_std_dev_ellipse()
    return
  }

  if cmd == "tsp" {
    if args.length() < 3 {
      println("Error: tsp requires start_id")
      println("Usage: moon run cmd tsp <start_id>")
      return
    }
    run_tsp(args.get(2).unwrap())
    return
  }

  if cmd == "benchmark" {
    let n = if args.length() >= 3 {
      try { @string.parse_int(args.get(2).unwrap()) } catch { _ => 1000 }
    } else {
      1000
    }
    run_benchmark(n)
    return
  }

  if cmd == "tsp-2opt" {
    if args.length() < 3 {
      println("Error: tsp-2opt requires start_id")
      println("Usage: moon run cmd tsp-2opt <start_id>")
      return
    }
    run_tsp_2opt(args.get(2).unwrap())
    return
  }

  if cmd == "idw" {
    if args.length() < 4 {
      println("Error: idw requires lat lng [power]")
      println("Usage: moon run cmd idw <lat> <lng> [power]")
      return
    }
    let power_str = if args.length() >= 5 { args.get(4).unwrap() } else { "2.0" }
    run_idw(args.get(2).unwrap(), args.get(3).unwrap(), power_str)
    return
  }

  if cmd == "concave-hull" {
    if args.length() < 3 {
      println("Error: concave-hull requires alpha")
      println("Usage: moon run cmd concave-hull <alpha>")
      return
    }
    run_concave_hull(args.get(2).unwrap())
    return
  }

  if cmd == "moran-i-knn" {
    run_moran_i_knn()
    return
  }

  if cmd == "demo" {
    run_demo()
    return
  }

  if cmd == "voronoi" {
    run_voronoi()
    return
  }

  if cmd == "voronoi-cell" {
    if args.length() < 3 {
      println("Error: voronoi-cell requires an id")
      println("Usage: moon run cmd voronoi-cell <id>")
      return
    }
    run_voronoi_cell(args.get(2).unwrap())
    return
  }

  if cmd == "voronoi-neighbors" {
    if args.length() < 3 {
      println("Error: voronoi-neighbors requires an id")
      println("Usage: moon run cmd voronoi-neighbors <id>")
      return
    }
    run_voronoi_neighbors(args.get(2).unwrap())
    return
  }

  if cmd == "morans-i-lat" {
    run_morans_i_lat()
    return
  }

  if cmd == "morans-i-lng" {
    run_morans_i_lng()
    return
  }

  if cmd == "hotspot-lat" {
    run_hotspot_lat()
    return
  }

  if cmd == "hotspot-lng" {
    run_hotspot_lng()
    return
  }

  if cmd == "lisa-lat" {
    run_lisa_lat()
    return
  }

  if cmd == "lisa-lng" {
    run_lisa_lng()
    return
  }

  if cmd == "delaunay" {
    run_delaunay()
    return
  }

  if cmd == "delaunay-edges" {
    run_delaunay_edges()
    return
  }

  if cmd == "kriging" {
    run_kriging()
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

///|
fn run_demo() -> Unit {
  println("=== moonbitGEODB Demo ===")
  println("")

  let db = build_sample_db()
  println("Database size: " + db.size().to_string())
  println("")

  // Retrieve: by id
  println("--- Retrieve by ID ---")
  match db.get("bj-yiheyuan") {
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

  // Retrieve: nearby
  println("--- Nearby 颐和园 (5km radius) ---")
  let nearby = db.find_nearby(
    @types.GeoPoint::make(39.9999, 116.2755),
    radius_km=5.0,
    limit=5,
  )
  for pair in nearby {
    println(
      "  " + pair.0.id + " (" + pair.0.name + ") - " + pair.1.to_string() + " km",
    )
  }
  println("")

  // K-Means + SDE
  println("--- K-Means (k=3, macro regions) ---")
  let clusters = db.kmeans(3)
  let mut ci = 0
  for cl in clusters {
    ci = ci + 1
    println("  Cluster " + ci.to_string() + ": " + cl.members.length().to_string() + " pts")
    // Cap the member listing at 5 so the demo stays readable.
    let mut mi = 0
    while mi < cl.members.length() && mi < 5 {
      println("    - " + cl.members[mi].name)
      mi = mi + 1
    }
    if cl.members.length() > 5 {
      println("    ... 及另外 " + (cl.members.length() - 5).to_string() + " 个")
    }
  }
  println("")

  // DBSCAN — density-based city clusters, no need to pick k up front.
  println("--- DBSCAN (eps=50km, min_points=3, city-level clusters) ---")
  let dbscan_clusters = db.cluster_dbscan(50.0, 3)
  let mut di = 0
  let mut assigned = 0
  while di < dbscan_clusters.length() {
    let members = dbscan_clusters[di]
    assigned = assigned + members.length()
    let line = "  Cluster #" + (di + 1).to_string() + ": " +
      members.length().to_string() + " POIs"
    println(line)
    di = di + 1
  }
  println(
    "  Total: " + dbscan_clusters.length().to_string() + " clusters, " +
      (db.size() - assigned).to_string() + " noise (far suburbs)",
  )
  println("")

  println("--- Standard Deviation Ellipse ---")
  match db.std_dev_ellipse() {
    None => println("  (Need >= 3 points)")
    Some(sde) => {
      let msg = "  Center (" + sde.center.lat.to_string() + ", " +
        sde.center.lng.to_string() + ")  Semi-major " +
        sde.semi_major_km.to_string() + " km"
      println(msg)
    }
  }
  println("")

  // TSP + 2-opt — start from Beijing for a realistic long-distance tour
  println("--- TSP NN + 2-opt (from bj-gugong, " + db.size().to_string() + " POIs) ---")
  match db.tsp_nearest("bj-gugong") {
    None => println("  (start id not found)")
    Some((_, nn_tot)) => {
      match db.tsp_2opt("bj-gugong") {
        None => ()
        Some((_, opt_tot)) => {
          println("  NN: " + nn_tot.to_string() + " km  2opt: " + opt_tot.to_string() + " km")
          println("  Saved " + (nn_tot - opt_tot).to_string() + " km")
        }
      }
    }
  }
  println("")

  // IDW
  println("--- IDW interpolation at (35N, 115E) ---")
  match db.idw_predict(@types.GeoPoint::make(35.0, 115.0), fn(e) { e.location.lng }) {
    None => println("  (empty DB)")
    Some(v) => println("  Predicted lng: " + v.to_string())
  }
  println("")

  // Concave hull
  println("--- Concave Hull (alpha=1.5) ---")
  let hull = db.concave_hull(1.5)
  println("  Hull vertices: " + hull.length().to_string())
  println("")

  // Kriging interpolation（普通克里金）
  println("--- Kriging Interpolation (35N, 115E) ---")
  let krig_entries = db.all()
  let krig_pts : Array[@types.GeoPoint] = []
  let krig_vals : Array[Double] = []
  for e in krig_entries {
    krig_pts.push(e.location)
    krig_vals.push(e.location.lng)
  }
  let krig_bins = @geo.empirical_variogram(krig_pts, krig_vals, max_lag_km=None, num_lags=10)
  let krig_fit = @geo.fit_variogram(krig_bins)
  println(
    "  Variogram: range=" + krig_fit.range.to_string() +
    " km, sill=" + krig_fit.sill.to_string(),
  )
  match @geo.ordinary_kriging_knn(
    krig_pts,
    krig_vals,
    @types.GeoPoint::make(35.0, 115.0),
    krig_fit,
    k=12,
  ) {
    None => println("  Prediction: (insufficient data)")
    Some(v) => println("  Predicted lng: " + v.to_string() + "°E")
  }
  println("")

  // Parse-only demonstration
  println("--- Parse-only: '广州市天河区珠江新城华夏路16号' ---")
  let addr = @parser.parse_address(
    "广州市天河区珠江新城华夏路16号",
  ) catch {
    _ => @types.Address::empty()
  }
  println("  Province: " + addr.province)
  println("  City:     " + addr.city)
  println("  District: " + addr.district)
  println("  Street:   " + addr.street)
  println("")

  println("Demo complete. Try:")
  println("  moon run cmd benchmark")
  println("  moon run cmd dbscan 50.0 3")
  println("  moon run cmd tsp-2opt bj-gugong")
  println("  moon run cmd kmeans 3")
  println("  moon run cmd idw 35.0 115.0 2.0")
  println("  moon run cmd kriging 35.0 115.0 12")
  println("  moon run cmd concave-hull 1.5")
  println("  moon run cmd moran-i-knn")
}

///|
fn run_seed(n : Int) -> Unit {
  println("=== Seeding " + n.to_string() + " random Chinese addresses ===")
  println("")

  let db = @db.GeoDB::in_memory()

  let entries = @gen.gen_batch(n)
  for e in entries {
    db.insert(e)
  }

  println(
    "Generated " +
    entries.length().to_string() +
    " entries from " +
    @gen.city_count().to_string() +
    " cities.",
  )
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
    println(
      "    lat=" +
      e.location.lat.to_string() +
      ", lng=" +
      e.location.lng.to_string(),
    )
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
      println(
        "  Lat: " + bbox.min_lat.to_string() + " ~ " + bbox.max_lat.to_string(),
      )
      println(
        "  Lng: " + bbox.min_lng.to_string() + " ~ " + bbox.max_lng.to_string(),
      )
    }
  }
  println("")

  // Save to file.
  let out_path = "testdata/geo_seeded.db"
  match db.save_to(out_path) {
    Err(e) => println("Error saving to " + out_path + ": " + e)
    Ok(_) =>
      println(
        "Saved " + entries.length().to_string() + " entries to " + out_path,
      )
  }
  println("")

  // Run stats
  println("--- Statistics ---")
  println(db.summary())
}

///|
fn run_parse_and_store(address_str : String) -> Unit {
  println("=== Parse & Store ===")
  println("Input: " + address_str)
  println("")

  let addr = @parser.parse_address(address_str) catch {
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

///|
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

///|
fn run_fuzzy(keyword : String, max_dist : Int) -> Unit {
  println(
    "=== Fuzzy Search: '" +
    keyword +
    "' (max distance=" +
    max_dist.to_string() +
    ") ==",
  )
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
      println(
        "  [distance=" + d.to_string() + "] " + e.id + " (" + e.name + ")",
      )
      println("    Address: " + e.address.to_line())
    }
  }
}

///|
fn run_nearby(lat : Double, lng : Double, km : Double) -> Unit {
  println("=== Nearby search ==")
  println(
    "Center: (" +
    lat.to_string() +
    ", " +
    lng.to_string() +
    "), radius: " +
    km.to_string() +
    " km",
  )
  println("")

  let db = build_sample_db()
  let results = db.find_nearby(
    @types.GeoPoint::make(lat, lng),
    radius_km=km,
    limit=20,
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
      println(
        "    Location: (" +
        e.location.lat.to_string() +
        ", " +
        e.location.lng.to_string() +
        ")",
      )
    }
  }
}

///|
fn run_within(lat : Double, lng : Double, km : Double) -> Unit {
  println(
    "=== Geofence: within " +
    km.to_string() +
    " km of (" +
    lat.to_string() +
    ", " +
    lng.to_string() +
    ") ==",
  )
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

///|
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

///|
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

///|
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

///|
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

///|
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

///|
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

///|
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

///|
fn run_stats() -> Unit {
  println("=== Geographic Statistics ===")
  println("")

  let db = build_sample_db()
  println(db.summary())
}

// ============ Export ============

///|
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

///|
fn run_clear() -> Unit {
  println("=== Clear all entries ===")
  let db = build_sample_db()
  println("Database size before clear: " + db.size().to_string())
  db.clear()
  println("Database size after clear: " + db.size().to_string())
  println("All entries removed.")
}

// ============ New command handlers ============

///|
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

///|
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

///|
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

///|
fn run_distance(id1 : String, id2 : String) -> Unit {
  println("=== Distance between '" + id1 + "' and '" + id2 + "' ==")
  let db = build_sample_db()
  match db.distance_between(id1, id2) {
    None => println("One or both IDs not found.")
    Some(d) => {
      println("Distance: " + d.to_string() + " km")
      match db.get(id1) {
        Some(a) =>
          println(
            "  " +
            a.id +
            " (" +
            a.name +
            ") at (" +
            a.location.lat.to_string() +
            ", " +
            a.location.lng.to_string() +
            ")",
          )
        None => ()
      }
      match db.get(id2) {
        Some(b) =>
          println(
            "  " +
            b.id +
            " (" +
            b.name +
            ") at (" +
            b.location.lat.to_string() +
            ", " +
            b.location.lng.to_string() +
            ")",
          )
        None => ()
      }
    }
  }
}

///|
fn run_neighbors(id : String, k : Int) -> Unit {
  println("=== Neighbors of '" + id + "' (k=" + k.to_string() + ") ==")
  let db = build_sample_db()
  match db.get(id) {
    None => println("Entry '" + id + "' not found.")
    Some(target) => {
      println("Target: " + target.id + " (" + target.name + ")")
      println(
        "  Location: (" +
        target.location.lat.to_string() +
        ", " +
        target.location.lng.to_string() +
        ")",
      )
      println("")
      let ns = db.find_neighbors(id, k)
      if ns.length() == 0 {
        println("No neighbors found.")
      } else {
        for pair in ns {
          let e = pair.0
          println(
            "  " + e.id + " (" + e.name + ") - " + pair.1.to_string() + " km",
          )
        }
      }
    }
  }
}

///|
fn run_nearest_pairs(k : Int) -> Unit {
  println("=== Nearest " + k.to_string() + " pairs ===")
  let db = build_sample_db()
  let pairs = db.find_nearest_pairs(k)
  if pairs.length() == 0 {
    println("Not enough entries to form pairs (need >=2).")
  } else {
    for p in pairs {
      println(
        "  " +
        p.0.id +
        " (" +
        p.0.name +
        ") <-> " +
        p.1.id +
        " (" +
        p.1.name +
        ") : " +
        p.2.to_string() +
        " km",
      )
    }
  }
}

///|
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
    db.district_distribution(province~)
  }
  if dist.length() == 0 {
    println("No entries.")
  } else {
    for pair in dist {
      println("  " + pair.0 + ": " + pair.1.to_string() + " entries")
    }
  }
}

///|
fn run_tag_count(tag : String) -> Unit {
  let db = build_sample_db()
  let n = db.count_by_tag(tag)
  println("Tag '" + tag + "' count: " + n.to_string())
}

///|
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

///|
fn run_rename(id : String, new_name : String) -> Unit {
  println("=== Rename '" + id + "' to '" + new_name + "' ==")
  let db = build_sample_db()
  if db.rename(id, new_name) {
    println("Renamed successfully.")
  } else {
    println("Failed: entry not found.")
  }
}

///|
fn run_update_coords(id : String, lat : Double, lng : Double) -> Unit {
  println(
    "=== Update coords of '" +
    id +
    "' to (" +
    lat.to_string() +
    ", " +
    lng.to_string() +
    ") ==",
  )
  let db = build_sample_db()
  if db.update_coordinates(id, lat, lng) {
    println("Updated successfully.")
  } else {
    println("Failed: entry not found.")
  }
}

///|
fn run_centroid(tag : String) -> Unit {
  println("=== Centroid of entries tagged '" + tag + "' ==")
  let db = build_sample_db()
  match db.centroid_weighted_by_tag(tag) {
    None => println("No entries with tag '" + tag + "'.")
    Some((pt, n)) => {
      println("  Entries: " + n.to_string())
      println(
        "  Centroid: (" + pt.lat.to_string() + ", " + pt.lng.to_string() + ")",
      )
    }
  }
}

// ============ Persistence Commands ============

///|
fn run_save(path : String) -> Unit {
  println("=== Save to: " + path + " ===")
  let db = build_sample_db()
  match db.save_to(path) {
    Err(e) => println("Error: " + e)
    Ok(_) => println("Saved " + db.size().to_string() + " entries to " + path)
  }
}

///|
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

///|
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

///|
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

///|
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

///|
fn build_sample_db() -> @db.GeoDB {
  let db = @db.GeoDB::in_memory()
  // === 北京 (中心 39.9, 116.4) ===
  ignore(db.insert_raw("bj-gugong", "故宫博物院", 39.9163, 116.3972, "北京市东城区景山前街4号"))
  ignore(db.insert_raw("bj-tiananmen", "天安门广场", 39.9055, 116.3972, "北京市东城区东长安街"))
  ignore(db.insert_raw("bj-tiantan", "天坛公园", 39.8822, 116.4066, "北京市东城区天坛东里"))
  ignore(db.insert_raw("bj-yiheyuan", "颐和园", 39.9999, 116.2755, "北京市海淀区颐和园路5号"))
  ignore(db.insert_raw("bj-bada", "八达岭长城", 40.3587, 116.0214, "北京市延庆区G6京藏高速"))
  ignore(db.insert_raw("bj-niuchao", "国家体育场(鸟巢)", 39.9927, 116.3964, "北京市朝阳区国家体育场南路"))
  ignore(db.insert_raw("bj-shuilih", "国家游泳中心(水立方)", 39.9929, 116.3969, "北京市朝阳区国家体育场北路"))
  ignore(db.insert_raw("bj-museum", "中国国家博物馆", 39.9047, 116.4031, "北京市东城区东长安街16号"))
  ignore(db.insert_raw("bj-wangfujing", "王府井步行街", 39.9148, 116.4108, "北京市东城区王府井大街"))
  ignore(db.insert_raw("bj-sanlitun", "三里屯", 39.9378, 116.4559, "北京市朝阳区三里屯路"))
  ignore(db.insert_raw("bj-798", "798艺术区", 39.9846, 116.5032, "北京市朝阳区酒仙桥路4号"))

  // === 上海 (中心 31.2, 121.5) ===
  ignore(db.insert_raw("sh-lijiazui", "东方明珠塔", 31.2397, 121.4997, "上海市浦东新区陆家嘴世纪大道1号"))
  ignore(db.insert_raw("sh-waitan", "外滩", 31.2397, 121.4905, "上海市黄浦区中山东一路"))
  ignore(db.insert_raw("sh-yuyuan", "豫园", 31.2267, 121.4902, "上海市黄浦区福佑路168号"))
  ignore(db.insert_raw("sh-nanjing", "南京路步行街", 31.2356, 121.4814, "上海市黄浦区南京东路"))
  ignore(db.insert_raw("sh-disney", "上海迪士尼乐园", 31.1440, 121.6570, "上海市浦东新区川沙新镇黄赵路310号"))
  ignore(db.insert_raw("sh-museum", "上海博物馆", 31.2301, 121.4758, "上海市黄浦区人民大道201号"))
  ignore(db.insert_raw("sh-center", "上海中心大厦", 31.2354, 121.5016, "上海市浦东新区银城中路501号"))
  ignore(db.insert_raw("sh-huangpu", "黄浦江游船码头", 31.2370, 121.4890, "上海市黄浦区中山东二路"))

  // === 广州 (中心 23.1, 113.3) ===
  ignore(db.insert_raw("gz-tower", "广州塔", 23.1066, 113.3239, "广州市海珠区阅江西路222号"))
  ignore(db.insert_raw("gz-chenjiaci", "陈家祠", 23.1266, 113.2380, "广州市荔湾区中山七路恩龙里34号"))
  ignore(db.insert_raw("gz-yuexiu", "越秀公园", 23.1321, 113.2566, "广州市越秀区解放北路988号"))
  ignore(db.insert_raw("gz-baiyun", "白云山", 23.1887, 113.3198, "广州市白云区广园中路"))
  ignore(db.insert_raw("gz-shamian", "沙面岛", 23.1057, 113.2382, "广州市荔湾区沙面大街"))

  // === 深圳 (中心 22.5, 114.0) ===
  ignore(db.insert_raw("sz-pingan", "深圳平安金融中心", 22.5431, 114.0579, "深圳市福田区福华三路"))
  ignore(db.insert_raw("sz-shijie", "世界之窗", 22.5399, 113.9728, "深圳市南山区深南大道9037号"))
  ignore(db.insert_raw("sz-huanlegu", "欢乐谷", 22.6147, 113.9747, "深圳市南山区侨城西街18号"))
  ignore(db.insert_raw("sz-lianhua", "莲花山", 22.5424, 114.0582, "深圳市福田区莲花山路"))
  ignore(db.insert_raw("sz-dameisha", "大梅沙海滨公园", 22.6087, 114.3328, "深圳市盐田区梅沙街道"))

  // === 成都 (中心 30.7, 104.1) ===
  ignore(db.insert_raw("cd-kuanzhai", "宽窄巷子", 30.6700, 104.0590, "四川省成都市青羊区金河路口"))
  ignore(db.insert_raw("cd-jinli", "锦里古街", 30.6449, 104.0247, "四川省成都市武侯区武侯祠大街231号"))
  ignore(db.insert_raw("cd-wuhou", "武侯祠", 30.6319, 104.0438, "四川省成都市武侯区武侯祠大街231号"))
  ignore(db.insert_raw("cd-panda", "大熊猫繁育研究基地", 30.7330, 104.1480, "四川省成都市成华区熊猫大道1375号"))
  ignore(db.insert_raw("cd-dujiangyan", "都江堰景区", 30.9918, 103.5764, "四川省成都市都江堰市青城山镇"))

  // === 重庆 (中心 29.6, 106.5) ===
  ignore(db.insert_raw("cq-jiefangbei", "解放碑步行街", 29.5580, 106.5781, "重庆市渝中区解放碑"))
  ignore(db.insert_raw("cq-hongyadong", "洪崖洞", 29.5630, 106.5786, "重庆市渝中区嘉陵江滨江路88号"))
  ignore(db.insert_raw("cq-nanshan", "南山一棵树观景台", 29.5501, 106.5828, "重庆市南岸区龙黄公路"))
  ignore(db.insert_raw("cq-ciqikou", "磁器口古镇", 29.5885, 106.4303, "重庆市沙坪坝区磁器口古镇"))
  ignore(db.insert_raw("cq-wulong", "武隆天生三桥", 29.4033, 107.7867, "重庆市武隆区天生三桥"))

  // === 杭州 (中心 30.2, 120.1) ===
  ignore(db.insert_raw("hz-xihu", "西湖", 30.2590, 120.1348, "浙江省杭州市西湖区"))
  ignore(db.insert_raw("hz-lingyin", "灵隐寺", 30.2403, 120.0992, "浙江省杭州市西湖区灵隐路法云弄1号"))
  ignore(db.insert_raw("hz-xixi", "西溪湿地", 30.2850, 120.0700, "浙江省杭州市西湖区天目山路518号"))
  ignore(db.insert_raw("hz-qiandao", "千岛湖", 29.6088, 119.0215, "浙江省杭州市淳安县千岛湖镇"))

  // === 南京 (中心 32.0, 118.8) ===
  ignore(db.insert_raw("nj-zhongshan", "中山陵", 32.0586, 118.8501, "江苏省南京市玄武区紫金山南麓"))
  ignore(db.insert_raw("nj-fuzimiao", "夫子庙", 32.0210, 118.7880, "江苏省南京市秦淮区夫子庙"))
  ignore(db.insert_raw("nj-museum", "南京博物院", 32.0395, 118.8090, "江苏省南京市玄武区中山东路307号"))

  // === 武汉 (中心 30.5, 114.3) ===
  ignore(db.insert_raw("wh-huanghe", "黄鹤楼", 30.5450, 114.3023, "湖北省武汉市武昌区蛇山西坡"))
  ignore(db.insert_raw("wh-donghu", "东湖风景区", 30.5520, 114.3570, "湖北省武汉市武昌区沿湖大道16号"))
  ignore(db.insert_raw("wh-wuhan", "武汉大学", 30.5320, 114.3630, "湖北省武汉市武昌区珞珈山"))

  // === 西安 (中心 34.2, 108.9) ===
  ignore(db.insert_raw("xa-dayanta", "大雁塔", 34.2238, 108.9650, "陕西省西安市雁塔区大慈恩寺内"))
  ignore(db.insert_raw("xa-bingmayong", "秦始皇兵马俑", 34.3848, 109.2786, "陕西省西安市临潼区秦陵北路"))
  ignore(db.insert_raw("xa-chengqiang", "西安城墙", 34.2636, 108.9410, "陕西省西安市碑林区南大街"))

  // === 天津 (中心 39.1, 117.2) ===
  ignore(db.insert_raw("tj-eye", "天津之眼", 39.1436, 117.0097, "天津市河北区三岔河口永乐桥"))
  ignore(db.insert_raw("tj-guwenhua", "古文化街", 39.1390, 117.1830, "天津市南开区古文化街"))
  ignore(db.insert_raw("tj-wudadao", "五大道", 39.1030, 117.2150, "天津市和平区五大道"))

  // === 青岛 (中心 36.0, 120.3) ===
  ignore(db.insert_raw("qd-zhanqiao", "青岛栈桥", 36.0588, 120.3168, "山东省青岛市市南区太平路12号"))
  ignore(db.insert_raw("qd-laoshan", "崂山", 36.2267, 120.4517, "山东省青岛市崂山区崂山路100号"))
  ignore(db.insert_raw("qd-badaguan", "八大关", 36.0558, 120.3318, "山东省青岛市市南区山海关路"))

  // === 昆明 (中心 25.0, 102.7) ===
  ignore(db.insert_raw("km-dianchi", "滇池", 24.8800, 102.8300, "云南省昆明市西山区"))
  ignore(db.insert_raw("km-cuihu", "翠湖", 25.0392, 102.7053, "云南省昆明市五华区翠湖南路"))
  ignore(db.insert_raw("km-xishan", "西山", 24.8930, 102.6370, "云南省昆明市西山区西山森林公园"))
  db
}

///|
fn print_entry(e : @types.GeoEntry) -> Unit {
  println("  id:       " + e.id)
  println("  name:     " + e.name)
  println(
    "  location: (" +
    e.location.lat.to_string() +
    ", " +
    e.location.lng.to_string() +
    ")",
  )
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

///|
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
    println(
      "    " +
      e.id +
      " | " +
      e.name +
      " | (" +
      e.location.lat.to_string() +
      ", " +
      e.location.lng.to_string() +
      ")",
    )
  }
}

///|
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

///|
fn run_duplicates(max_dist : Double, max_edit : Int) -> Unit {
  println(
    "=== Duplicate Detection (max_dist=" +
    max_dist.to_string() +
    "km, max_edit=" +
    max_edit.to_string() +
    ") ===",
  )
  let db = build_sample_db()
  let groups = db.find_duplicates(
    max_distance_km=max_dist,
    max_edit_dist=max_edit,
  )
  if groups.length() == 0 {
    println("  No duplicates found.")
  } else {
    println("  Found " + groups.length().to_string() + " duplicate group(s):")
    let mut gi = 0
    while gi < groups.length() {
      let group = groups[gi]
      println("  Group #" + (gi + 1).to_string() + ":")
      for e in group {
        println(
          "    - " +
          e.id +
          " | " +
          e.name +
          " | (" +
          e.location.lat.to_string() +
          ", " +
          e.location.lng.to_string() +
          ")",
        )
      }
      gi = gi + 1
    }
  }
}

///|
fn run_cluster(cell_size_km : Double) -> Unit {
  println(
    "=== Spatial Grid Clustering (cell=" + cell_size_km.to_string() + "km) ===",
  )
  let db = build_sample_db()
  let clusters = db.cluster_by_grid(cell_size_km~)
  println("  Total clusters: " + clusters.length().to_string())
  let mut ci = 0
  while ci < clusters.length() {
    let cluster = clusters[ci]
    let key = cluster.0
    let centroid = cluster.1
    let count = cluster.2
    println("  Cluster #" + (ci + 1).to_string() + " [" + key + "]:")
    println(
      "    Centroid: (" +
      centroid.lat.to_string() +
      ", " +
      centroid.lng.to_string() +
      ")",
    )
    println("    Count:    " + count.to_string() + " entries")
    ci = ci + 1
  }
}

///|
fn run_dbscan(eps_km : Double, min_points : Int) -> Unit {
  println(
    "=== DBSCAN (eps=" + eps_km.to_string() + "km, min_points=" +
      min_points.to_string() + ") ===",
  )
  let db = build_sample_db()
  let clusters = db.cluster_dbscan(eps_km, min_points)
  let assigned : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  let mut assigned_count = 0
  let mut ci = 0
  while ci < clusters.length() {
    let cluster = clusters[ci]
    assigned_count = assigned_count + cluster.length()
    println("  Cluster #" + (ci + 1).to_string() + " (" + cluster.length().to_string() +
      " POIs):")
    // Show up to 8 member names per cluster.
    let mut k = 0
    while k < cluster.length() && k < 8 {
      assigned.set(cluster[k], true)
      match db.get(cluster[k]) {
        Some(e) => println("    - " + e.name)
        None => ()
      }
      k = k + 1
    }
    // Mark members past the display cap too, so noise detection is exact.
    while k < cluster.length() {
      assigned.set(cluster[k], true)
      k = k + 1
    }
    if cluster.length() > 8 {
      println("    ... 及另外 " + (cluster.length() - 8).to_string() + " 个")
    }
    ci = ci + 1
  }
  let noise = db.size() - assigned_count
  println("  Clusters: " + clusters.length().to_string() + "  Noise: " + noise.to_string())
  if noise > 0 {
    println("  Noise points:")
    for e in db.all() {
      if not(assigned.contains(e.id)) {
        println("    - " + e.id + " (" + e.name + ")")
      }
    }
    println("  (远郊点，距最近城市中心超过 " + eps_km.to_string() + " km)")
  }
}

///|
fn addr_level_name(l : @parser.MatchLevel) -> String {
  match l {
    @parser.MatchLevel::Exact => "完全匹配"
    @parser.MatchLevel::Partial => "部分匹配"
    @parser.MatchLevel::None => "不匹配"
  }
}

///| Level -> confusion-matrix row index: Exact=0, Partial=1, None=2.
fn addr_level_idx(l : @parser.MatchLevel) -> Int {
  2 - l.rank()
}

///|
fn run_addr_match(query : String, candidate : String) -> Unit {
  println("=== Address match ===")
  println("  query:     " + query)
  println("  candidate: " + candidate)
  let r = @parser.match_address(query, candidate)
  println("  level: " + addr_level_name(r.level))
  println(
    "  score: " + r.score.to_string() + "  dice: " + r.dice.to_string() +
      "  road: " + r.road_recall.to_string() + "  num: " + r.num_recall.to_string(),
  )
}

///|
/// Evaluate the three-level address matcher against the labelled JSONL
/// corpus: prints parse/match timing, throughput, overall agreement and
/// a 3x3 confusion matrix with per-class precision/recall/F1.
fn run_addr_eval(path : String, max_records : Int) -> Unit {
  println("=== Address matcher evaluation: " + path + " ===")
  let content = match @persist.load_text(path) {
    Ok(s) => s
    Err(e) => {
      println("Error: cannot read " + path + ": " + e)
      return
    }
  }

  let t_parse0 = @bench.monotonic_clock_start()
  let records : Array[@parser.AddrMatchRecord] = []
  for line in content.split("\n").collect() {
    if max_records > 0 && records.length() >= max_records {
      break
    }
    match @parser.parse_match_record(line.to_owned()) {
      Some(r) => records.push(r)
      None => ()
    }
  }
  let t_parse = @bench.monotonic_clock_end(t_parse0)

  // confusion[gold][pred], index order Exact=0, Partial=1, None=2.
  let confusion : Array[Array[Int]] = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
  let mut pairs = 0

  let mut agreement = 0
  let t_match0 = @bench.monotonic_clock_start()
  for r in records {
    for c in r.candidates {
      let mr = @parser.match_address(r.query, c.text)
      let pred = mr.level
      let gi = addr_level_idx(c.level)
      let pi = addr_level_idx(pred)
      confusion[gi][pi] = confusion[gi][pi] + 1
      pairs = pairs + 1
      if gi == pi {
        agreement = agreement + 1
      }
    }
  }
  let t_match = @bench.monotonic_clock_end(t_match0)

  println("  Records: " + records.length().to_string() + "  pairs: " + pairs.to_string())
  println("  Parse: " + t_parse.to_string() + " us  Match: " + t_match.to_string() + " us")
  if t_match > 0 {
    let throughput = pairs.to_double() * 1000000.0 / t_match
    println("  Throughput: " + throughput.to_string() + " pairs/s")
  }
  if pairs > 0 {
    let pct = agreement.to_double() * 100.0 / pairs.to_double()
    println("  Agreement: " + pct.to_string() + "% (" + agreement.to_string() + "/" +
      pairs.to_string() + ")")
  }
  println("")
  println("  Confusion matrix (rows = gold, cols = pred):")
  println("                 完全匹配  部分匹配  不匹配")
  let names = ["完全匹配", "部分匹配", "不匹配"]
  let mut gi2 = 0
  while gi2 < 3 {
    let row = confusion[gi2]
    println(
      "  " + names[gi2] + "     " + row[0].to_string() + "       " +
        row[1].to_string() + "       " + row[2].to_string(),
    )
    gi2 = gi2 + 1
  }
  println("")
  println("  Per-class metrics:")
  println("    level      precision  recall     f1")
  let mut k = 0
  while k < 3 {
    let tp = confusion[k][k].to_double()
    let mut fp = 0.0
    let mut fn_ = 0.0
    let mut a = 0
    while a < 3 {
      if a != k {
        fp = fp + confusion[a][k].to_double()
        fn_ = fn_ + confusion[k][a].to_double()
      }
      a = a + 1
    }
    let prec = if tp + fp > 0.0 {
      tp / (tp + fp)
    } else {
      0.0
    }
    let rec = if tp + fn_ > 0.0 {
      tp / (tp + fn_)
    } else {
      0.0
    }
    let f1 = if prec + rec > 0.0 {
      2.0 * prec * rec / (prec + rec)
    } else {
      0.0
    }
    println(
      "    " + names[k] + "   " + (prec * 100.0).to_string() + "%   " +
        (rec * 100.0).to_string() + "%   " + (f1 * 100.0).to_string() + "%",
    )
    k = k + 1
  }
}

///|
/// Build a spatial database from the first N real-address corpus
/// records, persist it to testdata/geo_corpus.db and report its
/// spatial distribution plus a sample address retrieval.
fn run_corpus_db(n : Int) -> Unit {
  let path = "testdata/data.txt"
  println("=== Corpus DB (first " + n.to_string() + " records of " + path + ") ===")
  let content = match @persist.load_text(path) {
    Ok(s) => s
    Err(e) => {
      println("Error: cannot read " + path + ": " + e)
      return
    }
  }
  let records : Array[@parser.AddrMatchRecord] = []
  for line in content.split("\n").collect() {
    if records.length() >= n {
      break
    }
    match @parser.parse_match_record(line.to_owned()) {
      Some(r) => records.push(r)
      None => ()
    }
  }
  let t0 = @bench.monotonic_clock_start()
  let db = @gen.corpus_db(records)
  let t_build = @bench.monotonic_clock_end(t0)
  println("  Built " + db.size().to_string() + " entries in " + t_build.to_string() + " us")
  match db.compute_bbox() {
    Some((bbox, _)) =>
      println(
        "  BBox: (" + bbox.min_lat.to_string() + "," + bbox.min_lng.to_string() +
          ") .. (" + bbox.max_lat.to_string() + "," + bbox.max_lng.to_string() + ")",
      )
    None => ()
  }
  let clusters = db.cluster_dbscan(50.0, 5)
  let mut assigned = 0
  for cl in clusters {
    assigned = assigned + cl.length()
  }
  println(
    "  DBSCAN eps=50km: " + clusters.length().to_string() + " city clusters, " +
      (db.size() - assigned).to_string() + " noise",
  )
  match db.save_to("testdata/geo_corpus.db") {
    Ok(_) => println("  Saved: testdata/geo_corpus.db")
    Err(e) => println("  Save failed: " + e)
  }
  if records.length() > 0 {
    println("")
    println("  Sample retrieval for first query:")
    println("    " + records[0].query)
    let hits = db.match_addresses(records[0].query, limit=3)
    for (e, mr) in hits {
      println("    [" + addr_level_name(mr.level) + " " + mr.score.to_string() + "] " + e.id)
    }
  }
}

///|
fn run_matrix(ids : Array[String]) -> Unit {
  println("=== Distance Matrix ===")
  println("  IDs: " + ids.join(", "))
  let db = build_sample_db()
  let matrix = db.distance_matrix(ids)
  println(
    "  " +
    matrix.length().to_string() +
    "x" +
    matrix.length().to_string() +
    " matrix:",
  )
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

///|
fn run_reverse_geocode(lat : Double, lng : Double) -> Unit {
  println(
    "=== Reverse Geocode (" + lat.to_string() + ", " + lng.to_string() + ") ===",
  )
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
      println(
        "    Loc:  (" +
        entry.location.lat.to_string() +
        ", " +
        entry.location.lng.to_string() +
        ")",
      )
    }
  }
}

///|
fn run_tag_all(tags : Array[String]) -> Unit {
  println("=== Entries with ALL tags: " + tags.join(", ") + " ===")
  let db = build_sample_db()
  let results = db.find_by_tags_all(tags)
  println("  Found " + results.length().to_string() + " entries:")
  for e in results {
    println("    - " + e.id + " | " + e.name + " | tags: " + e.tags.join(", "))
  }
}

///|
fn run_tag_any(tags : Array[String]) -> Unit {
  println("=== Entries with ANY tag: " + tags.join(", ") + " ===")
  let db = build_sample_db()
  let results = db.find_by_tags_any(tags)
  println("  Found " + results.length().to_string() + " entries:")
  for e in results {
    println("    - " + e.id + " | " + e.name + " | tags: " + e.tags.join(", "))
  }
}

///|
fn run_bbox_count(
  min_lat : Double,
  max_lat : Double,
  min_lng : Double,
  max_lng : Double,
) -> Unit {
  println("=== Bounding Box Count ===")
  println(
    "  BBox: [" +
    min_lat.to_string() +
    ", " +
    max_lat.to_string() +
    "] x [" +
    min_lng.to_string() +
    ", " +
    max_lng.to_string() +
    "]",
  )
  let db = build_sample_db()
  let bbox : @types.BBox = { min_lat, max_lat, min_lng, max_lng, }
  let count = db.bbox_count(bbox)
  println("  Count: " + count.to_string() + " entries")
}

///|
fn run_within_radius(lat : Double, lng : Double, radius_km : Double) -> Unit {
  println(
    "=== Entries within " +
    radius_km.to_string() +
    " km of (" +
    lat.to_string() +
    ", " +
    lng.to_string() +
    ") ===",
  )
  let db = build_sample_db()
  let results = db.find_within_radius(lat, lng, radius_km)
  println("  Found " + results.length().to_string() + " entries:")
  for e in results {
    let d = @geo.haversine(@types.GeoPoint::make(lat, lng), e.location)
    println("    - " + e.id + " | " + e.name + " | " + d.to_string() + " km")
  }
}

///|
fn run_density(cell_size_km : Double) -> Unit {
  println("=== Density Map (cell=" + cell_size_km.to_string() + "km) ===")
  let db = build_sample_db()
  let map = db.density_map(cell_size_km~)
  println("  Total cells: " + map.length().to_string())
  for cell in map {
    println(
      "  Cell [" +
      cell.0 +
      "]: (" +
      cell.1.to_string() +
      ", " +
      cell.2.to_string() +
      ") count=" +
      cell.3.to_string(),
    )
  }
}

///|
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
      println(
        "  Center: " + center.lat.to_string() + ", " + center.lng.to_string(),
      )
    }
  }
}

///|
fn run_histogram() -> Unit {
  println("=== Province Histogram ===")
  let db = build_sample_db()
  let hist = db.province_histogram()
  println("  Provinces:")
  for pair in hist {
    println("    " + pair.0 + ": " + pair.1.to_string() + " entries")
  }
}

// ---- New query enhancement handlers ----

///|
fn run_ring_query(
  lat : Double,
  lng : Double,
  inner : Double,
  outer : Double,
) -> Unit {
  println("=== Ring Query ===")
  println("  Center: (" + lat.to_string() + ", " + lng.to_string() + ")")
  println(
    "  Ring: [" + inner.to_string() + " km, " + outer.to_string() + " km]",
  )
  let db = build_sample_db()
  let center = @types.GeoPoint::make(lat, lng)
  let (results, min_d, max_d, mean_d) = db.ring_query_summary(
    center, inner, outer,
  )
  println("")
  if results.length() == 0 {
    println("  No entries found in this ring.")
  } else {
    println("  Found " + results.length().to_string() + " entries:")
    for p in results {
      let e = p.0
      println(
        "    - " + e.id + " | " + e.name + " | " + p.1.to_string() + " km",
      )
    }
    println("")
    println("  Distance summary:")
    println("    Min:  " + min_d.to_string() + " km")
    println("    Max:  " + max_d.to_string() + " km")
    println("    Mean: " + mean_d.to_string() + " km")
  }
}

///|
fn run_distance_histogram(
  lat : Double,
  lng : Double,
  max_km : Double,
  bins : Int,
) -> Unit {
  println("=== Distance Histogram ===")
  println("  Center: (" + lat.to_string() + ", " + lng.to_string() + ")")
  println(
    "  Range: 0 to " + max_km.to_string() + " km, " + bins.to_string() + " bins",
  )
  let db = build_sample_db()
  let center = @types.GeoPoint::make(lat, lng)
  let hist = db.distance_histogram(center, max_km, num_bins=bins)
  println("")
  for bin in hist {
    let start = bin.0
    let end = bin.1
    let count = bin.2
    // ASCII bar
    let bar_len = count
    let mut bar = "|"
    let mut b = 0
    while b < bar_len && b < 50 {
      bar = bar + "#"
      b = b + 1
    }
    println(
      "  [" +
      start.to_string() +
      " - " +
      end.to_string() +
      " km] " +
      count.to_string() +
      bar,
    )
  }
}

///|
fn run_coord_histogram(axis : String, bins : Int) -> Unit {
  let db = build_sample_db()
  let hist = if axis == "lng" || axis == "longitude" {
    println("=== Longitude Histogram (" + bins.to_string() + " bins) ===")
    db.lng_histogram(num_bins=bins)
  } else {
    println("=== Latitude Histogram (" + bins.to_string() + " bins) ===")
    db.lat_histogram(num_bins=bins)
  }
  println("")
  for bin in hist {
    let start = bin.0
    let end = bin.1
    let count = bin.2
    let mut bar = "|"
    let mut b = 0
    while b < count && b < 50 {
      bar = bar + "#"
      b = b + 1
    }
    println(
      "  [" +
      start.to_string() +
      " - " +
      end.to_string() +
      "] " +
      count.to_string() +
      bar,
    )
  }
}

///|
fn run_distance_summary(lat : Double, lng : Double, use_center : Bool) -> Unit {
  println("=== Distance Summary ===")
  let db = build_sample_db()
  if use_center {
    println(
      "  Mode: distances from center (" +
      lat.to_string() +
      ", " +
      lng.to_string() +
      ")",
    )
    let center = @types.GeoPoint::make(lat, lng)
    let (count, min_d, max_d, mean, median) = db.distance_summary(
      center=Some(center),
    )
    println("  Count:  " + count.to_string())
    println("  Min:    " + min_d.to_string() + " km")
    println("  Max:    " + max_d.to_string() + " km")
    println("  Mean:   " + mean.to_string() + " km")
    println("  Median: " + median.to_string() + " km")
  } else {
    println("  Mode: all pairwise distances in DB")
    let (count, min_d, max_d, mean, median) = db.distance_summary(center=None)
    println("  Pairs:  " + count.to_string())
    println("  Min:    " + min_d.to_string() + " km")
    println("  Max:    " + max_d.to_string() + " km")
    println("  Mean:   " + mean.to_string() + " km")
    println("  Median: " + median.to_string() + " km")
  }
}

///|
fn run_nn_range(id : String, k : Int) -> Unit {
  println("=== Nearest-Neighbor Distance Range ===")
  println("  Entry: " + id + ", k=" + k.to_string())
  let db = build_sample_db()
  match db.nearest_neighbors_range(id, k) {
    None => println("  Entry not found or fewer than 2 entries in DB.")
    Some(result) => {
      let (n, min_d, max_d, mean, median) = result
      println("  Neighbors found: " + n.to_string())
      println("  Min distance:    " + min_d.to_string() + " km")
      println("  Max distance:    " + max_d.to_string() + " km")
      println("  Mean distance:   " + mean.to_string() + " km")
      println("  Median distance: " + median.to_string() + " km")
      // Also list the actual neighbors.
      let ns = db.find_neighbors(id, k)
      if ns.length() > 0 {
        println("")
        println("  Top neighbors:")
        for p in ns {
          let e = p.0
          println(
            "    - " + e.id + " | " + e.name + " | " + p.1.to_string() + " km",
          )
        }
      }
    }
  }
}

///|
fn run_voronoi() -> Unit {
  println("=== Voronoi Diagram ===")
  let db = build_sample_db()
  let cells = db.voronoi()
  if cells.length() == 0 {
    println("  No entries in DB.")
    return
  }
  println("  Cells: " + cells.length().to_string())
  for c in cells {
    println(
      "  Cell: (" +
      c.site.lat.to_string() +
      ", " +
      c.site.lng.to_string() +
      ") -> " +
      c.polygon.length().to_string() +
      " vertices",
    )
  }
}

///|
fn run_voronoi_cell(id : String) -> Unit {
  println("=== Voronoi Cell ===")
  println("  Entry: " + id)
  let db = build_sample_db()
  match db.voronoi_cell(id) {
    None => println("  Entry not found or DB has fewer than 2 entries.")
    Some(poly) => {
      println("  Vertices: " + poly.length().to_string())
      for v in poly {
        println("    (" + v.lat.to_string() + ", " + v.lng.to_string() + ")")
      }
    }
  }
}

///|
fn run_voronoi_neighbors(id : String) -> Unit {
  println("=== Voronoi Neighbors ===")
  println("  Entry: " + id)
  let db = build_sample_db()
  match db.voronoi_neighbors(id) {
    None => println("  Entry not found or DB has fewer than 2 entries.")
    Some(neighbors) =>
      if neighbors.length() == 0 {
        println("  No neighbors found.")
      } else {
        println("  Neighbors: " + neighbors.length().to_string())
        for nid in neighbors {
          match db.get(nid) {
            None => ()
            Some(e) => println("    - " + e.id + " | " + e.name)
          }
        }
      }
  }
}

// ---- New handlers: kmeans, elbow, centroid, bbox-query ----

///|
fn run_kmeans(k : Int, max_iter : Int) -> Unit {
  println("=== K-Means Clustering ===")
  println("  k = " + k.to_string() + ", max_iter = " + max_iter.to_string())
  let db = build_sample_db()
  let clusters = db.kmeans(k, max_iter~)
  println("")
  let mut inertia_total = 0.0
  let mut j = 0
  while j < clusters.length() {
    let cl = clusters[j]
    println(
      "  Cluster " +
      cl.id.to_string() +
      " (" +
      cl.members.length().to_string() +
      " members)",
    )
    println(
      "    Center: (" +
      cl.center.lat.to_string() +
      ", " +
      cl.center.lng.to_string() +
      ")",
    )
    for m in cl.members {
      println("      - " + m.id + " | " + m.name)
    }
    j = j + 1
  }
}

///|
fn run_elbow(max_k : Int) -> Unit {
  println("=== Elbow Method (WCSS for k = 1.." + max_k.to_string() + ") ===")
  let db = build_sample_db()
  let values = db.kmeans_elbow(max_k)
  println("")
  for pair in values {
    let k = pair.0
    let wcss = pair.1
    // ASCII bar
    let bar_len = if wcss < 1000000.0 { (wcss / 10000.0).to_int() } else { 0 }
    let mut bar = ""
    let mut b = 0
    while b < bar_len && b < 60 {
      bar = bar + "#"
      b = b + 1
    }
    println(
      "  k=" +
      k.to_string().pad_start(2, ' ') +
      "  inertia=" +
      wcss.to_string() +
      "  |" +
      bar,
    )
  }
}

///|
fn run_all_centroid() -> Unit {
  println("=== Centroid (planar mean) ===")
  let db = build_sample_db()
  let c = db.centroid()
  println("  DB has " + db.all().length().to_string() + " entries")
  println("  Centroid: (" + c.lat.to_string() + ", " + c.lng.to_string() + ")")
  println("")
  let gc = db.geographic_center()
  println("=== Geographic Mean Center (sphere-based) ===")
  println(
    "  Geographic center: (" +
    gc.lat.to_string() +
    ", " +
    gc.lng.to_string() +
    ")",
  )
}

///|
fn run_geographic_center() -> Unit {
  let db = build_sample_db()
  let gc = db.geographic_center()
  println("=== Geographic Mean Center ===")
  println("  DB has " + db.all().length().to_string() + " entries")
  println(
    "  Sphere-based center: (" +
    gc.lat.to_string() +
    ", " +
    gc.lng.to_string() +
    ")",
  )
  let c = db.centroid()
  println(
    "  Planar mean:        (" +
    c.lat.to_string() +
    ", " +
    c.lng.to_string() +
    ")",
  )
  let diff = @geo.haversine(gc, c)
  println("  Difference: " + diff.to_string() + " km")
}

///|
fn run_bbox_query(
  min_lat : Double,
  max_lat : Double,
  min_lng : Double,
  max_lng : Double,
) -> Unit {
  println("=== Bounding Box Query ===")
  println(
    "  Region: lat [" +
    min_lat.to_string() +
    ", " +
    max_lat.to_string() +
    "], lng [" +
    min_lng.to_string() +
    ", " +
    max_lng.to_string() +
    "]",
  )
  let db = build_sample_db()
  let results = db.find_bbox(min_lat, max_lat, min_lng, max_lng)
  println("")
  if results.length() == 0 {
    println("  No entries found in this region.")
  } else {
    println("  Found " + results.length().to_string() + " entries:")
    for e in results {
      println(
        "    - " +
        e.id +
        " | " +
        e.name +
        " | (" +
        e.location.lat.to_string() +
        ", " +
        e.location.lng.to_string() +
        ")",
      )
    }
  }
}

// ---- Moran's I handler ----

///|
fn run_morans_i() -> Unit {
  let db = build_sample_db()
  println("=== Moran's I Spatial Autocorrelation ===")
  let lat_res = db.morans_i_on_lat()
  match lat_res {
    None => println("  (computation failed)")
    Some(r) => {
      println("  Moran's I (on latitude): " + r.index.to_string())
      println("  Expected (random):      " + r.expected.to_string())
      println("  Interpretation:")
      let i = r.index
      if i > 0.3 {
        println("    → Strong positive spatial autocorrelation (clustered)")
      } else if i > 0.1 {
        println("    → Moderate positive spatial autocorrelation")
      } else if i > -0.1 {
        println("    → Near zero: random spatial pattern")
      } else if i > -0.3 {
        println("    → Moderate negative autocorrelation (dispersed)")
      } else {
        println("    → Strong negative autocorrelation")
      }
    }
  }
  let lng_res = db.morans_i_on_lng()
  match lng_res {
    None => ()
    Some(r) => println("  Moran's I (on longitude): " + r.index.to_string())
  }
}

// ---- Standard Deviation Ellipse handler ----

///|
fn run_std_dev_ellipse() -> Unit {
  let db = build_sample_db()
  println("=== Standard Deviation Ellipse ===")
  match db.std_dev_ellipse() {
    None => println("  (computation failed)")
    Some(sde) => {
      println(
        "  Center: (" +
        sde.center.lat.to_string() +
        ", " +
        sde.center.lng.to_string() +
        ")",
      )
      println("  Semi-major axis: " + sde.semi_major_km.to_string() + " km")
      println("  Semi-minor axis: " + sde.semi_minor_km.to_string() + " km")
      println(
        "  Rotation:        " +
        sde.rotation_deg.to_string() +
        "° (" +
        @geo.compass_direction(sde.rotation_deg) +
        ")",
      )
      println("  Area:            " + sde.area_sq_km.to_string() + " sq km")
      println("  Eccentricity:    " + sde.eccentricity.to_string())
      let shape = if sde.eccentricity < 0.3 {
        "roughly circular"
      } else if sde.eccentricity < 0.7 {
        "moderately elongated"
      } else {
        "strongly elongated"
      }
      println("  Shape:           " + shape)
    }
  }
}

// ---- TSP nearest-neighbor handler ----

///|
fn run_tsp(start_id : String) -> Unit {
  let db = build_sample_db()
  println("=== TSP Nearest-Neighbor Route ===")
  println("  Start: " + start_id)
  match db.tsp_nearest(start_id) {
    None => {
      println("  Error: start id not found")
      let all = db.all()
      println("  Available ids:")
      for e in all {
        println("    - " + e.id)
      }
    }
    Some((route, total_km)) => {
      println("  Total distance: " + total_km.to_string() + " km")
      println("  Route (" + route.length().to_string() + " stops):")
      let mut idx = 0
      for stop in route {
        let label = if idx == 0 {
          "START"
        } else if idx == route.length() - 1 {
          "END  "
        } else {
          "     "
        }
        println(
          "    " +
          label +
          "  " +
          stop.entry.id +
          " | " +
          stop.entry.name +
          " | cum=" +
          stop.cum_distance_km.to_string() +
          " km",
        )
        idx = idx + 1
      }
    }
  }
}

///| TSP 2-opt CLI.
fn run_tsp_2opt(start_id : String) -> Unit {
  let db = build_sample_db()
  println("=== TSP: Nearest-Neighbor + 2-opt Improvement ===")
  println("  Start: " + start_id)
  match db.tsp_2opt(start_id) {
    None => {
      println("  Error: start id not found")
    }
    Some((route, total_km)) => {
      // Also compute pure NN route for comparison.
      let nn = db.tsp_nearest(start_id)
      match nn {
        Some((_, nn_total)) => {
          let saved = nn_total - total_km
          let pct = if nn_total > 0.0 { saved / nn_total * 100.0 } else { 0.0 }
          println(
            "  NN total:   " + nn_total.to_string() + " km",
          )
          println(
            "  2-opt total: " + total_km.to_string() + " km",
          )
          println(
            "  Saved:      " + saved.to_string() + " km (" + pct.to_string() + "%)",
          )
        }
        None => ()
      }
      println("  Route (" + route.length().to_string() + " stops):")
      let mut idx = 0
      for stop in route {
        let label = if idx == 0 {
          "START"
        } else if idx == route.length() - 1 {
          "END  "
        } else {
          "     "
        }
        println(
          "    " + label + "  " + stop.entry.id + " | " +
          stop.entry.name + " | cum=" + stop.cum_distance_km.to_string() + " km",
        )
        idx = idx + 1
      }
    }
  }
}

///| IDW interpolation CLI. Predicts longitude at the given (lat, lng)
///| based on sample values distributed across the sample DB. We use the
///| longitude of each entry as the attribute to predict, so a sensible
///| query (lat near Beijing, lng between Beijing and Shanghai) shows
///| interpolation at work.
fn run_idw(lat_str : String, lng_str : String, power_str : String) -> Unit {
  let lat = try { @string.parse_double(lat_str) } catch { _ => 39.9 }
  let lng = try { @string.parse_double(lng_str) } catch { _ => 118.0 }
  let power = try { @string.parse_double(power_str) } catch { _ => 2.0 }
  let db = build_sample_db()
  let q = @types.GeoPoint::make(lat, lng)
  println("=== IDW Inverse Distance Weighting ===")
  println(
    "  Query point: (" + lat.to_string() + "°N, " + lng.to_string() + "°E)",
  )
  println("  Power:       " + power.to_string())
  // Predict longitude attribute.
  match db.idw_predict(q, fn(e) { e.location.lng }, power~) {
    None => println("  No prediction (empty DB)")
    Some(pred_lng) => {
      println("  Predicted longitude: " + pred_lng.to_string() + "°E")
      println(
        "  Distance from query to nearest entry: " +
        find_nearest_dist(db, q).to_string() + " km",
      )
    }
  }
  // Also show KNN version.
  let knn = db.idw_predict_knn(q, 5, fn(e) { e.location.lng }, power~)
  match knn {
    Some(v) => println("  KNN(5) version:      " + v.to_string() + "°E")
    None => ()
  }
}

///| Concave hull CLI.
fn run_concave_hull(alpha_str : String) -> Unit {
  let alpha = try { @string.parse_double(alpha_str) } catch { _ => 1.0 }
  let db = build_sample_db()
  println("=== Concave Hull (Alpha-Shape) ===")
  println("  Alpha: " + alpha.to_string())
  let hull = db.concave_hull(alpha)
  println("  Hull vertices: " + hull.length().to_string())
  for p in hull {
    println(
      "    (" + p.lat.to_string() + "°N, " + p.lng.to_string() + "°E)",
    )
  }
  // Compare with convex hull.
  let entries = db.all()
  let pts : Array[@types.GeoPoint] = []
  for e in entries {
    pts.push(e.location)
  }
  let convex = @geo.convex_hull(pts)
  println("  Convex hull vertices: " + convex.length().to_string())
  println("  (alpha → 0 recovers convex hull; alpha → ∞ tends toward all points)")
}

///| Helper: distance from a query point to the nearest DB entry.
fn find_nearest_dist(db : @db.GeoDB, q : @types.GeoPoint) -> Double {
  let arr = db.find_nearest(q, 1)
  if arr.length() > 0 { arr[0].1 } else { 0.0 }
}

///| Moran's I with KNN weights.
fn run_moran_i_knn() -> Unit {
  let db = build_sample_db()
  println("=== Moran's I (KNN weights, k=8) ===")
  match db.morans_i_knn_on_lat(k=8) {
    None => println("  No result (too few points)")
    Some(r) => {
      println("  I (latitude): " + r.index.to_string())
      let label = if r.index > 0.1 { "clustered" } else if r.index < -0.1 { "dispersed" } else { "random" }
      println("  Pattern:     " + label)
    }
  }
}

// ---- Benchmark ----

///| Simple benchmark: builds a DB of N random entries and times several
///| core queries so we can see the index working at scale.
fn run_benchmark(n : Int) -> Unit {
  let n = if n < 10 { 100 } else { n }
  println("=== Benchmark (N=" + n.to_string() + ") ===")
  // Build
  let t0 = @bench.monotonic_clock_start()
  let db = @gen.gen_db(n)
  let t_build = @bench.monotonic_clock_end(t0)
  println("  Build DB:       " + t_build.to_string() + " us")
  println("  Entries:        " + db.size().to_string())

  // BBox query (over Beijing area)
  let t1 = @bench.monotonic_clock_start()
  let _bbox_res = db.find_bbox(39.0, 40.0, 116.0, 117.0)
  let t_bbox = @bench.monotonic_clock_end(t1)
  println("  BBox query:     " + t_bbox.to_string() + " us")

  // KNN
  let t2 = @bench.monotonic_clock_start()
  let _nn = db.find_nearest(@types.GeoPoint::make(39.9, 116.4), 5)
  let t_nn = @bench.monotonic_clock_end(t2)
  println("  KNN query (k=5): " + t_nn.to_string() + " us")

  // Within radius
  let t3 = @bench.monotonic_clock_start()
  let _within = db.find_within_distance(@types.GeoPoint::make(39.9, 116.4), 100.0)
  let t_within = @bench.monotonic_clock_end(t3)
  println("  Within 100km:   " + t_within.to_string() + " us")

  // K-Means (k=3)
  let t4 = @bench.monotonic_clock_start()
  let _km = db.kmeans(3)
  let t_km = @bench.monotonic_clock_end(t4)
  println("  K-Means (k=3):  " + t_km.to_string() + " us")

  // DBSCAN (eps=50km, min_points=5) — realistic urban clustering scale
  let t5 = @bench.monotonic_clock_start()
  let _dbscan = db.cluster_dbscan(50.0, 5)
  let t_dbscan = @bench.monotonic_clock_end(t5)
  println("  DBSCAN (eps50):  " + t_dbscan.to_string() + " us")

  // TSP 2-opt from first entry
  let t6 = @bench.monotonic_clock_start()
  let _tsp = db.tsp_2opt(db.all()[0].id)
  let t_tsp = @bench.monotonic_clock_end(t6)
  println("  TSP 2-opt:       " + t_tsp.to_string() + " us")

  // Moran's I KNN on latitude
  let t7 = @bench.monotonic_clock_start()
  let _mi = db.morans_i_knn_on_lat(k=8)
  let t_mi = @bench.monotonic_clock_end(t7)
  println("  Moran's I KNN:   " + t_mi.to_string() + " us")

  // Kriging: empirical variogram + model fit + KNN interpolation
  let t8 = @bench.monotonic_clock_start()
  let kpts : Array[@types.GeoPoint] = []
  let kvals : Array[Double] = []
  for e in db.all() {
    kpts.push(e.location)
    kvals.push(e.location.lat)
  }
  let kbins = @geo.empirical_variogram(kpts, kvals, max_lag_km=None, num_lags=10)
  let kfit = @geo.fit_variogram(kbins)
  let _kpred = @geo.ordinary_kriging_knn(
    kpts,
    kvals,
    @types.GeoPoint::make(35.0, 115.0),
    kfit,
    k=12,
  )
  let t_kriging = @bench.monotonic_clock_end(t8)
  println("  Kriging KNN:     " + t_kriging.to_string() + " us")

  println("  ---")
  let us_per_entry = t_build / n.to_double()
  println("  Build per entry: " + us_per_entry.to_string() + " us")
}

// ---- Spatial autocorrelation / hotspot analysis ----

///|
fn run_morans_i_lat() -> Unit {
  let db = build_sample_db()
  println("=== Global Moran's I (Latitude) ===")
  match db.morans_i_on_lat() {
    None => println("  Not enough data or zero variance.")
    Some(r) => {
      println("  Moran's I:    " + r.index.to_string())
      println("  Expected I:   " + r.expected.to_string())
      println("  Observations: " + r.n.to_string())
    }
  }
}

///|
fn run_morans_i_lng() -> Unit {
  let db = build_sample_db()
  println("=== Global Moran's I (Longitude) ===")
  match db.morans_i_on_lng() {
    None => println("  Not enough data or zero variance.")
    Some(r) => {
      println("  Moran's I:    " + r.index.to_string())
      println("  Expected I:   " + r.expected.to_string())
      println("  Observations: " + r.n.to_string())
    }
  }
}

///|
fn run_hotspot_lat() -> Unit {
  let db = build_sample_db()
  println("=== Getis-Ord Gi* Hot/Cold Spots (Latitude) ===")
  let entries = db.all()
  let vals : Array[Double] = []
  for e in entries {
    vals.push(e.location.lat)
  }
  let results = db.getis_ord(vals, k=5, threshold=1.96)
  let mut hot = 0
  let mut cold = 0
  for r in results {
    if r.is_hotspot {
      hot = hot + 1
    }
    if r.is_coldspot {
      cold = cold + 1
    }
  }
  println("  Entries: " + results.length().to_string())
  println("  Hotspots: " + hot.to_string() + "  Coldspots: " + cold.to_string())
  println("  Top hotspots:")
  let sorted : Array[(Double, @geo.GetisResult)] = []
  for r in results {
    if r.is_hotspot || r.is_coldspot {
      sorted.push((r.gi_star.abs(), r))
    }
  }
  sorted.sort_by(fn(a, b) {
    if a.0 < b.0 {
      1
    } else if a.0 > b.0 {
      -1
    } else {
      0
    }
  })
  let mut shown = 0
  for (abs_gi, r) in sorted {
    if shown >= 5 {
      break
    }
    match db.get(entries[r.index].id) {
      None => ()
      Some(e) => {
        let label = if r.is_hotspot { "HOT" } else { "COLD" }
        println(
          "    [" +
          label +
          "] " +
          e.id +
          " | " +
          e.name +
          "  Gi*=" +
          r.gi_star.to_string(),
        )
        shown = shown + 1
      }
    }
  }
}

///|
fn run_hotspot_lng() -> Unit {
  let db = build_sample_db()
  println("=== Getis-Ord Gi* Hot/Cold Spots (Longitude) ===")
  let entries = db.all()
  let vals : Array[Double] = []
  for e in entries {
    vals.push(e.location.lng)
  }
  let results = db.getis_ord(vals, k=5, threshold=1.96)
  let mut hot = 0
  let mut cold = 0
  for r in results {
    if r.is_hotspot {
      hot = hot + 1
    }
    if r.is_coldspot {
      cold = cold + 1
    }
  }
  println("  Entries: " + results.length().to_string())
  println("  Hotspots: " + hot.to_string() + "  Coldspots: " + cold.to_string())
}

///|
fn run_lisa_lat() -> Unit {
  let db = build_sample_db()
  println("=== Local Moran's I (LISA) (Latitude) ===")
  let entries = db.all()
  let vals : Array[Double] = []
  for e in entries {
    vals.push(e.location.lat)
  }
  let results = db.lisa(vals, k=5, threshold=1.96)
  let mut hh = 0
  let mut ll = 0
  let mut hl = 0
  let mut lh = 0
  let mut ns = 0
  for r in results {
    match r.cluster {
      "HH" => hh = hh + 1
      "LL" => ll = ll + 1
      "HL" => hl = hl + 1
      "LH" => lh = lh + 1
      _ => ns = ns + 1
    }
  }
  println("  Entries: " + results.length().to_string())
  println("  HH (high-high): " + hh.to_string())
  println("  LL (low-low):   " + ll.to_string())
  println("  HL (high-low):  " + hl.to_string())
  println("  LH (low-high):  " + lh.to_string())
  println("  NS (not sig):   " + ns.to_string())
}

///|
fn run_lisa_lng() -> Unit {
  let db = build_sample_db()
  println("=== Local Moran's I (LISA) (Longitude) ===")
  let entries = db.all()
  let vals : Array[Double] = []
  for e in entries {
    vals.push(e.location.lng)
  }
  let results = db.lisa(vals, k=5, threshold=1.96)
  let mut hh = 0
  let mut ll = 0
  let mut hl = 0
  let mut lh = 0
  let mut ns = 0
  for r in results {
    match r.cluster {
      "HH" => hh = hh + 1
      "LL" => ll = ll + 1
      "HL" => hl = hl + 1
      "LH" => lh = lh + 1
      _ => ns = ns + 1
    }
  }
  println("  Entries: " + results.length().to_string())
  println("  HH (high-high): " + hh.to_string())
  println("  LL (low-low):   " + ll.to_string())
  println("  HL (high-low):  " + hl.to_string())
  println("  LH (low-high):  " + lh.to_string())
  println("  NS (not sig):   " + ns.to_string())
}

// ---- Delaunay triangulation ----

///|
fn run_delaunay() -> Unit {
  let db = build_sample_db()
  println("=== Delaunay Triangulation ===")
  let entries = db.all()
  let tris = db.delaunay()
  println("  Triangles: " + tris.length().to_string())
  let mut shown = 0
  for t in tris {
    if shown >= 10 {
      break
    }
    if t.a < entries.length() &&
      t.b < entries.length() &&
      t.c < entries.length() {
      let a = entries[t.a]
      let b = entries[t.b]
      let c = entries[t.c]
      println("    (" + a.id + " | " + b.id + " | " + c.id + ")")
      shown = shown + 1
    }
  }
  if tris.length() > shown {
    println("  ... and " + (tris.length() - shown).to_string() + " more")
  }
}

///|
fn run_delaunay_edges() -> Unit {
  let db = build_sample_db()
  println("=== Delaunay Edges ===")
  let entries = db.all()
  let edges = db.delaunay_edges()
  println("  Edges: " + edges.length().to_string())
  let mut shown = 0
  for e in edges {
    if shown >= 15 {
      break
    }
    if e.a < entries.length() && e.b < entries.length() {
      let a = entries[e.a]
      let b = entries[e.b]
      println("    " + a.id + " <-> " + b.id)
      shown = shown + 1
    }
  }
  if edges.length() > shown {
    println("  ... and " + (edges.length() - shown).to_string() + " more")
  }
}
///|
fn run_kriging() -> Unit {
  let db = build_sample_db()
  println("=== Kriging Interpolation ===")
  let entries = db.all()
  if entries.length() < 2 {
    println("  Need at least 2 entries for kriging")
    return
  }
  let args = @env.args()
  let lat_str = if args.length() > 2 { args.get(2).unwrap_or("39.9") } else { "39.9" }
  let lng_str = if args.length() > 3 { args.get(3).unwrap_or("116.4") } else { "116.4" }
  let k_str = if args.length() > 4 { args.get(4).unwrap_or("12") } else { "12" }
  let lat = try { @string.parse_double(lat_str) } catch { _ => 39.9 }
  let lng = try { @string.parse_double(lng_str) } catch { _ => 116.4 }
  let k = try { @string.parse_int(k_str) } catch { _ => 12 }
  let query = @types.GeoPoint::make(lat, lng)
  println("  Query point: (" + lat.to_string() + ", " + lng.to_string() + ")")
  println("  Using k=" + k.to_string() + " nearest neighbors")
  // Build points and values
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  for e in entries {
    pts.push(e.location)
    // Use latitude as the value to interpolate (for demo purposes)
    vals.push(e.location.lat)
  }
  // Compute empirical variogram
  let bins = @geo.empirical_variogram(pts, vals, max_lag_km=None, num_lags=10)
  if bins.length() < 2 {
    println("  Not enough variogram bins")
    return
  }
  // Fit variogram model
  let fitted = @geo.fit_variogram(bins)
  println("  Fitted variogram: nugget=" + fitted.nugget.to_string() +
          ", sill=" + fitted.sill.to_string() +
          ", range=" + fitted.range.to_string() + " km")
  // Kriging prediction
  let pred = @geo.ordinary_kriging_knn(pts, vals, query, fitted, k~)
  match pred {
    None => println("  Prediction: None (insufficient data)")
    Some(v) => println("  Prediction: " + v.to_string())
  }
}
