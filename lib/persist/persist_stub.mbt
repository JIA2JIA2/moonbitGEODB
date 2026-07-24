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

///| Atomically rename `old_path` to `new_path`. Not available on non-native backends.
pub fn rename_file(_old_path : String, _new_path : String) -> Result[Unit, String] {
  Err("file IO not available on this backend")
}

///| Remove a file. Not available on non-native backends.
pub fn remove_file(_path : String) -> Result[Unit, String] {
  Err("file IO not available on this backend")
}

///| Get file modification time. Returns -1 on non-native backends.
pub fn file_mtime(_path : String) -> Long {
  -1L
}

///| Atomically write content to file. Not available on non-native backends.
pub fn atomic_save(_path : String, _content : String) -> Result[Unit, String] {
  Err("file IO not available on this backend")
}
