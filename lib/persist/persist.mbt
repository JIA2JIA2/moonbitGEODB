// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Binary persistence layer for the geo database.
// Uses a custom binary format (see binary.mbt) with CRC32 checksums
// for integrity verification. All file IO goes through persist_native.mbt.

/// Current binary database format version.
pub let db_version : Int = 1

/// Database metadata (extracted from the binary file header).
pub(all) struct DBMeta {
  version : Int
  created_at : Int64
  updated_at : Int64
  entry_count : Int
}

/// Save entries to a binary file at `path`.
pub fn save_entries(
  path : String,
  entries : Array[@types.GeoEntry]
) -> Result[Unit, String] {
  let data = encode_snapshot(entries, 0L, 0L)
  save_bytes(path, data)
}

/// Load entries from a binary file at `path`.
pub fn load_entries(path : String) -> Result[Array[@types.GeoEntry], String] {
  match load_bytes(path) {
    Err(msg) => Err(msg)
    Ok(data) => {
      match decode_snapshot(data) {
        Err(e) => Err(e)
        Ok((entries, _, _)) => Ok(entries)
      }
    }
  }
}

///| Atomically save entries with metadata to `path` in binary format.
pub fn atomic_save_entries(
  path : String,
  entries : Array[@types.GeoEntry],
  created_at : Int64,
  updated_at : Int64
) -> Result[Unit, String] {
  let data = encode_snapshot(entries, created_at, updated_at)
  atomic_save_bytes(path, data)
}

///| Load a snapshot (entries + metadata) from a binary file.
pub fn load_snapshot(path : String) -> Result[(Array[@types.GeoEntry], Int64, Int64), String] {
  match load_bytes(path) {
    Err(e) => Err(e)
    Ok(data) => decode_snapshot(data)
  }
}

///| Create a binary backup of the file at `path` by copying to `path.bak`.
pub fn create_backup(path : String) -> Result[String, String] {
  let bak_path = path + ".bak"
  match load_bytes(path) {
    Err(e) => Err("cannot backup: \{e}")
    Ok(data) => {
      match save_bytes(bak_path, data) {
        Err(e) => Err("backup failed: \{e}")
        Ok(_) => Ok(bak_path)
      }
    }
  }
}

///| Restore the file at `path` from its `.bak` backup.
pub fn restore_from_backup(path : String) -> Result[Unit, String] {
  let bak_path = path + ".bak"
  match load_bytes(bak_path) {
    Err(e) => Err("restore failed: \{e}")
    Ok(data) => atomic_save_bytes(path, data)
  }
}

///| Check integrity: validate binary format, CRC32 checksum, and required fields.
pub fn check_integrity(path : String) -> Result[DBMeta, String] {
  match load_bytes(path) {
    Err(e) => Err("integrity check failed: \{e}")
    Ok(data) => {
      match validate_file(data) {
        Err(e) => Err("integrity check failed: \{e}")
        Ok(_) => {
          match decode_meta(data) {
            Err(e) => Err("integrity check failed: \{e}")
            Ok((version, created_at, updated_at, entry_count)) => {
              if version != db_version {
                return Err("version mismatch: expected \{db_version}, got \{version}")
              }
              match decode_snapshot(data) {
                Err(e) => Err("integrity check failed: \{e}")
                Ok((entries, _, _)) => {
                  for e in entries {
                    if e.id.length() == 0 {
                      return Err("integrity check failed: entry with empty id found")
                    }
                  }
                  Ok({ version, created_at, updated_at, entry_count })
                }
              }
            }
          }
        }
      }
    }
  }
}

///| Extract just the entries from a snapshot file.
pub fn load_entries_from_snapshot(path : String) -> Result[Array[@types.GeoEntry], String] {
  match load_snapshot(path) {
    Err(e) => Err(e)
    Ok((entries, _, _)) => Ok(entries)
  }
}

///| Encode entries + metadata to binary Bytes (thin wrapper for external callers).
pub fn binary_encode_snapshot(
  entries : Array[@types.GeoEntry],
  created_at : Int64,
  updated_at : Int64
) -> Bytes {
  encode_snapshot(entries, created_at, updated_at)
}

///| Decode binary Bytes to entries + metadata (thin wrapper for external callers).
pub fn binary_decode_snapshot(data : Bytes) -> Result[(Array[@types.GeoEntry], Int64, Int64), String] {
  decode_snapshot(data)
}
