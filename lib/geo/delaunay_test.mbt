// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

///|
fn dt_pt(lat : Double, lng : Double) -> @types.GeoPoint {
  @types.GeoPoint::make(lat, lng)
}

///|
test "delaunay_triangulation - 3 points forms 1 triangle" {
  let pts = [dt_pt(0.0, 0.0), dt_pt(1.0, 0.0), dt_pt(0.0, 1.0)]
  let tris = delaunay_triangulation(pts)
  @test.assert_eq(tris.length(), 1)
  let t = tris[0]
  @test.assert_eq(t.a < 3, true)
  @test.assert_eq(t.b < 3, true)
  @test.assert_eq(t.c < 3, true)
  @test.assert_eq(t.a != t.b && t.a != t.c && t.b != t.c, true)
}

///|
test "delaunay_edges - unique edges" {
  let pts = [dt_pt(0.0, 0.0), dt_pt(1.0, 0.0), dt_pt(0.0, 1.0)]
  let edges = delaunay_edges(pts)
  // Triangle has 3 edges.
  @test.assert_eq(edges.length(), 3)
  // All edges should be unique.
  let seen : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  for e in edges {
    let key = if e.a < e.b { "\{e.a},\{e.b}" } else { "\{e.b},\{e.a}" }
    @test.assert_eq(seen.contains(key), false)
    seen[key] = true
  }
}
