// More than a hundred `@import`s in one Linux image (D1594). The dynamic image keeps the
// loader's metadata -- .dynstr, .dynsym and .rela.dyn at 24 bytes a symbol, and DT_HASH --
// ahead of the code, and that used to be capped at the page before 4096: about 48 imports,
// past which the link failed with `link_elf.InvalidExecutable`. The code now starts on the
// first page past the metadata.
//
// An import that is never called is not in the image (D128), so every one here is called,
// and its answer checked: 90 from libc.so.6 and 48 from libm.so.6. Last, the fixture reads
// its own ELF header and checks what the change is for: the entry point lies past the first
// page, and the first loaded segment covers everything ahead of it. Each check has its own
// exit code.
use e.mem
use e.os

// --- libc: <ctype.h> and <wctype.h>
@import("libc.so.6", "isalnum")
extern fn c_isalnum(c: i32) -> i32
@import("libc.so.6", "isalpha")
extern fn c_isalpha(c: i32) -> i32
@import("libc.so.6", "isblank")
extern fn c_isblank(c: i32) -> i32
@import("libc.so.6", "iscntrl")
extern fn c_iscntrl(c: i32) -> i32
@import("libc.so.6", "isdigit")
extern fn c_isdigit(c: i32) -> i32
@import("libc.so.6", "isgraph")
extern fn c_isgraph(c: i32) -> i32
@import("libc.so.6", "islower")
extern fn c_islower(c: i32) -> i32
@import("libc.so.6", "isprint")
extern fn c_isprint(c: i32) -> i32
@import("libc.so.6", "ispunct")
extern fn c_ispunct(c: i32) -> i32
@import("libc.so.6", "isspace")
extern fn c_isspace(c: i32) -> i32
@import("libc.so.6", "isupper")
extern fn c_isupper(c: i32) -> i32
@import("libc.so.6", "isxdigit")
extern fn c_isxdigit(c: i32) -> i32
@import("libc.so.6", "isascii")
extern fn c_isascii(c: i32) -> i32
@import("libc.so.6", "toascii")
extern fn c_toascii(c: i32) -> i32
@import("libc.so.6", "tolower")
extern fn c_tolower(c: i32) -> i32
@import("libc.so.6", "toupper")
extern fn c_toupper(c: i32) -> i32
@import("libc.so.6", "towlower")
extern fn c_towlower(c: u32) -> u32
@import("libc.so.6", "towupper")
extern fn c_towupper(c: u32) -> u32
@import("libc.so.6", "iswalpha")
extern fn c_iswalpha(c: u32) -> i32
@import("libc.so.6", "iswdigit")
extern fn c_iswdigit(c: u32) -> i32
@import("libc.so.6", "iswspace")
extern fn c_iswspace(c: u32) -> i32
@import("libc.so.6", "iswupper")
extern fn c_iswupper(c: u32) -> i32
@import("libc.so.6", "iswlower")
extern fn c_iswlower(c: u32) -> i32
@import("libc.so.6", "iswalnum")
extern fn c_iswalnum(c: u32) -> i32
@import("libc.so.6", "iswxdigit")
extern fn c_iswxdigit(c: u32) -> i32
@import("libc.so.6", "iswpunct")
extern fn c_iswpunct(c: u32) -> i32

