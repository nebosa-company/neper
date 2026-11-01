// Round 62, lane c: a sample picture for the image, icon and avatar sheets. The renderer needs a texture to draw a
// photograph; the rig has none, so every rig uploads this procedural landscape (sky, sun, two hills) and a sheet reads
// `picture`. Derived, not a photograph: it stands in for one.

use e.gfx.image
use e.gfx.scene
use e.mem

var picture: scene.TextureId = zero

fn put(img: image.Image, x: u32, y: u32, r: u32, g: u32, b: u32) {
    let at = usize(y) * img.stride + usize(x) * 4usize
    img.pixels[at] = u8(r)
    img.pixels[at + 1usize] = u8(g)
    img.pixels[at + 2usize] = u8(b)
    img.pixels[at + 3usize] = 255u8
}

fn sample_picture(a: *mem.Arena, r: *scene.Renderer) -> err {
    let w = 96u32
    let h = 64u32
    let (img, img_error) = image.allocate(a, w, h, .Rgba8, .Premultiplied)
    if img_error != ok { ret img_error }
    var y = 0u32
    while y < h {
        var x = 0u32
        while x < w {
            // sky: light blue to pale at the horizon
            var red = 96u32 + y * 2u32
            var green = 160u32 + y
            var blue = 220u32
            let dx = i32(x) - 68i32
            let dy = i32(y) - 16i32
            if dx * dx + dy * dy < 81i32 {
                red = 255u32
                green = 214u32
                blue = 90u32
            }
            // far hill and near hill
            let far = 40i32 + (i32(x) * 3i32 % 17i32) / 2i32 - i32(x) / 12i32
            if i32(y) > far {
                red = 70u32
                green = 130u32
                blue = 110u32
            }
            let near = 50i32 - (i32(x) * 5i32 % 23i32) / 3i32 + i32(x) / 16i32
            if i32(y) > near {
                red = 40u32
                green = 96u32
                blue = 70u32
            }
            put(img, x, y, red, green, blue)
            x += 1u32
        }
        y += 1u32
    }
    let (id, up_error) = scene.upload_image(r, image.ConstImage { pixels: img.pixels, width: w, height: h, stride: img.stride, format: .Rgba8, alpha: .Premultiplied })
    if up_error != ok { ret up_error }
    picture = id
    ret ok
}
