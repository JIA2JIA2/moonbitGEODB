// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

/// Spatial autocorrelation and hotspot analysis.
///
/// Provides the classical statistics used in ecology, epidemiology, and
/// spatial transcriptomics to detect spatial clustering of numeric values:
///   - Global Moran's I (overall clustering tendency),
///   - Getis-Ord Gi* (local hot/cold spot detection),
///   - Local Moran's I / LISA (local cluster typing: HH/LL/HL/LH).
///
/// Spatial weights are binary (0/1) and symmetric. Two builders are offered:
/// k-nearest-neighbour (mutual-kNN symmetrised) and a distance threshold.
/// All statistics use the planar lat/lng approximation for distances.
///
/// References:
///   Moran (1950); Cliff & Ord (1981); Getis & Ord (1995); Anselin (1995).

///|
/// Result of the global Moran's I test.
pub(all) struct MoranResult {
  i : Double // Moran's I statistic
  expected : Double // E[I] = -1/(n-1) under randomisation
  z_score : Double // (I - E[I]) / sqrt(Var[I])
  p_value : Double // two-sided normal-approximation p-value
  n : Int // number of observations
} derive(Eq, Debug)

///|
/// Result of the Getis-Ord Gi* statistic for one point.
pub(all) struct GetisResult {
  index : Int // index into the input point/value arrays
  gi_star : Double // Gi* z-score (>0 hot, <0 cold)
  is_hotspot : Bool // gi_star > threshold
  is_coldspot : Bool // gi_star < -threshold
} derive(Eq, Debug)

///|
/// Result of the Local Moran's I (LISA) statistic for one point.
pub(all) struct LocalMoranResult {
  index : Int // index into the input point/value arrays
  local_i : Double // local Moran's I value
  z_score : Double // conditional randomisation z-score
  cluster : String // "HH" | "LL" | "HL" | "LH" | "NS"
} derive(Eq, Debug)

///|
/// Enhanced global Moran's I with full significance testing (z-score and
/// two-sided p-value under the randomisation assumption). For the simple
/// index-only variant see `morans_i`. Returns None when there are fewer
/// than 4 observations, values are all identical (zero variance), or the
/// weight matrix is empty.
pub fn morans_i_test(
  points : Array[@types.GeoPoint],
  values : Array[Double],
  weights : Array[Array[Int]],
) -> MoranResult? {
  let n = points.length()
  if n < 4 || values.length() != n {
    return None
  }
  let stats = value_stats(values)
  match stats {
    None => None // zero variance
    Some((mean, m2sq)) => {
      // Deviations.
      let z : Array[Double] = []
      for v in values {
        z.push(v - mean)
      }
      // S0, S1, S2 and the cross-product sum.
      let mut s0 = 0.0
      let mut s1 = 0.0
      let mut s2 = 0.0
      let mut cross = 0.0
      let row_sums : Array[Double] = []
      let mut i = 0
      while i < n {
        let nb = weights[i]
        let mut row_sum = 0.0
        for j in nb {
          if j != i {
            s0 = s0 + 1.0
            row_sum = row_sum + 1.0
            cross = cross + z[i] * z[j]
            // S1 accumulates (w_ij + w_ji)^2 / 2; for symmetric binary
            // weights this is 2 per pair, but compute generally.
            let w_ij = 1.0
            let w_ji = if has_neighbor(weights, j, i) { 1.0 } else { 0.0 }
            let t = w_ij + w_ji
            s1 = s1 + t * t / 2.0
          }
        }
        row_sums.push(row_sum)
        i = i + 1
      }
      if s0 == 0.0 {
        return None
      }
      // S2 = sum over i of (row_sum_i + col_sum_i)^2.
      let col_sums : Array[Double] = []
      let mut k = 0
      while k < n {
        col_sums.push(0.0)
        k = k + 1
      }
      let mut i2 = 0
      while i2 < n {
        for j in weights[i2] {
          if j != i2 {
            col_sums[j] = col_sums[j] + 1.0
          }
        }
        i2 = i2 + 1
      }
      let mut i3 = 0
      while i3 < n {
        let t = row_sums[i3] + col_sums[i3]
        s2 = s2 + t * t
        i3 = i3 + 1
      }
      // Moran's I.
      let denom = m2sq // sum of squared deviations
      let stat = n.to_double() / s0 * cross / denom
      let expected = -1.0 / (n - 1).to_double()
      // Kurtosis b2 = n * sum(z^4) / (sum(z^2))^2.
      let mut z4 = 0.0
      for zi in z {
        z4 = z4 + zi * zi * zi * zi
      }
      let b2 = n.to_double() * z4 / (denom * denom)
      // Randomisation variance (Cliff & Ord 1981).
      let nd = n.to_double()
      let s0sq = s0 * s0
      let num = nd * ((nd * nd - 3.0 * nd + 3.0) * s1 - nd * s2 + 3.0 * s0sq) -
        b2 * ((nd * nd - nd) * s1 - 2.0 * nd * s2 + 6.0 * s0sq)
      let den = (nd - 1.0) * (nd - 2.0) * (nd - 3.0) * s0sq
      let variance = num / den - expected * expected
      let var_safe = if variance > 0.0 { variance } else { 0.0 }
      let z_score = (stat - expected) / sqrt(var_safe)
      let p_value = two_sided_p(z_score)
      Some({ i: stat, expected, z_score, p_value, n, })
    }
  }
}

