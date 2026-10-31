# Architectural Blueprint: Implementing Android Support in the Neper Toolchain

This document specifies how to extend the **Neper** direct-emitting toolchain to produce native Android software: command-line executables for `adb shell`, and installable APKs that need no Java compiler and no Gradle.

Android is a Linux kernel under the Bionic libc and a platform runtime. The ISA work already exists (AArch64, x86-64). The new work is the packaging (APK, binary manifest, signing), the rules Android adds to ELF, and the lifecycle of a native activity. Two deliverables, in this order:

1. **Executable track.** A Bionic-linked ELF run from `/data/local/tmp` over `adb`. Validates the backend and `e.*` with no packaging.
2. **APK track.** A `NativeActivity` APK built entirely by Neper.

Verify every constant against the NDK headers and the AOSP docs for the target API level before it is baked into a table.

---

## 1. Compiler Backend

| Target | Use | Notes |
| :--- | :--- | :--- |
| `aarch64-android` | Phones, tablets | Primary. 64-bit only is the practical floor (Google Play requires 64-bit). |
| `x86_64-android` | Emulator, ChromeOS | Reuses the Linux x86-64 emitter. |

Rules that differ from desktop Linux:

*   **`x18` is reserved** on Android AArch64 (shadow call stack and the platform register). The register allocator must never use it, in prologues or anywhere else. Linux AArch64 code that uses `x18` as a scratch register crashes here, and the failure appears far from its cause.
*   **BTI and PAC.** Emit `bti c` at function entries reachable indirectly and mark the binary with a `PT_GNU_PROPERTY` note (`GNU_PROPERTY_AARCH64_FEATURE_1_BTI`) so devices that enforce BTI accept it. Pointer authentication on returns is optional; add `paciasp`/`autiasp` once the base works.
*   **No text relocations.** Since target API 23 the dynamic linker rejects `DT_TEXTREL`. Emit position-independent code with `R_AARCH64_RELATIVE` entries in `DT_RELA`.
*   **Page size.** Align every `PT_LOAD` to **16 KiB** (`p_align = 0x4000`). Google Play requires 16 KiB-compatible native code for apps targeting Android 15 and later, and devices with 16 KiB pages refuse to load 4 KiB-aligned segments.

---

## 2. Binary Format: ELF for Bionic

*   `PT_INTERP` is `/system/bin/linker64` (`/system/bin/linker` for 32-bit, which is out of scope).
*   Shared objects need `DT_SONAME`, `DT_GNU_HASH` or `DT_HASH`, and exported dynamic symbols. For a `NativeActivity`, the export is `ANativeActivity_onCreate`.
*   Libraries come from the platform, not from Neper. Executables link by name against `libc.so`, `libdl.so`, `liblog.so`, `libandroid.so`, `libEGL.so`, `libGLESv3.so` and `libvulkan.so`.
*   **Linker namespaces.** An app may only `dlopen` libraries on the public NDK list. Private platform libraries (`libcutils`, `libbinder` and similar) fail to load. This also rules out reaching the Java VM by private symbols.

---

## 3. System Interface

