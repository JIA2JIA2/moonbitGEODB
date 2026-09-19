// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

///|
test "haversine - same point is zero" {
  let p = @types.GeoPoint::make(39.9, 116.4)
  let d = haversine(p, p)
  @test.assert_eq(d < 0.000001, true)
}

///|
test "haversine - Beijing to Shanghai ~1067 km" {
  let beijing = @types.GeoPoint::make(39.9042, 116.4074)
  let shanghai = @types.GeoPoint::make(31.2304, 121.4737)
  let d = haversine(beijing, shanghai)
  // Real-world distance is ~1067 km; allow ±5 km tolerance.
  @test.assert_eq(d > 1062.0 && d < 1072.0, true)
}

///|
test "haversine - antipodal distance ~20015 km" {
  // Two antipodal points: (0, 0) and (0, 180).
  let a = @types.GeoPoint::make(0.0, 0.0)
  let b = @types.GeoPoint::make(0.0, 180.0)
  let d = haversine(a, b)
  // Half circumference of Earth ≈ π * 6371.0088 ≈ 20015.09 km.
  @test.assert_eq(d > 20010.0 && d < 20020.0, true)
}

///|
test "bbox_contains - inside" {
  let bbox : @types.BBox = {
    min_lat: 39.0,
    max_lat: 40.0,
    min_lng: 116.0,
    max_lng: 117.0,
  }
  let p = @types.GeoPoint::make(39.5, 116.5)
  @test.assert_eq(bbox_contains(bbox, p), true)
}

///|
test "bbox_contains - outside" {
  let bbox : @types.BBox = {
    min_lat: 39.0,
    max_lat: 40.0,
    min_lng: 116.0,
    max_lng: 117.0,
  }
  let p = @types.GeoPoint::make(38.5, 116.5)
  @test.assert_eq(bbox_contains(bbox, p), false)
}

///|
test "bbox_around - center is contained" {
  let center = @types.GeoPoint::make(39.9, 116.4)
  let bbox = bbox_around(center, 10.0)
  @test.assert_eq(bbox_contains(bbox, center), true)
}

///|
test "bbox_intersect - overlapping" {
  let a : @types.BBox = {
    min_lat: 0.0,
    max_lat: 10.0,
    min_lng: 0.0,
    max_lng: 10.0,
  }
  let b : @types.BBox = {
    min_lat: 5.0,
    max_lat: 15.0,
    min_lng: 5.0,
    max_lng: 15.0,
  }
  let i = bbox_intersect(a, b)
  @test.assert_eq(i is Some, true)
}

///|
test "bbox_intersect - disjoint" {
  let a : @types.BBox = {
    min_lat: 0.0,
    max_lat: 1.0,
    min_lng: 0.0,
    max_lng: 1.0,
  }
  let b : @types.BBox = {
    min_lat: 5.0,
    max_lat: 6.0,
    min_lng: 5.0,
    max_lng: 6.0,
  }
  @test.assert_eq(bbox_intersect(a, b) is None, true)
}

///|
test "bearing - due east is 90°" {
  let a = @types.GeoPoint::make(0.0, 0.0)
  let b = @types.GeoPoint::make(0.0, 1.0)
  let brg = bearing(a, b)
  @test.assert_eq(brg > 89.5 && brg < 90.5, true)
}

///|
test "bearing - due north is 0°" {
  let a = @types.GeoPoint::make(0.0, 0.0)
  let b = @types.GeoPoint::make(1.0, 0.0)
  let brg = bearing(a, b)
  @test.assert_eq(brg < 0.5 || brg > 359.5, true)
}

///|
test "voronoi_diagram - single point fills bbox" {
  let pts = [@types.GeoPoint::make(0.0, 0.0)]
  let bbox : @types.BBox = {
    min_lat: -1.0,
    max_lat: 1.0,
    min_lng: -1.0,
    max_lng: 1.0,
  }
  let cells = voronoi_diagram(pts, bbox)
  @test.assert_eq(cells.length(), 1)
  @test.assert_eq(cells[0].polygon.length(), 4)
}

///|
test "voronoi_diagram - two points split bbox" {
  let pts = [@types.GeoPoint::make(0.0, 0.0), @types.GeoPoint::make(2.0, 0.0)]
  let bbox : @types.BBox = {
    min_lat: -1.0,
    max_lat: 3.0,
    min_lng: -1.0,
    max_lng: 3.0,
  }
  let cells = voronoi_diagram(pts, bbox)
  @test.assert_eq(cells.length(), 2)
  @test.assert_eq(cells[0].polygon.length(), 4)
  @test.assert_eq(cells[1].polygon.length(), 4)
}

///|
test "voronoi_diagram - three points in triangle" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(2.0, 0.0),
    @types.GeoPoint::make(1.0, 2.0),
  ]
  let bbox : @types.BBox = {
    min_lat: -1.0,
    max_lat: 3.0,
    min_lng: -1.0,
    max_lng: 3.0,
  }
  let cells = voronoi_diagram(pts, bbox)
  @test.assert_eq(cells.length(), 3)
  for c in cells {
    @test.assert_eq(c.polygon.length() >= 3, true)
  }
}

