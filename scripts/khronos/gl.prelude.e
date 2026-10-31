// `x.khronos.gl`: OpenGL 3.3 to 4.6 core and OpenGL ES 3.0 to 3.2 as one table of entry points
// (D5940, D5883, D5885). A context module makes a context current and hands `load` its way of
// finding an entry point by C name; `load` fills the table and checks that every entry the
// profile requires was found. An entry outside the profile is filled when the driver has it and
// left 0 when it does not, and calling a 0 entry faults, as it does in C.
//
// Names drop the `gl`/`GL_` prefix: `glTexImage2D` is `tex_image_2d`, `GL_TEXTURE_2D` is
// `TEXTURE_2D`. Constants carry the registry's GLenum type, `u32`, unless the value needs more;
// a parameter declared `GLint` takes `i32(X)`. `void *` is `*void`, any other pointer is typed,
// and a pointer to pointers is a `usize` address.

use e.atomic
use e.mem
use e.os

error Unsupported
error Failed

type Profile = enum u8 { Gl33Core, Gl43Core, Gl46Core, Gles30, Gles31, Gles32 }

// The address of the entry point named in C, or 0; `context` is the resolver's own.
type Resolve = fn(*mem.Arena, usize, str) -> usize

type AddressPun = union { pointer: *u8, bits: usize }
type OffsetPun = union { pointer: *void, bits: usize }
// A dispatch table belongs to one GL context. The native context module owns this value and
// activates it after making that context current on a thread.
type Dispatch = struct { slot: u32 }

const MAX_DISPATCHES: usize = 64usize

// Context tables and the active table for each owning host thread. A closed context releases
// its slot, so repeated short-lived GL workers do not exhaust the fixed table.
var dispatch_used: [64]Atomic[u32] = zero
var active_threads: [64]Atomic[usize] = zero
var active_slots: [64]Atomic[u32] = zero
var missing_names: [64]str = zero

fn dispatch_slot(d: *const Dispatch) -> usize {
    if d.slot == 0u32 || usize(d.slot) > MAX_DISPATCHES { ret MAX_DISPATCHES }
    ret usize(d.slot - 1u32)
}

// The table active on this host thread, or MAX_DISPATCHES before a loaded context is made
// current. A GL wrapper then calls address and preserves the old null-entry failure mode.
fn active_slot() -> usize {
    let thread = os.current_thread_id()
    if thread == 0usize { ret MAX_DISPATCHES }
    var at = 0usize
    while at < MAX_DISPATCHES {
        if atomic.load(&active_threads[at], .Acquire) == thread {
            let active = atomic.load(&active_slots[at], .Acquire)
            if active == 0u32 || usize(active) > MAX_DISPATCHES { ret MAX_DISPATCHES }
            ret usize(active - 1u32)
        }
        at += 1usize
    }
    ret MAX_DISPATCHES
}

// Select `d` for the calling host thread. An unloaded Dispatch deliberately clears any old
// table selection, because making a native context current before its gl.load must not retain a
// different context's function pointers.
fn activate(d: *const Dispatch) -> bool {
    let slot = dispatch_slot(d)
    let thread = os.current_thread_id()
    if thread == 0usize { ret false }
    var at = 0usize
    while at < MAX_DISPATCHES {
        let owner = atomic.load(&active_threads[at], .Acquire)
        if owner == thread {
            if slot == MAX_DISPATCHES {
                // Clear the slot conditionally, then clear the owner only if no concurrent
                // release or later claim has changed the mapping.
                let active = atomic.load(&active_slots[at], .Acquire)
                let (cleared, _) = atomic.cas(&active_slots[at], active, 0u32, .AcqRel, .Acquire)
                if cleared {
                    let (_, _) = atomic.cas(&active_threads[at], thread, 0usize, .AcqRel, .Acquire)
                }
            } else {
                atomic.store(&active_slots[at], u32(slot + 1usize), .Release)
            }
            ret true
        }
        if owner == 0usize && atomic.load(&active_slots[at], .Acquire) == 0u32 {
            let (won, seen) = atomic.cas(&active_threads[at], 0usize, thread, .AcqRel, .Acquire)
            if won || seen == thread {
                if slot != MAX_DISPATCHES { atomic.store(&active_slots[at], u32(slot + 1usize), .Release) }
                ret true
            }
        }
        at += 1usize
    }
    ret false
}

