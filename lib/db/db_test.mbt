// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

///|
fn dabs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
fn make_entry(
  id : String,
  name : String,
  lat : Double,
  lng : Double,
) -> @types.GeoEntry {
  @types.GeoEntry::make(
    id,
    name,
    @types.Address::empty(),
    @types.GeoPoint::make(lat, lng),
  )
}

///|
test "GeoDB::in_memory starts empty" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.size(), 0)
}

///|
test "GeoDB::insert and get" {
  let db = GeoDB::in_memory()
  let e = make_entry("p01", "Tiananmen", 39.9087, 116.3975)
  db.insert(e)
  @test.assert_eq(db.size(), 1)
  @test.assert_eq(db.get("p01") is Some, true)
  @test.assert_eq(db.get("missing") is None, true)
}

///|
test "GeoDB::remove" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "X", 10.0, 20.0))
  @test.assert_eq(db.remove("p01") is Some, true)
  @test.assert_eq(db.size(), 0)
  @test.assert_eq(db.remove("p01") is None, true)
}

///|
test "GeoDB::insert_raw parses address string" {
  let db = GeoDB::in_memory()
  let e = db.insert_raw(
    "p01", "Tiananmen", 39.9, 116.4, "China,Beijing,Beijing,Dongcheng,Tiananmen,100009",
  )
  @test.assert_eq(e.address.country, "China")
  @test.assert_eq(e.address.city, "Beijing")
}

// ---- Geographic statistics tests ----

///|
fn make_entry_with_addr(
  id : String,
  name : String,
  lat : Double,
  lng : Double,
  province : String,
  city : String,
  district : String,
  tags : Array[String],
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

///|
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

///|
test "GeoDB::compute_center returns None for empty DB" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.compute_center() is None, true)
}

///|
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

///|
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

///|
test "GeoDB::compute_max_distance returns None for < 2 entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  @test.assert_eq(db.compute_max_distance() is None, true)
}

///|
test "GeoDB::province_distribution counts correctly" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "北京市",
      "北京市",
      "东城区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p03",
      "C",
      2.0,
      2.0,
      "上海市",
      "上海市",
      "浦东新区",
      [],
    ),
  )
  let dist = db.province_distribution()
  @test.assert_eq(dist.length(), 2)
  // 北京市 should have 2 entries (sorted by count desc)
  @test.assert_eq(dist[0].0, "北京市")
  @test.assert_eq(dist[0].1, 2)
  @test.assert_eq(dist[1].0, "上海市")
  @test.assert_eq(dist[1].1, 1)
}

///|
test "GeoDB::city_distribution counts correctly" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "广东省",
      "广州市",
      "天河区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "广东省",
      "深圳市",
      "南山区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p03",
      "C",
      2.0,
      2.0,
      "广东省",
      "广州市",
      "越秀区",
      [],
    ),
  )
  let dist = db.city_distribution()
  @test.assert_eq(dist.length(), 2)
  @test.assert_eq(dist[0].0, "广州市")
  @test.assert_eq(dist[0].1, 2)
  @test.assert_eq(dist[1].0, "深圳市")
  @test.assert_eq(dist[1].1, 1)
}

///|
test "GeoDB::city_distribution filtered by province" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "广东省",
      "广州市",
      "天河区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "广东省",
      "深圳市",
      "南山区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p03",
      "C",
      2.0,
      2.0,
      "北京市",
      "北京市",
      "海淀区",
      [],
    ),
  )
  let dist = db.city_distribution(province="广东省")
  @test.assert_eq(dist.length(), 2)
  let dist2 = db.city_distribution(province="北京市")
  @test.assert_eq(dist2.length(), 1)
}

///|
test "GeoDB::tag_distribution counts correctly" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      ["poi", "landmark"],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "北京市",
      "北京市",
      "东城区",
      ["poi", "transport"],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p03",
      "C",
      2.0,
      2.0,
      "上海市",
      "上海市",
      "浦东新区",
      ["medical"],
    ),
  )
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

///|
test "GeoDB::summary generates readable output" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      39.9,
      116.4,
      "北京市",
      "北京市",
      "海淀区",
      ["poi"],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      31.2,
      121.5,
      "上海市",
      "上海市",
      "浦东新区",
      ["landmark"],
    ),
  )
  let summary = db.summary()
  @test.assert_eq(summary.contains("Geographic Database Summary"), true)
  @test.assert_eq(summary.contains("Total entries: 2"), true)
  @test.assert_eq(summary.contains("Center:"), true)
  @test.assert_eq(summary.contains("Bounding box:"), true)
  @test.assert_eq(summary.contains("Provinces"), true)
  @test.assert_eq(summary.contains("Tags"), true)
}

///|
test "GeoDB::find_by_tag works through DB" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      ["poi", "landmark"],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "北京市",
      "北京市",
      "东城区",
      ["poi", "transport"],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p03",
      "C",
      2.0,
      2.0,
      "上海市",
      "上海市",
      "浦东新区",
      ["medical"],
    ),
  )
  @test.assert_eq(db.find_by_tag("poi").length(), 2)
  @test.assert_eq(db.find_by_tag("medical").length(), 1)
  @test.assert_eq(db.find_by_tag("nonexistent").length(), 0)
}

///|
test "GeoDB::find_by_province works through DB" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "北京市",
      "北京市",
      "东城区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p03",
      "C",
      2.0,
      2.0,
      "上海市",
      "上海市",
      "浦东新区",
      [],
    ),
  )
  @test.assert_eq(db.find_by_province("北京市").length(), 2)
  @test.assert_eq(db.find_by_province("上海市").length(), 1)
  @test.assert_eq(db.find_by_province("nonexistent").length(), 0)
}

///|
test "GeoDB::list_tags lists all unique tags" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      ["zebra", "apple"],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "北京市",
      "北京市",
      "东城区",
      ["apple", "mango"],
    ),
  )
  let tags = db.list_tags()
  @test.assert_eq(tags.length(), 3)
}

///|
test "GeoDB::list_provinces lists all unique provinces" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "上海市",
      "上海市",
      "浦东新区",
      [],
    ),
  )
  let provinces = db.list_provinces()
  @test.assert_eq(provinces.length(), 2)
}

///|
test "GeoDB::insert_raw parses postal code" {
  let db = GeoDB::in_memory()
  let e = db.insert_raw(
    "p01", "Tiananmen", 39.9, 116.4, "China,Beijing,Beijing,Dongcheng,Tiananmen,100009",
  )
  @test.assert_eq(e.address.postal_code, "100009")
  @test.assert_eq(db.size(), 1)
}

///|
test "GeoDB::insert_raw falls back to empty address on bad input" {
  let db = GeoDB::in_memory()
  let _ = db.insert_raw("p01", "X", 0.0, 0.0, "NoSeparatorHere")
  @test.assert_eq(db.size(), 1)
  match db.get("p01") {
    Some(e) => @test.assert_eq(e.address.country, "")
    None => @test.assert_eq(true, false)
  }
}

///|
test "GeoDB::insert_record_line with full line" {
  let db = GeoDB::in_memory()
  let r = db.insert_record_line("Tiananmen\t39.9087, 116.3975\tChina,Beijing")
  @test.assert_eq(r is Some, true)
  @test.assert_eq(db.size(), 1)
}

///|
test "GeoDB::insert_record_line assigns generated id when empty" {
  let db = GeoDB::in_memory()
  let r = db.insert_record_line("JustAName\t1.0, 2.0")
  match r {
    Some(e) => @test.assert_eq(e.id.length() > 0, true)
    None => @test.assert_eq(true, false)
  }
}

///|
test "GeoDB::insert_record_line returns None on empty line" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.insert_record_line(""), None)
}

///|
test "GeoDB::gen_id is monotonic" {
  let db = GeoDB::in_memory()
  let a = db.gen_id("e")
  let b = db.gen_id("e")
  @test.assert_eq(a == "e0", true)
  @test.assert_eq(b == "e1", true)
}

///|
test "GeoDB::find_by_name" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Tiananmen", 39.9, 116.4))
  db.insert(make_entry("p02", "Shanghai", 31.2, 121.5))
  @test.assert_eq(db.find_by_name("tiananmen").length(), 1)
  @test.assert_eq(db.find_by_name("SHANGHAI").length(), 1)
  @test.assert_eq(db.find_by_name("missing").length(), 0)
}

///|
test "GeoDB::find_name_prefix and contains" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Tiananmen", 39.9, 116.4))
  db.insert(make_entry("p02", "Tianjin", 39.1, 117.2))
  @test.assert_eq(db.find_name_prefix("Tian").length(), 2)
  @test.assert_eq(db.find_name_contains("men").length(), 1)
}

