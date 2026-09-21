// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

///|
/// Earth's mean radius in kilometers (WGS84).
pub let earth_radius_km : Double = 6371.0088

///|
/// Convert degrees to radians.
pub fn to_rad(deg : Double) -> Double {
  deg * 3.14159265358979323846 / 180.0
}

///|
/// Convert radians to degrees.
pub fn to_deg(rad : Double) -> Double {
  rad * 180.0 / 3.14159265358979323846
}

///|
/// Square helper.
fn sq(x : Double) -> Double {
  x * x
}

///|
/// Square root via math.pow (no direct sqrt in core).
pub fn sqrt(x : Double) -> Double {
  @math.pow(x, 0.5)
}

///|
/// Great-circle distance between two points (Haversine), in kilometers.
pub fn haversine(p1 : @types.GeoPoint, p2 : @types.GeoPoint) -> Double {
  let lat1 = to_rad(p1.lat)
  let lat2 = to_rad(p2.lat)
  let dlat = to_rad(p2.lat - p1.lat)
  let dlng = to_rad(p2.lng - p1.lng)
  let a = sq(@math.sin(dlat / 2.0)) +
    @math.cos(lat1) * @math.cos(lat2) * sq(@math.sin(dlng / 2.0))
  let c = 2.0 * @math.atan2(sqrt(a), sqrt(1.0 - a))
  earth_radius_km * c
}

///|
/// Initial bearing from p1 to p2 in degrees [0, 360).
pub fn bearing(p1 : @types.GeoPoint, p2 : @types.GeoPoint) -> Double {
  let lat1 = to_rad(p1.lat)
  let lat2 = to_rad(p2.lat)
  let dlng = to_rad(p2.lng - p1.lng)
  let y = @math.sin(dlng) * @math.cos(lat2)
  let x = @math.cos(lat1) * @math.sin(lat2) -
    @math.sin(lat1) * @math.cos(lat2) * @math.cos(dlng)
  let theta = @math.atan2(y, x)
  (to_deg(theta) + 360.0) % 360.0
}

///|
/// Test whether a point lies inside an axis-aligned bbox.
pub fn bbox_contains(b : @types.BBox, p : @types.GeoPoint) -> Bool {
  p.lat >= b.min_lat &&
  p.lat <= b.max_lat &&
  p.lng >= b.min_lng &&
  p.lng <= b.max_lng
}

///|
/// Approximate bbox centered at `center` covering a circle of `radius_km`.
/// Uses equirectangular approximation: 1° lat ≈ 111.32 km,
/// 1° lng ≈ 111.32 * cos(lat) km. Good enough for sub-city scale queries.
pub fn bbox_around(center : @types.GeoPoint, radius_km : Double) -> @types.BBox {
  let km_per_deg_lat = 111.32
  let km_per_deg_lng = 111.32 * @math.cos(to_rad(center.lat))
  // Guard against poles where cos(lat) -> 0.
  let km_per_deg_lng_safe = if km_per_deg_lng.abs() < 0.000001 {
    0.000001
  } else {
    km_per_deg_lng
  }
  let dlat = radius_km / km_per_deg_lat
  let dlng = radius_km / km_per_deg_lng_safe
  {
    min_lat: center.lat - dlat,
    max_lat: center.lat + dlat,
    min_lng: center.lng - dlng,
    max_lng: center.lng + dlng,
  }
}

///|
/// Intersect two bboxes; returns None if they don't overlap.
pub fn bbox_intersect(a : @types.BBox, b : @types.BBox) -> @types.BBox? {
  let min_lat = @cmp.maximum(a.min_lat, b.min_lat)
  let max_lat = @cmp.minimum(a.max_lat, b.max_lat)
  let min_lng = @cmp.maximum(a.min_lng, b.min_lng)
  let max_lng = @cmp.minimum(a.max_lng, b.max_lng)
  if min_lat > max_lat || min_lng > max_lng {
    None
  } else {
    Some({ min_lat, max_lat, min_lng, max_lng, })
  }
}

// ---- Geohash encoding / decoding ----

///|
/// Geohash base32 characters.
let geohash_chars : String = "0123456789bcdefghjkmnpqrstuvwxyz"

///|
let geohash_char_array : Array[String] = [
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "b", "c", "d", "e", "f", "g",
  "h", "j", "k", "m", "n", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
]

///|
fn byte_to_string(b : Char) -> String {
  // Convert a Char to its 1-character string by looking up in the geohash array.
  let code = b.to_int()
  let chars = geohash_chars
  let mut i = 0
  while i < chars.length() {
    if chars[i].to_int() == code {
      return geohash_char_array[i]
    }
    i = i + 1
  }
  ""
}

///|
/// Encode a (lat, lng) pair into a Geohash string of given precision.
/// Precision 1..9 is supported (higher = more accurate).
/// Returns empty string on invalid precision.
pub fn geohash_encode(lat : Double, lng : Double, precision : Int) -> String {
  if precision < 1 || precision > 9 {
    return ""
  }
  let lat_range : Array[Double] = [-90.0, 90.0]
  let lng_range : Array[Double] = [-180.0, 180.0]
  let mut is_even = true
  // Start with MSB (16 = 10000 in binary for a 5-bit character).
  let mut bit = 16
  let mut ch = 0
  let mut hash = ""
  let mut i = 0
  while i < precision * 5 {
    if is_even {
      let mid = (lng_range[0] + lng_range[1]) / 2.0
      if lng >= mid {
        ch = ch + bit
        lng_range[0] = mid
      } else {
        lng_range[1] = mid
      }
    } else {
      let mid = (lat_range[0] + lat_range[1]) / 2.0
      if lat >= mid {
        ch = ch + bit
        lat_range[0] = mid
      } else {
        lat_range[1] = mid
      }
    }
    is_even = !is_even
    if bit == 1 {
      // All 5 bits collected: write character and reset.
      hash = hash + geohash_char_at(ch)
      ch = 0
      bit = 16
    } else {
      bit = bit / 2
    }
    i = i + 1
  }
  hash
}

///|
fn geohash_char_at(n : Int) -> String {
  let i = n % 32
  geohash_char_array[i]
}

