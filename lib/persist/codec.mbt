// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Binary codec: low-level encoding/decoding of primitive types to/from Bytes.
// Big-endian byte order is used for portability across architectures.
// Uses UInt64 for all bitwise operations with infix operators per MoonBit conventions.
// Bytes is Array[Byte] - elements must use the Byte type.

/// Slice a Bytes range [start, end) into a new Bytes.
pub fn bytes_slice(data : Bytes, start : Int, end : Int) -> Bytes {
  let mut result : Bytes = []
  for i in start..<end {
    result = result + [data[i]]
  }
  result
}

/// Compare two Bytes for equality.
pub fn bytes_eq(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

/// Encode an Int as 4 big-endian bytes (32-bit 2's complement).
pub fn encode_int32(value : Int) -> Bytes {
  let v : UInt64 = value.to_uint64()
  let b0 : Byte = ((v >> 24) & 0xFF).to_byte()
  let b1 : Byte = ((v >> 16) & 0xFF).to_byte()
  let b2 : Byte = ((v >> 8) & 0xFF).to_byte()
  let b3 : Byte = (v & 0xFF).to_byte()
  [b0, b1, b2, b3]
}

/// Decode 4 big-endian bytes to a signed Int (sign-extended from 32-bit).
pub fn decode_int32(bytes : Bytes, offset : Int) -> Int {
  let b0 : UInt64 = bytes[offset].to_uint64()
  let b1 : UInt64 = bytes[offset + 1].to_uint64()
  let b2 : UInt64 = bytes[offset + 2].to_uint64()
  let b3 : UInt64 = bytes[offset + 3].to_uint64()
  let v = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
  // Sign-extend if bit 31 is set.
  let mask : UInt64 = 0x80000000
  let zero : UInt64 = 0
  if (v & mask) != zero {
    ((v << 32) >> 32).to_int()
  } else {
    v.to_int()
  }
}

/// Encode a UInt16 as 2 big-endian bytes.
pub fn encode_uint16(value : Int) -> Bytes {
  let v : UInt64 = value.to_uint64()
  let b0 : Byte = ((v >> 8) & 0xFF).to_byte()
  let b1 : Byte = (v & 0xFF).to_byte()
  [b0, b1]
}

/// Decode 2 big-endian bytes to UInt16 (returned as Int).
pub fn decode_uint16(bytes : Bytes, offset : Int) -> Int {
  let b0 : UInt64 = bytes[offset].to_uint64()
  let b1 : UInt64 = bytes[offset + 1].to_uint64()
  ((b0 << 8) | b1).to_int()
}

/// Encode an Int64 as 8 big-endian bytes.
pub fn encode_int64(value : Int64) -> Bytes {
  let v : UInt64 = value.reinterpret_as_uint64()
  let b0 : Byte = ((v >> 56) & 0xFF).to_byte()
  let b1 : Byte = ((v >> 48) & 0xFF).to_byte()
  let b2 : Byte = ((v >> 40) & 0xFF).to_byte()
  let b3 : Byte = ((v >> 32) & 0xFF).to_byte()
  let b4 : Byte = ((v >> 24) & 0xFF).to_byte()
  let b5 : Byte = ((v >> 16) & 0xFF).to_byte()
  let b6 : Byte = ((v >> 8) & 0xFF).to_byte()
  let b7 : Byte = (v & 0xFF).to_byte()
  [b0, b1, b2, b3, b4, b5, b6, b7]
}

/// Decode 8 big-endian bytes to Int64.
pub fn decode_int64(bytes : Bytes, offset : Int) -> Int64 {
  let b0 : UInt64 = bytes[offset].to_uint64()
  let b1 : UInt64 = bytes[offset + 1].to_uint64()
  let b2 : UInt64 = bytes[offset + 2].to_uint64()
  let b3 : UInt64 = bytes[offset + 3].to_uint64()
  let b4 : UInt64 = bytes[offset + 4].to_uint64()
  let b5 : UInt64 = bytes[offset + 5].to_uint64()
  let b6 : UInt64 = bytes[offset + 6].to_uint64()
  let b7 : UInt64 = bytes[offset + 7].to_uint64()
  let v = (b0 << 56)
    | (b1 << 48)
    | (b2 << 40)
    | (b3 << 32)
    | (b4 << 24)
    | (b5 << 16)
    | (b6 << 8)
    | b7
  v.reinterpret_as_int64()
}

/// Encode a Double as 8 big-endian bytes (IEEE 754).
pub fn encode_double(value : Double) -> Bytes {
  let bits : Int64 = value.reinterpret_as_int64()
  encode_int64(bits)
}

/// Decode 8 big-endian bytes to Double (IEEE 754).
pub fn decode_double(bytes : Bytes, offset : Int) -> Double {
  let bits = decode_int64(bytes, offset)
  bits.reinterpret_as_double()
}

/// Encode a length-prefixed UTF-8 string: UInt16 length + UTF-8 bytes.
pub fn encode_string(s : String) -> Bytes {
  let utf8 = @utf8.encode(s)
  let len = utf8.length()
  let len_bytes = encode_uint16(len)
  len_bytes + utf8
}

/// Decode a length-prefixed string from Bytes at offset.
/// Returns (decoded_string, new_offset).
pub fn decode_string(bytes : Bytes, offset : Int) -> (String, Int) {
  let len = decode_uint16(bytes, offset)
  let start = offset + 2
  let end = start + len
  let sub = bytes_slice(bytes, start, end)
  let s = try { @utf8.decode(sub) } catch {
    _ => ""
  }
  (s, end)
}

/// Encode raw Bytes with a UInt32 length prefix.
pub fn encode_bytes_with_len(data : Bytes) -> Bytes {
  let len = encode_int32(data.length())
  len + data
}

/// Decode raw Bytes with a UInt32 length prefix at offset.
/// Returns (data, new_offset).
pub fn decode_bytes_with_len(bytes : Bytes, offset : Int) -> (Bytes, Int) {
  let len = decode_int32(bytes, offset)
  let start = offset + 4
  let end = start + len
  let data = bytes_slice(bytes, start, end)
  (data, end)
}

/// Compute a CRC32 checksum of a Bytes slice.
pub fn crc32(data : Bytes) -> Int {
  let mut crc : UInt64 = 0xFFFFFFFF
  let zero : UInt64 = 0
  for i in 0..<data.length() {
    let byte : UInt64 = data[i].to_uint64()
    crc = (crc ^ byte) & 0xFFFFFFFF
    for _ in 0..<8 {
      let one : UInt64 = 1
      if (crc & one) != zero {
        crc = (crc >> 1) ^ 0xEDB88320
      } else {
        crc = crc >> 1
      }
    }
  }
  let result : UInt64 = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF
  result.to_int()
}

// ---- Writer/Reader for streaming ----

/// A sequential binary writer that appends encoded data to a Bytes buffer.
pub(all) struct BinWriter {
  mut buf : Bytes
}

/// Create a new empty BinWriter.
pub fn BinWriter::new() -> BinWriter {
  { buf: ([] : Bytes) }
}

/// Write an Int32.
pub fn BinWriter::write_int32(self : BinWriter, value : Int) -> Unit {
  self.buf = self.buf + encode_int32(value)
}

/// Write a UInt16.
pub fn BinWriter::write_uint16(self : BinWriter, value : Int) -> Unit {
  self.buf = self.buf + encode_uint16(value)
}

/// Write an Int64.
pub fn BinWriter::write_int64(self : BinWriter, value : Int64) -> Unit {
  self.buf = self.buf + encode_int64(value)
}

/// Write a Double.
pub fn BinWriter::write_double(self : BinWriter, value : Double) -> Unit {
  self.buf = self.buf + encode_double(value)
}

/// Write a length-prefixed string.
pub fn BinWriter::write_string(self : BinWriter, s : String) -> Unit {
  self.buf = self.buf + encode_string(s)
}

/// Write raw bytes with a UInt32 length prefix.
pub fn BinWriter::write_bytes(self : BinWriter, data : Bytes) -> Unit {
  self.buf = self.buf + encode_bytes_with_len(data)
}

/// Get the final encoded Bytes.
pub fn BinWriter::to_bytes(self : BinWriter) -> Bytes {
  self.buf
}

/// Get current length of written data.
pub fn BinWriter::len(self : BinWriter) -> Int {
  self.buf.length()
}

/// A sequential binary reader over a Bytes buffer.
pub(all) struct BinReader {
  data : Bytes
  mut pos : Int
}

/// Create a new BinReader from Bytes.
pub fn BinReader::new(data : Bytes) -> BinReader {
  { data, pos: 0 }
}

/// Read an Int32.
pub fn BinReader::read_int32(self : BinReader) -> Int {
  let v = decode_int32(self.data, self.pos)
  self.pos = self.pos + 4
  v
}

/// Read a UInt16.
pub fn BinReader::read_uint16(self : BinReader) -> Int {
  let v = decode_uint16(self.data, self.pos)
  self.pos = self.pos + 2
  v
}

/// Read an Int64.
pub fn BinReader::read_int64(self : BinReader) -> Int64 {
  let v = decode_int64(self.data, self.pos)
  self.pos = self.pos + 8
  v
}

/// Read a Double.
pub fn BinReader::read_double(self : BinReader) -> Double {
  let v = decode_double(self.data, self.pos)
  self.pos = self.pos + 8
  v
}

/// Read a length-prefixed string.
pub fn BinReader::read_string(self : BinReader) -> String {
  let (s, new_pos) = decode_string(self.data, self.pos)
  self.pos = new_pos
  s
}

/// Read raw bytes with a UInt32 length prefix.
pub fn BinReader::read_bytes(self : BinReader) -> Bytes {
  let (b, new_pos) = decode_bytes_with_len(self.data, self.pos)
  self.pos = new_pos
  b
}

/// Check if the reader has reached end of data.
pub fn BinReader::is_eof(self : BinReader) -> Bool {
  self.pos >= self.data.length()
}

/// Get current read position.
pub fn BinReader::position(self : BinReader) -> Int {
  self.pos
}

// ---- tests ----

test "encode/decode int32 roundtrip" {
  for v in [0, 1, -1, 255, 256, 32767, -32768, 2147483647, -2147483648] {
    let encoded = encode_int32(v)
    let decoded = decode_int32(encoded, 0)
    @test.assert_eq(decoded, v)
  }
}

test "encode/decode uint16 roundtrip" {
  for v in [0, 1, 255, 256, 65535] {
    let encoded = encode_uint16(v)
    let decoded = decode_uint16(encoded, 0)
    @test.assert_eq(decoded, v)
  }
}

test "encode/decode int64 roundtrip" {
  for v in [0L, 1L, -1L, 9223372036854775807L, -9223372036854775808L] {
    let encoded = encode_int64(v)
    let decoded = decode_int64(encoded, 0)
    @test.assert_eq(decoded, v)
  }
}

test "encode/decode double roundtrip" {
  for v in [0.0, 1.0, -1.0, 3.141592653589793, -273.15] {
    let encoded = encode_double(v)
    let decoded = decode_double(encoded, 0)
    @test.assert_eq(decoded, v)
  }
}

test "encode/decode string roundtrip" {
  for s in ["", "hello", "北京", "中国北京市海淀区颐和园路5号"] {
    let encoded = encode_string(s)
    let (decoded, _) = decode_string(encoded, 0)
    @test.assert_eq(decoded, s)
  }
}

test "BinWriter and BinReader roundtrip" {
  let w = BinWriter::new()
  w.write_int32(42)
  w.write_uint16(65535)
  w.write_int64(999999999999L)
  w.write_double(3.14)
  w.write_string("测试数据 test data 123")
  let encoded = w.to_bytes()

  let r = BinReader::new(encoded)
  @test.assert_eq(r.read_int32(), 42)
  @test.assert_eq(r.read_uint16(), 65535)
  @test.assert_eq(r.read_int64(), 999999999999L)
  @test.assert_eq(r.read_double(), 3.14)
  @test.assert_eq(r.read_string(), "测试数据 test data 123")
  @test.assert_eq(r.is_eof(), true)
}

test "crc32 produces consistent checksums" {
  let data : Bytes = [0x4D, 0x47, 0x44, 0x42]
  let crc = crc32(data)
  @test.assert_eq(crc > 0, true)
  @test.assert_eq(crc32(data), crc)
  let data2 : Bytes = [0x4D, 0x47, 0x44, 0x43]
  @test.assert_eq(crc32(data2) != crc, true)
}