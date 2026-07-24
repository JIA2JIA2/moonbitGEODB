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
