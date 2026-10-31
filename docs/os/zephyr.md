# Architectural Blueprint: Implementing Zephyr Support in the Neper Toolchain

This document specifies how to extend the **Neper** direct-emitting toolchain to build applications for the Zephyr RTOS.

Zephyr and FreeRTOS differ in one decisive way. FreeRTOS is a kernel you link. **Zephyr is a build system and a platform**: CMake, Kconfig, devicetree and `west` assemble the kernel, drivers, libc and the application for a chosen board, and the application is one source set among many. Neper therefore cannot own the final link and the image the way it can on Linux. Neper's job is to emit the *application object* and to plug into Zephyr's build as an external module.

`freertos.md` describes the shared embedded backend (Thumb-2 code generation, AAPCS32, ELF relocatable objects, the runtime helpers, code-size and stack tooling, RISC-V). **Read its sections 1, 2.1 and 4 first.** This document covers only what Zephyr changes. The same numbers-from-memory caveat applies: confirm against the Zephyr release in use (this document assumes the 3.x and 4.x series).

---

## 1. Integration Model

| Layer | Owner |
| :--- | :--- |
| Board, SoC, drivers, kernel, libc (picolibc by default in recent releases) | Zephyr, built by `west build -b <board>` |
| Application code, `e.*` standard library | **Neper**, compiled to an ELF relocatable object or archive (`libapp.a`) |
| The bridge: C functions that Neper can link against | **`neper-zephyr` module** (C shim, Kconfig, CMake) |

**Decision: deliver Neper as an out-of-tree Zephyr module.** A directory with `zephyr/module.yml`, `CMakeLists.txt` and `Kconfig`, found by the build through `ZEPHYR_EXTRA_MODULES`. Its `CMakeLists.txt`:

1.  runs `neper build --target <triple>-zephyr <project>` as a `add_custom_command`, producing `libapp.a` in the build tree,
2.  imports it with `zephyr_library_import(neper_app libapp.a)`,
3.  compiles the shim `neper_zephyr.c` into the Zephyr image like any other source.

The user keeps the whole of Zephyr's board support, drivers and tools, and Neper requires only that `neper` is on the build host's `PATH`. A Windows host works, since `west` runs there.

**The application entry** is `int main(void)`, which Zephyr's main thread calls after kernel start. Neper provides it. Zephyr, not Neper, owns the vector table, startup, MMU/MPU setup and the linker script.

---

## 2. Compiler Backend and Targets

Zephyr runs on many architectures. Neper supports a subset, in order of cheapness:

| Zephyr board / arch | Neper backend | Why |
| :--- | :--- | :--- |
| `native_sim/native/64` | **existing x86-64 ELF emitter** | Zephyr compiled as a Linux process (host libc, host gcc). Needs no new ISA work. |
| `qemu_x86_64` | existing x86-64 emitter | Bare-metal x86-64 under QEMU. Confirm the red zone and stack-alignment policy that the Zephyr x86-64 port requires. |
| `qemu_cortex_m3`, `mps2/an385`, real Cortex-M boards | Thumb-2 backend from `freertos.md` | The main embedded market (nRF, STM32, RP2040, i.MX RT, and others). |
| `qemu_riscv32`, `qemu_riscv64`, ESP32-C-series | RV32/RV64 backend | After Thumb-2. |
| Xtensa, ARC, MIPS, SPARC, Cortex-A/R | out of scope | |

*   `native_sim` is the **phase-1 verification target**: it needs no cross-toolchain for Neper, runs in seconds, and gives a debuggable host process. The Zephyr part of the build still needs the host C toolchain and `west`, so on this Windows machine it runs under WSL or a Linux CI job.
*   Neper must emit the object attributes and ABI flags that the board's compiler expects (float ABI, architecture level). A mismatch is a link-time error or, worse, a silent crash.

---

## 3. The C Shim (`neper_zephyr.c`)

Most Zephyr APIs cannot be called from outside C:

*   Many are `static inline` functions or macros in headers (`k_sleep`, `k_mutex_lock`, `K_MSEC`, `K_FOREVER`, `K_THREAD_DEFINE`, `DEVICE_DT_GET`, `GPIO_DT_SPEC_GET`). They have no linkable symbol, or they are syscall wrappers whose real symbol is `z_impl_*` and whose name changes with `CONFIG_USERSPACE`.
*   Timeouts are `k_timeout_t`, a structure holding an `int64_t`, passed by value. That is a 64-bit pair argument under AAPCS32, which is exactly the kind of ABI detail the shim should hide.
*   Object sizes (`struct k_thread`, `struct k_mutex`, `struct fs_file_t`) depend on Kconfig. Neper cannot hard-code them.
*   Devicetree is compile-time. Device handles and pin specifications are produced by macros.

