// Copyright 2026 moonbitGEODB contributors
// SPDX-License-Identifier: Apache-2.0
//
// Native C stubs for file IO used by the persist package.
// All paths and contents are passed as (pointer, length) pairs of bytes;
// paths are expected to be UTF-8 encoded (use @utf8.encode on the MoonBit side).
//
// Error reporting: write_file returns -1 on error, 0 on success.
// read_file returns an empty bytes object on error (callers treat empty
// as "missing or unreadable"). file_exists returns 0 or 1.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "moonbit.h"

MOONBIT_FFI_EXPORT int32_t geodb_write_file(
    moonbit_bytes_t path_bytes, int32_t path_len,
    moonbit_bytes_t content_bytes, int32_t content_len
) {
    if (path_len < 0 || content_len < 0) {
        return -1;
    }
    char *path = (char *)malloc((size_t)path_len + 1);
    if (path == NULL) {
        return -1;
    }
    memcpy(path, path_bytes, (size_t)path_len);
    path[path_len] = '\0';
    FILE *f = fopen(path, "wb");
    free(path);
    if (f == NULL) {
        return -1;
    }
    size_t to_write = (size_t)content_len;
    size_t written = (to_write == 0) ? 0 : fwrite(content_bytes, 1, to_write, f);
    int err = ferror(f);
    if (fclose(f) != 0) {
        return -1;
    }
    if (err || written != to_write) {
        return -1;
    }
    return 0;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t geodb_read_file(
    moonbit_bytes_t path_bytes, int32_t path_len
) {
    if (path_len < 0) {
        return moonbit_make_bytes(0, 0);
    }
    char *path = (char *)malloc((size_t)path_len + 1);
    if (path == NULL) {
        return moonbit_make_bytes(0, 0);
    }
    memcpy(path, path_bytes, (size_t)path_len);
    path[path_len] = '\0';
    FILE *f = fopen(path, "rb");
    free(path);
    if (f == NULL) {
        return moonbit_make_bytes(0, 0);
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return moonbit_make_bytes(0, 0);
    }
    long size = ftell(f);
    if (size < 0) {
        fclose(f);
        return moonbit_make_bytes(0, 0);
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return moonbit_make_bytes(0, 0);
    }
    moonbit_bytes_t buf = moonbit_make_bytes((int32_t)size, 0);
    if (buf == NULL) {
        fclose(f);
        return moonbit_make_bytes(0, 0);
    }
    if (size > 0) {
        size_t got = fread(buf, 1, (size_t)size, f);
        int err = ferror(f);
        fclose(f);
        if (err || got != (size_t)size) {
            return moonbit_make_bytes(0, 0);
        }
    } else {
        fclose(f);
    }
    return buf;
}

MOONBIT_FFI_EXPORT int32_t geodb_file_exists(
    moonbit_bytes_t path_bytes, int32_t path_len
) {
    if (path_len < 0) {
        return 0;
    }
    char *path = (char *)malloc((size_t)path_len + 1);
    if (path == NULL) {
        return 0;
    }
    memcpy(path, path_bytes, (size_t)path_len);
    path[path_len] = '\0';
    FILE *f = fopen(path, "rb");
    free(path);
    if (f == NULL) {
        return 0;
    }
    fclose(f);
    return 1;
}

MOONBIT_FFI_EXPORT int32_t geodb_rename(
    moonbit_bytes_t old_path_bytes, int32_t old_path_len,
    moonbit_bytes_t new_path_bytes, int32_t new_path_len
) {
    if (old_path_len < 0 || new_path_len < 0) {
        return -1;
    }
    char *old_path = (char *)malloc((size_t)old_path_len + 1);
    if (old_path == NULL) {
        return -1;
    }
    memcpy(old_path, old_path_bytes, (size_t)old_path_len);
    old_path[old_path_len] = '\0';
    char *new_path = (char *)malloc((size_t)new_path_len + 1);
    if (new_path == NULL) {
        free(old_path);
        return -1;
    }
    memcpy(new_path, new_path_bytes, (size_t)new_path_len);
    new_path[new_path_len] = '\0';
    int rc = rename(old_path, new_path);
    free(old_path);
    free(new_path);
    return rc;
}

MOONBIT_FFI_EXPORT int32_t geodb_remove_file(
    moonbit_bytes_t path_bytes, int32_t path_len
) {
    if (path_len < 0) {
        return -1;
    }
    char *path = (char *)malloc((size_t)path_len + 1);
    if (path == NULL) {
        return -1;
    }
    memcpy(path, path_bytes, (size_t)path_len);
    path[path_len] = '\0';
    int rc = remove(path);
    free(path);
    return rc;
}

MOONBIT_FFI_EXPORT int64_t geodb_file_mtime(
    moonbit_bytes_t path_bytes, int32_t path_len
) {
    if (path_len < 0) {
        return -1;
    }
    char *path = (char *)malloc((size_t)path_len + 1);
    if (path == NULL) {
        return -1;
    }
    memcpy(path, path_bytes, (size_t)path_len);
    path[path_len] = '\0';
    struct stat st;
    int rc = stat(path, &st);
    free(path);
    if (rc != 0) {
        return -1;
    }
    return (int64_t)st.st_mtime;
}
