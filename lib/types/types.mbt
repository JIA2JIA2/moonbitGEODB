// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

/// Geographic point in WGS84 (lat, lng in decimal degrees).
pub(all) struct GeoPoint {
  lat : Double // [-90, 90]
  lng : Double // [-180, 180]
} derive(Eq, Debug, ToJson, FromJson)

/// Axis-aligned geographic bounding box.
pub(all) struct BBox {
  min_lat : Double
  max_lat : Double
  min_lng : Double
  max_lng : Double
} derive(Eq, Debug, ToJson, FromJson)

/// Structured postal address. Empty string means "unspecified".
pub(all) struct Address {
  country : String // 国家 / Country
  province : String // 省 / 州 / Province or State
  city : String // 市 / City
  district : String // 区 / 县 / District or County
  street : String // 街道 / 门牌 / Street & house number
  postal_code : String // 邮政编码 / Postal / ZIP code
  detail : String // 补充说明 / Extra detail
} derive(Eq, Debug, ToJson, FromJson)

/// A stored geo record.
pub(all) struct GeoEntry {
  id : String
  name : String
  address : Address
  location : GeoPoint
  mut tags : Array[String]
} derive(Eq, Debug, ToJson, FromJson)

///| Construct a GeoPoint.
pub fn GeoPoint::make(lat : Double, lng : Double) -> GeoPoint {
  { lat, lng }
}

///| Construct an empty Address (all fields blank).
pub fn Address::empty() -> Address {
  {
    country: "",
    province: "",
    city: "",
    district: "",
    street: "",
    postal_code: "",
    detail: "",
  }
}

///| Build a one-line human-readable address string.
pub fn Address::to_line(self : Address) -> String {
  let parts = [
    self.country,
    self.province,
    self.city,
    self.district,
    self.street,
    self.detail,
  ]
  parts
    .iter()
    .filter(fn(s) { s.length() > 0 })
    .collect()
    .join(",")
}

///| Construct a GeoEntry with empty tags.
pub fn GeoEntry::make(
  id : String,
  name : String,
  address : Address,
  location : GeoPoint
) -> GeoEntry {
  { id, name, address, location, tags: [] }
}

///| Build a BBox from two opposite corners.
pub fn BBox::from_corners(a : GeoPoint, b : GeoPoint) -> BBox {
  {
    min_lat: if a.lat <= b.lat { a.lat } else { b.lat },
    max_lat: if a.lat <= b.lat { b.lat } else { a.lat },
    min_lng: if a.lng <= b.lng { a.lng } else { b.lng },
    max_lng: if a.lng <= b.lng { b.lng } else { a.lng },
  }
}