*   **Raw syscalls work but are filtered.** App processes run under a seccomp-BPF allowlist (stricter than the shell's). The common set (`read`, `write`, `openat`, `mmap`, `futex`, `clone`) is allowed, and blocked calls kill the process with `SIGSYS`. Rule: use libc imports for anything beyond the memory, file and time basics, and keep raw syscalls to a documented list.
*   The Linux AArch64 syscall table applies unchanged (number in `x8`, `svc #0`, `-errno` in `x0`). The existing `os.linux.e` syscall layer is the starting point for the executable track.
*   **Threads.** Bionic owns `TPIDR_EL0` and a fixed TLS slot layout (for example, the stack-protector canary and the sanitizer slots). Neper's own `clone(2)` threads that overwrite `TPIDR_EL0` corrupt Bionic. On Android, `e.thread` calls `pthread_create` and `pthread_join` through `@import`.
*   **Logging.** `stdout`/`stderr` do not reach `logcat` in an app. `io.print` becomes `__android_log_write(prio, tag, msg)` from `liblog.so`.
*   **SELinux and exec.** Targeting API 29 and later, an app cannot `execve` a file from its own data directory. `e.proc` is available to the shell track only. Apps spawn nothing from writable storage.

---

## 4. Standard Library Porting

| Module | Work |
| :--- | :--- |
| `e.mem` | `mmap`/`munmap` as on Linux. Low-memory kills are by process, not by allocation failure, so arenas must be small enough that the lifecycle callbacks (below) can release them. |
| `e.io`, `e.fs` | App-private storage is `ANativeActivity.internalDataPath` and `externalDataPath`. Outside it, scoped storage and permissions apply. A portable `/tmp` does not exist. |
| `e.asset` | Read bundled assets with `AAssetManager_open` from `libandroid.so`. APK assets are not files. |
| `e.thread` | `pthread` through import (section 3). |
| `e.time`, `e.data.*`, `e.fmt.*`, `e.math`, `e.simd` | None. |
| `e.gpu` / `--gpu` | Vulkan through `libvulkan.so`, or GLES 3 through EGL. The GLSL backend needs a `#version 300 es` dialect with precision qualifiers. `ANativeWindow` is the surface. |
| `e.ui` | The window system presents into an `ANativeWindow`. Touch arrives as `AInputEvent` (multi-touch with pointer IDs). The soft keyboard and clipboard have no NDK API. They need JNI (section 6). |

---

## 5. Packaging: The Neper APK Pipeline (`neper apk`)

An APK is a ZIP. `NativeActivity` is a framework class, so the manifest can declare `android:hasCode="false"` and the APK contains no `classes.dex`. That removes the need for a Java or Kotlin toolchain.

| Step | Output | Spec |
| :--- | :--- | :--- |
| 1. Compile | `lib/arm64-v8a/libapp.so` (and `lib/x86_64/`) | ELF from section 2 |
| 2. Manifest | `AndroidManifest.xml` in **binary XML (AXML)** | Chunks: string pool `0x0001`, resource map `0x0180`, start/end namespace `0x0100`/`0x0101`, start/end element `0x0102`/`0x0103`. Attributes reference framework resource IDs (`android:name` is `0x01010003`). |
| 3. Manifest contents | `package`, `uses-sdk` (`minSdkVersion` 26 or later, `targetSdkVersion` current), `<application android:hasCode="false" android:extractNativeLibs="false">`, `<activity android:name="android.app.NativeActivity">` with `<meta-data android:name="android.app.lib_name" android:value="app"/>` and a `MAIN`/`LAUNCHER` intent filter | |
| 4. Resources | `resources.arsc` is optional. Omit it for a first build (default icon). | |
| 5. ZIP | Native libs **stored (uncompressed) and 16 KiB-aligned** so the linker maps them straight from the APK (`extractNativeLibs=false`) | zipalign rule |
| 6. Sign | **APK Signature Scheme v2** (signing-block ID `0x7109871a`) inserted before the central directory; v3 (`0xf05368c0`) for key rotation | SHA-256 over 1 MiB chunks, then RSA-2048 or ECDSA P-256 |
| 7. Install | `adb install app.apk` | |

*   The signature covers the ZIP's section hashes, so the order is fixed: write entries, align, build the central directory, compute the digests, insert the block, then fix up the end-of-central-directory offset.
*   A debug keystore is generated on first use. Release signing keys are the user's and never enter a repository.
*   Signing needs SHA-256 and one asymmetric scheme. Reuse `e.crypto` if it carries ECDSA P-256. Otherwise use OpenSSL through the existing optional `dlopen` path.
*   Google Play also requires an Android App Bundle (`.aab`), not an APK. `.aab` is a protobuf-manifest ZIP and is out of scope for the first milestone.

---

## 6. Lifecycle and JNI

*   **Lifecycle.** `ANativeActivity` delivers callbacks on the Java main thread. The usual structure runs Neper's frame loop on its own thread and uses `ALooper` plus `AInputQueue` for events.
*   **Surface loss.** `onNativeWindowDestroyed` fires whenever the app is backgrounded. GPU resources tied to the surface must be rebuilt on `onNativeWindowCreated`. Arena state survives, GPU state does not.
*   `onSaveInstanceState` and `onLowMemory`/`onTrimMemory` are the hooks that call the arena give-back path.
*   **JNI by table slot.** `ANativeActivity` hands the code a `JavaVM*` and a `jobject`. Calling Java (soft keyboard, clipboard, accessibility, file picker) means calling through the `JNIEnv` function table by slot index. This is the same technique already used for COM vtables, and no new compiler capability is needed. The unsolved cost is accessibility: the Android bridge needs an `AccessibilityNodeProvider` subclass, which is Java. Defer it, and record the gap in the accessibility audit.

---

## 7. Verification and Phasing

1. **Phase 1.** Executable track: `aarch64-android` hello pushed to `/data/local/tmp`, run through `adb shell`. Check `x18` avoidance with a function that uses many registers.
2. **Phase 2.** `e.mem`, `e.io`, `e.fs`, `e.time` fixtures through the shell track. Fixtures run on the Android Emulator (x86-64 image) or a device.
3. **Phase 3.** AXML encoder, ZIP writer, v2 signer. First proof is that `adb install` accepts the APK (`apksigner verify` agrees).
4. **Phase 4.** `NativeActivity` hello with `__android_log_write`. Then an `ANativeWindow` clear with GLES.
5. **Phase 5.** Vulkan, touch, JNI keyboard, asset loading, lifecycle tests (rotate, background, restore).
6. **Phase 6.** 16 KiB device or emulator image check, BTI check, `.aab`.

---

## 8. Risks

| Risk | Mitigation |
| :--- | :--- |
| `x18` used by the allocator | Remove it from the register pool for the whole Android target, and add a test that fails if it appears in emitted code. |
| `SIGSYS` from seccomp on a raw syscall | Keep a short allowlist table. Everything else goes through libc. |
| Own TLS setup corrupts Bionic | Never write `TPIDR_EL0` on Android. Use `pthread`. |
| 4 KiB segment alignment | One check in the linker that rejects Android output whose `p_align` is below 0x4000. |
| APK v2 signature off by one byte | `apksigner verify --verbose` in the build, run on every artifact. |
| Surface destroyed mid-frame | Lifecycle test that backgrounds the app during rendering. |
| No emulator on the CI host | Android Emulator needs hardware virtualization. Run the device suite on a machine that has it, sequentially. |