// --- libc: <string.h> and <strings.h>; every pointer crosses as its address
@import("libc.so.6", "strlen")
extern fn c_strlen(s: usize) -> usize
@import("libc.so.6", "strnlen")
extern fn c_strnlen(s: usize, most: usize) -> usize
@import("libc.so.6", "strcmp")
extern fn c_strcmp(a: usize, b: usize) -> i32
@import("libc.so.6", "strncmp")
extern fn c_strncmp(a: usize, b: usize, n: usize) -> i32
@import("libc.so.6", "strcasecmp")
extern fn c_strcasecmp(a: usize, b: usize) -> i32
@import("libc.so.6", "strncasecmp")
extern fn c_strncasecmp(a: usize, b: usize, n: usize) -> i32
@import("libc.so.6", "strchr")
extern fn c_strchr(s: usize, c: i32) -> usize
@import("libc.so.6", "strrchr")
extern fn c_strrchr(s: usize, c: i32) -> usize
@import("libc.so.6", "strchrnul")
extern fn c_strchrnul(s: usize, c: i32) -> usize
@import("libc.so.6", "index")
extern fn c_index(s: usize, c: i32) -> usize
@import("libc.so.6", "rindex")
extern fn c_rindex(s: usize, c: i32) -> usize
@import("libc.so.6", "strstr")
extern fn c_strstr(hay: usize, needle: usize) -> usize
@import("libc.so.6", "strcasestr")
extern fn c_strcasestr(hay: usize, needle: usize) -> usize
@import("libc.so.6", "strspn")
extern fn c_strspn(s: usize, accept: usize) -> usize
@import("libc.so.6", "strcspn")
extern fn c_strcspn(s: usize, reject: usize) -> usize
@import("libc.so.6", "strpbrk")
extern fn c_strpbrk(s: usize, accept: usize) -> usize
@import("libc.so.6", "strcpy")
extern fn c_strcpy(dst: usize, src: usize) -> usize
@import("libc.so.6", "strncpy")
extern fn c_strncpy(dst: usize, src: usize, n: usize) -> usize
@import("libc.so.6", "stpcpy")
extern fn c_stpcpy(dst: usize, src: usize) -> usize
@import("libc.so.6", "stpncpy")
extern fn c_stpncpy(dst: usize, src: usize, n: usize) -> usize
@import("libc.so.6", "strcat")
extern fn c_strcat(dst: usize, src: usize) -> usize
@import("libc.so.6", "strncat")
extern fn c_strncat(dst: usize, src: usize, n: usize) -> usize
@import("libc.so.6", "strcoll")
extern fn c_strcoll(a: usize, b: usize) -> i32
@import("libc.so.6", "strxfrm")
extern fn c_strxfrm(dst: usize, src: usize, n: usize) -> usize
@import("libc.so.6", "strverscmp")
extern fn c_strverscmp(a: usize, b: usize) -> i32
@import("libc.so.6", "strtok_r")
extern fn c_strtok_r(s: usize, delim: usize, save: *usize) -> usize
@import("libc.so.6", "strsep")
extern fn c_strsep(s: *usize, delim: usize) -> usize
@import("libc.so.6", "strdup")
extern fn c_strdup(s: usize) -> usize
@import("libc.so.6", "strndup")
extern fn c_strndup(s: usize, n: usize) -> usize
@import("libc.so.6", "memcmp")
extern fn c_memcmp(a: usize, b: usize, n: usize) -> i32
@import("libc.so.6", "memchr")
extern fn c_memchr(s: usize, c: i32, n: usize) -> usize
@import("libc.so.6", "memrchr")
extern fn c_memrchr(s: usize, c: i32, n: usize) -> usize
@import("libc.so.6", "rawmemchr")
extern fn c_rawmemchr(s: usize, c: i32) -> usize
@import("libc.so.6", "memmem")
extern fn c_memmem(hay: usize, hay_len: usize, needle: usize, needle_len: usize) -> usize
@import("libc.so.6", "memset")
extern fn c_memset(s: usize, c: i32, n: usize) -> usize
@import("libc.so.6", "memcpy")
extern fn c_memcpy(dst: usize, src: usize, n: usize) -> usize
@import("libc.so.6", "memmove")
extern fn c_memmove(dst: usize, src: usize, n: usize) -> usize
@import("libc.so.6", "ffs")
extern fn c_ffs(v: i32) -> i32
@import("libc.so.6", "ffsl")
extern fn c_ffsl(v: i64) -> i32
@import("libc.so.6", "ffsll")
extern fn c_ffsll(v: i64) -> i32

