// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0

/// Cross-backend JSON serialization + persistence helpers for the geo DB.
/// The actual file IO lives in `persist_native.mbt` (native) / `persist_stub.mbt`
/// (other backends); this file just adds JSON (de)serialization on top.

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

///| Save entries to a file at `path` as pretty JSON.
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
