// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Append-only write-ahead log. Each record is laid out as:
//   [i32 op][i32 payload_len][payload][i32 crc32]
// The CRC covers op + payload_len + payload. Replay stops at the first
// incomplete or checksum-invalid record, so a torn tail (crash during
// append) does not lose earlier records.

///|
/// WAL operation: insert or replace an entry.
pub let wal_op_upsert : Int = 1

///|
/// WAL operation: delete an entry by id.
pub let wal_op_delete : Int = 2

///|
/// One decoded WAL record.
pub(all) struct WalRecord {
  op : Int
  entry : @types.GeoEntry?
  id : String
}

///|
/// Path of the WAL file belonging to a database path.
pub fn wal_path(path : String) -> String {
  path + ".wal"
}

///|
/// Encode one WAL record.
fn encode_wal_record(op : Int, payload : Bytes) -> Bytes {
  let w = BinWriter::new()
  w.write_int32(op)
  w.write_bytes(payload)
  let body = w.to_bytes()
  let crc = crc32(body)
  let out = BinWriter::new()
  out.append_bytes(body)
  out.write_int32(crc)
  out.to_bytes()
}

///|
/// Append an upsert record for `entry` to the WAL of `path`.
pub fn append_wal_upsert(
  path : String,
  entry : @types.GeoEntry,
) -> Result[Unit, String] {
  let record = encode_wal_record(wal_op_upsert, encode_entry(entry))
  append_bytes(wal_path(path), record)
}

///|
/// Append a delete record for `id` to the WAL of `path`.
pub fn append_wal_delete(path : String, id : String) -> Result[Unit, String] {
  let record = encode_wal_record(wal_op_delete, encode_string(id))
  append_bytes(wal_path(path), record)
}

///|
/// Load and decode all valid WAL records. A missing WAL yields [].
pub fn load_wal(path : String) -> Array[WalRecord] {
  match load_bytes(wal_path(path)) {
    Err(_) => []
    Ok(data) => decode_wal(data)
  }
}

///|
/// Remove the WAL file after a snapshot has been compacted into place.
pub fn clear_wal(path : String) -> Unit {
  ignore(remove_file(wal_path(path)))
}

///|
/// Decode WAL records until the tail is incomplete or corrupt.
fn decode_wal(data : Bytes) -> Array[WalRecord] {
  let records : Array[WalRecord] = []
  let total = data.length()
  let mut offset = 0
  while offset + 8 <= total {
    let op = decode_int32(data, offset)
    let payload_len = decode_int32(data, offset + 4)
    if payload_len < 0 {
      break
    }
    let payload_start = offset + 8
    let payload_end = payload_start + payload_len
    let crc_pos = payload_end
    if crc_pos + 4 > total {
      break
    }
    if crc32_range(data, offset, crc_pos) != decode_int32(data, crc_pos) {
      break
    }
    if op == wal_op_upsert {
      let (entry, end) = decode_entry(data, payload_start)
      if end != payload_end {
        break
      }
      records.push({ op, entry: Some(entry), id: "" })
    } else if op == wal_op_delete {
      let (id, end) = decode_string(data, payload_start)
      if end != payload_end {
        break
      }
      records.push({ op, entry: None, id })
    } else {
      break
    }
    offset = crc_pos + 4
  }
  records
}