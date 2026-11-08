//entry:main_loops
#version 430
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(std430, binding = 0) readonly buffer Args { uint args[]; };
layout(std430, binding = 1) buffer Heap { uint heap[]; };
void main() {
  uint a;
  uint fr[14];
  for (uint z = 0u; z < 14u; z += 1u) fr[z] = 0u;
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
  uint v105;
  uint v107;
  uint v108;
  uint v109;
  uint pc = 0u;
  while (true) {
    if (pc == 0u) {
      a = 8u;
      v0 = args[a >> 2u];
      fr[0u] = args[4u]; fr[1u] = 0u; fr[2u] = args[6u]; fr[3u] = 0u;
      v5 = gl_GlobalInvocationID.x;
      v6 = v5 >= uint(v0);
      if (v6) { pc = 1u; } else { pc = 2u; }
      continue;
    }
    if (pc == 1u) {
      return;
    }
    if (pc == 2u) {
      pc = 3u; continue;
    }
    if (pc == 3u) {
      v7 = 0x00000000u;
      a = 16u;
      fr[a >> 2u] = uint(v7);
      v9 = 0x00000000u;
      a = 24u;
      fr[a >> 2u] = uint(v9);
      pc = 4u; continue;
    }
    if (pc == 4u) {
      a = 24u;
      v11 = fr[a >> 2u];
      v12 = 0x00000007u;
      v13 = uint(v5) + uint(v12);
      v14 = ~v5;
      v15 = v12 <= uint(v14);
      if (v15) { pc = 6u; } else { pc = 5u; }
      continue;
    }
    if (pc == 5u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 15u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 6u) {
      v16 = v11 < uint(v13);
      if (v16) { pc = 7u; } else { pc = 20u; }
      continue;
    }
    if (pc == 7u) {
      a = 24u;
      v17 = fr[a >> 2u];
      v18 = 0x00000001u;
      v19 = uint(v17) + uint(v18);
      v20 = ~v17;
      v21 = v18 <= uint(v20);
      if (v21) { pc = 9u; } else { pc = 8u; }
      continue;
    }
    if (pc == 8u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 16u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 9u) {
      a = 24u;
      fr[a >> 2u] = uint(v19);
      a = 24u;
      v22 = fr[a >> 2u];
      v23 = 0x00000003u;
      v24 = 0x00000000u;
      v25 = v23 != uint(v24);
      if (v25) { pc = 11u; } else { pc = 10u; }
      continue;
    }
    if (pc == 10u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 5u, 0, 8);
        heap[f + 3u] = 17u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 11u) {
      v26 = uint(v22 + uint(gl_NumWorkGroups.z == 0u)) % uint(v23 + uint(gl_NumWorkGroups.z == 0u));
      v27 = 0x00000000u;
      v28 = v26 == uint(v27);
      if (v28) { pc = 12u; } else { pc = 13u; }
      continue;
    }
    if (pc == 12u) {
      pc = 4u; continue;
    }
    if (pc == 13u) {
      pc = 14u; continue;
    }
    if (pc == 14u) {
      a = 24u;
      v29 = fr[a >> 2u];
      v30 = 0x0000000bu;
      v31 = v29 > uint(v30);
      if (v31) { pc = 15u; } else { pc = 16u; }
      continue;
    }
    if (pc == 15u) {
      pc = 20u; continue;
    }
    if (pc == 16u) {
      pc = 17u; continue;
    }
    if (pc == 17u) {
      a = 16u;
      v32 = fr[a >> 2u];
      a = 24u;
      v33 = fr[a >> 2u];
      v34 = uint(v32) + uint(v33);
      v35 = ~v32;
      v36 = v33 <= uint(v35);
      if (v36) { pc = 19u; } else { pc = 18u; }
      continue;
    }
    if (pc == 18u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 19u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 19u) {
      a = 16u;
      fr[a >> 2u] = uint(v34);
      pc = 4u; continue;
    }
    if (pc == 20u) {
      v37 = 0x00000000u;
      v38 = 0x00000004u;
      v39 = uint(v5) + uint(v38);
      v40 = ~v5;
      v41 = v38 <= uint(v40);
      if (v41) { pc = 22u; } else { pc = 21u; }
      continue;
    }
    if (pc == 21u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 21u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 22u) {
      a = 32u;
      fr[a >> 2u] = uint(v37);
      pc = 23u; continue;
    }
    if (pc == 23u) {
      a = 32u;
      v43 = fr[a >> 2u];
      v44 = v43 < uint(v39);
      if (v44) { pc = 25u; } else { pc = 38u; }
      continue;
    }
    if (pc == 24u) {
      a = 32u;
      v45 = fr[a >> 2u];
      v46 = 0x00000001u;
      v47 = uint(v45) + uint(v46);
      a = 32u;
      fr[a >> 2u] = uint(v47);
      pc = 23u; continue;
    }
    if (pc == 25u) {
      a = 32u;
      v48 = fr[a >> 2u];
      v49 = 0x00000002u;
      v50 = v48 == uint(v49);
      if (v50) { pc = 26u; } else { pc = 27u; }
      continue;
    }
    if (pc == 26u) {
      pc = 24u; continue;
    }
    if (pc == 27u) {
      pc = 28u; continue;
    }
    if (pc == 28u) {
      v51 = 0x00000008u;
      v52 = v48 >= uint(v51);
      if (v52) { pc = 29u; } else { pc = 30u; }
      continue;
    }
    if (pc == 29u) {
      pc = 38u; continue;
    }
    if (pc == 30u) {
      pc = 31u; continue;
    }
    if (pc == 31u) {
      a = 16u;
      v53 = fr[a >> 2u];
      v54 = 0x00000002u;
      v55 = uint(v48) * uint(v54);
      v56 = 0x00000000u;
      v57 = v48 == uint(v56);
      if (v57) { pc = 35u; } else { pc = 32u; }
      continue;
    }
    if (pc == 32u) {
      v58 = uint(v55 + uint(gl_NumWorkGroups.z == 0u)) / uint(v48 + uint(gl_NumWorkGroups.z == 0u));
      v59 = v58 == uint(v54);
      if (v59) { pc = 34u; } else { pc = 33u; }
      continue;
    }
    if (pc == 33u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 24u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 34u) {
      pc = 35u; continue;
    }
    if (pc == 35u) {
      v60 = uint(v53) + uint(v55);
      v61 = ~v53;
      v62 = v55 <= uint(v61);
      if (v62) { pc = 37u; } else { pc = 36u; }
      continue;
    }
    if (pc == 36u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 24u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 37u) {
      a = 16u;
      fr[a >> 2u] = uint(v60);
      pc = 24u; continue;
    }
    if (pc == 38u) {
      v63 = 0x00000000u;
      a = 40u;
      fr[a >> 2u] = uint(v63);
      pc = 39u; continue;
    }
    if (pc == 39u) {
      a = 40u;
      v65 = fr[a >> 2u];
      v66 = 0x00000003u;
      v67 = v65 < uint(v66);
      if (v67) { pc = 40u; } else { pc = 63u; }
      continue;
    }
    if (pc == 40u) {
      a = 40u;
      v68 = fr[a >> 2u];
      v69 = 0x00000001u;
      v70 = uint(v68) + uint(v69);
      v71 = ~v68;
      v72 = v69 <= uint(v71);
      if (v72) { pc = 42u; } else { pc = 41u; }
      continue;
    }
    if (pc == 41u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 28u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 42u) {
      a = 40u;
      fr[a >> 2u] = uint(v70);
      v73 = 0x00000000u;
      a = 48u;
      fr[a >> 2u] = uint(v73);
      pc = 43u; continue;
    }
    if (pc == 43u) {
      a = 48u;
      v75 = fr[a >> 2u];
      v76 = 0x00000005u;
      v77 = v75 < uint(v76);
      if (v77) { pc = 44u; } else { pc = 62u; }
      continue;
    }
    if (pc == 44u) {
      a = 48u;
      v78 = fr[a >> 2u];
      v79 = 0x00000001u;
      v80 = uint(v78) + uint(v79);
      v81 = ~v78;
      v82 = v79 <= uint(v81);
      if (v82) { pc = 46u; } else { pc = 45u; }
      continue;
    }
    if (pc == 45u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 31u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 46u) {
      a = 48u;
      fr[a >> 2u] = uint(v80);
      a = 48u;
      v83 = fr[a >> 2u];
      v84 = 0x00000002u;
      v85 = v83 == uint(v84);
      if (v85) { pc = 47u; } else { pc = 48u; }
      continue;
    }
    if (pc == 47u) {
      pc = 43u; continue;
    }
    if (pc == 48u) {
      pc = 49u; continue;
    }
    if (pc == 49u) {
      a = 40u;
      v86 = fr[a >> 2u];
      v87 = 0x00000003u;
      v88 = v86 == uint(v87);
      if (v88) { pc = 50u; } else { pc = 54u; }
      continue;
    }
    if (pc == 50u) {
      a = 48u;
      v89 = fr[a >> 2u];
      v90 = 0x00000004u;
      v91 = v89 == uint(v90);
      if (v91) { pc = 51u; } else { pc = 52u; }
      continue;
    }
    if (pc == 51u) {
      pc = 62u; continue;
    }
    if (pc == 52u) {
      pc = 53u; continue;
    }
    if (pc == 53u) {
      pc = 55u; continue;
    }
    if (pc == 54u) {
      pc = 55u; continue;
    }
    if (pc == 55u) {
      a = 16u;
      v92 = fr[a >> 2u];
      a = 40u;
      v93 = fr[a >> 2u];
      a = 48u;
      v94 = fr[a >> 2u];
      v95 = uint(v93) * uint(v94);
      v96 = 0x00000000u;
      v97 = v93 == uint(v96);
      if (v97) { pc = 59u; } else { pc = 56u; }
      continue;
    }
    if (pc == 56u) {
      v98 = uint(v95 + uint(gl_NumWorkGroups.z == 0u)) / uint(v93 + uint(gl_NumWorkGroups.z == 0u));
      v99 = v98 == uint(v94);
      if (v99) { pc = 58u; } else { pc = 57u; }
      continue;
    }
    if (pc == 57u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 36u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 58u) {
      pc = 59u; continue;
    }
    if (pc == 59u) {
      v100 = uint(v92) + uint(v95);
      v101 = ~v92;
      v102 = v95 <= uint(v101);
      if (v102) { pc = 61u; } else { pc = 60u; }
      continue;
    }
    if (pc == 60u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 36u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 61u) {
      a = 16u;
      fr[a >> 2u] = uint(v100);
      pc = 43u; continue;
    }
    if (pc == 62u) {
      pc = 39u; continue;
    }
    if (pc == 63u) {
      v103 = uint(v5);
      a = 0u;
      v105 = fr[a >> 2u];
      a = 8u;
      v107 = fr[a >> 2u];
      if (!(v103 < v107)) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 0u, 0, 8);
        heap[f + 3u] = 39u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
        return;
      }
      v108 = v105 + uint(v103) * 4u;
      a = 16u;
      v109 = fr[a >> 2u];
      a = v108;
      heap[a >> 2u] = uint(v109);
      return;
    }
    break;
  }
  return;
}
