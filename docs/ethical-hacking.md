# ethical hacking → neper support plan

Status: plan. Source: Python/R/Zig security-tooling survey (`ethical.md`, 2026-10-01).
Target: neper `lib/e` (pure stdlib) for defensive building blocks; drivers/tools where
privilege or platform reaches beyond `e.*`.

Rule: authorized-use primitives — scanning, triage, fuzzing, forensics — go in `e.*`;
weaponized exploit/C2 kits never do. No new third-party deps, no hand-rolled crypto,
no network in `e.*` tests (fake transports only). `docs/progress.html` stays the only
readiness record; this file is the work plan.

## 0. Ground rules

- Fenced modules, arena-first allocating calls, `snake_case`, per-module fixtures
  (`tests/` + goldens). Every port carries test vectors forward.
- Self-host constraint: portable Neper first; hardware intrinsics (AES, SHA, CRC) only
  behind the existing link-gated pattern (cf. C098, D336). The C bootstrap still builds
  stage 1 (T021), so avoid constructs it rejects until C088 lands.
- Fail-closed parsers: malformed/truncated input is an `err`, never a silent drop.
- Each new module states its defensive purpose (authorized testing, triage, forensics)
  in its doc comment.

## 1. Already covered (no new items)

| # | Python/R/Zig equiv | neper home | Notes |
|---|---|---|---|
| C1 | `socket`, `nmap` (connect-scan), `dig`/`dnsrecon` | `e.net` TCP/UDP + resolve + `cidr_parse`/`cidr_contains`/`is_private` (`lib/e/net.e`), `e.net.dns` wire codec (`lib/e/net/dns.e`) | Connect-scan, banner grab, DNS enumeration are user code over these. |
| C2 | `requests`/`httpx`, `nuclei` templates (transport half) | `e.net.http/tls/ws`, `e.net.http.auth` | HTTP fuzzing/dir-enum runners are user code; S4 adds shared helpers. |
| C3 | `beautifulsoup4`/`lxml`, `xml2` | `e.fmt.html/xml/json/yaml/csv` | Response parsing for web testing and OSINT. |
| C4 | `cryptography`/`pycryptodome`, `openssl`/`sodium` | `e.crypto.hash/aead/sign/kx/kdf/mac/x509/classic/cipher/random/noise` | Full suite; password-audit harnesses compose `hash` + `e.task`. |
| C5 | `sqlmap`/`nuclei` binaries, `hashcat`/`john` (as tools) | `e.proc` spawn/output/run (`lib/e/proc.e`) | Wrap external tools over a process boundary, as Python does via subprocess. |
| C6 | `atheris`, `zig test` + `std.fuzz` | `e.test.fuzz` mutate/run/minimize + grammar (`lib/e/test/fuzz.e`) | The fuzzing story already exists. |
| C7 | `click`/`typer`/`rich`, `fabric` | `e.cli`, `e.log`, `e.task`, `e.os.shell` | Scanner CLIs and automation. |
| C8 | R log/traffic analysis, anomaly detection | `e.algo.stat/timeseries`, `e.ml.*`, `e.grep`, `e.log` | Threat-hunting/analyst side. |
| C9 | Zig static implants/scanners/fuzzers | core language properties: no GC/VM, tiny native binaries, `extern fn` C ABI (D32), per-target files | Neper already plays Zig's role. |

## 2. New backlog (the gaps worth filling)

