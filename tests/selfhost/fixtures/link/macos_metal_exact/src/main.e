// The MSL emitter's division, square root and loops against the CPU (C193, D5838): float.e and loop.e of tests/conformance/spirv
// written as MSL by `emit-executable ... msl none` are compiled by Metal with fast math off and run over one heap buffer. Division
// and square root must match the CPU's correctly rounded f32 bit for bit (a NaN matches any NaN); the loop kernel's sums must match
// the same loops run here. A machine with no Metal device says so and passes. macOS only.
use e.mem
use e.os
use e.math
use e.gpu.metal as mtl

fn put_f(bytes: []u8, offset: usize, value: f32) {
    var holder: [1]f32 = zero
    holder[0usize] = value
    let copied = os.raw_memcpy(mem.address_of(&bytes[offset]), mem.address_of(&holder[0usize]), 4usize)
}

fn get_bits(bytes: []u8, offset: usize) -> u32 {
    var holder: [1]u32 = zero
    let copied = os.raw_memcpy(mem.address_of(&holder[0usize]), mem.address_of(&bytes[offset]), 4usize)
    ret holder[0usize]
}

fn put_64(bytes: []u8, offset: usize, value: u64) {
    var holder: [1]u64 = zero
    holder[0usize] = value
    let copied = os.raw_memcpy(mem.address_of(&bytes[offset]), mem.address_of(&holder[0usize]), 8usize)
}

fn put_32(bytes: []u8, offset: usize, value: u32) {
    var holder: [1]u32 = zero
    holder[0usize] = value
    let copied = os.raw_memcpy(mem.address_of(&bytes[offset]), mem.address_of(&holder[0usize]), 4usize)
}

fn bits_of(value: f32) -> u32 {
    var holder: [1]f32 = zero
    holder[0usize] = value
    var out: [1]u32 = zero
    let copied = os.raw_memcpy(mem.address_of(&out[0usize]), mem.address_of(&holder[0usize]), 4usize)
    ret out[0usize]
}

fn same_answer(device: u32, cpu: f32) -> bool {
    let wanted = bits_of(cpu)
    if device == wanted { ret true }
    // Any NaN is any NaN.
    ret (device & 2139095040u32) == 2139095040u32 && (device & 8388607u32) != 0u32 && (wanted & 2139095040u32) == 2139095040u32 && (wanted & 8388607u32) != 0u32
}

