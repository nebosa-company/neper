# Security audit — 2026-09-24

## Remediation status

Remediation completed so far:

- M1: TAR entry and link paths reject slash/backslash roots, parent segments,
  drive-qualified segments, and unsafe PAX link paths.
- M2: CBOR `skip` enforces a 128-container nesting ceiling.
- M4: JWT lookup validates the complete UTF-8 JSON object, rejects escaped
  top-level names and all duplicate top-level names, and caps objects at 128
  members. Malformed strings, primitive values, and trailing data are rejected.
- L1: model endpoints require HTTPS, except for exact loopback hosts over HTTP;
  userinfo, queries, fragments, malformed ports, and other schemes are refused.
- H2: verified chains reject unknown critical extensions, CA key usage without
  `keyCertSign`, and excess CA depth under `pathLenConstraint`; critical DNS
  `nameConstraints` are parsed and applied to every descendant SAN, including
  wildcard SANs that overlap a specifically excluded hostname.
- H1: Bonsai's default model session exposes only repository-rooted read,
  search, and edit tools, then leaves changes unexecuted and uncommitted for
  review. The former unrestricted host workflow requires an explicit
  `--unsafe-compatibility` flag and warning.
- M5: IDNA validates Unicode 15.0 PVALID code points, RFC 5892 contextual
  characters, RFC 5893 domain-wide bidirectional rules, leading combiners, and
  incoming A-label canonical form and decoded hyphen restrictions.
- H3: AES uses algebraic constant-control-flow substitution, GHASH, Poly1305,
  and ML-KEM remove secret-dependent branches, and the variable-time P-256,
  BIP-340, FFDHE, ML-DSA, and RSA-PSS secret operations fail closed as
  `Unsupported`. Ed25519 secret scalar multiplication and reduction now use a
  fixed schedule and masked selection. Public signature verification remains
  available; this is not a formal proof of microarchitectural constant time.
- M3: build manifests carry HMAC-SHA-256 authentication under a random per-user
  key kept outside project caches and bind the full SHA-256 digest of every
  artifact. Unauthenticated manifests, missing digests, and mismatching artifacts
  are rebuilt from source; CRC32C is only a corruption check.

The focused fixtures pass on Windows and Linux, and all 15 tests in
`tests.test_llm_edit_benchmark` passed in the first remediation pass. The confirmed
findings below have targeted mitigations; the second pass corrected incomplete
fixes and does not establish that all source code is vulnerability-free.

## Second-pass verification

The earlier claim that all findings were fully remediated was too broad. Re-review
found five remaining gaps, now addressed:

1. **M3:** an authenticated CRC32C alone did not bind artifact contents. A
   machine-code mutation with compensating padding preserved the recorded CRC
   and the untouched signed manifest, and was reused as `stable`. The manifest
   now authenticates the full artifact SHA-256; both worker and serial reuse paths
   verify it. Old manifests without that digest rebuild. The CRC-preserving
   mutation and artifact-plus-manifest mutation regressions rebuild the clean
   executable on Windows and Linux, in debug and release modes; unchanged caches
   still reuse normally. Both self-host runners include these checks.
2. **H3:** Ed25519 still branched on secret scalar bits and RSA-PSS still used
   variable-time private exponentiation. Ed25519 now uses fixed-schedule point
   operations, masked selection/reduction, and arithmetic sign-bit encoding.
   RSA-PSS signing returns `Unsupported`; public verification is unchanged.
   `crypto_sign`, `crypto_sign_plan`, `crypto_pq`, `crypto_cipher`, and
   `crypto_aead` pass on both hosts; Ed25519 also passes release fixtures.
   Inspection of emitted x64 control flow for `pt_mul`, `fe_select`,
   `sc_reduce_once`, and `pt_encode` found no secret-bit-dependent branch. This
   focused check is not comprehensive side-channel certification.
3. **H2:** a wildcard SAN could cover a concrete excluded hostname without being
   rejected. Excluded-name checks now test that overlap. Signed-chain fixtures
   reject the overlapping wildcard even when another covered host is requested,
   while allowing a non-overlapping wildcard.
4. **M4:** duplicate unrequested claims and malformed unrequested JSON values
   escaped validation. Every top-level name is now checked for uniqueness and
   the entire object must be valid JSON. Fixtures cover duplicate custom/header
   members, trailing bytes, malformed escapes/surrogates/UTF-8/numbers, valid
   nested values, and the 128/129-member boundary.