///|
/// Decode a Geohash string back to a (lat, lng) pair.
/// Returns (lat, lng) as a GeoPoint, or (0,0) on invalid input.
pub fn geohash_decode(hash : String) -> @types.GeoPoint {
  if hash.length() == 0 {
    return @types.GeoPoint::make(0.0, 0.0)
  }
  let lat_range : Array[Double] = [-90.0, 90.0]
  let lng_range : Array[Double] = [-180.0, 180.0]
  let mut is_even = true
  let mut i = 0
  while i < hash.length() {
    let ch = byte_to_string(hash.get_char(i).unwrap())
    let cd = geohash_decode_char(ch)
    let mut mask = 16
    while mask >= 1 {
      if is_even {
        let mid = (lng_range[0] + lng_range[1]) / 2.0
        if (cd & mask) != 0 {
          lng_range[0] = mid
        } else {
          lng_range[1] = mid
        }
      } else {
        let mid = (lat_range[0] + lat_range[1]) / 2.0
        if (cd & mask) != 0 {
          lat_range[0] = mid
        } else {
          lat_range[1] = mid
        }
      }
      is_even = !is_even
      mask = mask / 2
    }
    i = i + 1
  }
  let lat = (lat_range[0] + lat_range[1]) / 2.0
  let lng = (lng_range[0] + lng_range[1]) / 2.0
  @types.GeoPoint::make(lat, lng)
}

///|
fn geohash_decode_char(ch : String) -> Int {
  let mut i = 0
  while i < geohash_char_array.length() {
    if geohash_char_array[i] == ch {
      return i
    }
    i = i + 1
  }
  0
}

// ---- WGS84 ↔ GCJ-02 coordinate conversion ----

///|
/// Convert WGS84 coordinates to GCJ-02 (Mars coordinates).
/// This is the standard offset algorithm used by Chinese map providers.
pub fn wgs84_to_gcj02(lng : Double, lat : Double) -> (Double, Double) {
  // Only apply offset within China's rough bounding box.
  if !in_china(lng, lat) {
    return (lng, lat)
  }
  let dlat = transform_lat(lng - 105.0, lat - 35.0)
  let dlng = transform_lng(lng - 105.0, lat - 35.0)
  let radlat = lat / 180.0 * 3.14159265358979323846
  let sin_val = @math.sin(radlat)
  let magic = 1.0 + 0.000002 * sin_val
  let dlat_final = dlat * 180.0 / (6378245.0 * (1.0 - 0.00669342162296594323))
  let dlng_final = dlng * 180.0 / (6378245.0 * magic * @math.cos(radlat))
  (lng + dlng_final, lat + dlat_final)
}

///|
/// Convert GCJ-02 coordinates back to WGS84.
pub fn gcj02_to_wgs84(lng : Double, lat : Double) -> (Double, Double) {
  let (glng, glat) = wgs84_to_gcj02(lng, lat)
  (lng * 2.0 - glng, lat * 2.0 - glat)
}

///|
fn in_china(lng : Double, lat : Double) -> Bool {
  lng > 73.66 && lng < 135.05 && lat > 3.86 && lat < 53.55
}

///|
fn transform_lat(x : Double, y : Double) -> Double {
  let abs_x = if x < 0.0 { -x } else { x }
  let mut ret = -100.0 +
    2.0 * x +
    3.0 * y +
    0.2 * y * y +
    0.1 * x * y +
    0.2 * sqrt(abs_x)
  ret = ret +
    (
      20.0 * @math.sin(6.0 * x * 3.14159265358979323846) +
      20.0 * @math.sin(2.0 * x * 3.14159265358979323846)
    ) *
    2.0 /
    3.0
  ret = ret +
    (
      20.0 * @math.sin(y * 3.14159265358979323846) +
      40.0 * @math.sin(y / 3.0 * 3.14159265358979323846)
    ) *
    2.0 /
    3.0
  ret = ret +
    (
      160.0 * @math.sin(y / 12.0 * 3.14159265358979323846) +
      320 * @math.sin(y * 3.14159265358979323846 / 30.0)
    ) *
    2.0 /
    3.0
  ret
}

///|
fn transform_lng(x : Double, y : Double) -> Double {
  let abs_x = if x < 0.0 { -x } else { x }
  let mut ret = 300.0 +
    x +
    2.0 * y +
    0.1 * x * x +
    0.1 * x * y +
    0.1 * sqrt(abs_x)
  ret = ret +
    (
      20.0 * @math.sin(6.0 * x * 3.14159265358979323846) +
      20.0 * @math.sin(2.0 * x * 3.14159265358979323846)
    ) *
    2.0 /
    3.0
  ret = ret +
    (
      20.0 * @math.sin(x * 3.14159265358979323846) +
      40.0 * @math.sin(x / 3.0 * 3.14159265358979323846)
    ) *
    2.0 /
    3.0
  ret = ret +
    (
      150.0 * @math.sin(x / 12.0 * 3.14159265358979323846) +
      300.0 * @math.sin(x / 30.0 * 3.14159265358979323846)
    ) *
    2.0 /
    3.0
  ret
}

// ---- Convex Hull (Andrew's monotone chain) ----

///|
/// Compute the convex hull of a set of GeoPoints.
/// Returns an array of points forming the convex hull in counter-clockwise order.
/// Returns empty array if fewer than 3 distinct points exist.
pub fn convex_hull(points : Array[@types.GeoPoint]) -> Array[@types.GeoPoint] {
  let n = points.length()
  if n < 3 {
    // Return distinct points.
    let result : Array[@types.GeoPoint] = []
    for p in points {
      if result.length() == 0 {
        result.push(p)
      } else {
        let mut dup = false
        let mut i = 0
        while i < result.length() {
          if result[i].lat == p.lat && result[i].lng == p.lng {
            dup = true
            break
          }
          i = i + 1
        }
        if !dup {
          result.push(p)
        }
      }
    }
    return result
  }
  // Sort by latitude first, then longitude.
  let sorted = sort_points_by_lat(points)
  let unique = remove_duplicate_points(sorted)
  if unique.length() < 3 {
    return unique
  }
  // Build lower hull.
  let lower : Array[@types.GeoPoint] = []
  for p in unique {
    while lower.length() >= 2 {
      let o = lower[lower.length() - 2]
      let a = lower[lower.length() - 1]
      let cross = cross_product(o, a, p)
      if cross <= 0.0 {
        ignore(lower.remove(lower.length() - 1))
      } else {
        break
      }
    }
    lower.push(p)
  }
  // Build upper hull.
  let upper : Array[@types.GeoPoint] = []
  let mut i = unique.length() - 1
  while i >= 0 {
    let p = unique[i]
    while upper.length() >= 2 {
      let o = upper[upper.length() - 2]
      let a = upper[upper.length() - 1]
      let cross = cross_product(o, a, p)
      if cross <= 0.0 {
        ignore(upper.remove(upper.length() - 1))
      } else {
        break
      }
    }
    upper.push(p)
    i = i - 1
  }
  // Concatenate, remove duplicate endpoints.
  ignore(lower.remove(lower.length() - 1))
  ignore(upper.remove(upper.length() - 1))
  for p in upper {
    lower.push(p)
  }
  lower
}

