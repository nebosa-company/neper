#include <metal_stdlib>
using namespace metal;

kernel void float_exact(device const uchar* args [[buffer(0)]], device uchar* heap [[buffer(1)]], uint3 gid3 [[thread_position_in_grid]], uint3 lid3 [[thread_position_in_threadgroup]], uint3 wgid3 [[threadgroup_position_in_grid]], uint sid [[thread_index_in_simdgroup]], uint sgw [[threads_per_simdgroup]]) {
  thread ulong fr_words[6];
  thread uchar* fr = (thread uchar*)fr_words;
  for (uint z = 0u; z < 6u; z += 1u) fr_words[z] = 0ul;
  uint v0;
  uint v7;
  bool v8;
  uint v9;
  uint v10;
  uint v11;
  uint v12;
  bool v13;
  uint v14;
  bool v15;
  ulong v17;
  uint v19;
  ulong v20;
  uint v21;
  ulong v23;
  uint v25;
  ulong v26;
  float v27;
  uint v28;
  ulong v30;
  uint v32;
  ulong v33;
  float v34;
  float v35;
  uint v36;
  uint v37;
  uint v38;
  uint v39;
  bool v40;
  uint v41;
  bool v42;
  uint v43;
  uint v44;
  uint v45;
  bool v46;
  ulong v48;
  uint v50;
  ulong v51;
  uint v52;
  ulong v54;
  uint v56;
  ulong v57;
  float v58;
  float v59;
  uint pc = 0u;
  while (true) {
    if (pc != simd_min(pc)) { continue; }
    switch (pc) {
    case 0: {
      v0 = *(device const uint*)(args + 8u);
      *(thread ulong*)(fr + 0u) = *(device const ulong*)(args + 16u);
      *(thread uint*)(fr + 8u) = *(device const uint*)(args + 24u);
      *(thread uint*)(fr + 12u) = 0u;
      *(thread ulong*)(fr + 16u) = *(device const ulong*)(args + 32u);
      *(thread uint*)(fr + 24u) = *(device const uint*)(args + 40u);
      *(thread uint*)(fr + 28u) = 0u;
      *(thread ulong*)(fr + 32u) = *(device const ulong*)(args + 48u);
      *(thread uint*)(fr + 40u) = *(device const uint*)(args + 56u);
      *(thread uint*)(fr + 44u) = 0u;
      v7 = gid3.x;
      v8 = v7 >= v0;
      if (v8) { pc = 1u; } else { pc = 2u; }
      continue;
    }
    case 1: {
      return;
    }
    case 2: {
      pc = 3u; continue;
    }
    case 3: {
      v9 = (uint)v7;
      v10 = (uint)2u;
      v11 = (uint)(v9 * v10);
      v12 = (uint)0u;
      v13 = v9 == v12;
      if (v13) { pc = 7u; } else { pc = 4u; }
      continue;
    }
    case 4: {
      v14 = (uint)(v11 / v9);
      v15 = v14 == v10;
      if (v15) { pc = 6u; } else { pc = 5u; }
      continue;
    }
    case 5: {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 4;
      *(device uint*)((device uchar*)count + 12) = 11u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
      return;
    }
    case 6: {
      pc = 7u; continue;
    }
    case 7: {
      v17 = *(thread ulong*)(fr + 32u);
      v19 = *(thread uint*)(fr + 40u);
      if (!(v11 < v19)) {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 0;
      *(device uint*)((device uchar*)count + 12) = 11u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
        return;
      }
      v20 = v17 + (ulong)v11 * 4ul;
      v21 = (uint)v7;
      v23 = *(thread ulong*)(fr + 0u);
      v25 = *(thread uint*)(fr + 8u);
      if (!(v21 < v25)) {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 0;
      *(device uint*)((device uchar*)count + 12) = 11u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
        return;
      }
      v26 = v23 + (ulong)v21 * 4ul;
      v27 = *(device float*)(heap + v26);
      v28 = (uint)v7;
      v30 = *(thread ulong*)(fr + 16u);
      v32 = *(thread uint*)(fr + 24u);
      if (!(v28 < v32)) {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 0;
      *(device uint*)((device uchar*)count + 12) = 11u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
        return;
      }
      v33 = v30 + (ulong)v28 * 4ul;
      v34 = *(device float*)(heap + v33);
      v35 = precise::divide(v27, v34);
      *(device float*)(heap + v20) = v35;
      v36 = (uint)v7;
      v37 = (uint)2u;
      v38 = (uint)(v36 * v37);
      v39 = (uint)0u;
      v40 = v36 == v39;
      if (v40) { pc = 11u; } else { pc = 8u; }
      continue;
    }
    case 8: {
      v41 = (uint)(v38 / v36);
      v42 = v41 == v37;
      if (v42) { pc = 10u; } else { pc = 9u; }
      continue;
    }
    case 9: {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 4;
      *(device uint*)((device uchar*)count + 12) = 12u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
      return;
    }
    case 10: {
      pc = 11u; continue;
    }
    case 11: {
      v43 = (uint)1u;
      v44 = (uint)(v38 + v43);
      v45 = (uint)(~v38);
      v46 = v43 <= v45;
      if (v46) { pc = 13u; } else { pc = 12u; }
      continue;
    }
    case 12: {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 4;
      *(device uint*)((device uchar*)count + 12) = 12u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
      return;
    }
    case 13: {
      v48 = *(thread ulong*)(fr + 32u);
      v50 = *(thread uint*)(fr + 40u);
      if (!(v44 < v50)) {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 0;
      *(device uint*)((device uchar*)count + 12) = 12u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
        return;
      }
      v51 = v48 + (ulong)v44 * 4ul;
      v52 = (uint)v7;
      v54 = *(thread ulong*)(fr + 0u);
      v56 = *(thread uint*)(fr + 8u);
      if (!(v52 < v56)) {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 0;
      *(device uint*)((device uchar*)count + 12) = 12u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
        return;
      }
      v57 = v54 + (ulong)v52 * 4ul;
      v58 = *(device float*)(heap + v57);
      v59 = precise::sqrt(v58);
      *(device float*)(heap + v51) = v59;
      return;
    }
    default: return;
    }
  }
}

