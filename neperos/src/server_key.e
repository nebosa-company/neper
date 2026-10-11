// The device's trust anchor for generated apps (C124): the Ed25519 public key of the server that signs
// packages (scripts/make_package.py key writes this file; the development server's key from a fixed seed,
// to be replaced by the real server's).
use e.crypto.sign as sign

fn public() -> sign.Ed25519PublicKey {
    ret sign.Ed25519PublicKey { bytes: [32]u8{ 121, 181, 86, 46, 143, 230, 84, 249, 64, 120, 177, 18, 232, 169, 139, 167, 144, 31, 133, 58, 230, 149, 190, 215, 224, 227, 145, 11, 173, 4, 150, 100 } }
}
