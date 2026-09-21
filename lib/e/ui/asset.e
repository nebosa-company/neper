// `e.ui.asset` (D798): the variants of one logical asset chosen by locale, theme
// and scale from `e.asset`'s metadata alone, a font handed out as the
// executable-backed bytes it is, and a bounded cache of decoded images uploaded
// to a renderer. Selection reads nothing but the registry, so it is the same on
// every host: variants share a `base` attribute; a request is matched by locale
// first -- exact, then with subtags removed one at a time, then the empty locale
// -- then by theme, exact before `any`, then by scale, the smallest not below the
// request or else the largest, and a tie is broken by the asset's name bytes.
//
// The cache keys a texture by the selected asset's SHA-256 and the decoder's
// identity -- its function address and context -- so the same bytes decoded two
// ways are two entries. It owns its textures, not the renderer: `evict`, `clear`
// and `close` release them through the renderer they were uploaded to.

use e.asset
use e.mem
use e.gfx.image
use e.gfx.scene
use e.text.shape

type Theme = enum u8 { Any, Light, Dark }
type Request = struct { scale: f32, locale: str, theme: Theme }
type ImageDecoder = struct { ctx: *void, decode: fn(*void, *mem.Arena, []const u8) -> (image.Image, err) }
type Cache = struct { state: *void }
error Missing
error InvalidVariant
error Decode
error Full

// A decoder's identity is its function's address, read through a pun: `==` has no
// meaning for a function value and `mem.bitcast` takes no function.
type FunctionBits = union { function: fn(*void, *mem.Arena, []const u8) -> (image.Image, err), bits: usize }
type Entry = struct { live: bool, sha256: [32]u8, decoder: usize, ctx: usize, base: str, texture: scene.TextureId }
type State = struct { renderer: *scene.Renderer, entries: []Entry, count: usize, closed: bool }

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn before(a: str, b: str) -> bool {
    var i = 0usize
    while i < a.len && i < b.len {
        if a[i] != b[i] { ret a[i] < b[i] }
        i += 1usize
    }
    ret a.len < b.len
}

// ASCII-lowercased comparison, as BCP 47 tags are compared.
fn same_fold(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        var x = a[i]
        var y = b[i]
        if x >= 65u8 && x <= 90u8 { x = x + 32u8 }
        if y >= 65u8 && y <= 90u8 { y = y + 32u8 }
        if x != y { ret false }
        i += 1usize
    }
    ret true
}

// The decimal `scale` attribute as a number; `false` when it is not one.
fn parse_scale(text: str) -> (f32, bool) {
    if text.len == 0usize || text.len > 16usize { ret (0.0, false) }
    var value: f32 = 0.0
    var fraction: f32 = 0.0
    var digits = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c == 46u8 {
            if fraction != 0.0 { ret (0.0, false) }
            fraction = 1.0
        } else {
            if c < 48u8 || c > 57u8 { ret (0.0, false) }
            if fraction == 0.0 {
                value = value * 10.0 + f32(c - 48u8)
            } else {
                fraction = fraction / 10.0
                value = value + f32(c - 48u8) * fraction
            }
            digits += 1usize
        }
        i += 1usize
    }
    if digits == 0usize || !(value > 0.0) { ret (0.0, false) }
    ret (value, true)
}

// The theme attribute's meaning, `Any` when absent; another word is a bad variant.
fn theme_of(value: asset.Asset) -> (Theme, bool) {
    let (text, has_theme) = asset.attribute(value, "theme")
    if !has_theme || same(text, "any") { ret (.Any, true) }
    if same(text, "light") { ret (.Light, true) }
    if same(text, "dark") { ret (.Dark, true) }
    ret (.Any, false)
}

// How well a variant's locale matches the request: the number of subtags shared
// from the front when the variant's locale is a prefix of the request by whole
// subtags, `-1` otherwise; the empty locale is the fallback at `0`.
fn locale_rank(variant: str, request: str) -> i32 {
    if variant.len == 0usize { ret 0i32 }
    if variant.len > request.len { ret -1i32 }
    if !same_fold(variant, request[0usize..variant.len]) { ret -1i32 }
    if variant.len != request.len && request[variant.len] != 45u8 { ret -1i32 }
    var rank = 1i32
    var i = 0usize
    while i < variant.len {
        if variant[i] == 45u8 { rank += 1i32 }
        i += 1usize
    }
    ret rank
}

