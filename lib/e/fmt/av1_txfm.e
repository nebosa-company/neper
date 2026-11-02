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
// length (ADST above 16, identity above 32) is `Invalid`. All the arithmetic is done in 64 bits, so every
// bit depth the spec allows is exact. The lossy fast path (reconstruct_eob) uses unrolled strided 1D
// transforms generated from the spec's butterfly structure (idctN, iadst8, iadst16 below); the lossless
// path and inverse_transform_2d use the generic loops.

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

fn idct4(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi: i64 = (1i64 << (r - 1u32)) - 1i64
    let lo: i64 = 0i64 - (1i64 << (r - 1u32))
    var tx: i64 = 0i64
    var ty: i64 = 0i64
    var v0: i64 = i64(t[off + 0usize * st])
    var v1: i64 = i64(t[off + 2usize * st])
    var v2: i64 = i64(t[off + 1usize * st])
    var v3: i64 = i64(t[off + 3usize * st])
    tx = (2048i64 + v0 * 2896i64 - v1 * 2896i64) >> 12u32
    ty = (2048i64 + v0 * 2896i64 + v1 * 2896i64) >> 12u32
    v0 = ty
    v1 = tx
    tx = (2048i64 + v2 * 1567i64 - v3 * 3784i64) >> 12u32
    ty = (2048i64 + v2 * 3784i64 + v3 * 1567i64) >> 12u32
    v2 = tx
    v3 = ty
    tx = v0 + v3
    ty = v0 - v3
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v3 = ty
    tx = v1 + v2
    ty = v1 - v2
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v2 = ty
    t[off + 0usize * st] = i32(v0)
    t[off + 1usize * st] = i32(v1)
    t[off + 2usize * st] = i32(v2)
    t[off + 3usize * st] = i32(v3)
    }
}

fn idct8(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi: i64 = (1i64 << (r - 1u32)) - 1i64
    let lo: i64 = 0i64 - (1i64 << (r - 1u32))
    var tx: i64 = 0i64
    var ty: i64 = 0i64
    var v0: i64 = i64(t[off + 0usize * st])
    var v1: i64 = i64(t[off + 4usize * st])
    var v2: i64 = i64(t[off + 2usize * st])
    var v3: i64 = i64(t[off + 6usize * st])
    var v4: i64 = i64(t[off + 1usize * st])
    var v5: i64 = i64(t[off + 5usize * st])
    var v6: i64 = i64(t[off + 3usize * st])
    var v7: i64 = i64(t[off + 7usize * st])
    tx = (2048i64 + v4 * 799i64 - v7 * 4017i64) >> 12u32
    ty = (2048i64 + v4 * 4017i64 + v7 * 799i64) >> 12u32
    v4 = tx
    v7 = ty
    tx = (2048i64 + v5 * 3406i64 - v6 * 2276i64) >> 12u32
    ty = (2048i64 + v5 * 2276i64 + v6 * 3406i64) >> 12u32
    v5 = tx
    v6 = ty
    tx = (2048i64 + v0 * 2896i64 - v1 * 2896i64) >> 12u32
    ty = (2048i64 + v0 * 2896i64 + v1 * 2896i64) >> 12u32
    v0 = ty
    v1 = tx
    tx = (2048i64 + v2 * 1567i64 - v3 * 3784i64) >> 12u32
    ty = (2048i64 + v2 * 3784i64 + v3 * 1567i64) >> 12u32
    v2 = tx
    v3 = ty
    tx = v4 + v5
    ty = v4 - v5
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v5 = ty
    tx = v7 + v6
    ty = v7 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v7 = tx
    v6 = ty
    tx = v0 + v3
    ty = v0 - v3
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v3 = ty
    tx = v1 + v2
    ty = v1 - v2
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v2 = ty
    tx = (2048i64 + v6 * 2896i64 - v5 * 2896i64) >> 12u32
    ty = (2048i64 + v6 * 2896i64 + v5 * 2896i64) >> 12u32
    v6 = ty
    v5 = tx
    tx = v0 + v7
    ty = v0 - v7
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v7 = ty
    tx = v1 + v6
    ty = v1 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v6 = ty
    tx = v2 + v5
    ty = v2 - v5
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v5 = ty
    tx = v3 + v4
    ty = v3 - v4
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v4 = ty
    t[off + 0usize * st] = i32(v0)
    t[off + 1usize * st] = i32(v1)
    t[off + 2usize * st] = i32(v2)
    t[off + 3usize * st] = i32(v3)
    t[off + 4usize * st] = i32(v4)
    t[off + 5usize * st] = i32(v5)
    t[off + 6usize * st] = i32(v6)
    t[off + 7usize * st] = i32(v7)
    }
}

fn idct16(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi: i64 = (1i64 << (r - 1u32)) - 1i64
    let lo: i64 = 0i64 - (1i64 << (r - 1u32))
    var tx: i64 = 0i64
    var ty: i64 = 0i64
    var v0: i64 = i64(t[off + 0usize * st])
    var v1: i64 = i64(t[off + 8usize * st])
    var v2: i64 = i64(t[off + 4usize * st])
    var v3: i64 = i64(t[off + 12usize * st])
    var v4: i64 = i64(t[off + 2usize * st])
    var v5: i64 = i64(t[off + 10usize * st])
    var v6: i64 = i64(t[off + 6usize * st])
    var v7: i64 = i64(t[off + 14usize * st])
    var v8: i64 = i64(t[off + 1usize * st])
    var v9: i64 = i64(t[off + 9usize * st])
    var v10: i64 = i64(t[off + 5usize * st])
    var v11: i64 = i64(t[off + 13usize * st])
    var v12: i64 = i64(t[off + 3usize * st])
    var v13: i64 = i64(t[off + 11usize * st])
    var v14: i64 = i64(t[off + 7usize * st])
    var v15: i64 = i64(t[off + 15usize * st])
    tx = (2048i64 + v8 * 401i64 - v15 * 4076i64) >> 12u32
    ty = (2048i64 + v8 * 4076i64 + v15 * 401i64) >> 12u32
    v8 = tx
    v15 = ty
    tx = (2048i64 + v9 * 3166i64 - v14 * 2598i64) >> 12u32
    ty = (2048i64 + v9 * 2598i64 + v14 * 3166i64) >> 12u32
    v9 = tx
    v14 = ty
    tx = (2048i64 + v10 * 1931i64 - v13 * 3612i64) >> 12u32
    ty = (2048i64 + v10 * 3612i64 + v13 * 1931i64) >> 12u32
    v10 = tx
    v13 = ty
    tx = (2048i64 + v11 * 3920i64 - v12 * 1189i64) >> 12u32
    ty = (2048i64 + v11 * 1189i64 + v12 * 3920i64) >> 12u32
    v11 = tx
    v12 = ty
    tx = (2048i64 + v4 * 799i64 - v7 * 4017i64) >> 12u32
    ty = (2048i64 + v4 * 4017i64 + v7 * 799i64) >> 12u32
    v4 = tx
    v7 = ty
    tx = (2048i64 + v5 * 3406i64 - v6 * 2276i64) >> 12u32
    ty = (2048i64 + v5 * 2276i64 + v6 * 3406i64) >> 12u32
    v5 = tx
    v6 = ty
    tx = v8 + v9
    ty = v8 - v9
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v8 = tx
    v9 = ty
    tx = v11 + v10
    ty = v11 - v10
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v11 = tx
    v10 = ty
    tx = v12 + v13
    ty = v12 - v13
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v12 = tx
    v13 = ty
    tx = v15 + v14
    ty = v15 - v14
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v15 = tx
    v14 = ty
    tx = (2048i64 + v0 * 2896i64 - v1 * 2896i64) >> 12u32
    ty = (2048i64 + v0 * 2896i64 + v1 * 2896i64) >> 12u32
    v0 = ty
    v1 = tx
    tx = (2048i64 + v2 * 1567i64 - v3 * 3784i64) >> 12u32
    ty = (2048i64 + v2 * 3784i64 + v3 * 1567i64) >> 12u32
    v2 = tx
    v3 = ty
    tx = v4 + v5
    ty = v4 - v5
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v5 = ty
    tx = v7 + v6
    ty = v7 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v7 = tx
    v6 = ty
    tx = (2048i64 + v14 * 1567i64 - v9 * 3784i64) >> 12u32
    ty = (2048i64 + v14 * 3784i64 + v9 * 1567i64) >> 12u32
    v14 = ty
    v9 = tx
    tx = (2048i64 - v13 * 3784i64 - v10 * 1567i64) >> 12u32
    ty = (2048i64 + v13 * 1567i64 - v10 * 3784i64) >> 12u32
    v13 = ty
    v10 = tx
    tx = v0 + v3
    ty = v0 - v3
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v3 = ty
    tx = v1 + v2
    ty = v1 - v2
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v2 = ty
    tx = (2048i64 + v6 * 2896i64 - v5 * 2896i64) >> 12u32
    ty = (2048i64 + v6 * 2896i64 + v5 * 2896i64) >> 12u32
    v6 = ty
    v5 = tx
    tx = v8 + v11
    ty = v8 - v11
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v8 = tx
    v11 = ty
    tx = v9 + v10
    ty = v9 - v10
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v9 = tx
    v10 = ty
    tx = v15 + v12
    ty = v15 - v12
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v15 = tx
    v12 = ty
    tx = v14 + v13
    ty = v14 - v13
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v14 = tx
    v13 = ty
    tx = v0 + v7
    ty = v0 - v7
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v7 = ty
    tx = v1 + v6
    ty = v1 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v6 = ty
    tx = v2 + v5
    ty = v2 - v5
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v5 = ty
    tx = v3 + v4
    ty = v3 - v4
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v4 = ty
    tx = (2048i64 + v13 * 2896i64 - v10 * 2896i64) >> 12u32
    ty = (2048i64 + v13 * 2896i64 + v10 * 2896i64) >> 12u32
    v13 = ty
    v10 = tx
    tx = (2048i64 + v12 * 2896i64 - v11 * 2896i64) >> 12u32
    ty = (2048i64 + v12 * 2896i64 + v11 * 2896i64) >> 12u32
    v12 = ty
    v11 = tx
    tx = v0 + v15
    ty = v0 - v15
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v15 = ty
    tx = v1 + v14
    ty = v1 - v14
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v14 = ty
    tx = v2 + v13
    ty = v2 - v13
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v13 = ty
    tx = v3 + v12
    ty = v3 - v12
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v12 = ty
    tx = v4 + v11
    ty = v4 - v11
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v11 = ty
    tx = v5 + v10
    ty = v5 - v10
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v5 = tx
    v10 = ty
    tx = v6 + v9
    ty = v6 - v9
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v6 = tx
    v9 = ty
    tx = v7 + v8
    ty = v7 - v8
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v7 = tx
    v8 = ty
    t[off + 0usize * st] = i32(v0)
    t[off + 1usize * st] = i32(v1)
    t[off + 2usize * st] = i32(v2)
    t[off + 3usize * st] = i32(v3)
    t[off + 4usize * st] = i32(v4)
    t[off + 5usize * st] = i32(v5)
    t[off + 6usize * st] = i32(v6)
    t[off + 7usize * st] = i32(v7)
    t[off + 8usize * st] = i32(v8)
    t[off + 9usize * st] = i32(v9)
    t[off + 10usize * st] = i32(v10)
    t[off + 11usize * st] = i32(v11)
    t[off + 12usize * st] = i32(v12)
    t[off + 13usize * st] = i32(v13)
    t[off + 14usize * st] = i32(v14)
    t[off + 15usize * st] = i32(v15)
    }
}