| # | Capability | neper home | Notes / acceptance |
|---|---|---|---|
| S1 | Packet codecs + pcap I/O (the `scapy`/`dpkt`/`pyshark` gap) | `e.net.packet`, `e.net.pcap` | Ethernet/IPv4/IPv6/TCP/UDP/ICMP encode/decode with checksums; pcap + pcapng read/write. Fixtures: crafted packets incl. malformed/truncated, checksum vectors, pcap round-trip goldens. Raw-socket send stays platform code outside `e.*` tests. |
| S2 | Executable format readers (the `lief`/`pefile`/`pyelftools` gap) | `e.fmt.elf`, `e.fmt.pe` | Read-only: headers, program/section tables, symbol + dynamic tables. Fixtures: minimal hand-built binaries plus cross-checks against `readelf`/`objdump` text goldens. No disassembler; Mach-O deferred. |
| S3 | Multi-pattern signature scanning (the `yara-python` gap) | extend `e.algo.search` or new small surface | First diff `e.algo.search` for Aho-Corasick; if absent, add a YARA-lite subset: hex strings with wildcards/jumps, ASCII/UTF-16 literals, `all of`/`any of`/count conditions. Fixtures incl. overlapping matches, wildcards, no-match. Framed for malware triage over S1/S2 inputs. |
| S4 | HTTP fuzz + host-sweep helpers (the `wfuzz`/`gobuster` pattern) | `e.net.http` extensions + recipe | Payload-encoder table (URL/form/JSON boundary cases), concurrent sweep runner over `e.task` with `e.ratelimit` + `e.cancel`, finding records with stable IDs (`e.algo.hash`, cf. petcow A6). Fixtures use fake HTTP only; target authorization is caller policy. |

Order: S1 → S2 → S3 → S4.

## 3. Explicitly out of scope (never `e.*`)

- Exploit automation: `pwntools`/`ropper` equivs, ROP/shellcode kits, disassemblers/assemblers/emulators (`capstone`/`keystone`/`unicorn` equivs). `extern fn` already reaches native engines without stdlib blessing.
- Post-exploitation/C2: `impacket`/`crackmapexec`/`ldap3` equivs (SMB/LDAP/Kerberos suites), implant frameworks.
- Wireless monitor/injection (`aircrack-ng` class); needs driver/hardware reach outside the language.
- Browser automation (`selenium`/`playwright` class); wrap via `e.proc`.
- Full vuln-scan engines (`nuclei`/`sqlmap` themselves) and password-cracking engines (`hashcat`/`john`); Neper provides primitives + wrapping, not the engines.
- R reporting surface (`rmarkdown` class); `e.fmt.*` + `e.log` suffice for machine-readable findings.

## 4. Acceptance per landing

- Fixture-driven goldens in-repo (inputs + expected outputs, incl. error cases named
  above); deterministic byte-equal reruns; Linux + Windows where platform matters.
- No `unsafe`, no new native deps, no network in `e.*` tests (fake transports/HTTP only).
- Docs: module API rows in `docs/module-apis.md` + `docs/modules.json` surface flags;
  this plan file tracks intent, `docs/progress.html` (generated) tracks readiness.

## 5. Architecture-spec review (infosec-language proposal, 2026-10-02)