///|
/// Getis-Ord Gi* for every point. `weights[i]` lists neighbour indices
/// (self may or may not be included; Gi* convention includes self, so the
/// caller should include `i` in its own list or pass `include_self=true`
/// via `knn_weights`/`distance_weights` helpers that do so for Gi* use).
/// `threshold` is the |z| cut-off for hotspot/coldspot labelling.
pub fn getis_ord_gi_star(
  points : Array[@types.GeoPoint],
  values : Array[Double],
  weights : Array[Array[Int]],
  threshold? : Double = 1.96,
) -> Array[GetisResult] {
  let n = points.length()
  if n == 0 || values.length() != n {
    return []
  }
  let stats = value_stats(values)
  match stats {
    None => []
    Some((mean, _)) => {
      let mut sum_x = 0.0
      let mut sum_x2 = 0.0
      for v in values {
        sum_x = sum_x + v
        sum_x2 = sum_x2 + v * v
      }
      // Denominator root shared by all points:
      // sqrt[(n * sum(x^2) - (sum x)^2) / (n-1)]
      let root = sqrt(
        (n.to_double() * sum_x2 - sum_x * sum_x) / (n - 1).to_double(),
      )
      let out : Array[GetisResult] = []
      let mut i = 0
      while i < n {
        let nb = weights[i]
        let mut w_sum = 0.0
        let mut wx = 0.0
        let mut w2 = 0.0
        for j in nb {
          w_sum = w_sum + 1.0
          wx = wx + values[j]
          w2 = w2 + 1.0
        }
        let s = sqrt(w2)
        let gi = if s > 0.0 && root > 0.0 {
          (wx - w_sum * mean) / (s * root)
        } else {
          0.0
        }
        out.push({
          index: i,
          gi_star: gi,
          is_hotspot: gi > threshold,
          is_coldspot: gi < -threshold,
        })
        i = i + 1
      }
      out
    }
  }
}

///|
/// Local Moran's I (LISA) for every point, with conditional randomisation
/// z-scores and Anselin cluster typing.
pub fn local_morans(
  points : Array[@types.GeoPoint],
  values : Array[Double],
  weights : Array[Array[Int]],
  threshold? : Double = 1.96,
) -> Array[LocalMoranResult] {
  let n = points.length()
  if n < 4 || values.length() != n {
    return []
  }
  let stats = value_stats(values)
  match stats {
    None => []
    Some((mean, _)) => {
      let z : Array[Double] = []
      for v in values {
        z.push(v - mean)
      }
      let mut m2 = 0.0
      let mut total_sq = 0.0
      for zi in z {
        total_sq = total_sq + zi * zi
      }
      m2 = total_sq / n.to_double()
      if m2 == 0.0 {
        return []
      }
      let out : Array[LocalMoranResult] = []
      let mut i = 0
      while i < n {
        let nb = weights[i]
        // k = neighbour count (binary weights).
        let k = nb
          .iter()
          .filter(fn(j) { j != i })
          .collect()
          .length()
          .to_double()
        // Weighted neighbour sum.
        let mut wz = 0.0
        for j in nb {
          if j != i {
            wz = wz + z[j]
          }
        }
        let local_i = z[i] * wz / m2
        // Conditional randomisation moments for the neighbour sum L:
        // E[L] = k * (-z_i/(n-1)); Var[L] = k(n-1-k)/(n-2) * sigma2_rest.
        let nd = n.to_double()
        let ki = k
        let sigma2_rest = (total_sq - z[i] * z[i]) / (nd - 1.0)
        let e_l = ki * (-z[i] / (nd - 1.0))
        let var_l = if nd > 2.0 && ki > 0.0 {
          ki * (nd - 1.0 - ki) / (nd - 2.0) * sigma2_rest
        } else {
          0.0
        }
        let e_i = z[i] * e_l / m2
        let var_i = z[i] * z[i] * var_l / (m2 * m2)
        let z_score = if var_i > 0.0 {
          (local_i - e_i) / sqrt(var_i)
        } else {
          0.0
        }
        let cluster = classify_lisa(z[i], local_i, e_i, z_score, threshold)
        out.push({ index: i, local_i, z_score, cluster, })
        i = i + 1
      }
      out
    }
  }
}

