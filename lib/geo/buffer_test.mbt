// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

///|
fn bf_pt(lat : Double, lng : Double) -> @types.GeoPoint {
  @types.GeoPoint::make(lat, lng)
}

///|
test "destination_point - due north/south/east/west" {
  let origin = bf_pt(0.0, 0.0)
  let d = 111.195 // ≈ 1 degree of arc
  // North: bearing 0 → lat +1, lng 0.
  let north = destination_point(origin, 0.0, d)
  @test.assert_eq((north.lat - 1.0).abs() < 0.01, true)
  @test.assert_eq(north.lng.abs() < 0.01, true)
  // East: bearing 90 → lat 0, lng +1.
  let east = destination_point(origin, 90.0, d)
  @test.assert_eq(east.lat.abs() < 0.01, true)
  @test.assert_eq((east.lng - 1.0).abs() < 0.01, true)
  // South: bearing 180 → lat -1.
  let south = destination_point(origin, 180.0, d)
  @test.assert_eq((south.lat + 1.0).abs() < 0.01, true)
  // West: bearing 270 → lng -1.
  let west = destination_point(origin, 270.0, d)
  @test.assert_eq((west.lng + 1.0).abs() < 0.01, true)
}

///|
test "destination_point - distance and bearing round-trip" {
  let origin = bf_pt(39.9, 116.4)
  let brg = 37.5
  let dist = 250.0
  let dest = destination_point(origin, brg, dist)
  // Distance from origin should equal the requested distance.
  @test.assert_eq((haversine(origin, dest) - dist).abs() < 0.001, true)
  // Initial bearing should match the requested bearing.
  let back = bearing(origin, dest)
  let diff = (back - brg + 180.0) % 360.0 - 180.0
  @test.assert_eq(diff.abs() < 0.001, true)
}

///|
test "buffer_point - square approximation" {
  let center = bf_pt(0.0, 0.0)
  let radius = 111.195
  let ring = buffer_point(center, radius, segments = 4)
  // 4 segments + closing vertex → 5 points.
  @test.assert_eq(ring.length(), 5)
  // Every vertex (except closing duplicate) lies ~radius from center.
  let mut i = 0
  while i < 4 {
    @test.assert_eq((haversine(center, ring[i]) - radius).abs() < 0.01, true)
    i = i + 1
  }
  // Closed ring: first == last.
  @test.assert_eq(ring[0].lat == ring[4].lat, true)
  @test.assert_eq(ring[0].lng == ring[4].lng, true)
}

///|
test "buffer_point - minimum segment count" {
  let center = bf_pt(10.0, 20.0)
  let ring = buffer_point(center, 5.0, segments = 1)
  // segments < 3 clamps to 3 → 3 + closing = 4 points.
  @test.assert_eq(ring.length(), 4)
}

///|
test "buffer_polygon - single point degenerates to buffer_point" {
  let pts = [bf_pt(0.0, 0.0)]
  let ring = buffer_polygon(pts, 10.0, segments = 8)
  @test.assert_eq(ring.length() >= 3, true)
  // Should be a small polygon around the origin.
  for p in ring {
    @test.assert_eq(haversine(bf_pt(0.0, 0.0), p) <= 10.1, true)
  }
}

///|
test "buffer_polygon - empty returns empty" {
  @test.assert_eq(buffer_polygon([], 5.0).length(), 0)
}

///|
test "buffer_point - circle has N distinct cap vertices" {
  let center = bf_pt(31.0, 121.0)
  let radius = 50.0
  let ring = buffer_point(center, radius, segments = 12)
  @test.assert_eq(ring.length(), 13)
  let mut i = 0
  while i < 12 {
    @test.assert_eq((haversine(center, ring[i]) - radius).abs() < 0.01, true)
    i = i + 1
  }
}