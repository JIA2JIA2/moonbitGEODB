// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Binary serialization for GeoEntry and database snapshots.
// Uses a custom binary format with length-prefixed strings and fixed-size
// numeric encoding (big-endian) for portability.

/// Magic bytes identifying an MGDB binary file ("MGDB").
const MAGIC : Bytes = [0x4D, 0x47, 0x44, 0x42]

/// Current binary format version.
pub let binary_version : Int = 1

/// Size of the file header in bytes.
const HEADER_SIZE : Int = 32

/// Encode a single GeoEntry to a binary record (with 4-byte size prefix).
pub fn encode_entry(entry : @types.GeoEntry) -> Bytes {
  let w = BinWriter::new()
  w.write_string(entry.id)
  w.write_string(entry.name)
  w.write_double(entry.location.lat)
  w.write_double(entry.location.lng)
  w.write_string(entry.address.country)
  w.write_string(entry.address.province)
  w.write_string(entry.address.city)
  w.write_string(entry.address.district)
  w.write_string(entry.address.street)
  w.write_string(entry.address.postal_code)
  w.write_string(entry.address.detail)
  w.write_uint16(entry.tags.length())
  for tag in entry.tags {
    w.write_string(tag)
  }
  let body = w.to_bytes()

  // Record = UInt32 size prefix + body
  let size_prefix = encode_int32(body.length() + 4)
  size_prefix + body
}

/// Decode a single GeoEntry from a binary record starting at offset.
/// Returns (entry, new_offset).
pub fn decode_entry(data : Bytes, offset : Int) -> (@types.GeoEntry, Int) {
  let r = BinReader::new(data)
  r.pos = offset

  // Read and skip the record size.
  let _record_size = r.read_int32()

  let id = r.read_string()
  let name = r.read_string()
  let lat = r.read_double()
  let lng = r.read_double()
  let country = r.read_string()
  let province = r.read_string()
  let city = r.read_string()
  let district = r.read_string()
  let street = r.read_string()
  let postal_code = r.read_string()
  let detail = r.read_string()
  let tag_count = r.read_uint16()
  let tags : Array[String] = []
  for _ in 0..<tag_count {
    tags.push(r.read_string())
  }

  let entry = @types.GeoEntry::make(
    id,
    name,
    {
      country,
      province,
      city,
      district,
      street,
      postal_code,
      detail,
    },
    @types.GeoPoint::make(lat, lng),
  )
  entry.tags = tags

  (entry, r.position())
}

/// Encode a full database snapshot (header + entries) to Bytes.
pub fn encode_snapshot(
  entries : Array[@types.GeoEntry],
  created_at : Int64,
  updated_at : Int64
) -> Bytes {
  let entry_writer = BinWriter::new()
  for entry in entries {
    let encoded = encode_entry(entry)
    entry_writer.buf = entry_writer.buf + encoded
  }
  let entry_data = entry_writer.to_bytes()

  // Compute CRC32 of all entry data.
  let checksum = crc32(entry_data)

  // Build header.
  let header_w = BinWriter::new()
  header_w.buf = header_w.buf + MAGIC
  header_w.write_uint16(binary_version)
  header_w.write_uint16(0) // flags (reserved)
  header_w.write_int32(entries.length())
  header_w.write_int64(created_at)
  header_w.write_int64(updated_at)
  header_w.write_int32(checksum)
  let header = header_w.to_bytes()

  header + entry_data
}

/// Decode a full database snapshot from Bytes.
/// Returns (entries, created_at, updated_at) or an error message.
pub fn decode_snapshot(data : Bytes) -> Result[(Array[@types.GeoEntry], Int64, Int64), String] {
  if data.length() < HEADER_SIZE {
    return Err("file too small: expected at least \{HEADER_SIZE} bytes, got \{data.length()}")
  }

  // Verify magic.
  let magic = bytes_slice(data, 0, 4)
  if !bytes_eq(magic, MAGIC) {
    return Err("invalid magic bytes: not an MGDB binary file")
  }

  let r = BinReader::new(data)
  r.pos = 4 // skip magic

  let version = r.read_uint16()
  if version != binary_version {
    return Err("unsupported binary version: expected \{binary_version}, got \{version}")
  }

  let _flags = r.read_uint16()
  let entry_count = r.read_int32()
  let created_at = r.read_int64()
  let updated_at = r.read_int64()
  let stored_checksum = r.read_int32()

  // Verify checksum over remaining data.
  let entry_data_start = r.position()
  let entry_data = bytes_slice(data, entry_data_start, data.length())
  let computed_checksum = crc32(entry_data)
  if stored_checksum != computed_checksum {
    return Err("checksum mismatch: file may be corrupted")
  }

  // Decode entries.
  let entries : Array[@types.GeoEntry] = []
  let mut pos = entry_data_start
  for _ in 0..<entry_count {
    let (entry, new_pos) = decode_entry(data, pos)
    entries.push(entry)
    pos = new_pos
  }

  Ok((entries, created_at, updated_at))
}

