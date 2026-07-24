// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

fn make_entry(
  id : String,
  name : String,
  lat : Double,
  lng : Double
) -> @types.GeoEntry {
  @types.GeoEntry::make(
    id,
    name,
    @types.Address::empty(),
    @types.GeoPoint::make(lat, lng),
  )
}

test "GeoDB::in_memory starts empty" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.size(), 0)
}

test "GeoDB::insert and get" {
  let db = GeoDB::in_memory()
  let e = make_entry("p01", "Tiananmen", 39.9087, 116.3975)
  db.insert(e)
  @test.assert_eq(db.size(), 1)
  @test.assert_eq(db.get("p01") is Some, true)
  @test.assert_eq(db.get("missing") is None, true)
}

test "GeoDB::remove" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "X", 10.0, 20.0))
  @test.assert_eq(db.remove("p01") is Some, true)
  @test.assert_eq(db.size(), 0)
  @test.assert_eq(db.remove("p01") is None, true)
}

test "GeoDB::insert_raw parses address string" {
  let db = GeoDB::in_memory()
  let e = db.insert_raw(
    "p01",
    "Tiananmen",
    39.9,
    116.4,
    "China,Beijing,Beijing,Dongcheng,Tiananmen,100009",
  )
  @test.assert_eq(e.address.country, "China")
  @test.assert_eq(e.address.city, "Beijing")
}

// ---- Geographic statistics tests ----

fn make_entry_with_addr(
  id : String,
  name : String,
  lat : Double,
  lng : Double,
  province : String,
  city : String,
  district : String,
  tags : Array[String]
) -> @types.GeoEntry {
  let addr : @types.Address = {
    country: "中国",
    province,
    city,
    district,
    street: "",
    postal_code: "",
    detail: "",
  }
  let e = @types.GeoEntry::make(id, name, addr, @types.GeoPoint::make(lat, lng))
  e.tags = tags
  e
}

test "GeoDB::compute_center returns correct center" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 10.0, 20.0))
  db.insert(make_entry("p02", "B", 30.0, 40.0))
  match db.compute_center() {
    None => @test.assert_eq(true, false)
    Some((center, count)) => {
      @test.assert_eq(count, 2)
      // Center should be average: (20, 30)
      @test.assert_eq(center.lat, 20.0)
      @test.assert_eq(center.lng, 30.0)
    }
  }
}

test "GeoDB::compute_center returns None for empty DB" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.compute_center() is None, true)
}

test "GeoDB::compute_bbox returns correct bounds" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 10.0, 20.0))
  db.insert(make_entry("p02", "B", 30.0, 40.0))
  db.insert(make_entry("p03", "C", 5.0, 50.0))
  match db.compute_bbox() {
    None => @test.assert_eq(true, false)
    Some((bbox, count)) => {
      @test.assert_eq(count, 3)
      @test.assert_eq(bbox.min_lat, 5.0)
      @test.assert_eq(bbox.max_lat, 30.0)
      @test.assert_eq(bbox.min_lng, 20.0)
      @test.assert_eq(bbox.max_lng, 50.0)
    }
  }
}

test "GeoDB::compute_max_distance finds farthest pair" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  db.insert(make_entry("p02", "B", 1.0, 1.0))
  db.insert(make_entry("p03", "C", 50.0, 50.0))
  match db.compute_max_distance() {
    None => @test.assert_eq(true, false)
    Some((p1, p2, d)) => {
      // Distance between (0,0) and (50,50) should be farthest
      @test.assert_eq(d > 0.0, true)
      @test.assert_eq(d < 10000.0, true) // sanity check
    }
  }
}

test "GeoDB::compute_max_distance returns None for < 2 entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  @test.assert_eq(db.compute_max_distance() is None, true)
}

test "GeoDB::province_distribution counts correctly" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", []))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "北京市", "北京市", "东城区", []))
  db.insert(make_entry_with_addr("p03", "C", 2.0, 2.0, "上海市", "上海市", "浦东新区", []))
  let dist = db.province_distribution()
  @test.assert_eq(dist.length(), 2)
  // 北京市 should have 2 entries (sorted by count desc)
  @test.assert_eq(dist[0].0, "北京市")
  @test.assert_eq(dist[0].1, 2)
  @test.assert_eq(dist[1].0, "上海市")
  @test.assert_eq(dist[1].1, 1)
}

test "GeoDB::city_distribution counts correctly" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "广东省", "广州市", "天河区", []))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "广东省", "深圳市", "南山区", []))
  db.insert(make_entry_with_addr("p03", "C", 2.0, 2.0, "广东省", "广州市", "越秀区", []))
  let dist = db.city_distribution()
  @test.assert_eq(dist.length(), 2)
  @test.assert_eq(dist[0].0, "广州市")
  @test.assert_eq(dist[0].1, 2)
  @test.assert_eq(dist[1].0, "深圳市")
  @test.assert_eq(dist[1].1, 1)
}

test "GeoDB::city_distribution filtered by province" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "广东省", "广州市", "天河区", []))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "广东省", "深圳市", "南山区", []))
  db.insert(make_entry_with_addr("p03", "C", 2.0, 2.0, "北京市", "北京市", "海淀区", []))
  let dist = db.city_distribution(province="广东省")
  @test.assert_eq(dist.length(), 2)
  let dist2 = db.city_distribution(province="北京市")
  @test.assert_eq(dist2.length(), 1)
}

test "GeoDB::tag_distribution counts correctly" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", ["poi", "landmark"]))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "北京市", "北京市", "东城区", ["poi", "transport"]))
  db.insert(make_entry_with_addr("p03", "C", 2.0, 2.0, "上海市", "上海市", "浦东新区", ["medical"]))
  let dist = db.tag_distribution()
  @test.assert_eq(dist.length(), 4)
  // "poi" should have 2 entries
  @test.assert_eq(dist[0].0, "poi")
  @test.assert_eq(dist[0].1, 2)
  // Others should have 1 each
  @test.assert_eq(dist[1].1, 1)
  @test.assert_eq(dist[2].1, 1)
  @test.assert_eq(dist[3].1, 1)
}

