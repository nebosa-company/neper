# macOS cross-compilation

Status: `aarch64-macos` emits a static, ad-hoc-signed Mach-O over raw BSD system calls (D5165) for programs that need no import or file open; not yet run on a Mac. `x64-macos`, `libSystem` imports and `os.macos.e` are planned.

Neper must be able to build a macOS executable on Windows or Linux. The build
host does not determine the output format: `--target` selects the source
variants, ABI, machine-code backend, runtime and executable writer.

```text
neper build src/main.e --target x64-macos
neper build src/main.e --target aarch64-macos
```

This is the same model already used when the Windows compiler writes a Linux
ELF executable. Cross-compiling must not require macOS, Xcode, the macOS SDK or
Apple's linker. Neper's own linker writes the complete Mach-O image.

## Required target support

The macOS path needs:

- a Mach-O executable writer with load commands, segments, symbols, dynamic
  imports, chained fixups, DWARF and `.nepersym`;
- startup and intrinsic runtimes for each supported architecture;
- `lib/e/os.macos.e`, implemented through `libSystem` rather than unstable raw
  Apple system-call numbers;
- ad-hoc `LC_CODE_SIGNATURE` generation for Apple Silicon executables;
- target dispatch that selects Mach-O instead of treating every non-Windows
  target as ELF; and
- cross-target fixtures whose bytes can be inspected on every host, followed
  by execution tests on macOS CI.

The existing System V x64 calling-convention work is reusable for
`x64-macos`. `aarch64-macos` additionally requires the AArch64 emitter,
register allocation rules, relocations and Apple AArch64 ABI support.

## Linking without a macOS SDK

Unlike the import-free Linux runtime, every macOS executable reaches host
services through `libSystem`. The own linker records the library install name
and undefined symbols for `dyld` to resolve on the destination Mac; it does not
need to open the target library while compiling.

The system-linker escape hatch may still require a macOS SDK for static
archives or platform-specific inputs. That does not apply to the default own
linker and is not part of basic cross-compilation.

## Validation and distribution

macOS is unnecessary while producing the executable, but a real Mac or macOS
CI is required to prove that the image loads, binds and runs. Format parsers and
byte-exact golden tests on Windows are necessary but cannot replace that smoke
test.

Ad-hoc signing makes an Apple Silicon executable runnable. Developer ID
signing, notarization and application bundles are separate distribution steps;
they are not required to emit a command-line executable.

## Delivery slices

1. `x64-macos`: reuse x64 code generation and add Mach-O, the x64 runtime,
   `os.macos.e`, ad-hoc signing support shared with the later target, and macOS
   CI. Expected effort: roughly four to eight engineer-weeks for the
   self-contained path.
2. `aarch64-macos`: add the AArch64 backend and runtime, then reuse the Mach-O
   writer and OS surface. A production-ready backend is a multi-month effort.

The normative target list and cross-compilation rules remain in
[`spec.md`](spec.md); this note records the implementation boundary and rollout.