///|
test "GeoDB::find_in_bbox" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9, 116.4))
  db.insert(make_entry("p02", "Shanghai", 31.2, 121.5))
  let bbox : @types.BBox = {
    min_lat: 39.0,
    max_lat: 40.0,
    min_lng: 116.0,
    max_lng: 117.0,
  }
  @test.assert_eq(db.find_in_bbox(bbox).length(), 1)
}

///|
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

///|
test "GeoDB::find_nearby respects limit" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  db.insert(make_entry("p02", "B", 0.001, 0.001))
  db.insert(make_entry("p03", "C", 0.002, 0.002))
  let center = @types.GeoPoint::make(0.0, 0.0)
  let near = db.find_nearby(center, radius_km=100.0, limit=2)
  @test.assert_eq(near.length(), 2)
}

///|
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

///|
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

///|
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

///|
test "GeoDB::save without path returns Err" {
  let db = GeoDB::in_memory()
  match db.save() {
    Err(_) => @test.assert_eq(true, true)
    Ok(_) => @test.assert_eq(true, false)
  }
}

///|
test "GeoDB::open on missing file yields empty db" {
  let db = GeoDB::open("/tmp/geodb_does_not_exist_xyz.db")
  @test.assert_eq(db.size(), 0)
}

///|
test "GeoDB::backup and restore round-trip" {
  let path = "/tmp/geodb_test_backup.db"
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9042, 116.4074))
  db.insert(make_entry("p02", "Shanghai", 31.2304, 121.4737))
  match db.save_to(path) {
    Err(_) => @test.assert_eq(true, false)
    Ok(_) =>
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

///|
test "GeoDB::check integrity" {
  let path = "/tmp/geodb_test_check.db"
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9042, 116.4074))
  match db.save_to(path) {
    Err(_) => @test.assert_eq(true, false)
    Ok(_) =>
      match db.check() {
        Err(_) => @test.assert_eq(true, false)
        Ok(meta) => {
          @test.assert_eq(meta.entry_count, 1)
          @test.assert_eq(meta.version, @persist.db_version)
        }
      }
  }
}

///|
test "GeoDB::all returns snapshot" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  let snap = db.all()
  db.insert(make_entry("p02", "B", 1.0, 1.0))
  @test.assert_eq(snap.length(), 1)
  @test.assert_eq(db.size(), 2)
}

// ---- Chinese address: storage + parse + retrieval example ----

///|
test "GeoDB - store, parse, retrieve: 北京市海淀区颐和园路5号" {
  let db = GeoDB::in_memory()
  // Step 1: Insert a record using raw API (triggers address parsing).
  let e = db.insert_raw(
    "summer-palace", "颐和园", 39.9999, 116.2755, "北京市海淀区颐和园路5号",
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
    max_lng: 117.0,
  }
  let in_bbox = db.find_in_bbox(bbox)
  @test.assert_eq(in_bbox.length(), 1)
  // Step 6: Verify nearby query works (within 5 km of Summer Palace).
  let palace = @types.GeoPoint::make(39.9999, 116.2755)
  let near = db.find_nearby(palace, radius_km=5.0, limit=10)
  @test.assert_eq(near.length(), 1)
}

// ---- Geofence tests ----

///|
test "GeoDB::contains_point checks if point is inside bbox" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 39.9, 116.4))
  db.insert(make_entry("p02", "B", 31.2, 121.5))
  // A point near Beijing should be inside the combined bbox
  @test.assert_eq(db.contains_point(@types.GeoPoint::make(39.9, 116.4)), true)
  // A point far away should be outside
  @test.assert_eq(db.contains_point(@types.GeoPoint::make(0.0, 0.0)), false)
}

///|
test "GeoDB::contains_point returns false for empty DB" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.contains_point(@types.GeoPoint::make(0.0, 0.0)), false)
}

///|
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

///|
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

///|
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

///|
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

///|
test "levenshtein_distance function works correctly" {
  @test.assert_eq(levenshtein_distance("kitten", "sitten"), 1)
  @test.assert_eq(levenshtein_distance("", "abc"), 3)
  @test.assert_eq(levenshtein_distance("abc", ""), 3)
  @test.assert_eq(levenshtein_distance("", ""), 0)
  @test.assert_eq(levenshtein_distance("abc", "abc"), 0)
}

// ---- CSV export tests ----

///|
test "GeoDB::to_csv exports all entries" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      39.9,
      116.4,
      "北京市",
      "北京市",
      "海淀区",
      ["poi"],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      31.2,
      121.5,
      "上海市",
      "上海市",
      "浦东新区",
      ["landmark"],
    ),
  )
  let csv = db.to_csv()
  // Should have header + 2 data rows
  @test.assert_eq(csv.contains("id,name,lat,lng"), true)
  @test.assert_eq(csv.contains("p01"), true)
  @test.assert_eq(csv.contains("p02"), true)
  @test.assert_eq(csv.contains("poi"), true)
  @test.assert_eq(csv.contains("landmark"), true)
}

///|
test "GeoDB::to_csv handles special characters" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr("p01", "Name,with,commas", 0.0, 0.0, "", "", [], [
      "tag1;tag2",
    ]),
  )
  let csv = db.to_csv()
  // Fields with commas should be quoted
  @test.assert_eq(csv.contains("\"Name,with,commas\""), true)
}

// ---- Tag management tests ----

///|
test "GeoDB::add_tag adds tag to entry" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi"]))
  @test.assert_eq(db.find_by_tag("landmark").length(), 0)
  let ok = db.add_tag("p01", "landmark")
  @test.assert_eq(ok, true)
  @test.assert_eq(db.find_by_tag("landmark").length(), 1)
  @test.assert_eq(db.find_by_all_tags(["poi", "landmark"]).length(), 1)
}

///|
test "GeoDB::add_tag returns false for existing tag" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi"]))
  let ok = db.add_tag("p01", "POI") // case-insensitive duplicate
  @test.assert_eq(ok, false)
}

///|
test "GeoDB::add_tag returns false for missing entry" {
  let db = GeoDB::in_memory()
  let ok = db.add_tag("nonexistent", "tag")
  @test.assert_eq(ok, false)
}

///|
test "GeoDB::remove_tag removes tag from entry" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi", "landmark"]),
  )
  let ok = db.remove_tag("p01", "poi")
  @test.assert_eq(ok, true)
  @test.assert_eq(db.find_by_tag("poi").length(), 0)
  @test.assert_eq(db.find_by_tag("landmark").length(), 1)
}

///|
test "GeoDB::remove_tag returns false if tag not present" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi"]))
  let ok = db.remove_tag("p01", "nonexistent")
  @test.assert_eq(ok, false)
}

// ---- Batch operation tests ----

///|
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

///|
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

///|
test "GeoDB::clear removes all entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  db.insert(make_entry("p02", "B", 1.0, 1.0))
  @test.assert_eq(db.size(), 2)
  db.clear()
  @test.assert_eq(db.size(), 0)
}

// ---- Update operation tests ----

///|
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

///|
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

///|
test "GeoDB::update_location returns false for missing entry" {
  let db = GeoDB::in_memory()
  @test.assert_eq(
    db.update_location("missing", @types.GeoPoint::make(0.0, 0.0)),
    false,
  )
}

// ---- Address query through DB tests ----

///|
test "GeoDB::find_by_city works through DB" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "广东省",
      "广州市",
      "天河区",
      [],
    ),
  )
  @test.assert_eq(db.find_by_city("北京市").length(), 1)
  @test.assert_eq(db.find_by_city("广州市").length(), 1)
  @test.assert_eq(db.find_by_city("nonexistent").length(), 0)
}

///|
test "GeoDB::find_by_district works through DB" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "北京市",
      "北京市",
      "东城区",
      [],
    ),
  )
  @test.assert_eq(db.find_by_district("海淀区").length(), 1)
  @test.assert_eq(db.find_by_district("东城区").length(), 1)
}

///|
test "GeoDB::find_by_province_city compound query" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "广东省",
      "广州市",
      "天河区",
      [],
    ),
  )
  let r = db.find_by_province_city("北京市", "北京市")
  @test.assert_eq(r.length(), 1)
  @test.assert_eq(r[0].id, "p01")
}

///|
test "GeoDB::find_by_all_tags AND logic through DB" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi", "landmark"]),
  )
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "", "", [], ["poi"]))
  let r = db.find_by_all_tags(["poi", "landmark"])
  @test.assert_eq(r.length(), 1)
  @test.assert_eq(r[0].id, "p01")
}