fn float_text() -> str {
    ret "#include <metal_stdlib>\nusing namespace metal;\n\nkernel void float_exact(device const uchar* args [[buffer(0)]], device uchar* heap [[buffer(1)]], uint3 gid3 [[thread_position_in_grid]], uint3 lid3 [[thread_position_in_threadgroup]], uint3 wgid3 [[threadgroup_position_in_grid]]) {\n  thread ulong fr_words[6];\n  thread uchar* fr = (thread uchar*)fr_words;\n  for (uint z = 0u; z < 6u; z += 1u) fr_words[z] = 0ul;\n  uint v0;\n  uint v7;\n  bool v8;\n  uint v9;\n  uint v10;\n  uint v11;\n  uint v12;\n  bool v13;\n  uint v14;\n  bool v15;\n  ulong v17;\n  uint v19;\n  ulong v20;\n  uint v21;\n  ulong v23;\n  uint v25;\n  ulong v26;\n  float v27;\n  uint v28;\n  ulong v30;\n  uint v32;\n  ulong v33;\n  float v34;\n  float v35;\n  uint v36;\n  uint v37;\n  uint v38;\n  uint v39;\n  bool v40;\n  uint v41;\n  bool v42;\n  uint v43;\n  uint v44;\n  uint v45;\n  bool v46;\n  ulong v48;\n  uint v50;\n  ulong v51;\n  uint v52;\n  ulong v54;\n  uint v56;\n  ulong v57;\n  float v58;\n  float v59;\n  uint pc = 0u;\n  while (true) {\n    switch (pc) {\n    case 0: {\n      v0 = *(device const uint*)(args + 8u);\n      *(thread ulong*)(fr + 0u) = *(device const ulong*)(args + 16u);\n      *(thread uint*)(fr + 8u) = *(device const uint*)(args + 24u);\n      *(thread uint*)(fr + 12u) = 0u;\n      *(thread ulong*)(fr + 16u) = *(device const ulong*)(args + 32u);\n      *(thread uint*)(fr + 24u) = *(device const uint*)(args + 40u);\n      *(thread uint*)(fr + 28u) = 0u;\n      *(thread ulong*)(fr + 32u) = *(device const ulong*)(args + 48u);\n      *(thread uint*)(fr + 40u) = *(device const uint*)(args + 56u);\n      *(thread uint*)(fr + 44u) = 0u;\n      v7 = gid3.x;\n      v8 = v7 >= v0;\n      if (v8) { pc = 1u; } else { pc = 2u; }\n      continue;\n    }\n    case 1: {\n      return;\n    }\n    case 2: {\n      pc = 3u; continue;\n    }\n    case 3: {\n      v9 = (uint)v7;\n      v10 = (uint)2u;\n      v11 = (uint)(v9 * v10);\n      v12 = (uint)0u;\n      v13 = v9 == v12;\n      if (v13) { pc = 7u; } else { pc = 4u; }\n      continue;\n    }\n    case 4: {\n      v14 = (uint)(v11 / v9);\n      v15 = v14 == v10;\n      if (v15) { pc = 6u; } else { pc = 5u; }\n      continue;\n    }\n    case 5: {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 4;\n      *(device uint*)((device uchar*)count + 12) = 11u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n      return;\n    }\n    case 6: {\n      pc = 7u; continue;\n    }\n    case 7: {\n      v17 = *(thread ulong*)(fr + 32u);\n      v19 = *(thread uint*)(fr + 40u);\n      if (!(v11 < v19)) {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 0;\n      *(device uint*)((device uchar*)count + 12) = 11u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n        return;\n      }\n      v20 = v17 + (ulong)v11 * 4ul;\n      v21 = (uint)v7;\n      v23 = *(thread ulong*)(fr + 0u);\n      v25 = *(thread uint*)(fr + 8u);\n      if (!(v21 < v25)) {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 0;\n      *(device uint*)((device uchar*)count + 12) = 11u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n        return;\n      }\n      v26 = v23 + (ulong)v21 * 4ul;\n      v27 = *(device float*)(heap + v26);\n      v28 = (uint)v7;\n      v30 = *(thread ulong*)(fr + 16u);\n      v32 = *(thread uint*)(fr + 24u);\n      if (!(v28 < v32)) {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 0;\n      *(device uint*)((device uchar*)count + 12) = 11u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n        return;\n      }\n      v33 = v30 + (ulong)v28 * 4ul;\n      v34 = *(device float*)(heap + v33);\n      v35 = precise::divide(v27, v34);\n      *(device float*)(heap + v20) = v35;\n      v36 = (uint)v7;\n      v37 = (uint)2u;\n      v38 = (uint)(v36 * v37);\n      v39 = (uint)0u;\n      v40 = v36 == v39;\n      if (v40) { pc = 11u; } else { pc = 8u; }\n      continue;\n    }\n    case 8: {\n      v41 = (uint)(v38 / v36);\n      v42 = v41 == v37;\n      if (v42) { pc = 10u; } else { pc = 9u; }\n      continue;\n    }\n    case 9: {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 4;\n      *(device uint*)((device uchar*)count + 12) = 12u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n      return;\n    }\n    case 10: {\n      pc = 11u; continue;\n    }\n    case 11: {\n      v43 = (uint)1u;\n      v44 = (uint)(v38 + v43);\n      v45 = (uint)(~v38);\n      v46 = v43 <= v45;\n      if (v46) { pc = 13u; } else { pc = 12u; }\n      continue;\n    }\n    case 12: {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 4;\n      *(device uint*)((device uchar*)count + 12) = 12u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n      return;\n    }\n    case 13: {\n      v48 = *(thread ulong*)(fr + 32u);\n      v50 = *(thread uint*)(fr + 40u);\n      if (!(v44 < v50)) {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 0;\n      *(device uint*)((device uchar*)count + 12) = 12u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n        return;\n      }\n      v51 = v48 + (ulong)v44 * 4ul;\n      v52 = (uint)v7;\n      v54 = *(thread ulong*)(fr + 0u);\n      v56 = *(thread uint*)(fr + 8u);\n      if (!(v52 < v56)) {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 0;\n      *(device uint*)((device uchar*)count + 12) = 12u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n        return;\n      }\n      v57 = v54 + (ulong)v52 * 4ul;\n      v58 = *(device float*)(heap + v57);\n      v59 = precise::sqrt(v58);\n      *(device float*)(heap + v51) = v59;\n      return;\n    }\n    default: return;\n    }\n  }\n}\n\n"
}

