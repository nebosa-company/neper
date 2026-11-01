// AV1 dequantization and inverse transforms (specification sections "Reconstruct process" and
// "Inverse transform process"), without quantizer matrices and without the final addition to the
// prediction.
//
//   reconstruct(quant, tx_size, tx_type, lossless, bit_depth, dc_q, ac_q, out) -> err
//     quant   the parsed coefficients as the spec's Quant array: Quant[i * tw + j] with tw = Min(32, w),
//             th = Min(32, h) rows (so a 64-wide or 64-high block has only its 32x32 corner)
//     out     w * h residual samples, row-major with stride w, already flipped for the FLIPADST types, so the
//             caller adds out[y * w + x] to the prediction at (x, y) and clips
//     dc_q, ac_q   the quantizer values for the plane (get_dc_quant / get_ac_quant)
//   inverse_transform_2d(dequant, tx_size, tx_type, lossless, bit_depth, out) -> err
//     the "2D inverse transform process" alone: dequant uses the same tw layout as quant; out is the Residual
//     array in transform orientation (no flip)
//   idct, iadst, iwht, iidentity: the 1D processes on a slice of at least 2^n entries
//
// tx_size is the spec's TxSize (0 = TX_4X4 .. 18 = TX_64X16), tx_type the spec's PlaneTxType
// (0 = DCT_DCT .. 15 = H_FLIPADST). A tx_type that needs a 1D transform the spec does not define for that
// length (ADST above 16, identity above 32) is `Invalid`. All the arithmetic is done in 64 bits, so every
// bit depth the spec allows is exact.

error Invalid

fn cos_tab() -> str { ret "\x10\x00\x0f\xff\x0f\xfb\x0f\xf5\x0f\xec\x0f\xe1\x0f\xd4\x0f\xc4\x0f\xb1\x0f\x9c\x0f\x85\x0f\x6c\x0f\x50\x0f\x31\x0f\x11\x0e\xee\x0e\xc8\x0e\xa1\x0e\x77\x0e\x4b\x0e\x1c\x0d\xec\x0d\xb9\x0d\x85\x0d\x4e\x0d\x15\x0c\xda\x0c\x9d\x0c\x5e\x0c\x1e\x0b\xdb\x0b\x97\x0b\x50\x0b\x08\x0a\xbf\x0a\x73\x0a\x26\x09\xd8\x09\x88\x09\x37\x08\xe4\x08\x8f\x08\x3a\x07\xe3\x07\x8b\x07\x32\x06\xd7\x06\x7c\x06\x1f\x05\xc2\x05\x64\x05\x05\x04\xa5\x04\x44\x03\xe3\x03\x81\x03\x1f\x02\xbc\x02\x59\x01\xf5\x01\x91\x01\x2d\x00\xc9\x00\x65\x00\x00" }

fn log2_w_tab() -> str { ret "\x02\x03\x04\x05\x06\x02\x03\x03\x04\x04\x05\x05\x06\x02\x04\x03\x05\x04\x06" }
fn log2_h_tab() -> str { ret "\x02\x03\x04\x05\x06\x03\x02\x04\x03\x05\x04\x06\x05\x04\x02\x05\x03\x06\x04" }
fn row_shift_tab() -> str { ret "\x00\x01\x02\x02\x02\x00\x00\x01\x01\x01\x01\x01\x01\x01\x01\x02\x02\x02\x02" }
// per tx_type: 0 = DCT, 1 = ADST (or FLIPADST), 2 = identity
fn row_kind_tab() -> str { ret "\x00\x00\x01\x01\x00\x01\x01\x01\x01\x02\x02\x00\x02\x01\x02\x01" }
fn col_kind_tab() -> str { ret "\x00\x01\x00\x01\x01\x00\x01\x01\x01\x02\x00\x02\x01\x02\x01\x02" }

