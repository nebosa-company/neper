// AV1 dequantization and inverse transforms (specification sections "Reconstruct process" and
// "Inverse transform process"), without quantizer matrices.
//
//   reconstruct_add(quant, tx_size, tx_type, lossless, bit_depth, dc_q, ac_q, eob_row_limit, eob_col_limit,
//                   dst, dst_stride, dst_x, dst_y, scratch) -> err
//     dequantizes, runs both transform passes and the final rounding, and ADDS the residual to the 8-bit
//     plane dst (row stride dst_stride) at (dst_x, dst_y), clamping to 0..255. bit_depth must be 8. The whole
//     w * h block must lie inside dst. scratch needs w * h + 4 * w entries (4352 always suffice).
//   reconstruct(quant, tx_size, tx_type, lossless, bit_depth, dc_q, ac_q, out) -> err
//     quant   the parsed coefficients as the spec's Quant array: Quant[i * tw + j] with tw = Min(32, w),
//             th = Min(32, h) rows (so a 64-wide or 64-high block has only its 32x32 corner)
//     out     w * h residual samples, row-major with stride w, already flipped for the FLIPADST types, so the
//             caller adds out[y * w + x] to the prediction at (x, y) and clips
//     dc_q, ac_q   the quantizer values for the plane (get_dc_quant / get_ac_quant)
//   reconstruct_eob(quant, tx_size, tx_type, lossless, bit_depth, dc_q, ac_q, eob_row_limit, eob_col_limit, out) -> err
//     the same, for a quant that is zero outside its first eob_row_limit rows and eob_col_limit columns (last
//     non-zero row / column plus one); only that corner is dequantized and the all-zero rows are skipped.
//     reconstruct finds the limits by scanning quant and calls it.
//   inverse_transform_2d(dequant, tx_size, tx_type, lossless, bit_depth, out) -> err
//     the "2D inverse transform process" alone: dequant uses the same tw layout as quant; out is the Residual
//     array in transform orientation (no flip)
//   idct, iadst, iwht, iidentity: the 1D processes on a slice of at least 2^n entries
//
// tx_size is the spec's TxSize (0 = TX_4X4 .. 18 = TX_64X16), tx_type the spec's PlaneTxType
// (0 = DCT_DCT .. 15 = H_FLIPADST). A tx_type that needs a 1D transform the spec does not define for that
// length (ADST above 16, identity above 32) is `Invalid`.
//
// Speed: for 8-bit lossy blocks (reconstruct_add, reconstruct_eob, reconstruct) the 1D transforms run on
// Vec[i32, 4]: one lane per row (row pass) or per column (column pass), the same butterfly network for all
// four, so the block is dequantized into a transposed 4-row staging buffer, transformed, and transposed back
// with unpack_lo / unpack_hi. For 8-bit input every product is a 16-bit value times a constant of at most 2^12
// (sums of two stay below 2^31), so i32 lanes give the spec's 64-bit result. DCTs have variants that skip the
// inputs known to be zero (4, 8, 16, 32 leading non-zero inputs). The unrolled vector transforms (v* below)
// are generated from the spec's butterfly structure. Lossless blocks and every bit depth other than 8 take
// the generic scalar path (reconstruct_generic, 64-bit arithmetic, exact for every bit depth).

use e.mem
use e.simd

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

fn reconstruct_generic(quant: []const i32, tx_size: usize, tx_type: usize, lossless: bool, bit_depth: u32, dc_q: i32, ac_q: i32, out: []i32) -> err {
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
fn vidct4(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 2usize * st)
    var s2 = vld(t, off + 1usize * st)
    var s3 = vld(t, off + 3usize * st)
    var s4 = (((kp2048) +% (s0 *% kp2896)) -% (s1 *% kp2896)) >> 12u32
    s0 = (((kp2048) +% (s0 *% kp2896)) +% (s1 *% kp2896)) >> 12u32
    s1 = (((kp2048) +% (s2 *% kp1567)) -% (s3 *% kp3784)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3784)) +% (s3 *% kp1567)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s0 +% s2), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s4 +% s1), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s4 -% s1), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s0 -% s2), lo, hi)))
    }
}

fn vidct8(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp3406 = vsp(3406i32)
    let kp2276 = vsp(2276i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 4usize * st)
    var s2 = vld(t, off + 2usize * st)
    var s3 = vld(t, off + 6usize * st)
    var s4 = vld(t, off + 1usize * st)
    var s5 = vld(t, off + 5usize * st)
    var s6 = vld(t, off + 3usize * st)
    var s7 = vld(t, off + 7usize * st)
    var s8 = (((kp2048) +% (s4 *% kp799)) -% (s7 *% kp4017)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp4017)) +% (s7 *% kp799)) >> 12u32
    s7 = (((kp2048) +% (s5 *% kp3406)) -% (s6 *% kp2276)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp2276)) +% (s6 *% kp3406)) >> 12u32
    s6 = (((kp2048) +% (s0 *% kp2896)) -% (s1 *% kp2896)) >> 12u32
    s0 = (((kp2048) +% (s0 *% kp2896)) +% (s1 *% kp2896)) >> 12u32
    s1 = (((kp2048) +% (s2 *% kp1567)) -% (s3 *% kp3784)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3784)) +% (s3 *% kp1567)) >> 12u32
    s3 = vclp((s8 +% s7), lo, hi)
    s7 = vclp((s8 -% s7), lo, hi)
    s8 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = vclp((s0 +% s2), lo, hi)
    s0 = vclp((s0 -% s2), lo, hi)
    s2 = vclp((s6 +% s1), lo, hi)
    s1 = vclp((s6 -% s1), lo, hi)
    s6 = (((kp2048) +% (s4 *% kp2896)) -% (s7 *% kp2896)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp2896)) +% (s7 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s5 +% s8), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s2 +% s4), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s1 +% s6), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s0 +% s3), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s0 -% s3), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s1 -% s6), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s2 -% s4), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s5 -% s8), lo, hi)))
    }
}

fn vidct16(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp3166 = vsp(3166i32)
    let kp2598 = vsp(2598i32)
    let kp1931 = vsp(1931i32)
    let kp3612 = vsp(3612i32)
    let kp3920 = vsp(3920i32)
    let kp1189 = vsp(1189i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp3406 = vsp(3406i32)
    let kp2276 = vsp(2276i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 8usize * st)
    var s2 = vld(t, off + 4usize * st)
    var s3 = vld(t, off + 12usize * st)
    var s4 = vld(t, off + 2usize * st)
    var s5 = vld(t, off + 10usize * st)
    var s6 = vld(t, off + 6usize * st)
    var s7 = vld(t, off + 14usize * st)
    var s8 = vld(t, off + 1usize * st)
    var s9 = vld(t, off + 9usize * st)
    var s10 = vld(t, off + 5usize * st)
    var s11 = vld(t, off + 13usize * st)
    var s12 = vld(t, off + 3usize * st)
    var s13 = vld(t, off + 11usize * st)
    var s14 = vld(t, off + 7usize * st)
    var s15 = vld(t, off + 15usize * st)
    var s16 = (((kp2048) +% (s8 *% kp401)) -% (s15 *% kp4076)) >> 12u32
    s8 = (((kp2048) +% (s8 *% kp4076)) +% (s15 *% kp401)) >> 12u32
    s15 = (((kp2048) +% (s9 *% kp3166)) -% (s14 *% kp2598)) >> 12u32
    s9 = (((kp2048) +% (s9 *% kp2598)) +% (s14 *% kp3166)) >> 12u32
    s14 = (((kp2048) +% (s10 *% kp1931)) -% (s13 *% kp3612)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp3612)) +% (s13 *% kp1931)) >> 12u32
    s13 = (((kp2048) +% (s11 *% kp3920)) -% (s12 *% kp1189)) >> 12u32
    s11 = (((kp2048) +% (s11 *% kp1189)) +% (s12 *% kp3920)) >> 12u32
    s12 = (((kp2048) +% (s4 *% kp799)) -% (s7 *% kp4017)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp4017)) +% (s7 *% kp799)) >> 12u32
    s7 = (((kp2048) +% (s5 *% kp3406)) -% (s6 *% kp2276)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp2276)) +% (s6 *% kp3406)) >> 12u32
    s6 = vclp((s16 +% s15), lo, hi)
    s15 = vclp((s16 -% s15), lo, hi)
    s16 = vclp((s13 +% s14), lo, hi)
    s13 = vclp((s13 -% s14), lo, hi)
    s14 = vclp((s11 +% s10), lo, hi)
    s10 = vclp((s11 -% s10), lo, hi)
    s11 = vclp((s8 +% s9), lo, hi)
    s8 = vclp((s8 -% s9), lo, hi)
    s9 = (((kp2048) +% (s0 *% kp2896)) -% (s1 *% kp2896)) >> 12u32
    s0 = (((kp2048) +% (s0 *% kp2896)) +% (s1 *% kp2896)) >> 12u32
    s1 = (((kp2048) +% (s2 *% kp1567)) -% (s3 *% kp3784)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3784)) +% (s3 *% kp1567)) >> 12u32
    s3 = vclp((s12 +% s7), lo, hi)
    s7 = vclp((s12 -% s7), lo, hi)
    s12 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = (((kp2048) +% (s8 *% kp1567)) -% (s15 *% kp3784)) >> 12u32
    s8 = (((kp2048) +% (s8 *% kp3784)) +% (s15 *% kp1567)) >> 12u32
    s15 = (((kp2048) -% (s10 *% kp3784)) -% (s13 *% kp1567)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp1567)) -% (s13 *% kp3784)) >> 12u32
    s13 = vclp((s0 +% s2), lo, hi)
    s0 = vclp((s0 -% s2), lo, hi)
    s2 = vclp((s9 +% s1), lo, hi)
    s1 = vclp((s9 -% s1), lo, hi)
    s9 = (((kp2048) +% (s4 *% kp2896)) -% (s7 *% kp2896)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp2896)) +% (s7 *% kp2896)) >> 12u32
    s7 = vclp((s6 +% s16), lo, hi)
    s6 = vclp((s6 -% s16), lo, hi)
    s16 = vclp((s5 +% s15), lo, hi)
    s5 = vclp((s5 -% s15), lo, hi)
    s15 = vclp((s11 +% s14), lo, hi)
    s11 = vclp((s11 -% s14), lo, hi)
    s14 = vclp((s8 +% s10), lo, hi)
    s8 = vclp((s8 -% s10), lo, hi)
    s10 = vclp((s13 +% s12), lo, hi)
    s12 = vclp((s13 -% s12), lo, hi)
    s13 = vclp((s2 +% s4), lo, hi)
    s2 = vclp((s2 -% s4), lo, hi)
    s4 = vclp((s1 +% s9), lo, hi)
    s1 = vclp((s1 -% s9), lo, hi)
    s9 = vclp((s0 +% s3), lo, hi)
    s0 = vclp((s0 -% s3), lo, hi)
    s3 = (((kp2048) +% (s8 *% kp2896)) -% (s5 *% kp2896)) >> 12u32
    s5 = (((kp2048) +% (s8 *% kp2896)) +% (s5 *% kp2896)) >> 12u32
    s8 = (((kp2048) +% (s11 *% kp2896)) -% (s6 *% kp2896)) >> 12u32
    s6 = (((kp2048) +% (s11 *% kp2896)) +% (s6 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s10 +% s15), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s13 +% s14), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s4 +% s5), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s9 +% s6), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s0 +% s8), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s1 +% s3), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s2 +% s16), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s12 +% s7), lo, hi)))
    vst(t, off + 8usize * st, (vclp((s12 -% s7), lo, hi)))
    vst(t, off + 9usize * st, (vclp((s2 -% s16), lo, hi)))
    vst(t, off + 10usize * st, (vclp((s1 -% s3), lo, hi)))
    vst(t, off + 11usize * st, (vclp((s0 -% s8), lo, hi)))
    vst(t, off + 12usize * st, (vclp((s9 -% s6), lo, hi)))
    vst(t, off + 13usize * st, (vclp((s4 -% s5), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s13 -% s14), lo, hi)))
    vst(t, off + 15usize * st, (vclp((s10 -% s15), lo, hi)))
    }
}

fn vidct32(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp201 = vsp(201i32)
    let kp4091 = vsp(4091i32)
    let kp3035 = vsp(3035i32)
    let kp2751 = vsp(2751i32)
    let kp1751 = vsp(1751i32)
    let kp3703 = vsp(3703i32)
    let kp3857 = vsp(3857i32)
    let kp1380 = vsp(1380i32)
    let kp995 = vsp(995i32)
    let kp3973 = vsp(3973i32)
    let kp3513 = vsp(3513i32)
    let kp2106 = vsp(2106i32)
    let kp2440 = vsp(2440i32)
    let kp3290 = vsp(3290i32)
    let kp4052 = vsp(4052i32)
    let kp601 = vsp(601i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp3166 = vsp(3166i32)
    let kp2598 = vsp(2598i32)
    let kp1931 = vsp(1931i32)
    let kp3612 = vsp(3612i32)
    let kp3920 = vsp(3920i32)
    let kp1189 = vsp(1189i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp3406 = vsp(3406i32)
    let kp2276 = vsp(2276i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 16usize * st)
    var s2 = vld(t, off + 8usize * st)
    var s3 = vld(t, off + 24usize * st)
    var s4 = vld(t, off + 4usize * st)
    var s5 = vld(t, off + 20usize * st)
    var s6 = vld(t, off + 12usize * st)
    var s7 = vld(t, off + 28usize * st)
    var s8 = vld(t, off + 2usize * st)
    var s9 = vld(t, off + 18usize * st)
    var s10 = vld(t, off + 10usize * st)
    var s11 = vld(t, off + 26usize * st)
    var s12 = vld(t, off + 6usize * st)
    var s13 = vld(t, off + 22usize * st)
    var s14 = vld(t, off + 14usize * st)
    var s15 = vld(t, off + 30usize * st)
    var s16 = vld(t, off + 1usize * st)
    var s17 = vld(t, off + 17usize * st)
    var s18 = vld(t, off + 9usize * st)
    var s19 = vld(t, off + 25usize * st)
    var s20 = vld(t, off + 5usize * st)
    var s21 = vld(t, off + 21usize * st)
    var s22 = vld(t, off + 13usize * st)
    var s23 = vld(t, off + 29usize * st)
    var s24 = vld(t, off + 3usize * st)
    var s25 = vld(t, off + 19usize * st)
    var s26 = vld(t, off + 11usize * st)
    var s27 = vld(t, off + 27usize * st)
    var s28 = vld(t, off + 7usize * st)
    var s29 = vld(t, off + 23usize * st)
    var s30 = vld(t, off + 15usize * st)
    var s31 = vld(t, off + 31usize * st)
    var s32 = (((kp2048) +% (s16 *% kp201)) -% (s31 *% kp4091)) >> 12u32
    s16 = (((kp2048) +% (s16 *% kp4091)) +% (s31 *% kp201)) >> 12u32
    s31 = (((kp2048) +% (s17 *% kp3035)) -% (s30 *% kp2751)) >> 12u32
    s17 = (((kp2048) +% (s17 *% kp2751)) +% (s30 *% kp3035)) >> 12u32
    s30 = (((kp2048) +% (s18 *% kp1751)) -% (s29 *% kp3703)) >> 12u32
    s18 = (((kp2048) +% (s18 *% kp3703)) +% (s29 *% kp1751)) >> 12u32
    s29 = (((kp2048) +% (s19 *% kp3857)) -% (s28 *% kp1380)) >> 12u32
    s19 = (((kp2048) +% (s19 *% kp1380)) +% (s28 *% kp3857)) >> 12u32
    s28 = (((kp2048) +% (s20 *% kp995)) -% (s27 *% kp3973)) >> 12u32
    s20 = (((kp2048) +% (s20 *% kp3973)) +% (s27 *% kp995)) >> 12u32
    s27 = (((kp2048) +% (s21 *% kp3513)) -% (s26 *% kp2106)) >> 12u32
    s21 = (((kp2048) +% (s21 *% kp2106)) +% (s26 *% kp3513)) >> 12u32
    s26 = (((kp2048) +% (s22 *% kp2440)) -% (s25 *% kp3290)) >> 12u32
    s22 = (((kp2048) +% (s22 *% kp3290)) +% (s25 *% kp2440)) >> 12u32
    s25 = (((kp2048) +% (s23 *% kp4052)) -% (s24 *% kp601)) >> 12u32
    s23 = (((kp2048) +% (s23 *% kp601)) +% (s24 *% kp4052)) >> 12u32
    s24 = (((kp2048) +% (s8 *% kp401)) -% (s15 *% kp4076)) >> 12u32
    s8 = (((kp2048) +% (s8 *% kp4076)) +% (s15 *% kp401)) >> 12u32
    s15 = (((kp2048) +% (s9 *% kp3166)) -% (s14 *% kp2598)) >> 12u32
    s9 = (((kp2048) +% (s9 *% kp2598)) +% (s14 *% kp3166)) >> 12u32
    s14 = (((kp2048) +% (s10 *% kp1931)) -% (s13 *% kp3612)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp3612)) +% (s13 *% kp1931)) >> 12u32
    s13 = (((kp2048) +% (s11 *% kp3920)) -% (s12 *% kp1189)) >> 12u32
    s11 = (((kp2048) +% (s11 *% kp1189)) +% (s12 *% kp3920)) >> 12u32
    s12 = vclp((s32 +% s31), lo, hi)
    s31 = vclp((s32 -% s31), lo, hi)
    s32 = vclp((s29 +% s30), lo, hi)
    s29 = vclp((s29 -% s30), lo, hi)
    s30 = vclp((s28 +% s27), lo, hi)
    s27 = vclp((s28 -% s27), lo, hi)
    s28 = vclp((s25 +% s26), lo, hi)
    s25 = vclp((s25 -% s26), lo, hi)
    s26 = vclp((s23 +% s22), lo, hi)
    s22 = vclp((s23 -% s22), lo, hi)
    s23 = vclp((s20 +% s21), lo, hi)
    s20 = vclp((s20 -% s21), lo, hi)
    s21 = vclp((s19 +% s18), lo, hi)
    s18 = vclp((s19 -% s18), lo, hi)
    s19 = vclp((s16 +% s17), lo, hi)
    s16 = vclp((s16 -% s17), lo, hi)
    s17 = (((kp2048) +% (s4 *% kp799)) -% (s7 *% kp4017)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp4017)) +% (s7 *% kp799)) >> 12u32
    s7 = (((kp2048) +% (s5 *% kp3406)) -% (s6 *% kp2276)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp2276)) +% (s6 *% kp3406)) >> 12u32
    s6 = vclp((s24 +% s15), lo, hi)
    s15 = vclp((s24 -% s15), lo, hi)
    s24 = vclp((s13 +% s14), lo, hi)
    s13 = vclp((s13 -% s14), lo, hi)
    s14 = vclp((s11 +% s10), lo, hi)
    s10 = vclp((s11 -% s10), lo, hi)
    s11 = vclp((s8 +% s9), lo, hi)
    s8 = vclp((s8 -% s9), lo, hi)
    s9 = (((kp2048) +% (s16 *% kp799)) -% (s31 *% kp4017)) >> 12u32
    s16 = (((kp2048) +% (s16 *% kp4017)) +% (s31 *% kp799)) >> 12u32
    s31 = (((kp2048) -% (s18 *% kp4017)) -% (s29 *% kp799)) >> 12u32
    s18 = (((kp2048) +% (s18 *% kp799)) -% (s29 *% kp4017)) >> 12u32
    s29 = (((kp2048) +% (s20 *% kp3406)) -% (s27 *% kp2276)) >> 12u32
    s20 = (((kp2048) +% (s20 *% kp2276)) +% (s27 *% kp3406)) >> 12u32
    s27 = (((kp2048) -% (s22 *% kp2276)) -% (s25 *% kp3406)) >> 12u32
    s22 = (((kp2048) +% (s22 *% kp3406)) -% (s25 *% kp2276)) >> 12u32
    s25 = (((kp2048) +% (s0 *% kp2896)) -% (s1 *% kp2896)) >> 12u32
    s0 = (((kp2048) +% (s0 *% kp2896)) +% (s1 *% kp2896)) >> 12u32
    s1 = (((kp2048) +% (s2 *% kp1567)) -% (s3 *% kp3784)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3784)) +% (s3 *% kp1567)) >> 12u32
    s3 = vclp((s17 +% s7), lo, hi)
    s7 = vclp((s17 -% s7), lo, hi)
    s17 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = (((kp2048) +% (s8 *% kp1567)) -% (s15 *% kp3784)) >> 12u32
    s8 = (((kp2048) +% (s8 *% kp3784)) +% (s15 *% kp1567)) >> 12u32
    s15 = (((kp2048) -% (s10 *% kp3784)) -% (s13 *% kp1567)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp1567)) -% (s13 *% kp3784)) >> 12u32
    s13 = vclp((s12 +% s32), lo, hi)
    s12 = vclp((s12 -% s32), lo, hi)
    s32 = vclp((s9 +% s31), lo, hi)
    s9 = vclp((s9 -% s31), lo, hi)
    s31 = vclp((s28 +% s30), lo, hi)
    s28 = vclp((s28 -% s30), lo, hi)
    s30 = vclp((s27 +% s29), lo, hi)
    s27 = vclp((s27 -% s29), lo, hi)
    s29 = vclp((s26 +% s23), lo, hi)
    s23 = vclp((s26 -% s23), lo, hi)
    s26 = vclp((s22 +% s20), lo, hi)
    s20 = vclp((s22 -% s20), lo, hi)
    s22 = vclp((s19 +% s21), lo, hi)
    s19 = vclp((s19 -% s21), lo, hi)
    s21 = vclp((s16 +% s18), lo, hi)
    s16 = vclp((s16 -% s18), lo, hi)
    s18 = vclp((s0 +% s2), lo, hi)
    s0 = vclp((s0 -% s2), lo, hi)
    s2 = vclp((s25 +% s1), lo, hi)
    s1 = vclp((s25 -% s1), lo, hi)
    s25 = (((kp2048) +% (s4 *% kp2896)) -% (s7 *% kp2896)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp2896)) +% (s7 *% kp2896)) >> 12u32
    s7 = vclp((s6 +% s24), lo, hi)
    s6 = vclp((s6 -% s24), lo, hi)
    s24 = vclp((s5 +% s15), lo, hi)
    s5 = vclp((s5 -% s15), lo, hi)
    s15 = vclp((s11 +% s14), lo, hi)
    s11 = vclp((s11 -% s14), lo, hi)
    s14 = vclp((s8 +% s10), lo, hi)
    s8 = vclp((s8 -% s10), lo, hi)
    s10 = (((kp2048) +% (s16 *% kp1567)) -% (s9 *% kp3784)) >> 12u32
    s9 = (((kp2048) +% (s16 *% kp3784)) +% (s9 *% kp1567)) >> 12u32
    s16 = (((kp2048) +% (s19 *% kp1567)) -% (s12 *% kp3784)) >> 12u32
    s12 = (((kp2048) +% (s19 *% kp3784)) +% (s12 *% kp1567)) >> 12u32
    s19 = (((kp2048) -% (s23 *% kp3784)) -% (s28 *% kp1567)) >> 12u32
    s23 = (((kp2048) +% (s23 *% kp1567)) -% (s28 *% kp3784)) >> 12u32
    s28 = (((kp2048) -% (s20 *% kp3784)) -% (s27 *% kp1567)) >> 12u32
    s20 = (((kp2048) +% (s20 *% kp1567)) -% (s27 *% kp3784)) >> 12u32
    s27 = vclp((s18 +% s17), lo, hi)
    s17 = vclp((s18 -% s17), lo, hi)
    s18 = vclp((s2 +% s4), lo, hi)
    s2 = vclp((s2 -% s4), lo, hi)
    s4 = vclp((s1 +% s25), lo, hi)
    s1 = vclp((s1 -% s25), lo, hi)
    s25 = vclp((s0 +% s3), lo, hi)
    s0 = vclp((s0 -% s3), lo, hi)
    s3 = (((kp2048) +% (s8 *% kp2896)) -% (s5 *% kp2896)) >> 12u32
    s5 = (((kp2048) +% (s8 *% kp2896)) +% (s5 *% kp2896)) >> 12u32
    s8 = (((kp2048) +% (s11 *% kp2896)) -% (s6 *% kp2896)) >> 12u32
    s6 = (((kp2048) +% (s11 *% kp2896)) +% (s6 *% kp2896)) >> 12u32
    s11 = vclp((s13 +% s31), lo, hi)
    s13 = vclp((s13 -% s31), lo, hi)
    s31 = vclp((s32 +% s30), lo, hi)
    s30 = vclp((s32 -% s30), lo, hi)
    s32 = vclp((s10 +% s28), lo, hi)
    s10 = vclp((s10 -% s28), lo, hi)
    s28 = vclp((s16 +% s19), lo, hi)
    s16 = vclp((s16 -% s19), lo, hi)
    s19 = vclp((s22 +% s29), lo, hi)
    s22 = vclp((s22 -% s29), lo, hi)
    s29 = vclp((s21 +% s26), lo, hi)
    s21 = vclp((s21 -% s26), lo, hi)
    s26 = vclp((s9 +% s20), lo, hi)
    s9 = vclp((s9 -% s20), lo, hi)
    s20 = vclp((s12 +% s23), lo, hi)
    s12 = vclp((s12 -% s23), lo, hi)
    s23 = vclp((s27 +% s15), lo, hi)
    s15 = vclp((s27 -% s15), lo, hi)
    s27 = vclp((s18 +% s14), lo, hi)
    s14 = vclp((s18 -% s14), lo, hi)
    s18 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = vclp((s25 +% s6), lo, hi)
    s6 = vclp((s25 -% s6), lo, hi)
    s25 = vclp((s0 +% s8), lo, hi)
    s0 = vclp((s0 -% s8), lo, hi)
    s8 = vclp((s1 +% s3), lo, hi)
    s1 = vclp((s1 -% s3), lo, hi)
    s3 = vclp((s2 +% s24), lo, hi)
    s2 = vclp((s2 -% s24), lo, hi)
    s24 = vclp((s17 +% s7), lo, hi)
    s7 = vclp((s17 -% s7), lo, hi)
    s17 = (((kp2048) +% (s12 *% kp2896)) -% (s16 *% kp2896)) >> 12u32
    s12 = (((kp2048) +% (s12 *% kp2896)) +% (s16 *% kp2896)) >> 12u32
    s16 = (((kp2048) +% (s9 *% kp2896)) -% (s10 *% kp2896)) >> 12u32
    s9 = (((kp2048) +% (s9 *% kp2896)) +% (s10 *% kp2896)) >> 12u32
    s10 = (((kp2048) +% (s21 *% kp2896)) -% (s30 *% kp2896)) >> 12u32
    s21 = (((kp2048) +% (s21 *% kp2896)) +% (s30 *% kp2896)) >> 12u32
    s30 = (((kp2048) +% (s22 *% kp2896)) -% (s13 *% kp2896)) >> 12u32
    s13 = (((kp2048) +% (s22 *% kp2896)) +% (s13 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s23 +% s19), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s27 +% s29), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s18 +% s26), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s5 +% s20), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s25 +% s12), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s8 +% s9), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s3 +% s21), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s24 +% s13), lo, hi)))
    vst(t, off + 8usize * st, (vclp((s7 +% s30), lo, hi)))
    vst(t, off + 9usize * st, (vclp((s2 +% s10), lo, hi)))
    vst(t, off + 10usize * st, (vclp((s1 +% s16), lo, hi)))
    vst(t, off + 11usize * st, (vclp((s0 +% s17), lo, hi)))
    vst(t, off + 12usize * st, (vclp((s6 +% s28), lo, hi)))
    vst(t, off + 13usize * st, (vclp((s4 +% s32), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s14 +% s31), lo, hi)))
    vst(t, off + 15usize * st, (vclp((s15 +% s11), lo, hi)))
    vst(t, off + 16usize * st, (vclp((s15 -% s11), lo, hi)))
    vst(t, off + 17usize * st, (vclp((s14 -% s31), lo, hi)))
    vst(t, off + 18usize * st, (vclp((s4 -% s32), lo, hi)))
    vst(t, off + 19usize * st, (vclp((s6 -% s28), lo, hi)))
    vst(t, off + 20usize * st, (vclp((s0 -% s17), lo, hi)))
    vst(t, off + 21usize * st, (vclp((s1 -% s16), lo, hi)))
    vst(t, off + 22usize * st, (vclp((s2 -% s10), lo, hi)))
    vst(t, off + 23usize * st, (vclp((s7 -% s30), lo, hi)))
    vst(t, off + 24usize * st, (vclp((s24 -% s13), lo, hi)))
    vst(t, off + 25usize * st, (vclp((s3 -% s21), lo, hi)))
    vst(t, off + 26usize * st, (vclp((s8 -% s9), lo, hi)))
    vst(t, off + 27usize * st, (vclp((s25 -% s12), lo, hi)))
    vst(t, off + 28usize * st, (vclp((s5 -% s20), lo, hi)))
    vst(t, off + 29usize * st, (vclp((s18 -% s26), lo, hi)))
    vst(t, off + 30usize * st, (vclp((s27 -% s29), lo, hi)))
    vst(t, off + 31usize * st, (vclp((s23 -% s19), lo, hi)))
    }
}