fn idct32(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi: i64 = (1i64 << (r - 1u32)) - 1i64
    let lo: i64 = 0i64 - (1i64 << (r - 1u32))
    var tx: i64 = 0i64
    var ty: i64 = 0i64
    var v0: i64 = i64(t[off + 0usize * st])
    var v1: i64 = i64(t[off + 16usize * st])
    var v2: i64 = i64(t[off + 8usize * st])
    var v3: i64 = i64(t[off + 24usize * st])
    var v4: i64 = i64(t[off + 4usize * st])
    var v5: i64 = i64(t[off + 20usize * st])
    var v6: i64 = i64(t[off + 12usize * st])
    var v7: i64 = i64(t[off + 28usize * st])
    var v8: i64 = i64(t[off + 2usize * st])
    var v9: i64 = i64(t[off + 18usize * st])
    var v10: i64 = i64(t[off + 10usize * st])
    var v11: i64 = i64(t[off + 26usize * st])
    var v12: i64 = i64(t[off + 6usize * st])
    var v13: i64 = i64(t[off + 22usize * st])
    var v14: i64 = i64(t[off + 14usize * st])
    var v15: i64 = i64(t[off + 30usize * st])
    var v16: i64 = i64(t[off + 1usize * st])
    var v17: i64 = i64(t[off + 17usize * st])
    var v18: i64 = i64(t[off + 9usize * st])
    var v19: i64 = i64(t[off + 25usize * st])
    var v20: i64 = i64(t[off + 5usize * st])
    var v21: i64 = i64(t[off + 21usize * st])
    var v22: i64 = i64(t[off + 13usize * st])
    var v23: i64 = i64(t[off + 29usize * st])
    var v24: i64 = i64(t[off + 3usize * st])
    var v25: i64 = i64(t[off + 19usize * st])
    var v26: i64 = i64(t[off + 11usize * st])
    var v27: i64 = i64(t[off + 27usize * st])
    var v28: i64 = i64(t[off + 7usize * st])
    var v29: i64 = i64(t[off + 23usize * st])
    var v30: i64 = i64(t[off + 15usize * st])
    var v31: i64 = i64(t[off + 31usize * st])
    tx = (2048i64 + v16 * 201i64 - v31 * 4091i64) >> 12u32
    ty = (2048i64 + v16 * 4091i64 + v31 * 201i64) >> 12u32
    v16 = tx
    v31 = ty
    tx = (2048i64 + v17 * 3035i64 - v30 * 2751i64) >> 12u32
    ty = (2048i64 + v17 * 2751i64 + v30 * 3035i64) >> 12u32
    v17 = tx
    v30 = ty
    tx = (2048i64 + v18 * 1751i64 - v29 * 3703i64) >> 12u32
    ty = (2048i64 + v18 * 3703i64 + v29 * 1751i64) >> 12u32
    v18 = tx
    v29 = ty
    tx = (2048i64 + v19 * 3857i64 - v28 * 1380i64) >> 12u32
    ty = (2048i64 + v19 * 1380i64 + v28 * 3857i64) >> 12u32
    v19 = tx
    v28 = ty
    tx = (2048i64 + v20 * 995i64 - v27 * 3973i64) >> 12u32
    ty = (2048i64 + v20 * 3973i64 + v27 * 995i64) >> 12u32
    v20 = tx
    v27 = ty
    tx = (2048i64 + v21 * 3513i64 - v26 * 2106i64) >> 12u32
    ty = (2048i64 + v21 * 2106i64 + v26 * 3513i64) >> 12u32
    v21 = tx
    v26 = ty
    tx = (2048i64 + v22 * 2440i64 - v25 * 3290i64) >> 12u32
    ty = (2048i64 + v22 * 3290i64 + v25 * 2440i64) >> 12u32
    v22 = tx
    v25 = ty
    tx = (2048i64 + v23 * 4052i64 - v24 * 601i64) >> 12u32
    ty = (2048i64 + v23 * 601i64 + v24 * 4052i64) >> 12u32
    v23 = tx
    v24 = ty
    tx = (2048i64 + v8 * 401i64 - v15 * 4076i64) >> 12u32
    ty = (2048i64 + v8 * 4076i64 + v15 * 401i64) >> 12u32
    v8 = tx
    v15 = ty
    tx = (2048i64 + v9 * 3166i64 - v14 * 2598i64) >> 12u32
    ty = (2048i64 + v9 * 2598i64 + v14 * 3166i64) >> 12u32
    v9 = tx
    v14 = ty
    tx = (2048i64 + v10 * 1931i64 - v13 * 3612i64) >> 12u32
    ty = (2048i64 + v10 * 3612i64 + v13 * 1931i64) >> 12u32
    v10 = tx
    v13 = ty
    tx = (2048i64 + v11 * 3920i64 - v12 * 1189i64) >> 12u32
    ty = (2048i64 + v11 * 1189i64 + v12 * 3920i64) >> 12u32
    v11 = tx
    v12 = ty
    tx = v16 + v17
    ty = v16 - v17
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v16 = tx
    v17 = ty
    tx = v19 + v18
    ty = v19 - v18
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v19 = tx
    v18 = ty
    tx = v20 + v21
    ty = v20 - v21
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v20 = tx
    v21 = ty
    tx = v23 + v22
    ty = v23 - v22
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v23 = tx
    v22 = ty
    tx = v24 + v25
    ty = v24 - v25
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v24 = tx
    v25 = ty
    tx = v27 + v26
    ty = v27 - v26
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v27 = tx
    v26 = ty
    tx = v28 + v29
    ty = v28 - v29
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v28 = tx
    v29 = ty
    tx = v31 + v30
    ty = v31 - v30
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v31 = tx
    v30 = ty
    tx = (2048i64 + v4 * 799i64 - v7 * 4017i64) >> 12u32
    ty = (2048i64 + v4 * 4017i64 + v7 * 799i64) >> 12u32
    v4 = tx
    v7 = ty
    tx = (2048i64 + v5 * 3406i64 - v6 * 2276i64) >> 12u32
    ty = (2048i64 + v5 * 2276i64 + v6 * 3406i64) >> 12u32
    v5 = tx
    v6 = ty
    tx = v8 + v9
    ty = v8 - v9
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v8 = tx
    v9 = ty
    tx = v11 + v10
    ty = v11 - v10
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v11 = tx
    v10 = ty
    tx = v12 + v13
    ty = v12 - v13
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v12 = tx
    v13 = ty
    tx = v15 + v14
    ty = v15 - v14
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v15 = tx
    v14 = ty
    tx = (2048i64 + v30 * 799i64 - v17 * 4017i64) >> 12u32
    ty = (2048i64 + v30 * 4017i64 + v17 * 799i64) >> 12u32
    v30 = ty
    v17 = tx
    tx = (2048i64 - v29 * 4017i64 - v18 * 799i64) >> 12u32
    ty = (2048i64 + v29 * 799i64 - v18 * 4017i64) >> 12u32
    v29 = ty
    v18 = tx
    tx = (2048i64 + v26 * 3406i64 - v21 * 2276i64) >> 12u32
    ty = (2048i64 + v26 * 2276i64 + v21 * 3406i64) >> 12u32
    v26 = ty
    v21 = tx
    tx = (2048i64 - v25 * 2276i64 - v22 * 3406i64) >> 12u32
    ty = (2048i64 + v25 * 3406i64 - v22 * 2276i64) >> 12u32
    v25 = ty
    v22 = tx
    tx = (2048i64 + v0 * 2896i64 - v1 * 2896i64) >> 12u32
    ty = (2048i64 + v0 * 2896i64 + v1 * 2896i64) >> 12u32
    v0 = ty
    v1 = tx
    tx = (2048i64 + v2 * 1567i64 - v3 * 3784i64) >> 12u32
    ty = (2048i64 + v2 * 3784i64 + v3 * 1567i64) >> 12u32
    v2 = tx
    v3 = ty
    tx = v4 + v5
    ty = v4 - v5
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v5 = ty
    tx = v7 + v6
    ty = v7 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v7 = tx
    v6 = ty
    tx = (2048i64 + v14 * 1567i64 - v9 * 3784i64) >> 12u32
    ty = (2048i64 + v14 * 3784i64 + v9 * 1567i64) >> 12u32
    v14 = ty
    v9 = tx
    tx = (2048i64 - v13 * 3784i64 - v10 * 1567i64) >> 12u32
    ty = (2048i64 + v13 * 1567i64 - v10 * 3784i64) >> 12u32
    v13 = ty
    v10 = tx
    tx = v16 + v19
    ty = v16 - v19
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v16 = tx
    v19 = ty
    tx = v17 + v18
    ty = v17 - v18
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v17 = tx
    v18 = ty
    tx = v23 + v20
    ty = v23 - v20
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v23 = tx
    v20 = ty
    tx = v22 + v21
    ty = v22 - v21
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v22 = tx
    v21 = ty
    tx = v24 + v27
    ty = v24 - v27
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v24 = tx
    v27 = ty
    tx = v25 + v26
    ty = v25 - v26
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v25 = tx
    v26 = ty
    tx = v31 + v28
    ty = v31 - v28
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v31 = tx
    v28 = ty
    tx = v30 + v29
    ty = v30 - v29
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v30 = tx
    v29 = ty
    tx = v0 + v3
    ty = v0 - v3
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v3 = ty
    tx = v1 + v2
    ty = v1 - v2
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v2 = ty
    tx = (2048i64 + v6 * 2896i64 - v5 * 2896i64) >> 12u32
    ty = (2048i64 + v6 * 2896i64 + v5 * 2896i64) >> 12u32
    v6 = ty
    v5 = tx
    tx = v8 + v11
    ty = v8 - v11
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v8 = tx
    v11 = ty
    tx = v9 + v10
    ty = v9 - v10
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v9 = tx
    v10 = ty
    tx = v15 + v12
    ty = v15 - v12
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v15 = tx
    v12 = ty
    tx = v14 + v13
    ty = v14 - v13
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v14 = tx
    v13 = ty
    tx = (2048i64 + v29 * 1567i64 - v18 * 3784i64) >> 12u32
    ty = (2048i64 + v29 * 3784i64 + v18 * 1567i64) >> 12u32
    v29 = ty
    v18 = tx
    tx = (2048i64 + v28 * 1567i64 - v19 * 3784i64) >> 12u32
    ty = (2048i64 + v28 * 3784i64 + v19 * 1567i64) >> 12u32
    v28 = ty
    v19 = tx
    tx = (2048i64 - v27 * 3784i64 - v20 * 1567i64) >> 12u32
    ty = (2048i64 + v27 * 1567i64 - v20 * 3784i64) >> 12u32
    v27 = ty
    v20 = tx
    tx = (2048i64 - v26 * 3784i64 - v21 * 1567i64) >> 12u32
    ty = (2048i64 + v26 * 1567i64 - v21 * 3784i64) >> 12u32
    v26 = ty
    v21 = tx
    tx = v0 + v7
    ty = v0 - v7
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v7 = ty
    tx = v1 + v6
    ty = v1 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v6 = ty
    tx = v2 + v5
    ty = v2 - v5
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v5 = ty
    tx = v3 + v4
    ty = v3 - v4
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v4 = ty
    tx = (2048i64 + v13 * 2896i64 - v10 * 2896i64) >> 12u32
    ty = (2048i64 + v13 * 2896i64 + v10 * 2896i64) >> 12u32
    v13 = ty
    v10 = tx
    tx = (2048i64 + v12 * 2896i64 - v11 * 2896i64) >> 12u32
    ty = (2048i64 + v12 * 2896i64 + v11 * 2896i64) >> 12u32
    v12 = ty
    v11 = tx
    tx = v16 + v23
    ty = v16 - v23
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v16 = tx
    v23 = ty
    tx = v17 + v22
    ty = v17 - v22
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v17 = tx
    v22 = ty
    tx = v18 + v21
    ty = v18 - v21
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v18 = tx
    v21 = ty
    tx = v19 + v20
    ty = v19 - v20
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v19 = tx
    v20 = ty
    tx = v31 + v24
    ty = v31 - v24
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v31 = tx
    v24 = ty
    tx = v30 + v25
    ty = v30 - v25
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v30 = tx
    v25 = ty
    tx = v29 + v26
    ty = v29 - v26
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v29 = tx
    v26 = ty
    tx = v28 + v27
    ty = v28 - v27
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v28 = tx
    v27 = ty
    tx = v0 + v15
    ty = v0 - v15
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v15 = ty
    tx = v1 + v14
    ty = v1 - v14
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v14 = ty
    tx = v2 + v13
    ty = v2 - v13
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v13 = ty
    tx = v3 + v12
    ty = v3 - v12
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v12 = ty
    tx = v4 + v11
    ty = v4 - v11
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v11 = ty
    tx = v5 + v10
    ty = v5 - v10
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v5 = tx
    v10 = ty
    tx = v6 + v9
    ty = v6 - v9
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v6 = tx
    v9 = ty
    tx = v7 + v8
    ty = v7 - v8
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v7 = tx
    v8 = ty
    tx = (2048i64 + v27 * 2896i64 - v20 * 2896i64) >> 12u32
    ty = (2048i64 + v27 * 2896i64 + v20 * 2896i64) >> 12u32
    v27 = ty
    v20 = tx
    tx = (2048i64 + v26 * 2896i64 - v21 * 2896i64) >> 12u32
    ty = (2048i64 + v26 * 2896i64 + v21 * 2896i64) >> 12u32
    v26 = ty
    v21 = tx
    tx = (2048i64 + v25 * 2896i64 - v22 * 2896i64) >> 12u32
    ty = (2048i64 + v25 * 2896i64 + v22 * 2896i64) >> 12u32
    v25 = ty
    v22 = tx
    tx = (2048i64 + v24 * 2896i64 - v23 * 2896i64) >> 12u32
    ty = (2048i64 + v24 * 2896i64 + v23 * 2896i64) >> 12u32
    v24 = ty
    v23 = tx
    tx = v0 + v31
    ty = v0 - v31
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v31 = ty
    tx = v1 + v30
    ty = v1 - v30
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v30 = ty
    tx = v2 + v29
    ty = v2 - v29
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v29 = ty
    tx = v3 + v28
    ty = v3 - v28
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v28 = ty
    tx = v4 + v27
    ty = v4 - v27
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v27 = ty
    tx = v5 + v26
    ty = v5 - v26
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v5 = tx
    v26 = ty
    tx = v6 + v25
    ty = v6 - v25
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v6 = tx
    v25 = ty
    tx = v7 + v24
    ty = v7 - v24
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v7 = tx
    v24 = ty
    tx = v8 + v23
    ty = v8 - v23
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v8 = tx
    v23 = ty
    tx = v9 + v22
    ty = v9 - v22
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v9 = tx
    v22 = ty
    tx = v10 + v21
    ty = v10 - v21
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v10 = tx
    v21 = ty
    tx = v11 + v20
    ty = v11 - v20
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v11 = tx
    v20 = ty
    tx = v12 + v19
    ty = v12 - v19
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v12 = tx
    v19 = ty
    tx = v13 + v18
    ty = v13 - v18
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v13 = tx
    v18 = ty
    tx = v14 + v17
    ty = v14 - v17
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v14 = tx
    v17 = ty
    tx = v15 + v16
    ty = v15 - v16
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v15 = tx
    v16 = ty
    t[off + 0usize * st] = i32(v0)
    t[off + 1usize * st] = i32(v1)
    t[off + 2usize * st] = i32(v2)
    t[off + 3usize * st] = i32(v3)
    t[off + 4usize * st] = i32(v4)
    t[off + 5usize * st] = i32(v5)
    t[off + 6usize * st] = i32(v6)
    t[off + 7usize * st] = i32(v7)
    t[off + 8usize * st] = i32(v8)
    t[off + 9usize * st] = i32(v9)
    t[off + 10usize * st] = i32(v10)
    t[off + 11usize * st] = i32(v11)
    t[off + 12usize * st] = i32(v12)
    t[off + 13usize * st] = i32(v13)
    t[off + 14usize * st] = i32(v14)
    t[off + 15usize * st] = i32(v15)
    t[off + 16usize * st] = i32(v16)
    t[off + 17usize * st] = i32(v17)
    t[off + 18usize * st] = i32(v18)
    t[off + 19usize * st] = i32(v19)
    t[off + 20usize * st] = i32(v20)
    t[off + 21usize * st] = i32(v21)
    t[off + 22usize * st] = i32(v22)
    t[off + 23usize * st] = i32(v23)
    t[off + 24usize * st] = i32(v24)
    t[off + 25usize * st] = i32(v25)
    t[off + 26usize * st] = i32(v26)
    t[off + 27usize * st] = i32(v27)
    t[off + 28usize * st] = i32(v28)
    t[off + 29usize * st] = i32(v29)
    t[off + 30usize * st] = i32(v30)
    t[off + 31usize * st] = i32(v31)
    }
}