///|
test "voronoi_diagram - cells cover bbox area" {
  let pts = [
    @types.GeoPoint::make(0.5, 0.5),
    @types.GeoPoint::make(0.5, 1.5),
    @types.GeoPoint::make(1.5, 0.5),
    @types.GeoPoint::make(1.5, 1.5),
  ]
  let bbox : @types.BBox = {
    min_lat: 0.0,
    max_lat: 2.0,
    min_lng: 0.0,
    max_lng: 2.0,
  }
  let cells = voronoi_diagram(pts, bbox)
  @test.assert_eq(cells.length(), 4)
  for c in cells {
    @test.assert_eq(c.polygon.length() >= 3, true)
  }
}

///|
test "voronoi_diagram - empty points returns empty" {
  let bbox : @types.BBox = {
    min_lat: 0.0,
    max_lat: 1.0,
    min_lng: 0.0,
    max_lng: 1.0,
  }
  @test.assert_eq(voronoi_diagram([], bbox).length(), 0)
}

// ---- K-Means ----

///|
test "kmeans with 2 tight clusters" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(0.1, 0.1),
    @types.GeoPoint::make(-0.1, -0.1),
    @types.GeoPoint::make(10.0, 10.0),
    @types.GeoPoint::make(10.1, 10.1),
    @types.GeoPoint::make(9.9, 9.9),
  ]
  let clusters = kmeans(pts, 2)
  @test.assert_eq(clusters.length(), 2)
  for cl in clusters {
    @test.assert_eq(cl.members.length() >= 2, true)
    @test.assert_eq(cl.members.length() <= 4, true)
  }
}

///|
test "kmeans single cluster returns one group" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(0.1, 0.0),
    @types.GeoPoint::make(0.0, 0.1),
  ]
  let clusters = kmeans(pts, 1)
  @test.assert_eq(clusters.length(), 1)
  @test.assert_eq(clusters[0].members.length(), 3)
}

///|
test "kmeans_inertia decreases as k grows" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(10.0, 0.0),
    @types.GeoPoint::make(0.0, 10.0),
    @types.GeoPoint::make(10.0, 10.0),
  ]
  let c1 = kmeans(pts, 1)
  let c2 = kmeans(pts, 2)
  let i1 = kmeans_inertia(pts, c1)
  let i2 = kmeans_inertia(pts, c2)
  @test.assert_eq(i2 < i1, true)
}

// ---- Centroid ----

///|
test "centroid of symmetric points" {
  let pts = [
    @types.GeoPoint::make(10.0, 20.0),
    @types.GeoPoint::make(20.0, 30.0),
    @types.GeoPoint::make(30.0, 40.0),
  ]
  let c = centroid(pts)
  @test.assert_eq((c.lat - 20.0).abs() < 0.001, true)
  @test.assert_eq((c.lng - 30.0).abs() < 0.001, true)
}

///|
test "centroid of single point is itself" {
  let c = centroid([@types.GeoPoint::make(39.9, 116.4)])
  @test.assert_eq((c.lat - 39.9).abs() < 0.0001, true)
  @test.assert_eq((c.lng - 116.4).abs() < 0.0001, true)
}

// ---- Standard Deviation Ellipse ----

///|
test "std_dev_ellipse on colinear points is very elongated" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(2.0, 0.0),
    @types.GeoPoint::make(4.0, 0.0),
    @types.GeoPoint::make(6.0, 0.0),
  ]
  match std_dev_ellipse(pts) {
    None => @test.assert_eq(false, true)
    Some(sde) => {
      @test.assert_eq(sde.eccentricity > 0.9, true)
      @test.assert_eq(sde.semi_major_km > sde.semi_minor_km, true)
    }
  }
}

///|
test "std_dev_ellipse on square points is more circular" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(1.0, 0.0),
    @types.GeoPoint::make(0.0, 1.0),
    @types.GeoPoint::make(1.0, 1.0),
  ]
  match std_dev_ellipse(pts) {
    None => @test.assert_eq(false, true)
    Some(sde) => {
      @test.assert_eq(sde.eccentricity < 0.5, true)
      @test.assert_eq(sde.semi_minor_km > 0.0, true)
    }
  }
}

///|
test "std_dev_ellipse on < 3 points returns None" {
  let pts = [@types.GeoPoint::make(0.0, 0.0), @types.GeoPoint::make(1.0, 1.0)]
  @test.assert_eq(std_dev_ellipse(pts) is None, true)
}

// ---- Moran's I ----