/// Extract just the metadata from a binary file without decoding all entries.
pub fn decode_meta(data : Bytes) -> Result[(Int, Int64, Int64, Int), String] {
  if data.length() < HEADER_SIZE {
    return Err("file too small for header")
  }

  let magic = bytes_slice(data, 0, 4)
  if !bytes_eq(magic, MAGIC) {
    return Err("invalid magic bytes")
  }

  let r = BinReader::new(data)
  r.pos = 4
  let version = r.read_uint16()
  let _flags = r.read_uint16()
  let entry_count = r.read_int32()
  let created_at = r.read_int64()
  let updated_at = r.read_int64()
  let _checksum = r.read_int32()

  Ok((version, created_at, updated_at, entry_count))
}

/// Validate the binary file structure (magic + version + checksum).
pub fn validate_file(data : Bytes) -> Result[Unit, String] {
  match decode_meta(data) {
    Err(e) => Err(e)
    Ok((version, _, _, _)) => {
      if version != binary_version {
        return Err("version mismatch: expected \{binary_version}, got \{version}")
      }
      match decode_snapshot(data) {
        Err(e) => Err("checksum validation failed: \{e}")
        Ok(_) => Ok(())
      }
    }
  }
}

// ---- tests ----

test "encode/decode GeoEntry roundtrip" {
  let entry = @types.GeoEntry::make(
    "test-001",
    "颐和园",
    {
      country: "中国",
      province: "北京市",
      city: "北京市",
      district: "海淀区",
      street: "颐和园路5号",
      postal_code: "100091",
      detail: "",
    },
    @types.GeoPoint::make(39.9999, 116.2755),
  )
  entry.tags = ["poi", "landmark"]

  let encoded = encode_entry(entry)
  let (decoded, new_pos) = decode_entry(encoded, 0)

  @test.assert_eq(decoded.id, "test-001")
  @test.assert_eq(decoded.name, "颐和园")
  @test.assert_eq(decoded.location.lat, 39.9999)
  @test.assert_eq(decoded.location.lng, 116.2755)
  @test.assert_eq(decoded.address.country, "中国")
  @test.assert_eq(decoded.address.province, "北京市")
  @test.assert_eq(decoded.address.city, "北京市")
  @test.assert_eq(decoded.address.district, "海淀区")
  @test.assert_eq(decoded.address.street, "颐和园路5号")
  @test.assert_eq(decoded.address.postal_code, "100091")
  @test.assert_eq(decoded.tags.length(), 2)
  @test.assert_eq(decoded.tags[0], "poi")
  @test.assert_eq(decoded.tags[1], "landmark")
  @test.assert_eq(new_pos, encoded.length())
}

test "encode/decode snapshot roundtrip" {
  let entries : Array[@types.GeoEntry] = []
  entries.push({
    id: "id-1",
    name: "Entry 1",
    address: {
      country: "中国",
      province: "广东省",
      city: "广州",
      district: "天河区",
      street: "珠江新城1号",
      postal_code: "510000",
      detail: "",
    },
    location: @types.GeoPoint::make(23.1291, 113.2644),
    tags: ["poi"],
  })
  entries.push({
    id: "id-2",
    name: "Entry 2",
    address: {
      country: "中国",
      province: "浙江省",
      city: "杭州",
      district: "西湖区",
      street: "西湖景区",
      postal_code: "310000",
      detail: "断桥残雪",
    },
    location: @types.GeoPoint::make(30.2741, 120.1551),
    tags: ["attraction", "landmark"],
  })

  let data = encode_snapshot(entries, 1000L, 2000L)
  @test.assert_eq(data.length() > 32, true)

  match decode_snapshot(data) {
    Err(e) => @test.assert_eq("should not error", e)
    Ok((decoded_entries, created_at, updated_at)) => {
      @test.assert_eq(decoded_entries.length(), 2)
      @test.assert_eq(created_at, 1000L)
      @test.assert_eq(updated_at, 2000L)

      let e1 = decoded_entries[0]
      @test.assert_eq(e1.id, "id-1")
      @test.assert_eq(e1.name, "Entry 1")
      @test.assert_eq(e1.address.province, "广东省")
      @test.assert_eq(e1.location.lat, 23.1291)
      @test.assert_eq(e1.tags[0], "poi")

      let e2 = decoded_entries[1]
      @test.assert_eq(e2.id, "id-2")
      @test.assert_eq(e2.address.city, "杭州")
      @test.assert_eq(e2.address.detail, "断桥残雪")
      @test.assert_eq(e2.tags.length(), 2)
    }
  }
}