test "GeoDB::summary generates readable output" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 39.9, 116.4, "北京市", "北京市", "海淀区", ["poi"]))
  db.insert(make_entry_with_addr("p02", "B", 31.2, 121.5, "上海市", "上海市", "浦东新区", ["landmark"]))
  let summary = db.summary()
  @test.assert_eq(summary.contains("Geographic Database Summary"), true)
  @test.assert_eq(summary.contains("Total entries: 2"), true)
  @test.assert_eq(summary.contains("Center:"), true)
  @test.assert_eq(summary.contains("Bounding box:"), true)
  @test.assert_eq(summary.contains("Provinces"), true)
  @test.assert_eq(summary.contains("Tags"), true)
}

test "GeoDB::find_by_tag works through DB" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", ["poi", "landmark"]))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "北京市", "北京市", "东城区", ["poi", "transport"]))
  db.insert(make_entry_with_addr("p03", "C", 2.0, 2.0, "上海市", "上海市", "浦东新区", ["medical"]))
  @test.assert_eq(db.find_by_tag("poi").length(), 2)
  @test.assert_eq(db.find_by_tag("medical").length(), 1)
  @test.assert_eq(db.find_by_tag("nonexistent").length(), 0)
}

test "GeoDB::find_by_province works through DB" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", []))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "北京市", "北京市", "东城区", []))
  db.insert(make_entry_with_addr("p03", "C", 2.0, 2.0, "上海市", "上海市", "浦东新区", []))
  @test.assert_eq(db.find_by_province("北京市").length(), 2)
  @test.assert_eq(db.find_by_province("上海市").length(), 1)
  @test.assert_eq(db.find_by_province("nonexistent").length(), 0)
}

test "GeoDB::list_tags lists all unique tags" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", ["zebra", "apple"]))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "北京市", "北京市", "东城区", ["apple", "mango"]))
  let tags = db.list_tags()
  @test.assert_eq(tags.length(), 3)
}

test "GeoDB::list_provinces lists all unique provinces" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", []))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "上海市", "上海市", "浦东新区", []))
  let provinces = db.list_provinces()
  @test.assert_eq(provinces.length(), 2)
}

test "GeoDB::insert_raw parses postal code" {
  let db = GeoDB::in_memory()
  let e = db.insert_raw(
    "p01",
    "Tiananmen",
    39.9,
    116.4,
    "China,Beijing,Beijing,Dongcheng,Tiananmen,100009",
  )
  @test.assert_eq(e.address.postal_code, "100009")
  @test.assert_eq(db.size(), 1)
}

test "GeoDB::insert_raw falls back to empty address on bad input" {
  let db = GeoDB::in_memory()
  let _ = db.insert_raw("p01", "X", 0.0, 0.0, "NoSeparatorHere")
  @test.assert_eq(db.size(), 1)
  match db.get("p01") {
    Some(e) => @test.assert_eq(e.address.country, "")
    None => @test.assert_eq(true, false)
  }
}

test "GeoDB::insert_record_line with full line" {
  let db = GeoDB::in_memory()
  let r = db.insert_record_line("Tiananmen\t39.9087, 116.3975\tChina,Beijing")
  @test.assert_eq(r is Some, true)
  @test.assert_eq(db.size(), 1)
}

test "GeoDB::insert_record_line assigns generated id when empty" {
  let db = GeoDB::in_memory()
  let r = db.insert_record_line("JustAName\t1.0, 2.0")
  match r {
    Some(e) => @test.assert_eq(e.id.length() > 0, true)
    None => @test.assert_eq(true, false)
  }
}

test "GeoDB::insert_record_line returns None on empty line" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.insert_record_line(""), None)
}

test "GeoDB::gen_id is monotonic" {
  let db = GeoDB::in_memory()
  let a = db.gen_id("e")
  let b = db.gen_id("e")
  @test.assert_eq(a == "e0", true)
  @test.assert_eq(b == "e1", true)
}

test "GeoDB::find_by_name" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Tiananmen", 39.9, 116.4))
  db.insert(make_entry("p02", "Shanghai", 31.2, 121.5))
  @test.assert_eq(db.find_by_name("tiananmen").length(), 1)
  @test.assert_eq(db.find_by_name("SHANGHAI").length(), 1)
  @test.assert_eq(db.find_by_name("missing").length(), 0)
}

test "GeoDB::find_name_prefix and contains" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Tiananmen", 39.9, 116.4))
  db.insert(make_entry("p02", "Tianjin", 39.1, 117.2))
  @test.assert_eq(db.find_name_prefix("Tian").length(), 2)
  @test.assert_eq(db.find_name_contains("men").length(), 1)
}

test "GeoDB::find_in_bbox" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9, 116.4))
  db.insert(make_entry("p02", "Shanghai", 31.2, 121.5))
  let bbox : @types.BBox = {
    min_lat: 39.0,
    max_lat: 40.0,
    min_lng: 116.0,
    max_lng: 117.0
  }
  @test.assert_eq(db.find_in_bbox(bbox).length(), 1)
}

test "GeoDB::find_nearby filters by radius" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9042, 116.4074))
  db.insert(make_entry("p02", "Tianjin", 39.0842, 117.2009))
  db.insert(make_entry("p03", "Shanghai", 31.2304, 121.4737))
  let beijing = @types.GeoPoint::make(39.9042, 116.4074)
  // 50 km radius should include Beijing only (Tianjin is ~110 km away).
  let near = db.find_nearby(beijing, radius_km=50.0, limit=10)
  @test.assert_eq(near.length(), 1)
  match near[0] {
    (e, _) => @test.assert_eq(e.id, "p01")
  }
}