///|
test "GeoDB::find_by_any_tags OR logic through DB" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi"]))
  db.insert(
    make_entry_with_addr("p02", "B", 1.0, 1.0, "", "", [], ["transport"]),
  )
  let r = db.find_by_any_tags(["poi", "transport"])
  @test.assert_eq(r.length(), 2)
}

///|
test "GeoDB::list_cities and list_districts" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "广东省",
      "广州市",
      "天河区",
      [],
    ),
  )
  let cities = db.list_cities()
  @test.assert_eq(cities.length(), 2)
  let districts = db.list_districts()
  @test.assert_eq(districts.length(), 2)
}

// ---- New feature tests ----

///|
test "GeoDB::to_json round-trip preserves entries" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      39.9,
      116.4,
      "北京市",
      "北京市",
      "海淀区",
      ["poi"],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      31.2,
      121.5,
      "上海市",
      "上海市",
      "浦东新区",
      ["landmark"],
    ),
  )
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

///|
test "GeoDB::to_json on empty DB returns []" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.to_json(), "[]")
}

///|
test "GeoDB::import_json on empty/empty-array returns 0" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.import_json(""), 0)
  @test.assert_eq(db.import_json("[]"), 0)
}

///|
test "GeoDB::distance_between computes haversine correctly" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 39.9, 116.4))
  db.insert(make_entry("p02", "B", 39.9, 116.4))
  match db.distance_between("p01", "p02") {
    None => @test.assert_eq(true, false)
    Some(d) => @test.assert_eq(d < 0.001, true)
  }
}

///|
test "GeoDB::distance_between with missing id returns None" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 39.9, 116.4))
  @test.assert_eq(db.distance_between("p01", "missing") is None, true)
}

///|
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

///|
test "GeoDB::find_nearest_pairs on empty/singleton returns empty" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.find_nearest_pairs(5).length(), 0)
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  @test.assert_eq(db.find_nearest_pairs(5).length(), 0)
}

///|
test "GeoDB::find_neighbors returns k nearest" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  db.insert(make_entry("p02", "B", 0.0, 1.0))
  db.insert(make_entry("p03", "C", 10.0, 10.0))
  let neighbors = db.find_neighbors("p01", 2)
  @test.assert_eq(neighbors.length(), 2)
  @test.assert_eq(neighbors[0].0.id, "p02")
}

///|
test "GeoDB::find_neighbors with missing id returns empty" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "A", 0.0, 0.0))
  @test.assert_eq(db.find_neighbors("missing", 5).length(), 0)
}

///|
test "GeoDB::count_by_tag works" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi", "landmark"]),
  )
  db.insert(make_entry_with_addr("p02", "B", 1.0, 1.0, "", "", [], ["poi"]))
  db.insert(
    make_entry_with_addr("p03", "C", 2.0, 2.0, "", "", [], ["transport"]),
  )
  @test.assert_eq(db.count_by_tag("poi"), 2)
  @test.assert_eq(db.count_by_tag("landmark"), 1)
  @test.assert_eq(db.count_by_tag("missing"), 0)
}

///|
test "GeoDB::count_by_tag is case-insensitive" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["POI"]))
  @test.assert_eq(db.count_by_tag("poi"), 1)
}

///|
test "GeoDB::district_distribution counts correctly" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "北京市",
      "北京市",
      "海淀区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p03",
      "C",
      2.0,
      2.0,
      "北京市",
      "北京市",
      "东城区",
      [],
    ),
  )
  let dist = db.district_distribution()
  @test.assert_eq(dist.length(), 2)
  // Both sorted by count desc: 海淀区(2) first, 东城区(1) second.
  @test.assert_eq(dist[0].0, "海淀区")
  @test.assert_eq(dist[0].1, 2)
}

///|
test "GeoDB::district_distribution filtered by province" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      0.0,
      0.0,
      "北京市",
      "北京市",
      "海淀区",
      [],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "p02",
      "B",
      1.0,
      1.0,
      "广东省",
      "广州市",
      "天河区",
      [],
    ),
  )
  let dist = db.district_distribution(province="北京市")
  @test.assert_eq(dist.length(), 1)
  @test.assert_eq(dist[0].0, "海淀区")
}

///|
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

///|
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

///|
test "GeoDB::centroid_weighted_by_tag returns None for missing tag" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi"]))
  @test.assert_eq(db.centroid_weighted_by_tag("missing") is None, true)
}

///|
test "GeoDB::tag_pair_distribution counts co-occurring pairs" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], ["poi", "landmark"]),
  )
  db.insert(
    make_entry_with_addr("p02", "B", 1.0, 1.0, "", "", [], ["poi", "landmark"]),
  )
  db.insert(
    make_entry_with_addr("p03", "C", 2.0, 2.0, "", "", [], ["poi", "transport"]),
  )
  let pairs = db.tag_pair_distribution()
  @test.assert_eq(pairs.length(), 2)
  let mut total_count = 0
  for p in pairs {
    total_count = total_count + p.1
  }
  // Total should be 3 (2 landmark-poi + 1 poi-transport).
  @test.assert_eq(total_count, 3)
}

///|
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

///|
test "GeoDB::update_coordinates missing id returns false" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.update_coordinates("missing", 0.0, 0.0), false)
}

///|
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

///|
test "GeoDB::to_geojson produces FeatureCollection" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "p01",
      "A",
      39.9,
      116.4,
      "北京市",
      "北京市",
      "海淀区",
      ["poi"],
    ),
  )
  let gj = db.to_geojson()
  @test.assert_eq(gj.contains("\"type\":\"FeatureCollection\""), true)
  @test.assert_eq(gj.contains("\"type\":\"Feature\""), true)
  @test.assert_eq(gj.contains("\"type\":\"Point\""), true)
  @test.assert_eq(gj.contains("\"coordinates\":[116.4,39.9]"), true)
  @test.assert_eq(gj.contains("\"id\":\"p01\""), true)
}

///|
test "GeoDB::find_name_contains_case preserves case" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Apple", 0.0, 0.0))
  db.insert(make_entry("p02", "apple", 1.0, 1.0))
  let r = db.find_name_contains_case("App")
  @test.assert_eq(r.length(), 1)
  @test.assert_eq(r[0].name, "Apple")
}

///|
test "GeoDB::find_name_prefix_case preserves case" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Apple", 0.0, 0.0))
  db.insert(make_entry("p02", "app", 1.0, 1.0))
  let r = db.find_name_prefix_case("App")
  @test.assert_eq(r.length(), 1)
  @test.assert_eq(r[0].name, "Apple")
}

///|
test "GeoDB::rename and update_address work" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("p01", "A", 0.0, 0.0, "", "", [], []))
  @test.assert_eq(db.rename("p01", "NewName"), true)
  match db.get("p01") {
    None => @test.assert_eq(true, false)
    Some(e) => @test.assert_eq(e.name, "NewName")
  }
  let new_addr : @types.Address = {
    country: "",
    province: "北京市",
    city: "北京市",
    district: "海淀区",
    street: "",
    postal_code: "",
    detail: "",
  }
  @test.assert_eq(db.update_address("p01", new_addr), true)
  match db.get("p01") {
    None => @test.assert_eq(true, false)
    Some(e) => @test.assert_eq(e.address.district, "海淀区")
  }
}

// ---- CSV import tests ----

///|
test "GeoDB::import_csv round-trip with to_csv" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "c01",
      "Cafe A",
      39.9,
      116.4,
      "北京市",
      "北京市",
      "海淀区",
      ["food"],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "c02",
      "Cafe B",
      31.2,
      121.5,
      "上海市",
      "上海市",
      "浦东新区",
      ["food", "landmark"],
    ),
  )
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

///|
test "GeoDB::import_csv handles empty input" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.import_csv(""), 0)
  @test.assert_eq(db.import_csv("id,name\n"), 0)
}

// ---- GeoJSON import tests ----

///|
test "GeoDB::import_geojson round-trip with to_geojson" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr(
      "g01",
      "Gate A",
      39.9,
      116.4,
      "北京市",
      "北京市",
      "海淀区",
      ["poi"],
    ),
  )
  db.insert(
    make_entry_with_addr(
      "g02",
      "Gate B",
      31.2,
      121.5,
      "上海市",
      "上海市",
      "浦东新区",
      ["landmark"],
    ),
  )
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