fn round2(v: i64, n: u32) -> i64 {
    if n == 0u32 { ret v }
    ret (v + (1i64 << (n - 1u32))) >> n
}

fn clip3(lo: i64, hi: i64, v: i64) -> i64 {
    if v < lo { ret lo }
    if v > hi { ret hi }
    ret v
}

fn brev(num_bits: i32, v: i32) -> i32 {
    var t = 0i32
    var i = 0i32
    while i < num_bits {
        let bit = (v >> u32(i)) & 1i32
        t += bit << u32(num_bits - 1i32 - i)
        i += 1i32
    }
    ret t
}

fn cos128(angle: i32) -> i64 {
    let a2 = angle & 255i32
    let tab = cos_tab()
    if a2 <= 64i32 { ret i64((u32(tab[usize(2i32 * a2)]) << 8u32) | u32(tab[usize(2i32 * a2 + 1i32)])) }
    if a2 <= 128i32 {
        let k = 128i32 - a2
        ret 0i64 - i64((u32(tab[usize(2i32 * k)]) << 8u32) | u32(tab[usize(2i32 * k + 1i32)]))
    }
    if a2 <= 192i32 {
        let k = a2 - 128i32
        ret 0i64 - i64((u32(tab[usize(2i32 * k)]) << 8u32) | u32(tab[usize(2i32 * k + 1i32)]))
    }
    let k = 256i32 - a2
    ret i64((u32(tab[usize(2i32 * k)]) << 8u32) | u32(tab[usize(2i32 * k + 1i32)]))
}

fn sin128(angle: i32) -> i64 { ret cos128(angle - 64i32) }

fn bfly(t: []i32, a: i32, b: i32, angle: i32, flip: bool) {
    let ta = i64(t[usize(a)])
    let tb = i64(t[usize(b)])
    let c = cos128(angle)
    let s = sin128(angle)
    let x = round2(ta * c - tb * s, 12u32)
    let y = round2(ta * s + tb * c, 12u32)
    if flip {
        t[usize(a)] = i32(y)
        t[usize(b)] = i32(x)
    } else {
        t[usize(a)] = i32(x)
        t[usize(b)] = i32(y)
    }
}

fn hada(t: []i32, a0: i32, b0: i32, flip: bool, r: u32) {
    var a = a0
    var b = b0
    if flip {
        a = b0
        b = a0
    }
    let x = i64(t[usize(a)])
    let y = i64(t[usize(b)])
    let hi = (1i64 << (r - 1u32)) - 1i64
    let lo = 0i64 - (1i64 << (r - 1u32))
    t[usize(a)] = i32(clip3(lo, hi, x + y))
    t[usize(b)] = i32(clip3(lo, hi, x - y))
}

