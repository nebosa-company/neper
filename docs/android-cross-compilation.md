# Android cross-compilation

Status: deferred; Android is not currently a Neper host target.

Neper may eventually build Android artifacts on Windows or Linux without
Android Studio, the Android SDK or NDK, Gradle, Java, or an external linker.
As with the existing Windows-to-Linux path, the compiler distribution must
contain everything needed to write the target artifact. An Android device or
emulator is required for execution tests, not compilation.

Android must be a distinct target rather than an alias for Linux. It uses the
Linux kernel, but its application ABI, Bionic imports, dynamic loader,
sandbox, packaging and signing rules differ from a desktop Linux target.

Proposed target spellings are:

```text
neper build src/main.e --target x64-android
neper build src/main.e --target aarch64-android
```

`target.Os` would gain `.Android`, and target-dependent modules would use an
`android` source suffix and `lib/e/os.android.e`.

## Output forms

Two outputs serve different purposes and must not be conflated:

1. A command-line Android ELF executable is useful for shell tools, tests and
   bring-up. It needs Android-compatible position-independent ELF output,
   startup code, Bionic or raw-kernel bindings where permitted, and a location
   from which the destination device allows execution.
2. An installable application is an APK containing a native shared library.
   A native-only application can use the platform's `NativeActivity`, so it
   needs no application Java or DEX implementation. It still needs a binary
   manifest, APK packaging, native-library alignment and an APK signature.

The command-line executable is not a substitute for the APK path: Package
Manager installs applications, while a standalone ELF is a development or
device-management artifact.

## SDK-free toolchain boundary

The default Neper path owns these pieces:

- Android target and API-level selection;
- `x86_64` and AArch64 ABI lowering;
- PIE executable and shared-object ELF modes;
- dynamic imports for Bionic and the stable NDK platform libraries;
- `os.android.e` and the Android startup/lifecycle bridge;
- APK ZIP layout and binary `AndroidManifest.xml`;
- 16 KiB ELF segment and uncompressed-native-library ZIP alignment;
- APK Signature Scheme v2/v3 generation; and
- byte-level validators for ELF, manifest, ZIP alignment and signatures.

No installed SDK is needed when those facilities are built into Neper. A
release APK still needs a caller-supplied signing identity. A generated local
debug identity is sufficient for development builds but must never silently
replace a configured release key.

An explicit system-toolchain escape hatch may accept NDK objects, archives or
platform-specific inputs. That path may require an SDK/NDK installation and is
outside the no-dependency default.

## Architecture order

`x64-android` can reuse the existing x64 backend and is the shortest route to
an emulator smoke test. It is not the useful shipping milestone by itself.
Most physical devices require `aarch64-android`, which depends on the planned
AArch64 emitter, register allocation rules, relocations and ABI support.

The AArch64 backend should be shared with the macOS and Linux AArch64 targets;
Android-specific work begins at the OS ABI, runtime, ELF mode and packaging
layers rather than creating another machine-code backend.

## Validation and distribution

Host-independent checks must parse every emitted structure and compare stable
goldens on Windows and Linux. Completion additionally requires Android tests
covering:

- loading and running both supported ABIs;
- 4 KiB and 16 KiB page-size devices;
- Bionic and platform-library symbol resolution across supported API levels;
- NativeActivity lifecycle, input, assets and process shutdown;
- APK installation, upgrade under the same key and rejection under another;
  and
- release builds on physical arm64 hardware.

Google Play publication, store metadata and developer registration are
distribution concerns, not compiler prerequisites.

The normative language currently keeps Android deferred in
[`spec.md`](spec.md). This note records the intended SDK-free boundary so that
eventual implementation does not accidentally depend on the host's Android
toolchain.