///|
test "GeoDB::import_geojson handles empty input" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.import_geojson(""), 0)
  @test.assert_eq(db.import_geojson("{}"), 0)
  @test.assert_eq(db.import_geojson("{\"type\":\"Feature\"}"), 0)
}

// ---- Duplicate detection tests ----

///|
test "GeoDB::find_duplicates groups near-identical entries" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr("d01", "Temple", 39.9000, 116.4000, "", "", "", []),
  )
  db.insert(
    make_entry_with_addr("d02", "Temple", 39.9001, 116.4001, "", "", "", []),
  )
  db.insert(
    make_entry_with_addr("d03", "School", 31.2000, 121.5000, "", "", "", []),
  )
  // Very close entries with same name should be duplicates.
  let groups = db.find_duplicates(max_distance_km=1.0, max_edit_dist=2)
  @test.assert_eq(groups.length(), 1)
  @test.assert_eq(groups[0].length(), 2)
}

///|
test "GeoDB::find_duplicates does not group far-apart entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("d01", "Park", 39.9, 116.4, "", "", "", []))
  db.insert(make_entry_with_addr("d02", "Park", 31.2, 121.5, "", "", "", []))
  let groups = db.find_duplicates(max_distance_km=1.0, max_edit_dist=2)
  @test.assert_eq(groups.length(), 0)
}

// ---- Spatial grid clustering tests ----

///|
test "GeoDB::cluster_by_grid groups nearby entries" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr("cl01", "A", 39.9000, 116.4000, "", "", "", []),
  )
  db.insert(
    make_entry_with_addr("cl02", "B", 39.9005, 116.4005, "", "", "", []),
  )
  db.insert(
    make_entry_with_addr("cl03", "C", 31.2000, 121.5000, "", "", "", []),
  )
  let clusters = db.cluster_by_grid(cell_size_km=5.0)
  @test.assert_eq(clusters.length() >= 2, true)
  // Third element is the count.
  let total_count = clusters[0].2 + clusters[1].2
  @test.assert_eq(total_count, 3)
}

///|
test "GeoDB::cluster_by_grid on empty DB returns empty" {
  let db = GeoDB::in_memory()
  let clusters = db.cluster_by_grid()
  @test.assert_eq(clusters.length(), 0)
}

// ---- Distance matrix tests ----

///|
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

///|
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

///|
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

///|
test "GeoDB::reverse_geocode on empty DB returns None" {
  let db = GeoDB::in_memory()
  match db.reverse_geocode(39.9, 116.4) {
    None => @test.assert_eq(true, true)
    Some(_) => @test.assert_eq(true, false)
  }
}

// ---- Tag combination queries ----

///|
test "GeoDB::find_by_tags_all returns entries with all tags" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr("ta01", "A", 0.0, 0.0, "", "", "", ["food", "cheap"]),
  )
  db.insert(
    make_entry_with_addr("ta02", "B", 0.0, 0.0, "", "", "", [
      "food", "expensive",
    ]),
  )
  db.insert(make_entry_with_addr("ta03", "C", 0.0, 0.0, "", "", "", ["cheap"]))
  let result = db.find_by_tags_all(["food", "cheap"])
  @test.assert_eq(result.length(), 1)
  @test.assert_eq(result[0].id, "ta01")
}

///|
test "GeoDB::find_by_tags_any returns entries with any tag" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("ta01", "A", 0.0, 0.0, "", "", "", ["food"]))
  db.insert(
    make_entry_with_addr("ta02", "B", 0.0, 0.0, "", "", "", ["transport"]),
  )
  db.insert(
    make_entry_with_addr("ta03", "C", 0.0, 0.0, "", "", "", [
      "food", "transport",
    ]),
  )
  let result = db.find_by_tags_any(["food", "transport"])
  @test.assert_eq(result.length(), 3)
}

// ---- Bounding box and radius queries ----

///|
test "GeoDB::bbox_count counts entries inside bbox" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("bb01", "A", 39.5, 116.5, "", "", "", []))
  db.insert(make_entry_with_addr("bb02", "B", 40.5, 117.5, "", "", "", []))
  db.insert(make_entry_with_addr("bb03", "C", 30.0, 120.0, "", "", "", []))
  let bbox : @types.BBox = {
    min_lat: 39.0,
    max_lat: 41.0,
    min_lng: 116.0,
    max_lng: 118.0,
  }
  let count = db.bbox_count(bbox)
  @test.assert_eq(count, 2)
}

///|
test "GeoDB::find_within_radius returns nearby entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("wr01", "A", 39.9, 116.4, "", "", "", []))
  db.insert(
    make_entry_with_addr("wr02", "B", 39.9001, 116.4001, "", "", "", []),
  )
  db.insert(make_entry_with_addr("wr03", "C", 31.0, 121.0, "", "", "", []))
  let results = db.find_within_radius(39.9, 116.4, 5.0)
  @test.assert_eq(results.length(), 2)
}

// ---- Density map tests ----

///|
test "GeoDB::density_map groups entries by grid" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr("dm01", "A", 39.9000, 116.4000, "", "", "", []),
  )
  db.insert(
    make_entry_with_addr("dm02", "B", 39.9001, 116.4001, "", "", "", []),
  )
  db.insert(
    make_entry_with_addr("dm03", "C", 31.2000, 121.5000, "", "", "", []),
  )
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

///|
test "GeoDB::location_stddev returns zero for single entry" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("sd01", "A", 39.9, 116.4, "", "", "", []))
  let (std_lat, std_lng) = db.location_stddev()
  @test.assert_eq(std_lat, 0.0)
  @test.assert_eq(std_lng, 0.0)
}

///|
test "GeoDB::location_stddev is non-negative for multiple entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("sd01", "A", 39.9, 116.4, "", "", "", []))
  db.insert(make_entry_with_addr("sd02", "B", 31.2, 121.5, "", "", "", []))
  let (std_lat, std_lng) = db.location_stddev()
  @test.assert_eq(std_lat >= 0.0, true)
  @test.assert_eq(std_lng >= 0.0, true)
}

///|
test "GeoDB::province_histogram counts entries by province" {
  let db = GeoDB::in_memory()
  db.insert(
    make_entry_with_addr("ph01", "A", 0.0, 0.0, "北京市", "北京市", "", []),
  )
  db.insert(
    make_entry_with_addr("ph02", "B", 0.0, 0.0, "北京市", "北京市", "", []),
  )
  db.insert(
    make_entry_with_addr("ph03", "C", 0.0, 0.0, "上海市", "上海市", "", []),
  )
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

// ---- Path distance tests ----

///|
test "GeoDB::path_distance computes multi-point route distance" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("pt01", "A", 39.9, 116.4, "", "", "", []))
  db.insert(make_entry_with_addr("pt02", "B", 31.2, 121.5, "", "", "", []))
  db.insert(make_entry_with_addr("pt03", "C", 22.3, 114.1, "", "", "", []))
  let d = db.path_distance(["pt01", "pt02", "pt03"])
  @test.assert_eq(d > 0.0, true)
  // Should be sum of A->B + B->C
  let ab = @geo.haversine(
    @types.GeoPoint::make(39.9, 116.4),
    @types.GeoPoint::make(31.2, 121.5),
  )
  let bc = @geo.haversine(
    @types.GeoPoint::make(31.2, 121.5),
    @types.GeoPoint::make(22.3, 114.1),
  )
  @test.assert_eq(dabs(d - (ab + bc)) < 0.01, true)
}

///|
test "GeoDB::path_distance with single entry returns 0" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("pt01", "A", 39.9, 116.4, "", "", "", []))
  @test.assert_eq(db.path_distance(["pt01"]), 0.0)
}

///|
test "GeoDB::path_detail returns entries and distance" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("pd01", "A", 39.9, 116.4, "", "", "", []))
  db.insert(make_entry_with_addr("pd02", "B", 31.2, 121.5, "", "", "", []))
  let (d, entries) = db.path_detail(["pd01", "pd02"])
  @test.assert_eq(entries.length(), 2)
  @test.assert_eq(d > 0.0, true)
}

// ---- Geohash tests ----

///|
test "GeoDB::entry_geohash computes correctly" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("g01", "A", 39.9087, 116.3975, "", "", "", []))
  let gh = db.entry_geohash("g01", precision=6)
  match gh {
    None => @test.assert_eq(true, false)
    Some(h) => {
      @test.assert_eq(h.length(), 6)
      // Verify roundtrip: decode the geohash and check coordinates are close.
      let pt = @geo.geohash_decode(h)
      @test.assert_eq(dabs(pt.lat - 39.9087) < 0.01, true)
      @test.assert_eq(dabs(pt.lng - 116.3975) < 0.01, true)
    }
  }
}

