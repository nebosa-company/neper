# Android cross-compilation

Status: implemented for `x64-android` and `aarch64-android` output (D5896–D5911).
The compiler emits Android ELF programs and shared libraries, and
[`scripts/build-apk.ps1`](../scripts/build-apk.ps1) packages a NativeActivity APK.

Android is a distinct output ABI rather than a Linux executable: it uses the Linux
kernel, but its Bionic imports, dynamic loader, sandbox, packaging and signing rules
differ from a desktop Linux target. Source selection intentionally remains Linux:
`target.os == .Linux`, `e.os` selects its Linux variant, and `.linux.e` variants
apply. There is no `.Android` member of `target.Os`, `.android.e` source selection,
or `os.android.e`.

The target spellings are:

```text
neper build src/main.e --target x64-android
neper build src/main.e --target aarch64-android
```

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

## Current packaging boundary

The compiler owns Android code generation, Bionic-targeted ELF output and shared
library exports. `scripts/build-apk.ps1` builds `x86_64` and `arm64-v8a` libraries,
writes the NativeActivity manifest, links and aligns the APK, and signs it. It
currently uses configured Android SDK build tools and Java for `aapt2`, `zipalign`
and `apksigner`; an Android device or emulator is required for execution tests, not
compilation.

A release APK still needs a caller-supplied signing identity. A generated local debug
identity is sufficient for development builds but must never silently replace a
configured release key.

## Architecture order

Both `x64-android` and `aarch64-android` are implemented. The x64 form is the
emulator route; the AArch64 form shares its emitter and ABI work with macOS and Linux
and is the physical-device route.

Android-specific work remains at the OS ABI, runtime, ELF mode and packaging layers
rather than creating another machine-code backend.

## Validation and distribution

Host-independent checks parse emitted structures and compare stable goldens. The
matrix exercises both output ABIs and the NativeActivity lifecycle on an emulator;
remaining validation includes:

- 4 KiB and 16 KiB page-size devices;
- Bionic and platform-library symbol resolution across supported API levels;
- APK installation, upgrade under the same key and rejection under another;
  and
- release builds on physical arm64 hardware.

Google Play publication, store metadata and developer registration are
distribution concerns, not compiler prerequisites.

The normative language models Android as an output ABI with Linux source selection;
it is not a deferred `target.Os` member. This note records the current packaging
boundary and remaining validation work.