fn loop_text() -> str {
    ret "#include <metal_stdlib>\nusing namespace metal;\n\nkernel void loop_fill(device const uchar* args [[buffer(0)]], device uchar* heap [[buffer(1)]], uint3 gid3 [[thread_position_in_grid]], uint3 lid3 [[thread_position_in_threadgroup]], uint3 wgid3 [[threadgroup_position_in_grid]]) {\n  thread ulong fr_words[7];\n  thread uchar* fr = (thread uchar*)fr_words;\n  for (uint z = 0u; z < 7u; z += 1u) fr_words[z] = 0ul;\n  uint v0;\n  uint v5;\n  bool v6;\n  uint v7;\n  uint v9;\n  uint v11;\n  uint v12;\n  uint v13;\n  uint v14;\n  bool v15;\n  bool v16;\n  uint v17;\n  uint v18;\n  uint v19;\n  uint v20;\n  uint v21;\n  uint v22;\n  bool v23;\n  uint v24;\n  uint v25;\n  bool v26;\n  uint v27;\n  uint v28;\n  bool v29;\n  uint v30;\n  uint v31;\n  uint v32;\n  uint v33;\n  uint v34;\n  uint v35;\n  uint v36;\n  bool v37;\n  uint v39;\n  bool v40;\n  uint v41;\n  uint v42;\n  uint v43;\n  uint v44;\n  uint v45;\n  bool v46;\n  uint v47;\n  bool v48;\n  uint v49;\n  uint v50;\n  uint v51;\n  uint v52;\n  bool v53;\n  uint v54;\n  bool v55;\n  uint v56;\n  uint v57;\n  uint v59;\n  uint v60;\n  bool v61;\n  uint v62;\n  uint v63;\n  uint v64;\n  uint v65;\n  uint v67;\n  uint v68;\n  bool v69;\n  uint v70;\n  uint v71;\n  uint v72;\n  uint v73;\n  uint v74;\n  bool v75;\n  uint v76;\n  uint v77;\n  bool v78;\n  uint v79;\n  uint v80;\n  bool v81;\n  uint v82;\n  uint v83;\n  uint v84;\n  uint v85;\n  uint v86;\n  bool v87;\n  uint v88;\n  bool v89;\n  uint v90;\n  uint v91;\n  ulong v93;\n  uint v95;\n  ulong v96;\n  uint v97;\n  uint pc = 0u;\n  while (true) {\n    switch (pc) {\n    case 0: {\n      v0 = *(device const uint*)(args + 8u);\n      *(thread ulong*)(fr + 0u) = *(device const ulong*)(args + 16u);\n      *(thread uint*)(fr + 8u) = *(device const uint*)(args + 24u);\n      *(thread uint*)(fr + 12u) = 0u;\n      v5 = gid3.x;\n      v6 = v5 >= v0;\n      if (v6) { pc = 1u; } else { pc = 2u; }\n      continue;\n    }\n    case 1: {\n      return;\n    }\n    case 2: {\n      pc = 3u; continue;\n    }\n    case 3: {\n      v7 = (uint)0u;\n      *(thread uint*)(fr + 16u) = v7;\n      v9 = (uint)0u;\n      *(thread uint*)(fr + 24u) = v9;\n      pc = 4u; continue;\n    }\n    case 4: {\n      v11 = *(thread uint*)(fr + 24u);\n      v12 = (uint)7u;\n      v13 = (uint)(v5 + v12);\n      v14 = (uint)(~v5);\n      v15 = v12 <= v14;\n      if (v15) { pc = 6u; } else { pc = 5u; }\n      continue;\n    }\n    case 5: {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 4;\n      *(device uint*)((device uchar*)count + 12) = 11u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n      return;\n    }\n    case 6: {\n      v16 = v11 < v13;\n      if (v16) { pc = 7u; } else { pc = 16u; }\n      continue;\n    }\n    case 7: {\n      v17 = *(thread uint*)(fr + 24u);\n      v18 = (uint)1u;\n      v19 = (uint)(v17 + v18);\n      *(thread uint*)(fr + 24u) = v19;\n      v20 = *(thread uint*)(fr + 24u);\n      v21 = (uint)3u;\n      v22 = (uint)0u;\n      v23 = v21 != v22;\n      if (v23) { pc = 9u; } else { pc = 8u; }\n      continue;\n    }\n    case 8: {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 5;\n      *(device uint*)((device uchar*)count + 12) = 13u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n      return;\n    }\n    case 9: {\n      v24 = (uint)(v20 % v21);\n      v25 = (uint)0u;\n      v26 = v24 == v25;\n      if (v26) { pc = 10u; } else { pc = 11u; }\n      continue;\n    }\n    case 10: {\n      pc = 4u; continue;\n    }\n    case 11: {\n      pc = 12u; continue;\n    }\n    case 12: {\n      v27 = *(thread uint*)(fr + 24u);\n      v28 = (uint)11u;\n      v29 = v27 > v28;\n      if (v29) { pc = 13u; } else { pc = 14u; }\n      continue;\n    }\n    case 13: {\n      pc = 16u; continue;\n    }\n    case 14: {\n      pc = 15u; continue;\n    }\n    case 15: {\n      v30 = *(thread uint*)(fr + 16u);\n      v31 = *(thread uint*)(fr + 24u);\n      v32 = (uint)(v30 + v31);\n      *(thread uint*)(fr + 16u) = v32;\n      pc = 4u; continue;\n    }\n    case 16: {\n      v33 = (uint)0u;\n      v34 = (uint)4u;\n      v35 = (uint)(v5 + v34);\n      v36 = (uint)(~v5);\n      v37 = v34 <= v36;\n      if (v37) { pc = 18u; } else { pc = 17u; }\n      continue;\n    }\n    case 17: {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 4;\n      *(device uint*)((device uchar*)count + 12) = 17u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n      return;\n    }\n    case 18: {\n      *(thread uint*)(fr + 32u) = v33;\n      pc = 19u; continue;\n    }\n    case 19: {\n      v39 = *(thread uint*)(fr + 32u);\n      v40 = v39 < v35;\n      if (v40) { pc = 21u; } else { pc = 32u; }\n      continue;\n    }\n    case 20: {\n      v41 = *(thread uint*)(fr + 32u);\n      v42 = (uint)1u;\n      v43 = (uint)(v41 + v42);\n      *(thread uint*)(fr + 32u) = v43;\n      pc = 19u; continue;\n    }\n    case 21: {\n      v44 = *(thread uint*)(fr + 32u);\n      v45 = (uint)2u;\n      v46 = v44 == v45;\n      if (v46) { pc = 22u; } else { pc = 23u; }\n      continue;\n    }\n    case 22: {\n      pc = 20u; continue;\n    }\n    case 23: {\n      pc = 24u; continue;\n    }\n    case 24: {\n      v47 = (uint)8u;\n      v48 = v44 >= v47;\n      if (v48) { pc = 25u; } else { pc = 26u; }\n      continue;\n    }\n    case 25: {\n      pc = 32u; continue;\n    }\n    case 26: {\n      pc = 27u; continue;\n    }\n    case 27: {\n      v49 = *(thread uint*)(fr + 16u);\n      v50 = (uint)2u;\n      v51 = (uint)(v44 * v50);\n      v52 = (uint)0u;\n      v53 = v44 == v52;\n      if (v53) { pc = 31u; } else { pc = 28u; }\n      continue;\n    }\n    case 28: {\n      v54 = (uint)(v51 / v44);\n      v55 = v54 == v50;\n      if (v55) { pc = 30u; } else { pc = 29u; }\n      continue;\n    }\n    case 29: {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 4;\n      *(device uint*)((device uchar*)count + 12) = 20u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n      return;\n    }\n    case 30: {\n      pc = 31u; continue;\n    }\n    case 31: {\n      v56 = (uint)(v49 + v51);\n      *(thread uint*)(fr + 16u) = v56;\n      pc = 20u; continue;\n    }\n    case 32: {\n      v57 = (uint)0u;\n      *(thread uint*)(fr + 40u) = v57;\n      pc = 33u; continue;\n    }\n    case 33: {\n      v59 = *(thread uint*)(fr + 40u);\n      v60 = (uint)3u;\n      v61 = v59 < v60;\n      if (v61) { pc = 34u; } else { pc = 51u; }\n      continue;\n    }\n    case 34: {\n      v62 = *(thread uint*)(fr + 40u);\n      v63 = (uint)1u;\n      v64 = (uint)(v62 + v63);\n      *(thread uint*)(fr + 40u) = v64;\n      v65 = (uint)0u;\n      *(thread uint*)(fr + 48u) = v65;\n      pc = 35u; continue;\n    }\n    case 35: {\n      v67 = *(thread uint*)(fr + 48u);\n      v68 = (uint)5u;\n      v69 = v67 < v68;\n      if (v69) { pc = 36u; } else { pc = 50u; }\n      continue;\n    }\n    case 36: {\n      v70 = *(thread uint*)(fr + 48u);\n      v71 = (uint)1u;\n      v72 = (uint)(v70 + v71);\n      *(thread uint*)(fr + 48u) = v72;\n      v73 = *(thread uint*)(fr + 48u);\n      v74 = (uint)2u;\n      v75 = v73 == v74;\n      if (v75) { pc = 37u; } else { pc = 38u; }\n      continue;\n    }\n    case 37: {\n      pc = 35u; continue;\n    }\n    case 38: {\n      pc = 39u; continue;\n    }\n    case 39: {\n      v76 = *(thread uint*)(fr + 40u);\n      v77 = (uint)3u;\n      v78 = v76 == v77;\n      if (v78) { pc = 40u; } else { pc = 44u; }\n      continue;\n    }\n    case 40: {\n      v79 = *(thread uint*)(fr + 48u);\n      v80 = (uint)4u;\n      v81 = v79 == v80;\n      if (v81) { pc = 41u; } else { pc = 42u; }\n      continue;\n    }\n    case 41: {\n      pc = 50u; continue;\n    }\n    case 42: {\n      pc = 43u; continue;\n    }\n    case 43: {\n      pc = 45u; continue;\n    }\n    case 44: {\n      pc = 45u; continue;\n    }\n    case 45: {\n      v82 = *(thread uint*)(fr + 16u);\n      v83 = *(thread uint*)(fr + 40u);\n      v84 = *(thread uint*)(fr + 48u);\n      v85 = (uint)(v83 * v84);\n      v86 = (uint)0u;\n      v87 = v83 == v86;\n      if (v87) { pc = 49u; } else { pc = 46u; }\n      continue;\n    }\n    case 46: {\n      v88 = (uint)(v85 / v83);\n      v89 = v88 == v84;\n      if (v89) { pc = 48u; } else { pc = 47u; }\n      continue;\n    }\n    case 47: {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 4;\n      *(device uint*)((device uchar*)count + 12) = 32u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n      return;\n    }\n    case 48: {\n      pc = 49u; continue;\n    }\n    case 49: {\n      v90 = (uint)(v82 + v85);\n      *(thread uint*)(fr + 16u) = v90;\n      pc = 35u; continue;\n    }\n    case 50: {\n      pc = 33u; continue;\n    }\n    case 51: {\n      v91 = (uint)v5;\n      v93 = *(thread ulong*)(fr + 0u);\n      v95 = *(thread uint*)(fr + 8u);\n      if (!(v91 < v95)) {\n      {\n        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);\n        uint expected = 0u;\n        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {\n      *(device uchar*)((device uchar*)count + 8) = 0;\n      *(device uint*)((device uchar*)count + 12) = 35u;\n            *(device uint*)((device uchar*)count + 16) = gid3.x;\n            *(device uint*)((device uchar*)count + 20) = gid3.y;\n            *(device uint*)((device uchar*)count + 24) = gid3.z;\n        } else {\n            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);\n        }\n      }\n        return;\n      }\n      v96 = v93 + (ulong)v91 * 4ul;\n      v97 = *(thread uint*)(fr + 16u);\n      *(device uint*)(heap + v96) = v97;\n      return;\n    }\n    default: return;\n    }\n  }\n}\n\n"
}