fn idct64_k32(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi: i64 = (1i64 << (r - 1u32)) - 1i64
    let lo: i64 = 0i64 - (1i64 << (r - 1u32))
    var tx: i64 = 0i64
    var ty: i64 = 0i64
    var v0: i64 = i64(t[off + 0usize * st])
    var v1: i64 = 0i64
    var v2: i64 = i64(t[off + 16usize * st])
    var v3: i64 = 0i64
    var v4: i64 = i64(t[off + 8usize * st])
    var v5: i64 = 0i64
    var v6: i64 = i64(t[off + 24usize * st])
    var v7: i64 = 0i64
    var v8: i64 = i64(t[off + 4usize * st])
    var v9: i64 = 0i64
    var v10: i64 = i64(t[off + 20usize * st])
    var v11: i64 = 0i64
    var v12: i64 = i64(t[off + 12usize * st])
    var v13: i64 = 0i64
    var v14: i64 = i64(t[off + 28usize * st])
    var v15: i64 = 0i64
    var v16: i64 = i64(t[off + 2usize * st])
    var v17: i64 = 0i64
    var v18: i64 = i64(t[off + 18usize * st])
    var v19: i64 = 0i64
    var v20: i64 = i64(t[off + 10usize * st])
    var v21: i64 = 0i64
    var v22: i64 = i64(t[off + 26usize * st])
    var v23: i64 = 0i64
    var v24: i64 = i64(t[off + 6usize * st])
    var v25: i64 = 0i64
    var v26: i64 = i64(t[off + 22usize * st])
    var v27: i64 = 0i64
    var v28: i64 = i64(t[off + 14usize * st])
    var v29: i64 = 0i64
    var v30: i64 = i64(t[off + 30usize * st])
    var v31: i64 = 0i64
    var v32: i64 = i64(t[off + 1usize * st])
    var v33: i64 = 0i64
    var v34: i64 = i64(t[off + 17usize * st])
    var v35: i64 = 0i64
    var v36: i64 = i64(t[off + 9usize * st])
    var v37: i64 = 0i64
    var v38: i64 = i64(t[off + 25usize * st])
    var v39: i64 = 0i64
    var v40: i64 = i64(t[off + 5usize * st])
    var v41: i64 = 0i64
    var v42: i64 = i64(t[off + 21usize * st])
    var v43: i64 = 0i64
    var v44: i64 = i64(t[off + 13usize * st])
    var v45: i64 = 0i64
    var v46: i64 = i64(t[off + 29usize * st])
    var v47: i64 = 0i64
    var v48: i64 = i64(t[off + 3usize * st])
    var v49: i64 = 0i64
    var v50: i64 = i64(t[off + 19usize * st])
    var v51: i64 = 0i64
    var v52: i64 = i64(t[off + 11usize * st])
    var v53: i64 = 0i64
    var v54: i64 = i64(t[off + 27usize * st])
    var v55: i64 = 0i64
    var v56: i64 = i64(t[off + 7usize * st])
    var v57: i64 = 0i64
    var v58: i64 = i64(t[off + 23usize * st])
    var v59: i64 = 0i64
    var v60: i64 = i64(t[off + 15usize * st])
    var v61: i64 = 0i64
    var v62: i64 = i64(t[off + 31usize * st])
    var v63: i64 = 0i64
    tx = (2048i64 + v32 * 101i64) >> 12u32
    ty = (2048i64 + v32 * 4095i64) >> 12u32
    v32 = tx
    v63 = ty
    tx = (2048i64 - v62 * 2824i64) >> 12u32
    ty = (2048i64 + v62 * 2967i64) >> 12u32
    v33 = tx
    v62 = ty
    tx = (2048i64 + v34 * 1660i64) >> 12u32
    ty = (2048i64 + v34 * 3745i64) >> 12u32
    v34 = tx
    v61 = ty
    tx = (2048i64 - v60 * 1474i64) >> 12u32
    ty = (2048i64 + v60 * 3822i64) >> 12u32
    v35 = tx
    v60 = ty
    tx = (2048i64 + v36 * 897i64) >> 12u32
    ty = (2048i64 + v36 * 3996i64) >> 12u32
    v36 = tx
    v59 = ty
    tx = (2048i64 - v58 * 2191i64) >> 12u32
    ty = (2048i64 + v58 * 3461i64) >> 12u32
    v37 = tx
    v58 = ty
    tx = (2048i64 + v38 * 2359i64) >> 12u32
    ty = (2048i64 + v38 * 3349i64) >> 12u32
    v38 = tx
    v57 = ty
    tx = (2048i64 - v56 * 700i64) >> 12u32
    ty = (2048i64 + v56 * 4036i64) >> 12u32
    v39 = tx
    v56 = ty
    tx = (2048i64 + v40 * 501i64) >> 12u32
    ty = (2048i64 + v40 * 4065i64) >> 12u32
    v40 = tx
    v55 = ty
    tx = (2048i64 - v54 * 2520i64) >> 12u32
    ty = (2048i64 + v54 * 3229i64) >> 12u32
    v41 = tx
    v54 = ty
    tx = (2048i64 + v42 * 2019i64) >> 12u32
    ty = (2048i64 + v42 * 3564i64) >> 12u32
    v42 = tx
    v53 = ty
    tx = (2048i64 - v52 * 1092i64) >> 12u32
    ty = (2048i64 + v52 * 3948i64) >> 12u32
    v43 = tx
    v52 = ty
    tx = (2048i64 + v44 * 1285i64) >> 12u32
    ty = (2048i64 + v44 * 3889i64) >> 12u32
    v44 = tx
    v51 = ty
    tx = (2048i64 - v50 * 1842i64) >> 12u32
    ty = (2048i64 + v50 * 3659i64) >> 12u32
    v45 = tx
    v50 = ty
    tx = (2048i64 + v46 * 2675i64) >> 12u32
    ty = (2048i64 + v46 * 3102i64) >> 12u32
    v46 = tx
    v49 = ty
    tx = (2048i64 - v48 * 301i64) >> 12u32
    ty = (2048i64 + v48 * 4085i64) >> 12u32
    v47 = tx
    v48 = ty
    tx = (2048i64 + v16 * 201i64) >> 12u32
    ty = (2048i64 + v16 * 4091i64) >> 12u32
    v16 = tx
    v31 = ty
    tx = (2048i64 - v30 * 2751i64) >> 12u32
    ty = (2048i64 + v30 * 3035i64) >> 12u32
    v17 = tx
    v30 = ty
    tx = (2048i64 + v18 * 1751i64) >> 12u32
    ty = (2048i64 + v18 * 3703i64) >> 12u32
    v18 = tx
    v29 = ty
    tx = (2048i64 - v28 * 1380i64) >> 12u32
    ty = (2048i64 + v28 * 3857i64) >> 12u32
    v19 = tx
    v28 = ty
    tx = (2048i64 + v20 * 995i64) >> 12u32
    ty = (2048i64 + v20 * 3973i64) >> 12u32
    v20 = tx
    v27 = ty
    tx = (2048i64 - v26 * 2106i64) >> 12u32
    ty = (2048i64 + v26 * 3513i64) >> 12u32
    v21 = tx
    v26 = ty
    tx = (2048i64 + v22 * 2440i64) >> 12u32
    ty = (2048i64 + v22 * 3290i64) >> 12u32
    v22 = tx
    v25 = ty
    tx = (2048i64 - v24 * 601i64) >> 12u32
    ty = (2048i64 + v24 * 4052i64) >> 12u32
    v23 = tx
    v24 = ty
    tx = v32 + v33
    ty = v32 - v33
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v32 = tx
    v33 = ty
    tx = v35 + v34
    ty = v35 - v34
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v35 = tx
    v34 = ty
    tx = v36 + v37
    ty = v36 - v37
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v36 = tx
    v37 = ty
    tx = v39 + v38
    ty = v39 - v38
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v39 = tx
    v38 = ty
    tx = v40 + v41
    ty = v40 - v41
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v40 = tx
    v41 = ty
    tx = v43 + v42
    ty = v43 - v42
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v43 = tx
    v42 = ty
    tx = v44 + v45
    ty = v44 - v45
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v44 = tx
    v45 = ty
    tx = v47 + v46
    ty = v47 - v46
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v47 = tx
    v46 = ty
    tx = v48 + v49
    ty = v48 - v49
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v48 = tx
    v49 = ty
    tx = v51 + v50
    ty = v51 - v50
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v51 = tx
    v50 = ty
    tx = v52 + v53
    ty = v52 - v53
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v52 = tx
    v53 = ty
    tx = v55 + v54
    ty = v55 - v54
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v55 = tx
    v54 = ty
    tx = v56 + v57
    ty = v56 - v57
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v56 = tx
    v57 = ty
    tx = v59 + v58
    ty = v59 - v58
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v59 = tx
    v58 = ty
    tx = v60 + v61
    ty = v60 - v61
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v60 = tx
    v61 = ty
    tx = v63 + v62
    ty = v63 - v62
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v63 = tx
    v62 = ty
    tx = (2048i64 + v8 * 401i64) >> 12u32
    ty = (2048i64 + v8 * 4076i64) >> 12u32
    v8 = tx
    v15 = ty
    tx = (2048i64 - v14 * 2598i64) >> 12u32
    ty = (2048i64 + v14 * 3166i64) >> 12u32
    v9 = tx
    v14 = ty
    tx = (2048i64 + v10 * 1931i64) >> 12u32
    ty = (2048i64 + v10 * 3612i64) >> 12u32
    v10 = tx
    v13 = ty
    tx = (2048i64 - v12 * 1189i64) >> 12u32
    ty = (2048i64 + v12 * 3920i64) >> 12u32
    v11 = tx
    v12 = ty
    tx = v16 + v17
    ty = v16 - v17
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v16 = tx
    v17 = ty
    tx = v19 + v18
    ty = v19 - v18
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v19 = tx
    v18 = ty
    tx = v20 + v21
    ty = v20 - v21
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v20 = tx
    v21 = ty
    tx = v23 + v22
    ty = v23 - v22
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v23 = tx
    v22 = ty
    tx = v24 + v25
    ty = v24 - v25
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v24 = tx
    v25 = ty
    tx = v27 + v26
    ty = v27 - v26
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v27 = tx
    v26 = ty
    tx = v28 + v29
    ty = v28 - v29
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v28 = tx
    v29 = ty
    tx = v31 + v30
    ty = v31 - v30
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v31 = tx
    v30 = ty
    tx = (2048i64 + v62 * 401i64 - v33 * 4076i64) >> 12u32
    ty = (2048i64 + v62 * 4076i64 + v33 * 401i64) >> 12u32
    v62 = ty
    v33 = tx
    tx = (2048i64 - v61 * 4076i64 - v34 * 401i64) >> 12u32
    ty = (2048i64 + v61 * 401i64 - v34 * 4076i64) >> 12u32
    v61 = ty
    v34 = tx
    tx = (2048i64 + v58 * 3166i64 - v37 * 2598i64) >> 12u32
    ty = (2048i64 + v58 * 2598i64 + v37 * 3166i64) >> 12u32
    v58 = ty
    v37 = tx
    tx = (2048i64 - v57 * 2598i64 - v38 * 3166i64) >> 12u32
    ty = (2048i64 + v57 * 3166i64 - v38 * 2598i64) >> 12u32
    v57 = ty
    v38 = tx
    tx = (2048i64 + v54 * 1931i64 - v41 * 3612i64) >> 12u32
    ty = (2048i64 + v54 * 3612i64 + v41 * 1931i64) >> 12u32
    v54 = ty
    v41 = tx
    tx = (2048i64 - v53 * 3612i64 - v42 * 1931i64) >> 12u32
    ty = (2048i64 + v53 * 1931i64 - v42 * 3612i64) >> 12u32
    v53 = ty
    v42 = tx
    tx = (2048i64 + v50 * 3920i64 - v45 * 1189i64) >> 12u32
    ty = (2048i64 + v50 * 1189i64 + v45 * 3920i64) >> 12u32
    v50 = ty
    v45 = tx
    tx = (2048i64 - v49 * 1189i64 - v46 * 3920i64) >> 12u32
    ty = (2048i64 + v49 * 3920i64 - v46 * 1189i64) >> 12u32
    v49 = ty
    v46 = tx
    tx = (2048i64 + v4 * 799i64) >> 12u32
    ty = (2048i64 + v4 * 4017i64) >> 12u32
    v4 = tx
    v7 = ty
    tx = (2048i64 - v6 * 2276i64) >> 12u32
    ty = (2048i64 + v6 * 3406i64) >> 12u32
    v5 = tx
    v6 = ty
    tx = v8 + v9
    ty = v8 - v9
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v8 = tx
    v9 = ty
    tx = v11 + v10
    ty = v11 - v10
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v11 = tx
    v10 = ty
    tx = v12 + v13
    ty = v12 - v13
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v12 = tx
    v13 = ty
    tx = v15 + v14
    ty = v15 - v14
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v15 = tx
    v14 = ty
    tx = (2048i64 + v30 * 799i64 - v17 * 4017i64) >> 12u32
    ty = (2048i64 + v30 * 4017i64 + v17 * 799i64) >> 12u32
    v30 = ty
    v17 = tx
    tx = (2048i64 - v29 * 4017i64 - v18 * 799i64) >> 12u32
    ty = (2048i64 + v29 * 799i64 - v18 * 4017i64) >> 12u32
    v29 = ty
    v18 = tx
    tx = (2048i64 + v26 * 3406i64 - v21 * 2276i64) >> 12u32
    ty = (2048i64 + v26 * 2276i64 + v21 * 3406i64) >> 12u32
    v26 = ty
    v21 = tx
    tx = (2048i64 - v25 * 2276i64 - v22 * 3406i64) >> 12u32
    ty = (2048i64 + v25 * 3406i64 - v22 * 2276i64) >> 12u32
    v25 = ty
    v22 = tx
    tx = v32 + v35
    ty = v32 - v35
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v32 = tx
    v35 = ty
    tx = v33 + v34
    ty = v33 - v34
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v33 = tx
    v34 = ty
    tx = v39 + v36
    ty = v39 - v36
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v39 = tx
    v36 = ty
    tx = v38 + v37
    ty = v38 - v37
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v38 = tx
    v37 = ty
    tx = v40 + v43
    ty = v40 - v43
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v40 = tx
    v43 = ty
    tx = v41 + v42
    ty = v41 - v42
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v41 = tx
    v42 = ty
    tx = v47 + v44
    ty = v47 - v44
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v47 = tx
    v44 = ty
    tx = v46 + v45
    ty = v46 - v45
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v46 = tx
    v45 = ty
    tx = v48 + v51
    ty = v48 - v51
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v48 = tx
    v51 = ty
    tx = v49 + v50
    ty = v49 - v50
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v49 = tx
    v50 = ty
    tx = v55 + v52
    ty = v55 - v52
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v55 = tx
    v52 = ty
    tx = v54 + v53
    ty = v54 - v53
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v54 = tx
    v53 = ty
    tx = v56 + v59
    ty = v56 - v59
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v56 = tx
    v59 = ty
    tx = v57 + v58
    ty = v57 - v58
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v57 = tx
    v58 = ty
    tx = v63 + v60
    ty = v63 - v60
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v63 = tx
    v60 = ty
    tx = v62 + v61
    ty = v62 - v61
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v62 = tx
    v61 = ty
    tx = (2048i64 + v0 * 2896i64) >> 12u32
    ty = (2048i64 + v0 * 2896i64) >> 12u32
    v0 = ty
    v1 = tx
    tx = (2048i64 + v2 * 1567i64) >> 12u32
    ty = (2048i64 + v2 * 3784i64) >> 12u32
    v2 = tx
    v3 = ty
    tx = v4 + v5
    ty = v4 - v5
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v5 = ty
    tx = v7 + v6
    ty = v7 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v7 = tx
    v6 = ty
    tx = (2048i64 + v14 * 1567i64 - v9 * 3784i64) >> 12u32
    ty = (2048i64 + v14 * 3784i64 + v9 * 1567i64) >> 12u32
    v14 = ty
    v9 = tx
    tx = (2048i64 - v13 * 3784i64 - v10 * 1567i64) >> 12u32
    ty = (2048i64 + v13 * 1567i64 - v10 * 3784i64) >> 12u32
    v13 = ty
    v10 = tx
    tx = v16 + v19
    ty = v16 - v19
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v16 = tx
    v19 = ty
    tx = v17 + v18
    ty = v17 - v18
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v17 = tx
    v18 = ty
    tx = v23 + v20
    ty = v23 - v20
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v23 = tx
    v20 = ty
    tx = v22 + v21
    ty = v22 - v21
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v22 = tx
    v21 = ty
    tx = v24 + v27
    ty = v24 - v27
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v24 = tx
    v27 = ty
    tx = v25 + v26
    ty = v25 - v26
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v25 = tx
    v26 = ty
    tx = v31 + v28
    ty = v31 - v28
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v31 = tx
    v28 = ty
    tx = v30 + v29
    ty = v30 - v29
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v30 = tx
    v29 = ty
    tx = (2048i64 + v61 * 799i64 - v34 * 4017i64) >> 12u32
    ty = (2048i64 + v61 * 4017i64 + v34 * 799i64) >> 12u32
    v61 = ty
    v34 = tx
    tx = (2048i64 + v60 * 799i64 - v35 * 4017i64) >> 12u32
    ty = (2048i64 + v60 * 4017i64 + v35 * 799i64) >> 12u32
    v60 = ty
    v35 = tx
    tx = (2048i64 - v59 * 4017i64 - v36 * 799i64) >> 12u32
    ty = (2048i64 + v59 * 799i64 - v36 * 4017i64) >> 12u32
    v59 = ty
    v36 = tx
    tx = (2048i64 - v58 * 4017i64 - v37 * 799i64) >> 12u32
    ty = (2048i64 + v58 * 799i64 - v37 * 4017i64) >> 12u32
    v58 = ty
    v37 = tx
    tx = (2048i64 + v53 * 3406i64 - v42 * 2276i64) >> 12u32
    ty = (2048i64 + v53 * 2276i64 + v42 * 3406i64) >> 12u32
    v53 = ty
    v42 = tx
    tx = (2048i64 + v52 * 3406i64 - v43 * 2276i64) >> 12u32
    ty = (2048i64 + v52 * 2276i64 + v43 * 3406i64) >> 12u32
    v52 = ty
    v43 = tx
    tx = (2048i64 - v51 * 2276i64 - v44 * 3406i64) >> 12u32
    ty = (2048i64 + v51 * 3406i64 - v44 * 2276i64) >> 12u32
    v51 = ty
    v44 = tx
    tx = (2048i64 - v50 * 2276i64 - v45 * 3406i64) >> 12u32
    ty = (2048i64 + v50 * 3406i64 - v45 * 2276i64) >> 12u32
    v50 = ty
    v45 = tx
    tx = v0 + v3
    ty = v0 - v3
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v3 = ty
    tx = v1 + v2
    ty = v1 - v2
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v2 = ty
    tx = (2048i64 + v6 * 2896i64 - v5 * 2896i64) >> 12u32
    ty = (2048i64 + v6 * 2896i64 + v5 * 2896i64) >> 12u32
    v6 = ty
    v5 = tx
    tx = v8 + v11
    ty = v8 - v11
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v8 = tx
    v11 = ty
    tx = v9 + v10
    ty = v9 - v10
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v9 = tx
    v10 = ty
    tx = v15 + v12
    ty = v15 - v12
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v15 = tx
    v12 = ty
    tx = v14 + v13
    ty = v14 - v13
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v14 = tx
    v13 = ty
    tx = (2048i64 + v29 * 1567i64 - v18 * 3784i64) >> 12u32
    ty = (2048i64 + v29 * 3784i64 + v18 * 1567i64) >> 12u32
    v29 = ty
    v18 = tx
    tx = (2048i64 + v28 * 1567i64 - v19 * 3784i64) >> 12u32
    ty = (2048i64 + v28 * 3784i64 + v19 * 1567i64) >> 12u32
    v28 = ty
    v19 = tx
    tx = (2048i64 - v27 * 3784i64 - v20 * 1567i64) >> 12u32
    ty = (2048i64 + v27 * 1567i64 - v20 * 3784i64) >> 12u32
    v27 = ty
    v20 = tx
    tx = (2048i64 - v26 * 3784i64 - v21 * 1567i64) >> 12u32
    ty = (2048i64 + v26 * 1567i64 - v21 * 3784i64) >> 12u32
    v26 = ty
    v21 = tx
    tx = v32 + v39
    ty = v32 - v39
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v32 = tx
    v39 = ty
    tx = v33 + v38
    ty = v33 - v38
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v33 = tx
    v38 = ty
    tx = v34 + v37
    ty = v34 - v37
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v34 = tx
    v37 = ty
    tx = v35 + v36
    ty = v35 - v36
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v35 = tx
    v36 = ty
    tx = v47 + v40
    ty = v47 - v40
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v47 = tx
    v40 = ty
    tx = v46 + v41
    ty = v46 - v41
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v46 = tx
    v41 = ty
    tx = v45 + v42
    ty = v45 - v42
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v45 = tx
    v42 = ty
    tx = v44 + v43
    ty = v44 - v43
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v44 = tx
    v43 = ty
    tx = v48 + v55
    ty = v48 - v55
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v48 = tx
    v55 = ty
    tx = v49 + v54
    ty = v49 - v54
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v49 = tx
    v54 = ty
    tx = v50 + v53
    ty = v50 - v53
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v50 = tx
    v53 = ty
    tx = v51 + v52
    ty = v51 - v52
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v51 = tx
    v52 = ty
    tx = v63 + v56
    ty = v63 - v56
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v63 = tx
    v56 = ty
    tx = v62 + v57
    ty = v62 - v57
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v62 = tx
    v57 = ty
    tx = v61 + v58
    ty = v61 - v58
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v61 = tx
    v58 = ty
    tx = v60 + v59
    ty = v60 - v59
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v60 = tx
    v59 = ty
    tx = v0 + v7
    ty = v0 - v7
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v7 = ty
    tx = v1 + v6
    ty = v1 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v6 = ty
    tx = v2 + v5
    ty = v2 - v5
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v5 = ty
    tx = v3 + v4
    ty = v3 - v4
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v4 = ty
    tx = (2048i64 + v13 * 2896i64 - v10 * 2896i64) >> 12u32
    ty = (2048i64 + v13 * 2896i64 + v10 * 2896i64) >> 12u32
    v13 = ty
    v10 = tx
    tx = (2048i64 + v12 * 2896i64 - v11 * 2896i64) >> 12u32
    ty = (2048i64 + v12 * 2896i64 + v11 * 2896i64) >> 12u32
    v12 = ty
    v11 = tx
    tx = v16 + v23
    ty = v16 - v23
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v16 = tx
    v23 = ty
    tx = v17 + v22
    ty = v17 - v22
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v17 = tx
    v22 = ty
    tx = v18 + v21
    ty = v18 - v21
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v18 = tx
    v21 = ty
    tx = v19 + v20
    ty = v19 - v20
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v19 = tx
    v20 = ty
    tx = v31 + v24
    ty = v31 - v24
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v31 = tx
    v24 = ty
    tx = v30 + v25
    ty = v30 - v25
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v30 = tx
    v25 = ty
    tx = v29 + v26
    ty = v29 - v26
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v29 = tx
    v26 = ty
    tx = v28 + v27
    ty = v28 - v27
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v28 = tx
    v27 = ty
    tx = (2048i64 + v59 * 1567i64 - v36 * 3784i64) >> 12u32
    ty = (2048i64 + v59 * 3784i64 + v36 * 1567i64) >> 12u32
    v59 = ty
    v36 = tx
    tx = (2048i64 + v58 * 1567i64 - v37 * 3784i64) >> 12u32
    ty = (2048i64 + v58 * 3784i64 + v37 * 1567i64) >> 12u32
    v58 = ty
    v37 = tx
    tx = (2048i64 + v57 * 1567i64 - v38 * 3784i64) >> 12u32
    ty = (2048i64 + v57 * 3784i64 + v38 * 1567i64) >> 12u32
    v57 = ty
    v38 = tx
    tx = (2048i64 + v56 * 1567i64 - v39 * 3784i64) >> 12u32
    ty = (2048i64 + v56 * 3784i64 + v39 * 1567i64) >> 12u32
    v56 = ty
    v39 = tx
    tx = (2048i64 - v55 * 3784i64 - v40 * 1567i64) >> 12u32
    ty = (2048i64 + v55 * 1567i64 - v40 * 3784i64) >> 12u32
    v55 = ty
    v40 = tx
    tx = (2048i64 - v54 * 3784i64 - v41 * 1567i64) >> 12u32
    ty = (2048i64 + v54 * 1567i64 - v41 * 3784i64) >> 12u32
    v54 = ty
    v41 = tx
    tx = (2048i64 - v53 * 3784i64 - v42 * 1567i64) >> 12u32
    ty = (2048i64 + v53 * 1567i64 - v42 * 3784i64) >> 12u32
    v53 = ty
    v42 = tx
    tx = (2048i64 - v52 * 3784i64 - v43 * 1567i64) >> 12u32
    ty = (2048i64 + v52 * 1567i64 - v43 * 3784i64) >> 12u32
    v52 = ty
    v43 = tx
    tx = v0 + v15
    ty = v0 - v15
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v15 = ty
    tx = v1 + v14
    ty = v1 - v14
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v14 = ty
    tx = v2 + v13
    ty = v2 - v13
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v13 = ty
    tx = v3 + v12
    ty = v3 - v12
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v12 = ty
    tx = v4 + v11
    ty = v4 - v11
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v11 = ty
    tx = v5 + v10
    ty = v5 - v10
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v5 = tx
    v10 = ty
    tx = v6 + v9
    ty = v6 - v9
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v6 = tx
    v9 = ty
    tx = v7 + v8
    ty = v7 - v8
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v7 = tx
    v8 = ty
    tx = (2048i64 + v27 * 2896i64 - v20 * 2896i64) >> 12u32
    ty = (2048i64 + v27 * 2896i64 + v20 * 2896i64) >> 12u32
    v27 = ty
    v20 = tx
    tx = (2048i64 + v26 * 2896i64 - v21 * 2896i64) >> 12u32
    ty = (2048i64 + v26 * 2896i64 + v21 * 2896i64) >> 12u32
    v26 = ty
    v21 = tx
    tx = (2048i64 + v25 * 2896i64 - v22 * 2896i64) >> 12u32
    ty = (2048i64 + v25 * 2896i64 + v22 * 2896i64) >> 12u32
    v25 = ty
    v22 = tx
    tx = (2048i64 + v24 * 2896i64 - v23 * 2896i64) >> 12u32
    ty = (2048i64 + v24 * 2896i64 + v23 * 2896i64) >> 12u32
    v24 = ty
    v23 = tx
    tx = v32 + v47
    ty = v32 - v47
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v32 = tx
    v47 = ty
    tx = v63 + v48
    ty = v63 - v48
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v63 = tx
    v48 = ty
    tx = v33 + v46
    ty = v33 - v46
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v33 = tx
    v46 = ty
    tx = v62 + v49
    ty = v62 - v49
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v62 = tx
    v49 = ty
    tx = v34 + v45
    ty = v34 - v45
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v34 = tx
    v45 = ty
    tx = v61 + v50
    ty = v61 - v50
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v61 = tx
    v50 = ty
    tx = v35 + v44
    ty = v35 - v44
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v35 = tx
    v44 = ty
    tx = v60 + v51
    ty = v60 - v51
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v60 = tx
    v51 = ty
    tx = v36 + v43
    ty = v36 - v43
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v36 = tx
    v43 = ty
    tx = v59 + v52
    ty = v59 - v52
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v59 = tx
    v52 = ty
    tx = v37 + v42
    ty = v37 - v42
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v37 = tx
    v42 = ty
    tx = v58 + v53
    ty = v58 - v53
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v58 = tx
    v53 = ty
    tx = v38 + v41
    ty = v38 - v41
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v38 = tx
    v41 = ty
    tx = v57 + v54
    ty = v57 - v54
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v57 = tx
    v54 = ty
    tx = v39 + v40
    ty = v39 - v40
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v39 = tx
    v40 = ty
    tx = v56 + v55
    ty = v56 - v55
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v56 = tx
    v55 = ty
    tx = v0 + v31
    ty = v0 - v31
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v31 = ty
    tx = v1 + v30
    ty = v1 - v30
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v30 = ty
    tx = v2 + v29
    ty = v2 - v29
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v29 = ty
    tx = v3 + v28
    ty = v3 - v28
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v28 = ty
    tx = v4 + v27
    ty = v4 - v27
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v27 = ty
    tx = v5 + v26
    ty = v5 - v26
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v5 = tx
    v26 = ty
    tx = v6 + v25
    ty = v6 - v25
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v6 = tx
    v25 = ty
    tx = v7 + v24
    ty = v7 - v24
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v7 = tx
    v24 = ty
    tx = v8 + v23
    ty = v8 - v23
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v8 = tx
    v23 = ty
    tx = v9 + v22
    ty = v9 - v22
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v9 = tx
    v22 = ty
    tx = v10 + v21
    ty = v10 - v21
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v10 = tx
    v21 = ty
    tx = v11 + v20
    ty = v11 - v20
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v11 = tx
    v20 = ty
    tx = v12 + v19
    ty = v12 - v19
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v12 = tx
    v19 = ty
    tx = v13 + v18
    ty = v13 - v18
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v13 = tx
    v18 = ty
    tx = v14 + v17
    ty = v14 - v17
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v14 = tx
    v17 = ty
    tx = v15 + v16
    ty = v15 - v16
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v15 = tx
    v16 = ty
    tx = (2048i64 + v55 * 2896i64 - v40 * 2896i64) >> 12u32
    ty = (2048i64 + v55 * 2896i64 + v40 * 2896i64) >> 12u32
    v55 = ty
    v40 = tx
    tx = (2048i64 + v54 * 2896i64 - v41 * 2896i64) >> 12u32
    ty = (2048i64 + v54 * 2896i64 + v41 * 2896i64) >> 12u32
    v54 = ty
    v41 = tx
    tx = (2048i64 + v53 * 2896i64 - v42 * 2896i64) >> 12u32
    ty = (2048i64 + v53 * 2896i64 + v42 * 2896i64) >> 12u32
    v53 = ty
    v42 = tx
    tx = (2048i64 + v52 * 2896i64 - v43 * 2896i64) >> 12u32
    ty = (2048i64 + v52 * 2896i64 + v43 * 2896i64) >> 12u32
    v52 = ty
    v43 = tx
    tx = (2048i64 + v51 * 2896i64 - v44 * 2896i64) >> 12u32
    ty = (2048i64 + v51 * 2896i64 + v44 * 2896i64) >> 12u32
    v51 = ty
    v44 = tx
    tx = (2048i64 + v50 * 2896i64 - v45 * 2896i64) >> 12u32
    ty = (2048i64 + v50 * 2896i64 + v45 * 2896i64) >> 12u32
    v50 = ty
    v45 = tx
    tx = (2048i64 + v49 * 2896i64 - v46 * 2896i64) >> 12u32
    ty = (2048i64 + v49 * 2896i64 + v46 * 2896i64) >> 12u32
    v49 = ty
    v46 = tx
    tx = (2048i64 + v48 * 2896i64 - v47 * 2896i64) >> 12u32
    ty = (2048i64 + v48 * 2896i64 + v47 * 2896i64) >> 12u32
    v48 = ty
    v47 = tx
    tx = v0 + v63
    ty = v0 - v63
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v63 = ty
    tx = v1 + v62
    ty = v1 - v62
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v62 = ty
    tx = v2 + v61
    ty = v2 - v61
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v61 = ty
    tx = v3 + v60
    ty = v3 - v60
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v60 = ty
    tx = v4 + v59
    ty = v4 - v59
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v59 = ty
    tx = v5 + v58
    ty = v5 - v58
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v5 = tx
    v58 = ty
    tx = v6 + v57
    ty = v6 - v57
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v6 = tx
    v57 = ty
    tx = v7 + v56
    ty = v7 - v56
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v7 = tx
    v56 = ty
    tx = v8 + v55
    ty = v8 - v55
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v8 = tx
    v55 = ty
    tx = v9 + v54
    ty = v9 - v54
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v9 = tx
    v54 = ty
    tx = v10 + v53
    ty = v10 - v53
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v10 = tx
    v53 = ty
    tx = v11 + v52
    ty = v11 - v52
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v11 = tx
    v52 = ty
    tx = v12 + v51
    ty = v12 - v51
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v12 = tx
    v51 = ty
    tx = v13 + v50
    ty = v13 - v50
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v13 = tx
    v50 = ty
    tx = v14 + v49
    ty = v14 - v49
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v14 = tx
    v49 = ty
    tx = v15 + v48
    ty = v15 - v48
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v15 = tx
    v48 = ty
    tx = v16 + v47
    ty = v16 - v47
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v16 = tx
    v47 = ty
    tx = v17 + v46
    ty = v17 - v46
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v17 = tx
    v46 = ty
    tx = v18 + v45
    ty = v18 - v45
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v18 = tx
    v45 = ty
    tx = v19 + v44
    ty = v19 - v44
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v19 = tx
    v44 = ty
    tx = v20 + v43
    ty = v20 - v43
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v20 = tx
    v43 = ty
    tx = v21 + v42
    ty = v21 - v42
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v21 = tx
    v42 = ty
    tx = v22 + v41
    ty = v22 - v41
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v22 = tx
    v41 = ty
    tx = v23 + v40
    ty = v23 - v40
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v23 = tx
    v40 = ty
    tx = v24 + v39
    ty = v24 - v39
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v24 = tx
    v39 = ty
    tx = v25 + v38
    ty = v25 - v38
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v25 = tx
    v38 = ty
    tx = v26 + v37
    ty = v26 - v37
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v26 = tx
    v37 = ty
    tx = v27 + v36
    ty = v27 - v36
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v27 = tx
    v36 = ty
    tx = v28 + v35
    ty = v28 - v35
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v28 = tx
    v35 = ty
    tx = v29 + v34
    ty = v29 - v34
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v29 = tx
    v34 = ty
    tx = v30 + v33
    ty = v30 - v33
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v30 = tx
    v33 = ty
    tx = v31 + v32
    ty = v31 - v32
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v31 = tx
    v32 = ty
    t[off + 0usize * st] = i32(v0)
    t[off + 1usize * st] = i32(v1)
    t[off + 2usize * st] = i32(v2)
    t[off + 3usize * st] = i32(v3)
    t[off + 4usize * st] = i32(v4)
    t[off + 5usize * st] = i32(v5)
    t[off + 6usize * st] = i32(v6)
    t[off + 7usize * st] = i32(v7)
    t[off + 8usize * st] = i32(v8)
    t[off + 9usize * st] = i32(v9)
    t[off + 10usize * st] = i32(v10)
    t[off + 11usize * st] = i32(v11)
    t[off + 12usize * st] = i32(v12)
    t[off + 13usize * st] = i32(v13)
    t[off + 14usize * st] = i32(v14)
    t[off + 15usize * st] = i32(v15)
    t[off + 16usize * st] = i32(v16)
    t[off + 17usize * st] = i32(v17)
    t[off + 18usize * st] = i32(v18)
    t[off + 19usize * st] = i32(v19)
    t[off + 20usize * st] = i32(v20)
    t[off + 21usize * st] = i32(v21)
    t[off + 22usize * st] = i32(v22)
    t[off + 23usize * st] = i32(v23)
    t[off + 24usize * st] = i32(v24)
    t[off + 25usize * st] = i32(v25)
    t[off + 26usize * st] = i32(v26)
    t[off + 27usize * st] = i32(v27)
    t[off + 28usize * st] = i32(v28)
    t[off + 29usize * st] = i32(v29)
    t[off + 30usize * st] = i32(v30)
    t[off + 31usize * st] = i32(v31)
    t[off + 32usize * st] = i32(v32)
    t[off + 33usize * st] = i32(v33)
    t[off + 34usize * st] = i32(v34)
    t[off + 35usize * st] = i32(v35)
    t[off + 36usize * st] = i32(v36)
    t[off + 37usize * st] = i32(v37)
    t[off + 38usize * st] = i32(v38)
    t[off + 39usize * st] = i32(v39)
    t[off + 40usize * st] = i32(v40)
    t[off + 41usize * st] = i32(v41)
    t[off + 42usize * st] = i32(v42)
    t[off + 43usize * st] = i32(v43)
    t[off + 44usize * st] = i32(v44)
    t[off + 45usize * st] = i32(v45)
    t[off + 46usize * st] = i32(v46)
    t[off + 47usize * st] = i32(v47)
    t[off + 48usize * st] = i32(v48)
    t[off + 49usize * st] = i32(v49)
    t[off + 50usize * st] = i32(v50)
    t[off + 51usize * st] = i32(v51)
    t[off + 52usize * st] = i32(v52)
    t[off + 53usize * st] = i32(v53)
    t[off + 54usize * st] = i32(v54)
    t[off + 55usize * st] = i32(v55)
    t[off + 56usize * st] = i32(v56)
    t[off + 57usize * st] = i32(v57)
    t[off + 58usize * st] = i32(v58)
    t[off + 59usize * st] = i32(v59)
    t[off + 60usize * st] = i32(v60)
    t[off + 61usize * st] = i32(v61)
    t[off + 62usize * st] = i32(v62)
    t[off + 63usize * st] = i32(v63)
    }
}