// --- libc: <stdlib.h>, memory and the process
@import("libc.so.6", "abs")
extern fn c_abs(v: i32) -> i32
@import("libc.so.6", "labs")
extern fn c_labs(v: i64) -> i64
@import("libc.so.6", "llabs")
extern fn c_llabs(v: i64) -> i64
@import("libc.so.6", "atoi")
extern fn c_atoi(s: usize) -> i32
@import("libc.so.6", "atol")
extern fn c_atol(s: usize) -> i64
@import("libc.so.6", "atoll")
extern fn c_atoll(s: usize) -> i64
@import("libc.so.6", "strtol")
extern fn c_strtol(s: usize, end: usize, base: i32) -> i64
@import("libc.so.6", "strtoul")
extern fn c_strtoul(s: usize, end: usize, base: i32) -> u64
@import("libc.so.6", "strtoll")
extern fn c_strtoll(s: usize, end: usize, base: i32) -> i64
@import("libc.so.6", "strtoull")
extern fn c_strtoull(s: usize, end: usize, base: i32) -> u64
@import("libc.so.6", "rand_r")
extern fn c_rand_r(seed: *u32) -> i32
@import("libc.so.6", "malloc")
extern fn c_malloc(n: usize) -> usize
@import("libc.so.6", "calloc")
extern fn c_calloc(count: usize, size: usize) -> usize
@import("libc.so.6", "realloc")
extern fn c_realloc(p: usize, n: usize) -> usize
@import("libc.so.6", "free")
extern fn c_free(p: usize)
@import("libc.so.6", "getpid")
extern fn c_getpid() -> i32
@import("libc.so.6", "getppid")
extern fn c_getppid() -> i32
@import("libc.so.6", "getuid")
extern fn c_getuid() -> u32
@import("libc.so.6", "geteuid")
extern fn c_geteuid() -> u32
@import("libc.so.6", "getgid")
extern fn c_getgid() -> u32
@import("libc.so.6", "getegid")
extern fn c_getegid() -> u32
@import("libc.so.6", "getpagesize")
extern fn c_getpagesize() -> i32
@import("libc.so.6", "sysconf")
extern fn c_sysconf(name: i32) -> i64
@import("libc.so.6", "time")
extern fn c_time(out: usize) -> i64

// --- libm
@import("libm.so.6", "sqrt")
extern fn m_sqrt(x: f64) -> f64
@import("libm.so.6", "cbrt")
extern fn m_cbrt(x: f64) -> f64
@import("libm.so.6", "floor")
extern fn m_floor(x: f64) -> f64
@import("libm.so.6", "ceil")
extern fn m_ceil(x: f64) -> f64
@import("libm.so.6", "trunc")
extern fn m_trunc(x: f64) -> f64
@import("libm.so.6", "round")
extern fn m_round(x: f64) -> f64
@import("libm.so.6", "rint")
extern fn m_rint(x: f64) -> f64
@import("libm.so.6", "nearbyint")
extern fn m_nearbyint(x: f64) -> f64
@import("libm.so.6", "lround")
extern fn m_lround(x: f64) -> i64
@import("libm.so.6", "llround")
extern fn m_llround(x: f64) -> i64
@import("libm.so.6", "fabs")
extern fn m_fabs(x: f64) -> f64
@import("libm.so.6", "fmin")
extern fn m_fmin(x: f64, y: f64) -> f64
@import("libm.so.6", "fmax")
extern fn m_fmax(x: f64, y: f64) -> f64
@import("libm.so.6", "fdim")
extern fn m_fdim(x: f64, y: f64) -> f64
@import("libm.so.6", "fmod")
extern fn m_fmod(x: f64, y: f64) -> f64
@import("libm.so.6", "remainder")
extern fn m_remainder(x: f64, y: f64) -> f64
@import("libm.so.6", "copysign")
extern fn m_copysign(x: f64, y: f64) -> f64
@import("libm.so.6", "nextafter")
extern fn m_nextafter(x: f64, y: f64) -> f64
@import("libm.so.6", "fma")
extern fn m_fma(x: f64, y: f64, z: f64) -> f64
@import("libm.so.6", "hypot")
extern fn m_hypot(x: f64, y: f64) -> f64
@import("libm.so.6", "pow")
extern fn m_pow(x: f64, y: f64) -> f64
@import("libm.so.6", "ldexp")
extern fn m_ldexp(x: f64, e: i32) -> f64
@import("libm.so.6", "scalbn")
extern fn m_scalbn(x: f64, e: i32) -> f64
@import("libm.so.6", "ilogb")
extern fn m_ilogb(x: f64) -> i32
@import("libm.so.6", "logb")
extern fn m_logb(x: f64) -> f64
@import("libm.so.6", "exp")
extern fn m_exp(x: f64) -> f64
@import("libm.so.6", "exp2")
extern fn m_exp2(x: f64) -> f64
@import("libm.so.6", "expm1")
extern fn m_expm1(x: f64) -> f64
@import("libm.so.6", "log")
extern fn m_log(x: f64) -> f64
@import("libm.so.6", "log2")
extern fn m_log2(x: f64) -> f64
@import("libm.so.6", "log10")
extern fn m_log10(x: f64) -> f64
@import("libm.so.6", "log1p")
extern fn m_log1p(x: f64) -> f64
@import("libm.so.6", "sin")
extern fn m_sin(x: f64) -> f64
@import("libm.so.6", "cos")
extern fn m_cos(x: f64) -> f64
@import("libm.so.6", "tan")
extern fn m_tan(x: f64) -> f64
@import("libm.so.6", "asin")
extern fn m_asin(x: f64) -> f64
@import("libm.so.6", "acos")
extern fn m_acos(x: f64) -> f64
@import("libm.so.6", "atan")
extern fn m_atan(x: f64) -> f64
@import("libm.so.6", "atan2")
extern fn m_atan2(y: f64, x: f64) -> f64
@import("libm.so.6", "sinh")
extern fn m_sinh(x: f64) -> f64
@import("libm.so.6", "cosh")
extern fn m_cosh(x: f64) -> f64
@import("libm.so.6", "tanh")
extern fn m_tanh(x: f64) -> f64
@import("libm.so.6", "asinh")
extern fn m_asinh(x: f64) -> f64
@import("libm.so.6", "acosh")
extern fn m_acosh(x: f64) -> f64
@import("libm.so.6", "atanh")
extern fn m_atanh(x: f64) -> f64
@import("libm.so.6", "erf")
extern fn m_erf(x: f64) -> f64
@import("libm.so.6", "erfc")
extern fn m_erfc(x: f64) -> f64
@import("libm.so.6", "tgamma")
extern fn m_tgamma(x: f64) -> f64

