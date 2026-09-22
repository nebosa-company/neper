// `e.crypto.sign` / `e.crypto.kx` / `e.crypto.mac` / `e.crypto.hash` extensions:
// ECDSA P-256 signing with RFC 6979 nonces (A.2.5 vectors), Poly1305 (RFC 8439
// 2.5.2), BLAKE3 (the official vectors and tree-boundary lengths against the
// `blake3` package), BIP-340 Schnorr (the BIP's test-vectors.csv), ffdhe2048 DH and
// RSASSA-PSS / PKCS#1 v1.5 against Python `cryptography`. Every check has its own
// exit code; the values come from scripts in the session scratchpad.
use e.os
use e.io
use e.mem
use e.crypto.sign as sign
use e.crypto.kx as kx
use e.crypto.mac as mac
use e.crypto.hash as hash

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    if c >= 65u8 { ret c - 55u8 }
    ret c - 48u8
}

fn unhex(s: str, out: []u8) -> usize {
    var i = 0usize
    while i * 2usize + 1usize < s.len {
        out[i] = (nibble(s[i * 2usize]) << 4u8) | nibble(s[i * 2usize + 1usize])
        i += 1usize
    }
    ret i
}

fn same_hex(bytes: []const u8, expected: str) -> bool {
    var buf: [512]u8 = zero
    let n = unhex(expected, buf[0..])
    if n != bytes.len { ret false }
    var i = 0usize
    while i < n {
        if buf[i] != bytes[i] { ret false }
        i += 1usize
    }
    ret true
}

fn fill_lcg(out: []u8) {
    var state = 7u64
    var i = 0usize
    while i < out.len {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        out[i] = u8((state >> 33u32) & 255u64)
        i += 1usize
    }
}

fn hex32(s: str) -> [32]u8 {
    var out: [32]u8 = zero
    let _ = unhex(s, out[0..])
    ret out
}

fn hex64(s: str) -> [64]u8 {
    var out: [64]u8 = zero
    let _ = unhex(s, out[0..])
    ret out
}

fn blake3_len(length: usize, expected: str) -> bool {
    var data: [3072]u8 = zero
    fill_lcg(data[..length])
    let digest = hash.blake3(data[..length])
    ret same_hex(digest[0..], expected)
}

fn blake3_official(length: usize, key: str, context: str, expected: str, keyed: str, derived: str) -> u8 {
    var data: [1024]u8 = zero
    var i = 0usize
    while i < length {
        data[i] = u8(i % 251usize)
        i += 1usize
    }
    let digest = hash.blake3(data[..length])
    if !same_hex(digest[0..], expected) { ret 1u8 }
    var key_bytes: [32]u8 = zero
    i = 0usize
    while i < 32usize {
        key_bytes[i] = key[i]
        i += 1usize
    }
    let keyed_digest = hash.blake3_keyed(key_bytes, data[..length])
    if !same_hex(keyed_digest[0..], keyed) { ret 2u8 }
    var derived_out: [32]u8 = zero
    hash.blake3_derive_key(context, data[..length], derived_out[0..])
    if !same_hex(derived_out[0..], derived) { ret 3u8 }
    ret 0u8
}