fn vidct64(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp101 = vsp(101i32)
    let kp4095 = vsp(4095i32)
    let kp2824 = vsp(2824i32)
    let kp2967 = vsp(2967i32)
    let kp1660 = vsp(1660i32)
    let kp3745 = vsp(3745i32)
    let kp1474 = vsp(1474i32)
    let kp3822 = vsp(3822i32)
    let kp897 = vsp(897i32)
    let kp3996 = vsp(3996i32)
    let kp2191 = vsp(2191i32)
    let kp3461 = vsp(3461i32)
    let kp2359 = vsp(2359i32)
    let kp3349 = vsp(3349i32)
    let kp700 = vsp(700i32)
    let kp4036 = vsp(4036i32)
    let kp501 = vsp(501i32)
    let kp4065 = vsp(4065i32)
    let kp2520 = vsp(2520i32)
    let kp3229 = vsp(3229i32)
    let kp2019 = vsp(2019i32)
    let kp3564 = vsp(3564i32)
    let kp1092 = vsp(1092i32)
    let kp3948 = vsp(3948i32)
    let kp1285 = vsp(1285i32)
    let kp3889 = vsp(3889i32)
    let kp1842 = vsp(1842i32)
    let kp3659 = vsp(3659i32)
    let kp2675 = vsp(2675i32)
    let kp3102 = vsp(3102i32)
    let kp301 = vsp(301i32)
    let kp4085 = vsp(4085i32)
    let kp201 = vsp(201i32)
    let kp4091 = vsp(4091i32)
    let kp2751 = vsp(2751i32)
    let kp3035 = vsp(3035i32)
    let kp1751 = vsp(1751i32)
    let kp3703 = vsp(3703i32)
    let kp1380 = vsp(1380i32)
    let kp3857 = vsp(3857i32)
    let kp995 = vsp(995i32)
    let kp3973 = vsp(3973i32)
    let kp2106 = vsp(2106i32)
    let kp3513 = vsp(3513i32)
    let kp2440 = vsp(2440i32)
    let kp3290 = vsp(3290i32)
    let kp601 = vsp(601i32)
    let kp4052 = vsp(4052i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp2598 = vsp(2598i32)
    let kp3166 = vsp(3166i32)
    let kp1931 = vsp(1931i32)
    let kp3612 = vsp(3612i32)
    let kp1189 = vsp(1189i32)
    let kp3920 = vsp(3920i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp2276 = vsp(2276i32)
    let kp3406 = vsp(3406i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 16usize * st)
    var s2 = vld(t, off + 8usize * st)
    var s3 = vld(t, off + 24usize * st)
    var s4 = vld(t, off + 4usize * st)
    var s5 = vld(t, off + 20usize * st)
    var s6 = vld(t, off + 12usize * st)
    var s7 = vld(t, off + 28usize * st)
    var s8 = vld(t, off + 2usize * st)
    var s9 = vld(t, off + 18usize * st)
    var s10 = vld(t, off + 10usize * st)
    var s11 = vld(t, off + 26usize * st)
    var s12 = vld(t, off + 6usize * st)
    var s13 = vld(t, off + 22usize * st)
    var s14 = vld(t, off + 14usize * st)
    var s15 = vld(t, off + 30usize * st)
    var s16 = vld(t, off + 1usize * st)
    var s17 = vld(t, off + 17usize * st)
    var s18 = vld(t, off + 9usize * st)
    var s19 = vld(t, off + 25usize * st)
    var s20 = vld(t, off + 5usize * st)
    var s21 = vld(t, off + 21usize * st)
    var s22 = vld(t, off + 13usize * st)
    var s23 = vld(t, off + 29usize * st)
    var s24 = vld(t, off + 3usize * st)
    var s25 = vld(t, off + 19usize * st)
    var s26 = vld(t, off + 11usize * st)
    var s27 = vld(t, off + 27usize * st)
    var s28 = vld(t, off + 7usize * st)
    var s29 = vld(t, off + 23usize * st)
    var s30 = vld(t, off + 15usize * st)
    var s31 = vld(t, off + 31usize * st)
    var s32 = ((kp2048) +% (s16 *% kp101)) >> 12u32
    s16 = ((kp2048) +% (s16 *% kp4095)) >> 12u32
    var s33 = ((kp2048) -% (s31 *% kp2824)) >> 12u32
    s31 = ((kp2048) +% (s31 *% kp2967)) >> 12u32
    var s34 = ((kp2048) +% (s17 *% kp1660)) >> 12u32
    s17 = ((kp2048) +% (s17 *% kp3745)) >> 12u32
    var s35 = ((kp2048) -% (s30 *% kp1474)) >> 12u32
    s30 = ((kp2048) +% (s30 *% kp3822)) >> 12u32
    var s36 = ((kp2048) +% (s18 *% kp897)) >> 12u32
    s18 = ((kp2048) +% (s18 *% kp3996)) >> 12u32
    var s37 = ((kp2048) -% (s29 *% kp2191)) >> 12u32
    s29 = ((kp2048) +% (s29 *% kp3461)) >> 12u32
    var s38 = ((kp2048) +% (s19 *% kp2359)) >> 12u32
    s19 = ((kp2048) +% (s19 *% kp3349)) >> 12u32
    var s39 = ((kp2048) -% (s28 *% kp700)) >> 12u32
    s28 = ((kp2048) +% (s28 *% kp4036)) >> 12u32
    var s40 = ((kp2048) +% (s20 *% kp501)) >> 12u32
    s20 = ((kp2048) +% (s20 *% kp4065)) >> 12u32
    var s41 = ((kp2048) -% (s27 *% kp2520)) >> 12u32
    s27 = ((kp2048) +% (s27 *% kp3229)) >> 12u32
    var s42 = ((kp2048) +% (s21 *% kp2019)) >> 12u32
    s21 = ((kp2048) +% (s21 *% kp3564)) >> 12u32
    var s43 = ((kp2048) -% (s26 *% kp1092)) >> 12u32
    s26 = ((kp2048) +% (s26 *% kp3948)) >> 12u32
    var s44 = ((kp2048) +% (s22 *% kp1285)) >> 12u32
    s22 = ((kp2048) +% (s22 *% kp3889)) >> 12u32
    var s45 = ((kp2048) -% (s25 *% kp1842)) >> 12u32
    s25 = ((kp2048) +% (s25 *% kp3659)) >> 12u32
    var s46 = ((kp2048) +% (s23 *% kp2675)) >> 12u32
    s23 = ((kp2048) +% (s23 *% kp3102)) >> 12u32
    var s47 = ((kp2048) -% (s24 *% kp301)) >> 12u32
    s24 = ((kp2048) +% (s24 *% kp4085)) >> 12u32
    var s48 = ((kp2048) +% (s8 *% kp201)) >> 12u32
    s8 = ((kp2048) +% (s8 *% kp4091)) >> 12u32
    var s49 = ((kp2048) -% (s15 *% kp2751)) >> 12u32
    s15 = ((kp2048) +% (s15 *% kp3035)) >> 12u32
    var s50 = ((kp2048) +% (s9 *% kp1751)) >> 12u32
    s9 = ((kp2048) +% (s9 *% kp3703)) >> 12u32
    var s51 = ((kp2048) -% (s14 *% kp1380)) >> 12u32
    s14 = ((kp2048) +% (s14 *% kp3857)) >> 12u32
    var s52 = ((kp2048) +% (s10 *% kp995)) >> 12u32
    s10 = ((kp2048) +% (s10 *% kp3973)) >> 12u32
    var s53 = ((kp2048) -% (s13 *% kp2106)) >> 12u32
    s13 = ((kp2048) +% (s13 *% kp3513)) >> 12u32
    var s54 = ((kp2048) +% (s11 *% kp2440)) >> 12u32
    s11 = ((kp2048) +% (s11 *% kp3290)) >> 12u32
    var s55 = ((kp2048) -% (s12 *% kp601)) >> 12u32
    s12 = ((kp2048) +% (s12 *% kp4052)) >> 12u32
    var s56 = vclp((s32 +% s33), lo, hi)
    s32 = vclp((s32 -% s33), lo, hi)
    s33 = vclp((s35 +% s34), lo, hi)
    s34 = vclp((s35 -% s34), lo, hi)
    s35 = vclp((s36 +% s37), lo, hi)
    s36 = vclp((s36 -% s37), lo, hi)
    s37 = vclp((s39 +% s38), lo, hi)
    s38 = vclp((s39 -% s38), lo, hi)
    s39 = vclp((s40 +% s41), lo, hi)
    s40 = vclp((s40 -% s41), lo, hi)
    s41 = vclp((s43 +% s42), lo, hi)
    s42 = vclp((s43 -% s42), lo, hi)
    s43 = vclp((s44 +% s45), lo, hi)
    s44 = vclp((s44 -% s45), lo, hi)
    s45 = vclp((s47 +% s46), lo, hi)
    s46 = vclp((s47 -% s46), lo, hi)
    s47 = vclp((s24 +% s23), lo, hi)
    s23 = vclp((s24 -% s23), lo, hi)
    s24 = vclp((s22 +% s25), lo, hi)
    s22 = vclp((s22 -% s25), lo, hi)
    s25 = vclp((s26 +% s21), lo, hi)
    s21 = vclp((s26 -% s21), lo, hi)
    s26 = vclp((s20 +% s27), lo, hi)
    s20 = vclp((s20 -% s27), lo, hi)
    s27 = vclp((s28 +% s19), lo, hi)
    s19 = vclp((s28 -% s19), lo, hi)
    s28 = vclp((s18 +% s29), lo, hi)
    s18 = vclp((s18 -% s29), lo, hi)
    s29 = vclp((s30 +% s17), lo, hi)
    s17 = vclp((s30 -% s17), lo, hi)
    s30 = vclp((s16 +% s31), lo, hi)
    s16 = vclp((s16 -% s31), lo, hi)
    s31 = ((kp2048) +% (s4 *% kp401)) >> 12u32
    s4 = ((kp2048) +% (s4 *% kp4076)) >> 12u32
    var s57 = ((kp2048) -% (s7 *% kp2598)) >> 12u32
    s7 = ((kp2048) +% (s7 *% kp3166)) >> 12u32
    var s58 = ((kp2048) +% (s5 *% kp1931)) >> 12u32
    s5 = ((kp2048) +% (s5 *% kp3612)) >> 12u32
    var s59 = ((kp2048) -% (s6 *% kp1189)) >> 12u32
    s6 = ((kp2048) +% (s6 *% kp3920)) >> 12u32
    var s60 = vclp((s48 +% s49), lo, hi)
    s48 = vclp((s48 -% s49), lo, hi)
    s49 = vclp((s51 +% s50), lo, hi)
    s50 = vclp((s51 -% s50), lo, hi)
    s51 = vclp((s52 +% s53), lo, hi)
    s52 = vclp((s52 -% s53), lo, hi)
    s53 = vclp((s55 +% s54), lo, hi)
    s54 = vclp((s55 -% s54), lo, hi)
    s55 = vclp((s12 +% s11), lo, hi)
    s11 = vclp((s12 -% s11), lo, hi)
    s12 = vclp((s10 +% s13), lo, hi)
    s10 = vclp((s10 -% s13), lo, hi)
    s13 = vclp((s14 +% s9), lo, hi)
    s9 = vclp((s14 -% s9), lo, hi)
    s14 = vclp((s8 +% s15), lo, hi)
    s8 = vclp((s8 -% s15), lo, hi)
    s15 = (((kp2048) +% (s16 *% kp401)) -% (s32 *% kp4076)) >> 12u32
    s16 = (((kp2048) +% (s16 *% kp4076)) +% (s32 *% kp401)) >> 12u32
    s32 = (((kp2048) -% (s17 *% kp4076)) -% (s34 *% kp401)) >> 12u32
    s17 = (((kp2048) +% (s17 *% kp401)) -% (s34 *% kp4076)) >> 12u32
    s34 = (((kp2048) +% (s18 *% kp3166)) -% (s36 *% kp2598)) >> 12u32
    s18 = (((kp2048) +% (s18 *% kp2598)) +% (s36 *% kp3166)) >> 12u32
    s36 = (((kp2048) -% (s19 *% kp2598)) -% (s38 *% kp3166)) >> 12u32
    s19 = (((kp2048) +% (s19 *% kp3166)) -% (s38 *% kp2598)) >> 12u32
    s38 = (((kp2048) +% (s20 *% kp1931)) -% (s40 *% kp3612)) >> 12u32
    s20 = (((kp2048) +% (s20 *% kp3612)) +% (s40 *% kp1931)) >> 12u32
    s40 = (((kp2048) -% (s21 *% kp3612)) -% (s42 *% kp1931)) >> 12u32
    s21 = (((kp2048) +% (s21 *% kp1931)) -% (s42 *% kp3612)) >> 12u32
    s42 = (((kp2048) +% (s22 *% kp3920)) -% (s44 *% kp1189)) >> 12u32
    s22 = (((kp2048) +% (s22 *% kp1189)) +% (s44 *% kp3920)) >> 12u32
    s44 = (((kp2048) -% (s23 *% kp1189)) -% (s46 *% kp3920)) >> 12u32
    s23 = (((kp2048) +% (s23 *% kp3920)) -% (s46 *% kp1189)) >> 12u32
    s46 = ((kp2048) +% (s2 *% kp799)) >> 12u32
    s2 = ((kp2048) +% (s2 *% kp4017)) >> 12u32
    var s61 = ((kp2048) -% (s3 *% kp2276)) >> 12u32
    s3 = ((kp2048) +% (s3 *% kp3406)) >> 12u32
    var s62 = vclp((s31 +% s57), lo, hi)
    s31 = vclp((s31 -% s57), lo, hi)
    s57 = vclp((s59 +% s58), lo, hi)
    s58 = vclp((s59 -% s58), lo, hi)
    s59 = vclp((s6 +% s5), lo, hi)
    s5 = vclp((s6 -% s5), lo, hi)
    s6 = vclp((s4 +% s7), lo, hi)
    s4 = vclp((s4 -% s7), lo, hi)
    s7 = (((kp2048) +% (s8 *% kp799)) -% (s48 *% kp4017)) >> 12u32
    s8 = (((kp2048) +% (s8 *% kp4017)) +% (s48 *% kp799)) >> 12u32
    s48 = (((kp2048) -% (s9 *% kp4017)) -% (s50 *% kp799)) >> 12u32
    s9 = (((kp2048) +% (s9 *% kp799)) -% (s50 *% kp4017)) >> 12u32
    s50 = (((kp2048) +% (s10 *% kp3406)) -% (s52 *% kp2276)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp2276)) +% (s52 *% kp3406)) >> 12u32
    s52 = (((kp2048) -% (s11 *% kp2276)) -% (s54 *% kp3406)) >> 12u32
    s11 = (((kp2048) +% (s11 *% kp3406)) -% (s54 *% kp2276)) >> 12u32
    s54 = vclp((s56 +% s33), lo, hi)
    s33 = vclp((s56 -% s33), lo, hi)
    s56 = vclp((s15 +% s32), lo, hi)
    s15 = vclp((s15 -% s32), lo, hi)
    s32 = vclp((s37 +% s35), lo, hi)
    s35 = vclp((s37 -% s35), lo, hi)
    s37 = vclp((s36 +% s34), lo, hi)
    s34 = vclp((s36 -% s34), lo, hi)
    s36 = vclp((s39 +% s41), lo, hi)
    s39 = vclp((s39 -% s41), lo, hi)
    s41 = vclp((s38 +% s40), lo, hi)
    s38 = vclp((s38 -% s40), lo, hi)
    s40 = vclp((s45 +% s43), lo, hi)
    s43 = vclp((s45 -% s43), lo, hi)
    s45 = vclp((s44 +% s42), lo, hi)
    s42 = vclp((s44 -% s42), lo, hi)
    s44 = vclp((s47 +% s24), lo, hi)
    s24 = vclp((s47 -% s24), lo, hi)
    s47 = vclp((s23 +% s22), lo, hi)
    s22 = vclp((s23 -% s22), lo, hi)
    s23 = vclp((s26 +% s25), lo, hi)
    s25 = vclp((s26 -% s25), lo, hi)
    s26 = vclp((s20 +% s21), lo, hi)
    s20 = vclp((s20 -% s21), lo, hi)
    s21 = vclp((s27 +% s28), lo, hi)
    s27 = vclp((s27 -% s28), lo, hi)
    s28 = vclp((s19 +% s18), lo, hi)
    s18 = vclp((s19 -% s18), lo, hi)
    s19 = vclp((s30 +% s29), lo, hi)
    s29 = vclp((s30 -% s29), lo, hi)
    s30 = vclp((s16 +% s17), lo, hi)
    s16 = vclp((s16 -% s17), lo, hi)
    s17 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    s0 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    var s63 = ((kp2048) +% (s1 *% kp1567)) >> 12u32
    s1 = ((kp2048) +% (s1 *% kp3784)) >> 12u32
    var s64 = vclp((s46 +% s61), lo, hi)
    s46 = vclp((s46 -% s61), lo, hi)
    s61 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = (((kp2048) +% (s4 *% kp1567)) -% (s31 *% kp3784)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp3784)) +% (s31 *% kp1567)) >> 12u32
    s31 = (((kp2048) -% (s5 *% kp3784)) -% (s58 *% kp1567)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp1567)) -% (s58 *% kp3784)) >> 12u32
    s58 = vclp((s60 +% s49), lo, hi)
    s49 = vclp((s60 -% s49), lo, hi)
    s60 = vclp((s7 +% s48), lo, hi)
    s7 = vclp((s7 -% s48), lo, hi)
    s48 = vclp((s53 +% s51), lo, hi)
    s51 = vclp((s53 -% s51), lo, hi)
    s53 = vclp((s52 +% s50), lo, hi)
    s50 = vclp((s52 -% s50), lo, hi)
    s52 = vclp((s55 +% s12), lo, hi)
    s12 = vclp((s55 -% s12), lo, hi)
    s55 = vclp((s11 +% s10), lo, hi)
    s10 = vclp((s11 -% s10), lo, hi)
    s11 = vclp((s14 +% s13), lo, hi)
    s13 = vclp((s14 -% s13), lo, hi)
    s14 = vclp((s8 +% s9), lo, hi)
    s8 = vclp((s8 -% s9), lo, hi)
    s9 = (((kp2048) +% (s16 *% kp799)) -% (s15 *% kp4017)) >> 12u32
    s15 = (((kp2048) +% (s16 *% kp4017)) +% (s15 *% kp799)) >> 12u32
    s16 = (((kp2048) +% (s29 *% kp799)) -% (s33 *% kp4017)) >> 12u32
    s29 = (((kp2048) +% (s29 *% kp4017)) +% (s33 *% kp799)) >> 12u32
    s33 = (((kp2048) -% (s27 *% kp4017)) -% (s35 *% kp799)) >> 12u32
    s27 = (((kp2048) +% (s27 *% kp799)) -% (s35 *% kp4017)) >> 12u32
    s35 = (((kp2048) -% (s18 *% kp4017)) -% (s34 *% kp799)) >> 12u32
    s18 = (((kp2048) +% (s18 *% kp799)) -% (s34 *% kp4017)) >> 12u32
    s34 = (((kp2048) +% (s20 *% kp3406)) -% (s38 *% kp2276)) >> 12u32
    s20 = (((kp2048) +% (s20 *% kp2276)) +% (s38 *% kp3406)) >> 12u32
    s38 = (((kp2048) +% (s25 *% kp3406)) -% (s39 *% kp2276)) >> 12u32
    s25 = (((kp2048) +% (s25 *% kp2276)) +% (s39 *% kp3406)) >> 12u32
    s39 = (((kp2048) -% (s24 *% kp2276)) -% (s43 *% kp3406)) >> 12u32
    s24 = (((kp2048) +% (s24 *% kp3406)) -% (s43 *% kp2276)) >> 12u32
    s43 = (((kp2048) -% (s22 *% kp2276)) -% (s42 *% kp3406)) >> 12u32
    s22 = (((kp2048) +% (s22 *% kp3406)) -% (s42 *% kp2276)) >> 12u32
    s42 = vclp((s0 +% s1), lo, hi)
    s0 = vclp((s0 -% s1), lo, hi)
    s1 = vclp((s17 +% s63), lo, hi)
    s17 = vclp((s17 -% s63), lo, hi)
    s63 = (((kp2048) +% (s2 *% kp2896)) -% (s46 *% kp2896)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp2896)) +% (s46 *% kp2896)) >> 12u32
    s46 = vclp((s62 +% s57), lo, hi)
    s57 = vclp((s62 -% s57), lo, hi)
    s62 = vclp((s3 +% s31), lo, hi)
    s3 = vclp((s3 -% s31), lo, hi)
    s31 = vclp((s6 +% s59), lo, hi)
    s6 = vclp((s6 -% s59), lo, hi)
    s59 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = (((kp2048) +% (s8 *% kp1567)) -% (s7 *% kp3784)) >> 12u32
    s7 = (((kp2048) +% (s8 *% kp3784)) +% (s7 *% kp1567)) >> 12u32
    s8 = (((kp2048) +% (s13 *% kp1567)) -% (s49 *% kp3784)) >> 12u32
    s13 = (((kp2048) +% (s13 *% kp3784)) +% (s49 *% kp1567)) >> 12u32
    s49 = (((kp2048) -% (s12 *% kp3784)) -% (s51 *% kp1567)) >> 12u32
    s12 = (((kp2048) +% (s12 *% kp1567)) -% (s51 *% kp3784)) >> 12u32
    s51 = (((kp2048) -% (s10 *% kp3784)) -% (s50 *% kp1567)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp1567)) -% (s50 *% kp3784)) >> 12u32
    s50 = vclp((s54 +% s32), lo, hi)
    s32 = vclp((s54 -% s32), lo, hi)
    s54 = vclp((s56 +% s37), lo, hi)
    s37 = vclp((s56 -% s37), lo, hi)
    s56 = vclp((s9 +% s35), lo, hi)
    s9 = vclp((s9 -% s35), lo, hi)
    s35 = vclp((s16 +% s33), lo, hi)
    s16 = vclp((s16 -% s33), lo, hi)
    s33 = vclp((s40 +% s36), lo, hi)
    s36 = vclp((s40 -% s36), lo, hi)
    s40 = vclp((s45 +% s41), lo, hi)
    s41 = vclp((s45 -% s41), lo, hi)
    s45 = vclp((s43 +% s34), lo, hi)
    s34 = vclp((s43 -% s34), lo, hi)
    s43 = vclp((s39 +% s38), lo, hi)
    s38 = vclp((s39 -% s38), lo, hi)
    s39 = vclp((s44 +% s23), lo, hi)
    s23 = vclp((s44 -% s23), lo, hi)
    s44 = vclp((s47 +% s26), lo, hi)
    s26 = vclp((s47 -% s26), lo, hi)
    s47 = vclp((s22 +% s20), lo, hi)
    s20 = vclp((s22 -% s20), lo, hi)
    s22 = vclp((s24 +% s25), lo, hi)
    s24 = vclp((s24 -% s25), lo, hi)
    s25 = vclp((s19 +% s21), lo, hi)
    s19 = vclp((s19 -% s21), lo, hi)
    s21 = vclp((s30 +% s28), lo, hi)
    s28 = vclp((s30 -% s28), lo, hi)
    s30 = vclp((s15 +% s18), lo, hi)
    s15 = vclp((s15 -% s18), lo, hi)
    s18 = vclp((s29 +% s27), lo, hi)
    s27 = vclp((s29 -% s27), lo, hi)
    s29 = vclp((s42 +% s61), lo, hi)
    s42 = vclp((s42 -% s61), lo, hi)
    s61 = vclp((s1 +% s2), lo, hi)
    s1 = vclp((s1 -% s2), lo, hi)
    s2 = vclp((s17 +% s63), lo, hi)
    s17 = vclp((s17 -% s63), lo, hi)
    s63 = vclp((s0 +% s64), lo, hi)
    s0 = vclp((s0 -% s64), lo, hi)
    s64 = (((kp2048) +% (s4 *% kp2896)) -% (s3 *% kp2896)) >> 12u32
    s3 = (((kp2048) +% (s4 *% kp2896)) +% (s3 *% kp2896)) >> 12u32
    s4 = (((kp2048) +% (s6 *% kp2896)) -% (s57 *% kp2896)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp2896)) +% (s57 *% kp2896)) >> 12u32
    s57 = vclp((s58 +% s48), lo, hi)
    s48 = vclp((s58 -% s48), lo, hi)
    s58 = vclp((s60 +% s53), lo, hi)
    s53 = vclp((s60 -% s53), lo, hi)
    s60 = vclp((s5 +% s51), lo, hi)
    s5 = vclp((s5 -% s51), lo, hi)
    s51 = vclp((s8 +% s49), lo, hi)
    s8 = vclp((s8 -% s49), lo, hi)
    s49 = vclp((s11 +% s52), lo, hi)
    s11 = vclp((s11 -% s52), lo, hi)
    s52 = vclp((s14 +% s55), lo, hi)
    s14 = vclp((s14 -% s55), lo, hi)
    s55 = vclp((s7 +% s10), lo, hi)
    s7 = vclp((s7 -% s10), lo, hi)
    s10 = vclp((s13 +% s12), lo, hi)
    s12 = vclp((s13 -% s12), lo, hi)
    s13 = (((kp2048) +% (s27 *% kp1567)) -% (s16 *% kp3784)) >> 12u32
    s16 = (((kp2048) +% (s27 *% kp3784)) +% (s16 *% kp1567)) >> 12u32
    s27 = (((kp2048) +% (s15 *% kp1567)) -% (s9 *% kp3784)) >> 12u32
    s9 = (((kp2048) +% (s15 *% kp3784)) +% (s9 *% kp1567)) >> 12u32
    s15 = (((kp2048) +% (s28 *% kp1567)) -% (s37 *% kp3784)) >> 12u32
    s28 = (((kp2048) +% (s28 *% kp3784)) +% (s37 *% kp1567)) >> 12u32
    s37 = (((kp2048) +% (s19 *% kp1567)) -% (s32 *% kp3784)) >> 12u32
    s19 = (((kp2048) +% (s19 *% kp3784)) +% (s32 *% kp1567)) >> 12u32
    s32 = (((kp2048) -% (s23 *% kp3784)) -% (s36 *% kp1567)) >> 12u32
    s23 = (((kp2048) +% (s23 *% kp1567)) -% (s36 *% kp3784)) >> 12u32
    s36 = (((kp2048) -% (s26 *% kp3784)) -% (s41 *% kp1567)) >> 12u32
    s26 = (((kp2048) +% (s26 *% kp1567)) -% (s41 *% kp3784)) >> 12u32
    s41 = (((kp2048) -% (s20 *% kp3784)) -% (s34 *% kp1567)) >> 12u32
    s20 = (((kp2048) +% (s20 *% kp1567)) -% (s34 *% kp3784)) >> 12u32
    s34 = (((kp2048) -% (s24 *% kp3784)) -% (s38 *% kp1567)) >> 12u32
    s24 = (((kp2048) +% (s24 *% kp1567)) -% (s38 *% kp3784)) >> 12u32
    s38 = vclp((s29 +% s31), lo, hi)
    s29 = vclp((s29 -% s31), lo, hi)
    s31 = vclp((s61 +% s59), lo, hi)
    s59 = vclp((s61 -% s59), lo, hi)
    s61 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = vclp((s63 +% s6), lo, hi)
    s6 = vclp((s63 -% s6), lo, hi)
    s63 = vclp((s0 +% s4), lo, hi)
    s0 = vclp((s0 -% s4), lo, hi)
    s4 = vclp((s17 +% s64), lo, hi)
    s17 = vclp((s17 -% s64), lo, hi)
    s64 = vclp((s1 +% s62), lo, hi)
    s1 = vclp((s1 -% s62), lo, hi)
    s62 = vclp((s42 +% s46), lo, hi)
    s42 = vclp((s42 -% s46), lo, hi)
    s46 = (((kp2048) +% (s12 *% kp2896)) -% (s8 *% kp2896)) >> 12u32
    s8 = (((kp2048) +% (s12 *% kp2896)) +% (s8 *% kp2896)) >> 12u32
    s12 = (((kp2048) +% (s7 *% kp2896)) -% (s5 *% kp2896)) >> 12u32
    s5 = (((kp2048) +% (s7 *% kp2896)) +% (s5 *% kp2896)) >> 12u32
    s7 = (((kp2048) +% (s14 *% kp2896)) -% (s53 *% kp2896)) >> 12u32
    s14 = (((kp2048) +% (s14 *% kp2896)) +% (s53 *% kp2896)) >> 12u32
    s53 = (((kp2048) +% (s11 *% kp2896)) -% (s48 *% kp2896)) >> 12u32
    s11 = (((kp2048) +% (s11 *% kp2896)) +% (s48 *% kp2896)) >> 12u32
    s48 = vclp((s50 +% s33), lo, hi)
    s33 = vclp((s50 -% s33), lo, hi)
    s50 = vclp((s25 +% s39), lo, hi)
    s25 = vclp((s25 -% s39), lo, hi)
    s39 = vclp((s54 +% s40), lo, hi)
    s40 = vclp((s54 -% s40), lo, hi)
    s54 = vclp((s21 +% s44), lo, hi)
    s21 = vclp((s21 -% s44), lo, hi)
    s44 = vclp((s56 +% s45), lo, hi)
    s45 = vclp((s56 -% s45), lo, hi)
    s56 = vclp((s30 +% s47), lo, hi)
    s30 = vclp((s30 -% s47), lo, hi)
    s47 = vclp((s35 +% s43), lo, hi)
    s35 = vclp((s35 -% s43), lo, hi)
    s43 = vclp((s18 +% s22), lo, hi)
    s18 = vclp((s18 -% s22), lo, hi)
    s22 = vclp((s13 +% s34), lo, hi)
    s13 = vclp((s13 -% s34), lo, hi)
    s34 = vclp((s16 +% s24), lo, hi)
    s16 = vclp((s16 -% s24), lo, hi)
    s24 = vclp((s27 +% s41), lo, hi)
    s27 = vclp((s27 -% s41), lo, hi)
    s41 = vclp((s9 +% s20), lo, hi)
    s9 = vclp((s9 -% s20), lo, hi)
    s20 = vclp((s15 +% s36), lo, hi)
    s15 = vclp((s15 -% s36), lo, hi)
    s36 = vclp((s28 +% s26), lo, hi)
    s26 = vclp((s28 -% s26), lo, hi)
    s28 = vclp((s37 +% s32), lo, hi)
    s32 = vclp((s37 -% s32), lo, hi)
    s37 = vclp((s19 +% s23), lo, hi)
    s19 = vclp((s19 -% s23), lo, hi)
    s23 = vclp((s38 +% s49), lo, hi)
    s38 = vclp((s38 -% s49), lo, hi)
    s49 = vclp((s31 +% s52), lo, hi)
    s31 = vclp((s31 -% s52), lo, hi)
    s52 = vclp((s61 +% s55), lo, hi)
    s55 = vclp((s61 -% s55), lo, hi)
    s61 = vclp((s3 +% s10), lo, hi)
    s3 = vclp((s3 -% s10), lo, hi)
    s10 = vclp((s63 +% s8), lo, hi)
    s8 = vclp((s63 -% s8), lo, hi)
    s63 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = vclp((s64 +% s14), lo, hi)
    s14 = vclp((s64 -% s14), lo, hi)
    s64 = vclp((s62 +% s11), lo, hi)
    s11 = vclp((s62 -% s11), lo, hi)
    s62 = vclp((s42 +% s53), lo, hi)
    s42 = vclp((s42 -% s53), lo, hi)
    s53 = vclp((s1 +% s7), lo, hi)
    s1 = vclp((s1 -% s7), lo, hi)
    s7 = vclp((s17 +% s12), lo, hi)
    s12 = vclp((s17 -% s12), lo, hi)
    s17 = vclp((s0 +% s46), lo, hi)
    s0 = vclp((s0 -% s46), lo, hi)
    s46 = vclp((s6 +% s51), lo, hi)
    s6 = vclp((s6 -% s51), lo, hi)
    s51 = vclp((s2 +% s60), lo, hi)
    s2 = vclp((s2 -% s60), lo, hi)
    s60 = vclp((s59 +% s58), lo, hi)
    s58 = vclp((s59 -% s58), lo, hi)
    s59 = vclp((s29 +% s57), lo, hi)
    s29 = vclp((s29 -% s57), lo, hi)
    s57 = (((kp2048) +% (s19 *% kp2896)) -% (s32 *% kp2896)) >> 12u32
    s19 = (((kp2048) +% (s19 *% kp2896)) +% (s32 *% kp2896)) >> 12u32
    s32 = (((kp2048) +% (s26 *% kp2896)) -% (s15 *% kp2896)) >> 12u32
    s15 = (((kp2048) +% (s26 *% kp2896)) +% (s15 *% kp2896)) >> 12u32
    s26 = (((kp2048) +% (s9 *% kp2896)) -% (s27 *% kp2896)) >> 12u32
    s9 = (((kp2048) +% (s9 *% kp2896)) +% (s27 *% kp2896)) >> 12u32
    s27 = (((kp2048) +% (s16 *% kp2896)) -% (s13 *% kp2896)) >> 12u32
    s13 = (((kp2048) +% (s16 *% kp2896)) +% (s13 *% kp2896)) >> 12u32
    s16 = (((kp2048) +% (s18 *% kp2896)) -% (s35 *% kp2896)) >> 12u32
    s18 = (((kp2048) +% (s18 *% kp2896)) +% (s35 *% kp2896)) >> 12u32
    s35 = (((kp2048) +% (s30 *% kp2896)) -% (s45 *% kp2896)) >> 12u32
    s30 = (((kp2048) +% (s30 *% kp2896)) +% (s45 *% kp2896)) >> 12u32
    s45 = (((kp2048) +% (s21 *% kp2896)) -% (s40 *% kp2896)) >> 12u32
    s21 = (((kp2048) +% (s21 *% kp2896)) +% (s40 *% kp2896)) >> 12u32
    s40 = (((kp2048) +% (s25 *% kp2896)) -% (s33 *% kp2896)) >> 12u32
    s25 = (((kp2048) +% (s25 *% kp2896)) +% (s33 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s23 +% s50), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s49 +% s54), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s52 +% s56), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s61 +% s43), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s10 +% s34), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s63 +% s41), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s5 +% s36), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s64 +% s37), lo, hi)))
    vst(t, off + 8usize * st, (vclp((s62 +% s19), lo, hi)))
    vst(t, off + 9usize * st, (vclp((s53 +% s15), lo, hi)))
    vst(t, off + 10usize * st, (vclp((s7 +% s9), lo, hi)))
    vst(t, off + 11usize * st, (vclp((s17 +% s13), lo, hi)))
    vst(t, off + 12usize * st, (vclp((s46 +% s18), lo, hi)))
    vst(t, off + 13usize * st, (vclp((s51 +% s30), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s60 +% s21), lo, hi)))
    vst(t, off + 15usize * st, (vclp((s59 +% s25), lo, hi)))
    vst(t, off + 16usize * st, (vclp((s29 +% s40), lo, hi)))
    vst(t, off + 17usize * st, (vclp((s58 +% s45), lo, hi)))
    vst(t, off + 18usize * st, (vclp((s2 +% s35), lo, hi)))
    vst(t, off + 19usize * st, (vclp((s6 +% s16), lo, hi)))
    vst(t, off + 20usize * st, (vclp((s0 +% s27), lo, hi)))
    vst(t, off + 21usize * st, (vclp((s12 +% s26), lo, hi)))
    vst(t, off + 22usize * st, (vclp((s1 +% s32), lo, hi)))
    vst(t, off + 23usize * st, (vclp((s42 +% s57), lo, hi)))
    vst(t, off + 24usize * st, (vclp((s11 +% s28), lo, hi)))
    vst(t, off + 25usize * st, (vclp((s14 +% s20), lo, hi)))
    vst(t, off + 26usize * st, (vclp((s4 +% s24), lo, hi)))
    vst(t, off + 27usize * st, (vclp((s8 +% s22), lo, hi)))
    vst(t, off + 28usize * st, (vclp((s3 +% s47), lo, hi)))
    vst(t, off + 29usize * st, (vclp((s55 +% s44), lo, hi)))
    vst(t, off + 30usize * st, (vclp((s31 +% s39), lo, hi)))
    vst(t, off + 31usize * st, (vclp((s38 +% s48), lo, hi)))
    vst(t, off + 32usize * st, (vclp((s38 -% s48), lo, hi)))
    vst(t, off + 33usize * st, (vclp((s31 -% s39), lo, hi)))
    vst(t, off + 34usize * st, (vclp((s55 -% s44), lo, hi)))
    vst(t, off + 35usize * st, (vclp((s3 -% s47), lo, hi)))
    vst(t, off + 36usize * st, (vclp((s8 -% s22), lo, hi)))
    vst(t, off + 37usize * st, (vclp((s4 -% s24), lo, hi)))
    vst(t, off + 38usize * st, (vclp((s14 -% s20), lo, hi)))
    vst(t, off + 39usize * st, (vclp((s11 -% s28), lo, hi)))
    vst(t, off + 40usize * st, (vclp((s42 -% s57), lo, hi)))
    vst(t, off + 41usize * st, (vclp((s1 -% s32), lo, hi)))
    vst(t, off + 42usize * st, (vclp((s12 -% s26), lo, hi)))
    vst(t, off + 43usize * st, (vclp((s0 -% s27), lo, hi)))
    vst(t, off + 44usize * st, (vclp((s6 -% s16), lo, hi)))
    vst(t, off + 45usize * st, (vclp((s2 -% s35), lo, hi)))
    vst(t, off + 46usize * st, (vclp((s58 -% s45), lo, hi)))
    vst(t, off + 47usize * st, (vclp((s29 -% s40), lo, hi)))
    vst(t, off + 48usize * st, (vclp((s59 -% s25), lo, hi)))
    vst(t, off + 49usize * st, (vclp((s60 -% s21), lo, hi)))
    vst(t, off + 50usize * st, (vclp((s51 -% s30), lo, hi)))
    vst(t, off + 51usize * st, (vclp((s46 -% s18), lo, hi)))
    vst(t, off + 52usize * st, (vclp((s17 -% s13), lo, hi)))
    vst(t, off + 53usize * st, (vclp((s7 -% s9), lo, hi)))
    vst(t, off + 54usize * st, (vclp((s53 -% s15), lo, hi)))
    vst(t, off + 55usize * st, (vclp((s62 -% s19), lo, hi)))
    vst(t, off + 56usize * st, (vclp((s64 -% s37), lo, hi)))
    vst(t, off + 57usize * st, (vclp((s5 -% s36), lo, hi)))
    vst(t, off + 58usize * st, (vclp((s63 -% s41), lo, hi)))
    vst(t, off + 59usize * st, (vclp((s10 -% s34), lo, hi)))
    vst(t, off + 60usize * st, (vclp((s61 -% s43), lo, hi)))
    vst(t, off + 61usize * st, (vclp((s52 -% s56), lo, hi)))
    vst(t, off + 62usize * st, (vclp((s49 -% s54), lo, hi)))
    vst(t, off + 63usize * st, (vclp((s23 -% s50), lo, hi)))
    }
}

