// The Secure vault's cryptography (vault.e, D2252) against hashlib and Python's cryptography package
// (scripts/gen_vault_test.py writes this file): the key from a password, records byte-for-byte equal to
// AES-256-GCM's, the meta file made and unlocked, and the refusals -- a wrong key, a flipped byte, another
// record name, a short record, a wrong password. Every check has its own exit code.
use e.os
use e.mem
use vault

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let salt: [16]u8 = [16]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
    let want_key: [32]u8 = [32]u8{ 201, 20, 204, 79, 6, 204, 110, 143, 70, 209, 87, 227, 161, 181, 170, 122, 188, 238, 187, 23, 187, 4, 68, 205, 76, 74, 193, 108, 162, 174, 152, 100 }
    let nonce: [12]u8 = [12]u8{ 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111 }
    let plain: [45]u8 = [45]u8{ 1, 10, 78, 101, 112, 101, 114, 32, 66, 97, 110, 107, 10, 115, 97, 109, 46, 114, 105, 118, 101, 114, 97, 21, 99, 111, 114, 114, 101, 99, 116, 45, 104, 111, 114, 115, 101, 45, 98, 97, 116, 116, 101, 114, 121 }
    let want_record: [74]u8 = [74]u8{ 1, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 190, 90, 189, 84, 169, 181, 89, 43, 147, 193, 130, 146, 52, 125, 134, 210, 159, 221, 224, 10, 242, 29, 127, 79, 162, 130, 47, 87, 180, 176, 150, 44, 225, 11, 61, 86, 95, 120, 56, 43, 155, 144, 198, 170, 17, 66, 84, 114, 64, 254, 144, 68, 200, 57, 11, 10, 53, 1, 89, 143, 75 }
    let password = "correct horse"
    let (key, derive_error) = vault.derive(password, salt[0..], 1000u32)
    if derive_error != ok || !same(key[0..], want_key[0..]) { os.exit(1) }
    var sealed: [128]u8 = zero
    let (sealed_len, seal_error) = vault.seal(key, nonce[0..], "l3", plain[0..], sealed[0..])
    if seal_error != ok || !same(sealed[..sealed_len], want_record[0..]) { os.exit(2) }
    var opened: [128]u8 = zero
    let (opened_len, open_error) = vault.open(key, "l3", want_record[0..], opened[0..])
    if open_error != ok || !same(opened[..opened_len], plain[0..]) { os.exit(3) }
    let (_n1, _e1) = vault.open(key, "l4", want_record[0..], opened[0..])
    if _e1 != vault.WrongPassword { os.exit(4) }
    var other_key = key
    other_key[0] = other_key[0] ^ 1u8
    let (_n2, _e2) = vault.open(other_key, "l3", want_record[0..], opened[0..])
    if _e2 != vault.WrongPassword { os.exit(5) }
    var damaged: [128]u8 = zero
    var di = 0usize
    while di < want_record.len {
        damaged[di] = want_record[di]
        di += 1usize
    }
    damaged[20] = damaged[20] ^ 1u8
    let (_n3, _e3) = vault.open(key, "l3", damaged[..want_record.len], opened[0..])
    if _e3 != vault.WrongPassword { os.exit(6) }
    let (_n4, _e4) = vault.open(key, "l3", want_record[..10], opened[0..])
    if _e4 != vault.Damaged { os.exit(7) }
    var meta: [80]u8 = zero
    let (meta_len, meta_error) = vault.meta_make(key, salt[0..], 1000u32, nonce[0..], meta[0..])
    if meta_error != ok || meta_len != 64usize || vault.meta_iterations(meta[..meta_len]) != 1000u32 { os.exit(8) }
    let (unlocked, unlock_error) = vault.meta_unlock(meta[..meta_len], password)
    if unlock_error != ok || !same(unlocked[0..], want_key[0..]) { os.exit(9) }
    let (_n5, _e5) = vault.meta_unlock(meta[..meta_len], "correct horsf")
    if _e5 != vault.WrongPassword { os.exit(10) }
    let (_n6, _e6) = vault.meta_unlock(meta[..20], password)
    if _e6 != vault.Damaged { os.exit(11) }
    os.exit(0)
    ret ok
}