fn idct(t: []i32, n: i32, r: u32) {
    var copy_t: [64]i32 = zero
    let n0 = 1i32 << u32(n)
    var i = 0i32
    var j = 0i32
    while i < n0 {
        copy_t[usize(i)] = t[usize(i)]
        i += 1i32
    }
    i = 0i32
    while i < n0 {
        t[usize(i)] = copy_t[usize(brev(n, i))]
        i += 1i32
    }
    if n == 6i32 {
        i = 0i32
        while i < 16i32 {
            bfly(t, 32i32 + i, 63i32 - i, 63i32 - 4i32 * brev(4i32, i), false)
            i += 1i32
        }
    }
    if n >= 5i32 {
        i = 0i32
        while i < 8i32 {
            bfly(t, 16i32 + i, 31i32 - i, 6i32 + (brev(3i32, 7i32 - i) << 3u32), false)
            i += 1i32
        }
    }
    if n == 6i32 {
        i = 0i32
        while i < 16i32 {
            hada(t, 32i32 + i * 2i32, 33i32 + i * 2i32, (i & 1i32) != 0i32, r)
            i += 1i32
        }
    }
    if n >= 4i32 {
        i = 0i32
        while i < 4i32 {
            bfly(t, 8i32 + i, 15i32 - i, 12i32 + (brev(2i32, 3i32 - i) << 4u32), false)
            i += 1i32
        }
    }
    if n >= 5i32 {
        i = 0i32
        while i < 8i32 {
            hada(t, 16i32 + 2i32 * i, 17i32 + 2i32 * i, (i & 1i32) != 0i32, r)
            i += 1i32
        }
    }
    if n == 6i32 {
        i = 0i32
        while i < 4i32 {
            j = 0i32
            while j < 2i32 {
                bfly(t, 62i32 - i * 4i32 - j, 33i32 + i * 4i32 + j, 60i32 - 16i32 * brev(2i32, i) + 64i32 * j, true)
                j += 1i32
            }
            i += 1i32
        }
    }
    if n >= 3i32 {
        i = 0i32
        while i < 2i32 {
            bfly(t, 4i32 + i, 7i32 - i, 56i32 - 32i32 * i, false)
            i += 1i32
        }
    }
    if n >= 4i32 {
        i = 0i32
        while i < 4i32 {
            hada(t, 8i32 + 2i32 * i, 9i32 + 2i32 * i, (i & 1i32) != 0i32, r)
            i += 1i32
        }
    }
    if n >= 5i32 {
        i = 0i32
        while i < 2i32 {
            j = 0i32
            while j < 2i32 {
                bfly(t, 30i32 - 4i32 * i - j, 17i32 + 4i32 * i + j, 24i32 + (j << 6u32) + ((1i32 - i) << 5u32), true)
                j += 1i32
            }
            i += 1i32
        }
    }
    if n == 6i32 {
        i = 0i32
        while i < 8i32 {
            j = 0i32
            while j < 2i32 {
                hada(t, 32i32 + i * 4i32 + j, 35i32 + i * 4i32 - j, (i & 1i32) != 0i32, r)
                j += 1i32
            }
            i += 1i32
        }
    }
    i = 0i32
    while i < 2i32 {
        bfly(t, 2i32 * i, 2i32 * i + 1i32, 32i32 + 16i32 * i, i == 0i32)
        i += 1i32
    }
    if n >= 3i32 {
        i = 0i32
        while i < 2i32 {
            hada(t, 4i32 + 2i32 * i, 5i32 + 2i32 * i, i != 0i32, r)
            i += 1i32
        }
    }
    if n >= 4i32 {
        i = 0i32
        while i < 2i32 {
            bfly(t, 14i32 - i, 9i32 + i, 48i32 + 64i32 * i, true)
            i += 1i32
        }
    }
    if n >= 5i32 {
        i = 0i32
        while i < 4i32 {
            j = 0i32
            while j < 2i32 {
                hada(t, 16i32 + 4i32 * i + j, 19i32 + 4i32 * i - j, (i & 1i32) != 0i32, r)
                j += 1i32
            }
            i += 1i32
        }
    }
    if n == 6i32 {
        i = 0i32
        while i < 2i32 {
            j = 0i32
            while j < 4i32 {
                bfly(t, 61i32 - i * 8i32 - j, 34i32 + i * 8i32 + j, 56i32 - i * 32i32 + (j >> 1u32) * 64i32, true)
                j += 1i32
            }
            i += 1i32
        }
    }
    i = 0i32
    while i < 2i32 {
        hada(t, i, 3i32 - i, false, r)
        i += 1i32
    }
    if n >= 3i32 { bfly(t, 6i32, 5i32, 32i32, true) }
    if n >= 4i32 {
        i = 0i32
        while i < 2i32 {
            j = 0i32
            while j < 2i32 {
                hada(t, 8i32 + 4i32 * i + j, 11i32 + 4i32 * i - j, i != 0i32, r)
                j += 1i32
            }
            i += 1i32
        }
    }
    if n >= 5i32 {
        i = 0i32
        while i < 4i32 {
            bfly(t, 29i32 - i, 18i32 + i, 48i32 + (i >> 1u32) * 64i32, true)
            i += 1i32
        }
    }
    if n == 6i32 {
        i = 0i32
        while i < 4i32 {
            j = 0i32
            while j < 4i32 {
                hada(t, 32i32 + 8i32 * i + j, 39i32 + 8i32 * i - j, (i & 1i32) != 0i32, r)
                j += 1i32
            }
            i += 1i32
        }
    }
    if n >= 3i32 {
        i = 0i32
        while i < 4i32 {
            hada(t, i, 7i32 - i, false, r)
            i += 1i32
        }
    }
    if n >= 4i32 {
        i = 0i32
        while i < 2i32 {
            bfly(t, 13i32 - i, 10i32 + i, 32i32, true)
            i += 1i32
        }
    }
    if n >= 5i32 {
        i = 0i32
        while i < 2i32 {
            j = 0i32
            while j < 4i32 {
                hada(t, 16i32 + i * 8i32 + j, 23i32 + i * 8i32 - j, i != 0i32, r)
                j += 1i32
            }
            i += 1i32
        }
    }
    if n == 6i32 {
        i = 0i32
        while i < 8i32 {
            var angle = 112i32
            if i < 4i32 { angle = 48i32 }
            bfly(t, 59i32 - i, 36i32 + i, angle, true)
            i += 1i32
        }
    }
    if n >= 4i32 {
        i = 0i32
        while i < 8i32 {
            hada(t, i, 15i32 - i, false, r)
            i += 1i32
        }
    }
    if n >= 5i32 {
        i = 0i32
        while i < 4i32 {
            bfly(t, 27i32 - i, 20i32 + i, 32i32, true)
            i += 1i32
        }
    }
    if n == 6i32 {
        i = 0i32
        while i < 8i32 {
            hada(t, 32i32 + i, 47i32 - i, false, r)
            hada(t, 48i32 + i, 63i32 - i, true, r)
            i += 1i32
        }
    }
    if n >= 5i32 {
        i = 0i32
        while i < 16i32 {
            hada(t, i, 31i32 - i, false, r)
            i += 1i32
        }
    }
    if n == 6i32 {
        i = 0i32
        while i < 8i32 {
            bfly(t, 55i32 - i, 40i32 + i, 32i32, true)
            i += 1i32
        }
        i = 0i32
        while i < 32i32 {
            hada(t, i, 63i32 - i, false, r)
            i += 1i32
        }
    }
}

