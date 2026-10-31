// The OpenGL device's limits (L181, D5903), built with `--gpu glsl`: shared memory past MAX_COMPUTE_SHARED_MEMORY_SIZE and a
// workgroup longer along an axis than MAX_COMPUTE_WORK_GROUP_SIZE are `TooLarge` at launch, as the CPU and Vulkan answer, not
// a driver compile failure (`Unsupported`). A mebibyte of shared memory is past every device's limit; a 1 x 1 x 1024
// workgroup is past Intel's 64 along z and within llvmpipe's, where it has to run and answer correctly. A host without an
// OpenGL compute device exits 0 having printed why.
use e.gpu
use e.io
use e.mem
use e.os
use x.khronos.compute

@gpu(64)
fn crowded(out: []u32) {
    shared var big: [262144]u32
    let i = gpu.lid.x
    big[usize(i) * 4096usize] = i
    gpu.barrier()
    out[usize(gpu.gid.x)] = big[usize(i) * 4096usize]
}

@gpu(1, 1, 1024)
fn tall(out: []u32) {
    out[usize(gpu.gid.z)] = gpu.gid.z + 7u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    compute.install()
    let (found, found_error) = gpu.devices(a, .Gl, 4usize)
    if found_error == gpu.Unsupported {
        try io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    if found_error != ok {
        try io.printf["OpenGL device enumeration failed: {}\n"](found_error)
        os.exit(1i32)
    }
    if found.len == 0usize {
        try io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    let (device, open_error) = gpu.open(a, .Gl, 0u32)
    if open_error != ok { os.exit(2i32) }
    let (q, q_error) = gpu.queue(device)
    if q_error != ok { os.exit(3i32) }
    let (out, out_error) = gpu.alloc[u32](q, 1024usize)
    if out_error != ok { os.exit(4i32) }
    let crowded_error = gpu.launch[crowded](q, gpu.grid1(64usize), out)
    if crowded_error != gpu.TooLarge {
        try io.printf["a mebibyte of shared memory answered {}\n"](crowded_error)
        os.exit(5i32)
    }
    let tall_error = gpu.launch[tall](q, gpu.Grid { x: 1usize, y: 1usize, z: 1024usize }, out)
    if tall_error == gpu.TooLarge {
        try io.print("tall workgroup too large; ")
    } else {
        if tall_error != ok { os.exit(6i32) }
        var got: [1024]u32 = zero
        if gpu.download(q, out, got[0..]) != ok { os.exit(7i32) }
        var at = 0usize
        while at < 1024usize {
            if got[at] != u32(at) + 7u32 { os.exit(8i32) }
            at += 1usize
        }
        try io.print("tall workgroup ran; ")
    }
    try io.printf["limits answered on {}\n"](found[0usize].name)
    ret gpu.close(device)
}