///|
fn cross_product(
  o : @types.GeoPoint,
  a : @types.GeoPoint,
  b : @types.GeoPoint,
) -> Double {
  (a.lat - o.lat) * (b.lng - o.lng) - (a.lng - o.lng) * (b.lat - o.lat)
}

///|
fn sort_points_by_lat(
  points : Array[@types.GeoPoint],
) -> Array[@types.GeoPoint] {
  let result = points
  result.sort_by(fn(a, b) {
    if a.lat < b.lat {
      -1
    } else if a.lat > b.lat {
      1
    } else if a.lng < b.lng {
      -1
    } else if a.lng > b.lng {
      1
    } else {
      0
    }
  })
  result
}

///|
fn remove_duplicate_points(
  points : Array[@types.GeoPoint],
) -> Array[@types.GeoPoint] {
  let result : Array[@types.GeoPoint] = []
  for p in points {
    if result.length() == 0 {
      result.push(p)
    } else {
      let last = result[result.length() - 1]
      if last.lat != p.lat || last.lng != p.lng {
        result.push(p)
      }
    }
  }
  result
}

///|
/// Compute the area of a polygon defined by an ordered list of GeoPoints.
/// Uses the spherical excess approximation (shoelace on projected lat/lng).
/// Returns area in square kilometers. Returns 0 for fewer than 3 points.
pub fn polygon_area(points : Array[@types.GeoPoint]) -> Double {
  let n = points.length()
  if n < 3 {
    return 0.0
  }
  let lat0 = points[0].lat
  let cos_lat = @math.cos(lat0 * 3.14159265358979323846 / 180.0)
  let m_per_deg_lat = 111320.0
  let m_per_deg_lng = 111320.0 * cos_lat
  let mut area = 0.0
  let mut i = 0
  while i < n {
    let j = (i + 1) % n
    let xi = points[i].lng * m_per_deg_lng
    let yi = points[i].lat * m_per_deg_lat
    let xj = points[j].lng * m_per_deg_lng
    let yj = points[j].lat * m_per_deg_lat
    area = area + xi * yj - xj * yi
    i = i + 1
  }
  // abs value and convert m² to km².
  let abs_area = if area < 0.0 { -area } else { area }
  abs_area / 2.0 / 1_000_000.0
}

///|
/// Test whether a point lies inside a polygon (ray casting algorithm).
/// Returns `true` if the point is strictly inside the polygon.
pub fn point_in_polygon(
  point : @types.GeoPoint,
  polygon : Array[@types.GeoPoint],
) -> Bool {
  let n = polygon.length()
  if n < 3 {
    return false
  }
  let mut inside = false
  let mut j = n - 1
  let mut i = 0
  while i < n {
    let pi = polygon[i]
    let pj = polygon[j]
    let intersect = (pi.lat > point.lat) != (pj.lat > point.lat) &&
      point.lng <
      (pj.lng - pi.lng) * (point.lat - pi.lat) / (pj.lat - pi.lat) + pi.lng
    if intersect {
      inside = !inside
    }
    j = i
    i = i + 1
  }
  inside
}

///|
/// Return the 9 geohash neighbors (3×3 grid) around a given geohash.
/// The center hash is included as the first element.
pub fn geohash_neighbors(hash : String) -> Array[String] {
  if hash.length() == 0 {
    return []
  }
  let center = geohash_decode(hash)
  let precision = hash.length()
  let (lat_span, lng_span) = geohash_cell_size(precision)
  let results : Array[String] = []
  let dlat_vals : Array[Double] = [-lat_span, 0.0, lat_span]
  let dlng_vals : Array[Double] = [-lng_span, 0.0, lng_span]
  for dlat in dlat_vals {
    for dlng in dlng_vals {
      let lat = center.lat + dlat
      let lng = center.lng + dlng
      let clamped_lat = if lat > 90.0 {
        90.0
      } else if lat < -90.0 {
        -90.0
      } else {
        lat
      }
      let clamped_lng = if lng > 180.0 {
        180.0
      } else if lng < -180.0 {
        -180.0
      } else {
        lng
      }
      results.push(geohash_encode(clamped_lat, clamped_lng, precision))
    }
  }
  results
}

///|
/// Return the approximate cell size (lat_span, lng_span) for a geohash precision.
pub fn geohash_cell_size(precision : Int) -> (Double, Double) {
  if precision < 1 || precision > 9 {
    return (0.0, 0.0)
  }
  let mut lat_span = 180.0
  let mut lng_span = 360.0
  let mut is_even = true
  let mut i = 0
  while i < precision {
    if is_even {
      lng_span = lng_span / 2.0
    } else {
      lat_span = lat_span / 2.0
    }
    is_even = !is_even
    i = i + 1
  }
  (lat_span, lng_span)
}

///|
/// Convert a geohash string to its approximate bounding box.
pub fn geohash_to_bbox(hash : String) -> @types.BBox {
  if hash.length() == 0 {
    return @types.BBox::from_corners(
      @types.GeoPoint::make(-90.0, -180.0),
      @types.GeoPoint::make(90.0, 180.0),
    )
  }
  let precision = hash.length()
  let center = geohash_decode(hash)
  let (lat_span, lng_span) = geohash_cell_size(precision)
  let half_lat = lat_span / 2.0
  let half_lng = lng_span / 2.0
  let sw = @types.GeoPoint::make(center.lat - half_lat, center.lng - half_lng)
  let ne = @types.GeoPoint::make(center.lat + half_lat, center.lng + half_lng)
  @types.BBox::from_corners(sw, ne)
}