fn want(holds: bool, code: i32) {
    if !holds { os.exit(code) }
}

// Within a billionth: the answers checked below are exact for these inputs in any libm
// worth the name, and the slack only forgives the ones that are merely correctly rounded.
fn near(x: f64, y: f64) -> bool {
    var d = x - y
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= 0.000000001f64
}

// A NUL-terminated copy of `s` in `buf`, answered as its address.
fn c_text(buf: []u8, s: str) -> usize {
    var i = 0usize
    while i < s.len {
        buf[i] = s[i]
        i += 1usize
    }
    buf[s.len] = 0u8
    ret mem.address_of(&buf[0usize])
}

fn ctype() {
    want(c_isalnum(97i32) != 0i32 && c_isalnum(33i32) == 0i32, 10i32)
    want(c_isalpha(90i32) != 0i32 && c_isalpha(48i32) == 0i32, 11i32)
    want(c_isblank(32i32) != 0i32 && c_isblank(65i32) == 0i32, 12i32)
    want(c_iscntrl(7i32) != 0i32 && c_iscntrl(65i32) == 0i32, 13i32)
    want(c_isdigit(55i32) != 0i32 && c_isdigit(97i32) == 0i32, 14i32)
    want(c_isgraph(33i32) != 0i32 && c_isgraph(32i32) == 0i32, 15i32)
    want(c_islower(113i32) != 0i32 && c_islower(81i32) == 0i32, 16i32)
    want(c_isprint(32i32) != 0i32 && c_isprint(10i32) == 0i32, 17i32)
    want(c_ispunct(44i32) != 0i32 && c_ispunct(65i32) == 0i32, 18i32)
    want(c_isspace(9i32) != 0i32 && c_isspace(95i32) == 0i32, 19i32)
    want(c_isupper(81i32) != 0i32 && c_isupper(113i32) == 0i32, 20i32)
    want(c_isxdigit(70i32) != 0i32 && c_isxdigit(71i32) == 0i32, 21i32)
    want(c_isascii(127i32) != 0i32 && c_isascii(200i32) == 0i32, 22i32)
    want(c_toascii(193i32) == 65i32, 23i32)
    want(c_tolower(65i32) == 97i32 && c_toupper(97i32) == 65i32, 24i32)
    want(c_towlower(66u32) == 98u32 && c_towupper(98u32) == 66u32, 25i32)
    want(c_iswalpha(120u32) != 0i32 && c_iswdigit(51u32) != 0i32 && c_iswspace(32u32) != 0i32, 26i32)
    want(c_iswupper(88u32) != 0i32 && c_iswlower(120u32) != 0i32 && c_iswalnum(57u32) != 0i32, 27i32)
    want(c_iswxdigit(97u32) != 0i32 && c_iswpunct(33u32) != 0i32 && c_iswalpha(33u32) == 0i32, 28i32)
}

