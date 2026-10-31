# Architectural Blueprint: Implementing FreeRTOS Support in the Neper Toolchain

This document specifies how to extend the **Neper** direct-emitting toolchain to produce firmware for microcontrollers running FreeRTOS, starting with ARM Cortex-M and then RISC-V (RV32).

FreeRTOS is a kernel library linked into the firmware, not an operating system that loads programs. There is no process, no loader, no filesystem unless one is added, and usually no MMU. Unlike the Linux, FreeBSD and Android targets, this one needs a **new ISA backend** (Thumb-2), a **relocatable-object output** (or a bare-metal linker), and a standard-library surface that is deliberately smaller. `zephyr.md` reuses sections 1, 2 and 4 of this document and describes only its own differences.

Every number below comes from memory of the ARM EABI documents and the FreeRTOS headers. Confirm each against the ARM ELF/EABI specs and the `FreeRTOS.h`, `task.h`, `queue.h` and `portmacro.h` of the release in use before it goes into a table.

---

## 1. Compiler Backend: Thumb-2 (new)

Cortex-M cores execute only the Thumb instruction set. The backend emits 16-bit and 32-bit Thumb-2 encodings, never ARM state.

| Target name | Core examples | Architecture | Notes |
| :--- | :--- | :--- | :--- |
| `thumbv6m` | M0, M0+ | ARMv6-M | Subset: few 32-bit encodings, no `SDIV`/`UDIV`, no `LDREX`, no `cbz` backward. Literal pools instead of `movw`/`movt`. |
| `thumbv7m` | M3 | ARMv7-M | Full Thumb-2, hardware divide, `LDREX`/`STREX`. **First target** (QEMU supports it). |
| `thumbv7em` | M4, M7 | ARMv7E-M | Adds DSP and optional FPU (single precision on M4F, double on some M7). |
| `thumbv8m.main` | M33, M55 | ARMv8-M | TrustZone, `BXNS`/`BLXNS`. Out of scope for the first milestone. |

Calling convention (AAPCS32):

*   `r0`-`r3` carry arguments and results. A 64-bit argument or result occupies an **even-aligned register pair** (`r0:r1`, `r2:r3`), and skips a register if needed.
*   `r4`-`r11` are callee-saved. `r12` is scratch. `r13` is `sp`, `r14` is `lr`, `r15` is `pc`.
*   The stack is 8-byte aligned at every public call boundary.
*   Pick the **soft-float calling convention** first (floats in integer registers). It links with every vendor library regardless of FPU, and the `softfp` variant (hardware FPU, soft ABI) is the usual FreeRTOS configuration. The hard-float ABI (`s0`-`s15`) is a later option.

Traps that do not exist on x86-64 and AArch64:

*   **The Thumb bit.** Every function address stored as data (vector table, function pointers, task entry) has bit 0 set. A branch to an even address is a hard fault.
*   **Branch range.** `B.cond` (T3) reaches ±1 MiB, `B`/`BL` reach ±16 MiB, and the 16-bit forms reach ±256 B and ±2 KiB. The emitter needs branch relaxation or veneers once a function or a link exceeds those ranges.
*   **Literal pools.** Constants that do not fit an immediate go to a pool within 1 KiB of the `ldr` on `thumbv6m`. On `thumbv7m` use `movw`/`movt`.
*   **No 64-bit divide, no `memcpy`.** Neither the CPU nor a libc supplies them. Neper must emit its own `__aeabi_uldivmod`, `__aeabi_ldivmod`, `__aeabi_uidiv` (on `thumbv6m`), `memcpy`, `memmove`, `memset` and `memcmp`, as compiler-runtime functions the linker pulls in only when referenced. Soft-float needs `__aeabi_fadd` and friends where there is no FPU (or `e.math` supplies its own).
*   **Atomics.** `thumbv7m` and later use `LDREX`/`STREX`. `thumbv6m` has none, so atomics become a critical section (`cpsid i` ... restore `PRIMASK`). 64-bit atomics always use the critical section.
*   **Interrupt handlers are ordinary functions.** The hardware stacks `r0-r3, r12, lr, pc, xPSR` on exception entry and loads `lr` with `EXC_RETURN`, so a handler written in Neper follows the normal calling convention. It needs only an attribute that places its address (with the Thumb bit) in the vector table, and the emitter must not assume `lr` is a plain return address in an ISR that makes calls.