///|
/// Compute the average nearest-neighbor distance for a set of points.
pub fn average_nn_distance(points : Array[@types.GeoPoint]) -> Double {
  let n = points.length()
  if n < 2 {
    return 0.0
  }
  let mut total = 0.0
  let mut count : Int = 0
  let mut i = 0
  while i < n {
    let mut min_d = 1.7976931348623157e+308
    let mut j = 0
    while j < n {
      if i != j {
        let d = haversine(points[i], points[j])
        if d < min_d {
          min_d = d
        }
      }
      j = j + 1
    }
    total = total + min_d
    count = count + 1
    i = i + 1
  }
  if count == 0 {
    0.0
  } else {
    total / count.to_double()
  }
}
// ---- Voronoi diagram (iterative clipping, planar approximation) ----

///|
/// A Voronoi cell: the site point and its clipped polygon (ordered vertices).
pub(all) struct VoronoiCell {
  site : @types.GeoPoint
  polygon : Array[@types.GeoPoint]
} derive(Eq, Debug)

///|
/// Compute the Voronoi diagram of a set of points within a bounding box.
/// Uses iterative half-plane clipping (O(n²) per cell, O(n³) total).
/// The planar approximation is accurate for small regions; for global-scale
/// data the result should be treated as an approximation.
pub fn voronoi_diagram(
  points : Array[@types.GeoPoint],
  bbox : @types.BBox,
) -> Array[VoronoiCell] {
  let n = points.length()
  if n == 0 {
    return []
  }
  let cells : Array[VoronoiCell] = []
  let mut i = 0
  while i < n {
    let site = points[i]
    let mut poly : Array[@types.GeoPoint] = [
      @types.GeoPoint::make(bbox.min_lat, bbox.min_lng),
      @types.GeoPoint::make(bbox.min_lat, bbox.max_lng),
      @types.GeoPoint::make(bbox.max_lat, bbox.max_lng),
      @types.GeoPoint::make(bbox.max_lat, bbox.min_lng),
    ]
    let mut j = 0
    while j < n {
      if i != j {
        let other = points[j]
        let (a, b, c) = perpendicular_bisector(site, other)
        // Keep the side containing `site` (negative side).
        poly = clip_polygon(poly, a, b, c, true)
        if poly.length() < 3 {
          break
        }
      }
      j = j + 1
    }
    if poly.length() >= 3 {
      cells.push({ site, polygon: poly, })
    }
    i = i + 1
  }
  cells
}

///|
/// Compute the perpendicular bisector line between two points in the form
/// a*lat + b*lng + c = 0 (planar approximation).
fn perpendicular_bisector(
  p1 : @types.GeoPoint,
  p2 : @types.GeoPoint,
) -> (Double, Double, Double) {
  let a = p2.lat - p1.lat
  let b = p2.lng - p1.lng
  let c = (
      p1.lat * p1.lat + p1.lng * p1.lng - p2.lat * p2.lat - p2.lng * p2.lng
    ) /
    2.0
  (a, b, c)
}

///|
/// Evaluate the signed distance of a point from the line a*lat + b*lng + c = 0.
/// Positive = one side, negative = the other, zero = on the line.
fn line_side(p : @types.GeoPoint, a : Double, b : Double, c : Double) -> Double {
  a * p.lat + b * p.lng + c
}

///|
/// Clip a polygon against a half-plane using the Sutherland-Hodgman algorithm.
/// `keep_negative` determines which side to keep (negative = true, positive = false).
fn clip_polygon(
  poly : Array[@types.GeoPoint],
  a : Double,
  b : Double,
  c : Double,
  keep_negative : Bool,
) -> Array[@types.GeoPoint] {
  let n = poly.length()
  if n == 0 {
    return []
  }
  let out : Array[@types.GeoPoint] = []
  let mut prev = poly[n - 1]
  let mut prev_side = side_sign(line_side(prev, a, b, c), keep_negative)
  let mut k = 0
  while k < n {
    let curr = poly[k]
    let curr_side = side_sign(line_side(curr, a, b, c), keep_negative)
    if prev_side {
      if curr_side {
        // Both inside: keep curr
        out.push(curr)
      } else {
        // Inside -> outside: keep intersection
        match segment_line_intersection(prev, curr, a, b, c) {
          Some(ip) => out.push(ip)
          None => ()
        }
      }
    } else if curr_side {
      // Outside -> inside: keep intersection + curr
      match segment_line_intersection(prev, curr, a, b, c) {
        Some(ip) => {
          out.push(ip)
          out.push(curr)
        }
        None => out.push(curr)
      }
    }
    // Both outside: keep nothing
    prev = curr
    prev_side = curr_side
    k = k + 1
  }
  out
}

///|
/// Determine whether a point is on the "keep" side of the bisector.
fn side_sign(value : Double, keep_negative : Bool) -> Bool {
  if keep_negative {
    value <= 0.0
  } else {
    value >= 0.0
  }
}

///|
/// Compute the intersection of a line segment with the line a*lat + b*lng + c = 0.
/// Returns None if the segment is parallel or degenerate.
fn segment_line_intersection(
  p1 : @types.GeoPoint,
  p2 : @types.GeoPoint,
  a : Double,
  b : Double,
  c : Double,
) -> @types.GeoPoint? {
  let d1 = line_side(p1, a, b, c)
  let d2 = line_side(p2, a, b, c)
  // If both on same side or either on the line, no proper intersection
  if d1 * d2 >= 0.0 {
    return None
  }
  // Linear interpolation: t = d1 / (d1 - d2)
  let t = d1 / (d1 - d2)
  let lat = p1.lat + t * (p2.lat - p1.lat)
  let lng = p1.lng + t * (p2.lng - p1.lng)
  Some(@types.GeoPoint::make(lat, lng))
}

// ---- K-Means clustering ----

///|
/// A single K-Means cluster result.
pub(all) struct KMeansCluster {
  id : Int
  center : @types.GeoPoint
  members : Array[Int] // indices into the original point array
} derive(Debug)

///|
/// Compute the centroid (arithmetic mean lat/lng) of a point array.
/// Returns (0, 0) for empty input.
pub fn centroid(points : Array[@types.GeoPoint]) -> @types.GeoPoint {
  let n = points.length()
  if n == 0 {
    return @types.GeoPoint::make(0.0, 0.0)
  }
  let mut sum_lat = 0.0
  let mut sum_lng = 0.0
  for p in points {
    sum_lat = sum_lat + p.lat
    sum_lng = sum_lng + p.lng
  }
  @types.GeoPoint::make(sum_lat / n.to_double(), sum_lng / n.to_double())
}

