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

///| FFI: check if file exists. Returns 1 if yes, 0 if no.
#borrow(path)
extern "c" fn ffi_file_exists(path : Bytes, path_len : Int) -> Int = "geodb_file_exists"

///| FFI: rename file old_path to new_path. Returns 0 on success, -1 on error.
#borrow(old_path, new_path)
extern "c" fn ffi_rename_file(
  old_path : Bytes,
  old_path_len : Int,
  new_path : Bytes,
  new_path_len : Int
) -> Int = "geodb_rename"

///| FFI: remove/delete a file. Returns 0 on success, -1 on error.
#borrow(path)
extern "c" fn ffi_remove_file(path : Bytes, path_len : Int) -> Int = "geodb_remove_file"

///| FFI: get file modification time (unix seconds). Returns -1 on error.
#borrow(path)
extern "c" fn ffi_file_mtime(path : Bytes, path_len : Int) -> Int64 = "geodb_file_mtime"

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

///| Atomically rename `old_path` to `new_path`. Returns `Ok` on success.
pub fn rename_file(old_path : String, new_path : String) -> Result[Unit, String] {
  let old_bytes = @utf8.encode(old_path)
  let new_bytes = @utf8.encode(new_path)
  let rc = ffi_rename_file(old_bytes, old_bytes.length(), new_bytes, new_bytes.length())
  if rc == 0 {
    Ok(())
  } else {
    Err("rename failed: \{old_path} -> \{new_path}")
  }
}

///| Remove a file. Returns `Ok` on success.
pub fn remove_file(path : String) -> Result[Unit, String] {
  let path_bytes = @utf8.encode(path)
  let rc = ffi_remove_file(path_bytes, path_bytes.length())
  if rc == 0 {
    Ok(())
  } else {
    Err("remove failed: \{path}")
  }
}

///| Get file modification time (unix seconds). Returns -1 if not found.
pub fn file_mtime(path : String) -> Int64 {
  let path_bytes = @utf8.encode(path)
  ffi_file_mtime(path_bytes, path_bytes.length())
}

///| Atomically write content to file: writes to .tmp first, then renames.
pub fn atomic_save(path : String, content : String) -> Result[Unit, String] {
  let tmp_path = path + ".tmp"
  match save_text(tmp_path, content) {
    Err(e) => Err(e)
    Ok(_) => {
      match rename_file(tmp_path, path) {
        Err(e) => {
          ignore(remove_file(tmp_path))
          Err(e)
        }
        Ok(_) => Ok(())
      }
    }
  }
}
