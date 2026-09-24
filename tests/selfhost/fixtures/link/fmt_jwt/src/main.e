// `e.fmt.jwt`: the RFC 7515 Appendix A.1 token splits, decodes and verifies under the
// RFC's key; PyJWT's HS256/HS384/HS512 tokens verify with the right key and fail with a
// wrong key, a flipped payload byte and a mismatched expectation; `alg: none` is refused;
// PyJWT's EdDSA token verifies; `claims_check` applies exp/nbf/iss/aud with leeway; and
// signing reproduces every PyJWT token byte for byte. Each check exits with its own code.
// Expected values: scratchpad/fmt_jwt/ref.py (PyJWT + cryptography).

use e.bytes
use e.crypto.sign as sign
use e.fmt.jwt
use e.io
use e.mem
use e.os
use e.str

fn hs_token(alg: jwt.Alg) -> str {
    if alg == .HS256 { ret "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWV9.DcF7CyEEgrhb_qZcyANClathfzglCCqW-R1ffE5fp80" }
    if alg == .HS384 { ret "eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWV9.kpKTtvFmJZ1864JAmSLS5y4kwAiK4HTdYjduIN6xVIi9Zj6pRgZRNGKgEylCoq-a" }
    ret "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWV9.xullzI-D-37t7YMlJWodRPlTW5bJwC5eg3ccPh_V1f1hV_AirPwiNLhKnCaLQhgov8drR5nB6kCfplVAjYmpkQ"
}

fn hs_header(alg: jwt.Alg) -> str {
    if alg == .HS256 { ret "{\"alg\":\"HS256\",\"typ\":\"JWT\"}" }
    if alg == .HS384 { ret "{\"alg\":\"HS384\",\"typ\":\"JWT\"}" }
    ret "{\"alg\":\"HS512\",\"typ\":\"JWT\"}"
}

fn payload_text() -> str { ret "{\"sub\":\"1234567890\",\"name\":\"John Doe\",\"admin\":true}" }
fn hs_key() -> str { ret "secret-key-0123456789" }
fn ed_token() -> str { ret "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWV9.lP_S2ds1UQP1y5H_cG5z4uB4FBRsOUGiu-kTRrEbYai7aIVP_JRxHOEjutK0vNZ7-ub9WIzPwg-hsA9LFnhPDw" }

// The token with one payload character replaced (still base64url).
fn tamper(token: str, dst: []u8) -> str {
    mem.copy[u8](dst[..token.len], token)
    let (parts, _) = jwt.split(token)
    let i = parts.header.len + 1usize + parts.payload.len / 2usize
    if dst[i] == 65u8 { dst[i] = 66u8 } else { dst[i] = 65u8 }
    ret dst[..token.len]
}