fn adst_in_perm(t: []i32, n: i32) {
    var copy_t: [16]i32 = zero
    let n0 = 1i32 << u32(n)
    var i = 0i32
    while i < n0 {
        copy_t[usize(i)] = t[usize(i)]
        i += 1i32
    }
    i = 0i32
    while i < n0 {
        var idx = n0 - i - 1i32
        if (i & 1i32) != 0i32 { idx = i - 1i32 }
        t[usize(i)] = copy_t[usize(idx)]
        i += 1i32
    }
}

fn adst_out_perm(t: []i32, n: i32) {
    var copy_t: [16]i32 = zero
    let n0 = 1i32 << u32(n)
    var i = 0i32
    while i < n0 {
        copy_t[usize(i)] = t[usize(i)]
        i += 1i32
    }
    i = 0i32
    while i < n0 {
        let a = (i >> 3u32) & 1i32
        let b = ((i >> 2u32) & 1i32) ^ ((i >> 3u32) & 1i32)
        let c = ((i >> 1u32) & 1i32) ^ ((i >> 2u32) & 1i32)
        let d = (i & 1i32) ^ ((i >> 1u32) & 1i32)
        let idx = ((d << 3u32) | (c << 2u32) | (b << 1u32) | a) >> u32(4i32 - n)
        if (i & 1i32) != 0i32 {
            t[usize(i)] = 0i32 - copy_t[usize(idx)]
        } else {
            t[usize(i)] = copy_t[usize(idx)]
        }
        i += 1i32
    }
}