fn vfadst8(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp1931 = vsp(1931i32)
    let kp3612 = vsp(3612i32)
    let kp3166 = vsp(3166i32)
    let kp2598 = vsp(2598i32)
    let kp3920 = vsp(3920i32)
    let kp1189 = vsp(1189i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    let kp2896 = vsp(2896i32)
    let kp0 = vsp(0i32)
    var s0 = vld(t, off + 7usize * st)
    var s1 = vld(t, off + 0usize * st)
    var s2 = vld(t, off + 5usize * st)
    var s3 = vld(t, off + 2usize * st)
    var s4 = vld(t, off + 3usize * st)
    var s5 = vld(t, off + 4usize * st)
    var s6 = vld(t, off + 1usize * st)
    var s7 = vld(t, off + 6usize * st)
    var s8 = (((kp2048) +% (s0 *% kp401)) -% (s1 *% kp4076)) >> 12u32
    s0 = (((kp2048) +% (s0 *% kp4076)) +% (s1 *% kp401)) >> 12u32
    s1 = (((kp2048) +% (s2 *% kp1931)) -% (s3 *% kp3612)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3612)) +% (s3 *% kp1931)) >> 12u32
    s3 = (((kp2048) +% (s4 *% kp3166)) -% (s5 *% kp2598)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp2598)) +% (s5 *% kp3166)) >> 12u32
    s5 = (((kp2048) +% (s6 *% kp3920)) -% (s7 *% kp1189)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp1189)) +% (s7 *% kp3920)) >> 12u32
    s7 = vclp((s0 +% s4), lo, hi)
    s0 = vclp((s0 -% s4), lo, hi)
    s4 = vclp((s8 +% s3), lo, hi)
    s3 = vclp((s8 -% s3), lo, hi)
    s8 = vclp((s2 +% s6), lo, hi)
    s2 = vclp((s2 -% s6), lo, hi)
    s6 = vclp((s1 +% s5), lo, hi)
    s1 = vclp((s1 -% s5), lo, hi)
    s5 = (((kp2048) +% (s0 *% kp1567)) -% (s3 *% kp3784)) >> 12u32
    s0 = (((kp2048) +% (s0 *% kp3784)) +% (s3 *% kp1567)) >> 12u32
    s3 = (((kp2048) +% (s1 *% kp3784)) -% (s2 *% kp1567)) >> 12u32
    s1 = (((kp2048) +% (s1 *% kp1567)) +% (s2 *% kp3784)) >> 12u32
    s2 = vclp((s7 -% s8), lo, hi)
    var s9 = vclp((s0 -% s3), lo, hi)
    var s10 = vclp((s4 -% s6), lo, hi)
    var s11 = vclp((s5 -% s1), lo, hi)
    vst(t, off + 0usize * st, (vclp((s7 +% s8), lo, hi)))
    vst(t, off + 1usize * st, kp0 -% (vclp((s0 +% s3), lo, hi)))
    vst(t, off + 2usize * st, ((((kp2048) +% (s9 *% kp2896)) +% (s11 *% kp2896)) >> 12u32))
    vst(t, off + 3usize * st, kp0 -% ((((kp2048) +% (s2 *% kp2896)) +% (s10 *% kp2896)) >> 12u32))
    vst(t, off + 4usize * st, ((((kp2048) +% (s2 *% kp2896)) -% (s10 *% kp2896)) >> 12u32))
    vst(t, off + 5usize * st, kp0 -% ((((kp2048) +% (s9 *% kp2896)) -% (s11 *% kp2896)) >> 12u32))
    vst(t, off + 6usize * st, (vclp((s5 +% s1), lo, hi)))
    vst(t, off + 7usize * st, kp0 -% (vclp((s4 +% s6), lo, hi)))
    }
}

fn vfadst16(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp201 = vsp(201i32)
    let kp4091 = vsp(4091i32)
    let kp995 = vsp(995i32)
    let kp3973 = vsp(3973i32)
    let kp1751 = vsp(1751i32)
    let kp3703 = vsp(3703i32)
    let kp2440 = vsp(2440i32)
    let kp3290 = vsp(3290i32)
    let kp3035 = vsp(3035i32)
    let kp2751 = vsp(2751i32)
    let kp3513 = vsp(3513i32)
    let kp2106 = vsp(2106i32)
    let kp3857 = vsp(3857i32)
    let kp1380 = vsp(1380i32)
    let kp4052 = vsp(4052i32)
    let kp601 = vsp(601i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp3406 = vsp(3406i32)
    let kp2276 = vsp(2276i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    let kp2896 = vsp(2896i32)
    let kp0 = vsp(0i32)
    var s0 = vld(t, off + 15usize * st)
    var s1 = vld(t, off + 0usize * st)
    var s2 = vld(t, off + 13usize * st)
    var s3 = vld(t, off + 2usize * st)
    var s4 = vld(t, off + 11usize * st)
    var s5 = vld(t, off + 4usize * st)
    var s6 = vld(t, off + 9usize * st)
    var s7 = vld(t, off + 6usize * st)
    var s8 = vld(t, off + 7usize * st)
    var s9 = vld(t, off + 8usize * st)
    var s10 = vld(t, off + 5usize * st)
    var s11 = vld(t, off + 10usize * st)
    var s12 = vld(t, off + 3usize * st)
    var s13 = vld(t, off + 12usize * st)
    var s14 = vld(t, off + 1usize * st)
    var s15 = vld(t, off + 14usize * st)
    var s16 = (((kp2048) +% (s0 *% kp201)) -% (s1 *% kp4091)) >> 12u32
    s0 = (((kp2048) +% (s0 *% kp4091)) +% (s1 *% kp201)) >> 12u32
    s1 = (((kp2048) +% (s2 *% kp995)) -% (s3 *% kp3973)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3973)) +% (s3 *% kp995)) >> 12u32
    s3 = (((kp2048) +% (s4 *% kp1751)) -% (s5 *% kp3703)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp3703)) +% (s5 *% kp1751)) >> 12u32
    s5 = (((kp2048) +% (s6 *% kp2440)) -% (s7 *% kp3290)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp3290)) +% (s7 *% kp2440)) >> 12u32
    s7 = (((kp2048) +% (s8 *% kp3035)) -% (s9 *% kp2751)) >> 12u32
    s8 = (((kp2048) +% (s8 *% kp2751)) +% (s9 *% kp3035)) >> 12u32
    s9 = (((kp2048) +% (s10 *% kp3513)) -% (s11 *% kp2106)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp2106)) +% (s11 *% kp3513)) >> 12u32
    s11 = (((kp2048) +% (s12 *% kp3857)) -% (s13 *% kp1380)) >> 12u32
    s12 = (((kp2048) +% (s12 *% kp1380)) +% (s13 *% kp3857)) >> 12u32
    s13 = (((kp2048) +% (s14 *% kp4052)) -% (s15 *% kp601)) >> 12u32
    s14 = (((kp2048) +% (s14 *% kp601)) +% (s15 *% kp4052)) >> 12u32
    s15 = vclp((s0 +% s8), lo, hi)
    s0 = vclp((s0 -% s8), lo, hi)
    s8 = vclp((s16 +% s7), lo, hi)
    s7 = vclp((s16 -% s7), lo, hi)
    s16 = vclp((s2 +% s10), lo, hi)
    s2 = vclp((s2 -% s10), lo, hi)
    s10 = vclp((s1 +% s9), lo, hi)
    s1 = vclp((s1 -% s9), lo, hi)
    s9 = vclp((s4 +% s12), lo, hi)
    s4 = vclp((s4 -% s12), lo, hi)
    s12 = vclp((s3 +% s11), lo, hi)
    s3 = vclp((s3 -% s11), lo, hi)
    s11 = vclp((s6 +% s14), lo, hi)
    s6 = vclp((s6 -% s14), lo, hi)
    s14 = vclp((s5 +% s13), lo, hi)
    s5 = vclp((s5 -% s13), lo, hi)
    s13 = (((kp2048) +% (s0 *% kp799)) -% (s7 *% kp4017)) >> 12u32
    s0 = (((kp2048) +% (s0 *% kp4017)) +% (s7 *% kp799)) >> 12u32
    s7 = (((kp2048) +% (s3 *% kp4017)) -% (s4 *% kp799)) >> 12u32
    s3 = (((kp2048) +% (s3 *% kp799)) +% (s4 *% kp4017)) >> 12u32
    s4 = (((kp2048) +% (s2 *% kp3406)) -% (s1 *% kp2276)) >> 12u32
    s1 = (((kp2048) +% (s2 *% kp2276)) +% (s1 *% kp3406)) >> 12u32
    s2 = (((kp2048) +% (s5 *% kp2276)) -% (s6 *% kp3406)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp3406)) +% (s6 *% kp2276)) >> 12u32
    s6 = vclp((s15 +% s9), lo, hi)
    s9 = vclp((s15 -% s9), lo, hi)
    s15 = vclp((s0 +% s7), lo, hi)
    s0 = vclp((s0 -% s7), lo, hi)
    s7 = vclp((s8 +% s12), lo, hi)
    s8 = vclp((s8 -% s12), lo, hi)
    s12 = vclp((s13 +% s3), lo, hi)
    s3 = vclp((s13 -% s3), lo, hi)
    s13 = vclp((s16 +% s11), lo, hi)
    s11 = vclp((s16 -% s11), lo, hi)
    s16 = vclp((s1 +% s2), lo, hi)
    s1 = vclp((s1 -% s2), lo, hi)
    s2 = vclp((s10 +% s14), lo, hi)
    s10 = vclp((s10 -% s14), lo, hi)
    s14 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = (((kp2048) +% (s9 *% kp1567)) -% (s8 *% kp3784)) >> 12u32
    s8 = (((kp2048) +% (s9 *% kp3784)) +% (s8 *% kp1567)) >> 12u32
    s9 = (((kp2048) +% (s0 *% kp1567)) -% (s3 *% kp3784)) >> 12u32
    s0 = (((kp2048) +% (s0 *% kp3784)) +% (s3 *% kp1567)) >> 12u32
    s3 = (((kp2048) +% (s10 *% kp3784)) -% (s11 *% kp1567)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp1567)) +% (s11 *% kp3784)) >> 12u32
    s11 = (((kp2048) +% (s4 *% kp3784)) -% (s1 *% kp1567)) >> 12u32
    s1 = (((kp2048) +% (s4 *% kp1567)) +% (s1 *% kp3784)) >> 12u32
    s4 = vclp((s6 -% s13), lo, hi)
    var s17 = vclp((s8 -% s3), lo, hi)
    var s18 = vclp((s15 -% s16), lo, hi)
    var s19 = vclp((s0 -% s11), lo, hi)
    var s20 = vclp((s7 -% s2), lo, hi)
    var s21 = vclp((s5 -% s10), lo, hi)
    var s22 = vclp((s12 -% s14), lo, hi)
    var s23 = vclp((s9 -% s1), lo, hi)
    vst(t, off + 0usize * st, (vclp((s6 +% s13), lo, hi)))
    vst(t, off + 1usize * st, kp0 -% (vclp((s15 +% s16), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s0 +% s11), lo, hi)))
    vst(t, off + 3usize * st, kp0 -% (vclp((s8 +% s3), lo, hi)))
    vst(t, off + 4usize * st, ((((kp2048) +% (s17 *% kp2896)) +% (s21 *% kp2896)) >> 12u32))
    vst(t, off + 5usize * st, kp0 -% ((((kp2048) +% (s19 *% kp2896)) +% (s23 *% kp2896)) >> 12u32))
    vst(t, off + 6usize * st, ((((kp2048) +% (s18 *% kp2896)) +% (s22 *% kp2896)) >> 12u32))
    vst(t, off + 7usize * st, kp0 -% ((((kp2048) +% (s4 *% kp2896)) +% (s20 *% kp2896)) >> 12u32))
    vst(t, off + 8usize * st, ((((kp2048) +% (s4 *% kp2896)) -% (s20 *% kp2896)) >> 12u32))
    vst(t, off + 9usize * st, kp0 -% ((((kp2048) +% (s18 *% kp2896)) -% (s22 *% kp2896)) >> 12u32))
    vst(t, off + 10usize * st, ((((kp2048) +% (s19 *% kp2896)) -% (s23 *% kp2896)) >> 12u32))
    vst(t, off + 11usize * st, kp0 -% ((((kp2048) +% (s17 *% kp2896)) -% (s21 *% kp2896)) >> 12u32))
    vst(t, off + 12usize * st, (vclp((s5 +% s10), lo, hi)))
    vst(t, off + 13usize * st, kp0 -% (vclp((s9 +% s1), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s12 +% s14), lo, hi)))
    vst(t, off + 15usize * st, kp0 -% (vclp((s7 +% s2), lo, hi)))
    }
}

fn vidct8_k4(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp2276 = vsp(2276i32)
    let kp3406 = vsp(3406i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 2usize * st)
    var s2 = vld(t, off + 1usize * st)
    var s3 = vld(t, off + 3usize * st)
    var s4 = ((kp2048) +% (s2 *% kp799)) >> 12u32
    s2 = ((kp2048) +% (s2 *% kp4017)) >> 12u32
    var s5 = ((kp2048) -% (s3 *% kp2276)) >> 12u32
    s3 = ((kp2048) +% (s3 *% kp3406)) >> 12u32
    var s6 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    s0 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    var s7 = ((kp2048) +% (s1 *% kp1567)) >> 12u32
    s1 = ((kp2048) +% (s1 *% kp3784)) >> 12u32
    var s8 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = vclp((s0 +% s1), lo, hi)
    s0 = vclp((s0 -% s1), lo, hi)
    s1 = vclp((s6 +% s7), lo, hi)
    s6 = vclp((s6 -% s7), lo, hi)
    s7 = (((kp2048) +% (s2 *% kp2896)) -% (s4 *% kp2896)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp2896)) +% (s4 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s3 +% s5), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s1 +% s2), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s6 +% s7), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s0 +% s8), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s0 -% s8), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s6 -% s7), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s1 -% s2), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s3 -% s5), lo, hi)))
    }
}

fn vidct16_k4(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp1189 = vsp(1189i32)
    let kp3920 = vsp(3920i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 2usize * st)
    var s2 = vld(t, off + 1usize * st)
    var s3 = vld(t, off + 3usize * st)
    var s4 = ((kp2048) +% (s2 *% kp401)) >> 12u32
    s2 = ((kp2048) +% (s2 *% kp4076)) >> 12u32
    var s5 = ((kp2048) -% (s3 *% kp1189)) >> 12u32
    s3 = ((kp2048) +% (s3 *% kp3920)) >> 12u32
    var s6 = ((kp2048) +% (s1 *% kp799)) >> 12u32
    s1 = ((kp2048) +% (s1 *% kp4017)) >> 12u32
    var s7 = vclp(s4, lo, hi)
    s4 = vclp(s4, lo, hi)
    var s8 = vclp(s5, lo, hi)
    s5 = vclp(s5, lo, hi)
    var s9 = vclp(s3, lo, hi)
    s3 = vclp(s3, lo, hi)
    var s10 = vclp(s2, lo, hi)
    s2 = vclp(s2, lo, hi)
    var s11 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    s0 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    var s12 = vclp(s6, lo, hi)
    s6 = vclp(s6, lo, hi)
    var s13 = vclp(s1, lo, hi)
    s1 = vclp(s1, lo, hi)
    var s14 = (((kp2048) +% (s2 *% kp1567)) -% (s4 *% kp3784)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3784)) +% (s4 *% kp1567)) >> 12u32
    s4 = (((kp2048) -% (s3 *% kp3784)) -% (s5 *% kp1567)) >> 12u32
    s3 = (((kp2048) +% (s3 *% kp1567)) -% (s5 *% kp3784)) >> 12u32
    s5 = vclp(s0, lo, hi)
    s0 = vclp(s0, lo, hi)
    var s15 = vclp(s11, lo, hi)
    s11 = vclp(s11, lo, hi)
    var s16 = (((kp2048) +% (s1 *% kp2896)) -% (s6 *% kp2896)) >> 12u32
    s1 = (((kp2048) +% (s1 *% kp2896)) +% (s6 *% kp2896)) >> 12u32
    s6 = vclp((s7 +% s8), lo, hi)
    s7 = vclp((s7 -% s8), lo, hi)
    s8 = vclp((s14 +% s4), lo, hi)
    s4 = vclp((s14 -% s4), lo, hi)
    s14 = vclp((s10 +% s9), lo, hi)
    s9 = vclp((s10 -% s9), lo, hi)
    s10 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = vclp((s5 +% s13), lo, hi)
    s5 = vclp((s5 -% s13), lo, hi)
    s13 = vclp((s15 +% s1), lo, hi)
    s1 = vclp((s15 -% s1), lo, hi)
    s15 = vclp((s11 +% s16), lo, hi)
    s11 = vclp((s11 -% s16), lo, hi)
    s16 = vclp((s0 +% s12), lo, hi)
    s0 = vclp((s0 -% s12), lo, hi)
    s12 = (((kp2048) +% (s2 *% kp2896)) -% (s4 *% kp2896)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp2896)) +% (s4 *% kp2896)) >> 12u32
    s4 = (((kp2048) +% (s9 *% kp2896)) -% (s7 *% kp2896)) >> 12u32
    s7 = (((kp2048) +% (s9 *% kp2896)) +% (s7 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s3 +% s14), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s13 +% s10), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s15 +% s2), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s16 +% s7), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s0 +% s4), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s11 +% s12), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s1 +% s8), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s5 +% s6), lo, hi)))
    vst(t, off + 8usize * st, (vclp((s5 -% s6), lo, hi)))
    vst(t, off + 9usize * st, (vclp((s1 -% s8), lo, hi)))
    vst(t, off + 10usize * st, (vclp((s11 -% s12), lo, hi)))
    vst(t, off + 11usize * st, (vclp((s0 -% s4), lo, hi)))
    vst(t, off + 12usize * st, (vclp((s16 -% s7), lo, hi)))
    vst(t, off + 13usize * st, (vclp((s15 -% s2), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s13 -% s10), lo, hi)))
    vst(t, off + 15usize * st, (vclp((s3 -% s14), lo, hi)))
    }
}

fn vidct16_k8(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp2598 = vsp(2598i32)
    let kp3166 = vsp(3166i32)
    let kp1931 = vsp(1931i32)
    let kp3612 = vsp(3612i32)
    let kp1189 = vsp(1189i32)
    let kp3920 = vsp(3920i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp2276 = vsp(2276i32)
    let kp3406 = vsp(3406i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 4usize * st)
    var s2 = vld(t, off + 2usize * st)
    var s3 = vld(t, off + 6usize * st)
    var s4 = vld(t, off + 1usize * st)
    var s5 = vld(t, off + 5usize * st)
    var s6 = vld(t, off + 3usize * st)
    var s7 = vld(t, off + 7usize * st)
    var s8 = ((kp2048) +% (s4 *% kp401)) >> 12u32
    s4 = ((kp2048) +% (s4 *% kp4076)) >> 12u32
    var s9 = ((kp2048) -% (s7 *% kp2598)) >> 12u32
    s7 = ((kp2048) +% (s7 *% kp3166)) >> 12u32
    var s10 = ((kp2048) +% (s5 *% kp1931)) >> 12u32
    s5 = ((kp2048) +% (s5 *% kp3612)) >> 12u32
    var s11 = ((kp2048) -% (s6 *% kp1189)) >> 12u32
    s6 = ((kp2048) +% (s6 *% kp3920)) >> 12u32
    var s12 = ((kp2048) +% (s2 *% kp799)) >> 12u32
    s2 = ((kp2048) +% (s2 *% kp4017)) >> 12u32
    var s13 = ((kp2048) -% (s3 *% kp2276)) >> 12u32
    s3 = ((kp2048) +% (s3 *% kp3406)) >> 12u32
    var s14 = vclp((s8 +% s9), lo, hi)
    s8 = vclp((s8 -% s9), lo, hi)
    s9 = vclp((s11 +% s10), lo, hi)
    s10 = vclp((s11 -% s10), lo, hi)
    s11 = vclp((s6 +% s5), lo, hi)
    s5 = vclp((s6 -% s5), lo, hi)
    s6 = vclp((s4 +% s7), lo, hi)
    s4 = vclp((s4 -% s7), lo, hi)
    s7 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    s0 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    var s15 = ((kp2048) +% (s1 *% kp1567)) >> 12u32
    s1 = ((kp2048) +% (s1 *% kp3784)) >> 12u32
    var s16 = vclp((s12 +% s13), lo, hi)
    s12 = vclp((s12 -% s13), lo, hi)
    s13 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = (((kp2048) +% (s4 *% kp1567)) -% (s8 *% kp3784)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp3784)) +% (s8 *% kp1567)) >> 12u32
    s8 = (((kp2048) -% (s5 *% kp3784)) -% (s10 *% kp1567)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp1567)) -% (s10 *% kp3784)) >> 12u32
    s10 = vclp((s0 +% s1), lo, hi)
    s0 = vclp((s0 -% s1), lo, hi)
    s1 = vclp((s7 +% s15), lo, hi)
    s7 = vclp((s7 -% s15), lo, hi)
    s15 = (((kp2048) +% (s2 *% kp2896)) -% (s12 *% kp2896)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp2896)) +% (s12 *% kp2896)) >> 12u32
    s12 = vclp((s14 +% s9), lo, hi)
    s9 = vclp((s14 -% s9), lo, hi)
    s14 = vclp((s3 +% s8), lo, hi)
    s3 = vclp((s3 -% s8), lo, hi)
    s8 = vclp((s6 +% s11), lo, hi)
    s6 = vclp((s6 -% s11), lo, hi)
    s11 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = vclp((s10 +% s13), lo, hi)
    s10 = vclp((s10 -% s13), lo, hi)
    s13 = vclp((s1 +% s2), lo, hi)
    s1 = vclp((s1 -% s2), lo, hi)
    s2 = vclp((s7 +% s15), lo, hi)
    s7 = vclp((s7 -% s15), lo, hi)
    s15 = vclp((s0 +% s16), lo, hi)
    s0 = vclp((s0 -% s16), lo, hi)
    s16 = (((kp2048) +% (s4 *% kp2896)) -% (s3 *% kp2896)) >> 12u32
    s3 = (((kp2048) +% (s4 *% kp2896)) +% (s3 *% kp2896)) >> 12u32
    s4 = (((kp2048) +% (s6 *% kp2896)) -% (s9 *% kp2896)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp2896)) +% (s9 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s5 +% s8), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s13 +% s11), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s2 +% s3), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s15 +% s6), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s0 +% s4), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s7 +% s16), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s1 +% s14), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s10 +% s12), lo, hi)))
    vst(t, off + 8usize * st, (vclp((s10 -% s12), lo, hi)))
    vst(t, off + 9usize * st, (vclp((s1 -% s14), lo, hi)))
    vst(t, off + 10usize * st, (vclp((s7 -% s16), lo, hi)))
    vst(t, off + 11usize * st, (vclp((s0 -% s4), lo, hi)))
    vst(t, off + 12usize * st, (vclp((s15 -% s6), lo, hi)))
    vst(t, off + 13usize * st, (vclp((s2 -% s3), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s13 -% s11), lo, hi)))
    vst(t, off + 15usize * st, (vclp((s5 -% s8), lo, hi)))
    }
}

