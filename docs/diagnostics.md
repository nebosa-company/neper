# neper diagnostic-code registry — version 1

Status: normative. Codes are stable API values for tests and harnesses. The prose is
descriptive; the cited specification rule is authoritative. Retired codes remain in
this file and are never reassigned.

Categories are `CLI`, `LEX`, `SYNTAX`, `NAME`, `TYPE`, `COMPTIME`, `ERROR`, `MEM`,
`GPU`, `SAFETY`, `MODULE`, `LINK`, `TEST`, `FORMAT`, and `TOOL`.

| Code | Meaning | Rule |
|---|---|---|
| `E-CLI-9999` | invalid command, option, operand or option combination | spec §13 |
| `E-LEX-0001` | invalid UTF-8 | spec §3 |
| `E-LEX-0002` | forbidden control character or tab | spec §3 |
| `E-LEX-0003` | malformed literal or escape | spec §3 |
| `E-LEX-9999` | other lexical violation | spec §3 and grammar |
| `E-SYNTAX-0012` | delimiter crossed a recovery barrier | spec §3 |
| `E-SYNTAX-9999` | other concrete-syntax violation | grammar |
| `E-NAME-0001` | duplicate declaration in one namespace/scope | spec §§2, 5, 14 |
| `E-NAME-0002` | qualifier collision or invalid alias | spec §2 |
| `E-NAME-0003` | illegal shadowing of an active or reserved name | spec §§2, 5 |
| `E-NAME-9999` | other declaration or resolution violation | spec §§2, 5, 9, 14 |
| `E-TYPE-0001` | expression has no typing context | spec §3 |
| `E-TYPE-0002` | implicit conversion is not permitted | spec §§4, 6 |
| `E-TYPE-0003` | argument type does not match its parameter | spec §§4–6 |
| `E-TYPE-0004` | value is not representable in the required type | spec §4 |
| `E-TYPE-9999` | other typing, layout or operation violation | spec §§4–6, 8–10 |
| `E-COMPTIME-9999` | invalid or failed compile-time evaluation | spec §9 |
| `E-ERROR-9999` | invalid error declaration, use or propagation | spec §7 |
| `E-MEM-9999` | invalid memory, arena, pointer or representation operation | spec §8 |
| `E-GPU-9999` | invalid GPU declaration, profile operation or capability | spec §10 |
| `E-SAFETY-9999` | statically diagnosed safety-contract violation | spec §11 |
| `E-MODULE-0001` | module is missing or defined by multiple roots | spec §2 |
| `E-MODULE-0002` | import graph contains a cycle | spec §2 |
| `E-MODULE-9999` | other module/source-root violation | spec §§2, 12 |
| `E-LINK-9999` | link input, symbol or artifact violation | spec §§12–13 |
| `E-TEST-9999` | invalid test declaration or runner option | spec §13 |
| `E-FORMAT-0001` | source is not in canonical layout | spec §13 and tooling §6 |
| `E-FORMAT-9999` | other formatter input or contract violation | tooling §6 |
| `E-TOOL-0001` | stale or malformed generated source map | tooling §8 |
| `E-TOOL-9999` | other machine-protocol or tooling violation | tooling protocol |

The most-specific listed code applies. A violation without a more-specific entry uses
its category's `9999` code, so every rejected program already has a registered code
before implementation begins. The documentation phase may split a `9999` case into a
new stable code alongside its conformance fixture. An implementation may not emit an
unregistered code, and adding a code is a specification change even when it does not
change accepted programs.

## Implementation limits

The self-hosted compiler lowers every program into fixed pools sized once per program
(D302): 524288 NIR instructions, 131072 blocks, 2097152 operands and 16384 functions --
the sizes the compiler itself needs. A program that fills one is rejected under
`E-TYPE-9999` with a message naming the pool, its size and the program's counts so far;
the function named is where the pool filled, not the cause. Machine-code selection and
register allocation size their per-function tables from the lowered program and have no
separate ceiling.