///|
/// Run K-Means clustering on a set of GeoPoints.
/// Uses lat/lng as 2D planar coordinates for centroid computation (not Haversine),
/// which is fine for regional-scale data. Haversine is still used for assignment.
///
/// - `k`: number of clusters (clamped to `[1, n]`).
/// - `max_iter`: maximum iterations (default 100).
///
/// Returns `k` KMeansCluster values sorted by cluster id.
pub fn kmeans(
  points : Array[@types.GeoPoint],
  k : Int,
  max_iter? : Int = 100,
) -> Array[KMeansCluster] {
  let n = points.length()
  if n == 0 {
    return []
  }
  // Clamp k.
  let mut kk = k
  if kk < 1 {
    kk = 1
  }
  if kk > n {
    kk = n
  }
  // Clamp max_iter.
  let mut iters = max_iter
  if iters < 1 {
    iters = 1
  }
  // K-Means++ initialization: choose centroids that are far apart.
  // 1. First centroid: pick a random point (use index 0 for determinism).
  let centroids : Array[@types.GeoPoint] = []
  centroids.push(points[0])
  // 2. For each remaining centroid, pick the point farthest from existing centroids.
  let mut ci = 1
  while ci < kk {
    let mut best_dist = -1.0
    let mut best_i = 0
    let mut i = 0
    while i < n {
      // Find minimum distance to any existing centroid.
      let mut min_d = 1.7976931348623157e+308
      let mut c = 0
      while c < centroids.length() {
        let d = haversine(points[i], centroids[c])
        if d < min_d {
          min_d = d
        }
        c = c + 1
      }
      // Pick the point with the maximum minimum distance.
      if min_d > best_dist {
        best_dist = min_d
        best_i = i
      }
      i = i + 1
    }
    centroids.push(points[best_i])
    ci = ci + 1
  }
  // Cluster assignments: cluster index for each point.
  let assignments : Array[Int] = []
  let mut a = 0
  while a < n {
    assignments.push(0)
    a = a + 1
  }
  let mut changed = true
  let mut iter = 0
  while changed && iter < iters {
    changed = false
    // Assignment step.
    let mut i = 0
    while i < n {
      let p = points[i]
      let mut best_c = 0
      let mut best_d = 1.7976931348623157e+308
      let mut c = 0
      while c < kk {
        let d = haversine(p, centroids[c])
        if d < best_d {
          best_d = d
          best_c = c
        }
        c = c + 1
      }
      if assignments[i] != best_c {
        assignments[i] = best_c
        changed = true
      }
      i = i + 1
    }
    // Update step: recompute centroids as planar mean of assigned points.
    let mut k_idx = 0
    while k_idx < kk {
      let mut sum_lat = 0.0
      let mut sum_lng = 0.0
      let mut count : Int = 0
      let mut j = 0
      while j < n {
        if assignments[j] == k_idx {
          sum_lat = sum_lat + points[j].lat
          sum_lng = sum_lng + points[j].lng
          count = count + 1
        }
        j = j + 1
      }
      if count > 0 {
        centroids[k_idx] = @types.GeoPoint::make(
          sum_lat / count.to_double(),
          sum_lng / count.to_double(),
        )
      } else {
        // Empty cluster: re-seed with a random point to avoid stagnation.
        // Pick a point farthest from existing centroids to encourage exploration.
        let mut best_dist = -1.0
        let mut best_i = 0
        let mut i = 0
        while i < n {
          if assignments[i] != k_idx {
            let mut min_d = 1.7976931348623157e+308
            let mut c = 0
            while c < kk {
              if c != k_idx {
                let d = haversine(points[i], centroids[c])
                if d < min_d {
                  min_d = d
                }
              }
              c = c + 1
            }
            if min_d > best_dist {
              best_dist = min_d
              best_i = i
            }
          }
          i = i + 1
        }
        centroids[k_idx] = points[best_i]
      }
      k_idx = k_idx + 1
    }
    iter = iter + 1
  }
  // Build result.
  let clusters : Array[KMeansCluster] = []
  let mut k_idx = 0
  while k_idx < kk {
    let members : Array[Int] = []
    let mut j = 0
    while j < n {
      if assignments[j] == k_idx {
        members.push(j)
      }
      j = j + 1
    }
    clusters.push({ id: k_idx, center: centroids[k_idx], members, })
    k_idx = k_idx + 1
  }
  clusters
}

///|
/// Find which cluster a point would be assigned to given the centroids.
/// Returns None if centroids is empty.
pub fn nearest_cluster(
  point : @types.GeoPoint,
  centroids : Array[@types.GeoPoint],
) -> Int? {
  if centroids.length() == 0 {
    return None
  }
  let mut best = 0
  let mut best_d = 1.7976931348623157e+308
  let mut i = 0
  while i < centroids.length() {
    let d = haversine(point, centroids[i])
    if d < best_d {
      best_d = d
      best = i
    }
    i = i + 1
  }
  Some(best)
}

///|
/// Compute the within-cluster sum of squares (WCSS / inertia) for a K-Means result.
/// A smaller value means tighter clusters. Useful for the "elbow method".
pub fn kmeans_inertia(
  points : Array[@types.GeoPoint],
  clusters : Array[KMeansCluster],
) -> Double {
  let mut total = 0.0
  for cl in clusters {
    for idx in cl.members {
      total = total + sq(haversine(points[idx], cl.center))
    }
  }
  total
}

// ---- Moran's I spatial autocorrelation ----

///|
/// Result of Moran's I computation.
/// `index` is the Moran's I statistic (-1 to 1).
/// `interpretation`:
///   Positive I → clustered (like values near each other)
///   I ≈ 0      → random spatial distribution
///   Negative I → dispersed (unlike values near each other)
pub(all) struct MoranIResult {
  index : Double
  expected : Double // -1/(n-1), the null expectation
  n : Int
} derive(Debug)