fn iadst4(t: []i32) {
    let t0 = i64(t[0usize])
    let t1 = i64(t[1usize])
    let t2 = i64(t[2usize])
    let t3 = i64(t[3usize])
    var s0 = 1321i64 * t0
    var s1 = 2482i64 * t0
    var s2 = 3344i64 * t1
    var s3 = 3803i64 * t2
    let s4 = 1321i64 * t2
    let s5 = 2482i64 * t3
    let s6 = 3803i64 * t3
    let a7 = t0 - t2
    let b7 = a7 + t3
    s0 = s0 + s3
    s1 = s1 - s4
    s3 = s2
    s2 = 3344i64 * b7
    s0 = s0 + s5
    s1 = s1 - s6
    let x0 = s0 + s3
    let x1 = s1 + s3
    let x2 = s2
    let x3 = s0 + s1 - s3
    t[0usize] = i32(round2(x0, 12u32))
    t[1usize] = i32(round2(x1, 12u32))
    t[2usize] = i32(round2(x2, 12u32))
    t[3usize] = i32(round2(x3, 12u32))
}

fn iadst8(t: []i32, r: u32) {
    var i = 0i32
    var j = 0i32
    adst_in_perm(t, 3i32)
    while i < 4i32 {
        bfly(t, 2i32 * i, 2i32 * i + 1i32, 60i32 - 16i32 * i, true)
        i += 1i32
    }
    i = 0i32
    while i < 4i32 {
        hada(t, i, 4i32 + i, false, r)
        i += 1i32
    }
    i = 0i32
    while i < 2i32 {
        bfly(t, 4i32 + 3i32 * i, 5i32 + i, 48i32 - 32i32 * i, true)
        i += 1i32
    }
    i = 0i32
    while i < 2i32 {
        j = 0i32
        while j < 2i32 {
            hada(t, 4i32 * j + i, 2i32 + 4i32 * j + i, false, r)
            j += 1i32
        }
        i += 1i32
    }
    i = 0i32
    while i < 2i32 {
        bfly(t, 2i32 + 4i32 * i, 3i32 + 4i32 * i, 32i32, true)
        i += 1i32
    }
    adst_out_perm(t, 3i32)
}

fn iadst16(t: []i32, r: u32) {
    var i = 0i32
    var j = 0i32
    adst_in_perm(t, 4i32)
    while i < 8i32 {
        bfly(t, 2i32 * i, 2i32 * i + 1i32, 62i32 - 8i32 * i, true)
        i += 1i32
    }
    i = 0i32
    while i < 8i32 {
        hada(t, i, 8i32 + i, false, r)
        i += 1i32
    }
    i = 0i32
    while i < 2i32 {
        bfly(t, 8i32 + 2i32 * i, 9i32 + 2i32 * i, 56i32 - 32i32 * i, true)
        bfly(t, 13i32 + 2i32 * i, 12i32 + 2i32 * i, 8i32 + 32i32 * i, true)
        i += 1i32
    }
    i = 0i32
    while i < 4i32 {
        j = 0i32
        while j < 2i32 {
            hada(t, 8i32 * j + i, 4i32 + 8i32 * j + i, false, r)
            j += 1i32
        }
        i += 1i32
    }
    i = 0i32
    while i < 2i32 {
        j = 0i32
        while j < 2i32 {
            bfly(t, 4i32 + 8i32 * j + 3i32 * i, 5i32 + 8i32 * j + i, 48i32 - 32i32 * i, true)
            j += 1i32
        }
        i += 1i32
    }
    i = 0i32
    while i < 2i32 {
        j = 0i32
        while j < 4i32 {
            hada(t, 4i32 * j + i, 2i32 + 4i32 * j + i, false, r)
            j += 1i32
        }
        i += 1i32
    }
    i = 0i32
    while i < 4i32 {
        bfly(t, 2i32 + 4i32 * i, 3i32 + 4i32 * i, 32i32, true)
        i += 1i32
    }
    adst_out_perm(t, 4i32)
}

