/* The foreign side of link/extern_struct (D1675): structs and unions by value, built
   by the host's own C compiler -- cl on Windows, cc on Linux -- whose aggregate rules
   are the ones `extern fn` has to match. Every function reads or writes every field in
   a position-weighted way, so a field that lands in the wrong register, slot or offset
   is a wrong number rather than a lucky one. The layouts mirror src/cabi.e. */
#include <stdarg.h>
#include <stdint.h>

#ifdef _WIN32
#define API __declspec(dllexport)
#else
#define API __attribute__((visibility("default")))
#endif

typedef struct { uint8_t a; } Byte;
typedef struct { int16_t a; } Short;
typedef struct { uint8_t a, b, c; } Triple;
typedef struct { float a; } Single;
typedef struct { int32_t x, y; } Pair;
typedef struct { float x, y; } Floats;
typedef struct { int64_t a, b; } Longs;
typedef struct { double d; int64_t i; } DoubleInt;
typedef struct { int64_t i; double d; } IntDouble;
typedef struct { double x, y; } Doubles;
typedef struct { float a, b, c; } ThreeFloats;
typedef struct { Pair p; float f[2]; } Nest;
typedef union { int64_t i; double d; } Num;
typedef struct { int64_t a, b, c; } Big;
#pragma pack(push, 1)
typedef struct { uint8_t tag; int32_t value; } Packed;
#pragma pack(pop)
typedef struct { int64_t k; } Key;

API int64_t byte_in(Byte s) { return s.a; }
API int64_t short_in(Short s) { return s.a; }
API int64_t triple_in(Triple s) { return s.a + 256 * s.b + 65536 * s.c; }
API double single_in(Single s) { return s.a; }
API int64_t pair_in(Pair s) { return 1000 * (int64_t)s.x + s.y; }
API double floats_in(Floats s) { return 10.0 * s.x + s.y; }
API int64_t longs_in(Longs s) { return 3 * s.a - s.b; }
API double double_int_in(DoubleInt s) { return 2.0 * s.d + (double)s.i; }
API double int_double_in(IntDouble s) { return 2.0 * (double)s.i + s.d; }
API double doubles_in(Doubles s) { return 10.0 * s.x + s.y; }
API double three_floats_in(ThreeFloats s) { return 100.0 * s.a + 10.0 * s.b + s.c; }
API double nest_in(Nest s) { return 1000.0 * s.p.x + 100.0 * s.p.y + 10.0 * s.f[0] + s.f[1]; }
API int64_t num_in(Num s) { return s.i; }
API int64_t big_in(Big s) { return 100 * s.a + 10 * s.b + s.c; }
API int64_t packed_in(Packed s) { return 1000 * (int64_t)s.tag + s.value; }

/* A MEMORY aggregate first, then a scalar that still gets the first register. */
API int64_t big_then(Big s, int64_t x) { return 10 * (s.a + s.b + s.c) + x; }

/* Five integers leave one register: System V puts the whole pair on the stack and
   gives `f` the register it did not take. */
API int64_t crowd(int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, Longs s, int64_t f) {
    return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * s.a + 7 * s.b + 8 * f;
}

/* The same with seven doubles and eight xmm registers. */
API double crowd_sse(double a, double b, double c, double d, double e, double f, double g, Doubles s, double h) {
    return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + 8 * s.x + 9 * s.y + 10 * h;
}

/* Structs in a C variadic's `...`. */
API int64_t sum_longs(int32_t n, ...) {
    va_list ap;
    int64_t total = 0;
    va_start(ap, n);
    for (int32_t at = 0; at < n; at++) {
        Longs s = va_arg(ap, Longs);
        total = 100 * total + 10 * s.a + s.b;
    }
    va_end(ap);
    return total;
}

API Byte byte_out(uint8_t a) { Byte s = { a }; return s; }
API Short short_out(int16_t a) { Short s = { a }; return s; }
API Triple triple_out(uint8_t a, uint8_t b, uint8_t c) { Triple s = { a, b, c }; return s; }
API Single single_out(float a) { Single s = { a }; return s; }
API Pair pair_out(int32_t x, int32_t y) { Pair s = { x, y }; return s; }
API Floats floats_out(float x, float y) { Floats s = { x, y }; return s; }
API Longs longs_out(int64_t a, int64_t b) { Longs s = { a, b }; return s; }
API DoubleInt double_int_out(double d, int64_t i) { DoubleInt s = { d, i }; return s; }
API IntDouble int_double_out(int64_t i, double d) { IntDouble s = { i, d }; return s; }
API Doubles doubles_out(double x, double y) { Doubles s = { x, y }; return s; }
API ThreeFloats three_floats_out(float a, float b, float c) { ThreeFloats s = { a, b, c }; return s; }
API Nest nest_out(int32_t x, int32_t y, float f0, float f1) { Nest s = { { x, y }, { f0, f1 } }; return s; }
API Num num_out(double d) { Num s; s.d = d; return s; }
API Big big_out(int64_t a, int64_t b, int64_t c) { Big s = { a, b, c }; return s; }
API Packed packed_out(uint8_t tag, int32_t value) { Packed s; s.tag = tag; s.value = value; return s; }

/* In and out at once: a pair swapped, and a MEMORY aggregate through a hidden result
   pointer while its argument is on the stack (System V) or behind a copy (Win64). */
API Doubles doubles_swap(Doubles s) { Doubles t = { s.y, s.x }; return t; }
API Big big_rotate(Big s) { Big t = { s.b, s.c, s.a }; return t; }

/* A key's declared `cmp` and `hash`, which a supplied protocol calls per element. */
API int32_t key_cmp(Key a, Key b) { return (a.k > b.k) - (a.k < b.k); }
API uint64_t key_hash(Key s) { return (uint64_t)s.k * 0x9E3779B97F4A7C15ull; }