test "GeoDB::find_nearby respects limit" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  db.insert(make_entry("p02", "B", 0.001, 0.001))
  db.insert(make_entry("p03", "C", 0.002, 0.002))
  let center = @types.GeoPoint::make(0.0, 0.0)
  let near = db.find_nearby(center, radius_km=100.0, limit=2)
  @test.assert_eq(near.length(), 2)
}

test "GeoDB::find_nearest returns k sorted" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Shanghai", 31.2304, 121.4737))
  db.insert(make_entry("p02", "Tianjin", 39.0842, 117.2009))
  db.insert(make_entry("p03", "Beijing", 39.9042, 116.4074))
  let beijing = @types.GeoPoint::make(39.9042, 116.4074)
  let near = db.find_nearest(beijing, 2)
  @test.assert_eq(near.length(), 2)
  match near[0] {
    (e, d) => {
      @test.assert_eq(e.id, "p03")
      @test.assert_eq(d < 1.0, true)
    }
  }
}

test "GeoDB::to_bytes and from_bytes round-trip" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9042, 116.4074))
  db.insert(make_entry("p02", "Shanghai", 31.2304, 121.4737))
  let bytes = db.to_bytes()
  let db2 = GeoDB::in_memory()
  match db2.from_bytes(bytes) {
    Err(_) => @test.assert_eq(true, false)
    Ok(_) => @test.assert_eq(db2.size(), 2)
  }
}

test "GeoDB::save_to and open round-trip" {
  let path = "/tmp/geodb_test_save_load.db"
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9042, 116.4074))
  db.insert(make_entry("p02", "Shanghai", 31.2304, 121.4737))
  match db.save_to(path) {
    Err(_) => @test.assert_eq(true, false)
    Ok(_) => {
      let db2 = GeoDB::open(path)
      @test.assert_eq(db2.size(), 2)
      @test.assert_eq(db2.get("p01") is Some, true)
      @test.assert_eq(db2.get("p02") is Some, true)
    }
  }
}

test "GeoDB::save without path returns Err" {
  let db = GeoDB::in_memory()
  match db.save() {
    Err(_) => @test.assert_eq(true, true)
    Ok(_) => @test.assert_eq(true, false)
  }
}

test "GeoDB::open on missing file yields empty db" {
  let db = GeoDB::open("/tmp/geodb_does_not_exist_xyz.db")
  @test.assert_eq(db.size(), 0)
}

test "GeoDB::backup and restore round-trip" {
  let path = "/tmp/geodb_test_backup.db"
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9042, 116.4074))
  db.insert(make_entry("p02", "Shanghai", 31.2304, 121.4737))
  match db.save_to(path) {
    Err(_) => @test.assert_eq(true, false)
    Ok(_) => {
      match db.backup() {
        Err(_) => @test.assert_eq(true, false)
        Ok(_) => {
          // Remove an entry, then restore.
          ignore(db.remove("p02"))
          @test.assert_eq(db.size(), 1)
          match db.restore() {
            Err(_) => @test.assert_eq(true, false)
            Ok(_) => {
              @test.assert_eq(db.size(), 2)
              @test.assert_eq(db.get("p01") is Some, true)
              @test.assert_eq(db.get("p02") is Some, true)
            }
          }
        }
      }
    }
  }
}

test "GeoDB::check integrity" {
  let path = "/tmp/geodb_test_check.db"
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9042, 116.4074))
  match db.save_to(path) {
    Err(_) => @test.assert_eq(true, false)
    Ok(_) => {
      match db.check() {
        Err(_) => @test.assert_eq(true, false)
        Ok(meta) => {
          @test.assert_eq(meta.entry_count, 1)
          @test.assert_eq(meta.version, @persist.db_version)
        }
      }
    }
  }
}

test "GeoDB::all returns snapshot" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  let snap = db.all()
  db.insert(make_entry("p02", "B", 1.0, 1.0))
  @test.assert_eq(snap.length(), 1)
  @test.assert_eq(db.size(), 2)
}

// ---- Chinese address: storage + parse + retrieval example ----

test "GeoDB - store, parse, retrieve: 北京市海淀区颐和园路5号" {
  let db = GeoDB::in_memory()
  // Step 1: Insert a record using raw API (triggers address parsing).
  let e = db.insert_raw(
    "summer-palace",
    "颐和园",
    39.9999,
    116.2755,
    "北京市海淀区颐和园路5号",
  )
  // Step 2: Verify parsed address fields.
  @test.assert_eq(e.address.country, "中国")
  @test.assert_eq(e.address.province, "北京市")
  @test.assert_eq(e.address.city, "北京市")
  @test.assert_eq(e.address.district, "海淀区")
  @test.assert_eq(e.address.street, "颐和园路")
  @test.assert_eq(e.address.detail, "5号")
  // Step 3: Verify it's retrievable by id.
  match db.get("summer-palace") {
    Some(found) => {
      @test.assert_eq(found.name, "颐和园")
      @test.assert_eq(found.address.district, "海淀区")
    }
    None => @test.assert_eq(true, false)
  }
  // Step 4: Verify name lookup works.
  let by_name = db.find_by_name("颐和园")
  @test.assert_eq(by_name.length(), 1)
  // Step 5: Verify bbox query works (Beijing area).
  let bbox : @types.BBox = {
    min_lat: 39.0,
    max_lat: 40.5,
    min_lng: 115.5,
    max_lng: 117.0
  }
  let in_bbox = db.find_in_bbox(bbox)
  @test.assert_eq(in_bbox.length(), 1)
  // Step 6: Verify nearby query works (within 5 km of Summer Palace).
  let palace = @types.GeoPoint::make(39.9999, 116.2755)
  let near = db.find_nearby(palace, radius_km=5.0, limit=10)
  @test.assert_eq(near.length(), 1)
}

// ---- Geofence tests ----

