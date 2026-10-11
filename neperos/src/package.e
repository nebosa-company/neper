// A NeperOS app package (C124, C143): what a server sends a device for a generated app, and what the device
// checks before it installs it. No I/O; the shell (or a test) hands it the bytes. The layout is
//
//     "NPKG" | version (1) | manifest length (2, little end) | manifest | image length (4, little end) |
//     image | signature (64)
//
// the signature being Ed25519 over everything before it, so a changed manifest or image fails it. The
// manifest is text, one `key=value` per line: `name`, `version`, `api` (the app kit's level), `entry`,
// `capabilities` (comma-separated: `network`, `storage`, `camera`, ...), `icon` (an SVG file name in the
// image's own directory, optional). The device verifies the signature against the server's public key
// (kept in the OS image, e.crypto.sign), checks `api`, and shows the capabilities before the first run.
use e.crypto.sign as sign

error BadPackage
error TooNew

const MAGIC: u32 = 1196770382u32
const FORMAT: u8 = 1u8
const SIGNATURE_BYTES: usize = 64usize
// The app kit's level this build of the system provides; a package asking for more is TooNew.
const API_LEVEL: usize = 1usize

type Package = struct { manifest: []const u8, image: []const u8, signed_len: usize, signature: sign.Ed25519Signature }

fn le16(data: []const u8, at: usize) -> usize {
    ret usize(data[at]) + usize(data[at + 1usize]) * 256usize
}

fn le32(data: []const u8, at: usize) -> usize {
    ret usize(data[at]) + usize(data[at + 1usize]) * 256usize + usize(data[at + 2usize]) * 65536usize + usize(data[at + 3usize]) * 16777216usize
}

// Split `data` into its parts; BadPackage when the magic, the version or a length is wrong.
fn parse(data: []const u8) -> (Package, err) {
    var p: Package = zero
    if data.len < 7usize + 4usize + SIGNATURE_BYTES { ret (p, BadPackage) }
    if data[0usize] != 78u8 || data[1usize] != 80u8 || data[2usize] != 75u8 || data[3usize] != 71u8 { ret (p, BadPackage) }
    if data[4usize] != FORMAT { ret (p, BadPackage) }
    let manifest_len = le16(data, 5usize)
    let image_at = 7usize + manifest_len
    if image_at + 4usize + SIGNATURE_BYTES > data.len { ret (p, BadPackage) }
    let image_len = le32(data, image_at)
    let image_start = image_at + 4usize
    if image_start + image_len + SIGNATURE_BYTES != data.len { ret (p, BadPackage) }
    p.manifest = data[7usize..image_at]
    p.image = data[image_start..image_start + image_len]
    p.signed_len = image_start + image_len
    var i = 0usize
    while i < SIGNATURE_BYTES {
        p.signature.bytes[i] = data[p.signed_len + i]
        i += 1usize
    }
    ret (p, ok)
}

// Whether the signature is the server's over the package's bytes (`data` is what was parsed).
fn verify(p: Package, data: []const u8, public: sign.Ed25519PublicKey) -> bool {
    ret sign.ed25519_verify(public, data[0usize..p.signed_len], p.signature)
}

// The value of `key` in the manifest, and whether there is one.
fn value(p: Package, key: str) -> ([]const u8, bool) {
    var at = 0usize
    while at < p.manifest.len {
        var end = at
        while end < p.manifest.len && p.manifest[end] != 10u8 { end += 1usize }
        // The line is manifest[at..end]: `key=value`.
        var eq = at
        while eq < end && p.manifest[eq] != 61u8 { eq += 1usize }
        if eq < end && eq - at == key.len {
            var same = true
            var k = 0usize
            while k < key.len {
                if p.manifest[at + k] != key[k] { same = false }
                k += 1usize
            }
            if same { ret (p.manifest[eq + 1usize..end], true) }
        }
        at = end + 1usize
    }
    ret (p.manifest[0usize..0usize], false)
}

fn text_is(left: []const u8, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

// Whether the manifest's `capabilities` list names `capability`.
fn declares(p: Package, capability: str) -> bool {
    let (list, found) = value(p, "capabilities")
    if !found { ret false }
    var at = 0usize
    while at <= list.len {
        var end = at
        while end < list.len && list[end] != 44u8 { end += 1usize }
        if text_is(list[at..end], capability) { ret true }
        at = end + 1usize
    }
    ret false
}

// The `api` the package needs as a number (0 when absent or not a number).
fn api_of(p: Package) -> usize {
    let (text, found) = value(p, "api")
    if !found || text.len == 0usize { ret 0usize }
    var n = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] < 48u8 || text[i] > 57u8 { ret 0usize }
        n = n * 10usize + usize(text[i] - 48u8)
        i += 1usize
    }
    ret n
}

// Everything the device checks before it installs: well-formed, signed by the server, an api this build
// provides. Returns ok or the reason.
fn check(data: []const u8, public: sign.Ed25519PublicKey) -> (Package, err) {
    let (p, parse_error) = parse(data)
    if parse_error != ok { ret (p, parse_error) }
    if !verify(p, data, public) { ret (p, BadPackage) }
    if api_of(p) == 0usize || api_of(p) > API_LEVEL { ret (p, TooNew) }
    ret (p, ok)
}