fn main(a: *mem.Arena, args: []str) -> err {
    var buffer: [512]u8 = zero
    var buffer2: [512]u8 = zero
    var key_bytes: [64]u8 = zero

    // 1: RFC 7515 Appendix A.1.
    let rfc = "eyJ0eXAiOiJKV1QiLA0KICJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    let (parts, split_error) = jwt.split(rfc)
    if split_error != ok || parts.header.len != 40usize || parts.signature.len != 43usize { os.exit(1i32) }
    let (rfc_header, header_error) = jwt.header(rfc, buffer[0..])
    if header_error != ok || !str.starts_with(rfc_header, "{\"typ\":\"JWT\",\r\n \"alg\"") { os.exit(1i32) }
    let (rfc_alg, alg_error) = jwt.algorithm(rfc_header)
    if alg_error != ok || rfc_alg != .HS256 { os.exit(1i32) }
    let (rfc_key, key_error) = bytes.base64_decode(key_bytes[0..], "AyM1SysPpbyDfgZld3umj1qzKObwVMkoqQ-EstJQLr_T-1qS0gZH75aKtMN3Yj0iPS4hcgUuTwjAzZr1Z9CAow", .Url)
    if key_error != ok || rfc_key.len != 64usize { os.exit(1i32) }
    let (rfc_good, rfc_error) = jwt.verify(rfc, rfc_key, .HS256)
    if rfc_error != ok || !rfc_good { os.exit(1i32) }
    let (rfc_payload, payload_error) = jwt.payload(rfc, buffer2[0..])
    if payload_error != ok || jwt.claims_check(rfc_payload, 1300819000i64, "joe", "", 0i64) != ok { os.exit(1i32) }
    if jwt.claims_check(rfc_payload, 1300819380i64, "joe", "", 0i64) != jwt.Expired { os.exit(1i32) }
    let (_, bad_split) = jwt.split("a.b")
    if bad_split != jwt.Malformed { os.exit(1i32) }
    let (_, padded) = jwt.header("eyJ0eXAiOiJKV1QifQ==.e30.", buffer[0..])
    if padded != jwt.Malformed { os.exit(1i32) }

    // 2: PyJWT HMAC tokens.
    var algs: [3]jwt.Alg = [3]jwt.Alg{ .HS256, .HS384, .HS512 }
    var k = 0usize
    while k < 3usize {
        let alg = algs[k]
        let token = hs_token(alg)
        let (good, e) = jwt.verify(token, hs_key(), alg)
        if e != ok || !good { os.exit(2i32) }
        let (wrong_key, e2) = jwt.verify(token, "secret-key-0123456780", alg)
        if e2 != ok || wrong_key { os.exit(2i32) }
        let (flipped, e3) = jwt.verify(tamper(token, buffer[0..]), hs_key(), alg)
        if e3 != ok || flipped { os.exit(2i32) }
        var other: jwt.Alg = .HS256
        if alg == .HS256 { other = .HS512 }
        let (mismatched, e4) = jwt.verify(token, hs_key(), other)
        if e4 != ok || mismatched { os.exit(2i32) }
        k += 1usize
    }

    // 3: alg none is never accepted.
    let none_token = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiYWRtaW4iOnRydWV9."
    let (none_header, _) = jwt.header(none_token, buffer[0..])
    let (none_alg, none_alg_error) = jwt.algorithm(none_header)
    if none_alg_error != ok || none_alg != .None { os.exit(3i32) }
    let (_, none_error) = jwt.verify(none_token, hs_key(), .None)
    if none_error != jwt.Unsupported { os.exit(3i32) }
    let (none_as_hs, none_hs_error) = jwt.verify(none_token, hs_key(), .HS256)
    if none_hs_error != ok || none_as_hs { os.exit(3i32) }
    let (_, unknown) = jwt.algorithm("{\"alg\":\"RS256\"}")
    if unknown != jwt.Unsupported { os.exit(3i32) }

    // 4: EdDSA.
    let (public_bytes, public_error) = bytes.base64_decode(key_bytes[0..], "A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg", .Url)
    if public_error != ok || public_bytes.len != 32usize { os.exit(4i32) }
    var public: sign.Ed25519PublicKey = zero
    mem.copy[u8](public.bytes[0..], public_bytes)
    let (ed_good, ed_error) = jwt.verify_ed25519(ed_token(), public)
    if ed_error != ok || !ed_good { os.exit(4i32) }
    let (ed_raw, ed_raw_error) = jwt.verify(ed_token(), public_bytes, .EdDSA)
    if ed_raw_error != ok || !ed_raw { os.exit(4i32) }
    let (ed_flipped, ed_flip_error) = jwt.verify_ed25519(tamper(ed_token(), buffer[0..]), public)
    if ed_flip_error != ok || ed_flipped { os.exit(4i32) }
    let (ed_as_hs, ed_hs_error) = jwt.verify(ed_token(), public_bytes, .HS256)
    if ed_hs_error != ok || ed_as_hs { os.exit(4i32) }

    // 5: claims.
    let claims = "{\"iss\":\"issuer.example\",\"aud\":[\"svc-a\",\"svc-b\"],\"exp\":1700000600,\"nbf\":1700000000,\"iat\":1699999990}"
    if jwt.claims_check(claims, 1700000300i64, "issuer.example", "svc-b", 0i64) != ok { os.exit(5i32) }
    if jwt.claims_check(claims, 1700000600i64, "issuer.example", "svc-a", 0i64) != jwt.Expired { os.exit(5i32) }
    if jwt.claims_check(claims, 1700000610i64, "issuer.example", "svc-a", 30i64) != ok { os.exit(5i32) }
    if jwt.claims_check(claims, 1699999999i64, "issuer.example", "svc-a", 0i64) != jwt.NotYetValid { os.exit(5i32) }
    if jwt.claims_check(claims, 1699999999i64, "issuer.example", "svc-a", 1i64) != ok { os.exit(5i32) }
    if jwt.claims_check(claims, 1700000300i64, "issuer.example", "svc-c", 0i64) != jwt.WrongAudience { os.exit(5i32) }
    if jwt.claims_check(claims, 1700000300i64, "other", "svc-a", 0i64) != jwt.WrongIssuer { os.exit(5i32) }
    if jwt.claims_check(claims, 1700000300i64, "", "", 0i64) != ok { os.exit(5i32) }
    let claims2 = "{\"iss\":\"issuer.example\",\"aud\":\"svc-a\",\"exp\":1700000600,\"nbf\":1700000000}"
    if jwt.claims_check(claims2, 1700000300i64, "", "svc-a", 0i64) != ok { os.exit(5i32) }
    if jwt.claims_check(claims2, 1700000300i64, "", "svc-b", 0i64) != jwt.WrongAudience { os.exit(5i32) }
    if jwt.claims_check("{\"exp\":\"soon\"}", 0i64, "", "", 0i64) != jwt.Malformed { os.exit(5i32) }
    if jwt.claims_check("{\"sub\":1", 0i64, "", "", 0i64) != jwt.Malformed { os.exit(5i32) }
    if jwt.claims_check("{\"\\u0065xp\":0}", 1i64, "", "", 0i64) != jwt.Malformed { os.exit(5i32) }
    if jwt.claims_check("{\"exp\":1700000600,\"exp\":0}", 1i64, "", "", 0i64) != jwt.Malformed { os.exit(5i32) }
    let (_, duplicate_alg) = jwt.algorithm("{\"alg\":\"HS256\",\"alg\":\"none\"}")
    if duplicate_alg != jwt.Malformed { os.exit(5i32) }
    // Unused/custom claims are still one unambiguous JSON object.
    if jwt.claims_check("{\"sub\":\"alice\",\"sub\":\"admin\"}", 1i64, "", "", 0i64) != jwt.Malformed { os.exit(7i32) }
    if jwt.claims_check("{}trailing", 1i64, "", "", 0i64) != jwt.Malformed { os.exit(7i32) }
    if jwt.claims_check("{\"exp\":2000}{}", 1i64, "", "", 0i64) != jwt.Malformed { os.exit(7i32) }
    if jwt.claims_check("{\"custom\":garbage}", 1i64, "", "", 0i64) != jwt.Malformed { os.exit(7i32) }
    if jwt.claims_check("{\"custom\":01}", 1i64, "", "", 0i64) != jwt.Malformed { os.exit(7i32) }
    if jwt.claims_check("{\"custom\":\"\\q\"}", 1i64, "", "", 0i64) != jwt.Malformed { os.exit(7i32) }
    if jwt.claims_check("{\"custom\":\"\\ud800\"}", 1i64, "", "", 0i64) != jwt.Malformed { os.exit(7i32) }
    if jwt.claims_check("{\"custom\":\"\xff\"}", 1i64, "", "", 0i64) != jwt.Malformed { os.exit(7i32) }
    if jwt.claims_check("\x0b{}", 1i64, "", "", 0i64) != jwt.Malformed { os.exit(7i32) }
    if jwt.claims_check("{\"custom\":{\"list\":[true,false,null,1.5e+2,\"\\ud83d\\ude00\"]}} \n", 1i64, "", "", 0i64) != ok { os.exit(7i32) }
    let (_, duplicate_custom) = jwt.algorithm("{\"alg\":\"HS256\",\"kid\":\"one\",\"kid\":\"two\"}")
    if duplicate_custom != jwt.Malformed { os.exit(7i32) }
    var many_claims: [1033]u8 = zero
    many_claims[0] = 123u8
    var claim_at = 0usize
    while claim_at < 129usize {
        let at = 1usize + claim_at * 8usize
        many_claims[at] = 34u8
        many_claims[at + 1usize] = 48u8 + u8(claim_at / 100usize)
        many_claims[at + 2usize] = 48u8 + u8((claim_at / 10usize) % 10usize)
        many_claims[at + 3usize] = 48u8 + u8(claim_at % 10usize)
        many_claims[at + 4usize] = 34u8
        many_claims[at + 5usize] = 58u8
        many_claims[at + 6usize] = 48u8
        many_claims[at + 7usize] = 44u8
        claim_at += 1usize
    }
    many_claims[1024] = 125u8
    if jwt.claims_check(many_claims[..1025usize], 1i64, "", "", 0i64) != ok { os.exit(7i32) }
    many_claims[1024] = 44u8
    many_claims[1032] = 125u8
    if jwt.claims_check(many_claims[..], 1i64, "", "", 0i64) != jwt.Malformed { os.exit(7i32) }

    // 6: signing reproduces PyJWT byte for byte.
    let (n256, sign_error) = jwt.sign_hs256(hs_header(.HS256), payload_text(), hs_key(), buffer[0..])
    if sign_error != ok || !str.eq(buffer[..n256], hs_token(.HS256)) { os.exit(6i32) }
    let (n384, sign384_error) = jwt.sign_hmac(hs_header(.HS384), payload_text(), hs_key(), .HS384, buffer[0..])
    if sign384_error != ok || !str.eq(buffer[..n384], hs_token(.HS384)) { os.exit(6i32) }
    let (n512, sign512_error) = jwt.sign_hmac(hs_header(.HS512), payload_text(), hs_key(), .HS512, buffer[0..])
    if sign512_error != ok || !str.eq(buffer[..n512], hs_token(.HS512)) { os.exit(6i32) }
    let (_, header_mismatch) = jwt.sign_hmac(hs_header(.HS256), payload_text(), hs_key(), .HS512, buffer[0..])
    if header_mismatch != jwt.Unsupported { os.exit(6i32) }
    let (_, too_small) = jwt.sign_hs256(hs_header(.HS256), payload_text(), hs_key(), buffer[..100usize])
    if too_small != jwt.TooSmall { os.exit(6i32) }
    var secret: sign.Ed25519SecretKey = zero
    var b = 0usize
    while b < 32usize {
        secret.bytes[b] = u8(b)
        b += 1usize
    }
    let (n_ed, ed_sign_error) = jwt.sign_ed25519("{\"alg\":\"EdDSA\",\"typ\":\"JWT\"}", payload_text(), secret, buffer[0..])
    if ed_sign_error != ok || !str.eq(buffer[..n_ed], ed_token()) { os.exit(6i32) }

    try io.print("fmt jwt ok\n")
    ret ok
}