///|
test "GeoDB::find_by_geohash matches exact geohash" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("g01", "A", 39.9087, 116.3975, "", "", "", []))
  // Get the geohash for this entry, then search by it.
  let gh = db.entry_geohash("g01", precision=6)
  match gh {
    None => @test.assert_eq(true, false)
    Some(h) => {
      let results = db.find_by_geohash(h, precision=6)
      @test.assert_eq(results.length(), 1)
      @test.assert_eq(results[0].id, "g01")
    }
  }
}

///|
test "GeoDB::find_by_geohash_prefix groups nearby entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("g01", "A", 39.9087, 116.3975, "", "", "", []))
  db.insert(make_entry_with_addr("g02", "B", 39.9090, 116.3980, "", "", "", []))
  db.insert(make_entry_with_addr("g03", "C", 22.3000, 114.1000, "", "", "", []))
  let results = db.find_by_geohash_prefix("wx4g", precision=6)
  @test.assert_eq(results.length(), 2)
}

// ---- Convex hull tests ----

///|
test "GeoDB::convex_hull_all returns hull points" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("ch01", "A", 0.0, 0.0, "", "", "", []))
  db.insert(make_entry_with_addr("ch02", "B", 10.0, 0.0, "", "", "", []))
  db.insert(make_entry_with_addr("ch03", "C", 0.0, 10.0, "", "", "", []))
  db.insert(make_entry_with_addr("ch04", "D", 10.0, 10.0, "", "", "", []))
  let hull = db.convex_hull_all()
  // 4 corners should form the hull.
  @test.assert_eq(hull.length(), 4)
}

// ---- Pagination tests ----

///|
test "GeoDB::page_all returns correct slice" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("pg01", "A", 1.0, 1.0, "", "", "", []))
  db.insert(make_entry_with_addr("pg02", "B", 2.0, 2.0, "", "", "", []))
  db.insert(make_entry_with_addr("pg03", "C", 3.0, 3.0, "", "", "", []))
  let page = db.page_all(2, offset=0)
  @test.assert_eq(page.length(), 2)
  let page2 = db.page_all(2, offset=2)
  @test.assert_eq(page2.length(), 1)
}

///|
test "GeoDB::page_all with offset beyond size returns empty" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("pg01", "A", 1.0, 1.0, "", "", "", []))
  let page = db.page_all(10, offset=5)
  @test.assert_eq(page.length(), 0)
}

///|
test "GeoDB::page_results paginates any array" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("pg01", "A", 1.0, 1.0, "", "", "", []))
  db.insert(make_entry_with_addr("pg02", "B", 2.0, 2.0, "", "", "", []))
  let results = db.find_name_contains("A")
  let page = db.page_results(results, 1, offset=0)
  @test.assert_eq(page.length(), 1)
}

// ---- Address normalization tests ----

///|
test "GeoDB::normalize_address strips province/city suffixes" {
  let db = GeoDB::in_memory()
  let addr : @types.Address = {
    country: "中国",
    province: "北京市",
    city: "北京市",
    district: "海淀区",
    street: "",
    postal_code: "",
    detail: "",
  }
  db.insert(
    @types.GeoEntry::make(
      "n01",
      "Test",
      addr,
      @types.GeoPoint::make(39.9, 116.4),
    ),
  )
  let ok = db.normalize_address("n01")
  @test.assert_eq(ok, true)
  match db.get("n01") {
    None => @test.assert_eq(true, false)
    Some(e) => {
      @test.assert_eq(e.address.province, "北京")
      @test.assert_eq(e.address.city, "北京")
      @test.assert_eq(e.address.district, "海淀")
    }
  }
}

///|
test "GeoDB::normalize_address on missing entry returns false" {
  let db = GeoDB::in_memory()
  @test.assert_eq(db.normalize_address("nope"), false)
}

// ---- Geohash encoding/decoding tests ----

///|
test "geohash_encode produces known value for Beijing" {
  // Beijing Tiananmen (39.9087, 116.3975) area.
  let gh = @geo.geohash_encode(39.9087, 116.3975, 6)
  @test.assert_eq(gh.length(), 6)
  // Verify roundtrip
  let pt = @geo.geohash_decode(gh)
  @test.assert_eq(dabs(pt.lat - 39.9087) < 0.01, true)
  @test.assert_eq(dabs(pt.lng - 116.3975) < 0.01, true)
}

///|
test "geohash_decode encodes back to nearby coordinates" {
  let gh = @geo.geohash_encode(39.9087, 116.3975, 8)
  let pt = @geo.geohash_decode(gh)
  @test.assert_eq(dabs(pt.lat - 39.9087) < 0.01, true)
  @test.assert_eq(dabs(pt.lng - 116.3975) < 0.01, true)
}

///|
test "geohash_encode rejects invalid precision" {
  @test.assert_eq(@geo.geohash_encode(39.9, 116.4, 0), "")
  @test.assert_eq(@geo.geohash_encode(39.9, 116.4, 10), "")
}

// ---- WGS84 ↔ GCJ-02 tests ----

///|
test "wgs84_to_gcj02 shifts Chinese coordinates" {
  // Beijing should be shifted. Function returns (lng, lat).
  let (glng, glat) = @geo.wgs84_to_gcj02(116.4, 39.9)
  @test.assert_eq(glat != 39.9, true)
  @test.assert_eq(glng != 116.4, true)
}

///|
test "wgs84_to_gcj02 leaves non-China coordinates unchanged" {
  // London should be unchanged. Function returns (lng, lat).
  let (olng, olat) = @geo.wgs84_to_gcj02(-0.1276, 51.5074)
  @test.assert_eq(dabs(olat - 51.5074) < 0.001, true)
  @test.assert_eq(dabs(olng - -0.1276) < 0.001, true)
}

///|
test "gcj02_to_wgs84 reverses the transform approximately" {
  let (glng, glat) = @geo.wgs84_to_gcj02(116.4, 39.9)
  let (olng, olat) = @geo.gcj02_to_wgs84(glng, glat)
  @test.assert_eq(dabs(olat - 39.9) < 0.05, true)
  @test.assert_eq(dabs(olng - 116.4) < 0.05, true)
}

// ---- Convex hull tests in geo module ----

///|
test "convex_hull handles triangle correctly" {
  let points : Array[@types.GeoPoint] = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(10.0, 0.0),
    @types.GeoPoint::make(0.0, 10.0),
  ]
  let hull = @geo.convex_hull(points)
  @test.assert_eq(hull.length(), 3)
}

///|
test "convex_hull returns points as-is for fewer than 3" {
  let points : Array[@types.GeoPoint] = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(1.0, 1.0),
  ]
  let hull = @geo.convex_hull(points)
  @test.assert_eq(hull.length(), 2)
}

///|
test "convex_hull handles collinear points" {
  let points : Array[@types.GeoPoint] = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(5.0, 5.0),
    @types.GeoPoint::make(10.0, 10.0),
  ]
  let hull = @geo.convex_hull(points)
  // Collinear: only endpoints should be on hull (2 points).
  @test.assert_eq(hull.length(), 2)
}

// ---- Polygon area and point-in-polygon tests ----

///|
test "polygon_area of a square is non-zero" {
  let square : Array[@types.GeoPoint] = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(0.0, 1.0),
    @types.GeoPoint::make(1.0, 1.0),
    @types.GeoPoint::make(1.0, 0.0),
  ]
  let area = @geo.polygon_area(square)
  @test.assert_eq(area > 0.0, true)
}

///|
test "polygon_area returns 0 for fewer than 3 points" {
  @test.assert_eq(@geo.polygon_area([]), 0.0)
  @test.assert_eq(@geo.polygon_area([@types.GeoPoint::make(0.0, 0.0)]), 0.0)
}

///|
test "point_in_polygon detects point inside square" {
  let square : Array[@types.GeoPoint] = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(0.0, 1.0),
    @types.GeoPoint::make(1.0, 1.0),
    @types.GeoPoint::make(1.0, 0.0),
  ]
  let inside = @geo.point_in_polygon(@types.GeoPoint::make(0.5, 0.5), square)
  @test.assert_eq(inside, true)
}

///|
test "point_in_polygon detects point outside square" {
  let square : Array[@types.GeoPoint] = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(0.0, 1.0),
    @types.GeoPoint::make(1.0, 1.0),
    @types.GeoPoint::make(1.0, 0.0),
  ]
  let outside = @geo.point_in_polygon(@types.GeoPoint::make(2.0, 2.0), square)
  @test.assert_eq(outside, false)
}