fn vidct32_k4(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp201 = vsp(201i32)
    let kp4091 = vsp(4091i32)
    let kp601 = vsp(601i32)
    let kp4052 = vsp(4052i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp2276 = vsp(2276i32)
    let kp3406 = vsp(3406i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 2usize * st)
    var s2 = vld(t, off + 1usize * st)
    var s3 = vld(t, off + 3usize * st)
    var s4 = ((kp2048) +% (s2 *% kp201)) >> 12u32
    s2 = ((kp2048) +% (s2 *% kp4091)) >> 12u32
    var s5 = ((kp2048) -% (s3 *% kp601)) >> 12u32
    s3 = ((kp2048) +% (s3 *% kp4052)) >> 12u32
    var s6 = ((kp2048) +% (s1 *% kp401)) >> 12u32
    s1 = ((kp2048) +% (s1 *% kp4076)) >> 12u32
    var s7 = vclp(s4, lo, hi)
    s4 = vclp(s4, lo, hi)
    var s8 = vclp(s5, lo, hi)
    s5 = vclp(s5, lo, hi)
    var s9 = vclp(s3, lo, hi)
    s3 = vclp(s3, lo, hi)
    var s10 = vclp(s2, lo, hi)
    s2 = vclp(s2, lo, hi)
    var s11 = vclp(s6, lo, hi)
    s6 = vclp(s6, lo, hi)
    var s12 = vclp(s1, lo, hi)
    s1 = vclp(s1, lo, hi)
    var s13 = (((kp2048) +% (s2 *% kp799)) -% (s4 *% kp4017)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp4017)) +% (s4 *% kp799)) >> 12u32
    s4 = (((kp2048) -% (s3 *% kp2276)) -% (s5 *% kp3406)) >> 12u32
    s3 = (((kp2048) +% (s3 *% kp3406)) -% (s5 *% kp2276)) >> 12u32
    s5 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    s0 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    var s14 = (((kp2048) +% (s1 *% kp1567)) -% (s6 *% kp3784)) >> 12u32
    s1 = (((kp2048) +% (s1 *% kp3784)) +% (s6 *% kp1567)) >> 12u32
    s6 = vclp(s7, lo, hi)
    s7 = vclp(s7, lo, hi)
    var s15 = vclp(s13, lo, hi)
    s13 = vclp(s13, lo, hi)
    var s16 = vclp(s8, lo, hi)
    s8 = vclp(s8, lo, hi)
    var s17 = vclp(s4, lo, hi)
    s4 = vclp(s4, lo, hi)
    var s18 = vclp(s9, lo, hi)
    s9 = vclp(s9, lo, hi)
    var s19 = vclp(s3, lo, hi)
    s3 = vclp(s3, lo, hi)
    var s20 = vclp(s10, lo, hi)
    s10 = vclp(s10, lo, hi)
    var s21 = vclp(s2, lo, hi)
    s2 = vclp(s2, lo, hi)
    var s22 = vclp(s0, lo, hi)
    s0 = vclp(s0, lo, hi)
    var s23 = vclp(s5, lo, hi)
    s5 = vclp(s5, lo, hi)
    var s24 = vclp(s11, lo, hi)
    s11 = vclp(s11, lo, hi)
    var s25 = vclp(s14, lo, hi)
    s14 = vclp(s14, lo, hi)
    var s26 = vclp(s12, lo, hi)
    s12 = vclp(s12, lo, hi)
    var s27 = vclp(s1, lo, hi)
    s1 = vclp(s1, lo, hi)
    var s28 = (((kp2048) +% (s2 *% kp1567)) -% (s13 *% kp3784)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3784)) +% (s13 *% kp1567)) >> 12u32
    s13 = (((kp2048) +% (s10 *% kp1567)) -% (s7 *% kp3784)) >> 12u32
    s7 = (((kp2048) +% (s10 *% kp3784)) +% (s7 *% kp1567)) >> 12u32
    s10 = (((kp2048) -% (s9 *% kp3784)) -% (s8 *% kp1567)) >> 12u32
    s8 = (((kp2048) +% (s9 *% kp1567)) -% (s8 *% kp3784)) >> 12u32
    s9 = (((kp2048) -% (s3 *% kp3784)) -% (s4 *% kp1567)) >> 12u32
    s3 = (((kp2048) +% (s3 *% kp1567)) -% (s4 *% kp3784)) >> 12u32
    s4 = vclp(s22, lo, hi)
    s22 = vclp(s22, lo, hi)
    var s29 = vclp(s23, lo, hi)
    s23 = vclp(s23, lo, hi)
    var s30 = vclp(s5, lo, hi)
    s5 = vclp(s5, lo, hi)
    var s31 = vclp(s0, lo, hi)
    s0 = vclp(s0, lo, hi)
    var s32 = (((kp2048) +% (s1 *% kp2896)) -% (s14 *% kp2896)) >> 12u32
    s1 = (((kp2048) +% (s1 *% kp2896)) +% (s14 *% kp2896)) >> 12u32
    s14 = (((kp2048) +% (s12 *% kp2896)) -% (s11 *% kp2896)) >> 12u32
    s11 = (((kp2048) +% (s12 *% kp2896)) +% (s11 *% kp2896)) >> 12u32
    s12 = vclp((s6 +% s16), lo, hi)
    s6 = vclp((s6 -% s16), lo, hi)
    s16 = vclp((s15 +% s17), lo, hi)
    s15 = vclp((s15 -% s17), lo, hi)
    s17 = vclp((s28 +% s9), lo, hi)
    s9 = vclp((s28 -% s9), lo, hi)
    s28 = vclp((s13 +% s10), lo, hi)
    s10 = vclp((s13 -% s10), lo, hi)
    s13 = vclp((s20 +% s18), lo, hi)
    s18 = vclp((s20 -% s18), lo, hi)
    s20 = vclp((s21 +% s19), lo, hi)
    s19 = vclp((s21 -% s19), lo, hi)
    s21 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = vclp((s7 +% s8), lo, hi)
    s7 = vclp((s7 -% s8), lo, hi)
    s8 = vclp((s4 +% s26), lo, hi)
    s4 = vclp((s4 -% s26), lo, hi)
    s26 = vclp((s29 +% s27), lo, hi)
    s27 = vclp((s29 -% s27), lo, hi)
    s29 = vclp((s30 +% s1), lo, hi)
    s1 = vclp((s30 -% s1), lo, hi)
    s30 = vclp((s31 +% s11), lo, hi)
    s11 = vclp((s31 -% s11), lo, hi)
    s31 = vclp((s0 +% s14), lo, hi)
    s0 = vclp((s0 -% s14), lo, hi)
    s14 = vclp((s5 +% s32), lo, hi)
    s5 = vclp((s5 -% s32), lo, hi)
    s32 = vclp((s23 +% s25), lo, hi)
    s23 = vclp((s23 -% s25), lo, hi)
    s25 = vclp((s22 +% s24), lo, hi)
    s22 = vclp((s22 -% s24), lo, hi)
    s24 = (((kp2048) +% (s7 *% kp2896)) -% (s10 *% kp2896)) >> 12u32
    s7 = (((kp2048) +% (s7 *% kp2896)) +% (s10 *% kp2896)) >> 12u32
    s10 = (((kp2048) +% (s2 *% kp2896)) -% (s9 *% kp2896)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp2896)) +% (s9 *% kp2896)) >> 12u32
    s9 = (((kp2048) +% (s19 *% kp2896)) -% (s15 *% kp2896)) >> 12u32
    s15 = (((kp2048) +% (s19 *% kp2896)) +% (s15 *% kp2896)) >> 12u32
    s19 = (((kp2048) +% (s18 *% kp2896)) -% (s6 *% kp2896)) >> 12u32
    s6 = (((kp2048) +% (s18 *% kp2896)) +% (s6 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s8 +% s13), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s26 +% s20), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s29 +% s21), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s30 +% s3), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s31 +% s7), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s14 +% s2), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s32 +% s15), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s25 +% s6), lo, hi)))
    vst(t, off + 8usize * st, (vclp((s22 +% s19), lo, hi)))
    vst(t, off + 9usize * st, (vclp((s23 +% s9), lo, hi)))
    vst(t, off + 10usize * st, (vclp((s5 +% s10), lo, hi)))
    vst(t, off + 11usize * st, (vclp((s0 +% s24), lo, hi)))
    vst(t, off + 12usize * st, (vclp((s11 +% s28), lo, hi)))
    vst(t, off + 13usize * st, (vclp((s1 +% s17), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s27 +% s16), lo, hi)))
    vst(t, off + 15usize * st, (vclp((s4 +% s12), lo, hi)))
    vst(t, off + 16usize * st, (vclp((s4 -% s12), lo, hi)))
    vst(t, off + 17usize * st, (vclp((s27 -% s16), lo, hi)))
    vst(t, off + 18usize * st, (vclp((s1 -% s17), lo, hi)))
    vst(t, off + 19usize * st, (vclp((s11 -% s28), lo, hi)))
    vst(t, off + 20usize * st, (vclp((s0 -% s24), lo, hi)))
    vst(t, off + 21usize * st, (vclp((s5 -% s10), lo, hi)))
    vst(t, off + 22usize * st, (vclp((s23 -% s9), lo, hi)))
    vst(t, off + 23usize * st, (vclp((s22 -% s19), lo, hi)))
    vst(t, off + 24usize * st, (vclp((s25 -% s6), lo, hi)))
    vst(t, off + 25usize * st, (vclp((s32 -% s15), lo, hi)))
    vst(t, off + 26usize * st, (vclp((s14 -% s2), lo, hi)))
    vst(t, off + 27usize * st, (vclp((s31 -% s7), lo, hi)))
    vst(t, off + 28usize * st, (vclp((s30 -% s3), lo, hi)))
    vst(t, off + 29usize * st, (vclp((s29 -% s21), lo, hi)))
    vst(t, off + 30usize * st, (vclp((s26 -% s20), lo, hi)))
    vst(t, off + 31usize * st, (vclp((s8 -% s13), lo, hi)))
    }
}

fn vidct32_k8(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp201 = vsp(201i32)
    let kp4091 = vsp(4091i32)
    let kp1380 = vsp(1380i32)
    let kp3857 = vsp(3857i32)
    let kp995 = vsp(995i32)
    let kp3973 = vsp(3973i32)
    let kp601 = vsp(601i32)
    let kp4052 = vsp(4052i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp1189 = vsp(1189i32)
    let kp3920 = vsp(3920i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp3406 = vsp(3406i32)
    let kp2276 = vsp(2276i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 4usize * st)
    var s2 = vld(t, off + 2usize * st)
    var s3 = vld(t, off + 6usize * st)
    var s4 = vld(t, off + 1usize * st)
    var s5 = vld(t, off + 5usize * st)
    var s6 = vld(t, off + 3usize * st)
    var s7 = vld(t, off + 7usize * st)
    var s8 = ((kp2048) +% (s4 *% kp201)) >> 12u32
    s4 = ((kp2048) +% (s4 *% kp4091)) >> 12u32
    var s9 = ((kp2048) -% (s7 *% kp1380)) >> 12u32
    s7 = ((kp2048) +% (s7 *% kp3857)) >> 12u32
    var s10 = ((kp2048) +% (s5 *% kp995)) >> 12u32
    s5 = ((kp2048) +% (s5 *% kp3973)) >> 12u32
    var s11 = ((kp2048) -% (s6 *% kp601)) >> 12u32
    s6 = ((kp2048) +% (s6 *% kp4052)) >> 12u32
    var s12 = ((kp2048) +% (s2 *% kp401)) >> 12u32
    s2 = ((kp2048) +% (s2 *% kp4076)) >> 12u32
    var s13 = ((kp2048) -% (s3 *% kp1189)) >> 12u32
    s3 = ((kp2048) +% (s3 *% kp3920)) >> 12u32
    var s14 = vclp(s8, lo, hi)
    s8 = vclp(s8, lo, hi)
    var s15 = vclp(s9, lo, hi)
    s9 = vclp(s9, lo, hi)
    var s16 = vclp(s10, lo, hi)
    s10 = vclp(s10, lo, hi)
    var s17 = vclp(s11, lo, hi)
    s11 = vclp(s11, lo, hi)
    var s18 = vclp(s6, lo, hi)
    s6 = vclp(s6, lo, hi)
    var s19 = vclp(s5, lo, hi)
    s5 = vclp(s5, lo, hi)
    var s20 = vclp(s7, lo, hi)
    s7 = vclp(s7, lo, hi)
    var s21 = vclp(s4, lo, hi)
    s4 = vclp(s4, lo, hi)
    var s22 = ((kp2048) +% (s1 *% kp799)) >> 12u32
    s1 = ((kp2048) +% (s1 *% kp4017)) >> 12u32
    var s23 = vclp(s12, lo, hi)
    s12 = vclp(s12, lo, hi)
    var s24 = vclp(s13, lo, hi)
    s13 = vclp(s13, lo, hi)
    var s25 = vclp(s3, lo, hi)
    s3 = vclp(s3, lo, hi)
    var s26 = vclp(s2, lo, hi)
    s2 = vclp(s2, lo, hi)
    var s27 = (((kp2048) +% (s4 *% kp799)) -% (s8 *% kp4017)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp4017)) +% (s8 *% kp799)) >> 12u32
    s8 = (((kp2048) -% (s7 *% kp4017)) -% (s9 *% kp799)) >> 12u32
    s7 = (((kp2048) +% (s7 *% kp799)) -% (s9 *% kp4017)) >> 12u32
    s9 = (((kp2048) +% (s5 *% kp3406)) -% (s10 *% kp2276)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp2276)) +% (s10 *% kp3406)) >> 12u32
    s10 = (((kp2048) -% (s6 *% kp2276)) -% (s11 *% kp3406)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp3406)) -% (s11 *% kp2276)) >> 12u32
    s11 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    s0 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    var s28 = vclp(s22, lo, hi)
    s22 = vclp(s22, lo, hi)
    var s29 = vclp(s1, lo, hi)
    s1 = vclp(s1, lo, hi)
    var s30 = (((kp2048) +% (s2 *% kp1567)) -% (s12 *% kp3784)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3784)) +% (s12 *% kp1567)) >> 12u32
    s12 = (((kp2048) -% (s3 *% kp3784)) -% (s13 *% kp1567)) >> 12u32
    s3 = (((kp2048) +% (s3 *% kp1567)) -% (s13 *% kp3784)) >> 12u32
    s13 = vclp((s14 +% s15), lo, hi)
    s14 = vclp((s14 -% s15), lo, hi)
    s15 = vclp((s27 +% s8), lo, hi)
    s8 = vclp((s27 -% s8), lo, hi)
    s27 = vclp((s17 +% s16), lo, hi)
    s16 = vclp((s17 -% s16), lo, hi)
    s17 = vclp((s10 +% s9), lo, hi)
    s9 = vclp((s10 -% s9), lo, hi)
    s10 = vclp((s18 +% s19), lo, hi)
    s18 = vclp((s18 -% s19), lo, hi)
    s19 = vclp((s6 +% s5), lo, hi)
    s5 = vclp((s6 -% s5), lo, hi)
    s6 = vclp((s21 +% s20), lo, hi)
    s20 = vclp((s21 -% s20), lo, hi)
    s21 = vclp((s4 +% s7), lo, hi)
    s4 = vclp((s4 -% s7), lo, hi)
    s7 = vclp(s0, lo, hi)
    s0 = vclp(s0, lo, hi)
    var s31 = vclp(s11, lo, hi)
    s11 = vclp(s11, lo, hi)
    var s32 = (((kp2048) +% (s1 *% kp2896)) -% (s22 *% kp2896)) >> 12u32
    s1 = (((kp2048) +% (s1 *% kp2896)) +% (s22 *% kp2896)) >> 12u32
    s22 = vclp((s23 +% s24), lo, hi)
    s23 = vclp((s23 -% s24), lo, hi)
    s24 = vclp((s30 +% s12), lo, hi)
    s12 = vclp((s30 -% s12), lo, hi)
    s30 = vclp((s26 +% s25), lo, hi)
    s25 = vclp((s26 -% s25), lo, hi)
    s26 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = (((kp2048) +% (s4 *% kp1567)) -% (s8 *% kp3784)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp3784)) +% (s8 *% kp1567)) >> 12u32
    s8 = (((kp2048) +% (s20 *% kp1567)) -% (s14 *% kp3784)) >> 12u32
    s14 = (((kp2048) +% (s20 *% kp3784)) +% (s14 *% kp1567)) >> 12u32
    s20 = (((kp2048) -% (s18 *% kp3784)) -% (s16 *% kp1567)) >> 12u32
    s16 = (((kp2048) +% (s18 *% kp1567)) -% (s16 *% kp3784)) >> 12u32
    s18 = (((kp2048) -% (s5 *% kp3784)) -% (s9 *% kp1567)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp1567)) -% (s9 *% kp3784)) >> 12u32
    s9 = vclp((s7 +% s29), lo, hi)
    s7 = vclp((s7 -% s29), lo, hi)
    s29 = vclp((s31 +% s1), lo, hi)
    s1 = vclp((s31 -% s1), lo, hi)
    s31 = vclp((s11 +% s32), lo, hi)
    s11 = vclp((s11 -% s32), lo, hi)
    s32 = vclp((s0 +% s28), lo, hi)
    s0 = vclp((s0 -% s28), lo, hi)
    s28 = (((kp2048) +% (s2 *% kp2896)) -% (s12 *% kp2896)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp2896)) +% (s12 *% kp2896)) >> 12u32
    s12 = (((kp2048) +% (s25 *% kp2896)) -% (s23 *% kp2896)) >> 12u32
    s23 = (((kp2048) +% (s25 *% kp2896)) +% (s23 *% kp2896)) >> 12u32
    s25 = vclp((s13 +% s27), lo, hi)
    s13 = vclp((s13 -% s27), lo, hi)
    s27 = vclp((s15 +% s17), lo, hi)
    s15 = vclp((s15 -% s17), lo, hi)
    s17 = vclp((s3 +% s18), lo, hi)
    s3 = vclp((s3 -% s18), lo, hi)
    s18 = vclp((s8 +% s20), lo, hi)
    s8 = vclp((s8 -% s20), lo, hi)
    s20 = vclp((s6 +% s10), lo, hi)
    s6 = vclp((s6 -% s10), lo, hi)
    s10 = vclp((s21 +% s19), lo, hi)
    s19 = vclp((s21 -% s19), lo, hi)
    s21 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = vclp((s14 +% s16), lo, hi)
    s14 = vclp((s14 -% s16), lo, hi)
    s16 = vclp((s9 +% s30), lo, hi)
    s9 = vclp((s9 -% s30), lo, hi)
    s30 = vclp((s29 +% s26), lo, hi)
    s26 = vclp((s29 -% s26), lo, hi)
    s29 = vclp((s31 +% s2), lo, hi)
    s2 = vclp((s31 -% s2), lo, hi)
    s31 = vclp((s32 +% s23), lo, hi)
    s23 = vclp((s32 -% s23), lo, hi)
    s32 = vclp((s0 +% s12), lo, hi)
    s0 = vclp((s0 -% s12), lo, hi)
    s12 = vclp((s11 +% s28), lo, hi)
    s11 = vclp((s11 -% s28), lo, hi)
    s28 = vclp((s1 +% s24), lo, hi)
    s1 = vclp((s1 -% s24), lo, hi)
    s24 = vclp((s7 +% s22), lo, hi)
    s7 = vclp((s7 -% s22), lo, hi)
    s22 = (((kp2048) +% (s14 *% kp2896)) -% (s8 *% kp2896)) >> 12u32
    s8 = (((kp2048) +% (s14 *% kp2896)) +% (s8 *% kp2896)) >> 12u32
    s14 = (((kp2048) +% (s4 *% kp2896)) -% (s3 *% kp2896)) >> 12u32
    s3 = (((kp2048) +% (s4 *% kp2896)) +% (s3 *% kp2896)) >> 12u32
    s4 = (((kp2048) +% (s19 *% kp2896)) -% (s15 *% kp2896)) >> 12u32
    s15 = (((kp2048) +% (s19 *% kp2896)) +% (s15 *% kp2896)) >> 12u32
    s19 = (((kp2048) +% (s6 *% kp2896)) -% (s13 *% kp2896)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp2896)) +% (s13 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s16 +% s20), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s30 +% s10), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s29 +% s21), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s31 +% s5), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s32 +% s8), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s12 +% s3), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s28 +% s15), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s24 +% s6), lo, hi)))
    vst(t, off + 8usize * st, (vclp((s7 +% s19), lo, hi)))
    vst(t, off + 9usize * st, (vclp((s1 +% s4), lo, hi)))
    vst(t, off + 10usize * st, (vclp((s11 +% s14), lo, hi)))
    vst(t, off + 11usize * st, (vclp((s0 +% s22), lo, hi)))
    vst(t, off + 12usize * st, (vclp((s23 +% s18), lo, hi)))
    vst(t, off + 13usize * st, (vclp((s2 +% s17), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s26 +% s27), lo, hi)))
    vst(t, off + 15usize * st, (vclp((s9 +% s25), lo, hi)))
    vst(t, off + 16usize * st, (vclp((s9 -% s25), lo, hi)))
    vst(t, off + 17usize * st, (vclp((s26 -% s27), lo, hi)))
    vst(t, off + 18usize * st, (vclp((s2 -% s17), lo, hi)))
    vst(t, off + 19usize * st, (vclp((s23 -% s18), lo, hi)))
    vst(t, off + 20usize * st, (vclp((s0 -% s22), lo, hi)))
    vst(t, off + 21usize * st, (vclp((s11 -% s14), lo, hi)))
    vst(t, off + 22usize * st, (vclp((s1 -% s4), lo, hi)))
    vst(t, off + 23usize * st, (vclp((s7 -% s19), lo, hi)))
    vst(t, off + 24usize * st, (vclp((s24 -% s6), lo, hi)))
    vst(t, off + 25usize * st, (vclp((s28 -% s15), lo, hi)))
    vst(t, off + 26usize * st, (vclp((s12 -% s3), lo, hi)))
    vst(t, off + 27usize * st, (vclp((s32 -% s8), lo, hi)))
    vst(t, off + 28usize * st, (vclp((s31 -% s5), lo, hi)))
    vst(t, off + 29usize * st, (vclp((s29 -% s21), lo, hi)))
    vst(t, off + 30usize * st, (vclp((s30 -% s10), lo, hi)))
    vst(t, off + 31usize * st, (vclp((s16 -% s20), lo, hi)))
    }
}

