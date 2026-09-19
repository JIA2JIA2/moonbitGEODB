// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

/// Kriging (克里金插值) — 基于变异函数的最优无偏空间插值。
///
/// 相比 IDW 的简单距离加权，Kriging 通过变异函数建模空间相关性，
/// 给出最优无偏估计（BLUE），并提供估计方差。
///
/// 算法流程：
///   1. 计算经验变异函数（empirical variogram）
///   2. 拟合变异函数模型（spherical / exponential / gaussian）
///   3. 解普通克里金方程组（ordinary kriging system）
///
/// 参考：
///   Cressie (1993) Statistics for Spatial Data
///   Isaaks & Srivastava (1989) An Introduction to Applied Geostatistics

///|
/// 变异函数模型类型。
pub enum VariogramModel {
  Spherical
  Exponential
  Gaussian
} derive(Debug)

///|
/// 拟合后的变异函数参数。
/// - nugget: 块金值（h→0 时的 γ(h)）
/// - sill: 基台值（γ(h) 的渐近上限）
/// - range: 变程（达到基台的距离）
/// - model: 模型类型
pub(all) struct FittedVariogram {
  nugget : Double
  sill : Double
  range : Double
  model : VariogramModel
} derive(Debug)

///|
/// 经验变异函数的一个滞后项。
/// - lag_center: 滞后中心距离（km）
/// - semivariance: 半方差 γ(h)
/// - num_pairs: 该滞后中的点对数
pub(all) struct LagBin {
  lag_center : Double
  semivariance : Double
  num_pairs : Int
} derive(Debug)

// ---- 经验变异函数 ----

///|
/// 计算经验变异函数（empirical variogram）。
///
/// 对于每对点 (i, j)，半方差 γ(h) = 0.5 * (z_i - z_j)^2，
/// 按距离 h 分入 lag_bin 中。
///
/// - max_lag_km: 最大滞后距离（默认取点集最大距离）
/// - num_lags: 滞后数量（默认 10）
/// - 返回按 lag_center 排序的 LagBin 数组
pub fn empirical_variogram(
  points : Array[@types.GeoPoint],
  values : Array[Double],
  max_lag_km? : Double? = None,
  num_lags? : Int = 10,
) -> Array[LagBin] {
  let n = points.length()
  if n < 2 || values.length() != n {
    return []
  }
  let num_lag = if num_lags > 0 { num_lags } else { 10 }
  // 计算最大距离
  let mut max_d = 0.0
  let mut i = 0
  while i < n {
    let mut j = i + 1
    while j < n {
      let d = haversine(points[i], points[j])
      if d > max_d {
        max_d = d
      }
      j = j + 1
    }
    i = i + 1
  }
  if max_d == 0.0 {
    return []
  }
  let max_lag = match max_lag_km {
    Some(m) => m
    None => max_d
  }
  let lag_width = max_lag / num_lag.to_double()
  if lag_width <= 0.0 {
    return []
  }
  // 累积半方差和计数
  let sum_gamma : Array[Double] = []
  let count : Array[Int] = []
  let mut k = 0
  while k < num_lag {
    sum_gamma.push(0.0)
    count.push(0)
    k = k + 1
  }
  let mut i2 = 0
  while i2 < n {
    let mut j2 = i2 + 1
    while j2 < n {
      let d = haversine(points[i2], points[j2])
      let bin_raw = (d / lag_width).to_int()
      let bin = if bin_raw >= num_lag { num_lag - 1 } else { bin_raw }
      if bin >= 0 && bin < num_lag {
        let gamma = 0.5 * (values[i2] - values[j2]) * (values[i2] - values[j2])
        sum_gamma[bin] = sum_gamma[bin] + gamma
        count[bin] = count[bin] + 1
      }
      j2 = j2 + 1
    }
    i2 = i2 + 1
  }
  // 构建结果
  let out : Array[LagBin] = []
  let mut k2 = 0
  while k2 < num_lag {
    if count[k2] > 0 {
      let center = (k2.to_double() + 0.5) * lag_width
      let gamma = sum_gamma[k2] / count[k2].to_double()
      out.push({ lag_center: center, semivariance: gamma, num_pairs: count[k2] })
    }
    k2 = k2 + 1
  }
  out
}

// ---- 变异函数模型拟合 ----

///|
/// 球形模型：γ(h) = nugget + sill * (1.5*h/r - 0.5*(h/r)^3) for h <= r
pub fn spherical_model(h : Double, nugget : Double, sill : Double, range : Double) -> Double {
  if h <= 0.0 {
    return nugget
  }
  let hr = h / range
  if hr >= 1.0 {
    return nugget + sill
  }
  nugget + sill * (1.5 * hr - 0.5 * hr * hr * hr)
}