fn fadst8(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi: i64 = (1i64 << (r - 1u32)) - 1i64
    let lo: i64 = 0i64 - (1i64 << (r - 1u32))
    var tx: i64 = 0i64
    var ty: i64 = 0i64
    var v0: i64 = i64(t[off + 7usize * st])
    var v1: i64 = i64(t[off + 0usize * st])
    var v2: i64 = i64(t[off + 5usize * st])
    var v3: i64 = i64(t[off + 2usize * st])
    var v4: i64 = i64(t[off + 3usize * st])
    var v5: i64 = i64(t[off + 4usize * st])
    var v6: i64 = i64(t[off + 1usize * st])
    var v7: i64 = i64(t[off + 6usize * st])
    tx = (2048i64 + v0 * 401i64 - v1 * 4076i64) >> 12u32
    ty = (2048i64 + v0 * 4076i64 + v1 * 401i64) >> 12u32
    v0 = ty
    v1 = tx
    tx = (2048i64 + v2 * 1931i64 - v3 * 3612i64) >> 12u32
    ty = (2048i64 + v2 * 3612i64 + v3 * 1931i64) >> 12u32
    v2 = ty
    v3 = tx
    tx = (2048i64 + v4 * 3166i64 - v5 * 2598i64) >> 12u32
    ty = (2048i64 + v4 * 2598i64 + v5 * 3166i64) >> 12u32
    v4 = ty
    v5 = tx
    tx = (2048i64 + v6 * 3920i64 - v7 * 1189i64) >> 12u32
    ty = (2048i64 + v6 * 1189i64 + v7 * 3920i64) >> 12u32
    v6 = ty
    v7 = tx
    tx = v0 + v4
    ty = v0 - v4
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v4 = ty
    tx = v1 + v5
    ty = v1 - v5
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v5 = ty
    tx = v2 + v6
    ty = v2 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v6 = ty
    tx = v3 + v7
    ty = v3 - v7
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v7 = ty
    tx = (2048i64 + v4 * 1567i64 - v5 * 3784i64) >> 12u32
    ty = (2048i64 + v4 * 3784i64 + v5 * 1567i64) >> 12u32
    v4 = ty
    v5 = tx
    tx = (2048i64 + v7 * 3784i64 - v6 * 1567i64) >> 12u32
    ty = (2048i64 + v7 * 1567i64 + v6 * 3784i64) >> 12u32
    v7 = ty
    v6 = tx
    tx = v0 + v2
    ty = v0 - v2
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v2 = ty
    tx = v4 + v6
    ty = v4 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v6 = ty
    tx = v1 + v3
    ty = v1 - v3
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v3 = ty
    tx = v5 + v7
    ty = v5 - v7
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v5 = tx
    v7 = ty
    tx = (2048i64 + v2 * 2896i64 - v3 * 2896i64) >> 12u32
    ty = (2048i64 + v2 * 2896i64 + v3 * 2896i64) >> 12u32
    v2 = ty
    v3 = tx
    tx = (2048i64 + v6 * 2896i64 - v7 * 2896i64) >> 12u32
    ty = (2048i64 + v6 * 2896i64 + v7 * 2896i64) >> 12u32
    v6 = ty
    v7 = tx
    t[off + 0usize * st] = i32(v0)
    t[off + 1usize * st] = i32(0i64 - v4)
    t[off + 2usize * st] = i32(v6)
    t[off + 3usize * st] = i32(0i64 - v2)
    t[off + 4usize * st] = i32(v3)
    t[off + 5usize * st] = i32(0i64 - v7)
    t[off + 6usize * st] = i32(v5)
    t[off + 7usize * st] = i32(0i64 - v1)
    }
}