fn strings() {
    var hello: [32]u8 = zero
    var world: [32]u8 = zero
    var other: [32]u8 = zero
    var out: [64]u8 = zero
    let h = c_text(hello[0..], "hello, world")
    let w = c_text(world[0..], "o")
    want(c_strlen(h) == 12usize && c_strnlen(h, 5usize) == 5usize, 30i32)
    let o = c_text(other[0..], "hello, there")
    want(c_strcmp(h, o) > 0i32 && c_strncmp(h, o, 7usize) == 0i32, 31i32)
    let upper = c_text(other[0..], "HELLO, WORLD")
    want(c_strcasecmp(h, upper) == 0i32 && c_strncasecmp(h, upper, 3usize) == 0i32, 32i32)
    // "hello, world": the first `o` is at 4, the last at 8.
    want(c_strchr(h, 111i32) == h + 4usize && c_strrchr(h, 111i32) == h + 8usize, 33i32)
    want(c_index(h, 111i32) == h + 4usize && c_rindex(h, 111i32) == h + 8usize, 34i32)
    want(c_strchrnul(h, 122i32) == h + 12usize, 35i32)
    let needle = c_text(other[0..], "wor")
    want(c_strstr(h, needle) == h + 7usize, 36i32)
    let shout = c_text(other[0..], "WOR")
    want(c_strcasestr(h, shout) == h + 7usize, 37i32)
    let letters = c_text(other[0..], "leh")
    want(c_strspn(h, letters) == 4usize, 38i32)
    let punct = c_text(other[0..], ",!")
    want(c_strcspn(h, punct) == 5usize && c_strpbrk(h, punct) == h + 5usize, 39i32)
    let dst = mem.address_of(&out[0usize])
    want(c_strcpy(dst, h) == dst && c_strcmp(dst, h) == 0i32, 40i32)
    want(c_strcat(dst, w) == dst && c_strlen(dst) == 13usize, 41i32)
    want(c_strncat(dst, w, 1usize) == dst && c_strlen(dst) == 14usize, 42i32)
    want(c_stpcpy(dst, w) == dst + 1usize, 43i32)
    want(c_strncpy(dst, h, 20usize) == dst && out[19usize] == 0u8 && c_strlen(dst) == 12usize, 44i32)
    want(c_stpncpy(dst, h, 3usize) == dst + 3usize, 45i32)
    let apple = c_text(other[0..], "apple")
    let banana = c_text(world[0..], "banana")
    want(c_strcoll(apple, banana) < 0i32, 46i32)
    want(c_strxfrm(dst, apple, 32usize) == 5usize, 47i32)
    let v9 = c_text(other[0..], "file9")
    let v10 = c_text(world[0..], "file10")
    want(c_strverscmp(v9, v10) < 0i32, 48i32)
    // strtok_r and strsep walk "a,b,,c".
    let list = c_text(out[0..], "a,b,,c")
    let comma = c_text(other[0..], ",")
    var save = 0usize
    let t1 = c_strtok_r(list, comma, &save)
    let t2 = c_strtok_r(0usize, comma, &save)
    let t3 = c_strtok_r(0usize, comma, &save)
    let t4 = c_strtok_r(0usize, comma, &save)
    want(t1 == list && t2 == list + 2usize && t3 == list + 5usize && t4 == 0usize, 49i32)
    let again = c_text(out[0..], "a,b,,c")
    var cursor = again
    let s1 = c_strsep(&cursor, comma)
    let s2 = c_strsep(&cursor, comma)
    let s3 = c_strsep(&cursor, comma)
    want(s1 == again && s2 == again + 2usize && s3 == again + 4usize && c_strlen(s3) == 0usize, 50i32)
    let copy = c_strdup(h)
    want(copy != 0usize && c_strcmp(copy, h) == 0i32, 51i32)
    let half = c_strndup(h, 5usize)
    want(half != 0usize && c_strlen(half) == 5usize && c_strncmp(half, h, 5usize) == 0i32, 52i32)
    c_free(copy)
    c_free(half)
    want(c_ffs(8i32) == 4i32 && c_ffsl(1024i64) == 11i32 && c_ffsll(0i64) == 0i32, 53i32)
}

