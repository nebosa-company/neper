// `dis` decodes the VEX forms `--cpu x64-v3` writes for a thirty-two-byte vector (T010):
// the operands three wide, vvvv the extra source, a shift's count still an xmm.
use e.os
use e.simd

fn mix(a: Vec[i32, 8], b: Vec[i32, 8], n: u32) -> Vec[i32, 8] {
    ret ((a +% b) *% a ^ (b << 3u32)) >> n
}

fn main() {
    let v = mix(simd.splat[Vec[i32, 8]](1i32), simd.splat[Vec[i32, 8]](2i32), 1u32)
    os.exit(v[0])
}
