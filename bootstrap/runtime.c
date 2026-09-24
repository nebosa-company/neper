/* Fixed neper-0 host intrinsics. Keep this file independent of the C runtime on
 * Windows; generated programs link it with the platform libraries directly. */
#ifndef _WIN32
#define _GNU_SOURCE
#endif

#include <stddef.h>
#include <stdint.h>

typedef struct { unsigned char *base; size_t cap; size_t off; } NpArena;
typedef struct { const unsigned char *ptr; size_t len; } NpStr;
typedef struct { uintptr_t raw; } NpFile;
typedef struct { uintptr_t raw; } NpProc;
typedef struct { NpStr name; unsigned char kind; unsigned char pad[7]; } NpDirEntry;
typedef struct { NpFile in, out, err; struct { const uintptr_t *ptr; size_t len; } inherit; } NpStdio;

enum {
    NP_OK = 0, NP_NOT_FOUND = 2, NP_DENIED = 3, NP_EXISTS = 4,
    NP_INTERRUPTED = 5, NP_OUT_OF_MEMORY = 6, NP_FAILED = 7,
    NP_TIMEOUT = 8, NP_WOULD_BLOCK = 9, NP_UNSUPPORTED = 10,
    NP_EXHAUSTED = 11
};

/* `os.copy_bytes` (D329): as many bytes as the shorter slice holds, forwards. */
void neper_os_copy_bytes(unsigned char *dst, size_t dst_len, const unsigned char *src, size_t src_len) {
    size_t count = dst_len < src_len ? dst_len : src_len, at;
    for (at = 0; at < count; at++) dst[at] = src[at];
}
/* `os.sha256_blocks` (D332): the C runtime has no SHA extensions, so none are done and
   the caller runs its own rounds. */
size_t neper_os_sha256_blocks(size_t *state, size_t state_len, const unsigned char *bytes, size_t len) {
    (void)state; (void)state_len; (void)bytes; (void)len;
    return 0;
}
/* `os.crc32c_bytes` (D332): likewise none; the caller keeps its tables. */
size_t neper_os_crc32c_bytes(size_t *crc, size_t crc_len, const unsigned char *bytes, size_t len) {
    (void)crc; (void)crc_len; (void)bytes; (void)len;
    return 0;
}
static const NpStr *np_args_ptr;
static size_t np_args_len;

/* Spec section 9 rule 4: the supplied `hash` is xxHash64 with seed 0 over a value's
 * canonical little-endian bytes. This is the one-shot form of algo.hash.xxhash64,
 * which it must agree with bit for bit; a fixture asserts that on both platforms. */
#define NP_XXH_P1 11400714785074694791ull
#define NP_XXH_P2 14029467366897019727ull
#define NP_XXH_P3 1609587929392839161ull
#define NP_XXH_P4 9650029242287828579ull
#define NP_XXH_P5 2870177450012600261ull

static uint64_t np_xxh_rotl(uint64_t v, unsigned bits) {
    return (v << bits) | (v >> (64u - bits));
}

static uint64_t np_xxh_read64(const unsigned char *p) {
    return (uint64_t)p[0] | ((uint64_t)p[1] << 8) | ((uint64_t)p[2] << 16) |
           ((uint64_t)p[3] << 24) | ((uint64_t)p[4] << 32) | ((uint64_t)p[5] << 40) |
           ((uint64_t)p[6] << 48) | ((uint64_t)p[7] << 56);
}

static uint64_t np_xxh_read32(const unsigned char *p) {
    return (uint64_t)p[0] | ((uint64_t)p[1] << 8) | ((uint64_t)p[2] << 16) |
           ((uint64_t)p[3] << 24);
}

static uint64_t np_xxh_round(uint64_t acc, uint64_t word) {
    return np_xxh_rotl(acc + word * NP_XXH_P2, 31) * NP_XXH_P1;
}

static uint64_t np_xxh_merge(uint64_t hash, uint64_t lane) {
    return (hash ^ (np_xxh_rotl(lane * NP_XXH_P2, 31) * NP_XXH_P1)) * NP_XXH_P1 + NP_XXH_P4;
}

uint64_t neper_hash_bytes(const unsigned char *p, size_t len) {
    uint64_t hash;
    size_t at = 0;
    if (len >= 32) {
        uint64_t v1 = NP_XXH_P1 + NP_XXH_P2, v2 = NP_XXH_P2, v3 = 0, v4 = 0 - NP_XXH_P1;
        size_t limit = len - 32;
        do {
            v1 = np_xxh_round(v1, np_xxh_read64(p + at)); at += 8;
            v2 = np_xxh_round(v2, np_xxh_read64(p + at)); at += 8;
            v3 = np_xxh_round(v3, np_xxh_read64(p + at)); at += 8;
            v4 = np_xxh_round(v4, np_xxh_read64(p + at)); at += 8;
        } while (at <= limit);
        hash = np_xxh_rotl(v1, 1) + np_xxh_rotl(v2, 7) + np_xxh_rotl(v3, 12) + np_xxh_rotl(v4, 18);
        hash = np_xxh_merge(hash, v1);
        hash = np_xxh_merge(hash, v2);
        hash = np_xxh_merge(hash, v3);
        hash = np_xxh_merge(hash, v4);
    } else {
        hash = NP_XXH_P5;
    }
    hash += (uint64_t)len;
    while (at + 8 <= len) {
        hash ^= np_xxh_rotl(np_xxh_read64(p + at) * NP_XXH_P2, 31) * NP_XXH_P1;
        hash = np_xxh_rotl(hash, 27) * NP_XXH_P1 + NP_XXH_P4;
        at += 8;
    }
    if (at + 4 <= len) {
        hash ^= np_xxh_read32(p + at) * NP_XXH_P1;
        hash = np_xxh_rotl(hash, 23) * NP_XXH_P2 + NP_XXH_P3;
        at += 4;
    }
    while (at < len) {
        hash ^= (uint64_t)p[at] * NP_XXH_P5;
        hash = np_xxh_rotl(hash, 11) * NP_XXH_P1;
        at += 1;
    }
    hash ^= hash >> 33;
    hash *= NP_XXH_P2;
    hash ^= hash >> 29;
    hash *= NP_XXH_P3;
    return hash ^ (hash >> 32);
}