---

## 2. Binary Format: Where the Output Goes

Two output modes, built in this order.

### 2.1 Mode A (first): ELF relocatable object for the vendor linker

Neper emits one `ET_REL` ELF file (or an `ar` archive of them) containing the application. The vendor toolchain's linker (`arm-none-eabi-ld`, or the IDE's) combines it with the FreeRTOS kernel, the vendor startup file, and the HAL. The vendor files keep owning the vector table, `Reset_Handler`, the linker script and the clock setup. Neper provides `main`.

| Item | Requirement |
| :--- | :--- |
| `e_machine` | `EM_ARM` (40) for Cortex-M, `EM_RISCV` (243) for RISC-V |
| `e_flags` (ARM) | `EF_ARM_EABI_VER5` (`0x05000000`), plus `EF_ARM_ABI_FLOAT_SOFT` (`0x200`) or `EF_ARM_ABI_FLOAT_HARD` (`0x400`) |
| Sections | `.text`, `.rodata`, `.data`, `.bss`, optionally one section per function and per datum (`-ffunction-sections` equivalent) so the vendor linker can discard dead code |
| `.ARM.attributes` | Build attributes (CPU architecture, Thumb-2 support, VFP argument convention). Without them the vendor linker may warn about or reject mixed ABI. |
| Relocations (ARM) | `R_ARM_THM_CALL` (10), `R_ARM_THM_JUMP24` (30), `R_ARM_THM_JUMP19` (51), `R_ARM_THM_JUMP11` (102), `R_ARM_ABS32` (2), `R_ARM_REL32` (3), `R_ARM_THM_MOVW_ABS_NC` (47), `R_ARM_THM_MOVT_ABS` (48), and `R_ARM_TARGET1` (38) for data pointers |
| Debug | DWARF, as for the existing ELF targets |

Mode A has a hard dependency on the Neper pipeline being able to write relocatable objects. The existing link-em machinery produces final images, so confirm what it can already emit before sizing this work.

### 2.2 Mode B (later): standalone image from Neper's own linker

Neper writes the final ELF and the flashable files, with no vendor linker involved. It then also owns:

*   **A memory map** as an input file (regions `FLASH` and `RAM` with origin and size, optional `CCM`/`DTCM`), since there is no linker-script language. Overflow of any region is a link error with the region name and the byte count.
*   **The vector table**: word 0 is the initial `sp`, word 1 is the reset handler with the Thumb bit set, and the following words are the system exceptions and IRQs. It is aligned to the size of the table rounded up to a power of two (`SCB->VTOR`).
*   **Startup**: copy `.data` from its load address in flash to RAM, zero `.bss`, run `SystemInit`/clock setup, then call `main`. Clock and peripheral setup is per-chip, so Mode B means a small per-chip package (or a vendor-supplied startup object).
*   **Outputs**: `.elf`, raw `.bin` (flash image), Intel `.hex`, and UF2 where the board's bootloader uses it.
*   Flashing and debugging stay with OpenOCD, probe-rs or J-Link.

---

## 3. The Kernel Bridge: a C shim built by the vendor toolchain

Neper has no C compiler, and FreeRTOS's public API is mostly **macros**, not symbols. A call such as `xSemaphoreTake` has no symbol to link against, and structure sizes depend on `FreeRTOSConfig.h`.

| Macro the C code writes | What Neper would need to call or emit |
| :--- | :--- |
| `xSemaphoreTake(s, t)` | `xQueueSemaphoreTake(s, t)` |
| `xSemaphoreGive(s)` | `xQueueGenericSend(s, NULL, 0, queueSEND_TO_BACK)` |
| `xQueueSend(q, p, t)` | `xQueueGenericSend(q, p, t, queueSEND_TO_BACK)` |
| `taskENTER_CRITICAL()` | `vPortEnterCritical()` |
| `portYIELD_FROM_ISR(x)` | write `0x10000000` (`PENDSVSET`) to `0xE000ED04` when `x` is true |
| `pdMS_TO_TICKS(ms)` | `ms * configTICK_RATE_HZ / 1000` (use a 64-bit intermediate) |
| `StaticTask_t`, `StaticQueue_t` | size and alignment depend on the configuration |

