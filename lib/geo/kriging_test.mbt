// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

///|
fn kp(lat : Double, lng : Double) -> @types.GeoPoint {
  @types.GeoPoint::make(lat, lng)
}

///|
/// 测试经验变异函数：空输入返回空数组。
test "empirical_variogram - empty input" {
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  let bins = empirical_variogram(pts, vals)
  @test.assert_eq(bins.length(), 0)
}

///|
/// 测试经验变异函数：单点返回空数组。
test "empirical_variogram - single point" {
  let pts = [kp(0.0, 0.0)]
  let vals = [1.0]
  let bins = empirical_variogram(pts, vals)
  @test.assert_eq(bins.length(), 0)
}

///|
/// 测试经验变异函数：两点返回单个滞后项。
test "empirical_variogram - two points" {
  let pts = [kp(0.0, 0.0), kp(0.0, 0.01)]
  let vals = [1.0, 3.0]
  let bins = empirical_variogram(pts, vals, max_lag_km=None, num_lags=5)
  @test.assert_eq(bins.length() >= 1, true)
  // γ(h) = 0.5 * (1-3)^2 = 2.0
  if bins.length() > 0 {
    let b = bins[0]
    @test.assert_eq(b.num_pairs, 1)
    @test.assert_eq(b.semivariance > 1.9 && b.semivariance < 2.1, true)
  }
}

///|
/// 测试经验变异函数：三点返回多个滞后项。
test "empirical_variogram - three points" {
  let pts = [kp(0.0, 0.0), kp(0.0, 1.0), kp(0.0, 2.0)]
  let vals = [1.0, 2.0, 3.0]
  let bins = empirical_variogram(pts, vals, max_lag_km=None, num_lags=5)
  @test.assert_eq(bins.length() >= 1, true)
}

///|
/// 测试球形模型：h=0 返回 nugget。
test "spherical_model - zero distance" {
  let g = spherical_model(0.0, 0.5, 2.0, 10.0)
  @test.assert_eq(g, 0.5)
}

///|
/// 测试球形模型：h>=range 返回 nugget+sill。
test "spherical_model - beyond range" {
  let g = spherical_model(20.0, 0.5, 2.0, 10.0)
  @test.assert_eq(g, 2.5)
}

///|
/// 测试球形模型：h=range/2 的中间值。
test "spherical_model - half range" {
  let g = spherical_model(5.0, 0.5, 2.0, 10.0)
  // hr = 0.5, 1.5*0.5 - 0.5*0.125 = 0.75 - 0.0625 = 0.6875
  // γ = 0.5 + 2.0 * 0.6875 = 1.875
  @test.assert_eq(g > 1.8 && g < 1.95, true)
}

///|
/// 测试指数模型：h=0 返回 nugget。
test "exponential_model - zero distance" {
  let g = exponential_model(0.0, 0.5, 2.0, 10.0)
  @test.assert_eq(g, 0.5)
}

///|
/// 测试指数模型：h 较大时接近 nugget+sill。
test "exponential_model - large distance" {
  let g = exponential_model(100.0, 0.5, 2.0, 10.0)
  @test.assert_eq(g > 2.4 && g < 2.6, true)
}

///|
/// 测试高斯模型：h=0 返回 nugget。
test "gaussian_model - zero distance" {
  let g = gaussian_model(0.0, 0.5, 2.0, 10.0)
  @test.assert_eq(g, 0.5)
}

///|
/// 测试变异函数拟合：返回合理参数。
test "fit_variogram - returns reasonable params" {
  let pts = [kp(0.0, 0.0), kp(0.0, 1.0), kp(0.0, 2.0), kp(0.0, 3.0)]
  let vals = [1.0, 2.0, 3.0, 4.0]
  let bins = empirical_variogram(pts, vals, max_lag_km=None, num_lags=5)
  let fitted = fit_variogram(bins)
  @test.assert_eq(fitted.nugget >= 0.0, true)
  @test.assert_eq(fitted.sill >= fitted.nugget, true)
  @test.assert_eq(fitted.range > 0.0, true)
}

