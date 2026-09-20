// `e.gpu` on the CPU backend (D778): the one device enumerates and opens, a queue
// takes uploads, `gpu.launch[saxpy]` runs a 1-D kernel over a grid that rounds up to
// whole workgroups with `gpu.gid` guarding the tail, a 2-D kernel sees its local and
// workgroup ids, `write` at an offset and `download` round-trip, tokens and waits
// answer, and the refusals hold: a stale handle after `release`, a short download,
// a write past the end, a token from another device, a second backend, a wrong
// index, a closed device.

use e.gpu
use e.io
use e.mem
use e.os

@gpu(256)
fn saxpy(n: u32, a: f32, x: []const f32, y: []f32) {
    let i = gpu.gid.x
    if i >= n { ret }
    let k = usize(i)
    y[k] = a * x[k] + y[k]
}

// Every invocation writes its ids where it lands in a 16x16 tile grid of 8x8 groups.
@gpu(8, 8)
fn ids(width: u32, out: []u32) {
    let x = gpu.gid.x
    let y = gpu.gid.y
    if x >= width || y >= width { ret }
    let at = usize(y * width + x)
    out[at] = (gpu.wgid.y << 24u32) | (gpu.wgid.x << 16u32) | (gpu.lid.y << 8u32) | gpu.lid.x
}