///|
/// 指数模型：γ(h) = nugget + sill * (1 - exp(-3h/r))
pub fn exponential_model(h : Double, nugget : Double, sill : Double, range : Double) -> Double {
  if h <= 0.0 {
    return nugget
  }
  nugget + sill * (1.0 - @math.exp(-3.0 * h / range))
}

///|
/// 高斯模型：γ(h) = nugget + sill * (1 - exp(-3h^2/r^2))
pub fn gaussian_model(h : Double, nugget : Double, sill : Double, range : Double) -> Double {
  if h <= 0.0 {
    return nugget
  }
  nugget + sill * (1.0 - @math.exp(-3.0 * h * h / (range * range)))
}

///|
/// 用指定模型计算预测半方差。
fn model_predict(
  h : Double,
  nugget : Double,
  sill : Double,
  range : Double,
  model : VariogramModel,
) -> Double {
  match model {
    Spherical => spherical_model(h, nugget, sill, range)
    Exponential => exponential_model(h, nugget, sill, range)
    Gaussian => gaussian_model(h, nugget, sill, range)
  }
}

///|
/// 用最小二乘法拟合变异函数模型。
///
/// 对每个模型类型，在 nugget ∈ [0, γ_min], sill ∈ [γ_max, 2*γ_max],
/// range ∈ [lag_width, max_lag] 的网格上搜索最优参数。
/// 返回残差平方和最小的模型。
pub fn fit_variogram(
  bins : Array[LagBin],
  model_type? : VariogramModel = Spherical,
) -> FittedVariogram {
  if bins.length() < 2 {
    return { nugget: 0.0, sill: 1.0, range: 1.0, model: model_type }
  }
  // 提取 lag_center 和 semivariance
  let xs : Array[Double] = []
  let ys : Array[Double] = []
  for b in bins {
    xs.push(b.lag_center)
    ys.push(b.semivariance)
  }
  let n = xs.length()
  let mut y_min = ys[0]
  let mut y_max = ys[0]
  for y in ys {
    if y < y_min { y_min = y }
    if y > y_max { y_max = y }
  }
  let lag_width = xs[1] - xs[0]
  let max_lag = xs[n - 1]
  if y_max <= 0.0 || max_lag <= 0.0 {
    return { nugget: 0.0, sill: 1.0, range: 1.0, model: model_type }
  }
  // 网格搜索
  let mut best_nugget = 0.0
  let mut best_sill = y_max
  let mut best_range = max_lag
  let mut best_ss = 1000000000000000000000000000000.0
  let nugget_steps = 5
  let sill_steps = 5
  let range_steps = 5
  let mut si = 0
  while si < nugget_steps {
    let nugget = y_min * (si.to_double() / (nugget_steps - 1).to_double())
    let mut ii = 0
    while ii < sill_steps {
      let sill = y_max + (y_max - y_min) * (ii.to_double() / (sill_steps - 1).to_double())
      let mut ri = 0
      while ri < range_steps {
        let range = lag_width + (max_lag - lag_width) * (ri.to_double() / (range_steps - 1).to_double())
        let mut ss = 0.0
        let mut k = 0
        while k < n {
          let pred = model_predict(xs[k], nugget, sill, range, model_type)
          let err = pred - ys[k]
          ss = ss + err * err
          k = k + 1
        }
        if ss < best_ss {
          best_ss = ss
          best_nugget = nugget
          best_sill = sill
          best_range = range
        }
        ri = ri + 1
      }
      ii = ii + 1
    }
    si = si + 1
  }
  { nugget: best_nugget, sill: best_sill, range: best_range, model: model_type }
}

// ---- 普通克里金（Ordinary Kriging） ----

///|
/// 解 (n+1)×(n+1) 线性方程组（高斯消元法，部分选主元）。
/// 输入为增广矩阵 A（最后列为右端项），返回解向量。
fn solve_linear_system(a : Array[Array[Double]]) -> Array[Double]? {
  let n = a.length()
  if n == 0 {
    return None
  }
  let m = a[0].length()
  if m != n + 1 {
    return None
  }
  // 复制矩阵
  let mat : Array[Array[Double]] = []
  for row in a {
    let new_row : Array[Double] = []
    for v in row {
      new_row.push(v)
    }
    mat.push(new_row)
  }
  // 高斯消元
  let mut col = 0
  while col < n {
    // 选主元
    let mut pivot = col
    let mut max_abs = mat[col][col].abs()
    let mut row = col + 1
    while row < n {
      let v = mat[row][col].abs()
      if v > max_abs {
        max_abs = v
        pivot = row
      }
      row = row + 1
    }
    if max_abs < 0.000000000000001 {
      return None // 奇异矩阵
    }
    // 交换行
    if pivot != col {
      let tmp = mat[col]
      mat[col] = mat[pivot]
      mat[pivot] = tmp
    }
    // 消元
    let pivot_val = mat[col][col]
    let mut row2 = col + 1
    while row2 < n {
      let factor = mat[row2][col] / pivot_val
      let mut k = col
      while k <= n {
        mat[row2][k] = mat[row2][k] - factor * mat[col][k]
        k = k + 1
      }
      row2 = row2 + 1
    }
    col = col + 1
  }
  // 回代
  let x : Array[Double] = []
  let mut i = 0
  while i < n {
    x.push(0.0)
    i = i + 1
  }
  let mut i2 = n - 1
  while i2 >= 0 {
    let mut s = mat[i2][n]
    let mut j = i2 + 1
    while j < n {
      s = s - mat[i2][j] * x[j]
      j = j + 1
    }
    if mat[i2][i2].abs() < 0.000000000000001 {
      return None
    }
    x[i2] = s / mat[i2][i2]
    i2 = i2 - 1
  }
  Some(x)
}

