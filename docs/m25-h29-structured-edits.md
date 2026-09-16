# M2.5 stage B: H29 -- structured edits

H29 of [`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) section 30 (R11 of the
recommendations): the tool stream expresses semantic refactors as typed operations
with pre- and postconditions, in addition to byte spans, so that H09/H17 multi-file
migrations are verifiable rather than text-replacement-fragile. Sections 1-3 are the
design; section 4 is what D376 delivered.

## 1. The shape

A **plan** is a stream: `precondition` records, `edit` records, a `postcondition`
record, the `result`. The compiler writes plans and never applies them; a harness
applies a plan to files whose preconditions still hold and re-checks. Every span in
a plan was computed by the compiler over one snapshot -- the files as read by that
command -- and the preconditions name the snapshot: the SHA-256 of every file an
edit touches. An edit whose file hash no longer matches is not applied, and nothing
else is either: a plan is applied whole or not at all.

| record | fields | meaning |
|---|---|---|
| `precondition` | `source`, `sha256` | the file as the plan saw it |
| `edit` | `op`, `symbol`, `site`, `span`, `replacement` | one byte-span replacement, derived from the operation |
| `postcondition` | `check` | what re-checking must find after the edits |
| `result.data` | `edits`, `files`, `complete` | counts; `complete` is false when the checker's tables overflowed |

The byte spans are not the operation; they are its rendering over this snapshot.
The operation is `op` with its arguments, and a harness that keeps the plan keeps
both: the intent, replayable against another snapshot by asking the compiler
again, and the spans, applicable to this one.

## 2. The operations

| `op` | arguments | preconditions | edits | postcondition |
|---|---|---|---|---|
| `rename-symbol` | `symbol` (a declared function), `to` (an identifier) | every touched file's hash; `to` is a value name | the declaration's name token; the name token at every resolved use, qualified or not | `check-file` passes; the uses of the new name are at the old sites; the old name names nothing |
| `change-signature` | `symbol`, the new parameter list | as above; every call site resolved | the declaration's signature; each call's argument list re-rendered per the mapping | `check-file` passes; the arity at every site is the new one |
| `add-parameter-and-migrate` | `symbol`, the parameter, a default expression per call | as above | the declaration; each call gains the argument | as above |
| `replace-expression` | a span and a replacement expression | the file's hash; the span is one expression node | one edit | `check-file` passes; the expression's type is unchanged |

The first (D376), the third (D406, `plan-add-parameter-file --symbol m.f
--parameter "name: T" --argument EXPR`) and the fourth (D414,
`plan-replace-expression-file --span START:END --with EXPR`) are delivered
(section 4); the parameter goes last and every call gains the argument last, a
function named as a value or chosen by a protocol is refused with the site, since
its type is its signature, and a span that is not exactly one expression node is
refused. `change-signature` is named here so that its plan shape is fixed before
it exists: the same record kinds, the operation in `op`, no new record.

## 3. What a plan does not claim

- Comments, strings and generated registrations that spell a name are not uses;
  a rename does not touch them (`uses-file`'s limit, D362).
- A function whose name is taken as a value and called through it is renamed at
  the value site; the calls through the value spell nothing and need nothing.
- Two functions of one name in two modules are two symbols; the plan renames the
  one the subject names.
- A plan is over the program the operand roots. A second program that imports the
  module and calls the function is not in the plan; the harness that renames a
  library symbol plans once per dependent program.

## 4. Implementation record

**D376** delivered `rename-symbol`: `plan-rename-file PATH ROOT ARCH OS --json
--symbol module.name --to NEW` in the compiler, over the checker's explain table
(D359-D362); `scripts/apply_plan.py` as the reference applier, which checks every
precondition before writing anything and applies each file's edits from the
highest offset down through a temporary and a replace; the corpus fixture
`plan_rename` (a generic function, its declaration and two instantiating calls)
and the suites' round trip -- plan, apply to a copy, `check-file`, `uses-file` of
the new name at the same sites, a second apply refused by the precondition.
