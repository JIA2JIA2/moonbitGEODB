// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

/// Errors raised by the address / coordinate parser.
pub(all) suberror ParseError {
  EmptyInput
  NoSeparatorFound(String)
  BadCoordinate(String)
} derive(Eq, Debug, ToJson, FromJson)

///| Human-readable representation of a parse error.
pub impl Show for ParseError with fn output(self, logger) {
  match self {
    EmptyInput => logger.write_string("EmptyInput")
    NoSeparatorFound(s) =>
      logger <+
        $|NoSeparatorFound(\{s.escape()})
    BadCoordinate(s) =>
      logger <+
        $|BadCoordinate(\{s.escape()})
  }
}

///| A parsed address field layout: which input segment goes to which field.
priv struct FieldAssign {
  mut country : String
  mut province : String
  mut city : String
  mut district : String
  mut street : String
  postal_code : String
  mut detail : String
}

///| Detect the most likely separator in the input string.
/// Tries comma, slash, semicolon, then " > ". Returns the first one that
/// splits the string into >= 2 non-empty segments.
fn detect_separator(input : String) -> String? {
  let candidates = [",", "/", ";", ">", "|", " "]
  for sep in candidates {
    let count = input.split(sep).filter(fn(s) { s.trim().length() > 0 }).count()
    if count >= 2 {
      return Some(sep)
    }
  }
  None
}

///| Check whether a string looks like a postal/ZIP code:
/// all ASCII digits, length 3..=10.
fn looks_like_postal(s : String) -> Bool {
  let n = s.length()
  if n < 3 || n > 10 {
    return false
  }
  s.all(fn(c) { c.is_digit(10) })
}

///| Strip surrounding whitespace and quotes; returns an owned String.
fn clean(s : StringView) -> String {
  let t = s.trim().to_owned()
  let n = t.length()
  if n >= 2 {
    let first = t.get_char(0).unwrap()
    let last = t.get_char(n - 1).unwrap()
    if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
      return t.get_view(start=1, end=n - 1).unwrap().to_owned()
    }
  }
  t
}

///| Assign raw segments to Address fields.
/// Strategy: detect postal code if any segment looks like one;
/// the rest are mapped in order to country, province, city, district, street, detail.
fn assign_fields(segments : Array[String]) -> FieldAssign {
  let mut postal = ""
  let rest : Array[String] = []
  for s in segments {
    if postal.length() == 0 && looks_like_postal(s) {
      postal = s
    } else if s.length() > 0 {
      rest.push(s)
    }
  }
  let order = ["country", "province", "city", "district", "street", "detail"]
  let fa : FieldAssign = {
    country: "",
    province: "",
    city: "",
    district: "",
    street: "",
    postal_code: postal,
    detail: "",
  }
  let mut i = 0
  for s in rest {
    if i >= order.length() {
      // Overflow: append to detail, comma-separated.
      if fa.detail.length() == 0 {
        fa.detail = s
      } else {
        fa.detail = fa.detail + "," + s
      }
    } else {
      match order[i] {
        "country" => fa.country = s
        "province" => fa.province = s
        "city" => fa.city = s
        "district" => fa.district = s
        "street" => fa.street = s
        "detail" => fa.detail = s
        _ => ()
      }
      i = i + 1
    }
  }
  fa
}

///| Check if a character is in the CJK Unified Ideographs range.
fn is_cjk(c : Char) -> Bool {
  let code = c.to_int()
  code >= 0x4E00 && code <= 0x9FFF
}

///| Check whether the string contains at least one CJK character.
fn has_chinese(text : String) -> Bool {
  text.any(fn(c) { is_cjk(c) })
}

///| Find the end index (exclusive) of the province-level segment.
/// Matches suffixes: 省, 市 (直辖市), 自治区, 特别行政区, 特区.
/// Returns None if no province-level suffix is found.
fn find_province_end(text : String) -> Int? {
  let n = text.length()
  // Known province-level suffixes (checked in order of length, longest first).
  let suffixes = ["特别行政区", "自治区", "省", "市", "特区"]
  for s in suffixes {
    let slen = s.length()
    // Search from left to right for the first occurrence of this suffix.
    let mut i = 0
    while i <= n - slen {
      let sub = text.get_view(start=i, end=i + slen).unwrap()
      if sub.to_string() == s {
        // Must have at least one CJK char before the suffix (not just "市").
        if i > 0 {
          return Some(i + slen)
        }
      }
      i = i + 1
    }
  }
  None
}

///| Find the end index (exclusive) of the city-level segment.
/// Matches suffixes: 市, 州, 盟, 地区.
fn find_city_end(text : String, start : Int) -> Int? {
  let n = text.length()
  let suffixes = ["地区", "市", "州", "盟"]
  for s in suffixes {
    let slen = s.length()
    let mut i = start
    while i <= n - slen {
      let sub = text.get_view(start=i, end=i + slen).unwrap()
      if sub.to_string() == s {
        return Some(i + slen)
      }
      i = i + 1
    }
  }
  None
}