/* On Windows the root arena is reserved rather than committed, so that a process is not
 * charged the whole of it against the commit limit before `main` runs. It grows a chunk at
 * a time from here, which is the one place an arena's offset moves. Linux needs none of
 * this: an anonymous mapping there is already backed only by the pages that are touched. */
#define NP_ROOT_CHUNK ((size_t)0x100000)

static unsigned char *np_root_base;
static size_t np_root_size;
static size_t np_root_committed;

#ifdef _WIN32
static int np_root_grow(size_t need);
#else
#define np_root_grow(need) 1
#endif

/* The startup stub names the region it reserved and how much of it it committed first. A
 * program whose stub says nothing -- every Linux one -- leaves the base null and never
 * reaches the growth below. */
void neper_mem_root(unsigned char *base, size_t size, size_t committed) {
    np_root_base = base;
    np_root_size = size;
    np_root_committed = committed;
}

#ifdef _WIN32
static int np_reserved_grow(NpArena *a, size_t need);
#else
#define np_reserved_grow(a, need) 1
#endif

static void *np_arena_alloc(NpArena *a, size_t n, size_t alignment) {
    size_t at;
    if (!a || !alignment || (alignment & (alignment - 1))) return 0;
    if (a->off > SIZE_MAX - (alignment - 1)) return 0;
    at = (a->off + alignment - 1) & ~(alignment - 1);
    if (at > a->cap || n > a->cap - at) return 0;
    if (np_root_base && a->base == np_root_base && a->cap == np_root_size &&
        at + n > np_root_committed && !np_root_grow(at + n)) return 0;
    /* A worker's reservation, one page short of the root's capacity (D339): this runtime
       has no commit-on-touch, so it commits as the root does, a chunk at a time, with no
       watermark -- what was committed is the old offset rounded up. */
    if (np_root_base && a->base != np_root_base && a->cap == np_root_size - 4096 &&
        !np_reserved_grow(a, at + n)) return 0;
    a->off = at + n;
    return a->base ? a->base + at : 0;
}

void neper_mem_alloc(void *result, NpArena *arena, size_t count,
                     size_t element_size, size_t alignment) {
    unsigned char *out = (unsigned char *)result;
    void *allocation;
    size_t bytes;
    *(void **)out = 0;
    *(size_t *)(out + 8) = 0;
    *(uint32_t *)(out + 16) = NP_OK;
    if (!arena || arena->off > arena->cap || (!arena->base && arena->cap) ||
        !alignment || (alignment & (alignment - 1))) {
        *(uint32_t *)(out + 16) = NP_EXHAUSTED;
        return;
    }
    if (count == 0) {
        *(void **)out = arena->base ? arena->base + arena->off : 0;
        return;
    }
    if (element_size && count > SIZE_MAX / element_size) {
        *(uint32_t *)(out + 16) = NP_EXHAUSTED;
        return;
    }
    bytes = count * element_size;
    allocation = np_arena_alloc(arena, bytes, alignment);
    if (!allocation && bytes) {
        *(uint32_t *)(out + 16) = NP_EXHAUSTED;
        return;
    }
    *(void **)out = allocation;
    *(size_t *)(out + 8) = count;
}

static void np_copy(void *destination, const void *source, size_t n) {
    unsigned char *d = (unsigned char *)destination;
    const unsigned char *s = (const unsigned char *)source;
    while (n--) *d++ = *s++;
}

void neper_mem_arena_from(void *result, unsigned char *buffer, size_t length) {
    NpArena *arena = (NpArena *)result;
    arena->base = buffer;
    arena->cap = length;
    arena->off = 0;
}

size_t neper_mem_mark(const NpArena *arena) { return arena->off; }

void neper_mem_reset(NpArena *arena, size_t mark) { arena->off = mark; }

void neper_mem_stats(void *result, const NpArena *arena) {
    size_t *out = (size_t *)result;
    out[0] = arena->off;
    out[1] = arena->cap;
}

void neper_os_set_args(const NpStr *args, size_t count) {
    np_args_ptr = args;
    np_args_len = count;
}

void neper_os_args(void *result, NpArena *arena) {
    unsigned char *out = (unsigned char *)result;
    NpStr *copy;
    size_t saved = arena ? arena->off : 0, i;
    *(NpStr *)out = (NpStr){0, 0};
    *(uint32_t *)(out + 16) = NP_OK;
    copy = (NpStr *)np_arena_alloc(arena, np_args_len * sizeof(NpStr), 8);
    if (!copy && np_args_len) { *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    for (i = 0; i < np_args_len; ++i) {
        unsigned char *bytes = (unsigned char *)np_arena_alloc(arena, np_args_ptr[i].len, 1);
        if (!bytes && np_args_ptr[i].len) {
            arena->off = saved;
            *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY;
            return;
        }
        np_copy(bytes, np_args_ptr[i].ptr, np_args_ptr[i].len);
        copy[i].ptr = bytes;
        copy[i].len = np_args_ptr[i].len;
    }
    *(NpStr *)out = (NpStr){(const unsigned char *)copy, np_args_len};
}

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define PSAPI_VERSION 2
#include <psapi.h>

BOOLEAN NTAPI SystemFunction036(PVOID buffer, ULONG length);

#pragma function(memset)
void *memset(void *destination, int value, size_t count) {
    volatile unsigned char *at = (volatile unsigned char *)destination;
    while (count--) *at++ = (unsigned char)value;
    return destination;
}

static uint32_t np_error(DWORD value) {
    switch (value) {
        case ERROR_FILE_NOT_FOUND: case ERROR_PATH_NOT_FOUND: case ERROR_INVALID_DRIVE: return NP_NOT_FOUND;
        case ERROR_ACCESS_DENIED: case ERROR_SHARING_VIOLATION: return NP_DENIED;
        case ERROR_FILE_EXISTS: case ERROR_ALREADY_EXISTS: return NP_EXISTS;
        case ERROR_OPERATION_ABORTED: return NP_INTERRUPTED;
        case ERROR_NOT_ENOUGH_MEMORY: case ERROR_OUTOFMEMORY: return NP_OUT_OF_MEMORY;
        case ERROR_TIMEOUT: case WAIT_TIMEOUT: return NP_TIMEOUT;
        case ERROR_NOT_SUPPORTED: case ERROR_CALL_NOT_IMPLEMENTED: return NP_UNSUPPORTED;
        default: return NP_FAILED;
    }
}

static wchar_t *np_wide(NpStr text) {
    int count;
    wchar_t *out;
    HANDLE heap = GetProcessHeap();
    if (text.len > 0x7ffffffeu) return 0;
    count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)text.ptr,
                                (int)text.len, 0, 0);
    if (!count && text.len) return 0;
    out = (wchar_t *)HeapAlloc(heap, 0, ((size_t)count + 1) * sizeof(wchar_t));
    if (!out) return 0;
    if (count) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)text.ptr,
                                   (int)text.len, out, count);
    out[count] = 0;
    return out;
}