fn reserve(d: *Dispatch) -> usize {
    let existing = dispatch_slot(d)
    if existing != MAX_DISPATCHES { ret existing }
    var at = 0usize
    while at < MAX_DISPATCHES {
        let (won, seen) = atomic.cas(&dispatch_used[at], 0u32, 1u32, .AcqRel, .Acquire)
        if won {
            d.slot = u32(at + 1usize)
            ret at
        }
        at += 1usize
    }
    ret MAX_DISPATCHES
}

fn clear_dispatch(slot: usize) {
    if slot >= MAX_DISPATCHES { ret }
    var entry = 0usize
    while entry < ENTRY_COUNT {
        procs[slot][entry] = 0usize
        entry += 1usize
    }
    missing_names[slot] = ""
}

// Releases the table once its native context is gone. Any stale active selection is cleared
// before another context may claim the slot.
fn release(d: *Dispatch) {
    let slot = dispatch_slot(d)
    if slot == MAX_DISPATCHES {
        d.slot = 0u32
        ret
    }
    let encoded = u32(slot + 1usize)
    var at = 0usize
    while at < MAX_DISPATCHES {
        let owner = atomic.load(&active_threads[at], .Acquire)
        if owner != 0usize && atomic.load(&active_slots[at], .Acquire) == encoded {
            // The conditional exchanges leave a mapping intact if another closer or a later
            // claimant has changed this row after we observed this dispatch's slot.
            let (cleared, _) = atomic.cas(&active_slots[at], encoded, 0u32, .AcqRel, .Acquire)
            if cleared {
                let (_, _) = atomic.cas(&active_threads[at], owner, 0usize, .AcqRel, .Acquire)
            }
        }
        at += 1usize
    }
    clear_dispatch(slot)
    atomic.store(&dispatch_used[slot], 0u32, .Release)
    d.slot = 0u32
}

fn profile_bit(profile: Profile) -> u8 {
    if profile == .Gl33Core { ret 1u8 }
    if profile == .Gl43Core { ret 2u8 }
    if profile == .Gl46Core { ret 4u8 }
    if profile == .Gles30 { ret 8u8 }
    if profile == .Gles31 { ret 16u8 }
    ret 32u8
}

fn fetch(a: *mem.Arena, resolve: Resolve, context: usize, slot: usize, index: usize, name: str, required: u8) -> err {
    var entry_address = resolve(a, context, name)
    // A core entry some drivers still export only under the extension it came from (Intel's GL 4.6 has
    // glGetnTexImageARB, not glGetnTexImage): the suffixed names are asked before the entry counts as missing.
    if entry_address == 0usize { entry_address = suffixed(a, resolve, context, name, "ARB") }
    if entry_address == 0usize { entry_address = suffixed(a, resolve, context, name, "KHR") }
    if entry_address == 0usize { entry_address = suffixed(a, resolve, context, name, "EXT") }
    procs[slot][index] = entry_address
    if entry_address == 0usize && required != 0u8 {
        missing_names[slot] = name
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

// Fills `d` from the current native context. `Unsupported` names the first entry point the
// profile requires and the driver lacks, through `missing`; `d` stays active so the name remains
// observable until the context closes.
fn load(a: *mem.Arena, profile: Profile, resolve: Resolve, context: usize, d: *Dispatch) -> err {
    let slot = reserve(d)
    if slot == MAX_DISPATCHES { ret Unsupported }
    if !activate(d) {
        release(d)
        ret Unsupported
    }
    clear_dispatch(slot)
    ret load_entries(a, resolve, context, slot, profile_bit(profile))
}

fn missing() -> str {
    let slot = active_slot()
    if slot == MAX_DISPATCHES { ret "" }
    ret missing_names[slot]
}

// Whether the driver supplied the entry in slot `entry` (a `*_ENTRY` constant): the check
// before calling one the loaded profile does not require.
fn present(entry: usize) -> bool {
    let slot = active_slot()
    ret slot < MAX_DISPATCHES && entry < ENTRY_COUNT && procs[slot][entry] != 0usize
}

fn address(entry: usize) -> usize {
    let slot = active_slot()
    if slot == MAX_DISPATCHES || entry >= ENTRY_COUNT { ret 0usize }
    ret procs[slot][entry]
}

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