**Decision: all kernel objects and all macro uses live in the shim.** It exposes a small fixed C API with integers, pointers and milliseconds only (the `nz_` prefix), and Neper holds opaque integer handles:

| Group | Shim functions (examples) | Zephyr behind it |
| :--- | :--- | :--- |
| Threads | `nz_thread_create(entry, arg, prio, slot)`, `nz_thread_join`, `nz_yield` | `k_thread_create` on stacks from `K_THREAD_STACK_ARRAY_DEFINE` pools |
| Sync | `nz_mutex_*`, `nz_sem_*`, `nz_msgq_*`, `nz_event_*` | `k_mutex`, `k_sem`, `k_msgq`, `k_event` in static pools |
| Time | `nz_now_ms`, `nz_cycles`, `nz_sleep_ms` | `k_uptime_get`, `k_cycle_get_64`, `k_sleep(K_MSEC(n))` |
| I/O | `nz_write(buf, len)` | `console_write` or `printk` of the length-bounded string |
| Files | `nz_fs_*` | `fs_open`, `fs_read`, `fs_write`, `fs_readdir` (with the VFS and littlefs or FAT enabled) |
| Network | `nz_sock_*` | the sockets API (`zsock_socket`, `zsock_connect`, `zsock_send`, `zsock_recv`, `zsock_poll`) |
| Hardware | `nz_gpio_*`, `nz_i2c_*`, `nz_spi_*` for pins named in the project's `neper.hw` file | driver APIs, with specs from `DT_ALIAS(...)` macros the shim generates |

*   Pool sizes are Kconfig symbols in the module: `NEPER_MAX_THREADS`, `NEPER_THREAD_STACK_SIZE`, `NEPER_MAX_MUTEXES`, and so on. The shim `BUILD_ASSERT`s against the real struct sizes.
*   Pool exhaustion returns an `err` (kind out-of-memory), never a fault.
*   The hardware group is generated from `neper.hw`, a short declarative list of the devicetree aliases the application uses (`led0`, `sw0`, `i2c0`). This keeps devicetree knowledge out of the Neper compiler.

---

## 4. Standard Library Mapping

The target is `surface: "partial"`. Where Zephyr offers a service, Neper maps it. Where it does not, the call returns `Unsupported`.

| Module | Mapping on Zephyr |
| :--- | :--- |
| `e.mem` | A static arena array in `.noinit` or `.bss`, sized by `NEPER_ARENA_KB`. Commit equals reserve, and there is no give-back. `k_heap`/`k_malloc` is unused unless the application opts in. On MMU boards (Cortex-A, `native_sim`) the same fixed arena is used, for one behavior everywhere. |
| `e.thread` | `k_thread` via the shim. **Priority is reversed from FreeRTOS**: a *lower* number is a *higher* priority, **negative values are cooperative** (never preempted by the scheduler), and non-negative values are preemptible. The module maps a portable priority scale onto the range `CONFIG_NUM_COOP_PRIORITIES` and `CONFIG_NUM_PREEMPT_PRIORITIES` allow. Thread count is fixed at build time. |
| `e.sync` | `k_mutex`, `k_sem`, `k_msgq`, `k_event`, `k_condvar`. A forever wait passes `-1` to the shim. |
| `e.time` | `k_uptime_get` (ms since boot, 64-bit, no wrap problem). Wall-clock time needs an RTC driver or an application-supplied value. |
| `e.io` | Through `nz_write`: the console UART, RTT or USB CDC, as `CONFIG_*` selects. |
| `e.fs` | `fs_*` over the Zephyr VFS, on littlefs or FAT, when `CONFIG_FILE_SYSTEM` is enabled. Otherwise `Unsupported`. Paths are mount-point based (`/lfs/...`). |
| `e.net` | Zephyr's BSD-sockets layer. This is the best fit among the embedded targets, since the `e.net` shape already follows sockets. TLS goes through mbedTLS or the sockets TLS option. |
| `e.proc`, `@import` dynamic | `Unsupported`. (Zephyr has no processes and no dynamic loader in the common case.) |
| `e.gpu`, `e.ui`, graphics | `Unsupported`, except through the display API for small framebuffer panels (a later module). |
| `e.fmt.*`, `e.data.*`, `e.str`, `e.math`, `e.simd` | Portable. Same code-size notes as `freertos.md` (float-text tables are optional). |

