// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

///|
fn ac_pt(lat : Double, lng : Double) -> @types.GeoPoint {
  @types.GeoPoint::make(lat, lng)
}

///|
test "normal_cdf - standard values" {
  @test.assert_eq(normal_cdf(0.0) > 0.4999 && normal_cdf(0.0) < 0.5001, true)
  @test.assert_eq(normal_cdf(1.96) > 0.9749 && normal_cdf(1.96) < 0.9751, true)
  @test.assert_eq(
    normal_cdf(-1.96) > 0.0249 && normal_cdf(-1.96) < 0.0251,
    true,
  )
}

///|
test "morans_i_test - strong positive clustering" {
  // 20 points on a line; first half value 10, second half 0.
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  let mut i = 0
  while i < 20 {
    pts.push(ac_pt(0.0, i.to_double()))
    vals.push(if i < 10 { 10.0 } else { 0.0 })
    i = i + 1
  }
  let w = knn_weights(pts, k=4)
  match morans_i_test(pts, vals, w) {
    None => @test.assert_eq(true, false)
    Some(r) => {
      @test.assert_eq(r.i > 0.3, true)
      @test.assert_eq(r.z_score > 1.96, true)
      @test.assert_eq(r.p_value < 0.05, true)
      @test.assert_eq(r.n, 20)
    }
  }
}

///|
test "morans_i_test - checkerboard dispersion is negative" {
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  let mut i = 0
  while i < 10 {
    pts.push(ac_pt(0.0, i.to_double()))
    vals.push(if i % 2 == 0 { 0.0 } else { 1.0 })
    i = i + 1
  }
  let w = knn_weights(pts, k=2)
  match morans_i_test(pts, vals, w) {
    None => @test.assert_eq(true, false)
    Some(r) => {
      @test.assert_eq(r.i < 0.0, true)
      @test.assert_eq(r.z_score < 0.0, true)
    }
  }
}

///|
test "morans_i_test - degenerate inputs return None" {
  let pts = [ac_pt(0.0, 0.0), ac_pt(0.0, 1.0), ac_pt(1.0, 0.0)]
  let w = knn_weights(pts, k=1)
  // Fewer than 4 observations.
  @test.assert_eq(morans_i_test(pts, [1.0, 2.0, 3.0], w) is None, true)
  // Zero variance.
  let pts4 = [
    ac_pt(0.0, 0.0),
    ac_pt(0.0, 1.0),
    ac_pt(1.0, 0.0),
    ac_pt(1.0, 1.0),
  ]
  let w4 = knn_weights(pts4, k=2)
  @test.assert_eq(morans_i_test(pts4, [5.0, 5.0, 5.0, 5.0], w4) is None, true)
}

///|
test "getis_ord_gi_star - detects the central hotspot" {
  // 3x3 grid, ~111 km spacing; cross + centre = 10, corners = 0.
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  let mut rr = 0
  while rr < 3 {
    let mut cc = 0
    while cc < 3 {
      pts.push(ac_pt(rr.to_double(), cc.to_double()))
      let is_cross = (rr == 1 && cc == 1) ||
        (rr == 0 && cc == 1) ||
        (rr == 2 && cc == 1) ||
        (rr == 1 && cc == 0) ||
        (rr == 1 && cc == 2)
      vals.push(if is_cross { 10.0 } else { 0.0 })
      cc = cc + 1
    }
    rr = rr + 1
  }
  // Grid spacing is 1 degree ≈ 111 km. 120 km covers orthogonal neighbours
  // (~111 km) but not diagonal (~141 km), so the centre sees only the
  // cross-shaped high-value neighbours.
  let w = distance_weights(pts, radius_km=120.0)
  let results = getis_ord_gi_star(pts, vals, w, threshold=0.5)
  @test.assert_eq(results.length(), 9)
  // Centre is index 4 (row 1, col 1); corner (0,0) is index 0.
  @test.assert_eq(results[4].gi_star > 0.5, true)
  @test.assert_eq(results[4].is_hotspot, true)
  @test.assert_eq(results[0].is_hotspot, false)
}

///|
test "getis_ord_gi_star - zero variance yields no hotspots" {
  let pts = [ac_pt(0.0, 0.0), ac_pt(0.0, 1.0), ac_pt(1.0, 0.0), ac_pt(1.0, 1.0)]
  let w = distance_weights(pts, radius_km=200.0)
  let results = getis_ord_gi_star(pts, [3.0, 3.0, 3.0, 3.0], w)
  @test.assert_eq(results.length(), 0)
}

///|
test "local_morans - HH and LL clusters typed correctly" {
  // 20 points on a line; first half value 10, second half 0.
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  let mut i = 0
  while i < 20 {
    pts.push(ac_pt(0.0, i.to_double()))
    vals.push(if i < 10 { 10.0 } else { 0.0 })
    i = i + 1
  }
  let w = knn_weights(pts, k=4)
  let results = local_morans(pts, vals, w, threshold=1.5)
  @test.assert_eq(results.length(), 20)
  // Index 2 sits deep inside the high block -> HH.
  @test.assert_eq(results[2].cluster, "HH")
  // Index 15 sits deep inside the low block -> LL.
  @test.assert_eq(results[15].cluster, "LL")
}

///|
test "knn_weights - symmetric and includes self" {
  let pts = [ac_pt(0.0, 0.0), ac_pt(0.0, 1.0), ac_pt(0.0, 2.0), ac_pt(0.0, 3.0)]
  let w = knn_weights(pts, k=1)
  @test.assert_eq(w.length(), 4)
  let mut i = 0
  while i < 4 {
    // Self is always first.
    @test.assert_eq(w[i][0], i)
    // Symmetry: if j in w[i] then i in w[j].
    for j in w[i] {
      let mut found = false
      for back in w[j] {
        if back == i {
          found = true
          break
        }
      }
      @test.assert_eq(found, true)
    }
    i = i + 1
  }
}

///|
test "distance_weights - threshold filtering" {
  let pts = [ac_pt(0.0, 0.0), ac_pt(0.0, 1.0), ac_pt(0.0, 5.0)]
  let w = distance_weights(pts, radius_km=200.0)
  // Points 0 and 1 are ~111 km apart; point 2 is ~555 km away.
  @test.assert_eq(w[0].length(), 2)
  @test.assert_eq(w[2].length(), 1) // only self
}
