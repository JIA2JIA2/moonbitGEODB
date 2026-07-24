// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

test "GeoPoint::make stores lat/lng" {
  let p = GeoPoint::make(39.9, 116.4)
  @test.assert_eq(p.lat, 39.9)
  @test.assert_eq(p.lng, 116.4)
}

test "Address::empty has all blank fields" {
  let a = Address::empty()
  @test.assert_eq(a.country, "")
  @test.assert_eq(a.province, "")
  @test.assert_eq(a.city, "")
  @test.assert_eq(a.district, "")
  @test.assert_eq(a.street, "")
  @test.assert_eq(a.postal_code, "")
  @test.assert_eq(a.detail, "")
}

test "Address::to_line joins non-empty parts with comma" {
  let a : Address = {
    country: "China",
    province: "Beijing",
    city: "",
    district: "Haidian",
    street: "",
    postal_code: "100080",
    detail: "",
  }
  @test.assert_eq(a.to_line(), "China,Beijing,Haidian")
}

test "Address::to_line on empty address returns empty string" {
  @test.assert_eq(Address::empty().to_line(), "")
}

test "GeoEntry::make has empty tags" {
  let p = GeoPoint::make(0.0, 0.0)
  let e = GeoEntry::make("id1", "name", Address::empty(), p)
  @test.assert_eq(e.id, "id1")
  @test.assert_eq(e.name, "name")
  @test.assert_eq(e.tags.length(), 0)
}

test "BBox::from_corners normalizes min/max" {
  let a = GeoPoint::make(40.0, 117.0)
  let b = GeoPoint::make(39.0, 116.0)
  let bbox = BBox::from_corners(a, b)
  @test.assert_eq(bbox.min_lat, 39.0)
  @test.assert_eq(bbox.max_lat, 40.0)
  @test.assert_eq(bbox.min_lng, 116.0)
  @test.assert_eq(bbox.max_lng, 117.0)
}

test "GeoPoint ToJson / FromJson round-trip" {
  let p = GeoPoint::make(1.5, -2.25)
  let ok = try {
    let q : GeoPoint = @json.from_json(p.to_json())
    q.lat == 1.5 && q.lng == -2.25
  } catch {
    _ => false
  }
  @test.assert_eq(ok, true)
}

test "Address ToJson / FromJson round-trip" {
  let a : Address = {
    country: "CN",
    province: "BJ",
    city: "Beijing",
    district: "HD",
    street: "ZGC",
    postal_code: "100080",
    detail: "extra",
  }
  let ok = try {
    let b : Address = @json.from_json(a.to_json())
    a == b
  } catch {
    _ => false
  }
  @test.assert_eq(ok, true)
}
