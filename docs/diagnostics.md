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
| `E-SAFETY-0001` | a resource used after it was moved, or never owned | spec §11 |
| `E-SAFETY-0002` | a resource still owned at an exit: its cleanup was forgotten | spec §11 |
| `E-SAFETY-0003` | an aggregate moved whole after a field was moved out of it | spec §11 |
| `E-SAFETY-0004` | a resource moved or closed while a pointer to it, taken in the open block, is kept | spec §11 |
| `E-SAFETY-0005` | a resource copied: `mem.bitcast`, a pointer cast, an element copied to an element | spec §11 |
| `E-SAFETY-0006` | an owned resource overwritten by assignment | spec §11 |
| `E-SAFETY-0007` | `undef` of a resource type | spec §11 |
| `E-SAFETY-0008` | a resource used before the error or flag it was returned beside was tested | spec §11 |
| `E-SAFETY-0009` | a resource consumed after a deferred call reserved it | spec §11 |
| `E-SAFETY-0010` | a declared resource's field read outside its module | spec §11 |
| `E-SAFETY-0011` | a resource declared outside a loop consumed inside it | spec §11 |
| `E-SAFETY-0012` | a borrowed resource closed, moved to an `own` parameter, or returned | spec §11 |
| `E-SAFETY-0013` | a value allocated in a region used after the region was reset | spec §11 |
| `E-SAFETY-0014` | a view of a container used after the container was mutated | spec §11 |
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

The self-hosted compiler lowers into pools sized from the program's source (D306):
the function, reference and string tables from the whole program, and the body pools
-- blocks, instructions, operands -- from the largest module when it builds an
executable, since it lowers and selects one module at a time and discards the bodies
before the next (D314), or from the whole program for an artifact or an object, which
keep every function. A body pool holds 262144 instructions plus one per four bytes of
the source it is sized from, five times what the compiler's own largest module lowers
to. A program that fills a pool is rejected under `E-TYPE-9999` with a message naming
the pool, its size and the program's counts so far; the function named is where the
pool filled, not the cause. Machine-code selection and register allocation size their
per-function tables from the pools and have no separate ceiling.
