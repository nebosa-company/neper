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
    *'error: graph.ImportCycle'*) ;;
    *) printf '%s\n' 'module import cycle returned the wrong error' >&2; exit 1 ;;
esac
if duplicate_graph=$($test_build/neper-self graph-file "$graph_root/duplicate/src/main.e" "$repo" x64 linux '' 2>&1); then
    printf '%s\n' 'duplicate source-root module unexpectedly succeeded' >&2
    exit 1
fi
case "$duplicate_graph" in
    *'error: graph.DuplicateModule'*) ;;
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
    *'error: project.ModuleNotFound'*) ;;
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
# A slice is formattable under section 4 but needs the expansion to recurse into an
# element at a time, which it does not do yet, so the build stops rather than quietly
# formatting nothing. Rejected at lowering, not at checking, so it needs an emission.
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
check_protocol_diagnostic generic_instance_field_leak 'main.e:8:5: error[E-TYPE-9999]: type checking failed: check.InvalidType'
check_protocol_diagnostic thread_create_context 'main.e:16:5: error[E-TYPE-0002]: initializer type does not match binding'
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
check_protocol_diagnostic atomic_load_release 'main.e:8:34: error[E-TYPE-9999]: `atomic.load` may not take the ordering `.Release`'
check_protocol_diagnostic atomic_store_acquire 'main.e:8:33: error[E-TYPE-9999]: `atomic.store` may not take the ordering `.Acquire`'
check_protocol_diagnostic atomic_cas_failure 'main.e:9:65: error[E-TYPE-9999]: `atomic.cas` may not take the ordering `.SeqCst`'
check_protocol_diagnostic atomic_element 'main.e:5:14: error[E-TYPE-9999]: `Atomic[f64]` is not a type: an atomic holds an integer or a pointer'
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
# code section offset is at byte 136; each record is a 24-byte header followed by
# its machine code and its relocations.
em_code_count() {
    em_code=$(od -An -tu8 -j136 -N8 "$1" | tr -d ' ')
    od -An -tu4 -j"$em_code" -N4 "$1" | tr -d ' '
}
em_code_field() {
    em_code=$(od -An -tu8 -j136 -N8 "$1" | tr -d ' ')
    em_cursor=$((em_code + 4))
    em_index=0
    while [ "$em_index" -lt "$2" ]; do
        em_length=$(od -An -tu4 -j$((em_cursor + 16)) -N4 "$1" | tr -d ' ')
        em_relocations=$(od -An -tu4 -j$((em_cursor + 20)) -N4 "$1" | tr -d ' ')
        em_cursor=$((em_cursor + 24 + em_length + em_relocations * 20))
        em_index=$((em_index + 1))
    done
    if [ "$3" = 'instance' ]; then
        od -An -tu4 -j$((em_cursor + 4)) -N4 "$1" | tr -d ' '
    else
        od -An -tu8 -j$((em_cursor + 8)) -N8 "$1" | tr -d ' '
    fi
}
[ "$(em_code_count "$generic_instances_dep_path")" = '0' ]
[ "$(em_code_count "$generic_instances_root_path")" = '7' ]
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
[ "$(od -An -tu2 -j4 -N2 "$module_artifact_path" | tr -d ' ')" = '3' ]
[ "$(od -An -tu2 -j6 -N2 "$module_artifact_path" | tr -d ' ')" = '32' ]
[ "$(od -An -tu4 -j20 -N4 "$module_artifact_path" | tr -d ' ')" = '7' ]
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