///| Find the end index (exclusive) of the district-level segment.
/// Matches suffixes: 区, 县, 市, 旗.
fn find_district_end(text : String, start : Int) -> Int? {
  let n = text.length()
  let suffixes = ["区", "县", "市", "旗"]
  for s in suffixes {
    let slen = s.length()
    let mut i = start
    while i <= n - slen {
      let sub = text.get_view(start=i, end=i + slen).unwrap()
      if sub.to_string() == s {
        return Some(i + slen)
      }
      i = i + 1
    }
  }
  None
}

///| Find the end index (exclusive) of the street-level segment.
/// Matches suffixes: 路, 街, 道, 巷, 弄, 街, 线.
fn find_street_end(text : String, start : Int) -> Int? {
  let n = text.length()
  let suffixes = ["路", "街", "道", "巷", "弄", "线"]
  for s in suffixes {
    let slen = s.length()
    let mut i = start
    while i <= n - slen {
      let sub = text.get_view(start=i, end=i + slen).unwrap()
      if sub.to_string() == s {
        return Some(i + slen)
      }
      i = i + 1
    }
  }
  None
}

///| Parse a Chinese address without explicit separators.
/// Handles addresses like "北京市海淀区颐和园路5号" by recognizing
/// administrative division and street suffixes.
///
/// Hierarchy: province → city → district → street → detail
/// Special case: municipalities (北京市, 上海市, etc.) where 市
/// serves as both province and city.
pub fn parse_chinese_address(input : String) -> @types.Address {
  let trimmed = input.trim().to_owned()
  let n = trimmed.length()

  let mut province = ""
  let mut city = ""
  let mut district = ""
  let mut street = ""
  let mut detail = ""
  let mut postal = ""

  // ---- 1. Province-level ----
  let (prov_end, is_municipality) = match find_province_end(trimmed) {
    Some(idx) => {
      let prov_text = trimmed.get_view(end=idx).unwrap().to_owned()
      // Check if this is a municipality (直辖市): the suffix is just 市
      // and it's a well-known municipality.
      let municipalities = ["北京市", "上海市", "天津市", "重庆市"]
      let is_muni = municipalities.contains(prov_text)
      (Some(idx), is_muni)
    }
    None => (None, false)
  }

  let mut cursor = 0
  match prov_end {
    Some(idx) => {
      province = trimmed.get_view(end=idx).unwrap().to_owned()
      cursor = idx
    }
    None => ()
  }

  // ---- 2. City-level ----
  if is_municipality {
    // For municipalities, the province name already contains the city info.
    // e.g. "北京市" = province+city
    city = province
  } else {
    match find_city_end(trimmed, cursor) {
      Some(idx) => {
        city = trimmed.get_view(start=cursor, end=idx).unwrap().to_owned()
        cursor = idx
      }
      None => ()
    }
  }

  // ---- 3. District-level ----
  match find_district_end(trimmed, cursor) {
    Some(idx) => {
      district = trimmed.get_view(start=cursor, end=idx).unwrap().to_owned()
      cursor = idx
    }
    None => ()
  }

  // ---- 4. Street-level ----
  match find_street_end(trimmed, cursor) {
    Some(idx) => {
      street = trimmed.get_view(start=cursor, end=idx).unwrap().to_owned()
      cursor = idx
    }
    None => ()
  }

  // ---- 5. Remaining goes to detail ----
  if cursor < n {
    detail = trimmed.get_view(start=cursor).unwrap().to_owned()
  }

  // ---- 6. Detect postal code in detail or anywhere ----
  // Check if detail contains a postal code pattern.
  if detail.length() > 0 {
    // Try to find a 6-digit postal code in the detail.
    let mut i = 0
    while i <= detail.length() - 6 {
      let sub = detail.get_view(start=i, end=i + 6).unwrap()
      if sub.all(fn(c) { c.is_digit(10) }) {
        postal = sub.to_owned()
        // Remove postal code from detail.
        let before = if i == 0 { "" } else { detail.get_view(end=i).unwrap().to_owned() }
        let after = if i + 6 >= detail.length() {
          ""
        } else {
          detail.get_view(start=i + 6).unwrap().to_owned()
        }
        detail = before + after
        break
      }
      i = i + 1
    }
  }

  // Detect postal code in the full input as well (just in case).
  if postal.length() == 0 {
    let mut i = 0
    while i <= trimmed.length() - 6 {
      let sub = trimmed.get_view(start=i, end=i + 6).unwrap()
      if sub.all(fn(c) { c.is_digit(10) }) {
        postal = sub.to_owned()
        break
      }
      i = i + 1
    }
  }

  @types.Address::{
    country: "中国",
    province,
    city,
    district,
    street,
    postal_code: postal,
    detail,
  }
}