fn fadst16(t: []i32, off: usize, st: usize, r: u32) {
    @nocheck {
    let hi: i64 = (1i64 << (r - 1u32)) - 1i64
    let lo: i64 = 0i64 - (1i64 << (r - 1u32))
    var tx: i64 = 0i64
    var ty: i64 = 0i64
    var v0: i64 = i64(t[off + 15usize * st])
    var v1: i64 = i64(t[off + 0usize * st])
    var v2: i64 = i64(t[off + 13usize * st])
    var v3: i64 = i64(t[off + 2usize * st])
    var v4: i64 = i64(t[off + 11usize * st])
    var v5: i64 = i64(t[off + 4usize * st])
    var v6: i64 = i64(t[off + 9usize * st])
    var v7: i64 = i64(t[off + 6usize * st])
    var v8: i64 = i64(t[off + 7usize * st])
    var v9: i64 = i64(t[off + 8usize * st])
    var v10: i64 = i64(t[off + 5usize * st])
    var v11: i64 = i64(t[off + 10usize * st])
    var v12: i64 = i64(t[off + 3usize * st])
    var v13: i64 = i64(t[off + 12usize * st])
    var v14: i64 = i64(t[off + 1usize * st])
    var v15: i64 = i64(t[off + 14usize * st])
    tx = (2048i64 + v0 * 201i64 - v1 * 4091i64) >> 12u32
    ty = (2048i64 + v0 * 4091i64 + v1 * 201i64) >> 12u32
    v0 = ty
    v1 = tx
    tx = (2048i64 + v2 * 995i64 - v3 * 3973i64) >> 12u32
    ty = (2048i64 + v2 * 3973i64 + v3 * 995i64) >> 12u32
    v2 = ty
    v3 = tx
    tx = (2048i64 + v4 * 1751i64 - v5 * 3703i64) >> 12u32
    ty = (2048i64 + v4 * 3703i64 + v5 * 1751i64) >> 12u32
    v4 = ty
    v5 = tx
    tx = (2048i64 + v6 * 2440i64 - v7 * 3290i64) >> 12u32
    ty = (2048i64 + v6 * 3290i64 + v7 * 2440i64) >> 12u32
    v6 = ty
    v7 = tx
    tx = (2048i64 + v8 * 3035i64 - v9 * 2751i64) >> 12u32
    ty = (2048i64 + v8 * 2751i64 + v9 * 3035i64) >> 12u32
    v8 = ty
    v9 = tx
    tx = (2048i64 + v10 * 3513i64 - v11 * 2106i64) >> 12u32
    ty = (2048i64 + v10 * 2106i64 + v11 * 3513i64) >> 12u32
    v10 = ty
    v11 = tx
    tx = (2048i64 + v12 * 3857i64 - v13 * 1380i64) >> 12u32
    ty = (2048i64 + v12 * 1380i64 + v13 * 3857i64) >> 12u32
    v12 = ty
    v13 = tx
    tx = (2048i64 + v14 * 4052i64 - v15 * 601i64) >> 12u32
    ty = (2048i64 + v14 * 601i64 + v15 * 4052i64) >> 12u32
    v14 = ty
    v15 = tx
    tx = v0 + v8
    ty = v0 - v8
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v8 = ty
    tx = v1 + v9
    ty = v1 - v9
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v9 = ty
    tx = v2 + v10
    ty = v2 - v10
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v10 = ty
    tx = v3 + v11
    ty = v3 - v11
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v11 = ty
    tx = v4 + v12
    ty = v4 - v12
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v12 = ty
    tx = v5 + v13
    ty = v5 - v13
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v5 = tx
    v13 = ty
    tx = v6 + v14
    ty = v6 - v14
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v6 = tx
    v14 = ty
    tx = v7 + v15
    ty = v7 - v15
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v7 = tx
    v15 = ty
    tx = (2048i64 + v8 * 799i64 - v9 * 4017i64) >> 12u32
    ty = (2048i64 + v8 * 4017i64 + v9 * 799i64) >> 12u32
    v8 = ty
    v9 = tx
    tx = (2048i64 + v13 * 4017i64 - v12 * 799i64) >> 12u32
    ty = (2048i64 + v13 * 799i64 + v12 * 4017i64) >> 12u32
    v13 = ty
    v12 = tx
    tx = (2048i64 + v10 * 3406i64 - v11 * 2276i64) >> 12u32
    ty = (2048i64 + v10 * 2276i64 + v11 * 3406i64) >> 12u32
    v10 = ty
    v11 = tx
    tx = (2048i64 + v15 * 2276i64 - v14 * 3406i64) >> 12u32
    ty = (2048i64 + v15 * 3406i64 + v14 * 2276i64) >> 12u32
    v15 = ty
    v14 = tx
    tx = v0 + v4
    ty = v0 - v4
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v4 = ty
    tx = v8 + v12
    ty = v8 - v12
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v8 = tx
    v12 = ty
    tx = v1 + v5
    ty = v1 - v5
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v5 = ty
    tx = v9 + v13
    ty = v9 - v13
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v9 = tx
    v13 = ty
    tx = v2 + v6
    ty = v2 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v2 = tx
    v6 = ty
    tx = v10 + v14
    ty = v10 - v14
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v10 = tx
    v14 = ty
    tx = v3 + v7
    ty = v3 - v7
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v3 = tx
    v7 = ty
    tx = v11 + v15
    ty = v11 - v15
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v11 = tx
    v15 = ty
    tx = (2048i64 + v4 * 1567i64 - v5 * 3784i64) >> 12u32
    ty = (2048i64 + v4 * 3784i64 + v5 * 1567i64) >> 12u32
    v4 = ty
    v5 = tx
    tx = (2048i64 + v12 * 1567i64 - v13 * 3784i64) >> 12u32
    ty = (2048i64 + v12 * 3784i64 + v13 * 1567i64) >> 12u32
    v12 = ty
    v13 = tx
    tx = (2048i64 + v7 * 3784i64 - v6 * 1567i64) >> 12u32
    ty = (2048i64 + v7 * 1567i64 + v6 * 3784i64) >> 12u32
    v7 = ty
    v6 = tx
    tx = (2048i64 + v15 * 3784i64 - v14 * 1567i64) >> 12u32
    ty = (2048i64 + v15 * 1567i64 + v14 * 3784i64) >> 12u32
    v15 = ty
    v14 = tx
    tx = v0 + v2
    ty = v0 - v2
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v0 = tx
    v2 = ty
    tx = v4 + v6
    ty = v4 - v6
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v4 = tx
    v6 = ty
    tx = v8 + v10
    ty = v8 - v10
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v8 = tx
    v10 = ty
    tx = v12 + v14
    ty = v12 - v14
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v12 = tx
    v14 = ty
    tx = v1 + v3
    ty = v1 - v3
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v1 = tx
    v3 = ty
    tx = v5 + v7
    ty = v5 - v7
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v5 = tx
    v7 = ty
    tx = v9 + v11
    ty = v9 - v11
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v9 = tx
    v11 = ty
    tx = v13 + v15
    ty = v13 - v15
    if tx > hi { tx = hi } else if tx < lo { tx = lo }
    if ty > hi { ty = hi } else if ty < lo { ty = lo }
    v13 = tx
    v15 = ty
    tx = (2048i64 + v2 * 2896i64 - v3 * 2896i64) >> 12u32
    ty = (2048i64 + v2 * 2896i64 + v3 * 2896i64) >> 12u32
    v2 = ty
    v3 = tx
    tx = (2048i64 + v6 * 2896i64 - v7 * 2896i64) >> 12u32
    ty = (2048i64 + v6 * 2896i64 + v7 * 2896i64) >> 12u32
    v6 = ty
    v7 = tx
    tx = (2048i64 + v10 * 2896i64 - v11 * 2896i64) >> 12u32
    ty = (2048i64 + v10 * 2896i64 + v11 * 2896i64) >> 12u32
    v10 = ty
    v11 = tx
    tx = (2048i64 + v14 * 2896i64 - v15 * 2896i64) >> 12u32
    ty = (2048i64 + v14 * 2896i64 + v15 * 2896i64) >> 12u32
    v14 = ty
    v15 = tx
    t[off + 0usize * st] = i32(v0)
    t[off + 1usize * st] = i32(0i64 - v8)
    t[off + 2usize * st] = i32(v12)
    t[off + 3usize * st] = i32(0i64 - v4)
    t[off + 4usize * st] = i32(v6)
    t[off + 5usize * st] = i32(0i64 - v14)
    t[off + 6usize * st] = i32(v10)
    t[off + 7usize * st] = i32(0i64 - v2)
    t[off + 8usize * st] = i32(v3)
    t[off + 9usize * st] = i32(0i64 - v11)
    t[off + 10usize * st] = i32(v15)
    t[off + 11usize * st] = i32(0i64 - v7)
    t[off + 12usize * st] = i32(v5)
    t[off + 13usize * st] = i32(0i64 - v13)
    t[off + 14usize * st] = i32(v9)
    t[off + 15usize * st] = i32(0i64 - v1)
    }
}