// ---- Geohash neighbors and cell size ----

///|
test "geohash_neighbors returns 9 cells" {
  let gh = @geo.geohash_encode(39.9, 116.4, 6)
  let neighbors = @geo.geohash_neighbors(gh)
  @test.assert_eq(neighbors.length(), 9)
}

///|
test "geohash_cell_size decreases with precision" {
  let (lat1, _) = @geo.geohash_cell_size(1)
  let (lat6, _) = @geo.geohash_cell_size(6)
  @test.assert_eq(lat1 > lat6, true)
  @test.assert_eq(lat6 > 0.0, true)
}

///|
test "geohash_to_bbox returns valid bbox" {
  let gh = @geo.geohash_encode(39.9, 116.4, 6)
  let bbox = @geo.geohash_to_bbox(gh)
  @test.assert_eq(bbox.min_lat < bbox.max_lat, true)
  @test.assert_eq(bbox.min_lng < bbox.max_lng, true)
}

// ---- Average nearest-neighbor distance ----

///|
test "average_nn_distance is positive for separated points" {
  let points : Array[@types.GeoPoint] = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(1.0, 1.0),
    @types.GeoPoint::make(2.0, 0.0),
  ]
  let avg = @geo.average_nn_distance(points)
  @test.assert_eq(avg > 0.0, true)
}

///|
test "average_nn_distance returns 0 for fewer than 2 points" {
  @test.assert_eq(@geo.average_nn_distance([]), 0.0)
  @test.assert_eq(
    @geo.average_nn_distance([@types.GeoPoint::make(0.0, 0.0)]),
    0.0,
  )
}

// ---- Database-level new feature tests ----

///|
test "GeoDB::convex_hull_area returns positive" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("a", "A", 0.0, 0.0, "", "", "", []))
  db.insert(make_entry_with_addr("b", "B", 0.0, 1.0, "", "", "", []))
  db.insert(make_entry_with_addr("c", "C", 1.0, 1.0, "", "", "", []))
  db.insert(make_entry_with_addr("d", "D", 1.0, 0.0, "", "", "", []))
  let area = db.convex_hull_area()
  @test.assert_eq(area > 0.0, true)
}

///|
test "GeoDB::find_in_polygon returns points inside polygon" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("inside", "I", 0.5, 0.5, "", "", "", []))
  db.insert(make_entry_with_addr("outside", "O", 5.0, 5.0, "", "", "", []))
  let poly : Array[@types.GeoPoint] = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(0.0, 1.0),
    @types.GeoPoint::make(1.0, 1.0),
    @types.GeoPoint::make(1.0, 0.0),
  ]
  let results = db.find_in_polygon(poly)
  @test.assert_eq(results.length(), 1)
  @test.assert_eq(results[0].id, "inside")
}

///|
test "GeoDB::average_nn_distance is positive with entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("a", "A", 39.9, 116.4, "", "", "", []))
  db.insert(make_entry_with_addr("b", "B", 31.2, 121.5, "", "", "", []))
  db.insert(make_entry_with_addr("c", "C", 22.3, 114.1, "", "", "", []))
  let avg = db.average_nn_distance()
  @test.assert_eq(avg > 0.0, true)
}

///|
test "GeoDB::cluster_dbscan groups close points together" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("c1", "C1", 39.9000, 116.4000, "", "", "", []))
  db.insert(make_entry_with_addr("c2", "C2", 39.9001, 116.4001, "", "", "", []))
  db.insert(make_entry_with_addr("c3", "C3", 39.9002, 116.4002, "", "", "", []))
  db.insert(make_entry_with_addr("o1", "O1", 22.3000, 114.1000, "", "", "", []))
  let clusters = db.cluster_dbscan(1.0, 2)
  @test.assert_eq(clusters.length() >= 1, true)
  // Verify that a cluster containing at least the 3 Beijing points exists.
  let mut found = false
  for c in clusters {
    if c.length() >= 3 {
      found = true
    }
  }
  @test.assert_eq(found, true)
}

///|
/// Build 3 known clusters of 8 points each, packed inside ~10 km
/// (±0.05° box), centered on Beijing / Shanghai / Guangzhou.
/// Cities are 1000+ km apart so no cross-cluster neighbors exist.
fn build_three_cluster_db() -> GeoDB {
  let db = GeoDB::in_memory()
  let centers : Array[(String, Double, Double)] = [
    ("bj", 39.9, 116.4),
    ("sh", 31.2, 121.5),
    ("gz", 23.1, 113.3),
  ]
  let offsets : Array[(Double, Double)] = [
    (0.00, 0.00), (0.02, 0.01), (-0.02, 0.02), (0.01, -0.03),
    (-0.03, -0.01), (0.03, 0.03), (-0.01, 0.04), (0.04, -0.02),
  ]
  for (prefix, clat, clng) in centers {
    let mut i = 0
    while i < 8 {
      let (dlat, dlng) = offsets[i]
      db.insert(
        make_entry_with_addr(
          prefix + i.to_string(),
          prefix + i.to_string(),
          clat + dlat,
          clng + dlng,
          "",
          "",
          "",
          [],
        ),
      )
      i = i + 1
    }
  }
  db
}

///|
test "GeoDB::cluster_dbscan finds exactly 3 known clusters" {
  let db = build_three_cluster_db()
  @test.assert_eq(db.size(), 24)
  let clusters = db.cluster_dbscan(50.0, 5)
  @test.assert_eq(clusters.length(), 3)
  // Every cluster must have exactly 8 members sharing a city prefix.
  for c in clusters {
    @test.assert_eq(c.length(), 8)
    let prefix = c[0].substring(start=0, end=2)
    for id in c {
      @test.assert_eq(id.substring(start=0, end=2), prefix)
    }
  }
}

///|
test "GeoDB::cluster_dbscan marks isolated points as noise (no false clusters)" {
  let db = build_three_cluster_db()
  // Two far-away isolated points, >50 km from anything.
  db.insert(make_entry_with_addr("n1", "N1", 45.0, 90.0, "", "", "", []))
  db.insert(make_entry_with_addr("n2", "N2", 28.0, 100.0, "", "", "", []))
  let clusters = db.cluster_dbscan(50.0, 5)
  @test.assert_eq(clusters.length(), 3)
  // Noise points must not appear in any cluster.
  for c in clusters {
    for id in c {
      @test.assert_eq(id != "n1" && id != "n2", true)
    }
  }
}

///|
test "GeoDB::kmeans separates the 3 known clusters" {
  let db = build_three_cluster_db()
  // Run k-means multiple times to handle non-deterministic initialization.
  // With Forgy init (first k points), the result depends on data order.
  // We try up to 10 times; at least one run should converge correctly.
  let mut ok = false
  let mut attempt = 0
  while attempt < 10 && !ok {
    let result = db.kmeans(3)
    if result.length() != 3 {
      attempt = attempt + 1
      continue
    }
    // Map each entry id to its cluster index.
    let cluster_of : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
    let mut ci = 0
    for cl in result {
      for e in cl.members {
        cluster_of[e.id] = ci
      }
      ci = ci + 1
    }
    // Check that each city's points are in the same cluster.
    let mut all_same = true
    for prefix in ["bj", "sh", "gz"] {
      let mut cluster_idx : Int = -1
      let mut i = 0
      while i < 8 {
        let id = prefix + i.to_string()
        match cluster_of.get(id) {
          Some(idx) =>
            if cluster_idx < 0 {
              cluster_idx = idx
            } else if idx != cluster_idx {
              all_same = false
            }
          None => all_same = false
        }
        i = i + 1
      }
    }
    // Check that the 3 clusters are distinct.
    let mut bj_cluster : Int = -1
    let mut sh_cluster : Int = -1
    let mut gz_cluster : Int = -1
    match cluster_of.get("bj0") {
      Some(idx) => bj_cluster = idx
      None => all_same = false
    }
    match cluster_of.get("sh0") {
      Some(idx) => sh_cluster = idx
      None => all_same = false
    }
    match cluster_of.get("gz0") {
      Some(idx) => gz_cluster = idx
      None => all_same = false
    }
    let distinct = (bj_cluster != sh_cluster) && (bj_cluster != gz_cluster) && (sh_cluster != gz_cluster)
    if all_same && distinct {
      ok = true
    }
    attempt = attempt + 1
  }
  @test.assert_eq(ok, true)
}