// n = 2..4; the FLIPADST variants are the same transform with the output flipped by the caller
fn iadst(t: []i32, n: i32, r: u32) {
    if n == 2i32 { iadst4(t) } else if n == 3i32 { iadst8(t, r) } else { iadst16(t, r) }
}

fn iwht(t: []i32, shift: u32) {
    var a = t[0usize] >> shift
    var c = t[1usize] >> shift
    var d = t[2usize] >> shift
    var b = t[3usize] >> shift
    a += c
    d -= b
    let e = (a - d) >> 1u32
    b = e - b
    c = e - c
    a -= b
    d += c
    t[0usize] = a
    t[1usize] = b
    t[2usize] = c
    t[3usize] = d
}

// n = 2..5
fn iidentity(t: []i32, n: i32) {
    let n0 = 1i32 << u32(n)
    var i = 0i32
    while i < n0 {
        let v = i64(t[usize(i)])
        if n == 2i32 { t[usize(i)] = i32(round2(v * 5793i64, 12u32)) } else if n == 3i32 { t[usize(i)] = i32(v * 2i64) } else if n == 4i32 { t[usize(i)] = i32(round2(v * 11586i64, 12u32)) } else { t[usize(i)] = i32(v * 4i64) }
        i += 1i32
    }
}

fn transform_1d(t: []i32, kind: u8, n: i32, r: u32, lossless: bool, wht_shift: u32) {
    if lossless { iwht(t, wht_shift) } else if kind == 0u8 { idct(t, n, r) } else if kind == 1u8 { iadst(t, n, r) } else { iidentity(t, n) }
}

fn kind_ok(kind: u8, n: i32) -> bool {
    if kind == 1u8 { ret n <= 4i32 }
    if kind == 2u8 { ret n <= 5i32 }
    ret true
}