fn memory() {
    var a: [16]u8 = zero
    var b: [16]u8 = zero
    let pa = mem.address_of(&a[0usize])
    let pb = mem.address_of(&b[0usize])
    want(c_memset(pa, 7i32, 16usize) == pa && a[15usize] == 7u8, 60i32)
    want(c_memcpy(pb, pa, 16usize) == pb && c_memcmp(pa, pb, 16usize) == 0i32, 61i32)
    a[9usize] = 42u8
    a[12usize] = 42u8
    want(c_memchr(pa, 42i32, 16usize) == pa + 9usize && c_memrchr(pa, 42i32, 16usize) == pa + 12usize, 62i32)
    want(c_rawmemchr(pa, 42i32) == pa + 9usize, 63i32)
    want(c_memcmp(pa, pb, 16usize) > 0i32, 64i32)
    b[0usize] = 42u8
    b[1usize] = 7u8
    // 42 then 7 first occurs at 9.
    want(c_memmem(pa, 16usize, pb, 2usize) == pa + 9usize, 65i32)
    // Overlapping: shift left by one.
    want(c_memmove(pa, pa + 1usize, 15usize) == pa && a[8usize] == 42u8, 66i32)
    let heap = c_malloc(64usize)
    want(heap != 0usize && c_memset(heap, 0i32, 64usize) == heap, 67i32)
    let zeroes = c_calloc(8usize, 8usize)
    want(zeroes != 0usize && c_memcmp(heap, zeroes, 64usize) == 0i32, 68i32)
    let grown = c_realloc(heap, 4096usize)
    want(grown != 0usize && c_memcmp(grown, zeroes, 64usize) == 0i32, 69i32)
    c_free(grown)
    c_free(zeroes)
}

fn numbers() {
    var digits: [32]u8 = zero
    want(c_abs(-7i32) == 7i32 && c_labs(-7000000000i64) == 7000000000i64 && c_llabs(-1i64) == 1i64, 70i32)
    let n = c_text(digits[0..], "-1234")
    want(c_atoi(n) == -1234i32 && c_atol(n) == -1234i64 && c_atoll(n) == -1234i64, 71i32)
    let hex = c_text(digits[0..], "ff")
    want(c_strtol(hex, 0usize, 16i32) == 255i64 && c_strtoul(hex, 0usize, 16i32) == 255u64, 72i32)
    let big = c_text(digits[0..], "18446744073709551615")
    want(c_strtoull(big, 0usize, 10i32) == 18446744073709551615u64, 73i32)
    let negative = c_text(digits[0..], "-9223372036854775808")
    want(c_strtoll(negative, 0usize, 10i32) == -9223372036854775807i64 - 1i64, 74i32)
    // rand_r is deterministic from its seed.
    var seed_a = 12345u32
    var seed_b = 12345u32
    want(c_rand_r(&seed_a) == c_rand_r(&seed_b) && seed_a == seed_b, 75i32)
}

fn process() {
    want(c_getpid() > 0i32 && c_getppid() > 0i32, 80i32)
    want(c_getuid() == c_getuid() && c_geteuid() == c_geteuid(), 81i32)
    want(c_getgid() == c_getgid() && c_getegid() == c_getegid(), 82i32)
    // _SC_PAGESIZE is 30 on Linux.
    want(c_getpagesize() == i32.trunc(c_sysconf(30i32)) && c_getpagesize() >= 4096i32, 83i32)
    // After 2020-01-01.
    want(c_time(0usize) > 1577836800i64, 84i32)
}