fn vidct32_k16(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp201 = vsp(201i32)
    let kp4091 = vsp(4091i32)
    let kp2751 = vsp(2751i32)
    let kp3035 = vsp(3035i32)
    let kp1751 = vsp(1751i32)
    let kp3703 = vsp(3703i32)
    let kp1380 = vsp(1380i32)
    let kp3857 = vsp(3857i32)
    let kp995 = vsp(995i32)
    let kp3973 = vsp(3973i32)
    let kp2106 = vsp(2106i32)
    let kp3513 = vsp(3513i32)
    let kp2440 = vsp(2440i32)
    let kp3290 = vsp(3290i32)
    let kp601 = vsp(601i32)
    let kp4052 = vsp(4052i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp2598 = vsp(2598i32)
    let kp3166 = vsp(3166i32)
    let kp1931 = vsp(1931i32)
    let kp3612 = vsp(3612i32)
    let kp1189 = vsp(1189i32)
    let kp3920 = vsp(3920i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp2276 = vsp(2276i32)
    let kp3406 = vsp(3406i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 8usize * st)
    var s2 = vld(t, off + 4usize * st)
    var s3 = vld(t, off + 12usize * st)
    var s4 = vld(t, off + 2usize * st)
    var s5 = vld(t, off + 10usize * st)
    var s6 = vld(t, off + 6usize * st)
    var s7 = vld(t, off + 14usize * st)
    var s8 = vld(t, off + 1usize * st)
    var s9 = vld(t, off + 9usize * st)
    var s10 = vld(t, off + 5usize * st)
    var s11 = vld(t, off + 13usize * st)
    var s12 = vld(t, off + 3usize * st)
    var s13 = vld(t, off + 11usize * st)
    var s14 = vld(t, off + 7usize * st)
    var s15 = vld(t, off + 15usize * st)
    var s16 = ((kp2048) +% (s8 *% kp201)) >> 12u32
    s8 = ((kp2048) +% (s8 *% kp4091)) >> 12u32
    var s17 = ((kp2048) -% (s15 *% kp2751)) >> 12u32
    s15 = ((kp2048) +% (s15 *% kp3035)) >> 12u32
    var s18 = ((kp2048) +% (s9 *% kp1751)) >> 12u32
    s9 = ((kp2048) +% (s9 *% kp3703)) >> 12u32
    var s19 = ((kp2048) -% (s14 *% kp1380)) >> 12u32
    s14 = ((kp2048) +% (s14 *% kp3857)) >> 12u32
    var s20 = ((kp2048) +% (s10 *% kp995)) >> 12u32
    s10 = ((kp2048) +% (s10 *% kp3973)) >> 12u32
    var s21 = ((kp2048) -% (s13 *% kp2106)) >> 12u32
    s13 = ((kp2048) +% (s13 *% kp3513)) >> 12u32
    var s22 = ((kp2048) +% (s11 *% kp2440)) >> 12u32
    s11 = ((kp2048) +% (s11 *% kp3290)) >> 12u32
    var s23 = ((kp2048) -% (s12 *% kp601)) >> 12u32
    s12 = ((kp2048) +% (s12 *% kp4052)) >> 12u32
    var s24 = ((kp2048) +% (s4 *% kp401)) >> 12u32
    s4 = ((kp2048) +% (s4 *% kp4076)) >> 12u32
    var s25 = ((kp2048) -% (s7 *% kp2598)) >> 12u32
    s7 = ((kp2048) +% (s7 *% kp3166)) >> 12u32
    var s26 = ((kp2048) +% (s5 *% kp1931)) >> 12u32
    s5 = ((kp2048) +% (s5 *% kp3612)) >> 12u32
    var s27 = ((kp2048) -% (s6 *% kp1189)) >> 12u32
    s6 = ((kp2048) +% (s6 *% kp3920)) >> 12u32
    var s28 = vclp((s16 +% s17), lo, hi)
    s16 = vclp((s16 -% s17), lo, hi)
    s17 = vclp((s19 +% s18), lo, hi)
    s18 = vclp((s19 -% s18), lo, hi)
    s19 = vclp((s20 +% s21), lo, hi)
    s20 = vclp((s20 -% s21), lo, hi)
    s21 = vclp((s23 +% s22), lo, hi)
    s22 = vclp((s23 -% s22), lo, hi)
    s23 = vclp((s12 +% s11), lo, hi)
    s11 = vclp((s12 -% s11), lo, hi)
    s12 = vclp((s10 +% s13), lo, hi)
    s10 = vclp((s10 -% s13), lo, hi)
    s13 = vclp((s14 +% s9), lo, hi)
    s9 = vclp((s14 -% s9), lo, hi)
    s14 = vclp((s8 +% s15), lo, hi)
    s8 = vclp((s8 -% s15), lo, hi)
    s15 = ((kp2048) +% (s2 *% kp799)) >> 12u32
    s2 = ((kp2048) +% (s2 *% kp4017)) >> 12u32
    var s29 = ((kp2048) -% (s3 *% kp2276)) >> 12u32
    s3 = ((kp2048) +% (s3 *% kp3406)) >> 12u32
    var s30 = vclp((s24 +% s25), lo, hi)
    s24 = vclp((s24 -% s25), lo, hi)
    s25 = vclp((s27 +% s26), lo, hi)
    s26 = vclp((s27 -% s26), lo, hi)
    s27 = vclp((s6 +% s5), lo, hi)
    s5 = vclp((s6 -% s5), lo, hi)
    s6 = vclp((s4 +% s7), lo, hi)
    s4 = vclp((s4 -% s7), lo, hi)
    s7 = (((kp2048) +% (s8 *% kp799)) -% (s16 *% kp4017)) >> 12u32
    s8 = (((kp2048) +% (s8 *% kp4017)) +% (s16 *% kp799)) >> 12u32
    s16 = (((kp2048) -% (s9 *% kp4017)) -% (s18 *% kp799)) >> 12u32
    s9 = (((kp2048) +% (s9 *% kp799)) -% (s18 *% kp4017)) >> 12u32
    s18 = (((kp2048) +% (s10 *% kp3406)) -% (s20 *% kp2276)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp2276)) +% (s20 *% kp3406)) >> 12u32
    s20 = (((kp2048) -% (s11 *% kp2276)) -% (s22 *% kp3406)) >> 12u32
    s11 = (((kp2048) +% (s11 *% kp3406)) -% (s22 *% kp2276)) >> 12u32
    s22 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    s0 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    var s31 = ((kp2048) +% (s1 *% kp1567)) >> 12u32
    s1 = ((kp2048) +% (s1 *% kp3784)) >> 12u32
    var s32 = vclp((s15 +% s29), lo, hi)
    s15 = vclp((s15 -% s29), lo, hi)
    s29 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = (((kp2048) +% (s4 *% kp1567)) -% (s24 *% kp3784)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp3784)) +% (s24 *% kp1567)) >> 12u32
    s24 = (((kp2048) -% (s5 *% kp3784)) -% (s26 *% kp1567)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp1567)) -% (s26 *% kp3784)) >> 12u32
    s26 = vclp((s28 +% s17), lo, hi)
    s17 = vclp((s28 -% s17), lo, hi)
    s28 = vclp((s7 +% s16), lo, hi)
    s7 = vclp((s7 -% s16), lo, hi)
    s16 = vclp((s21 +% s19), lo, hi)
    s19 = vclp((s21 -% s19), lo, hi)
    s21 = vclp((s20 +% s18), lo, hi)
    s18 = vclp((s20 -% s18), lo, hi)
    s20 = vclp((s23 +% s12), lo, hi)
    s12 = vclp((s23 -% s12), lo, hi)
    s23 = vclp((s11 +% s10), lo, hi)
    s10 = vclp((s11 -% s10), lo, hi)
    s11 = vclp((s14 +% s13), lo, hi)
    s13 = vclp((s14 -% s13), lo, hi)
    s14 = vclp((s8 +% s9), lo, hi)
    s8 = vclp((s8 -% s9), lo, hi)
    s9 = vclp((s0 +% s1), lo, hi)
    s0 = vclp((s0 -% s1), lo, hi)
    s1 = vclp((s22 +% s31), lo, hi)
    s22 = vclp((s22 -% s31), lo, hi)
    s31 = (((kp2048) +% (s2 *% kp2896)) -% (s15 *% kp2896)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp2896)) +% (s15 *% kp2896)) >> 12u32
    s15 = vclp((s30 +% s25), lo, hi)
    s25 = vclp((s30 -% s25), lo, hi)
    s30 = vclp((s3 +% s24), lo, hi)
    s3 = vclp((s3 -% s24), lo, hi)
    s24 = vclp((s6 +% s27), lo, hi)
    s6 = vclp((s6 -% s27), lo, hi)
    s27 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = (((kp2048) +% (s8 *% kp1567)) -% (s7 *% kp3784)) >> 12u32
    s7 = (((kp2048) +% (s8 *% kp3784)) +% (s7 *% kp1567)) >> 12u32
    s8 = (((kp2048) +% (s13 *% kp1567)) -% (s17 *% kp3784)) >> 12u32
    s13 = (((kp2048) +% (s13 *% kp3784)) +% (s17 *% kp1567)) >> 12u32
    s17 = (((kp2048) -% (s12 *% kp3784)) -% (s19 *% kp1567)) >> 12u32
    s12 = (((kp2048) +% (s12 *% kp1567)) -% (s19 *% kp3784)) >> 12u32
    s19 = (((kp2048) -% (s10 *% kp3784)) -% (s18 *% kp1567)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp1567)) -% (s18 *% kp3784)) >> 12u32
    s18 = vclp((s9 +% s29), lo, hi)
    s9 = vclp((s9 -% s29), lo, hi)
    s29 = vclp((s1 +% s2), lo, hi)
    s1 = vclp((s1 -% s2), lo, hi)
    s2 = vclp((s22 +% s31), lo, hi)
    s22 = vclp((s22 -% s31), lo, hi)
    s31 = vclp((s0 +% s32), lo, hi)
    s0 = vclp((s0 -% s32), lo, hi)
    s32 = (((kp2048) +% (s4 *% kp2896)) -% (s3 *% kp2896)) >> 12u32
    s3 = (((kp2048) +% (s4 *% kp2896)) +% (s3 *% kp2896)) >> 12u32
    s4 = (((kp2048) +% (s6 *% kp2896)) -% (s25 *% kp2896)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp2896)) +% (s25 *% kp2896)) >> 12u32
    s25 = vclp((s26 +% s16), lo, hi)
    s16 = vclp((s26 -% s16), lo, hi)
    s26 = vclp((s28 +% s21), lo, hi)
    s21 = vclp((s28 -% s21), lo, hi)
    s28 = vclp((s5 +% s19), lo, hi)
    s5 = vclp((s5 -% s19), lo, hi)
    s19 = vclp((s8 +% s17), lo, hi)
    s8 = vclp((s8 -% s17), lo, hi)
    s17 = vclp((s11 +% s20), lo, hi)
    s11 = vclp((s11 -% s20), lo, hi)
    s20 = vclp((s14 +% s23), lo, hi)
    s14 = vclp((s14 -% s23), lo, hi)
    s23 = vclp((s7 +% s10), lo, hi)
    s7 = vclp((s7 -% s10), lo, hi)
    s10 = vclp((s13 +% s12), lo, hi)
    s12 = vclp((s13 -% s12), lo, hi)
    s13 = vclp((s18 +% s24), lo, hi)
    s18 = vclp((s18 -% s24), lo, hi)
    s24 = vclp((s29 +% s27), lo, hi)
    s27 = vclp((s29 -% s27), lo, hi)
    s29 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = vclp((s31 +% s6), lo, hi)
    s6 = vclp((s31 -% s6), lo, hi)
    s31 = vclp((s0 +% s4), lo, hi)
    s0 = vclp((s0 -% s4), lo, hi)
    s4 = vclp((s22 +% s32), lo, hi)
    s22 = vclp((s22 -% s32), lo, hi)
    s32 = vclp((s1 +% s30), lo, hi)
    s1 = vclp((s1 -% s30), lo, hi)
    s30 = vclp((s9 +% s15), lo, hi)
    s9 = vclp((s9 -% s15), lo, hi)
    s15 = (((kp2048) +% (s12 *% kp2896)) -% (s8 *% kp2896)) >> 12u32
    s8 = (((kp2048) +% (s12 *% kp2896)) +% (s8 *% kp2896)) >> 12u32
    s12 = (((kp2048) +% (s7 *% kp2896)) -% (s5 *% kp2896)) >> 12u32
    s5 = (((kp2048) +% (s7 *% kp2896)) +% (s5 *% kp2896)) >> 12u32
    s7 = (((kp2048) +% (s14 *% kp2896)) -% (s21 *% kp2896)) >> 12u32
    s14 = (((kp2048) +% (s14 *% kp2896)) +% (s21 *% kp2896)) >> 12u32
    s21 = (((kp2048) +% (s11 *% kp2896)) -% (s16 *% kp2896)) >> 12u32
    s11 = (((kp2048) +% (s11 *% kp2896)) +% (s16 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s13 +% s17), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s24 +% s20), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s29 +% s23), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s3 +% s10), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s31 +% s8), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s4 +% s5), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s32 +% s14), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s30 +% s11), lo, hi)))
    vst(t, off + 8usize * st, (vclp((s9 +% s21), lo, hi)))
    vst(t, off + 9usize * st, (vclp((s1 +% s7), lo, hi)))
    vst(t, off + 10usize * st, (vclp((s22 +% s12), lo, hi)))
    vst(t, off + 11usize * st, (vclp((s0 +% s15), lo, hi)))
    vst(t, off + 12usize * st, (vclp((s6 +% s19), lo, hi)))
    vst(t, off + 13usize * st, (vclp((s2 +% s28), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s27 +% s26), lo, hi)))
    vst(t, off + 15usize * st, (vclp((s18 +% s25), lo, hi)))
    vst(t, off + 16usize * st, (vclp((s18 -% s25), lo, hi)))
    vst(t, off + 17usize * st, (vclp((s27 -% s26), lo, hi)))
    vst(t, off + 18usize * st, (vclp((s2 -% s28), lo, hi)))
    vst(t, off + 19usize * st, (vclp((s6 -% s19), lo, hi)))
    vst(t, off + 20usize * st, (vclp((s0 -% s15), lo, hi)))
    vst(t, off + 21usize * st, (vclp((s22 -% s12), lo, hi)))
    vst(t, off + 22usize * st, (vclp((s1 -% s7), lo, hi)))
    vst(t, off + 23usize * st, (vclp((s9 -% s21), lo, hi)))
    vst(t, off + 24usize * st, (vclp((s30 -% s11), lo, hi)))
    vst(t, off + 25usize * st, (vclp((s32 -% s14), lo, hi)))
    vst(t, off + 26usize * st, (vclp((s4 -% s5), lo, hi)))
    vst(t, off + 27usize * st, (vclp((s31 -% s8), lo, hi)))
    vst(t, off + 28usize * st, (vclp((s3 -% s10), lo, hi)))
    vst(t, off + 29usize * st, (vclp((s29 -% s23), lo, hi)))
    vst(t, off + 30usize * st, (vclp((s24 -% s20), lo, hi)))
    vst(t, off + 31usize * st, (vclp((s13 -% s17), lo, hi)))
    }
}

fn vidct64_k4(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp101 = vsp(101i32)
    let kp4095 = vsp(4095i32)
    let kp301 = vsp(301i32)
    let kp4085 = vsp(4085i32)
    let kp201 = vsp(201i32)
    let kp4091 = vsp(4091i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp1189 = vsp(1189i32)
    let kp3920 = vsp(3920i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp2896 = vsp(2896i32)
    let kp2276 = vsp(2276i32)
    let kp3406 = vsp(3406i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 2usize * st)
    var s2 = vld(t, off + 1usize * st)
    var s3 = vld(t, off + 3usize * st)
    var s4 = ((kp2048) +% (s2 *% kp101)) >> 12u32
    s2 = ((kp2048) +% (s2 *% kp4095)) >> 12u32
    var s5 = ((kp2048) -% (s3 *% kp301)) >> 12u32
    s3 = ((kp2048) +% (s3 *% kp4085)) >> 12u32
    var s6 = ((kp2048) +% (s1 *% kp201)) >> 12u32
    s1 = ((kp2048) +% (s1 *% kp4091)) >> 12u32
    var s7 = vclp(s4, lo, hi)
    s4 = vclp(s4, lo, hi)
    var s8 = vclp(s5, lo, hi)
    s5 = vclp(s5, lo, hi)
    var s9 = vclp(s3, lo, hi)
    s3 = vclp(s3, lo, hi)
    var s10 = vclp(s2, lo, hi)
    s2 = vclp(s2, lo, hi)
    var s11 = vclp(s6, lo, hi)
    s6 = vclp(s6, lo, hi)
    var s12 = vclp(s1, lo, hi)
    s1 = vclp(s1, lo, hi)
    var s13 = (((kp2048) +% (s2 *% kp401)) -% (s4 *% kp4076)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp4076)) +% (s4 *% kp401)) >> 12u32
    s4 = (((kp2048) -% (s3 *% kp1189)) -% (s5 *% kp3920)) >> 12u32
    s3 = (((kp2048) +% (s3 *% kp3920)) -% (s5 *% kp1189)) >> 12u32
    s5 = (((kp2048) +% (s1 *% kp799)) -% (s6 *% kp4017)) >> 12u32
    s1 = (((kp2048) +% (s1 *% kp4017)) +% (s6 *% kp799)) >> 12u32
    s6 = vclp(s7, lo, hi)
    s7 = vclp(s7, lo, hi)
    var s14 = vclp(s13, lo, hi)
    s13 = vclp(s13, lo, hi)
    var s15 = vclp(s8, lo, hi)
    s8 = vclp(s8, lo, hi)
    var s16 = vclp(s4, lo, hi)
    s4 = vclp(s4, lo, hi)
    var s17 = vclp(s9, lo, hi)
    s9 = vclp(s9, lo, hi)
    var s18 = vclp(s3, lo, hi)
    s3 = vclp(s3, lo, hi)
    var s19 = vclp(s10, lo, hi)
    s10 = vclp(s10, lo, hi)
    var s20 = vclp(s2, lo, hi)
    s2 = vclp(s2, lo, hi)
    var s21 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    s0 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    var s22 = vclp(s11, lo, hi)
    s11 = vclp(s11, lo, hi)
    var s23 = vclp(s5, lo, hi)
    s5 = vclp(s5, lo, hi)
    var s24 = vclp(s12, lo, hi)
    s12 = vclp(s12, lo, hi)
    var s25 = vclp(s1, lo, hi)
    s1 = vclp(s1, lo, hi)
    var s26 = (((kp2048) +% (s2 *% kp799)) -% (s13 *% kp4017)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp4017)) +% (s13 *% kp799)) >> 12u32
    s13 = (((kp2048) +% (s10 *% kp799)) -% (s7 *% kp4017)) >> 12u32
    s7 = (((kp2048) +% (s10 *% kp4017)) +% (s7 *% kp799)) >> 12u32
    s10 = (((kp2048) -% (s9 *% kp2276)) -% (s8 *% kp3406)) >> 12u32
    s8 = (((kp2048) +% (s9 *% kp3406)) -% (s8 *% kp2276)) >> 12u32
    s9 = (((kp2048) -% (s3 *% kp2276)) -% (s4 *% kp3406)) >> 12u32
    s3 = (((kp2048) +% (s3 *% kp3406)) -% (s4 *% kp2276)) >> 12u32
    s4 = vclp(s0, lo, hi)
    s0 = vclp(s0, lo, hi)
    var s27 = vclp(s21, lo, hi)
    s21 = vclp(s21, lo, hi)
    var s28 = (((kp2048) +% (s1 *% kp1567)) -% (s5 *% kp3784)) >> 12u32
    s1 = (((kp2048) +% (s1 *% kp3784)) +% (s5 *% kp1567)) >> 12u32
    s5 = (((kp2048) +% (s12 *% kp1567)) -% (s11 *% kp3784)) >> 12u32
    s11 = (((kp2048) +% (s12 *% kp3784)) +% (s11 *% kp1567)) >> 12u32
    s12 = vclp(s6, lo, hi)
    s6 = vclp(s6, lo, hi)
    var s29 = vclp(s14, lo, hi)
    s14 = vclp(s14, lo, hi)
    var s30 = vclp(s26, lo, hi)
    s26 = vclp(s26, lo, hi)
    var s31 = vclp(s13, lo, hi)
    s13 = vclp(s13, lo, hi)
    var s32 = vclp(s15, lo, hi)
    s15 = vclp(s15, lo, hi)
    var s33 = vclp(s16, lo, hi)
    s16 = vclp(s16, lo, hi)
    var s34 = vclp(s9, lo, hi)
    s9 = vclp(s9, lo, hi)
    var s35 = vclp(s10, lo, hi)
    s10 = vclp(s10, lo, hi)
    var s36 = vclp(s17, lo, hi)
    s17 = vclp(s17, lo, hi)
    var s37 = vclp(s18, lo, hi)
    s18 = vclp(s18, lo, hi)
    var s38 = vclp(s3, lo, hi)
    s3 = vclp(s3, lo, hi)
    var s39 = vclp(s8, lo, hi)
    s8 = vclp(s8, lo, hi)
    var s40 = vclp(s19, lo, hi)
    s19 = vclp(s19, lo, hi)
    var s41 = vclp(s20, lo, hi)
    s20 = vclp(s20, lo, hi)
    var s42 = vclp(s2, lo, hi)
    s2 = vclp(s2, lo, hi)
    var s43 = vclp(s7, lo, hi)
    s7 = vclp(s7, lo, hi)
    var s44 = vclp(s4, lo, hi)
    s4 = vclp(s4, lo, hi)
    var s45 = vclp(s27, lo, hi)
    s27 = vclp(s27, lo, hi)
    var s46 = vclp(s21, lo, hi)
    s21 = vclp(s21, lo, hi)
    var s47 = vclp(s0, lo, hi)
    s0 = vclp(s0, lo, hi)
    var s48 = vclp(s22, lo, hi)
    s22 = vclp(s22, lo, hi)
    var s49 = vclp(s23, lo, hi)
    s23 = vclp(s23, lo, hi)
    var s50 = vclp(s28, lo, hi)
    s28 = vclp(s28, lo, hi)
    var s51 = vclp(s5, lo, hi)
    s5 = vclp(s5, lo, hi)
    var s52 = vclp(s24, lo, hi)
    s24 = vclp(s24, lo, hi)
    var s53 = vclp(s25, lo, hi)
    s25 = vclp(s25, lo, hi)
    var s54 = vclp(s1, lo, hi)
    s1 = vclp(s1, lo, hi)
    var s55 = vclp(s11, lo, hi)
    s11 = vclp(s11, lo, hi)
    var s56 = (((kp2048) +% (s7 *% kp1567)) -% (s13 *% kp3784)) >> 12u32
    s7 = (((kp2048) +% (s7 *% kp3784)) +% (s13 *% kp1567)) >> 12u32
    s13 = (((kp2048) +% (s2 *% kp1567)) -% (s26 *% kp3784)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3784)) +% (s26 *% kp1567)) >> 12u32
    s26 = (((kp2048) +% (s20 *% kp1567)) -% (s14 *% kp3784)) >> 12u32
    s14 = (((kp2048) +% (s20 *% kp3784)) +% (s14 *% kp1567)) >> 12u32
    s20 = (((kp2048) +% (s19 *% kp1567)) -% (s6 *% kp3784)) >> 12u32
    s6 = (((kp2048) +% (s19 *% kp3784)) +% (s6 *% kp1567)) >> 12u32
    s19 = (((kp2048) -% (s17 *% kp3784)) -% (s15 *% kp1567)) >> 12u32
    s15 = (((kp2048) +% (s17 *% kp1567)) -% (s15 *% kp3784)) >> 12u32
    s17 = (((kp2048) -% (s18 *% kp3784)) -% (s16 *% kp1567)) >> 12u32
    s16 = (((kp2048) +% (s18 *% kp1567)) -% (s16 *% kp3784)) >> 12u32
    s18 = (((kp2048) -% (s3 *% kp3784)) -% (s9 *% kp1567)) >> 12u32
    s3 = (((kp2048) +% (s3 *% kp1567)) -% (s9 *% kp3784)) >> 12u32
    s9 = (((kp2048) -% (s8 *% kp3784)) -% (s10 *% kp1567)) >> 12u32
    s8 = (((kp2048) +% (s8 *% kp1567)) -% (s10 *% kp3784)) >> 12u32
    s10 = vclp(s44, lo, hi)
    s44 = vclp(s44, lo, hi)
    var s57 = vclp(s45, lo, hi)
    s45 = vclp(s45, lo, hi)
    var s58 = vclp(s46, lo, hi)
    s46 = vclp(s46, lo, hi)
    var s59 = vclp(s47, lo, hi)
    s47 = vclp(s47, lo, hi)
    var s60 = vclp(s0, lo, hi)
    s0 = vclp(s0, lo, hi)
    var s61 = vclp(s21, lo, hi)
    s21 = vclp(s21, lo, hi)
    var s62 = vclp(s27, lo, hi)
    s27 = vclp(s27, lo, hi)
    var s63 = vclp(s4, lo, hi)
    s4 = vclp(s4, lo, hi)
    var s64 = (((kp2048) +% (s11 *% kp2896)) -% (s5 *% kp2896)) >> 12u32
    s5 = (((kp2048) +% (s11 *% kp2896)) +% (s5 *% kp2896)) >> 12u32
    s11 = (((kp2048) +% (s1 *% kp2896)) -% (s28 *% kp2896)) >> 12u32
    s1 = (((kp2048) +% (s1 *% kp2896)) +% (s28 *% kp2896)) >> 12u32
    s28 = (((kp2048) +% (s25 *% kp2896)) -% (s23 *% kp2896)) >> 12u32
    s23 = (((kp2048) +% (s25 *% kp2896)) +% (s23 *% kp2896)) >> 12u32
    s25 = (((kp2048) +% (s24 *% kp2896)) -% (s22 *% kp2896)) >> 12u32
    s22 = (((kp2048) +% (s24 *% kp2896)) +% (s22 *% kp2896)) >> 12u32
    s24 = vclp((s12 +% s32), lo, hi)
    s12 = vclp((s12 -% s32), lo, hi)
    s32 = vclp((s40 +% s36), lo, hi)
    s36 = vclp((s40 -% s36), lo, hi)
    s40 = vclp((s29 +% s33), lo, hi)
    s29 = vclp((s29 -% s33), lo, hi)
    s33 = vclp((s41 +% s37), lo, hi)
    s37 = vclp((s41 -% s37), lo, hi)
    s41 = vclp((s30 +% s34), lo, hi)
    s30 = vclp((s30 -% s34), lo, hi)
    s34 = vclp((s42 +% s38), lo, hi)
    s38 = vclp((s42 -% s38), lo, hi)
    s42 = vclp((s31 +% s35), lo, hi)
    s31 = vclp((s31 -% s35), lo, hi)
    s35 = vclp((s43 +% s39), lo, hi)
    s39 = vclp((s43 -% s39), lo, hi)
    s43 = vclp((s56 +% s9), lo, hi)
    s9 = vclp((s56 -% s9), lo, hi)
    s56 = vclp((s7 +% s8), lo, hi)
    s7 = vclp((s7 -% s8), lo, hi)
    s8 = vclp((s13 +% s18), lo, hi)
    s13 = vclp((s13 -% s18), lo, hi)
    s18 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = vclp((s26 +% s17), lo, hi)
    s17 = vclp((s26 -% s17), lo, hi)
    s26 = vclp((s14 +% s16), lo, hi)
    s14 = vclp((s14 -% s16), lo, hi)
    s16 = vclp((s20 +% s19), lo, hi)
    s19 = vclp((s20 -% s19), lo, hi)
    s20 = vclp((s6 +% s15), lo, hi)
    s6 = vclp((s6 -% s15), lo, hi)
    s15 = vclp((s10 +% s52), lo, hi)
    s10 = vclp((s10 -% s52), lo, hi)
    s52 = vclp((s57 +% s53), lo, hi)
    s53 = vclp((s57 -% s53), lo, hi)
    s57 = vclp((s58 +% s54), lo, hi)
    s54 = vclp((s58 -% s54), lo, hi)
    s58 = vclp((s59 +% s55), lo, hi)
    s55 = vclp((s59 -% s55), lo, hi)
    s59 = vclp((s60 +% s5), lo, hi)
    s5 = vclp((s60 -% s5), lo, hi)
    s60 = vclp((s61 +% s1), lo, hi)
    s1 = vclp((s61 -% s1), lo, hi)
    s61 = vclp((s62 +% s23), lo, hi)
    s23 = vclp((s62 -% s23), lo, hi)
    s62 = vclp((s63 +% s22), lo, hi)
    s22 = vclp((s63 -% s22), lo, hi)
    s63 = vclp((s4 +% s25), lo, hi)
    s4 = vclp((s4 -% s25), lo, hi)
    s25 = vclp((s27 +% s28), lo, hi)
    s27 = vclp((s27 -% s28), lo, hi)
    s28 = vclp((s21 +% s11), lo, hi)
    s11 = vclp((s21 -% s11), lo, hi)
    s21 = vclp((s0 +% s64), lo, hi)
    s0 = vclp((s0 -% s64), lo, hi)
    s64 = vclp((s47 +% s51), lo, hi)
    s47 = vclp((s47 -% s51), lo, hi)
    s51 = vclp((s46 +% s50), lo, hi)
    s46 = vclp((s46 -% s50), lo, hi)
    s50 = vclp((s45 +% s49), lo, hi)
    s45 = vclp((s45 -% s49), lo, hi)
    s49 = vclp((s44 +% s48), lo, hi)
    s44 = vclp((s44 -% s48), lo, hi)
    s48 = (((kp2048) +% (s6 *% kp2896)) -% (s19 *% kp2896)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp2896)) +% (s19 *% kp2896)) >> 12u32
    s19 = (((kp2048) +% (s14 *% kp2896)) -% (s17 *% kp2896)) >> 12u32
    s14 = (((kp2048) +% (s14 *% kp2896)) +% (s17 *% kp2896)) >> 12u32
    s17 = (((kp2048) +% (s2 *% kp2896)) -% (s13 *% kp2896)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp2896)) +% (s13 *% kp2896)) >> 12u32
    s13 = (((kp2048) +% (s7 *% kp2896)) -% (s9 *% kp2896)) >> 12u32
    s7 = (((kp2048) +% (s7 *% kp2896)) +% (s9 *% kp2896)) >> 12u32
    s9 = (((kp2048) +% (s39 *% kp2896)) -% (s31 *% kp2896)) >> 12u32
    s31 = (((kp2048) +% (s39 *% kp2896)) +% (s31 *% kp2896)) >> 12u32
    s39 = (((kp2048) +% (s38 *% kp2896)) -% (s30 *% kp2896)) >> 12u32
    s30 = (((kp2048) +% (s38 *% kp2896)) +% (s30 *% kp2896)) >> 12u32
    s38 = (((kp2048) +% (s37 *% kp2896)) -% (s29 *% kp2896)) >> 12u32
    s29 = (((kp2048) +% (s37 *% kp2896)) +% (s29 *% kp2896)) >> 12u32
    s37 = (((kp2048) +% (s36 *% kp2896)) -% (s12 *% kp2896)) >> 12u32
    s12 = (((kp2048) +% (s36 *% kp2896)) +% (s12 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s15 +% s32), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s52 +% s33), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s57 +% s34), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s58 +% s35), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s59 +% s56), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s60 +% s18), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s61 +% s26), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s62 +% s20), lo, hi)))
    vst(t, off + 8usize * st, (vclp((s63 +% s6), lo, hi)))
    vst(t, off + 9usize * st, (vclp((s25 +% s14), lo, hi)))
    vst(t, off + 10usize * st, (vclp((s28 +% s2), lo, hi)))
    vst(t, off + 11usize * st, (vclp((s21 +% s7), lo, hi)))
    vst(t, off + 12usize * st, (vclp((s64 +% s31), lo, hi)))
    vst(t, off + 13usize * st, (vclp((s51 +% s30), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s50 +% s29), lo, hi)))
    vst(t, off + 15usize * st, (vclp((s49 +% s12), lo, hi)))
    vst(t, off + 16usize * st, (vclp((s44 +% s37), lo, hi)))
    vst(t, off + 17usize * st, (vclp((s45 +% s38), lo, hi)))
    vst(t, off + 18usize * st, (vclp((s46 +% s39), lo, hi)))
    vst(t, off + 19usize * st, (vclp((s47 +% s9), lo, hi)))
    vst(t, off + 20usize * st, (vclp((s0 +% s13), lo, hi)))
    vst(t, off + 21usize * st, (vclp((s11 +% s17), lo, hi)))
    vst(t, off + 22usize * st, (vclp((s27 +% s19), lo, hi)))
    vst(t, off + 23usize * st, (vclp((s4 +% s48), lo, hi)))
    vst(t, off + 24usize * st, (vclp((s22 +% s16), lo, hi)))
    vst(t, off + 25usize * st, (vclp((s23 +% s3), lo, hi)))
    vst(t, off + 26usize * st, (vclp((s1 +% s8), lo, hi)))
    vst(t, off + 27usize * st, (vclp((s5 +% s43), lo, hi)))
    vst(t, off + 28usize * st, (vclp((s55 +% s42), lo, hi)))
    vst(t, off + 29usize * st, (vclp((s54 +% s41), lo, hi)))
    vst(t, off + 30usize * st, (vclp((s53 +% s40), lo, hi)))
    vst(t, off + 31usize * st, (vclp((s10 +% s24), lo, hi)))
    vst(t, off + 32usize * st, (vclp((s10 -% s24), lo, hi)))
    vst(t, off + 33usize * st, (vclp((s53 -% s40), lo, hi)))
    vst(t, off + 34usize * st, (vclp((s54 -% s41), lo, hi)))
    vst(t, off + 35usize * st, (vclp((s55 -% s42), lo, hi)))
    vst(t, off + 36usize * st, (vclp((s5 -% s43), lo, hi)))
    vst(t, off + 37usize * st, (vclp((s1 -% s8), lo, hi)))
    vst(t, off + 38usize * st, (vclp((s23 -% s3), lo, hi)))
    vst(t, off + 39usize * st, (vclp((s22 -% s16), lo, hi)))
    vst(t, off + 40usize * st, (vclp((s4 -% s48), lo, hi)))
    vst(t, off + 41usize * st, (vclp((s27 -% s19), lo, hi)))
    vst(t, off + 42usize * st, (vclp((s11 -% s17), lo, hi)))
    vst(t, off + 43usize * st, (vclp((s0 -% s13), lo, hi)))
    vst(t, off + 44usize * st, (vclp((s47 -% s9), lo, hi)))
    vst(t, off + 45usize * st, (vclp((s46 -% s39), lo, hi)))
    vst(t, off + 46usize * st, (vclp((s45 -% s38), lo, hi)))
    vst(t, off + 47usize * st, (vclp((s44 -% s37), lo, hi)))
    vst(t, off + 48usize * st, (vclp((s49 -% s12), lo, hi)))
    vst(t, off + 49usize * st, (vclp((s50 -% s29), lo, hi)))
    vst(t, off + 50usize * st, (vclp((s51 -% s30), lo, hi)))
    vst(t, off + 51usize * st, (vclp((s64 -% s31), lo, hi)))
    vst(t, off + 52usize * st, (vclp((s21 -% s7), lo, hi)))
    vst(t, off + 53usize * st, (vclp((s28 -% s2), lo, hi)))
    vst(t, off + 54usize * st, (vclp((s25 -% s14), lo, hi)))
    vst(t, off + 55usize * st, (vclp((s63 -% s6), lo, hi)))
    vst(t, off + 56usize * st, (vclp((s62 -% s20), lo, hi)))
    vst(t, off + 57usize * st, (vclp((s61 -% s26), lo, hi)))
    vst(t, off + 58usize * st, (vclp((s60 -% s18), lo, hi)))
    vst(t, off + 59usize * st, (vclp((s59 -% s56), lo, hi)))
    vst(t, off + 60usize * st, (vclp((s58 -% s35), lo, hi)))
    vst(t, off + 61usize * st, (vclp((s57 -% s34), lo, hi)))
    vst(t, off + 62usize * st, (vclp((s52 -% s33), lo, hi)))
    vst(t, off + 63usize * st, (vclp((s15 -% s32), lo, hi)))
    }
}

