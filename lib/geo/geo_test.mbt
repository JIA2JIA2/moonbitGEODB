// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

test "haversine - same point is zero" {
  let p = @types.GeoPoint::make(39.9, 116.4)
  let d = haversine(p, p)
  @test.assert_eq(d < 0.000001, true)
}

test "haversine - Beijing to Shanghai ~1067 km" {
  let beijing = @types.GeoPoint::make(39.9042, 116.4074)
  let shanghai = @types.GeoPoint::make(31.2304, 121.4737)
  let d = haversine(beijing, shanghai)
  // Real-world distance is ~1067 km; allow ±5 km tolerance.
  @test.assert_eq(d > 1062.0 && d < 1072.0, true)
}

test "haversine - antipodal distance ~20015 km" {
  // Two antipodal points: (0, 0) and (0, 180).
  let a = @types.GeoPoint::make(0.0, 0.0)
  let b = @types.GeoPoint::make(0.0, 180.0)
  let d = haversine(a, b)
  // Half circumference of Earth ≈ π * 6371.0088 ≈ 20015.09 km.
  @test.assert_eq(d > 20010.0 && d < 20020.0, true)
}

test "bbox_contains - inside" {
  let bbox : @types.BBox = {
    min_lat: 39.0,
    max_lat: 40.0,
    min_lng: 116.0,
    max_lng: 117.0
  }
  let p = @types.GeoPoint::make(39.5, 116.5)
  @test.assert_eq(bbox_contains(bbox, p), true)
}

test "bbox_contains - outside" {
  let bbox : @types.BBox = {
    min_lat: 39.0,
    max_lat: 40.0,
    min_lng: 116.0,
    max_lng: 117.0
  }
  let p = @types.GeoPoint::make(38.5, 116.5)
  @test.assert_eq(bbox_contains(bbox, p), false)
}

test "bbox_around - center is contained" {
  let center = @types.GeoPoint::make(39.9, 116.4)
  let bbox = bbox_around(center, 10.0)
  @test.assert_eq(bbox_contains(bbox, center), true)
}

test "bbox_intersect - overlapping" {
  let a : @types.BBox = {
    min_lat: 0.0,
    max_lat: 10.0,
    min_lng: 0.0,
    max_lng: 10.0
  }
  let b : @types.BBox = {
    min_lat: 5.0,
    max_lat: 15.0,
    min_lng: 5.0,
    max_lng: 15.0
  }
  let i = bbox_intersect(a, b)
  @test.assert_eq(i is Some, true)
}

test "bbox_intersect - disjoint" {
  let a : @types.BBox = {
    min_lat: 0.0,
    max_lat: 1.0,
    min_lng: 0.0,
    max_lng: 1.0
  }
  let b : @types.BBox = {
    min_lat: 5.0,
    max_lat: 6.0,
    min_lng: 5.0,
    max_lng: 6.0
  }
  @test.assert_eq(bbox_intersect(a, b) is None, true)
}

test "bearing - due east is 90°" {
  let a = @types.GeoPoint::make(0.0, 0.0)
  let b = @types.GeoPoint::make(0.0, 1.0)
  let brg = bearing(a, b)
  @test.assert_eq(brg > 89.5 && brg < 90.5, true)
}

test "bearing - due north is 0°" {
  let a = @types.GeoPoint::make(0.0, 0.0)
  let b = @types.GeoPoint::make(1.0, 0.0)
  let brg = bearing(a, b)
  @test.assert_eq(brg < 0.5 || brg > 359.5, true)
}