fn idct_nd(t: []i32, off: usize, st: usize, n: i32, r: u32) {
    if n == 2i32 { idct4(t, off, st, r) } else if n == 3i32 { idct8(t, off, st, r) } else if n == 4i32 { idct16(t, off, st, r) } else if n == 5i32 { idct32(t, off, st, r) } else { idct64_k32(t, off, st, r) }
}

fn iadst4_nd(t: []i32, off: usize, st: usize) {
    @nocheck {
    let t0 = i64(t[off])
    let t1 = i64(t[off + st])
    let t2 = i64(t[off + 2usize * st])
    let t3 = i64(t[off + 3usize * st])
    let s0 = 1321i64 * t0 + 3803i64 * t2 + 2482i64 * t3
    let s1 = 2482i64 * t0 - 1321i64 * t2 - 3803i64 * t3
    let s2 = 3344i64 * (t0 - t2 + t3)
    let s3 = 3344i64 * t1
    t[off] = i32((s0 + s3 + 2048i64) >> 12u32)
    t[off + st] = i32((s1 + s3 + 2048i64) >> 12u32)
    t[off + 2usize * st] = i32((s2 + 2048i64) >> 12u32)
    t[off + 3usize * st] = i32((s0 + s1 - s3 + 2048i64) >> 12u32)
    }
}