///|
/// 测试普通克里金：两点线性插值。
test "ordinary_kriging - two points linear" {
  let pts = [kp(0.0, 0.0), kp(0.0, 1.0)]
  let vals = [1.0, 3.0]
  let bins = empirical_variogram(pts, vals, max_lag_km=None, num_lags=5)
  let fitted = fit_variogram(bins)
  let pred = ordinary_kriging(pts, vals, kp(0.0, 0.5), fitted)
  match pred {
    None => @test.assert_eq(1, 0) // should not be None
    Some(v) => {
      // 两点线性插值，中间点应在 1.0 和 3.0 之间
      @test.assert_eq(v >= 1.0 && v <= 3.0, true)
    }
  }
}

///|
/// 测试普通克里金：查询点与已知点重合返回精确值。
test "ordinary_kriging - coincident point" {
  let pts = [kp(0.0, 0.0), kp(0.0, 1.0)]
  let vals = [1.0, 3.0]
  let bins = empirical_variogram(pts, vals, max_lag_km=None, num_lags=5)
  let fitted = fit_variogram(bins)
  let pred = ordinary_kriging(pts, vals, kp(0.0, 0.0), fitted)
  match pred {
    None => @test.assert_eq(1, 0)
    Some(v) => @test.assert_eq(v, 1.0)
  }
}

///|
/// 测试普通克里金：单点返回该点值。
test "ordinary_kriging - single point" {
  let pts = [kp(0.0, 0.0)]
  let vals = [42.0]
  let bins = empirical_variogram(pts, vals, max_lag_km=None, num_lags=5)
  let fitted = fit_variogram(bins)
  let pred = ordinary_kriging(pts, vals, kp(0.0, 0.5), fitted)
  match pred {
    None => @test.assert_eq(1, 0)
    Some(v) => @test.assert_eq(v, 42.0)
  }
}

///|
/// 测试普通克里金 KNN：三点插值。
test "ordinary_kriging_knn - three points" {
  let pts = [kp(0.0, 0.0), kp(0.0, 1.0), kp(0.0, 2.0)]
  let vals = [1.0, 2.0, 3.0]
  let bins = empirical_variogram(pts, vals, max_lag_km=None, num_lags=5)
  let fitted = fit_variogram(bins)
  let pred = ordinary_kriging_knn(pts, vals, kp(0.0, 0.5), fitted, k=3)
  match pred {
    None => @test.assert_eq(1, 0)
    Some(v) => {
      @test.assert_eq(v >= 1.0 && v <= 3.0, true)
    }
  }
}

///|
/// 测试普通克里金 KNN：k 大于点数时回退到全点。
test "ordinary_kriging_knn - k larger than n" {
  let pts = [kp(0.0, 0.0), kp(0.0, 1.0)]
  let vals = [1.0, 3.0]
  let bins = empirical_variogram(pts, vals, max_lag_km=None, num_lags=5)
  let fitted = fit_variogram(bins)
  let pred = ordinary_kriging_knn(pts, vals, kp(0.0, 0.5), fitted, k=10)
  match pred {
    None => @test.assert_eq(1, 0)
    Some(v) => {
      @test.assert_eq(v >= 1.0 && v <= 3.0, true)
    }
  }
}

///|
/// 测试普通克里金：值数组不匹配返回 None。
test "ordinary_kriging - mismatched lengths" {
  let pts = [kp(0.0, 0.0), kp(0.0, 1.0)]
  let vals = [1.0]
  let fitted = fit_variogram([])
  let pred = ordinary_kriging(pts, vals, kp(0.0, 0.5), fitted)
  @test.assert_eq(pred, None)
}
///|
/// 测试经验变异函数采样：大 n 时用 max_pairs 上限避免 O(n²)。
test "empirical_variogram - max_pairs sampling" {
  let n = 200
  let pts : Array[@types.GeoPoint] = []
  let vals : Array[Double] = []
  let mut i = 0
  while i < n {
    pts.push(kp((i % 20).to_double() * 0.1, (i / 20).to_double() * 0.1))
    vals.push(i.to_double())
    i = i + 1
  }
  // 强制采样（max_pairs 很小）。
  let bins = empirical_variogram(pts, vals, max_lag_km=None, num_lags=5, max_pairs=500)
  @test.assert_eq(bins.length() >= 1, true)
  let mut total_pairs = 0
  for b in bins {
    total_pairs = total_pairs + b.num_pairs
  }
  @test.assert_eq(total_pairs <= 500, true)
}