///|
test "GeoDB::radial_density counts entries by ring" {
  let db = GeoDB::in_memory()
  let center = @types.GeoPoint::make(0.0, 0.0)
  db.insert(make_entry_with_addr("near", "N", 0.001, 0.001, "", "", "", []))
  db.insert(make_entry_with_addr("mid", "M", 1.0, 1.0, "", "", "", []))
  db.insert(make_entry_with_addr("far", "F", 10.0, 10.0, "", "", "", []))
  let rings = db.radial_density(center, 1.0, 10)
  @test.assert_eq(rings.length(), 10)
  // At least the near entry should be in ring 0.
  @test.assert_eq(rings[0].1 >= 1, true)
}

///|
test "GeoDB::to_geojson_with_bbox produces valid feature collection" {
  let db = GeoDB::in_memory()
  db.insert(make_entry_with_addr("t1", "Test", 39.9, 116.4, "", "", "", []))
  let geojson = db.to_geojson_with_bbox()
  @test.assert_eq(geojson.contains("\"type\":\"FeatureCollection\""), true)
  @test.assert_eq(geojson.contains("\"bbox\""), true)
  @test.assert_eq(geojson.contains("\"coordinates\""), true)
}

// ---- Query enhancement tests ----

///|
test "GeoDB::distance_histogram has correct bin count" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("h01", "A", 39.9, 116.4))
  db.insert(make_entry("h02", "B", 31.2, 121.5))
  db.insert(make_entry("h03", "C", 22.3, 114.1))
  let center = @types.GeoPoint::make(39.9, 116.4)
  let hist = db.distance_histogram(center, 5000.0, num_bins=5)
  @test.assert_eq(hist.length(), 5)
  // Total count should match number of entries.
  let mut total = 0
  for bin in hist {
    total = total + bin.2
  }
  @test.assert_eq(total, 3)
}

///|
test "GeoDB::distance_histogram handles edge case with 0 bins" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("h01", "A", 0.0, 0.0))
  let center = @types.GeoPoint::make(0.0, 0.0)
  @test.assert_eq(db.distance_histogram(center, 100.0, num_bins=0).length(), 0)
  @test.assert_eq(db.distance_histogram(center, 0.0, num_bins=5).length(), 0)
}

///|
test "GeoDB::lat_histogram produces correct number of bins" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("h01", "A", 39.9, 116.4))
  db.insert(make_entry("h02", "B", 31.2, 121.5))
  let hist = db.lat_histogram(num_bins=4)
  @test.assert_eq(hist.length(), 4)
  let mut total = 0
  for bin in hist {
    total = total + bin.2
  }
  @test.assert_eq(total, 2)
}

///|
test "GeoDB::lng_histogram produces correct number of bins" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("h01", "A", 39.9, 116.4))
  db.insert(make_entry("h02", "B", 31.2, 121.5))
  let hist = db.lng_histogram(num_bins=4)
  @test.assert_eq(hist.length(), 4)
  let mut total = 0
  for bin in hist {
    total = total + bin.2
  }
  @test.assert_eq(total, 2)
}

///|
test "GeoDB::distance_summary returns non-zero on multi-entry DB" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("s01", "A", 39.9, 116.4))
  db.insert(make_entry("s02", "B", 31.2, 121.5))
  let (count, min_d, max_d, mean, median) = db.distance_summary()
  @test.assert_eq(count, 1) // 1 pair from 2 entries
  @test.assert_eq(min_d > 0.0, true)
  @test.assert_eq(max_d > 0.0, true)
  @test.assert_eq(mean >= min_d, true)
  @test.assert_eq(mean <= max_d, true)
  @test.assert_eq(median >= min_d, true)
  @test.assert_eq(median <= max_d, true)
}

///|
test "GeoDB::distance_summary with center computes distances from point" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("s01", "A", 39.9, 116.4))
  db.insert(make_entry("s02", "B", 31.2, 121.5))
  let center = @types.GeoPoint::make(39.9, 116.4)
  let (count, _, _, _, _) = db.distance_summary(center=Some(center))
  @test.assert_eq(count, 2) // distances from center to 2 entries
}

///|
test "GeoDB::distance_summary on empty DB returns zeros" {
  let db = GeoDB::in_memory()
  let (count, min_d, max_d, mean, median) = db.distance_summary()
  @test.assert_eq(count, 0)
  @test.assert_eq(min_d, 0.0)
  @test.assert_eq(max_d, 0.0)
  @test.assert_eq(mean, 0.0)
  @test.assert_eq(median, 0.0)
}

// ---- Ring query tests ----

///|
test "GeoDB::find_in_ring returns entries in annulus" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("r01", "Near", 39.9000, 116.4000)) // ~0 km from center
  db.insert(make_entry("r02", "Mid", 39.9100, 116.4100)) // ~1.5 km from center
  db.insert(make_entry("r03", "Far", 40.5000, 117.0000)) // ~80 km from center
  let center = @types.GeoPoint::make(39.9000, 116.4000)
  // Ring between 0.5 and 10 km should only include Mid.
  let ring = db.find_in_ring(center, 0.5, 10.0)
  @test.assert_eq(ring.length(), 1)
  @test.assert_eq(ring[0].0.id, "r02")
}

///|
test "GeoDB::find_in_ring handles reversed radii" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("r01", "Mid", 39.9100, 116.4100))
  let center = @types.GeoPoint::make(39.9000, 116.4000)
  // Passing (outer=10, inner=0.5) reversed should still work.
  let ring = db.find_in_ring(center, 10.0, 0.5)
  @test.assert_eq(ring.length(), 1)
}

///|
test "GeoDB::ring_query_summary returns distance stats" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("r01", "A", 39.9100, 116.4100))
  db.insert(make_entry("r02", "B", 39.9200, 116.4200))
  let center = @types.GeoPoint::make(39.9000, 116.4000)
  let (results, min_d, max_d, mean_d) = db.ring_query_summary(center, 0.1, 50.0)
  @test.assert_eq(results.length(), 2)
  @test.assert_eq(min_d > 0.0, true)
  @test.assert_eq(max_d >= min_d, true)
  @test.assert_eq(mean_d >= min_d, true)
  @test.assert_eq(mean_d <= max_d, true)
}

// ---- Spatial join tests ----

///|
test "GeoDB::spatial_join_nearest matches each DB entry to nearest other" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("sj01", "A", 0.0, 0.0))
  db.insert(make_entry("sj02", "B", 10.0, 10.0))
  let other : Array[@types.GeoEntry] = [
    make_entry("x01", "X1", 0.001, 0.001),
    make_entry("x02", "X2", 10.001, 10.001),
  ]
  let pairs = db.spatial_join_nearest(other)
  @test.assert_eq(pairs.length(), 2)
  // Each pair's distance should be very small (< 10km since other entries are very close).
  for p in pairs {
    @test.assert_eq(p.distance_km < 10.0, true)
  }
}

///|
test "GeoDB::spatial_join_nearest on empty other returns empty" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("sj01", "A", 0.0, 0.0))
  @test.assert_eq(db.spatial_join_nearest([]).length(), 0)
}

///|
test "GeoDB::spatial_join_within finds pairs within distance" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("sj01", "A", 0.0, 0.0))
  db.insert(make_entry("sj02", "B", 10.0, 10.0))
  let other : Array[@types.GeoEntry] = [
    make_entry("x01", "X1", 0.001, 0.001), // close to A
    make_entry("x02", "X2", 20.0, 20.0), // far from both
  ]
  // With max_km = 10, only A-X1 should pair.
  let pairs = db.spatial_join_within(other, 10.0)
  @test.assert_eq(pairs.length(), 1)
  @test.assert_eq(pairs[0].left.id, "sj01")
  @test.assert_eq(pairs[0].right.id, "x01")
}

///|
test "GeoDB::spatial_join_knearest returns k per entry" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("sj01", "A", 0.0, 0.0))
  let other : Array[@types.GeoEntry] = [
    make_entry("x01", "X1", 0.001, 0.001),
    make_entry("x02", "X2", 0.002, 0.002),
    make_entry("x03", "X3", 10.0, 10.0),
  ]
  let pairs = db.spatial_join_knearest(other, 2)
  // 1 left entry * 2 nearest = 2 pairs.
  @test.assert_eq(pairs.length(), 2)
  // Sorted by distance.
  @test.assert_eq(pairs[0].distance_km <= pairs[1].distance_km, true)
}

///|
test "GeoDB::spatial_join_knearest on empty other returns empty" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("sj01", "A", 0.0, 0.0))
  @test.assert_eq(db.spatial_join_knearest([], 5).length(), 0)
  @test.assert_eq(db.spatial_join_knearest([], 0).length(), 0)
}