fn iidentity_nd(t: []i32, off: usize, st: usize, n: i32) {
    @nocheck {
    let n0 = usize(1i32 << u32(n))
    var k = 0usize
    var p = off
    while k < n0 {
        let v = i64(t[p])
        if n == 2i32 { t[p] = i32((v * 5793i64 + 2048i64) >> 12u32) } else if n == 3i32 { t[p] = i32(v * 2i64) } else if n == 4i32 { t[p] = i32((v * 11586i64 + 2048i64) >> 12u32) } else { t[p] = i32(v * 4i64) }
        p += st
        k += 1usize
    }
    }
}

fn transform_nd(t: []i32, off: usize, st: usize, kind: u8, n: i32, r: u32) {
    let guard = t[off + ((1usize << u32(n)) - 1usize) * st]
    if kind == 0u8 { idct_nd(t, off, st, n, r) } else if kind == 1u8 {
        if n == 2i32 { iadst4_nd(t, off, st) } else if n == 3i32 { fadst8(t, off, st, r) } else { fadst16(t, off, st, r) }
    } else { iidentity_nd(t, off, st, n) }
}

fn finish_block(out: []i32, w: usize, h: usize, flip_ud: bool, flip_lr: bool) {
    @nocheck {
    var y = 0usize
    var x = 0usize
    if flip_ud {
        while y < h / 2usize {
            let y2 = h - 1usize - y
            x = 0usize
            while x < w {
                var sx = x
                if flip_lr { sx = w - 1usize - x }
                let a = out[y * w + x]
                let b = out[y2 * w + sx]
                out[y * w + x] = (b + 8i32) >> 4u32
                out[y2 * w + sx] = (a + 8i32) >> 4u32
                x += 1usize
            }
            y += 1usize
        }
    } else if flip_lr {
        while y < h {
            x = 0usize
            while x < w / 2usize {
                let a = out[y * w + x]
                let b = out[y * w + w - 1usize - x]
                out[y * w + x] = (b + 8i32) >> 4u32
                out[y * w + w - 1usize - x] = (a + 8i32) >> 4u32
                x += 1usize
            }
            y += 1usize
        }
    } else {
        let n = w * h
        var k = 0usize
        while k < n {
            out[k] = (out[k] + 8i32) >> 4u32
            k += 1usize
        }
    }
    }
}

