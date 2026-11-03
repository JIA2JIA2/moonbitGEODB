// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Binary persistence layer for the geo database.
// Uses a custom binary format (see binary.mbt) with CRC32 checksums
// for integrity verification. All file IO goes through persist_native.mbt.

///|
/// Current binary database format version.
pub let db_version : Int = 1

///|
/// Database metadata (extracted from the binary file header).
pub(all) struct DBMeta {
  version : Int
  created_at : Int64
  updated_at : Int64
  entry_count : Int
}

///|
/// Save entries to a binary file at `path`.
pub fn save_entries(
  path : String,
  entries : Array[@types.GeoEntry],
) -> Result[Unit, String] {
  let data = encode_snapshot(entries, 0L, 0L)
  save_bytes(path, data)
}

///|
/// Load entries from a binary file at `path`.
pub fn load_entries(path : String) -> Result[Array[@types.GeoEntry], String] {
  match load_snapshot(path) {
    Err(e) => Err(e)
    Ok((entries, _, _)) => Ok(entries)
  }
}

///|
/// Atomically save entries with metadata to `path` in binary format.
pub fn atomic_save_entries(
  path : String,
  entries : Array[@types.GeoEntry],
  created_at : Int64,
  updated_at : Int64,
) -> Result[Unit, String] {
  let data = encode_snapshot(entries, created_at, updated_at)
  atomic_save_bytes(path, data)
}

///|
/// Buffered sequential reader for snapshot decoding.
priv struct SnapshotReader {
  path : String
  mut buf : Bytes
  mut pos : Int
  mut file_off : Int64
  mut eof : Bool
}

///|
fn SnapshotReader::new(path : String) -> SnapshotReader {
  { path, buf: [], pos: 0, file_off: 0L, eof: false, }
}

///|
fn SnapshotReader::fill(self : SnapshotReader, need : Int) -> Bool {
  while self.buf.length() - self.pos < need && !self.eof {
    let chunk = read_range(self.path, self.file_off, 65536)
    if chunk.length() == 0 {
      self.eof = true
      break
    }
    self.file_off = self.file_off + chunk.length().to_int64()
    let remain = bytes_slice(self.buf, self.pos, self.buf.length())
    self.buf = remain + chunk
    self.pos = 0
  }
  self.buf.length() - self.pos >= need
}

///|
fn SnapshotReader::take(self : SnapshotReader, n : Int) -> Bytes? {
  if n < 0 || !self.fill(n) {
    return None
  }
  let out = bytes_slice(self.buf, self.pos, self.pos + n)
  self.pos = self.pos + n
  Some(out)
}

///|
/// Load a snapshot by streaming fixed-size chunks instead of reading the whole
/// file into memory. Peak memory is bounded by the chunk plus one entry.
pub fn load_snapshot_stream(
  path : String,
) -> Result[(Array[@types.GeoEntry], Int64, Int64), String] {
  let total = file_size(path)
  if total <= 0L {
    return Err("file not found or empty: \{path}")
  }
  let reader = SnapshotReader::new(path)
  let header = match reader.take(header_size) {
    Some(b) => b
    None => return Err("truncated snapshot header")
  }
  let (version, created_at, updated_at, entry_count, checksum) = match decode_header(
    header,
  ) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if version != binary_version {
    return Err("version mismatch: expected \{binary_version}, got \{version}")
  }
  if entry_count < 0 || entry_count.to_double() > total.to_double() {
    return Err("invalid entry count in snapshot header")
  }
  let entries : Array[@types.GeoEntry] = []
  let mut crc : UInt64 = 0xFFFFFFFF
  let mut i = 0
  while i < entry_count {
    let size_bytes = match reader.take(4) {
      Some(b) => b
      None => return Err("truncated entry size")
    }
    let record_size = decode_int32(size_bytes, 0)
    if record_size < 4 || record_size > 16777216 {
      return Err("invalid entry size")
    }
    let body = match reader.take(record_size - 4) {
      Some(b) => b
      None => return Err("truncated entry body")
    }
    let record = size_bytes + body
    crc = crc32_update(crc, record, 0, record.length())
    let (entry, end) = decode_entry(record, 0)
    if end != record.length() {
      return Err("entry size mismatch")
    }
    entries.push(entry)
    i = i + 1
  }
  let computed : UInt64 = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF
  if computed.to_int() != checksum {
    return Err("checksum mismatch: file may be corrupted")
  }
  Ok((entries, created_at, updated_at))
}

///|
/// Load a snapshot (entries + metadata) from a binary file.
pub fn load_snapshot(
  path : String,
) -> Result[(Array[@types.GeoEntry], Int64, Int64), String] {
  load_snapshot_stream(path)
}

///|
/// Create a binary backup of the file at `path` by copying to `path.bak`.
pub fn create_backup(path : String) -> Result[String, String] {
  let bak_path = path + ".bak"
  match copy_file(path, bak_path) {
    Err(e) => Err("cannot backup: \{e}")
    Ok(_) => Ok(bak_path)
  }
}

///|
/// Restore the file at `path` from its `.bak` backup.
pub fn restore_from_backup(path : String) -> Result[Unit, String] {
  let bak_path = path + ".bak"
  let tmp_path = path + ".tmp"
  match copy_file(bak_path, tmp_path) {
    Err(e) => Err("restore failed: \{e}")
    Ok(_) =>
      match rename_file(tmp_path, path) {
        Err(e) => {
          ignore(remove_file(tmp_path))
          Err(e)
        }
        Ok(_) => Ok(())
      }
  }
}

///|
/// Check integrity: validate binary format, CRC32 checksum, and required fields.
pub fn check_integrity(path : String) -> Result[DBMeta, String] {
  match load_bytes(path) {
    Err(e) => Err("integrity check failed: \{e}")
    Ok(data) =>
      match decode_meta(data) {
        Err(e) => Err("integrity check failed: \{e}")
        Ok((version, created_at, updated_at, entry_count)) => {
          if version != db_version {
            return Err(
              "version mismatch: expected \{db_version}, got \{version}",
            )
          }
          match decode_snapshot(data) {
            Err(e) => Err("integrity check failed: \{e}")
            Ok((entries, _, _)) => {
              for e in entries {
                if e.id.length() == 0 {
                  return Err(
                    "integrity check failed: entry with empty id found",
                  )
                }
              }
              Ok({ version, created_at, updated_at, entry_count, })
            }
          }
        }
      }
  }
}

///|
/// Extract just the entries from a snapshot file.
pub fn load_entries_from_snapshot(
  path : String,
) -> Result[Array[@types.GeoEntry], String] {
  match load_snapshot(path) {
    Err(e) => Err(e)
    Ok((entries, _, _)) => Ok(entries)
  }
}

///|
/// Encode entries + metadata to binary Bytes (thin wrapper for external callers).
pub fn binary_encode_snapshot(
  entries : Array[@types.GeoEntry],
  created_at : Int64,
  updated_at : Int64,
) -> Bytes {
  encode_snapshot(entries, created_at, updated_at)
}

///|
/// Decode binary Bytes to entries + metadata (thin wrapper for external callers).
pub fn binary_decode_snapshot(
  data : Bytes,
) -> Result[(Array[@types.GeoEntry], Int64, Int64), String] {
  decode_snapshot(data)
}
