// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Native (C backend) file IO via FFI stubs in stub.c.
// Gated to `native` target by moon.pkg `targets`.

///| FFI: write content bytes to file at path bytes. Returns 0 on success, -1 on error.
#borrow(path, content)
extern "c" fn ffi_write_file(
  path : Bytes,
  path_len : Int,
  content : Bytes,
  content_len : Int
) -> Int = "geodb_write_file"

///| FFI: read file at path bytes. Returns the file contents as bytes;
/// empty bytes on any error (missing file, IO error, OOM).
#borrow(path)
extern "c" fn ffi_read_file(path : Bytes, path_len : Int) -> Bytes = "geodb_read_file"

///| FFI: check if file exists at path bytes. Returns 1 if yes, 0 if no.
#borrow(path)
extern "c" fn ffi_file_exists(path : Bytes, path_len : Int) -> Int = "geodb_file_exists"

///| Write a UTF-8 string `content` to the file at `path`. Returns `Ok` on
/// success or `Err(msg)` on failure.
pub fn save_text(path : String, content : String) -> Result[Unit, String] {
  let path_bytes = @utf8.encode(path)
  let content_bytes = @utf8.encode(content)
  let rc = ffi_write_file(
    path_bytes,
    path_bytes.length(),
    content_bytes,
    content_bytes.length()
  )
  if rc == 0 {
    Ok(())
  } else {
    Err("failed to write file: \{path}")
  }
}

///| Read the file at `path` as a UTF-8 string. Returns `Ok(text)` on success
/// or `Err(msg)` if the file is missing / unreadable / not valid UTF-8.
pub fn load_text(path : String) -> Result[String, String] {
  let path_bytes = @utf8.encode(path)
  let bytes = ffi_read_file(path_bytes, path_bytes.length())
  if bytes.length() == 0 {
    return Err("file not found or empty: \{path}")
  }
  try Ok(@utf8.decode(bytes)) catch {
    _ => Err("file is not valid UTF-8: \{path}")
  }
}

///| Test whether a file exists at `path`.
pub fn file_exists(path : String) -> Bool {
  let path_bytes = @utf8.encode(path)
  ffi_file_exists(path_bytes, path_bytes.length()) != 0
}
