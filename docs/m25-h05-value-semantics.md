# M2.5 H05 closure: by-value ABI and alias semantics

This is H05's closure record (D654). The normative rule is `spec.md` section 5:
a by-value argument is a shallow snapshot at its left-to-right evaluation point.
An aggregate larger than two machine words may travel by hidden reference only when
the compiler proves the caller's storage cannot change during the call.

## Selected design and alternatives

Neper materializes caller-owned storage before the call and elides that copy for a
fresh value or a local whose address is never taken. Pointer, slice, string and global
places remain conservative. This keeps ordinary value semantics and uses `*T` as the
explicit spelling for mutation.

The former alternative—hidden-reference passing plus a nonlocal no-write
obligation—was rejected because `f(x, &x)` looked like an ordinary call but made the
program invalid. Copying every aggregate was correct but needlessly expensive; a
callee-effect proof may elide more copies later without changing this contract.

## Implementation and compatibility

`src/lower.e` implements the decision in `argument_can_change` and
`lower_call_arguments`; `--stats` reports copied and elided snapshots. Resources are
not copyable and retain H01's move/borrow rules. Format 11 of `.em` is the explicit
compatibility identity: a format-10 artifact is rejected before linking, so code built
under the old no-write contract cannot mix with snapshot code.

## Evidence

`tests/selfhost/fixtures/link/by_value_snapshot` runs in debug and release on Windows
and Linux. It covers `f(x, &x)`, mutation through a slice, shallow pointer fields,
fresh large returns, a concrete generic aggregate, a hidden multiple-return slot, a
foreign C write, and the cross-module call/inlining path. The self-host suites also
rewrite an artifact to format 10 and require `UnsupportedVersion`.

D358 measured 4,238 copies and 7,670 elisions in a compiler build, with cold-wall
cost between four and nine percent and a five-percent release-image increase against
D357. The semantics are closed; a proof from transitive callee effects remains an
optimization opportunity, not an aliasing obligation on source code.
