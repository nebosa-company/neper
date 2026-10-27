// `x.khronos.gl`: OpenGL 3.3 to 4.6 core and OpenGL ES 3.0 to 3.2 as one table of entry points
// (D5877, D5883, D5885). A context module makes a context current and hands `load` its way of
// finding an entry point by C name; `load` fills the table and checks that every entry the
// profile requires was found. An entry outside the profile is filled when the driver has it and
// left 0 when it does not, and calling a 0 entry faults, as it does in C.
//
// Names drop the `gl`/`GL_` prefix: `glTexImage2D` is `tex_image_2d`, `GL_TEXTURE_2D` is
// `TEXTURE_2D`. Constants carry the registry's GLenum type, `u32`, unless the value needs more;
// a parameter declared `GLint` takes `i32(X)`. `void *` is `*void`, any other pointer is typed,
// and a pointer to pointers is a `usize` address.

use e.mem

error Unsupported
error Failed

type Profile = enum u8 { Gl33Core, Gl43Core, Gl46Core, Gles30, Gles31, Gles32 }

// The address of the entry point named in C, or 0; `context` is the resolver's own.
type Resolve = fn(*mem.Arena, usize, str) -> usize

type AddressPun = union { pointer: *u8, bits: usize }
type OffsetPun = union { pointer: *void, bits: usize }

var missing_name: str = zero

fn profile_bit(profile: Profile) -> u8 {
    if profile == .Gl33Core { ret 1u8 }
    if profile == .Gl43Core { ret 2u8 }
    if profile == .Gl46Core { ret 4u8 }
    if profile == .Gles30 { ret 8u8 }
    if profile == .Gles31 { ret 16u8 }
    ret 32u8
}

fn fetch(a: *mem.Arena, resolve: Resolve, context: usize, index: usize, name: str, required: u8) -> err {
    var address = resolve(a, context, name)
    // A core entry some drivers still export only under the extension it came from (Intel's GL 4.6 has
    // glGetnTexImageARB, not glGetnTexImage): the suffixed names are asked before the entry counts as missing.
    if address == 0usize { address = suffixed(a, resolve, context, name, "ARB") }
    if address == 0usize { address = suffixed(a, resolve, context, name, "KHR") }
    if address == 0usize { address = suffixed(a, resolve, context, name, "EXT") }
    procs[index] = address
    if address == 0usize && required != 0u8 {
        missing_name = name
        ret Unsupported
    }
    ret ok
}

fn suffixed(a: *mem.Arena, resolve: Resolve, context: usize, name: str, suffix: str) -> usize {
    var buffer: [96]u8 = zero
    if name.len + suffix.len > buffer.len { ret 0usize }
    var k = 0usize
    while k < name.len {
        buffer[k] = name[k]
        k += 1usize
    }
    var s = 0usize
    while s < suffix.len {
        buffer[k + s] = suffix[s]
        s += 1usize
    }
    ret resolve(a, context, buffer[0usize..name.len + suffix.len])
}

// Fills the table from the current context. `Unsupported` names the first entry point the
// profile requires and the driver lacks, through `missing`.
fn load(a: *mem.Arena, profile: Profile, resolve: Resolve, context: usize) -> err {
    missing_name = ""
    ret load_entries(a, resolve, context, profile_bit(profile))
}

fn missing() -> str { ret missing_name }

// Whether the driver supplied the entry in slot `entry` (a `*_ENTRY` constant): the check
// before calling one the loaded profile does not require.
fn present(entry: usize) -> bool { ret entry < ENTRY_COUNT && procs[entry] != 0usize }

// A buffer offset where the API takes `const void *`, as `vertex_attrib_pointer`'s last argument.
fn offset(n: usize) -> *void {
    var pun: OffsetPun = zero
    pun.bits = n
    ret pun.pointer
}

// The bytes of a C string the driver owns, borrowed; empty for a null pointer.
fn c_text(p: *const u8) -> str {
    var pun: AddressPun = zero
    pun.bits = mem.address_of(p)
    if pun.bits == 0usize { ret "" }
    var region: mem.Arena = zero
    region.base = pun.pointer
    region.cap = 65536usize
    region.off = 0usize
    let bytes = mem.view(&region, 0usize, 65536usize)
    var n = 0usize
    while n < 65536usize && bytes[n] != 0u8 { n += 1usize }
    ret bytes[0usize..n]
}

// The current context's version from GL_VERSION: major, minor, and whether it is OpenGL ES.
fn version() -> (u32, u32, bool, err) {
    let words = c_text(get_string(VERSION))
    var at = 0usize
    var es = false
    let prefix = "OpenGL ES "
    if words.len >= prefix.len && mem.eq[u8](words[0usize..prefix.len], prefix) {
        es = true
        at = prefix.len
    }
    var major = 0u32
    var minor = 0u32
    var digits = 0usize
    while at < words.len && words[at] >= 48u8 && words[at] <= 57u8 {
        major = major * 10u32 + u32(words[at] - 48u8)
        at += 1usize
        digits += 1usize
    }
    if digits == 0usize || at >= words.len || words[at] != 46u8 { ret (0u32, 0u32, es, Failed) }
    at += 1usize
    digits = 0usize
    while at < words.len && words[at] >= 48u8 && words[at] <= 57u8 {
        minor = minor * 10u32 + u32(words[at] - 48u8)
        at += 1usize
        digits += 1usize
    }
    if digits == 0usize { ret (0u32, 0u32, es, Failed) }
    ret (major, minor, es, ok)
}

// Whether the current context lists `name` among GL_EXTENSIONS.
fn has_extension(name: str) -> bool {
    var count = 0i32
    get_integerv(NUM_EXTENSIONS, &count)
    var k = 0i32
    while k < count {
        if mem.eq[u8](c_text(get_stringi(EXTENSIONS, u32(k))), name) { ret true }
        k += 1i32
    }
    ret false
}
