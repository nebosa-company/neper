// `e.ml.fingerprint`: Morgan and path fingerprints of three small
// molecules against packed bit keys, Tanimoto/Dice scores, Butina clusters,
// FMCS counts with map validity, and the storage, endpoint and empty cases.
// Each check exits with its own code.

use e.mem
use e.ml.fingerprint as fp
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn pack(bits: []const u8, n: usize) -> u64 {
    var key = 0u64
    var i = 0usize
    while i < n {
        if bits[i] != 0u8 { key += 1u64 << u64(i) }
        i += 1usize
    }
    ret key
}

fn mapped_count(map: []const usize, na: usize, none: usize) -> usize {
    var count = 0usize
    var i = 0usize
    while i < na {
        if map[i] != none { count += 1usize }
        i += 1usize
    }
    ret count
}

fn maps_match(a_atoms: []const u32, map: []const usize, b_atoms: []const u32, na: usize, nb: usize) -> bool {
    var i = 0usize
    while i < na {
        if map[i] > nb { ret false }
        if map[i] != nb && a_atoms[i] != b_atoms[map[i]] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var atomsA: [3]u32 = zero
    atomsA[0usize] = 6u32
    atomsA[1usize] = 6u32
    atomsA[2usize] = 8u32
    var srcA: [2]usize = zero
    srcA[0usize] = 0usize
    srcA[1usize] = 1usize
    var dstA: [2]usize = zero
    dstA[0usize] = 1usize
    dstA[1usize] = 2usize
    var orderA: [2]u8 = zero
    orderA[0usize] = 1u8
    orderA[1usize] = 1u8
    var atomsB: [4]u32 = zero
    atomsB[0usize] = 6u32
    atomsB[1usize] = 6u32
    atomsB[2usize] = 6u32
    atomsB[3usize] = 8u32
    var srcB: [3]usize = zero
    srcB[0usize] = 0usize
    srcB[1usize] = 1usize
    srcB[2usize] = 2usize
    var dstB: [3]usize = zero
    dstB[0usize] = 1usize
    dstB[1usize] = 2usize
    dstB[2usize] = 3usize
    var orderB: [3]u8 = zero
    orderB[0usize] = 1u8
    orderB[1usize] = 1u8
    orderB[2usize] = 1u8
    var atomsC: [2]u32 = zero
    atomsC[0usize] = 6u32
    atomsC[1usize] = 6u32
    var srcC: [1]usize = zero
    srcC[0usize] = 0usize
    var dstC: [1]usize = zero
    dstC[0usize] = 1usize
    var orderC: [1]u8 = zero
    orderC[0usize] = 1u8
    var bitsA: [16]u8 = zero
    var bitsB: [16]u8 = zero
    var bitsC: [16]u8 = zero
    var bitsD: [16]u8 = zero
    var mscratch: [8]u64 = zero
    var pscratch: [8]usize = zero

    // 1: Morgan radius-1 fingerprints as packed keys; D repeats A exactly.
    if fp.morgan_fingerprint(atomsA[..], 3usize, srcA[..], dstA[..], orderA[..], 2usize, 1u32, bitsA[..], mscratch[..]) != ok { os.exit(1i32) }
    if fp.morgan_fingerprint(atomsB[..], 4usize, srcB[..], dstB[..], orderB[..], 3usize, 1u32, bitsB[..], mscratch[..]) != ok { os.exit(1i32) }
    if fp.morgan_fingerprint(atomsC[..], 2usize, srcC[..], dstC[..], orderC[..], 1usize, 1u32, bitsC[..], mscratch[..]) != ok { os.exit(1i32) }
    if fp.morgan_fingerprint(atomsA[..], 3usize, srcA[..], dstA[..], orderA[..], 2usize, 1u32, bitsD[..], mscratch[..]) != ok { os.exit(1i32) }
    if pack(bitsA[..], 16usize) != 21697u64 { os.exit(1i32) }
    if pack(bitsB[..], 16usize) != 21585u64 { os.exit(1i32) }
    if pack(bitsC[..], 16usize) != 16392u64 { os.exit(1i32) }
    if pack(bitsD[..], 16usize) != 21697u64 { os.exit(1i32) }

    // 2: path fingerprints of length up to two.
    if fp.path_fingerprint(atomsA[..], 3usize, srcA[..], dstA[..], orderA[..], 2usize, 2u32, bitsA[..], pscratch[..]) != ok { os.exit(2i32) }
    if fp.path_fingerprint(atomsB[..], 4usize, srcB[..], dstB[..], orderB[..], 3usize, 2u32, bitsB[..], pscratch[..]) != ok { os.exit(2i32) }
    if pack(bitsA[..], 16usize) != 8770u64 { os.exit(2i32) }
    if pack(bitsB[..], 16usize) != 8770u64 { os.exit(2i32) }
    if fp.morgan_fingerprint(atomsA[..], 3usize, srcA[..], dstA[..], orderA[..], 2usize, 1u32, bitsA[..], mscratch[..]) != ok { os.exit(2i32) }
    if fp.morgan_fingerprint(atomsB[..], 4usize, srcB[..], dstB[..], orderB[..], 3usize, 1u32, bitsB[..], mscratch[..]) != ok { os.exit(2i32) }

    // 3: Tanimoto and Dice, with the identical pair at exactly one.
    let (tab, tab_error) = fp.tanimoto(bitsA[..], bitsB[..], 16usize)
    if tab_error != ok { os.exit(3i32) }
    let (tac, tac_error) = fp.tanimoto(bitsA[..], bitsC[..], 16usize)
    if tac_error != ok { os.exit(3i32) }
    let (dab, dab_error) = fp.dice(bitsA[..], bitsB[..], 16usize)
    if dab_error != ok { os.exit(3i32) }
    let (tad, tad_error) = fp.tanimoto(bitsA[..], bitsD[..], 16usize)
    if tad_error != ok { os.exit(3i32) }
    if !near(tab, 0.7142857142857143f64, 0.000000001f64) { os.exit(3i32) }
    if !near(tac, 0.14285714285714285f64, 0.000000001f64) { os.exit(3i32) }
    if !near(dab, 0.8333333333333334f64, 0.000000001f64) { os.exit(3i32) }
    if tad != 1.0f64 { os.exit(3i32) }
    let (short_value, short_error) = fp.tanimoto(bitsA[..15usize], bitsB[..], 16usize)
    if short_error != fp.TooSmall { os.exit(3i32) }
    if short_value != 0.0f64 { os.exit(3i32) }
    let (empty_value, empty_error) = fp.tanimoto(bitsA[..0usize], bitsB[..0usize], 0usize)
    if empty_error != fp.Invalid { os.exit(3i32) }
    if empty_value != 0.0f64 { os.exit(3i32) }

    // 4: Butina at cutoff 0.35 puts the duplicate pair together.
    var mat: [64]u8 = zero
    var r = 0usize
    while r < 16usize {
        mat[r] = bitsA[r]
        mat[16usize + r] = bitsB[r]
        mat[32usize + r] = bitsC[r]
        mat[48usize + r] = bitsD[r]
        r += 1usize
    }
    var labels: [4]usize = zero
    var border: [4]usize = zero
    var bscratch: [8]usize = zero
    let (clusters, clusters_error) = fp.butina(mat[..], 4usize, 16usize, 0.35f64, labels[..], border[..], bscratch[..])
    if clusters_error != ok { os.exit(4i32) }
    if clusters != 2usize { os.exit(4i32) }
    if labels[0usize] != 0usize || labels[1usize] != 0usize || labels[2usize] != 1usize || labels[3usize] != 0usize { os.exit(4i32) }
    if border[0usize] != 0usize || border[1usize] != 1usize || border[2usize] != 3usize || border[3usize] != 2usize { os.exit(4i32) }
    let (no_clusters, no_clusters_error) = fp.butina(mat[..0usize], 0usize, 16usize, 0.35f64, labels[..0usize], border[..0usize], bscratch[..0usize])
    if no_clusters_error != fp.Invalid { os.exit(4i32) }
    if no_clusters != 0usize { os.exit(4i32) }

    // 5: FMCS counts with valid maps, and the zero budget.
    var fmap: [4]usize = zero
    var fscratch: [12]usize = zero
    let (common_ab, ab_error) = fp.fmcs(atomsA[..], 3usize, srcA[..], dstA[..], orderA[..], 2usize, atomsB[..], 4usize, srcB[..], dstB[..], orderB[..], 3usize, 10000u32, fmap[..3usize], fscratch[..])
    if ab_error != ok { os.exit(5i32) }
    if common_ab != 2usize { os.exit(5i32) }
    if mapped_count(fmap[..3usize], 3usize, 4usize) != 3usize { os.exit(5i32) }
    if !maps_match(atomsA[..], fmap[..3usize], atomsB[..], 3usize, 4usize) { os.exit(5i32) }
    var cmap: [3]usize = zero
    var cscratch: [8]usize = zero
    let (common_ac, ac_error) = fp.fmcs(atomsA[..], 3usize, srcA[..], dstA[..], orderA[..], 2usize, atomsC[..], 2usize, srcC[..], dstC[..], orderC[..], 1usize, 10000u32, cmap[..], cscratch[..])
    if ac_error != ok { os.exit(5i32) }
    if common_ac != 1usize { os.exit(5i32) }
    if mapped_count(cmap[..], 3usize, 2usize) != 2usize { os.exit(5i32) }
    if !maps_match(atomsA[..], cmap[..], atomsC[..], 3usize, 2usize) { os.exit(5i32) }
    let (common_zero, zero_error) = fp.fmcs(atomsA[..], 3usize, srcA[..], dstA[..], orderA[..], 2usize, atomsB[..], 4usize, srcB[..], dstB[..], orderB[..], 3usize, 0u32, fmap[..3usize], fscratch[..])
    if zero_error != ok { os.exit(5i32) }
    if common_zero != 0usize { os.exit(5i32) }
    if fmap[0usize] != 4usize || fmap[1usize] != 4usize || fmap[2usize] != 4usize { os.exit(5i32) }

    // 6: storage, endpoint and empty cases.
    var badSrc: [2]usize = zero
    badSrc[0usize] = 0usize
    badSrc[1usize] = 9usize
    if fp.morgan_fingerprint(atomsA[..], 3usize, srcA[..], dstA[..], orderA[..], 2usize, 1u32, bitsA[..], mscratch[..5usize]) != fp.TooSmall { os.exit(6i32) }
    if fp.morgan_fingerprint(atomsA[..], 3usize, badSrc[..], dstA[..], orderA[..], 2usize, 1u32, bitsA[..], mscratch[..]) != fp.Invalid { os.exit(6i32) }
    if fp.path_fingerprint(atomsA[..], 3usize, srcA[..], dstA[..], orderA[..], 2usize, 0u32, bitsA[..], pscratch[..]) != fp.Invalid { os.exit(6i32) }
    let (small_bonds, small_error) = fp.fmcs(atomsA[..], 3usize, srcA[..], dstA[..], orderA[..], 2usize, atomsB[..], 4usize, srcB[..], dstB[..], orderB[..], 3usize, 10000u32, fmap[..3usize], fscratch[..11usize])
    if small_error != fp.TooSmall { os.exit(6i32) }
    if small_bonds != 0usize { os.exit(6i32) }
    let (bad_bonds, bad_error) = fp.fmcs(atomsA[..], 3usize, badSrc[..], dstA[..], orderA[..], 2usize, atomsB[..], 4usize, srcB[..], dstB[..], orderB[..], 3usize, 10000u32, fmap[..3usize], fscratch[..])
    if bad_error != fp.Invalid { os.exit(6i32) }
    if bad_bonds != 0usize { os.exit(6i32) }
    let (empty_bonds, bare_error) = fp.fmcs(atomsA[..0usize], 0usize, srcA[..0usize], dstA[..0usize], orderA[..0usize], 0usize, atomsB[..], 4usize, srcB[..], dstB[..], orderB[..], 3usize, 10000u32, fmap[..0usize], fscratch[..])
    if bare_error != fp.Invalid { os.exit(6i32) }
    if empty_bonds != 0usize { os.exit(6i32) }
    ret ok
}