**Decision: ship a thin C shim, `neper_freertos.c`, compiled by the user's own toolchain against their own `FreeRTOSConfig.h`.** It exports plain functions with a fixed, ABI-simple signature (integers and pointers only, milliseconds instead of ticks):

*   `nrt_task_create(entry, arg, prio, stack_slot)`, `nrt_task_delete`, `nrt_delay_ms`, `nrt_now_ms`
*   `nrt_mutex_*`, `nrt_sem_*`, `nrt_queue_*`, `nrt_event_*`, `nrt_notify_*`, `nrt_timer_*`
*   `nrt_in_isr()` (reads `IPSR`), plus `*_from_isr` variants
*   `nrt_write(buf, len)` for output
*   the idle-task and timer-task memory callbacks that static allocation requires (`vApplicationGetIdleTaskMemory`, `vApplicationGetTimerTaskMemory`)

All kernel objects (the `Static*_t` control blocks, task stacks, queue storage) live in the shim as fixed pools sized by build constants. Neper holds only integer handles. This removes the struct-size problem and keeps every FreeRTOS macro on the C side. An unknown or exhausted slot returns an `err` (out of memory), never a crash.

A native port of the kernel into Neper (tasks, scheduler, context switch) is rejected: it would be a large, high-risk rewrite that vendor ports, certification and every board support package already cover.

---

## 4. Standard Library Porting Strategy

The target is **freestanding with a kernel**: `surface: "partial"`, and every module that cannot exist returns a normal `err` (kind `Unsupported`), never a link failure.

| Module | Behavior on FreeRTOS |
| :--- | :--- |
| `e.mem` | **No virtual memory.** Arenas are fixed-size static arrays in `.bss` or `.noinit`, with commit equal to reserve. The "reserve address space, give back on reset" model does not apply, and `--arena` is in KB. Heap functions (`pvPortMalloc`) are not used. Build with `configSUPPORT_STATIC_ALLOCATION=1`. |
| `e.thread` | Tasks, from the shim's stack pool. A task's stack depth is given in **words**, not bytes (`StackType_t`, 4 bytes on Cortex-M) in FreeRTOS calls, so the shim takes bytes and converts. Priority runs the opposite way to Zephyr: **a higher number is a higher priority**, and 0 is idle. |
| `e.sync` | Mutex, semaphore, queue, event group, task notification. Calls from an interrupt must use the `FromISR` forms, so the module checks `nrt_in_isr()` and either chooses the right form or returns `err`. |
| `e.time` | `nrt_now_ms` extends the 32-bit tick count to a monotonic `i64` (count overflows in the tick hook, since `xTaskGetTickCount` wraps at about 49 days at 1 kHz). **No wall clock.** Calendar functions work on a value the application supplies. |
| `e.io` | `io.print` goes through `nrt_write`: UART, semihosting, ITM/SWO or SEGGER RTT, chosen at build time. There are no `stdout` and no `stdin`. |
| `e.fs`, `e.path` (filesystem), `e.proc`, `e.os.dyn`, `@import` dynamic | Return `Unsupported`. A FAT or littlefs layer may be wired later. `e.path` string operations still work. |
| `e.fmt.*`, `e.data.*`, `e.bytes`, `e.str`, `e.test`, `e.simd` | Portable, with one cost: code size. |
| `e.math` | Works with no FPU (slow), single-precision on M4F, `f64` always in software on M0-M4. |
| `e.fmt` / `e.str` float text | The shortest-round-trip and parsing tables (the Ryu and Eisel-Lemire work) add roughly tens of KB of flash. Gate them behind a build option so small parts can drop float formatting. |
| `e.net` | `Unsupported` until a TCP/IP stack (FreeRTOS+TCP, lwIP) is chosen and bridged through the shim. |

**Code size and stack are the constraints that matter.**

*   `e.fmt` synthesizes one function per call shape, so a program with many format calls grows quickly. Add `neper size` (per-function and per-module bytes, with region totals), and keep dead-function elimination on, since only reachable functions should be emitted.
*   Task stacks are small (often 512 to 2048 words). Neper values and arenas on the stack can overflow them. Add `neper stack-report`, a static worst-case stack-depth report from the call graph, and ban or flag recursion in tasks. Set `configCHECK_FOR_STACK_OVERFLOW` in debug builds.

