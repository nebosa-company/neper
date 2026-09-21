// `e.gfx.texture`: BC1/BC3/BC4/BC5 over 12 LCG blocks each and two hand blocks
// against a Python replica (FNV of the RGBA output), then 50 ASTC blocks that
// `astcenc` 4.x produced from random and gradient images at 4x4, 5x5, 6x6, 8x8,
// 10x8 and 12x12 in the linear and sRGB profiles, each decoded to the FNV hash
// of what `astcenc` itself decompressed: void extents, one to four partitions,
// dual planes, trit and quint weights, uniform and mixed end-point modes. A
// reserved block mode answers Invalid and an HDR end-point mode Unsupported.
// Each check exits with its own code.

use e.gfx.texture
use e.io
use e.mem
use e.os

fn draw(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn fnv(bytes: []const u8) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < bytes.len {
        h = (h ^ u64(bytes[i])) *% 1099511628211u64
        i += 1usize
    }
    ret h
}

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(text: str, out: []u8) {
    var i = 0usize
    while i < 16usize {
        out[i] = (nibble(text[2usize * i]) << 4u32) | nibble(text[2usize * i + 1usize])
        i += 1usize
    }
}

fn bc_sum(state: *u64, format: texture.Format, size: usize, code: i32) -> u64 {
    var block: [16]u8 = zero
    var out: [64]u8 = zero
    var total = 0u64
    var k = 0usize
    while k < 12usize {
        var i = 0usize
        while i < size {
            block[i] = u8(draw(state) & 255u64)
            i += 1usize
        }
        if texture.bc_decode(block[..size], format, out[..]) != ok { os.exit(code) }
        total +%= fnv(out[..])
        k += 1usize
    }
    ret total
}

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 17u64
    var out: [64]u8 = zero

    // 1-4: the four BC formats over LCG blocks.
    if bc_sum(&state, .Bc1, 8usize, 1i32) != 17750045578453603436u64 { os.exit(1i32) }
    if bc_sum(&state, .Bc3, 16usize, 2i32) != 13637156597464019072u64 { os.exit(2i32) }
    if bc_sum(&state, .Bc4, 8usize, 3i32) != 8044689837445009691u64 { os.exit(3i32) }
    if bc_sum(&state, .Bc5, 16usize, 4i32) != 10408487377744643896u64 { os.exit(4i32) }

    // 5: hand blocks: red to blue in four colours, then the three-colour order.
    let four: [8]u8 = [8]u8{ 0, 248, 31, 0, 0, 85, 170, 255 }
    if texture.bc_decode(four[..], .Bc1, out[..]) != ok || fnv(out[..]) != 12632130739030153061u64 { os.exit(5i32) }
    if out[0] != 255u8 || out[2] != 0u8 || out[16usize + 2usize] != 255u8 || out[3] != 255u8 { os.exit(5i32) }
    let three: [8]u8 = [8]u8{ 31, 0, 0, 248, 0, 85, 170, 255 }
    if texture.bc_decode(three[..], .Bc1, out[..]) != ok || fnv(out[..]) != 180204927428001365u64 { os.exit(5i32) }
    if out[48usize + 3usize] != 0u8 || out[32usize] != 128u8 { os.exit(5i32) }
    if texture.bc_decode(three[..], .Bc1, out[..63usize]) != texture.TooSmall { os.exit(5i32) }
    if texture.bc_decode(three[..], .Bc3, out[..]) != texture.Invalid { os.exit(5i32) }

    // 6: ASTC blocks against astcenc.
    let hexes: [50]str = [50]str{ "fcfdffffffffffff0a0ac8c81e1effff", "fcfdffffffffffff0a0ac8c81e1effff", "5284d3c4c17db076e5df511d9bd1c996", "512ae4439f64bc4b22ca81005c34ea6e", "410a5cf0a6847a632f182407414163ff", "528467a7f9a039e4ca5183fdc3640c6a", "410a95676e94a1ea2b380c85f2cfd482", "53c8dc876e7527179715c4415cae4c94", "42f090e136dda992ba8b1988c5627d03", "43d06634ed5d8e436f2a86df8c317e71", "148992755fd2636a422895b229967fee", "6ee8f7753ff76acc81b69aae7b277146", "4304616010456a43ac3d5e8c0b831860", "14696630e9e7b1260d016fb69d092df3", "08493b488df761ea68fff3eee465be26", "1881b89d1b672cb79f47ae3b04761619", "08411fed73f25f7e74d9e2809e6c89bb", "1469ff83de6ebe192278ab1e021c2de7", "448bbef1de37b6ef8712cfeb724870c2", "4485ed8bb7dee919467390e36c4ac8f5", "34452bf78bb2c9cdeda74dec296f0a11", "6204814679577f3b5d196e2a6e2a4c08", "44ed50487f79315bdbeb552bdfdac89b", "f184dbeb7e3d5d85059d0025c0006f98", "f184f799ac97c5f6806222e7bdaa2cb9", "44edc1b1fff67e8e52eab3173b1ff9eb", "d3a89463b3e4fb6b5ae2f775c6f57131", "f2a88543d9f2edb9118d8e762c4f886f", "e1a80c98115bbcaac97597a599b4588a", "4384afeb78e8f4c6e2c562825c1283c6", "f2a80850263fcffa89366d23cf7d7be3", "e3801fffbdaee51a9e0d0d6c1c8c260f", "f268c3636664dcbd321b321ba86dac0e", "438471bc13c1448d36d697381312cb8d", "5480f5f02e9bf0212e1d898ceb22a6e4", "44851fcf66efe51dd59e3d78efda5d4d", "64eb18c5cf7ff647e5ae8dcff2eaf857", "f18465e6c8b54d351fa28fc52d6ae59e", "64cb505015b92de592dc12375beb7fdd", "748145b572dcad368c9f2c9ead358fbc", "44855f0625cf773cf75926d16478ce51", "64c888e336d3f53ee9078473d352a220", "5483d45598ad39abcb409889e914644c", "4485a5c579ded13ad4ee6a655dcdb5ce", "a4c998a3a5f7fed6ba37e3a16e7b2c5d", "75c9cf92bf0e2c267432f54022268402", "44cd15ec6fced92d86a59aa7ebf727bb", "4485b997fd9bbf306341da17695cde2b", "75816dd5d61746a02bfecc055630144c", "a4699db5fff25eef22f52224249cbb78" }
    let widths: [50]u8 = [50]u8{ 4, 8, 4, 4, 4, 4, 4, 4, 4, 4, 6, 6, 6, 6, 6, 6, 6, 6, 8, 8, 8, 8, 8, 8, 8, 8, 5, 5, 5, 5, 5, 5, 5, 5, 12, 12, 12, 12, 12, 12, 12, 12, 10, 10, 10, 10, 10, 10, 10, 10 }
    let heights: [50]u8 = [50]u8{ 4, 8, 4, 4, 4, 4, 4, 4, 4, 4, 6, 6, 6, 6, 6, 6, 6, 6, 8, 8, 8, 8, 8, 8, 8, 8, 5, 5, 5, 5, 5, 5, 5, 5, 12, 12, 12, 12, 12, 12, 12, 12, 8, 8, 8, 8, 8, 8, 8, 8 }
    let srgbs: [50]u8 = [50]u8{ 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1 }
    let hashes: [50]u64 = [50]u64{ 6871760718713222693u64, 2667970831733583653u64, 5426935304887022198u64, 15945948744075806654u64, 8167747743665732808u64, 17094658790717031182u64, 12754877088125978835u64, 9031966809421635653u64, 13701833146222741218u64, 1517872014271941258u64, 16992146798309417502u64, 13359396160265280734u64, 1170857948915372149u64, 8518860946198380013u64, 11011774452804431022u64, 7491690647574409924u64, 5976725199119741158u64, 13247894118580395110u64, 12719507004348319707u64, 8929845375757199108u64, 13729071427715088635u64, 11187800985444010985u64, 6770240093898486431u64, 5450913450794626382u64, 17446412803848118307u64, 4239445528307100657u64, 6838111542021140073u64, 4610152665605507933u64, 11830929257721430339u64, 5304214542315125080u64, 4802387943183031024u64, 16755937930759809845u64, 11139886259955342433u64, 2218211478695220205u64, 6167308306303889562u64, 13846151564434570375u64, 3847823424862842390u64, 12024886170459062472u64, 3855071895738763802u64, 5987255301384853712u64, 14818476869748142782u64, 5227938131789634661u64, 18179913061186902863u64, 2461167660972460368u64, 3930652164142547507u64, 4400817469088177707u64, 6349684744543430590u64, 16695430509882120570u64, 3290155469409669866u64, 16099277660772877103u64 }
    var block: [16]u8 = zero
    var texels: [576]u8 = zero
    var i = 0usize
    while i < 50usize {
        unhex(hexes[i], block[..])
        let width = usize(widths[i])
        let height = usize(heights[i])
        let decode_error = texture.astc_decode(block[..], width, height, srgbs[i] != 0u8, texels[..])
        if decode_error != ok { os.exit(6i32) }
        if fnv(texels[..width * height * 4usize]) != hashes[i] { os.exit(7i32) }
        i += 1usize
    }

    // 8: a reserved mode is Invalid, an HDR end-point mode Unsupported, no room TooSmall.
    var bad: [16]u8 = zero
    bad[0] = 0xC0u8
    bad[1] = 0x01u8
    if texture.astc_decode(bad[..], 4usize, 4usize, false, texels[..]) != texture.Invalid { os.exit(8i32) }
    unhex(hexes[2usize], block[..])
    block[1] = (block[1] & 0x1Fu8) | 0x40u8
    block[2] = block[2] & 0xFEu8
    if texture.astc_decode(block[..], 4usize, 4usize, false, texels[..]) != texture.Unsupported { os.exit(8i32) }
    unhex(hexes[2usize], block[..])
    if texture.astc_decode(block[..], 4usize, 4usize, false, texels[..63usize]) != texture.TooSmall { os.exit(8i32) }

    try io.print("gfx texture ok\n")
    ret ok
}
