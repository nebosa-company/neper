# Architectural Blueprint: Implementing FreeBSD Support in the Neper Toolchain

This document specifies how to extend the **Neper** direct-emitting toolchain to produce native FreeBSD executables (x86-64 and AArch64) with no libc, no LLVM, and no external linker.

FreeBSD is the cheapest new OS target Neper can add. The ISA, the calling convention and the container format (ELF) already exist in the Linux backend. The work is in four places: the ELF identity, the syscall convention, a table of constants that differ from Linux, and the thread/TLS primitives. Unlike macOS and OpenBSD, FreeBSD keeps its syscall ABI stable, so statically linked binaries that issue raw syscalls are supported.

Every number below comes from memory of the FreeBSD 14 headers. Confirm each against `sys/syscall.h`, `sys/fcntl.h`, `sys/mman.h`, `sys/errno.h`, `sys/time.h` and `sys/umtx.h` of the target release before it is baked into a table.

---

## 1. Compiler Backend (no new ISA work)

| Target | Reuse | Delta |
| :--- | :--- | :--- |
| `x86_64-freebsd` | Linux x86-64 emitter, SysV calling convention, same red zone and 16-byte stack alignment | syscall stub, TLS setup |
| `aarch64-freebsd` | Linux AArch64 emitter, AAPCS64 | syscall stub, TLS setup |

*   Neper's target is an (arch, os) pair. Add `freebsd` as an os. Per the module-variant rule, `os.freebsd.e` coexists with `os.linux.e` and the os variant wins. The C bootstrap ignores variants, so FreeBSD intrinsics are added only where the bootstrap seeds them.
*   **Entry point.** The kernel enters `_start` with `rdi` pointing at the `argc` block (and `rsp` valid, as on Linux). Stack layout is `argc, argv[], NULL, envp[], NULL, auxv[]`. The existing Linux entry works unchanged if it reads from `rsp`.
*   **Stack frames.** FreeBSD needs no LE-style frame layout. Frames follow the SysV/AAPCS64 rules the Linux target already implements.

---

## 2. Binary Format: ELF with a FreeBSD Identity

The linker emits ELF64 as it does for Linux, with these differences:

| Field | Linux | FreeBSD |
| :--- | :--- | :--- |
| `e_ident[EI_OSABI]` | 0 (SYSV) | **9 (`ELFOSABI_FREEBSD`)** |
| ABI note | none | **`PT_NOTE` containing `.note.tag`**: name `"FreeBSD\0"`, type `NT_FREEBSD_ABI_TAG` (1), desc = `__FreeBSD_version` (use `1400000` as the floor) |
| Interpreter (dynamic only) | `/lib64/ld-linux-x86-64.so.2` | **`/libexec/ld-elf.so.1`** |
| System libraries | `libc.so.6`, `libdl.so.2` | **`libc.so.7`** (`dlopen` lives in libc), `libthr.so.3`, `libm.so.5` |

*   Without the OSABI byte or the note, the kernel runs the binary through the wrong compat path or refuses it.
*   Static binaries need no `PT_INTERP`. Dynamic binaries (for `@import`, see section 5) need `PT_INTERP`, `PT_DYNAMIC` and `DT_NEEDED` entries.
*   Page size is 4 KiB on x86-64 and 4 KiB on AArch64 (FreeBSD does not use 16 KiB pages by default).

---

## 3. System Interface

### 3.1 Syscall convention

| | x86-64 | AArch64 |
| :--- | :--- | :--- |
| Instruction | `syscall` | `svc #0` |
| Number | `rax` | `x8` |
| Arguments | `rdi, rsi, rdx, r10, r8, r9` | `x0 .. x7` |
| Success | `rax` = result, carry flag clear | `x0` = result, C flag clear |
| **Failure** | **carry flag set, `rax` = positive errno** | **C flag set, `x0` = positive errno** |
| Second result | `rdx` (used by `pipe`, `fork`) | `x1` |

The failure convention differs from Linux, which returns `-errno` in `rax`. The syscall stub must test the carry flag (`setc` or `jc`; `cset`/`b.cs`) and build the `(T, err)` pair from it. Reusing the Linux "value in [-4095,-1]" check will silently report success on every failing call, which is the same class of bug as the narrow-extern-return miss.

### 3.2 Syscall numbers needed by the e.* surface

| Call | No. | Call | No. |
| :--- | :--- | :--- | :--- |
| `exit` | 1 | `thr_exit` | 431 |
| `fork` | 2 | `_umtx_op` | 454 |
| `read` | 3 | `thr_new` | 455 |
| `write` | 4 | `pread` / `pwrite` | 475 / 476 |
| `open` / `close` | 5 / 6 | **`mmap`** | **477** |
| `wait4` | 7 | `lseek` | 478 |
| `munmap` / `mprotect` | 73 / 74 | `ftruncate` | 480 |
| `sysctl` | 202 | `openat` | 499 |
| `clock_gettime` | 232 | `pipe2` | 542 |
| `nanosleep` | 240 | `fstat` / `fstatat` | 551 / 552 |
| `kqueue` | 362 | `getdirentries` | 554 |
| `sigaction` | 416 | `kevent` | 560 |
| `execve` | 59 | `getrandom` | 563 |
| `sysarch` | 165 | `cap_enter` | 516 |

### 3.3 Constants that differ from Linux

These are the traps. Each one compiles and then misbehaves.