///|
/// 普通克里金插值。
///
/// 在查询点 q 处，用 n 个已知点 (points, values) 和拟合的变异函数模型，
/// 解克里金方程组得到最优权重 λ，返回估计值。
///
/// 克里金方程组：
///   [γ(d_ij)] [λ_j]   [γ(d_iq)]
///   [   1   ] [μ ]  = [   1   ]
///
/// 返回 None 当：点数 < 1、值数组不匹配、方程组奇异、或查询点与已知点重合。
pub fn ordinary_kriging(
  points : Array[@types.GeoPoint],
  values : Array[Double],
  query : @types.GeoPoint,
  variogram : FittedVariogram,
) -> Double? {
  let n = points.length()
  if n < 1 || values.length() != n {
    return None
  }
  // 检查是否与已知点重合
  let mut i = 0
  while i < n {
    let d = haversine(query, points[i])
    if d < 0.000001 {
      return Some(values[i])
    }
    i = i + 1
  }
  if n == 1 {
    return Some(values[0])
  }
  // 构建 (n+1)×(n+1) 增广矩阵
  let mat : Array[Array[Double]] = []
  let mut i2 = 0
  while i2 < n {
    let row : Array[Double] = []
    let mut j = 0
    while j < n {
      let d = haversine(points[i2], points[j])
      let gamma = model_predict(d, variogram.nugget, variogram.sill, variogram.range, variogram.model)
      row.push(gamma)
      j = j + 1
    }
    row.push(1.0) // 拉格朗日乘子列
    mat.push(row)
    i2 = i2 + 1
  }
  // 最后一行：约束 ∑λ_i = 1
  let last_row : Array[Double] = []
  let mut j2 = 0
  while j2 < n {
    last_row.push(1.0)
    j2 = j2 + 1
  }
  last_row.push(0.0)
  mat.push(last_row)
  // 右端项
  let rhs : Array[Double] = []
  let mut i3 = 0
  while i3 < n {
    let d = haversine(points[i3], query)
    rhs.push(model_predict(d, variogram.nugget, variogram.sill, variogram.range, variogram.model))
    i3 = i3 + 1
  }
  rhs.push(1.0)
  // 将 rhs 并入 mat 作为最后一列
  let mut i4 = 0
  while i4 < n + 1 {
    mat[i4].push(rhs[i4])
    i4 = i4 + 1
  }
  // 解方程组
  let sol = solve_linear_system(mat)
  match sol {
    None => None
    Some(x) => {
      // x[0..n] 是权重 λ，x[n] 是 μ
      let mut estimate = 0.0
      let mut k = 0
      while k < n {
        estimate = estimate + x[k] * values[k]
        k = k + 1
      }
      Some(estimate)
    }
  }
}

///|
/// 普通克里金插值（k 近邻版本）。
///
/// 仅使用距离查询点最近的 k 个已知点进行插值，
/// 适合大数据集，避免构建大型方程组。
///
/// - k: 近邻数量（默认 12，经验值）
pub fn ordinary_kriging_knn(
  points : Array[@types.GeoPoint],
  values : Array[Double],
  query : @types.GeoPoint,
  variogram : FittedVariogram,
  k? : Int = 12,
) -> Double? {
  let n = points.length()
  if n < 1 || values.length() != n {
    return None
  }
  let k_eff = if k < n { k } else { n }
  if k_eff < 1 {
    return None
  }
  // 计算所有距离
  let dists : Array[(Double, Int)] = []
  let mut i = 0
  while i < n {
    dists.push((haversine(query, points[i]), i))
    i = i + 1
  }
  dists.sort_by(fn(a, b) {
    if a.0 < b.0 { -1 } else if a.0 > b.0 { 1 } else { 0 }
  })
  // 取 k 个最近邻
  let knn_pts : Array[@types.GeoPoint] = []
  let knn_vals : Array[Double] = []
  let mut j = 0
  while j < k_eff {
    let (_, idx) = dists[j]
    knn_pts.push(points[idx])
    knn_vals.push(values[idx])
    j = j + 1
  }
  ordinary_kriging(knn_pts, knn_vals, query, variogram)
}