fn vidct64_k8(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp101 = vsp(101i32)
    let kp4095 = vsp(4095i32)
    let kp700 = vsp(700i32)
    let kp4036 = vsp(4036i32)
    let kp501 = vsp(501i32)
    let kp4065 = vsp(4065i32)
    let kp301 = vsp(301i32)
    let kp4085 = vsp(4085i32)
    let kp201 = vsp(201i32)
    let kp4091 = vsp(4091i32)
    let kp601 = vsp(601i32)
    let kp4052 = vsp(4052i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp2598 = vsp(2598i32)
    let kp3166 = vsp(3166i32)
    let kp1931 = vsp(1931i32)
    let kp3612 = vsp(3612i32)
    let kp1189 = vsp(1189i32)
    let kp3920 = vsp(3920i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp2276 = vsp(2276i32)
    let kp3406 = vsp(3406i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 4usize * st)
    var s2 = vld(t, off + 2usize * st)
    var s3 = vld(t, off + 6usize * st)
    var s4 = vld(t, off + 1usize * st)
    var s5 = vld(t, off + 5usize * st)
    var s6 = vld(t, off + 3usize * st)
    var s7 = vld(t, off + 7usize * st)
    var s8 = ((kp2048) +% (s4 *% kp101)) >> 12u32
    s4 = ((kp2048) +% (s4 *% kp4095)) >> 12u32
    var s9 = ((kp2048) -% (s7 *% kp700)) >> 12u32
    s7 = ((kp2048) +% (s7 *% kp4036)) >> 12u32
    var s10 = ((kp2048) +% (s5 *% kp501)) >> 12u32
    s5 = ((kp2048) +% (s5 *% kp4065)) >> 12u32
    var s11 = ((kp2048) -% (s6 *% kp301)) >> 12u32
    s6 = ((kp2048) +% (s6 *% kp4085)) >> 12u32
    var s12 = ((kp2048) +% (s2 *% kp201)) >> 12u32
    s2 = ((kp2048) +% (s2 *% kp4091)) >> 12u32
    var s13 = ((kp2048) -% (s3 *% kp601)) >> 12u32
    s3 = ((kp2048) +% (s3 *% kp4052)) >> 12u32
    var s14 = vclp(s8, lo, hi)
    s8 = vclp(s8, lo, hi)
    var s15 = vclp(s9, lo, hi)
    s9 = vclp(s9, lo, hi)
    var s16 = vclp(s10, lo, hi)
    s10 = vclp(s10, lo, hi)
    var s17 = vclp(s11, lo, hi)
    s11 = vclp(s11, lo, hi)
    var s18 = vclp(s6, lo, hi)
    s6 = vclp(s6, lo, hi)
    var s19 = vclp(s5, lo, hi)
    s5 = vclp(s5, lo, hi)
    var s20 = vclp(s7, lo, hi)
    s7 = vclp(s7, lo, hi)
    var s21 = vclp(s4, lo, hi)
    s4 = vclp(s4, lo, hi)
    var s22 = ((kp2048) +% (s1 *% kp401)) >> 12u32
    s1 = ((kp2048) +% (s1 *% kp4076)) >> 12u32
    var s23 = vclp(s12, lo, hi)
    s12 = vclp(s12, lo, hi)
    var s24 = vclp(s13, lo, hi)
    s13 = vclp(s13, lo, hi)
    var s25 = vclp(s3, lo, hi)
    s3 = vclp(s3, lo, hi)
    var s26 = vclp(s2, lo, hi)
    s2 = vclp(s2, lo, hi)
    var s27 = (((kp2048) +% (s4 *% kp401)) -% (s8 *% kp4076)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp4076)) +% (s8 *% kp401)) >> 12u32
    s8 = (((kp2048) -% (s7 *% kp2598)) -% (s9 *% kp3166)) >> 12u32
    s7 = (((kp2048) +% (s7 *% kp3166)) -% (s9 *% kp2598)) >> 12u32
    s9 = (((kp2048) +% (s5 *% kp1931)) -% (s10 *% kp3612)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp3612)) +% (s10 *% kp1931)) >> 12u32
    s10 = (((kp2048) -% (s6 *% kp1189)) -% (s11 *% kp3920)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp3920)) -% (s11 *% kp1189)) >> 12u32
    s11 = vclp(s22, lo, hi)
    s22 = vclp(s22, lo, hi)
    var s28 = vclp(s1, lo, hi)
    s1 = vclp(s1, lo, hi)
    var s29 = (((kp2048) +% (s2 *% kp799)) -% (s12 *% kp4017)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp4017)) +% (s12 *% kp799)) >> 12u32
    s12 = (((kp2048) -% (s3 *% kp2276)) -% (s13 *% kp3406)) >> 12u32
    s3 = (((kp2048) +% (s3 *% kp3406)) -% (s13 *% kp2276)) >> 12u32
    s13 = vclp(s14, lo, hi)
    s14 = vclp(s14, lo, hi)
    var s30 = vclp(s27, lo, hi)
    s27 = vclp(s27, lo, hi)
    var s31 = vclp(s15, lo, hi)
    s15 = vclp(s15, lo, hi)
    var s32 = vclp(s8, lo, hi)
    s8 = vclp(s8, lo, hi)
    var s33 = vclp(s16, lo, hi)
    s16 = vclp(s16, lo, hi)
    var s34 = vclp(s9, lo, hi)
    s9 = vclp(s9, lo, hi)
    var s35 = vclp(s17, lo, hi)
    s17 = vclp(s17, lo, hi)
    var s36 = vclp(s10, lo, hi)
    s10 = vclp(s10, lo, hi)
    var s37 = vclp(s18, lo, hi)
    s18 = vclp(s18, lo, hi)
    var s38 = vclp(s6, lo, hi)
    s6 = vclp(s6, lo, hi)
    var s39 = vclp(s19, lo, hi)
    s19 = vclp(s19, lo, hi)
    var s40 = vclp(s5, lo, hi)
    s5 = vclp(s5, lo, hi)
    var s41 = vclp(s20, lo, hi)
    s20 = vclp(s20, lo, hi)
    var s42 = vclp(s7, lo, hi)
    s7 = vclp(s7, lo, hi)
    var s43 = vclp(s21, lo, hi)
    s21 = vclp(s21, lo, hi)
    var s44 = vclp(s4, lo, hi)
    s4 = vclp(s4, lo, hi)
    var s45 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    s0 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    var s46 = (((kp2048) +% (s1 *% kp1567)) -% (s22 *% kp3784)) >> 12u32
    s1 = (((kp2048) +% (s1 *% kp3784)) +% (s22 *% kp1567)) >> 12u32
    s22 = vclp(s23, lo, hi)
    s23 = vclp(s23, lo, hi)
    var s47 = vclp(s29, lo, hi)
    s29 = vclp(s29, lo, hi)
    var s48 = vclp(s24, lo, hi)
    s24 = vclp(s24, lo, hi)
    var s49 = vclp(s12, lo, hi)
    s12 = vclp(s12, lo, hi)
    var s50 = vclp(s25, lo, hi)
    s25 = vclp(s25, lo, hi)
    var s51 = vclp(s3, lo, hi)
    s3 = vclp(s3, lo, hi)
    var s52 = vclp(s26, lo, hi)
    s26 = vclp(s26, lo, hi)
    var s53 = vclp(s2, lo, hi)
    s2 = vclp(s2, lo, hi)
    var s54 = (((kp2048) +% (s4 *% kp799)) -% (s27 *% kp4017)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp4017)) +% (s27 *% kp799)) >> 12u32
    s27 = (((kp2048) +% (s21 *% kp799)) -% (s14 *% kp4017)) >> 12u32
    s14 = (((kp2048) +% (s21 *% kp4017)) +% (s14 *% kp799)) >> 12u32
    s21 = (((kp2048) -% (s20 *% kp4017)) -% (s15 *% kp799)) >> 12u32
    s15 = (((kp2048) +% (s20 *% kp799)) -% (s15 *% kp4017)) >> 12u32
    s20 = (((kp2048) -% (s7 *% kp4017)) -% (s8 *% kp799)) >> 12u32
    s7 = (((kp2048) +% (s7 *% kp799)) -% (s8 *% kp4017)) >> 12u32
    s8 = (((kp2048) +% (s5 *% kp3406)) -% (s9 *% kp2276)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp2276)) +% (s9 *% kp3406)) >> 12u32
    s9 = (((kp2048) +% (s19 *% kp3406)) -% (s16 *% kp2276)) >> 12u32
    s16 = (((kp2048) +% (s19 *% kp2276)) +% (s16 *% kp3406)) >> 12u32
    s19 = (((kp2048) -% (s18 *% kp2276)) -% (s17 *% kp3406)) >> 12u32
    s17 = (((kp2048) +% (s18 *% kp3406)) -% (s17 *% kp2276)) >> 12u32
    s18 = (((kp2048) -% (s6 *% kp2276)) -% (s10 *% kp3406)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp3406)) -% (s10 *% kp2276)) >> 12u32
    s10 = vclp(s0, lo, hi)
    s0 = vclp(s0, lo, hi)
    var s55 = vclp(s45, lo, hi)
    s45 = vclp(s45, lo, hi)
    var s56 = vclp(s11, lo, hi)
    s11 = vclp(s11, lo, hi)
    var s57 = vclp(s46, lo, hi)
    s46 = vclp(s46, lo, hi)
    var s58 = vclp(s28, lo, hi)
    s28 = vclp(s28, lo, hi)
    var s59 = vclp(s1, lo, hi)
    s1 = vclp(s1, lo, hi)
    var s60 = (((kp2048) +% (s2 *% kp1567)) -% (s29 *% kp3784)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3784)) +% (s29 *% kp1567)) >> 12u32
    s29 = (((kp2048) +% (s26 *% kp1567)) -% (s23 *% kp3784)) >> 12u32
    s23 = (((kp2048) +% (s26 *% kp3784)) +% (s23 *% kp1567)) >> 12u32
    s26 = (((kp2048) -% (s25 *% kp3784)) -% (s24 *% kp1567)) >> 12u32
    s24 = (((kp2048) +% (s25 *% kp1567)) -% (s24 *% kp3784)) >> 12u32
    s25 = (((kp2048) -% (s3 *% kp3784)) -% (s12 *% kp1567)) >> 12u32
    s3 = (((kp2048) +% (s3 *% kp1567)) -% (s12 *% kp3784)) >> 12u32
    s12 = vclp((s13 +% s31), lo, hi)
    s13 = vclp((s13 -% s31), lo, hi)
    s31 = vclp((s30 +% s32), lo, hi)
    s30 = vclp((s30 -% s32), lo, hi)
    s32 = vclp((s54 +% s20), lo, hi)
    s20 = vclp((s54 -% s20), lo, hi)
    s54 = vclp((s27 +% s21), lo, hi)
    s21 = vclp((s27 -% s21), lo, hi)
    s27 = vclp((s35 +% s33), lo, hi)
    s33 = vclp((s35 -% s33), lo, hi)
    s35 = vclp((s36 +% s34), lo, hi)
    s34 = vclp((s36 -% s34), lo, hi)
    s36 = vclp((s18 +% s8), lo, hi)
    s8 = vclp((s18 -% s8), lo, hi)
    s18 = vclp((s19 +% s9), lo, hi)
    s9 = vclp((s19 -% s9), lo, hi)
    s19 = vclp((s37 +% s39), lo, hi)
    s37 = vclp((s37 -% s39), lo, hi)
    s39 = vclp((s38 +% s40), lo, hi)
    s38 = vclp((s38 -% s40), lo, hi)
    s40 = vclp((s6 +% s5), lo, hi)
    s5 = vclp((s6 -% s5), lo, hi)
    s6 = vclp((s17 +% s16), lo, hi)
    s16 = vclp((s17 -% s16), lo, hi)
    s17 = vclp((s43 +% s41), lo, hi)
    s41 = vclp((s43 -% s41), lo, hi)
    s43 = vclp((s44 +% s42), lo, hi)
    s42 = vclp((s44 -% s42), lo, hi)
    s44 = vclp((s4 +% s7), lo, hi)
    s4 = vclp((s4 -% s7), lo, hi)
    s7 = vclp((s14 +% s15), lo, hi)
    s14 = vclp((s14 -% s15), lo, hi)
    s15 = vclp(s10, lo, hi)
    s10 = vclp(s10, lo, hi)
    var s61 = vclp(s55, lo, hi)
    s55 = vclp(s55, lo, hi)
    var s62 = vclp(s45, lo, hi)
    s45 = vclp(s45, lo, hi)
    var s63 = vclp(s0, lo, hi)
    s0 = vclp(s0, lo, hi)
    var s64 = (((kp2048) +% (s1 *% kp2896)) -% (s46 *% kp2896)) >> 12u32
    s1 = (((kp2048) +% (s1 *% kp2896)) +% (s46 *% kp2896)) >> 12u32
    s46 = (((kp2048) +% (s28 *% kp2896)) -% (s11 *% kp2896)) >> 12u32
    s11 = (((kp2048) +% (s28 *% kp2896)) +% (s11 *% kp2896)) >> 12u32
    s28 = vclp((s22 +% s48), lo, hi)
    s22 = vclp((s22 -% s48), lo, hi)
    s48 = vclp((s47 +% s49), lo, hi)
    s47 = vclp((s47 -% s49), lo, hi)
    s49 = vclp((s60 +% s25), lo, hi)
    s25 = vclp((s60 -% s25), lo, hi)
    s60 = vclp((s29 +% s26), lo, hi)
    s26 = vclp((s29 -% s26), lo, hi)
    s29 = vclp((s52 +% s50), lo, hi)
    s50 = vclp((s52 -% s50), lo, hi)
    s52 = vclp((s53 +% s51), lo, hi)
    s51 = vclp((s53 -% s51), lo, hi)
    s53 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = vclp((s23 +% s24), lo, hi)
    s23 = vclp((s23 -% s24), lo, hi)
    s24 = (((kp2048) +% (s14 *% kp1567)) -% (s21 *% kp3784)) >> 12u32
    s14 = (((kp2048) +% (s14 *% kp3784)) +% (s21 *% kp1567)) >> 12u32
    s21 = (((kp2048) +% (s4 *% kp1567)) -% (s20 *% kp3784)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp3784)) +% (s20 *% kp1567)) >> 12u32
    s20 = (((kp2048) +% (s42 *% kp1567)) -% (s30 *% kp3784)) >> 12u32
    s30 = (((kp2048) +% (s42 *% kp3784)) +% (s30 *% kp1567)) >> 12u32
    s42 = (((kp2048) +% (s41 *% kp1567)) -% (s13 *% kp3784)) >> 12u32
    s13 = (((kp2048) +% (s41 *% kp3784)) +% (s13 *% kp1567)) >> 12u32
    s41 = (((kp2048) -% (s37 *% kp3784)) -% (s33 *% kp1567)) >> 12u32
    s33 = (((kp2048) +% (s37 *% kp1567)) -% (s33 *% kp3784)) >> 12u32
    s37 = (((kp2048) -% (s38 *% kp3784)) -% (s34 *% kp1567)) >> 12u32
    s34 = (((kp2048) +% (s38 *% kp1567)) -% (s34 *% kp3784)) >> 12u32
    s38 = (((kp2048) -% (s5 *% kp3784)) -% (s8 *% kp1567)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp1567)) -% (s8 *% kp3784)) >> 12u32
    s8 = (((kp2048) -% (s16 *% kp3784)) -% (s9 *% kp1567)) >> 12u32
    s9 = (((kp2048) +% (s16 *% kp1567)) -% (s9 *% kp3784)) >> 12u32
    s16 = vclp((s15 +% s58), lo, hi)
    s15 = vclp((s15 -% s58), lo, hi)
    s58 = vclp((s61 +% s59), lo, hi)
    s59 = vclp((s61 -% s59), lo, hi)
    s61 = vclp((s62 +% s1), lo, hi)
    s1 = vclp((s62 -% s1), lo, hi)
    s62 = vclp((s63 +% s11), lo, hi)
    s11 = vclp((s63 -% s11), lo, hi)
    s63 = vclp((s0 +% s46), lo, hi)
    s0 = vclp((s0 -% s46), lo, hi)
    s46 = vclp((s45 +% s64), lo, hi)
    s45 = vclp((s45 -% s64), lo, hi)
    s64 = vclp((s55 +% s57), lo, hi)
    s55 = vclp((s55 -% s57), lo, hi)
    s57 = vclp((s10 +% s56), lo, hi)
    s10 = vclp((s10 -% s56), lo, hi)
    s56 = (((kp2048) +% (s23 *% kp2896)) -% (s26 *% kp2896)) >> 12u32
    s23 = (((kp2048) +% (s23 *% kp2896)) +% (s26 *% kp2896)) >> 12u32
    s26 = (((kp2048) +% (s2 *% kp2896)) -% (s25 *% kp2896)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp2896)) +% (s25 *% kp2896)) >> 12u32
    s25 = (((kp2048) +% (s51 *% kp2896)) -% (s47 *% kp2896)) >> 12u32
    s47 = (((kp2048) +% (s51 *% kp2896)) +% (s47 *% kp2896)) >> 12u32
    s51 = (((kp2048) +% (s50 *% kp2896)) -% (s22 *% kp2896)) >> 12u32
    s22 = (((kp2048) +% (s50 *% kp2896)) +% (s22 *% kp2896)) >> 12u32
    s50 = vclp((s12 +% s27), lo, hi)
    s12 = vclp((s12 -% s27), lo, hi)
    s27 = vclp((s17 +% s19), lo, hi)
    s17 = vclp((s17 -% s19), lo, hi)
    s19 = vclp((s31 +% s35), lo, hi)
    s31 = vclp((s31 -% s35), lo, hi)
    s35 = vclp((s43 +% s39), lo, hi)
    s39 = vclp((s43 -% s39), lo, hi)
    s43 = vclp((s32 +% s36), lo, hi)
    s32 = vclp((s32 -% s36), lo, hi)
    s36 = vclp((s44 +% s40), lo, hi)
    s40 = vclp((s44 -% s40), lo, hi)
    s44 = vclp((s54 +% s18), lo, hi)
    s18 = vclp((s54 -% s18), lo, hi)
    s54 = vclp((s7 +% s6), lo, hi)
    s6 = vclp((s7 -% s6), lo, hi)
    s7 = vclp((s24 +% s8), lo, hi)
    s8 = vclp((s24 -% s8), lo, hi)
    s24 = vclp((s14 +% s9), lo, hi)
    s9 = vclp((s14 -% s9), lo, hi)
    s14 = vclp((s21 +% s38), lo, hi)
    s21 = vclp((s21 -% s38), lo, hi)
    s38 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = vclp((s20 +% s37), lo, hi)
    s20 = vclp((s20 -% s37), lo, hi)
    s37 = vclp((s30 +% s34), lo, hi)
    s30 = vclp((s30 -% s34), lo, hi)
    s34 = vclp((s42 +% s41), lo, hi)
    s41 = vclp((s42 -% s41), lo, hi)
    s42 = vclp((s13 +% s33), lo, hi)
    s13 = vclp((s13 -% s33), lo, hi)
    s33 = vclp((s16 +% s29), lo, hi)
    s16 = vclp((s16 -% s29), lo, hi)
    s29 = vclp((s58 +% s52), lo, hi)
    s52 = vclp((s58 -% s52), lo, hi)
    s58 = vclp((s61 +% s53), lo, hi)
    s53 = vclp((s61 -% s53), lo, hi)
    s61 = vclp((s62 +% s3), lo, hi)
    s3 = vclp((s62 -% s3), lo, hi)
    s62 = vclp((s63 +% s23), lo, hi)
    s23 = vclp((s63 -% s23), lo, hi)
    s63 = vclp((s46 +% s2), lo, hi)
    s2 = vclp((s46 -% s2), lo, hi)
    s46 = vclp((s64 +% s47), lo, hi)
    s47 = vclp((s64 -% s47), lo, hi)
    s64 = vclp((s57 +% s22), lo, hi)
    s22 = vclp((s57 -% s22), lo, hi)
    s57 = vclp((s10 +% s51), lo, hi)
    s10 = vclp((s10 -% s51), lo, hi)
    s51 = vclp((s55 +% s25), lo, hi)
    s25 = vclp((s55 -% s25), lo, hi)
    s55 = vclp((s45 +% s26), lo, hi)
    s26 = vclp((s45 -% s26), lo, hi)
    s45 = vclp((s0 +% s56), lo, hi)
    s0 = vclp((s0 -% s56), lo, hi)
    s56 = vclp((s11 +% s60), lo, hi)
    s11 = vclp((s11 -% s60), lo, hi)
    s60 = vclp((s1 +% s49), lo, hi)
    s1 = vclp((s1 -% s49), lo, hi)
    s49 = vclp((s59 +% s48), lo, hi)
    s48 = vclp((s59 -% s48), lo, hi)
    s59 = vclp((s15 +% s28), lo, hi)
    s15 = vclp((s15 -% s28), lo, hi)
    s28 = (((kp2048) +% (s13 *% kp2896)) -% (s41 *% kp2896)) >> 12u32
    s13 = (((kp2048) +% (s13 *% kp2896)) +% (s41 *% kp2896)) >> 12u32
    s41 = (((kp2048) +% (s30 *% kp2896)) -% (s20 *% kp2896)) >> 12u32
    s20 = (((kp2048) +% (s30 *% kp2896)) +% (s20 *% kp2896)) >> 12u32
    s30 = (((kp2048) +% (s4 *% kp2896)) -% (s21 *% kp2896)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp2896)) +% (s21 *% kp2896)) >> 12u32
    s21 = (((kp2048) +% (s9 *% kp2896)) -% (s8 *% kp2896)) >> 12u32
    s8 = (((kp2048) +% (s9 *% kp2896)) +% (s8 *% kp2896)) >> 12u32
    s9 = (((kp2048) +% (s6 *% kp2896)) -% (s18 *% kp2896)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp2896)) +% (s18 *% kp2896)) >> 12u32
    s18 = (((kp2048) +% (s40 *% kp2896)) -% (s32 *% kp2896)) >> 12u32
    s32 = (((kp2048) +% (s40 *% kp2896)) +% (s32 *% kp2896)) >> 12u32
    s40 = (((kp2048) +% (s39 *% kp2896)) -% (s31 *% kp2896)) >> 12u32
    s31 = (((kp2048) +% (s39 *% kp2896)) +% (s31 *% kp2896)) >> 12u32
    s39 = (((kp2048) +% (s17 *% kp2896)) -% (s12 *% kp2896)) >> 12u32
    s12 = (((kp2048) +% (s17 *% kp2896)) +% (s12 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s33 +% s27), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s29 +% s35), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s58 +% s36), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s61 +% s54), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s62 +% s24), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s63 +% s38), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s46 +% s37), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s64 +% s42), lo, hi)))
    vst(t, off + 8usize * st, (vclp((s57 +% s13), lo, hi)))
    vst(t, off + 9usize * st, (vclp((s51 +% s20), lo, hi)))
    vst(t, off + 10usize * st, (vclp((s55 +% s4), lo, hi)))
    vst(t, off + 11usize * st, (vclp((s45 +% s8), lo, hi)))
    vst(t, off + 12usize * st, (vclp((s56 +% s6), lo, hi)))
    vst(t, off + 13usize * st, (vclp((s60 +% s32), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s49 +% s31), lo, hi)))
    vst(t, off + 15usize * st, (vclp((s59 +% s12), lo, hi)))
    vst(t, off + 16usize * st, (vclp((s15 +% s39), lo, hi)))
    vst(t, off + 17usize * st, (vclp((s48 +% s40), lo, hi)))
    vst(t, off + 18usize * st, (vclp((s1 +% s18), lo, hi)))
    vst(t, off + 19usize * st, (vclp((s11 +% s9), lo, hi)))
    vst(t, off + 20usize * st, (vclp((s0 +% s21), lo, hi)))
    vst(t, off + 21usize * st, (vclp((s26 +% s30), lo, hi)))
    vst(t, off + 22usize * st, (vclp((s25 +% s41), lo, hi)))
    vst(t, off + 23usize * st, (vclp((s10 +% s28), lo, hi)))
    vst(t, off + 24usize * st, (vclp((s22 +% s34), lo, hi)))
    vst(t, off + 25usize * st, (vclp((s47 +% s5), lo, hi)))
    vst(t, off + 26usize * st, (vclp((s2 +% s14), lo, hi)))
    vst(t, off + 27usize * st, (vclp((s23 +% s7), lo, hi)))
    vst(t, off + 28usize * st, (vclp((s3 +% s44), lo, hi)))
    vst(t, off + 29usize * st, (vclp((s53 +% s43), lo, hi)))
    vst(t, off + 30usize * st, (vclp((s52 +% s19), lo, hi)))
    vst(t, off + 31usize * st, (vclp((s16 +% s50), lo, hi)))
    vst(t, off + 32usize * st, (vclp((s16 -% s50), lo, hi)))
    vst(t, off + 33usize * st, (vclp((s52 -% s19), lo, hi)))
    vst(t, off + 34usize * st, (vclp((s53 -% s43), lo, hi)))
    vst(t, off + 35usize * st, (vclp((s3 -% s44), lo, hi)))
    vst(t, off + 36usize * st, (vclp((s23 -% s7), lo, hi)))
    vst(t, off + 37usize * st, (vclp((s2 -% s14), lo, hi)))
    vst(t, off + 38usize * st, (vclp((s47 -% s5), lo, hi)))
    vst(t, off + 39usize * st, (vclp((s22 -% s34), lo, hi)))
    vst(t, off + 40usize * st, (vclp((s10 -% s28), lo, hi)))
    vst(t, off + 41usize * st, (vclp((s25 -% s41), lo, hi)))
    vst(t, off + 42usize * st, (vclp((s26 -% s30), lo, hi)))
    vst(t, off + 43usize * st, (vclp((s0 -% s21), lo, hi)))
    vst(t, off + 44usize * st, (vclp((s11 -% s9), lo, hi)))
    vst(t, off + 45usize * st, (vclp((s1 -% s18), lo, hi)))
    vst(t, off + 46usize * st, (vclp((s48 -% s40), lo, hi)))
    vst(t, off + 47usize * st, (vclp((s15 -% s39), lo, hi)))
    vst(t, off + 48usize * st, (vclp((s59 -% s12), lo, hi)))
    vst(t, off + 49usize * st, (vclp((s49 -% s31), lo, hi)))
    vst(t, off + 50usize * st, (vclp((s60 -% s32), lo, hi)))
    vst(t, off + 51usize * st, (vclp((s56 -% s6), lo, hi)))
    vst(t, off + 52usize * st, (vclp((s45 -% s8), lo, hi)))
    vst(t, off + 53usize * st, (vclp((s55 -% s4), lo, hi)))
    vst(t, off + 54usize * st, (vclp((s51 -% s20), lo, hi)))
    vst(t, off + 55usize * st, (vclp((s57 -% s13), lo, hi)))
    vst(t, off + 56usize * st, (vclp((s64 -% s42), lo, hi)))
    vst(t, off + 57usize * st, (vclp((s46 -% s37), lo, hi)))
    vst(t, off + 58usize * st, (vclp((s63 -% s38), lo, hi)))
    vst(t, off + 59usize * st, (vclp((s62 -% s24), lo, hi)))
    vst(t, off + 60usize * st, (vclp((s61 -% s54), lo, hi)))
    vst(t, off + 61usize * st, (vclp((s58 -% s36), lo, hi)))
    vst(t, off + 62usize * st, (vclp((s29 -% s35), lo, hi)))
    vst(t, off + 63usize * st, (vclp((s33 -% s27), lo, hi)))
    }
}