test "GeoDB::contains_point checks if point is inside bbox" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 39.9, 116.4))
  db.insert(make_entry("p02", "B", 31.2, 121.5))
  // A point near Beijing should be inside the combined bbox
  @test.assert_eq(db.contains_point(@types.GeoPoint::make(39.9, 116.4)), true)
  // A point far away should be outside
  @test.assert_eq(db.contains_point(@types.GeoPoint::make(0.0, 0.0)), false)
}

test "GeoDB::contains_point returns false for empty DB" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.contains_point(@types.GeoPoint::make(0.0, 0.0)), false)
}

test "GeoDB::find_within_distance returns sorted results" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9042, 116.4074))
  db.insert(make_entry("p02", "Tianjin", 39.0842, 117.2009))
  db.insert(make_entry("p03", "Shanghai", 31.2304, 121.4737))
  let beijing = @types.GeoPoint::make(39.9042, 116.4074)
  // 200 km should include Beijing and Tianjin
  let near = db.find_within_distance(beijing, 200.0)
  @test.assert_eq(near.length(), 2)
  // First result should be Beijing itself (distance ~0)
  match near[0] {
    (e, d) => {
      @test.assert_eq(e.id, "p01")
      @test.assert_eq(d < 1.0, true)
    }
  }
}

test "GeoDB::find_sorted_by_distance returns all sorted" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Shanghai", 31.2304, 121.4737))
  db.insert(make_entry("p02", "Tianjin", 39.0842, 117.2009))
  db.insert(make_entry("p03", "Beijing", 39.9042, 116.4074))
  let beijing = @types.GeoPoint::make(39.9042, 116.4074)
  let sorted = db.find_sorted_by_distance(beijing)
  @test.assert_eq(sorted.length(), 3)
  // First should be Beijing (closest)
  match sorted[0] {
    (e, _) => @test.assert_eq(e.id, "p03")
  }
}

// ---- Fuzzy search tests ----

test "GeoDB::find_name_fuzzy finds similar names" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Tiananmen", 39.9, 116.4))
  db.insert(make_entry("p02", "Shanghai", 31.2, 121.5))
  db.insert(make_entry("p03", "Tianjin", 39.1, 117.2))
  // "Tiananmen" vs "Tiananmen" should be distance 0
  let exact = db.find_name_fuzzy("Tiananmen", max_distance=1)
  @test.assert_eq(exact.length(), 1)
  // "Tiananmn" (missing 'e') should match "Tiananmen" with distance 1
  let fuzzy = db.find_name_fuzzy("Tiananmn", max_distance=2)
  @test.assert_eq(fuzzy.length(), 1)
  // "Shangai" (missing 'h') should match "Shanghai" with distance 1
  let fuzzy2 = db.find_name_fuzzy("Shangai", max_distance=2)
  @test.assert_eq(fuzzy2.length(), 1)
}

test "GeoDB::find_name_fuzzy respects max_distance" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9, 116.4))
  // "Bejing" (distance 1) should match with max_distance=2
  let r1 = db.find_name_fuzzy("Bejing", max_distance=2)
  @test.assert_eq(r1.length(), 1)
  // "Bejing" should NOT match with max_distance=0 or 1
  let r2 = db.find_name_fuzzy("Bejing", max_distance=0)
  @test.assert_eq(r2.length(), 0)
}

test "levenshtein_distance function works correctly" {
  @test.assert_eq(levenshtein_distance("kitten", "sitten"), 1)
  @test.assert_eq(levenshtein_distance("", "abc"), 3)
  @test.assert_eq(levenshtein_distance("abc", ""), 3)
  @test.assert_eq(levenshtein_distance("", ""), 0)
  @test.assert_eq(levenshtein_distance("abc", "abc"), 0)
}

// ---- CSV export tests ----

test "GeoDB::to_csv exports all entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 39.9, 116.4, "北京市", "北京市", "海淀区", ["poi"]))
  db.insert(make_entry_with_addr("p02", "B", 31.2, 121.5, "上海市", "上海市", "浦东新区", ["landmark"]))
  let csv = db.to_csv()
  // Should have header + 2 data rows
  @test.assert_eq(csv.contains("id,name,lat,lng"), true)
  @test.assert_eq(csv.contains("p01"), true)
  @test.assert_eq(csv.contains("p02"), true)
  @test.assert_eq(csv.contains("poi"), true)
  @test.assert_eq(csv.contains("landmark"), true)
}

test "GeoDB::to_csv handles special characters" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "Name,with,commas", 0.0, 0.0, "", "", [], ["tag1;tag2"]))
  let csv = db.to_csv()
  // Fields with commas should be quoted
  @test.assert_eq(csv.contains("\"Name,with,commas\""), true)
}

// ---- Tag management tests ----

test "GeoDB::add_tag adds tag to entry" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi"]))
  @test.assert_eq(db.find_by_tag("landmark").length(), 0)
  let ok = db.add_tag("p01", "landmark")
  @test.assert_eq(ok, true)
  @test.assert_eq(db.find_by_tag("landmark").length(), 1)
  @test.assert_eq(db.find_by_all_tags(["poi", "landmark"]).length(), 1)
}

test "GeoDB::add_tag returns false for existing tag" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi"]))
  let ok = db.add_tag("p01", "POI") // case-insensitive duplicate
  @test.assert_eq(ok, false)
}

test "GeoDB::add_tag returns false for missing entry" {
  let db = GeoDB::in_memory()
  let ok = db.add_tag("nonexistent", "tag")
  @test.assert_eq(ok, false)
}

test "GeoDB::remove_tag removes tag from entry" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi", "landmark"]))
  let ok = db.remove_tag("p01", "poi")
  @test.assert_eq(ok, true)
  @test.assert_eq(db.find_by_tag("poi").length(), 0)
  @test.assert_eq(db.find_by_tag("landmark").length(), 1)
}

test "GeoDB::remove_tag returns false if tag not present" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi"]))
  let ok = db.remove_tag("p01", "nonexistent")
  @test.assert_eq(ok, false)
}

// ---- Batch operation tests ----

