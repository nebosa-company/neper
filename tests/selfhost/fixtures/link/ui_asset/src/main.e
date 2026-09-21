// `e.ui.asset` (D798): one logical image in four variants chosen by locale, theme
// and scale from the registry's metadata; a font as the executable's bytes; a
// texture cache keyed by the chosen asset's digest and the decoder, its entries
// evicted, cleared and closed through the renderer.

use e.asset
use e.gpu
use e.io
use e.mem
use e.os
use e.gfx.image
use e.gfx.scene
use e.text.shape
use e.ui.asset as ui_asset

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// The fixture's "codec": the bytes are 2x2 RGBA8 pixels already.
fn decode_raw(ctx: *void, a: *mem.Arena, bytes: []const u8) -> (image.Image, err) {
    if bytes.len != 16usize { ret (zero, image.Invalid) }
    let (pixels, pixels_error) = mem.alloc[u8](a, 16usize)
    if pixels_error != ok { ret (zero, pixels_error) }
    mem.copy[u8](pixels, bytes)
    let (decoded, make_error) = image.make(pixels, 2u32, 2u32, 8usize, .Rgba8, .Straight)
    ret (decoded, make_error)
}

fn decode_never(ctx: *void, a: *mem.Arena, bytes: []const u8) -> (image.Image, err) {
    ret (zero, image.Invalid)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if asset.count() != 5usize { os.exit(1i32) }
    // Selection: scale 1, no locale, any theme -> the 1x; scale 2 -> the 2x; scale 2
    // dark -> the dark 2x; scale 1.5 -> the 2x (smallest not below); scale 3 -> the
    // 2x (largest below); es-ES -> the Spanish one, es-MX falls back by subtag to
    // es, and fr to the empty locale; a light theme takes `any`.
    let plain = ui_asset.Request { scale: 1.0, locale: "", theme: .Any }
    let (one, one_error) = ui_asset.select("images/logo", plain)
    if one_error != ok || !same(one.name, "images/logo@1x") { os.exit(2i32) }
    let (two, two_error) = ui_asset.select("images/logo", ui_asset.Request { scale: 2.0, locale: "", theme: .Any })
    if two_error != ok || !same(two.name, "images/logo@2x") { os.exit(3i32) }
    let (dark, dark_error) = ui_asset.select("images/logo", ui_asset.Request { scale: 2.0, locale: "", theme: .Dark })
    if dark_error != ok || !same(dark.name, "images/logo@2x-dark") { os.exit(4i32) }
    let (between, between_error) = ui_asset.select("images/logo", ui_asset.Request { scale: 1.5, locale: "", theme: .Any })
    if between_error != ok || !same(between.name, "images/logo@2x") { os.exit(5i32) }
    let (above, above_error) = ui_asset.select("images/logo", ui_asset.Request { scale: 3.0, locale: "", theme: .Light })
    if above_error != ok || !same(above.name, "images/logo@2x") { os.exit(6i32) }
    let (spanish, spanish_error) = ui_asset.select("images/logo", ui_asset.Request { scale: 1.0, locale: "es-ES", theme: .Any })
    if spanish_error != ok || !same(spanish.name, "images/logo-es") { os.exit(7i32) }
    let (mexican, mexican_error) = ui_asset.select("images/logo", ui_asset.Request { scale: 1.0, locale: "es-MX", theme: .Any })
    if mexican_error != ok || !same(mexican.name, "images/logo@1x") { os.exit(8i32) }
    let (french, french_error) = ui_asset.select("images/logo", ui_asset.Request { scale: 2.0, locale: "fr", theme: .Any })
    if french_error != ok || !same(french.name, "images/logo@2x") { os.exit(9i32) }
    let (_, missing_error) = ui_asset.select("images/nothing", plain)
    if missing_error != ui_asset.Missing { os.exit(10i32) }
    let (_, bad_scale_error) = ui_asset.select("images/logo", ui_asset.Request { scale: 0.0, locale: "", theme: .Any })
    if bad_scale_error != ui_asset.InvalidVariant { os.exit(11i32) }
    // The font: the registry's bytes, validated, with a stable id.
    let (font, font_error) = ui_asset.font("fonts/square", plain, 0u32)
    if font_error != ok || font.data.len != 512usize || font.id == 0u32 { os.exit(12i32) }
    let (font_again, font_again_error) = ui_asset.font("fonts/square", plain, 0u32)
    if font_again_error != ok || font_again.id != font.id { os.exit(13i32) }
    let (_, not_font_error) = ui_asset.font("images/logo", plain, 0u32)
    if not_font_error != ui_asset.InvalidVariant { os.exit(14i32) }
    // The cache over a renderer.
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(15i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(16i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 2u32, 3u32)
    if renderer_error != ok { os.exit(17i32) }
    var renderer = r
    let (c, cache_error) = ui_asset.cache(a, &renderer, 2usize)
    if cache_error != ok { os.exit(18i32) }
    var cache = c
    let decoder = ui_asset.ImageDecoder { ctx: zero, decode: decode_raw }
    let (first, first_error) = ui_asset.texture(&cache, a, "images/logo", plain, decoder)
    if first_error != ok { os.exit(19i32) }
    // The same selection with the same decoder is the same texture; another
    // variant is another entry; a third is Full; a failing decoder is Decode.
    let (again, again_error) = ui_asset.texture(&cache, a, "images/logo", plain, decoder)
    if again_error != ok || again.slot != first.slot || again.generation != first.generation { os.exit(20i32) }
    let (second, second_error) = ui_asset.texture(&cache, a, "images/logo", ui_asset.Request { scale: 2.0, locale: "", theme: .Dark }, decoder)
    if second_error != ok || second.slot == first.slot { os.exit(21i32) }
    let (_, full_error) = ui_asset.texture(&cache, a, "images/logo", ui_asset.Request { scale: 1.0, locale: "es-ES", theme: .Any }, decoder)
    if full_error != ui_asset.Full { os.exit(22i32) }
    if ui_asset.evict(&cache, &renderer, "images/logo") != ok { os.exit(23i32) }
    if ui_asset.evict(&cache, &renderer, "images/logo") != ui_asset.Missing { os.exit(24i32) }
    if scene.update_image(&renderer, first, zero) != scene.Invalid { os.exit(25i32) }
    let never = ui_asset.ImageDecoder { ctx: zero, decode: decode_never }
    let (_, decode_error) = ui_asset.texture(&cache, a, "images/logo", plain, never)
    if decode_error != ui_asset.Decode { os.exit(26i32) }
    let (third, third_error) = ui_asset.texture(&cache, a, "images/logo", plain, decoder)
    if third_error != ok { os.exit(27i32) }
    if ui_asset.clear(&cache, &renderer) != ok || scene.release_image(&renderer, third) != scene.Invalid { os.exit(28i32) }
    if ui_asset.close(&cache, &renderer) != ok || ui_asset.close(&cache, &renderer) != ui_asset.Full { os.exit(29i32) }
    if scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(30i32) }
    try io.print("ui asset ok\n")
    ret ok
}