fn math() {
    want(m_sqrt(16.0f64) == 4.0f64 && near(m_cbrt(27.0f64), 3.0f64), 90i32)
    want(m_floor(-2.5f64) == -3.0f64 && m_ceil(2.1f64) == 3.0f64 && m_trunc(-2.7f64) == -2.0f64, 91i32)
    want(m_round(2.5f64) == 3.0f64 && m_rint(2.5f64) == 2.0f64 && m_nearbyint(3.5f64) == 4.0f64, 92i32)
    want(m_lround(2.5f64) == 3i64 && m_llround(-2.5f64) == -3i64, 93i32)
    want(m_fabs(-3.0f64) == 3.0f64 && m_fmin(2.0f64, 3.0f64) == 2.0f64 && m_fmax(2.0f64, 3.0f64) == 3.0f64, 94i32)
    want(m_fdim(5.0f64, 3.0f64) == 2.0f64 && m_fmod(7.0f64, 3.0f64) == 1.0f64 && m_remainder(7.0f64, 2.0f64) == -1.0f64, 95i32)
    want(m_copysign(3.0f64, -1.0f64) == -3.0f64 && m_fma(2.0f64, 3.0f64, 4.0f64) == 10.0f64, 96i32)
    want(mem.bitcast[u64](m_nextafter(1.0f64, 2.0f64)) == mem.bitcast[u64](1.0f64) + 1u64, 97i32)
    want(m_hypot(3.0f64, 4.0f64) == 5.0f64 && m_pow(2.0f64, 10.0f64) == 1024.0f64, 98i32)
    want(m_ldexp(1.0f64, 10i32) == 1024.0f64 && m_scalbn(1.0f64, 3i32) == 8.0f64, 99i32)
    want(m_ilogb(1024.0f64) == 10i32 && m_logb(8.0f64) == 3.0f64, 100i32)
    want(m_exp(0.0f64) == 1.0f64 && m_exp2(10.0f64) == 1024.0f64 && m_expm1(0.0f64) == 0.0f64, 101i32)
    want(m_log(1.0f64) == 0.0f64 && m_log2(1024.0f64) == 10.0f64 && near(m_log10(1000.0f64), 3.0f64) && m_log1p(0.0f64) == 0.0f64, 102i32)
    want(m_sin(0.0f64) == 0.0f64 && m_cos(0.0f64) == 1.0f64 && m_tan(0.0f64) == 0.0f64, 103i32)
    want(m_asin(0.0f64) == 0.0f64 && m_acos(1.0f64) == 0.0f64 && m_atan(0.0f64) == 0.0f64 && m_atan2(0.0f64, 1.0f64) == 0.0f64, 104i32)
    want(m_sinh(0.0f64) == 0.0f64 && m_cosh(0.0f64) == 1.0f64 && m_tanh(0.0f64) == 0.0f64, 105i32)
    want(m_asinh(0.0f64) == 0.0f64 && m_acosh(1.0f64) == 0.0f64 && m_atanh(0.0f64) == 0.0f64, 106i32)
    want(m_erf(0.0f64) == 0.0f64 && m_erfc(0.0f64) == 1.0f64 && near(m_tgamma(5.0f64), 24.0f64), 107i32)
}

fn little_u64(bytes: []const u8, at: usize) -> usize {
    var value = 0usize
    var index = 8usize
    while index > 0usize {
        index -= 1usize
        value = value * 256usize + usize(bytes[at + index])
    }
    ret value
}

fn little_u32(bytes: []const u8, at: usize) -> usize {
    var value = 0usize
    var index = 4usize
    while index > 0usize {
        index -= 1usize
        value = value * 256usize + usize(bytes[at + index])
    }
    ret value
}

// The image itself: the entry point is past the first page -- the metadata did not fit in
// it -- and the first PT_LOAD maps from the start of the file to the end of the code, so the
// loader sees every byte of the metadata ahead of the entry.
fn layout(a: *mem.Arena) {
    let (path, path_error) = os.executable_path(a)
    if path_error != ok || path.len == 0usize { os.exit(110i32) }
    var flags: os.OpenFlags = zero
    flags.read = true
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { os.exit(111i32) }
    var header: [512]u8 = zero
    let (count, read_error) = os.read(file, header[0..])
    let closed = os.close(file)
    if read_error != ok || count != 512usize { os.exit(112i32) }
    let entry = little_u64(header[0..], 24usize)
    let base = 4194304usize
    want(entry >= base + 8192usize, 113i32)
    let phoff = little_u64(header[0..], 32usize)
    let phnum = usize(header[56usize]) + usize(header[57usize]) * 256usize
    var first_load = false
    var i = 0usize
    while i < phnum {
        let at = phoff + i * 56usize
        if !first_load && little_u32(header[0..], at) == 1usize {
            first_load = true
            let offset = little_u64(header[0..], at + 8usize)
            let filesz = little_u64(header[0..], at + 32usize)
            want(offset == 0usize && filesz > entry - base, 114i32)
        }
        i += 1usize
    }
    want(first_load, 115i32)
}

fn main(a: *mem.Arena) -> err {
    ctype()
    strings()
    memory()
    numbers()
    process()
    math()
    layout(a)
    ret ok
}
