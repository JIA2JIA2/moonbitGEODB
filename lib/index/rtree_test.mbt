// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

///|
fn rt_pt(lat : Double, lng : Double) -> @types.GeoPoint {
  @types.GeoPoint::make(lat, lng)
}

///|
fn rt_brute(
  points : Array[(String, @types.GeoPoint)],
  query : @types.GeoPoint,
  k : Int,
) -> Array[(String, Double)] {
  let pairs : Array[(String, Double)] = []
  for item in points {
    pairs.push((item.0, @geo.haversine(query, item.1)))
  }
  pairs.sort_by(fn(a, b) {
    if a.1 < b.1 {
      -1
    } else if a.1 > b.1 {
      1
    } else {
      0
    }
  })
  let out : Array[(String, Double)] = []
  let mut i = 0
  for p in pairs {
    if i >= k {
      break
    }
    out.push(p)
    i = i + 1
  }
  out
}

///|
fn rt_same(a : Array[(String, Double)], b : Array[(String, Double)]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  while i < a.length() {
    if a[i].0 != b[i].0 {
      return false
    }
    if a[i].1 != b[i].1 {
      return false
    }
    i = i + 1
  }
  true
}

///|
test "RTree::new is empty" {
  let t = RTree::new()
  @test.assert_eq(t.size(), 0)
  @test.assert_eq(t.nearest(rt_pt(0.0, 0.0), 10).length(), 0)
  @test.assert_eq(
    t
    .search({ min_lat: -90.0, max_lat: 90.0, min_lng: -180.0, max_lng: 180.0, })
    .length(),
    0,
  )
}

///|
test "RTree::insert and size" {
  let t = RTree::new()
  t.insert("a", rt_pt(39.9, 116.4))
  t.insert("b", rt_pt(31.2, 121.5))
  @test.assert_eq(t.size(), 2)
  @test.assert_eq(t.contains("a"), true)
  @test.assert_eq(t.contains("z"), false)
}

///|
test "RTree::search returns contained ids" {
  let t = RTree::new()
  t.insert("bj", rt_pt(39.9, 116.4))
  t.insert("sh", rt_pt(31.2, 121.5))
  t.insert("tj", rt_pt(39.1, 117.2))
  let bbox : @types.BBox = {
    min_lat: 39.0,
    max_lat: 40.5,
    min_lng: 116.0,
    max_lng: 117.5,
  }
  @test.assert_eq(t.search(bbox).length(), 2)
}

///|
test "RTree::nearest matches brute force (small)" {
  let points : Array[(String, @types.GeoPoint)] = [
    ("bj", rt_pt(39.9, 116.4)),
    ("sh", rt_pt(31.2, 121.5)),
    ("tj", rt_pt(39.1, 117.2)),
  ]
  let t = RTree::new()
  for item in points {
    t.insert(item.0, item.1)
  }
  let q = rt_pt(39.5, 116.8)
  @test.assert_eq(rt_same(t.nearest(q, 3), rt_brute(points, q, 3)), true)
}

///|
test "RTree::nearest matches brute force (large, triggers splits)" {
  let t = RTree::new()
  let points : Array[(String, @types.GeoPoint)] = []
  let mut i = 0
  while i < 100 {
    let lat = 30.0 + (i % 20).to_double() * 0.5
    let lng = 110.0 + (i / 20).to_double() * 0.5
    let id = "p\{i}"
    points.push((id, rt_pt(lat, lng)))
    t.insert(id, rt_pt(lat, lng))
    i = i + 1
  }
  let queries = [
    rt_pt(35.0, 113.0),
    rt_pt(32.0, 116.0),
    rt_pt(37.0, 115.0),
    rt_pt(40.0, 110.0),
  ]
  for q in queries {
    @test.assert_eq(rt_same(t.nearest(q, 5), rt_brute(points, q, 5)), true)
  }
}

///|
test "RTree::remove keeps nearest correct" {
  let t = RTree::new()
  let mut i = 0
  while i < 50 {
    let lat = 30.0 + (i % 10).to_double() * 0.3
    let lng = 110.0 + (i / 10).to_double() * 0.3
    t.insert("p\{i}", rt_pt(lat, lng))
    i = i + 1
  }
  let mut j = 0
  while j < 25 {
    ignore(t.remove("p\{j}"))
    j = j + 1
  }
  @test.assert_eq(t.size(), 25)
  let remaining : Array[(String, @types.GeoPoint)] = []
  let mut k2 = 25
  while k2 < 50 {
    let id = "p\{k2}"
    remaining.push(
      (
        id,
        rt_pt(
          30.0 + (k2 % 10).to_double() * 0.3,
          110.0 + (k2 / 10).to_double() * 0.3,
        ),
      ),
    )
    k2 = k2 + 1
  }
  let q = rt_pt(32.0, 111.0)
  @test.assert_eq(rt_same(t.nearest(q, 7), rt_brute(remaining, q, 7)), true)
}

///|
test "RTree::insert replaces same id" {
  let t = RTree::new()
  t.insert("a", rt_pt(0.0, 0.0))
  t.insert("a", rt_pt(40.0, 120.0))
  @test.assert_eq(t.size(), 1)
  let near = t.nearest(rt_pt(40.0, 120.0), 1)
  @test.assert_eq(near.length(), 1)
  @test.assert_eq(near[0].0, "a")
  @test.assert_eq(near[0].1 < 1.0, true)
}

///|
test "RTree::nearest k bounds" {
  let t = RTree::new()
  t.insert("a", rt_pt(0.0, 0.0))
  t.insert("b", rt_pt(1.0, 1.0))
  @test.assert_eq(t.nearest(rt_pt(0.0, 0.0), 0).length(), 0)
  @test.assert_eq(t.nearest(rt_pt(0.0, 0.0), 10).length(), 2)
}

///|
test "RTree::remove missing returns false" {
  let t = RTree::new()
  t.insert("a", rt_pt(0.0, 0.0))
  @test.assert_eq(t.remove("nope"), false)
  @test.assert_eq(t.remove("a"), true)
  @test.assert_eq(t.remove("a"), false)
  @test.assert_eq(t.size(), 0)
}