fn vidct64_k16(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi = vsp(i32((1i64 << (r - 1u32)) - 1i64))
    let lo = vsp(i32(0i64 - (1i64 << (r - 1u32))))
    let kp2048 = vsp(2048i32)
    let kp101 = vsp(101i32)
    let kp4095 = vsp(4095i32)
    let kp1474 = vsp(1474i32)
    let kp3822 = vsp(3822i32)
    let kp897 = vsp(897i32)
    let kp3996 = vsp(3996i32)
    let kp700 = vsp(700i32)
    let kp4036 = vsp(4036i32)
    let kp501 = vsp(501i32)
    let kp4065 = vsp(4065i32)
    let kp1092 = vsp(1092i32)
    let kp3948 = vsp(3948i32)
    let kp1285 = vsp(1285i32)
    let kp3889 = vsp(3889i32)
    let kp301 = vsp(301i32)
    let kp4085 = vsp(4085i32)
    let kp201 = vsp(201i32)
    let kp4091 = vsp(4091i32)
    let kp1380 = vsp(1380i32)
    let kp3857 = vsp(3857i32)
    let kp995 = vsp(995i32)
    let kp3973 = vsp(3973i32)
    let kp601 = vsp(601i32)
    let kp4052 = vsp(4052i32)
    let kp401 = vsp(401i32)
    let kp4076 = vsp(4076i32)
    let kp1189 = vsp(1189i32)
    let kp3920 = vsp(3920i32)
    let kp3166 = vsp(3166i32)
    let kp2598 = vsp(2598i32)
    let kp1931 = vsp(1931i32)
    let kp3612 = vsp(3612i32)
    let kp799 = vsp(799i32)
    let kp4017 = vsp(4017i32)
    let kp3406 = vsp(3406i32)
    let kp2276 = vsp(2276i32)
    let kp2896 = vsp(2896i32)
    let kp1567 = vsp(1567i32)
    let kp3784 = vsp(3784i32)
    var s0 = vld(t, off + 0usize * st)
    var s1 = vld(t, off + 8usize * st)
    var s2 = vld(t, off + 4usize * st)
    var s3 = vld(t, off + 12usize * st)
    var s4 = vld(t, off + 2usize * st)
    var s5 = vld(t, off + 10usize * st)
    var s6 = vld(t, off + 6usize * st)
    var s7 = vld(t, off + 14usize * st)
    var s8 = vld(t, off + 1usize * st)
    var s9 = vld(t, off + 9usize * st)
    var s10 = vld(t, off + 5usize * st)
    var s11 = vld(t, off + 13usize * st)
    var s12 = vld(t, off + 3usize * st)
    var s13 = vld(t, off + 11usize * st)
    var s14 = vld(t, off + 7usize * st)
    var s15 = vld(t, off + 15usize * st)
    var s16 = ((kp2048) +% (s8 *% kp101)) >> 12u32
    s8 = ((kp2048) +% (s8 *% kp4095)) >> 12u32
    var s17 = ((kp2048) -% (s15 *% kp1474)) >> 12u32
    s15 = ((kp2048) +% (s15 *% kp3822)) >> 12u32
    var s18 = ((kp2048) +% (s9 *% kp897)) >> 12u32
    s9 = ((kp2048) +% (s9 *% kp3996)) >> 12u32
    var s19 = ((kp2048) -% (s14 *% kp700)) >> 12u32
    s14 = ((kp2048) +% (s14 *% kp4036)) >> 12u32
    var s20 = ((kp2048) +% (s10 *% kp501)) >> 12u32
    s10 = ((kp2048) +% (s10 *% kp4065)) >> 12u32
    var s21 = ((kp2048) -% (s13 *% kp1092)) >> 12u32
    s13 = ((kp2048) +% (s13 *% kp3948)) >> 12u32
    var s22 = ((kp2048) +% (s11 *% kp1285)) >> 12u32
    s11 = ((kp2048) +% (s11 *% kp3889)) >> 12u32
    var s23 = ((kp2048) -% (s12 *% kp301)) >> 12u32
    s12 = ((kp2048) +% (s12 *% kp4085)) >> 12u32
    var s24 = ((kp2048) +% (s4 *% kp201)) >> 12u32
    s4 = ((kp2048) +% (s4 *% kp4091)) >> 12u32
    var s25 = ((kp2048) -% (s7 *% kp1380)) >> 12u32
    s7 = ((kp2048) +% (s7 *% kp3857)) >> 12u32
    var s26 = ((kp2048) +% (s5 *% kp995)) >> 12u32
    s5 = ((kp2048) +% (s5 *% kp3973)) >> 12u32
    var s27 = ((kp2048) -% (s6 *% kp601)) >> 12u32
    s6 = ((kp2048) +% (s6 *% kp4052)) >> 12u32
    var s28 = vclp(s16, lo, hi)
    s16 = vclp(s16, lo, hi)
    var s29 = vclp(s17, lo, hi)
    s17 = vclp(s17, lo, hi)
    var s30 = vclp(s18, lo, hi)
    s18 = vclp(s18, lo, hi)
    var s31 = vclp(s19, lo, hi)
    s19 = vclp(s19, lo, hi)
    var s32 = vclp(s20, lo, hi)
    s20 = vclp(s20, lo, hi)
    var s33 = vclp(s21, lo, hi)
    s21 = vclp(s21, lo, hi)
    var s34 = vclp(s22, lo, hi)
    s22 = vclp(s22, lo, hi)
    var s35 = vclp(s23, lo, hi)
    s23 = vclp(s23, lo, hi)
    var s36 = vclp(s12, lo, hi)
    s12 = vclp(s12, lo, hi)
    var s37 = vclp(s11, lo, hi)
    s11 = vclp(s11, lo, hi)
    var s38 = vclp(s13, lo, hi)
    s13 = vclp(s13, lo, hi)
    var s39 = vclp(s10, lo, hi)
    s10 = vclp(s10, lo, hi)
    var s40 = vclp(s14, lo, hi)
    s14 = vclp(s14, lo, hi)
    var s41 = vclp(s9, lo, hi)
    s9 = vclp(s9, lo, hi)
    var s42 = vclp(s15, lo, hi)
    s15 = vclp(s15, lo, hi)
    var s43 = vclp(s8, lo, hi)
    s8 = vclp(s8, lo, hi)
    var s44 = ((kp2048) +% (s2 *% kp401)) >> 12u32
    s2 = ((kp2048) +% (s2 *% kp4076)) >> 12u32
    var s45 = ((kp2048) -% (s3 *% kp1189)) >> 12u32
    s3 = ((kp2048) +% (s3 *% kp3920)) >> 12u32
    var s46 = vclp(s24, lo, hi)
    s24 = vclp(s24, lo, hi)
    var s47 = vclp(s25, lo, hi)
    s25 = vclp(s25, lo, hi)
    var s48 = vclp(s26, lo, hi)
    s26 = vclp(s26, lo, hi)
    var s49 = vclp(s27, lo, hi)
    s27 = vclp(s27, lo, hi)
    var s50 = vclp(s6, lo, hi)
    s6 = vclp(s6, lo, hi)
    var s51 = vclp(s5, lo, hi)
    s5 = vclp(s5, lo, hi)
    var s52 = vclp(s7, lo, hi)
    s7 = vclp(s7, lo, hi)
    var s53 = vclp(s4, lo, hi)
    s4 = vclp(s4, lo, hi)
    var s54 = (((kp2048) +% (s8 *% kp401)) -% (s16 *% kp4076)) >> 12u32
    s8 = (((kp2048) +% (s8 *% kp4076)) +% (s16 *% kp401)) >> 12u32
    s16 = (((kp2048) -% (s15 *% kp4076)) -% (s17 *% kp401)) >> 12u32
    s15 = (((kp2048) +% (s15 *% kp401)) -% (s17 *% kp4076)) >> 12u32
    s17 = (((kp2048) +% (s9 *% kp3166)) -% (s18 *% kp2598)) >> 12u32
    s9 = (((kp2048) +% (s9 *% kp2598)) +% (s18 *% kp3166)) >> 12u32
    s18 = (((kp2048) -% (s14 *% kp2598)) -% (s19 *% kp3166)) >> 12u32
    s14 = (((kp2048) +% (s14 *% kp3166)) -% (s19 *% kp2598)) >> 12u32
    s19 = (((kp2048) +% (s10 *% kp1931)) -% (s20 *% kp3612)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp3612)) +% (s20 *% kp1931)) >> 12u32
    s20 = (((kp2048) -% (s13 *% kp3612)) -% (s21 *% kp1931)) >> 12u32
    s13 = (((kp2048) +% (s13 *% kp1931)) -% (s21 *% kp3612)) >> 12u32
    s21 = (((kp2048) +% (s11 *% kp3920)) -% (s22 *% kp1189)) >> 12u32
    s11 = (((kp2048) +% (s11 *% kp1189)) +% (s22 *% kp3920)) >> 12u32
    s22 = (((kp2048) -% (s12 *% kp1189)) -% (s23 *% kp3920)) >> 12u32
    s12 = (((kp2048) +% (s12 *% kp3920)) -% (s23 *% kp1189)) >> 12u32
    s23 = ((kp2048) +% (s1 *% kp799)) >> 12u32
    s1 = ((kp2048) +% (s1 *% kp4017)) >> 12u32
    var s55 = vclp(s44, lo, hi)
    s44 = vclp(s44, lo, hi)
    var s56 = vclp(s45, lo, hi)
    s45 = vclp(s45, lo, hi)
    var s57 = vclp(s3, lo, hi)
    s3 = vclp(s3, lo, hi)
    var s58 = vclp(s2, lo, hi)
    s2 = vclp(s2, lo, hi)
    var s59 = (((kp2048) +% (s4 *% kp799)) -% (s24 *% kp4017)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp4017)) +% (s24 *% kp799)) >> 12u32
    s24 = (((kp2048) -% (s7 *% kp4017)) -% (s25 *% kp799)) >> 12u32
    s7 = (((kp2048) +% (s7 *% kp799)) -% (s25 *% kp4017)) >> 12u32
    s25 = (((kp2048) +% (s5 *% kp3406)) -% (s26 *% kp2276)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp2276)) +% (s26 *% kp3406)) >> 12u32
    s26 = (((kp2048) -% (s6 *% kp2276)) -% (s27 *% kp3406)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp3406)) -% (s27 *% kp2276)) >> 12u32
    s27 = vclp((s28 +% s29), lo, hi)
    s28 = vclp((s28 -% s29), lo, hi)
    s29 = vclp((s54 +% s16), lo, hi)
    s16 = vclp((s54 -% s16), lo, hi)
    s54 = vclp((s31 +% s30), lo, hi)
    s30 = vclp((s31 -% s30), lo, hi)
    s31 = vclp((s18 +% s17), lo, hi)
    s17 = vclp((s18 -% s17), lo, hi)
    s18 = vclp((s32 +% s33), lo, hi)
    s32 = vclp((s32 -% s33), lo, hi)
    s33 = vclp((s19 +% s20), lo, hi)
    s19 = vclp((s19 -% s20), lo, hi)
    s20 = vclp((s35 +% s34), lo, hi)
    s34 = vclp((s35 -% s34), lo, hi)
    s35 = vclp((s22 +% s21), lo, hi)
    s21 = vclp((s22 -% s21), lo, hi)
    s22 = vclp((s36 +% s37), lo, hi)
    s36 = vclp((s36 -% s37), lo, hi)
    s37 = vclp((s12 +% s11), lo, hi)
    s11 = vclp((s12 -% s11), lo, hi)
    s12 = vclp((s39 +% s38), lo, hi)
    s38 = vclp((s39 -% s38), lo, hi)
    s39 = vclp((s10 +% s13), lo, hi)
    s10 = vclp((s10 -% s13), lo, hi)
    s13 = vclp((s40 +% s41), lo, hi)
    s40 = vclp((s40 -% s41), lo, hi)
    s41 = vclp((s14 +% s9), lo, hi)
    s9 = vclp((s14 -% s9), lo, hi)
    s14 = vclp((s43 +% s42), lo, hi)
    s42 = vclp((s43 -% s42), lo, hi)
    s43 = vclp((s8 +% s15), lo, hi)
    s8 = vclp((s8 -% s15), lo, hi)
    s15 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    s0 = ((kp2048) +% (s0 *% kp2896)) >> 12u32
    var s60 = vclp(s23, lo, hi)
    s23 = vclp(s23, lo, hi)
    var s61 = vclp(s1, lo, hi)
    s1 = vclp(s1, lo, hi)
    var s62 = (((kp2048) +% (s2 *% kp1567)) -% (s44 *% kp3784)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp3784)) +% (s44 *% kp1567)) >> 12u32
    s44 = (((kp2048) -% (s3 *% kp3784)) -% (s45 *% kp1567)) >> 12u32
    s3 = (((kp2048) +% (s3 *% kp1567)) -% (s45 *% kp3784)) >> 12u32
    s45 = vclp((s46 +% s47), lo, hi)
    s46 = vclp((s46 -% s47), lo, hi)
    s47 = vclp((s59 +% s24), lo, hi)
    s24 = vclp((s59 -% s24), lo, hi)
    s59 = vclp((s49 +% s48), lo, hi)
    s48 = vclp((s49 -% s48), lo, hi)
    s49 = vclp((s26 +% s25), lo, hi)
    s25 = vclp((s26 -% s25), lo, hi)
    s26 = vclp((s50 +% s51), lo, hi)
    s50 = vclp((s50 -% s51), lo, hi)
    s51 = vclp((s6 +% s5), lo, hi)
    s5 = vclp((s6 -% s5), lo, hi)
    s6 = vclp((s53 +% s52), lo, hi)
    s52 = vclp((s53 -% s52), lo, hi)
    s53 = vclp((s4 +% s7), lo, hi)
    s4 = vclp((s4 -% s7), lo, hi)
    s7 = (((kp2048) +% (s8 *% kp799)) -% (s16 *% kp4017)) >> 12u32
    s8 = (((kp2048) +% (s8 *% kp4017)) +% (s16 *% kp799)) >> 12u32
    s16 = (((kp2048) +% (s42 *% kp799)) -% (s28 *% kp4017)) >> 12u32
    s28 = (((kp2048) +% (s42 *% kp4017)) +% (s28 *% kp799)) >> 12u32
    s42 = (((kp2048) -% (s40 *% kp4017)) -% (s30 *% kp799)) >> 12u32
    s30 = (((kp2048) +% (s40 *% kp799)) -% (s30 *% kp4017)) >> 12u32
    s40 = (((kp2048) -% (s9 *% kp4017)) -% (s17 *% kp799)) >> 12u32
    s9 = (((kp2048) +% (s9 *% kp799)) -% (s17 *% kp4017)) >> 12u32
    s17 = (((kp2048) +% (s10 *% kp3406)) -% (s19 *% kp2276)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp2276)) +% (s19 *% kp3406)) >> 12u32
    s19 = (((kp2048) +% (s38 *% kp3406)) -% (s32 *% kp2276)) >> 12u32
    s32 = (((kp2048) +% (s38 *% kp2276)) +% (s32 *% kp3406)) >> 12u32
    s38 = (((kp2048) -% (s36 *% kp2276)) -% (s34 *% kp3406)) >> 12u32
    s34 = (((kp2048) +% (s36 *% kp3406)) -% (s34 *% kp2276)) >> 12u32
    s36 = (((kp2048) -% (s11 *% kp2276)) -% (s21 *% kp3406)) >> 12u32
    s11 = (((kp2048) +% (s11 *% kp3406)) -% (s21 *% kp2276)) >> 12u32
    s21 = vclp(s0, lo, hi)
    s0 = vclp(s0, lo, hi)
    var s63 = vclp(s15, lo, hi)
    s15 = vclp(s15, lo, hi)
    var s64 = (((kp2048) +% (s1 *% kp2896)) -% (s23 *% kp2896)) >> 12u32
    s1 = (((kp2048) +% (s1 *% kp2896)) +% (s23 *% kp2896)) >> 12u32
    s23 = vclp((s55 +% s56), lo, hi)
    s55 = vclp((s55 -% s56), lo, hi)
    s56 = vclp((s62 +% s44), lo, hi)
    s44 = vclp((s62 -% s44), lo, hi)
    s62 = vclp((s58 +% s57), lo, hi)
    s57 = vclp((s58 -% s57), lo, hi)
    s58 = vclp((s2 +% s3), lo, hi)
    s2 = vclp((s2 -% s3), lo, hi)
    s3 = (((kp2048) +% (s4 *% kp1567)) -% (s24 *% kp3784)) >> 12u32
    s4 = (((kp2048) +% (s4 *% kp3784)) +% (s24 *% kp1567)) >> 12u32
    s24 = (((kp2048) +% (s52 *% kp1567)) -% (s46 *% kp3784)) >> 12u32
    s46 = (((kp2048) +% (s52 *% kp3784)) +% (s46 *% kp1567)) >> 12u32
    s52 = (((kp2048) -% (s50 *% kp3784)) -% (s48 *% kp1567)) >> 12u32
    s48 = (((kp2048) +% (s50 *% kp1567)) -% (s48 *% kp3784)) >> 12u32
    s50 = (((kp2048) -% (s5 *% kp3784)) -% (s25 *% kp1567)) >> 12u32
    s5 = (((kp2048) +% (s5 *% kp1567)) -% (s25 *% kp3784)) >> 12u32
    s25 = vclp((s27 +% s54), lo, hi)
    s27 = vclp((s27 -% s54), lo, hi)
    s54 = vclp((s29 +% s31), lo, hi)
    s29 = vclp((s29 -% s31), lo, hi)
    s31 = vclp((s7 +% s40), lo, hi)
    s7 = vclp((s7 -% s40), lo, hi)
    s40 = vclp((s16 +% s42), lo, hi)
    s16 = vclp((s16 -% s42), lo, hi)
    s42 = vclp((s20 +% s18), lo, hi)
    s18 = vclp((s20 -% s18), lo, hi)
    s20 = vclp((s35 +% s33), lo, hi)
    s33 = vclp((s35 -% s33), lo, hi)
    s35 = vclp((s36 +% s17), lo, hi)
    s17 = vclp((s36 -% s17), lo, hi)
    s36 = vclp((s38 +% s19), lo, hi)
    s19 = vclp((s38 -% s19), lo, hi)
    s38 = vclp((s22 +% s12), lo, hi)
    s12 = vclp((s22 -% s12), lo, hi)
    s22 = vclp((s37 +% s39), lo, hi)
    s37 = vclp((s37 -% s39), lo, hi)
    s39 = vclp((s11 +% s10), lo, hi)
    s10 = vclp((s11 -% s10), lo, hi)
    s11 = vclp((s34 +% s32), lo, hi)
    s32 = vclp((s34 -% s32), lo, hi)
    s34 = vclp((s14 +% s13), lo, hi)
    s13 = vclp((s14 -% s13), lo, hi)
    s14 = vclp((s43 +% s41), lo, hi)
    s41 = vclp((s43 -% s41), lo, hi)
    s43 = vclp((s8 +% s9), lo, hi)
    s8 = vclp((s8 -% s9), lo, hi)
    s9 = vclp((s28 +% s30), lo, hi)
    s28 = vclp((s28 -% s30), lo, hi)
    s30 = vclp((s21 +% s61), lo, hi)
    s21 = vclp((s21 -% s61), lo, hi)
    s61 = vclp((s63 +% s1), lo, hi)
    s1 = vclp((s63 -% s1), lo, hi)
    s63 = vclp((s15 +% s64), lo, hi)
    s15 = vclp((s15 -% s64), lo, hi)
    s64 = vclp((s0 +% s60), lo, hi)
    s0 = vclp((s0 -% s60), lo, hi)
    s60 = (((kp2048) +% (s2 *% kp2896)) -% (s44 *% kp2896)) >> 12u32
    s2 = (((kp2048) +% (s2 *% kp2896)) +% (s44 *% kp2896)) >> 12u32
    s44 = (((kp2048) +% (s57 *% kp2896)) -% (s55 *% kp2896)) >> 12u32
    s55 = (((kp2048) +% (s57 *% kp2896)) +% (s55 *% kp2896)) >> 12u32
    s57 = vclp((s45 +% s59), lo, hi)
    s45 = vclp((s45 -% s59), lo, hi)
    s59 = vclp((s47 +% s49), lo, hi)
    s47 = vclp((s47 -% s49), lo, hi)
    s49 = vclp((s3 +% s50), lo, hi)
    s3 = vclp((s3 -% s50), lo, hi)
    s50 = vclp((s24 +% s52), lo, hi)
    s24 = vclp((s24 -% s52), lo, hi)
    s52 = vclp((s6 +% s26), lo, hi)
    s6 = vclp((s6 -% s26), lo, hi)
    s26 = vclp((s53 +% s51), lo, hi)
    s51 = vclp((s53 -% s51), lo, hi)
    s53 = vclp((s4 +% s5), lo, hi)
    s4 = vclp((s4 -% s5), lo, hi)
    s5 = vclp((s46 +% s48), lo, hi)
    s46 = vclp((s46 -% s48), lo, hi)
    s48 = (((kp2048) +% (s28 *% kp1567)) -% (s16 *% kp3784)) >> 12u32
    s16 = (((kp2048) +% (s28 *% kp3784)) +% (s16 *% kp1567)) >> 12u32
    s28 = (((kp2048) +% (s8 *% kp1567)) -% (s7 *% kp3784)) >> 12u32
    s7 = (((kp2048) +% (s8 *% kp3784)) +% (s7 *% kp1567)) >> 12u32
    s8 = (((kp2048) +% (s41 *% kp1567)) -% (s29 *% kp3784)) >> 12u32
    s29 = (((kp2048) +% (s41 *% kp3784)) +% (s29 *% kp1567)) >> 12u32
    s41 = (((kp2048) +% (s13 *% kp1567)) -% (s27 *% kp3784)) >> 12u32
    s13 = (((kp2048) +% (s13 *% kp3784)) +% (s27 *% kp1567)) >> 12u32
    s27 = (((kp2048) -% (s12 *% kp3784)) -% (s18 *% kp1567)) >> 12u32
    s12 = (((kp2048) +% (s12 *% kp1567)) -% (s18 *% kp3784)) >> 12u32
    s18 = (((kp2048) -% (s37 *% kp3784)) -% (s33 *% kp1567)) >> 12u32
    s33 = (((kp2048) +% (s37 *% kp1567)) -% (s33 *% kp3784)) >> 12u32
    s37 = (((kp2048) -% (s10 *% kp3784)) -% (s17 *% kp1567)) >> 12u32
    s10 = (((kp2048) +% (s10 *% kp1567)) -% (s17 *% kp3784)) >> 12u32
    s17 = (((kp2048) -% (s32 *% kp3784)) -% (s19 *% kp1567)) >> 12u32
    s19 = (((kp2048) +% (s32 *% kp1567)) -% (s19 *% kp3784)) >> 12u32
    s32 = vclp((s30 +% s62), lo, hi)
    s30 = vclp((s30 -% s62), lo, hi)
    s62 = vclp((s61 +% s58), lo, hi)
    s58 = vclp((s61 -% s58), lo, hi)
    s61 = vclp((s63 +% s2), lo, hi)
    s2 = vclp((s63 -% s2), lo, hi)
    s63 = vclp((s64 +% s55), lo, hi)
    s55 = vclp((s64 -% s55), lo, hi)
    s64 = vclp((s0 +% s44), lo, hi)
    s0 = vclp((s0 -% s44), lo, hi)
    s44 = vclp((s15 +% s60), lo, hi)
    s15 = vclp((s15 -% s60), lo, hi)
    s60 = vclp((s1 +% s56), lo, hi)
    s1 = vclp((s1 -% s56), lo, hi)
    s56 = vclp((s21 +% s23), lo, hi)
    s21 = vclp((s21 -% s23), lo, hi)
    s23 = (((kp2048) +% (s46 *% kp2896)) -% (s24 *% kp2896)) >> 12u32
    s24 = (((kp2048) +% (s46 *% kp2896)) +% (s24 *% kp2896)) >> 12u32
    s46 = (((kp2048) +% (s4 *% kp2896)) -% (s3 *% kp2896)) >> 12u32
    s3 = (((kp2048) +% (s4 *% kp2896)) +% (s3 *% kp2896)) >> 12u32
    s4 = (((kp2048) +% (s51 *% kp2896)) -% (s47 *% kp2896)) >> 12u32
    s47 = (((kp2048) +% (s51 *% kp2896)) +% (s47 *% kp2896)) >> 12u32
    s51 = (((kp2048) +% (s6 *% kp2896)) -% (s45 *% kp2896)) >> 12u32
    s6 = (((kp2048) +% (s6 *% kp2896)) +% (s45 *% kp2896)) >> 12u32
    s45 = vclp((s25 +% s42), lo, hi)
    s25 = vclp((s25 -% s42), lo, hi)
    s42 = vclp((s34 +% s38), lo, hi)
    s34 = vclp((s34 -% s38), lo, hi)
    s38 = vclp((s54 +% s20), lo, hi)
    s20 = vclp((s54 -% s20), lo, hi)
    s54 = vclp((s14 +% s22), lo, hi)
    s14 = vclp((s14 -% s22), lo, hi)
    s22 = vclp((s31 +% s35), lo, hi)
    s31 = vclp((s31 -% s35), lo, hi)
    s35 = vclp((s43 +% s39), lo, hi)
    s39 = vclp((s43 -% s39), lo, hi)
    s43 = vclp((s40 +% s36), lo, hi)
    s36 = vclp((s40 -% s36), lo, hi)
    s40 = vclp((s9 +% s11), lo, hi)
    s9 = vclp((s9 -% s11), lo, hi)
    s11 = vclp((s48 +% s17), lo, hi)
    s17 = vclp((s48 -% s17), lo, hi)
    s48 = vclp((s16 +% s19), lo, hi)
    s16 = vclp((s16 -% s19), lo, hi)
    s19 = vclp((s28 +% s37), lo, hi)
    s28 = vclp((s28 -% s37), lo, hi)
    s37 = vclp((s7 +% s10), lo, hi)
    s7 = vclp((s7 -% s10), lo, hi)
    s10 = vclp((s8 +% s18), lo, hi)
    s8 = vclp((s8 -% s18), lo, hi)
    s18 = vclp((s29 +% s33), lo, hi)
    s29 = vclp((s29 -% s33), lo, hi)
    s33 = vclp((s41 +% s27), lo, hi)
    s27 = vclp((s41 -% s27), lo, hi)
    s41 = vclp((s13 +% s12), lo, hi)
    s12 = vclp((s13 -% s12), lo, hi)
    s13 = vclp((s32 +% s52), lo, hi)
    s32 = vclp((s32 -% s52), lo, hi)
    s52 = vclp((s62 +% s26), lo, hi)
    s26 = vclp((s62 -% s26), lo, hi)
    s62 = vclp((s61 +% s53), lo, hi)
    s53 = vclp((s61 -% s53), lo, hi)
    s61 = vclp((s63 +% s5), lo, hi)
    s5 = vclp((s63 -% s5), lo, hi)
    s63 = vclp((s64 +% s24), lo, hi)
    s24 = vclp((s64 -% s24), lo, hi)
    s64 = vclp((s44 +% s3), lo, hi)
    s3 = vclp((s44 -% s3), lo, hi)
    s44 = vclp((s60 +% s47), lo, hi)
    s47 = vclp((s60 -% s47), lo, hi)
    s60 = vclp((s56 +% s6), lo, hi)
    s6 = vclp((s56 -% s6), lo, hi)
    s56 = vclp((s21 +% s51), lo, hi)
    s21 = vclp((s21 -% s51), lo, hi)
    s51 = vclp((s1 +% s4), lo, hi)
    s1 = vclp((s1 -% s4), lo, hi)
    s4 = vclp((s15 +% s46), lo, hi)
    s15 = vclp((s15 -% s46), lo, hi)
    s46 = vclp((s0 +% s23), lo, hi)
    s0 = vclp((s0 -% s23), lo, hi)
    s23 = vclp((s55 +% s50), lo, hi)
    s50 = vclp((s55 -% s50), lo, hi)
    s55 = vclp((s2 +% s49), lo, hi)
    s2 = vclp((s2 -% s49), lo, hi)
    s49 = vclp((s58 +% s59), lo, hi)
    s58 = vclp((s58 -% s59), lo, hi)
    s59 = vclp((s30 +% s57), lo, hi)
    s30 = vclp((s30 -% s57), lo, hi)
    s57 = (((kp2048) +% (s12 *% kp2896)) -% (s27 *% kp2896)) >> 12u32
    s12 = (((kp2048) +% (s12 *% kp2896)) +% (s27 *% kp2896)) >> 12u32
    s27 = (((kp2048) +% (s29 *% kp2896)) -% (s8 *% kp2896)) >> 12u32
    s8 = (((kp2048) +% (s29 *% kp2896)) +% (s8 *% kp2896)) >> 12u32
    s29 = (((kp2048) +% (s7 *% kp2896)) -% (s28 *% kp2896)) >> 12u32
    s7 = (((kp2048) +% (s7 *% kp2896)) +% (s28 *% kp2896)) >> 12u32
    s28 = (((kp2048) +% (s16 *% kp2896)) -% (s17 *% kp2896)) >> 12u32
    s16 = (((kp2048) +% (s16 *% kp2896)) +% (s17 *% kp2896)) >> 12u32
    s17 = (((kp2048) +% (s9 *% kp2896)) -% (s36 *% kp2896)) >> 12u32
    s9 = (((kp2048) +% (s9 *% kp2896)) +% (s36 *% kp2896)) >> 12u32
    s36 = (((kp2048) +% (s39 *% kp2896)) -% (s31 *% kp2896)) >> 12u32
    s31 = (((kp2048) +% (s39 *% kp2896)) +% (s31 *% kp2896)) >> 12u32
    s39 = (((kp2048) +% (s14 *% kp2896)) -% (s20 *% kp2896)) >> 12u32
    s14 = (((kp2048) +% (s14 *% kp2896)) +% (s20 *% kp2896)) >> 12u32
    s20 = (((kp2048) +% (s34 *% kp2896)) -% (s25 *% kp2896)) >> 12u32
    s25 = (((kp2048) +% (s34 *% kp2896)) +% (s25 *% kp2896)) >> 12u32
    vst(t, off + 0usize * st, (vclp((s13 +% s42), lo, hi)))
    vst(t, off + 1usize * st, (vclp((s52 +% s54), lo, hi)))
    vst(t, off + 2usize * st, (vclp((s62 +% s35), lo, hi)))
    vst(t, off + 3usize * st, (vclp((s61 +% s40), lo, hi)))
    vst(t, off + 4usize * st, (vclp((s63 +% s48), lo, hi)))
    vst(t, off + 5usize * st, (vclp((s64 +% s37), lo, hi)))
    vst(t, off + 6usize * st, (vclp((s44 +% s18), lo, hi)))
    vst(t, off + 7usize * st, (vclp((s60 +% s41), lo, hi)))
    vst(t, off + 8usize * st, (vclp((s56 +% s12), lo, hi)))
    vst(t, off + 9usize * st, (vclp((s51 +% s8), lo, hi)))
    vst(t, off + 10usize * st, (vclp((s4 +% s7), lo, hi)))
    vst(t, off + 11usize * st, (vclp((s46 +% s16), lo, hi)))
    vst(t, off + 12usize * st, (vclp((s23 +% s9), lo, hi)))
    vst(t, off + 13usize * st, (vclp((s55 +% s31), lo, hi)))
    vst(t, off + 14usize * st, (vclp((s49 +% s14), lo, hi)))
    vst(t, off + 15usize * st, (vclp((s59 +% s25), lo, hi)))
    vst(t, off + 16usize * st, (vclp((s30 +% s20), lo, hi)))
    vst(t, off + 17usize * st, (vclp((s58 +% s39), lo, hi)))
    vst(t, off + 18usize * st, (vclp((s2 +% s36), lo, hi)))
    vst(t, off + 19usize * st, (vclp((s50 +% s17), lo, hi)))
    vst(t, off + 20usize * st, (vclp((s0 +% s28), lo, hi)))
    vst(t, off + 21usize * st, (vclp((s15 +% s29), lo, hi)))
    vst(t, off + 22usize * st, (vclp((s1 +% s27), lo, hi)))
    vst(t, off + 23usize * st, (vclp((s21 +% s57), lo, hi)))
    vst(t, off + 24usize * st, (vclp((s6 +% s33), lo, hi)))
    vst(t, off + 25usize * st, (vclp((s47 +% s10), lo, hi)))
    vst(t, off + 26usize * st, (vclp((s3 +% s19), lo, hi)))
    vst(t, off + 27usize * st, (vclp((s24 +% s11), lo, hi)))
    vst(t, off + 28usize * st, (vclp((s5 +% s43), lo, hi)))
    vst(t, off + 29usize * st, (vclp((s53 +% s22), lo, hi)))
    vst(t, off + 30usize * st, (vclp((s26 +% s38), lo, hi)))
    vst(t, off + 31usize * st, (vclp((s32 +% s45), lo, hi)))
    vst(t, off + 32usize * st, (vclp((s32 -% s45), lo, hi)))
    vst(t, off + 33usize * st, (vclp((s26 -% s38), lo, hi)))
    vst(t, off + 34usize * st, (vclp((s53 -% s22), lo, hi)))
    vst(t, off + 35usize * st, (vclp((s5 -% s43), lo, hi)))
    vst(t, off + 36usize * st, (vclp((s24 -% s11), lo, hi)))
    vst(t, off + 37usize * st, (vclp((s3 -% s19), lo, hi)))
    vst(t, off + 38usize * st, (vclp((s47 -% s10), lo, hi)))
    vst(t, off + 39usize * st, (vclp((s6 -% s33), lo, hi)))
    vst(t, off + 40usize * st, (vclp((s21 -% s57), lo, hi)))
    vst(t, off + 41usize * st, (vclp((s1 -% s27), lo, hi)))
    vst(t, off + 42usize * st, (vclp((s15 -% s29), lo, hi)))
    vst(t, off + 43usize * st, (vclp((s0 -% s28), lo, hi)))
    vst(t, off + 44usize * st, (vclp((s50 -% s17), lo, hi)))
    vst(t, off + 45usize * st, (vclp((s2 -% s36), lo, hi)))
    vst(t, off + 46usize * st, (vclp((s58 -% s39), lo, hi)))
    vst(t, off + 47usize * st, (vclp((s30 -% s20), lo, hi)))
    vst(t, off + 48usize * st, (vclp((s59 -% s25), lo, hi)))
    vst(t, off + 49usize * st, (vclp((s49 -% s14), lo, hi)))
    vst(t, off + 50usize * st, (vclp((s55 -% s31), lo, hi)))
    vst(t, off + 51usize * st, (vclp((s23 -% s9), lo, hi)))
    vst(t, off + 52usize * st, (vclp((s46 -% s16), lo, hi)))
    vst(t, off + 53usize * st, (vclp((s4 -% s7), lo, hi)))
    vst(t, off + 54usize * st, (vclp((s51 -% s8), lo, hi)))
    vst(t, off + 55usize * st, (vclp((s56 -% s12), lo, hi)))
    vst(t, off + 56usize * st, (vclp((s60 -% s41), lo, hi)))
    vst(t, off + 57usize * st, (vclp((s44 -% s18), lo, hi)))
    vst(t, off + 58usize * st, (vclp((s64 -% s37), lo, hi)))
    vst(t, off + 59usize * st, (vclp((s63 -% s48), lo, hi)))
    vst(t, off + 60usize * st, (vclp((s61 -% s40), lo, hi)))
    vst(t, off + 61usize * st, (vclp((s62 -% s35), lo, hi)))
    vst(t, off + 62usize * st, (vclp((s52 -% s54), lo, hi)))
    vst(t, off + 63usize * st, (vclp((s13 -% s42), lo, hi)))
    }
}


