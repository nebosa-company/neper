# FreeBSD cross-compilation

Status: evaluated; FreeBSD is a candidate target, not an implemented or
scheduled Neper host.

Linux and FreeBSD are close enough to share most compiler machinery, but they
are different binary targets. A Linux executable must not be relabelled as a
FreeBSD executable even when both use x86-64 ELF.

## Overlap with Linux

| Layer | Reusable for FreeBSD |
| --- | --- |
| Language frontend | Parser, resolver, type checker and diagnostics |
| Optimisation | Target-independent lowering and optimisation passes |
| Machine code | The x86-64 System V calling convention and most x64 code generation |
| Object format | Most ELF section, symbol, relocation and DWARF machinery |
| Library | Target-independent `e` modules |

Both systems are Unix-like and expose broadly POSIX-oriented process, file,
memory and socket APIs. FreeBSD supports amd64 and aarch64 as Tier 1
architectures, so the same architecture backends can eventually serve Linux
and FreeBSD. See the official [FreeBSD platform tiers](https://www.freebsd.org/platforms/).

## Target-specific differences

| Boundary | Linux | FreeBSD |
| --- | --- | --- |
| Product | Kernel combined with a selected userland | Integrated kernel and base system |
| Executable identity | Linux ELF ABI and notes | FreeBSD ELF OS ABI and ABI tag |
| Process entry | Linux initial stack and auxiliary vector | FreeBSD startup contract and auxiliary vector |
| Host calls | Linux syscall numbers and semantics | FreeBSD syscall numbers and semantics |
| Dynamic runtime | Commonly glibc or musl and a Linux loader | FreeBSD libc and `ld-elf.so.1` |
| Threads and TLS | Linux-specific runtime details | FreeBSD-specific runtime details |
| Isolation | Namespaces, cgroups and containers | Jails and FreeBSD resource controls |
| System assumptions | Linux paths, `/proc` behaviour and facilities | FreeBSD paths, `sysctl` and facilities |

Source code written against Neper's portable OS surface should usually compile
for either target. Prebuilt executables are not generally portable between
them. FreeBSD's optional Linux binary compatibility layer can run many Linux
programs, but using it would test the Linux target rather than provide a native
FreeBSD target. See the FreeBSD Handbook's
[Linux binary compatibility](https://docs.freebsd.org/en/books/handbook/linuxemu/).

## Neper implementation boundary

A native `x64-freebsd` target needs only the OS-specific slice rather than a
new compiler pipeline:

- `.Freebsd` in `target.Os`, a `freebsd` source suffix and
  `lib/e/os.freebsd.e`;
- FreeBSD ELF identification, ABI notes and dynamic-loader metadata;
- FreeBSD startup, auxiliary-vector, syscall, signal, thread and TLS support;
- FreeBSD libc imports for facilities that should not use raw syscalls; and
- byte-level ELF checks on every build host plus execution tests on FreeBSD.

The current planning estimate is that 70-85% of the compiler work is reusable.
That is an architectural estimate, not a measured implementation metric. A
useful static or otherwise self-contained x86-64 target is roughly a three-to-
six engineer-week project; full dynamic-library and runtime parity may take
longer.

FreeBSD is therefore the most economical additional general-purpose OS target.
Linux distributions such as TinyCore, Alpine and SteamOS remain compatibility
profiles for `x64-linux`, not new values in `target.Os`.
