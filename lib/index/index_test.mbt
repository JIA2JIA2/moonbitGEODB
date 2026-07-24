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

// ---- Tag query tests ----

fn make_entry_with_tags(
  id : String,
  name : String,
  lat : Double,
  lng : Double,
  tags : Array[String]
) -> @types.GeoEntry {
  let e = @types.GeoEntry::make(
    id,
    name,
    @types.Address::empty(),
    @types.GeoPoint::make(lat, lng),
  )
  e.tags = tags
  e
}

fn make_entry_with_address(
  id : String,
  name : String,
  lat : Double,
  lng : Double,
  province : String,
  city : String,
  district : String
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
  @types.GeoEntry::make(
    id,
    name,
    addr,
    @types.GeoPoint::make(lat, lng),
  )
}

test "Index::find_by_tag single tag" {
  let idx = Index::new()
  idx.insert(make_entry_with_tags("p01", "A", 0.0, 0.0, ["poi", "landmark"]))
  idx.insert(make_entry_with_tags("p02", "B", 1.0, 1.0, ["poi", "transport"]))
  idx.insert(make_entry_with_tags("p03", "C", 2.0, 2.0, ["medical"]))
  @test.assert_eq(idx.find_by_tag("poi").length(), 2)
  @test.assert_eq(idx.find_by_tag("medical").length(), 1)
  @test.assert_eq(idx.find_by_tag("nonexistent").length(), 0)
  // Case-insensitive
  @test.assert_eq(idx.find_by_tag("POI").length(), 2)
}

test "Index::find_by_all_tags AND logic" {
  let idx = Index::new()
  idx.insert(make_entry_with_tags("p01", "A", 0.0, 0.0, ["poi", "landmark", "attraction"]))
  idx.insert(make_entry_with_tags("p02", "B", 1.0, 1.0, ["poi", "landmark"]))
  idx.insert(make_entry_with_tags("p03", "C", 2.0, 2.0, ["poi"]))
  // Both tags must be present
  let result = idx.find_by_all_tags(["poi", "landmark"])
  @test.assert_eq(result.length(), 2)
  // All three tags must be present
  let result2 = idx.find_by_all_tags(["poi", "landmark", "attraction"])
  @test.assert_eq(result2.length(), 1)
  // Empty tags returns all
  let result3 = idx.find_by_all_tags([])
  @test.assert_eq(result3.length(), 3)
}

test "Index::find_by_any_tags OR logic" {
  let idx = Index::new()
  idx.insert(make_entry_with_tags("p01", "A", 0.0, 0.0, ["poi", "landmark"]))
  idx.insert(make_entry_with_tags("p02", "B", 1.0, 1.0, ["transport"]))
  idx.insert(make_entry_with_tags("p03", "C", 2.0, 2.0, ["medical"]))
  // Any of these tags
  let result = idx.find_by_any_tags(["poi", "transport"])
  @test.assert_eq(result.length(), 2)
  // Empty tags returns empty
  let result2 = idx.find_by_any_tags([])
  @test.assert_eq(result2.length(), 0)
}

test "Index::list_tags returns sorted unique tags" {
  let idx = Index::new()
  idx.insert(make_entry_with_tags("p01", "A", 0.0, 0.0, ["zebra", "apple"]))
  idx.insert(make_entry_with_tags("p02", "B", 1.0, 1.0, ["apple", "mango"]))
  let tags = idx.list_tags()
  @test.assert_eq(tags.length(), 3)
  @test.assert_eq(tags[0], "apple")
  @test.assert_eq(tags[1], "mango")
  @test.assert_eq(tags[2], "zebra")
}

test "Index::remove updates tag index" {
  let idx = Index::new()
  idx.insert(make_entry_with_tags("p01", "A", 0.0, 0.0, ["poi", "landmark"]))
  @test.assert_eq(idx.find_by_tag("poi").length(), 1)
  ignore(idx.remove("p01"))
  @test.assert_eq(idx.find_by_tag("poi").length(), 0)
  @test.assert_eq(idx.list_tags().length(), 0)
}

// ---- Address query tests ----

test "Index::find_by_province" {
  let idx = Index::new()
  idx.insert(make_entry_with_address("p01", "A", 39.9, 116.4, "北京市", "北京市", "海淀区"))
  idx.insert(make_entry_with_address("p02", "B", 31.2, 121.5, "上海市", "上海市", "浦东新区"))
  idx.insert(make_entry_with_address("p03", "C", 39.1, 117.2, "天津市", "天津市", "和平区"))
  @test.assert_eq(idx.find_by_province("北京市").length(), 1)
  @test.assert_eq(idx.find_by_province("上海市").length(), 1)
  @test.assert_eq(idx.find_by_province("天津市").length(), 1)
  @test.assert_eq(idx.find_by_province("nonexistent").length(), 0)
}