///|
/// Compute Moran's I spatial autocorrelation statistic for a set of
/// points with numeric attribute values. Uses an inverse-distance-weighted
/// spatial weight matrix: w_ij = 1 / haversine(p_i, p_j).
///
/// `points`: geographic locations
/// `values`: attribute values at each location (same length)
///
/// Returns MoranIResult or None if fewer than 3 points.
pub fn morans_i(
  points : Array[@types.GeoPoint],
  values : Array[Double],
) -> MoranIResult? {
  let n = points.length()
  if n < 3 || values.length() != n {
    return None
  }
  let nf = n.to_double()
  // Compute mean.
  let mut sum_v = 0.0
  for v in values {
    sum_v = sum_v + v
  }
  let mean_v = sum_v / nf
  // Center values.
  let z : Array[Double] = []
  for v in values {
    z.push(v - mean_v)
  }
  // Compute denominator: sum z_i².
  let mut denom = 0.0
  for zi in z {
    denom = denom + zi * zi
  }
  if denom == 0.0 {
    return None // All values identical
  }
  // Build weight matrix + row sums, then row-standardize.
  // Raw weight w_ij = 1/haversine(p_i, p_j) for i != j.
  let raw_w : Array[Array[Double]] = []
  let mut i = 0
  while i < n {
    let row : Array[Double] = []
    let mut w_sum_row = 0.0
    let mut j = 0
    while j < n {
      if i == j {
        row.push(0.0)
      } else {
        let d = haversine(points[i], points[j])
        let w = if d > 0.0 { 1.0 / d } else { 0.0 }
        row.push(w)
        w_sum_row = w_sum_row + w
      }
      j = j + 1
    }
    // Row-standardize so each row sums to 1.
    let norm_row : Array[Double] = []
    if w_sum_row > 0.0 {
      for w in row {
        norm_row.push(w / w_sum_row)
      }
    } else {
      for w in row {
        norm_row.push(w)
      }
    }
    raw_w.push(norm_row)
    i = i + 1
  }
  // Compute numerator with row-standardized weights.
  let mut num = 0.0
  i = 0
  while i < n {
    let mut j = 0
    while j < n {
      if i != j {
        num = num + raw_w[i][j] * z[i] * z[j]
      }
      j = j + 1
    }
    i = i + 1
  }
  // With row-standardized weights (each row sums to 1), W = n, so:
  // I = (n/n) * num/denom = num / denom
  let index = num / denom
  let expected = -1.0 / (nf - 1.0)
  Some({ index, expected, n, })
}

///|
/// Moran's I with **k-nearest-neighbor weights** instead of the full n×n
/// distance matrix. Much faster for large n: O(n·k·log n) vs O(n²).
/// Each point's weight row sums to 1 (row-standardized), so the result is
/// directly comparable to `morans_i`.
pub fn morans_i_knn(
  points : Array[@types.GeoPoint],
  values : Array[Double],
  k? : Int = 8,
) -> MoranIResult? {
  let n = points.length()
  if n < 3 || values.length() != n {
    return None
  }
  let nf = n.to_double()
  let k_eff = if k < n - 1 { k } else { n - 1 }
  // Mean-center values.
  let mut sum_v = 0.0
  for v in values { sum_v = sum_v + v }
  let mean_v = sum_v / nf
  let z : Array[Double] = []
  for v in values { z.push(v - mean_v) }
  let mut denom = 0.0
  for zi in z { denom = denom + zi * zi }
  if denom == 0.0 { return None }
  // For each point, find its k nearest neighbors (haversine).
  let mut num = 0.0
  let mut i = 0
  while i < n {
    // Compute distances from points[i] to all others, take k smallest.
    let dists : Array[(Double, Int)] = []
    let mut j = 0
    while j < n {
      if j != i { dists.push((haversine(points[i], points[j]), j)) }
      j = j + 1
    }
    dists.sort_by(fn(a, b) { if a.0 < b.0 { -1 } else if a.0 > b.0 { 1 } else { 0 } })
    // Row-standardized weights: each of k neighbors gets weight 1/k.
    let mut jj = 0
    while jj < k_eff {
      let (_, idx) = dists[jj]
      num = num + (1.0 / k_eff.to_double()) * z[i] * z[idx]
      jj = jj + 1
    }
    i = i + 1
  }
  // With row-standardized weights, W = n → I = num / denom.
  let index = num / denom
  let expected = -1.0 / (nf - 1.0)
  Some({ index, expected, n })
}

// ---- Standard Deviation Ellipse (SDE) ----

///|
/// Standard Deviation Ellipse result: measures directional dispersion of
/// a point set. The center equals the centroid; `semi_major` >= `semi_minor`.
pub(all) struct StdDevEllipse {
  center : @types.GeoPoint
  semi_major_km : Double
  semi_minor_km : Double
  rotation_deg : Double // degrees clockwise from north
  area_sq_km : Double
  eccentricity : Double // sqrt(1 - (b/a)²), 0 = circle, 1 = line
} derive(Debug)

///|
/// Compute the Standard Deviation Ellipse of a point set.
/// Projects lat/lng to a local km coordinate system using equirectangular
/// approximation centered on the centroid. Returns None for < 3 points.
pub fn std_dev_ellipse(points : Array[@types.GeoPoint]) -> StdDevEllipse? {
  let n = points.length()
  if n < 3 {
    return None
  }
  let center = centroid(points)
  let cos_lat = @math.cos(center.lat * 3.14159265358979323846 / 180.0)
  let cos_lat_safe = if cos_lat.abs() < 0.000001 { 0.000001 } else { cos_lat }
  let km_per_deg_lat = 111.32
  let km_per_deg_lng = 111.32 * cos_lat_safe
  // Project to local (x_km, y_km). y = north, x = east.
  let xs : Array[Double] = []
  let ys : Array[Double] = []
  for p in points {
    let x = (p.lng - center.lng) * km_per_deg_lng
    let y = (p.lat - center.lat) * km_per_deg_lat
    xs.push(x)
    ys.push(y)
  }
  let nf = n.to_double()
  // Covariance terms (centered at origin already, since we subtracted mean).
  let mut sxx = 0.0
  let mut syy = 0.0
  let mut sxy = 0.0
  let mut i = 0
  while i < n {
    sxx = sxx + xs[i] * xs[i]
    syy = syy + ys[i] * ys[i]
    sxy = sxy + xs[i] * ys[i]
    i = i + 1
  }
  sxx = sxx / nf
  syy = syy / nf
  sxy = sxy / nf
  // Solve 2x2 eigenvalue problem for the ellipse axes.
  // Eigenvalues of [[sxx, sxy], [sxy, syy]].
  let trace = sxx + syy
  let det = sxx * syy - sxy * sxy
  let diff = sqrt((sxx - syy) * (sxx - syy) + 4.0 * sxy * sxy)
  let lambda1 = (trace + diff) / 2.0
  let lambda2 = (trace - diff) / 2.0
  let semi_major = if lambda1 >= lambda2 {
    sqrt(lambda1)
  } else {
    sqrt(lambda2)
  }
  let semi_minor = if lambda1 >= lambda2 {
    sqrt(lambda2)
  } else {
    sqrt(lambda1)
  }
  // Rotation angle: the eigenvector for the largest eigenvalue.
  // angle = 0.5 * atan2(2*sxy, sxx - syy), converted so 0° = north.
  let rot_rad = 0.5 * @math.atan2(2.0 * sxy, sxx - syy)
  // Convert from math convention (0 = east, CCW) to compass (0 = north, CW).
  let rot_deg = (90.0 - rot_rad * 180.0 / 3.14159265358979323846 + 360.0) %
    360.0
  let area = 3.14159265358979323846 * semi_major * semi_minor
  let ecc = if semi_major > 0.0 {
    sqrt(1.0 - semi_minor / semi_major * (semi_minor / semi_major))
  } else {
    0.0
  }
  Some({
    center,
    semi_major_km: semi_major,
    semi_minor_km: semi_minor,
    rotation_deg: rot_deg,
    area_sq_km: area,
    eccentricity: ecc,
  })
}