test "GeoDB::insert_batch inserts multiple entries" {
  let db = GeoDB::in_memory()
  let entries : Array[@types.GeoEntry] = [
    make_entry("p01", "A", 0.0, 0.0),
    make_entry("p02", "B", 1.0, 1.0),
    make_entry("p03", "C", 2.0, 2.0),
  ]
  let n = db.insert_batch(entries)
  @test.assert_eq(n, 3)
  @test.assert_eq(db.size(), 3)
}

test "GeoDB::remove_batch removes multiple entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  db.insert(make_entry("p02", "B", 1.0, 1.0))
  db.insert(make_entry("p03", "C", 2.0, 2.0))
  let n = db.remove_batch(["p01", "p03", "nonexistent"])
  @test.assert_eq(n, 2)
  @test.assert_eq(db.size(), 1)
  @test.assert_eq(db.get("p02") is Some, true)
}

test "GeoDB::clear removes all entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  db.insert(make_entry("p02", "B", 1.0, 1.0))
  @test.assert_eq(db.size(), 2)
  db.clear()
  @test.assert_eq(db.size(), 0)
}

// ---- Update operation tests ----

test "GeoDB::update_location changes entry location" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  let ok = db.update_location("p01", @types.GeoPoint::make(39.9, 116.4))
  @test.assert_eq(ok, true)
  match db.get("p01") {
    Some(e) => {
      @test.assert_eq(e.location.lat, 39.9)
      @test.assert_eq(e.location.lng, 116.4)
    }
    None => @test.assert_eq(true, false)
  }
}

test "GeoDB::update_name changes entry name" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "OldName", 0.0, 0.0))
  let ok = db.update_name("p01", "NewName")
  @test.assert_eq(ok, true)
  match db.get("p01") {
    Some(e) => @test.assert_eq(e.name, "NewName")
    None => @test.assert_eq(true, false)
  }
  // Name index should be updated
  @test.assert_eq(db.find_by_name("NewName").length(), 1)
  @test.assert_eq(db.find_by_name("OldName").length(), 0)
}

test "GeoDB::update_location returns false for missing entry" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.update_location("missing", @types.GeoPoint::make(0.0, 0.0)), false)
}

// ---- Address query through DB tests ----

test "GeoDB::find_by_city works through DB" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", []))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "广东省", "广州市", "天河区", []))
  @test.assert_eq(db.find_by_city("北京市").length(), 1)
  @test.assert_eq(db.find_by_city("广州市").length(), 1)
  @test.assert_eq(db.find_by_city("nonexistent").length(), 0)
}

test "GeoDB::find_by_district works through DB" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", []))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "北京市", "北京市", "东城区", []))
  @test.assert_eq(db.find_by_district("海淀区").length(), 1)
  @test.assert_eq(db.find_by_district("东城区").length(), 1)
}

test "GeoDB::find_by_province_city compound query" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", []))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "广东省", "广州市", "天河区", []))
  let r = db.find_by_province_city("北京市", "北京市")
  @test.assert_eq(r.length(), 1)
  @test.assert_eq(r[0].id, "p01")
}

test "GeoDB::find_by_all_tags AND logic through DB" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi", "landmark"]))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "", "", [], ["poi"]))
  let r = db.find_by_all_tags(["poi", "landmark"])
  @test.assert_eq(r.length(), 1)
  @test.assert_eq(r[0].id, "p01")
}

test "GeoDB::find_by_any_tags OR logic through DB" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi"]))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "", "", [], ["transport"]))
  let r = db.find_by_any_tags(["poi", "transport"])
  @test.assert_eq(r.length(), 2)
}

test "GeoDB::list_cities and list_districts" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", []))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "广东省", "广州市", "天河区", []))
  let cities = db.list_cities()
  @test.assert_eq(cities.length(), 2)
  let districts = db.list_districts()
  @test.assert_eq(districts.length(), 2)
}

// ---- New feature tests ----

test "GeoDB::to_json round-trip preserves entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 39.9, 116.4, "北京市", "北京市", "海淀区", ["poi"]))
  db.insert(make_entry_with_addr("p02", "B", 31.2, 121.5, "上海市", "上海市", "浦东新区", ["landmark"]))
  let json_str = db.to_json()
  @test.assert_eq(json_str.length() > 0, true)
  // Import into a fresh DB.
  let db2 = GeoDB::in_memory()
  let n = db2.import_json(json_str)
  @test.assert_eq(n, 2)
  @test.assert_eq(db2.size(), 2)
  match db2.get("p01") {
    None => @test.assert_eq(true, false)
    Some(e) => {
      @test.assert_eq(e.name, "A")
      @test.assert_eq(e.location.lat, 39.9)
      @test.assert_eq(e.address.province, "北京市")
    }
  }
}

test "GeoDB::to_json on empty DB returns []" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.to_json(), "[]")
}

test "GeoDB::import_json on empty/empty-array returns 0" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.import_json(""), 0)
  @test.assert_eq(db.import_json("[]"), 0)
}

test "GeoDB::distance_between computes haversine correctly" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 39.9, 116.4))
  db.insert(make_entry("p02", "B", 39.9, 116.4))
  match db.distance_between("p01", "p02") {
    None => @test.assert_eq(true, false)
    Some(d) => @test.assert_eq(d < 0.001, true)
  }
}

test "GeoDB::distance_between with missing id returns None" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 39.9, 116.4))
  @test.assert_eq(db.distance_between("p01", "missing") is None, true)
}

test "GeoDB::find_nearest_pairs returns closest pairs" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  db.insert(make_entry("p02", "B", 0.0, 1.0))
  db.insert(make_entry("p03", "C", 10.0, 10.0))
  let pairs = db.find_nearest_pairs(2)
  @test.assert_eq(pairs.length(), 2)
  // Closest pair should be p01<->p02.
  let closest = pairs[0]
  @test.assert_eq(closest.2 < 200.0, true)
}

