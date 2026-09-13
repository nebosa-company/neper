# The bootstrap's archive

D95 makes the bootstrap's archive three things: a git tag on the last revision whose
`bootstrap/neper.c` compiles `src/main.e`, the SHA-256 of stage one, stage two and the
stable stage per platform at that revision, and the commands that reproduce those
hashes from a clean checkout of the tag on a machine carrying no `neper` binary. This
file is the second and third of those; the tag is `bootstrap-archive-1`, on the
revision that added this file, which differs from the one the hashes were taken at
(`448256c7a48c233e211b53a9cfbab6d2bbb2afe0`) only by this file and the readiness page,
neither of which the compiler reads.

## The stages

- **Stage one** is the bootstrap: `bootstrap/neper.c` and `bootstrap/runtime.c`
  compiled by the platform's C compiler. Its bytes depend on that compiler, so its
  hash is recorded for the toolchain named and is not expected to reproduce under
  another.
- **Stage two** is `src/main.e` compiled by stage one, under the bootstrap's own
  driver and C runtime.
- **Stage three** is `src/main.e` compiled by stage two, under the self-hosted
  compiler's own linker and embedded runtime. It is the **stable stage**: stage four,
  which it compiles, is byte-identical to it, and every later stage is the same
  file. Stages two and three are deterministic -- they depend on the sources alone --
  and are what a recovery must reproduce.

## Windows (x64)

Stage one built by MSVC 14.51.36231 (`cl /std:c11 /O2`), through
`scripts/build-bootstrap.ps1`.

| Stage | SHA-256 |
|---|---|
| one, `build/windows/neper.exe` | `118238A3A564AF03827344EFE2282B894C3B0BCFA0989AC6A700688E00BA9C7D` (toolchain-specific) |
| two | `DF44746CC6BFDDC1900338DC525C11BBCF1E8C770C36038F80D24BD953F9999D` |
| three, stable | `E765A90FEDB633E8F45E9CAFB4551F407C55BC6759D87CED1643E9A77B249B43` |
| four | `E765A90FEDB633E8F45E9CAFB4551F407C55BC6759D87CED1643E9A77B249B43` |

```powershell
git clone --branch bootstrap-archive-1 <repository> neper
cd neper
pwsh scripts/build-bootstrap.ps1
build\windows\neper.exe build src\main.e --arena 1g --output build\windows\stage2.exe
build\windows\stage2.exe emit-executable src\main.e . x64 windows build\windows\stage3.exe
build\windows\stage3.exe emit-executable src\main.e . x64 windows build\windows\stage4.exe
Get-FileHash build\windows\neper.exe, build\windows\stage2.exe, build\windows\stage3.exe, build\windows\stage4.exe
```

## Linux (x64)

Stage one built by GCC 13.3.0 (`cc -std=c99 -O2`), through `scripts/build-bootstrap.sh`.

| Stage | SHA-256 |
|---|---|
| one, `build/linux/neper` | `46416725566db367437caded884bb00136e4db75cf9dfc523db003cf31fa3a6f` (toolchain-specific) |
| two | `1847ea3aeb9fab295198e67301dcf952a17a12d6a77adb3f4ca603ec280f3e2d` |
| three, stable | `a74f577569d9325b30bcc7f94aea26e38ff11e33ffc6a52356a601a2e82019e5` |
| four | `a74f577569d9325b30bcc7f94aea26e38ff11e33ffc6a52356a601a2e82019e5` |

```sh
git clone --branch bootstrap-archive-1 <repository> neper
cd neper
sh scripts/build-bootstrap.sh
build/linux/neper build src/main.e --arena 1g --output build/linux/stage2
chmod +x build/linux/stage2
build/linux/stage2 emit-executable src/main.e . x64 linux build/linux/stage3
chmod +x build/linux/stage3
build/linux/stage3 emit-executable src/main.e . x64 linux build/linux/stage4
sha256sum build/linux/neper build/linux/stage2 build/linux/stage3 build/linux/stage4
```

## What the archive is for

Deleting the bootstrap (the M2 exit item after this one) removes `bootstrap/` from
the working tree; the tag keeps it buildable, and a recovery is the commands above
run at the tag, checked against the stage-three hashes, before the compiler at the
tag is used to build the compiler at the head. The self-host suite checks the fixed
point on every run, so the stable stage's hash at any later revision is the one the
suite's own build reports.