| Item | Linux | FreeBSD |
| :--- | :--- | :--- |
| `errno` 1-34 | | identical |
| `EAGAIN`, `EINPROGRESS`, `ENOTSUP`, `ETIMEDOUT`, `ECONNREFUSED`, `ENOTEMPTY`, `ENOSYS` | 11, 115, 95, 110, 111, 39, 38 | **35, 36, 45, 60, 61, 66, 78** |
| `CLOCK_MONOTONIC` | 1 | **4** (`CLOCK_REALTIME` is 0 on both) |
| `O_CREAT` / `O_TRUNC` / `O_EXCL` | 0x40 / 0x200 / 0x80 | **0x200 / 0x400 / 0x800** |
| `O_APPEND` / `O_NONBLOCK` | 0x400 / 0x800 | **0x8 / 0x4** |
| `O_CLOEXEC` / `O_DIRECTORY` | 0x80000 / 0x10000 | **0x100000 / 0x20000** |
| `MAP_ANON` / `MAP_FIXED` | 0x20 / 0x10 | **0x1000** / 0x10 |
| `struct stat` | Linux layout | 224-byte ino64 layout (FreeBSD 12+) |
| `sigaction` | needs `SA_RESTORER` on x86-64 | no restorer; the kernel supplies the trampoline |

Translate errno through one table at the syscall boundary so `e.os` surfaces portable error kinds and never raw numbers.

---

## 4. Standard Library Porting Strategy

| Module | Work |
| :--- | :--- |
| `e.os` | New `os.freebsd.e` variant: syscall stub with carry-flag errors, errno table, `sysctl` for facts that Linux reads from `/proc` (executable path is `CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, -1`; CPU count is `hw.ncpu`). FreeBSD has no `/proc` by default. |
| `e.mem` | `mmap`/`munmap` with FreeBSD flag values. `MAP_GUARD` and `MAP_NORESERVE` map straight onto arena reservation semantics. Keep the halved-reservation and give-back-on-reset behavior. |
| `e.io`, `e.fs` | Flag table, `getdirentries` record walk (`struct dirent` carries a 64-bit `d_fileno`, `d_off`, `d_reclen`), ino64 stat layout. |
| `e.time` | `clock_gettime` with ID 4 for monotonic. The calendar code is OS-independent. |
| `e.thread` | `thr_new` with a `struct thr_param` (start function, arg, stack base/size, `tls_base`, `child_tid`, `parent_tid`). Join and mutex wait use `_umtx_op`: `UMTX_OP_WAIT_UINT_PRIVATE` (15) and `UMTX_OP_WAKE_PRIVATE` (16). This replaces the Linux `clone(2)` + futex pair and is simpler, because the kernel allocates the thread and sets TLS. |
| `e.proc` | `pipe2`, `fork` + `execve`, `wait4`. Two pipes still need two threads. |
| `e.net`, async | `kqueue`/`kevent` replaces epoll. Same readiness model, different struct (`struct kevent`, 64 bytes). |
| `e.sync`, `e.test`, `e.data.*`, `e.fmt.*`, `e.math`, `e.simd` | None. Portable source. |

**TLS.** Static x86-64: `sysarch(AMD64_SET_FSBASE, &base)` (number 129). AArch64: write `TPIDR_EL0` directly. Threads created by `thr_new` receive `tls_base` from the parameter block.

---

## 5. Dynamic Linking, GPU and UI

*   `@import` already binds through a loader-filled indirect slot. On FreeBSD the dynamic section needs `DT_NEEDED`, `DT_SYMTAB`/`DT_STRTAB`/`DT_HASH` (or `DT_GNU_HASH`) and `DT_RELA` with `JUMP_SLOT`/`GLOB_DAT`, the same machinery as Linux but with the FreeBSD interpreter path and library names.
*   `dlopen` is in `libc.so.7`, so the optional-library path used for OpenSSL and database drivers works without a separate `libdl`.
*   GPU: `x.khronos.*` reaches Mesa through `libGL`/`libEGL`/`libvulkan` from packages. `--gpu glsl` already covers the shader side. Mesa and the GPU driver (`drm-kmod`) are packages, so CI cannot assume a GPU.
*   UI: X11 (xcb) is the first window path. Wayland follows the Linux `e.ui` work and needs no FreeBSD-specific code beyond the socket path.

---

## 6. Optional: Capsicum

`cap_enter()` (syscall 516) puts the process in capability mode, where only already-open descriptors are usable. It maps well onto the `(T, err)` model: a sandboxed Neper program opens its inputs, calls `cap_enter`, then every later `open` fails with `ECAPMODE` as an ordinary `err`. Defer until the base target passes its suites.

---

## 7. Verification and Phasing

1. **Phase 1.** `x86_64-freebsd` static hello: ELF identity, note, `write`, `exit`. Verify under a FreeBSD 14.x QEMU image (`qcow2`) or `cross-platform-actions/action` on GitHub Actions.
2. **Phase 2.** `e.mem`, `e.io`, `e.fs`, `e.time` with the constant tables above. Run the existing fixtures for those modules on both Linux and FreeBSD.
3. **Phase 3.** `e.thread`, `e.proc`, kqueue.
4. **Phase 4.** `aarch64-freebsd` (QEMU `virt` with a FreeBSD arm64 image).
5. **Phase 5.** Dynamic linking, GPU, UI.

A passing build on the cross-linker is not proof. The first useful gate is one fixture per differing constant (`CLOCK_MONOTONIC`, `O_CREAT|O_EXCL`, `EAGAIN`) that fails if the Linux value is used.

---

## 8. Risks

| Risk | Mitigation |
| :--- | :--- |
| Carry-flag errors read as success | A fixture that forces `ENOENT` on `open` and checks the `err` kind. |
| Raw syscalls break on a future release | The ABI is stable, but each release can add compat shims. Pin the ABI-tag version and re-run suites per release. |
| Linux numbers copied by habit | One generated table per OS, produced from the target headers, never hand-typed. |
| No FreeBSD hardware in the suite loop | Run the FreeBSD suite in a VM, one sequential job, never beside the other suites. |