///|
/// k-nearest-neighbour binary weights, mutual-symmetrised: w_ij = 1 iff i is
/// among the k nearest of j OR j is among the k nearest of i. Each list
/// includes `i` itself first (for Gi* usage); skip self when interpreting
/// Moran/LISA (the statistics ignore self-entries).
pub fn knn_weights(
  points : Array[@types.GeoPoint],
  k? : Int = 5,
) -> Array[Array[Int]] {
  let n = points.length()
  if n == 0 {
    return []
  }
  // Brute-force kNN per point (fine for the data sizes this library targets).
  let knn : Array[Array[Int]] = []
  let mut i = 0
  while i < n {
    let cands : Array[(Int, Double)] = []
    let mut j = 0
    while j < n {
      if j != i {
        cands.push((j, haversine(points[i], points[j])))
      }
      j = j + 1
    }
    cands.sort_by(fn(a, b) {
      if a.1 < b.1 {
        -1
      } else if a.1 > b.1 {
        1
      } else {
        0
      }
    })
    let kk = if k < cands.length() { k } else { cands.length() }
    let list : Array[Int] = []
    let mut m = 0
    for c in cands {
      if m >= kk {
        break
      }
      list.push(c.0)
      m = m + 1
    }
    knn.push(list)
    i = i + 1
  }
  // Symmetrise: w_ij = 1 iff j in knn[i] OR i in knn[j]. Prepend self.
  let weights : Array[Array[Int]] = []
  let mut i2 = 0
  while i2 < n {
    let row : Array[Int] = [i2]
    let mut j = 0
    while j < n {
      if j != i2 && (contains_int(knn[i2], j) || contains_int(knn[j], i2)) {
        row.push(j)
      }
      j = j + 1
    }
    weights.push(row)
    i2 = i2 + 1
  }
  weights
}

///|
/// Linear membership test for small int arrays.
fn contains_int(arr : Array[Int], target : Int) -> Bool {
  for v in arr {
    if v == target {
      return true
    }
  }
  false
}

///|
/// Distance-threshold binary weights: w_ij = 1 iff haversine(i, j) <= radius_km.
/// Each list includes `i` itself first (for Gi* usage).
pub fn distance_weights(
  points : Array[@types.GeoPoint],
  radius_km~ : Double,
) -> Array[Array[Int]] {
  let n = points.length()
  let weights : Array[Array[Int]] = []
  let mut i = 0
  while i < n {
    let row : Array[Int] = []
    let mut j = 0
    while j < n {
      if haversine(points[i], points[j]) <= radius_km {
        row.push(j)
      }
      j = j + 1
    }
    weights.push(row)
    i = i + 1
  }
  weights
}

///|
/// Standard normal CDF via the Abramowitz-Stegun 26.2.17 rational
/// approximation (|error| < 7.5e-8).
pub fn normal_cdf(z : Double) -> Double {
  if z != z {
    return 0.5 // NaN guard
  }
  if z > 8.0 {
    return 1.0
  }
  if z < -8.0 {
    return 0.0
  }
  let neg = z < 0.0
  let x = if neg { -z } else { z }
  let t = 1.0 / (1.0 + 0.2316419 * x)
  let pdf = @math.exp(-x * x / 2.0) / 2.5066282746310002
  let poly = t *
    (
      0.319381530 +
      t *
      (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429)))
    )
  let upper = 1.0 - pdf * poly
  if neg {
    1.0 - upper
  } else {
    upper
  }
}

///|
/// Two-sided p-value for a standard normal z-score.
fn two_sided_p(z : Double) -> Double {
  let p = 2.0 * (1.0 - normal_cdf(if z < 0.0 { -z } else { z }))
  if p < 0.0 {
    0.0
  } else if p > 1.0 {
    1.0
  } else {
    p
  }
}

///|
/// Mean and sum of squared deviations; None when all values are identical.
fn value_stats(values : Array[Double]) -> (Double, Double)? {
  let n = values.length()
  if n == 0 {
    return None
  }
  let mut mean = 0.0
  for v in values {
    mean = mean + v
  }
  mean = mean / n.to_double()
  let mut sq = 0.0
  for v in values {
    let d = v - mean
    sq = sq + d * d
  }
  if sq == 0.0 {
    None
  } else {
    Some((mean, sq))
  }
}

///|
/// Whether row `row` of the weight lists contains `target`.
fn has_neighbor(weights : Array[Array[Int]], row : Int, target : Int) -> Bool {
  if row < 0 || row >= weights.length() {
    return false
  }
  for j in weights[row] {
    if j == target {
      return true
    }
  }
  false
}

///|
/// Anselin LISA cluster typing: quadrant of (z_i, local I) when significant.
fn classify_lisa(
  zi : Double,
  local_i : Double,
  expected_i : Double,
  z_score : Double,
  threshold : Double,
) -> String {
  if z_score.abs() <= threshold {
    return "NS"
  }
  let above = local_i > expected_i
  if zi > 0.0 && above {
    "HH"
  } else if zi < 0.0 && above {
    "LL"
  } else if zi > 0.0 {
    "HL"
  } else {
    "LH"
  }
}
