// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

/// Earth's mean radius in kilometers (WGS84).
pub let earth_radius_km : Double = 6371.0088

///| Convert degrees to radians.
pub fn to_rad(deg : Double) -> Double {
  deg * 3.14159265358979323846 / 180.0
}

///| Convert radians to degrees.
pub fn to_deg(rad : Double) -> Double {
  rad * 180.0 / 3.14159265358979323846
}

///| Square helper.
fn sq(x : Double) -> Double {
  x * x
}

///| Square root via math.pow (no direct sqrt in core).
pub fn sqrt(x : Double) -> Double {
  @math.pow(x, 0.5)
}

///| Great-circle distance between two points (Haversine), in kilometers.
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

///| Initial bearing from p1 to p2 in degrees [0, 360).
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

///| Test whether a point lies inside an axis-aligned bbox.
pub fn bbox_contains(b : @types.BBox, p : @types.GeoPoint) -> Bool {
  p.lat >= b.min_lat &&
  p.lat <= b.max_lat &&
  p.lng >= b.min_lng &&
  p.lng <= b.max_lng
}

///| Approximate bbox centered at `center` covering a circle of `radius_km`.
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

///| Intersect two bboxes; returns None if they don't overlap.
pub fn bbox_intersect(
  a : @types.BBox,
  b : @types.BBox
) -> @types.BBox? {
  let min_lat = @cmp.maximum(a.min_lat, b.min_lat)
  let max_lat = @cmp.minimum(a.max_lat, b.max_lat)
  let min_lng = @cmp.maximum(a.min_lng, b.min_lng)
  let max_lng = @cmp.minimum(a.max_lng, b.max_lng)
  if min_lat > max_lat || min_lng > max_lng {
    None
  } else {
    Some({ min_lat, max_lat, min_lng, max_lng })
  }
}

// ---- Geohash encoding / decoding ----

/// Geohash base32 characters.
let geohash_chars : String = "0123456789bcdefghjkmnpqrstuvwxyz"

let geohash_char_array : Array[String] = [
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
  "b", "c", "d", "e", "f", "g", "h", "j", "k", "m",
  "n", "p", "q", "r", "s", "t", "u", "v", "w", "x",
  "y", "z",
]

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

///| Encode a (lat, lng) pair into a Geohash string of given precision.
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

fn geohash_char_at(n : Int) -> String {
  let i = n % 32
  geohash_char_array[i]
}

///| Decode a Geohash string back to a (lat, lng) pair.
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

///| Convert WGS84 coordinates to GCJ-02 (Mars coordinates).
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
  let dlat_final = (dlat * 180.0) / (6378245.0 * (1.0 - 0.00669342162296594323))
  let dlng_final = (dlng * 180.0) / (6378245.0 * magic * @math.cos(radlat))
  (lng + dlng_final, lat + dlat_final)
}

///| Convert GCJ-02 coordinates back to WGS84.
pub fn gcj02_to_wgs84(lng : Double, lat : Double) -> (Double, Double) {
  let (glng, glat) = wgs84_to_gcj02(lng, lat)
  (lng * 2.0 - glng, lat * 2.0 - glat)
}

fn in_china(lng : Double, lat : Double) -> Bool {
  lng > 73.66 && lng < 135.05 && lat > 3.86 && lat < 53.55
}

fn transform_lat(x : Double, y : Double) -> Double {
  let abs_x = if x < 0.0 { -x } else { x }
  let mut ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y +
    0.2 * sqrt(abs_x)
  ret = ret + (20.0 * @math.sin(6.0 * x * 3.14159265358979323846) +
    20.0 * @math.sin(2.0 * x * 3.14159265358979323846)) * 2.0 / 3.0
  ret = ret + (20.0 * @math.sin(y * 3.14159265358979323846) +
    40.0 * @math.sin(y / 3.0 * 3.14159265358979323846)) * 2.0 / 3.0
  ret = ret + (160.0 * @math.sin(y / 12.0 * 3.14159265358979323846) +
    320 * @math.sin(y * 3.14159265358979323846 / 30.0)) * 2.0 / 3.0
  ret
}

fn transform_lng(x : Double, y : Double) -> Double {
  let abs_x = if x < 0.0 { -x } else { x }
  let mut ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y +
    0.1 * sqrt(abs_x)
  ret = ret + (20.0 * @math.sin(6.0 * x * 3.14159265358979323846) +
    20.0 * @math.sin(2.0 * x * 3.14159265358979323846)) * 2.0 / 3.0
  ret = ret + (20.0 * @math.sin(x * 3.14159265358979323846) +
    40.0 * @math.sin(x / 3.0 * 3.14159265358979323846)) * 2.0 / 3.0
  ret = ret + (150.0 * @math.sin(x / 12.0 * 3.14159265358979323846) +
    300.0 * @math.sin(x / 30.0 * 3.14159265358979323846)) * 2.0 / 3.0
  ret
}

// ---- Convex Hull (Andrew's monotone chain) ----

///| Compute the convex hull of a set of GeoPoints.
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

fn cross_product(o : @types.GeoPoint, a : @types.GeoPoint, b : @types.GeoPoint) -> Double {
  (a.lat - o.lat) * (b.lng - o.lng) - (a.lng - o.lng) * (b.lat - o.lat)
}

fn sort_points_by_lat(points : Array[@types.GeoPoint]) -> Array[@types.GeoPoint] {
  let result = points
  result.sort_by(fn(a, b) {
    if a.lat < b.lat { -1 }
    else if a.lat > b.lat { 1 }
    else {
      if a.lng < b.lng { -1 }
      else if a.lng > b.lng { 1 }
      else { 0 }
    }
  })
  result
}

fn remove_duplicate_points(points : Array[@types.GeoPoint]) -> Array[@types.GeoPoint] {
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

///| Compute the area of a polygon defined by an ordered list of GeoPoints.
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

///| Test whether a point lies inside a polygon (ray casting algorithm).
/// Returns `true` if the point is strictly inside the polygon.
pub fn point_in_polygon(point : @types.GeoPoint, polygon : Array[@types.GeoPoint]) -> Bool {
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
    let intersect = ((pi.lat > point.lat) != (pj.lat > point.lat)) &&
      (point.lng < (pj.lng - pi.lng) * (point.lat - pi.lat) / (pj.lat - pi.lat) + pi.lng)
    if intersect {
      inside = !inside
    }
    j = i
    i = i + 1
  }
  inside
}

///| Return the 9 geohash neighbors (3×3 grid) around a given geohash.
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
      let clamped_lat = if lat > 90.0 { 90.0 } else { if lat < -90.0 { -90.0 } else { lat } }
      let clamped_lng = if lng > 180.0 { 180.0 } else { if lng < -180.0 { -180.0 } else { lng } }
      results.push(geohash_encode(clamped_lat, clamped_lng, precision))
    }
  }
  results
}

///| Return the approximate cell size (lat_span, lng_span) for a geohash precision.
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

///| Convert a geohash string to its approximate bounding box.
pub fn geohash_to_bbox(hash : String) -> @types.BBox {
  if hash.length() == 0 {
    return @types.BBox::from_corners(
      @types.GeoPoint::make(-90.0, -180.0),
      @types.GeoPoint::make(90.0, 180.0)
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

///| Compute the average nearest-neighbor distance for a set of points.
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
  if count == 0 { 0.0 } else { total / (count.to_double()) }
}
