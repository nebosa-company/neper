#include <metal_stdlib>
using namespace metal;

kernel void loop_fill(device const uchar* args [[buffer(0)]], device uchar* heap [[buffer(1)]], uint3 gid3 [[thread_position_in_grid]], uint3 lid3 [[thread_position_in_threadgroup]], uint3 wgid3 [[threadgroup_position_in_grid]], uint sid [[thread_index_in_simdgroup]], uint sgw [[threads_per_simdgroup]]) {
  thread ulong fr_words[7];
  thread uchar* fr = (thread uchar*)fr_words;
  for (uint z = 0u; z < 7u; z += 1u) fr_words[z] = 0ul;
  uint v0;
  uint v5;
  bool v6;
  uint v7;
  uint v9;
  uint v11;
  uint v12;
  uint v13;
  uint v14;
  bool v15;
  bool v16;
  uint v17;
  uint v18;
  uint v19;
  uint v20;
  uint v21;
  uint v22;
  bool v23;
  uint v24;
  uint v25;
  bool v26;
  uint v27;
  uint v28;
  bool v29;
  uint v30;
  uint v31;
  uint v32;
  uint v33;
  uint v34;
  uint v35;
  uint v36;
  bool v37;
  uint v39;
  bool v40;
  uint v41;
  uint v42;
  uint v43;
  uint v44;
  uint v45;
  bool v46;
  uint v47;
  bool v48;
  uint v49;
  uint v50;
  uint v51;
  uint v52;
  bool v53;
  uint v54;
  bool v55;
  uint v56;
  uint v57;
  uint v59;
  uint v60;
  bool v61;
  uint v62;
  uint v63;
  uint v64;
  uint v65;
  uint v67;
  uint v68;
  bool v69;
  uint v70;
  uint v71;
  uint v72;
  uint v73;
  uint v74;
  bool v75;
  uint v76;
  uint v77;
  bool v78;
  uint v79;
  uint v80;
  bool v81;
  uint v82;
  uint v83;
  uint v84;
  uint v85;
  uint v86;
  bool v87;
  uint v88;
  bool v89;
  uint v90;
  uint v91;
  ulong v93;
  uint v95;
  ulong v96;
  uint v97;
  uint pc = 0u;
  while (true) {
    if (pc != simd_min(pc)) { continue; }
    switch (pc) {
    case 0: {
      v0 = *(device const uint*)(args + 8u);
      *(thread ulong*)(fr + 0u) = *(device const ulong*)(args + 16u);
      *(thread uint*)(fr + 8u) = *(device const uint*)(args + 24u);
      *(thread uint*)(fr + 12u) = 0u;
      v5 = gid3.x;
      v6 = v5 >= v0;
      if (v6) { pc = 1u; } else { pc = 2u; }
      continue;
    }
    case 1: {
      return;
    }
    case 2: {
      pc = 3u; continue;
    }
    case 3: {
      v7 = (uint)0u;
      *(thread uint*)(fr + 16u) = v7;
      v9 = (uint)0u;
      *(thread uint*)(fr + 24u) = v9;
      pc = 4u; continue;
    }
    case 4: {
      v11 = *(thread uint*)(fr + 24u);
      v12 = (uint)7u;
      v13 = (uint)(v5 + v12);
      v14 = (uint)(~v5);
      v15 = v12 <= v14;
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
      v16 = v11 < v13;
      if (v16) { pc = 7u; } else { pc = 16u; }
      continue;
    }
    case 7: {
      v17 = *(thread uint*)(fr + 24u);
      v18 = (uint)1u;
      v19 = (uint)(v17 + v18);
      *(thread uint*)(fr + 24u) = v19;
      v20 = *(thread uint*)(fr + 24u);
      v21 = (uint)3u;
      v22 = (uint)0u;
      v23 = v21 != v22;
      if (v23) { pc = 9u; } else { pc = 8u; }
      continue;
    }
    case 8: {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 5;
      *(device uint*)((device uchar*)count + 12) = 13u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
      return;
    }
    case 9: {
      v24 = (uint)(v20 % v21);
      v25 = (uint)0u;
      v26 = v24 == v25;
      if (v26) { pc = 10u; } else { pc = 11u; }
      continue;
    }
    case 10: {
      pc = 4u; continue;
    }
    case 11: {
      pc = 12u; continue;
    }
    case 12: {
      v27 = *(thread uint*)(fr + 24u);
      v28 = (uint)11u;
      v29 = v27 > v28;
      if (v29) { pc = 13u; } else { pc = 14u; }
      continue;
    }
    case 13: {
      pc = 16u; continue;
    }
    case 14: {
      pc = 15u; continue;
    }
    case 15: {
      v30 = *(thread uint*)(fr + 16u);
      v31 = *(thread uint*)(fr + 24u);
      v32 = (uint)(v30 + v31);
      *(thread uint*)(fr + 16u) = v32;
      pc = 4u; continue;
    }
    case 16: {
      v33 = (uint)0u;
      v34 = (uint)4u;
      v35 = (uint)(v5 + v34);
      v36 = (uint)(~v5);
      v37 = v34 <= v36;
      if (v37) { pc = 18u; } else { pc = 17u; }
      continue;
    }
    case 17: {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 4;
      *(device uint*)((device uchar*)count + 12) = 17u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
      return;
    }
    case 18: {
      *(thread uint*)(fr + 32u) = v33;
      pc = 19u; continue;
    }
    case 19: {
      v39 = *(thread uint*)(fr + 32u);
      v40 = v39 < v35;
      if (v40) { pc = 21u; } else { pc = 32u; }
      continue;
    }
    case 20: {
      v41 = *(thread uint*)(fr + 32u);
      v42 = (uint)1u;
      v43 = (uint)(v41 + v42);
      *(thread uint*)(fr + 32u) = v43;
      pc = 19u; continue;
    }
    case 21: {
      v44 = *(thread uint*)(fr + 32u);
      v45 = (uint)2u;
      v46 = v44 == v45;
      if (v46) { pc = 22u; } else { pc = 23u; }
      continue;
    }
    case 22: {
      pc = 20u; continue;
    }
    case 23: {
      pc = 24u; continue;
    }
    case 24: {
      v47 = (uint)8u;
      v48 = v44 >= v47;
      if (v48) { pc = 25u; } else { pc = 26u; }
      continue;
    }
    case 25: {
      pc = 32u; continue;
    }
    case 26: {
      pc = 27u; continue;
    }
    case 27: {
      v49 = *(thread uint*)(fr + 16u);
      v50 = (uint)2u;
      v51 = (uint)(v44 * v50);
      v52 = (uint)0u;
      v53 = v44 == v52;
      if (v53) { pc = 31u; } else { pc = 28u; }
      continue;
    }
    case 28: {
      v54 = (uint)(v51 / v44);
      v55 = v54 == v50;
      if (v55) { pc = 30u; } else { pc = 29u; }
      continue;
    }
    case 29: {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 4;
      *(device uint*)((device uchar*)count + 12) = 20u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
      return;
    }
    case 30: {
      pc = 31u; continue;
    }
    case 31: {
      v56 = (uint)(v49 + v51);
      *(thread uint*)(fr + 16u) = v56;
      pc = 20u; continue;
    }
    case 32: {
      v57 = (uint)0u;
      *(thread uint*)(fr + 40u) = v57;
      pc = 33u; continue;
    }
    case 33: {
      v59 = *(thread uint*)(fr + 40u);
      v60 = (uint)3u;
      v61 = v59 < v60;
      if (v61) { pc = 34u; } else { pc = 51u; }
      continue;
    }
    case 34: {
      v62 = *(thread uint*)(fr + 40u);
      v63 = (uint)1u;
      v64 = (uint)(v62 + v63);
      *(thread uint*)(fr + 40u) = v64;
      v65 = (uint)0u;
      *(thread uint*)(fr + 48u) = v65;
      pc = 35u; continue;
    }
    case 35: {
      v67 = *(thread uint*)(fr + 48u);
      v68 = (uint)5u;
      v69 = v67 < v68;
      if (v69) { pc = 36u; } else { pc = 50u; }
      continue;
    }
    case 36: {
      v70 = *(thread uint*)(fr + 48u);
      v71 = (uint)1u;
      v72 = (uint)(v70 + v71);
      *(thread uint*)(fr + 48u) = v72;
      v73 = *(thread uint*)(fr + 48u);
      v74 = (uint)2u;
      v75 = v73 == v74;
      if (v75) { pc = 37u; } else { pc = 38u; }
      continue;
    }
    case 37: {
      pc = 35u; continue;
    }
    case 38: {
      pc = 39u; continue;
    }
    case 39: {
      v76 = *(thread uint*)(fr + 40u);
      v77 = (uint)3u;
      v78 = v76 == v77;
      if (v78) { pc = 40u; } else { pc = 44u; }
      continue;
    }
    case 40: {
      v79 = *(thread uint*)(fr + 48u);
      v80 = (uint)4u;
      v81 = v79 == v80;
      if (v81) { pc = 41u; } else { pc = 42u; }
      continue;
    }
    case 41: {
      pc = 50u; continue;
    }
    case 42: {
      pc = 43u; continue;
    }
    case 43: {
      pc = 45u; continue;
    }
    case 44: {
      pc = 45u; continue;
    }
    case 45: {
      v82 = *(thread uint*)(fr + 16u);
      v83 = *(thread uint*)(fr + 40u);
      v84 = *(thread uint*)(fr + 48u);
      v85 = (uint)(v83 * v84);
      v86 = (uint)0u;
      v87 = v83 == v86;
      if (v87) { pc = 49u; } else { pc = 46u; }
      continue;
    }
    case 46: {
      v88 = (uint)(v85 / v83);
      v89 = v88 == v84;
      if (v89) { pc = 48u; } else { pc = 47u; }
      continue;
    }
    case 47: {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 4;
      *(device uint*)((device uchar*)count + 12) = 32u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
      return;
    }
    case 48: {
      pc = 49u; continue;
    }
    case 49: {
      v90 = (uint)(v82 + v85);
      *(thread uint*)(fr + 16u) = v90;
      pc = 35u; continue;
    }
    case 50: {
      pc = 33u; continue;
    }
    case 51: {
      v91 = (uint)v5;
      v93 = *(thread ulong*)(fr + 0u);
      v95 = *(thread uint*)(fr + 8u);
      if (!(v91 < v95)) {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 0;
      *(device uint*)((device uchar*)count + 12) = 35u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
        return;
      }
      v96 = v93 + (ulong)v91 * 4ul;
      v97 = *(thread uint*)(fr + 16u);
      *(device uint*)(heap + v96) = v97;
      return;
    }
    default: return;
    }
  }
}

