// The MSL emitter's output run (C193, D5232): `neper emit-executable saxpy.e . msl none out.metal` wrote the text below from
// examples/saxpy.e's kernel. It is compiled by Metal at run time and dispatched over one heap buffer (a fault word block, then x and
// y at 64-byte offsets) with the SPIR-V launch ABI's argument block, and the answer is checked on the CPU. A machine with no
// Metal device says so and passes. macOS only.
use e.mem
use e.os
use e.gpu.metal as mtl

fn word(bytes: []u8, index: usize) -> f32 {
    var holder: [1]f32 = zero
    let copied = os.raw_memcpy(mem.address_of(&holder[0usize]), mem.address_of(&bytes[index * 4usize]), 4usize)
    ret holder[0usize]
}

fn put(bytes: []u8, index: usize, value: f32) {
    var holder: [1]f32 = zero
    holder[0usize] = value
    let copied = os.raw_memcpy(mem.address_of(&bytes[index * 4usize]), mem.address_of(&holder[0usize]), 4usize)
}

fn put64(bytes: []u8, offset: usize, value: u64) {
    var holder: [1]u64 = zero
    holder[0usize] = value
    let copied = os.raw_memcpy(mem.address_of(&bytes[offset]), mem.address_of(&holder[0usize]), 8usize)
}

fn put32(bytes: []u8, offset: usize, value: u32) {
    var holder: [1]u32 = zero
    holder[0usize] = value
    let copied = os.raw_memcpy(mem.address_of(&bytes[offset]), mem.address_of(&holder[0usize]), 4usize)
}

fn kernel_text() -> str {
    ret "#include <metal_stdlib>\nusing namespace metal;\n\nkernel void saxpy_saxpy(device const uchar* args [[buffer(0)]], device uchar* heap [[buffer(1)]], uint3 gid3 [[thread_position_in_grid]], uint3 lid3 [[thread_position_in_threadgroup]], uint3 wgid3 [[threadgroup_position_in_grid]]) {\n  thread ulong fr_words[4];\n  thread uchar* fr = (thread uchar*)fr_words;\n  for (uint z = 0u; z < 4u; z += 1u) fr_words[z] = 0ul;\n  uint v0;\n  float v1;\n  uint v7;\n  bool v8;\n  uint v9;\n  ulong v11;\n  uint v13;\n  ulong v14;\n  ulong v16;\n  uint v18;\n  ulong v19;\n  float v20;\n  float v21;\n  ulong v23;\n  uint v25;\n  ulong v26;\n  float v27;\n  float v28;\n  uint pc = 0u;\n  while (true) {\n    switch (pc) {\n    case 0: {\n      v0 = *(device const uint*)(args + 8u);\n      v1 = *(device const float*)(args + 12u);\n      *(thread ulong*)(fr + 0u) = *(device const ulong*)(args + 16u);\n      *(thread uint*)(fr + 8u) = *(device const uint*)(args + 24u);\n      *(thread uint*)(fr + 12u) = 0u;\n      *(thread ulong*)(fr + 16u) = *(device const ulong*)(args + 32u);\n      *(thread uint*)(fr + 24u) = *(device const uint*)(args + 40u);\n      *(thread uint*)(fr + 28u) = 0u;\n      v7 = gid3.x;\n      v8 = v7 >= v0;\n      if (v8) { pc = 1u; } else { pc = 2u; }\n      continue;\n    }\n    case 1: {\n      return;\n    }\n    case 2: {\n      pc = 3u; continue;\n    }\n    case 3: {\n      v9 = (uint)v7;\n      v11 = *(thread ulong*)(fr + 16u);\n      v13 = *(thread uint*)(fr + 24u);\n      if (!(v9 < v13)) {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 0;\n      *(device uint*)((device uchar*)count + 12) = 25u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n        return;\n      }\n      v14 = v11 + (ulong)v9 * 4ul;\n      v16 = *(thread ulong*)(fr + 0u);\n      v18 = *(thread uint*)(fr + 8u);\n      if (!(v9 < v18)) {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 0;\n      *(device uint*)((device uchar*)count + 12) = 25u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n        return;\n      }\n      v19 = v16 + (ulong)v9 * 4ul;\n      v20 = *(device float*)(heap + v19);\n      v21 = (float)(v1 * v20);\n      v23 = *(thread ulong*)(fr + 16u);\n      v25 = *(thread uint*)(fr + 24u);\n      if (!(v9 < v25)) {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 0;\n      *(device uint*)((device uchar*)count + 12) = 25u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n        return;\n      }\n      v26 = v23 + (ulong)v9 * 4ul;\n      v27 = *(device float*)(heap + v26);\n      v28 = (float)(v21 + v27);\n      *(device float*)(heap + v14) = v28;\n      return;\n    }\n    default: return;\n    }\n  }\n}\n\n"
}

fn main(a: *mem.Arena) -> err {
    if !mtl.available() {
        os.exit(0i32)
    }
    let (context, open_error) = mtl.open(a)
    if open_error != ok { os.exit(2i32) }
    let (heap, heap_error) = mtl.buffer(context, 16384usize)
    let (args, args_error) = mtl.buffer(context, 64usize)
    if heap_error != ok { os.exit(3i32) }
    if args_error != ok { os.exit(4i32) }
    // x at byte 64 and y at 4160: words 16 and 1040 of the heap.
    var at = 0usize
    while at < 1024usize {
        put(heap.bytes, 16usize + at, f32(at))
        put(heap.bytes, 1040usize + at, 3.0f32)
        at += 1usize
    }
    // The argument block: fault offset, n, a, then the slices x and y as {offset, len}.
    put64(args.bytes, 0usize, 0u64)
    put32(args.bytes, 8usize, 1024u32)
    put(args.bytes, 3usize, 2.0f32)
    put64(args.bytes, 16usize, 64u64)
    put32(args.bytes, 24usize, 1024u32)
    put64(args.bytes, 32usize, 4160u64)
    put32(args.bytes, 40usize, 1024u32)
    let (pipeline, compile_error) = mtl.compile(context, kernel_text(), "saxpy_saxpy")
    if compile_error != ok { os.exit(5i32) }
    var both: [2]mtl.Buffer = zero
    both[0usize] = args
    both[1usize] = heap
    let run = mtl.dispatch(context, pipeline, both[..], mtl.Size { width: 4usize, height: 1usize, depth: 1usize }, mtl.Size { width: 256usize, height: 1usize, depth: 1usize }, 0usize)
    if run != ok { os.exit(6i32) }
    if word(heap.bytes, 0usize) != 0.0f32 { os.exit(7i32) }
    at = 0usize
    while at < 1024usize {
        if word(heap.bytes, 1040usize + at) != 2.0f32 * f32(at) + 3.0f32 { os.exit(8i32) }
        at += 1usize
    }
    mtl.destroy(pipeline)
    mtl.free(heap)
    mtl.free(args)
    mtl.close(context)
    ret ok
}
