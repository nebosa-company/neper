#include <metal_stdlib>
using namespace metal;

// A device address: the heap in its top byte, the offset in the rest (D5877).
#define HP(a) ((((a) >> 56) == 0ul ? heap : ((a) >> 56) == 1ul ? heap1 : ((a) >> 56) == 2ul ? heap2 : heap3) + ((a) & 0xFFFFFFFFFFFFFFul))

kernel void loop_fill(device const uchar* args [[buffer(0)]], device uchar* heap [[buffer(1)]], device uchar* heap1 [[buffer(2)]], device uchar* heap2 [[buffer(3)]], device uchar* heap3 [[buffer(4)]], uint3 gid3 [[thread_position_in_grid]], uint3 lid3 [[thread_position_in_threadgroup]], uint3 wgid3 [[threadgroup_position_in_grid]], uint sid [[thread_index_in_simdgroup]], uint sgw [[threads_per_simdgroup]]) {
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
  bool v21;
  uint v22;
  uint v23;
  uint v24;
  bool v25;
  uint v26;
  uint v27;
  bool v28;
  uint v29;
  uint v30;
  bool v31;
  uint v32;
  uint v33;
  uint v34;
  uint v35;
  bool v36;
  uint v37;
  uint v38;
  uint v39;
  uint v40;
  bool v41;
  uint v43;
  bool v44;
  uint v45;
  uint v46;
  uint v47;
  uint v48;
  uint v49;
  bool v50;
  uint v51;
  bool v52;
  uint v53;
  uint v54;
  uint v55;
  uint v56;
  bool v57;
  uint v58;
  bool v59;
  uint v60;
  uint v61;
  bool v62;
  uint v63;
  uint v65;
  uint v66;
  bool v67;
  uint v68;
  uint v69;
  uint v70;
  uint v71;
  bool v72;
  uint v73;
  uint v75;
  uint v76;
  bool v77;
  uint v78;
  uint v79;
  uint v80;
  uint v81;
  bool v82;
  uint v83;
  uint v84;
  bool v85;
  uint v86;
  uint v87;
  bool v88;
  uint v89;
  uint v90;
  bool v91;
  uint v92;
  uint v93;
  uint v94;
  uint v95;
  uint v96;
  bool v97;
  uint v98;
  bool v99;
  uint v100;
  uint v101;
  bool v102;
  uint v103;
  ulong v105;
  uint v107;
  ulong v108;
  uint v109;
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
      if (v16) { pc = 7u; } else { pc = 20u; }
      continue;
    }
    case 7: {
      v17 = *(thread uint*)(fr + 24u);
      v18 = (uint)1u;
      v19 = (uint)(v17 + v18);
      v20 = (uint)(~v17);
      v21 = v18 <= v20;
      if (v21) { pc = 9u; } else { pc = 8u; }
      continue;
    }
    case 8: {
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
    case 9: {
      *(thread uint*)(fr + 24u) = v19;
      v22 = *(thread uint*)(fr + 24u);
      v23 = (uint)3u;
      v24 = (uint)0u;
      v25 = v23 != v24;
      if (v25) { pc = 11u; } else { pc = 10u; }
      continue;
    }
    case 10: {
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
    case 11: {
      v26 = (uint)(v22 % v23);
      v27 = (uint)0u;
      v28 = v26 == v27;
      if (v28) { pc = 12u; } else { pc = 13u; }
      continue;
    }
    case 12: {
      pc = 4u; continue;
    }
    case 13: {
      pc = 14u; continue;
    }
    case 14: {
      v29 = *(thread uint*)(fr + 24u);
      v30 = (uint)11u;
      v31 = v29 > v30;
      if (v31) { pc = 15u; } else { pc = 16u; }
      continue;
    }
    case 15: {
      pc = 20u; continue;
    }
    case 16: {
      pc = 17u; continue;
    }
    case 17: {
      v32 = *(thread uint*)(fr + 16u);
      v33 = *(thread uint*)(fr + 24u);
      v34 = (uint)(v32 + v33);
      v35 = (uint)(~v32);
      v36 = v33 <= v35;
      if (v36) { pc = 19u; } else { pc = 18u; }
      continue;
    }
    case 18: {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 4;
      *(device uint*)((device uchar*)count + 12) = 15u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
      return;
    }
    case 19: {
      *(thread uint*)(fr + 16u) = v34;
      pc = 4u; continue;
    }
    case 20: {
      v37 = (uint)0u;
      v38 = (uint)4u;
      v39 = (uint)(v5 + v38);
      v40 = (uint)(~v5);
      v41 = v38 <= v40;
      if (v41) { pc = 22u; } else { pc = 21u; }
      continue;
    }
    case 21: {
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
    case 22: {
      *(thread uint*)(fr + 32u) = v37;
      pc = 23u; continue;
    }
    case 23: {
      v43 = *(thread uint*)(fr + 32u);
      v44 = v43 < v39;
      if (v44) { pc = 25u; } else { pc = 38u; }
      continue;
    }
    case 24: {
      v45 = *(thread uint*)(fr + 32u);
      v46 = (uint)1u;
      v47 = (uint)(v45 + v46);
      *(thread uint*)(fr + 32u) = v47;
      pc = 23u; continue;
    }
    case 25: {
      v48 = *(thread uint*)(fr + 32u);
      v49 = (uint)2u;
      v50 = v48 == v49;
      if (v50) { pc = 26u; } else { pc = 27u; }
      continue;
    }
    case 26: {
      pc = 24u; continue;
    }
    case 27: {
      pc = 28u; continue;
    }
    case 28: {
      v51 = (uint)8u;
      v52 = v48 >= v51;
      if (v52) { pc = 29u; } else { pc = 30u; }
      continue;
    }
    case 29: {
      pc = 38u; continue;
    }
    case 30: {
      pc = 31u; continue;
    }
    case 31: {
      v53 = *(thread uint*)(fr + 16u);
      v54 = (uint)2u;
      v55 = (uint)(v48 * v54);
      v56 = (uint)0u;
      v57 = v48 == v56;
      if (v57) { pc = 35u; } else { pc = 32u; }
      continue;
    }
    case 32: {
      v58 = (uint)(v55 / v48);
      v59 = v58 == v54;
      if (v59) { pc = 34u; } else { pc = 33u; }
      continue;
    }
    case 33: {
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
    case 34: {
      pc = 35u; continue;
    }
    case 35: {
      v60 = (uint)(v53 + v55);
      v61 = (uint)(~v53);
      v62 = v55 <= v61;
      if (v62) { pc = 37u; } else { pc = 36u; }
      continue;
    }
    case 36: {
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
    case 37: {
      *(thread uint*)(fr + 16u) = v60;
      pc = 24u; continue;
    }
    case 38: {
      v63 = (uint)0u;
      *(thread uint*)(fr + 40u) = v63;
      pc = 39u; continue;
    }
    case 39: {
      v65 = *(thread uint*)(fr + 40u);
      v66 = (uint)3u;
      v67 = v65 < v66;
      if (v67) { pc = 40u; } else { pc = 63u; }
      continue;
    }
    case 40: {
      v68 = *(thread uint*)(fr + 40u);
      v69 = (uint)1u;
      v70 = (uint)(v68 + v69);
      v71 = (uint)(~v68);
      v72 = v69 <= v71;
      if (v72) { pc = 42u; } else { pc = 41u; }
      continue;
    }
    case 41: {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 4;
      *(device uint*)((device uchar*)count + 12) = 24u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
      return;
    }
    case 42: {
      *(thread uint*)(fr + 40u) = v70;
      v73 = (uint)0u;
      *(thread uint*)(fr + 48u) = v73;
      pc = 43u; continue;
    }
    case 43: {
      v75 = *(thread uint*)(fr + 48u);
      v76 = (uint)5u;
      v77 = v75 < v76;
      if (v77) { pc = 44u; } else { pc = 62u; }
      continue;
    }
    case 44: {
      v78 = *(thread uint*)(fr + 48u);
      v79 = (uint)1u;
      v80 = (uint)(v78 + v79);
      v81 = (uint)(~v78);
      v82 = v79 <= v81;
      if (v82) { pc = 46u; } else { pc = 45u; }
      continue;
    }
    case 45: {
      {
        device atomic_uint* count = (device atomic_uint*)(heap + *(device const ulong*)args);
        uint expected = 0u;
        if (atomic_compare_exchange_weak_explicit(count, &expected, 1u, memory_order_relaxed, memory_order_relaxed)) {
      *(device uchar*)((device uchar*)count + 8) = 4;
      *(device uint*)((device uchar*)count + 12) = 27u;
            *(device uint*)((device uchar*)count + 16) = gid3.x;
            *(device uint*)((device uchar*)count + 20) = gid3.y;
            *(device uint*)((device uchar*)count + 24) = gid3.z;
        } else {
            atomic_fetch_add_explicit(count, 1u, memory_order_relaxed);
        }
      }
      return;
    }
    case 46: {
      *(thread uint*)(fr + 48u) = v80;
      v83 = *(thread uint*)(fr + 48u);
      v84 = (uint)2u;
      v85 = v83 == v84;
      if (v85) { pc = 47u; } else { pc = 48u; }
      continue;
    }
    case 47: {
      pc = 43u; continue;
    }
    case 48: {
      pc = 49u; continue;
    }
    case 49: {
      v86 = *(thread uint*)(fr + 40u);
      v87 = (uint)3u;
      v88 = v86 == v87;
      if (v88) { pc = 50u; } else { pc = 54u; }
      continue;
    }
    case 50: {
      v89 = *(thread uint*)(fr + 48u);
      v90 = (uint)4u;
      v91 = v89 == v90;
      if (v91) { pc = 51u; } else { pc = 52u; }
      continue;
    }
    case 51: {
      pc = 62u; continue;
    }
    case 52: {
      pc = 53u; continue;
    }
    case 53: {
      pc = 55u; continue;
    }
    case 54: {
      pc = 55u; continue;
    }
    case 55: {
      v92 = *(thread uint*)(fr + 16u);
      v93 = *(thread uint*)(fr + 40u);
      v94 = *(thread uint*)(fr + 48u);
      v95 = (uint)(v93 * v94);
      v96 = (uint)0u;
      v97 = v93 == v96;
      if (v97) { pc = 59u; } else { pc = 56u; }
      continue;
    }
    case 56: {
      v98 = (uint)(v95 / v93);
      v99 = v98 == v94;
      if (v99) { pc = 58u; } else { pc = 57u; }
      continue;
    }
    case 57: {
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
    case 58: {
      pc = 59u; continue;
    }
    case 59: {
      v100 = (uint)(v92 + v95);
      v101 = (uint)(~v92);
      v102 = v95 <= v101;
      if (v102) { pc = 61u; } else { pc = 60u; }
      continue;
    }
    case 60: {
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
    case 61: {
      *(thread uint*)(fr + 16u) = v100;
      pc = 43u; continue;
    }
    case 62: {
      pc = 39u; continue;
    }
    case 63: {
      v103 = (uint)v5;
      v105 = *(thread ulong*)(fr + 0u);
      v107 = *(thread uint*)(fr + 8u);
      if (!(v103 < v107)) {
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
      v108 = v105 + (ulong)v103 * 4ul;
      v109 = *(thread uint*)(fr + 16u);
      *(device uint*)HP(v108) = v109;
      return;
    }
    default: return;
    }
  }
}