///|
/// Return a human-readable compass direction from a bearing in degrees [0, 360).
pub fn compass_direction(bearing_deg : Double) -> String {
  let b = (bearing_deg % 360.0 + 360.0) % 360.0
  let dirs : Array[String] = [
    "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W",
    "WNW", "NW", "NNW",
  ]
  let idx = ((b + 11.25) / 22.5).to_int() % 16
  dirs[idx]
}

// ---- IDW Inverse Distance Weighting ----

///|
/// Inverse Distance Weighting interpolation.
///
/// Given known (point, value) pairs and a query point, estimate the value
/// at the query location as a weighted average where weights decay with
/// distance raised to the power `power` (default 2.0, the classic power).
///
/// Returns None if no input points or if the query point coincides with a
/// known point (returns that known value directly in that case).
pub fn idw_interpolate(
  points : Array[@types.GeoPoint],
  values : Array[Double],
  query : @types.GeoPoint,
  power? : Double = 2.0,
) -> Double? {
  let n = points.length()
  if n < 1 || values.length() != n {
    return None
  }
  let mut num = 0.0
  let mut w_sum = 0.0
  let mut i = 0
  while i < n {
    let d = haversine(query, points[i])
    if d < 0.000001 {
      // Coincides with a known point → exact value.
      return Some(values[i])
    }
    let w = 1.0 / @math.pow(d, power)
    num = num + w * values[i]
    w_sum = w_sum + w
    i = i + 1
  }
  if w_sum == 0.0 {
    None
  } else {
    Some(num / w_sum)
  }
}

///|
/// IDW interpolation restricted to the k nearest neighbors only.
/// Faster and more localized than using all points.
pub fn idw_interpolate_knn(
  points : Array[@types.GeoPoint],
  values : Array[Double],
  query : @types.GeoPoint,
  k : Int,
  power? : Double = 2.0,
) -> Double? {
  let n = points.length()
  if n < 1 || values.length() != n {
    return None
  }
  let k_eff = if k < n { k } else { n }
  // Compute all distances, take k smallest.
  let dists : Array[(Double, Double)] = []
  let mut i = 0
  while i < n {
    dists.push((haversine(query, points[i]), values[i]))
    i = i + 1
  }
  dists.sort_by(fn(a, b) { if a.0 < b.0 { -1 } else if a.0 > b.0 { 1 } else { 0 } })
  let mut num = 0.0
  let mut w_sum = 0.0
  let mut j = 0
  while j < k_eff {
    let (d, v) = dists[j]
    if d < 0.000001 {
      return Some(v)
    }
    let w = 1.0 / @math.pow(d, power)
    num = num + w * v
    w_sum = w_sum + w
    j = j + 1
  }
  if w_sum == 0.0 { None } else { Some(num / w_sum) }
}

// ---- Concave Hull (Alpha-Shape) ----

