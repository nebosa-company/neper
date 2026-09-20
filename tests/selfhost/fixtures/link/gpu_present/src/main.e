// Presentation on the CPU backend (D791): an image is a device buffer of pixels a
// kernel writes, an offscreen target hands out its back image as a frame, `present`
// orders behind the queue's work and swaps, `presented` is the snapshot, a second
// acquire before the present is refused, `resize` remakes the pair, a native surface
// is `Unsupported` here, and a closed target is stale.

use e.gpu
use e.io
use e.mem
use e.os

// A gradient: each pixel's red is its x, green its y, alpha opaque.
@gpu(8, 8)
fn fill(width: u32, height: u32, pixels: []u32) {
    let x = gpu.gid.x
    let y = gpu.gid.y
    if x >= width || y >= height { ret }
    pixels[usize(y * width + x)] = 4278190080u32 | (y << 8u32) | x
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    // An image: written in part from the host, read back whole.
    let (img, img_error) = gpu.image(q, 4u32, 3u32, .Rgba8)
    if img_error != ok || gpu.len(img.data) != 12usize || img.width != 4u32 { os.exit(3i32) }
    let patch: [4]u32 = [4]u32{ 1u32, 2u32, 3u32, 4u32 }
    if gpu.write_image(q, img, 1u32, 1u32, 2u32, 2u32, patch[0..]) != ok { os.exit(4i32) }
    if gpu.write_image(q, img, 3u32, 1u32, 2u32, 2u32, patch[0..]) != gpu.TooLarge { os.exit(5i32) }
    if gpu.write_image(q, img, 0u32, 0u32, 2u32, 1u32, patch[0..]) != gpu.TooLarge { os.exit(6i32) }
    var pixels: [12]u32 = zero
    if gpu.read_image(q, img, pixels[0..]) != ok || pixels[5] != 1u32 || pixels[6] != 2u32 || pixels[9] != 3u32 || pixels[10] != 4u32 { os.exit(7i32) }
    if gpu.release_image(q, img) != ok || gpu.read_image(q, img, pixels[0..]) != gpu.InvalidHandle { os.exit(8i32) }
    // A native surface is not the CPU device's to present.
    let (_, native_error) = gpu.open_target(q, gpu.Surface { kind: .Win32, handle: zero, context: zero }, 8u32, 8u32, .Bgra8)
    if native_error != gpu.Unsupported { os.exit(9i32) }
    // An offscreen target: nothing presented yet, a frame acquired, filled, presented.
    let (t, target_error) = gpu.open_target(q, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, 16u32, 8u32, .Rgba8)
    if target_error != ok { os.exit(10i32) }
    let (w, h) = gpu.extent(t)
    if w != 16u32 || h != 8u32 { os.exit(11i32) }
    let (_, nothing_error) = gpu.presented(t)
    if nothing_error != gpu.InvalidHandle { os.exit(12i32) }
    let (frame, frame_error) = gpu.acquire(t)
    if frame_error != ok || frame.serial != 0u64 || frame.image.width != 16u32 { os.exit(13i32) }
    let (_, again_error) = gpu.acquire(t)
    if again_error != gpu.InvalidHandle { os.exit(14i32) }
    if gpu.launch[fill](q, gpu.grid2(16usize, 8usize), 16u32, 8u32, frame.image.data) != ok { os.exit(15i32) }
    let (shown, present_error) = gpu.present(q, t, frame)
    if present_error != ok || shown.serial != 1u64 { os.exit(16i32) }
    // The presented image is the one filled; a stale frame cannot be presented again.
    let (snapshot, snapshot_error) = gpu.presented(t)
    if snapshot_error != ok { os.exit(17i32) }
    var shot: [128]u32 = zero
    if gpu.read_image(q, snapshot, shot[0..]) != ok { os.exit(18i32) }
    if shot[0] != 4278190080u32 || shot[5usize * 16usize + 7usize] != (4278190080u32 | (5u32 << 8u32) | 7u32) || shot[127] != (4278190080u32 | (7u32 << 8u32) | 15u32) { os.exit(19i32) }
    let (_, stale_error) = gpu.present(q, t, frame)
    if stale_error != gpu.InvalidHandle { os.exit(20i32) }
    // The next frame is the other image, blank until drawn; presenting it swaps.
    let (next, next_error) = gpu.acquire(t)
    if next_error != ok || next.serial != 1u64 || next.image.data.slot == snapshot.data.slot { os.exit(21i32) }
    let (_, next_shown_error) = gpu.present(q, t, next)
    if next_shown_error != ok { os.exit(22i32) }
    let (second, second_error) = gpu.presented(t)
    if second_error != ok || second.data.slot != next.image.data.slot { os.exit(23i32) }
    // Resize remakes the pair; the old images are stale.
    if gpu.resize(t, 4u32, 4u32) != ok { os.exit(24i32) }
    let (rw, rh) = gpu.extent(t)
    if rw != 4u32 || rh != 4u32 || gpu.read_image(q, snapshot, shot[0..]) != gpu.InvalidHandle { os.exit(25i32) }
    let (small, small_error) = gpu.acquire(t)
    if small_error != ok || small.image.height != 4u32 || gpu.len(small.image.data) != 16usize { os.exit(26i32) }
    // Another device's queue cannot present here.
    let (other, other_error) = gpu.open(a, .Cpu, 0u32)
    if other_error != ok { os.exit(27i32) }
    let (other_queue, other_queue_error) = gpu.queue(other)
    if other_queue_error != ok { os.exit(28i32) }
    let (_, wrong_error) = gpu.present(other_queue, t, small)
    if wrong_error != gpu.WrongDevice { os.exit(29i32) }
    if gpu.close(other) != ok { os.exit(30i32) }
    // Closed: stale afterwards.
    if gpu.close_target(t) != ok || gpu.close_target(t) != gpu.InvalidHandle { os.exit(31i32) }
    let (_, closed_error) = gpu.acquire(t)
    if closed_error != gpu.InvalidHandle { os.exit(32i32) }
    if gpu.close(device) != ok { os.exit(33i32) }
    try io.print("gpu present ok\n")
    ret ok
}