5. **M5:** bidi validation was per-label only and decoded A-labels skipped hyphen
   restrictions. When any label is RTL, every label now passes the domain-wide
   Bidi rule, including ASCII siblings. Conversion in both directions rejects
   RTL-plus-numeric-label domains and malformed decoded hyphens; ordinary ASCII
   numeric domains and valid mixed RTL/LTR domains still pass.

The updated `fmt_jwt`, `crypto_x509`, `net_idna`, and transitive `net_tls` fixtures
pass on Windows and Linux. The IDNA table generator remains reproducible.
The strict manifest schema now accepts the authentication tag and artifact digest;
schema conformance passed 2,808 records in 307 files. Semgrep and Grype were not
reinstalled or rerun; their results below are historical.

## Executive summary

The audit covered the tracked source under `src/`, `lib/`, `scripts/`,
`benchmarks/`, `bootstrap/`, `examples/`, and `tests/`: 1,865 source files
(1,739 `.e`, 89 Python, 15 shell, 10 Rust, 9 PowerShell, and 3 C). Generated
output, local virtual environments, and `tmp/` were excluded.

No embedded private keys or likely hard-coded credentials were found. Grype
reported no known vulnerable packages, but the repository has no dependency
manifest that gives Grype meaningful coverage of the custom `.e` standard
library. Semgrep reported four Python findings. One of them belongs to a larger,
confirmed trust-boundary issue in the autonomous Bonsai driver; the other three
are low-risk dynamic-URL warnings.

| Severity | Count | Summary |
| --- | ---: | --- |
| Critical | 0 | None found |
| High | 3 | Autonomous model has host shell access; incomplete X.509 policy validation; variable-time private-key crypto |
| Medium | 5 | TAR traversal forms; CBOR recursion DoS; forgeable build-cache integrity; JWT claim ambiguity; incomplete IDNA validation |
| Low | 1 | User-selected URLs are not scheme/credential-bound |

This is a source audit, not a proof of absence. Semgrep does not parse Neper's
`.e` language, so the custom runtime and library findings below come from manual
trust-boundary review and targeted tests.

## Findings (initial audit)

### H1 — The autonomous Bonsai driver gives model output unsandboxed host command execution

**Evidence:** `scripts/bonsai_driver.py:28`, `:94-99`, `:133-143`, and
`:269-272`.

The model's `run` tool passes its string directly to Git Bash with `bash -lc`.
The denylist only recognizes a few textual spellings. It does not block, among
many equivalents, `rm -rf .`, network exfiltration, PowerShell, arbitrary
executables, writes to protected paths, or access outside the repository.
`read_lines` also resolves absolute paths without applying `_inside`.

The audit verified without mutating data that `read_lines("C:\\Windows\\win.ini")`
returns host-file contents and that the denylist returns false for `rm -rf .`, a
`curl` exfiltration command, and a shell write to `docs/tasks/README.md`.
Prompt injection in a task file, model compromise, or simply incorrect model
output therefore has the user's full filesystem and network authority. The
driver's later Git revert cannot recover deleted or exfiltrated data.

**Recommendation:** run the model process and tools in a disposable sandbox with
no user secrets and explicit filesystem/network policy. Root every read and
write through `_inside`. Replace the shell-string tool with an allowlist of exact
compiler/test commands and argument arrays; do not try to expand the denylist.

### H2 — X.509 verification accepts chains that RFC policy requires rejecting

**Evidence:** `lib/e/crypto/x509.e:20`, `:304-355`, and `:551-593`.

The parser recognizes only `subjectAltName` and the CA boolean in
`basicConstraints`. It consumes but does not retain an extension's `critical`
flag, and unknown critical extensions are silently ignored. Chain verification
checks the intermediate CA boolean, dates, signatures, hostname, and leaf EKU,
but does not enforce:

- rejection of unknown critical extensions;
- `basicConstraints.pathLenConstraint`;
- `nameConstraints`;
- CA `keyUsage.keyCertSign`.

An otherwise valid chain can therefore be accepted despite a critical
constraint that forbids it—for example, a constrained intermediate signing a
leaf outside its permitted DNS namespace.

**Recommendation:** retain extension criticality, reject every unhandled
critical extension, parse and enforce path length/name constraints, and require
`keyCertSign` when CA key usage is present. Add adversarial chain fixtures for
each rule before using this verifier as a general TLS trust engine.

### H3 — Several secret-key cryptographic operations are explicitly variable-time