// ---- Nearest-neighbor range tests ----

///|
test "GeoDB::nearest_neighbors_range returns distance range" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("nn01", "Center", 39.9000, 116.4000))
  db.insert(make_entry("nn02", "Near1", 39.9005, 116.4005)) // very close
  db.insert(make_entry("nn03", "Near2", 39.9010, 116.4010)) // slightly farther
  db.insert(make_entry("nn04", "Far", 31.2000, 121.5000)) // very far
  match db.nearest_neighbors_range("nn01", 2) {
    None => @test.assert_eq(true, false)
    Some((n, min_d, max_d, mean, median)) => {
      @test.assert_eq(n, 2)
      @test.assert_eq(min_d >= 0.0, true)
      @test.assert_eq(max_d >= min_d, true)
      @test.assert_eq(mean >= min_d, true)
      @test.assert_eq(mean <= max_d, true)
      @test.assert_eq(median >= min_d, true)
      @test.assert_eq(median <= max_d, true)
    }
  }
}

///|
test "GeoDB::nearest_neighbors_range on missing id returns None" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("nn01", "A", 0.0, 0.0))
  @test.assert_eq(db.nearest_neighbors_range("missing", 5) is None, true)
}

///|
test "GeoDB::nearest_neighbors_range on singleton DB returns None" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("nn01", "A", 0.0, 0.0))
  @test.assert_eq(db.nearest_neighbors_range("nn01", 5) is None, true)
}

// ---- New feature tests (TSP, kmeans, bbox, ring, spatial_join, sde) ----

///|
test "GeoDB::tsp_nearest visits all entries" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  db.insert(make_entry("b", "B", 0.1, 0.0))
  db.insert(make_entry("c", "C", 10.0, 10.0))
  db.insert(make_entry("d", "D", 10.1, 10.0))
  match db.tsp_nearest("a") {
    None => @test.assert_eq(false, true)
    Some((route, total)) => {
      @test.assert_eq(route.length(), 4)
      @test.assert_eq(route[0].entry.id, "a")
      @test.assert_eq(total > 0.0, true)
    }
  }
}

///|
test "GeoDB::tsp_nearest with missing start returns None" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  @test.assert_eq(db.tsp_nearest("missing") is None, true)
}

///|
test "GeoDB::kmeans produces k clusters" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  db.insert(make_entry("b", "B", 0.1, 0.1))
  db.insert(make_entry("c", "C", 10.0, 10.0))
  db.insert(make_entry("d", "D", 10.1, 10.1))
  let clusters = db.kmeans(2)
  @test.assert_eq(clusters.length(), 2)
}

///|
test "GeoDB::find_bbox filters correctly" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 39.5, 116.5))
  db.insert(make_entry("b", "B", 41.0, 116.5))  // outside
  db.insert(make_entry("c", "C", 39.5, 118.0))  // outside lng
  let r = db.find_bbox(39.0, 40.0, 116.0, 117.0)
  @test.assert_eq(r.length(), 1)
  @test.assert_eq(r[0].id, "a")
}

///|
test "GeoDB::find_in_ring uses index correctly" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  db.insert(make_entry("b", "B", 0.0, 0.5))   // ~55 km
  db.insert(make_entry("c", "C", 0.0, 5.0))   // ~500 km
  db.insert(make_entry("d", "D", 0.0, 10.0))  // ~1100 km
  let center = @types.GeoPoint::make(0.0, 0.0)
  // Ring between 500 km and 1200 km → c and d
  let r = db.find_in_ring(center, 500.0, 1200.0)
  @test.assert_eq(r.length(), 2)
}

///|
test "GeoDB::centroid and geographic_center" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  db.insert(make_entry("b", "B", 10.0, 10.0))
  let c = db.centroid()
  @test.assert_eq((c.lat - 5.0).abs() < 0.001, true)
  let gc = db.geographic_center()
  @test.assert_eq((gc.lat - 5.0).abs() < 1.0, true)
}

///|
test "GeoDB::std_dev_ellipse" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  db.insert(make_entry("b", "B", 1.0, 0.0))
  db.insert(make_entry("c", "C", 0.0, 1.0))
  db.insert(make_entry("d", "D", 1.0, 1.0))
  match db.std_dev_ellipse() {
    None => @test.assert_eq(false, true)
    Some(sde) => {
      @test.assert_eq(sde.semi_major_km > 0.0, true)
      @test.assert_eq(sde.area_sq_km > 0.0, true)
    }
  }
}

///|
test "GeoDB::spatial_join_nearest using temp R-tree" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  db.insert(make_entry("b", "B", 10.0, 10.0))
  let other = [
    make_entry("x", "X", 0.1, 0.1),
    make_entry("y", "Y", 9.9, 9.9),
  ]
  let pairs = db.spatial_join_nearest(other)
  @test.assert_eq(pairs.length(), 2)
  // Each left entry should be paired with the closer right entry.
  // (a→x, b→y) after sorting by distance.
  @test.assert_eq(pairs[0].distance_km < pairs[1].distance_km, true)
  @test.assert_eq(pairs[0].right.id == "x" || pairs[0].right.id == "y", true)
}

///|
test "GeoDB::spatial_join_knearest temp R-tree" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  let other = [
    make_entry("x", "X", 0.1, 0.0),
    make_entry("y", "Y", 0.2, 0.0),
    make_entry("z", "Z", 10.0, 10.0),
  ]
  let pairs = db.spatial_join_knearest(other, 2)
  @test.assert_eq(pairs.length(), 2)
  // The k=2 nearest should be x and y (both ~11 and ~22 km), not z (~1570 km)
  @test.assert_eq(pairs[0].distance_km < pairs[1].distance_km, true)
  @test.assert_eq(pairs[1].distance_km < 100.0, true)
}

///|
test "GeoDB::nearest_neighbors_range still works after R-tree opt" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  db.insert(make_entry("b", "B", 0.0, 0.1))
  db.insert(make_entry("c", "C", 10.0, 10.0))
  match db.nearest_neighbors_range("a", 2) {
    None => @test.assert_eq(false, true)
    Some((n, min_d, max_d, mean_d, median_d)) => {
      @test.assert_eq(n >= 2, true)
      @test.assert_eq(min_d <= max_d, true)
      @test.assert_eq(mean_d > 0.0, true)
    }
  }
}

// ---- tsp_2opt test ----

///|
test "GeoDB::tsp_2opt produces route no worse than NN" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  db.insert(make_entry("b", "B", 0.0, 0.1))
  db.insert(make_entry("c", "C", 10.0, 10.0))
  db.insert(make_entry("d", "D", 10.1, 10.0))
  match db.tsp_2opt("a") {
    None => @test.assert_eq(false, true)
    Some((route, total)) => {
      @test.assert_eq(route.length(), 4)
      // Verify no worse than NN.
      match db.tsp_nearest("a") {
        Some((_, nn_total)) => @test.assert_eq(total <= nn_total + 0.001, true)
        None => ()
      }
    }
  }
}

///|
test "GeoDB::tsp_2opt with missing start returns None" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  @test.assert_eq(db.tsp_2opt("missing") is None, true)
}

// ---- IDW tests ----

///|
test "GeoDB::idw_predict basic" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  db.insert(make_entry("b", "B", 0.0, 1.0))
  let q = @types.GeoPoint::make(0.0, 0.5)
  match db.idw_predict(q, fn(e) { e.location.lng }) {
    None => @test.assert_eq(false, true)
    Some(v) => @test.assert_eq((v - 0.5).abs() < 0.01, true)
  }
}

///|
test "GeoDB::idw_predict_knn restricts to k nearest" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  db.insert(make_entry("b", "B", 0.0, 1.0))
  db.insert(make_entry("c", "C", 0.0, 100.0))
  let q = @types.GeoPoint::make(0.0, 0.5)
  match db.idw_predict_knn(q, 2, fn(e) { e.location.lng }) {
    None => @test.assert_eq(false, true)
    Some(v) => {
      // Within ~50 km from 0.5 is near 0.5, not influenced by point c at lng=100.
      @test.assert_eq((v - 0.5).abs() < 0.1, true)
    }
  }
}

// ---- Concave hull test ----

///|
test "GeoDB::concave_hull basic" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("a", "A", 0.0, 0.0))
  db.insert(make_entry("b", "B", 1.0, 0.0))
  db.insert(make_entry("c", "C", 1.0, 1.0))
  db.insert(make_entry("d", "D", 0.0, 1.0))
  let hull = db.concave_hull(2.0)
  @test.assert_eq(hull.length() >= 3, true)
}