test "GeoDB::find_nearest_pairs on empty/singleton returns empty" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.find_nearest_pairs(5).length(), 0)
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  @test.assert_eq(db.find_nearest_pairs(5).length(), 0)
}

test "GeoDB::find_neighbors returns k nearest" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  db.insert(make_entry("p02", "B", 0.0, 1.0))
  db.insert(make_entry("p03", "C", 10.0, 10.0))
  let neighbors = db.find_neighbors("p01", 2)
  @test.assert_eq(neighbors.length(), 2)
  @test.assert_eq(neighbors[0].0.id, "p02")
}

test "GeoDB::find_neighbors with missing id returns empty" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  @test.assert_eq(db.find_neighbors("missing", 5).length(), 0)
}

test "GeoDB::count_by_tag works" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi", "landmark"]))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "", "", [], ["poi"]))
  db.insert(make_entry_with_addr("p03", "C", 2.0, 2.0, "", "", [], ["transport"]))
  @test.assert_eq(db.count_by_tag("poi"), 2)
  @test.assert_eq(db.count_by_tag("landmark"), 1)
  @test.assert_eq(db.count_by_tag("missing"), 0)
}

test "GeoDB::count_by_tag is case-insensitive" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["POI"]))
  @test.assert_eq(db.count_by_tag("poi"), 1)
}

test "GeoDB::district_distribution counts correctly" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", []))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "北京市", "北京市", "海淀区", []))
  db.insert(make_entry_with_addr("p03", "C", 2.0, 2.0, "北京市", "北京市", "东城区", []))
  let dist = db.district_distribution()
  @test.assert_eq(dist.length(), 2)
  // Both sorted by count desc: 海淀区(2) first, 东城区(1) second.
  @test.assert_eq(dist[0].0, "海淀区")
  @test.assert_eq(dist[0].1, 2)
}

test "GeoDB::district_distribution filtered by province" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "北京市", "北京市", "海淀区", []))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "广东省", "广州市", "天河区", []))
  let dist = db.district_distribution(province="北京市")
  @test.assert_eq(dist.length(), 1)
  @test.assert_eq(dist[0].0, "海淀区")
}

test "GeoDB::find_name_pattern supports wildcards" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Apple", 0.0, 0.0))
  db.insert(make_entry("p02", "Application", 1.0, 1.0))
  db.insert(make_entry("p03", "Banana", 2.0, 2.0))
  // * matches any sequence.
  let r1 = db.find_name_pattern("A*")
  @test.assert_eq(r1.length(), 2)
  // ? matches single character.
  let r2 = db.find_name_pattern("Appl?")
  @test.assert_eq(r2.length(), 1)
  @test.assert_eq(r2[0].name, "Apple")
  // Exact literal.
  let r3 = db.find_name_pattern("Banana")
  @test.assert_eq(r3.length(), 1)
}

test "GeoDB::centroid_weighted_by_tag works" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 10.0, 20.0, "", "", [], ["poi"]))
  db.insert(make_entry_with_addr("p02", "B", 30.0, 40.0, "", "", [], ["poi"]))
  match db.centroid_weighted_by_tag("poi") {
    None => @test.assert_eq(true, false)
    Some((pt, n)) => {
      @test.assert_eq(n, 2)
      @test.assert_eq(pt.lat, 20.0)
      @test.assert_eq(pt.lng, 30.0)
    }
  }
}

test "GeoDB::centroid_weighted_by_tag returns None for missing tag" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi"]))
  @test.assert_eq(db.centroid_weighted_by_tag("missing") is None, true)
}

test "GeoDB::tag_pair_distribution counts co-occurring pairs" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi", "landmark"]))
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "", "", [], ["poi", "landmark"]))
  db.insert(make_entry_with_addr("p03", "C", 2.0, 2.0, "", "", [], ["poi", "transport"]))
  let pairs = db.tag_pair_distribution()
  @test.assert_eq(pairs.length(), 2)
  let mut total_count = 0
  for p in pairs {
    total_count = total_count + p.1
  }
  // Total should be 3 (2 landmark-poi + 1 poi-transport).
  @test.assert_eq(total_count, 3)
}

test "GeoDB::update_coordinates changes location" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 10.0, 20.0))
  let ok = db.update_coordinates("p01", 30.0, 40.0)
  @test.assert_eq(ok, true)
  match db.get("p01") {
    None => @test.assert_eq(true, false)
    Some(e) => {
      @test.assert_eq(e.location.lat, 30.0)
      @test.assert_eq(e.location.lng, 40.0)
    }
  }
}

test "GeoDB::update_coordinates missing id returns false" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.update_coordinates("missing", 0.0, 0.0), false)
}

test "GeoDB::find_in_bbox_strict filters by bbox AND radius" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  db.insert(make_entry("p02", "B", 0.001, 0.001)) // ~157m away
  db.insert(make_entry("p03", "C", 10.0, 10.0)) // far away
  let bbox = @types.BBox::from_corners(
    @types.GeoPoint::make(-0.01, -0.01),
    @types.GeoPoint::make(0.01, 0.01),
  )
  // With a strict radius of 1km from bbox center, p03 is excluded by bbox anyway.
  // p01 and p02 should be inside bbox; with radius=1km both pass.
  let r = db.find_in_bbox_strict(bbox, radius_km=1.0)
  @test.assert_eq(r.length(), 2)
}

test "GeoDB::to_geojson produces FeatureCollection" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 39.9, 116.4, "北京市", "北京市", "海淀区", ["poi"]))
  let gj = db.to_geojson()
  @test.assert_eq(gj.contains("\"type\":\"FeatureCollection\""), true)
  @test.assert_eq(gj.contains("\"type\":\"Feature\""), true)
  @test.assert_eq(gj.contains("\"type\":\"Point\""), true)
  @test.assert_eq(gj.contains("\"coordinates\":[116.4,39.9]"), true)
  @test.assert_eq(gj.contains("\"id\":\"p01\""), true)
}

