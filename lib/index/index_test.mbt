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

test "Index::new has size 0" {
  let idx = Index::new()
  @test.assert_eq(idx.size(), 0)
}

test "Index::insert and get by id" {
  let idx = Index::new()
  let e = make_entry("p01", "Tiananmen", 39.9087, 116.3975)
  idx.insert(e)
  @test.assert_eq(idx.size(), 1)
  @test.assert_eq(idx.get("p01") is Some, true)
  @test.assert_eq(idx.get("missing") is None, true)
}

test "Index::insert replaces same id" {
  let idx = Index::new()
  idx.insert(make_entry("p01", "Old", 0.0, 0.0))
  idx.insert(make_entry("p01", "New", 1.0, 1.0))
  @test.assert_eq(idx.size(), 1)
  match idx.get("p01") {
    Some(e) => @test.assert_eq(e.name, "New")
    None => @test.assert_eq(true, false)
  }
}

test "Index::remove returns the entry" {
  let idx = Index::new()
  let e = make_entry("p01", "X", 10.0, 20.0)
  idx.insert(e)
  let removed = idx.remove("p01")
  @test.assert_eq(removed is Some, true)
  @test.assert_eq(idx.size(), 0)
  @test.assert_eq(idx.remove("p01") is None, true)
}

test "Index::find_by_name case-insensitive" {
  let idx = Index::new()
  idx.insert(make_entry("p01", "Tiananmen", 39.9, 116.4))
  @test.assert_eq(idx.find_by_name("tiananmen").length(), 1)
  @test.assert_eq(idx.find_by_name("TIANANMEN").length(), 1)
  @test.assert_eq(idx.find_by_name("missing").length(), 0)
}

test "Index::find_name_prefix" {
  let idx = Index::new()
  idx.insert(make_entry("p01", "Tiananmen", 39.9, 116.4))
  idx.insert(make_entry("p02", "Tianjin", 39.1, 117.2))
  idx.insert(make_entry("p03", "Shanghai", 31.2, 121.5))
  @test.assert_eq(idx.find_name_prefix("Tian").length(), 2)
  @test.assert_eq(idx.find_name_prefix("tian").length(), 2)
  @test.assert_eq(idx.find_name_prefix("Sha").length(), 1)
  @test.assert_eq(idx.find_name_prefix("").length(), 0)
}

test "Index::find_name_contains" {
  let idx = Index::new()
  idx.insert(make_entry("p01", "Tiananmen Square", 39.9, 116.4))
  idx.insert(make_entry("p02", "Tianjin", 39.1, 117.2))
  @test.assert_eq(idx.find_name_contains("an").length(), 2)
  @test.assert_eq(idx.find_name_contains("men").length(), 1)
  @test.assert_eq(idx.find_name_contains("xyz").length(), 0)
  @test.assert_eq(idx.find_name_contains("").length(), 0)
}

test "Index::query_bbox returns only contained entries" {
  let idx = Index::new()
  idx.insert(make_entry("p01", "Beijing", 39.9, 116.4))
  idx.insert(make_entry("p02", "Shanghai", 31.2, 121.5))
  idx.insert(make_entry("p03", "Tianjin", 39.1, 117.2))
  let bbox : @types.BBox = {
    min_lat: 39.0,
    max_lat: 40.0,
    min_lng: 116.0,
    max_lng: 117.5
  }
  let result = idx.query_bbox(bbox)
  @test.assert_eq(result.length(), 2)
}

test "Index::query_bbox empty region returns nothing" {
  let idx = Index::new()
  idx.insert(make_entry("p01", "Beijing", 39.9, 116.4))
  let bbox : @types.BBox = {
    min_lat: 0.0,
    max_lat: 1.0,
    min_lng: 0.0,
    max_lng: 1.0
  }
  @test.assert_eq(idx.query_bbox(bbox).length(), 0)
}

test "Index::query_nearest returns sorted ascending" {
  let idx = Index::new()
  idx.insert(make_entry("p01", "Shanghai", 31.2304, 121.4737))
  idx.insert(make_entry("p02", "Tianjin", 39.0842, 117.2009))
  idx.insert(make_entry("p03", "Beijing", 39.9042, 116.4074))
  let beijing = @types.GeoPoint::make(39.9042, 116.4074)
  let near = idx.query_nearest(beijing, 2)
  @test.assert_eq(near.length(), 2)
  // Closest to Beijing should be Beijing itself (distance 0).
  match near[0] {
    (e, d) => {
      @test.assert_eq(e.id, "p03")
      @test.assert_eq(d < 1.0, true)
    }
  }
}

test "Index::query_nearest with k=0 returns empty" {
  let idx = Index::new()
  idx.insert(make_entry("p01", "X", 0.0, 0.0))
  @test.assert_eq(idx.query_nearest(@types.GeoPoint::make(0.0, 0.0), 0).length(), 0)
}

test "Index::query_nearest with k > size returns all" {
  let idx = Index::new()
  idx.insert(make_entry("p01", "A", 0.0, 0.0))
  idx.insert(make_entry("p02", "B", 1.0, 1.0))
  let near = idx.query_nearest(@types.GeoPoint::make(0.0, 0.0), 10)
  @test.assert_eq(near.length(), 2)
}

test "Index::to_array is a snapshot" {
  let idx = Index::new()
  idx.insert(make_entry("p01", "A", 0.0, 0.0))
  let snap = idx.to_array()
  idx.insert(make_entry("p02", "B", 1.0, 1.0))
  @test.assert_eq(snap.length(), 1)
  @test.assert_eq(idx.size(), 2)
}

test "Index::remove updates name index" {
  let idx = Index::new()
  idx.insert(make_entry("p01", "Tiananmen", 39.9, 116.4))
  @test.assert_eq(idx.find_by_name("tiananmen").length(), 1)
  ignore(idx.remove("p01"))
  @test.assert_eq(idx.find_by_name("tiananmen").length(), 0)
}