// eob_row_limit / eob_col_limit: quant is zero outside its first eob_row_limit rows and eob_col_limit columns
// (the last non-zero row / column plus one); larger values are clamped to the 32x32 corner.
fn reconstruct_eob(quant: []const i32, tx_size: usize, tx_type: usize, lossless: bool, bit_depth: u32, dc_q: i32, ac_q: i32, eob_row_limit: usize, eob_col_limit: usize, out: []i32) -> err {
    if tx_size >= 19usize || tx_type >= 16usize { ret Invalid }
    if lossless { ret reconstruct_generic(quant, tx_size, tx_type, lossless, bit_depth, dc_q, ac_q, out) }
    let log2_w = i32(log2_w_tab()[tx_size])
    let log2_h = i32(log2_h_tab()[tx_size])
    let row_kind = row_kind_tab()[tx_type]
    let col_kind = col_kind_tab()[tx_type]
    if !kind_ok(row_kind, log2_w) || !kind_ok(col_kind, log2_h) { ret Invalid }
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
    var j = 0usize
    let total = w * h
    if rl == 0usize || cl == 0usize {
        while i < total {
            out[i] = 0i32
            i += 1usize
        }
        ret ok
    }
    var dq_shift = 0u32
    if tx_size == 3usize || tx_size == 9usize || tx_size == 10usize || tx_size == 17usize || tx_size == 18usize { dq_shift = 1u32 } else if tx_size == 4usize || tx_size == 11usize || tx_size == 12usize { dq_shift = 2u32 }
    let lim_hi = (1i64 << (7u32 + bit_depth)) - 1i64
    let lim_lo = 0i64 - (1i64 << (7u32 + bit_depth))
    let row_shift = u32(row_shift_tab()[tx_size])
    let row_clamp = bit_depth + 8u32
    var col_clamp = bit_depth + 6u32
    if col_clamp < 16u32 { col_clamp = 16u32 }
    let col_hi = (1i64 << (col_clamp - 1u32)) - 1i64
    let col_lo = 0i64 - (1i64 << (col_clamp - 1u32))
    var rect = false
    if log2_w - log2_h == 1i32 || log2_h - log2_w == 1i32 { rect = true }
    i = rl * w
    while i < total {
        out[i] = 0i32
        i += 1usize
    }
    i = 0usize
    @nocheck {
    while i < rl {
        let base = i * w
        var nz = false
        j = 0usize
        while j < cl {
            var v = 0i32
            let qv = quant[i * tw + j]
            if qv != 0i32 {
                var q = ac_q
                if i == 0usize && j == 0usize { q = dc_q }
                let dq = i64(qv) * i64(q)
                var mag = dq
                if dq < 0i64 { mag = 0i64 - dq }
                mag = (mag & 16777215i64) >> dq_shift
                if dq < 0i64 { mag = 0i64 - mag }
                if mag < lim_lo { mag = lim_lo } else if mag > lim_hi { mag = lim_hi }
                v = i32(mag)
                if rect { v = i32((i64(v) * 2896i64 + 2048i64) >> 12u32) }
                if v != 0i32 { nz = true }
            }
            out[base + j] = v
            j += 1usize
        }
        while j < w {
            out[base + j] = 0i32
            j += 1usize
        }
        if nz {
            if cl == 1usize && row_kind == 0u8 {
                var f = (i64(out[base]) * 2896i64 + 2048i64) >> 12u32
                if row_shift != 0u32 { f = (f + (1i64 << (row_shift - 1u32))) >> row_shift }
                if f < col_lo { f = col_lo } else if f > col_hi { f = col_hi }
                let fv = i32(f)
                j = 0usize
                while j < w {
                    out[base + j] = fv
                    j += 1usize
                }
            } else {
                transform_nd(out, base, 1usize, row_kind, log2_w, row_clamp)
                j = 0usize
                while j < w {
                    var s = i64(out[base + j])
                    if row_shift != 0u32 { s = (s + (1i64 << (row_shift - 1u32))) >> row_shift }
                    if s < col_lo { s = col_lo } else if s > col_hi { s = col_hi }
                    out[base + j] = i32(s)
                    j += 1usize
                }
            }
        }
        i += 1usize
    }
    j = 0usize
    while j < w {
        if rl == 1usize && col_kind == 0u8 {
            let f = i32((i64(out[j]) * 2896i64 + 2048i64) >> 12u32)
            i = 0usize
            while i < h {
                out[i * w + j] = f
                i += 1usize
            }
        } else {
            transform_nd(out, j, w, col_kind, log2_h, col_clamp)
        }
        j += 1usize
    }
    }
    var flip_ud = false
    var flip_lr = false
    if tx_type == 4usize || tx_type == 8usize || tx_type == 14usize || tx_type == 6usize { flip_ud = true }
    if tx_type == 5usize || tx_type == 7usize || tx_type == 15usize || tx_type == 6usize { flip_lr = true }
    finish_block(out, w, h, flip_ud, flip_lr)
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