// Signs when a secret is given and compares; verifies and compares with `expect`.
fn schnorr_case(sk: str, pk: str, aux: str, msg: str, sig: str, expect: bool) -> u8 {
    var message: [128]u8 = zero
    let message_len = unhex(msg, message[0..])
    let public = hex32(pk)
    let signature = hex64(sig)
    if sk.len > 0usize {
        let (derived, derive_error) = sign.schnorr_public_from_secret(hex32(sk))
        if derive_error != ok || !same_hex(derived[0..], pk) { ret 1u8 }
        let (made, sign_error) = sign.schnorr(hex32(sk), message[..message_len], hex32(aux))
        if sign_error != ok || !same_hex(made[0..], sig) { ret 2u8 }
    }
    if sign.schnorr_verify(public, message[..message_len], signature) != expect { ret 3u8 }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1-4: ECDSA P-256, RFC 6979 A.2.5.
    let p256_secret = sign.P256SecretKey { bytes: hex32("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721") }
    let (p256_public, p256_public_error) = sign.p256_public_from_secret(p256_secret)
    if p256_public_error != ok || !same_hex(p256_public.bytes[0..], "0460fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb67903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299") { os.exit(1i32) }
    var der: [72]u8 = zero
    let (der_len, sign_error) = sign.p256_sign(p256_secret, "sample", der[0..])
    if sign_error != ok || !same_hex(der[..der_len], "3046022100efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716022100f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8") { os.exit(2i32) }
    if !sign.p256_verify(p256_public, "sample", der[..der_len]) { os.exit(3i32) }
    let (der_len2, sign_error2) = sign.p256_sign(p256_secret, "test", der[0..])
    if sign_error2 != ok || !same_hex(der[..der_len2], "3045022100f1abb023518351cd71d881567b1ea663ed3efcf6c5132b354f28d3b0b7d383670220019f4113742a2b14bd25926b49c649155f267e60d3814b4c0cc84250e46f0083") { os.exit(4i32) }
    try io.print("p256 ok\n")
    // 10-12: Poly1305.
    let poly_key = hex32("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b")
    let tag = mac.poly1305(poly_key, "Cryptographic Forum Research Group")
    if !same_hex(tag[0..], "a8061dc1305136c6c22b8baf0c0127a9") { os.exit(10i32) }
    var lcg100: [100]u8 = zero
    fill_lcg(lcg100[0..])
    var poly = mac.poly1305_init(poly_key)
    mac.poly1305_update(&poly, lcg100[..7])
    mac.poly1305_update(&poly, lcg100[7..57])
    mac.poly1305_update(&poly, lcg100[57..])
    let lcg_tag = mac.poly1305_done(&poly)
    if !same_hex(lcg_tag[0..], "90d883c0154f54532332d55003195db6") { os.exit(11i32) }
    if !mac.poly1305_verify(poly_key, lcg100[0..], lcg_tag) || mac.poly1305_verify(poly_key, lcg100[..99], lcg_tag) { os.exit(12i32) }
    try io.print("poly1305 ok\n")
    // 20-38: BLAKE3.
    if !blake3_len(0usize, "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262") { os.exit(20i32) }
    if !blake3_len(1usize, "684200d461e94e063925de567369dd89b8c1959b6f94ec8e740edf4c2bd21396") { os.exit(21i32) }
    if !blake3_len(63usize, "d42a4f908c06b61a1e1b11d1a38e3050ca97c590d5a91b6fa66175c2f07cb6d0") { os.exit(22i32) }
    if !blake3_len(64usize, "91af6fbd9007866699120ea3a92a1db039b4e4035fcb5635dd62de1c210d11d3") { os.exit(23i32) }
    if !blake3_len(65usize, "31b5fba904b06f789be999f8c5cdf15d8f29b3896203be4f598996e82acef912") { os.exit(24i32) }
    if !blake3_len(1024usize, "427d74273d74995e8564c94a9a16cc1240fece71138b9a662089a6591422fb44") { os.exit(25i32) }
    if !blake3_len(1025usize, "fcaa98bc5eef86ceae5c5d2c179cdd43ba282b9df8c88a7ae184fe5cc0cbdcb8") { os.exit(26i32) }
    if !blake3_len(2048usize, "b4fb1ce167caf1cc3d0311a8b57f993ba9ab146af558b41d87f249467cef1ec0") { os.exit(27i32) }
    if !blake3_len(3072usize, "ac58ace843bfa01ca7e31d3446389d883d258a85878f37bf760f598c2f9901c8") { os.exit(28i32) }
    var lcg1025: [1025]u8 = zero
    fill_lcg(lcg1025[0..])
    var xof: [100]u8 = zero
    hash.blake3_xof(lcg1025[0..], xof[0..])
    if !same_hex(xof[0..], "fcaa98bc5eef86ceae5c5d2c179cdd43ba282b9df8c88a7ae184fe5cc0cbdcb8fc8b42b34a08dae18b5e027b8f71a5812c1f1928598d7abcc1f664e75ac45f669ea28d1b0fd4c3a66f96e22fc9d181197092248179cda718b562f1d099f48b1e45f6c1f7") { os.exit(29i32) }
    var lcg2048: [2048]u8 = zero
    fill_lcg(lcg2048[0..])
    var key32: [32]u8 = zero
    var ki = 0usize
    while ki < 32usize {
        key32[ki] = u8(ki)
        ki += 1usize
    }
    let keyed = hash.blake3_keyed(key32, lcg2048[0..])
    if !same_hex(keyed[0..], "9b7b79c163e41199e9e306a471be60a8c227f398cf75da5e3422ee4d6c3186d2") { os.exit(30i32) }
    var derived: [48]u8 = zero
    hash.blake3_derive_key("neper crypto 2026-09-22 fixture", lcg2048[..64], derived[0..])
    if !same_hex(derived[0..], "2a065d657f8b05fa99649b2d5a5cdf7c0543685443ed6c20436fd0e3e88e0c4fe7b221622274d45321015225886de093") { os.exit(31i32) }
    if blake3_official(0usize, "whats the Elvish word for friend", "BLAKE3 2019-12-27 16:29:52 test vectors context", "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262", "92b2b75604ed3c761f9d6f62392c8a9227ad0ea3f09573e783f1498a4ed60d26", "2cc39783c223154fea8dfb7c1b1660f2ac2dcbd1c1de8277b0b0dd39b7e50d7d") != 0u8 { os.exit(32i32) }
    if blake3_official(1usize, "whats the Elvish word for friend", "BLAKE3 2019-12-27 16:29:52 test vectors context", "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213", "6d7878dfff2f485635d39013278ae14f1454b8c0a3a2d34bc1ab38228a80c95b", "b3e2e340a117a499c6cf2398a19ee0d29cca2bb7404c73063382693bf66cb06c") != 0u8 { os.exit(33i32) }
    if blake3_official(2usize, "whats the Elvish word for friend", "BLAKE3 2019-12-27 16:29:52 test vectors context", "7b7015bb92cf0b318037702a6cdd81dee41224f734684c2c122cd6359cb1ee63", "5392ddae0e0a69d5f40160462cbd9bd889375082ff224ac9c758802b7a6fd20a", "1f166565a7df0098ee65922d7fea425fb18b9943f19d6161e2d17939356168e6") != 0u8 { os.exit(34i32) }
    if blake3_official(3usize, "whats the Elvish word for friend", "BLAKE3 2019-12-27 16:29:52 test vectors context", "e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f", "39e67b76b5a007d4921969779fe666da67b5213b096084ab674742f0d5ec62b9", "440aba35cb006b61fc17c0529255de438efc06a8c9ebf3f2ddac3b5a86705797") != 0u8 { os.exit(35i32) }
    if blake3_official(4usize, "whats the Elvish word for friend", "BLAKE3 2019-12-27 16:29:52 test vectors context", "f30f5ab28fe047904037f77b6da4fea1e27241c5d132638d8bedce9d40494f32", "7671dde590c95d5ac9616651ff5aa0a27bee5913a348e053b8aa9108917fe070", "f46085c8190d69022369ce1a18880e9b369c135eb93f3c63550d3e7630e91060") != 0u8 { os.exit(36i32) }
    if blake3_official(5usize, "whats the Elvish word for friend", "BLAKE3 2019-12-27 16:29:52 test vectors context", "b40b44dfd97e7a84a996a91af8b85188c66c126940ba7aad2e7ae6b385402aa2", "73ac69eecf286894d8102018a6fc729f4b1f4247d3703f69bdc6a5fe3e0c8461", "1f24eda69dbcb752847ec3ebb5dd42836d86e58500c7c98d906ecd82ed9ae47f") != 0u8 { os.exit(37i32) }
    try io.print("blake3 ok\n")
    // 40-58: BIP-340 test-vectors.csv rows 0-18.
    if schnorr_case("0000000000000000000000000000000000000000000000000000000000000003", "F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9", "0000000000000000000000000000000000000000000000000000000000000000", "0000000000000000000000000000000000000000000000000000000000000000", "E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA821525F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0", true) != 0u8 { os.exit(40i32) }
    if schnorr_case("B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF", "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", "0000000000000000000000000000000000000000000000000000000000000001", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", "6896BD60EEAE296DB48A229FF71DFE071BDE413E6D43F917DC8DCF8C78DE33418906D11AC976ABCCB20B091292BFF4EA897EFCB639EA871CFA95F6DE339E4B0A", true) != 0u8 { os.exit(41i32) }
    if schnorr_case("C90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B14E5C9", "DD308AFEC5777E13121FA72B9CC1B7CC0139715309B086C960E18FD969774EB8", "C87AA53824B4D7AE2EB035A2B5BBBCCC080E76CDC6D1692C4B0B62D798E6D906", "7E2D58D8B3BCDF1ABADEC7829054F90DDA9805AAB56C77333024B9D0A508B75C", "5831AAEED7B44BB74E5EAB94BA9D4294C49BCF2A60728D8B4C200F50DD313C1BAB745879A5AD954A72C45A91C3A51D3C7ADEA98D82F8481E0E1E03674A6F3FB7", true) != 0u8 { os.exit(42i32) }
    if schnorr_case("0B432B2677937381AEF05BB02A66ECD012773062CF3FA2549E44F58ED2401710", "25D1DFF95105F5253C4022F628A996AD3A0D95FBF21D468A1B33F8C160D8F517", "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", "7EB0509757E246F19449885651611CB965ECC1A187DD51B64FDA1EDC9637D5EC97582B9CB13DB3933705B32BA982AF5AF25FD78881EBB32771FC5922EFC66EA3", true) != 0u8 { os.exit(43i32) }
    if schnorr_case("", "D69C3509BB99E412E68B0FE8544E72837DFA30746D8BE2AA65975F29D22DC7B9", "", "4DF3C3F68FCC83B27E9D42C90431A72499F17875C81A599B566C9889B9696703", "00000000000000000000003B78CE563F89A0ED9414F5AA28AD0D96D6795F9C6376AFB1548AF603B3EB45C9F8207DEE1060CB71C04E80F593060B07D28308D7F4", true) != 0u8 { os.exit(44i32) }
    if schnorr_case("", "EEFDEA4CDB677750A420FEE807EACF21EB9898AE79B9768766E4FAA04A2D4A34", "", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", "6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E17776969E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B", false) != 0u8 { os.exit(45i32) }
    if schnorr_case("", "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", "", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", "FFF97BD5755EEEA420453A14355235D382F6472F8568A18B2F057A14602975563CC27944640AC607CD107AE10923D9EF7A73C643E166BE5EBEAFA34B1AC553E2", false) != 0u8 { os.exit(46i32) }
    if schnorr_case("", "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", "", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", "1FA62E331EDBC21C394792D2AB1100A7B432B013DF3F6FF4F99FCB33E0E1515F28890B3EDB6E7189B630448B515CE4F8622A954CFE545735AAEA5134FCCDB2BD", false) != 0u8 { os.exit(47i32) }
    if schnorr_case("", "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", "", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", "6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E177769961764B3AA9B2FFCB6EF947B6887A226E8D7C93E00C5ED0C1834FF0D0C2E6DA6", false) != 0u8 { os.exit(48i32) }
    if schnorr_case("", "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", "", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", "0000000000000000000000000000000000000000000000000000000000000000123DDA8328AF9C23A94C1FEECFD123BA4FB73476F0D594DCB65C6425BD186051", false) != 0u8 { os.exit(49i32) }
    if schnorr_case("", "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", "", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", "00000000000000000000000000000000000000000000000000000000000000017615FBAF5AE28864013C099742DEADB4DBA87F11AC6754F93780D5A1837CF197", false) != 0u8 { os.exit(50i32) }
    if schnorr_case("", "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", "", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", "4A298DACAE57395A15D0795DDBFD1DCB564DA82B0F269BC70A74F8220429BA1D69E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B", false) != 0u8 { os.exit(51i32) }
    if schnorr_case("", "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", "", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F69E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B", false) != 0u8 { os.exit(52i32) }
    if schnorr_case("", "DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659", "", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", "6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E177769FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", false) != 0u8 { os.exit(53i32) }
    if schnorr_case("", "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC30", "", "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89", "6CFF5C3BA86C69EA4B7376F31A9BCB4F74C1976089B2D9963DA2E5543E17776969E89B4C5564D00349106B8497785DD7D1D713A8AE82B32FA79D5F7FC407D39B", false) != 0u8 { os.exit(54i32) }
    if schnorr_case("0340034003400340034003400340034003400340034003400340034003400340", "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117", "0000000000000000000000000000000000000000000000000000000000000000", "", "71535DB165ECD9FBBC046E5FFAEA61186BB6AD436732FCCC25291A55895464CF6069CE26BF03466228F19A3A62DB8A649F2D560FAC652827D1AF0574E427AB63", true) != 0u8 { os.exit(55i32) }
    if schnorr_case("0340034003400340034003400340034003400340034003400340034003400340", "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117", "0000000000000000000000000000000000000000000000000000000000000000", "11", "08A20A0AFEF64124649232E0693C583AB1B9934AE63B4C3511F3AE1134C6A303EA3173BFEA6683BD101FA5AA5DBC1996FE7CACFC5A577D33EC14564CEC2BACBF", true) != 0u8 { os.exit(56i32) }
    if schnorr_case("0340034003400340034003400340034003400340034003400340034003400340", "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117", "0000000000000000000000000000000000000000000000000000000000000000", "0102030405060708090A0B0C0D0E0F1011", "5130F39A4059B43BC7CAC09A19ECE52B5D8699D1A71E3C52DA9AFDB6B50AC370C4A482B77BF960F8681540E25B6771ECE1E5A37FD80E5A51897C5566A97EA5A5", true) != 0u8 { os.exit(57i32) }
    if schnorr_case("0340034003400340034003400340034003400340034003400340034003400340", "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117", "0000000000000000000000000000000000000000000000000000000000000000", "99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999", "403B12B0D8555A344175EA7EC746566303321E5DBFA8BE6F091635163ECA79A8585ED3E3170807E7C03B720FC54C7B23897FCBA0E9D0B4A06894CFD249F22367", true) != 0u8 { os.exit(58i32) }
    try io.print("schnorr ok\n")
    // 80-85: ffdhe2048.
    var dh_secret_a: [32]u8 = hex32("101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f")
    var dh_secret_b: [32]u8 = hex32("505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f")
    var public_a: [256]u8 = zero
    var public_b: [256]u8 = zero
    var secret_out: [256]u8 = zero
    let (pa_len, pa_error) = kx.dh_public(a, dh_secret_a[0..], public_a[0..])
    if pa_error != ok || pa_len != 256usize || !same_hex(public_a[0..], "45a70603e614cedc34e8c84749ce83f065580d5dc6c4159b602b66575eb5b099d597f8c1e5cbe9f7417b4f887b01d896777678a8b3b88b3d826addc60c2844371e4127023ca5488a687cc19feab9e75564d950094de42282e0f45a3abd5f573b115de3be75eddaffb3672b42ce831e9cbadf11ac1b4b3ebcc98232246c7125ff577830f2f22a648a1782678f6b6b9ec6ccf6afc0f70312bd9cbc60d0849b84b4203c18e950bc222c8f779d6d1f6a4c4976f4396dd7d810d798166500475521064862d52deaac9cdabc2c99e94c8cf51e27e3d784bb6af1c0c8368b8c8396c0c89cc4952e69ab2cdc9b4d619dc67277bdb64a32f08b20053935051ba771a79ef9") { os.exit(80i32) }
    let (pb_len, pb_error) = kx.dh_public(a, dh_secret_b[0..], public_b[0..])
    if pb_error != ok || pb_len != 256usize || !same_hex(public_b[0..], "182456d31daef8648d16397597f9f3b18cc6429d56940cb8f7f12532e732c77db03be5a65a2839aa94097960add229e71a466586c738432889445f628f94cc14ce8252fc28d42e5cf16e162793967ea367021fc8d4743152061a8f828ce75ee5cf196eb91bab5c639922b36f0c4da6389317e38f29c8e686fe460d2256a7087bcd676820785c9c65ca3b036d7e0848695d189949697d06faab8e380cb89649c9762ea8df5db1fd02e0238daf8ae7d946fbc37658ca8ae261728ce0370592c931235b415c6f16f26804a4e4ef15657c26071a4a54e41d1b0087a5eacdc8e08d7549c80c0cd8bc88bcc08782752279d7961326bcc620f1b04e996f485d138f46f3") { os.exit(81i32) }
    let (sa_len, sa_error) = kx.dh_shared(a, dh_secret_a[0..], public_b[0..], secret_out[0..])
    if sa_error != ok || sa_len != 256usize || !same_hex(secret_out[0..], "09cd97fcfda28add68edcf9f0bfc6fef1b2a00da2efe9925e1d30302bc67ad26baa1820c8f19385f6938db9e9e950327b119c4cde511eba03ac8852933434082264c49573fb5815dee648205881fab36a5bc52b8e0896ab2e8cb95a4a82aa9e7e0323a57eb02eff2ec2dcfb0d5f19c1e0d0085423030533270c5c710c8831bb1fa4e2a2f3152e71e93f4438fd62db536bc7402c4790d9ff94814b0b1dae34f8e15a97895a092f247a707f622de303f711619d623fc87f3651c4d809c30b28785615f4243e327e068cc00cb8024ccd51311255e437ae716062a5f138d2a9b0bafe2842d110a11406e17b78f714aeefbadb86123c5b7ef145c890431d71e936997") { os.exit(82i32) }
    let (sb_len, sb_error) = kx.dh(a, dh_secret_b[0..], public_a[0..], secret_out[0..])
    if sb_error != ok || sb_len != 256usize || !same_hex(secret_out[0..], "09cd97fcfda28add68edcf9f0bfc6fef1b2a00da2efe9925e1d30302bc67ad26baa1820c8f19385f6938db9e9e950327b119c4cde511eba03ac8852933434082264c49573fb5815dee648205881fab36a5bc52b8e0896ab2e8cb95a4a82aa9e7e0323a57eb02eff2ec2dcfb0d5f19c1e0d0085423030533270c5c710c8831bb1fa4e2a2f3152e71e93f4438fd62db536bc7402c4790d9ff94814b0b1dae34f8e15a97895a092f247a707f622de303f711619d623fc87f3651c4d809c30b28785615f4243e327e068cc00cb8024ccd51311255e437ae716062a5f138d2a9b0bafe2842d110a11406e17b78f714aeefbadb86123c5b7ef145c890431d71e936997") { os.exit(83i32) }
    var one: [1]u8 = [1]u8{ 1 }
    if kx.dh_valid_public(a, one[0..]) { os.exit(84i32) }
    let (_, bad_error) = kx.dh_shared(a, dh_secret_a[0..], one[0..], secret_out[0..])
    if bad_error != kx.InvalidKey { os.exit(85i32) }
    try io.print("dh ok\n")
    // 90-95: RSA-PSS and PKCS#1 v1.5 over a 2048-bit key.
    var rsa_n: [256]u8 = zero
    var rsa_d: [256]u8 = zero
    var rsa_e: [3]u8 = zero
    var rsa_sig: [256]u8 = zero
    let _ = unhex("b6cd06af5f7b675d60a46856b2c45f6443325aa396456890679cdaaab58daaa175e14a00f0557b6c387ad0617cd5a8b65fc2cb28b2c1ab750f8bb25bd9334ef40d359d23b12e28291a79e9b6b27e87259be798c26b1ecc197dace7aa60069b113f989645a8ae18393e56dcde10362723d59860d96621b54264a574eff84faae7142268fbb9ceb6ac122619544f888febbdafb96bc3c5b5164a45a5a9cf4600175c76da4553d52dac48a4e3ef80bcbfe7ba5fa898d28811d641c36592f90f9ee6807996f6d3e4e79eb09cee26c66f87801dada6519d5950bcfee61972bf0f827d8ad763db9d9fab16b6020007178c9365e8a62cf003d8741d2c87036ede93d951", rsa_n[0..])
    let _ = unhex("0a7ecf8732a5786c0f5029306f1fa0b57639362485cc72e2359cb71e4d81b67e02315ee91a63620c76dab04ba499f4cf91c4729b21d646449891a5fa29888d5c2c44fb8270da0c52bdd32994c47f48bda34ba304e897125355589fcd73a9756e42573dab7eb18e30fd300a0ad2e5f50dd4e5e48b9ed6491ca8802a6c5bb6a1427dbb012a08a49118af9303e629b7c6e5b3b97280c6cd7b9ad11e064d248692658716431cdf2dc8a12dc692832404de6e88587a9de36cf3914f10da1dabae2fe0e713fecdec3983425e9e6e97edecc792bfb650bc4755791002f95c6d526831c180fa30a5890ac319337bdd8cb342473a6158d43068974c0aa76b6d326d345f75", rsa_d[0..])
    let _ = unhex("010001", rsa_e[0..])
    var salt: [32]u8 = zero
    var si = 0usize
    while si < 32usize {
        salt[si] = u8(si + 1usize)
        si += 1usize
    }
    let (rsa_len, rsa_error) = sign.rsa_pss_sign(a, rsa_n[0..], rsa_d[0..], "The quick brown fox jumps over the lazy dog", salt[0..], rsa_sig[0..])
    if rsa_error != ok || rsa_len != 256usize || !same_hex(rsa_sig[0..], "2fbbfafb87d492b5a757eac47e4b1693cb71afdf9592c3de7ee5a53eeb8ad4411792ec1e3e0199c8e4fe2ba2e3b43bd1bcdd2bb93815a03de1d9ca24ed61b57a266560049269da5949897ea8793f0487cdd39b85362f32b636bfc8b06188e0067119caa42aa71573a0b0d9c82b97d6cda7be6bbecbccb5a753f27781dc482a7beec33bb036c031b291d5bd8b1bc97b62a4a39b3c41d217aa2d584351ee72f21031b406d4d2fded7c2f2d0ca65e191ed55233c8a54c557f5c803428ffe88f0d726ac17bd139c8a72784b65b69a6dedeb9fd76ff096ab0aba2dda4baa6d3ebb7eca1870c9b8af8878ee1d1fc1cbe2e258c46cdcefe7e7f51f6a9c09f93815e4dc4") { os.exit(90i32) }
    if !sign.rsa_pss_verify(a, rsa_n[0..], rsa_e[0..], "The quick brown fox jumps over the lazy dog", rsa_sig[0..]) { os.exit(91i32) }
    let _ = unhex("378284c477481101cd8197fd2f66514280e1a579bb737a3d2c00f021038c58c27a0a1f6f9c12db1e968b19c084fac7143679d0be5a1543ac4e80e7cc8e988fea5ed63d71b35fbc1346903cc6840a507687bd61ac126660c020c98edcb498aab250691731735749531c0457b5aa5859a3154eb16b3d366b1a5ebe7d870febdf7aea4e10e185cfbbc73c68db7c2fbfae9a45e4aacc80ce2f1bb4a633734d3e6538f935235d2fabbb7f748ee54750153b187b075a5b9ecf0ef8002b046bc0db8b1a41435f0dcd65260d38e939a964f6f89431bbe212c677e7df8a6a77c149a2d7df92887153b4d62dce3fc33a07b524db4719b185dfd74ccade879892daba3eff44", rsa_sig[0..])
    if !sign.rsa_pss_verify(a, rsa_n[0..], rsa_e[0..], "another message", rsa_sig[0..]) { os.exit(92i32) }
    rsa_sig[100] = rsa_sig[100] ^ 1u8
    if sign.rsa_pss_verify(a, rsa_n[0..], rsa_e[0..], "another message", rsa_sig[0..]) { os.exit(93i32) }
    let _ = unhex("3fb76bf07b18baaeba5c095a6d34fd30d35f0674757e1991af082dc185ef74264e0b9f49bc3b1b21e3318413da926329e885fab7a6ec29e2a9e902b0e33b1455df238561034b7ce8b66b0f709a0281b51e971c48806ae66b08c000ea182ab6f69ad59518f2c2a2d3edcdef743073fca4a00a5ce0f4e1e6573ea6f933535b95b903ba9572c839517e16433f298c2a33f32d82473070bbbe3b3b1da87660a8721c2d5381cc3daa796fc4f1e1d8a6e1311e5962f2082c848791685c8df51bdac3e21e1125aaeca6cc5b171252c02615371b6f75bbb507200fdea9b0310fbef7860ae36d0379a22e827ba8d20e211d4a5d4144e17449a68dcb6e55a2eaac925c41ae", rsa_sig[0..])
    if !sign.rsa_pkcs1v15_verify(a, rsa_n[0..], rsa_e[0..], "The quick brown fox jumps over the lazy dog", rsa_sig[0..]) { os.exit(94i32) }
    if sign.rsa_pkcs1v15_verify(a, rsa_n[0..], rsa_e[0..], "another message", rsa_sig[0..]) { os.exit(95i32) }
    try io.print("crypto sign plan ok\n")
    ret ok
}
