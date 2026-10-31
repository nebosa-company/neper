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
  uint v93;
  uint v95;
  uint v96;
  uint v97;
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
        heap[f + 3u] = 14u;
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
      if (v16) { pc = 7u; } else { pc = 16u; }
      continue;
    }
    if (pc == 7u) {
      a = 24u;
      v17 = fr[a >> 2u];
      v18 = 0x00000001u;
      v19 = uint(v17) + uint(v18);
      a = 24u;
      fr[a >> 2u] = uint(v19);
      a = 24u;
      v20 = fr[a >> 2u];
      v21 = 0x00000003u;
      v22 = 0x00000000u;
      v23 = v21 != uint(v22);
      if (v23) { pc = 9u; } else { pc = 8u; }
      continue;
    }
    if (pc == 8u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 5u, 0, 8);
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
      v24 = uint(v20 + uint(gl_NumWorkGroups.z == 0u)) % uint(v21 + uint(gl_NumWorkGroups.z == 0u));
      v25 = 0x00000000u;
      v26 = v24 == uint(v25);
      if (v26) { pc = 10u; } else { pc = 11u; }
      continue;
    }
    if (pc == 10u) {
      pc = 4u; continue;
    }
    if (pc == 11u) {
      pc = 12u; continue;
    }
    if (pc == 12u) {
      a = 24u;
      v27 = fr[a >> 2u];
      v28 = 0x0000000bu;
      v29 = v27 > uint(v28);
      if (v29) { pc = 13u; } else { pc = 14u; }
      continue;
    }
    if (pc == 13u) {
      pc = 16u; continue;
    }
    if (pc == 14u) {
      pc = 15u; continue;
    }
    if (pc == 15u) {
      a = 16u;
      v30 = fr[a >> 2u];
      a = 24u;
      v31 = fr[a >> 2u];
      v32 = uint(v30) + uint(v31);
      a = 16u;
      fr[a >> 2u] = uint(v32);
      pc = 4u; continue;
    }
    if (pc == 16u) {
      v33 = 0x00000000u;
      v34 = 0x00000004u;
      v35 = uint(v5) + uint(v34);
      v36 = ~v5;
      v37 = v34 <= uint(v36);
      if (v37) { pc = 18u; } else { pc = 17u; }
      continue;
    }
    if (pc == 17u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 20u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 18u) {
      a = 32u;
      fr[a >> 2u] = uint(v33);
      pc = 19u; continue;
    }
    if (pc == 19u) {
      a = 32u;
      v39 = fr[a >> 2u];
      v40 = v39 < uint(v35);
      if (v40) { pc = 21u; } else { pc = 32u; }
      continue;
    }
    if (pc == 20u) {
      a = 32u;
      v41 = fr[a >> 2u];
      v42 = 0x00000001u;
      v43 = uint(v41) + uint(v42);
      a = 32u;
      fr[a >> 2u] = uint(v43);
      pc = 19u; continue;
    }
    if (pc == 21u) {
      a = 32u;
      v44 = fr[a >> 2u];
      v45 = 0x00000002u;
      v46 = v44 == uint(v45);
      if (v46) { pc = 22u; } else { pc = 23u; }
      continue;
    }
    if (pc == 22u) {
      pc = 20u; continue;
    }
    if (pc == 23u) {
      pc = 24u; continue;
    }
    if (pc == 24u) {
      v47 = 0x00000008u;
      v48 = v44 >= uint(v47);
      if (v48) { pc = 25u; } else { pc = 26u; }
      continue;
    }
    if (pc == 25u) {
      pc = 32u; continue;
    }
    if (pc == 26u) {
      pc = 27u; continue;
    }
    if (pc == 27u) {
      a = 16u;
      v49 = fr[a >> 2u];
      v50 = 0x00000002u;
      v51 = uint(v44) * uint(v50);
      v52 = 0x00000000u;
      v53 = v44 == uint(v52);
      if (v53) { pc = 31u; } else { pc = 28u; }
      continue;
    }
    if (pc == 28u) {
      v54 = uint(v51 + uint(gl_NumWorkGroups.z == 0u)) / uint(v44 + uint(gl_NumWorkGroups.z == 0u));
      v55 = v54 == uint(v50);
      if (v55) { pc = 30u; } else { pc = 29u; }
      continue;
    }
    if (pc == 29u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 23u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 30u) {
      pc = 31u; continue;
    }
    if (pc == 31u) {
      v56 = uint(v49) + uint(v51);
      a = 16u;
      fr[a >> 2u] = uint(v56);
      pc = 20u; continue;
    }
    if (pc == 32u) {
      v57 = 0x00000000u;
      a = 40u;
      fr[a >> 2u] = uint(v57);
      pc = 33u; continue;
    }
    if (pc == 33u) {
      a = 40u;
      v59 = fr[a >> 2u];
      v60 = 0x00000003u;
      v61 = v59 < uint(v60);
      if (v61) { pc = 34u; } else { pc = 51u; }
      continue;
    }
    if (pc == 34u) {
      a = 40u;
      v62 = fr[a >> 2u];
      v63 = 0x00000001u;
      v64 = uint(v62) + uint(v63);
      a = 40u;
      fr[a >> 2u] = uint(v64);
      v65 = 0x00000000u;
      a = 48u;
      fr[a >> 2u] = uint(v65);
      pc = 35u; continue;
    }
    if (pc == 35u) {
      a = 48u;
      v67 = fr[a >> 2u];
      v68 = 0x00000005u;
      v69 = v67 < uint(v68);
      if (v69) { pc = 36u; } else { pc = 50u; }
      continue;
    }
    if (pc == 36u) {
      a = 48u;
      v70 = fr[a >> 2u];
      v71 = 0x00000001u;
      v72 = uint(v70) + uint(v71);
      a = 48u;
      fr[a >> 2u] = uint(v72);
      a = 48u;
      v73 = fr[a >> 2u];
      v74 = 0x00000002u;
      v75 = v73 == uint(v74);
      if (v75) { pc = 37u; } else { pc = 38u; }
      continue;
    }
    if (pc == 37u) {
      pc = 35u; continue;
    }
    if (pc == 38u) {
      pc = 39u; continue;
    }
    if (pc == 39u) {
      a = 40u;
      v76 = fr[a >> 2u];
      v77 = 0x00000003u;
      v78 = v76 == uint(v77);
      if (v78) { pc = 40u; } else { pc = 44u; }
      continue;
    }
    if (pc == 40u) {
      a = 48u;
      v79 = fr[a >> 2u];
      v80 = 0x00000004u;
      v81 = v79 == uint(v80);
      if (v81) { pc = 41u; } else { pc = 42u; }
      continue;
    }
    if (pc == 41u) {
      pc = 50u; continue;
    }
    if (pc == 42u) {
      pc = 43u; continue;
    }
    if (pc == 43u) {
      pc = 45u; continue;
    }
    if (pc == 44u) {
      pc = 45u; continue;
    }
    if (pc == 45u) {
      a = 16u;
      v82 = fr[a >> 2u];
      a = 40u;
      v83 = fr[a >> 2u];
      a = 48u;
      v84 = fr[a >> 2u];
      v85 = uint(v83) * uint(v84);
      v86 = 0x00000000u;
      v87 = v83 == uint(v86);
      if (v87) { pc = 49u; } else { pc = 46u; }
      continue;
    }
    if (pc == 46u) {
      v88 = uint(v85 + uint(gl_NumWorkGroups.z == 0u)) / uint(v83 + uint(gl_NumWorkGroups.z == 0u));
      v89 = v88 == uint(v84);
      if (v89) { pc = 48u; } else { pc = 47u; }
      continue;
    }
    if (pc == 47u) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 4u, 0, 8);
        heap[f + 3u] = 35u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
      return;
    }
    if (pc == 48u) {
      pc = 49u; continue;
    }
    if (pc == 49u) {
      v90 = uint(v82) + uint(v85);
      a = 16u;
      fr[a >> 2u] = uint(v90);
      pc = 35u; continue;
    }
    if (pc == 50u) {
      pc = 33u; continue;
    }
    if (pc == 51u) {
      v91 = uint(v5);
      a = 0u;
      v93 = fr[a >> 2u];
      a = 8u;
      v95 = fr[a >> 2u];
      if (!(v91 < v95)) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 0u, 0, 8);
        heap[f + 3u] = 38u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
        return;
      }
      v96 = v93 + uint(v91) * 4u;
      a = 16u;
      v97 = fr[a >> 2u];
      a = v96;
      heap[a >> 2u] = uint(v97);
      return;
    }
    break;
  }
  return;
}
