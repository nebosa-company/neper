# Neper OpenGL and OpenGL ES design

Decisions D5940–D5884. The work items, with their acceptance criteria, models and
thinking levels, are the `OpenGL` group in `docs/work-queue.json` (C214–C220,
L172–L182, T044–T049). This file holds only the design and the order.

## Three layers

1. **A binding** — `x.khronos.gl` and `x.khronos.egl`, loaded at run time like
   `e.gpu.vulkan`. Programs draw with GLSL strings. This is how Neper reaches graphics
   (vertex and fragment stages) without changing the language; §10's compute-only
   `@gpu` stands (D5940).
2. **Presentation** — `e.ui` uploads its finished CPU frame as a texture and swaps with
   vsync. The CPU renderer stays the one renderer.
3. **Compute** — `e.gpu`'s `Backend.Gl` runs kernels on GL 4.3 or GLES 3.1 where there is
   no Vulkan. It uses Metal's model: one SSBO heap, with a device address as a byte
   offset into it, emitted by `src/glsl.e` (D5941).

Profiles, contexts, threading, exactness, generation and the mobile plan are D5879–D5884.

## Order and parallelism

- **Phase 1, the binding (L172–L177, T045)** comes first: everything else loads through
  it. L174 (Linux EGL) and L175 (Windows WGL) touch different `os` hosts and can run at
  the same time.
- **Phase 2, presentation (L178, L179, T046)** and **phase 3, compute (C214–C218,
  L180, L181, T047, T048)** depend only on L173 plus one context item, so they can run
  side by side.
- C215, C216 and C217 all edit `src/glsl.e` and run one at a time, in that order.
- **Phase 4, Android (C219, C220, L182, T044, T049)** starts after T047. C220, L182,
  T044 and T049 also wait for an `@export` proposal.

## Verification hosts

- **Windows:** the machine's own GL driver, and ANGLE for GLES.
- **Linux:** cross-compiled ELF run in WSL on Mesa llvmpipe (`LIBGL_ALWAYS_SOFTWARE=1`,
  surfaceless EGL). llvmpipe is deterministic, so image goldens are exact there. This
  uses the per-target fixture route, because neither full suite completes on this
  machine.
- **macOS:** CI runners, for L176 only.
- **Android:** the SDK's x86_64 emulator image, running `android-x64` output with the
  existing x64 back end.

Prerequisites that need the user's go-ahead: the Khronos registry XML, Mesa EGL/GLES in
WSL, the ANGLE DLLs, and the Android SDK and emulator.

## Risks and known ceilings

- **Exact `f32` division in GLSL (C217)** is the hardest item. The fallback is to
  emulate the divide in integers: slower, but exact.
- **Atomic-RMW narrow stores (C216)** make byte-heavy kernels slow on GL. Vulkan stays
  the fast path wherever it exists.
- **The 256 MiB heap** is the ceiling Metal also hit (D5853). A second heap is a later
  item for both backends.
- **The second X11 connection (L174)** must keep GL's swaps and Neper's own `Expose` and
  resize handling in step.
- **Driver variance:** on real drivers, goldens compare words only where the CPU backend
  defines them; image goldens are exact on llvmpipe only.

## Not planned

Vertex and fragment stages in `@gpu`; GL before 3.3 and GLES before 3.0; GLES on iOS;
GL on NeperOS; OpenCL.
