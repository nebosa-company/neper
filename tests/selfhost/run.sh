#!/usr/bin/env sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
neper="$repo/build/linux/neper"
test_build="$repo/build/linux/tests/selfhost"

# A rejection test asserts only that the compiler failed, and a path that does not
# exist fails too -- so a fixture whose path is wrong passes for the wrong reason.
# Twice today a mangled path in the PowerShell runner did exactly that. Every
# rejection names its fixture here first.
require_fixture() {
    if [ ! -f "$repo/tests/selfhost/fixtures/$1/src/main.e" ]; then
        printf '%s\n' "fixture $1 is missing" >&2
        exit 1
    fi
}
"$repo/scripts/build-bootstrap.sh" >/dev/null
mkdir -p "$test_build"

# The arena is reserved and committed as it is used (D133), so its size is a ceiling rather
# than a cost -- what a run charges is what it allocates. Measured against the heaviest
# workload there is, the compiler compiling itself: 384m exhausts, 400m succeeds, and the
# peak is 388m. A gigabyte is the largest program worth compiling, not the largest the
# commit limit will bear.
$neper build "$repo/src/main.e" --arena 1g --output "$test_build/neper-self" --emit-asm "$test_build/neper-self.s"
# Every bootstrap frame has to cover the temporaries its statements allocate. A
# frame sized by guess rather than by measurement lets a deep statement address
# below rsp, into the outgoing argument area and past the stack pointer.
awk '
function report() {
    if (proc != "" && frame > 0 && deepest > frame) {
        printf "%s reaches [rbp-%d] in a %d-byte frame\n", proc, deepest, frame
        bad = 1
    }
}
/^\.type [A-Za-z0-9_]+, @function/ { report(); proc = $2; sub(/,$/, "", proc); frame = 0; deepest = 0; probe = -1; next }
proc == "" { next }
frame == 0 && /^[ \t]+sub rsp, [0-9]+$/ { frame = $3 + 0; next }
frame == 0 && /^[ \t]+mov eax, [0-9]+$/ { probe = $3 + 0; next }
frame == 0 && probe >= 0 && /call np_stack_probe/ { frame = probe; probe = -1; next }
frame == 0 { next }
{
    rest = $0
    while (match(rest, /\[rbp-[0-9]+/)) {
        depth = substr(rest, RSTART + 5, RLENGTH - 5) + 0
        if (depth > deepest) deepest = depth
        rest = substr(rest, RSTART + RLENGTH)
    }
}
END { report(); if (bad) exit 1; exit 0 }
' "$test_build/neper-self.s"
# A bootstrap code-generation regression: `.len` on a call result is read out of a
# register, not an address, because a call result has no address. Built and run with
# the bootstrap, since that is the back end that had it wrong.
call_len_path="$test_build/call-result-len-bootstrap"
$neper build "$repo/tests/neper0/call-result-len.e" --output "$call_len_path" >/dev/null
chmod +x "$call_len_path"
"$call_len_path"
lexer=$($test_build/neper-self self-test)
[ "$lexer" = 'selfhost lexer ok' ]
scan=$($test_build/neper-self scan 'fn main() -> err { ret ok }')
[ "$scan" = 'scan ok' ]
parse=$($test_build/neper-self parse 'fn main() -> err { ret ok }')
[ "$parse" = 'parse ok' ]
scan_file=$($test_build/neper-self scan-file "$repo/src/main.e")
[ "$scan_file" = 'scan file ok' ]
parse_file=$($test_build/neper-self parse-file "$repo/tests/selfhost/fixtures/source-load.e")
[ "$parse_file" = 'parse file ok' ]
if missing_file=$($test_build/neper-self scan-file "$test_build/missing-source.e" 2>&1); then
    printf '%s\n' 'missing source unexpectedly loaded' >&2
    exit 1
fi
case "$missing_file" in
    *'error: os.NotFound'*) ;;
    *) printf '%s\n' 'source loader returned the wrong missing-file error' >&2; exit 1 ;;
esac
project_root=$($test_build/neper-self project-file "$repo/src/main.e" "$repo" main)
[ "$project_root" = 'project file ok' ]
library_module=$($test_build/neper-self project-file "$repo/lib/e/mem.e" "$repo" e.mem)
[ "$library_module" = 'project file ok' ]
nested_root="$repo/tests/selfhost/fixtures/modules"
nested_module=$($test_build/neper-self project-file "$nested_root/src/util/math.e" "$nested_root" util.math)
[ "$nested_module" = 'project file ok' ]
outside_root=$($test_build/neper-self project-file "$repo/examples/hello.e" "$repo" hello)
[ "$outside_root" = 'project file ok' ]
relative_root=$(cd "$repo" && "$test_build/neper-self" project-file src/main.e . main)
[ "$relative_root" = 'project file ok' ]
if invalid_module=$($test_build/neper-self project-file "$repo/src/main.txt" "$repo" main 2>&1); then
    printf '%s\n' 'non-source module path unexpectedly succeeded' >&2
    exit 1
fi
case "$invalid_module" in
    *'error: project.InvalidPath'*) ;;
    *) printf '%s\n' 'non-source module path returned the wrong error' >&2; exit 1 ;;
esac
variant_root="$repo/tests/selfhost/fixtures/variants"
variant_module=$($test_build/neper-self project-file "$variant_root/src/system.windows.e" "$variant_root" system)
[ "$variant_module" = 'project file ok' ]
nested_variant_module=$($test_build/neper-self project-file "$variant_root/src/nested/codec.aarch64.e" "$variant_root" nested.codec)
[ "$nested_variant_module" = 'project file ok' ]
windows_variant=$($test_build/neper-self select-file "$variant_root" src system x64 windows "$variant_root/src/system.windows.e")
[ "$windows_variant" = 'source variant ok' ]
linux_variant=$($test_build/neper-self select-file "$variant_root" src system x86 linux "$variant_root/src/system.linux.e")
[ "$linux_variant" = 'source variant ok' ]
plain_fallback=$($test_build/neper-self select-file "$variant_root" src system x64 macos "$variant_root/src/system.e")
[ "$plain_fallback" = 'source variant ok' ]
arch_variant=$($test_build/neper-self select-file "$variant_root" src architecture x64 linux "$variant_root/src/architecture.x64.e")
[ "$arch_variant" = 'source variant ok' ]
nested_variant=$($test_build/neper-self select-file "$variant_root" src nested.codec aarch64 macos "$variant_root/src/nested/codec.aarch64.e")
[ "$nested_variant" = 'source variant ok' ]
device_variant=$($test_build/neper-self select-file "$variant_root" src device spv none "$variant_root/src/device.none.e")
[ "$device_variant" = 'source variant ok' ]
if ambiguous_variant=$($test_build/neper-self select-file "$variant_root" src ambiguous x64 windows '' 2>&1); then
    printf '%s\n' 'ambiguous target source variants unexpectedly succeeded' >&2
    exit 1
fi
case "$ambiguous_variant" in
    *'error: project.AmbiguousVariant'*) ;;
    *) printf '%s\n' 'ambiguous target source variants returned the wrong error' >&2; exit 1 ;;
esac
if missing_variant=$($test_build/neper-self select-file "$variant_root" src missing x64 windows '' 2>&1); then
    printf '%s\n' 'missing target source module unexpectedly succeeded' >&2
    exit 1
fi
case "$missing_variant" in
    *'error: project.ModuleNotFound'*) ;;
    *) printf '%s\n' 'missing target source module returned the wrong error' >&2; exit 1 ;;
esac
if invalid_target=$($test_build/neper-self select-file "$variant_root" src system riscv64 linux '' 2>&1); then
    printf '%s\n' 'invalid source target unexpectedly succeeded' >&2
    exit 1
fi
case "$invalid_target" in
    *'error: project.InvalidTarget'*) ;;
    *) printf '%s\n' 'invalid source target returned the wrong error' >&2; exit 1 ;;
esac
if invalid_target_pair=$($test_build/neper-self select-file "$variant_root" src system x86 macos '' 2>&1); then
    printf '%s\n' 'invalid architecture/OS pair unexpectedly succeeded' >&2
    exit 1
fi
case "$invalid_target_pair" in
    *'error: project.InvalidTarget'*) ;;
    *) printf '%s\n' 'invalid architecture/OS pair returned the wrong error' >&2; exit 1 ;;
esac
if invalid_source_root=$($test_build/neper-self select-file "$variant_root" source system x64 windows '' 2>&1); then
    printf '%s\n' 'invalid source-root name unexpectedly succeeded' >&2
    exit 1
fi
case "$invalid_source_root" in
    *'error: project.InvalidPath'*) ;;
    *) printf '%s\n' 'invalid source-root name returned the wrong error' >&2; exit 1 ;;
esac
if reserved_module=$($test_build/neper-self project-file "$variant_root/src/windows.e" "$variant_root" '' 2>&1); then
    printf '%s\n' 'reserved target module name unexpectedly succeeded' >&2
    exit 1
fi
case "$reserved_module" in
    *'error: project.InvalidPath'*) ;;
    *) printf '%s\n' 'reserved target module name returned the wrong error' >&2; exit 1 ;;
esac
if compound_variant=$($test_build/neper-self project-file "$variant_root/src/system.x64.windows.e" "$variant_root" '' 2>&1); then
    printf '%s\n' 'compound target source suffix unexpectedly succeeded' >&2
    exit 1
fi
case "$compound_variant" in
    *'error: project.InvalidPath'*) ;;
    *) printf '%s\n' 'compound target source suffix returned the wrong error' >&2; exit 1 ;;
esac
graph_root="$repo/tests/selfhost/fixtures/graph"
transitive_graph=$($test_build/neper-self graph-file "$graph_root/transitive/src/main.e" "$repo" x64 linux main branch leaf)
[ "$transitive_graph" = 'module graph ok' ]
reused_graph=$($test_build/neper-self graph-file "$graph_root/reuse/src/main.e" "$repo" x64 linux main common)
[ "$reused_graph" = 'module graph ok' ]
toolchain_graph=$($test_build/neper-self graph-file "$nested_root/src/main.e" "$repo" x64 linux main e.io e.mem e.os e.str util.math)
[ "$toolchain_graph" = 'module graph ok' ]
variant_graph=$($test_build/neper-self graph-file "$variant_root/src/root.e" "$repo" x64 linux root system)
[ "$variant_graph" = 'module graph ok' ]
if cycle_graph=$($test_build/neper-self graph-file "$graph_root/cycle/src/a.e" "$repo" x64 linux '' 2>&1); then
    printf '%s\n' 'module import cycle unexpectedly succeeded' >&2
    exit 1
fi
case "$cycle_graph" in
    *'b.e:1:1: error[E-MODULE-0002]: `use a` closes an import cycle'*) ;;
    *) printf '%s\n' 'module import cycle returned the wrong error' >&2; exit 1 ;;
esac
if duplicate_graph=$($test_build/neper-self graph-file "$graph_root/duplicate/src/main.e" "$repo" x64 linux '' 2>&1); then
    printf '%s\n' 'duplicate source-root module unexpectedly succeeded' >&2
    exit 1
fi
case "$duplicate_graph" in
    *'main.e:1:1: error[E-MODULE-0001]: `use thing` is defined by both source roots'*) ;;
    *) printf '%s\n' 'duplicate source-root module returned the wrong error' >&2; exit 1 ;;
esac
if alias_graph=$($test_build/neper-self graph-file "$graph_root/alias/src/main.e" "$repo" x64 linux '' 2>&1); then
    printf '%s\n' 'duplicate import qualifier unexpectedly succeeded' >&2
    exit 1
fi
case "$alias_graph" in
    *'error: graph.DuplicateQualifier'*) ;;
    *) printf '%s\n' 'duplicate import qualifier returned the wrong error' >&2; exit 1 ;;
esac
if missing_graph=$($test_build/neper-self graph-file "$graph_root/missing/src/main.e" "$repo" x64 linux '' 2>&1); then
    printf '%s\n' 'missing graph module unexpectedly succeeded' >&2
    exit 1
fi
case "$missing_graph" in
    *'main.e:1:1: error[E-MODULE-0001]: `use absent` names no module'*) ;;
    *) printf '%s\n' 'missing graph module returned the wrong error' >&2; exit 1 ;;
esac
if invalid_graph=$($test_build/neper-self graph-file "$graph_root/invalid/src/main.e" "$repo" x64 linux '' 2>&1); then
    printf '%s\n' 'invalid imported source unexpectedly succeeded' >&2
    exit 1
fi
# A syntax error names the module that holds it and the token it stopped on.
case "$invalid_graph" in
    *'broken.e:1:12: error[E-SYNTAX-9999]: unexpected `{`'*) ;;
    *) printf '%s\n' 'invalid imported source did not name the offending module, position and token' >&2; exit 1 ;;
esac
if invalid_graph_target=$($test_build/neper-self graph-file "$graph_root/transitive/src/leaf.e" "$repo" x86 macos '' 2>&1); then
    printf '%s\n' 'module graph accepted an invalid target without imports' >&2
    exit 1
fi
case "$invalid_graph_target" in
    *'error: project.InvalidTarget'*) ;;
    *) printf '%s\n' 'invalid graph target returned the wrong error' >&2; exit 1 ;;
esac
resolve_root="$repo/tests/selfhost/fixtures/resolve"
resolved=$($test_build/neper-self resolve-file "$resolve_root/valid/src/main.e" "$repo" x64 linux)
[ "$resolved" = 'module resolve ok' ]
compiler_resolved=$($test_build/neper-self resolve-file "$repo/src/main.e" "$repo" x64 linux)
[ "$compiler_resolved" = 'module resolve ok' ]
builtin_qualifier=$($test_build/neper-self resolve-file "$resolve_root/builtin_qualifier/src/main.e" "$repo" x64 linux)
[ "$builtin_qualifier" = 'module resolve ok' ]
if duplicate_value=$($test_build/neper-self resolve-file "$resolve_root/duplicate_value/src/main.e" "$repo" x64 linux 2>&1); then
    printf '%s\n' 'duplicate value declaration unexpectedly succeeded' >&2
    exit 1
fi
case "$duplicate_value" in *'error: resolve.DuplicateName'*) ;; *) printf '%s\n' 'duplicate value returned the wrong error' >&2; exit 1 ;; esac
if duplicate_type=$($test_build/neper-self resolve-file "$resolve_root/duplicate_type/src/main.e" "$repo" x64 linux 2>&1); then
    printf '%s\n' 'duplicate type declaration unexpectedly succeeded' >&2
    exit 1
fi
case "$duplicate_type" in *'error: resolve.DuplicateName'*) ;; *) printf '%s\n' 'duplicate type returned the wrong error' >&2; exit 1 ;; esac
if qualifier_collision=$($test_build/neper-self resolve-file "$resolve_root/qualifier_collision/src/main.e" "$repo" x64 linux 2>&1); then
    printf '%s\n' 'qualifier/value collision unexpectedly succeeded' >&2
    exit 1
fi
case "$qualifier_collision" in *'error: resolve.QualifierCollision'*) ;; *) printf '%s\n' 'qualifier collision returned the wrong error' >&2; exit 1 ;; esac
if reserved_value=$($test_build/neper-self resolve-file "$resolve_root/reserved_value/src/main.e" "$repo" x64 linux 2>&1); then
    printf '%s\n' 'reserved value declaration unexpectedly succeeded' >&2
    exit 1
fi
case "$reserved_value" in *'error: resolve.ReservedName'*) ;; *) printf '%s\n' 'reserved value returned the wrong error' >&2; exit 1 ;; esac
if reserved_type=$($test_build/neper-self resolve-file "$resolve_root/reserved_type/src/main.e" "$repo" x64 linux 2>&1); then
    printf '%s\n' 'reserved type declaration unexpectedly succeeded' >&2
    exit 1
fi
case "$reserved_type" in *'error: resolve.ReservedName'*) ;; *) printf '%s\n' 'reserved type returned the wrong error' >&2; exit 1 ;; esac
if reserved_module=$($test_build/neper-self resolve-file "$resolve_root/reserved_module/src/u8.e" "$repo" x64 linux 2>&1); then
    printf '%s\n' 'reserved module name unexpectedly succeeded' >&2
    exit 1
fi
case "$reserved_module" in *'error: resolve.ReservedName'*) ;; *) printf '%s\n' 'reserved module returned the wrong error' >&2; exit 1 ;; esac
if reserved_qualifier=$($test_build/neper-self resolve-file "$resolve_root/reserved_qualifier/src/main.e" "$repo" x64 linux 2>&1); then
    printf '%s\n' 'reserved target qualifier unexpectedly succeeded' >&2
    exit 1
fi
case "$reserved_qualifier" in *'error: resolve.ReservedName'*) ;; *) printf '%s\n' 'reserved qualifier returned the wrong error' >&2; exit 1 ;; esac
if unknown_value=$($test_build/neper-self resolve-file "$resolve_root/unknown_value/src/main.e" "$repo" x64 linux 2>&1); then
    printf '%s\n' 'unknown qualified value unexpectedly succeeded' >&2
    exit 1
fi
case "$unknown_value" in *'error: resolve.UnknownMember'*) ;; *) printf '%s\n' 'unknown qualified value returned the wrong error' >&2; exit 1 ;; esac
if unknown_type=$($test_build/neper-self resolve-file "$resolve_root/unknown_type/src/main.e" "$repo" x64 linux 2>&1); then
    printf '%s\n' 'unknown qualified type unexpectedly succeeded' >&2
    exit 1
fi
case "$unknown_type" in *'error: resolve.UnknownMember'*) ;; *) printf '%s\n' 'unknown qualified type returned the wrong error' >&2; exit 1 ;; esac
unqualified_valid=$($test_build/neper-self resolve-file "$resolve_root/unqualified_valid/src/main.e" "$repo" x64 linux)
[ "$unqualified_valid" = 'module resolve ok' ]
if unknown_name=$($test_build/neper-self resolve-file "$resolve_root/unknown_name/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'unknown unqualified name unexpectedly succeeded' >&2; exit 1; fi
case "$unknown_name" in *'error: resolve.UnknownName'*) ;; *) printf '%s\n' 'unknown unqualified name returned the wrong error' >&2; exit 1 ;; esac
if unknown_bare_type=$($test_build/neper-self resolve-file "$resolve_root/unknown_bare_type/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'unknown unqualified type unexpectedly succeeded' >&2; exit 1; fi
case "$unknown_bare_type" in *'error: resolve.UnknownType'*) ;; *) printf '%s\n' 'unknown unqualified type returned the wrong error' >&2; exit 1 ;; esac
if namespace_as_type=$($test_build/neper-self resolve-file "$resolve_root/namespace_as_type/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'builtin namespace was accepted as a type' >&2; exit 1; fi
case "$namespace_as_type" in *'error: resolve.UnknownType'*) ;; *) printf '%s\n' 'builtin namespace type returned the wrong error' >&2; exit 1 ;; esac
if use_before_binding=$($test_build/neper-self resolve-file "$resolve_root/use_before_binding/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'binding was visible in its initializer' >&2; exit 1; fi
case "$use_before_binding" in *'error: resolve.UnknownName'*) ;; *) printf '%s\n' 'use-before-binding returned the wrong error' >&2; exit 1 ;; esac
if sibling_out_of_scope=$($test_build/neper-self resolve-file "$resolve_root/sibling_out_of_scope/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'sibling local remained visible after its scope' >&2; exit 1; fi
case "$sibling_out_of_scope" in *'error: resolve.UnknownName'*) ;; *) printf '%s\n' 'out-of-scope reference returned the wrong error' >&2; exit 1 ;; esac
if capture_not_in_case=$($test_build/neper-self resolve-file "$resolve_root/capture_not_in_case/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'switch capture was visible in its case expression' >&2; exit 1; fi
case "$capture_not_in_case" in *'error: resolve.UnknownName'*) ;; *) printf '%s\n' 'switch case reference returned the wrong error' >&2; exit 1 ;; esac
if unknown_top_level=$($test_build/neper-self resolve-file "$resolve_root/unknown_top_level/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'unknown top-level initializer name unexpectedly succeeded' >&2; exit 1; fi
case "$unknown_top_level" in *'error: resolve.UnknownName'*) ;; *) printf '%s\n' 'top-level initializer returned the wrong error' >&2; exit 1 ;; esac
if defer_binding_scope=$($test_build/neper-self resolve-file "$resolve_root/defer_binding_scope/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'deferred binding escaped its implicit scope' >&2; exit 1; fi
case "$defer_binding_scope" in *'error: resolve.UnknownName'*) ;; *) printf '%s\n' 'deferred binding scope returned the wrong error' >&2; exit 1 ;; esac
check_root="$repo/tests/selfhost/fixtures/check"
checked=$($test_build/neper-self check-file "$check_root/valid/src/main.e" "$repo" x64 linux)
[ "$checked" = 'module check ok' ]
lowered=$($test_build/neper-self nir-file "$repo/lib/e/io.e" "$repo" x64 linux)
[ "$lowered" = 'module nir ok' ]
hello_lowered=$($test_build/neper-self nir-file "$repo/examples/hello.e" "$repo" x64 linux)
[ "$hello_lowered" = 'module nir ok' ]
expressions_lowered=$($test_build/neper-self nir-file "$repo/tests/selfhost/fixtures/nir/expressions/src/main.e" "$repo" x64 linux)
[ "$expressions_lowered" = 'module nir ok' ]
expressions_generated=$($test_build/neper-self codegen-file "$repo/tests/selfhost/fixtures/nir/expressions/src/main.e" "$repo" x64 linux)
[ "$expressions_generated" = 'module codegen ok' ]
parameters_generated=$($test_build/neper-self codegen-file "$repo/tests/selfhost/fixtures/nir/parameters/src/main.e" "$repo" x64 linux)
[ "$parameters_generated" = 'module codegen ok' ]
calls_generated=$($test_build/neper-self codegen-file "$repo/tests/selfhost/fixtures/nir/calls/src/main.e" "$repo" x64 linux)
[ "$calls_generated" = 'module codegen ok' ]
object_generated=$($test_build/neper-self object-file "$repo/tests/selfhost/fixtures/nir/calls/src/main.e" "$repo" x64 linux)
[ "$object_generated" = 'module object ok' ]
elf_path="$test_build/calls.o"
object_written=$($test_build/neper-self emit-object "$repo/tests/selfhost/fixtures/nir/calls/src/main.e" "$repo" x64 linux "$elf_path")
[ "$object_written" = 'object written' ]
readelf -h "$elf_path" >/dev/null
executable_path="$test_build/basic-selfhost"
executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/basic/src/main.e" "$repo" x64 linux "$executable_path")
[ "$executable_written" = 'executable written' ]
chmod +x "$executable_path"
"$executable_path"
readelf -h -l "$executable_path" >/dev/null
scalar_executable_path="$test_build/scalar-selfhost"
scalar_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/scalar/src/main.e" "$repo" x64 linux "$scalar_executable_path")
[ "$scalar_executable_written" = 'executable written' ]
chmod +x "$scalar_executable_path"
"$scalar_executable_path"
generic_executable_path="$test_build/generic-selfhost"
generic_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/generic/src/main.e" "$repo" x64 linux "$generic_executable_path")
[ "$generic_executable_written" = 'executable written' ]
chmod +x "$generic_executable_path"
"$generic_executable_path"
generic_artifact_path="$test_build/generic.x64-linux.em"
generic_artifact_written=$($test_build/neper-self emit-em "$repo/tests/selfhost/fixtures/link/generic/src/main.e" "$repo" x64 linux "$generic_artifact_path")
[ "$generic_artifact_written" = 'compiled module written' ]
generic_artifact_executable_path="$test_build/generic-from-artifact"
generic_artifact_executable_written=$($test_build/neper-self link-em "$generic_artifact_executable_path" "$generic_artifact_path")
[ "$generic_artifact_executable_written" = 'artifact executable written' ]
chmod +x "$generic_artifact_executable_path"
"$generic_artifact_executable_path"
cmp "$generic_artifact_executable_path" "$generic_executable_path"
function_value_executable="$test_build/function-values-selfhost"
function_value_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/function_values/src/main.e" "$repo" x64 linux "$function_value_executable")
[ "$function_value_written" = 'executable written' ]
chmod +x "$function_value_executable"
"$function_value_executable"
function_value_artifacts="$test_build/function-values"
mkdir -p "$function_value_artifacts"
function_value_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/link/function_values/src/main.e" "$repo" x64 linux "$function_value_artifacts")
[ "$function_value_artifacts_written" = 'compiled modules written' ]
function_value_linked="$test_build/function-values-from-artifacts"
function_value_link_written=$($test_build/neper-self link-em "$function_value_linked" "$function_value_artifacts/main.x64-linux.em" "$function_value_artifacts/ops.x64-linux.em")
[ "$function_value_link_written" = 'artifact executable written' ]
chmod +x "$function_value_linked"
"$function_value_linked"
cmp "$function_value_linked" "$function_value_executable"
protocol_executable_path="$test_build/protocol-cmp-selfhost"
protocol_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/protocol_cmp/src/main.e" "$repo" x64 linux "$protocol_executable_path")
[ "$protocol_written" = 'executable written' ]
chmod +x "$protocol_executable_path"
"$protocol_executable_path"
# An enum orders by its backing integer. Codegen sees only the named type, so a
# `u64` enum whose top member sets the sign bit orders backwards unless lowering
# resolves the backing type first.
enum_ordering_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/enum_ordering/src/main.e" "$repo" x64 linux "$test_build/enum-ordering-selfhost")
[ "$enum_ordering_written" = 'executable written' ]
chmod +x "$test_build/enum-ordering-selfhost"
"$test_build/enum-ordering-selfhost"
# A negative member is the backing integer's two's complement at the backing
# width, so it has to compare, match and order like that integer.
enum_negative_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/enum_negative/src/main.e" "$repo" x64 linux "$test_build/enum-negative-selfhost")
[ "$enum_negative_written" = 'executable written' ]
chmod +x "$test_build/enum-negative-selfhost"
"$test_build/enum-negative-selfhost"
# Spec section 9 rule 4 recurses into arrays, slices and `str` in index order, and
# orders a matching prefix before the sequence that extends it.
sequence_cmp_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/sequence_cmp/src/main.e" "$repo" x64 linux "$test_build/sequence-cmp-selfhost")
[ "$sequence_cmp_written" = 'executable written' ]
chmod +x "$test_build/sequence-cmp-selfhost"
"$test_build/sequence-cmp-selfhost"
# An element whose own module declares `fn <t>_cmp` is compared by calling it. The
# fixture's `tag_cmp` reverses deliberately, so any comparison that did not reach the
# declaration would order the other way, and the call has to carry a dependency edge.
element_cmp_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/element_cmp/src/main.e" "$repo" x64 linux "$test_build/element-cmp-selfhost")
[ "$element_cmp_written" = 'executable written' ]
chmod +x "$test_build/element-cmp-selfhost"
"$test_build/element-cmp-selfhost"
element_cmp_artifacts="$test_build/element-cmp-artifacts"
rm -rf "$element_cmp_artifacts"
mkdir -p "$element_cmp_artifacts"
element_cmp_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/link/element_cmp/src/main.e" "$repo" x64 linux "$element_cmp_artifacts")
[ "$element_cmp_artifacts_written" = 'compiled modules written' ]
element_cmp_edge=$($test_build/neper-self check-em-edge "$element_cmp_artifacts/main.x64-linux.em" "$element_cmp_artifacts/shapes.x64-linux.em")
[ "$element_cmp_edge" = 'dependency current' ]
element_cmp_link_written=$($test_build/neper-self link-em "$test_build/element-cmp-from-artifacts" "$element_cmp_artifacts/main.x64-linux.em" "$element_cmp_artifacts/shapes.x64-linux.em")
[ "$element_cmp_link_written" = 'artifact executable written' ]
chmod +x "$test_build/element-cmp-from-artifacts"
"$test_build/element-cmp-from-artifacts"
# Rule 4 orders a tagged union by its tag before the live payload, and a void arm is
# equal to itself once the tags match.
tagged_union_cmp_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/tagged_union_cmp/src/main.e" "$repo" x64 linux "$test_build/tagged-union-cmp-selfhost")
[ "$tagged_union_cmp_written" = 'executable written' ]
chmod +x "$test_build/tagged-union-cmp-selfhost"
"$test_build/tagged-union-cmp-selfhost"
# The supplied `hash` is xxHash64 seed 0 over a value's canonical little-endian
# bytes, computed by the host runtime, and the fixture checks it against
# e.algo.hash.xxhash64 over those same bytes. The artifact link matters here as well:
# the call is the first host runtime symbol to reach the compiled-module linker.
supplied_hash_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/supplied_hash/src/main.e" "$repo" x64 linux "$test_build/supplied-hash-selfhost")
[ "$supplied_hash_written" = 'executable written' ]
chmod +x "$test_build/supplied-hash-selfhost"
"$test_build/supplied-hash-selfhost"
supplied_hash_artifacts="$test_build/supplied-hash-artifacts"
rm -rf "$supplied_hash_artifacts"
mkdir -p "$supplied_hash_artifacts"
supplied_hash_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/link/supplied_hash/src/main.e" "$repo" x64 linux "$supplied_hash_artifacts")
[ "$supplied_hash_artifacts_written" = 'compiled modules written' ]
supplied_hash_link_written=$($test_build/neper-self link-em "$test_build/supplied-hash-from-artifacts" "$supplied_hash_artifacts/main.x64-linux.em" "$supplied_hash_artifacts/e.algo.hash.x64-linux.em")
[ "$supplied_hash_link_written" = 'artifact executable written' ]
chmod +x "$test_build/supplied-hash-from-artifacts"
"$test_build/supplied-hash-from-artifacts"
# Rule 4 supplies `eq` for the same shapes as `cmp` and adds pointers. The fixture's
# `pair_eq` compares one field of two deliberately, so a comparison that did not reach
# the declaration would call unequal pairs equal.
supplied_eq_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/supplied_eq/src/main.e" "$repo" x64 linux "$test_build/supplied-eq-selfhost")
[ "$supplied_eq_written" = 'executable written' ]
chmod +x "$test_build/supplied-eq-selfhost"
"$test_build/supplied-eq-selfhost"
# A value whose bytes are not contiguous folds one hash per component instead of
# hashing one run. The fixture pins that the contiguous path is unchanged, that equal
# contents through different storage agree, and that regrouping the same flat bytes
# does not collide.
folded_hash_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/folded_hash/src/main.e" "$repo" x64 linux "$test_build/folded-hash-selfhost")
[ "$folded_hash_written" = 'executable written' ]
chmod +x "$test_build/folded-hash-selfhost"
"$test_build/folded-hash-selfhost"
# `mem.view` is the one arena intrinsic emitted where it is called rather than
# through a runtime symbol. It must alias storage the caller already owns.
mem_view_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/mem_view/src/main.e" "$repo" x64 linux "$test_build/mem-view-selfhost")
[ "$mem_view_written" = 'executable written' ]
chmod +x "$test_build/mem-view-selfhost"
"$test_build/mem-view-selfhost"
# `mem.cast` is the only route between pointer types, and the only route to `*void`
# at all. It must retype without moving: the address in is the address out.
mem_cast_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/mem_cast/src/main.e" "$repo" x64 linux "$test_build/mem-cast-selfhost")
[ "$mem_cast_written" = 'executable written' ]
chmod +x "$test_build/mem-cast-selfhost"
"$test_build/mem-cast-selfhost"
# The builder owns the top of an arena and grows in place. The fixture pins that the
# initial reservation is not a limit, that a foreign allocation turns the next push
# into `str.NotOnTop` rather than an overwrite, that `done` gives the unwritten tail
# back, that every integer form writes what its verb writes, and that a builder with
# a sink drains through it instead of reporting `mem.Exhausted`.
str_builder_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/str_builder/src/main.e" "$repo" x64 linux "$test_build/str-builder-selfhost")
[ "$str_builder_written" = 'executable written' ]
chmod +x "$test_build/str-builder-selfhost"
"$test_build/str-builder-selfhost"
# Each generator in `e.algo.rand` is a named published algorithm, so the fixture
# checks its stream against a separate implementation of the reference rather than
# against a property. A near miss is the failure worth catching here.
rand_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_rand/src/main.e" "$repo" x64 linux "$test_build/algo-rand-selfhost")
[ "$rand_written" = 'executable written' ]
chmod +x "$test_build/algo-rand-selfhost"
"$test_build/algo-rand-selfhost"
# Section 4's formatter is checked against its format string: a call whose arity or
# argument types do not match is a compile error, not a runtime one. The expansion
# is not written yet, so these are check fixtures rather than link ones.
format_accepted=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/format_accept/src/main.e" "$repo" x64 linux)
[ "$format_accepted" = 'module check ok' ]
for format_case in format_too_few format_too_many format_no_arena format_printf_arena format_hex_float format_binary_str format_precision_integer format_unknown_verb format_unterminated format_precision_wide format_not_literal format_untyped; do
    require_fixture "check/$format_case"
    if $test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/$format_case/src/main.e" "$repo" x64 linux >/dev/null 2>&1; then
        printf '%s\n' "formatter fixture $format_case was accepted" >&2
        exit 1
    fi
done
# `os.seek` is the first `e.os` intrinsic added since the runtime blobs were
# frozen. The file it works in is passed as an argument.
seek_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_seek/src/main.e" "$repo" x64 linux "$test_build/os-seek-selfhost")
[ "$seek_written" = 'executable written' ]
chmod +x "$test_build/os-seek-selfhost"
rm -f "$test_build/os-seek-output.txt"
"$test_build/os-seek-selfhost" "$test_build/os-seek-output.txt"
[ "$(wc -c < "$test_build/os-seek-output.txt")" = "11" ]
# `os.dup` (D349): a second identity for an open file, sharing its offset, closed on
# its own.
dup_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_dup/src/main.e" "$repo" x64 linux "$test_build/os-dup-selfhost")
[ "$dup_written" = 'executable written' ]
chmod +x "$test_build/os-dup-selfhost"
rm -f "$test_build/os-dup-output.txt"
"$test_build/os-dup-selfhost" "$test_build/os-dup-output.txt"
# A comptime `str` parameter binds a string literal where the call is written, so
# each distinct literal is its own instance and the body reads it as an ordinary
# `str`.
comptime_str_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/comptime_str/src/main.e" "$repo" x64 linux "$test_build/comptime-str-selfhost")
[ "$comptime_str_written" = 'executable written' ]
chmod +x "$test_build/comptime-str-selfhost"
"$test_build/comptime-str-selfhost"
# Only a string literal can bind one, and it binds nothing else.
for comptime_str_case in comptime_str_runtime comptime_str_integer comptime_str_type comptime_str_for_usize; do
    require_fixture "check/$comptime_str_case"
    if $test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/$comptime_str_case/src/main.e" "$repo" x64 linux >/dev/null 2>&1; then
        printf '%s\n' "comptime string fixture $comptime_str_case was accepted" >&2
        exit 1
    fi
done
# `type` is a compile-time parameter kind, not something a struct field can hold. The
# report has to name the field, because a location-less failure is what this was.
require_fixture "check/field_type_keyword"
if $test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/field_type_keyword/src/main.e" "$repo" x64 linux >/dev/null 2>&1; then
    printf '%s
' 'a field typed `type` was accepted' >&2
    exit 1
fi
# `@cc(CONV)` names a calling convention. Its argument parses as an expression but is
# not a value, and resolving it as one reported `unknown value name` at every `@cc`.
cc_accepted=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/cc_accepted/src/main.e" "$repo" x64 linux)
[ "$cc_accepted" = 'module check ok' ]
require_fixture "check/cc_unknown"
if $test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/cc_unknown/src/main.e" "$repo" x64 linux >/dev/null 2>&1; then
    printf '%s\n' 'an unknown calling convention was accepted' >&2
    exit 1
fi
# `os.thread_create` / `join` / `detach`. Windows runs a real thread; Linux answers
# `Unsupported` for now, the ELF output being static with no libc to get one from.
thread_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_thread/src/main.e" "$repo" x64 linux "$test_build/os-thread-selfhost")
[ "$thread_written" = 'executable written' ]
chmod +x "$test_build/os-thread-selfhost"
"$test_build/os-thread-selfhost"
# `e.meta`'s scalar reflection. Section 9 keeps all of it at compile time, so each
# call is a constant by the time lowering sees it and the binary carries no type
# information at all.
meta_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/meta_scalar/src/main.e" "$repo" x64 linux "$test_build/meta-scalar-selfhost")
[ "$meta_written" = 'executable written' ]
chmod +x "$test_build/meta-scalar-selfhost"
"$test_build/meta-scalar-selfhost"
# `e.io`'s streams: a reader and a writer are a context and a callback, so every
# adapter is a value the caller owns. The callbacks the constructors install are
# ordinary declarations (D94), which is what let the module be written at all.
io_streams_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/io_streams/src/main.e" "$repo" x64 linux "$test_build/io-streams-selfhost")
[ "$io_streams_written" = 'executable written' ]
chmod +x "$test_build/io-streams-selfhost"
"$test_build/io-streams-selfhost"
# `io.printf[FMT]` is `format` over a buffer of its own, drained through a generated
# sink. Its output is compared byte for byte against a file written from the format
# strings, so the line that outgrows the 4 KiB buffer pins that the drains and the
# final write agree about where they are.
printf_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/io_printf/src/main.e" "$repo" x64 linux "$test_build/io-printf-selfhost")
[ "$printf_written" = 'executable written' ]
chmod +x "$test_build/io-printf-selfhost"
"$test_build/io-printf-selfhost" > "$test_build/io-printf-output.txt"
cmp "$test_build/io-printf-output.txt" "$repo/tests/selfhost/fixtures/link/io_printf/expected.txt"
# `push_err` writes an error's qualified name. It is the one `e.str` declaration a
# library cannot write: the answer is the merged error table, which is a property of
# the whole program rather than of any one module.
push_err_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/str_push_err/src/main.e" "$repo" x64 linux "$test_build/str-push-err-selfhost")
[ "$push_err_written" = 'executable written' ]
chmod +x "$test_build/str-push-err-selfhost"
"$test_build/str-push-err-selfhost"
# A flushing builder over a stack arena: the shape `printf` expands to, and the only
# thing that exercises `builder_to`'s drain. Pushing several times the arena's size
# through it proves the drain happens during the pushes, not once at the end.
flush_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/str_flush/src/main.e" "$repo" x64 linux "$test_build/str-flush-selfhost")
[ "$flush_written" = 'executable written' ]
chmod +x "$test_build/str-flush-selfhost"
"$test_build/str-flush-selfhost"
# `str.format[FMT]` expands to a generated function: a builder, a push per piece of
# the format string, and `done`. The fixture compares its output against the same
# pushes written by hand.
format_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/str_format/src/main.e" "$repo" x64 linux "$test_build/str-format-selfhost")
[ "$format_written" = 'executable written' ]
chmod +x "$test_build/str-format-selfhost"
"$test_build/str-format-selfhost"
# A struct whose module declares no format has nothing rule 4 supplies and nothing to
# call, so the build stops rather than quietly formatting nothing (D189-D191 cover
# what is formattable).
require_fixture "check/format_compound_argument"
if $test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/check/format_compound_argument/src/main.e" "$repo" x64 linux "$test_build/format-compound-argument" >/dev/null 2>&1; then
    printf '%s\n' 'a format verb with no push was lowered' >&2
    exit 1
fi
# `e.algo.uuid` reads no clock and no random source, so a UUID is a pure function of
# its inputs and the fixture can pin the exact text of one.
uuid_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_uuid/src/main.e" "$repo" x64 linux "$test_build/algo-uuid-selfhost")
[ "$uuid_written" = 'executable written' ]
chmod +x "$test_build/algo-uuid-selfhost"
"$test_build/algo-uuid-selfhost"
# The float pushes: `{}` writes the shortest string that reads back as the same value,
# `{.N}` exactly N digits after the point. The fixture checks the text against an
# independent implementation and reads every shortest case back through the parser.
push_float_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/str_push_float/src/main.e" "$repo" x64 linux "$test_build/str-push-float-selfhost")
[ "$push_float_written" = 'executable written' ]
chmod +x "$test_build/str-push-float-selfhost"
"$test_build/str-push-float-selfhost"
# `parse_f64` and `parse_f32` are the inverse of the float pushes and accept nothing
# else. The fixture pins the grammar, the non-finite tokens, both range ends and the
# exact ties, against bit patterns produced by rounding an exact rational.
parse_float_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/str_parse_float/src/main.e" "$repo" x64 linux "$test_build/str-parse-float-selfhost")
[ "$parse_float_written" = 'executable written' ]
chmod +x "$test_build/str-parse-float-selfhost"
"$test_build/str-parse-float-selfhost"
# `mem.bitcast` reads a value's bytes as another type of the same size, which is what
# lets a pun avoid a `union`. A scalar lives in a register and an aggregate is an
# address, so the fixture covers all four shapes as well as the bit patterns.
bitcast_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/mem_bitcast/src/main.e" "$repo" x64 linux "$test_build/mem-bitcast-selfhost")
[ "$bitcast_written" = 'executable written' ]
chmod +x "$test_build/mem-bitcast-selfhost"
"$test_build/mem-bitcast-selfhost"
# `mem.address_of` is the one way a pointer becomes a number. Where the arena lands is
# not knowable from inside the program, so the fixture checks what an address has to
# satisfy whatever it is: distances that follow the element size, field offsets,
# alignment, and the same answer for one place reached two ways.
address_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/mem_address/src/main.e" "$repo" x64 linux "$test_build/mem-address-selfhost")
[ "$address_written" = 'executable written' ]
chmod +x "$test_build/mem-address-selfhost"
"$test_build/mem-address-selfhost"
# `e.os`'s filesystem primitives and `e.fs` over them, on a real filesystem. The
# primitives are the per-target half -- `os.syscall` on Linux, `kernel32` through
# `@import` on Windows -- so the same two fixtures run on both hosts and what they
# assert is that the two spellings answer alike. Both use relative paths, so they run
# with the build directory as the working directory and write nothing outside it.
fs_scratch="$test_build/fs-scratch"
mkdir -p "$fs_scratch"
os_fs_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_fs/src/main.e" "$repo" x64 linux "$test_build/os-fs-selfhost")
[ "$os_fs_written" = 'executable written' ]
chmod +x "$test_build/os-fs-selfhost"
(cd "$fs_scratch" && "$test_build/os-fs-selfhost")
fs_basics_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fs_basics/src/main.e" "$repo" x64 linux "$test_build/fs-basics-selfhost")
[ "$fs_basics_written" = 'executable written' ]
chmod +x "$test_build/fs-basics-selfhost"
(cd "$fs_scratch" && "$test_build/fs-basics-selfhost")
# `e.proc` against a real child, which is the fixture's own image. The child fills its stderr
# pipe before its stdout is drained, so `output` returning at all is what proves the two
# streams are read at once; a child that never stops is what proves the limit ends it.
proc_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/proc_output/src/main.e" "$repo" x64 linux "$test_build/proc-output-selfhost")
[ "$proc_written" = 'executable written' ]
chmod +x "$test_build/proc-output-selfhost"
"$test_build/proc-output-selfhost"
# `e.thread` over `e.os`'s three intrinsics: spawned and joined, the work in the context it
# was given, a zero stack meaning the default, and `Thread` being `os.Thread` in every respect.
thread_spawn_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/thread_spawn/src/main.e" "$repo" x64 linux "$test_build/thread-spawn-selfhost")
[ "$thread_spawn_written" = 'executable written' ]
chmod +x "$test_build/thread-spawn-selfhost"
"$test_build/thread-spawn-selfhost"
# `e.test`'s four assertions, each in both directions, and `eq` across every kind rule 4
# supplies equality for -- the floats now among them, under the container rule.
test_assert_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/test_assert/src/main.e" "$repo" x64 linux "$test_build/test-assert-selfhost")
[ "$test_assert_written" = 'executable written' ]
chmod +x "$test_build/test-assert-selfhost"
"$test_build/test-assert-selfhost"
# `e.data.map`: open addressing with linear probing, keyed by anything with a `hash` and an
# `eq`. The fixture fills past several doublings, removes from the middle so that keys placed
# past a hole must still be reached through the dead slot, reinserts into it, and iterates.
data_map_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_map/src/main.e" "$repo" x64 linux "$test_build/data-map-selfhost")
[ "$data_map_written" = 'executable written' ]
chmod +x "$test_build/data-map-selfhost"
"$test_build/data-map-selfhost"
# `e.bytes`: numbers through bytes in both orders and every width, the bit operations, and
# base64, base32 and base85 against the vectors their RFCs print, then every byte value round
# tripped through each. One generic `load` serves every width because `size_of` folds for a
# scalar, so the arm for the other width is gone rather than merely not taken.
bytes_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/bytes_codec/src/main.e" "$repo" x64 linux "$test_build/bytes-codec-selfhost")
[ "$bytes_written" = 'executable written' ]
chmod +x "$test_build/bytes-codec-selfhost"
"$test_build/bytes-codec-selfhost"
# `e.data.iter`: every adapter over a list's iterator, stacked two and three deep, every fold
# to its end or its first answer, and the `try_` family over a source that fails where it is
# told to. It also pins the nested-instance annotation that misread its arguments (D145).
data_iter_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_iter/src/main.e" "$repo" x64 linux "$test_build/data-iter-selfhost")
[ "$data_iter_written" = 'executable written' ]
chmod +x "$test_build/data-iter-selfhost"
"$test_build/data-iter-selfhost"
# `e.math`'s exact set: `sqrt` as the instruction, correctly rounded on both widths and checked
# by its bits, and the rounders, `abs`, `copysign`, `min` and `max` as source. Exact means
# bit-for-bit, so `-0` and `+0` are told apart wherever a sign could hide.
math_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_exact/src/main.e" "$repo" x64 linux "$test_build/math-exact-selfhost")
[ "$math_written" = 'executable written' ]
chmod +x "$test_build/math-exact-selfhost"
"$test_build/math-exact-selfhost"
# `exp`, `exp2`, `log`, `log2` and `log10` against mpmath at 200 bits: within 1 ULP of the correctly rounded answer at every input, the reductions and the subnormal results included.
math_exp_log_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_exp_log/src/main.e" "$repo" x64 linux "$test_build/math-exp-log-selfhost")
[ "$math_exp_log_written" = 'executable written' ]
chmod +x "$test_build/math-exp-log-selfhost"
"$test_build/math-exp-log-selfhost"
# `atan`, `atan2`, `asin` and `acos` against the same reference, on every fold point and every signed zero and infinity IEEE assigns a quadrant to.
math_inverse_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_inverse/src/main.e" "$repo" x64 linux "$test_build/math-inverse-selfhost")
[ "$math_inverse_written" = 'executable written' ]
chmod +x "$test_build/math-inverse-selfhost"
"$test_build/math-inverse-selfhost"
# `sin`, `cos` and `tan` against the same reference, through the direct kernel, the Cody-Waite reduction and the Payne-Hanek one, on the double that cancels the most bits of any.
math_trig_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_trig/src/main.e" "$repo" x64 linux "$test_build/math-trig-selfhost")
[ "$math_trig_written" = 'executable written' ]
chmod +x "$test_build/math-trig-selfhost"
"$test_build/math-trig-selfhost"
# `pow` against the same reference and the whole of section 11's special-value table, plus one value through each single-precision wrapper.
math_pow_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_pow/src/main.e" "$repo" x64 linux "$test_build/math-pow-selfhost")
[ "$math_pow_written" = 'executable written' ]
chmod +x "$test_build/math-pow-selfhost"
"$test_build/math-pow-selfhost"
# `e.simd` over the two builtins: the closed table's layout, every intrinsic but `shuffle` on
# integer and float lanes, the pairwise reduction order, masked loads at a slice's tail, and
# `pdep`/`pext` against their definitions.
simd_lanes_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/simd_lanes/src/main.e" "$repo" x64 linux "$test_build/simd-lanes-selfhost")
[ "$simd_lanes_written" = 'executable written' ]
chmod +x "$test_build/simd-lanes-selfhost"
"$test_build/simd-lanes-selfhost"
# A module-scope `var` is storage: a function that writes and another that reads agree, and each
# global keeps its own width. Never wired when it was written (849fa5b), and on Windows it did not
# link until D150 -- a global's index was bounded against the function references.
module_var_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/module_var/src/main.e" "$repo" x64 linux "$test_build/module-var-selfhost")
[ "$module_var_written" = 'executable written' ]
chmod +x "$test_build/module-var-selfhost"
"$test_build/module-var-selfhost"
# And from `.em` artifacts (D154), quickly because the reach walk reads each module once (D155).
module_var_artifacts="$test_build/module-var-artifacts"
mkdir -p "$module_var_artifacts"
module_var_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/link/module_var/src/main.e" "$repo" x64 linux "$module_var_artifacts")
[ "$module_var_artifacts_written" = 'compiled modules written' ]
module_var_link_written=$($test_build/neper-self link-em "$test_build/module-var-from-artifacts" "$module_var_artifacts/main.x64-linux.em" "$module_var_artifacts/e.mem.x64-linux.em" "$module_var_artifacts/e.os.x64-linux.em")
[ "$module_var_link_written" = 'artifact executable written' ]
chmod +x "$test_build/module-var-from-artifacts"
cmp "$test_build/module-var-selfhost" "$test_build/module-var-from-artifacts"
"$test_build/module-var-from-artifacts"
# `main` declaring `args` receives the command line whether the image was linked from source or
# from `.em` artifacts, and a quoted argument arrives whole. The root artifact goes first: the
# linker finds `main` in module 0, which is whichever artifact is named first.
main_args_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/main_args/src/main.e" "$repo" x64 linux "$test_build/main-args-selfhost")
[ "$main_args_written" = 'executable written' ]
chmod +x "$test_build/main-args-selfhost"
"$test_build/main-args-selfhost" one 'two words'
main_args_artifacts="$test_build/main-args-artifacts"
mkdir -p "$main_args_artifacts"
main_args_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/link/main_args/src/main.e" "$repo" x64 linux "$main_args_artifacts")
[ "$main_args_artifacts_written" = 'compiled modules written' ]
main_args_link_written=$($test_build/neper-self link-em "$test_build/main-args-from-artifacts" "$main_args_artifacts/main.x64-linux.em" "$main_args_artifacts/e.mem.x64-linux.em")
[ "$main_args_link_written" = 'artifact executable written' ]
chmod +x "$test_build/main-args-from-artifacts"
"$test_build/main-args-from-artifacts" one 'two words'
# A module-scope `var` links the same from source and from `.em` artifacts (D154): the format
# carries a section for it and a code relocation says which of a function or a var it names.
# This one imports nothing, so its single artifact links at once.
global_artifact_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/global_artifact/src/main.e" "$repo" x64 linux "$test_build/global-artifact-selfhost")
[ "$global_artifact_written" = 'executable written' ]
chmod +x "$test_build/global-artifact-selfhost"
"$test_build/global-artifact-selfhost"
global_artifacts="$test_build/global-artifact"
mkdir -p "$global_artifacts"
global_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/link/global_artifact/src/main.e" "$repo" x64 linux "$global_artifacts")
[ "$global_artifacts_written" = 'compiled modules written' ]
global_artifact_link_written=$($test_build/neper-self link-em "$test_build/global-artifact-from-artifacts" "$global_artifacts/main.x64-linux.em")
[ "$global_artifact_link_written" = 'artifact executable written' ]
chmod +x "$test_build/global-artifact-from-artifacts"
cmp "$test_build/global-artifact-selfhost" "$test_build/global-artifact-from-artifacts"
"$test_build/global-artifact-from-artifacts"
# `e.data.stack` and `e.data.queue` over their storage modules, and `e.algo.disjoint_set`
# on caller storage: order, peek, non-mutating iteration, growth, and union-find with path
# compression and union by rank.
data_adapters_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_adapters/src/main.e" "$repo" x64 linux "$test_build/data-adapters-selfhost")
[ "$data_adapters_written" = 'executable written' ]
chmod +x "$test_build/data-adapters-selfhost"
"$test_build/data-adapters-selfhost"
# `e.algo.stat` against closed-form moments and a least-squares line, and `e.data.slot_map`'s
# generational keys: stale after removal, reused with the next generation, retired at the last.
stat_slots_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/stat_slots/src/main.e" "$repo" x64 linux "$test_build/stat-slots-selfhost")
[ "$stat_slots_written" = 'executable written' ]
chmod +x "$test_build/stat-slots-selfhost"
"$test_build/stat-slots-selfhost"
# `e.data.linked`: stable node identifiers through insertion at both ends and beside a node,
# removal that never reuses one, and `clear` invalidating every identifier.
data_linked_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_linked/src/main.e" "$repo" x64 linux "$test_build/data-linked-selfhost")
[ "$data_linked_written" = 'executable written' ]
chmod +x "$test_build/data-linked-selfhost"
"$test_build/data-linked-selfhost"
# `e.data.graph`: CSR adjacency from a builder, insertion order kept, undirected edges as two.
data_graph_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_graph/src/main.e" "$repo" x64 linux "$test_build/data-graph-selfhost")
[ "$data_graph_written" = 'executable written' ]
chmod +x "$test_build/data-graph-selfhost"
"$test_build/data-graph-selfhost"
# `e.algo.graph`: BFS, DFS, topological order and its Cycle, weak and strong components, Dijkstra.
algo_graph_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph/src/main.e" "$repo" x64 linux "$test_build/algo-graph-selfhost")
[ "$algo_graph_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-selfhost"
"$test_build/algo-graph-selfhost"
# `e.data.tree`: an ordered map as a treap keyed by hash priority: ascending iteration, bounds,
# removal with reuse, clear, a set of strings, and two thousand keys.
data_tree_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_tree/src/main.e" "$repo" x64 linux "$test_build/data-tree-selfhost")
[ "$data_tree_written" = 'executable written' ]
chmod +x "$test_build/data-tree-selfhost"
"$test_build/data-tree-selfhost"
# `e.algo.complex` against closed forms: Smith's division, the scaled modulus, both sides of the cut.
algo_complex_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_complex/src/main.e" "$repo" x64 linux "$test_build/algo-complex-selfhost")
[ "$algo_complex_written" = 'executable written' ]
chmod +x "$test_build/algo-complex-selfhost"
"$test_build/algo-complex-selfhost"
# `e.algo.linalg.matrix` and `.tensor`: strided views, multiply, determinant, inverse, reshape.
algo_linalg_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_linalg/src/main.e" "$repo" x64 linux "$test_build/algo-linalg-selfhost")
[ "$algo_linalg_written" = 'executable written' ]
chmod +x "$test_build/algo-linalg-selfhost"
"$test_build/algo-linalg-selfhost"
# `e.text.encoding`: UTF-16 and UTF-32 both ways, BOMs, rejection and replacement, streaming.
text_encoding_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_encoding/src/main.e" "$repo" x64 linux "$test_build/text-encoding-selfhost")
[ "$text_encoding_written" = 'executable written' ]
chmod +x "$test_build/text-encoding-selfhost"
"$test_build/text-encoding-selfhost"
# `e.algo.bignum`: three radices, the four operations, truncating division, gcd, rationals.
algo_bignum_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_bignum/src/main.e" "$repo" x64 linux "$test_build/algo-bignum-selfhost")
[ "$algo_bignum_written" = 'executable written' ]
chmod +x "$test_build/algo-bignum-selfhost"
"$test_build/algo-bignum-selfhost"
# `e.fmt.uri`: RFC 3986 parsing, the section 5.4 resolution examples, normalisation, escapes.
fmt_uri_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_uri/src/main.e" "$repo" x64 linux "$test_build/fmt-uri-selfhost")
[ "$fmt_uri_written" = 'executable written' ]
chmod +x "$test_build/fmt-uri-selfhost"
"$test_build/fmt-uri-selfhost"
# `e.algo.decimal`: exact arithmetic over a 128-bit coefficient, every rounding mode, the edges.
algo_decimal_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_decimal/src/main.e" "$repo" x64 linux "$test_build/algo-decimal-selfhost")
[ "$algo_decimal_written" = 'executable written' ]
chmod +x "$test_build/algo-decimal-selfhost"
"$test_build/algo-decimal-selfhost"
# `e.time.calendar`: weekdays, ISO weeks, month arithmetic with the clamped day, comptime patterns.
time_calendar_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/time_calendar/src/main.e" "$repo" x64 linux "$test_build/time-calendar-selfhost")
[ "$time_calendar_written" = 'executable written' ]
chmod +x "$test_build/time-calendar-selfhost"
"$test_build/time-calendar-selfhost"
# `e.fmt.quoted_printable`: escapes, soft breaks at the limit, strict decoding, one-byte reads.
fmt_quoted_printable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_quoted_printable/src/main.e" "$repo" x64 linux "$test_build/fmt-quoted-printable-selfhost")
[ "$fmt_quoted_printable_written" = 'executable written' ]
chmod +x "$test_build/fmt-quoted-printable-selfhost"
"$test_build/fmt-quoted-printable-selfhost"
# `e.fmt.mime`: media types both ways, the extension table, header blocks with case-folded lookup.
fmt_mime_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_mime/src/main.e" "$repo" x64 linux "$test_build/fmt-mime-selfhost")
[ "$fmt_mime_written" = 'executable written' ]
chmod +x "$test_build/fmt-mime-selfhost"
"$test_build/fmt-mime-selfhost"
# `e.fmt.tar`: ustar and PAX archives from Python's tarfile, partial reads, skips, limits, `..` refused.
fmt_tar_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_tar/src/main.e" "$repo" x64 linux "$test_build/fmt-tar-selfhost")
[ "$fmt_tar_written" = 'executable written' ]
chmod +x "$test_build/fmt-tar-selfhost"
"$test_build/fmt-tar-selfhost"
# `e.metrics`: a counter, a gauge, cumulative histogram buckets and the sum under a CAS loop.
metrics_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/metrics/src/main.e" "$repo" x64 linux "$test_build/metrics-selfhost")
[ "$metrics_written" = 'executable written' ]
chmod +x "$test_build/metrics-selfhost"
"$test_build/metrics-selfhost"
# `e.fmt.lzw`: both bit orders, two literal widths, table clears, and bytes matched to a reference.
fmt_lzw_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_lzw/src/main.e" "$repo" x64 linux "$test_build/fmt-lzw-selfhost")
[ "$fmt_lzw_written" = 'executable written' ]
chmod +x "$test_build/fmt-lzw-selfhost"
"$test_build/fmt-lzw-selfhost"
# `e.fs.mmap` and `e.fs.watch`: a file mapped by path both ways, and a directory watch seeing a file added.
# Run from a local filesystem for the same reason `os_watch` is: no inotify event ever
# arrives on the 9p mount.
fs_watch_scratch="${TMPDIR:-/tmp}/neper-fs-watch-scratch"
rm -rf "$fs_watch_scratch"
mkdir -p "$fs_watch_scratch"
fs_mmap_watch_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fs_mmap_watch/src/main.e" "$repo" x64 linux "$test_build/fs-mmap-watch-selfhost")
[ "$fs_mmap_watch_written" = 'executable written' ]
chmod +x "$test_build/fs-mmap-watch-selfhost"
(cd "$fs_watch_scratch" && "$test_build/fs-mmap-watch-selfhost")
# `e.fmt.msgpack`: every family byte-exact against the specification, the tree reader, the typed codec.
fmt_msgpack_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_msgpack/src/main.e" "$repo" x64 linux "$test_build/fmt-msgpack-selfhost")
[ "$fmt_msgpack_written" = 'executable written' ]
chmod +x "$test_build/fmt-msgpack-selfhost"
"$test_build/fmt-msgpack-selfhost"
# `e.crypto.hash`: six digests on four inputs against hashlib, streaming across block edges.
crypto_hash_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_hash/src/main.e" "$repo" x64 linux "$test_build/crypto-hash-selfhost")
[ "$crypto_hash_written" = 'executable written' ]
chmod +x "$test_build/crypto-hash-selfhost"
"$test_build/crypto-hash-selfhost"
# `e.crypto.mac`, `.kdf`, `.random`: RFC 4231, RFC 5869 and RFC 8439 vectors, exhaustion, bounded draws.
crypto_mac_kdf_random_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_mac_kdf_random/src/main.e" "$repo" x64 linux "$test_build/crypto-mac-kdf-random-selfhost")
[ "$crypto_mac_kdf_random_written" = 'executable written' ]
chmod +x "$test_build/crypto-mac-kdf-random-selfhost"
"$test_build/crypto-mac-kdf-random-selfhost"
# `e.crypto.aead`: NIST GCM cases 4 and 16 and RFC 8439's ChaCha20-Poly1305, tampering refused.
crypto_aead_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_aead/src/main.e" "$repo" x64 linux "$test_build/crypto-aead-selfhost")
[ "$crypto_aead_written" = 'executable written' ]
chmod +x "$test_build/crypto-aead-selfhost"
"$test_build/crypto-aead-selfhost"
# `e.crypto.kx`: X25519 against RFC 7748's exchange and 5.2 vector, the zero peer refused.
crypto_kx_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_kx/src/main.e" "$repo" x64 linux "$test_build/crypto-kx-selfhost")
[ "$crypto_kx_written" = 'executable written' ]
chmod +x "$test_build/crypto-kx-selfhost"
"$test_build/crypto-kx-selfhost"
# `e.crypto.sign`: Ed25519 against RFC 8032 7.1 tests 1-3, five refusals.
crypto_sign_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_sign/src/main.e" "$repo" x64 linux "$test_build/crypto-sign-selfhost")
[ "$crypto_sign_written" = 'executable written' ]
chmod +x "$test_build/crypto-sign-selfhost"
"$test_build/crypto-sign-selfhost"
# `e.fmt.pem`: blocks with a suffix and with headers, encode in 64 columns, five refusals.
fmt_pem_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_pem/src/main.e" "$repo" x64 linux "$test_build/fmt-pem-selfhost")
[ "$fmt_pem_written" = 'executable written' ]
chmod +x "$test_build/fmt-pem-selfhost"
"$test_build/fmt-pem-selfhost"
# `e.fmt.asn1`: a DER SEQUENCE walked, decoded and re-encoded, the long length form, six refusals.
fmt_asn1_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_asn1/src/main.e" "$repo" x64 linux "$test_build/fmt-asn1-selfhost")
[ "$fmt_asn1_written" = 'executable written' ]
chmod +x "$test_build/fmt-asn1-selfhost"
"$test_build/fmt-asn1-selfhost"
# `e.fmt.bson`: every carried tag parsed, sized and written back, the typed codec, five refusals.
fmt_bson_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_bson/src/main.e" "$repo" x64 linux "$test_build/fmt-bson-selfhost")
[ "$fmt_bson_written" = 'executable written' ]
chmod +x "$test_build/fmt-bson-selfhost"
"$test_build/fmt-bson-selfhost"
# `e.fmt.protobuf`: every wire type read and written back byte for byte, sizes, four refusals.
fmt_protobuf_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_protobuf/src/main.e" "$repo" x64 linux "$test_build/fmt-protobuf-selfhost")
[ "$fmt_protobuf_written" = 'executable written' ]
chmod +x "$test_build/fmt-protobuf-selfhost"
"$test_build/fmt-protobuf-selfhost"
# `e.algo.deflate`: zlib's dynamic stream inflated whole and in steps, every level round-tripped, three blocks, six refusals.
algo_deflate_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_deflate/src/main.e" "$repo" x64 linux "$test_build/algo-deflate-selfhost")
[ "$algo_deflate_written" = 'executable written' ]
chmod +x "$test_build/algo-deflate-selfhost"
"$test_build/algo-deflate-selfhost"
# `e.fmt.zlib`: Python's stream read back, the writer read back, five refusals.
fmt_zlib_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_zlib/src/main.e" "$repo" x64 linux "$test_build/fmt-zlib-selfhost")
[ "$fmt_zlib_written" = 'executable written' ]
chmod +x "$test_build/fmt-zlib-selfhost"
"$test_build/fmt-zlib-selfhost"
# `e.fmt.gzip`: Python's member with FNAME read back, the writer read back, seven refusals.
fmt_gzip_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_gzip/src/main.e" "$repo" x64 linux "$test_build/fmt-gzip-selfhost")
[ "$fmt_gzip_written" = 'executable written' ]
chmod +x "$test_build/fmt-gzip-selfhost"
"$test_build/fmt-gzip-selfhost"
# `e.fmt.zip`: Python's archive and a hand-built ZIP64 one read, seven refusals.
fmt_zip_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_zip/src/main.e" "$repo" x64 linux "$test_build/fmt-zip-selfhost")
[ "$fmt_zip_written" = 'executable written' ]
chmod +x "$test_build/fmt-zip-selfhost"
"$test_build/fmt-zip-selfhost"
# `e.test.support`: the clock, the scripted reader and writer, the schedule.
test_support_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/test_support/src/main.e" "$repo" x64 linux "$test_build/test-support-selfhost")
[ "$test_support_written" = 'executable written' ]
chmod +x "$test_build/test-support-selfhost"
"$test_build/test-support-selfhost"
# `e.cli`: a command tree parsed, validated, refused and rendered; parse_into over a struct.
cli_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/cli/src/main.e" "$repo" x64 linux "$test_build/cli-selfhost")
[ "$cli_written" = 'executable written' ]
chmod +x "$test_build/cli-selfhost"
"$test_build/cli-selfhost"
# `e.text.template`: interpolation, if/else, repeat with index, seven refusals, the typed path.
text_template_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_template/src/main.e" "$repo" x64 linux "$test_build/text-template-selfhost")
[ "$text_template_written" = 'executable written' ]
chmod +x "$test_build/text-template-selfhost"
"$test_build/text-template-selfhost"
# `e.fmt.multipart`: three parts read in 5-byte chunks, the writer read back, six refusals.
fmt_multipart_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_multipart/src/main.e" "$repo" x64 linux "$test_build/fmt-multipart-selfhost")
[ "$fmt_multipart_written" = 'executable written' ]
chmod +x "$test_build/fmt-multipart-selfhost"
"$test_build/fmt-multipart-selfhost"
# `e.db`: the contract over an in-memory driver, every handle Closed after its close.
db_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/db/src/main.e" "$repo" x64 linux "$test_build/db-selfhost")
[ "$db_written" = 'executable written' ]
chmod +x "$test_build/db-selfhost"
"$test_build/db-selfhost"
# `e.fmt.xml`: a document walked as events, the writer read back, seven refusals.
fmt_xml_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_xml/src/main.e" "$repo" x64 linux "$test_build/fmt-xml-selfhost")
[ "$fmt_xml_written" = 'executable written' ]
chmod +x "$test_build/fmt-xml-selfhost"
"$test_build/fmt-xml-selfhost"
# `e.tz`: the builtin database against zoneinfo, transitions and footer rules, resolve three ways.
tz_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/tz/src/main.e" "$repo" x64 linux "$test_build/tz-selfhost")
[ "$tz_written" = 'executable written' ]
chmod +x "$test_build/tz-selfhost"
"$test_build/tz-selfhost"
# `e.concurrent.queue` and `e.concurrent.map`: try, blocking, timed and closed forms; threads through both.
concurrent_queue_map_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/concurrent_queue_map/src/main.e" "$repo" x64 linux "$test_build/concurrent-queue-map-selfhost")
[ "$concurrent_queue_map_written" = 'executable written' ]
chmod +x "$test_build/concurrent-queue-map-selfhost"
"$test_build/concurrent-queue-map-selfhost"
# `e.fmt.bzip2`: Python's three-block stream read back in pulls, six refusals.
fmt_bzip2_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_bzip2/src/main.e" "$repo" x64 linux "$test_build/fmt-bzip2-selfhost")
[ "$fmt_bzip2_written" = 'executable written' ]
chmod +x "$test_build/fmt-bzip2-selfhost"
"$test_build/fmt-bzip2-selfhost"
# `e.text.io`: lines across LF, CRLF and a bare CR, BOM sniffing, limits, both writers.
text_io_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_io/src/main.e" "$repo" x64 linux "$test_build/text-io-selfhost")
[ "$text_io_written" = 'executable written' ]
chmod +x "$test_build/text-io-selfhost"
"$test_build/text-io-selfhost"
# `e.log` and `e.debug`: the level gate, both sinks, a file read back, the empty backtrace.
log_debug_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/log_debug/src/main.e" "$repo" x64 linux "$test_build/log-debug-selfhost")
[ "$log_debug_written" = 'executable written' ]
chmod +x "$test_build/log-debug-selfhost"
"$test_build/log-debug-selfhost"
# `e.fmt.yaml`: every scalar and collection form, the writer read back, the typed codec, eight refusals.
fmt_yaml_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_yaml/src/main.e" "$repo" x64 linux "$test_build/fmt-yaml-selfhost")
[ "$fmt_yaml_written" = 'executable written' ]
chmod +x "$test_build/fmt-yaml-selfhost"
"$test_build/fmt-yaml-selfhost"
# `e.crypto.x509`: an Ed25519 chain from Python parsed, signatures checked, chains built and refused.
crypto_x509_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_x509/src/main.e" "$repo" x64 linux "$test_build/crypto-x509-selfhost")
[ "$crypto_x509_written" = 'executable written' ]
chmod +x "$test_build/crypto-x509-selfhost"
"$test_build/crypto-x509-selfhost"
# `e.text.unicode`: properties and case mappings against unicodedata, grapheme clusters.
text_unicode_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_unicode/src/main.e" "$repo" x64 linux "$test_build/text-unicode-selfhost")
[ "$text_unicode_written" = 'executable written' ]
chmod +x "$test_build/text-unicode-selfhost"
"$test_build/text-unicode-selfhost"
# `e.text.utf8` (D299): strict decode at every malformed shape, encode at every width boundary, count, byte_offset, lossy and strict iteration.
text_utf8_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_utf8/src/main.e" "$repo" x64 linux "$test_build/text-utf8-selfhost")
[ "$text_utf8_written" = 'executable written' ]
chmod +x "$test_build/text-utf8-selfhost"
"$test_build/text-utf8-selfhost"
# `e.text.normalize` (D301): four forms, ordering, exclusions, Hangul, compatibility mappings, is_normalized in a stack window.
text_normalize_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_normalize/src/main.e" "$repo" x64 linux "$test_build/text-normalize-selfhost")
[ "$text_normalize_written" = 'executable written' ]
chmod +x "$test_build/text-normalize-selfhost"
"$test_build/text-normalize-selfhost"
# One function of 3000 checks (D302): wider than the old small NIR tier and than codegen's old per-function block table.
capacity_wide_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/capacity_wide/src/main.e" "$repo" x64 linux "$test_build/capacity-wide-selfhost")
[ "$capacity_wide_written" = 'executable written' ]
chmod +x "$test_build/capacity-wide-selfhost"
"$test_build/capacity-wide-selfhost"
# `e.fmt.zstd`: libzstd's frames at three levels read back, the writer's frame read back, six refusals.
fmt_zstd_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_zstd/src/main.e" "$repo" x64 linux "$test_build/fmt-zstd-selfhost")
[ "$fmt_zstd_written" = 'executable written' ]
chmod +x "$test_build/fmt-zstd-selfhost"
"$test_build/fmt-zstd-selfhost"
# `e.fmt.html`: a document tokenized and built, serialized and read back, a bare fragment, four refusals.
fmt_html_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_html/src/main.e" "$repo" x64 linux "$test_build/fmt-html-selfhost")
[ "$fmt_html_written" = 'executable written' ]
chmod +x "$test_build/fmt-html-selfhost"
"$test_build/fmt-html-selfhost"
# `e.async`: the loop over two loopback datagram sockets, the os_poller shape.
async_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/async/src/main.e" "$repo" x64 linux "$test_build/async-selfhost")
[ "$async_written" = 'executable written' ]
chmod +x "$test_build/async-selfhost"
"$test_build/async-selfhost"
# `e.fmt.mail`: addresses, lists, dates against email.utils, a message with a folded header, encoded words.
fmt_mail_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_mail/src/main.e" "$repo" x64 linux "$test_build/fmt-mail-selfhost")
[ "$fmt_mail_written" = 'executable written' ]
chmod +x "$test_build/fmt-mail-selfhost"
"$test_build/fmt-mail-selfhost"
# `e.fmt.html.template`: every context escaped, an unsafe scheme replaced, the typed path, six refusals.
fmt_html_template_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_html_template/src/main.e" "$repo" x64 linux "$test_build/fmt-html-template-selfhost")
[ "$fmt_html_template_written" = 'executable written' ]
chmod +x "$test_build/fmt-html-template-selfhost"
"$test_build/fmt-html-template-selfhost"
# `e.os`'s sockets over the loopback interface: a real TCP connection and a real UDP
# datagram inside one process, so nothing waits on a peer that has not already acted.
socket_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_socket/src/main.e" "$repo" x64 linux "$test_build/os-socket-selfhost")
[ "$socket_written" = 'executable written' ]
chmod +x "$test_build/os-socket-selfhost"
"$test_build/os-socket-selfhost"
# `e.os`'s poller over epoll, with two loopback sockets made readable at once so the
# packed event stride is exercised, and a wake timed against the clock.
poller_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_poller/src/main.e" "$repo" x64 linux "$test_build/os-poller-selfhost")
[ "$poller_written" = 'executable written' ]
chmod +x "$test_build/os-poller-selfhost"
"$test_build/os-poller-selfhost"
# `e.os`'s file mapping: a file read through memory, written through memory, and the change
# then seen by an ordinary read -- which is what says a mapping is the file and not a copy.
# Dropping MAP_FIXED here is a segmentation fault rather than a wrong answer, since the
# pointer would still address the reservation the mapping was meant to replace.
mapping_scratch="$test_build/map-scratch"
mkdir -p "$mapping_scratch"
mapping_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_mapping/src/main.e" "$repo" x64 linux "$test_build/os-mapping-selfhost")
[ "$mapping_written" = 'executable written' ]
chmod +x "$test_build/os-mapping-selfhost"
(cd "$mapping_scratch" && "$test_build/os-mapping-selfhost")
# `e.os`'s directory watch over inotify. The change is made before the read, so the event has
# to have been queued from the watch's opening rather than from the read.
#
# Not run under $test_build: on this machine the repository is a 9p mount, where
# `inotify_add_watch` succeeds and returns a descriptor and then no event ever arrives -- so a
# blocking read there waits forever. Measured, and it is why this uses a local filesystem.
watch_scratch="${TMPDIR:-/tmp}/neper-watch-scratch"
rm -rf "$watch_scratch"
mkdir -p "$watch_scratch"
watch_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_watch/src/main.e" "$repo" x64 linux "$test_build/os-watch-selfhost")
[ "$watch_written" = 'executable written' ]
chmod +x "$test_build/os-watch-selfhost"
(cd "$watch_scratch" && "$test_build/os-watch-selfhost")
# `e.os`'s pipe, page size, reservation release and `kill`. The child `kill` needs is this
# fixture's own image spawned again, which is the only program it can be sure exists.
process_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_process/src/main.e" "$repo" x64 linux "$test_build/os-process-selfhost")
[ "$process_written" = 'executable written' ]
chmod +x "$test_build/os-process-selfhost"
"$test_build/os-process-selfhost"
# `e.os`'s file locks. Two separate opens of one path are two separate claims, so one process
# is enough to make a lock actually block -- and the timed case is checked against the clock,
# since neither host has a timeout and the wait is polled.
lock_scratch="$test_build/lock-scratch"
mkdir -p "$lock_scratch"
lock_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_lock/src/main.e" "$repo" x64 linux "$test_build/os-lock-selfhost")
[ "$lock_written" = 'executable written' ]
chmod +x "$test_build/os-lock-selfhost"
(cd "$lock_scratch" && "$test_build/os-lock-selfhost")
# `e.os`'s `spawn_with_options` and its process groups. Every check needs a second program and
# the only one the fixture can be sure exists is itself, so it spawns its own image with a
# marker argument and each mode answers by its exit code.
group_scratch="$test_build/group-scratch"
mkdir -p "$group_scratch"
group_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_group/src/main.e" "$repo" x64 linux "$test_build/os-group-selfhost")
[ "$group_written" = 'executable written' ]
chmod +x "$test_build/os-group-selfhost"
(cd "$group_scratch" && "$test_build/os-group-selfhost")
# `e.os`'s `socket_resolve`. Nothing here needs a network: a literal is parsed and the loopback
# name comes from /etc/hosts. Verified by isolating it -- under `unshare -rn` the fixture still
# passes, and fails at 40 if the hosts path is removed.
resolve_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_resolve/src/main.e" "$repo" x64 linux "$test_build/os-resolve-selfhost")
[ "$resolve_written" = 'executable written' ]
chmod +x "$test_build/os-resolve-selfhost"
"$test_build/os-resolve-selfhost"
# `e.time`'s civil calendar and ISO 8601. The nanosecond counts the fixture checks against were
# computed independently of this code, so a wrong shift or leap rule fails rather than agreeing
# with itself -- truncating instead of flooring fails at 22, and dropping the century rule at 34.
calendar_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/time_calendar/src/main.e" "$repo" x64 linux "$test_build/time-calendar-selfhost")
[ "$calendar_written" = 'executable written' ]
chmod +x "$test_build/time-calendar-selfhost"
"$test_build/time-calendar-selfhost"
# `e.path`'s globs, which are pure matching and touch no filesystem. The boundary between `*`
# and a whole `**` component is what the fixture spends most of itself on -- making `**` consume a
# component instead of matching zero fails at 40.
glob_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/path_glob/src/main.e" "$repo" x64 linux "$test_build/path-glob-selfhost")
[ "$glob_written" = 'executable written' ]
chmod +x "$test_build/path-glob-selfhost"
"$test_build/path-glob-selfhost"
# `e.mem`'s last four. `copy` and `eq` are ordinary generic code -- the first of `e.mem` that is
# not an intrinsic -- while `size_of` and `align_of` cannot be written at all and answer with a
# constant, which the fixture pins by standing one in an array length.
mem_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/mem_slices/src/main.e" "$repo" x64 linux "$test_build/mem-slices-selfhost")
[ "$mem_written" = 'executable written' ]
chmod +x "$test_build/mem-slices-selfhost"
"$test_build/mem-slices-selfhost"
# `e.meta`'s two type-valued questions. What is checked is that the answer is a type in every
# respect -- a comptime argument to anything taking one, including the other question and a generic
# of the caller's own -- since a function that merely returned something would pass a weaker test.
meta_type_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/meta_types/src/main.e" "$repo" x64 linux "$test_build/meta-types-selfhost")
[ "$meta_type_written" = 'executable written' ]
chmod +x "$test_build/meta-types-selfhost"
"$test_build/meta-types-selfhost"
# Reflection inside a generic function, where the type is a parameter rather than a name. A
# generic body is checked once as a template with nothing bound and again per instance, and a
# `meta` question has no answer in the first pass -- so it stands there and the instance settles
# it, which is the deferral `mem.size_of` always had (D136). Every answer here is the instance's
# own: a placeholder that survived would make them all agree.
meta_generic_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/meta_generic/src/main.e" "$repo" x64 linux "$test_build/meta-generic-selfhost")
[ "$meta_generic_written" = 'executable written' ]
chmod +x "$test_build/meta-generic-selfhost"
"$test_build/meta-generic-selfhost"
# A branch whose condition is settled at compile time has one arm, and the other is not code:
# not checked, not emitted. Only a `meta` question settles one (D138). The two things that
# could not be written before are both here -- a walk over `meta.fields` whose arms do not type
# check for each other's field types, and a generic recursing on `meta.element_type` whose base
# case is the arm that disappears. An ordinary runtime `if` is here too, to say what is not
# folded.
fold_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/comptime_branch/src/main.e" "$repo" x64 linux "$test_build/comptime-branch-selfhost")
[ "$fold_written" = 'executable written' ]
chmod +x "$test_build/comptime-branch-selfhost"
"$test_build/comptime-branch-selfhost"
# Section 9's `Field` and `Member` as declared names: a comptime value crossing a call, so the
# callee is instantiated per field and its own return type depends on which one it was given.
# Without the guard that stops inference rebinding such a parameter, this fails at 88.
field_param_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/meta_field_param/src/main.e" "$repo" x64 linux "$test_build/meta-field-param-selfhost")
[ "$field_param_written" = 'executable written' ]
chmod +x "$test_build/meta-field-param-selfhost"
"$test_build/meta-field-param-selfhost"
# `e.os`'s loader. Each host opens the library it already depends on, so nothing needs installing.
# `dlsym` answers with a value of the caller's own `extern fn` type, which is why the fixture calls
# what it gets: a result passed the wrong way would be rubbish rather than a wrong number.
dl_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_dl/src/main.e" "$repo" x64 linux "$test_build/os-dl-selfhost")
[ "$dl_written" = 'executable written' ]
chmod +x "$test_build/os-dl-selfhost"
"$test_build/os-dl-selfhost"
# D131's property: a program that uses `e.os` and opens no library needs no loader. It checks
# itself -- it reads its own image and walks its own program headers -- so nothing here has to
# have `readelf`, and what is asserted is the file that was produced rather than what the
# compiler says about it. Leaving a dead function's references behind fails it at 51.
freestanding_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/freestanding/src/main.e" "$repo" x64 linux "$test_build/freestanding-selfhost")
[ "$freestanding_written" = 'executable written' ]
chmod +x "$test_build/freestanding-selfhost"
"$test_build/freestanding-selfhost"
# `e.fmt.json`'s value tree. The module keeps a number as the lexeme it arrived with, which
# only a round trip can show: a parser that rounded through an `f64` would agree with itself
# everywhere except on what came back out. Escapes, surrogate pairs, duplicate keys, the depth
# limit and RFC 6901 pointers are checked here too.
json_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_json/src/main.e" "$repo" x64 linux "$test_build/fmt-json-selfhost")
[ "$json_written" = 'executable written' ]
chmod +x "$test_build/fmt-json-selfhost"
"$test_build/fmt-json-selfhost"
# `e.fmt.csv` reads a bounded stream and writes a row at a time. The reader is a state
# machine with two bits of memory, so the fixture pins every byte that changes one: the
# quote that opens a field and the quote that is data, the doubled quote, the CRLF that
# terminates and the bare CR that does not. It runs over a real file as well as a slice,
# because a file reports its end by taking nothing rather than by saying so.
csv_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_csv/src/main.e" "$repo" x64 linux "$test_build/fmt-csv-selfhost")
[ "$csv_written" = 'executable written' ]
chmod +x "$test_build/fmt-csv-selfhost"
(cd "$fs_scratch" && "$test_build/fmt-csv-selfhost")
# `e.fmt.ini` both ways over the same text: the document `parse` builds and the stream
# `reader` yields have to agree about what the format says. The format has no standard, so
# what the fixture pins is the choices -- a comment starts a line and nothing else, a
# case-insensitive parse folds the name it stores rather than the comparison it makes later,
# and a value is quoted on the way out only when leaving it bare would not read back as itself.
ini_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_ini/src/main.e" "$repo" x64 linux "$test_build/fmt-ini-selfhost")
[ "$ini_written" = 'executable written' ]
chmod +x "$test_build/fmt-ini-selfhost"
(cd "$fs_scratch" && "$test_build/fmt-ini-selfhost")
# Scalar f32 and f64 end to end. Float values live in general registers as raw bits
# and move into xmm only for the operation itself, so the fixture pins the literals,
# the four operators, IEEE comparison against a NaN, both conversion directions
# including the unsigned 64-bit edge, and float arguments across the convention.
float_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/float_scalar/src/main.e" "$repo" x64 linux "$test_build/float-scalar-selfhost")
[ "$float_written" = 'executable written' ]
chmod +x "$test_build/float-scalar-selfhost"
"$test_build/float-scalar-selfhost"
# The read-only half of `e.str`: comparison, search, trim, split, the integer parsers
# and the forms that allocate. The fixture pins what an empty needle matches, where a
# non-overlapping count stops, that `lines` takes CRLF without inventing a final empty
# line, and that a parser rejects the value one past each end of its range.
str_pure_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/str_pure/src/main.e" "$repo" x64 linux "$test_build/str-pure-selfhost")
[ "$str_pure_written" = 'executable written' ]
chmod +x "$test_build/str-pure-selfhost"
"$test_build/str-pure-selfhost"
# Spec section 9 rules 3 and 5: a missing protocol names what to declare, and a
# protocol whose first parameter is not the type by value is rejected outright.
check_protocol_diagnostic() {
    require_fixture "check/$1"
    if protocol_output=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/$1/src/main.e" "$repo" x64 linux 2>&1); then
        printf '%s\n' "protocol fixture $1 was accepted" >&2
        exit 1
    fi
    case "$protocol_output" in
        *"$2"*) ;;
        *) printf '%s\n' "protocol diagnostic for $1 is wrong: $protocol_output" >&2; exit 1 ;;
    esac
}
check_protocol_diagnostic protocol_missing 'main.e:4:9: error[E-NAME-9999]: no `cmp` protocol for `Point`; declare `fn point_cmp` in the module that declares the type'
check_protocol_diagnostic protocol_signature 'main.e:6:9: error[E-TYPE-0003]: protocol `point_cmp` must take `Point` by value as its first parameter'
check_protocol_diagnostic protocol_no_fallback 'main.e:6:9: error[E-NAME-9999]: no `cmp` protocol for `Pair`; declare `fn pair_cmp` in the module that declares the type'
# `ret` and `try` each reported one message for four different mistakes, so a returned
# value of the wrong type said "ret is not legal inside defer" in a file with no defer.
# Each situation now has its own text, and each is pinned to the message and not merely
# to the rejection.
check_protocol_diagnostic return_type 'main.e:5:9: error[E-TYPE-0002]: the returned value does not have the declared return type'
check_protocol_diagnostic return_count 'main.e:4:5: error[E-TYPE-0003]: ret gives a different number of values than this function returns'
check_protocol_diagnostic return_values_unexpected 'main.e:4:5: error[E-TYPE-0003]: this function returns nothing, so ret takes no value'
check_protocol_diagnostic return_inside_defer 'main.e:5:9: error[E-TYPE-9999]: ret is not legal inside defer'
check_protocol_diagnostic try_cast 'main.e:4:5: error[E-ERROR-9999]: try needs a call that can fail; a conversion cannot'
check_protocol_diagnostic try_not_fallible 'main.e:8:5: error[E-ERROR-9999]: try needs a call whose last result is an err'
check_protocol_diagnostic try_no_propagate 'main.e:8:5: error[E-ERROR-9999]: try propagates an err, so the enclosing function must return one'
check_protocol_diagnostic try_inside_defer 'main.e:9:9: error[E-ERROR-9999]: try is not legal inside defer'
check_protocol_diagnostic aggregate_field_count 'main.e:12:17: error[E-TYPE-9999]: this literal gives a different number of fields than `Bad` declares'
check_protocol_diagnostic break_outside_loop 'main.e:5:5: error[E-TYPE-9999]: break requires an enclosing loop or switch'
# `os.thread_create[Ctx]` binds a context type at the call and checks the entry point
# against it. The checker half only -- the runtime has no `neper_os_thread_create` yet.
thread_accepted=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/thread_create_accepted/src/main.e" "$repo" x64 linux)
[ "$thread_accepted" = 'module check ok' ]
# An aggregate's fields are one contiguous run, and resolving a field's type can
# instantiate a generic, which appends the instance's own fields. That split the run
# being collected, so `Holder` exposed `Box`'s `v` and hid its own `slot` -- the shape
# every `e.sync` lock is written in. Both halves are pinned: the read that has to work,
# and the leaked name that has to stop working.
require_fixture check/generic_instance_field
generic_field_accepted=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/generic_instance_field/src/main.e" "$repo" x64 linux)
[ "$generic_field_accepted" = 'module check ok' ]
check_protocol_diagnostic generic_instance_field_leak 'main.e:8:20: error[E-TYPE-9999]: `Holder` has no field `v`'
check_protocol_diagnostic thread_create_context 'main.e:16:5: error[E-TYPE-0002]: type mismatch: expected `*main.Other`, found `*main.Ctx`'
# `extern fn` bound by `@import`, reached through the image's import table: a
# descriptor and an address table on PE, `DT_NEEDED` and a `GLOB_DAT` slot on ELF.
extern_unbound=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/extern_without_import/src/main.e" "$repo" x64 linux 2>&1 || true)
case "$extern_unbound" in
    *'is an extern fn with no `@import(LIBRARY, SYMBOL)`'*) ;;
    *) printf '%s\n' "an extern with no @import was not reported: $extern_unbound" >&2; exit 1 ;;
esac
extern_path="$test_build/extern-import-selfhost"
extern_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/extern_import/src/main.e" "$repo" x64 linux "$extern_path")
[ "$extern_written" = 'executable written' ]
chmod +x "$extern_path"
"$extern_path"
# A C variadic through the same dynamic slots: `snprintf` with an `f64` in a `...`
# position, which System V wants counted in `al`.
variadic_path="$test_build/extern-variadic-selfhost"
variadic_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/extern_variadic/src/main.e" "$repo" x64 linux "$variadic_path")
[ "$variadic_written" = 'executable written' ]
chmod +x "$variadic_path"
"$variadic_path"
# Section 11's trap protocol: a failed bounds check writes `file:line:col: trap[bounds]:
# <values>` to stderr and exits 134; the same program with no check tripped exits 0.
trap_path="$test_build/trap-bounds-selfhost"
trap_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_bounds/src/main.e" "$repo" x64 linux "$trap_path")
[ "$trap_written" = 'executable written' ]
chmod +x "$trap_path"
trap_status=0
trap_index=$("$trap_path" index 2>&1) || trap_status=$?
[ "$trap_status" -eq 134 ]
case "$trap_index" in
    *'main.e:10:50: trap[bounds]: index 7 out of bounds for len 5'*) ;;
    *) printf '%s\n' "an index past the end did not trap as section 11 says: $trap_index" >&2; exit 1 ;;
esac
trap_status=0
trap_slice=$("$trap_path" slice 2>&1) || trap_status=$?
[ "$trap_status" -eq 134 ]
case "$trap_slice" in
    *'main.e:13:16: trap[bounds]: slice end 7 out of bounds for len 5'*) ;;
    *) printf '%s\n' "a slice past the end did not trap as section 11 says: $trap_slice" >&2; exit 1 ;;
esac
"$trap_path" none
# `unreachable()`: the literal form and the bare form each trap with kind `unreachable`,
# and a function may end in one instead of a `ret`.
unreachable_path="$test_build/trap-unreachable-selfhost"
unreachable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_unreachable/src/main.e" "$repo" x64 linux "$unreachable_path")
[ "$unreachable_written" = 'executable written' ]
chmod +x "$unreachable_path"
unreachable_status=0
unreachable_message=$("$unreachable_path" message 2>&1) || unreachable_status=$?
[ "$unreachable_status" -eq 134 ]
case "$unreachable_message" in
    *'main.e:11:5: trap[unreachable]: n past the table'*) ;;
    *) printf '%s\n' "unreachable(...) did not trap as section 11 says: $unreachable_message" >&2; exit 1 ;;
esac
unreachable_status=0
unreachable_bare=$("$unreachable_path" bare 2>&1) || unreachable_status=$?
[ "$unreachable_status" -eq 134 ]
case "$unreachable_bare" in
    *'main.e:21:9: trap[unreachable]: unreachable() reached'*) ;;
    *) printf '%s\n' "unreachable() did not trap as section 11 says: $unreachable_bare" >&2; exit 1 ;;
esac
"$unreachable_path" none
# The arithmetic rows that trap in every mode: division by zero, the remainder by zero,
# the minimum divided by -1, and a shift count past the width, each with its record.
arithmetic_path="$test_build/trap-arithmetic-selfhost"
arithmetic_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_arithmetic/src/main.e" "$repo" x64 linux "$arithmetic_path")
[ "$arithmetic_written" = 'executable written' ]
chmod +x "$arithmetic_path"
arithmetic_status=0
arithmetic_output=$("$arithmetic_path" zero 2>&1) || arithmetic_status=$?
[ "$arithmetic_status" -eq 134 ]
case "$arithmetic_output" in
    *'main.e:14:17: trap[divide]: 7 / 0 divides by zero'*) ;;
    *) printf '%s\n' "the zero case did not trap as section 11 says: $arithmetic_output" >&2; exit 1 ;;
esac
arithmetic_status=0
arithmetic_output=$("$arithmetic_path" rem 2>&1) || arithmetic_status=$?
[ "$arithmetic_status" -eq 134 ]
case "$arithmetic_output" in
    *'main.e:18:17: trap[divide]: 7 % 0 divides by zero'*) ;;
    *) printf '%s\n' "the rem case did not trap as section 11 says: $arithmetic_output" >&2; exit 1 ;;
esac
arithmetic_status=0
arithmetic_output=$("$arithmetic_path" min 2>&1) || arithmetic_status=$?
[ "$arithmetic_status" -eq 134 ]
case "$arithmetic_output" in
    *'main.e:23:17: trap[divide]: -2147483648 / -1 overflows'*) ;;
    *) printf '%s\n' "the min case did not trap as section 11 says: $arithmetic_output" >&2; exit 1 ;;
esac
arithmetic_status=0
arithmetic_output=$("$arithmetic_path" shift 2>&1) || arithmetic_status=$?
[ "$arithmetic_status" -eq 134 ]
case "$arithmetic_output" in
    *'main.e:27:17: trap[shift]: shift by 40 on a width of 32'*) ;;
    *) printf '%s\n' "the shift case did not trap as section 11 says: $arithmetic_output" >&2; exit 1 ;;
esac
"$arithmetic_path" none
# The `enum` row, which traps in every mode: `Kind(x)` naming no member, unsigned and
# signed, and the same casts naming members untouched.
enum_trap_path="$test_build/trap-enum-selfhost"
enum_trap_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_enum/src/main.e" "$repo" x64 linux "$enum_trap_path")
[ "$enum_trap_written" = 'executable written' ]
chmod +x "$enum_trap_path"
enum_trap_status=0
enum_trap_output=$("$enum_trap_path" color 2>&1) || enum_trap_status=$?
[ "$enum_trap_status" -eq 134 ]
case "$enum_trap_output" in
    *'main.e:16:17: trap[enum]: no member of Color has value 7'*) ;;
    *) printf '%s\n' "the color case did not trap as section 11 says: $enum_trap_output" >&2; exit 1 ;;
esac
enum_trap_status=0
enum_trap_output=$("$enum_trap_path" level 2>&1) || enum_trap_status=$?
[ "$enum_trap_status" -eq 134 ]
case "$enum_trap_output" in
    *'main.e:20:17: trap[enum]: no member of Level has value -6'*) ;;
    *) printf '%s\n' "the level case did not trap as section 11 says: $enum_trap_output" >&2; exit 1 ;;
esac
"$enum_trap_path" none
# The `narrow` row: a checked integer cast whose value does not fit, by width, by sign
# and by both, and the meant truncation `T.trunc(x)` that never checks.
narrow_path="$test_build/trap-narrow-selfhost"
narrow_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_narrow/src/main.e" "$repo" x64 linux "$narrow_path")
[ "$narrow_written" = 'executable written' ]
chmod +x "$narrow_path"
narrow_status=0
narrow_output=$("$narrow_path" wide 2>&1) || narrow_status=$?
[ "$narrow_status" -eq 134 ]
case "$narrow_output" in
    *'main.e:15:17: trap[narrow]: 300 does not fit u8'*) ;;
    *) printf '%s\n' "the wide case did not trap as section 11 says: $narrow_output" >&2; exit 1 ;;
esac
narrow_status=0
narrow_output=$("$narrow_path" negative 2>&1) || narrow_status=$?
[ "$narrow_status" -eq 134 ]
case "$narrow_output" in
    *'main.e:20:17: trap[narrow]: -300 does not fit u16'*) ;;
    *) printf '%s\n' "the negative case did not trap as section 11 says: $narrow_output" >&2; exit 1 ;;
esac
narrow_status=0
narrow_output=$("$narrow_path" sign 2>&1) || narrow_status=$?
[ "$narrow_status" -eq 134 ]
case "$narrow_output" in
    *'main.e:24:17: trap[narrow]: 200 does not fit i8'*) ;;
    *) printf '%s\n' "the sign case did not trap as section 11 says: $narrow_output" >&2; exit 1 ;;
esac
narrow_status=0
narrow_output=$("$narrow_path" unsigned 2>&1) || narrow_status=$?
[ "$narrow_status" -eq 134 ]
case "$narrow_output" in
    *'main.e:28:17: trap[narrow]: -298 does not fit usize'*) ;;
    *) printf '%s\n' "the unsigned case did not trap as section 11 says: $narrow_output" >&2; exit 1 ;;
esac
narrow_status=0
narrow_output=$("$narrow_path" same 2>&1) || narrow_status=$?
[ "$narrow_status" -eq 134 ]
case "$narrow_output" in
    *'main.e:32:17: trap[narrow]: 4294967000 does not fit i32'*) ;;
    *) printf '%s\n' "the same case did not trap as section 11 says: $narrow_output" >&2; exit 1 ;;
esac
"$narrow_path" none
# Section 13's failure line: `main` returning an error writes `error: <qualified name>`
# to stderr, for this module's error and for one of `e.os`'s, and exits 1.
failure_path="$test_build/failure-line-selfhost"
failure_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/failure_line/src/main.e" "$repo" x64 linux "$failure_path")
[ "$failure_written" = 'executable written' ]
chmod +x "$failure_path"
failure_status=0
failure_own=$("$failure_path" own 2>&1) || failure_status=$?
[ "$failure_status" -eq 1 ]
[ "$failure_own" = 'error: main.Boom' ]
failure_status=0
failure_os=$("$failure_path" os 2>&1) || failure_status=$?
[ "$failure_status" -eq 1 ]
[ "$failure_os" = 'error: e.os.NotFound' ]
failure_status=0
failure_try=$("$failure_path" try 2>&1) || failure_status=$?
[ "$failure_status" -eq 1 ]
[ "$failure_try" = 'error: main.Tried' ]
failure_none=$("$failure_path" none 2>&1)
[ "$failure_none" = '' ]
# The `tag` row -- a payload read or written under another member's tag -- and the
# float side of `narrow`: NaN and values past the target's range refused.
tag_path="$test_build/trap-tag-selfhost"
tag_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_tag/src/main.e" "$repo" x64 linux "$tag_path")
[ "$tag_written" = 'executable written' ]
chmod +x "$tag_path"
tag_status=0
tag_output=$("$tag_path" tag 2>&1) || tag_status=$?
[ "$tag_status" -eq 134 ]
case "$tag_output" in
    *'main.e:17:17: trap[tag]: Node.Pair read while the tag is 1'*) ;;
    *) printf '%s\n' "the tag case did not trap as section 11 says: $tag_output" >&2; exit 1 ;;
esac
tag_status=0
tag_output=$("$tag_path" write 2>&1) || tag_status=$?
[ "$tag_status" -eq 134 ]
case "$tag_output" in
    *'main.e:22:9: trap[tag]: Node.Lit read while the tag is 0'*) ;;
    *) printf '%s\n' "the write case did not trap as section 11 says: $tag_output" >&2; exit 1 ;;
esac
tag_status=0
tag_output=$("$tag_path" nan 2>&1) || tag_status=$?
[ "$tag_status" -eq 134 ]
case "$tag_output" in
    *'main.e:26:17: trap[narrow]: a float outside i32'*) ;;
    *) printf '%s\n' "the nan case did not trap as section 11 says: $tag_output" >&2; exit 1 ;;
esac
tag_status=0
tag_output=$("$tag_path" big 2>&1) || tag_status=$?
[ "$tag_status" -eq 134 ]
case "$tag_output" in
    *'main.e:31:17: trap[narrow]: a float outside i32'*) ;;
    *) printf '%s\n' "the big case did not trap as section 11 says: $tag_output" >&2; exit 1 ;;
esac
tag_status=0
tag_output=$("$tag_path" negative 2>&1) || tag_status=$?
[ "$tag_status" -eq 134 ]
case "$tag_output" in
    *'main.e:36:17: trap[narrow]: a float outside u16'*) ;;
    *) printf '%s\n' "the negative case did not trap as section 11 says: $tag_output" >&2; exit 1 ;;
esac
tag_status=0
tag_output=$("$tag_path" wide 2>&1) || tag_status=$?
[ "$tag_status" -eq 134 ]
case "$tag_output" in
    *'main.e:41:17: trap[narrow]: a float outside i64'*) ;;
    *) printf '%s\n' "the wide case did not trap as section 11 says: $tag_output" >&2; exit 1 ;;
esac
"$tag_path" none
# The `null` row: a field read or written through a nil pointer, and `*p` read or
# written, each refused; the same through live pointers untouched.
null_path="$test_build/trap-null-selfhost"
null_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_null/src/main.e" "$repo" x64 linux "$null_path")
[ "$null_written" = 'executable written' ]
chmod +x "$null_path"
null_status=0
null_output=$("$null_path" field 2>&1) || null_status=$?
[ "$null_status" -eq 134 ]
case "$null_output" in
    *'main.e:11:35: trap[null]: nil dereferenced as *Point'*) ;;
    *) printf '%s
' "the field case did not trap as section 11 says: $null_output" >&2; exit 1 ;;
esac
null_status=0
null_output=$("$null_path" write 2>&1) || null_status=$?
[ "$null_status" -eq 134 ]
case "$null_output" in
    *'main.e:12:33: trap[null]: nil dereferenced as *Point'*) ;;
    *) printf '%s
' "the write case did not trap as section 11 says: $null_output" >&2; exit 1 ;;
esac
null_status=0
null_output=$("$null_path" deref 2>&1) || null_status=$?
[ "$null_status" -eq 134 ]
case "$null_output" in
    *'main.e:13:31: trap[null]: nil dereferenced as *i32'*) ;;
    *) printf '%s
' "the deref case did not trap as section 11 says: $null_output" >&2; exit 1 ;;
esac
null_status=0
null_output=$("$null_path" store 2>&1) || null_status=$?
[ "$null_status" -eq 134 ]
case "$null_output" in
    *'main.e:34:9: trap[null]: nil dereferenced as *i32'*) ;;
    *) printf '%s
' "the store case did not trap as section 11 says: $null_output" >&2; exit 1 ;;
esac
"$null_path" none
# The `align` row: `simd.load_aligned` and `store_aligned` at an address that is not a
# multiple of the vector's width, each refused with the width named; aligned untouched.
align_path="$test_build/trap-align-selfhost"
align_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_align/src/main.e" "$repo" x64 linux "$align_path")
[ "$align_written" = 'executable written' ]
chmod +x "$align_path"
align_status=0
align_output=$("$align_path" load 2>&1) || align_status=$?
[ "$align_status" -eq 134 ]
case "$align_output" in
    *'main.e:28:13: trap[align]: address not a multiple of 16: '*) ;;
    *) printf '%s
' "the load case did not trap as section 11 says: $align_output" >&2; exit 1 ;;
esac
align_status=0
align_output=$("$align_path" store 2>&1) || align_status=$?
[ "$align_status" -eq 134 ]
case "$align_output" in
    *'main.e:31:5: trap[align]: address not a multiple of 16: '*) ;;
    *) printf '%s
' "the store case did not trap as section 11 says: $align_output" >&2; exit 1 ;;
esac
"$align_path" none
# The `overflow` row: `+ - *` and unary `-` on every width, signed and unsigned, refused
# when the result does not fit; the same in range, and `+%` past the edge, untouched.
overflow_path="$test_build/trap-overflow-selfhost"
overflow_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_overflow/src/main.e" "$repo" x64 linux "$overflow_path")
[ "$overflow_written" = 'executable written' ]
chmod +x "$overflow_path"
overflow_status=0
overflow_output=$("$overflow_path" add32 2>&1) || overflow_status=$?
[ "$overflow_status" -eq 134 ]
case "$overflow_output" in
    *'main.e:14:17: trap[overflow]: i32 + overflows'*) ;;
    *) printf '%s
' "the add32 case did not trap as section 11 says: $overflow_output" >&2; exit 1 ;;
esac
overflow_status=0
overflow_output=$("$overflow_path" sub8 2>&1) || overflow_status=$?
[ "$overflow_status" -eq 134 ]
case "$overflow_output" in
    *'main.e:18:17: trap[overflow]: i8 - overflows'*) ;;
    *) printf '%s
' "the sub8 case did not trap as section 11 says: $overflow_output" >&2; exit 1 ;;
esac
overflow_status=0
overflow_output=$("$overflow_path" mulu16 2>&1) || overflow_status=$?
[ "$overflow_status" -eq 134 ]
case "$overflow_output" in
    *'main.e:22:17: trap[overflow]: u16 * overflows'*) ;;
    *) printf '%s
' "the mulu16 case did not trap as section 11 says: $overflow_output" >&2; exit 1 ;;
esac
overflow_status=0
overflow_output=$("$overflow_path" add64 2>&1) || overflow_status=$?
[ "$overflow_status" -eq 134 ]
case "$overflow_output" in
    *'main.e:26:17: trap[overflow]: i64 + overflows'*) ;;
    *) printf '%s
' "the add64 case did not trap as section 11 says: $overflow_output" >&2; exit 1 ;;
esac
overflow_status=0
overflow_output=$("$overflow_path" subusize 2>&1) || overflow_status=$?
[ "$overflow_status" -eq 134 ]
case "$overflow_output" in
    *'main.e:30:17: trap[overflow]: usize - overflows'*) ;;
    *) printf '%s
' "the subusize case did not trap as section 11 says: $overflow_output" >&2; exit 1 ;;
esac
overflow_status=0
overflow_output=$("$overflow_path" mulusize 2>&1) || overflow_status=$?
[ "$overflow_status" -eq 134 ]
case "$overflow_output" in
    *'main.e:34:17: trap[overflow]: usize * overflows'*) ;;
    *) printf '%s
' "the mulusize case did not trap as section 11 says: $overflow_output" >&2; exit 1 ;;
esac
overflow_status=0
overflow_output=$("$overflow_path" muli64 2>&1) || overflow_status=$?
[ "$overflow_status" -eq 134 ]
case "$overflow_output" in
    *'main.e:38:17: trap[overflow]: i64 * overflows'*) ;;
    *) printf '%s
' "the muli64 case did not trap as section 11 says: $overflow_output" >&2; exit 1 ;;
esac
overflow_status=0
overflow_output=$("$overflow_path" neg 2>&1) || overflow_status=$?
[ "$overflow_status" -eq 134 ]
case "$overflow_output" in
    *'main.e:43:17: trap[overflow]: i16 unary - overflows'*) ;;
    *) printf '%s
' "the neg case did not trap as section 11 says: $overflow_output" >&2; exit 1 ;;
esac
"$overflow_path" none
# `@nocheck { ... }`: the debug-only rows elided inside, a release-mode row still
# trapping inside, and the same operation trapping outside.
# The memory rows in a release build (D355, H03): bounds, null and tag trap with the
# debug record, and `@nocheck` is the one way past them.
release_checks_path="$test_build/release-checks-selfhost"
release_checks_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/release_checks/src/main.e" "$repo" x64 linux "$release_checks_path" --release)
[ "$release_checks_written" = 'executable written' ]
chmod +x "$release_checks_path"
for release_check in 'bounds main.e:22:9: trap[bounds]: index 9 out of bounds for len 8' 'null main.e:26:16: trap[null]: nil dereferenced' 'tag main.e:31:23: trap[tag]: Node.Lit read while the tag is 0'; do
    release_check_mode=${release_check%% *}
    release_check_text=${release_check#* }
    release_check_status=0
    release_check_output=$("$release_checks_path" "$release_check_mode" 2>&1) || release_check_status=$?
    [ "$release_check_status" -eq 134 ]
    case "$release_check_output" in
        *"$release_check_text"*) ;;
        *) printf '%s
' "the $release_check_mode row did not trap in release: $release_check_output" >&2; exit 1 ;;
    esac
done
release_checks_quiet=$("$release_checks_path" quiet 2>&1)
[ "$release_checks_quiet" = '' ]
# Bounds checks under a proof (D356): `--stats` counts the ones left out, the
# unproven access past the end still traps, and the other shapes keep their checks.
bounds_proof_path="$test_build/bounds-proof-selfhost"
bounds_proof_stats=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/bounds_proof/src/main.e" "$repo" x64 linux "$bounds_proof_path" --release --stats 2>&1)
chmod +x "$bounds_proof_path"
bounds_elided=$(printf '%s\n' "$bounds_proof_stats" | sed -n 's/^bounds checks elided | \([0-9]*\)$/\1/p')
[ -n "$bounds_elided" ] && [ "$bounds_elided" -ge 2 ]
"$bounds_proof_path" none
bounds_shifted_status=0
bounds_shifted=$("$bounds_proof_path" shifted 2>&1) || bounds_shifted_status=$?
[ "$bounds_shifted_status" -eq 134 ]
case "$bounds_shifted" in
    *'main.e:26:26: trap[bounds]: index 5 out of bounds for len 5'*) ;;
    *) printf '%s\n' "the unproven access did not trap: $bounds_shifted" >&2; exit 1 ;;
esac
"$bounds_proof_path" nested
"$bounds_proof_path" reslice
"$bounds_proof_path" guarded
"$bounds_proof_path" conjunct
"$bounds_proof_path" exit_guard
"$bounds_proof_path" width
"$bounds_proof_path" slack
"$bounds_proof_path" equal
"$bounds_proof_path" aliased
"$bounds_proof_path" field
# The second-local form (D452): the shifted read past the aliased length traps.
bounds_aliased_status=0
bounds_aliased=$("$bounds_proof_path" aliased_shifted 2>&1) || bounds_aliased_status=$?
[ "$bounds_aliased_status" -eq 134 ]
case "$bounds_aliased" in
    *'main.e:280:26: trap[bounds]: index 5 out of bounds for len 5'*) ;;
    *) printf '%s\n' "the access past the aliased length did not trap: $bounds_aliased" >&2; exit 1 ;;
esac
# The field base (D462): the shifted read past the field's length traps, and the loop
# through a pointer that calls before the access keeps its check.
bounds_field_status=0
bounds_field=$("$bounds_proof_path" field_shifted 2>&1) || bounds_field_status=$?
[ "$bounds_field_status" -eq 134 ]
case "$bounds_field" in
    *'main.e:335:26: trap[bounds]: index 5 out of bounds for len 5'*) ;;
    *) printf '%s\n' "the access past the field length did not trap: $bounds_field" >&2; exit 1 ;;
esac
bounds_field_call_status=0
bounds_field_call=$("$bounds_proof_path" field_call_shrinks 2>&1) || bounds_field_call_status=$?
[ "$bounds_field_call_status" -eq 134 ]
case "$bounds_field_call" in
    *'main.e:325:26: trap[bounds]: index 0 out of bounds for len 0'*) ;;
    *) printf '%s\n' "the field access after a call kept no check: $bounds_field_call" >&2; exit 1 ;;
esac
bounds_equal_status=0
bounds_equal=$("$bounds_proof_path" equal_shifted 2>&1) || bounds_equal_status=$?
[ "$bounds_equal_status" -eq 134 ]
case "$bounds_equal" in
    *'main.e:145:30: trap[bounds]: index 5 out of bounds for len 5'*) ;;
    *) printf '%s
' "the access past the equal length did not trap: $bounds_equal" >&2; exit 1 ;;
esac
bounds_slack_status=0
bounds_slack=$("$bounds_proof_path" slack_shifted 2>&1) || bounds_slack_status=$?
[ "$bounds_slack_status" -eq 134 ]
case "$bounds_slack" in
    *'main.e:121:26: trap[bounds]: index 4 out of bounds for len 4'*) ;;
    *) printf '%s
' "the access past the slack did not trap: $bounds_slack" >&2; exit 1 ;;
esac
bounds_exit_status=0
bounds_exit=$("$bounds_proof_path" exit_shifted 2>&1) || bounds_exit_status=$?
[ "$bounds_exit_status" -eq 134 ]
case "$bounds_exit" in
    *'main.e:95:9: trap[bounds]: index 5 out of bounds for len 5'*) ;;
    *) printf '%s\n' "the exit-guard-then-shifted access did not trap: $bounds_exit" >&2; exit 1 ;;
esac
# The guard form (D377): `if at < items.len` proves the block's access; a write of
# the index first keeps the check, which trips at the end.
bounds_guarded_status=0
bounds_guarded=$("$bounds_proof_path" guarded_shifted 2>&1) || bounds_guarded_status=$?
[ "$bounds_guarded_status" -eq 134 ]
case "$bounds_guarded" in
    *'main.e:70:17: trap[bounds]: index 5 out of bounds for len 5'*) ;;
    *) printf '%s\n' "the guarded-then-shifted access did not trap: $bounds_guarded" >&2; exit 1 ;;
esac
# Error detail across a cleanup (D360, H07): a failing close after a failed stat
# leaves the stat's detail to be read, and the next failing cleanup after that read.
error_detail_path="$test_build/error-detail-selfhost"
error_detail_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/error_detail/src/main.e" "$repo" x64 linux "$error_detail_path")
[ "$error_detail_written" = 'executable written' ]
chmod +x "$error_detail_path"
"$error_detail_path"
# By-value snapshots (D358, H05): `f(x, &x)` reads the old `x`, in both modes.
for snapshot_mode in debug release; do
    snapshot_flag=''
    [ "$snapshot_mode" = release ] && snapshot_flag='--release'
    snapshot_path="$test_build/by-value-snapshot-$snapshot_mode-selfhost"
    snapshot_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/by_value_snapshot/src/main.e" "$repo" x64 linux "$snapshot_path" $snapshot_flag)
    [ "$snapshot_written" = 'executable written' ]
    chmod +x "$snapshot_path"
    "$snapshot_path"
done
nocheck_path="$test_build/nocheck-selfhost"
nocheck_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/nocheck/src/main.e" "$repo" x64 linux "$nocheck_path")
[ "$nocheck_written" = 'executable written' ]
chmod +x "$nocheck_path"
nocheck_quiet=$("$nocheck_path" quiet 2>&1)
[ "$nocheck_quiet" = '' ]
nocheck_status=0
nocheck_output=$("$nocheck_path" divide 2>&1) || nocheck_status=$?
[ "$nocheck_status" -eq 134 ]
case "$nocheck_output" in
    *'main.e:36:21: trap[divide]: 7 / 0 divides by zero'*) ;;
    *) printf '%s
' "the divide case of the nocheck fixture went wrong: $nocheck_output" >&2; exit 1 ;;
esac
nocheck_status=0
nocheck_output=$("$nocheck_path" loud 2>&1) || nocheck_status=$?
[ "$nocheck_status" -eq 134 ]
case "$nocheck_output" in
    *'main.e:41:23: trap[overflow]: u8 + overflows'*) ;;
    *) printf '%s
' "the loud case of the nocheck fixture went wrong: $nocheck_output" >&2; exit 1 ;;
esac
"$nocheck_path" none
# The release build: the same program traps on its first `+` in debug and, built with
# `--release`, wraps, truncates, masks and saturates through to exit 0.
release_source="$repo/tests/selfhost/fixtures/link/release_build/src/main.e"
release_debug_path="$test_build/release-build-debug-selfhost"
release_debug_written=$($test_build/neper-self emit-executable "$release_source" "$repo" x64 linux "$release_debug_path")
[ "$release_debug_written" = 'executable written' ]
chmod +x "$release_debug_path"
release_status=0
release_debug_output=$("$release_debug_path" 2>&1) || release_status=$?
[ "$release_status" -eq 134 ]
case "$release_debug_output" in
    *'main.e:14:19: trap[overflow]: u8 + overflows'*) ;;
    *) printf '%s
' "the release fixture did not trap in debug: $release_debug_output" >&2; exit 1 ;;
esac
release_path="$test_build/release-build-selfhost"
release_written=$($test_build/neper-self emit-executable "$release_source" "$repo" x64 linux "$release_path" --release)
[ "$release_written" = 'executable written' ]
chmod +x "$release_path"
release_output=$("$release_path" 2>&1)
[ "$release_output" = '' ]
[ "$(stat -c %s "$release_path")" -lt "$(stat -c %s "$release_debug_path")" ]
# Section 12's incremental rebuild: unchanged sources keep every artifact, a body edit
# behind a signature edge rebuilds only its module and links equal to a clean build,
# and a signature edit rebuilds the dependent too.
incremental_fixture="$repo/tests/selfhost/fixtures/link/incremental"
incremental_scratch="$test_build/incremental-scratch"
incremental_source="$incremental_scratch/src"
incremental_artifacts="$test_build/incremental-artifacts"
rm -rf "$incremental_scratch" "$incremental_artifacts"
mkdir -p "$incremental_source" "$incremental_artifacts"
cp "$incremental_fixture"/src/*.e "$incremental_source/"
incremental_main="$incremental_source/main.e"
incremental_first=$($test_build/neper-self emit-em-all "$incremental_main" "$repo" x64 linux "$incremental_artifacts" --release)
[ "$incremental_first" = 'compiled modules written' ]
incremental_same=$($test_build/neper-self emit-em-all "$incremental_main" "$repo" x64 linux "$incremental_artifacts" --release --incremental)
case "$incremental_same" in *'kept main'*) ;; *) printf %s "unchanged main was not kept: $incremental_same" >&2; echo >&2; exit 1 ;; esac
case "$incremental_same" in *'kept dep'*) ;; *) printf %s "unchanged dep was not kept: $incremental_same" >&2; echo >&2; exit 1 ;; esac
case "$incremental_same" in *'rebuilt'*) printf %s "unchanged sources were rebuilt: $incremental_same" >&2; echo >&2; exit 1 ;; esac
cp "$incremental_fixture/edits/dep_body.e" "$incremental_source/dep.e"
incremental_body=$($test_build/neper-self emit-em-all "$incremental_main" "$repo" x64 linux "$incremental_artifacts" --release --incremental)
case "$incremental_body" in *'kept main'*) ;; *) printf %s "a body edit rebuilt the dependent: $incremental_body" >&2; echo >&2; exit 1 ;; esac
case "$incremental_body" in *'rebuilt dep'*) ;; *) printf %s "a body edit did not rebuild its module: $incremental_body" >&2; echo >&2; exit 1 ;; esac
incremental_linked="$test_build/incremental-linked"
incremental_link_written=$($test_build/neper-self link-em "$incremental_linked" "$incremental_artifacts/main.x64-linux.em" "$incremental_artifacts/dep.x64-linux.em" "$incremental_artifacts/e.os.x64-linux.em" "$incremental_artifacts/e.mem.x64-linux.em")
[ "$incremental_link_written" = 'artifact executable written' ]
chmod +x "$incremental_linked"
incremental_status=0
"$incremental_linked" || incremental_status=$?
[ "$incremental_status" -eq 8 ]
incremental_clean="$test_build/incremental-clean"
incremental_clean_written=$($test_build/neper-self emit-executable "$incremental_main" "$repo" x64 linux "$incremental_clean" --release)
[ "$incremental_clean_written" = 'executable written' ]
cmp "$incremental_linked" "$incremental_clean"
cp "$incremental_fixture/edits/dep_inlined.e" "$incremental_source/dep.e"
incremental_inlined=$($test_build/neper-self emit-em-all "$incremental_main" "$repo" x64 linux "$incremental_artifacts" --release --incremental)
case "$incremental_inlined" in *'rebuilt main'*) ;; *) printf %s "a body edit behind a body edge did not rebuild the dependent: $incremental_inlined" >&2; echo >&2; exit 1 ;; esac
case "$incremental_inlined" in *'rebuilt dep'*) ;; *) printf %s "a body edit behind a body edge did not rebuild its module: $incremental_inlined" >&2; echo >&2; exit 1 ;; esac
incremental_inlined_written=$($test_build/neper-self link-em "$incremental_linked" "$incremental_artifacts/main.x64-linux.em" "$incremental_artifacts/dep.x64-linux.em" "$incremental_artifacts/e.os.x64-linux.em" "$incremental_artifacts/e.mem.x64-linux.em")
[ "$incremental_inlined_written" = 'artifact executable written' ]
incremental_status=0
"$incremental_linked" || incremental_status=$?
[ "$incremental_status" -eq 9 ]
cp "$incremental_fixture/edits/dep_signature.e" "$incremental_source/dep.e"
cp "$incremental_fixture/edits/main_signature.e" "$incremental_main"
incremental_signature=$($test_build/neper-self emit-em-all "$incremental_main" "$repo" x64 linux "$incremental_artifacts" --release --incremental)
case "$incremental_signature" in *'rebuilt main'*) ;; *) printf %s "a signature edit did not rebuild the dependent: $incremental_signature" >&2; echo >&2; exit 1 ;; esac
case "$incremental_signature" in *'rebuilt dep'*) ;; *) printf %s "a signature edit did not rebuild its module: $incremental_signature" >&2; echo >&2; exit 1 ;; esac
case "$incremental_signature" in *'kept e.os'*) ;; *) printf %s "an untouched module was rebuilt: $incremental_signature" >&2; echo >&2; exit 1 ;; esac
# A hot build (D319): `emit-executable --incremental` settles the keep set, writes each
# fresh module's artifact under `.neper/<mode>/em/` and links the image from every
# artifact; a warm one and one after a body edit are each the clean build's image.
hot_fixture="$repo/tests/selfhost/fixtures/link/incremental"
hot_scratch="$test_build/hot-scratch"
hot_source="$hot_scratch/src"
rm -rf "$hot_scratch"
mkdir -p "$hot_source"
cp "$hot_fixture"/src/*.e "$hot_source/"
hot_main="$hot_source/main.e"
for hot_mode in --release --time; do
    hot_exe="$test_build/hot-built$hot_mode"
    hot_clean="$test_build/hot-clean$hot_mode"
    cp "$hot_fixture/src/dep.e" "$hot_source/dep.e"
    hot_first=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)
    [ "$hot_first" = 'executable written' ]
    hot_clean_written=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_clean" $hot_mode 2>/dev/null)
    [ "$hot_clean_written" = 'executable written' ]
    cmp "$hot_exe" "$hot_clean"
    hot_warm=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)
    [ "$hot_warm" = 'executable written' ]
    # The manifest says what the warm build kept and why (D363, H14): everything, stable.
    hot_manifest_mode=debug
    [ "$hot_mode" = --release ] && hot_manifest_mode=release
    hot_manifest="$hot_scratch/.neper/$hot_manifest_mode/build-manifest.json"
    python3 "$repo/scripts/check_incremental.py" "$hot_manifest" main=kept:stable dep=kept:stable e.os=kept:stable work.bodies_checked=0 work.modules_lowered=0 work.functions_lowered=0 work.declarations_checked=29
    cmp "$hot_exe" "$hot_clean"
    # Trivia apart from identity (D504, H14): a comment edit on its own line keeps every module.
    cp "$hot_fixture/edits/dep_comment.e" "$hot_source/dep.e"
    [ "$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)" = 'executable written' ]
    python3 "$repo/scripts/check_incremental.py" "$hot_manifest" main=kept:stable dep=kept:stable
    cmp "$hot_exe" "$hot_clean"
    # The kept module's input digest is the edited bytes' own (D507, H15).
    python3 -c "import json,sys,hashlib; m=json.load(open(sys.argv[1])); want=hashlib.sha256(open(sys.argv[2],'rb').read()).hexdigest(); sys.exit(0 if any(i['source']['path']=='dep.e' and i['sha256']==want for i in m['inputs']) else 1)" "$hot_manifest" "$hot_fixture/edits/dep_comment.e"
    cp "$hot_fixture/src/dep.e" "$hot_source/dep.e"
    # An injected key collision (D507, H15): a body edit under --fault-collision still rebuilds dep.
    cp "$hot_fixture/edits/dep_body.e" "$hot_source/dep.e"
    [ "$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental --fault-collision 2>/dev/null)" = 'executable written' ]
    hot_collision_status=0
    "$hot_exe" || hot_collision_status=$?
    [ "$hot_collision_status" -eq 8 ]
    python3 "$repo/scripts/check_incremental.py" "$hot_manifest" main=kept:edges-hold dep=rebuilt:source-changed
    cp "$hot_fixture/src/dep.e" "$hot_source/dep.e"
    [ "$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)" = 'executable written' ]
    cmp "$hot_exe" "$hot_clean"
    # `--stats` on a warm build (D412): the kept modules are parsed for the counts.
    $test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental --stats 2>&1 | grep -q 'bodies checked | 0'
    # The compiler is an identity (D398, H15): a warm build by another compiler
    # executable -- this one with a byte appended -- rebuilds every module as
    # `compiler-changed` and is the clean build; the original then rebuilds them back.
    hot_other="$test_build/hot-other-compiler"
    cp "$test_build/neper-self" "$hot_other"
    printf 'x' >> "$hot_other"
    [ "$("$hot_other" emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    python3 "$repo/scripts/check_incremental.py" "$hot_manifest" main=rebuilt:compiler-changed dep=rebuilt:compiler-changed e.os=rebuilt:compiler-changed
    cmp "$hot_exe" "$hot_clean"
    [ "$("$test_build/neper-self" emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    python3 "$repo/scripts/check_incremental.py" "$hot_manifest" main=rebuilt:compiler-changed dep=rebuilt:compiler-changed
    cmp "$hot_exe" "$hot_clean"
    # The options are part of the identity (D431, H15): another `--inline-cap` rebuilds
    # every module as `options-changed`; the plain warm build after it is the clean one.
    [ "$("$test_build/neper-self" emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental --inline-cap 0 2>/dev/null)" = "executable written" ]
    python3 "$repo/scripts/check_incremental.py" "$hot_manifest" main=rebuilt:options-changed dep=rebuilt:options-changed e.os=rebuilt:options-changed
    [ "$("$test_build/neper-self" emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    python3 "$repo/scripts/check_incremental.py" "$hot_manifest" main=rebuilt:options-changed dep=rebuilt:options-changed
    cmp "$hot_exe" "$hot_clean"
    # A constant's value is a value edge (D492, H14): the module folding on it is rebuilt.
    value_scratch="$test_build/value-scratch"
    rm -rf "$value_scratch"
    cp -r "$repo/tests/selfhost/fixtures/link/incremental_value" "$value_scratch"
    [ "$("$test_build/neper-self" emit-executable "$value_scratch/src/main.e" "$repo" x64 linux "$test_build/value$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    value_status=0
    "$test_build/value$hot_mode" || value_status=$?
    [ "$value_status" -eq 8 ]
    cp "$value_scratch/edits/dep_limit.e" "$value_scratch/src/dep.e"
    [ "$("$test_build/neper-self" emit-executable "$value_scratch/src/main.e" "$repo" x64 linux "$test_build/value$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    python3 "$repo/scripts/check_incremental.py" "$value_scratch/.neper/$hot_manifest_mode/build-manifest.json" main=rebuilt:edge-changed dep=rebuilt:source-changed
    value_status=0
    "$test_build/value$hot_mode" || value_status=$?
    [ "$value_status" -eq 4 ]
    [ "$("$test_build/neper-self" emit-executable "$value_scratch/src/main.e" "$repo" x64 linux "$test_build/value-clean$hot_mode" $hot_mode 2>/dev/null)" = "executable written" ]
    cmp "$test_build/value$hot_mode" "$test_build/value-clean$hot_mode"
    # A layout a body reads is an edge (D493, H14): the module reading it is rebuilt.
    layout_scratch="$test_build/layout-scratch"
    rm -rf "$layout_scratch"
    cp -r "$repo/tests/selfhost/fixtures/link/incremental_layout" "$layout_scratch"
    [ "$("$test_build/neper-self" emit-executable "$layout_scratch/src/main.e" "$repo" x64 linux "$test_build/layout$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    layout_status=0
    "$test_build/layout$hot_mode" || layout_status=$?
    [ "$layout_status" -eq 7 ]
    cp "$layout_scratch/edits/dep_layout.e" "$layout_scratch/src/dep.e"
    [ "$("$test_build/neper-self" emit-executable "$layout_scratch/src/main.e" "$repo" x64 linux "$test_build/layout$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    python3 "$repo/scripts/check_incremental.py" "$layout_scratch/.neper/$hot_manifest_mode/build-manifest.json" main=rebuilt:edge-changed dep=rebuilt:source-changed
    layout_status=0
    "$test_build/layout$hot_mode" || layout_status=$?
    [ "$layout_status" -eq 7 ]
    [ "$("$test_build/neper-self" emit-executable "$layout_scratch/src/main.e" "$repo" x64 linux "$test_build/layout-clean$hot_mode" $hot_mode 2>/dev/null)" = "executable written" ]
    cmp "$test_build/layout$hot_mode" "$test_build/layout-clean$hot_mode"
    # A protocol function's absence is an edge (D494, H14): the instance's module is rebuilt.
    fallback_scratch="$test_build/fallback-scratch"
    rm -rf "$fallback_scratch"
    cp -r "$repo/tests/selfhost/fixtures/link/incremental_fallback" "$fallback_scratch"
    [ "$("$test_build/neper-self" emit-executable "$fallback_scratch/src/main.e" "$repo" x64 linux "$test_build/fallback$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    fallback_status=0
    "$test_build/fallback$hot_mode" || fallback_status=$?
    [ "$fallback_status" -eq 3 ]
    cp "$fallback_scratch/edits/dep_declared.e" "$fallback_scratch/src/dep.e"
    [ "$("$test_build/neper-self" emit-executable "$fallback_scratch/src/main.e" "$repo" x64 linux "$test_build/fallback$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    python3 "$repo/scripts/check_incremental.py" "$fallback_scratch/.neper/$hot_manifest_mode/build-manifest.json" main=rebuilt:edge-changed dep=rebuilt:source-changed
    fallback_status=0
    "$test_build/fallback$hot_mode" || fallback_status=$?
    [ "$fallback_status" -eq 4 ]
    [ "$("$test_build/neper-self" emit-executable "$fallback_scratch/src/main.e" "$repo" x64 linux "$test_build/fallback-clean$hot_mode" $hot_mode 2>/dev/null)" = "executable written" ]
    cmp "$test_build/fallback$hot_mode" "$test_build/fallback-clean$hot_mode"
    # A deleted declaration (D495, H14): the warm build fails as a cold build does.
    deleted_scratch="$test_build/deleted-scratch"
    rm -rf "$deleted_scratch"
    cp -r "$repo/tests/selfhost/fixtures/link/incremental_deleted" "$deleted_scratch"
    [ "$("$test_build/neper-self" emit-executable "$deleted_scratch/src/main.e" "$repo" x64 linux "$test_build/deleted$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    deleted_status=0
    "$test_build/deleted$hot_mode" || deleted_status=$?
    [ "$deleted_status" -eq 5 ]
    cp "$deleted_scratch/edits/dep_without.e" "$deleted_scratch/src/dep.e"
    deleted_status=0
    deleted_output=$("$test_build/neper-self" emit-executable "$deleted_scratch/src/main.e" "$repo" x64 linux "$test_build/deleted$hot_mode" $hot_mode --incremental 2>&1) || deleted_status=$?
    [ "$deleted_status" -eq 1 ]
    echo "$deleted_output" | grep -q 'main.e:7:[0-9]*: error\[E-NAME-9999\]: `dep` has no member `extra`' || { echo "the warm build after a deleted declaration did not name the lost member: $deleted_output" >&2; exit 1; }
    deleted_status=0
    "$test_build/deleted$hot_mode" || deleted_status=$?
    [ "$deleted_status" -eq 5 ]
    # A cyclic artifact reference (D472, H24): distrusted, rebuilt as invalid-artifact, the clean image.
    cycle_scratch="$test_build/cycle-scratch"
    rm -rf "$cycle_scratch"
    cp -r "$repo/tests/selfhost/fixtures/link/artifact_cycle" "$cycle_scratch"
    [ "$("$test_build/neper-self" emit-executable "$cycle_scratch/src/main.e" "$repo" x64 linux "$test_build/cycle$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    [ "$("$test_build/neper-self" emit-executable "$cycle_scratch/src/main.e" "$repo" x64 linux "$test_build/cycle-clean$hot_mode" $hot_mode 2>/dev/null)" = "executable written" ]
    cycle_manifest="$cycle_scratch/.neper/$hot_manifest_mode/build-manifest.json"
    cycle_ring="$cycle_scratch/.neper/$hot_manifest_mode/em/ring.x64-linux.em"
    cycle_main="$cycle_scratch/.neper/$hot_manifest_mode/em/main.x64-linux.em"
    python3 "$repo/benchmarks/fuzz/corrupt.py" cycle "$cycle_ring" e.os main
    cycle_link_status=0
    "$test_build/neper-self" link-em "$test_build/cycle-link$hot_mode" "$cycle_main" "$cycle_ring" >/dev/null 2>&1 || cycle_link_status=$?
    [ "$cycle_link_status" -le 2 ]
    [ "$("$test_build/neper-self" emit-executable "$cycle_scratch/src/main.e" "$repo" x64 linux "$test_build/cycle$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    cmp -s "$test_build/cycle$hot_mode" "$test_build/cycle-clean$hot_mode"
    python3 "$repo/scripts/check_incremental.py" "$cycle_manifest" 'main=kept:edges-hold' 'ring=rebuilt:invalid-artifact'
    python3 "$repo/benchmarks/fuzz/corrupt.py" cycle "$cycle_main" ring main
    [ "$("$test_build/neper-self" emit-executable "$cycle_scratch/src/main.e" "$repo" x64 linux "$test_build/cycle$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    cmp -s "$test_build/cycle$hot_mode" "$test_build/cycle-clean$hot_mode"
    python3 "$repo/scripts/check_incremental.py" "$cycle_manifest" 'main=rebuilt:invalid-artifact' 'ring=kept:stable'
    # The manifest as the anchor (D473, H24): a rewritten artifact, no cycle, is invalid-artifact.
    python3 "$repo/benchmarks/fuzz/corrupt.py" cycle "$cycle_ring" e.os e.io
    [ "$("$test_build/neper-self" emit-executable "$cycle_scratch/src/main.e" "$repo" x64 linux "$test_build/cycle$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    cmp -s "$test_build/cycle$hot_mode" "$test_build/cycle-clean$hot_mode"
    python3 "$repo/scripts/check_incremental.py" "$cycle_manifest" 'main=kept:edges-hold' 'ring=rebuilt:invalid-artifact'
    python3 -c "import json,re,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if all(re.fullmatch('[0-9a-f]{8}', e.get('artifact_crc32c','')) for e in d['incremental']) else 1)" "$cycle_manifest"
    [ "$("$test_build/neper-self" emit-executable "$cycle_scratch/src/main.e" "$repo" x64 linux "$test_build/cycle$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    python3 "$repo/scripts/check_incremental.py" "$cycle_manifest" 'main=kept:stable' 'ring=kept:stable'
    # The unsafe inventory rides in the artifact (D457): warm and cold manifests agree.
    inventory_scratch="$test_build/inventory-scratch"
    rm -rf "$inventory_scratch"
    cp -r "$repo/tests/conformance/tools/manifest_unsafe" "$inventory_scratch"
    [ "$("$test_build/neper-self" emit-executable "$inventory_scratch/src/main.e" "$repo" x64 linux "$test_build/inventory$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1]))['unsafe']))" "$inventory_scratch/.neper/$hot_manifest_mode/build-manifest.json" > "$test_build/inventory-cold.json"
    [ "$("$test_build/neper-self" emit-executable "$inventory_scratch/src/main.e" "$repo" x64 linux "$test_build/inventory$hot_mode" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1]))['unsafe']))" "$inventory_scratch/.neper/$hot_manifest_mode/build-manifest.json" > "$test_build/inventory-warm.json"
    cmp -s "$test_build/inventory-cold.json" "$test_build/inventory-warm.json"
    grep -q '"nocheck"' "$test_build/inventory-warm.json"
    # A write that dies (D435, H24): the second module's artifact write dies after
    # staging; the warm build after it rebuilds that module alone and is the clean build.
    cp "$hot_fixture/src/dep.e" "$hot_source/dep.e"
    rm -rf "$hot_scratch/.neper"
    hot_fault_status=0
    hot_fault_output=$("$test_build/neper-self" emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental --fault-write 1 2>&1) || hot_fault_status=$?
    [ "$hot_fault_status" -eq 1 ] || { echo "a build with an injected write fault exited $hot_fault_status, not 1" >&2; exit 1; }
    case "$hot_fault_output" in *"made to fail by --fault-write"*) ;; *) echo "a build with an injected write fault did not say so: $hot_fault_output" >&2; exit 1 ;; esac
    [ -n "$(find "$hot_scratch/.neper" -name '*.tmp')" ] || { echo "the injected write fault left no staged file" >&2; exit 1; }
    [ "$("$test_build/neper-self" emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)" = "executable written" ]
    python3 "$repo/scripts/check_incremental.py" "$hot_manifest" main=kept:edges-hold dep=rebuilt:no-artifact
    cmp "$hot_exe" "$hot_clean"
    # A damaged cache (D343, H24): a truncated artifact, a stray `.tmp` of a write that
    # died, and an artifact with bytes flipped behind a valid checksum are each rebuilt
    # or ignored, and the build is the clean build; the `.tmp` is never read.
    hot_artifact=$(find "$hot_scratch/.neper" -name 'dep.*.em' | head -1)
    [ -n "$hot_artifact" ]
    for damage in truncate flip; do
        python3 "$repo/benchmarks/fuzz/corrupt.py" $damage "$hot_artifact"
        printf 'a write that died' > "$hot_artifact.tmp"
        hot_damaged=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)
        [ "$hot_damaged" = 'executable written' ]
        cmp "$hot_exe" "$hot_clean"
        # The manifest names the damage (D368, H24): `invalid-artifact`, not `no-artifact`.
        python3 "$repo/scripts/check_incremental.py" "$hot_manifest" dep=rebuilt:invalid-artifact
    done
    # A policy is an identity (D369, H15): a warm `--unchecked` build over checked
    # artifacts rebuilds every module (`mode-changed`) and is the clean unchecked build.
    if [ "$hot_mode" = --release ]; then
        hot_unchecked="$test_build/hot-unchecked"
        hot_unchecked_clean="$test_build/hot-unchecked-clean"
        hot_unchecked_warm=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_unchecked" --release --unchecked --incremental 2>/dev/null)
        [ "$hot_unchecked_warm" = 'executable written' ]
        python3 "$repo/scripts/check_incremental.py" "$hot_manifest" main=rebuilt:mode-changed dep=rebuilt:mode-changed
        hot_unchecked_clean_written=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_unchecked_clean" --release --unchecked 2>/dev/null)
        [ "$hot_unchecked_clean_written" = 'executable written' ]
        cmp "$hot_unchecked" "$hot_unchecked_clean"
        hot_rechecked=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" --release --incremental 2>/dev/null)
        [ "$hot_rechecked" = 'executable written' ]
        cmp "$hot_exe" "$hot_clean"
    fi
    # A corrupt artifact named on the command line is E-LINK-0001, exit 1 (D368, H24).
    hot_corrupt="$hot_scratch/corrupt.em"
    cp "$hot_artifact" "$hot_corrupt"
    python3 "$repo/benchmarks/fuzz/corrupt.py" truncate "$hot_corrupt"
    hot_corrupt_status=0
    hot_corrupt_out=$($test_build/neper-self validate-em "$hot_corrupt" 2>&1) || hot_corrupt_status=$?
    [ "$hot_corrupt_status" -eq 1 ]
    case "$hot_corrupt_out" in *E-LINK-0001*) ;; *) echo "corrupt artifact not refused as E-LINK-0001: $hot_corrupt_out"; exit 1;; esac
    cp "$hot_fixture/edits/dep_body.e" "$hot_source/dep.e"
    hot_edited=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)
    [ "$hot_edited" = 'executable written' ]
    chmod +x "$hot_exe"
    hot_status=0
    "$hot_exe" || hot_status=$?
    [ "$hot_status" -eq 8 ]
    # A body edit behind a signature edge (D363): `dep` rebuilt for its source, `main`
    # kept because every edge held, the rest stable.
    python3 "$repo/scripts/check_incremental.py" "$hot_manifest" main=kept:edges-hold dep=rebuilt:source-changed e.os=kept:stable
    hot_clean_edited=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_clean" $hot_mode 2>/dev/null)
    [ "$hot_clean_edited" = 'executable written' ]
    cmp "$hot_exe" "$hot_clean"
    # An edit to the body `main` inlines (D322): a body edge, so the unchanged `main` is
    # parsed and rebuilt only now; then a signature edit, which rebuilds both.
    cp "$hot_fixture/edits/dep_inlined.e" "$hot_source/dep.e"
    hot_inlined=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)
    [ "$hot_inlined" = 'executable written' ]
    chmod +x "$hot_exe"
    hot_status=0
    "$hot_exe" || hot_status=$?
    [ "$hot_status" -eq 9 ]
    hot_clean_inlined=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_clean" $hot_mode 2>/dev/null)
    [ "$hot_clean_inlined" = 'executable written' ]
    cmp "$hot_exe" "$hot_clean"
    cp "$hot_fixture/edits/dep_signature.e" "$hot_source/dep.e"
    cp "$hot_fixture/edits/main_signature.e" "$hot_source/main.e"
    hot_signed=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_exe" $hot_mode --incremental 2>/dev/null)
    [ "$hot_signed" = 'executable written' ]
    chmod +x "$hot_exe"
    hot_status=0
    "$hot_exe" || hot_status=$?
    [ "$hot_status" -eq 10 ]
    hot_clean_signed=$($test_build/neper-self emit-executable "$hot_main" "$repo" x64 linux "$hot_clean" $hot_mode 2>/dev/null)
    [ "$hot_clean_signed" = 'executable written' ]
    cmp "$hot_exe" "$hot_clean"
    cp "$hot_fixture/src/main.e" "$hot_source/main.e"
done
# Nested inlining (D212): a release build copies `leaf.add` into `mid.twice` and that
# into `main`, the trap record names leaf.e through both copies with one frame in
# release and three in debug, and an edit to the leaf's body rebuilds all three.
nested_fixture="$repo/tests/selfhost/fixtures/link/inline_nested"
nested_release="$test_build/inline-nested-release"
nested_release_written=$($test_build/neper-self emit-executable "$nested_fixture/src/main.e" "$repo" x64 linux "$nested_release" --release)
[ "$nested_release_written" = 'executable written' ]
chmod +x "$nested_release"
nested_status=0
"$nested_release" || nested_status=$?
[ "$nested_status" -eq 5 ]
# The relocated build (D337): the same sources at two places, named four ways -- from
# inside each as `src/main.e` and `./src/main.e`, and by absolute path -- are one image,
# and its trap names `src/leaf.e`.
reloc_a="$test_build/relocated-a"
reloc_b="$test_build/relocated-b"
for reloc_dir in "$reloc_a" "$reloc_b"; do
    rm -rf "$reloc_dir"
    mkdir -p "$reloc_dir"
    cp -r "$nested_fixture/src" "$reloc_dir/src"
done
(cd "$reloc_a" && [ "$($test_build/neper-self emit-executable src/main.e "$repo" x64 linux rel --release)" = 'executable written' ])
(cd "$reloc_a" && [ "$($test_build/neper-self emit-executable ./src/main.e "$repo" x64 linux dot --release)" = 'executable written' ])
(cd "$reloc_b" && [ "$($test_build/neper-self emit-executable src/main.e "$repo" x64 linux rel --release)" = 'executable written' ])
(cd "$reloc_b" && [ "$($test_build/neper-self emit-executable "$reloc_b/src/main.e" "$repo" x64 linux abs --release)" = 'executable written' ])
cmp "$reloc_a/rel" "$reloc_a/dot"
cmp "$reloc_a/rel" "$reloc_b/rel"
cmp "$reloc_a/rel" "$reloc_b/abs"
chmod +x "$reloc_b/abs"
reloc_status=0
reloc_output=$("$reloc_b/abs" trap 2>&1) || reloc_status=$?
[ "$reloc_status" -eq 134 ]
case "$reloc_output" in 'src/leaf.e:3:13: trap[unreachable]'*) ;; *) printf %s "the relocated build's trap is not spelled from the project root: $reloc_output" >&2; echo >&2; exit 1 ;; esac
# `-j 1 --perturb` (D331): the inlined release image on one worker, turned around.
nested_jobs="$test_build/inline-nested-release-jobs"
nested_jobs_written=$($test_build/neper-self emit-executable "$nested_fixture/src/main.e" "$repo" x64 linux "$nested_jobs" --release -j 1 --perturb)
[ "$nested_jobs_written" = 'executable written' ]
cmp "$nested_jobs" "$nested_release"
nested_status=0
nested_output=$("$nested_release" trap 2>&1) || nested_status=$?
[ "$nested_status" -eq 134 ]
case "$nested_output" in *'leaf.e:3:13: trap[unreachable]: leaf gave up'*'  at main.main ('*) ;; *) printf %s "the nested release trap did not name leaf.e: $nested_output" >&2; echo >&2; exit 1 ;; esac
case "$nested_output" in *'at mid.'*) printf %s "the nested release build kept a frame it inlined: $nested_output" >&2; echo >&2; exit 1 ;; *) ;; esac
nested_debug="$test_build/inline-nested-debug"
nested_debug_written=$($test_build/neper-self emit-executable "$nested_fixture/src/main.e" "$repo" x64 linux "$nested_debug")
[ "$nested_debug_written" = 'executable written' ]
chmod +x "$nested_debug"
nested_status=0
nested_output=$("$nested_debug" trap 2>&1) || nested_status=$?
[ "$nested_status" -eq 134 ]
case "$nested_output" in *'  at leaf.boom ('*'leaf.e:3)'*'  at mid.fail ('*'mid.e:5)'*'  at main.main ('*'main.e:15)'*) ;; *) printf %s "the nested debug trap did not walk three frames: $nested_output" >&2; echo >&2; exit 1 ;; esac
nested_scratch="$test_build/inline-nested-scratch"
nested_source="$nested_scratch/src"
nested_artifacts="$test_build/inline-nested-artifacts"
rm -rf "$nested_scratch" "$nested_artifacts"
mkdir -p "$nested_source" "$nested_artifacts"
cp "$nested_fixture"/src/*.e "$nested_source/"
nested_main="$nested_source/main.e"
nested_first=$($test_build/neper-self emit-em-all "$nested_main" "$repo" x64 linux "$nested_artifacts" --release)
[ "$nested_first" = 'compiled modules written' ]
cp "$nested_fixture/edits/leaf_body.e" "$nested_source/leaf.e"
nested_edited=$($test_build/neper-self emit-em-all "$nested_main" "$repo" x64 linux "$nested_artifacts" --release --incremental)
case "$nested_edited" in *'rebuilt main'*) ;; *) printf %s "a leaf body edit did not rebuild main through the nested copy: $nested_edited" >&2; echo >&2; exit 1 ;; esac
case "$nested_edited" in *'rebuilt mid'*) ;; *) printf %s "a leaf body edit did not rebuild mid: $nested_edited" >&2; echo >&2; exit 1 ;; esac
case "$nested_edited" in *'rebuilt leaf'*) ;; *) printf %s "a leaf body edit did not rebuild leaf: $nested_edited" >&2; echo >&2; exit 1 ;; esac
case "$nested_edited" in *'kept e.os'*) ;; *) printf %s "an untouched module was rebuilt: $nested_edited" >&2; echo >&2; exit 1 ;; esac
nested_linked="$test_build/inline-nested-linked"
nested_link_written=$($test_build/neper-self link-em "$nested_linked" "$nested_artifacts/main.x64-linux.em" "$nested_artifacts/mid.x64-linux.em" "$nested_artifacts/leaf.x64-linux.em" "$nested_artifacts/e.os.x64-linux.em" "$nested_artifacts/e.mem.x64-linux.em" "$nested_artifacts/e.str.x64-linux.em")
[ "$nested_link_written" = 'artifact executable written' ]
chmod +x "$nested_linked"
nested_status=0
"$nested_linked" || nested_status=$?
[ "$nested_status" -eq 6 ]
# Section 9's compile-time evaluation of a call in a `const` (D218): seven constants
# computed by the interpreter agree with the same functions at run time, one is an
# array length; a call that reaches runtime state, and one that never returns, are
# refused naming the constant.
comptime_call_path="$test_build/comptime-call-selfhost"
comptime_call_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/comptime_call/src/main.e" "$repo" x64 linux "$comptime_call_path")
[ "$comptime_call_written" = 'executable written' ]
chmod +x "$comptime_call_path"
"$comptime_call_path"
check_protocol_diagnostic comptime_call_runtime 'main.e:8:19: error[E-COMPTIME-9999]: constant `CODE` cannot be evaluated at compile time: its call reached a statement it does not evaluate'
check_protocol_diagnostic comptime_call_budget 'main.e:6:11: error[E-COMPTIME-9999]: constant `FOREVER` cannot be evaluated at compile time: its call reached ten million steps'
check_protocol_diagnostic comptime_call_in_type 'main.e:5:28: error[E-COMPTIME-9999]: a constant that calls a function is used in a type'
# `emit-executable --arena SIZE` (D225): the root arena is the size given. Twelve
# mebibytes fit the default and not eight.
arena_path="$test_build/arena-size-selfhost"
arena_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/arena_size/src/main.e" "$repo" x64 linux "$arena_path")
[ "$arena_written" = 'executable written' ]
chmod +x "$arena_path"
"$arena_path"
arena_small_path="$test_build/arena-size-8m-selfhost"
arena_small_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/arena_size/src/main.e" "$repo" x64 linux "$arena_small_path" --arena 8m)
[ "$arena_small_written" = 'executable written' ]
chmod +x "$arena_small_path"
arena_small_status=0
arena_small_output=$("$arena_small_path" 2>&1) || arena_small_status=$?
[ "$arena_small_status" -eq 1 ]
case "$arena_small_output" in *'error: e.mem.Exhausted'*) ;; *) printf '%s
' "an arena of eight mebibytes held twelve: $arena_small_output" >&2; exit 1 ;; esac
# docs/tooling.md sections 4 and 9 (D227): `tokens --json` and `parse --json` against the
# conformance corpus, byte for byte, with the exit status the result record carries.
conformance_root="$repo/tests/conformance"
for conformance_case in 'tokens every_kind 0' 'tokens hostile 1' 'parse every_kind 0' 'parse recovery 1' 'parse two_errors 1' 'parse barrier 1'; do
    set -- $conformance_case
    conformance_actual="$test_build/conformance-$1-$2.jsonl"
    conformance_status=0
    $test_build/neper-self "$1" --json --path "$2.e" "$conformance_root/$1/$2.e" > "$conformance_actual" || conformance_status=$?
    [ "$conformance_status" -eq "$3" ]
    cmp -s "$conformance_actual" "$conformance_root/$1/$2.expected.jsonl" || { printf '%s
' "$1 --json on $2.e differs from the conformance corpus" >&2; exit 1; }
done
# `-` reads stdin under `--path` (D289): a fixture piped in with its basename as the
# identity is its own golden, for tokens, parse and fmt; `-` without `--path` is usage.
# `--overlay PATH=FILE` (D502, H15): a module's text from another file, the tree untouched.
overlay_scratch="$test_build/overlay-scratch"
rm -rf "$overlay_scratch"
cp -r "$repo/tests/selfhost/fixtures/link/incremental_value" "$overlay_scratch"
[ "$("$test_build/neper-self" emit-executable "$overlay_scratch/src/main.e" "$repo" x64 linux "$test_build/overlay" --overlay "dep.e=$overlay_scratch/edits/dep_limit.e" 2>/dev/null)" = "executable written" ]
overlay_status=0
"$test_build/overlay" || overlay_status=$?
[ "$overlay_status" -eq 4 ]
cmp -s "$overlay_scratch/src/dep.e" "$repo/tests/selfhost/fixtures/link/incremental_value/src/dep.e"
python3 -c "import json,sys,hashlib; m=json.load(open(sys.argv[1])); want=hashlib.sha256(open(sys.argv[2],'rb').read()).hexdigest(); sys.exit(0 if any(i['source']['path']=='dep.e' and i['sha256']==want for i in m['inputs']) else 1)" "$overlay_scratch/.neper/debug/build-manifest.json" "$overlay_scratch/edits/dep_limit.e"
[ "$("$test_build/neper-self" emit-executable "$overlay_scratch/src/main.e" "$repo" x64 linux "$test_build/overlay" 2>/dev/null)" = "executable written" ]
overlay_status=0
"$test_build/overlay" || overlay_status=$?
[ "$overlay_status" -eq 8 ]
# An overlay on a check and on a query (D524, H15).
{ cat "$overlay_scratch/src/main.e"; printf '\nfn again() -> i32 {\n    ret dep.answer()\n}\n'; } > "$overlay_scratch/main_more.e"
[ "$("$test_build/neper-self" uses-file "$overlay_scratch/src/main.e" "$repo" x64 linux --json --symbol dep.answer --overlay "main.e=$overlay_scratch/main_more.e" | grep -c '"record":"use"')" -eq 3 ]
[ "$("$test_build/neper-self" uses-file "$overlay_scratch/src/main.e" "$repo" x64 linux --json --symbol dep.answer | grep -c '"record":"use"')" -eq 2 ]
printf 'const LIMIT: usize = 3usize\n\nfn answer() -> i32 {\n    ret true\n}\n' > "$overlay_scratch/dep_bad.e"
overlay_check_status=0
"$test_build/neper-self" check-file "$overlay_scratch/src/main.e" "$repo" x64 linux --json --overlay "dep.e=$overlay_scratch/dep_bad.e" > "$test_build/overlay-check.jsonl" || overlay_check_status=$?
[ "$overlay_check_status" -eq 1 ]
grep -q 'E-TYPE-0002' "$test_build/overlay-check.jsonl"
[ "$("$test_build/neper-self" check-file "$overlay_scratch/src/main.e" "$repo" x64 linux)" = 'module check ok' ]
# A trap inside a dependency (D503): the run record names the module's source and line.
(cd "$test_build" && ./neper-self run "$conformance_root/tools/run_trap_module/src/main.e" "$repo" x64 linux conformance-tools-run-trap-module.out --json > "conformance-tools-run-trap-module.jsonl") || true
grep -q '"trap":{"kind":"bounds","span":{"source":{"root":"project-src","path":"deep.e"},"byte_start":[0-9]*,"byte_end":[0-9]*,"line":3' "$test_build/conformance-tools-run-trap-module.jsonl"
grep -q '{"function":"deep.pick","source":{"root":"project-src","path":"deep.e"},"line":3}' "$test_build/conformance-tools-run-trap-module.jsonl"
python3 "$repo/scripts/validate_stream.py" "$test_build/conformance-tools-run-trap-module.jsonl"
grep -q '{"function":"main.main","source":{"root":"project-src","path":"main.e"},"line":9}' "$test_build/conformance-tools-run-trap-module.jsonl"
# Provenance through inlining (D519, H19): the release frame at deep.e names deep.pick as inlined_from.
(cd "$test_build" && ./neper-self run "$conformance_root/tools/run_trap_module/src/main.e" "$repo" x64 linux conformance-tools-run-trap-inlined.out --release --json > "conformance-tools-run-trap-inlined.jsonl") || true
grep -q '{"function":"main.main","source":{"root":"project-src","path":"deep.e"},"line":3,"inlined_from":"deep.pick"}' "$test_build/conformance-tools-run-trap-inlined.jsonl"
python3 "$repo/scripts/validate_stream.py" "$test_build/conformance-tools-run-trap-inlined.jsonl"
# The index marks the boundaries a declaration holds (D513, H27).
(cd "$conformance_root/tools/manifest_unsafe" && "$test_build/neper-self" index-file src/main.e "$repo" x64 linux --json > "$test_build/conformance-tools-index-unsafe.jsonl")
cmp -s "$test_build/conformance-tools-index-unsafe.jsonl" "$conformance_root/tools/index_unsafe.expected.jsonl" || { echo "index-file --json over the unsafe fixture differs from the conformance corpus" >&2; exit 1; }
# `-` on `check-file` (D490) and `index` (D488): the module from stdin under its `--path` identity is the file's golden.
stdin_check_status=0
$test_build/neper-self check-file - "$repo" x64 linux --json --path scope.e < "$conformance_root/reject/scope.e" > "$test_build/conformance-stdin-check.jsonl" || stdin_check_status=$?
[ "$stdin_check_status" -eq 1 ]
cmp -s "$test_build/conformance-stdin-check.jsonl" "$conformance_root/reject/scope.expected.jsonl" || { echo "check-file --json from stdin differs from the conformance corpus" >&2; exit 1; }
$test_build/neper-self index-file - "$repo" x64 linux --json --path index.e < "$conformance_root/tools/index.e" > "$test_build/conformance-stdin-index.jsonl"
cmp -s "$test_build/conformance-stdin-index.jsonl" "$conformance_root/tools/index.expected.jsonl" || { echo "index --json from stdin differs from the conformance corpus" >&2; exit 1; }
$test_build/neper-self tokens --json --path every_kind.e - < "$conformance_root/tokens/every_kind.e" > "$test_build/conformance-stdin-tokens.jsonl"
cmp -s "$test_build/conformance-stdin-tokens.jsonl" "$conformance_root/tokens/every_kind.expected.jsonl" || { printf '%s
' "tokens --json from stdin differs from the conformance corpus" >&2; exit 1; }
$test_build/neper-self parse --json --path every_kind.e - < "$conformance_root/parse/every_kind.e" > "$test_build/conformance-stdin-parse.jsonl"
cmp -s "$test_build/conformance-stdin-parse.jsonl" "$conformance_root/parse/every_kind.expected.jsonl" || { printf '%s
' "parse --json from stdin differs from the conformance corpus" >&2; exit 1; }
$test_build/neper-self fmt-file - --json --path fmt.e < "$conformance_root/tools/fmt.e" > "$test_build/conformance-stdin-fmt.jsonl"
cmp -s "$test_build/conformance-stdin-fmt.jsonl" "$conformance_root/tools/fmt.expected.jsonl" || { printf '%s
' "fmt --json from stdin differs from the conformance corpus" >&2; exit 1; }
$test_build/neper-self fmt-file - < "$conformance_root/tools/fmt.e" > "$test_build/conformance-stdin-fmt.e"
cmp -s "$test_build/conformance-stdin-fmt.e" "$conformance_root/tools/fmt.e" || { printf '%s
' "fmt from stdin is not the canonical source" >&2; exit 1; }
stdin_usage_status=0
$test_build/neper-self tokens --json - < "$conformance_root/tokens/every_kind.e" > /dev/null 2>&1 || stdin_usage_status=$?
[ "$stdin_usage_status" -eq 1 ]
# `--absolute-paths` (D290): the operand's absolute spelling as `absolute_path` beside its
# identity and nothing else -- the stream with that field taken out is the golden. An
# absolute operand is spelled as given; a relative one under the current directory.
absolute_status=0
$test_build/neper-self check-file "$conformance_root/reject/scope.e" "$repo" x64 linux --json --absolute-paths > "$test_build/conformance-absolute-check.jsonl" || absolute_status=$?
[ "$absolute_status" -eq 1 ]
grep -q ",\"absolute_path\":\"$conformance_root/reject/scope.e\"" "$test_build/conformance-absolute-check.jsonl" || { printf '%s
' "--absolute-paths did not write the operand's absolute path" >&2; exit 1; }
sed -i "s|,\"absolute_path\":\"$conformance_root/reject/scope.e\"||g" "$test_build/conformance-absolute-check.jsonl"
cmp -s "$test_build/conformance-absolute-check.jsonl" "$conformance_root/reject/scope.expected.jsonl" || { printf '%s
' "--absolute-paths changed more than absolute_path on check" >&2; exit 1; }
cp "$conformance_root/tokens/every_kind.e" "$test_build/every_kind.e"
(cd "$test_build" && ./neper-self tokens --json --absolute-paths every_kind.e > "conformance-absolute-tokens.jsonl")
grep -q ",\"absolute_path\":\"$test_build/every_kind.e\"" "$test_build/conformance-absolute-tokens.jsonl" || { printf '%s
' "--absolute-paths did not spell a relative operand under the current directory" >&2; exit 1; }
sed -i "s|,\"absolute_path\":\"$test_build/every_kind.e\"||g" "$test_build/conformance-absolute-tokens.jsonl"
# `.` and `..` collapsed in `absolute_path` (D489).
(cd "$test_build" && ./neper-self tokens --json --absolute-paths "./../$(basename "$test_build")/every_kind.e" > "conformance-absolute-dots.jsonl")
grep -q ",\"absolute_path\":\"$test_build/every_kind.e\"" "$test_build/conformance-absolute-dots.jsonl" || { echo "--absolute-paths did not collapse the . and .. segments of the operand" >&2; exit 1; }
cmp -s "$test_build/conformance-absolute-tokens.jsonl" "$conformance_root/tokens/every_kind.expected.jsonl" || { printf '%s
' "--absolute-paths changed more than absolute_path on tokens" >&2; exit 1; }
# `check-file ... --json` (D228) against accept/ and reject/: a diagnostic record per
# error with its span, the result with the exit status, nothing on stderr.
for conformance_case in 'accept scalar 0' 'accept aggregate 0' 'reject enum_values 1' 'reject lexical 1' 'reject when_local 1' 'reject scope 1' 'reject barrier 1' 'reject module_missing 1' 'reject qualifier_collision 1' 'reject reserved_local 1' 'reject try_not_fallible 1' 'reject return_count 1' 'reject generic_inference 1' 'reject condition_type 1' 'reject atomic_ordering 1' 'reject nesting 1' 'accept safety 0' 'reject safety_use_after_move 1' 'reject safety_cleanup_forgotten 1' 'reject safety_overwrite 1' 'reject safety_undef 1' 'reject safety_unchecked 1' 'reject safety_deferred_consumed 1' 'reject safety_moved_in_loop 1' 'reject safety_partial_move 1' 'reject safety_cleanup_signature 1' 'reject safety_borrowed 1' 'reject safety_borrowed_return 1' 'reject safety_copy 1' 'reject safety_copy_elements 1' 'reject safety_copy_generic 1' 'reject safety_handle_leak 1' 'reject safety_moved_while_borrowed 1' 'reject safety_arena_moved 1' 'reject safety_pushed_twice 1' 'accept regions 0' 'reject regions_reset 1' 'reject regions_view 1' 'reject regions_join 1' 'reject safety_detached_frame 1' 'reject safety_thread_shared 1' 'reject safety_guard_leak 1' 'reject safety_thread_alias 1' 'reject regions_alias 1' 'reject safety_thread_slice 1' 'reject type_mismatch 1' 'reject safety_thread_field 1' 'reject safety_thread_reassign 1' 'reject safety_copy_toolchain 1' 'reject safety_rwguard_leak 1' 'reject safety_thread_group_leak 1' 'reject type_mismatch_fix 1' 'reject name_near 1' 'reject member_near 1' 'reject field_near 1' 'reject instance_site 1' 'reject safety_undef_value 1' 'reject type_near 1' 'reject type_mismatch_call 1'; do
    set -- $conformance_case
    conformance_actual="$test_build/conformance-$1-$2.jsonl"
    conformance_stderr="$test_build/conformance-$1-$2.stderr"
    conformance_status=0
    $test_build/neper-self check-file "$conformance_root/$1/$2.e" "$repo" x64 linux --json > "$conformance_actual" 2> "$conformance_stderr" || conformance_status=$?
    [ "$conformance_status" -eq "$3" ]
    [ ! -s "$conformance_stderr" ]
    cmp -s "$conformance_actual" "$conformance_root/$1/$2.expected.jsonl" || { printf '%s
' "check-file --json on $1/$2.e differs from the conformance corpus" >&2; exit 1; }
done
# A reject fixture that is a project (D297): a cycle and an ambiguous variant need
# more than one module, so the operand is `reject/<name>/src/main.e`.
for reject_project in module_cycle module_variants safety_opaque; do
    reject_project_status=0
    $test_build/neper-self check-file "$conformance_root/reject/$reject_project/src/main.e" "$repo" x64 linux --json > "$test_build/conformance-reject-$reject_project.jsonl" || reject_project_status=$?
    [ "$reject_project_status" -eq 1 ]
    cmp -s "$test_build/conformance-reject-$reject_project.jsonl" "$conformance_root/reject/$reject_project.expected.jsonl" || { printf '%s
' "check-file --json on reject/$reject_project differs from the conformance corpus" >&2; exit 1; }
done
# An accept fixture that is a project (D348): a declared resource lives in its own module.
accept_project_status=0
$test_build/neper-self check-file "$conformance_root/accept/safety_resource/src/main.e" "$repo" x64 linux --json > "$test_build/conformance-accept-safety_resource.jsonl" || accept_project_status=$?
[ "$accept_project_status" -eq 0 ]
cmp -s "$test_build/conformance-accept-safety_resource.jsonl" "$conformance_root/accept/safety_resource.expected.jsonl" || { printf '%s
' "check-file --json on accept/safety_resource differs from the conformance corpus" >&2; exit 1; }
# `info --json` (D229): the capability record for this host, byte for byte.
info_actual="$test_build/conformance-tools-info.jsonl"
$test_build/neper-self info --json > "$info_actual"
cmp -s "$info_actual" "$conformance_root/tools/info.x64-linux.expected.jsonl" || { printf '%s
' "info --json differs from the conformance corpus" >&2; exit 1; }
# `check-project --json` (D262): every module under a project's src in byte order, each
# checked in its own process under its path relative to src, one stream; two of the
# fixture's three modules carry an error.
check_project_status=0
$test_build/neper-self check-project "$conformance_root/tools/check_project" "$repo" x64 linux "$test_build" --json > "$test_build/conformance-tools-check-project.jsonl" || check_project_status=$?
[ "$check_project_status" -eq 1 ]
cmp -s "$test_build/conformance-tools-check-project.jsonl" "$conformance_root/tools/check_project.expected.jsonl" || { printf '%s
' "check-project --json differs from the conformance corpus" >&2; exit 1; }
# `--language-version` (D283): the advertised 0.1 is accepted on any command and taken
# off the arguments; another is E-CLI-9999 before any source is read, as a stream under
# `--json` whose header names the command.
$test_build/neper-self info --json --language-version 0.1 > "$test_build/conformance-tools-info-version.jsonl"
cmp -s "$test_build/conformance-tools-info-version.jsonl" "$conformance_root/tools/info.x64-linux.expected.jsonl" || { printf '%s
' "--language-version 0.1 changed the info stream" >&2; exit 1; }
version_status=0
$test_build/neper-self info --json --language-version 9.9 > "$test_build/conformance-tools-info-version.jsonl" || version_status=$?
[ "$version_status" -eq 2 ]
cmp -s "$test_build/conformance-tools-info-version.jsonl" "$conformance_root/tools/info_version.expected.jsonl" || { printf '%s
' "an unadvertised language version is not refused as the conformance corpus says" >&2; exit 1; }
# `emit-executable --json` (D230): the build stream, the executable named as given,
# a rejected program's diagnostics as records; both byte for byte from test_build.
# A build writes `.neper/<mode>/build-manifest.json` under the project root, making the
# directory when it is missing (D254, D287); the repo is the corpus's project root, so
# the mode directory is removed first to prove the build makes it.
rm -rf "$repo/.neper/debug"
for build_case in 'tools/build.e build 0' 'reject/scope.e build_reject 1'; do
    set -- $build_case
    build_status=0
    (cd "$test_build" && ./neper-self emit-executable "$conformance_root/$1" "$repo" x64 linux "conformance-tools-$2.out" --json > "conformance-tools-$2.jsonl") || build_status=$?
    [ "$build_status" -eq "$3" ]
    cmp -s "$test_build/conformance-tools-$2.jsonl" "$conformance_root/tools/$2.expected.jsonl" || { printf '%s
' "emit-executable --json on $1 differs from the conformance corpus" >&2; exit 1; }
done
# The build wrote the file executable (D291): it runs as written, with no chmod first.
[ -x "$test_build/conformance-tools-build.out" ] || { printf '%s
' "the build did not write an executable file" >&2; exit 1; }
"$test_build/conformance-tools-build.out"
# The manifest the build.e build wrote: valid against the schema, naming the executable
# as given with the SHA-256 of the bytes on disk.
python3 "$repo/scripts/validate_stream.py" "$repo/.neper/debug/build-manifest.json" || { printf '%s
' "the build manifest a build writes does not validate against the v1 schema" >&2; exit 1; }
[ -d "$repo/.neper/debug" ] || { printf '%s
' "the build did not make .neper/debug/" >&2; exit 1; }
# The artifact's path is project-relative (D293): the executable was named beside the
# test build directory, and the manifest spells it from the repo.
manifest_artifact=$(sed -n 's/.*"artifacts":\[{"path":"build\/linux\/tests\/selfhost\/conformance-tools-build.out","kind":"executable","target":"x64-linux","sha256":"\([0-9a-f]*\)".*/\1/p' "$repo/.neper/debug/build-manifest.json")
[ "$manifest_artifact" = "$(sha256sum "$test_build/conformance-tools-build.out" | cut -c1-64)" ] || { printf '%s
' "the build manifest does not carry the executable's SHA-256" >&2; exit 1; }
# Reproducible builds (D261): the same source built again is the same bytes, and the
# manifest of the second build carries the same artifact hash as the first -- so a
# manifest is a witness two builds can be compared by, without the executables.
(cd "$test_build" && ./neper-self emit-executable "$conformance_root/tools/build.e" "$repo" x64 linux "conformance-tools-build-again.out" > /dev/null)
cmp -s "$test_build/conformance-tools-build.out" "$test_build/conformance-tools-build-again.out" || { printf '%s
' "the same source built twice is not the same executable" >&2; exit 1; }
# `compare-manifests` (D482): the two builds' manifests agree; debug against release differs.
cp "$repo/.neper/debug/build-manifest.json" "$test_build/manifest-first.json"
manifest_again=$(sed -n 's/.*"artifacts":\[{"path":"build\/linux\/tests\/selfhost\/conformance-tools-build-again.out","kind":"executable","target":"x64-linux","sha256":"\([0-9a-f]*\)".*/\1/p' "$repo/.neper/debug/build-manifest.json")
[ "$manifest_again" = "$manifest_artifact" ] || { printf '%s
' "the second build's manifest does not carry the first build's artifact hash" >&2; exit 1; }
[ "$("$test_build/neper-self" compare-manifests "$test_build/manifest-first.json" "$repo/.neper/debug/build-manifest.json")" = "manifests agree" ] || { echo "the manifests of two builds of the same source differ" >&2; exit 1; }
(cd "$test_build" && ./neper-self emit-executable "$conformance_root/tools/contract.e" "$repo" x64 linux "conformance-tools-compare-debug.out" > /dev/null)
cp "$repo/.neper/debug/build-manifest.json" "$test_build/manifest-debug.json"
(cd "$test_build" && ./neper-self emit-executable "$conformance_root/tools/contract.e" "$repo" x64 linux "conformance-tools-compare-release.out" --release > /dev/null)
"$test_build/neper-self" compare-manifests "$test_build/manifest-debug.json" "$repo/.neper/release/build-manifest.json" --json > "$test_build/conformance-tools-compare-manifests.jsonl"
grep -q '"record":"difference","kind":"mode","name":"","left":"debug","right":"release"' "$test_build/conformance-tools-compare-manifests.jsonl"
grep -q '"record":"difference","kind":"artifact"' "$test_build/conformance-tools-compare-manifests.jsonl"
grep -q '"same":false' "$test_build/conformance-tools-compare-manifests.jsonl"
python3 "$repo/scripts/validate_stream.py" "$test_build/conformance-tools-compare-manifests.jsonl"
# Spec section 2's spelling (D276): `neper build FILE -o OUT --json` from a binary that
# has the toolchain's lib/ beside it is the same stream as the positional form.
rm -rf "$repo/build/linux/short"
mkdir -p "$repo/build/linux/short"
cp -r "$repo/lib" "$repo/build/linux/short/lib"
cp "$test_build/neper-self" "$repo/build/linux/short/neper-self-short"
chmod +x "$repo/build/linux/short/neper-self-short"
(cd "$test_build" && "$repo/build/linux/short/neper-self-short" build "$conformance_root/tools/build.e" -o conformance-tools-build.out --json > "conformance-tools-build-short.jsonl")
cmp -s "$test_build/conformance-tools-build-short.jsonl" "$conformance_root/tools/build.expected.jsonl" || { printf '%s
' "the short build spelling differs from the positional form" >&2; exit 1; }
# `neper test FILE` (D292): the short spelling is the test stream, its WORKDIR
# `.neper/debug/test/` under the operand's project -- the repo here -- made by the command.
rm -rf "$repo/.neper/debug/test"
test_short_status=0
"$repo/build/linux/short/neper-self-short" test "$conformance_root/tools/test.e" > "$test_build/conformance-tools-test-short.jsonl" || test_short_status=$?
[ "$test_short_status" -eq 1 ]
[ -f "$repo/.neper/debug/test/nptest-runner.e" ] || { printf '%s
' "the short test spelling did not work under .neper/debug/test/" >&2; exit 1; }
sed -i -E 's/"duration_ms":[0-9]+/"duration_ms":0/g; s|[^" (]*nptest-runner\.e|nptest-runner.e|g' "$test_build/conformance-tools-test-short.jsonl"
# `test --json --only n1,n2` (D424, H10): the named tests alone.
test_only_status=0
$test_build/neper-self test-file "$conformance_root/tools/test.e" "$repo" x64 linux "$test_build" --json --only arithmetic_holds,reports_a_failure > "$test_build/conformance-tools-test-only.jsonl" || test_only_status=$?
[ "$test_only_status" -eq 1 ]
sed -i 's/"duration_ms":[0-9]*/"duration_ms":0/g' "$test_build/conformance-tools-test-only.jsonl"
cmp -s "$test_build/conformance-tools-test-only.jsonl" "$conformance_root/tools/test_only.expected.jsonl" || { echo "test --json --only differs from the conformance corpus" >&2; exit 1; }
cmp -s "$test_build/conformance-tools-test-short.jsonl" "$conformance_root/tools/test.expected.jsonl" || { printf '%s
' "the short test spelling differs from the positional form" >&2; exit 1; }
# `neper check` and `neper test` with no operand (D294): the project the current
# directory is in, as the project forms, working under its `.neper/debug/<command>/`.
check_short_status=0
(cd "$conformance_root/tools/check_project" && "$repo/build/linux/short/neper-self-short" check > "$test_build/conformance-tools-check-project-short.jsonl") || check_short_status=$?
[ "$check_short_status" -eq 1 ]
cmp -s "$test_build/conformance-tools-check-project-short.jsonl" "$conformance_root/tools/check_project.expected.jsonl" || { printf '%s
' "the operand-less check differs from check-project" >&2; exit 1; }
test_short_project_status=0
(cd "$conformance_root/tools/test_project" && "$repo/build/linux/short/neper-self-short" test > "$test_build/conformance-tools-test-project-short.jsonl") || test_short_project_status=$?
[ "$test_short_project_status" -eq 1 ]
sed -i 's/"duration_ms":[0-9]*/"duration_ms":0/g' "$test_build/conformance-tools-test-project-short.jsonl"
cmp -s "$test_build/conformance-tools-test-project-short.jsonl" "$conformance_root/tools/test_project.expected.jsonl" || { printf '%s
' "the operand-less test differs from test-project" >&2; exit 1; }
# `fmt FILE` formats the file in place, and `fmt` / `fmt --check` with no operand cover
# every `.e` under the project's src/ and lib/ (D295): a project of one non-canonical
# file fails the check, is formatted to the corpus's canonical text, then passes.
rm -rf "$test_build/fmt_project"
mkdir -p "$test_build/fmt_project/src"
cp "$conformance_root/format/layout.e" "$test_build/fmt_project/src/layout.e"
fmt_check_status=0
(cd "$test_build/fmt_project" && "$repo/build/linux/short/neper-self-short" fmt --check > /dev/null 2>&1) || fmt_check_status=$?
[ "$fmt_check_status" -eq 1 ]
(cd "$test_build/fmt_project" && "$repo/build/linux/short/neper-self-short" fmt)
cmp -s "$test_build/fmt_project/src/layout.e" "$conformance_root/format/layout.expected.e" || { printf '%s
' "fmt over the project did not write the canonical text" >&2; exit 1; }
(cd "$test_build/fmt_project" && "$repo/build/linux/short/neper-self-short" fmt --check)
cp "$conformance_root/format/layout.e" "$test_build/fmt-in-place.e"
"$repo/build/linux/short/neper-self-short" fmt "$test_build/fmt-in-place.e"
cmp -s "$test_build/fmt-in-place.e" "$conformance_root/format/layout.expected.e" || { printf '%s
' "fmt FILE did not format the file in place" >&2; exit 1; }
# `index-project --json` (D298): every module under a project's src and lib, each
# indexed under its path from the root, one stream; and `neper index` with no operand
# from inside the project is the same stream.
$test_build/neper-self index-project "$conformance_root/tools/index_project" "$repo" x64 linux "$test_build" --json > "$test_build/conformance-tools-index-project.jsonl"
cmp -s "$test_build/conformance-tools-index-project.jsonl" "$conformance_root/tools/index_project.expected.jsonl" || { printf '%s
' "index-project --json differs from the conformance corpus" >&2; exit 1; }
(cd "$conformance_root/tools/index_project" && "$repo/build/linux/short/neper-self-short" index > "$test_build/conformance-tools-index-project.jsonl")
cmp -s "$test_build/conformance-tools-index-project.jsonl" "$conformance_root/tools/index_project.expected.jsonl" || { printf '%s
' "the operand-less index differs from index-project" >&2; exit 1; }
# `run --json` (D231): the build stream plus one `run` record of the program's whole
# stdout, stderr and exit status, byte for byte.
run_actual="$test_build/conformance-tools-run.jsonl"
(cd "$test_build" && ./neper-self run "$conformance_root/tools/run.e" "$repo" x64 linux conformance-tools-run.out --json > "conformance-tools-run.jsonl")
cmp -s "$run_actual" "$conformance_root/tools/run.expected.jsonl" || { printf '%s
' "run --json differs from the conformance corpus" >&2; exit 1; }
# `run --json` on a program that traps (D253): section 11's record read back as the
# `trap` payload. The operand is spelled relative to the test build dir, whose depth is
# the same on both hosts, so the child's stderr -- and the golden -- carry no host path.
run_trap_actual="$test_build/conformance-tools-run-trap.jsonl"
(cd "$test_build" && ./neper-self run ../../../../tests/conformance/tools/run_trap.e "$repo" x64 linux conformance-tools-run-trap.out --json > "conformance-tools-run-trap.jsonl")
cmp -s "$run_trap_actual" "$conformance_root/tools/run_trap.expected.jsonl" || { printf '%s
' "run --json on a trapping program differs from the conformance corpus" >&2; exit 1; }
# `run --json -- ARGS...` (D267): what follows `--` reaches the program, spaces and all.
(cd "$test_build" && ./neper-self run ../../../../tests/conformance/tools/run_args.e "$repo" x64 linux conformance-tools-run-args.out --json -- first "second word" 3 > "conformance-tools-run-args.jsonl")
# `run --json --capture N` (D370, H18): a bounded record, the whole output in the file.
(cd "$test_build" && ./neper-self run ../../../../tests/conformance/tools/run_flood.e "$repo" x64 linux conformance-tools-run-flood.out --json --capture 50 > "conformance-tools-run-flood.jsonl")
cmp -s "$test_build/conformance-tools-run-flood.jsonl" "$conformance_root/tools/run_flood.expected.jsonl" || { echo "run --json --capture differs from the conformance corpus"; exit 1; }
# `--explain --json` (D408, H20): every inlining decision a record of the build stream.
(cd "$test_build" && ./neper-self emit-executable ../../../../tests/conformance/tools/contract.e "$repo" x64 linux conformance-tools-explain-inline.out --release --explain --json -j 1 > "conformance-tools-explain-inline.jsonl")
cmp -s "$test_build/conformance-tools-explain-inline.jsonl" "$conformance_root/tools/explain_inline.x64-linux.expected.jsonl" || { echo "emit-executable --explain --json differs from the conformance corpus"; exit 1; }
# Progress records (D454, H18): every phase a record of the stream under `--json --time`.
(cd "$test_build" && ./neper-self emit-executable ../../../../tests/conformance/tools/contract.e "$repo" x64 linux conformance-tools-progress.out --json --time > "conformance-tools-progress.jsonl")
grep -q '"record":"progress","phase":"lower and codegen"' "$test_build/conformance-tools-progress.jsonl"
python3 "$repo/scripts/validate_stream.py" "$test_build/conformance-tools-progress.jsonl"
# `--stats` as a record (D476, H18): one flat `stats` record before the result.
(cd "$test_build" && ./neper-self emit-executable ../../../../tests/conformance/tools/contract.e "$repo" x64 linux conformance-tools-stats.out --json --stats-full > "conformance-tools-stats.jsonl")
python3 "$repo/scripts/check_stats_record.py" "$test_build/conformance-tools-stats.jsonl"
python3 "$repo/scripts/validate_stream.py" "$test_build/conformance-tools-stats.jsonl"
# Per-instance cost (D453, H06): `instance-cost` records after the lowering.
(cd "$test_build" && ./neper-self emit-executable ../../../../tests/conformance/tools/instances.e "$repo" x64 linux conformance-tools-explain-instances.out --release --explain --json -j 1 > "conformance-tools-explain-instances.jsonl")
cmp -s "$test_build/conformance-tools-explain-instances.jsonl" "$conformance_root/tools/explain_instances.x64-linux.expected.jsonl" || { echo "the instance-cost records differ from the conformance corpus" >&2; exit 1; }
[ "$(stat -c %s "$test_build/conformance-tools-run-flood.out.stdout")" -eq 296 ]
cmp -s "$test_build/conformance-tools-run-args.jsonl" "$conformance_root/tools/run_args.expected.jsonl" || { printf '%s
' "run --json with program arguments differs from the conformance corpus" >&2; exit 1; }
# `index --json` (D232): the operand module's symbol records, byte for byte (target-independent).
index_actual="$test_build/conformance-tools-index.jsonl"
$test_build/neper-self index-file "$conformance_root/tools/index.e" "$repo" x64 linux --json > "$index_actual"
cmp -s "$index_actual" "$conformance_root/tools/index.expected.jsonl" || { printf '%s
' "index --json differs from the conformance corpus" >&2; exit 1; }
# `dis --json` (D233): one record of hex bytes per emitted function, byte for byte per host.
dis_actual="$test_build/conformance-tools-dis.jsonl"
$test_build/neper-self dis-file "$conformance_root/tools/dis.e" "$repo" x64 linux --json > "$dis_actual"
# `dis-file --json --release` (D542, H19): the release image, each function's inlined runs named.
$test_build/neper-self dis-file "$conformance_root/tools/dis_inlined.e" "$repo" x64 linux --json --release > "$test_build/conformance-tools-dis-inlined.jsonl"
cmp "$test_build/conformance-tools-dis-inlined.jsonl" "$conformance_root/tools/dis_inlined.x64-linux.expected.jsonl"
cmp -s "$dis_actual" "$conformance_root/tools/dis.x64-linux.expected.jsonl" || { printf '%s
' "dis --json differs from the conformance corpus" >&2; exit 1; }
# `fmt --json` (D234): the operand's canonical layout, byte for byte (target-independent);
# the fixture is already canonical, so this also pins idempotence.
fmt_actual="$test_build/conformance-tools-fmt.jsonl"
$test_build/neper-self fmt-file "$conformance_root/tools/fmt.e" --json > "$fmt_actual"
cmp -s "$fmt_actual" "$conformance_root/tools/fmt.expected.jsonl" || { printf '%s
' "fmt --json differs from the conformance corpus" >&2; exit 1; }
# The format corpus (D255): each `format/<name>.e` is a non-canonical source and
# `format/<name>.expected.e` what `fmt` makes of it, byte for byte; the canonical side
# passes `--check`, which pins idempotence.
for format_case in layout types; do
    "$test_build/neper-self" fmt-file "$conformance_root/format/$format_case.e" > "$test_build/conformance-format-$format_case.e"
    cmp -s "$test_build/conformance-format-$format_case.e" "$conformance_root/format/$format_case.expected.e" || { printf '%s
' "fmt on format/$format_case.e differs from the conformance corpus" >&2; exit 1; }
    "$test_build/neper-self" fmt-file "$conformance_root/format/$format_case.expected.e" --check --json > /dev/null
done
# `fmt --json` on what it refuses (D257): an invalid token under its lexical code and a
# comment splitting an attribute from its declaration under E-FORMAT-9999, exit 1.
fmt_reject_status=0
$test_build/neper-self fmt-file "$conformance_root/tools/fmt_reject.e" --json > "$test_build/conformance-tools-fmt-reject.jsonl" || fmt_reject_status=$?
[ "$fmt_reject_status" -eq 1 ]
cmp -s "$test_build/conformance-tools-fmt-reject.jsonl" "$conformance_root/tools/fmt_reject.expected.jsonl" || { printf '%s
' "fmt --json on a refused source differs from the conformance corpus" >&2; exit 1; }
# `fmt --check --json` (D244): a canonical source passes, a non-canonical one reports E-FORMAT-0001.
"$test_build/neper-self" fmt-file "$conformance_root/tools/fmt.e" --check --json > /dev/null
fmt_check_status=0
$test_build/neper-self fmt-file "$conformance_root/tools/fmt_check.e" --check --json > "$test_build/conformance-tools-fmt-check.jsonl" || fmt_check_status=$?
[ "$fmt_check_status" -eq 1 ]
cmp -s "$test_build/conformance-tools-fmt-check.jsonl" "$conformance_root/tools/fmt_check.expected.jsonl" || { printf '%s
' "fmt --check --json differs from the conformance corpus" >&2; exit 1; }
# `build-manifest --json` (D236): the canonical manifest with each input's SHA-256, byte for byte.
manifest_actual="$test_build/conformance-tools-manifest.jsonl"
# `context-file --json` (D361): one function's facts with provenance, budgeted.
context_actual="$test_build/conformance-tools-context.jsonl"
(cd "$conformance_root/tools" && $test_build/neper-self context-file explain.e "$repo" x64 linux --json --symbol explain.main --budget 8 > "$context_actual")
cmp -s "$context_actual" "$conformance_root/tools/context.x64-linux.expected.jsonl" || { printf '%s\n' "context-file --json differs from the conformance corpus" >&2; exit 1; }
# A body's moves and folded ifs as facts (D486, H17).
moves_actual="$test_build/conformance-tools-context-moves.jsonl"
: > "$moves_actual"
for moves_subject in context_moves.open_and_close context_moves.width context_moves.views context_moves.ends; do
    (cd "$conformance_root/tools" && $test_build/neper-self context-file context_moves.e "$repo" x64 linux --json --symbol "$moves_subject" --budget 16 >> "$moves_actual")
done
cmp -s "$moves_actual" "$conformance_root/tools/context_moves.x64-linux.expected.jsonl" || { echo "context-file --json over moves and a folded if differs from the conformance corpus" >&2; exit 1; }
# A constant and a global as subjects (D437, H08).
subjects_actual="$test_build/conformance-tools-subjects.jsonl"
: > "$subjects_actual"
for subject in subjects.LIMIT subjects.counter; do
    (cd "$conformance_root/tools" && $test_build/neper-self context-file subjects.e "$repo" x64 linux --json --symbol "$subject" --budget 8 >> "$subjects_actual")
done
cmp -s "$subjects_actual" "$conformance_root/tools/subjects.x64-linux.expected.jsonl" || { echo "context-file --json over a constant and a global differs from the conformance corpus" >&2; exit 1; }
# The caller's contract from a signature (D396, H11): four subjects of one fixture.
contract_actual="$test_build/conformance-tools-contract.jsonl"
: > "$contract_actual"
for contract_subject in contract.main contract.bump contract.first contract.total; do
    (cd "$conformance_root/tools" && $test_build/neper-self context-file contract.e "$repo" x64 linux --json --symbol $contract_subject --budget 16 >> "$contract_actual")
done
cmp -s "$contract_actual" "$conformance_root/tools/contract.x64-linux.expected.jsonl" || { printf '%s
' "context-file --json contract facts differ from the conformance corpus" >&2; exit 1; }
# `query-batch --json --batch FILE` (D409, H16): six queries over one check, two refused.
batch_status=0
(cd "$conformance_root/tools" && $test_build/neper-self query-batch contract.e "$repo" x64 linux --json --batch batch.txt > "$test_build/conformance-tools-batch.jsonl") || batch_status=$?
[ "$batch_status" -eq 2 ]
cmp -s "$test_build/conformance-tools-batch.jsonl" "$conformance_root/tools/batch.x64-linux.expected.jsonl" || { printf '%s
' "query-batch --json differs from the conformance corpus" >&2; exit 1; }
# A batch over a program that does not check (D523, H18): one stream, exit 1.
batch_broken_status=0
(cd "$conformance_root/tools" && "$test_build/neper-self" query-batch query_broken.e "$repo" x64 linux --json --batch batch_broken.txt > "$test_build/conformance-tools-batch-broken.jsonl" 2> "$test_build/conformance-tools-batch-broken.stderr") || batch_broken_status=$?
[ "$batch_broken_status" -eq 1 ]
[ ! -s "$test_build/conformance-tools-batch-broken.stderr" ]
cmp -s "$test_build/conformance-tools-batch-broken.jsonl" "$conformance_root/tools/batch_broken.expected.jsonl" || { echo "query-batch over a program that does not check differs from the conformance corpus" >&2; exit 1; }
# A batch retains nothing between lines (D410, H16): `memory` before and after three
# queries reports the same arena use.
batch_used=$($test_build/neper-self query-batch "$conformance_root/tools/contract.e" "$repo" x64 linux --json --batch "$conformance_root/tools/batch_memory.txt" | grep -o '"arena_used":[0-9]*' | sort -u | wc -l)
[ "$batch_used" -eq 1 ]
# The catalogue (D397, H11): every function of the module, subjects and facts under one
# budget; the byte budget (D400, H08) ends the page at the record that crosses it.
catalog_actual="$test_build/conformance-tools-catalog.jsonl"
(cd "$conformance_root/tools" && $test_build/neper-self context-file contract.e "$repo" x64 linux --json --module contract --budget 64 --bytes 3000 > "$catalog_actual")
cmp -s "$catalog_actual" "$conformance_root/tools/catalog.x64-linux.expected.jsonl" || { printf '%s
' "context-file --module differs from the conformance corpus" >&2; exit 1; }
# `--deadline MS` (D399, H16): a deadline already passed cancels the build at the first
# checkpoint -- one diagnostic, a result of exit code 3, no image written.
deadline_actual="$test_build/conformance-tools-deadline.jsonl"
deadline_image="$test_build/deadline-never"
rm -f "$deadline_image"
deadline_status=0
(cd "$conformance_root/tools" && $test_build/neper-self emit-executable contract.e "$repo" x64 linux "$deadline_image" --json --deadline 0 > "$deadline_actual") || deadline_status=$?
[ "$deadline_status" = 3 ] || { printf '%s
' "a build past its deadline did not exit 3 (got $deadline_status)" >&2; exit 1; }
[ ! -e "$deadline_image" ] || { printf '%s
' "a build past its deadline wrote an image" >&2; exit 1; }
cmp -s "$deadline_actual" "$conformance_root/tools/deadline.expected.jsonl" || { printf '%s
' "the cancelled build's stream differs from the conformance corpus" >&2; exit 1; }
# Metamorphic tests (D438, H10): comments removed build the same image; declarations
# reversed behave the same.
python3 "$repo/benchmarks/metamorphic/metamorphic.py" "$test_build/neper-self" "$repo" x64 linux "$test_build/metamorphic" "$repo/tests/selfhost/fixtures/link/algo_sort/src/main.e" "$repo/tests/selfhost/fixtures/link/algo_bitset/src/main.e" "$repo/tests/selfhost/fixtures/link/control/src/main.e" "$repo/tests/selfhost/fixtures/link/atomic_ops/src/main.e"
# The bootstrap as the codegen's oracle (D456, H10).
python3 "$repo/benchmarks/differential/bootstrap.py" "$test_build/neper-self" "$neper" "$repo" x64 linux "$test_build/bootstrap-oracle" "$repo/tests/neper0/arena-alloc.e" "$repo/tests/neper0/array.e" "$repo/tests/neper0/struct.e" "$repo/tests/neper0/slice.e" "$repo/tests/neper0/defer.e" "$repo/tests/neper0/range.e" "$repo/tests/neper0/unsigned-ops.e" "$repo/tests/neper0/multiple-return.e" "$repo/tests/neper0/constant-folding.e" "$repo/tests/neper0/enum-union-switch.e" "$repo/tests/neper0/generic-function.e" "$repo/tests/neper0/generic-aggregate.e" "$repo/tests/neper0/protocol-iteration.e" "$repo/tests/neper0/slice-iterate.e" "$repo/tests/neper0/slice-mutate.e" "$repo/tests/neper0/os-intrinsics.e" "$repo/tests/neper0/aggregate-abi.e"
# Differential execution against an independent oracle (D449, H10).
python3 "$repo/benchmarks/differential/differential.py" "$test_build/neper-self" "$repo" x64 linux "$test_build/differential" --cases 60 --seed 7
# `--instances N` (D426, H06): a budget over the specializations a build makes.
instances_status=0
(cd "$conformance_root/tools" && $test_build/neper-self emit-executable instances.e "$repo" x64 linux "$test_build/instances" --json --instances 2 > "$test_build/conformance-tools-instances.jsonl") || instances_status=$?
[ "$instances_status" = 1 ] || { echo "a build past its instance budget did not exit 1 (got $instances_status)" >&2; exit 1; }
cmp -s "$test_build/conformance-tools-instances.jsonl" "$conformance_root/tools/instances.expected.jsonl" || { echo "the refused build's stream differs from the conformance corpus" >&2; exit 1; }
(cd "$conformance_root/tools" && $test_build/neper-self emit-executable instances.e "$repo" x64 linux "$test_build/instances" --release --instances 3 > /dev/null)
"$test_build/instances"
# `--comptime-steps N` (D474, H24): a budget over the interpreter's steps in the whole build.
steps_status=0
(cd "$conformance_root/tools" && $test_build/neper-self emit-executable comptime_steps.e "$repo" x64 linux "$test_build/comptime-steps" --json --comptime-steps 10 > "$test_build/conformance-tools-comptime-steps.jsonl") || steps_status=$?
[ "$steps_status" = 1 ] || { echo "a build past its comptime step budget did not exit 1 (got $steps_status)" >&2; exit 1; }
cmp -s "$test_build/conformance-tools-comptime-steps.jsonl" "$conformance_root/tools/comptime_steps.expected.jsonl" || { echo "the refused build's stream differs from the conformance corpus" >&2; exit 1; }
(cd "$conformance_root/tools" && $test_build/neper-self emit-executable comptime_steps.e "$repo" x64 linux "$test_build/comptime-steps" --release --comptime-steps 100000 > /dev/null)
"$test_build/comptime-steps"
# A deadline inside an evaluation (D496, H16): cancelled in milliseconds, exit 3.
long_started=$(date +%s%N)
long_status=0
(cd "$conformance_root/tools" && $test_build/neper-self emit-executable comptime_long.e "$repo" x64 linux "$test_build/comptime-long" --json --deadline 50 > "$test_build/conformance-tools-comptime-long.jsonl") || long_status=$?
[ "$long_status" = 3 ] || { echo "a build whose deadline passed inside an evaluation did not exit 3 (got $long_status)" >&2; exit 1; }
[ $(( ($(date +%s%N) - long_started) / 1000000 )) -lt 2000 ] || { echo "a deadline inside an evaluation was not honoured until the evaluation ended" >&2; exit 1; }
grep -q '"cancelled_after":"check declarations"' "$test_build/conformance-tools-comptime-long.jsonl"
# A deadline inside a phase (D422, H16): the compiler's own build under a deadline it
# cannot meet is cancelled by a worker between two modules -- exit 3, no image.
deadline_inside="$test_build/deadline-inside"
rm -f "$deadline_inside"
deadline_inside_status=0
$test_build/neper-self emit-executable "$repo/src/main.e" "$repo" x64 linux "$deadline_inside" --release --deadline 150 --json > "$test_build/deadline-inside.jsonl" 2>/dev/null || deadline_inside_status=$?
[ "$deadline_inside_status" = 3 ]
[ ! -e "$deadline_inside" ]
grep -q '"code":"E-CLI-0001"' "$test_build/deadline-inside.jsonl"
# `test-impact-file --json --changed m1,m2` (D423, H10): the tests an edit reaches.
for impact_case in 'helper impact' 'nested.deep impact_local'; do
    set -- $impact_case
    (cd "$conformance_root/tools" && $test_build/neper-self test-impact-file test_project/src/nested/deep.e "$repo" x64 linux --json --changed "$1" > "$test_build/conformance-tools-$2.jsonl")
    cmp -s "$test_build/conformance-tools-$2.jsonl" "$conformance_root/tools/$2.expected.jsonl" || { echo "test-impact-file --json differs from the conformance corpus for $1" >&2; exit 1; }
done
impact_refused=0
(cd "$conformance_root/tools" && $test_build/neper-self test-impact-file test_project/src/nested/deep.e "$repo" x64 linux --json --changed nowhere > "$test_build/conformance-tools-impact-refused.jsonl") || impact_refused=$?
[ "$impact_refused" -eq 2 ]
# A query over a program that does not check (D520, H08, H18): the stream, exit 1.
for broken_case in "context-file context_broken" "uses-file uses_broken" "plan-rename-file plan_rename_broken"; do
    set -- $broken_case
    broken_tail=""
    if [ "$1" = "plan-rename-file" ]; then broken_tail="--to aide"; fi
    broken_status=0
    (cd "$conformance_root/tools" && "$test_build/neper-self" "$1" query_broken.e "$repo" x64 linux --json --symbol query_broken.helper $broken_tail > "$test_build/conformance-tools-$2.jsonl" 2> "$test_build/conformance-tools-$2.stderr") || broken_status=$?
    [ "$broken_status" -eq 1 ]
    [ ! -s "$test_build/conformance-tools-$2.stderr" ]
    cmp -s "$test_build/conformance-tools-$2.jsonl" "$conformance_root/tools/$2.expected.jsonl" || { echo "$1 --json over a program that does not check differs from the conformance corpus" >&2; exit 1; }
done
# A dependency that does not parse (D521, H18): the stream under the query's header, exit 1.
for syntax_case in "context-file context_syntax" "uses-file uses_syntax" "explain-file explain_syntax"; do
    set -- $syntax_case
    syntax_tail="--symbol main.main"
    if [ "$1" = "explain-file" ]; then syntax_tail=""; fi
    syntax_status=0
    (cd "$conformance_root/tools/query_syntax" && "$test_build/neper-self" "$1" src/main.e "$repo" x64 linux --json $syntax_tail > "$test_build/conformance-tools-$2.jsonl" 2> "$test_build/conformance-tools-$2.stderr") || syntax_status=$?
    [ "$syntax_status" -eq 1 ]
    [ ! -s "$test_build/conformance-tools-$2.stderr" ]
    cmp -s "$test_build/conformance-tools-$2.jsonl" "$conformance_root/tools/$2.expected.jsonl" || { echo "$1 --json over a dependency that does not parse differs from the conformance corpus" >&2; exit 1; }
done
for syntax_command in "dis-file dis_syntax" "build-manifest-file manifest_syntax"; do
    set -- $syntax_command
    syntax_command_status=0
    (cd "$conformance_root/tools/query_syntax" && "$test_build/neper-self" "$1" src/main.e "$repo" x64 linux --json > "$test_build/conformance-tools-$2.jsonl" 2> "$test_build/conformance-tools-$2.stderr") || syntax_command_status=$?
    [ "$syntax_command_status" -eq 1 ]
    [ ! -s "$test_build/conformance-tools-$2.stderr" ]
    cmp -s "$test_build/conformance-tools-$2.jsonl" "$conformance_root/tools/$2.expected.jsonl" || { echo "$1 --json over a dependency that does not parse differs from the conformance corpus" >&2; exit 1; }
done
index_syntax_status=0
(cd "$conformance_root/tools/query_syntax" && "$test_build/neper-self" index-file src/dep.e "$repo" x64 linux --json > "$test_build/conformance-tools-index-syntax.jsonl") || index_syntax_status=$?
[ "$index_syntax_status" -eq 1 ]
cmp -s "$test_build/conformance-tools-index-syntax.jsonl" "$conformance_root/tools/index_syntax.expected.jsonl" || { echo "index-file --json over a file that does not parse differs from the conformance corpus" >&2; exit 1; }
# `uses-file --json` (D362): every resolved use of one function.
uses_actual="$test_build/conformance-tools-uses.jsonl"
(cd "$conformance_root/tools" && $test_build/neper-self uses-file explain.e "$repo" x64 linux --json --symbol explain.same > "$uses_actual")
cmp -s "$uses_actual" "$conformance_root/tools/uses.expected.jsonl" || { printf '%s\n' "uses-file --json differs from the conformance corpus" >&2; exit 1; }
# `explain-file --json` (D359): every dispatch and instantiation the checker decided.
explain_actual="$test_build/conformance-tools-explain.jsonl"
(cd "$conformance_root/tools" && $test_build/neper-self explain-file explain.e "$repo" x64 linux --json > "$explain_actual")
cmp -s "$explain_actual" "$conformance_root/tools/explain.expected.jsonl" || { printf '%s\n' "explain-file --json differs from the conformance corpus" >&2; exit 1; }
# An `if` over constants folds (D500): two phase records, the program runs.
(cd "$conformance_root/tools" && $test_build/neper-self explain-file fold_const.e "$repo" x64 linux --json > "$test_build/conformance-tools-fold-const.jsonl")
cmp -s "$test_build/conformance-tools-fold-const.jsonl" "$conformance_root/tools/fold_const.expected.jsonl" || { echo "the constant folds differ from the conformance corpus" >&2; exit 1; }
[ "$(grep -o '"record":"phase","construct":"if"' "$test_build/conformance-tools-fold-const.jsonl" | wc -l)" -eq 2 ]
(cd "$conformance_root/tools" && $test_build/neper-self emit-executable fold_const.e "$repo" x64 linux "$test_build/fold-const" --release > /dev/null)
"$test_build/fold-const"
# The phase and the layouts (D463, H06).
(cd "$conformance_root/tools" && $test_build/neper-self explain-file explain_fold.e "$repo" x64 linux --json > "$test_build/conformance-tools-explain-fold.jsonl")
cmp -s "$test_build/conformance-tools-explain-fold.jsonl" "$conformance_root/tools/explain_fold.expected.jsonl" || { printf '%s\n' "the phase and layout records differ from the conformance corpus" >&2; exit 1; }
# `explain-file --json` over a program that does not check (D430, H06).
for explain_none in 'explain_none/src/main.e explain_none' 'explain_arm.e explain_arm'; do
    set -- $explain_none
    explain_none_status=0
    (cd "$conformance_root/tools" && $test_build/neper-self explain-file "$1" "$repo" x64 linux --json > "$test_build/conformance-tools-$2.jsonl") || explain_none_status=$?
    [ "$explain_none_status" -eq 1 ] || { echo "explain-file --json on $1 exited $explain_none_status, not 1" >&2; exit 1; }
    cmp -s "$test_build/conformance-tools-$2.jsonl" "$conformance_root/tools/$2.expected.jsonl" || { echo "explain-file --json on $1 differs from the conformance corpus" >&2; exit 1; }
done
$test_build/neper-self build-manifest-file "$conformance_root/tools/manifest.e" "$repo" x64 linux --json > "$manifest_actual"
# The operand's source map as an input (D467, H19).
$test_build/neper-self build-manifest-file "$conformance_root/tools/generated_map.e" "$repo" x64 linux --json > "$test_build/conformance-tools-manifest-map.jsonl"
cmp -s "$test_build/conformance-tools-manifest-map.jsonl" "$conformance_root/tools/manifest_map.x64-linux.expected.jsonl" || { printf '%s\n' "the manifest of an operand with a source map differs from the conformance corpus" >&2; exit 1; }
cmp -s "$manifest_actual" "$conformance_root/tools/manifest.x64-linux.expected.jsonl" || { printf '%s
' "build-manifest --json differs from the conformance corpus" >&2; exit 1; }
# On a project (D265): inputs under `project-src`, and the one module beyond the root as a
# dependency with its interface hash -- the source with function bodies left out -- and its
# body hash.
$test_build/neper-self build-manifest-file "$conformance_root/tools/manifest_project/src/main.e" "$repo" x64 linux --json > "$test_build/conformance-tools-manifest-project.jsonl"
cmp -s "$test_build/conformance-tools-manifest-project.jsonl" "$conformance_root/tools/manifest_project.x64-linux.expected.jsonl" || { printf '%s
' "build-manifest --json on a project differs from the conformance corpus" >&2; exit 1; }
# The `unsafe` inventory (D371, H27): every declared and trusted escape hatch, by kind.
$test_build/neper-self build-manifest-file "$conformance_root/tools/manifest_unsafe/src/main.e" "$repo" x64 linux --json > "$test_build/conformance-tools-manifest-unsafe.jsonl"
cmp -s "$test_build/conformance-tools-manifest-unsafe.jsonl" "$conformance_root/tools/manifest_unsafe.x64-linux.expected.jsonl" || { echo "the unsafe inventory differs from the conformance corpus" >&2; exit 1; }
# `test --json` (D240): @test discovery, a per-process run of each, section 7's stream; the
# fixture has a passing and a failing test so the command exits 1. Target-independent golden.
test_actual="$test_build/conformance-tools-test.jsonl"
test_status=0
$test_build/neper-self test-file "$conformance_root/tools/test.e" "$repo" x64 linux "$test_build" --json > "$test_actual" || test_status=$?
[ "$test_status" -eq 1 ]
# duration_ms is real wall time (D241): normalise it out before the byte-exact compare.
sed -i 's/"duration_ms":[0-9]*/"duration_ms":0/g' "$test_actual"
# The crashed test's stderr spells the runner by WORKDIR (D253): normalise that too.
sed -i "s#$test_build/nptest-runner.e#nptest-runner.e#g" "$test_actual"
cmp -s "$test_actual" "$conformance_root/tools/test.expected.jsonl" || { printf '%s
' "test --json differs from the conformance corpus" >&2; exit 1; }
# `test --json` on a `@test` that is not a test (D256): E-TEST-9999 at the declaration,
# exit 2, nothing compiled or run.
reject_status=0
$test_build/neper-self test-file "$conformance_root/tools/test_reject.e" "$repo" x64 linux "$test_build" --json > "$test_build/conformance-tools-test-reject.jsonl" || reject_status=$?
[ "$reject_status" -eq 2 ]
cmp -s "$test_build/conformance-tools-test-reject.jsonl" "$conformance_root/tools/test_reject.expected.jsonl" || { printf '%s
' "test --json on a non-test differs from the conformance corpus" >&2; exit 1; }
# `test-project --json` (D263): every module under a project's src in byte order, each
# run through `test-file --json --path REL` in its own process with its runner built as
# part of the project, the records merged; a module with no tests is counted and skipped.
test_project_status=0
$test_build/neper-self test-project "$conformance_root/tools/test_project" "$repo" x64 linux "$test_build" --json > "$test_build/conformance-tools-test-project.jsonl" || test_project_status=$?
[ "$test_project_status" -eq 1 ]
sed -i 's/"duration_ms":[0-9]*/"duration_ms":0/g' "$test_build/conformance-tools-test-project.jsonl"
cmp -s "$test_build/conformance-tools-test-project.jsonl" "$conformance_root/tools/test_project.expected.jsonl" || { printf '%s
' "test-project --json differs from the conformance corpus" >&2; exit 1; }
# `test --json` on a test that does not compile (D264): the runner's source map brings
# the compiler's diagnostic back at the operand's own span, the generated one related,
# before the E-CLI-9999 that says nothing ran; exit 2.
compile_error_status=0
$test_build/neper-self test-file "$conformance_root/tools/test_compile_error.e" "$repo" x64 linux "$test_build" --json > "$test_build/conformance-tools-test-compile-error.jsonl" || compile_error_status=$?
[ "$compile_error_status" -eq 2 ]
cmp -s "$test_build/conformance-tools-test-compile-error.jsonl" "$conformance_root/tools/test_compile_error.expected.jsonl" || { printf '%s
' "test --json on a test that does not compile differs from the conformance corpus" >&2; exit 1; }
python3 "$repo/scripts/validate_stream.py" "$test_build/nptest-runner.e.map.json" > /dev/null || { printf '%s
' "the runner's source map does not validate against the v1 schema" >&2; exit 1; }
# A stale source map beside the operand is E-TOOL-0001 and no artifact (D264).
stale_status=0
(cd "$test_build" && rm -f conformance-tools-stale-map.out && ./neper-self emit-executable "$conformance_root/tools/stale_map.e" "$repo" x64 linux conformance-tools-stale-map.out --json > "conformance-tools-stale-map.jsonl") || stale_status=$?
[ "$stale_status" -eq 1 ]
[ ! -e "$test_build/conformance-tools-stale-map.out" ]
cmp -s "$test_build/conformance-tools-stale-map.jsonl" "$conformance_root/tools/stale_map.expected.jsonl" || { printf '%s
' "a stale source map is not refused as the conformance corpus says" >&2; exit 1; }
# A stale map beside an operand that does not compile (D300): the analysis still runs,
# its diagnostic follows the E-TOOL-0001 at its own unmapped span; exit 1, no artifact.
stale_error_status=0
(cd "$test_build" && rm -f conformance-tools-stale-map-error.out && ./neper-self emit-executable "$conformance_root/tools/stale_map_error.e" "$repo" x64 linux conformance-tools-stale-map-error.out --json > "conformance-tools-stale-map-error.jsonl") || stale_error_status=$?
[ "$stale_error_status" -eq 1 ]
[ ! -e "$test_build/conformance-tools-stale-map-error.out" ]
# The language card is the render of the grammar (D374, H28).
python3 "$repo/scripts/render_card.py" --check > /dev/null
# The card's examples are checked by the compiler (D404, H11).
python3 "$repo/scripts/card_examples.py" "$test_build/neper-self" "$repo" x64 linux "$test_build/card-examples" > /dev/null
# `plan-rename-file --json` (D376, H29): the plan byte for byte; applied to a copy it
# re-checks, the new name has uses at the old sites, and a second apply is refused.
(cd "$conformance_root/tools" && $test_build/neper-self plan-rename-file explain.e "$repo" x64 linux --json --symbol explain.same --to alike > "$test_build/conformance-tools-plan-rename.jsonl")
cmp -s "$test_build/conformance-tools-plan-rename.jsonl" "$conformance_root/tools/plan_rename.x64-linux.expected.jsonl" || { echo "plan-rename-file --json differs from the conformance corpus" >&2; exit 1; }
plan_scratch="$test_build/plan-scratch"
rm -rf "$plan_scratch" && mkdir -p "$plan_scratch/src" && cp "$conformance_root/tools/explain.e" "$plan_scratch/src/"
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-rename.jsonl" --root "$plan_scratch/src" > /dev/null
plan_checked=$($test_build/neper-self check-file "$plan_scratch/src/explain.e" "$repo" x64 linux)
[ "$plan_checked" = 'module check ok' ]
plan_sites=$($test_build/neper-self uses-file "$plan_scratch/src/explain.e" "$repo" x64 linux --json --symbol explain.alike | grep '"record":"use"' | sed 's/.*"byte_start":\([0-9]*\).*/\1/' | sort -u | wc -l)
[ "$plan_sites" -eq 2 ]
plan_again=0
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-rename.jsonl" --root "$plan_scratch/src" > /dev/null 2>&1 || plan_again=$?
[ "$plan_again" -ne 0 ]
# Uses and a rename through an alias, past a same-spelled function and local (D509, H17).
alias_fixture="$conformance_root/tools/uses_alias"
(cd "$alias_fixture" && "$test_build/neper-self" uses-file src/main.e "$repo" x64 linux --json --symbol deep.pick > "$test_build/conformance-tools-uses-alias.jsonl")
cmp -s "$test_build/conformance-tools-uses-alias.jsonl" "$conformance_root/tools/uses_alias.expected.jsonl" || { echo "uses-file --json through an alias differs from the conformance corpus" >&2; exit 1; }
[ "$(cd "$alias_fixture" && "$test_build/neper-self" uses-file src/main.e "$repo" x64 linux --json --symbol other.pick | grep -c '"record":"use"')" -eq 2 ]
(cd "$alias_fixture" && "$test_build/neper-self" plan-rename-file src/main.e "$repo" x64 linux --json --symbol deep.pick --to choose > "$test_build/conformance-tools-plan-rename-alias.jsonl")
cmp -s "$test_build/conformance-tools-plan-rename-alias.jsonl" "$conformance_root/tools/plan_rename_alias.x64-linux.expected.jsonl" || { echo "plan-rename-file --json through an alias differs from the conformance corpus" >&2; exit 1; }
rm -rf "$test_build/alias-scratch"
cp -r "$alias_fixture" "$test_build/alias-scratch"
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-rename-alias.jsonl" --root "$test_build/alias-scratch/src" > /dev/null
cmp -s "$test_build/alias-scratch/src/other.e" "$alias_fixture/src/other.e"
[ "$("$test_build/neper-self" emit-executable "$test_build/alias-scratch/src/main.e" "$repo" x64 linux "$test_build/alias" 2>/dev/null)" = 'executable written' ]
alias_status=0
"$test_build/alias" || alias_status=$?
[ "$alias_status" -eq 8 ]
# A function only a constant reaches (D510, H17): its call in the initializer is a use the rename plan rewrites.
comptime_fixture="$conformance_root/tools/uses_comptime"
(cd "$comptime_fixture" && "$test_build/neper-self" uses-file src/main.e "$repo" x64 linux --json --symbol main.twice > "$test_build/conformance-tools-uses-comptime.jsonl")
cmp -s "$test_build/conformance-tools-uses-comptime.jsonl" "$conformance_root/tools/uses_comptime.expected.jsonl" || { echo "uses-file --json of a function only a constant reaches differs from the conformance corpus" >&2; exit 1; }
(cd "$comptime_fixture" && "$test_build/neper-self" plan-rename-file src/main.e "$repo" x64 linux --json --symbol main.twice --to double > "$test_build/conformance-tools-plan-rename-comptime.jsonl")
cmp -s "$test_build/conformance-tools-plan-rename-comptime.jsonl" "$conformance_root/tools/plan_rename_comptime.x64-linux.expected.jsonl" || { echo "plan-rename-file --json of a function only a constant reaches differs from the conformance corpus" >&2; exit 1; }
rm -rf "$test_build/comptime-scratch"
cp -r "$comptime_fixture" "$test_build/comptime-scratch"
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-rename-comptime.jsonl" --root "$test_build/comptime-scratch/src" > /dev/null
[ "$("$test_build/neper-self" emit-executable "$test_build/comptime-scratch/src/main.e" "$repo" x64 linux "$test_build/comptime-renamed" 2>/dev/null)" = 'executable written' ]
comptime_status=0
"$test_build/comptime-renamed" || comptime_status=$?
[ "$comptime_status" -eq 8 ]
# A function taken as a value and called through it (D511, H17): value uses, the plan rewriting them.
callback_fixture="$conformance_root/tools/uses_callback"
(cd "$callback_fixture" && "$test_build/neper-self" uses-file src/main.e "$repo" x64 linux --json --symbol main.twice > "$test_build/conformance-tools-uses-callback.jsonl")
cmp -s "$test_build/conformance-tools-uses-callback.jsonl" "$conformance_root/tools/uses_callback.expected.jsonl" || { echo "uses-file --json of a callback differs from the conformance corpus" >&2; exit 1; }
(cd "$callback_fixture" && "$test_build/neper-self" plan-rename-file src/main.e "$repo" x64 linux --json --symbol main.twice --to double > "$test_build/conformance-tools-plan-rename-callback.jsonl")
cmp -s "$test_build/conformance-tools-plan-rename-callback.jsonl" "$conformance_root/tools/plan_rename_callback.x64-linux.expected.jsonl" || { echo "plan-rename-file --json of a callback differs from the conformance corpus" >&2; exit 1; }
rm -rf "$test_build/callback-scratch"
cp -r "$callback_fixture" "$test_build/callback-scratch"
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-rename-callback.jsonl" --root "$test_build/callback-scratch/src" > /dev/null
[ "$("$test_build/neper-self" emit-executable "$test_build/callback-scratch/src/main.e" "$repo" x64 linux "$test_build/callback" 2>/dev/null)" = 'executable written' ]
callback_status=0
"$test_build/callback" || callback_status=$?
[ "$callback_status" -eq 8 ]
# A plan into generated text (D512, H19): the owned edit named, apply-plan refusing.
generated_fixture="$conformance_root/tools/plan_generated"
(cd "$generated_fixture" && "$test_build/neper-self" plan-rename-file src/main.e "$repo" x64 linux --json --symbol deep.pick --to choose > "$test_build/conformance-tools-plan-generated.jsonl")
cmp -s "$test_build/conformance-tools-plan-generated.jsonl" "$conformance_root/tools/plan_generated.x64-linux.expected.jsonl" || { echo "plan-rename-file --json over a generated root differs from the conformance corpus" >&2; exit 1; }
rm -rf "$test_build/generated-scratch"
cp -r "$generated_fixture" "$test_build/generated-scratch"
generated_status=0
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-generated.jsonl" --root "$test_build/generated-scratch/src" > "$test_build/generated-apply.txt" 2>&1 || generated_status=$?
[ "$generated_status" -eq 2 ]
grep -q 'a generator owns' "$test_build/generated-apply.txt"
cmp -s "$test_build/generated-scratch/src/deep.e" "$generated_fixture/src/deep.e"
# The uses of a type (D516, H17): every annotation and literal naming it.
(cd "$conformance_root/tools/plan_rename_type" && "$test_build/neper-self" uses-file src/main.e "$repo" x64 linux --json --symbol deep.Rec > "$test_build/conformance-tools-uses-type.jsonl")
cmp -s "$test_build/conformance-tools-uses-type.jsonl" "$conformance_root/tools/uses_type.expected.jsonl" || { echo "uses-file --json over a type differs from the conformance corpus" >&2; exit 1; }
# A type's rename (D515, H17, H29): every reference and the declaration, applied and run.
type_fixture="$conformance_root/tools/plan_rename_type"
(cd "$type_fixture" && "$test_build/neper-self" plan-rename-file src/main.e "$repo" x64 linux --json --symbol deep.Rec --to Pair > "$test_build/conformance-tools-plan-rename-type.jsonl")
cmp -s "$test_build/conformance-tools-plan-rename-type.jsonl" "$conformance_root/tools/plan_rename_type.x64-linux.expected.jsonl" || { echo "plan-rename-file --json over a type differs from the conformance corpus" >&2; exit 1; }
rm -rf "$test_build/type-scratch"
cp -r "$type_fixture" "$test_build/type-scratch"
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-rename-type.jsonl" --root "$test_build/type-scratch/src" > /dev/null
! grep -q 'Rec\b' "$test_build/type-scratch/src/main.e" "$test_build/type-scratch/src/deep.e"
[ "$("$test_build/neper-self" emit-executable "$test_build/type-scratch/src/main.e" "$repo" x64 linux "$test_build/type-renamed" 2>/dev/null)" = 'executable written' ]
type_status=0
"$test_build/type-renamed" || type_status=$?
[ "$type_status" -eq 12 ]
grep -q 'fn pair_cmp' "$test_build/type-scratch/src/deep.e"
# A function found by its spelling (D518, H17): renaming `rec_cmp` on its own is refused.
protocol_status=0
(cd "$type_fixture" && "$test_build/neper-self" plan-rename-file src/main.e "$repo" x64 linux --json --symbol deep.rec_cmp --to compare > "$test_build/conformance-tools-plan-rename-protocol-refused.jsonl") || protocol_status=$?
[ "$protocol_status" -eq 2 ]
cmp -s "$test_build/conformance-tools-plan-rename-protocol-refused.jsonl" "$conformance_root/tools/plan_rename_protocol_refused.expected.jsonl" || { echo "a refused rename of a protocol function differs from the conformance corpus" >&2; exit 1; }
# `plan-replace-expression-file --json` (D414, H29): one expression's plan, applied and
# checked; a span that is not one expression is refused with exit 2.
(cd "$conformance_root/tools" && $test_build/neper-self plan-replace-expression-file contract.e "$repo" x64 linux --json --span 693:703 --with 131072usize > "$test_build/conformance-tools-plan-replace.jsonl")
cmp -s "$test_build/conformance-tools-plan-replace.jsonl" "$conformance_root/tools/plan_replace.x64-linux.expected.jsonl" || { echo "plan-replace-expression-file --json differs from the conformance corpus" >&2; exit 1; }
replace_scratch="$test_build/plan-replace-scratch"
rm -rf "$replace_scratch" && mkdir -p "$replace_scratch/src" && cp "$conformance_root/tools/contract.e" "$replace_scratch/src/"
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-replace.jsonl" --root "$replace_scratch/src" > /dev/null
replace_checked=$($test_build/neper-self check-file "$replace_scratch/src/contract.e" "$repo" x64 linux)
[ "$replace_checked" = 'module check ok' ]
replace_refused=0
(cd "$conformance_root/tools" && $test_build/neper-self plan-replace-expression-file contract.e "$repo" x64 linux --json --span 693:700 --with 1usize > "$test_build/conformance-tools-plan-replace-refused.jsonl") || replace_refused=$?
[ "$replace_refused" -eq 2 ]
cmp -s "$test_build/conformance-tools-plan-replace-refused.jsonl" "$conformance_root/tools/plan_replace_refused.expected.jsonl" || { echo "a refused plan-replace-expression-file differs from the conformance corpus" >&2; exit 1; }
# `plan-change-signature-file --json` (D415, H29): the parameters reordered, applied and
# checked; a repeated index is refused with exit 2.
(cd "$conformance_root/tools" && $test_build/neper-self plan-change-signature-file signature.e "$repo" x64 linux --json --symbol signature.adjust --order 2,0,1 > "$test_build/conformance-tools-plan-signature.jsonl")
cmp -s "$test_build/conformance-tools-plan-signature.jsonl" "$conformance_root/tools/plan_signature.x64-linux.expected.jsonl" || { echo "plan-change-signature-file --json differs from the conformance corpus" >&2; exit 1; }
signature_scratch="$test_build/plan-signature-scratch"
rm -rf "$signature_scratch" && mkdir -p "$signature_scratch/src" && cp "$conformance_root/tools/signature.e" "$signature_scratch/src/"
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-signature.jsonl" --root "$signature_scratch/src" > /dev/null
signature_checked=$($test_build/neper-self check-file "$signature_scratch/src/signature.e" "$repo" x64 linux)
[ "$signature_checked" = 'module check ok' ]
grep -q 'fn adjust(offset: f32, reading: f32, gain: f32)' "$signature_scratch/src/signature.e"
# A parameter removed (D439, H17): `0,1` drops the unused `scale`; `0,2` is refused.
remove_actual="$test_build/conformance-tools-plan-signature-remove.jsonl"
(cd "$conformance_root/tools" && $test_build/neper-self plan-change-signature-file signature_remove.e "$repo" x64 linux --json --symbol signature_remove.adjust --order 0,1 > "$remove_actual")
cmp -s "$remove_actual" "$conformance_root/tools/plan_signature_remove.x64-linux.expected.jsonl" || { echo "plan-change-signature-file with a removal differs from the conformance corpus" >&2; exit 1; }
remove_scratch="$test_build/plan-signature-remove-scratch"
rm -rf "$remove_scratch"
mkdir -p "$remove_scratch/src"
cp "$conformance_root/tools/signature_remove.e" "$remove_scratch/src/signature_remove.e"
"$test_build/neper-self" apply-plan "$remove_actual" --root "$remove_scratch/src" > /dev/null
[ "$($test_build/neper-self check-file "$remove_scratch/src/signature_remove.e" "$repo" x64 linux)" = 'module check ok' ]
grep -q 'fn adjust(reading: f32, gain: f32)' "$remove_scratch/src/signature_remove.e"
remove_refused=0
(cd "$conformance_root/tools" && $test_build/neper-self plan-change-signature-file signature_remove.e "$repo" x64 linux --json --symbol signature_remove.adjust --order 0,2 > "$test_build/conformance-tools-plan-signature-remove-refused.jsonl") || remove_refused=$?
[ "$remove_refused" -eq 2 ]
grep -q 'the body names it' "$test_build/conformance-tools-plan-signature-remove-refused.jsonl"
signature_refused=0
(cd "$conformance_root/tools" && $test_build/neper-self plan-change-signature-file signature.e "$repo" x64 linux --json --symbol signature.adjust --order 0,0 > "$test_build/conformance-tools-plan-signature-refused.jsonl") || signature_refused=$?
[ "$signature_refused" -eq 2 ]
cmp -s "$test_build/conformance-tools-plan-signature-refused.jsonl" "$conformance_root/tools/plan_signature_refused.expected.jsonl" || { echo "a refused plan-change-signature-file differs from the conformance corpus" >&2; exit 1; }
# An error's uses and rename (D451, H17).
(cd "$conformance_root/tools" && $test_build/neper-self uses-file errors_project/src/main.e "$repo" x64 linux --json --symbol faults.Stalled > "$test_build/conformance-tools-uses-error.jsonl")
cmp -s "$test_build/conformance-tools-uses-error.jsonl" "$conformance_root/tools/uses_error.expected.jsonl" || { echo "uses-file --json over an error differs from the conformance corpus" >&2; exit 1; }
(cd "$conformance_root/tools" && $test_build/neper-self plan-rename-file errors_project/src/main.e "$repo" x64 linux --json --symbol faults.Stalled --to Blocked > "$test_build/conformance-tools-plan-rename-error.jsonl")
cmp -s "$test_build/conformance-tools-plan-rename-error.jsonl" "$conformance_root/tools/plan_rename_error.x64-linux.expected.jsonl" || { echo "plan-rename-file --json over an error differs from the conformance corpus" >&2; exit 1; }
error_scratch="$test_build/plan-rename-error-scratch"
rm -rf "$error_scratch"
mkdir -p "$error_scratch/src"
cp "$conformance_root/tools/errors_project/src/"*.e "$error_scratch/src/"
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-rename-error.jsonl" --root "$error_scratch/src" > /dev/null
[ "$($test_build/neper-self check-file "$error_scratch/src/main.e" "$repo" x64 linux)" = 'module check ok' ]
! grep -q 'Stalled' "$error_scratch/src/"*.e
grep -q 'error Blocked' "$error_scratch/src/faults.e"
# A field's uses and rename (D420, H17): the uses byte for byte; the rename applied to a
# copy checks, and the new name has the five uses.
(cd "$conformance_root/tools" && $test_build/neper-self uses-file contract.e "$repo" x64 linux --json --symbol contract.Counter.hits > "$test_build/conformance-tools-uses-field.jsonl")
cmp -s "$test_build/conformance-tools-uses-field.jsonl" "$conformance_root/tools/uses_field.expected.jsonl" || { echo "uses-file --json on a field differs from the conformance corpus" >&2; exit 1; }
(cd "$conformance_root/tools" && $test_build/neper-self plan-rename-file contract.e "$repo" x64 linux --json --symbol contract.Counter.hits --to count > "$test_build/conformance-tools-plan-rename-field.jsonl")
cmp -s "$test_build/conformance-tools-plan-rename-field.jsonl" "$conformance_root/tools/plan_rename_field.x64-linux.expected.jsonl" || { echo "plan-rename-file --json on a field differs from the conformance corpus" >&2; exit 1; }
field_scratch="$test_build/plan-rename-field-scratch"
rm -rf "$field_scratch" && mkdir -p "$field_scratch/src" && cp "$conformance_root/tools/contract.e" "$field_scratch/src/"
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-rename-field.jsonl" --root "$field_scratch/src" > /dev/null
field_checked=$($test_build/neper-self check-file "$field_scratch/src/contract.e" "$repo" x64 linux)
[ "$field_checked" = 'module check ok' ]
field_uses=$($test_build/neper-self uses-file "$field_scratch/src/contract.e" "$repo" x64 linux --json --symbol contract.Counter.count | grep -c '"record":"use"')
[ "$field_uses" -eq 5 ]
# The subject's snapshot (D407, H15): the renamed program's differs from the original's.
snapshot_before=$($test_build/neper-self context-file "$conformance_root/tools/explain.e" "$repo" x64 linux --json --symbol explain.main --budget 1 | grep -o '"snapshot":"[0-9a-f]*"' | head -1)
snapshot_after=$($test_build/neper-self context-file "$plan_scratch/src/explain.e" "$repo" x64 linux --json --symbol explain.main --budget 1 | grep -o '"snapshot":"[0-9a-f]*"' | head -1)
[ "${#snapshot_before}" -eq 29 ] && [ "$snapshot_before" != "$snapshot_after" ]
# `plan-add-parameter-file --json` (D406, H17): the signature-change plan byte for byte;
# applied to a copy it checks with the parameter last; a function named as a value is
# refused with exit 2 and the diagnostic naming the site.
(cd "$conformance_root/tools" && $test_build/neper-self plan-add-parameter-file contract.e "$repo" x64 linux --json --symbol contract.total --parameter 'scale: i64' --argument 1i64 > "$test_build/conformance-tools-plan-parameter.jsonl")
cmp -s "$test_build/conformance-tools-plan-parameter.jsonl" "$conformance_root/tools/plan_parameter.x64-linux.expected.jsonl" || { echo "plan-add-parameter-file --json differs from the conformance corpus" >&2; exit 1; }
parameter_scratch="$test_build/plan-parameter-scratch"
rm -rf "$parameter_scratch" && mkdir -p "$parameter_scratch/src" && cp "$conformance_root/tools/contract.e" "$parameter_scratch/src/"
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-parameter.jsonl" --root "$parameter_scratch/src" > /dev/null
parameter_checked=$($test_build/neper-self check-file "$parameter_scratch/src/contract.e" "$repo" x64 linux)
[ "$parameter_checked" = 'module check ok' ]
grep -q 'fn total(c: \*const Counter, scale: i64) -> i64' "$parameter_scratch/src/contract.e"
# An argument per call (D455, H29).
(cd "$conformance_root/tools" && $test_build/neper-self plan-add-parameter-file contract.e "$repo" x64 linux --json --symbol contract.total --parameter "scale: i64" --arguments parameter_sites.txt > "$test_build/conformance-tools-plan-parameter-sites.jsonl")
cmp -s "$test_build/conformance-tools-plan-parameter-sites.jsonl" "$conformance_root/tools/plan_parameter_sites.x64-linux.expected.jsonl" || { echo "plan-add-parameter-file --arguments differs from the conformance corpus" >&2; exit 1; }
parameter_refused=0
(cd "$conformance_root/tools" && $test_build/neper-self plan-add-parameter-file contract.e "$repo" x64 linux --json --symbol contract.bump --parameter 'by: i64' --argument 1i64 > "$test_build/conformance-tools-plan-parameter-refused.jsonl") || parameter_refused=$?
[ "$parameter_refused" -eq 2 ]
cmp -s "$test_build/conformance-tools-plan-parameter-refused.jsonl" "$conformance_root/tools/plan_parameter_refused.expected.jsonl" || { echo "a refused plan-add-parameter-file differs from the conformance corpus" >&2; exit 1; }
# A version 2 map (D373, H19): the generator's input is hashed, a regeneration-owned
# mapping says so in the related location, and a changed input is E-TOOL-0001.
# Combined inputs (D464, H19).
for map_case in generated_map stale_generator hand_edited combined_inputs combined_stale nested_map nested_stale nested_deep; do
    map_status=0
    (cd "$test_build" && rm -f "conformance-tools-$map_case.out" && ./neper-self emit-executable "$conformance_root/tools/$map_case.e" "$repo" x64 linux "conformance-tools-$map_case.out" --json > "conformance-tools-$map_case.jsonl") || map_status=$?
    [ "$map_status" -eq 1 ]
    [ ! -e "$test_build/conformance-tools-$map_case.out" ]
    cmp -s "$test_build/conformance-tools-$map_case.jsonl" "$conformance_root/tools/$map_case.expected.jsonl" || { echo "$map_case differs from the conformance corpus" >&2; exit 1; }
done
cmp -s "$test_build/conformance-tools-stale-map-error.jsonl" "$conformance_root/tools/stale_map_error.expected.jsonl" || { printf '%s
' "analysis under a stale source map differs from the conformance corpus" >&2; exit 1; }
# An operand that defines `main` and carries tests (D281): the runner renames the
# operand's `main`, both tests run, and a compile error after the rename still maps back.
$test_build/neper-self test-file "$conformance_root/tools/test_main.e" "$repo" x64 linux "$test_build" --json > "$test_build/conformance-tools-test-main.jsonl"
sed -i 's/"duration_ms":[0-9]*/"duration_ms":0/g' "$test_build/conformance-tools-test-main.jsonl"
cmp -s "$test_build/conformance-tools-test-main.jsonl" "$conformance_root/tools/test_main.expected.jsonl" || { printf '%s
' "test --json on an operand with main differs from the conformance corpus" >&2; exit 1; }
main_error_status=0
$test_build/neper-self test-file "$conformance_root/tools/test_main_error.e" "$repo" x64 linux "$test_build" --json > "$test_build/conformance-tools-test-main-error.jsonl" || main_error_status=$?
[ "$main_error_status" -eq 2 ]
cmp -s "$test_build/conformance-tools-test-main-error.jsonl" "$conformance_root/tools/test_main_error.expected.jsonl" || { printf '%s
' "a compile error past the renamed main differs from the conformance corpus" >&2; exit 1; }
# `test --json` with a deadline (D246): a test that never returns is ended by the runner's
# own watchdog thread and reported `timeout`. 400ms keeps the suite quick.
timeout_actual="$test_build/conformance-tools-test-timeout.jsonl"
timeout_status=0
$test_build/neper-self test-file "$conformance_root/tools/test_timeout.e" "$repo" x64 linux "$test_build" 400 --json > "$timeout_actual" || timeout_status=$?
[ "$timeout_status" -eq 1 ]
sed -i 's/"duration_ms":[0-9]*/"duration_ms":0/g' "$timeout_actual"
cmp -s "$timeout_actual" "$conformance_root/tools/test_timeout.expected.jsonl" || { printf '%s
' "test --json deadline differs from the conformance corpus" >&2; exit 1; }
# An operand that cannot be read answers with section 1's envelope on every `--json`
# command (D260): the header, one location-free E-CLI-9999, the result exiting 2 with the
# command's zero counts. The expected stream is built here from that shape.
for unreadable_case in 'tokens {"tokens":0,"diagnostics":1} tokens --json' 'parse {"tokens":0,"diagnostics":1} parse --json' 'fmt {"diagnostics":1} fmt-file' 'fmt {"diagnostics":1} fmt-file --check --json' 'dis {"functions":0} dis-file' 'test {"tests":0} test-file'; do
    set -- $unreadable_case
    unreadable_command=$1
    unreadable_data=$2
    shift 2
    unreadable_status=0
    case "$1" in
        tokens|parse) "$test_build/neper-self" "$@" "$test_build/no-such-operand.e" > "$test_build/conformance-unreadable.jsonl" || unreadable_status=$? ;;
        fmt-file) if [ $# -eq 1 ]; then "$test_build/neper-self" fmt-file "$test_build/no-such-operand.e" --json > "$test_build/conformance-unreadable.jsonl" || unreadable_status=$?; else "$test_build/neper-self" fmt-file "$test_build/no-such-operand.e" --check --json > "$test_build/conformance-unreadable.jsonl" || unreadable_status=$?; fi ;;
        dis-file) "$test_build/neper-self" dis-file "$test_build/no-such-operand.e" "$repo" x64 linux --json > "$test_build/conformance-unreadable.jsonl" || unreadable_status=$? ;;
        test-file) "$test_build/neper-self" test-file "$test_build/no-such-operand.e" "$repo" x64 linux "$test_build" --json > "$test_build/conformance-unreadable.jsonl" || unreadable_status=$? ;;
    esac
    [ "$unreadable_status" -eq 2 ]
    printf '%s\n' "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"$unreadable_command\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":3}" '{"record":"diagnostic","severity":"error","code":"E-CLI-9999","message":"the operand cannot be read","span":null,"parent":null,"related":[],"fixes":[]}' "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":$unreadable_data}" > "$test_build/conformance-unreadable.expected.jsonl"
    cmp -s "$test_build/conformance-unreadable.jsonl" "$test_build/conformance-unreadable.expected.jsonl" || { printf '%s
' "$unreadable_command --json on an unreadable operand is not section 1's envelope" >&2; exit 1; }
done
# Every record of the corpus against docs/schemas/neper-v1.schema.json (D250). The
# goldens are what the commands emit, byte for byte, so validating them validates the
# emitters; the script skips itself where the `jsonschema` package is absent.
python3 "$repo/scripts/validate_stream.py" || { printf '%s
' "the conformance corpus does not validate against the v1 schema" >&2; exit 1; }
# Section 11's debug fills (D217): a fresh allocation reads 0xCD and a reset's memory
# 0xDD in the debug build, and neither in release.
fills_path="$test_build/debug-fills-selfhost"
fills_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/debug_fills/src/main.e" "$repo" x64 linux "$fills_path")
[ "$fills_written" = 'executable written' ]
chmod +x "$fills_path"
"$fills_path" debug
fills_release_path="$test_build/debug-fills-release-selfhost"
fills_release_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/debug_fills/src/main.e" "$repo" x64 linux "$fills_release_path" --release)
[ "$fills_release_written" = 'executable written' ]
chmod +x "$fills_release_path"
"$fills_release_path" release
# Section 6's `when` (D216): conditions over `target.arch` and `target.os`, settled at
# compile time, the taken arms adding up to 27 on Linux, four of them through a
# condition the interpreter evaluates (D220), and `target.arch`/`target.os` as values
# -- compared, switched over, passed -- adding 88 (D223); a condition over runtime
# state is refused.
when_path="$test_build/when-target-selfhost"
when_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/when_target/src/main.e" "$repo" x64 linux "$when_path")
[ "$when_written" = 'executable written' ]
chmod +x "$when_path"
when_status=0
"$when_path" || when_status=$?
[ "$when_status" -eq 115 ]
check_protocol_diagnostic when_condition 'main.e:5:10: error[E-COMPTIME-9999]: a `when` condition cannot be evaluated at compile time: it reached a name that is no local or constant'
# The trap protocol's backtrace: one `  at module.function` line per frame, from the
# trapping function up to main, after the record.
backtrace_path="$test_build/trap-backtrace-selfhost"
backtrace_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_backtrace/src/main.e" "$repo" x64 linux "$backtrace_path")
[ "$backtrace_written" = 'executable written' ]
chmod +x "$backtrace_path"
backtrace_status=0
backtrace_output=$("$backtrace_path" 2>&1) || backtrace_status=$?
[ "$backtrace_status" -eq 134 ]
backtrace_expected=$'helper.e:1:50: trap[bounds]: index 7 out of bounds for len 5\n  at helper.pick ('
case "$backtrace_output" in *"$backtrace_expected"*) ;; *) printf %s "the trap did not print its backtrace: $backtrace_output" >&2; echo >&2; exit 1 ;; esac
case "$backtrace_output" in *'helper.e:1)'*) ;; *) printf %s "the first frame has no line: $backtrace_output" >&2; echo >&2; exit 1 ;; esac
case "$backtrace_output" in *'  at main.deeper ('*'main.e:12)'*) ;; *) printf %s "the debug build inlined deeper, or its frame has no line: $backtrace_output" >&2; echo >&2; exit 1 ;; esac
case "$backtrace_output" in *'  at main.main ('*'main.e:16)'*) ;; *) printf %s "the third frame has no line: $backtrace_output" >&2; echo >&2; exit 1 ;; esac
# `os.syscall`, which exists on Linux alone -- so this step has no Windows counterpart.
# Every argument position is exercised, including a six-argument `mmap` whose fifth and
# sixth a register shuffle that stops early would drop.
os_syscall_path="$test_build/os-syscall-selfhost"
os_syscall_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_syscall/src/main.e" "$repo" x64 linux "$os_syscall_path")
[ "$os_syscall_written" = 'executable written' ]
chmod +x "$os_syscall_path"
"$os_syscall_path"
# `e.path` is pure: the same answers on both platforms, so the fixture asserts exact
# strings rather than only that nothing failed.
path_pure_path="$test_build/path-pure-selfhost"
path_pure_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/path_pure/src/main.e" "$repo" x64 linux "$path_pure_path")
[ "$path_pure_written" = 'executable written' ]
chmod +x "$path_pure_path"
"$path_pure_path"
# Section 9's reflection, run rather than only checked: the offsets and sizes are
# asserted by hand, so a field read at the wrong offset is a wrong value here.
meta_reflect_path="$test_build/meta-reflect-selfhost"
meta_reflect_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/meta_reflect/src/main.e" "$repo" x64 linux "$meta_reflect_path")
[ "$meta_reflect_written" = 'executable written' ]
chmod +x "$meta_reflect_path"
"$meta_reflect_path"
# `e.channel`, over `e.sync`. The threaded half runs four producers through a channel
# that holds four, so every one of them blocks, and the close is what releases the
# consumers waiting on empty -- a close that failed to wake would hang here.
channel_path="$test_build/channel-semantics-selfhost"
channel_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/channel_semantics/src/main.e" "$repo" x64 linux "$channel_path")
[ "$channel_written" = 'executable written' ]
chmod +x "$channel_path"
"$channel_path"
channel_threads_path="$test_build/channel-threads-selfhost"
channel_threads_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/channel_threads/src/main.e" "$repo" x64 linux "$channel_threads_path")
[ "$channel_threads_written" = 'executable written' ]
chmod +x "$channel_threads_path"
"$channel_threads_path"
# `e.sync`. The uncontended half first, where every fence promise lives and where a
# wrong wait fails in milliseconds; then the half a single thread cannot check, where
# a mutex that does not exclude loses increments and the total comes out short.
sync_path="$test_build/sync-semantics-selfhost"
sync_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/sync_semantics/src/main.e" "$repo" x64 linux "$sync_path")
[ "$sync_written" = 'executable written' ]
chmod +x "$sync_path"
"$sync_path"
# A lock as a resource (D379, H04): guards released on every exit, workers excluded.
sync_guard_path="$test_build/sync-guard-selfhost"
sync_guard_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/sync_guard/src/main.e" "$repo" x64 linux "$sync_guard_path")
[ "$sync_guard_written" = 'executable written' ]
chmod +x "$sync_guard_path"
"$sync_guard_path"
# A group of threads as one resource (D434, H04).
thread_group_path="$test_build/thread-group-selfhost"
thread_group_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/thread_group/src/main.e" "$repo" x64 linux "$thread_group_path")
[ "$thread_group_written" = 'executable written' ]
chmod +x "$thread_group_path"
"$thread_group_path"
# Read and write locks as resources (D433, H04).
sync_rwguard_path="$test_build/sync-rwguard-selfhost"
sync_rwguard_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/sync_rwguard/src/main.e" "$repo" x64 linux "$sync_rwguard_path")
[ "$sync_rwguard_written" = 'executable written' ]
chmod +x "$sync_rwguard_path"
"$sync_rwguard_path"
sync_threads_path="$test_build/sync-threads-selfhost"
sync_threads_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/sync_threads/src/main.e" "$repo" x64 linux "$sync_threads_path")
[ "$sync_threads_written" = 'executable written' ]
chmod +x "$sync_threads_path"
"$sync_threads_path"
# Section 8's blocking primitives, under the wake that a bug here turns into a hang.
futex_path="$test_build/os-futex-selfhost"
futex_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_futex/src/main.e" "$repo" x64 linux "$futex_path")
[ "$futex_written" = 'executable written' ]
chmod +x "$futex_path"
"$futex_path"
# Section 8's atomics. The ordering rules are settled while checking, so each is pinned
# to its message; the operations themselves are run, because `and`, `or`, `xor`, `min`
# and `max` are compare-and-swap loops whose widening and signedness a check cannot see.
# docs/diagnostics.md's codes for the module graph, the scanner and the command line
# (D215): each at the module that wrote the `use`, the token the scanner refused, or
# the usage line, under its registered code.
check_protocol_diagnostic module_missing 'main.e:1:1: error[E-MODULE-0001]: `use nowhere` names no module under the source root or the toolchain'
check_protocol_diagnostic module_cycle 'b.e:1:1: error[E-MODULE-0002]: `use main` closes an import cycle'
check_protocol_diagnostic lex_literal 'main.e:3:13: error[E-LEX-0003]: invalid token'
check_protocol_diagnostic lex_tab 'main.e:3:1: error[E-LEX-0002]: invalid token'
check_protocol_diagnostic lex_utf8 'main.e:2:21: error[E-LEX-0001]: invalid token'
cli_status=0
cli_output=$($test_build/neper-self 2>&1) || cli_status=$?
[ "$cli_status" -eq 1 ]
case "$cli_output" in *'error[E-CLI-9999]: usage: '*) ;; *) printf '%s\n' "an empty command line was not refused under E-CLI-9999: $cli_output" >&2; exit 1 ;; esac
check_protocol_diagnostic atomic_load_release 'main.e:8:34: error[E-MEM-9999]: `atomic.load` may not take the ordering `.Release`'
check_protocol_diagnostic atomic_store_acquire 'main.e:8:33: error[E-MEM-9999]: `atomic.store` may not take the ordering `.Acquire`'
check_protocol_diagnostic atomic_cas_failure 'main.e:9:65: error[E-MEM-9999]: `atomic.cas` may not take the ordering `.SeqCst`'
check_protocol_diagnostic atomic_element 'main.e:5:14: error[E-MEM-9999]: `Atomic[f64]` is not a type: an atomic holds an integer or a pointer'
atomic_ops_path="$test_build/atomic-ops-selfhost"
atomic_ops_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/atomic_ops/src/main.e" "$repo" x64 linux "$atomic_ops_path")
[ "$atomic_ops_written" = 'executable written' ]
chmod +x "$atomic_ops_path"
"$atomic_ops_path"
# The one check a single thread cannot make: that `lock` is really on the instruction.
# Without it the four workers lose updates and the total comes out short. The fixture
# returns early where `os.thread_create` is still `Unsupported`.
atomic_threads_path="$test_build/atomic-threads-selfhost"
atomic_threads_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/atomic_threads/src/main.e" "$repo" x64 linux "$atomic_threads_path")
[ "$atomic_threads_written" = 'executable written' ]
chmod +x "$atomic_threads_path"
"$atomic_threads_path"
# An alias to a generic instantiation cannot resolve in `collect_aliases`' first pass,
# which runs before any aggregate is registered, so a field naming one holds the alias
# name until the second pass. `lead` and `tail` bracket the instances, so a size or
# offset taken from an unexpanded field type is a wrong value and not just a wrong type.
generic_instance_alias_path="$test_build/generic-instance-alias-selfhost"
generic_instance_alias_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/generic_instance_alias/src/main.e" "$repo" x64 linux "$generic_instance_alias_path")
[ "$generic_instance_alias_written" = 'executable written' ]
chmod +x "$generic_instance_alias_path"
"$generic_instance_alias_path"
generic_instances_executable_path="$test_build/generic-instances-selfhost"
generic_instances_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/generic_instances/src/main.e" "$repo" x64 linux "$generic_instances_executable_path")
[ "$generic_instances_executable_written" = 'executable written' ]
chmod +x "$generic_instances_executable_path"
"$generic_instances_executable_path"
generic_instances_artifacts="$test_build/generic-instances"
generic_instances_copy="$test_build/generic-instances-copy"
mkdir -p "$generic_instances_artifacts" "$generic_instances_copy"
generic_instances_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/link/generic_instances/src/main.e" "$repo" x64 linux "$generic_instances_artifacts")
[ "$generic_instances_written" = 'compiled modules written' ]
generic_instances_copy_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/link/generic_instances/src/main.e" "$repo" x64 linux "$generic_instances_copy")
[ "$generic_instances_copy_written" = 'compiled modules written' ]
generic_instances_root_path="$generic_instances_artifacts/main.x64-linux.em"
generic_instances_dep_path="$generic_instances_artifacts/dep.x64-linux.em"
for artifact_name in main dep; do
    artifact_path="$generic_instances_artifacts/$artifact_name.x64-linux.em"
    [ -f "$artifact_path" ]
    artifact_validation=$($test_build/neper-self validate-em "$artifact_path")
    [ "$artifact_validation" = 'compiled module valid' ]
    cmp "$artifact_path" "$generic_instances_copy/$artifact_name.x64-linux.em"
done
generic_instances_edge=$($test_build/neper-self check-em-edge "$generic_instances_root_path" "$generic_instances_dep_path")
[ "$generic_instances_edge" = 'dependency current' ]
generic_instances_artifact_executable="$test_build/generic-instances-from-artifacts"
generic_instances_artifact_written=$($test_build/neper-self link-em "$generic_instances_artifact_executable" "$generic_instances_root_path" "$generic_instances_dep_path")
[ "$generic_instances_artifact_written" = 'artifact executable written' ]
chmod +x "$generic_instances_artifact_executable"
"$generic_instances_artifact_executable"
cmp "$generic_instances_artifact_executable" "$generic_instances_executable_path"
# Walk a compiled module's code section. The section directory is fixed, so the
# code section offset is at byte 112 (D320: no NIR section); each record is a 24-byte header followed by
# its machine code and its relocations.
em_code_count() {
    em_code=$(od -An -tu8 -j112 -N8 "$1" | tr -d ' ')
    od -An -tu4 -j"$em_code" -N4 "$1" | tr -d ' '
}
em_code_field() {
    em_code=$(od -An -tu8 -j112 -N8 "$1" | tr -d ' ')
    em_cursor=$((em_code + 4))
    em_index=0
    while [ "$em_index" -lt "$2" ]; do
        em_length=$(od -An -tu4 -j$((em_cursor + 16)) -N4 "$1" | tr -d ' ')
        em_relocations=$(od -An -tu4 -j$((em_cursor + 20)) -N4 "$1" | tr -d ' ')
        em_cursor=$((em_cursor + 24 + em_length + em_relocations * 28))
        em_index=$((em_index + 1))
    done
    if [ "$3" = 'instance' ]; then
        od -An -tu4 -j$((em_cursor + 4)) -N4 "$1" | tr -d ' '
    else
        od -An -tu8 -j$((em_cursor + 8)) -N8 "$1" | tr -d ' '
    fi
}
[ "$(em_code_count "$generic_instances_dep_path")" = '0' ]
# Seven instances plus `neper_report_failure`, the failure line's function (D199), which
# is code of the root module too.
[ "$(em_code_count "$generic_instances_root_path")" = '8' ]
folding_fixture="$repo/tests/selfhost/fixtures/link/generic_folding/src/main.e"
folding_direct="$test_build/generic-folding-selfhost"
folding_direct_written=$($test_build/neper-self emit-executable "$folding_fixture" "$repo" x64 linux "$folding_direct")
[ "$folding_direct_written" = 'executable written' ]
chmod +x "$folding_direct"
"$folding_direct"
folding_artifacts="$test_build/generic-folding"
mkdir -p "$folding_artifacts"
folding_written=$($test_build/neper-self emit-em-all "$folding_fixture" "$repo" x64 linux "$folding_artifacts")
[ "$folding_written" = 'compiled modules written' ]
[ "$(em_code_count "$folding_artifacts/lib.x64-linux.em")" = '0' ]
[ "$(em_code_count "$folding_artifacts/one.x64-linux.em")" = '2' ]
[ "$(em_code_count "$folding_artifacts/two.x64-linux.em")" = '2' ]
[ "$(em_code_field "$folding_artifacts/one.x64-linux.em" 1 instance)" = '1' ]
[ "$(em_code_field "$folding_artifacts/two.x64-linux.em" 1 instance)" = '1' ]
[ "$(em_code_field "$folding_artifacts/one.x64-linux.em" 1 hash)" = "$(em_code_field "$folding_artifacts/two.x64-linux.em" 1 hash)" ]
folded_executable="$test_build/generic-folding-from-artifacts"
folded_written=$($test_build/neper-self link-em "$folded_executable" "$folding_artifacts/main.x64-linux.em" "$folding_artifacts/one.x64-linux.em" "$folding_artifacts/two.x64-linux.em" "$folding_artifacts/lib.x64-linux.em")
[ "$folded_written" = 'artifact executable written' ]
chmod +x "$folded_executable"
"$folded_executable"
# A shared instance links byte-for-byte the same from artifacts as from source (D156).
cmp "$folded_executable" "$folding_direct"
bitwise_executable_path="$test_build/bitwise-selfhost"
bitwise_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/bitwise/src/main.e" "$repo" x64 linux "$bitwise_executable_path")
[ "$bitwise_executable_written" = 'executable written' ]
chmod +x "$bitwise_executable_path"
"$bitwise_executable_path"
division_executable_path="$test_build/division-selfhost"
division_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/division/src/main.e" "$repo" x64 linux "$division_executable_path")
[ "$division_executable_written" = 'executable written' ]
chmod +x "$division_executable_path"
"$division_executable_path"
shift_executable_path="$test_build/shifts-selfhost"
shift_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/shifts/src/main.e" "$repo" x64 linux "$shift_executable_path")
[ "$shift_executable_written" = 'executable written' ]
chmod +x "$shift_executable_path"
"$shift_executable_path"
locals_lowered=$($test_build/neper-self nir-file "$repo/tests/selfhost/fixtures/nir/locals/src/main.e" "$repo" x64 linux)
[ "$locals_lowered" = 'module nir ok' ]
locals_generated=$($test_build/neper-self codegen-file "$repo/tests/selfhost/fixtures/nir/locals/src/main.e" "$repo" x64 linux)
[ "$locals_generated" = 'module codegen ok' ]
storage_executable_path="$test_build/storage-selfhost"
storage_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/storage/src/main.e" "$repo" x64 linux "$storage_executable_path")
[ "$storage_executable_written" = 'executable written' ]
chmod +x "$storage_executable_path"
"$storage_executable_path"
aggregate_executable_path="$test_build/aggregate-selfhost"
aggregate_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/aggregate/src/main.e" "$repo" x64 linux "$aggregate_executable_path")
[ "$aggregate_executable_written" = 'executable written' ]
chmod +x "$aggregate_executable_path"
"$aggregate_executable_path"
advanced_executable_path="$test_build/advanced-selfhost"
advanced_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/advanced/src/main.e" "$repo" x64 linux "$advanced_executable_path")
[ "$advanced_executable_written" = 'executable written' ]
chmod +x "$advanced_executable_path"
"$advanced_executable_path"
constant_executable_path="$test_build/constant-folding-selfhost"
constant_executable_written=$($test_build/neper-self emit-executable "$repo/tests/neper0/constant-folding.e" "$repo" x64 linux "$constant_executable_path")
[ "$constant_executable_written" = 'executable written' ]
chmod +x "$constant_executable_path"
constant_output=$("$constant_executable_path")
[ "$constant_output" = 'constant folding ok' ]
generic_neper0_path="$test_build/generic-neper0-selfhost"
generic_neper0_written=$($test_build/neper-self emit-executable "$repo/tests/neper0/generic-function.e" "$repo" x64 linux "$generic_neper0_path")
[ "$generic_neper0_written" = 'executable written' ]
chmod +x "$generic_neper0_path"
generic_neper0_output=$("$generic_neper0_path")
[ "$generic_neper0_output" = 'generic function ok' ]
switch_executable_path="$test_build/enum-union-switch-selfhost"
switch_executable_written=$($test_build/neper-self emit-executable "$repo/tests/neper0/enum-union-switch.e" "$repo" x64 linux "$switch_executable_path")
[ "$switch_executable_written" = 'executable written' ]
chmod +x "$switch_executable_path"
switch_output=$("$switch_executable_path")
[ "$switch_output" = 'enum union switch ok' ]
defer_executable_path="$test_build/defer-selfhost"
defer_executable_written=$($test_build/neper-self emit-executable "$repo/tests/neper0/defer.e" "$repo" x64 linux "$defer_executable_path")
[ "$defer_executable_written" = 'executable written' ]
chmod +x "$defer_executable_path"
defer_output=$("$defer_executable_path")
[ "$defer_output" = 'defer ok' ]
protocol_executable_path="$test_build/protocol-iteration-selfhost"
protocol_executable_written=$($test_build/neper-self emit-executable "$repo/tests/neper0/protocol-iteration.e" "$repo" x64 linux "$protocol_executable_path")
[ "$protocol_executable_written" = 'executable written' ]
chmod +x "$protocol_executable_path"
protocol_output=$("$protocol_executable_path")
[ "$protocol_output" = 'protocol iteration ok' ]
hash_surface=$(sed -nE 's/^(type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*).*/\2/p' "$repo/lib/e/algo/hash.e")
expected_hash_surface='XxHash64
Crc32
fnv1a32
fnv1a64
xxhash64
xxhash64_init
xxhash64_update
xxhash64_done
crc32
crc32_init
crc32_update
crc32_done
adler32'
[ "$hash_surface" = "$expected_hash_surface" ]
hash_parsed=$($test_build/neper-self parse-file "$repo/lib/e/algo/hash.e")
[ "$hash_parsed" = 'parse file ok' ]
hash_executable_path="$test_build/algo-hash-selfhost"
hash_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_hash/src/main.e" "$repo" x64 linux "$hash_executable_path")
[ "$hash_executable_written" = 'executable written' ]
chmod +x "$hash_executable_path"
hash_output=$("$hash_executable_path")
[ "$hash_output" = 'algo hash ok' ]
bitset_surface=$(sed -nE 's/^(type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*).*/\2/p' "$repo/lib/e/algo/bitset.e")
expected_bitset_surface='BitSet
TooSmall
init
len
clear_all
fill_all
get
set
unset
toggle
count
first_set
next_set
union_in_place
intersect_in_place
difference_in_place
complement_in_place
is_subset
eq'
[ "$bitset_surface" = "$expected_bitset_surface" ]
bitset_parsed=$($test_build/neper-self parse-file "$repo/lib/e/algo/bitset.e")
[ "$bitset_parsed" = 'parse file ok' ]
bitset_executable_path="$test_build/algo-bitset-selfhost"
bitset_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_bitset/src/main.e" "$repo" x64 linux "$bitset_executable_path")
[ "$bitset_executable_written" = 'executable written' ]
chmod +x "$bitset_executable_path"
bitset_output=$("$bitset_executable_path")
[ "$bitset_output" = 'algo bitset ok' ]
ring_surface=$(sed -nE 's/^(type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*).*/\2/p' "$repo/lib/e/data/ring.e")
expected_ring_surface='Ring
Iter
init
len
capacity
push
push_overwrite
pop
peek
clear
iter
iter_next'
[ "$ring_surface" = "$expected_ring_surface" ]
ring_parsed=$($test_build/neper-self parse-file "$repo/lib/e/data/ring.e")
[ "$ring_parsed" = 'parse file ok' ]
ring_executable_path="$test_build/data-ring-selfhost"
ring_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_ring/src/main.e" "$repo" x64 linux "$ring_executable_path")
[ "$ring_executable_written" = 'executable written' ]
chmod +x "$ring_executable_path"
ring_output=$("$ring_executable_path")
[ "$ring_output" = 'data ring ok' ]
# `e.cancel` (D347, SL03): tokens, controls, deadlines and a request shared by threads.
for cancel_mode in '' '--release'; do
    cancel_path="$test_build/cancel-selfhost$cancel_mode"
    cancel_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/cancel/src/main.e" "$repo" x64 linux "$cancel_path" $cancel_mode)
    [ "$cancel_written" = 'executable written' ]
    chmod +x "$cancel_path"
    cancel_output=$("$cancel_path")
    [ "$cancel_output" = 'cancel ok' ]
done
# D330: a promoted local copied from a later-declared local and reassigned in the same block.
for promote_mode in '' '--release'; do
    promote_path="$test_build/promote-copy-selfhost$promote_mode"
    promote_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/promote_copy/src/main.e" "$repo" x64 linux "$promote_path" $promote_mode)
    [ "$promote_written" = 'executable written' ]
    chmod +x "$promote_path"
    promote_output=$("$promote_path")
    [ "$promote_output" = 'promote copy ok' ]
done
deque_surface=$(sed -nE 's/^(type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*).*/\2/p' "$repo/lib/e/data/deque.e")
expected_deque_surface='Deque
Iter
init
len
reserve
push_front
push_back
pop_front
pop_back
get
clear
iter
iter_next'
[ "$deque_surface" = "$expected_deque_surface" ]
deque_parsed=$($test_build/neper-self parse-file "$repo/lib/e/data/deque.e")
[ "$deque_parsed" = 'parse file ok' ]
deque_executable_path="$test_build/data-deque-selfhost"
deque_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_deque/src/main.e" "$repo" x64 linux "$deque_executable_path")
[ "$deque_executable_written" = 'executable written' ]
chmod +x "$deque_executable_path"
deque_output=$("$deque_executable_path")
[ "$deque_output" = 'data deque ok' ]
list_surface=$(sed -nE 's/^(type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*).*/\2/p' "$repo/lib/e/data/list.e")
expected_list_surface='List
Iter
init
from_slice
slice
slice_const
reserve
push
pop
insert
remove
clear
iter
iter_next'
[ "$list_surface" = "$expected_list_surface" ]
list_parsed=$($test_build/neper-self parse-file "$repo/lib/e/data/list.e")
[ "$list_parsed" = 'parse file ok' ]
list_executable_path="$test_build/data-list-selfhost"
list_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_list/src/main.e" "$repo" x64 linux "$list_executable_path")
[ "$list_executable_written" = 'executable written' ]
chmod +x "$list_executable_path"
list_output=$("$list_executable_path")
[ "$list_output" = 'data list ok' ]
sort_surface=$(grep -E '^(type|fn|error|const|var) ' "$repo/lib/e/algo/sort.e" | sed -E 's/^(type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*).*/\2/')
expected_sort_surface='in_place
in_place_by
stable_in_place
stable_in_place_by
radix_u32_in_place
radix_u64_in_place
is_sorted'
[ "$sort_surface" = "$expected_sort_surface" ]
sort_parsed=$($test_build/neper-self parse-file "$repo/lib/e/algo/sort.e")
[ "$sort_parsed" = 'parse file ok' ]
sort_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_sort/src/main.e" "$repo" x64 linux "$test_build/algo-sort-selfhost")
[ "$sort_executable_written" = 'executable written' ]
chmod +x "$test_build/algo-sort-selfhost"
sort_output=$($test_build/algo-sort-selfhost)
[ "$sort_output" = 'algo sort ok' ]
heap_surface=$(grep -E '^(type|fn|error|const|var) ' "$repo/lib/e/data/heap.e" | sed -E 's/^(type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*).*/\2/')
expected_heap_surface='Heap
HeapBy
Iter
init
from_slice
len
push
peek
pop
clear
init_by
from_slice_by
len_by
push_by
peek_by
pop_by
clear_by
heapify_in_place
heapify_in_place_by
iter
iter_by
iter_next'
[ "$heap_surface" = "$expected_heap_surface" ]
heap_parsed=$($test_build/neper-self parse-file "$repo/lib/e/data/heap.e")
[ "$heap_parsed" = 'parse file ok' ]
heap_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_heap/src/main.e" "$repo" x64 linux "$test_build/data-heap-selfhost")
[ "$heap_executable_written" = 'executable written' ]
chmod +x "$test_build/data-heap-selfhost"
heap_output=$($test_build/data-heap-selfhost)
[ "$heap_output" = 'data heap ok' ]
same_name_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/generic_same_name/src/main.e" "$repo" x64 linux "$test_build/generic-same-name-selfhost")
[ "$same_name_written" = 'executable written' ]
chmod +x "$test_build/generic-same-name-selfhost"
"$test_build/generic-same-name-selfhost"
os_helper_path="$test_build/os-spawn-helper-selfhost"
os_helper_written=$($test_build/neper-self emit-executable "$repo/tests/neper0/os-spawn-helper.e" "$repo" x64 linux "$os_helper_path")
[ "$os_helper_written" = 'executable written' ]
chmod +x "$os_helper_path"
os_intrinsic_path="$test_build/os-intrinsics-selfhost"
os_intrinsic_written=$($test_build/neper-self emit-executable "$repo/tests/neper0/os-intrinsics.e" "$repo" x64 linux "$os_intrinsic_path")
[ "$os_intrinsic_written" = 'executable written' ]
chmod +x "$os_intrinsic_path"
os_intrinsic_output_path="$test_build/os-intrinsics-output.txt"
os_intrinsic_output=$("$os_intrinsic_path" "$os_intrinsic_output_path" "$repo/tests/neper0" "$os_helper_path")
[ "$os_intrinsic_output" = 'intrinsic ok' ]
[ "$(cat "$os_intrinsic_output_path")" = 'neper os!' ]
own_compiler_path="$test_build/neper-own"
own_compiler_written=$($test_build/neper-self emit-executable "$repo/src/main.e" "$repo" x64 linux "$own_compiler_path")
[ "$own_compiler_written" = 'executable written' ]
chmod +x "$own_compiler_path"
own_self_test=$("$own_compiler_path" self-test)
[ "$own_self_test" = 'selfhost lexer ok' ]
own_advanced_path="$test_build/advanced-own"
own_advanced_written=$("$own_compiler_path" emit-executable "$repo/tests/selfhost/fixtures/link/advanced/src/main.e" "$repo" x64 linux "$own_advanced_path")
[ "$own_advanced_written" = 'executable written' ]
chmod +x "$own_advanced_path"
"$own_advanced_path"
stable_compiler_path="$test_build/neper-own-stable"
stable_compiler_written=$("$own_compiler_path" emit-executable "$repo/src/main.e" "$repo" x64 linux "$stable_compiler_path")
[ "$stable_compiler_written" = 'executable written' ]
cmp "$own_compiler_path" "$stable_compiler_path"
# `-j N` and `--perturb` (D331): the compiler built on one worker, and on three with
# the schedule turned around, is the stable stage byte for byte.
for jobs_case in '-j 1' '-j 3 --perturb'; do
    jobs_path="$test_build/neper-own-jobs$(echo "$jobs_case" | tr -d ' -')"
    jobs_written=$("$own_compiler_path" emit-executable "$repo/src/main.e" "$repo" x64 linux "$jobs_path" $jobs_case)
    [ "$jobs_written" = 'executable written' ]
    cmp "$jobs_path" "$stable_compiler_path"
done
# The deterministic half of the performance gate (D506, H25): sc500k's image and arenas against the static baseline.
python3 "$repo/benchmarks/baseline/static.py" --compiler "$own_compiler_path" --repo "$repo" --host linux --out "$test_build/static-linux.json" --fixtures "$test_build/baseline-fixtures"
python3 "$repo/benchmarks/baseline/gate.py" "$test_build/static-linux.json" --baseline "$repo/benchmarks/baseline/results/static-linux.json"
# The formatted compiler (D525, H10): built from every module through `fmt -`, it builds the stable stage.
formatted_src="$test_build/formatted-src"
rm -rf "$formatted_src"
mkdir -p "$formatted_src/src"
for module in "$repo"/src/*; do
    case "$module" in
        *.e) "$test_build/neper-self" fmt - < "$module" > "$formatted_src/src/$(basename "$module")" ;;
        *) cp "$module" "$formatted_src/src/" ;;
    esac
done
formatted_written=$("$own_compiler_path" emit-executable "$formatted_src/src/main.e" "$repo" x64 linux "$test_build/neper-formatted")
[ "$formatted_written" = 'executable written' ]
chmod +x "$test_build/neper-formatted"
by_formatted_written=$("$test_build/neper-formatted" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-by-formatted")
[ "$by_formatted_written" = 'executable written' ]
cmp "$test_build/neper-by-formatted" "$stable_compiler_path"
# The compiler without its comments (D526, H10): built from `src/` with every comment blanked, it is the stable stage.
python3 "$repo/benchmarks/metamorphic/strip_comments.py" "$test_build/neper-self" "$repo/src" "$test_build/blanked-src/src"
blanked_written=$("$own_compiler_path" emit-executable "$test_build/blanked-src/src/main.e" "$repo" x64 linux "$test_build/neper-blanked")
[ "$blanked_written" = 'executable written' ]
cmp "$test_build/neper-blanked" "$stable_compiler_path"
# The compiler with its literals hoisted (D527, H03, H10): built from `src/` with every typed literal a constant, it is the stable stage.
python3 "$repo/benchmarks/metamorphic/hoist_constants.py" "$test_build/neper-self" "$repo/src" "$test_build/hoisted-src/src"
hoisted_written=$("$own_compiler_path" emit-executable "$test_build/hoisted-src/src/main.e" "$repo" x64 linux "$test_build/neper-hoisted")
[ "$hoisted_written" = 'executable written' ]
cmp "$test_build/neper-hoisted" "$stable_compiler_path"
# The compiler with its locals renamed (D528, H10, H17): built from `src/` with every local renamed through the index, it is the stable stage.
python3 "$repo/benchmarks/metamorphic/rename_locals.py" "$test_build/neper-self" "$repo" "$repo/src" "$test_build/renamed-src/src" linux
renamed_written=$("$own_compiler_path" emit-executable "$test_build/renamed-src/src/main.e" "$repo" x64 linux "$test_build/neper-renamed")
[ "$renamed_written" = 'executable written' ]
cmp "$test_build/neper-renamed" "$stable_compiler_path"
# The compiler with its functions and types renamed (D529, H10, H17): built from `src/` renamed through the index, it builds the stable stage.
python3 "$repo/benchmarks/metamorphic/rename_symbols.py" "$test_build/neper-self" "$repo" "$repo/src" "$test_build/resymbolled-src/src" linux
resymbolled_written=$("$own_compiler_path" emit-executable "$test_build/resymbolled-src/src/main.e" "$repo" x64 linux "$test_build/neper-resymbolled")
[ "$resymbolled_written" = 'executable written' ]
chmod +x "$test_build/neper-resymbolled"
by_resymbolled_written=$("$test_build/neper-resymbolled" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-by-resymbolled")
[ "$by_resymbolled_written" = 'executable written' ]
cmp "$test_build/neper-by-resymbolled" "$stable_compiler_path"
# The compiler with every struct's fields reversed (D530, H10): built from `src/` so, it builds the stable stage.
python3 "$repo/benchmarks/metamorphic/reverse_fields.py" "$test_build/neper-self" "$repo/src" "$test_build/reversed-src/src"
reversed_written=$("$own_compiler_path" emit-executable "$test_build/reversed-src/src/main.e" "$repo" x64 linux "$test_build/neper-reversed")
[ "$reversed_written" = 'executable written' ]
chmod +x "$test_build/neper-reversed"
by_reversed_written=$("$test_build/neper-reversed" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-by-reversed")
[ "$by_reversed_written" = 'executable written' ]
cmp "$test_build/neper-by-reversed" "$stable_compiler_path"
# The compiler with its declarations reversed (D531, H10): built from `src/` so, it builds the stable stage.
python3 "$repo/benchmarks/metamorphic/reorder_declarations.py" "$repo/src" "$test_build/reordered-src/src"
reordered_written=$("$own_compiler_path" emit-executable "$test_build/reordered-src/src/main.e" "$repo" x64 linux "$test_build/neper-reordered")
[ "$reordered_written" = 'executable written' ]
chmod +x "$test_build/neper-reordered"
by_reordered_written=$("$test_build/neper-reordered" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-by-reordered")
[ "$by_reordered_written" = 'executable written' ]
cmp "$test_build/neper-by-reordered" "$stable_compiler_path"
# The standard library turned too (D532, H10): the compiler built against `lib/` blanked, then hoisted, is the stable stage.
for lib_turn in "strip_comments.py lib-blanked" "hoist_constants.py lib-hoisted"; do
    set -- $lib_turn
    lib_project="$test_build/$2"
    rm -rf "$lib_project"
    mkdir -p "$lib_project"
    cp -r "$repo/src" "$lib_project/src"
    python3 "$repo/benchmarks/metamorphic/$1" "$test_build/neper-self" "$repo/lib" "$lib_project/lib"
    lib_written=$("$own_compiler_path" emit-executable "$lib_project/src/main.e" "$lib_project" x64 linux "$test_build/neper-$2")
    [ "$lib_written" = 'executable written' ]
    cmp "$test_build/neper-$2" "$stable_compiler_path"
done
# The turns in release (D533, H10): the release self-build twice, the image-holding trees, the turn compilers, the library.
[ "$("$own_compiler_path" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-own-release" --release)" = 'executable written' ]
[ "$("$own_compiler_path" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-own-release-again" --release)" = 'executable written' ]
cmp "$test_build/neper-own-release-again" "$test_build/neper-own-release"
for release_tree in blanked-src hoisted-src renamed-src; do
    [ "$("$own_compiler_path" emit-executable "$test_build/$release_tree/src/main.e" "$repo" x64 linux "$test_build/neper-release-$release_tree" --release)" = 'executable written' ]
    cmp "$test_build/neper-release-$release_tree" "$test_build/neper-own-release"
done
for turn_compiler in neper-formatted neper-resymbolled neper-reversed neper-reordered; do
    [ "$("$test_build/$turn_compiler" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/release-by-$turn_compiler" --release)" = 'executable written' ]
    cmp "$test_build/release-by-$turn_compiler" "$test_build/neper-own-release"
done
for lib_turn in lib-blanked lib-hoisted; do
    [ "$("$own_compiler_path" emit-executable "$test_build/$lib_turn/src/main.e" "$test_build/$lib_turn" x64 linux "$test_build/neper-$lib_turn-release" --release)" = 'executable written' ]
    cmp "$test_build/neper-$lib_turn-release" "$test_build/neper-own-release"
done
# The warm path under the turns (D534, H14): cold with artifacts, then blanked (all stable), hoisted lex (rebuilt), renamed check (rebuilt); the cold image every time.
warm_project="$test_build/warm-turns"
rm -rf "$warm_project"
mkdir -p "$warm_project"
cp -r "$repo/src" "$warm_project/src"
warm_manifest="$warm_project/.neper/debug/build-manifest.json"
[ "$("$own_compiler_path" emit-executable "$warm_project/src/main.e" "$repo" x64 linux "$test_build/neper-warm-turns-cold" --incremental)" = 'executable written' ]
cp "$test_build/blanked-src/src/"*.e "$warm_project/src/"
[ "$("$own_compiler_path" emit-executable "$warm_project/src/main.e" "$repo" x64 linux "$test_build/neper-warm-turns" --incremental)" = 'executable written' ]
python3 -c "import json,sys; m=json.load(open(sys.argv[1])); sys.exit(0 if all(e['reason']=='stable' for e in m['incremental']) else 1)" "$warm_manifest"
cmp "$test_build/neper-warm-turns" "$test_build/neper-warm-turns-cold"
cp "$test_build/hoisted-src/src/lex.e" "$warm_project/src/lex.e"
[ "$("$own_compiler_path" emit-executable "$warm_project/src/main.e" "$repo" x64 linux "$test_build/neper-warm-turns" --incremental)" = 'executable written' ]
python3 "$repo/scripts/check_incremental.py" "$warm_manifest" lex=rebuilt:source-changed check=kept:edges-hold main=kept:edges-hold binary=kept:stable
cmp "$test_build/neper-warm-turns" "$test_build/neper-warm-turns-cold"
cp "$test_build/renamed-src/src/check.e" "$warm_project/src/check.e"
[ "$("$own_compiler_path" emit-executable "$warm_project/src/main.e" "$repo" x64 linux "$test_build/neper-warm-turns" --incremental)" = 'executable written' ]
python3 "$repo/scripts/check_incremental.py" "$warm_manifest" check=rebuilt:source-changed lex=kept:stable main=kept:edges-hold
cmp "$test_build/neper-warm-turns" "$test_build/neper-warm-turns-cold"
# The warm path under the turns in release (D536, H14): the same three edits over a cold release build with artifacts.
warm_release="$test_build/warm-turns-release"
rm -rf "$warm_release"
mkdir -p "$warm_release"
cp -r "$repo/src" "$warm_release/src"
warm_release_manifest="$warm_release/.neper/release/build-manifest.json"
[ "$("$own_compiler_path" emit-executable "$warm_release/src/main.e" "$repo" x64 linux "$test_build/neper-warm-release-cold" --release --incremental)" = 'executable written' ]
cp "$test_build/blanked-src/src/"*.e "$warm_release/src/"
[ "$("$own_compiler_path" emit-executable "$warm_release/src/main.e" "$repo" x64 linux "$test_build/neper-warm-release" --release --incremental)" = 'executable written' ]
python3 -c "import json,sys; m=json.load(open(sys.argv[1])); sys.exit(0 if all(e['reason']=='stable' for e in m['incremental']) else 1)" "$warm_release_manifest"
cmp "$test_build/neper-warm-release" "$test_build/neper-warm-release-cold"
cp "$test_build/hoisted-src/src/lex.e" "$warm_release/src/lex.e"
[ "$("$own_compiler_path" emit-executable "$warm_release/src/main.e" "$repo" x64 linux "$test_build/neper-warm-release" --release --incremental)" = 'executable written' ]
python3 "$repo/scripts/check_incremental.py" "$warm_release_manifest" lex=rebuilt:source-changed binary=kept:stable
cmp "$test_build/neper-warm-release" "$test_build/neper-warm-release-cold"
cp "$test_build/renamed-src/src/check.e" "$warm_release/src/check.e"
[ "$("$own_compiler_path" emit-executable "$warm_release/src/main.e" "$repo" x64 linux "$test_build/neper-warm-release" --release --incremental)" = 'executable written' ]
python3 "$repo/scripts/check_incremental.py" "$warm_release_manifest" check=rebuilt:source-changed lex=kept:stable
cmp "$test_build/neper-warm-release" "$test_build/neper-warm-release-cold"
# The plans over the compiler (D537, H17, H29): check.same and check.Type renamed by plan, applied, and the result builds the stable stage.
# And the signature plans (D538): the parameters of check.same reordered, then one added.
plan_turn_command() {
    case "$1" in
        plan-fn) "$test_build/neper-self" plan-rename-file src/main.e "$repo" x64 linux --json --symbol check.same --to alike ;;
        plan-type) "$test_build/neper-self" plan-rename-file src/main.e "$repo" x64 linux --json --symbol check.Type --to Kind2 ;;
        plan-order) "$test_build/neper-self" plan-change-signature-file src/main.e "$repo" x64 linux --json --symbol check.same --order 1,0 ;;
        plan-add) "$test_build/neper-self" plan-add-parameter-file src/main.e "$repo" x64 linux --json --symbol check.same --parameter "extra: usize" --argument 0usize ;;
    esac
}
for plan_turn in plan-fn plan-type plan-order plan-add; do
    set -- x x "$plan_turn"
    plan_project="$test_build/$3"
    rm -rf "$plan_project"
    mkdir -p "$plan_project"
    cp -r "$repo/src" "$plan_project/src"
    (cd "$plan_project" && plan_turn_command "$3" > "$test_build/$3.jsonl")
    "$test_build/neper-self" apply-plan "$test_build/$3.jsonl" --root "$plan_project/src" > /dev/null
    [ "$("$own_compiler_path" emit-executable "$plan_project/src/main.e" "$repo" x64 linux "$test_build/neper-$3")" = 'executable written' ]
    chmod +x "$test_build/neper-$3"
    [ "$("$test_build/neper-$3" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-by-$3")" = 'executable written' ]
    cmp "$test_build/neper-by-$3" "$stable_compiler_path"
done
# The deadline inside a function (D540, H16): --fault-cancel at the 4096th statement is inside the check, at the 12288th inside the lowering.
python3 -c "lines=['use e.os','','fn main() -> err {','    var x = 0usize']+['    x = x + 1usize']*8000+['    os.exit(i32(x % 200usize))','    ret ok','}']; open('$test_build/long-function.e','w').write('\n'.join(lines)+'\n')"
[ "$("$test_build/neper-self" emit-executable "$test_build/long-function.e" "$repo" x64 linux "$test_build/long-function" 2>/dev/null)" = 'executable written' ]
for cancel_case in "4096 the body sweep, inside a function" "12288 lowering, inside a function"; do
    cancel_ticks="${cancel_case%% *}"
    cancel_place="${cancel_case#* }"
    rm -f "$test_build/long-function"
    cancel_status=0
    "$test_build/neper-self" emit-executable "$test_build/long-function.e" "$repo" x64 linux "$test_build/long-function" --fault-cancel "$cancel_ticks" --json > "$test_build/long-function-cancel.jsonl" 2>/dev/null || cancel_status=$?
    [ "$cancel_status" -eq 3 ]
    grep -q "\"cancelled_after\":\"$cancel_place\"" "$test_build/long-function-cancel.jsonl"
    [ ! -e "$test_build/long-function" ]
done
# The buffers grow to the function (D541, H14): thirty thousand and seven statements in one function build and answer 7.
python3 -c "lines=['use e.os','','fn main() -> err {','    var x = 0usize']+['    x = x + 1usize']*30007+['    os.exit(i32(x % 200usize))','    ret ok','}']; open('$test_build/longer-function.e','w').write('\n'.join(lines)+'\n')"
[ "$("$test_build/neper-self" emit-executable "$test_build/longer-function.e" "$repo" x64 linux "$test_build/longer-function" 2>/dev/null)" = 'executable written' ]
chmod +x "$test_build/longer-function"
longer_status=0
"$test_build/longer-function" || longer_status=$?
[ "$longer_status" -eq 7 ]
branches_lowered=$($test_build/neper-self nir-file "$repo/tests/selfhost/fixtures/nir/branches/src/main.e" "$repo" x64 linux)
[ "$branches_lowered" = 'module nir ok' ]
branches_generated=$($test_build/neper-self codegen-file "$repo/tests/selfhost/fixtures/nir/branches/src/main.e" "$repo" x64 linux)
[ "$branches_generated" = 'module codegen ok' ]
loops_lowered=$($test_build/neper-self nir-file "$repo/tests/selfhost/fixtures/nir/loops/src/main.e" "$repo" x64 linux)
[ "$loops_lowered" = 'module nir ok' ]
loops_generated=$($test_build/neper-self codegen-file "$repo/tests/selfhost/fixtures/nir/loops/src/main.e" "$repo" x64 linux)
[ "$loops_generated" = 'module codegen ok' ]
control_executable_path="$test_build/control-selfhost"
control_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/control/src/main.e" "$repo" x64 linux "$control_executable_path")
[ "$control_executable_written" = 'executable written' ]
chmod +x "$control_executable_path"
"$control_executable_path"
# `else if` (D245): the grammar's chained form, lowered as the nested if it is.
else_if_executable_path="$test_build/else-if-selfhost"
else_if_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/else_if/src/main.e" "$repo" x64 linux "$else_if_executable_path")
[ "$else_if_executable_written" = 'executable written' ]
chmod +x "$else_if_executable_path"
"$else_if_executable_path"
# `ret (expr) op y` (D247): a grouped return value that carries a binary operator.
ret_group_executable_path="$test_build/ret-group-selfhost"
ret_group_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ret_group/src/main.e" "$repo" x64 linux "$ret_group_executable_path")
[ "$ret_group_executable_written" = 'executable written' ]
chmod +x "$ret_group_executable_path"
"$ret_group_executable_path"
# `e.math.fixed` (D267): Q16.16 arithmetic and angles in turns.
math_fixed_executable_path="$test_build/math-fixed-selfhost"
math_fixed_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_fixed/src/main.e" "$repo" x64 linux "$math_fixed_executable_path")
[ "$math_fixed_executable_written" = 'executable written' ]
chmod +x "$math_fixed_executable_path"
"$math_fixed_executable_path"
# `e.game.loop` and `e.game.ecs` (D268): the fixed step and the entity store.
game_core_executable_path="$test_build/game-core-selfhost"
game_core_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_core/src/main.e" "$repo" x64 linux "$game_core_executable_path")
[ "$game_core_executable_written" = 'executable written' ]
chmod +x "$game_core_executable_path"
"$game_core_executable_path"
# `e.game.grid` and `e.game.tilemap` (D270): coordinates and layered tile grids.
game_grid_executable_path="$test_build/game-grid-selfhost"
game_grid_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_grid/src/main.e" "$repo" x64 linux "$game_grid_executable_path")
[ "$game_grid_executable_written" = 'executable written' ]
chmod +x "$game_grid_executable_path"
"$game_grid_executable_path"
# `e.game.collide2d` and `e.game.vision` (D272): swept boxes and shadowcast fog.
game_sight_executable_path="$test_build/game-sight-selfhost"
game_sight_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_sight/src/main.e" "$repo" x64 linux "$game_sight_executable_path")
[ "$game_sight_executable_written" = 'executable written' ]
chmod +x "$game_sight_executable_path"
"$game_sight_executable_path"
# `e.game.dialog` and `e.game.particle` (D279): branching conversation and particle pools.
game_story_executable_path="$test_build/game-story-selfhost"
game_story_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_story/src/main.e" "$repo" x64 linux "$game_story_executable_path")
[ "$game_story_executable_written" = 'executable written' ]
chmod +x "$game_story_executable_path"
"$game_story_executable_path"
# `e.game.sprite` and `e.game.camera` (D282): clip playback and the ordered draw list.
game_view_executable_path="$test_build/game-view-selfhost"
game_view_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_view/src/main.e" "$repo" x64 linux "$game_view_executable_path")
[ "$game_view_executable_written" = 'executable written' ]
chmod +x "$game_view_executable_path"
"$game_view_executable_path"
# `e.game.ai` and `e.game.input` (D289): steering, behaviour trees, A* and input buffering.
game_mind_executable_path="$test_build/game-mind-selfhost"
game_mind_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_mind/src/main.e" "$repo" x64 linux "$game_mind_executable_path")
[ "$game_mind_executable_written" = 'executable written' ]
chmod +x "$game_mind_executable_path"
"$game_mind_executable_path"
# `e.net.snapshot` and `e.game.netsync` (D296): quantised deltas, prediction and rollback.
game_net_executable_path="$test_build/game-net-selfhost"
game_net_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_net/src/main.e" "$repo" x64 linux "$game_net_executable_path")
[ "$game_net_executable_written" = 'executable written' ]
chmod +x "$game_net_executable_path"
"$game_net_executable_path"
module_executable_path="$test_build/modules-selfhost"
module_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/modules/src/main.e" "$repo" x64 linux "$module_executable_path")
[ "$module_executable_written" = 'executable written' ]
chmod +x "$module_executable_path"
"$module_executable_path"
collision_executable_path="$test_build/error-collision-selfhost"
if collision_output=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/error_collision/src/main.e" "$repo" x64 linux "$collision_executable_path" 2>&1); then
    printf '%s\n' 'error hash collision unexpectedly linked' >&2
    exit 1
fi
case "$collision_output" in *'main.E49B7D00B'*'main.E9E692E7E'*) ;; *) printf '%s\n' 'error hash collision did not name both qualified errors' >&2; exit 1 ;; esac
[ ! -e "$collision_executable_path" ]
module_artifact_path="$test_build/modules.x64-linux.em"
module_artifact_copy_path="$test_build/modules-copy.x64-linux.em"
module_artifact_written=$($test_build/neper-self emit-em "$repo/tests/selfhost/fixtures/link/modules/src/main.e" "$repo" x64 linux "$module_artifact_path")
[ "$module_artifact_written" = 'compiled module written' ]
module_artifact_copy_written=$($test_build/neper-self emit-em "$repo/tests/selfhost/fixtures/link/modules/src/main.e" "$repo" x64 linux "$module_artifact_copy_path")
[ "$module_artifact_copy_written" = 'compiled module written' ]
cmp "$module_artifact_path" "$module_artifact_copy_path"
[ "$(head -c 4 "$module_artifact_path")" = 'NEPM' ]
[ "$(od -An -tu2 -j4 -N2 "$module_artifact_path" | tr -d ' ')" = '10' ]
[ "$(od -An -tu2 -j6 -N2 "$module_artifact_path" | tr -d ' ')" = '32' ]
[ "$(od -An -tu4 -j20 -N4 "$module_artifact_path" | tr -d ' ')" = '9' ]
[ "$(od -An -tu8 -j96 -N8 "$module_artifact_path" | tr -d ' ')" -gt 4 ]
interface_artifact_path="$test_build/interface.x64-linux.em"
interface_artifact_written=$($test_build/neper-self emit-em "$repo/tests/selfhost/fixtures/em/interface/src/main.e" "$repo" x64 linux "$interface_artifact_path")
[ "$interface_artifact_written" = 'compiled module written' ]
interface_offset=$(od -An -tu8 -j64 -N8 "$interface_artifact_path" | tr -d ' ')
[ "$(od -An -tu4 -j$((interface_offset + 8)) -N4 "$interface_artifact_path" | tr -d ' ')" = '6' ]
[ "$(od -An -tu8 -j$((interface_offset + 28)) -N8 "$interface_artifact_path" | tr -d ' ')" -ne 0 ]
hash_module_artifacts="$test_build/hash-module"
mkdir -p "$hash_module_artifacts"
hash_module_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/em/hash_module/src/main.e" "$repo" x64 linux "$hash_module_artifacts")
[ "$hash_module_artifacts_written" = 'compiled modules written' ]
[ -f "$hash_module_artifacts/main.x64-linux.em" ]
[ -f "$hash_module_artifacts/e.algo.hash.x64-linux.em" ]
hash_module_validation=$($test_build/neper-self validate-em "$hash_module_artifacts/main.x64-linux.em")
[ "$hash_module_validation" = 'compiled module valid' ]
hash_module_interface_offset=$(od -An -tu8 -j64 -N8 "$hash_module_artifacts/e.algo.hash.x64-linux.em" | tr -d ' ')
[ "$(od -An -tu4 -j$((hash_module_interface_offset + 8)) -N4 "$hash_module_artifacts/e.algo.hash.x64-linux.em" | tr -d ' ')" = '13' ]
hash_runtime_artifacts="$test_build/hash-runtime"
mkdir -p "$hash_runtime_artifacts"
hash_runtime_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/link/algo_hash/src/main.e" "$repo" x64 linux "$hash_runtime_artifacts")
[ "$hash_runtime_artifacts_written" = 'compiled modules written' ]
for artifact_name in main e.algo.hash e.io e.mem e.os; do
    artifact_path="$hash_runtime_artifacts/$artifact_name.x64-linux.em"
    [ -f "$artifact_path" ]
    artifact_validation=$($test_build/neper-self validate-em "$artifact_path")
    [ "$artifact_validation" = 'compiled module valid' ]
done
host_dependency_artifacts="$test_build/host-dependency"
mkdir -p "$host_dependency_artifacts"
host_dependency_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/em/host_dependency/src/main.e" "$repo" x64 linux "$host_dependency_artifacts")
[ "$host_dependency_artifacts_written" = 'compiled modules written' ]
runtime_host_edge=$($test_build/neper-self check-em-edge "$host_dependency_artifacts/main.x64-linux.em" "$host_dependency_artifacts/e.os.x64-linux.em")
[ "$runtime_host_edge" = 'dependency current' ]
all_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/link/modules/src/main.e" "$repo" x64 linux "$test_build")
[ "$all_artifacts_written" = 'compiled modules written' ]
[ -f "$test_build/main.x64-linux.em" ]
[ -f "$test_build/dep.x64-linux.em" ]
cmp "$module_artifact_path" "$test_build/main.x64-linux.em"
validated_artifact=$($test_build/neper-self validate-em "$test_build/main.x64-linux.em")
[ "$validated_artifact" = 'compiled module valid' ]
artifact_executable_path="$test_build/modules-from-artifacts"
artifact_executable_written=$($test_build/neper-self link-em "$artifact_executable_path" "$test_build/main.x64-linux.em" "$test_build/dep.x64-linux.em")
[ "$artifact_executable_written" = 'artifact executable written' ]
chmod +x "$artifact_executable_path"
"$artifact_executable_path"
cmp "$artifact_executable_path" "$module_executable_path"
current_edge=$($test_build/neper-self check-em-edge "$test_build/main.x64-linux.em" "$test_build/dep.x64-linux.em")
[ "$current_edge" = 'dependency current' ]
merged_error_tables=$($test_build/neper-self check-em-errors "$test_build/main.x64-linux.em" "$test_build/dep.x64-linux.em")
[ "$merged_error_tables" = 'error tables merged' ]
collision_artifacts="$test_build/error-collision"
mkdir -p "$collision_artifacts"
collision_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/em/error_collision/src/main.e" "$repo" x64 linux "$collision_artifacts")
[ "$collision_artifacts_written" = 'compiled modules written' ]
if artifact_collision_output=$($test_build/neper-self check-em-errors "$collision_artifacts/main.x64-linux.em" "$collision_artifacts/dep.x64-linux.em" 2>&1); then
    printf '%s\n' 'compiled-module error hash collision unexpectedly merged' >&2
    exit 1
fi
case "$artifact_collision_output" in *'main.E08DED258'*'dep.E29EBB918'*) ;; *) printf '%s\n' 'compiled-module collision did not name both qualified errors' >&2; exit 1 ;; esac
artifact_collision_executable="$collision_artifacts/collision"
if artifact_link_collision_output=$($test_build/neper-self link-em "$artifact_collision_executable" "$collision_artifacts/main.x64-linux.em" "$collision_artifacts/dep.x64-linux.em" 2>&1); then
    printf '%s\n' 'artifact linker accepted an error hash collision' >&2
    exit 1
fi
case "$artifact_link_collision_output" in *'main.E08DED258'*'dep.E29EBB918'*) ;; *) printf '%s\n' 'artifact linker collision did not name both errors' >&2; exit 1 ;; esac
[ ! -e "$artifact_collision_executable" ]
body_edit_artifacts="$test_build/body-edit"
signature_edit_artifacts="$test_build/signature-edit"
mkdir -p "$body_edit_artifacts" "$signature_edit_artifacts"
body_edit_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/em/body_edit/src/main.e" "$repo" x64 linux "$body_edit_artifacts")
[ "$body_edit_written" = 'compiled modules written' ]
signature_edit_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/em/signature_edit/src/main.e" "$repo" x64 linux "$signature_edit_artifacts")
[ "$signature_edit_written" = 'compiled modules written' ]
body_edge=$($test_build/neper-self check-em-edge "$test_build/main.x64-linux.em" "$body_edit_artifacts/dep.x64-linux.em")
[ "$body_edge" = 'dependency current' ]
if signature_edge=$($test_build/neper-self check-em-edge "$test_build/main.x64-linux.em" "$signature_edit_artifacts/dep.x64-linux.em" 2>&1); then
    printf '%s\n' 'signature edit left dependency current' >&2
    exit 1
fi
case "$signature_edge" in *'dependency stale'*) ;; *) printf '%s\n' 'signature dependency returned the wrong stale result' >&2; exit 1 ;; esac
value_base_artifacts="$test_build/value-base"
value_edit_artifacts="$test_build/value-edit"
mkdir -p "$value_base_artifacts" "$value_edit_artifacts"
value_base_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/em/value_base/src/main.e" "$repo" x64 linux "$value_base_artifacts")
[ "$value_base_written" = 'compiled modules written' ]
value_edit_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/em/value_edit/src/main.e" "$repo" x64 linux "$value_edit_artifacts")
[ "$value_edit_written" = 'compiled modules written' ]
current_value_edge=$($test_build/neper-self check-em-edge "$value_base_artifacts/main.x64-linux.em" "$value_base_artifacts/dep.x64-linux.em")
[ "$current_value_edge" = 'dependency current' ]
if stale_value_edge=$($test_build/neper-self check-em-edge "$value_base_artifacts/main.x64-linux.em" "$value_edit_artifacts/dep.x64-linux.em" 2>&1); then
    printf '%s\n' 'constant value edit left dependency current' >&2
    exit 1
fi
case "$stale_value_edge" in *'dependency stale'*) ;; *) printf '%s\n' 'constant value dependency returned the wrong stale result' >&2; exit 1 ;; esac
scalar_ops_lowered=$($test_build/neper-self nir-file "$repo/tests/selfhost/fixtures/nir/scalar_ops/src/main.e" "$repo" x64 linux)
[ "$scalar_ops_lowered" = 'module nir ok' ]
scalar_ops_generated=$($test_build/neper-self codegen-file "$repo/tests/selfhost/fixtures/nir/scalar_ops/src/main.e" "$repo" x64 linux)
[ "$scalar_ops_generated" = 'module codegen ok' ]
composite_checked=$($test_build/neper-self check-file "$check_root/composite_valid/src/main.e" "$repo" x64 linux)
[ "$composite_checked" = 'module check ok' ]
qualified_checked=$($test_build/neper-self check-file "$check_root/qualified_valid/src/main.e" "$repo" x64 linux)
[ "$qualified_checked" = 'module check ok' ]
alias_checked=$($test_build/neper-self check-file "$check_root/alias_valid/src/main.e" "$repo" x64 linux)
[ "$alias_checked" = 'module check ok' ]
constant_checked=$($test_build/neper-self check-file "$check_root/constant_valid/src/main.e" "$repo" x64 linux)
[ "$constant_checked" = 'module check ok' ]
constant_generated=$($test_build/neper-self codegen-file "$check_root/constant_valid/src/main.e" "$repo" x64 linux)
[ "$constant_generated" = 'module codegen ok' ]
constant_alias_checked=$($test_build/neper-self check-file "$check_root/constant_alias_array_valid/src/main.e" "$repo" x64 linux)
[ "$constant_alias_checked" = 'module check ok' ]
constant_operators_checked=$($test_build/neper-self check-file "$check_root/constant_operators_valid/src/main.e" "$repo" x64 linux)
[ "$constant_operators_checked" = 'module check ok' ]
intrinsic_checked=$($test_build/neper-self check-file "$check_root/intrinsic_valid/src/main.e" "$repo" x64 linux)
[ "$intrinsic_checked" = 'module check ok' ]
multi_result_checked=$($test_build/neper-self check-file "$check_root/multi_result_valid/src/main.e" "$repo" x64 linux)
[ "$multi_result_checked" = 'module check ok' ]
try_checked=$($test_build/neper-self check-file "$check_root/try_valid/src/main.e" "$repo" x64 linux)
[ "$try_checked" = 'module check ok' ]
intrinsic_multi_checked=$($test_build/neper-self check-file "$check_root/intrinsic_multi_valid/src/main.e" "$repo" x64 linux)
[ "$intrinsic_multi_checked" = 'module check ok' ]
alloc_checked=$($test_build/neper-self check-file "$check_root/alloc_valid/src/main.e" "$repo" x64 linux)
[ "$alloc_checked" = 'module check ok' ]
generic_checked=$($test_build/neper-self check-file "$check_root/generic_valid/src/main.e" "$repo" x64 linux)
[ "$generic_checked" = 'module check ok' ]
generic_declaration_checked=$($test_build/neper-self check-file "$check_root/generic_declaration_valid/src/main.e" "$repo" x64 linux)
[ "$generic_declaration_checked" = 'module check ok' ]
qualified_generic_checked=$($test_build/neper-self check-file "$check_root/generic_qualified_valid/src/main.e" "$repo" x64 linux)
[ "$qualified_generic_checked" = 'module check ok' ]
generic_multi_checked=$($test_build/neper-self check-file "$check_root/generic_multi_valid/src/main.e" "$repo" x64 linux)
[ "$generic_multi_checked" = 'module check ok' ]
index_checked=$($test_build/neper-self check-file "$check_root/index_valid/src/main.e" "$repo" x64 linux)
[ "$index_checked" = 'module check ok' ]
aggregate_checked=$($test_build/neper-self check-file "$check_root/aggregate_valid/src/main.e" "$repo" x64 linux)
[ "$aggregate_checked" = 'module check ok' ]
generic_aggregate_checked=$($test_build/neper-self check-file "$check_root/generic_aggregate_valid/src/main.e" "$repo" x64 linux)
[ "$generic_aggregate_checked" = 'module check ok' ]
nested_generic_aggregate_checked=$($test_build/neper-self check-file "$check_root/nested_generic_aggregate_valid/src/main.e" "$repo" x64 linux)
[ "$nested_generic_aggregate_checked" = 'module check ok' ]
generic_aggregate_alias_checked=$($test_build/neper-self check-file "$check_root/generic_aggregate_alias_valid/src/main.e" "$repo" x64 linux)
[ "$generic_aggregate_alias_checked" = 'module check ok' ]
compound_checked=$($test_build/neper-self check-file "$check_root/compound_valid/src/main.e" "$repo" x64 linux)
[ "$compound_checked" = 'module check ok' ]
language_constructs_checked=$($test_build/neper-self check-file "$check_root/language_constructs_valid/src/main.e" "$repo" x64 linux)
[ "$language_constructs_checked" = 'module check ok' ]
defer_checked=$($test_build/neper-self check-file "$check_root/defer_valid/src/main.e" "$repo" x64 linux)
[ "$defer_checked" = 'module check ok' ]
switch_checked=$($test_build/neper-self check-file "$check_root/switch_valid/src/main.e" "$repo" x64 linux)
[ "$switch_checked" = 'module check ok' ]
tag_checked=$($test_build/neper-self check-file "$check_root/tag_valid/src/main.e" "$repo" x64 linux)
[ "$tag_checked" = 'module check ok' ]
expect_check_error() {
    fixture=$1
    expected=$2
    if check_output=$($test_build/neper-self check-file "$check_root/$fixture/src/main.e" "$repo" x64 linux 2>&1); then
        printf '%s\n' "scalar type-check fixture $fixture unexpectedly succeeded" >&2
        exit 1
    fi
    case "$check_output" in
        *": error[E-"*"]: "*) ;;
        *) printf '%s\n' "scalar type-check fixture $fixture returned the wrong result" >&2; exit 1 ;;
    esac
}
expect_check_error missing_context MissingContext
expect_check_error binding_mismatch TypeMismatch
expect_check_error return_mismatch InvalidReturn
expect_check_error condition_mismatch InvalidCondition
expect_check_error argument_mismatch TypeMismatch
expect_check_error argument_count ArgumentCount
expect_check_error invalid_operator InvalidOperator
expect_check_error numeric_mismatch TypeMismatch
expect_check_error immutable_assignment ImmutableAssignment
expect_check_error void_value TypeMismatch
expect_check_error cast_untyped MissingContext
expect_check_error cast_mismatch TypeMismatch
expect_check_error address_of_slice TypeMismatch
expect_check_error bool_ordering InvalidOperator
expect_check_error void_parameter InvalidType
expect_check_error missing_return_value InvalidReturn
expect_check_error missing_return MissingReturn
expect_check_error const_slice_to_mutable TypeMismatch
expect_check_error const_pointer_to_mutable TypeMismatch
expect_check_error array_length_mismatch TypeMismatch
expect_check_error array_element_mismatch TypeMismatch
expect_check_error array_length_type TypeMismatch
expect_check_error array_length_overflow TypeMismatch
expect_check_error array_length_division_zero TypeMismatch
expect_check_error inferred_array_type Unsupported
expect_check_error void_slice InvalidType
expect_check_error void_pointer_deref InvalidOperator
expect_check_error nil_without_context MissingContext
expect_check_error qualified_argument_mismatch TypeMismatch
expect_check_error qualified_argument_count ArgumentCount
expect_check_error qualified_not_callable UnknownCallable
expect_check_error alias_cycle AliasCycle
expect_check_error alias_pointer_cycle AliasCycle
expect_check_error alias_mismatch TypeMismatch
expect_check_error alias_const_to_mutable TypeMismatch
expect_check_error alias_void_parameter InvalidType
expect_check_error alias_void_slice InvalidType
expect_check_error alias_void_array InvalidType
expect_check_error generic_type_bare Unsupported
expect_check_error constant_cycle ConstantCycle
expect_check_error constant_type_mismatch TypeMismatch
expect_check_error constant_missing_context MissingContext
expect_check_error constant_overflow ConstantOverflow
expect_check_error constant_arithmetic_overflow ConstantOverflow
expect_check_error constant_signed_overflow ConstantOverflow
expect_check_error constant_operand_overflow ConstantOverflow
expect_check_error constant_unsigned_negative ConstantOverflow
expect_check_error constant_unsigned_operator InvalidOperator
expect_check_error constant_invalid_reference InvalidConstant
expect_check_error constant_division_zero InvalidConstant
expect_check_error constant_shift_range InvalidConstant
expect_check_error constant_shift_signed InvalidOperator
expect_check_error constant_bitwise_missing_context MissingContext
expect_check_error array_length_shift_range TypeMismatch
expect_check_error array_length_constant_type TypeMismatch
expect_check_error intrinsic_argument_count ArgumentCount
expect_check_error intrinsic_argument_mismatch TypeMismatch
expect_check_error intrinsic_pointer_mismatch TypeMismatch
expect_check_error intrinsic_result_mismatch TypeMismatch
expect_check_error intrinsic_multi_argument_mismatch TypeMismatch
expect_check_error intrinsic_multi_unsupported ArgumentCount
expect_check_error multi_result_count ArgumentCount
expect_check_error multi_result_assignment_type TypeMismatch
expect_check_error multi_result_invalid_return InvalidReturn
expect_check_error multi_result_invalid_type InvalidReturn
expect_check_error tuple_annotation InvalidType
expect_check_error try_invalid_callee InvalidTry
expect_check_error try_invalid_caller InvalidTry
expect_check_error try_statement_results ArgumentCount
expect_check_error try_binding_count ArgumentCount
expect_check_error call_result_ignored ArgumentCount
expect_check_error multi_return_void InvalidType
expect_check_error error_return_not_last InvalidType
expect_check_error extern_error_return InvalidType
expect_check_error extern_multi_return InvalidType
expect_check_error extern_slice_parameter InvalidType
expect_check_error extern_slice_return InvalidType
expect_check_error variadic_narrow_argument TypeMismatch
expect_check_error unreachable_argument TypeMismatch
expect_check_error enum_cast_width TypeMismatch
expect_check_error trunc_float_argument TypeMismatch
expect_check_error intrinsic_generic_unsupported ArgumentCount
expect_check_error alloc_argument_type TypeMismatch
expect_check_error alloc_arena_type TypeMismatch
expect_check_error alloc_argument_count ArgumentCount
expect_check_error alloc_missing_type_argument ArgumentCount
expect_check_error alloc_type_argument_count ArgumentCount
expect_check_error alloc_value_type_argument InvalidType
expect_check_error alloc_void InvalidType
expect_check_error alloc_result_type TypeMismatch
expect_check_error generic_untyped_inference MissingContext
expect_check_error generic_conflicting_inference TypeMismatch
expect_check_error generic_argument_count ArgumentCount
expect_check_error generic_argument_kind InvalidType
expect_check_error generic_body_mismatch InvalidReturn
expect_check_error generic_integer_conflict TypeMismatch
expect_check_error generic_partial_missing MissingContext
expect_check_error generic_declaration_binding TypeMismatch
expect_check_error generic_declaration_operator InvalidOperator
expect_check_error generic_declaration_missing_return MissingReturn
expect_check_error generic_declaration_call_count ArgumentCount
expect_check_error generic_declaration_index InvalidReturn
expect_check_error generic_declaration_generic_arity ArgumentCount
expect_check_error generic_declaration_unknown_field InvalidType
expect_check_error generic_declaration_invalid_len InvalidOperator
expect_check_error generic_declaration_pointer_arithmetic InvalidOperator
expect_check_error generic_declaration_literal_field InvalidType
expect_check_error generic_declaration_array_count InvalidReturn
expect_check_error generic_declaration_switch_body TypeMismatch
expect_check_error generic_declaration_duplicate_default DuplicateCase
expect_check_error generic_declaration_const_pointer ImmutableAssignment
expect_check_error generic_declaration_instantiation_operator InvalidOperator
expect_check_error index_type TypeMismatch
expect_check_error index_non_indexable InvalidOperator
expect_check_error index_count ArgumentCount
expect_check_error index_empty ArgumentCount
expect_check_error slice_bound_type TypeMismatch
expect_check_error const_slice_assignment ImmutableAssignment
expect_check_error array_parameter_assignment ImmutableAssignment
expect_check_error string_assignment ImmutableAssignment
expect_check_error pointer_index InvalidOperator
expect_check_error len_non_indexable InvalidOperator
expect_check_error const_pointer_assignment ImmutableAssignment
expect_check_error array_slice_mutability TypeMismatch
expect_check_error aggregate_missing_field ArgumentCount
expect_check_error aggregate_duplicate_field ArgumentCount
expect_check_error aggregate_unknown_field InvalidType
expect_check_error aggregate_field_mismatch InvalidReturn
expect_check_error array_literal_count InvalidReturn
expect_check_error array_literal_type InvalidReturn
expect_check_error immutable_field_assignment ImmutableAssignment
expect_check_error union_literal_count ArgumentCount
expect_check_error tagged_payload_missing InvalidReturn
expect_check_error tagged_void_payload InvalidReturn
expect_check_error unknown_field_access InvalidType
expect_check_error generic_aggregate_arity ArgumentCount
expect_check_error generic_aggregate_kind InvalidType
expect_check_error generic_aggregate_identity InvalidReturn
expect_check_error generic_aggregate_field_type InvalidReturn
expect_check_error nested_generic_aggregate_mismatch InvalidReturn
expect_check_error compound_unsupported InvalidOperator
expect_check_error enum_unknown_member InvalidType
expect_check_error enum_type_mismatch InvalidReturn
expect_check_error shift_signed_count InvalidOperator
expect_check_error shift_untyped_value InvalidOperator
expect_check_error for_non_iterable InvalidOperator
expect_check_error break_outside_loop Unsupported
expect_check_error defer_return InvalidReturn
expect_check_error defer_try InvalidTry
expect_check_error defer_outer_break Unsupported
expect_check_error defer_fallible_call ArgumentCount
expect_check_error switch_non_exhaustive NonExhaustiveSwitch
expect_check_error switch_duplicate_case DuplicateCase
expect_check_error switch_duplicate_default DuplicateCase
expect_check_error switch_non_constant InvalidConstant
expect_check_error switch_invalid_subject InvalidSwitch
expect_check_error switch_invalid_capture InvalidSwitch
expect_check_error tag_invalid_type InvalidType
expect_check_error tag_unknown_member InvalidType
expect_check_error tag_capture InvalidSwitch
expect_check_error switch_missing_return MissingReturn
for source in "$repo"/tests/neper0/*.e; do
    fixture=$(basename "$source")
    case "$fixture" in
        *-error.e)
            if [ "$fixture" = os-error.e ]; then
                parity_output=$($test_build/neper-self check-file "$source" "$repo" x64 linux)
                [ "$parity_output" = 'module check ok' ]
            else
                if parity_output=$($test_build/neper-self check-file "$source" "$repo" x64 linux 2>&1); then
                    printf '%s\n' "self-hosted front end accepted rejected neper-0 fixture $fixture" >&2
                    exit 1
                else
                    parity_exit=$?
                fi
                if reference_output=$($neper build "$source" --output "$test_build/diagnostic-reference" 2>&1); then
                    printf '%s\n' "bootstrap accepted rejected neper-0 fixture $fixture" >&2
                    exit 1
                else
                    reference_exit=$?
                fi
                if [ "$parity_exit" -ne "$reference_exit" ] || [ "$parity_output" != "$reference_output" ]; then
                    printf '%s\n' "self-hosted diagnostic parity failed for neper-0 fixture $fixture" >&2
                    exit 1
                fi
            fi
            ;;
        *)
            parity_output=$($test_build/neper-self check-file "$source" "$repo" x64 linux)
            [ "$parity_output" = 'module check ok' ]
            ;;
    esac
done
scope_root="$repo/tests/selfhost/fixtures/scope"
valid_scopes=$($test_build/neper-self resolve-file "$scope_root/valid/src/main.e" "$repo" x64 linux)
[ "$valid_scopes" = 'module resolve ok' ]
if module_shadow=$($test_build/neper-self resolve-file "$scope_root/module_shadow/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'module name shadowing unexpectedly succeeded' >&2; exit 1; fi
case "$module_shadow" in *'error: resolve.ModuleShadow'*) ;; *) printf '%s\n' 'module shadow returned the wrong error' >&2; exit 1 ;; esac
if qualifier_shadow=$($test_build/neper-self resolve-file "$scope_root/qualifier_shadow/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'qualifier shadowing unexpectedly succeeded' >&2; exit 1; fi
case "$qualifier_shadow" in *'error: resolve.ModuleShadow'*) ;; *) printf '%s\n' 'qualifier shadow returned the wrong error' >&2; exit 1 ;; esac
if duplicate_local=$($test_build/neper-self resolve-file "$scope_root/duplicate_local/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'same-block local reuse unexpectedly succeeded' >&2; exit 1; fi
case "$duplicate_local" in *'error: resolve.DuplicateLocal'*) ;; *) printf '%s\n' 'duplicate local returned the wrong error' >&2; exit 1 ;; esac
if nested_shadow=$($test_build/neper-self resolve-file "$scope_root/nested_shadow/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'nested local shadowing unexpectedly succeeded' >&2; exit 1; fi
case "$nested_shadow" in *'error: resolve.DuplicateLocal'*) ;; *) printf '%s\n' 'nested shadow returned the wrong error' >&2; exit 1 ;; esac
if duplicate_parameter=$($test_build/neper-self resolve-file "$scope_root/duplicate_parameter/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'duplicate parameter unexpectedly succeeded' >&2; exit 1; fi
case "$duplicate_parameter" in *'error: resolve.DuplicateLocal'*) ;; *) printf '%s\n' 'duplicate parameter returned the wrong error' >&2; exit 1 ;; esac
if parameter_shadow=$($test_build/neper-self resolve-file "$scope_root/parameter_shadow/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'parameter/module shadowing unexpectedly succeeded' >&2; exit 1; fi
case "$parameter_shadow" in *'error: resolve.ModuleShadow'*) ;; *) printf '%s\n' 'parameter shadow returned the wrong error' >&2; exit 1 ;; esac
if reserved_local=$($test_build/neper-self resolve-file "$scope_root/reserved_local/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'reserved local unexpectedly succeeded' >&2; exit 1; fi
case "$reserved_local" in *'error: resolve.ReservedLocal'*) ;; *) printf '%s\n' 'reserved local returned the wrong error' >&2; exit 1 ;; esac
if tuple_duplicate=$($test_build/neper-self resolve-file "$scope_root/tuple_duplicate/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'tuple binding duplicate unexpectedly succeeded' >&2; exit 1; fi
case "$tuple_duplicate" in *'error: resolve.DuplicateLocal'*) ;; *) printf '%s\n' 'tuple duplicate returned the wrong error' >&2; exit 1 ;; esac
if for_shadow=$($test_build/neper-self resolve-file "$scope_root/for_shadow/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'for binding shadowing unexpectedly succeeded' >&2; exit 1; fi
case "$for_shadow" in *'error: resolve.DuplicateLocal'*) ;; *) printf '%s\n' 'for shadow returned the wrong error' >&2; exit 1 ;; esac
if switch_capture=$($test_build/neper-self resolve-file "$scope_root/switch_capture/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'switch capture shadowing unexpectedly succeeded' >&2; exit 1; fi
case "$switch_capture" in *'error: resolve.DuplicateLocal'*) ;; *) printf '%s\n' 'switch capture returned the wrong error' >&2; exit 1 ;; esac
if shared_duplicate=$($test_build/neper-self resolve-file "$scope_root/shared_duplicate/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'shared local duplicate unexpectedly succeeded' >&2; exit 1; fi
case "$shared_duplicate" in *'error: resolve.DuplicateLocal'*) ;; *) printf '%s\n' 'shared duplicate returned the wrong error' >&2; exit 1 ;; esac
if declaration_duplicate=$($test_build/neper-self resolve-file "$scope_root/declaration_duplicate/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'duplicate module-scope declaration unexpectedly succeeded' >&2; exit 1; fi
case "$declaration_duplicate" in *'error: resolve.DuplicateName'*) ;; *) printf '%s\n' 'duplicate declaration returned the wrong error' >&2; exit 1 ;; esac
if qualifier_collision=$($test_build/neper-self resolve-file "$scope_root/qualifier_collision/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'declaration over a use qualifier unexpectedly succeeded' >&2; exit 1; fi
case "$qualifier_collision" in *'error: resolve.QualifierCollision'*) ;; *) printf '%s\n' 'qualifier collision returned the wrong error' >&2; exit 1 ;; esac
if reserved_declaration=$($test_build/neper-self resolve-file "$scope_root/reserved_declaration/src/main.e" "$repo" x64 linux 2>&1); then printf '%s\n' 'reserved declaration name unexpectedly succeeded' >&2; exit 1; fi
case "$reserved_declaration" in *'error: resolve.ReservedName'*) ;; *) printf '%s\n' 'reserved declaration returned the wrong error' >&2; exit 1 ;; esac
# Every spec section 5 and section 14 name collision reports an exact token, the
# offending name and its registered docs/diagnostics.md code.
check_name_diagnostic() {
    if name_output=$($test_build/neper-self check-file "$scope_root/$1/src/main.e" "$repo" x64 linux 2>&1); then
        printf '%s\n' "name collision fixture $1 was accepted" >&2
        exit 1
    fi
    case "$name_output" in
        *"$2"*) ;;
        *) printf '%s\n' "name collision diagnostic for $1 is wrong: $name_output" >&2; exit 1 ;;
    esac
}
check_name_diagnostic module_shadow 'main.e:4:9: error[E-NAME-0003]: `helper` already names a module-scope function; a local or parameter may not reuse it'
check_name_diagnostic parameter_shadow 'main.e:2:8: error[E-NAME-0003]: `value` already names a module-scope function; a local or parameter may not reuse it'
check_name_diagnostic qualifier_shadow 'main.e:4:9: error[E-NAME-0003]: `d` already names a module-scope use qualifier; a local or parameter may not reuse it'
check_name_diagnostic duplicate_local 'main.e:3:9: error[E-NAME-0003]: `value` is already bound in an active scope'
check_name_diagnostic duplicate_parameter 'main.e:1:20: error[E-NAME-0003]: `value` is already bound in an active scope'
check_name_diagnostic reserved_local 'main.e:2:9: error[E-NAME-0003]: `u8` is a reserved name and cannot name a local or parameter'
check_name_diagnostic declaration_duplicate 'main.e:3:4: error[E-NAME-0001]: `Thing` already names a module-scope error; each name may be declared once per namespace'
check_name_diagnostic qualifier_collision 'main.e:3:4: error[E-NAME-0002]: `d` collides with a use qualifier in this module'
check_name_diagnostic reserved_declaration 'main.e:1:4: error[E-NAME-0003]: `u8` is a reserved name and cannot name a declaration'
capacity_source=''
i=0
while [ "$i" -lt 260 ]; do
    capacity_source="${capacity_source}error Capacity${i}
"
    i=$((i + 1))
done
capacity_items='0u8'
i=1
while [ "$i" -lt 130 ]; do
    capacity_items="${capacity_items}, 0u8"
    i=$((i + 1))
done
capacity_source="${capacity_source}fn capacity() {
    let values = [_]u8{ ${capacity_items} }
}
"
capacity_parse=$($test_build/neper-self parse "$capacity_source")
[ "$capacity_parse" = 'parse ok' ]
if invalid=$($test_build/neper-self scan '#' 2>&1); then
    printf '%s\n' 'invalid source unexpectedly succeeded' >&2
    exit 1
fi
case "$invalid" in
    *lex.InvalidSource*) ;;
    *) printf '%s\n' 'invalid source returned the wrong error' >&2; exit 1 ;;
esac
if invalid_parse=$($test_build/neper-self parse 'fn broken() -> err {' 2>&1); then
    printf '%s\n' 'invalid syntax unexpectedly succeeded' >&2
    exit 1
fi
case "$invalid_parse" in
    *'<argument>:1:21: error[E-SYNTAX-9999]: unexpected end of file'*) ;;
    *) printf '%s\n' 'invalid syntax returned the wrong error' >&2; exit 1 ;;
esac
# Spec section 5: a keyword in a binding position is rejected by name and reason,
# not as a bare syntax error, because it reads as an ordinary name.
check_reserved_binding() {
    if reserved_output=$($test_build/neper-self check-file "$scope_root/$1/src/main.e" "$repo" x64 linux 2>&1); then
        printf '%s\n' "reserved binding $1 unexpectedly checked" >&2
        exit 1
    fi
    case "$reserved_output" in
        *"$2"*) ;;
        *) printf '%s\n' "reserved binding diagnostic for $1 is wrong: $reserved_output" >&2; exit 1 ;;
    esac
}
check_reserved_binding reserved_binding_let 'main.e:2:9: error[E-NAME-0003]: `zero` is a keyword and cannot name a local or parameter'
check_reserved_binding reserved_binding_parameter 'main.e:1:8: error[E-NAME-0003]: `zero` is a keyword and cannot name a local or parameter'

module_output=$($neper run "$repo/tests/selfhost/fixtures/modules/src/main.e" \
    --output "$test_build/modules")
[ "$module_output" = 'module loading ok' ]

if diagnostic_output=$($neper build \
    "$repo/tests/selfhost/fixtures/diagnostics/src/main.e" \
    --output "$test_build/diagnostics" 2>&1); then
    printf '%s\n' 'imported-module diagnostic unexpectedly succeeded' >&2
    exit 1
fi
case "$diagnostic_output" in
    *broken.e:1:1:' error[E-NAME-9999]'*) ;;
    *) printf '%s\n' 'imported-module diagnostic source failed' >&2; exit 1 ;;
esac


if cycle_output=$($neper build "$repo/tests/selfhost/fixtures/cycle/src/main.e" \
    --output "$test_build/cycle" 2>&1); then
    printf '%s\n' 'module import cycle unexpectedly succeeded' >&2
    exit 1
fi
case "$cycle_output" in
    *'module import cycle: cycle.a -> cycle.b -> cycle.a'*) ;;
    *) printf '%s\n' 'module import cycle rejection failed' >&2; exit 1 ;;
esac

printf '%s\n' 'selfhost tests passed'