fn theme_rank(variant: Theme, request: Theme) -> i32 {
    if variant == request { ret 2i32 }
    if variant == .Any { ret 1i32 }
    ret -1i32
}

// Scale preference: the smallest at or above the request ranks by how little it
// exceeds it; every one below ranks lower, the largest of them best.
fn scale_better(candidate: f32, best: f32, request: f32) -> bool {
    let candidate_up = candidate >= request
    let best_up = best >= request
    if candidate_up && !best_up { ret true }
    if !candidate_up && best_up { ret false }
    if candidate_up { ret candidate < best }
    ret candidate > best
}

fn select(base: str, request: Request) -> (asset.Asset, err) {
    var chosen: asset.Asset = zero
    var found = false
    var best_locale = -1i32
    var best_theme = -1i32
    var best_scale: f32 = 0.0
    if !(request.scale > 0.0) { ret (chosen, InvalidVariant) }
    var i = 0usize
    let total = asset.count()
    while i < total {
        let (candidate, has_candidate) = asset.at(i)
        if !has_candidate { break }
        let (candidate_base, has_base) = asset.attribute(candidate, "base")
        if has_base && same(candidate_base, base) {
            let (candidate_theme, theme_ok) = theme_of(candidate)
            if !theme_ok { ret (chosen, InvalidVariant) }
            var candidate_scale: f32 = 1.0
            let (scale_text, has_scale) = asset.attribute(candidate, "scale")
            if has_scale {
                let (parsed, parsed_ok) = parse_scale(scale_text)
                if !parsed_ok { ret (chosen, InvalidVariant) }
                candidate_scale = parsed
            }
            var candidate_locale = ""
            let (locale_text, has_locale) = asset.attribute(candidate, "locale")
            if has_locale { candidate_locale = locale_text }
            let locale = locale_rank(candidate_locale, request.locale)
            let theme = theme_rank(candidate_theme, request.theme)
            if locale >= 0i32 && theme >= 0i32 {
                var take = !found
                if found && locale != best_locale { take = locale > best_locale }
                if found && locale == best_locale && theme != best_theme { take = theme > best_theme }
                if found && locale == best_locale && theme == best_theme && candidate_scale != best_scale { take = scale_better(candidate_scale, best_scale, request.scale) }
                if found && locale == best_locale && theme == best_theme && candidate_scale == best_scale { take = before(candidate.name, chosen.name) }
                if take {
                    chosen = candidate
                    found = true
                    best_locale = locale
                    best_theme = theme
                    best_scale = candidate_scale
                }
            }
        }
        i += 1usize
    }
    if !found { ret (chosen, Missing) }
    ret (chosen, ok)
}

// The font's bytes are the executable's: no copy, the id is the asset's index.
fn font(base: str, request: Request, face_index: u32) -> (shape.Font, err) {
    let (chosen, select_error) = select(base, request)
    if select_error != ok { ret (zero, select_error) }
    let value = shape.Font { id: font_id(chosen), data: chosen.bytes, face_index: face_index }
    if shape.validate_font(value) != ok { ret (zero, InvalidVariant) }
    ret (value, ok)
}

// A stable id from the asset's digest, so two fonts of one registry differ.
fn font_id(value: asset.Asset) -> shape.FontId {
    ret (u32(value.sha256[0]) << 24u32) | (u32(value.sha256[1]) << 16u32) | (u32(value.sha256[2]) << 8u32) | u32(value.sha256[3])
}

