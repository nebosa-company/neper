//entry:saxpy_saxpy
#version 430
layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(std430, binding = 0) readonly buffer Args { uint args[]; };
layout(std430, binding = 1) buffer Heap { uint heap[]; };
void main() {
  uint a;
  uint fr[8];
  for (uint z = 0u; z < 8u; z += 1u) fr[z] = 0u;
  uint v0;
  precise float v1;
  uint v7;
  bool v8;
  uint v9;
  uint v11;
  uint v13;
  uint v14;
  uint v16;
  uint v18;
  uint v19;
  precise float v20;
  precise float v21;
  uint v23;
  uint v25;
  uint v26;
  precise float v27;
  precise float v28;
  uint pc = 0u;
  while (true) {
    if (pc == 0u) {
      a = 8u;
      v0 = args[a >> 2u];
      a = 12u;
      v1 = uintBitsToFloat(args[a >> 2u]);
      fr[0u] = args[4u]; fr[1u] = 0u; fr[2u] = args[6u]; fr[3u] = 0u;
      fr[4u] = args[8u]; fr[5u] = 0u; fr[6u] = args[10u]; fr[7u] = 0u;
      v7 = gl_GlobalInvocationID.x;
      v8 = v7 >= uint(v0);
      if (v8) { pc = 1u; } else { pc = 2u; }
      continue;
    }
    if (pc == 1u) {
      return;
    }
    if (pc == 2u) {
      pc = 3u; continue;
    }
    if (pc == 3u) {
      v9 = uint(v7);
      a = 16u;
      v11 = fr[a >> 2u];
      a = 24u;
      v13 = fr[a >> 2u];
      if (!(v9 < v13)) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 0u, 0, 8);
        heap[f + 3u] = 25u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
        return;
      }
      v14 = v11 + uint(v9) * 4u;
      a = 0u;
      v16 = fr[a >> 2u];
      a = 8u;
      v18 = fr[a >> 2u];
      if (!(v9 < v18)) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 0u, 0, 8);
        heap[f + 3u] = 25u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
        return;
      }
      v19 = v16 + uint(v9) * 4u;
      a = v19;
      v20 = uintBitsToFloat(heap[a >> 2u]);
      v21 = float(v1) * float(v20);
      if (isnan(v21)) v21 = uintBitsToFloat(0x7FC00000u);
      a = 16u;
      v23 = fr[a >> 2u];
      a = 24u;
      v25 = fr[a >> 2u];
      if (!(v9 < v25)) {
      {
        uint f = args[0] >> 2u;
        if (atomicCompSwap(heap[f], 0u, 1u) == 0u) {
        heap[f + 2u] = bitfieldInsert(heap[f + 2u], 0u, 0, 8);
        heap[f + 3u] = 25u;
          heap[f + 4u] = gl_GlobalInvocationID.x;
          heap[f + 5u] = gl_GlobalInvocationID.y;
          heap[f + 6u] = gl_GlobalInvocationID.z;
        } else {
          atomicAdd(heap[f], 1u);
        }
      }
        return;
      }
      v26 = v23 + uint(v9) * 4u;
      a = v26;
      v27 = uintBitsToFloat(heap[a >> 2u]);
      v28 = float(v21) + float(v27);
      if (isnan(v28)) v28 = uintBitsToFloat(0x7FC00000u);
      a = v14;
      heap[a >> 2u] = floatBitsToUint(v28);
      return;
    }
    break;
  }
  return;
}