fn near(x: f32, y: f32) -> bool {
    let d = x - y
    ret d < 0.0001 && d > -0.0001
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Discovery: one CPU device, supported, no stable key; other backends absent.
    let (found, found_error) = gpu.devices(a, .Cpu, 4usize)
    if found_error != ok || found.len != 1usize || !found[0].supported || found[0].key_valid || found[0].kind != .Cpu || found[0].index != 0u32 { os.exit(1i32) }
    let (_, vulkan_error) = gpu.devices(a, .Vulkan, 4usize)
    if vulkan_error != gpu.Unsupported { os.exit(2i32) }
    let (_, limit_error) = gpu.devices(a, .Cpu, 0usize)
    if limit_error != gpu.TooLarge { os.exit(3i32) }
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(4i32) }
    let (_, index_error) = gpu.open(a, .Cpu, 1u32)
    if index_error != gpu.NoDevice { os.exit(5i32) }
    let (_, cuda_error) = gpu.open(a, .Cuda, 0u32)
    if cuda_error != gpu.Unsupported { os.exit(6i32) }
    let (_, key_error) = gpu.open_id(a, gpu.DeviceKey { backend: .Cpu, uuid: zero })
    if key_error != gpu.NoDevice { os.exit(7i32) }
    let (described, info_error) = gpu.info(a, device)
    if info_error != ok || described.capabilities.len != 5usize || !gpu.has(device, .Int64) || gpu.has(device, .Float16) { os.exit(8i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(9i32) }
    let (_, staging_error) = gpu.queue_with(device, gpu.StagingLimits { blocks: 0u32, block_bytes: 4096usize })
    if staging_error != gpu.TooLarge { os.exit(10i32) }

    // saxpy over 1000 elements: four workgroups of 256, the tail guarded.
    var x: [1000]f32 = zero
    var y: [1000]f32 = zero
    var i = 0usize
    while i < 1000usize {
        x[i] = f32(i)
        y[i] = 1.0
        i += 1usize
    }
    let (dx, dx_error) = gpu.upload[f32](q, x[0..])
    if dx_error != ok || gpu.len[f32](dx) != 1000usize { os.exit(11i32) }
    let (dy, dy_error) = gpu.upload[f32](q, y[0..])
    if dy_error != ok { os.exit(12i32) }
    let (before, before_error) = gpu.token(q)
    if before_error != ok || before.serial != 0u64 { os.exit(13i32) }
    let launch_error = gpu.launch[saxpy](q, gpu.grid1(1000usize), 1000u32, 2.0, dx, dy)
    if launch_error != ok { os.exit(14i32) }
    let (after, after_error) = gpu.token(q)
    if after_error != ok || after.serial != 1u64 || after.owner != dx.owner { os.exit(15i32) }
    let (finished, done_error) = gpu.done(after)
    if done_error != ok || !finished || gpu.wait(after) != ok || gpu.wait_for(q, after) != ok { os.exit(16i32) }
    var result: [1000]f32 = zero
    if gpu.download[f32](q, dy, result[0..]) != ok { os.exit(17i32) }
    i = 0usize
    while i < 1000usize {
        if !near(result[i], 2.0 * f32(i) + 1.0) { os.exit(18i32) }
        i += 1usize
    }
    // The source is untouched: device memory is its own.
    if !near(y[999], 1.0) { os.exit(19i32) }
    // A zero grid is an ordered no-op.
    if gpu.launch[saxpy](q, gpu.grid1(0usize), 1000u32, 5.0, dx, dy) != ok { os.exit(20i32) }
    if gpu.download[f32](q, dy, result[0..]) != ok || !near(result[1], 3.0) { os.exit(21i32) }

    // write at an offset, then a short download and a write past the end refused.
    let patch: [2]f32 = [2]f32{ 100.0, 200.0 }
    if gpu.write[f32](q, dy, 998usize, patch[0..]) != ok { os.exit(22i32) }
    if gpu.download[f32](q, dy, result[0..]) != ok || !near(result[998], 100.0) || !near(result[999], 200.0) || !near(result[997], 2.0 * 997.0 + 1.0) { os.exit(23i32) }
    if gpu.write[f32](q, dy, 999usize, patch[0..]) != gpu.TooLarge { os.exit(24i32) }
    var short: [10]f32 = zero
    if gpu.download[f32](q, dy, short[0..]) != gpu.TooLarge { os.exit(25i32) }

    // ids: a 16x16 grid of 8x8 workgroups, every invocation placed by its ids.
    let (tile, tile_error) = gpu.alloc[u32](q, 256usize)
    if tile_error != ok { os.exit(26i32) }
    if gpu.launch[ids](q, gpu.grid2(16usize, 16usize), 16u32, tile) != ok { os.exit(27i32) }
    var seen: [256]u32 = zero
    if gpu.download[u32](q, tile, seen[0..]) != ok { os.exit(28i32) }
    // (x 11, y 5): workgroup (1, 0), local (3, 5).
    if seen[5usize * 16usize + 11usize] != ((1u32 << 16u32) | (5u32 << 8u32) | 3u32) { os.exit(29i32) }
    // (x 2, y 13): workgroup (0, 1), local (2, 5).
    if seen[13usize * 16usize + 2usize] != ((1u32 << 24u32) | (5u32 << 8u32) | 2u32) { os.exit(30i32) }
    if seen[0] != 0u32 || seen[255] != ((1u32 << 24u32) | (1u32 << 16u32) | (7u32 << 8u32) | 7u32) { os.exit(31i32) }

    // Release: the handle is stale afterwards, and its slot is reused.
    if gpu.release[u32](q, tile) != ok { os.exit(32i32) }
    if gpu.download[u32](q, tile, seen[0..]) != gpu.InvalidHandle { os.exit(33i32) }
    if gpu.release[u32](q, tile) != gpu.InvalidHandle { os.exit(34i32) }
    let (again, again_error) = gpu.alloc[u32](q, 4usize)
    if again_error != ok || again.slot != tile.slot || again.generation == tile.generation { os.exit(35i32) }
    // Another device's handle is the wrong device here.
    let (other, other_error) = gpu.open(a, .Cpu, 0u32)
    if other_error != ok { os.exit(36i32) }
    let (other_queue, other_queue_error) = gpu.queue(other)
    if other_queue_error != ok { os.exit(37i32) }
    if gpu.download[f32](other_queue, dy, result[0..]) != gpu.WrongDevice { os.exit(38i32) }
    let (other_token, other_token_error) = gpu.token(other_queue)
    if other_token_error != ok || other_token.serial != 0u64 { os.exit(39i32) }
    if gpu.launch[saxpy](other_queue, gpu.grid1(1usize), 1u32, 1.0, dx, dy) != gpu.WrongDevice { os.exit(40i32) }
    if gpu.close(other) != ok || gpu.close(other) != gpu.InvalidHandle || gpu.sync(other_queue) != gpu.InvalidHandle { os.exit(41i32) }
    if gpu.has(other, .Int8) { os.exit(42i32) }
    if gpu.sync(q) != ok || gpu.close(device) != ok { os.exit(43i32) }

    try io.print("gpu cpu ok\n")
    ret ok
}