fn cache(a: *mem.Arena, renderer: *scene.Renderer, capacity: usize) -> (Cache, err) {
    if capacity == 0usize { ret (zero, Full) }
    let (states, states_error) = mem.alloc[State](a, 1usize)
    if states_error != ok { ret (zero, Full) }
    let (entries, entries_error) = mem.alloc[Entry](a, capacity)
    if entries_error != ok { ret (zero, Full) }
    var i = 0usize
    while i < capacity {
        var empty: Entry = zero
        entries[i] = empty
        i += 1usize
    }
    states[0usize] = State { renderer: renderer, entries: entries, count: 0usize, closed: false }
    ret (Cache { state: mem.cast[*void](&states[0usize]) }, ok)
}

fn state_of(texture_cache: *Cache) -> (*State, err) {
    let s = mem.cast[*State](texture_cache.state)
    if mem.address_of(s) == 0usize || s.closed { ret (s, Full) }
    ret (s, ok)
}

fn same_digest(a: [32]u8, b: [32]u8) -> bool {
    var i = 0usize
    while i < 32usize {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn texture(texture_cache: *Cache, scratch: *mem.Arena, base: str, request: Request, decoder: ImageDecoder) -> (scene.TextureId, err) {
    let (s, state_error) = state_of(texture_cache)
    if state_error != ok { ret (zero, state_error) }
    let (chosen, select_error) = select(base, request)
    if select_error != ok { ret (zero, select_error) }
    var pun: FunctionBits = zero
    pun.function = decoder.decode
    let decoder_key = pun.bits
    let ctx_key = mem.address_of(decoder.ctx)
    var i = 0usize
    while i < s.entries.len {
        let e = &s.entries[i]
        if e.live && e.decoder == decoder_key && e.ctx == ctx_key && same_digest(e.sha256, chosen.sha256) { ret (e.texture, ok) }
        i += 1usize
    }
    var slot = 0usize
    while slot < s.entries.len && s.entries[slot].live { slot += 1usize }
    if slot >= s.entries.len { ret (zero, Full) }
    // Decoded into the caller's scratch and uploaded before this returns.
    let checkpoint = mem.mark(scratch)
    let (decoded, decode_error) = decoder.decode(decoder.ctx, scratch, chosen.bytes)
    if decode_error != ok {
        mem.reset(scratch, checkpoint)
        ret (zero, Decode)
    }
    let (view, view_error) = image.make_const(decoded.pixels, decoded.width, decoded.height, decoded.stride, decoded.format, decoded.alpha)
    if view_error != ok {
        mem.reset(scratch, checkpoint)
        ret (zero, Decode)
    }
    let (uploaded, upload_error) = scene.upload_image(renderer_of(s), view)
    mem.reset(scratch, checkpoint)
    if upload_error != ok { ret (zero, Full) }
    s.entries[slot] = Entry { live: true, sha256: chosen.sha256, decoder: decoder_key, ctx: ctx_key, base: base, texture: uploaded }
    s.count += 1usize
    ret (uploaded, ok)
}

// The renderer a cache uploads to is the one given at `cache`; kept as a pointer.
fn renderer_of(s: *State) -> *scene.Renderer {
    ret s.renderer
}

fn evict(texture_cache: *Cache, renderer: *scene.Renderer, base: str) -> err {
    let (s, state_error) = state_of(texture_cache)
    if state_error != ok { ret state_error }
    var found = false
    var i = 0usize
    while i < s.entries.len {
        let e = &s.entries[i]
        if e.live && same(e.base, base) {
            let released = scene.release_image(renderer, e.texture)
            e.live = false
            s.count = s.count - 1usize
            found = true
        }
        i += 1usize
    }
    if !found { ret Missing }
    ret ok
}

fn clear(texture_cache: *Cache, renderer: *scene.Renderer) -> err {
    let (s, state_error) = state_of(texture_cache)
    if state_error != ok { ret state_error }
    var i = 0usize
    while i < s.entries.len {
        let e = &s.entries[i]
        if e.live {
            let released = scene.release_image(renderer, e.texture)
            e.live = false
        }
        i += 1usize
    }
    s.count = 0usize
    ret ok
}

fn close(texture_cache: *Cache, renderer: *scene.Renderer) -> err {
    try clear(texture_cache, renderer)
    let (s, state_error) = state_of(texture_cache)
    if state_error != ok { ret state_error }
    s.closed = true
    ret ok
}
