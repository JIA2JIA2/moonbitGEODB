// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Cross-backend JSON serialization + persistence helpers for the geo DB.

/// Current database format version.
pub let db_version : Int = 1

/// Database metadata embedded in the JSON file.
pub(all) struct DBMeta {
  version : Int
  created_at : Int64
  updated_at : Int64
  entry_count : Int
} derive(ToJson, FromJson)

/// Wrapper: metadata + entries array for a complete DB snapshot.
pub(all) struct DBSnapshot {
  meta : DBMeta
  entries : Array[@types.GeoEntry]
} derive(ToJson, FromJson)

///| Serialize an array of entries to a pretty-printed JSON string.
pub fn entries_to_json(entries : Array[@types.GeoEntry]) -> String {
  entries.to_json().stringify(indent=2)
}

///| Parse a JSON string into an array of entries.
pub fn entries_from_json(text : String) -> Result[Array[@types.GeoEntry], String] {
  try {
    let json = @json.parse(text)
    let entries : Array[@types.GeoEntry] = @json.from_json(json)
    Ok(entries)
  } catch {
    e => Err("JSON error: \{e}")
  }
}

///| Serialize a full snapshot (meta + entries) to JSON.
pub fn snapshot_to_json(snap : DBSnapshot) -> String {
  snap.to_json().stringify(indent=2)
}

///| Parse a full snapshot from JSON.
pub fn snapshot_from_json(text : String) -> Result[DBSnapshot, String] {
  try {
    let json = @json.parse(text)
    let snap : DBSnapshot = @json.from_json(json)
    Ok(snap)
  } catch {
    e => Err("JSON error: \{e}")
  }
}

///| Build a snapshot from entries and timestamps.
pub fn make_snapshot(
  entries : Array[@types.GeoEntry],
  created_at : Int64,
  updated_at : Int64
) -> DBSnapshot {
  {
    meta: {
      version: db_version,
      created_at,
      updated_at,
      entry_count: entries.length(),
    },
    entries,
  }
}

///| Save entries to a file at `path` as pretty JSON (simple, non-atomic).
pub fn save_entries(
  path : String,
  entries : Array[@types.GeoEntry]
) -> Result[Unit, String] {
  let text = entries_to_json(entries)
  save_text(path, text)
}

///| Load entries from a JSON file at `path`.
pub fn load_entries(path : String) -> Result[Array[@types.GeoEntry], String] {
  match load_text(path) {
    Err(msg) => Err(msg)
    Ok(text) => entries_from_json(text)
  }
}

///| Atomically save entries with metadata to `path`.
pub fn atomic_save_entries(
  path : String,
  entries : Array[@types.GeoEntry],
  created_at : Int64,
  updated_at : Int64
) -> Result[Unit, String] {
  let snap = make_snapshot(entries, created_at, updated_at)
  let text = snapshot_to_json(snap)
  atomic_save(path, text)
}

///| Load a snapshot (meta + entries) from a JSON file.
pub fn load_snapshot(path : String) -> Result[DBSnapshot, String] {
  match load_text(path) {
    Err(e) => Err(e)
    Ok(text) => {
      // Try new format first (snapshot with meta).
      match snapshot_from_json(text) {
        Ok(snap) => Ok(snap)
        Err(_) => {
          // Fall back to legacy: raw array of entries.
          match entries_from_json(text) {
            Err(e) => Err(e)
            Ok(entries) => {
              let now = get_timestamp()
              Ok(make_snapshot(entries, now, now))
            }
          }
        }
      }
    }
  }
}

///| Create a backup of the file at `path` by copying to `path.bak`.
pub fn create_backup(path : String) -> Result[String, String] {
  let bak_path = path + ".bak"
  match load_text(path) {
    Err(e) => Err("cannot backup: \{e}")
    Ok(text) => {
      match save_text(bak_path, text) {
        Err(e) => Err("backup failed: \{e}")
        Ok(_) => Ok(bak_path)
      }
    }
  }
}

///| Restore the file at `path` from its `.bak` backup.
pub fn restore_from_backup(path : String) -> Result[Unit, String] {
  let bak_path = path + ".bak"
  match load_text(bak_path) {
    Err(e) => Err("restore failed: \{e}")
    Ok(text) => atomic_save(path, text)
  }
}

///| Check integrity: validate JSON format and that entries have required fields.
pub fn check_integrity(path : String) -> Result[DBMeta, String] {
  match load_snapshot(path) {
    Err(e) => Err("integrity check failed: \{e}")
    Ok(snap) => {
      for e in snap.entries {
        if e.id.length() == 0 {
          return Err("integrity check failed: entry with empty id found")
        }
      }
      if snap.meta.version != db_version {
        return Err("version mismatch: expected \{db_version}, got \{snap.meta.version}")
      }
      Ok(snap.meta)
    }
  }
}

///| Get a timestamp (returns 0 as portable placeholder).
fn get_timestamp() -> Int64 {
  0L
}

///| Extract just the entries from a snapshot file.
pub fn load_entries_from_snapshot(path : String) -> Result[Array[@types.GeoEntry], String] {
  match load_snapshot(path) {
    Err(e) => Err(e)
    Ok(snap) => Ok(snap.entries)
  }
}
