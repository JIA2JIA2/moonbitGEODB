// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

test "parse_coordinate - basic comma form" {
  let p = parse_coordinate("39.9,116.4")
  @test.assert_eq(p.lat, 39.9)
  @test.assert_eq(p.lng, 116.4)
}

test "parse_coordinate - semicolon separator" {
  let p = parse_coordinate("39.9; 116.4")
  @test.assert_eq(p.lat, 39.9)
  @test.assert_eq(p.lng, 116.4)
}

test "parse_coordinate - whitespace separator" {
  let p = parse_coordinate("39.9 116.4")
  @test.assert_eq(p.lat, 39.9)
  @test.assert_eq(p.lng, 116.4)
}

test "parse_coordinate - negative values" {
  let p = parse_coordinate("-33.8688, 151.2093")
  @test.assert_eq(p.lat, -33.8688)
  @test.assert_eq(p.lng, 151.2093)
}

test "parse_coordinate - empty input raises" {
  let raised = try {
    ignore(parse_coordinate("   "))
    false
  } catch {
    _ => true
  }
  @test.assert_eq(raised, true)
}

test "parse_coordinate - out-of-range lat raises" {
  let raised = try {
    ignore(parse_coordinate("91.0, 0.0"))
    false
  } catch {
    _ => true
  }
  @test.assert_eq(raised, true)
}

test "parse_coordinate - no separator raises" {
  let raised = try {
    ignore(parse_coordinate("39.9"))
    false
  } catch {
    _ => true
  }
  @test.assert_eq(raised, true)
}

test "parse_address - comma with postal code" {
  let a = parse_address("China,Beijing,Beijing,Haidian,Zhongguancun,100080")
  @test.assert_eq(a.country, "China")
  @test.assert_eq(a.province, "Beijing")
  @test.assert_eq(a.city, "Beijing")
  @test.assert_eq(a.district, "Haidian")
  @test.assert_eq(a.street, "Zhongguancun")
  @test.assert_eq(a.postal_code, "100080")
}

test "parse_address - slash separator" {
  let a = parse_address("China / USA / California / San Francisco / Mission St / 94103")
  @test.assert_eq(a.country, "China")
  @test.assert_eq(a.province, "USA")
  @test.assert_eq(a.city, "California")
  @test.assert_eq(a.postal_code, "94103")
}

test "parse_address - semicolon separator" {
  let a = parse_address("Beijing; Haidian; Zhongguancun")
  @test.assert_eq(a.country, "Beijing")
  @test.assert_eq(a.province, "Haidian")
  @test.assert_eq(a.city, "Zhongguancun")
  @test.assert_eq(a.postal_code, "")
}

test "parse_address - empty input raises" {
  let raised = try {
    ignore(parse_address(""))
    false
  } catch {
    _ => true
  }
  @test.assert_eq(raised, true)
}

test "parse_address - no separator raises" {
  let raised = try {
    ignore(parse_address("SingleToken"))
    false
  } catch {
    _ => true
  }
  @test.assert_eq(raised, true)
}

test "parse_record_line - full 3-field line" {
  let e = parse_record_line("Tiananmen\t39.9087, 116.3975\tChina,Beijing,Beijing,Dongcheng,Tiananmen,100009")
  @test.assert_eq(e.name, "Tiananmen")
  @test.assert_eq(e.location.lat, 39.9087)
  @test.assert_eq(e.location.lng, 116.3975)
  @test.assert_eq(e.address.country, "China")
  @test.assert_eq(e.address.city, "Beijing")
  @test.assert_eq(e.address.postal_code, "100009")
}

test "parse_record_line - 2-field line (name + coordinate)" {
  let e = parse_record_line("Eiffel Tower\t48.8584, 2.2945")
  @test.assert_eq(e.name, "Eiffel Tower")
  @test.assert_eq(e.location.lat, 48.8584)
  @test.assert_eq(e.location.lng, 2.2945)
}

test "parse_record_line - single field (name only)" {
  let e = parse_record_line("JustAName")
  @test.assert_eq(e.name, "JustAName")
  @test.assert_eq(e.location.lat, 0.0)
  @test.assert_eq(e.location.lng, 0.0)
}

test "parse_record_line - empty line raises" {
  let raised = try {
    ignore(parse_record_line(""))
    false
  } catch {
    _ => true
  }
  @test.assert_eq(raised, true)
}
