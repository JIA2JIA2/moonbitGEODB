// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Non-native (wasm/js) stub: file IO is not available.
// Users of these backends should serialize via the @json API directly.

///| Write a UTF-8 string `content` to the file at `path`. Not available on
/// non-native backends.
pub fn save_text(_path : String, _content : String) -> Result[Unit, String] {
  Err("file IO not available on this backend")
}

///| Read the file at `path` as a UTF-8 string. Not available on non-native backends.
pub fn load_text(_path : String) -> Result[String, String] {
  Err("file IO not available on this backend")
}

///| Test whether a file exists at `path`. Always false on non-native backends.
pub fn file_exists(_path : String) -> Bool {
  false
}