///|
/// Compute the concave hull (alpha-shape) of a point set using the
/// Delaunay triangulation. Edges whose circumcircle radius exceeds
/// `1/alpha` are removed; the remaining boundary edges form the hull.
///
/// - `alpha`: Controls concavity. alpha=0 → convex hull; alpha→∞ → all
///   points lie on the hull boundary. Typical values 0.5 – 2.0.
/// - Returns the ordered boundary vertices (as GeoPoints).
/// - For < 3 points, falls back to convex_hull.
pub fn concave_hull(
  points : Array[@types.GeoPoint],
  alpha : Double,
) -> Array[@types.GeoPoint] {
  let n = points.length()
  if n < 3 || alpha <= 0.0 {
    return convex_hull(points)
  }
  // Guard: Delaunay via Voronoi is O(n³). Beyond this size, fall back to
  // convex hull so the call doesn't hang the CLI.
  if n > 500 {
    return convex_hull(points)
  }
  // Get Delaunay triangulation via Voronoi dual.
  let tris = delaunay_triangulation(points)
  if tris.length() == 0 {
    return convex_hull(points)
  }
  let threshold = 1.0 / alpha
  // Count how many triangles share each edge. Boundary edges are shared
  // by exactly one triangle. Remove edges whose circumradius > threshold.
  // Work in (min_idx, max_idx) canonical form.
  let edge_count : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  let edge_radius : @hashmap.HashMap[String, Double] = @hashmap.HashMap([])
  for t in tris {
    let (_, r) = circumcircle(points[t.a], points[t.b], points[t.c])
    add_edge_radius(edge_count, edge_radius, t.a, t.b, r)
    add_edge_radius(edge_count, edge_radius, t.b, t.c, r)
    add_edge_radius(edge_count, edge_radius, t.c, t.a, r)
  }
  // Collect boundary edges (count == 1) whose radius <= threshold.
  let boundary_edges : Array[(Int, Int)] = []
  for (key, cnt) in edge_count {
    let r = match edge_radius.get(key) {
      Some(v) => v
      None => 1.0e308
    }
    if cnt == 1 && r <= threshold {
      let parts = key.split(",").collect()
      let a = @string.parse_int(parts[0]) catch { _ => -1 }
      let b = @string.parse_int(parts[1]) catch { _ => -1 }
      if a >= 0 && b >= 0 {
        boundary_edges.push((a, b))
      }
    }
  }
  if boundary_edges.length() == 0 {
    return convex_hull(points)
  }
  // Build adjacency list for boundary walk.
  let adj : @hashmap.HashMap[Int, Array[Int]] = @hashmap.HashMap([])
  for (a, b) in boundary_edges {
    match adj.get(a) {
      None => adj[a] = [b]
      Some(arr) => arr.push(b)
    }
    match adj.get(b) {
      None => adj[b] = [a]
      Some(arr) => arr.push(a)
    }
  }
  // Walk the boundary starting from the vertex with smallest lng (then lat).
  let mut start = boundary_edges[0].0
  let mut min_lng = points[start].lng
  let mut i = 0
  while i < boundary_edges.length() {
    let (a, b) = boundary_edges[i]
    if points[a].lng < min_lng ||
      (points[a].lng == min_lng && points[a].lat < points[start].lat) {
      start = a
      min_lng = points[a].lng
    }
    if points[b].lng < min_lng ||
      (points[b].lng == min_lng && points[b].lat < points[start].lat) {
      start = b
      min_lng = points[b].lng
    }
    i = i + 1
  }
  let path : Array[Int] = [start]
  let mut prev = -1
  let mut curr = start
  let mut safety = 0
  while safety < n * 3 {
    let nexts = match adj.get(curr) {
      None => break
      Some(arr) => arr
    }
    let mut next = -1
    for nb in nexts {
      if nb != prev {
        next = nb
        break
      }
    }
    if next < 0 {
      // Try back edge (prev could still have another neighbor).
      for nb in nexts {
        if nb != curr {
          next = nb
          break
        }
      }
    }
    if next < 0 || next == start {
      break
    }
    path.push(next)
    prev = curr
    curr = next
    safety = safety + 1
  }
  if path.length() < 3 {
    return convex_hull(points)
  }
  // Convert indices → points, remove consecutive duplicates.
  let result : Array[@types.GeoPoint] = []
  for idx in path {
    let p = points[idx]
    if result.length() == 0 {
      result.push(p)
    } else {
      let last = result[result.length() - 1]
      if last.lat != p.lat || last.lng != p.lng {
        result.push(p)
      }
    }
  }
  result
}

///| Helper: record an edge's circumradius. Uses canonical (min, max) key.
fn add_edge_radius(
  count : @hashmap.HashMap[String, Int],
  radius : @hashmap.HashMap[String, Double],
  a : Int,
  b : Int,
  r : Double,
) -> Unit {
  let (lo, hi) = if a < b { (a, b) } else { (b, a) }
  let key = "\{lo},\{hi}"
  match count.get(key) {
    None => {
      count[key] = 1
      radius[key] = r
    }
    Some(c) => count[key] = c + 1
  }
}
// ---- Buffer analysis ----

///|
/// Destination point from an origin, initial bearing (degrees clockwise from
/// north), and distance in km. Uses the spherical-law-of-cosines exact
/// forward-geodesy formula; accurate for Earth-scale distances.
pub fn destination_point(
  origin : @types.GeoPoint,
  bearing_deg : Double,
  distance_km : Double,
) -> @types.GeoPoint {
  let phi1 = to_rad(origin.lat)
  let lambda1 = to_rad(origin.lng)
  let theta = to_rad(bearing_deg)
  let delta = distance_km / earth_radius_km // angular distance (radians)
  let sin_phi1 = @math.sin(phi1)
  let cos_phi1 = @math.cos(phi1)
  let sin_delta = @math.sin(delta)
  let cos_delta = @math.cos(delta)
  let sin_phi2 = sin_phi1 * cos_delta + cos_phi1 * sin_delta * @math.cos(theta)
  let phi2 = @math.asin(if sin_phi2 > 1.0 { 1.0 } else if sin_phi2 < -1.0 { -1.0 } else { sin_phi2 })
  let y = @math.sin(theta) * sin_delta * cos_phi1
  let x = cos_delta - sin_phi1 * @math.sin(phi2)
  let lambda2 = lambda1 + @math.atan2(y, x)
  // Normalize longitude to [-180, 180].
  let lng = to_deg(lambda2)
  let lng_norm = ((lng + 540.0) % 360.0) - 180.0
  @types.GeoPoint::make(to_deg(phi2), lng_norm)
}

///|
/// Compute a circular buffer polygon around a point. Approximates the circle
/// as a regular polygon with `segments` vertices (default 32). The result is
/// a closed ring (first point == last point).
pub fn buffer_point(
  center : @types.GeoPoint,
  radius_km : Double,
  segments? : Int = 32,
) -> Array[@types.GeoPoint] {
  let n = if segments < 3 { 3 } else { segments }
  let out : Array[@types.GeoPoint] = []
  let mut i = 0
  while i < n {
    let bearing = 360.0 * i.to_double() / n.to_double()
    out.push(destination_point(center, bearing, radius_km))
    i = i + 1
  }
  out.push(out[0])
  out
}

///|
/// Compute the buffer polygon around a polyline/polygon (ordered vertex
/// list). For each vertex, a circular cap of `radius_km` is generated; the
/// union's convex hull is returned. This is a round-cap buffer approximation
/// that is exact for convex inputs and generous for concave ones.
pub fn buffer_polygon(
  polygon : Array[@types.GeoPoint],
  radius_km : Double,
  segments? : Int = 16,
) -> Array[@types.GeoPoint] {
  let n = polygon.length()
  if n == 0 {
    return []
  }
  if n == 1 {
    return buffer_point(polygon[0], radius_km, segments~)
  }
  // Collect every vertex's cap as sample points, then take the convex hull.
  let samples : Array[@types.GeoPoint] = []
  let mut i = 0
  while i < n {
    let cap = buffer_point(polygon[i], radius_km, segments~)
    let mut j = 0
    while j < cap.length() - 1 {
      samples.push(cap[j])
      j = j + 1
    }
    i = i + 1
  }
  convex_hull(samples)
}