///| Parse a free-form address string into a structured `Address`.
///
/// Supported formats (auto-detected):
///   "中国,北京,北京,海淀区,中关村大街,100080"
///   "China / USA / California / San Francisco / Mission St / 94103"
///   "Beijing; Haidian; Zhongguancun"
///   "上海市|浦东新区|张江路|201203"
///   "北京市海淀区颐和园路5号"  (Chinese address without separators)
///
/// Field mapping order: country, province, city, district, street, detail.
/// A segment of pure digits (length 3..=10) is treated as the postal code.
pub fn parse_address(input : String) -> @types.Address raise ParseError {
  let trimmed = input.trim().to_owned()
  if trimmed.is_empty() {
    raise EmptyInput
  }
  match detect_separator(trimmed) {
    None => {
      // No separator found: try Chinese address parser if input contains CJK.
      if has_chinese(trimmed) {
        parse_chinese_address(trimmed)
      } else {
        raise NoSeparatorFound(trimmed)
      }
    }
    Some(sep) => {
      // If the input contains Chinese characters, prefer the Chinese parser
      // over a naive space-based split, which would mis-parse CJK addresses.
      if has_chinese(trimmed) {
        parse_chinese_address(trimmed)
      } else {
        let segments = []
        for s in trimmed.split(sep) {
          let c = clean(s)
          if c.length() > 0 {
            segments.push(c)
          }
        }
        if segments.length() == 0 {
          raise EmptyInput
        }
        let fa = assign_fields(segments)
        {
          country: fa.country,
          province: fa.province,
          city: fa.city,
          district: fa.district,
          street: fa.street,
          postal_code: fa.postal_code,
          detail: fa.detail,
        }
      }
    }
  }
}

///| Parse a "lat,lng" coordinate string into a `GeoPoint`.
/// Accepts comma, semicolon, or whitespace as separator.
/// Both components must parse as doubles; lat in [-90, 90], lng in [-180, 180].
pub fn parse_coordinate(input : String) -> @types.GeoPoint raise ParseError {
  let trimmed = input.trim().to_owned()
  if trimmed.is_empty() {
    raise EmptyInput
  }
  // Find separator: first of ',', ';', or whitespace.
  let sep_idx = trimmed.find_by(fn(c) { c == ',' || c == ';' || c == ' ' })
  match sep_idx {
    None => raise BadCoordinate(trimmed)
    Some(idx) => {
      let lat_str = trimmed.get_view(end=idx).unwrap().trim().to_owned()
      let lng_part = trimmed.get_view(start=idx + 1).unwrap()
      // lng may have leading whitespace; find where the number starts.
      let lng_trimmed = lng_part.trim().to_owned()
      // If there's a trailing whitespace+something (e.g. altitude), cut at first space.
      let lng_str = match lng_trimmed.find_by(fn(c) { c == ' ' || c == ',' }) {
        Some(end) => lng_trimmed.get_view(end=end).unwrap().to_owned()
        None => lng_trimmed
      }
      let lat = try @string.parse_double(lat_str) catch {
        _ => raise BadCoordinate(trimmed)
      }
      let lng = try @string.parse_double(lng_str) catch {
        _ => raise BadCoordinate(trimmed)
      }
      if lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0 {
        raise BadCoordinate(trimmed)
      }
      { lat, lng }
    }
  }
}

///| Parse a full record line of the form:
///   "<name>\t<lat>,<lng>\t<address>"
/// where <address> is any string accepted by `parse_address`.
/// Tab-separated; if no tabs present, the whole line is treated as the name
/// and address/location are empty.
pub fn parse_record_line(line : String) -> @types.GeoEntry raise ParseError {
  let trimmed = line.trim().to_owned()
  if trimmed.is_empty() {
    raise EmptyInput
  }
  let parts = trimmed.split("\t").collect()
  let name = if parts.length() >= 1 {
    clean(parts[0])
  } else {
    ""
  }
  let (location, address) = if parts.length() >= 3 {
    let loc = try parse_coordinate(clean(parts[1])) catch {
      _ => @types.GeoPoint::make(0.0, 0.0)
    }
    let addr = try parse_address(clean(parts[2])) catch {
      _ => @types.Address::empty()
    }
    (loc, addr)
  } else if parts.length() == 2 {
    // Try coordinate first; if that fails, treat as address.
    let second = clean(parts[1])
    let loc = try parse_coordinate(second) catch {
      _ => @types.GeoPoint::make(0.0, 0.0)
    }
    let addr = if loc.lat == 0.0 && loc.lng == 0.0 {
      try parse_address(second) catch { _ => @types.Address::empty() }
    } else {
      @types.Address::empty()
    }
    (loc, addr)
  } else {
    (@types.GeoPoint::make(0.0, 0.0), @types.Address::empty())
  }
  @types.GeoEntry::make(name, name, address, location)
}