test "GeoDB::find_name_contains_case preserves case" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Apple", 0.0, 0.0))
  db.insert(make_entry("p02", "apple", 1.0, 1.0))
  let r = db.find_name_contains_case("App")
  @test.assert_eq(r.length(), 1)
  @test.assert_eq(r[0].name, "Apple")
}

test "GeoDB::find_name_prefix_case preserves case" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Apple", 0.0, 0.0))
  db.insert(make_entry("p02", "app", 1.0, 1.0))
  let r = db.find_name_prefix_case("App")
  @test.assert_eq(r.length(), 1)
  @test.assert_eq(r[0].name, "Apple")
}

test "GeoDB::rename and update_address work" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], []))
  @test.assert_eq(db.rename("p01", "NewName"), true)
  match db.get("p01") {
    None => @test.assert_eq(true, false)
    Some(e) => @test.assert_eq(e.name, "NewName")
  }
  let new_addr : @types.Address = {
    country: "", province: "北京市", city: "北京市", district: "海淀区",
    street: "", postal_code: "", detail: "",
  }
  @test.assert_eq(db.update_address("p01", new_addr), true)
  match db.get("p01") {
    None => @test.assert_eq(true, false)
    Some(e) => @test.assert_eq(e.address.district, "海淀区")
  }
}

// ---- CSV import tests ----

test "GeoDB::import_csv round-trip with to_csv" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("c01", "Cafe A", 39.9, 116.4, "北京市", "北京市", "海淀区", ["food"]))
  db.insert(make_entry_with_addr("c02", "Cafe B", 31.2, 121.5, "上海市", "上海市", "浦东新区", ["food", "landmark"]))
  let csv = db.to_csv()
  @test.assert_eq(csv.length() > 0, true)
  // Import into a fresh DB.
  let db2 = GeoDB::in_memory()
  let n = db2.import_csv(csv)
  @test.assert_eq(n, 2)
  @test.assert_eq(db2.size(), 2)
  match db2.get("c01") {
    None => @test.assert_eq(true, false)
    Some(e) => {
      @test.assert_eq(e.name, "Cafe A")
      @test.assert_eq(e.location.lat, 39.9)
      @test.assert_eq(e.address.province, "北京市")
    }
  }
}

test "GeoDB::import_csv handles empty input" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.import_csv(""), 0)
  @test.assert_eq(db.import_csv("id,name\n"), 0)
}

// ---- GeoJSON import tests ----

test "GeoDB::import_geojson round-trip with to_geojson" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("g01", "Gate A", 39.9, 116.4, "北京市", "北京市", "海淀区", ["poi"]))
  db.insert(make_entry_with_addr("g02", "Gate B", 31.2, 121.5, "上海市", "上海市", "浦东新区", ["landmark"]))
  let gj = db.to_geojson()
  @test.assert_eq(gj.length() > 0, true)
  // Import into a fresh DB.
  let db2 = GeoDB::in_memory()
  let n = db2.import_geojson(gj)
  @test.assert_eq(n, 2)
  @test.assert_eq(db2.size(), 2)
  match db2.get("g01") {
    None => @test.assert_eq(true, false)
    Some(e) => {
      @test.assert_eq(e.name, "Gate A")
      @test.assert_eq(e.location.lat, 39.9)
    }
  }
}

test "GeoDB::import_geojson handles empty input" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.import_geojson(""), 0)
  @test.assert_eq(db.import_geojson("{}"), 0)
  @test.assert_eq(db.import_geojson("{\"type\":\"Feature\"}"), 0)
}

// ---- Duplicate detection tests ----

test "GeoDB::find_duplicates groups near-identical entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("d01", "Temple", 39.9000, 116.4000, "", "", "", []))
  db.insert(make_entry_with_addr("d02", "Temple", 39.9001, 116.4001, "", "", "", []))
  db.insert(make_entry_with_addr("d03", "School", 31.2000, 121.5000, "", "", "", []))
  // Very close entries with same name should be duplicates.
  let groups = db.find_duplicates(max_distance_km=1.0, max_edit_dist=2)
  @test.assert_eq(groups.length(), 1)
  @test.assert_eq(groups[0].length(), 2)
}

test "GeoDB::find_duplicates does not group far-apart entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("d01", "Park", 39.9, 116.4, "", "", "", []))
  db.insert(make_entry_with_addr("d02", "Park", 31.2, 121.5, "", "", "", []))
  let groups = db.find_duplicates(max_distance_km=1.0, max_edit_dist=2)
  @test.assert_eq(groups.length(), 0)
}

// ---- Spatial grid clustering tests ----

test "GeoDB::cluster_by_grid groups nearby entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("cl01", "A", 39.9000, 116.4000, "", "", "", []))
  db.insert(make_entry_with_addr("cl02", "B", 39.9005, 116.4005, "", "", "", []))
  db.insert(make_entry_with_addr("cl03", "C", 31.2000, 121.5000, "", "", "", []))
  let clusters = db.cluster_by_grid(cell_size_km=5.0)
  @test.assert_eq(clusters.length() >= 2, true)
  // Third element is the count.
  let total_count = clusters[0].2 + clusters[1].2
  @test.assert_eq(total_count, 3)
}

test "GeoDB::cluster_by_grid on empty DB returns empty" {
  let db = GeoDB::in_memory()
  let clusters = db.cluster_by_grid()
  @test.assert_eq(clusters.length(), 0)
}

// ---- Distance matrix tests ----

test "GeoDB::distance_matrix computes pairwise distances" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("m01", "A", 39.9, 116.4, "", "", "", []))
  db.insert(make_entry_with_addr("m02", "B", 31.2, 121.5, "", "", "", []))
  let matrix = db.distance_matrix(["m01", "m02"])
  @test.assert_eq(matrix.length(), 2)
  @test.assert_eq(matrix[0].length(), 2)
  // Diagonal should be 0.
  @test.assert_eq(matrix[0][0], 0.0)
  @test.assert_eq(matrix[1][1], 0.0)
  // Off-diagonal should be > 0.
  @test.assert_eq(matrix[0][1] > 0.0, true)
  @test.assert_eq(matrix[1][0] > 0.0, true)
  // Should be symmetric.
  @test.assert_eq(matrix[0][1], matrix[1][0])
}