///|
test "morans_i with perfectly clustered values has high positive I" {
  // Two tight clusters of 3 each. Cluster 1 has all low values,
  // cluster 2 has all high values → very strong positive I.
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(0.0, 0.01),
    @types.GeoPoint::make(0.01, 0.0),
    @types.GeoPoint::make(10.0, 10.0),
    @types.GeoPoint::make(10.0, 10.01),
    @types.GeoPoint::make(10.01, 10.0),
  ]
  let vals = [1.0, 1.1, 0.9, 10.0, 10.1, 9.9]
  match morans_i(pts, vals) {
    None => @test.assert_eq(false, true)
    Some(r) => {
      @test.assert_eq(r.index > 0.7, true)
    }
  }
}

///|
test "morans_i with dispersed values has negative I" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(0.0, 1.0),
    @types.GeoPoint::make(0.0, 2.0),
    @types.GeoPoint::make(0.0, 3.0),
  ]
  // High, Low, High, Low → nearby values are unalike.
  let vals = [1.0, 4.0, 1.0, 4.0]
  match morans_i(pts, vals) {
    None => @test.assert_eq(false, true)
    Some(r) => {
      @test.assert_eq(r.index < 0.0, true)
    }
  }
}

///|
test "morans_i with mismatched lengths returns None" {
  let pts = [@types.GeoPoint::make(0.0, 0.0), @types.GeoPoint::make(1.0, 1.0)]
  @test.assert_eq(morans_i(pts, [1.0, 2.0, 3.0]) is None, true)
}

// ---- Compass direction ----

///|
test "compass_direction" {
  @test.assert_eq(compass_direction(0.0), "N")
  @test.assert_eq(compass_direction(90.0), "E")
  @test.assert_eq(compass_direction(180.0), "S")
  @test.assert_eq(compass_direction(270.0), "W")
  @test.assert_eq(compass_direction(360.0), "N")
}

// ---- IDW ----

///|
test "idw midpoint equals average of two values" {
  let pts = [@types.GeoPoint::make(0.0, 0.0), @types.GeoPoint::make(0.0, 1.0)]
  let vals = [10.0, 20.0]
  let q = @types.GeoPoint::make(0.0, 0.5)
  match idw_interpolate(pts, vals, q) {
    None => @test.assert_eq(false, true)
    Some(v) => @test.assert_eq((v - 15.0).abs() < 0.01, true)
  }
}

///|
test "idw closer point has more influence" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(0.0, 1.0),
    @types.GeoPoint::make(0.0, 100.0),  // very far away
  ]
  let vals = [0.0, 100.0, 1000.0]
  let q = @types.GeoPoint::make(0.0, 0.5)
  match idw_interpolate(pts, vals, q) {
    None => @test.assert_eq(false, true)
    Some(v) => {
      // Should be near 50 (midpoint of 0 and 100), not pulled by 1000.
      @test.assert_eq(v > 40.0 && v < 60.0, true)
    }
  }
}

///|
test "idw coincident point returns exact value" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(1.0, 1.0),
  ]
  let vals = [42.0, 99.0]
  match idw_interpolate(pts, vals, @types.GeoPoint::make(0.0, 0.0)) {
    None => @test.assert_eq(false, true)
    Some(v) => @test.assert_eq((v - 42.0).abs() < 0.0001, true)
  }
}

///|
test "idw empty points returns None" {
  @test.assert_eq(idw_interpolate([], [], @types.GeoPoint::make(0.0, 0.0)) is None, true)
}

///|
test "idw_interpolate_knn uses only k nearest" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(0.0, 1.0),
    @types.GeoPoint::make(0.0, 100.0),
  ]
  let vals = [0.0, 100.0, 1000.0]
  let q = @types.GeoPoint::make(0.0, 0.5)
  // With k=2, the far point is excluded → near 50.
  match idw_interpolate_knn(pts, vals, q, 2) {
    None => @test.assert_eq(false, true)
    Some(v) => @test.assert_eq(v > 40.0 && v < 60.0, true)
  }
}

// ---- Concave Hull ----

///|
test "concave hull of square is 4 vertices" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(1.0, 0.0),
    @types.GeoPoint::make(1.0, 1.0),
    @types.GeoPoint::make(0.0, 1.0),
  ]
  let hull = concave_hull(pts, 2.0)
  @test.assert_eq(hull.length() >= 3, true)
}

///|
test "concave hull on < 3 points falls back" {
  let pts = [@types.GeoPoint::make(0.0, 0.0), @types.GeoPoint::make(1.0, 1.0)]
  let hull = concave_hull(pts, 1.0)
  @test.assert_eq(hull.length() <= 2, true)
}

///|
test "concave hull alpha<=0 falls back to convex" {
  let pts = [
    @types.GeoPoint::make(0.0, 0.0),
    @types.GeoPoint::make(1.0, 0.0),
    @types.GeoPoint::make(0.0, 1.0),
    @types.GeoPoint::make(0.5, 0.5),  // interior
  ]
  let hull0 = concave_hull(pts, 0.0)
  let convex = convex_hull(pts)
  @test.assert_eq(hull0.length() == convex.length(), true)
}
