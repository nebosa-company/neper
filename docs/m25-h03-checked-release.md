# M2.5 stage B: H03 -- checked optimized execution and unsafe boundaries

The design H03 of [`post-m2-llm-hardening.md`](post-m2-llm-hardening.md) section 6
asks for, cut to what the compiler can promise today, with its record (D355).

## 1. The policy

Optimization and check removal are separate. A release build (`--release`) keeps
every row of spec section 11's table that is one compare -- `bounds`, `null`,
`tag`, `align` -- and gives the arithmetic rows their defined release results
(wrap, truncate, saturate, mask), as before. What a release build removes is the
debug fills and the two rows that are not a compare, `barrier` and `invalid`. The
label is not "safe release": section 11 says which rows are kept, and H01 and H02
say what the checks cannot establish -- a null check is not liveness, a bounds
check is not a validly constructed slice.

One check is eliminated by the compiler's own reasoning (D356): under
`while i < x.len { ... }` with `i` and `x` locals of the function, `x[i]` before the
body's first write of `i` is in range -- the condition read the length the access
sees -- provided no nested loop in the body writes `i` (its back edge would repeat
the access after the change), the body never writes `x`, and the function never
takes the address of `i`. The proof is read off the tokens when the loop is
lowered; the index instruction is emitted without its check; `--stats` reports
`bounds checks elided`. The fixture `bounds_proof` holds the eliminated case and
three retained ones -- the index read after its increment (which traps at the
end), an increment inside a nested loop, and the slice reassigned in the body --
as H03's acceptance asks. The same proof opens over the true block of
`if i < x.len { ... }` (D377): the guard read the length the access sees, and the
body's first write of `i` bounds it as the loop's does; `guarded` and
`guarded_shifted` in the fixture are its eliminated and retained cases, and the
compiler's own build reports 336 checks elided with both forms; the leftmost
conjunct of an `&&` condition opens the same proof over the rest of the condition
and the block (D378: 354); an early exit under `i >= x.len` proves the rest of its
block (D380: 369); an index bounded by its shape -- a `u8` widened, a literal mask,
a literal offset of a bounded value -- into an array of known length needs no
control flow at all (D384: 376). Further proofs -- an offset below a loop's slack
(`bytes[at + 3usize]` under `while at + 8usize <= bytes.len`), a bound through a
second local, a field base (`out.bytes[at]`) -- are the follow-up, and the compiler's own hot loops are mostly of
those shapes, which is why the cost below stands.

## 2. Unsafe operations

Two, both visible in source and both inventoried:

- `@nocheck { ... }` leaves every row but the always-on ones (`divide`, `enum`,
  `unreachable`) out of a block, in every build mode. It is the explicit unchecked
  index, dereference and payload read H03 asks to name; the obligation is the
  caller's, stated in a comment at the block, and nothing about the rest of the
  function or its callees changes. A checked caller does not sanitize an unchecked
  callee: what a `@nocheck` block computes is as trusted as the block.
- `--unchecked` on a release build leaves the same rows out of the whole image. It
  is not a mode: the manifest records it as `options.checks: "off"`, and a program
  built so is one unsafe boundary.

`@unsafe` (H01) is the other boundary -- a function that touches a resource's bits
-- and is inventoried beside them. The three are the whole of what "unsafe" means
in this revision.

## 3. The inventory

The build manifest's `unsafe` array lists every `@unsafe` function and every
`@nocheck` block of the program -- module, function, line -- read off the modules'
bytes so a warm build that checks no body lists them too; `options.checks` says
`retained` or `off`. A harness that wants the program's unsafe boundaries reads
that array (H27's one-command enumeration); the artifact format is 9, so a cache
made under the old policy is rebuilt rather than linked.

## 4. Obligations not yet met

- Check elimination with proofs, and the codegen tests for eliminated checks.
- `invalid` in release: the `zero`/`undef` and representation rows stay off.
- Definite initialization of fields and elements: not checked beyond `undef` of a
  resource (H01).
- The arithmetic rows' debug/release divergence (trap against wrap) is unchanged
  and recorded as build-mode context, as H03 allows; reconciling it is a versioned
  language change, not this record's.
- Foreign callbacks, packed records and the optimizer's assumptions: the audit of
  emitted loads and stores is not written.

## 5. Measurement (D355)

The compiler, built with the memory rows retained, against itself built without
them (the D344 release build), eight workers, five runs, p50, Windows:

| workload | mode | before | after (D355) | after (D356) | budget |
|---|---|---|---|---|---|
| sc500k (cold wall) | debug | 1477 ms | 1771 ms (+20%) | 1794 ms (+22%) | +10% |
| sc500k (cold wall) | release | 1650 ms | 1959 ms (+19%) | 1967 ms (+16%) | +10% |
| compiler (cold wall) | debug | 433 ms | 550 ms (+27%) | 536 ms (+23%) | +10% |
| compiler (cold wall) | release | 472 ms | 632 ms (+34%) | 620 ms (+29%) | +10% |
| compiler image | release | 5,513,728 B | 7,476,736 B (+36%) | 7,742,976 B (+40%) | +5% |

The image grew again at D356 for a reason that is a correction: the inline
oracle lowered its bodies with every check off (the old release mode), so a
function inlined into a release build ran unchecked -- the `bounds_proof`
fixture's `shifted` case found it by not trapping -- and now keeps its checks
like any body. The 312 checks the proof removes from the compiler are not
measurable against the run-to-run noise. **The M2 budgets for cold wall and
image size are not met** under this policy; the breach is recorded rather than
the policy narrowed, because H03 asks for the policy and the way back under
budget is section 1's further proofs, not check removal. `--unchecked`
reproduces the old numbers for a measurement or a build that accepts the
boundary.