test "GeoDB::distance_matrix with missing IDs returns 0" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("m01", "A", 39.9, 116.4, "", "", "", []))
  let matrix = db.distance_matrix(["m01", "missing"])
  @test.assert_eq(matrix.length(), 2)
  @test.assert_eq(matrix[0][0], 0.0)
  @test.assert_eq(matrix[0][1], 0.0)
  @test.assert_eq(matrix[1][0], 0.0)
}

// ---- Reverse geocode tests ----

test "GeoDB::reverse_geocode finds nearest entry" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("rg01", "North", 40.0, 116.0, "", "", "", []))
  db.insert(make_entry_with_addr("rg02", "South", 31.0, 121.0, "", "", "", []))
  // Query near (39.9, 116.1) - should be closer to rg01.
  match db.reverse_geocode(39.9, 116.1) {
    None => @test.assert_eq(true, false)
    Some((entry, d)) => {
      @test.assert_eq(entry.id, "rg01")
      @test.assert_eq(d < 100.0, true)
    }
  }
}

test "GeoDB::reverse_geocode on empty DB returns None" {
  let db = GeoDB::in_memory()
  match db.reverse_geocode(39.9, 116.4) {
    None => @test.assert_eq(true, true)
    Some(_) => @test.assert_eq(true, false)
  }
}

// ---- Tag combination queries ----

test "GeoDB::find_by_tags_all returns entries with all tags" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("ta01", "A", 0.0, 0.0, "", "", "", ["food", "cheap"]))
  db.insert(make_entry_with_addr("ta02", "B", 0.0, 0.0, "", "", "", ["food", "expensive"]))
  db.insert(make_entry_with_addr("ta03", "C", 0.0, 0.0, "", "", "", ["cheap"]))
  let result = db.find_by_tags_all(["food", "cheap"])
  @test.assert_eq(result.length(), 1)
  @test.assert_eq(result[0].id, "ta01")
}

test "GeoDB::find_by_tags_any returns entries with any tag" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("ta01", "A", 0.0, 0.0, "", "", "", ["food"]))
  db.insert(make_entry_with_addr("ta02", "B", 0.0, 0.0, "", "", "", ["transport"]))
  db.insert(make_entry_with_addr("ta03", "C", 0.0, 0.0, "", "", "", ["food", "transport"]))
  let result = db.find_by_tags_any(["food", "transport"])
  @test.assert_eq(result.length(), 3)
}

// ---- Bounding box and radius queries ----

test "GeoDB::bbox_count counts entries inside bbox" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("bb01", "A", 39.5, 116.5, "", "", "", []))
  db.insert(make_entry_with_addr("bb02", "B", 40.5, 117.5, "", "", "", []))
  db.insert(make_entry_with_addr("bb03", "C", 30.0, 120.0, "", "", "", []))
  let bbox : @types.BBox = { min_lat: 39.0, max_lat: 41.0, min_lng: 116.0, max_lng: 118.0 }
  let count = db.bbox_count(bbox)
  @test.assert_eq(count, 2)
}

test "GeoDB::find_within_radius returns nearby entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("wr01", "A", 39.9, 116.4, "", "", "", []))
  db.insert(make_entry_with_addr("wr02", "B", 39.9001, 116.4001, "", "", "", []))
  db.insert(make_entry_with_addr("wr03", "C", 31.0, 121.0, "", "", "", []))
  let results = db.find_within_radius(39.9, 116.4, 5.0)
  @test.assert_eq(results.length(), 2)
}

// ---- Density map tests ----

test "GeoDB::density_map groups entries by grid" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("dm01", "A", 39.9000, 116.4000, "", "", "", []))
  db.insert(make_entry_with_addr("dm02", "B", 39.9001, 116.4001, "", "", "", []))
  db.insert(make_entry_with_addr("dm03", "C", 31.2000, 121.5000, "", "", "", []))
  let map = db.density_map(cell_size_km=5.0)
  @test.assert_eq(map.length() >= 2, true)
  // The counts should sum to the total entries.
  let mut total = 0
  for cell in map {
    total = total + cell.3
  }
  @test.assert_eq(total, 3)
}

// ---- Statistics tests ----

test "GeoDB::location_stddev returns zero for single entry" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("sd01", "A", 39.9, 116.4, "", "", "", []))
  let (std_lat, std_lng) = db.location_stddev()
  @test.assert_eq(std_lat, 0.0)
  @test.assert_eq(std_lng, 0.0)
}

test "GeoDB::location_stddev is non-negative for multiple entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("sd01", "A", 39.9, 116.4, "", "", "", []))
  db.insert(make_entry_with_addr("sd02", "B", 31.2, 121.5, "", "", "", []))
  let (std_lat, std_lng) = db.location_stddev()
  @test.assert_eq(std_lat >= 0.0, true)
  @test.assert_eq(std_lng >= 0.0, true)
}

test "GeoDB::province_histogram counts entries by province" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("ph01", "A", 0.0, 0.0, "北京市", "北京市", "", []))
  db.insert(make_entry_with_addr("ph02", "B", 0.0, 0.0, "北京市", "北京市", "", []))
  db.insert(make_entry_with_addr("ph03", "C", 0.0, 0.0, "上海市", "上海市", "", []))
  let hist = db.province_histogram()
  @test.assert_eq(hist.length(), 2)
  let mut found_beijing = 0
  for pair in hist {
    if pair.0 == "北京市" {
      found_beijing = pair.1
    }
  }
  @test.assert_eq(found_beijing, 2)
}