**Evidence:** `lib/e/crypto/aead.e:5-9`, `lib/e/crypto/cipher.e:7-9`,
`lib/e/crypto/sign.e:865-866`, `lib/e/crypto/sign.e:994-997`,
`lib/e/crypto/sign.e:1344-1348`, `lib/e/crypto/kx.e:359-364`, and
`lib/e/crypto/kx.e:446-450`.

The implementations themselves document secret-dependent timing or cache
behavior: table-based AES, P-256 and BIP-340 signing, FFDHE exponentiation,
ML-DSA's early rejection loop, and ML-KEM decapsulation comparison. These can
leak key material to a co-resident attacker able to measure timing/cache effects.
Constant-time tag comparison does not make the underlying primitive
constant-time.

**Recommendation:** do not expose these operations to attacker-observable
shared-host workloads. Prefer audited platform/native constant-time
implementations; otherwise replace each secret-dependent primitive and add
side-channel-specific verification. The public API should state the limitation
until that work lands.

### M1 — TAR path checks miss Windows absolute/traversal forms and link targets

**Evidence:** `lib/e/fmt/tar.e:1-7`, `:112-123`, and `:280-287`.

`name_allowed` rejects only a leading `/` and `/`-delimited `..`. On Windows it
accepts drive paths (`C:\\...`), root-relative/UNC paths (`\\...`), and
backslash traversal (`..\\...`). The entry name is checked, but symlink and
hardlink targets—including PAX `linkpath`—are returned without equivalent
validation. A caller that extracts entries using the module's stated safety
contract can write or link outside the destination directory.

**Recommendation:** reject both slash forms, drive/UNC/device prefixes, and all
parent segments after separator normalization. Validate link targets separately,
or explicitly make extraction safety the caller's responsibility and provide a
single reusable safe-join helper.

### M2 — Public CBOR `skip` can exhaust the process stack on hostile input

**Evidence:** `lib/e/fmt/cbor.e:364-401`, `:492-494`, and `:563`.

`skip` recursively descends arrays, maps, and tags without a depth limit. It is
used by public operations such as canonical ordering and counting. The bounded
tree decoder accepts `max_depth`, but that protection does not apply to `skip`.
A few thousand nested items can crash the process with stack exhaustion.

**Recommendation:** thread a small depth counter through one internal `skip`
implementation and fail with `Invalid` at the same documented maximum used by
the decoder.

### M3 — Build-cache integrity is forgeable by an actor that can edit the cache

**Evidence:**
`src/main.e` artifact reuse, `src/tool.e` manifest publication, and the C042
record in `docs/work-done.jsonl` (D1020, corrected by D1028).

Artifacts were hashed and checked against an unkeyed manifest, so an actor that
could replace both could make a malicious artifact satisfy the old check.

**Remediation:** manifests now carry an HMAC-SHA-256 tag made with a random
per-user key stored outside the project cache, binding each artifact's full
SHA-256 rather than only CRC32C. The compiler authenticates the manifest before
reusing any artifact or prior executable digest and rebuilds unrecorded or
mismatching artifacts. Both CRC-preserving and manifest-rewriting regressions
rebuild the clean image on Windows and Linux. If no key can be obtained, the
build succeeds with an unsigned manifest that cannot authorize later cache reuse.

**Recommendation:** authenticate the manifest with a key held outside the cache,
or treat all cache contents as untrusted and rebuild from source whenever the
cache crosses a trust boundary. Local single-user caches are lower risk; shared,
downloaded, or cross-privilege caches are high risk.

### M4 — JWT claim lookup permits escaped and duplicate-name ambiguity

**Evidence:** `lib/e/fmt/jwt.e:130-154` and `:296-320`.

The flat scanner compares JSON member names as raw bytes, returns the first exact
match, and intentionally does not resolve escapes. A semantic claim such as
`"\\u0065xp"` is invisible to `claims_check`; duplicate claim names are accepted
and the first wins. A downstream standards-compliant JSON parser can see a
different claim set/value, creating validation-versus-use inconsistencies.

**Recommendation:** decode member names, reject duplicates after decoding, and
apply claims checks to that single parsed representation. If expiration is
mandatory for an application, also provide a required-claim option rather than
treating missing `exp` as valid.

### M5 — IDNA conversion omits validity and bidirectional-text rules

**Evidence:** `lib/e/net/idna.e:13-19`.

The module documents that it does not implement IDNA 2008 PVALID, CONTEXTJ,
CONTEXTO, or the RFC 5893 Bidi rule. It accepts labels after NFC/lowercasing and
hyphen checks alone. Invalid labels can therefore enter resolver, certificate,
allowlist, or UI flows and be interpreted differently by another component.