fn vld(t: []i32, o: usize) -> Vec[i32, 4] { ret simd.load[Vec[i32, 4]](t, o) }
fn vst(t: []i32, o: usize, v: Vec[i32, 4]) { simd.store[Vec[i32, 4]](t, o, v) }
fn vsp(c: i32) -> Vec[i32, 4] { ret simd.splat[Vec[i32, 4]](c) }
fn vclp(x: Vec[i32, 4], lo: Vec[i32, 4], hi: Vec[i32, 4]) -> Vec[i32, 4] { ret simd.min[Vec[i32, 4]](simd.max[Vec[i32, 4]](x, lo), hi) }

// ---- vector (SSE, 4 lanes of i32) path for 8-bit streams ----------------------------------------------------
// The 1D transforms below run 4 independent transforms at once: element k of lane l is t[off + k * st + l].
// The spec arithmetic is unchanged; for 8-bit input every intermediate is clamped or bounded to 16 bits
// (times 2^12 constants, sums of two products) so it fits i32.

fn viadst4(t: []i32, off: usize, st: usize) {
    @nocheck {
    let k1321 = simd.splat[Vec[i32, 4]](1321i32)
    let k3803 = simd.splat[Vec[i32, 4]](3803i32)
    let k2482 = simd.splat[Vec[i32, 4]](2482i32)
    let k3344 = simd.splat[Vec[i32, 4]](3344i32)
    let rnd = simd.splat[Vec[i32, 4]](2048i32)
    let t0 = simd.load[Vec[i32, 4]](t, off)
    let t1 = simd.load[Vec[i32, 4]](t, off + st)
    let t2 = simd.load[Vec[i32, 4]](t, off + 2usize * st)
    let t3 = simd.load[Vec[i32, 4]](t, off + 3usize * st)
    let s0 = (t0 *% k1321) +% (t2 *% k3803) +% (t3 *% k2482)
    let s1 = (t0 *% k2482) -% (t2 *% k1321) -% (t3 *% k3803)
    let s2 = (t0 -% t2 +% t3) *% k3344
    let s3 = t1 *% k3344
    simd.store[Vec[i32, 4]](t, off, (s0 +% s3 +% rnd) >> 12u32)
    simd.store[Vec[i32, 4]](t, off + st, (s1 +% s3 +% rnd) >> 12u32)
    simd.store[Vec[i32, 4]](t, off + 2usize * st, (s2 +% rnd) >> 12u32)
    simd.store[Vec[i32, 4]](t, off + 3usize * st, (s0 +% s1 -% s3 +% rnd) >> 12u32)
    }
}

fn viidentity(t: []i32, off: usize, st: usize, n: i32) {
    @nocheck {
    let n0 = usize(1i32 << u32(n))
    let rnd = simd.splat[Vec[i32, 4]](2048i32)
    let k5793 = simd.splat[Vec[i32, 4]](5793i32)
    let k11586 = simd.splat[Vec[i32, 4]](11586i32)
    var k = 0usize
    var p = off
    while k < n0 {
        let v = simd.load[Vec[i32, 4]](t, p)
        if n == 2i32 { simd.store[Vec[i32, 4]](t, p, ((v *% k5793) +% rnd) >> 12u32) } else if n == 3i32 { simd.store[Vec[i32, 4]](t, p, v +% v) } else if n == 4i32 { simd.store[Vec[i32, 4]](t, p, ((v *% k11586) +% rnd) >> 12u32) } else { simd.store[Vec[i32, 4]](t, p, v << 2u32) }
        p += st
        k += 1usize
    }
    }
}

// The number of leading inputs a DCT of 2^n points reads when at most kin of them are non-zero.
fn kbound(kin: usize, n: i32) -> usize {
    let n0 = usize(1i32 << u32(n))
    if n0 > 4usize && kin <= 4usize { ret 4usize }
    if n0 > 8usize && kin <= 8usize { ret 8usize }
    if n0 > 16usize && kin <= 16usize { ret 16usize }
    if n0 > 32usize { ret 32usize }
    ret n0
}

fn vdct(t: []i32, off: usize, st: usize, n: i32, kb: usize, r: u32) {
    if n == 2i32 {
        vidct4(t, off, st, r)
    } else if n == 3i32 {
        if kb == 4usize { vidct8_k4(t, off, st, r) } else { vidct8(t, off, st, r) }
    } else if n == 4i32 {
        if kb == 4usize { vidct16_k4(t, off, st, r) } else if kb == 8usize { vidct16_k8(t, off, st, r) } else { vidct16(t, off, st, r) }
    } else if n == 5i32 {
        if kb == 4usize { vidct32_k4(t, off, st, r) } else if kb == 8usize { vidct32_k8(t, off, st, r) } else if kb == 16usize { vidct32_k16(t, off, st, r) } else { vidct32(t, off, st, r) }
    } else {
        if kb == 4usize { vidct64_k4(t, off, st, r) } else if kb == 8usize { vidct64_k8(t, off, st, r) } else if kb == 16usize { vidct64_k16(t, off, st, r) } else { vidct64(t, off, st, r) }
    }
}

// kb: the kbound of the inputs for a DCT (ignored by the other kinds)
fn vtransform(t: []i32, off: usize, st: usize, kind: u8, n: i32, kb: usize, r: u32) {
    let guard = t[off + ((1usize << u32(n)) - 1usize) * st + 3usize]
    if kind == 0u8 {
        vdct(t, off, st, n, kb, r)
    } else if kind == 1u8 {
        if n == 2i32 { viadst4(t, off, st) } else if n == 3i32 { vfadst8(t, off, st, r) } else { vfadst16(t, off, st, r) }
    } else { viidentity(t, off, st, n) }
}

// out[o + l * stride + c] = lane l of the c-th argument
fn tr_store(out: []i32, o: usize, stride: usize, a: Vec[i32, 4], b: Vec[i32, 4], c: Vec[i32, 4], d: Vec[i32, 4]) {
    let t0 = simd.unpack_lo[Vec[i32, 4]](a, b)
    let t1 = simd.unpack_lo[Vec[i32, 4]](c, d)
    let t2 = simd.unpack_hi[Vec[i32, 4]](a, b)
    let t3 = simd.unpack_hi[Vec[i32, 4]](c, d)
    simd.store[Vec[i32, 4]](out, o, mem.bitcast[Vec[i32, 4]](simd.unpack_lo[Vec[i64, 2]](mem.bitcast[Vec[i64, 2]](t0), mem.bitcast[Vec[i64, 2]](t1))))
    simd.store[Vec[i32, 4]](out, o + stride, mem.bitcast[Vec[i32, 4]](simd.unpack_hi[Vec[i64, 2]](mem.bitcast[Vec[i64, 2]](t0), mem.bitcast[Vec[i64, 2]](t1))))
    simd.store[Vec[i32, 4]](out, o + 2usize * stride, mem.bitcast[Vec[i32, 4]](simd.unpack_lo[Vec[i64, 2]](mem.bitcast[Vec[i64, 2]](t2), mem.bitcast[Vec[i64, 2]](t3))))
    simd.store[Vec[i32, 4]](out, o + 3usize * stride, mem.bitcast[Vec[i32, 4]](simd.unpack_hi[Vec[i64, 2]](mem.bitcast[Vec[i64, 2]](t2), mem.bitcast[Vec[i64, 2]](t3))))
}

fn row_post(x: Vec[i32, 4], rnd: Vec[i32, 4], sh: u32, lo: Vec[i32, 4], hi: Vec[i32, 4]) -> Vec[i32, 4] {
    ret simd.min[Vec[i32, 4]](simd.max[Vec[i32, 4]](((x +% rnd) >> sh), lo), hi)
}

// The 2D process for 8-bit, lossy, valid arguments, rl / cl >= 1 already clamped. On return out holds the
// column-pass output before the final rounding (Round2(x, 4)) and before the FLIPUD row reversal; the FLIPLR
// reversal is already applied. rb: scratch of at least 4 * w entries.
fn core_vec(quant: []const i32, tx_size: usize, tx_type: usize, dc_q: i32, ac_q: i32, rl: usize, cl: usize, out: []i32, rb: []i32) {
    let log2_w = i32(log2_w_tab()[tx_size])
    let log2_h = i32(log2_h_tab()[tx_size])
    let row_kind = row_kind_tab()[tx_type]
    let col_kind = col_kind_tab()[tx_type]
    let w = usize(1i32 << u32(log2_w))
    let h = usize(1i32 << u32(log2_h))
    var tw = w
    if tw > 32usize { tw = 32usize }
    var dq_shift = 0u32
    if tx_size == 3usize || tx_size == 9usize || tx_size == 10usize || tx_size == 17usize || tx_size == 18usize { dq_shift = 1u32 } else if tx_size == 4usize || tx_size == 11usize || tx_size == 12usize { dq_shift = 2u32 }
    let row_shift = u32(row_shift_tab()[tx_size])
    var rect = false
    if log2_w - log2_h == 1i32 || log2_h - log2_w == 1i32 { rect = true }
    var flip_lr = false
    if tx_type == 5usize || tx_type == 7usize || tx_type == 15usize || tx_type == 6usize { flip_lr = true }
    let vhi = simd.splat[Vec[i32, 4]](32767i32)
    let vlo = simd.splat[Vec[i32, 4]](0i32 - 32768i32)
    var rnd_s = 0i32
    if row_shift != 0u32 { rnd_s = 1i32 << (row_shift - 1u32) }
    let vrnd = simd.splat[Vec[i32, 4]](rnd_s)
    let vz = simd.splat[Vec[i32, 4]](0i32)
    var zw = w
    if zw > 32usize { zw = 32usize }
    var rkb = zw
    if row_kind == 0u8 { rkb = kbound(cl, log2_w) }
    let groups = (rl + 3usize) / 4usize
    var g = 0usize
    while g < groups {
        var j = 0usize
        while j < rkb {
            simd.store[Vec[i32, 4]](rb, j * 4usize, vz)
            j += 1usize
        }
        var l = 0usize
        while l < 4usize {
            let i = g * 4usize + l
            if i < rl {
                j = 0usize
                while j < cl {
                    let qv = quant[i * tw + j]
                    if qv != 0i32 {
                        var q = ac_q
                        if i == 0usize && j == 0usize { q = dc_q }
                        let dq = i64(qv) * i64(q)
                        var mag = dq
                        if dq < 0i64 { mag = 0i64 - dq }
                        mag = (mag & 16777215i64) >> dq_shift
                        if dq < 0i64 { mag = 0i64 - mag }
                        if mag < -32768i64 { mag = -32768i64 } else if mag > 32767i64 { mag = 32767i64 }
                        var v = i32(mag)
                        if rect { v = i32((i64(v) * 2896i64 + 2048i64) >> 12u32) }
                        rb[j * 4usize + l] = v
                    }
                    j += 1usize
                }
            }
            l += 1usize
        }
        if cl == 1usize && row_kind == 0u8 {
            let f = ((simd.load[Vec[i32, 4]](rb, 0usize) *% simd.splat[Vec[i32, 4]](2896i32)) +% simd.splat[Vec[i32, 4]](2048i32)) >> 12u32
            j = 0usize
            while j < w {
                simd.store[Vec[i32, 4]](rb, j * 4usize, f)
                j += 1usize
            }
        } else {
            vtransform(rb, 0usize, 4usize, row_kind, log2_w, rkb, 16u32)
        }
        let o = g * 4usize * w
        var jb = 0usize
        while jb < w {
            let a = row_post(simd.load[Vec[i32, 4]](rb, jb * 4usize), vrnd, row_shift, vlo, vhi)
            let b = row_post(simd.load[Vec[i32, 4]](rb, jb * 4usize + 4usize), vrnd, row_shift, vlo, vhi)
            let c = row_post(simd.load[Vec[i32, 4]](rb, jb * 4usize + 8usize), vrnd, row_shift, vlo, vhi)
            let d = row_post(simd.load[Vec[i32, 4]](rb, jb * 4usize + 12usize), vrnd, row_shift, vlo, vhi)
            if flip_lr {
                tr_store(out, o + w - 4usize - jb, w, d, c, b, a)
            } else {
                tr_store(out, o + jb, w, a, b, c, d)
            }
            jb += 4usize
        }
        g += 1usize
    }
    var zh = h
    if col_kind == 0u8 { zh = kbound(groups * 4usize, log2_h) }
    var i = groups * 4usize
    while i < zh {
        var jb = 0usize
        while jb < w {
            simd.store[Vec[i32, 4]](out, i * w + jb, vz)
            jb += 4usize
        }
        i += 1usize
    }
    var jb = 0usize
    if rl == 1usize && col_kind == 0u8 {
        let k2896 = simd.splat[Vec[i32, 4]](2896i32)
        let k2048 = simd.splat[Vec[i32, 4]](2048i32)
        while jb < w {
            let f = ((simd.load[Vec[i32, 4]](out, jb) *% k2896) +% k2048) >> 12u32
            i = 0usize
            while i < h {
                simd.store[Vec[i32, 4]](out, i * w + jb, f)
                i += 1usize
            }
            jb += 4usize
        }
    } else {
        while jb < w {
            vtransform(out, jb, w, col_kind, log2_h, zh, 16u32)
            jb += 4usize
        }
    }
}

fn finish_vec(out: []i32, w: usize, h: usize, flip_ud: bool) {
    let k8 = simd.splat[Vec[i32, 4]](8i32)
    var i = 0usize
    var x = 0usize
    if flip_ud {
        while i < h / 2usize {
            let i2 = h - 1usize - i
            x = 0usize
            while x < w {
                let a = simd.load[Vec[i32, 4]](out, i * w + x)
                let b = simd.load[Vec[i32, 4]](out, i2 * w + x)
                simd.store[Vec[i32, 4]](out, i * w + x, (b +% k8) >> 4u32)
                simd.store[Vec[i32, 4]](out, i2 * w + x, (a +% k8) >> 4u32)
                x += 4usize
            }
            i += 1usize
        }
    } else {
        let n = w * h
        while x < n {
            simd.store[Vec[i32, 4]](out, x, (simd.load[Vec[i32, 4]](out, x) +% k8) >> 4u32)
            x += 4usize
        }
    }
}

fn add16(dst: []u8, o: usize, r0: Vec[i32, 4], r1: Vec[i32, 4], r2: Vec[i32, 4], r3: Vec[i32, 4]) {
    let z = simd.splat[Vec[u8, 16]](0u8)
    let a = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](r0, r1)
    let b = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](r2, r3)
    let p = simd.load[Vec[u8, 16]](dst, o)
    let lo = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](p, z))
    let hi = mem.bitcast[Vec[i16, 8]](simd.unpack_hi[Vec[u8, 16]](p, z))
    simd.store[Vec[u8, 16]](dst, o, simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](simd.adds[Vec[i16, 8]](lo, a), simd.adds[Vec[i16, 8]](hi, b)))
}

// 8 pixels at o. The window read is 16 bytes (dst.len >= o + 16) but only the 8 bytes of the block are written back: the
// bytes after them belong to the next block, which another thread may be writing at the same time.
fn add8(dst: []u8, o: usize, r0: Vec[i32, 4], r1: Vec[i32, 4]) {
    let z = simd.splat[Vec[u8, 16]](0u8)
    let a = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](r0, r1)
    let p = simd.load[Vec[u8, 16]](dst, o)
    let lo = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](p, z))
    let packed = mem.bitcast[Vec[u64, 2]](simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](simd.adds[Vec[i16, 8]](lo, a), a))
    *mem.cast[*u64](&dst[o]) = packed.lanes[0usize]
}

// 4 pixels at o; same rule as add8
fn add4(dst: []u8, o: usize, r0: Vec[i32, 4]) {
    let z = simd.splat[Vec[u8, 16]](0u8)
    let a = simd.pack_sat[Vec[i16, 8], Vec[i32, 4]](r0, r0)
    let p = simd.load[Vec[u8, 16]](dst, o)
    let lo = mem.bitcast[Vec[i16, 8]](simd.unpack_lo[Vec[u8, 16]](p, z))
    let packed = mem.bitcast[Vec[u32, 4]](simd.pack_sat[Vec[u8, 16], Vec[i16, 8]](simd.adds[Vec[i16, 8]](lo, a), a))
    *mem.cast[*u32](&dst[o]) = packed.lanes[0usize]
}

fn add_scalar(dst: []u8, o: usize, n: usize, res: []const i32, ro: usize, round: bool) {
    var x = 0usize
    while x < n {
        var r = res[ro + x]
        if round { r = (r + 8i32) >> 4u32 }
        var v = i32(dst[o + x]) + r
        if v < 0i32 { v = 0i32 } else if v > 255i32 { v = 255i32 }
        dst[o + x] = u8(v)
        x += 1usize
    }
}

fn add_block(out: []const i32, w: usize, h: usize, flip_ud: bool, dst: []u8, stride: usize, x0: usize, y0: usize) {
    let k8 = simd.splat[Vec[i32, 4]](8i32)
    var i = 0usize
    while i < h {
        var s = i
        if flip_ud { s = h - 1usize - i }
        let o = (y0 + i) * stride + x0
        let ro = s * w
        if w >= 16usize {
            var x = 0usize
            while x < w {
                add16(dst, o + x, (simd.load[Vec[i32, 4]](out, ro + x) +% k8) >> 4u32, (simd.load[Vec[i32, 4]](out, ro + x + 4usize) +% k8) >> 4u32, (simd.load[Vec[i32, 4]](out, ro + x + 8usize) +% k8) >> 4u32, (simd.load[Vec[i32, 4]](out, ro + x + 12usize) +% k8) >> 4u32)
                x += 16usize
            }
        } else if o + 16usize <= dst.len {
            if w == 8usize {
                add8(dst, o, (simd.load[Vec[i32, 4]](out, ro) +% k8) >> 4u32, (simd.load[Vec[i32, 4]](out, ro + 4usize) +% k8) >> 4u32)
            } else {
                add4(dst, o, (simd.load[Vec[i32, 4]](out, ro) +% k8) >> 4u32)
            }
        } else {
            add_scalar(dst, o, w, out, ro, true)
        }
        i += 1usize
    }
}

fn add_const(c: i32, w: usize, h: usize, dst: []u8, stride: usize, x0: usize, y0: usize) {
    let r = simd.splat[Vec[i32, 4]](c)
    var i = 0usize
    while i < h {
        let o = (y0 + i) * stride + x0
        if w >= 16usize {
            var x = 0usize
            while x < w {
                add16(dst, o + x, r, r, r, r)
                x += 16usize
            }
        } else if o + 16usize <= dst.len {
            if w == 8usize { add8(dst, o, r, r) } else { add4(dst, o, r) }
        } else {
            var x = 0usize
            while x < w {
                var v = i32(dst[o + x]) + c
                if v < 0i32 { v = 0i32 } else if v > 255i32 { v = 255i32 }
                dst[o + x] = u8(v)
                x += 1usize
            }
        }
        i += 1usize
    }
}

fn is_flip_ud(tx_type: usize) -> bool {
    ret tx_type == 4usize || tx_type == 8usize || tx_type == 14usize || tx_type == 6usize
}

// Both 1D transforms DCT and only Quant[0] non-zero: the residual is one constant (final rounding included).
fn dc_only_value(q0: i32, tx_size: usize, dc_q: i32) -> i32 {
    var dq_shift = 0u32
    if tx_size == 3usize || tx_size == 9usize || tx_size == 10usize || tx_size == 17usize || tx_size == 18usize { dq_shift = 1u32 } else if tx_size == 4usize || tx_size == 11usize || tx_size == 12usize { dq_shift = 2u32 }
    let log2_w = i32(log2_w_tab()[tx_size])
    let log2_h = i32(log2_h_tab()[tx_size])
    var v = 0i64
    if q0 != 0i32 {
        let dq = i64(q0) * i64(dc_q)
        var mag = dq
        if dq < 0i64 { mag = 0i64 - dq }
        mag = (mag & 16777215i64) >> dq_shift
        if dq < 0i64 { mag = 0i64 - mag }
        if mag < -32768i64 { mag = -32768i64 } else if mag > 32767i64 { mag = 32767i64 }
        v = mag
        if log2_w - log2_h == 1i32 || log2_h - log2_w == 1i32 { v = (v * 2896i64 + 2048i64) >> 12u32 }
    }
    var f = (v * 2896i64 + 2048i64) >> 12u32
    let row_shift = u32(row_shift_tab()[tx_size])
    if row_shift != 0u32 { f = (f + (1i64 << (row_shift - 1u32))) >> row_shift }
    if f < -32768i64 { f = -32768i64 } else if f > 32767i64 { f = 32767i64 }
    f = (f * 2896i64 + 2048i64) >> 12u32
    ret i32((f + 8i64) >> 4u32)
}

fn reconstruct_eob(quant: []const i32, tx_size: usize, tx_type: usize, lossless: bool, bit_depth: u32, dc_q: i32, ac_q: i32, eob_row_limit: usize, eob_col_limit: usize, out: []i32) -> err {
    if tx_size >= 19usize || tx_type >= 16usize { ret Invalid }
    if lossless || bit_depth != 8u32 { ret reconstruct_generic(quant, tx_size, tx_type, lossless, bit_depth, dc_q, ac_q, out) }
    let log2_w = i32(log2_w_tab()[tx_size])
    let log2_h = i32(log2_h_tab()[tx_size])
    if !kind_ok(row_kind_tab()[tx_type], log2_w) || !kind_ok(col_kind_tab()[tx_type], log2_h) { ret Invalid }
    let w = usize(1i32 << u32(log2_w))
    let h = usize(1i32 << u32(log2_h))
    var tw = w
    if tw > 32usize { tw = 32usize }
    var th = h
    if th > 32usize { th = 32usize }
    if quant.len < tw * th || out.len < w * h { ret Invalid }
    var rl = eob_row_limit
    if rl > th { rl = th }
    var cl = eob_col_limit
    if cl > tw { cl = tw }
    var i = 0usize
    if rl == 0usize || cl == 0usize {
        let vz = simd.splat[Vec[i32, 4]](0i32)
        while i < w * h {
            simd.store[Vec[i32, 4]](out, i, vz)
            i += 4usize
        }
        ret ok
    }
    var rb: [256]i32 = zero
    core_vec(quant, tx_size, tx_type, dc_q, ac_q, rl, cl, out, rb[..])
    finish_vec(out, w, h, is_flip_ud(tx_type))
    ret ok
}

//   reconstruct_add(quant, tx_size, tx_type, lossless, bit_depth, dc_q, ac_q, eob_row_limit, eob_col_limit,
//                   dst, dst_stride, dst_x, dst_y, scratch) -> err
//     reconstruct_eob followed by adding the residual to the 8-bit plane dst (row stride dst_stride) at
//     (dst_x, dst_y), clamping to 0..255. bit_depth must be 8 (else Invalid). The whole w * h block must lie
//     inside dst ((dst_y + h - 1) * dst_stride + dst_x + w <= dst.len). scratch needs w * h + 4 * w entries
//     (4352 always suffice); its contents on return are unspecified.
fn reconstruct_add(quant: []const i32, tx_size: usize, tx_type: usize, lossless: bool, bit_depth: u32, dc_q: i32, ac_q: i32, eob_row_limit: usize, eob_col_limit: usize, dst: []u8, dst_stride: usize, dst_x: usize, dst_y: usize, scratch: []i32) -> err {
    if bit_depth != 8u32 || tx_size >= 19usize || tx_type >= 16usize { ret Invalid }
    let log2_w = i32(log2_w_tab()[tx_size])
    let log2_h = i32(log2_h_tab()[tx_size])
    let w = usize(1i32 << u32(log2_w))
    let h = usize(1i32 << u32(log2_h))
    if (dst_y + h - 1usize) * dst_stride + dst_x + w > dst.len || dst_x + w > dst_stride { ret Invalid }
    if lossless {
        if scratch.len < w * h { ret Invalid }
        try reconstruct_generic(quant, tx_size, tx_type, lossless, bit_depth, dc_q, ac_q, scratch)
        var i = 0usize
        while i < h {
            add_scalar(dst, (dst_y + i) * dst_stride + dst_x, w, scratch, i * w, false)
            i += 1usize
        }
        ret ok
    }
    let row_kind = row_kind_tab()[tx_type]
    let col_kind = col_kind_tab()[tx_type]
    if !kind_ok(row_kind, log2_w) || !kind_ok(col_kind, log2_h) { ret Invalid }
    var tw = w
    if tw > 32usize { tw = 32usize }
    var th = h
    if th > 32usize { th = 32usize }
    if quant.len < tw * th || scratch.len < w * h + 4usize * w { ret Invalid }
    var rl = eob_row_limit
    if rl > th { rl = th }
    var cl = eob_col_limit
    if cl > tw { cl = tw }
    if rl == 0usize || cl == 0usize { ret ok }
    if rl == 1usize && cl == 1usize && row_kind == 0u8 && col_kind == 0u8 {
        add_const(dc_only_value(quant[0usize], tx_size, dc_q), w, h, dst, dst_stride, dst_x, dst_y)
        ret ok
    }
    core_vec(quant, tx_size, tx_type, dc_q, ac_q, rl, cl, scratch[0usize..w * h], scratch[w * h..])
    add_block(scratch[0usize..w * h], w, h, is_flip_ud(tx_type), dst, dst_stride, dst_x, dst_y)
    ret ok
}

fn reconstruct(quant: []const i32, tx_size: usize, tx_type: usize, lossless: bool, bit_depth: u32, dc_q: i32, ac_q: i32, out: []i32) -> err {
    if tx_size >= 19usize || tx_type >= 16usize { ret Invalid }
    let tw = usize(1u32 << u32(log2_w_tab()[tx_size]))
    let th = usize(1u32 << u32(log2_h_tab()[tx_size]))
    var cw = tw
    if cw > 32usize { cw = 32usize }
    var ch = th
    if ch > 32usize { ch = 32usize }
    if quant.len < cw * ch { ret Invalid }
    var rl = 0usize
    var cl = 0usize
    var i = 0usize
    while i < ch {
        var j = 0usize
        while j < cw {
            if quant[i * cw + j] != 0i32 {
                if i + 1usize > rl { rl = i + 1usize }
                if j + 1usize > cl { cl = j + 1usize }
            }
            j += 1usize
        }
        i += 1usize
    }
    ret reconstruct_eob(quant, tx_size, tx_type, lossless, bit_depth, dc_q, ac_q, rl, cl, out)
}