test "Index::find_by_city" {
  let idx = Index::new()
  idx.insert(make_entry_with_address("p01", "A", 39.9, 116.4, "北京市", "北京市", "海淀区"))
  idx.insert(make_entry_with_address("p02", "B", 31.2, 121.5, "上海市", "上海市", "浦东新区"))
  idx.insert(make_entry_with_address("p03", "C", 23.1, 113.3, "广东省", "广州市", "天河区"))
  @test.assert_eq(idx.find_by_city("北京市").length(), 1)
  @test.assert_eq(idx.find_by_city("广州市").length(), 1)
  @test.assert_eq(idx.find_by_city("nonexistent").length(), 0)
}

test "Index::find_by_district" {
  let idx = Index::new()
  idx.insert(make_entry_with_address("p01", "A", 39.9, 116.4, "北京市", "北京市", "海淀区"))
  idx.insert(make_entry_with_address("p02", "B", 39.9, 116.4, "北京市", "北京市", "东城区"))
  idx.insert(make_entry_with_address("p03", "C", 31.2, 121.5, "上海市", "上海市", "浦东新区"))
  @test.assert_eq(idx.find_by_district("海淀区").length(), 1)
  @test.assert_eq(idx.find_by_district("东城区").length(), 1)
  @test.assert_eq(idx.find_by_district("浦东新区").length(), 1)
  @test.assert_eq(idx.find_by_district("nonexistent").length(), 0)
}

test "Index::find_by_province_city compound" {
  let idx = Index::new()
  idx.insert(make_entry_with_address("p01", "A", 39.9, 116.4, "北京市", "北京市", "海淀区"))
  idx.insert(make_entry_with_address("p02", "B", 31.2, 121.5, "北京市", "上海市", "浦东新区"))
  idx.insert(make_entry_with_address("p03", "C", 23.1, 113.3, "广东省", "广州市", "天河区"))
  // Only p01 matches both 北京市 AND 北京市
  let result = idx.find_by_province_city("北京市", "北京市")
  @test.assert_eq(result.length(), 1)
  @test.assert_eq(result[0].id, "p01")
  // p03 matches 广东省 AND 广州市
  let result2 = idx.find_by_province_city("广东省", "广州市")
  @test.assert_eq(result2.length(), 1)
  // No match for 北京市 AND 广州市
  let result3 = idx.find_by_province_city("北京市", "广州市")
  @test.assert_eq(result3.length(), 0)
}

test "Index::list_provinces returns sorted unique" {
  let idx = Index::new()
  idx.insert(make_entry_with_address("p01", "A", 39.9, 116.4, "北京市", "北京市", "海淀区"))
  idx.insert(make_entry_with_address("p02", "B", 31.2, 121.5, "上海市", "上海市", "浦东新区"))
  idx.insert(make_entry_with_address("p03", "C", 23.1, 113.3, "广东省", "广州市", "天河区"))
  let provinces = idx.list_provinces()
  @test.assert_eq(provinces.length(), 3)
  // Sort order follows Unicode code points: 上 (4E0A) < 北 (5317) < 广 (5E7F)
  @test.assert_eq(provinces[0], "上海市")
  @test.assert_eq(provinces[1], "北京市")
  @test.assert_eq(provinces[2], "广东省")
}

test "Index::list_cities returns sorted unique" {
  let idx = Index::new()
  idx.insert(make_entry_with_address("p01", "A", 39.9, 116.4, "北京市", "北京市", "海淀区"))
  idx.insert(make_entry_with_address("p02", "B", 31.2, 121.5, "上海市", "上海市", "浦东新区"))
  idx.insert(make_entry_with_address("p03", "C", 23.1, 113.3, "广东省", "广州市", "天河区"))
  let cities = idx.list_cities()
  @test.assert_eq(cities.length(), 3)
  @test.assert_eq(cities[0], "上海市")
  @test.assert_eq(cities[1], "北京市")
  @test.assert_eq(cities[2], "广州市")
}

test "Index::remove updates address indexes" {
  let idx = Index::new()
  idx.insert(make_entry_with_address("p01", "A", 39.9, 116.4, "北京市", "北京市", "海淀区"))
  @test.assert_eq(idx.find_by_province("北京市").length(), 1)
  @test.assert_eq(idx.find_by_city("北京市").length(), 1)
  @test.assert_eq(idx.find_by_district("海淀区").length(), 1)
  ignore(idx.remove("p01"))
  @test.assert_eq(idx.find_by_province("北京市").length(), 0)
  @test.assert_eq(idx.find_by_city("北京市").length(), 0)
  @test.assert_eq(idx.find_by_district("海淀区").length(), 0)
  @test.assert_eq(idx.list_provinces().length(), 0)
}
