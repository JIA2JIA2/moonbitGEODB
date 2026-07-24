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

test "GeoDB::to_json and from_json round-trip" {
  let db = GeoDB::in_memory()
  db.insert(make_entry("p01", "Beijing", 39.9042, 116.4074))
  db.insert(make_entry("p02", "Shanghai", 31.2304, 121.4737))
  let text = db.to_json()
  let db2 = GeoDB::in_memory()
  match db2.from_json(text) {
    Err(_) => @test.assert_eq(true, false)
    Ok(_) => @test.assert_eq(db2.size(), 2)
  }
}

test "GeoDB::save_to and open round-trip" {
  let path = "/tmp/geodb_test_save_load.json"
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
  let db = GeoDB::open("/tmp/geodb_does_not_exist_xyz.json")
  @test.assert_eq(db.size(), 0)
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