test "decode_meta reads header correctly" {
  let entries : Array[@types.GeoEntry] = []
  let data = encode_snapshot(entries, 123456789L, 987654321L)

  match decode_meta(data) {
    Err(e) => @test.assert_eq("should not error", e)
    Ok((version, created_at, updated_at, count)) => {
      @test.assert_eq(version, binary_version)
      @test.assert_eq(created_at, 123456789L)
      @test.assert_eq(updated_at, 987654321L)
      @test.assert_eq(count, 0)
    }
  }
}

test "validate_file passes for valid data" {
  let entries : Array[@types.GeoEntry] = []
  entries.push({
    id: "test",
    name: "Test",
    address: @types.Address::empty(),
    location: @types.GeoPoint::make(0.0, 0.0),
    tags: [],
  })
  let data = encode_snapshot(entries, 0L, 0L)
  match validate_file(data) {
    Err(e) => @test.assert_eq("should be valid", e)
    Ok(_) => ()
  }
}

test "validate_file rejects corrupted data" {
  let entries : Array[@types.GeoEntry] = []
  entries.push({
    id: "test",
    name: "Test",
    address: @types.Address::empty(),
    location: @types.GeoPoint::make(0.0, 0.0),
    tags: [],
  })
  let encoded = encode_snapshot(entries, 0L, 0L)

  // Original should decode fine.
  match decode_snapshot(encoded) {
    Err(_) => @test.assert_eq(true, false)
    Ok(_) => ()
  }

  // Build a corrupted version by flipping one byte in the entry area.
  let mut corrupted : Bytes = []
  for i in 0..<encoded.length() {
    corrupted = corrupted + [if i == 33 { encoded[i] ^ 0xFF } else { encoded[i] }]
  }
  // Corrupted should fail validation.
  match validate_file(corrupted) {
    Err(_) => ()
    Ok(_) => @test.assert_eq(true, false)
  }

  // Verify that the original still validates OK.
  let mut ok = false
  match validate_file(encoded) {
    Ok(_) => ok = true
    Err(_) => ()
  }
  @test.assert_eq(ok, true)
}

test "empty entries snapshot" {
  let entries : Array[@types.GeoEntry] = []
  let data = encode_snapshot(entries, 0L, 0L)
  match decode_snapshot(data) {
    Err(e) => @test.assert_eq("should not error", e)
    Ok((decoded, _, _)) => {
      @test.assert_eq(decoded.length(), 0)
    }
  }
}

test "snapshot with many entries" {
  let entries : Array[@types.GeoEntry] = []
  for i in 0..<100 {
    let id_str = "id-\{i}"
    let name_str = "Entry \{i}"
    let street_str = "测试路\{i}号"
    let postal_str = "\{100000 + i}"
    let lat_val = 20.0 + (i.to_double()) * 0.1
    let lng_val = 100.0 + (i.to_double()) * 0.1
    entries.push({
      id: id_str,
      name: name_str,
      address: {
        country: "中国",
        province: "测试省",
        city: "测试市",
        district: "测试区",
        street: street_str,
        postal_code: postal_str,
        detail: "",
      },
      location: @types.GeoPoint::make(lat_val, lng_val),
      tags: [],
    })
  }

  let data = encode_snapshot(entries, 0L, 0L)
  match decode_snapshot(data) {
    Err(_) => @test.assert_eq(true, false)
    Ok((decoded, _, _)) => {
      @test.assert_eq(decoded.length(), 100)
      @test.assert_eq(decoded[50].id, "id-50")
      @test.assert_eq(decoded[50].address.city, "测试市")
      @test.assert_eq(decoded[50].location.lat > 20.0, true)
    }
  }
}
