#include <metal_stdlib>
using namespace metal;

kernel void saxpy_saxpy(device const uchar* args [[buffer(0)]], device uchar* heap [[buffer(1)]], uint3 gid3 [[thread_position_in_grid]], uint3 lid3 [[thread_position_in_threadgroup]], uint3 wgid3 [[threadgroup_position_in_grid]], uint sid [[thread_index_in_simdgroup]], uint sgw [[threads_per_simdgroup]]) {
  thread ulong fr_words[4];
  thread uchar* fr = (thread uchar*)fr_words;
  for (uint z = 0u; z < 4u; z += 1u) fr_words[z] = 0ul;
  uint v0;
  float v1;
  uint v7;
  bool v8;
  uint v9;
  ulong v11;
  uint v13;
  ulong v14;
  ulong v16;
  uint v18;
  ulong v19;
  float v20;
  float v21;
  ulong v23;
  uint v25;
  ulong v26;
  float v27;
  float v28;
  uint pc = 0u;
  while (true) {
    if (pc != simd_min(pc)) { continue; }
    switch (pc) {
    case 0: {
      v0 = *(device const uint*)(args + 8u);
      v1 = *(device const float*)(args + 12u);
      *(thread ulong*)(fr + 0u) = *(device const ulong*)(args + 16u);
      *(thread uint*)(fr + 8u) = *(device const uint*)(args + 24u);
      *(thread uint*)(fr + 12u) = 0u;
      *(thread ulong*)(fr + 16u) = *(device const ulong*)(args + 32u);
      *(thread uint*)(fr + 24u) = *(device const uint*)(args + 40u);
      *(thread uint*)(fr + 28u) = 0u;
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
      v11 = *(thread ulong*)(fr + 16u);
      v13 = *(thread uint*)(fr + 24u);
      if (!(v9 < v13)) {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 0;
      *(device uint*)((device uchar*)count + 12) = 25u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
        return;
      }
      v14 = v11 + (ulong)v9 * 4ul;
      v16 = *(thread ulong*)(fr + 0u);
      v18 = *(thread uint*)(fr + 8u);
      if (!(v9 < v18)) {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 0;
      *(device uint*)((device uchar*)count + 12) = 25u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
        return;
      }
      v19 = v16 + (ulong)v9 * 4ul;
      v20 = *(device float*)(heap + v19);
      v21 = (float)(v1 * v20);
      v23 = *(thread ulong*)(fr + 16u);
      v25 = *(thread uint*)(fr + 24u);
      if (!(v9 < v25)) {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 0;
      *(device uint*)((device uchar*)count + 12) = 25u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
        return;
      }
      v26 = v23 + (ulong)v9 * 4ul;
      v27 = *(device float*)(heap + v26);
      v28 = (float)(v21 + v27);
      *(device float*)(heap + v14) = v28;
      return;
    }
    default: return;
    }
  }
}