static unsigned char *np_utf8_arena(NpArena *arena, const wchar_t *text, size_t *length) {
    int wide_length = 0, count;
    unsigned char *out;
    while (text[wide_length]) ++wide_length;
    count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, wide_length, 0, 0, 0, 0);
    if (count <= 0 && wide_length) return 0;
    out = (unsigned char *)np_arena_alloc(arena, (size_t)count, 1);
    if (!out && count) return 0;
    if (count && WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, wide_length,
                                     (char *)out, count, 0, 0) <= 0) return 0;
    *length = (size_t)count;
    return out;
}

void neper_os_open(void *result, NpArena *arena, const unsigned char *path, size_t path_len,
                   uintptr_t packed_flags) {
    unsigned char *out = (unsigned char *)result;
    NpStr text = {path, path_len};
    wchar_t *wide = np_wide(text);
    DWORD access = 0, disposition = OPEN_EXISTING;
    HANDLE handle;
    int read_flag = (packed_flags & 0xffu) != 0;
    int write_flag = ((packed_flags >> 8) & 0xffu) != 0;
    int create_flag = ((packed_flags >> 16) & 0xffu) != 0;
    int truncate_flag = ((packed_flags >> 24) & 0xffu) != 0;
    int append_flag = ((packed_flags >> 32) & 0xffu) != 0;
    (void)arena;
    *(uintptr_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (!wide) { *(uint32_t *)(out + 8) = NP_OUT_OF_MEMORY; return; }
    if (read_flag) access |= GENERIC_READ;
    if (write_flag) access |= append_flag ? FILE_APPEND_DATA : GENERIC_WRITE;
    if (create_flag && truncate_flag) disposition = CREATE_ALWAYS;
    else if (create_flag) disposition = OPEN_ALWAYS;
    else if (truncate_flag) disposition = TRUNCATE_EXISTING;
    handle = CreateFileW(wide, access, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                         0, disposition, FILE_ATTRIBUTE_NORMAL, 0);
    HeapFree(GetProcessHeap(), 0, wide);
    if (handle == INVALID_HANDLE_VALUE) { *(uint32_t *)(out + 8) = np_error(GetLastError()); return; }
    *(uintptr_t *)out = (uintptr_t)handle;
}

void neper_os_read(void *result, uintptr_t raw, unsigned char *buffer, size_t length) {
    unsigned char *out = (unsigned char *)result;
    DWORD got = 0, request = length > 0xffffffffu ? 0xffffffffu : (DWORD)length;
    *(size_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (!ReadFile((HANDLE)raw, buffer, request, &got, 0)) {
        /* A writer that is gone is the end of a pipe, not a failure -- as the PE runtime reads it. */
        if (GetLastError() == ERROR_BROKEN_PIPE) return;
        *(uint32_t *)(out + 8) = np_error(GetLastError()); return;
    }
    *(size_t *)out = got;
}

void neper_os_write(void *result, uintptr_t raw, const unsigned char *buffer, size_t length) {
    unsigned char *out = (unsigned char *)result;
    DWORD put = 0, request = length > 0xffffffffu ? 0xffffffffu : (DWORD)length;
    *(size_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (!WriteFile((HANDLE)raw, buffer, request, &put, 0)) { *(uint32_t *)(out + 8) = np_error(GetLastError()); return; }
    *(size_t *)out = put;
}

uint32_t neper_os_close(uintptr_t raw) {
    return CloseHandle((HANDLE)raw) ? NP_OK : np_error(GetLastError());
}

uint32_t neper_os_mkdir(NpArena *arena, const unsigned char *path, size_t path_len) {
    wchar_t *wide = np_wide((NpStr){path, path_len});
    BOOL made;
    (void)arena;
    if (!wide) return NP_OUT_OF_MEMORY;
    made = CreateDirectoryW(wide, 0);
    HeapFree(GetProcessHeap(), 0, wide);
    return made ? NP_OK : np_error(GetLastError());
}

/* `os.replace` (D343): MoveFileExW, replacing when asked and written through when asked. */
uint32_t neper_os_replace(NpArena *arena, const unsigned char *src, size_t src_len, const unsigned char *dst, size_t dst_len, uint8_t overwrite, uint8_t durable) {
    wchar_t *from = np_wide((NpStr){src, src_len});
    wchar_t *to = np_wide((NpStr){dst, dst_len});
    BOOL moved;
    DWORD flags = 0;
    (void)arena;
    if (!from || !to) { if (from) HeapFree(GetProcessHeap(), 0, from); if (to) HeapFree(GetProcessHeap(), 0, to); return NP_OUT_OF_MEMORY; }
    if (overwrite) flags |= MOVEFILE_REPLACE_EXISTING;
    if (durable) flags |= MOVEFILE_WRITE_THROUGH;
    moved = MoveFileExW(from, to, flags);
    HeapFree(GetProcessHeap(), 0, from);
    HeapFree(GetProcessHeap(), 0, to);
    return moved ? NP_OK : np_error(GetLastError());
}

/* Windows keeps one bit of a mode: a file no one may write is read-only. */
uint32_t neper_os_set_mode(NpArena *arena, const unsigned char *path, size_t path_len, uint32_t mode) {
    wchar_t *wide = np_wide((NpStr){path, path_len});
    DWORD current, wanted;
    BOOL set;
    (void)arena;
    if (!wide) return NP_OUT_OF_MEMORY;
    current = GetFileAttributesW(wide);
    if (current == INVALID_FILE_ATTRIBUTES) { HeapFree(GetProcessHeap(), 0, wide); return np_error(GetLastError()); }
    wanted = (mode & 0222u) ? (current & ~(DWORD)FILE_ATTRIBUTE_READONLY) : (current | FILE_ATTRIBUTE_READONLY);
    if (!wanted) wanted = FILE_ATTRIBUTE_NORMAL;
    set = SetFileAttributesW(wide, wanted);
    HeapFree(GetProcessHeap(), 0, wide);
    return set ? NP_OK : np_error(GetLastError());
}

void neper_os_current_dir(void *result, NpArena *arena) {
    unsigned char *out = (unsigned char *)result, *bytes;
    wchar_t *wide;
    DWORD need;
    size_t length = 0;
    *(NpStr *)out = (NpStr){0, 0}; *(uint32_t *)(out + 16) = NP_OK;
    need = GetCurrentDirectoryW(0, 0);
    if (!need) { *(uint32_t *)(out + 16) = np_error(GetLastError()); return; }
    wide = (wchar_t *)HeapAlloc(GetProcessHeap(), 0, need * sizeof(wchar_t));
    if (!wide) { *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    if (!GetCurrentDirectoryW(need, wide)) {
        *(uint32_t *)(out + 16) = np_error(GetLastError());
        HeapFree(GetProcessHeap(), 0, wide);
        return;
    }
    bytes = np_utf8_arena(arena, wide, &length);
    HeapFree(GetProcessHeap(), 0, wide);
    if (!bytes) { *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    *(NpStr *)out = (NpStr){bytes, length};
}

void neper_os_env(void *result, NpArena *arena, const unsigned char *name, size_t name_len) {
    unsigned char *out = (unsigned char *)result, *bytes;
    wchar_t *wide_name = np_wide((NpStr){name, name_len}), *wide_value;
    DWORD need, error;
    size_t length = 0;
    *(NpStr *)out = (NpStr){0, 0}; *(uint32_t *)(out + 16) = NP_OK;
    if (!wide_name) { *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    SetLastError(ERROR_SUCCESS);
    need = GetEnvironmentVariableW(wide_name, 0, 0);
    error = GetLastError();
    if (!need && error == ERROR_ENVVAR_NOT_FOUND) {
        HeapFree(GetProcessHeap(), 0, wide_name);
        *(uint32_t *)(out + 16) = NP_NOT_FOUND;
        return;
    }
    wide_value = (wchar_t *)HeapAlloc(GetProcessHeap(), 0, ((size_t)need + 1) * sizeof(wchar_t));
    if (!wide_value) { HeapFree(GetProcessHeap(), 0, wide_name); *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    if (need) GetEnvironmentVariableW(wide_name, wide_value, need + 1);
    else wide_value[0] = 0;
    HeapFree(GetProcessHeap(), 0, wide_name);
    bytes = np_utf8_arena(arena, wide_value, &length);
    HeapFree(GetProcessHeap(), 0, wide_value);
    if (!bytes && length) { *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    *(NpStr *)out = (NpStr){bytes, length};
}

uint32_t neper_os_random(unsigned char *buffer, size_t length) {
    if (length > 0xffffffffu) return NP_FAILED;
    return SystemFunction036(buffer, (ULONG)length) ? NP_OK : NP_FAILED;
}

void neper_os_create_new(void *result, NpArena *arena, const unsigned char *path, size_t path_len) {
    unsigned char *out = (unsigned char *)result;
    wchar_t *wide = np_wide((NpStr){path, path_len});
    HANDLE handle;
    (void)arena;
    *(uintptr_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (!wide) { *(uint32_t *)(out + 8) = NP_OUT_OF_MEMORY; return; }
    handle = CreateFileW(wide, GENERIC_READ | GENERIC_WRITE, 0, 0, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
    HeapFree(GetProcessHeap(), 0, wide);
    if (handle == INVALID_HANDLE_VALUE) { *(uint32_t *)(out + 8) = np_error(GetLastError()); return; }
    *(uintptr_t *)out = (uintptr_t)handle;
}

void neper_os_stdin(void *result) { *(uintptr_t *)result = (uintptr_t)GetStdHandle(STD_INPUT_HANDLE); }
void neper_os_stdout(void *result) { *(uintptr_t *)result = (uintptr_t)GetStdHandle(STD_OUTPUT_HANDLE); }
void neper_os_stderr(void *result) { *(uintptr_t *)result = (uintptr_t)GetStdHandle(STD_ERROR_HANDLE); }

void neper_os_readdir(void *result, NpArena *arena, const unsigned char *path, size_t path_len) {
    unsigned char *out = (unsigned char *)result;
    NpStr text = {path, path_len};
    wchar_t *wide = np_wide(text), *pattern;
    WIN32_FIND_DATAW item;
    HANDLE find;
    size_t count = 0, capacity = 16, saved = arena ? arena->off : 0, n;
    NpDirEntry *entries;
    *(NpStr *)out = (NpStr){0, 0}; *(uint32_t *)(out + 16) = NP_OK;
    if (!wide) { *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    n = 0; while (wide[n]) ++n;
    pattern = (wchar_t *)HeapAlloc(GetProcessHeap(), 0, (n + 3) * sizeof(wchar_t));
    if (!pattern) { HeapFree(GetProcessHeap(), 0, wide); *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    np_copy(pattern, wide, n * sizeof(wchar_t));
    if (n && pattern[n - 1] != L'\\' && pattern[n - 1] != L'/') pattern[n++] = L'\\';
    pattern[n++] = L'*'; pattern[n] = 0;
    HeapFree(GetProcessHeap(), 0, wide);
    entries = (NpDirEntry *)np_arena_alloc(arena, capacity * sizeof(NpDirEntry), 8);
    if (!entries) { HeapFree(GetProcessHeap(), 0, pattern); *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    find = FindFirstFileW(pattern, &item);
    HeapFree(GetProcessHeap(), 0, pattern);
    if (find == INVALID_HANDLE_VALUE) { arena->off = saved; *(uint32_t *)(out + 16) = np_error(GetLastError()); return; }
    do {
        size_t len;
        unsigned char *name;
        if ((item.cFileName[0] == L'.' && item.cFileName[1] == 0) ||
            (item.cFileName[0] == L'.' && item.cFileName[1] == L'.' && item.cFileName[2] == 0)) continue;
        if (count == capacity) {
            NpDirEntry *grown;
            capacity *= 2;
            grown = (NpDirEntry *)np_arena_alloc(arena, capacity * sizeof(NpDirEntry), 8);
            if (!grown) goto oom;
            np_copy(grown, entries, count * sizeof(NpDirEntry)); entries = grown;
        }
        name = np_utf8_arena(arena, item.cFileName, &len);
        if (!name && item.cFileName[0]) goto oom;
        entries[count].name = (NpStr){name, len};
        entries[count].kind = (item.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? 1 :
                              (item.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ? 2 : 0;
        ++count;
    } while (FindNextFileW(find, &item));
    if (GetLastError() != ERROR_NO_MORE_FILES) { uint32_t error = np_error(GetLastError()); FindClose(find); arena->off = saved; *(uint32_t *)(out + 16) = error; return; }
    FindClose(find); *(NpStr *)out = (NpStr){(const unsigned char *)entries, count}; return;
oom:
    FindClose(find); arena->off = saved; *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY;
}

static size_t np_quoted_size(NpStr arg) {
    size_t i, n = 2, slashes = 0;
    for (i = 0; i < arg.len; ++i) {
        if (arg.ptr[i] == '\\') { ++slashes; ++n; }
        else if (arg.ptr[i] == '"') { n += slashes + 2; slashes = 0; }
        else { ++n; slashes = 0; }
    }
    return n + slashes;
}

static unsigned char *np_quote(unsigned char *out, NpStr arg) {
    size_t i, slashes = 0, k;
    *out++ = '"';
    for (i = 0; i < arg.len; ++i) {
        if (arg.ptr[i] == '\\') { *out++ = '\\'; ++slashes; continue; }
        if (arg.ptr[i] == '"') { for (k = 0; k < slashes + 1; ++k) *out++ = '\\'; *out++ = '"'; }
        else *out++ = arg.ptr[i];
        slashes = 0;
    }
    for (k = 0; k < slashes; ++k) *out++ = '\\';
    *out++ = '"'; return out;
}

void neper_os_spawn(void *result, NpArena *arena, const NpStr *argv, size_t argc, const NpStdio *stdio) {
    unsigned char *out = (unsigned char *)result, *command, *at;
    size_t i, bytes = 1;
    wchar_t *wide;
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    BOOL ok;
    (void)arena;
    *(uintptr_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (!argc) { *(uint32_t *)(out + 8) = NP_NOT_FOUND; return; }
    for (i = 0; i < argc; ++i) bytes += np_quoted_size(argv[i]) + (i != 0);
    command = (unsigned char *)HeapAlloc(GetProcessHeap(), 0, bytes);
    if (!command) { *(uint32_t *)(out + 8) = NP_OUT_OF_MEMORY; return; }
    at = command;
    for (i = 0; i < argc; ++i) { if (i) *at++ = ' '; at = np_quote(at, argv[i]); }
    *at = 0;
    wide = np_wide((NpStr){command, (size_t)(at - command)});
    HeapFree(GetProcessHeap(), 0, command);
    if (!wide) { *(uint32_t *)(out + 8) = NP_OUT_OF_MEMORY; return; }
    for (i = 0; i < sizeof(startup); ++i) ((unsigned char *)&startup)[i] = 0;
    for (i = 0; i < sizeof(process); ++i) ((unsigned char *)&process)[i] = 0;
    startup.cb = sizeof(startup); startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = (HANDLE)stdio->in.raw; startup.hStdOutput = (HANDLE)stdio->out.raw;
    startup.hStdError = (HANDLE)stdio->err.raw;
    SetHandleInformation(startup.hStdInput, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
    SetHandleInformation(startup.hStdOutput, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
    SetHandleInformation(startup.hStdError, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
    for (i = 0; i < stdio->inherit.len; ++i)
        SetHandleInformation((HANDLE)stdio->inherit.ptr[i], HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
    ok = CreateProcessW(0, wide, 0, 0, TRUE, 0, 0, 0, &startup, &process);
    for (i = 0; i < stdio->inherit.len; ++i)
        SetHandleInformation((HANDLE)stdio->inherit.ptr[i], HANDLE_FLAG_INHERIT, 0);
    HeapFree(GetProcessHeap(), 0, wide);
    if (!ok) { *(uint32_t *)(out + 8) = np_error(GetLastError()); return; }
    CloseHandle(process.hThread); *(uintptr_t *)out = (uintptr_t)process.hProcess;
}

void neper_os_wait(void *result, uintptr_t raw) {
    unsigned char *out = (unsigned char *)result; DWORD status, code;
    *(int32_t *)out = -1; *(uint32_t *)(out + 4) = NP_OK;
    status = WaitForSingleObject((HANDLE)raw, INFINITE);
    if (status != WAIT_OBJECT_0 || !GetExitCodeProcess((HANDLE)raw, &code)) {
        *(uint32_t *)(out + 4) = status == WAIT_TIMEOUT ? NP_TIMEOUT : np_error(GetLastError()); return;
    }
    CloseHandle((HANDLE)raw); *(int32_t *)out = (int32_t)code;
}

/* The exit code and the peak working set together (D311): the handle is closed by the
   wait, so the peak has to be read before it goes, in the same call. */
void neper_os_wait_usage(void *result, uintptr_t raw) {
    unsigned char *out = (unsigned char *)result; DWORD status, code; PROCESS_MEMORY_COUNTERS counters;
    *(int32_t *)out = -1; *(size_t *)(out + 8) = 0; *(uint32_t *)(out + 16) = NP_OK;
    status = WaitForSingleObject((HANDLE)raw, INFINITE);
    if (status != WAIT_OBJECT_0 || !GetExitCodeProcess((HANDLE)raw, &code)) {
        *(uint32_t *)(out + 16) = status == WAIT_TIMEOUT ? NP_TIMEOUT : np_error(GetLastError()); return;
    }
    if (GetProcessMemoryInfo((HANDLE)raw, &counters, sizeof counters)) *(size_t *)(out + 8) = counters.PeakWorkingSetSize;
    CloseHandle((HANDLE)raw); *(int32_t *)out = (int32_t)code;
}

void neper_os_peak_memory(void *result) {
    unsigned char *out = (unsigned char *)result; PROCESS_MEMORY_COUNTERS counters;
    *(size_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof counters)) *(size_t *)out = counters.PeakWorkingSetSize;
    else *(uint32_t *)(out + 8) = np_error(GetLastError());
}

void neper_os_exit(int32_t code) { ExitProcess((UINT)code); }

void neper_os_reserve(void *result, size_t n) {
    unsigned char *out = (unsigned char *)result;
    void *p = VirtualAlloc(0, n, MEM_RESERVE, PAGE_NOACCESS);
    *(void **)out = p; *(uint32_t *)(out + 8) = p ? NP_OK : np_error(GetLastError());
}

static int np_root_grow(size_t need) {
    size_t want = (need + NP_ROOT_CHUNK - 1) & ~(NP_ROOT_CHUNK - 1);
    if (want > np_root_size) want = np_root_size;
    if (want <= np_root_committed) return 1;
    if (!VirtualAlloc(np_root_base + np_root_committed, want - np_root_committed,
                      MEM_COMMIT, PAGE_READWRITE)) return 0;
    np_root_committed = want;
    return 1;
}

uint32_t neper_os_commit(unsigned char *p, size_t n) {
    return VirtualAlloc(p, n, MEM_COMMIT, PAGE_READWRITE) ? NP_OK : np_error(GetLastError());
}

/* A reserved arena of the root's capacity (D339): committed a chunk at a time as the root
 * is, with no watermark -- what was committed is the old offset rounded up to a chunk. */
static int np_reserved_grow(NpArena *a, size_t need) {
    size_t have = (a->off + NP_ROOT_CHUNK - 1) & ~(NP_ROOT_CHUNK - 1);
    size_t want = (need + NP_ROOT_CHUNK - 1) & ~(NP_ROOT_CHUNK - 1);
    if (want > a->cap) want = a->cap;
    if (want <= have) return 1;
    return VirtualAlloc(a->base + have, want - have, MEM_COMMIT, PAGE_READWRITE) != 0;
}


/* A thread, run inline (D321): the bootstrap compiler need not be fast, only right, and
   its parallel front end is written so that the workers share nothing they write. */
void neper_os_thread_create(void *result, void *entry, void *ctx, size_t stack) {
    unsigned char *out = (unsigned char *)result;
    (void)stack;
    ((void (*)(void *))entry)(ctx);
    *(uintptr_t *)out = 1; *(uint32_t *)(out + 8) = NP_OK;
}
uint32_t neper_os_thread_join(uintptr_t raw) { (void)raw; return NP_OK; }
/* `os.seek` (D324): the new position, or the error. */
void neper_os_seek(void *result, uintptr_t raw, int64_t off, unsigned char whence) {
    unsigned char *out = (unsigned char *)result; LARGE_INTEGER move, position;
    *(uint64_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    move.QuadPart = off;
    if (whence > 2 || !SetFilePointerEx((HANDLE)raw, move, &position, whence == 0 ? FILE_BEGIN : whence == 1 ? FILE_CURRENT : FILE_END)) {
        *(uint32_t *)(out + 8) = whence > 2 ? NP_UNSUPPORTED : np_error(GetLastError()); return;
    }
    *(uint64_t *)out = (uint64_t)position.QuadPart;
}

void neper_os_clock(void *result, unsigned char clock_kind) {
    unsigned char *out = (unsigned char *)result;
    *(int64_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (clock_kind == 0) {
        FILETIME ft; ULARGE_INTEGER value;
        GetSystemTimeAsFileTime(&ft); value.LowPart = ft.dwLowDateTime; value.HighPart = ft.dwHighDateTime;
        *(int64_t *)out = (int64_t)((value.QuadPart - UINT64_C(116444736000000000)) * 100);
    } else if (clock_kind == 1) {
        LARGE_INTEGER now, frequency;
        if (!QueryPerformanceCounter(&now) || !QueryPerformanceFrequency(&frequency)) { *(uint32_t *)(out + 8) = NP_FAILED; return; }
        *(int64_t *)out = (now.QuadPart / frequency.QuadPart) * INT64_C(1000000000) +
                          (now.QuadPart % frequency.QuadPart) * INT64_C(1000000000) / frequency.QuadPart;
    } else *(uint32_t *)(out + 8) = NP_UNSUPPORTED;
}

#else
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <sys/random.h>
#include <stdlib.h>
#include <string.h>

static uint32_t np_error(int value) {
    switch (value) {
        case ENOENT: case ENOTDIR: return NP_NOT_FOUND;
        case EACCES: case EPERM: return NP_DENIED;
        case EEXIST: return NP_EXISTS;
        case EINTR: return NP_INTERRUPTED;
        case ENOMEM: return NP_OUT_OF_MEMORY;
        case ETIMEDOUT: return NP_TIMEOUT;
        case EAGAIN: return NP_WOULD_BLOCK;
        case ENOSYS: case ENOTSUP: return NP_UNSUPPORTED;
        default: return NP_FAILED;
    }
}

static char *np_c_string_arena(NpArena *arena, NpStr value) {
    char *out = (char *)np_arena_alloc(arena, value.len + 1, 1);
    if (!out) return 0;
    np_copy(out, value.ptr, value.len); out[value.len] = 0; return out;
}

void neper_os_open(void *result, NpArena *arena, const unsigned char *path, size_t path_len,
                   uintptr_t packed_flags) {
    unsigned char *out = (unsigned char *)result;
    size_t saved = arena ? arena->off : 0;
    char *name = np_c_string_arena(arena, (NpStr){path, path_len});
    int flags = 0, fd;
    int r = (packed_flags & 0xffu) != 0, w = ((packed_flags >> 8) & 0xffu) != 0;
    *(uintptr_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (!name) { *(uint32_t *)(out + 8) = NP_OUT_OF_MEMORY; return; }
    flags |= r && w ? O_RDWR : w ? O_WRONLY : O_RDONLY;
    if ((packed_flags >> 16) & 0xffu) flags |= O_CREAT;
    if ((packed_flags >> 24) & 0xffu) flags |= O_TRUNC;
    if ((packed_flags >> 32) & 0xffu) flags |= O_APPEND;
    fd = open(name, flags, 0666); arena->off = saved;
    if (fd < 0) { *(uint32_t *)(out + 8) = np_error(errno); return; }
    *(uintptr_t *)out = (uintptr_t)fd;
}

void neper_os_read(void *result, uintptr_t raw, unsigned char *buffer, size_t length) {
    unsigned char *out = (unsigned char *)result; ssize_t got = read((int)raw, buffer, length);
    *(size_t *)out = 0; *(uint32_t *)(out + 8) = got < 0 ? np_error(errno) : NP_OK;
    if (got >= 0) *(size_t *)out = (size_t)got;
}

void neper_os_write(void *result, uintptr_t raw, const unsigned char *buffer, size_t length) {
    unsigned char *out = (unsigned char *)result; ssize_t put = write((int)raw, buffer, length);
    *(size_t *)out = 0; *(uint32_t *)(out + 8) = put < 0 ? np_error(errno) : NP_OK;
    if (put >= 0) *(size_t *)out = (size_t)put;
}

uint32_t neper_os_close(uintptr_t raw) { return close((int)raw) == 0 ? NP_OK : np_error(errno); }
uint32_t neper_os_mkdir(NpArena *arena, const unsigned char *path, size_t path_len) {
    size_t saved = arena ? arena->off : 0;
    char *name = np_c_string_arena(arena, (NpStr){path, path_len});
    int made;
    if (!name) return NP_OUT_OF_MEMORY;
    made = mkdir(name, 0777); arena->off = saved;
    return made == 0 ? NP_OK : np_error(errno);
}

/* `os.replace` (D343): rename(2), which replaces; without `overwrite` a link-then-unlink
   that refuses an existing destination; `durable` syncs the destination's directory. */
uint32_t neper_os_replace(NpArena *arena, const unsigned char *src, size_t src_len, const unsigned char *dst, size_t dst_len, uint8_t overwrite, uint8_t durable) {
    size_t saved = arena ? arena->off : 0;
    char *from = np_c_string_arena(arena, (NpStr){src, src_len});
    char *to = from ? np_c_string_arena(arena, (NpStr){dst, dst_len}) : 0;
    int result;
    if (!from || !to) { if (arena) arena->off = saved; return NP_OUT_OF_MEMORY; }
    if (overwrite) {
        result = rename(from, to);
    } else {
        result = link(from, to);
        if (result == 0) result = unlink(from);
    }
    if (result == 0 && durable) {
        char *slash = strrchr(to, '/');
        int dir;
        if (slash) { *slash = 0; dir = open(to, O_RDONLY); } else { dir = open(".", O_RDONLY); }
        if (dir >= 0) { fsync(dir); close(dir); }
    }
    arena->off = saved;
    return result == 0 ? NP_OK : np_error(errno);
}

uint32_t neper_os_set_mode(NpArena *arena, const unsigned char *path, size_t path_len, uint32_t mode) {
    size_t saved = arena ? arena->off : 0;
    char *name = np_c_string_arena(arena, (NpStr){path, path_len});
    int changed;
    if (!name) return NP_OUT_OF_MEMORY;
    changed = chmod(name, (mode_t)(mode & 07777u)); arena->off = saved;
    return changed == 0 ? NP_OK : np_error(errno);
}

void neper_os_current_dir(void *result, NpArena *arena) {
    unsigned char *out = (unsigned char *)result;
    size_t capacity = 256, saved = arena ? arena->off : 0, length;
    *(NpStr *)out = (NpStr){0, 0}; *(uint32_t *)(out + 16) = NP_OK;
    for (;;) {
        char *buffer = (char *)np_arena_alloc(arena, capacity, 1);
        if (!buffer) { *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
        if (getcwd(buffer, capacity)) {
            for (length = 0; buffer[length]; ++length) {}
            *(NpStr *)out = (NpStr){(unsigned char *)buffer, length};
            return;
        }
        arena->off = saved;
        if (errno != ERANGE) { *(uint32_t *)(out + 16) = np_error(errno); return; }
        capacity *= 2;
    }
}

void neper_os_env(void *result, NpArena *arena, const unsigned char *name, size_t name_len) {
    unsigned char *out = (unsigned char *)result, *copy;
    char *named = np_c_string_arena(arena, (NpStr){name, name_len});
    char *value;
    size_t length = 0;
    *(NpStr *)out = (NpStr){0, 0}; *(uint32_t *)(out + 16) = NP_OK;
    if (!named) { *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    value = getenv(named);
    if (!value) { *(uint32_t *)(out + 16) = NP_NOT_FOUND; return; }
    while (value[length]) ++length;
    copy = (unsigned char *)np_arena_alloc(arena, length, 1);
    if (!copy && length) { *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    np_copy(copy, value, length);
    *(NpStr *)out = (NpStr){copy, length};
}

uint32_t neper_os_random(unsigned char *buffer, size_t length) {
    size_t filled = 0;
    while (filled < length) {
        ssize_t got = getrandom(buffer + filled, length - filled, 0);
        if (got < 0) { if (errno == EINTR) continue; return np_error(errno); }
        if (got == 0) return NP_FAILED;
        filled += (size_t)got;
    }
    return NP_OK;
}

void neper_os_create_new(void *result, NpArena *arena, const unsigned char *path, size_t path_len) {
    unsigned char *out = (unsigned char *)result;
    size_t saved = arena ? arena->off : 0;
    char *name = np_c_string_arena(arena, (NpStr){path, path_len});
    int fd;
    *(uintptr_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (!name) { *(uint32_t *)(out + 8) = NP_OUT_OF_MEMORY; return; }
    fd = open(name, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    arena->off = saved;
    if (fd < 0) { *(uint32_t *)(out + 8) = np_error(errno); return; }
    *(uintptr_t *)out = (uintptr_t)fd;
}

void neper_os_stdin(void *result) { *(uintptr_t *)result = 0; }
void neper_os_stdout(void *result) { *(uintptr_t *)result = 1; }
void neper_os_stderr(void *result) { *(uintptr_t *)result = 2; }

void neper_os_readdir(void *result, NpArena *arena, const unsigned char *path, size_t path_len) {
    unsigned char *out = (unsigned char *)result;
    size_t saved = arena ? arena->off : 0, count = 0, capacity = 16;
    char *name = np_c_string_arena(arena, (NpStr){path, path_len});
    NpDirEntry *entries;
    DIR *dir; struct dirent *item;
    *(NpStr *)out = (NpStr){0, 0}; *(uint32_t *)(out + 16) = NP_OK;
    if (!name) { *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY; return; }
    dir = opendir(name); arena->off = saved;
    if (!dir) { *(uint32_t *)(out + 16) = np_error(errno); return; }
    entries = (NpDirEntry *)np_arena_alloc(arena, capacity * sizeof(NpDirEntry), 8);
    if (!entries) goto oom;
    errno = 0;
    while ((item = readdir(dir)) != 0) {
        size_t len = 0; unsigned char *bytes; NpDirEntry *grown;
        if ((item->d_name[0] == '.' && item->d_name[1] == 0) ||
            (item->d_name[0] == '.' && item->d_name[1] == '.' && item->d_name[2] == 0)) continue;
        while (item->d_name[len]) ++len;
        if (count == capacity) {
            capacity *= 2; grown = (NpDirEntry *)np_arena_alloc(arena, capacity * sizeof(NpDirEntry), 8);
            if (!grown) goto oom;
            np_copy(grown, entries, count * sizeof(NpDirEntry)); entries = grown;
        }
        bytes = (unsigned char *)np_arena_alloc(arena, len, 1); if (!bytes && len) goto oom;
        np_copy(bytes, item->d_name, len); entries[count].name = (NpStr){bytes, len};
        entries[count].kind = item->d_type == DT_REG ? 0 : item->d_type == DT_DIR ? 1 : item->d_type == DT_LNK ? 2 : 3;
        ++count;
    }
    if (errno) { uint32_t error = np_error(errno); closedir(dir); arena->off = saved; *(uint32_t *)(out + 16) = error; return; }
    closedir(dir); *(NpStr *)out = (NpStr){(const unsigned char *)entries, count}; return;
oom:
    closedir(dir); arena->off = saved; *(uint32_t *)(out + 16) = NP_OUT_OF_MEMORY;
}

void neper_os_spawn(void *result, NpArena *arena, const NpStr *argv, size_t argc, const NpStdio *stdio) {
    unsigned char *out = (unsigned char *)result;
    size_t saved = arena ? arena->off : 0, i;
    char **native; pid_t pid;
    *(uintptr_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (!argc) { *(uint32_t *)(out + 8) = NP_NOT_FOUND; return; }
    native = (char **)np_arena_alloc(arena, (argc + 1) * sizeof(char *), 8);
    if (!native) { *(uint32_t *)(out + 8) = NP_OUT_OF_MEMORY; return; }
    for (i = 0; i < argc; ++i) if (!(native[i] = np_c_string_arena(arena, argv[i]))) { arena->off = saved; *(uint32_t *)(out + 8) = NP_OUT_OF_MEMORY; return; }
    native[argc] = 0; pid = fork();
    if (pid == 0) {
        if ((int)stdio->in.raw != 0) dup2((int)stdio->in.raw, 0);
        if ((int)stdio->out.raw != 1) dup2((int)stdio->out.raw, 1);
        if ((int)stdio->err.raw != 2) dup2((int)stdio->err.raw, 2);
        execvp(native[0], native); _exit(127);
    }
    arena->off = saved;
    if (pid < 0) { *(uint32_t *)(out + 8) = np_error(errno); return; }
    *(uintptr_t *)out = (uintptr_t)pid;
}

void neper_os_wait(void *result, uintptr_t raw) {
    unsigned char *out = (unsigned char *)result; int status;
    *(int32_t *)out = -1; *(uint32_t *)(out + 4) = NP_OK;
    if (waitpid((pid_t)raw, &status, 0) < 0) { *(uint32_t *)(out + 4) = np_error(errno); return; }
    *(int32_t *)out = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}

void neper_os_wait_usage(void *result, uintptr_t raw) {
    unsigned char *out = (unsigned char *)result; int status; struct rusage usage;
    *(int32_t *)out = -1; *(size_t *)(out + 8) = 0; *(uint32_t *)(out + 16) = NP_OK;
    if (wait4((pid_t)raw, &status, 0, &usage) < 0) { *(uint32_t *)(out + 16) = np_error(errno); return; }
    *(int32_t *)out = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    *(size_t *)(out + 8) = (size_t)usage.ru_maxrss * 1024;
}

void neper_os_peak_memory(void *result) {
    unsigned char *out = (unsigned char *)result; struct rusage usage;
    *(size_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (getrusage(RUSAGE_SELF, &usage) < 0) { *(uint32_t *)(out + 8) = np_error(errno); return; }
    *(size_t *)out = (size_t)usage.ru_maxrss * 1024;
}

void neper_os_exit(int32_t code) { _exit(code); }

void neper_os_reserve(void *result, size_t n) {
    unsigned char *out = (unsigned char *)result; void *p = mmap(0, n, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    *(void **)out = p == MAP_FAILED ? 0 : p; *(uint32_t *)(out + 8) = p == MAP_FAILED ? np_error(errno) : NP_OK;
}

uint32_t neper_os_commit(unsigned char *p, size_t n) { return mprotect(p, n, PROT_READ | PROT_WRITE) == 0 ? NP_OK : np_error(errno); }


/* A thread, run inline (D321): the bootstrap compiler need not be fast, only right, and
   its parallel front end is written so that the workers share nothing they write. */
void neper_os_thread_create(void *result, void *entry, void *ctx, size_t stack) {
    unsigned char *out = (unsigned char *)result;
    (void)stack;
    ((void (*)(void *))entry)(ctx);
    *(uintptr_t *)out = 1; *(uint32_t *)(out + 8) = NP_OK;
}
uint32_t neper_os_thread_join(uintptr_t raw) { (void)raw; return NP_OK; }
/* `os.seek` (D324): the new position, or the error. */
void neper_os_seek(void *result, uintptr_t raw, int64_t off, unsigned char whence) {
    unsigned char *out = (unsigned char *)result; off_t position;
    *(uint64_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (whence > 2) { *(uint32_t *)(out + 8) = NP_UNSUPPORTED; return; }
    position = lseek((int)raw, (off_t)off, whence == 0 ? SEEK_SET : whence == 1 ? SEEK_CUR : SEEK_END);
    if (position < 0) { *(uint32_t *)(out + 8) = np_error(errno); return; }
    *(uint64_t *)out = (uint64_t)position;
}

void neper_os_clock(void *result, unsigned char clock_kind) {
    unsigned char *out = (unsigned char *)result; struct timespec value; clockid_t id;
    *(int64_t *)out = 0; *(uint32_t *)(out + 8) = NP_OK;
    if (clock_kind == 0) id = CLOCK_REALTIME; else if (clock_kind == 1) id = CLOCK_MONOTONIC;
    else { *(uint32_t *)(out + 8) = NP_UNSUPPORTED; return; }
    if (clock_gettime(id, &value) != 0) { *(uint32_t *)(out + 8) = np_error(errno); return; }
    *(int64_t *)out = (int64_t)value.tv_sec * INT64_C(1000000000) + value.tv_nsec;
}
#endif