**Error bridge.** FreeRTOS calls return `BaseType_t`: `pdPASS` (1), `pdFAIL` (0), `errQUEUE_FULL` (0), `errQUEUE_EMPTY` (0), and a timeout is just `pdFALSE`. The shim converts these to negative codes (`-timeout`, `-full`, `-empty`), and the Neper wrapper turns them into `err`, so `try q.send(x)` works. The shim never reports "ok" for an unknown failure.

---

## 5. Interrupts and Priorities

*   NVIC priority registers use only the top `__NVIC_PRIO_BITS` bits of each byte. The value written is `prio << (8 - __NVIC_PRIO_BITS)`. Interrupts that call the kernel (`FromISR`) must be at or below `configMAX_SYSCALL_INTERRUPT_PRIORITY`, or the kernel's critical sections do not protect them.
*   The port needs the three handlers `vPortSVCHandler`, `xPortPendSVHandler` and `xPortSysTickHandler` in the vector table (often through `#define` aliases to `SVC_Handler`, `PendSV_Handler`, `SysTick_Handler`). In Mode A the vendor startup file already provides them. In Mode B Neper's table must name them, per `FreeRTOSConfig.h`.
*   An `@isr` attribute (or an `isr` decorator on a function) places a handler into the vector slot named by its IRQ and checks that it is not called from task code.

---

## 6. Second Architecture: RISC-V (RV32)

*   Targets `riscv32imac` with the `ilp32` ABI first. Relocations are `R_RISCV_*` (`CALL_PLT`, `PCREL_HI20`/`PCREL_LO12_I`, `HI20`/`LO12_I`) and linker relaxation (`R_RISCV_RELAX`) should be left to the vendor linker in Mode A.
*   The FreeRTOS RISC-V port needs machine-timer registers (`mtime`, `mtimecmp`) and the trap vector. Both come from the vendor startup in Mode A.
*   Espressif parts (ESP-IDF) use a modified, SMP-aware FreeRTOS and their own image format and bootloader. They are out of scope.

---

## 7. Verification and Phasing

1. **Phase 1.** `thumbv7m` object with a `main` that prints through semihosting and exits. Run under **QEMU** (`lm3s6965evb` or `mps2-an385`, with `-semihosting`) linked with the FreeRTOS `ARM_CM3` port. Test result is the process exit code, passed through the semihosting `SYS_EXIT` call (`bkpt 0xAB`).
2. **Phase 2.** The runtime helpers (`__aeabi_*`, `memcpy`) with a fixture per helper against known-answer vectors, including 64-bit division edge cases.
3. **Phase 3.** The C shim, and `e.thread`, `e.sync`, `e.time` fixtures in QEMU. Check priority inversion handling and tick wrap.
4. **Phase 4.** `e.mem` static arenas, `neper size`, `neper stack-report`.
5. **Phase 5.** `thumbv7em` with FPU on a real board (`mps2-an386` in QEMU first), `thumbv6m`.
6. **Phase 6.** Mode B standalone image with a memory map.
7. **Phase 7.** RV32.

Fixtures are one binary per module, since a QEMU run needs no OS, boots in milliseconds, and the whole suite can run on the Windows host without WSL.

---

## 8. Risks

| Risk | Mitigation |
| :--- | :--- |
| Function address without the Thumb bit | Single point in the emitter that makes every code address odd. A fixture calls a function through a pointer. |
| Branch out of range in a large image | Branch relaxation with a test image over 1 MiB of `.text` (synthesized). |
| Stack overflow in a task | `stack-report` as a build gate, plus overflow checking enabled in tests. |
| Wrong `FreeRTOSConfig.h` assumptions in the shim | Shim compiled by the user's toolchain against their header, with `_Static_assert`s on the pool sizes. |
| Soft-float or divide helper wrong at an edge | Known-answer vectors from a reference (Python and the vendor `libgcc`) for each helper. |
| ISR calls a non-ISR kernel function | `nrt_in_isr()` check in every `e.sync` entry, and a QEMU fixture that triggers it from SysTick. |
| Flash overflow discovered late | Region overflow is a hard link error in Mode B, and `neper size` is run on every build in Mode A. |
| Relocatable output is not yet supported by Neper's linker | Resolve first: it blocks Mode A entirely. |
