/* Homogeneous float aggregates returned by value (C178): AAPCS64 brings three and four doubles back in v0-v3 and four floats in
   v0-v3 as well; on x86-64 the same structs come back through memory (the doubles) or in xmm0/xmm1 (the floats). */
typedef struct { double a, b, c; } D3;
typedef struct { double a, b, c, d; } D4;
typedef struct { float a, b, c, d; } F4;

D3 hfa_make_d3(double a, double b, double c) { D3 r = { a, b, c }; return r; }
D4 hfa_make_d4(double a, double b, double c, double d) { D4 r = { a, b, c, d }; return r; }
F4 hfa_make_f4(float a, float b, float c, float d) { F4 r = { a, b, c, d }; return r; }
D4 hfa_rotate_d4(D4 v) { D4 r = { v.b, v.c, v.d, v.a }; return r; }
D3 hfa_scale_d3(D3 v, double k) { D3 r = { v.a * k, v.b * k, v.c * k }; return r; }
