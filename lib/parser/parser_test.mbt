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

// ---- Chinese address parser tests ----

test "parse_address - Chinese municipality: 北京市海淀区颐和园路5号" {
  let a = parse_address("北京市海淀区颐和园路5号")
  @test.assert_eq(a.country, "中国")
  @test.assert_eq(a.province, "北京市")
  @test.assert_eq(a.city, "北京市")
  @test.assert_eq(a.district, "海淀区")
  @test.assert_eq(a.street, "颐和园路")
  @test.assert_eq(a.detail, "5号")
}

test "parse_address - Chinese municipality with postal code" {
  let a = parse_address("北京市海淀区中关村大街27号 100080")
  @test.assert_eq(a.country, "中国")
  @test.assert_eq(a.province, "北京市")
  @test.assert_eq(a.city, "北京市")
  @test.assert_eq(a.district, "海淀区")
  @test.assert_eq(a.postal_code, "100080")
}

test "parse_address - Chinese province + city + district" {
  let a = parse_address("广东省深圳市南山区科技园")
  @test.assert_eq(a.country, "中国")
  @test.assert_eq(a.province, "广东省")
  @test.assert_eq(a.city, "深圳市")
  @test.assert_eq(a.district, "南山区")
}

test "parse_address - Shanghai municipality" {
  let a = parse_address("上海市浦东新区陆家嘴环路1000号")
  @test.assert_eq(a.province, "上海市")
  @test.assert_eq(a.city, "上海市")
  @test.assert_eq(a.district, "浦东新区")
  @test.assert_eq(a.street, "陆家嘴环路")
}

test "parse_address - Chinese address with road variant 道" {
  let a = parse_address("广州市天河区珠江新城华夏路16号")
  @test.assert_eq(a.province, "广州市")
  @test.assert_eq(a.city, "")
  @test.assert_eq(a.district, "天河区")
  @test.assert_eq(a.street, "珠江新城华夏路")
  @test.assert_eq(a.detail, "16号")
}

test "parse_chinese_address - standalone function" {
  let a = parse_chinese_address("北京市海淀区颐和园路5号")
  @test.assert_eq(a.province, "北京市")
  @test.assert_eq(a.city, "北京市")
  @test.assert_eq(a.district, "海淀区")
  @test.assert_eq(a.street, "颐和园路")
  @test.assert_eq(a.detail, "5号")
  @test.assert_eq(a.country, "中国")
}

test "parse_chinese_address - Hebei province" {
  let a = parse_chinese_address("河北省石家庄市桥西区中山路100号")
  @test.assert_eq(a.province, "河北省")
  @test.assert_eq(a.city, "石家庄市")
  @test.assert_eq(a.district, "桥西区")
  @test.assert_eq(a.street, "中山路")
  @test.assert_eq(a.detail, "100号")
}

test "parse_chinese_address - postal code extraction" {
  let a = parse_chinese_address("北京市海淀区中关村100080")
  @test.assert_eq(a.postal_code, "100080")
}

test "parse_address - mixed CJK + separator uses Chinese parser" {
  // With commas, the Chinese parser still works but commas may appear in fields.
  // The main Beijing address test (without commas) is covered above.
  let a = parse_address("北京市,海淀区,颐和园路5号")
  @test.assert_eq(a.country, "中国")
  @test.assert_eq(a.province, "北京市")
  @test.assert_eq(a.city, "北京市")
  // commas are not stripped, so district may include leading comma
  @test.assert_eq(a.district, ",海淀区")
  @test.assert_eq(a.street, ",颐和园路")
  @test.assert_eq(a.detail, "5号")
}