**Recommendation:** implement the derived-property/context/Bidi checks before
using this module at a security boundary. Until then, label the API as partial
conversion rather than domain-name validation.

### L1 — Dynamic endpoint URLs are not constrained to expected schemes/hosts

**Evidence:** `benchmarks/llm_edit/jev_router.py:151-174` and
`scripts/bonsai_driver.py:179-224`.

Both tools pass user-selected URLs to `urllib`. In the Jev benchmark, the chosen
URL receives the configured bearer API key. This is operator-controlled rather
than remotely controlled, so it is not an SSRF vulnerability in the current CLI
threat model, but a typo or copied command can disclose credentials or repository
task metadata to an unintended endpoint.

**Recommendation:** require `https` for credential-bearing remote endpoints;
permit `http` only for an explicit loopback development mode. Parse the URL once
and reject other schemes.

## Automated results (initial audit)

### Semgrep 1.178.0

Command:

```text
semgrep scan --config p/security-audit --metrics=off --json-output build/security-audit/semgrep-security-audit.json --exclude build --exclude .venv-docs-pdf --exclude tmp .
```

- 986 tracked files parsed; 96 of 225 rules were applicable.
- Four findings: `subprocess-shell-true` at
  `scripts/bonsai_driver.py:194`, plus dynamic `urllib` calls at
  `scripts/bonsai_driver.py:182`, `scripts/bonsai_driver.py:224`, and
  `benchmarks/llm_edit/jev_router.py:174`.
- The shell finding is subsumed by H1. The URL findings are assessed in L1.
- A separate `p/secrets` scan applied 37 rules and found zero secrets.

Raw reports:
`build/security-audit/semgrep-security-audit.json` and
`build/security-audit/semgrep-secrets.json`.

Semgrep was installed in the ignored local environment
`build/security-tools/semgrep-venv`. The initial `--config auto --metrics=off`
attempt was invalid because the registry auto-selection requires metrics; the
explicit security and secrets rulesets avoid that requirement.

### Grype 0.119.0

Command:

```text
grype dir:. --exclude './build/**' --exclude './.venv-docs-pdf/**' --exclude './tmp/**' -o json --file ./build/security-audit/grype.json
```

- Zero vulnerability matches.
- Database schema `v6.1.9`, built 2026-09-24 06:31:52 UTC and validated at scan
  time.
- The result is limited: no supported third-party package manifest was
  catalogued, and Grype cannot assess custom `.e` code.

Raw report: `build/security-audit/grype.json`. Grype was installed from Anchore's
official installer in the ignored local path `build/security-tools/grype/bin`
and run through WSL.

## Targeted regression checks (initial audit)

The existing `crypto_x509`, `net_tls`, `fmt_tar`, `fmt_cbor`, and `fmt_jwt`
self-host fixtures were compiled with
`build/windows/tests/selfhost/neper-self.exe` and executed on Windows. All five
exited successfully. They confirm the supported behavior still works; none
currently contains the adversarial cases described above.

## Security-positive observations

- Filesystem temporary creation uses OS randomness and exclusive creation.
- Linux random bytes use `getrandom`; Windows uses `BCryptGenRandom`.
- ZIP path validation rejects slash and backslash traversal, drive paths, and
  absolute paths, and applies entry/aggregate size limits.
- HTTP parsing bounds headers and rejects ambiguous Content-Length plus
  Transfer-Encoding framing.
- JWT signature verification requires the caller's expected algorithm, rejects
  `none`, and compares HMAC tags in constant time.
- Process execution uses argument arrays by default and has explicit time/output
  limits; H1 is the deliberate shell-string exception.
- Compiler artifacts have checksums, atomic publication, corruption rebuilds,
  nesting/resource caps, extensive fuzz coverage, and an authenticated manifest
  whose key is held outside project caches.

## Original remediation priorities

1. Sandbox or remove the Bonsai shell tool before running model-authored tasks on
   a workstation containing credentials.
2. Complete X.509 critical-extension and CA-constraint enforcement before using
   the verifier for general Internet TLS.
3. Prevent secret-key use of the variable-time crypto on shared hardware.
4. Fix TAR path/link validation and cap CBOR recursion; both are small,
   centralized parser changes.
5. Resolve cache authentication, JWT parsing, and IDNA validation when those
   features cross an untrusted boundary.