fn inverse_transform_2d(dequant: []const i32, tx_size: usize, tx_type: usize, lossless: bool, bit_depth: u32, out: []i32) -> err {
    if tx_size >= 19usize || tx_type >= 16usize { ret Invalid }
    let log2_w = i32(log2_w_tab()[tx_size])
    let log2_h = i32(log2_h_tab()[tx_size])
    let w = usize(1i32 << u32(log2_w))
    let h = usize(1i32 << u32(log2_h))
    let row_kind = row_kind_tab()[tx_type]
    let col_kind = col_kind_tab()[tx_type]
    if lossless {
        if tx_size != 0usize { ret Invalid }
    } else {
        if !kind_ok(row_kind, log2_w) || !kind_ok(col_kind, log2_h) { ret Invalid }
    }
    var tw = w
    if tw > 32usize { tw = 32usize }
    var th = h
    if th > 32usize { th = 32usize }
    if dequant.len < tw * th || out.len < w * h { ret Invalid }
    var row_shift = u32(row_shift_tab()[tx_size])
    var col_shift = 4u32
    if lossless {
        row_shift = 0u32
        col_shift = 0u32
    }
    let row_clamp = bit_depth + 8u32
    var col_clamp = bit_depth + 6u32
    if col_clamp < 16u32 { col_clamp = 16u32 }
    let col_hi = (1i64 << (col_clamp - 1u32)) - 1i64
    let col_lo = 0i64 - (1i64 << (col_clamp - 1u32))
    var rect = false
    if log2_w - log2_h == 1i32 || log2_h - log2_w == 1i32 { rect = true }
    var t: [64]i32 = zero
    var i = 0usize
    var j = 0usize
    while i < h {
        j = 0usize
        var any = false
        while j < w {
            var v = 0i32
            if i < 32usize && j < 32usize { v = dequant[i * tw + j] }
            if rect { v = i32(round2(i64(v) * 2896i64, 12u32)) }
            if v != 0i32 { any = true }
            t[j] = v
            j += 1usize
        }
        j = 0usize
        if any {
            transform_1d(t[..], row_kind, log2_w, row_clamp, lossless, 2u32)
            while j < w {
                out[i * w + j] = i32(clip3(col_lo, col_hi, round2(i64(t[j]), row_shift)))
                j += 1usize
            }
        } else {
            while j < w {
                out[i * w + j] = 0i32
                j += 1usize
            }
        }
        i += 1usize
    }
    j = 0usize
    while j < w {
        i = 0usize
        while i < h {
            t[i] = out[i * w + j]
            i += 1usize
        }
        transform_1d(t[..], col_kind, log2_h, col_clamp, lossless, 0u32)
        i = 0usize
        while i < h {
            out[i * w + j] = i32(round2(i64(t[i]), col_shift))
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

fn reconstruct(quant: []const i32, tx_size: usize, tx_type: usize, lossless: bool, bit_depth: u32, dc_q: i32, ac_q: i32, out: []i32) -> err {
    if tx_size >= 19usize || tx_type >= 16usize { ret Invalid }
    let log2_w = u32(log2_w_tab()[tx_size])
    let log2_h = u32(log2_h_tab()[tx_size])
    let w = usize(1u32 << log2_w)
    let h = usize(1u32 << log2_h)
    var tw = w
    if tw > 32usize { tw = 32usize }
    var th = h
    if th > 32usize { th = 32usize }
    if quant.len < tw * th || out.len < w * h { ret Invalid }
    var dq_shift = 0u32
    if tx_size == 3usize || tx_size == 9usize || tx_size == 10usize || tx_size == 17usize || tx_size == 18usize { dq_shift = 1u32 } else if tx_size == 4usize || tx_size == 11usize || tx_size == 12usize { dq_shift = 2u32 }
    let lim_hi = (1i64 << (7u32 + bit_depth)) - 1i64
    let lim_lo = 0i64 - (1i64 << (7u32 + bit_depth))
    var dequant: [1024]i32 = zero
    var i = 0usize
    var j = 0usize
    while i < th {
        j = 0usize
        while j < tw {
            var q = ac_q
            if i == 0usize && j == 0usize { q = dc_q }
            let dq = i64(quant[i * tw + j]) * i64(q)
            var mag = dq
            if dq < 0i64 { mag = 0i64 - dq }
            mag = (mag & 16777215i64) >> dq_shift
            if dq < 0i64 { mag = 0i64 - mag }
            dequant[i * tw + j] = i32(clip3(lim_lo, lim_hi, mag))
            j += 1usize
        }
        i += 1usize
    }
    try inverse_transform_2d(dequant[0usize..tw * th], tx_size, tx_type, lossless, bit_depth, out)
    var flip_ud = false
    var flip_lr = false
    if tx_type == 4usize || tx_type == 8usize || tx_type == 14usize || tx_type == 6usize { flip_ud = true }
    if tx_type == 5usize || tx_type == 7usize || tx_type == 15usize || tx_type == 6usize { flip_lr = true }
    if flip_lr {
        i = 0usize
        while i < h {
            j = 0usize
            while j < w / 2usize {
                let tmp = out[i * w + j]
                out[i * w + j] = out[i * w + w - 1usize - j]
                out[i * w + w - 1usize - j] = tmp
                j += 1usize
            }
            i += 1usize
        }
    }
    if flip_ud {
        i = 0usize
        while i < h / 2usize {
            j = 0usize
            while j < w {
                let tmp = out[i * w + j]
                out[i * w + j] = out[(h - 1usize - i) * w + j]
                out[(h - 1usize - i) * w + j] = tmp
                j += 1usize
            }
            i += 1usize
        }
    }
    ret ok
}