fn expected(id: u32) -> u32 {
    var sum = 0u32
    var i = 0u32
    while i < id + 7u32 {
        i += 1u32
        if i % 3u32 == 0u32 { continue }
        if i > 11u32 { break }
        sum += i
    }
    for j in 0u32..id + 4u32 {
        if j == 2u32 { continue }
        if j >= 8u32 { break }
        sum += j * 2u32
    }
    var outer = 0u32
    while outer < 3u32 {
        outer += 1u32
        var inner = 0u32
        while inner < 5u32 {
            inner += 1u32
            if inner == 2u32 { continue }
            if outer == 3u32 {
                if inner == 4u32 { break }
            }
            sum += outer * inner
        }
    }
    ret sum
}

fn main(a: *mem.Arena) -> err {
    if !mtl.available() {
        os.exit(0i32)
    }
    let (context, open_error) = mtl.open(a)
    if open_error != ok { os.exit(2i32) }
    let (heap, heap_error) = mtl.buffer(context, 4096usize)
    let (args, args_error) = mtl.buffer(context, 64usize)
    if heap_error != ok { os.exit(3i32) }
    if args_error != ok { os.exit(4i32) }
    var both: [2]mtl.Buffer = zero
    both[0usize] = args
    both[1usize] = heap
    let one = mtl.Size { width: 1usize, height: 1usize, depth: 1usize }
    let group = mtl.Size { width: 64usize, height: 1usize, depth: 1usize }
    // Division and square root: numerators at 64, denominators at 320, answers (two per element) at 576.
    var numerators: [64]f32 = zero
    var denominators: [64]f32 = zero
    var at = 0usize
    while at < 64usize {
        numerators[at] = f32(at + 1usize) * 0.7311f32
        denominators[at] = f32(at % 7usize + 1usize) * 1.913f32
        at += 1usize
    }
    let zero_value = 0.0f32
    numerators[60usize] = 1.0f32 / zero_value
    denominators[61usize] = zero_value
    numerators[62usize] = zero_value
    denominators[62usize] = zero_value
    numerators[63usize] = -4.0f32
    at = 0usize
    while at < 64usize {
        put_f(heap.bytes, 64usize + at * 4usize, numerators[at])
        put_f(heap.bytes, 320usize + at * 4usize, denominators[at])
        at += 1usize
    }
    put_64(args.bytes, 0usize, 0u64)
    put_32(args.bytes, 8usize, 64u32)
    put_64(args.bytes, 16usize, 64u64)
    put_32(args.bytes, 24usize, 64u32)
    put_64(args.bytes, 32usize, 320u64)
    put_32(args.bytes, 40usize, 64u32)
    put_64(args.bytes, 48usize, 576u64)
    put_32(args.bytes, 56usize, 128u32)
    let (exact, exact_error) = mtl.compile(context, float_text(), "float_exact")
    if exact_error != ok { os.exit(5i32) }
    let ran = mtl.dispatch(context, exact, both[..], one, group, 0usize)
    if ran != ok { os.exit(6i32) }
    at = 0usize
    while at < 64usize {
        if !same_answer(get_bits(heap.bytes, 576usize + at * 8usize), numerators[at] / denominators[at]) { os.exit(7i32) }
        if !same_answer(get_bits(heap.bytes, 576usize + at * 8usize + 4usize), math.sqrt[f32](numerators[at])) { os.exit(8i32) }
        at += 1usize
    }
    // Loops: 64 sums at 64.
    put_64(args.bytes, 0usize, 0u64)
    put_32(args.bytes, 8usize, 64u32)
    put_64(args.bytes, 16usize, 64u64)
    put_32(args.bytes, 24usize, 64u32)
    let (filler, filler_error) = mtl.compile(context, loop_text(), "loop_fill")
    if filler_error != ok { os.exit(9i32) }
    let filled = mtl.dispatch(context, filler, both[..], one, group, 0usize)
    if filled != ok { os.exit(10i32) }
    var id = 0u32
    while id < 64u32 {
        if get_bits(heap.bytes, 64usize + usize(id) * 4usize) != expected(id) { os.exit(11i32) }
        id += 1u32
    }
    mtl.destroy(exact)
    mtl.destroy(filler)
    mtl.free(heap)
    mtl.free(args)
    mtl.close(context)
    ret ok
}