Verdict per proposal: **covered** (exists), **adapt** (Neper's existing pattern serves it),
**queued** (new backlog item below), **deferred** (legitimate, not now), **rejected**
(never `e.*`, with reason). Only S5 is queued; everything else resolves to existing
surface, a recipe, or an explicit no.

| # | Proposal | Verdict | Rationale |
|---|---|---|---|
| P1 | Invisible ownership / no GC | covered | D3 arenas + explicit ownership already give deterministic memory with no GC pauses. |
| P2 | First-class `u32_le`/`u32_be` endian types | adapt | `e.bytes` load/store take an explicit `Endian`; S1/S2 codecs follow that pattern. No new type family. |
| P3 | Arbitrary bit-width `u7`/`u12`/`u24` | adapt | Integer widths are closed (`spec.md` §4); sub-byte fields decode via shifts/masks over `e.bytes`. Keeps codegen and D11 casing closed. |
| P4 | `#[packed]` zero-padding structs | covered | `@packed` exists (`spec.md:544,590-597`); direct byte→struct casts go through fail-closed codecs, not aliasing. |
| P5 | LLVM backend | rejected | D1 own direct emitter is locked; LLVM contradicts the 1M-lines/sec and hermetic-build goals. |
| P6 | `--emit=exe` | covered | Static native executables via the own linker (D13). |
| P7 | `--emit=dll` shared libraries | deferred | General linker work, not security-specific; no backlog item until a non-security consumer needs it. |
| P8 | `--emit=pic`/`shellcode` + PEB-walk import resolution | rejected | Raw position-independent payload emission is a weaponization path and contradicts the complete-unsafe-inventory and deterministic-artifact guarantees. |
| P9 | PE/ELF/Mach-O *modification* (IAT/EAT carve, code caves, PLT/GOT hooking, sig-strip) | rejected | Write/hook side stays out; the read-only triage side is S2/L052. Mach-O read-only slicing is an S2 follow-up, not queued. |
| P10 | APK/IPA backdooring (dex inject, resign, sign-bypass) | rejected | Payload injection plus signature bypass is offensive; read-only manifest/plist triage stays a deferred candidate over `e.fmt.zip`, not queued. |
| P11 | DMG/HFS+/APFS parsing | deferred | Forensics value but large scope and no demander yet; not queued. |
| P12 | Intercept proxy + auto-CA + forged leaf certs | adapt + queued (S5) | Proxy runner is user code over `tcp_listen` + `read_request` + `e.net.tls` (recipe under S4); the gap is cert *issuance* — `e.crypto.x509` parses/verifies only (`lib/e/crypto/x509.e:242,601`) — queued as S5. |
| P13 | Cookie jar, JWT none-alg / RS256→HS256 confusion | covered | Jar is L046; confusion testing is user code over `e.fmt.jwt` (`algorithm` + `verify` with expected alg, `lib/e/fmt/jwt.e:240,330`). |
| P14 | WebSocket frame mutate, GraphQL introspect/fuzz | covered | User code over `e.net.ws` + `e.net.http` + `e.fmt.json`. |
| P15 | `std::evasion` (indirect syscalls, `obf_str!`, CFG flattening) | rejected | EDR-bypass and obfuscation primitives defeat auditors as well as detectors and contradict the auditable-build guarantees; `extern fn` (D32) already reaches native APIs openly. |
| P16 | `std::asm` JIT, gadget discovery, lifter/IR taint | deferred | Needs a disassembler Neper deliberately does not ship (see S2); gadget search follows S2, lifter is research scope. Not queued. |
| P17 | Bit-flip protocol fuzzing | covered | `e.test.fuzz` mutation over S1 packet codecs; no new primitive. |
| P18 | eBPF/AF_PACKET stateless scanners | deferred | Privileged, platform-specific capture path; user code via `extern fn`, not stdlib. |
| P19 | Malleable C2 sockets (HTTP/DNS/ICMP wrapping) | rejected | C2 transport is never `e.*`. |
| P20 | `pattern_create`/`pattern_offset` | adapt | Recipe: one-liner over `e.algo.rand` + `e.bytes` + `e.str` for crash triage; no module. |
| P21 | Heap Feng Shui visualization | deferred | glibc/LFH internals are allocator-specific and version-fragile; not queued. |
| P22 | Python-like REPL | deferred | Neper is ahead-of-time native with no runtime JIT; a REPL needs an interpretive mode that contradicts the build model. Large scope, not queued. |
| P23 | Air-gapped package bundles | covered | `docs/pacman.md:275` project-relative path deps for air-gapped use, immutable cache, script-free hash-verified packages. |
| P24 | Headless scriptable debugging | deferred | Input to M4 `neper dap` scope (D9), not a new item. |

| # | Capability | neper home | Notes / acceptance |
|---|---|---|---|
| S5 | Certificate issuance for authorized TLS-intercept testing | `e.crypto.x509` extensions | CA generation plus leaf issuance/signing over `e.crypto.sign` (the `mitmproxy` pattern: one lab CA, per-host leaves). Fixtures: issued-chain verifies under a pinned CA, expiry/SAN/DNS-name goldens, fail-closed on wrong-issuer. No new crypto primitives. Follows S4's fake-transport test rule. |