**Error bridge.** Zephyr functions return **negative `errno`** values (`-EAGAIN`, `-EBUSY`, `-ETIMEDOUT`, `-ENOMEM`, `-EINVAL`, `-ENOENT`). That matches `(T, err)` directly: the shim returns the value unchanged, and Neper's wrapper maps each errno to a portable error kind through one table. Zephyr numbers its errno values like Linux for the common ones (**verify** against `zephyr/errno.h`, since a minimal libc may differ).

---

## 5. Kernel Configuration and Build Details

*   The module's `Kconfig` selects what Neper needs: `CONFIG_MAIN_STACK_SIZE` (the Neper `main` runs on it, and Neper's frame sizes come from `neper stack-report`), `CONFIG_TIMESLICING` as needed, `CONFIG_PRINTK`, `CONFIG_CONSOLE`, and the optional `CONFIG_FILE_SYSTEM`, `CONFIG_NETWORKING`.
*   `CONFIG_USERSPACE` (memory-protected user threads, syscalls through traps) is **out of scope** for the first milestone. Neper code runs in kernel mode. Add it only if there is a need for sandboxed Neper threads, because every shim call would then need a proper `__syscall` definition.
*   Static linking order: `zephyr_library_import` keeps the Neper archive in the same link as the kernel. The Zephyr linker script (not Neper) places `.text`, `.data`, `.bss` and the `.noinit` stacks and arena. Neper must therefore not assume its own sections; it uses standard section names, one section per function.
*   Reproducibility: Neper emits byte-identical objects for byte-identical input, so `west build` caches correctly. The custom command declares the Neper sources and `neper` itself as dependencies.
*   Debugging uses Zephyr's own tools (`west debug`, `west flash`, GDB over OpenOCD or J-Link). Neper's DWARF in the object makes the `.neper` source lines visible.

---

## 6. Verification and Phasing

1. **Phase 1.** `native_sim`: a Neper `main` that prints via the shim and exits. This runs on Linux (WSL or CI). Checks the module plumbing (`module.yml`, CMake import, shim linking) and the existing x86-64 backend, with no new ISA.
2. **Phase 2.** `e.thread`, `e.sync`, `e.time` fixtures on `native_sim`, including the priority-direction fixture (the highest-priority thread must run first) and a cooperative-priority fixture.
3. **Phase 3.** `e.mem` static arena and `e.fmt`. Run the portable `e.*` fixtures on `native_sim` as the baseline against the desktop results.
4. **Phase 4.** Thumb-2 backend on `qemu_cortex_m3` (see `freertos.md` phases 1-2: helpers, relocations). Results come back through the console or semihosting, and the suite runs under `west build -t run`.
5. **Phase 5.** A real Cortex-M board (for example, `nrf52840dk` or `nucleo_f429zi`): `neper.hw` GPIO, I2C, SPI.
6. **Phase 6.** `e.fs` over littlefs, `e.net` over sockets on `native_sim` (uses the host's TAP or the offloaded sockets) and then on a board.
7. **Phase 7.** RISC-V (`qemu_riscv32`), then `CONFIG_USERSPACE` if wanted.

---

## 7. Risks

| Risk | Mitigation |
| :--- | :--- |
| A macro or `static inline` API assumed to be a symbol | Neper never calls a Zephyr API directly. Everything goes through the shim, which the vendor compiler builds. A CI job that links an empty Neper archive proves the plumbing. |
| Priority direction confused with FreeRTOS | One portable priority type in `e.thread`, translated in the shim only. Fixtures for both directions on both targets. |
| Pool sizes disagree with real struct sizes | `BUILD_ASSERT` in the shim on every pooled type. |
| `k_timeout_t` or other 64-bit by-value ABI mismatch | No 64-bit or struct arguments across the shim. Milliseconds as `i32` or pointers only. |
| Kconfig drift across Zephyr releases | Pin the Zephyr version in the module's `west.yml` and run the suite on each upgrade. Many symbols were renamed between 2.x, 3.x and 4.x. |
| Native `main` stack too small | `neper stack-report` feeds `CONFIG_MAIN_STACK_SIZE`, and an overflow test with stack-guard enabled. |
| Windows host cannot run the `native_sim` build | Run Phase 1-3 in WSL or a Linux CI job, and use QEMU boards on Windows. |
| `native_sim` hides embedded problems (large stacks, no MPU, host libc) | Treat it as a plumbing and logic test only. Phase 4 on QEMU Cortex-M is the first embedded gate. |
