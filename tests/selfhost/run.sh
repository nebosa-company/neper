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
python3 "$repo/scripts/check_module_surfaces.py" --compiler "$test_build/neper-self" --arch x64 --os linux
# The bootstrap's rules for `src/` (D794), before the next ten-minute build finds one.
python3 "$repo/scripts/lint_bootstrap.py" "$repo/src"
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
# H06's semantic-law properties: supplied equality is reflexive, symmetric and
# transitive over a finite domain, and equal values always have equal hashes.
protocol_law_supplied_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/protocol_law_supplied/src/main.e" "$repo" x64 linux "$test_build/protocol-law-supplied-selfhost")
[ "$protocol_law_supplied_written" = 'executable written' ]
chmod +x "$test_build/protocol-law-supplied-selfhost"
"$test_build/protocol-law-supplied-selfhost"
# The same harness accepts a coherent declared pair and detects an intentionally
# incoherent one, proving the property check is not vacuous.
protocol_law_declared_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/protocol_law_declared/src/main.e" "$repo" x64 linux "$test_build/protocol-law-declared-selfhost")
[ "$protocol_law_declared_written" = 'executable written' ]
chmod +x "$test_build/protocol-law-declared-selfhost"
"$test_build/protocol-law-declared-selfhost"
# Implicit dispatch and an explicit function strategy agree over the same task;
# a reverse strategy remains observably distinct across the module boundary.
protocol_strategy_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/protocol_strategy_equivalence/src/main.e" "$repo" x64 linux "$test_build/protocol-strategy-equivalence-selfhost")
[ "$protocol_strategy_written" = 'executable written' ]
chmod +x "$test_build/protocol-strategy-equivalence-selfhost"
"$test_build/protocol-strategy-equivalence-selfhost"
# A recursively forwarded strategy produces exactly 66 instances. One fewer is a
# structured budget refusal; the exact budget builds and executes.
protocol_recursive_status=0
protocol_recursive_rejected=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/protocol_strategy_recursive/src/main.e" "$repo" x64 linux "$test_build/protocol-strategy-recursive-selfhost" --json --instances 65) || protocol_recursive_status=$?
[ "$protocol_recursive_status" = 1 ] || { echo "recursive strategy budget refusal exited $protocol_recursive_status" >&2; exit 1; }
case "$protocol_recursive_rejected" in
    *'"code":"E-COMPTIME-0001"'*'66 instances'*'budget of 65'*) ;;
    *) echo 'recursive strategy specialization returned the wrong budget diagnostic' >&2; exit 1 ;;
esac
protocol_recursive_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/protocol_strategy_recursive/src/main.e" "$repo" x64 linux "$test_build/protocol-strategy-recursive-selfhost" --instances 66)
[ "$protocol_recursive_written" = 'executable written' ]
chmod +x "$test_build/protocol-strategy-recursive-selfhost"
"$test_build/protocol-strategy-recursive-selfhost"
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
# assert is that the two spellings answer alike. Both use relative paths, so their
# scratch working directories decide where entries land and nothing escapes them.
fs_scratch="$test_build/fs-scratch"
mkdir -p "$fs_scratch"
os_fs_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_fs/src/main.e" "$repo" x64 linux "$test_build/os-fs-selfhost")
[ "$os_fs_written" = 'executable written' ]
chmod +x "$test_build/os-fs-selfhost"
(cd "$fs_scratch" && "$test_build/os-fs-selfhost")
fs_basics_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fs_basics/src/main.e" "$repo" x64 linux "$test_build/fs-basics-selfhost")
[ "$fs_basics_written" = 'executable written' ]
chmod +x "$test_build/fs-basics-selfhost"
# The moved-root contract needs native directory-handle semantics. DrvFS/9p keeps a
# renamed directory invisible until its old handle closes, so neither the old handle nor
# the new name can reach it. Run the public e.fs contract on the target's native filesystem;
# os_fs above still exercises the mounted repository filesystem separately.
fs_native_scratch=$(mktemp -d "${TMPDIR:-/tmp}/neper-fs.XXXXXX")
trap 'rm -rf "$fs_native_scratch"' EXIT HUP INT TERM
if [ "$(stat -c %d "$fs_native_scratch")" != "$(stat -c %d "$test_build")" ]; then
    (cd "$fs_native_scratch" && NEPER_CROSS_VOLUME_DIR="$test_build" NEPER_PARTIAL_DURABILITY_TARGET=/dev/null "$test_build/fs-basics-selfhost")
else
    (cd "$fs_native_scratch" && env -u NEPER_CROSS_VOLUME_DIR NEPER_PARTIAL_DURABILITY_TARGET=/dev/null "$test_build/fs-basics-selfhost")
fi
rm -rf "$fs_native_scratch"
trap - EXIT HUP INT TERM
# `e.proc` against a real child, which is the fixture's own image. Besides the legacy output
# path, `run` checks independent limits, pre-start cancellation, a live contained deadline,
# explicit outcomes, invalid grace, retained writers and the complete forced-shutdown grace.
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
# A function selected in brackets is a compile-time strategy and part of the
# specialization identity: two choices make two direct-call bodies.
comptime_function_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/comptime_function_strategy/src/main.e" "$repo" x64 linux "$test_build/comptime-function-strategy-selfhost")
[ "$comptime_function_written" = 'executable written' ]
chmod +x "$test_build/comptime-function-strategy-selfhost"
"$test_build/comptime-function-strategy-selfhost"
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
# The same fixture under --cpu x64-v3 (D765): one AVX2 instruction per thirty-two-byte vector, debug and release.
for avx_mode in "debug" "release --release"; do
    set -- $avx_mode
    avx_name="$1"
    shift
    [ "$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/simd_lanes/src/main.e" "$repo" x64 linux "$test_build/simd-lanes-v3-$avx_name" --cpu x64-v3 "$@")" = 'executable written' ]
    chmod +x "$test_build/simd-lanes-v3-$avx_name"
    "$test_build/simd-lanes-v3-$avx_name"
done
avx_bad=0
"$test_build/neper-self" emit-executable "$repo/tests/selfhost/fixtures/link/simd_lanes/src/main.e" "$repo" x64 linux "$test_build/simd-lanes-v9" --cpu x64-v9 > /dev/null 2>&1 || avx_bad=$?
[ "$avx_bad" -ne 0 ]
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
# `e.text.regex` (D768): Pike-VM matching, leftmost-first preference, captures, the three options and `$n` replacement.
text_regex_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_regex/src/main.e" "$repo" x64 linux "$test_build/text-regex-selfhost")
[ "$text_regex_written" = 'executable written' ]
chmod +x "$test_build/text-regex-selfhost"
text_regex_output=$("$test_build/text-regex-selfhost")
[ "$text_regex_output" = 'text regex ok' ]
# `e.text.shape` (D769): cmap, GSUB single and ligature lookups, feature ranges, GPOS pair kerning and legacy `kern` over a synthetic font.
text_shape_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_shape/src/main.e" "$repo" x64 linux "$test_build/text-shape-selfhost")
[ "$text_shape_written" = 'executable written' ]
chmod +x "$test_build/text-shape-selfhost"
text_shape_output=$("$test_build/text-shape-selfhost")
[ "$text_shape_output" = 'text shape ok' ]
# `e.text.locale` (D771): tags, grouped numbers, currency layout, LDML dates, natural comparison and Turkic case over the built-in CLDR subset and a loaded database.
text_locale_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_locale/src/main.e" "$repo" x64 linux "$test_build/text-locale-selfhost")
[ "$text_locale_written" = 'executable written' ]
chmod +x "$test_build/text-locale-selfhost"
text_locale_output=$("$test_build/text-locale-selfhost")
[ "$text_locale_output" = 'text locale ok' ]
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
# `generic_value` (D772): a generic function instantiated by name stands as a value, a typed trampoline behind a `*void` callback.
generic_value_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/generic_value/src/main.e" "$repo" x64 linux "$test_build/generic-value-selfhost")
[ "$generic_value_written" = 'executable written' ]
chmod +x "$test_build/generic-value-selfhost"
generic_value_output=$("$test_build/generic-value-selfhost")
[ "$generic_value_output" = 'generic value ok' ]
# `e.task` (D772): a bounded pool over the trampoline instances -- tasks, futures, failure, cancellation, bounded waits, wait_any, a full ring, parallel_for, close.
task_pool_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/task_pool/src/main.e" "$repo" x64 linux "$test_build/task-pool-selfhost")
[ "$task_pool_written" = 'executable written' ]
chmod +x "$test_build/task-pool-selfhost"
task_pool_output=$("$test_build/task-pool-selfhost")
[ "$task_pool_output" = 'task pool ok' ]
# `e.async.io` (D773): connect and accept through the loop, callback read and write, progress, wait_any, cancellation, an expired deadline, take's refusals.
async_io_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/async_io/src/main.e" "$repo" x64 linux "$test_build/async-io-selfhost")
[ "$async_io_written" = 'executable written' ]
chmod +x "$test_build/async-io-selfhost"
async_io_output=$("$test_build/async-io-selfhost")
[ "$async_io_output" = 'async io ok' ]
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
# `e.algo.search`: binary search and its bounds, the probe form, exponential, interpolation, ternary and saddleback search, quickselect and median of medians, and both cycle finders (D834).
algo_search_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_search/src/main.e" "$repo" x64 linux "$test_build/algo-search-selfhost")
[ "$algo_search_written" = 'executable written' ]
chmod +x "$test_build/algo-search-selfhost"
"$test_build/algo-search-selfhost"
# `e.text.search`: KMP, Horspool, Boyer-Moore and Rabin-Karp against a naive scan, Aho-Corasick over nested patterns, the Z array, bitap with edits and Manacher (D834).
text_search_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_search/src/main.e" "$repo" x64 linux "$test_build/text-search-selfhost")
[ "$text_search_written" = 'executable written' ]
chmod +x "$test_build/text-search-selfhost"
"$test_build/text-search-selfhost"
# `e.text.distance`: Levenshtein, Damerau, Hamming, Jaro-Winkler, the longest common substring and trigram similarity against reference values (D834).
text_distance_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_distance/src/main.e" "$repo" x64 linux "$test_build/text-distance-selfhost")
[ "$text_distance_written" = 'executable written' ]
chmod +x "$test_build/text-distance-selfhost"
"$test_build/text-distance-selfhost"
# `e.algo.sketch`: Bloom and counting filters, Count-Min, HyperLogLog, Misra-Gries, Space-Saving, MinHash and SimHash over caller storage (D834).
algo_sketch_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_sketch/src/main.e" "$repo" x64 linux "$test_build/algo-sketch-selfhost")
[ "$algo_sketch_written" = 'executable written' ]
chmod +x "$test_build/algo-sketch-selfhost"
"$test_build/algo-sketch-selfhost"
# `e.algo.coding`: run-length, LEB128, VLQ, ZigZag, deltas, bit packing, frame of reference, Elias gamma, Rice, move-to-front, Burrows-Wheeler and canonical Huffman (D834).
algo_coding_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_coding/src/main.e" "$repo" x64 linux "$test_build/algo-coding-selfhost")
[ "$algo_coding_written" = 'executable written' ]
chmod +x "$test_build/algo-coding-selfhost"
"$test_build/algo-coding-selfhost"
# `e.math.ntheory`: gcd and modular arithmetic at the top of the 64-bit range, Miller-Rabin, three sieves, trial, rho and p-1 factoring, Garner's CRT, three discrete logarithms, Tonelli-Shanks, Stern-Brocot and Farey, against SymPy values (D836).
math_ntheory_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_ntheory/src/main.e" "$repo" x64 linux "$test_build/math-ntheory-selfhost")
[ "$math_ntheory_written" = 'executable written' ]
chmod +x "$test_build/math-ntheory-selfhost"
"$test_build/math-ntheory-selfhost"
# `e.math.root`: bisection, Newton, Halley, secant and Brent on sqrt(2), the Dottie number and a flat-shouldered cubic, with refusals for a bracket without a sign change and a flat slope (D836).
math_root_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_root/src/main.e" "$repo" x64 linux "$test_build/math-root-selfhost")
[ "$math_root_written" = 'executable written' ]
chmod +x "$test_build/math-root-selfhost"
"$test_build/math-root-selfhost"
# `e.algo.combin`: binomials to the last that fits a u64, lexicographic permutations and combinations, Heap's algorithm, subsets and submasks by mask, Gosper's hack and the subset-sum transforms (D836).
algo_combin_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_combin/src/main.e" "$repo" x64 linux "$test_build/algo-combin-selfhost")
[ "$algo_combin_written" = 'executable written' ]
chmod +x "$test_build/algo-combin-selfhost"
"$test_build/algo-combin-selfhost"
# `e.data.fenwick` and `e.data.sparse_table`: prefix and range sums under point updates and the lower-bound descent; range minimum, maximum and disjoint-table sums over every window of a 13-element array (D836).
data_range_query_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_range_query/src/main.e" "$repo" x64 linux "$test_build/data-range-query-selfhost")
[ "$data_range_query_written" = 'executable written' ]
chmod +x "$test_build/data-range-query-selfhost"
"$test_build/data-range-query-selfhost"
# `e.algo.dp`: three knapsacks, LIS, LCS and derived lengths, coin change, subset sum, Kadane and the product form, matrix chain, optimal BST, the histogram rectangle, the monotonic stack, Li Chao and the convex hull trick against a scan (D836).
algo_dp_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_dp/src/main.e" "$repo" x64 linux "$test_build/algo-dp-selfhost")
[ "$algo_dp_written" = 'executable written' ]
chmod +x "$test_build/algo-dp-selfhost"
"$test_build/algo-dp-selfhost"
# `e.data.segment_tree`: a max tree under point updates, the lazy tree's sums and minima under overlapping range additions, and the persistent tree answering every old version (D836).
data_segment_tree_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_segment_tree/src/main.e" "$repo" x64 linux "$test_build/data-segment-tree-selfhost")
[ "$data_segment_tree_written" = 'executable written' ]
chmod +x "$test_build/data-segment-tree-selfhost"
"$test_build/data-segment-tree-selfhost"
# `e.data.cache`: the keyed LRU through hits, overwrites, removals, evictions and a long churn, and the FIFO, Clock, LFU, SLRU and 2Q policies' victims against their definitions (D836).
data_cache_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_cache/src/main.e" "$repo" x64 linux "$test_build/data-cache-selfhost")
[ "$data_cache_written" = 'executable written' ]
chmod +x "$test_build/data-cache-selfhost"
"$test_build/data-cache-selfhost"
# `e.data.trie` and `e.algo.consistent_hash`: insert, lookup, prefix and longest-prefix queries and an ordered walk; a ring and rendezvous hashing that move only a leaving node's keys, and the jump hash against a transcription of the paper (D836).
data_trie_hash_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_trie_hash/src/main.e" "$repo" x64 linux "$test_build/data-trie-hash-selfhost")
[ "$data_trie_hash_written" = 'executable written' ]
chmod +x "$test_build/data-trie-hash-selfhost"
"$test_build/data-trie-hash-selfhost"
# `e.algo.geom` and `e.algo.geom.clip`: predicates, segment intersection, polygon area, convexity and containment, two hulls, closest and farthest pairs, the enclosing circle and rectangle, Pick and Morton; clipping by three algorithms, ear clipping and two simplifiers (D837).
algo_geom_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_geom/src/main.e" "$repo" x64 linux "$test_build/algo-geom-selfhost")
[ "$algo_geom_written" = 'executable written' ]
chmod +x "$test_build/algo-geom-selfhost"
"$test_build/algo-geom-selfhost"
# `e.math.special`: log-gamma, erf and erfc, the regularised incomplete gamma and beta, the normal, t, chi-squared and F distribution functions and the normal quantile against SciPy (D837).
math_special_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_special/src/main.e" "$repo" x64 linux "$test_build/math-special-selfhost")
[ "$math_special_written" = 'executable written' ]
chmod +x "$test_build/math-special-selfhost"
"$test_build/math-special-selfhost"
# `e.algo.rand.dist` and the sampling added to `e.algo.rand`: variate moments over 20,000 draws, Dirichlet, a multivariate normal's covariance, inverse-transform and rejection sampling, the alias table, weighted reservoir, shuffles, reservoir sampling, stratified, Latin hypercube, Halton and Sobol against SciPy (D837).
algo_rand_dist_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_rand_dist/src/main.e" "$repo" x64 linux "$test_build/algo-rand-dist-selfhost")
[ "$algo_rand_dist_written" = 'executable written' ]
chmod +x "$test_build/algo-rand-dist-selfhost"
"$test_build/algo-rand-dist-selfhost"
# `e.algo.stat.test`: t-tests, Welch, Mann-Whitney, Wilcoxon, chi-squared, Fisher's exact, Kolmogorov-Smirnov, ANOVA, Kruskal-Wallis, a permutation test and the Bonferroni and Benjamini-Hochberg corrections against SciPy (D837).
algo_stat_test_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_stat_test/src/main.e" "$repo" x64 linux "$test_build/algo-stat-test-selfhost")
[ "$algo_stat_test_written" = 'executable written' ]
chmod +x "$test_build/algo-stat-test-selfhost"
"$test_build/algo-stat-test-selfhost"
# `e.algo.graph.flow`: Edmonds-Karp, Dinic and push-relabel agree on CLRS's network (23), on parallel and anti-parallel arcs and on a bipartite instance; the minimum cut equals the flow and edge flows conserve (D837).
algo_graph_flow_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph_flow/src/main.e" "$repo" x64 linux "$test_build/algo-graph-flow-selfhost")
[ "$algo_graph_flow_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-flow-selfhost"
"$test_build/algo-graph-flow-selfhost"
# `e.algo.graph.match`: Hopcroft-Karp, the Hungarian algorithm against SciPy's assignment, Gale-Shapley stability and the blossom algorithm on two odd cycles and the Petersen graph (D837).
algo_graph_match_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph_match/src/main.e" "$repo" x64 linux "$test_build/algo-graph-match-selfhost")
[ "$algo_graph_match_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-match-selfhost"
"$test_build/algo-graph-match-selfhost"
# `e.algo.graph.path`: Bellman-Ford, Floyd-Warshall and Johnson against Dijkstra with a negative edge and a refused negative cycle, Dial, A*, IDA*, bidirectional search, IDDFS and path reconstruction (D837).
algo_graph_path_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph_path/src/main.e" "$repo" x64 linux "$test_build/algo-graph-path-selfhost")
[ "$algo_graph_path_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-path-selfhost"
"$test_build/algo-graph-path-selfhost"
# `e.algo.graph.tree`: rooting, binary-lifting and offline LCAs against NetworkX, the Euler tour, heavy-light path ranges, centroid decomposition, Prüfer codes both ways and AHU labels (D837).
algo_graph_tree_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph_tree/src/main.e" "$repo" x64 linux "$test_build/algo-graph-tree-selfhost")
[ "$algo_graph_tree_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-tree-selfhost"
"$test_build/algo-graph-tree-selfhost"
# `e.algo.graph.span`: Kruskal, Prim and Borůvka on CLRS's graph and a forest, bridges and articulation points, Hierholzer's circuit and path, and Warshall's closure (D837).
algo_graph_span_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph_span/src/main.e" "$repo" x64 linux "$test_build/algo-graph-span-selfhost")
[ "$algo_graph_span_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-span-selfhost"
"$test_build/algo-graph-span-selfhost"
# `e.math.fft`: the transform of an impulse and a cosine, round trips, convolution against direct multiplication, the number-theoretic transform and its convolution, Walsh-Hadamard and the cosine transforms against SciPy (D838).
math_fft_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_fft/src/main.e" "$repo" x64 linux "$test_build/math-fft-selfhost")
[ "$math_fft_written" = 'executable written' ]
chmod +x "$test_build/math-fft-selfhost"
"$test_build/math-fft-selfhost"
# `e.math.ode`: exponential decay and the harmonic oscillator by Euler, RK4 and adaptive RKF45, symplectic energy conservation over a thousand periods, Yoshida against leapfrog, and Euler-Maruyama's Brownian variance (D838).
math_ode_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_ode/src/main.e" "$repo" x64 linux "$test_build/math-ode-selfhost")
[ "$math_ode_written" = 'executable written' ]
chmod +x "$test_build/math-ode-selfhost"
"$test_build/math-ode-selfhost"
# `e.math.filter`: a constant-velocity Kalman filter over a noisy line, the extended and unscented filters over a range observation, a particle filter that resamples, and the complementary, Madgwick and Mahony attitude filters converging on a tilt (D838).
math_filter_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_filter/src/main.e" "$repo" x64 linux "$test_build/math-filter-selfhost")
[ "$math_filter_written" = 'executable written' ]
chmod +x "$test_build/math-filter-selfhost"
"$test_build/math-filter-selfhost"
# `e.math.opt`: every descent method and Nelder-Mead reach Rosenbrock's minimum, a five-dimensional bowl converges by all of them, and the simplex solves two small linear programmes against SciPy and reports an unbounded and an infeasible one (D838).
math_opt_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_opt/src/main.e" "$repo" x64 linux "$test_build/math-opt-selfhost")
[ "$math_opt_written" = 'executable written' ]
chmod +x "$test_build/math-opt-selfhost"
"$test_build/math-opt-selfhost"
# `e.math.opt.meta`: annealing and tabu search escape Rastrigin's local minima where hill climbing settles, the genetic algorithm, particle swarm and differential evolution minimise Rosenbrock in a box, and ant colony finds the octagon tour (D838).
math_opt_meta_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_opt_meta/src/main.e" "$repo" x64 linux "$test_build/math-opt-meta-selfhost")
[ "$math_opt_meta_written" = 'executable written' ]
chmod +x "$test_build/math-opt-meta-selfhost"
"$test_build/math-opt-meta-selfhost"
# `e.math.float`: fields unpack and pack back, binary16 against NumPy on normals, ties, subnormals and the specials with every finite half round-tripping, and bfloat16 rounding the top half to even (D838).
math_float_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_float/src/main.e" "$repo" x64 linux "$test_build/math-float-selfhost")
[ "$math_float_written" = 'executable written' ]
chmod +x "$test_build/math-float-selfhost"
"$test_build/math-float-selfhost"
# `e.math.gf`: the AES worked example and inverse, generator orders and tables agreeing with `mul` everywhere, carry-less products and reductions against a Python polynomial reference (D838).
math_gf_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_gf/src/main.e" "$repo" x64 linux "$test_build/math-gf-selfhost")
[ "$math_gf_written" = 'executable written' ]
chmod +x "$test_build/math-gf-selfhost"
"$test_build/math-gf-selfhost"
# `e.math.mc`: a Black-Scholes call by the plain estimator within its standard error, antithetic pairs and a terminal-price control variate cutting that error, and an odd payoff estimated exactly by antithesis (D838).
math_mc_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_mc/src/main.e" "$repo" x64 linux "$test_build/math-mc-selfhost")
[ "$math_mc_written" = 'executable written' ]
chmod +x "$test_build/math-mc-selfhost"
"$test_build/math-mc-selfhost"
# `e.math.mcmc`: Metropolis-Hastings, Gibbs, HMC and NUTS each recover the moments of a correlated bivariate normal from a far start, with the random walk rejecting about half and the gradient samplers nearly none (D838).
math_mcmc_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_mcmc/src/main.e" "$repo" x64 linux "$test_build/math-mcmc-selfhost")
[ "$math_mcmc_written" = 'executable written' ]
chmod +x "$test_build/math-mcmc-selfhost"
"$test_build/math-mcmc-selfhost"
# `e.math.opt.convex`: the interior-point method reaches the simplex fixture's optima, a Markowitz portfolio against SciPy, and stalls on the unbounded and the infeasible programme (D838).
math_opt_convex_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_opt_convex/src/main.e" "$repo" x64 linux "$test_build/math-opt-convex-selfhost")
[ "$math_opt_convex_written" = 'executable written' ]
chmod +x "$test_build/math-opt-convex-selfhost"
"$test_build/math-opt-convex-selfhost"
# `e.text.casing`: identifiers split at separators and case boundaries and convert between five conventions, slugs fold punctuation to hyphens, and title case spares the small words (D842).
text_casing_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_casing/src/main.e" "$repo" x64 linux "$test_build/text-casing-selfhost")
[ "$text_casing_written" = 'executable written' ]
chmod +x "$test_build/text-casing-selfhost"
"$test_build/text-casing-selfhost"
# `e.text.phonetic`: Soundex, the original Metaphone and NYSIIS agree with jellyfish on fifty-odd names (D842).
text_phonetic_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_phonetic/src/main.e" "$repo" x64 linux "$test_build/text-phonetic-selfhost")
[ "$text_phonetic_written" = 'executable written' ]
chmod +x "$test_build/text-phonetic-selfhost"
"$test_build/text-phonetic-selfhost"
# `e.text.stem`: Porter and Lancaster agree with NLTK on Porter's own examples and a hundred more, and affix stripping keeps the minimum (D842).
text_stem_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_stem/src/main.e" "$repo" x64 linux "$test_build/text-stem-selfhost")
[ "$text_stem_written" = 'executable written' ]
chmod +x "$test_build/text-stem-selfhost"
"$test_build/text-stem-selfhost"
# `e.text.wrap`: greedy and optimal breaking agree where the greedy choice is even and differ where a short line costs (checked exhaustively), an overlong word stands alone, and justification spreads from the left (D842).
text_wrap_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_wrap/src/main.e" "$repo" x64 linux "$test_build/text-wrap-selfhost")
[ "$text_wrap_written" = 'executable written' ]
chmod +x "$test_build/text-wrap-selfhost"
"$test_build/text-wrap-selfhost"
# `e.text.metric`: BLEU against NLTK, ROUGE-1/2/L and exact-match METEOR against hand counts, and the degenerate cases (D842).
text_metric_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_metric/src/main.e" "$repo" x64 linux "$test_build/text-metric-selfhost")
[ "$text_metric_written" = 'executable written' ]
chmod +x "$test_build/text-metric-selfhost"
"$test_build/text-metric-selfhost"
# `e.text.suffix`: suffix and LCP arrays against a naive sort on six texts, search ranges, the suffix automaton accepting exactly the substrings and counting them, and the suffix tree from the array with its node count (D843).
text_suffix_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_suffix/src/main.e" "$repo" x64 linux "$test_build/text-suffix-selfhost")
[ "$text_suffix_written" = 'executable written' ]
chmod +x "$test_build/text-suffix-selfhost"
"$test_build/text-suffix-selfhost"
# `e.text.diff`: Myers on the paper's example replayed by patch, patience diff anchored on unique lines, three-way merges taking, folding and marking, conflicts as base ranges, and the similarity ratio (D843).
text_diff_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_diff/src/main.e" "$repo" x64 linux "$test_build/text-diff-selfhost")
[ "$text_diff_written" = 'executable written' ]
chmod +x "$test_build/text-diff-selfhost"
"$test_build/text-diff-selfhost"
# `e.text.rank`: TF-IDF and BM25 against the formulas worked in Python, reciprocal rank fusion with ties by id, and MMR skipping the near duplicate (D843).
text_rank_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_rank/src/main.e" "$repo" x64 linux "$test_build/text-rank-selfhost")
[ "$text_rank_written" = 'executable written' ]
chmod +x "$test_build/text-rank-selfhost"
"$test_build/text-rank-selfhost"
# `e.text.index`: an inverted index of four documents with hits and misses, AND and OR, and Elias-Fano on a worked example and a random list (D843).
text_index_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_index/src/main.e" "$repo" x64 linux "$test_build/text-index-selfhost")
[ "$text_index_written" = 'executable written' ]
chmod +x "$test_build/text-index-selfhost"
"$test_build/text-index-selfhost"
# `e.text.tokenize`: shingles, dictionary word breaking, BPE merges matching a Python replica, WordPiece on unaffable, and unigram Viterbi with a sampler whose draws follow the probabilities (D843).
text_tokenize_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_tokenize/src/main.e" "$repo" x64 linux "$test_build/text-tokenize-selfhost")
[ "$text_tokenize_written" = 'executable written' ]
chmod +x "$test_build/text-tokenize-selfhost"
"$test_build/text-tokenize-selfhost"
# `e.data.spatial`: 200 LCG points against brute force for every index: nearest, ranges, overlaps, neighbours, ray hits (D857).
data_spatial_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_spatial/src/main.e" "$repo" x64 linux "$test_build/data-spatial-selfhost")
[ "$data_spatial_written" = 'executable written' ]
chmod +x "$test_build/data-spatial-selfhost"
"$test_build/data-spatial-selfhost"
# `e.data.succinct`: rank/select against a scan, LOUDS and parentheses over a tree, wavelet queries, CSA and FM-index over a text (D857).
data_succinct_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_succinct/src/main.e" "$repo" x64 linux "$test_build/data-succinct-selfhost")
[ "$data_succinct_written" = 'executable written' ]
chmod +x "$test_build/data-succinct-selfhost"
"$test_build/data-succinct-selfhost"
# `e.data.rope`: sixty LCG-driven inserts, removes and concatenations checked against a flat reference (D857).
data_rope_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_rope/src/main.e" "$repo" x64 linux "$test_build/data-rope-selfhost")
[ "$data_rope_written" = 'executable written' ]
chmod +x "$test_build/data-rope-selfhost"
"$test_build/data-rope-selfhost"
# `e.data.cartesian_tree`: parent arrays, range minima and LCAs of 48 LCG arrays against a recursive definition (D857).
data_cartesian_tree_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_cartesian_tree/src/main.e" "$repo" x64 linux "$test_build/data-cartesian-tree-selfhost")
[ "$data_cartesian_tree_written" = 'executable written' ]
chmod +x "$test_build/data-cartesian-tree-selfhost"
"$test_build/data-cartesian-tree-selfhost"
# `e.data.bitmap`: roaring sets against Python sets (membership, and/or, removals) and WAH round trips with fills over streams of unequal length (D857).
data_bitmap_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_bitmap/src/main.e" "$repo" x64 linux "$test_build/data-bitmap-selfhost")
[ "$data_bitmap_written" = 'executable written' ]
chmod +x "$test_build/data-bitmap-selfhost"
"$test_build/data-bitmap-selfhost"
# `e.data.hamt`: sixty kept versions each still answering its own dictionary, node usage matched exactly against a Python mirror (D858).
data_hamt_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_hamt/src/main.e" "$repo" x64 linux "$test_build/data-hamt-selfhost")
[ "$data_hamt_written" = 'executable written' ]
chmod +x "$test_build/data-hamt-selfhost"
"$test_build/data-hamt-selfhost"
# `e.data.link_cut`: 260 random links, cuts, path sums and connectivity queries on 40 vertices against a BFS (D858).
data_link_cut_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_link_cut/src/main.e" "$repo" x64 linux "$test_build/data-link-cut-selfhost")
[ "$data_link_cut_written" = 'executable written' ]
chmod +x "$test_build/data-link-cut-selfhost"
"$test_build/data-link-cut-selfhost"
# `e.data.stream`: 200 out-of-order events: the watermark sequence, late events, merged marks and the fired windows against a replica (D858).
data_stream_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_stream/src/main.e" "$repo" x64 linux "$test_build/data-stream-selfhost")
[ "$data_stream_written" = 'executable written' ]
chmod +x "$test_build/data-stream-selfhost"
"$test_build/data-stream-selfhost"
# `e.ratelimit`: 200 timed requests per limiter against a replica; the fixed window admits the boundary burst, the sliding ones do not (D858).
ratelimit_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ratelimit/src/main.e" "$repo" x64 linux "$test_build/ratelimit-selfhost")
[ "$ratelimit_written" = 'executable written' ]
chmod +x "$test_build/ratelimit-selfhost"
"$test_build/ratelimit-selfhost"
# `e.resilience`: a scripted breaker, jitter bounds over 800 draws, heartbeat sweeps, shedding matrix and rollout buckets against a replica (D858).
resilience_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/resilience/src/main.e" "$repo" x64 linux "$test_build/resilience-selfhost")
[ "$resilience_written" = 'executable written' ]
chmod +x "$test_build/resilience-selfhost"
"$test_build/resilience-selfhost"
# `e.valid`: known identifiers accepted and every single-digit and transposition corruption refused, from a Python replica (D859).
valid_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/valid/src/main.e" "$repo" x64 linux "$test_build/valid-selfhost")
[ "$valid_written" = 'executable written' ]
chmod +x "$test_build/valid-selfhost"
"$test_build/valid-selfhost"
# `e.control`: PID families on a simulated plant, LQR and pole-placement gains against numpy and scipy, an observer converging (D859).
control_loop_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/control_loop/src/main.e" "$repo" x64 linux "$test_build/control-loop-selfhost")
[ "$control_loop_written" = 'executable written' ]
chmod +x "$test_build/control-loop-selfhost"
"$test_build/control-loop-selfhost"
# `e.fmt.semver`: the spec precedence chain both ways, bad versions and ranges, and 168 range pairs verified by node semver (D859).
fmt_semver_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_semver/src/main.e" "$repo" x64 linux "$test_build/fmt-semver-selfhost")
[ "$fmt_semver_written" = 'executable written' ]
chmod +x "$test_build/fmt-semver-selfhost"
"$test_build/fmt-semver-selfhost"
# `e.fmt.cbor`: the RFC 8949 Appendix A stream byte-equal to cbor2 and decoded back, f16 patterns, skips and the error paths (D859).
fmt_cbor_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_cbor/src/main.e" "$repo" x64 linux "$test_build/fmt-cbor-selfhost")
[ "$fmt_cbor_written" = 'executable written' ]
chmod +x "$test_build/fmt-cbor-selfhost"
"$test_build/fmt-cbor-selfhost"
# `e.parse`: RPN, Pratt and descent values, token streams, CYK and Earley membership over LCG sentences, PEG matches and next-terminal sets against a Python oracle (D859).
parse_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/parse/src/main.e" "$repo" x64 linux "$test_build/parse-selfhost")
[ "$parse_written" = 'executable written' ]
chmod +x "$test_build/parse-selfhost"
"$test_build/parse-selfhost"
# `e.ml.linear`: OLS, ridge, lasso and logistic regression against scikit-learn, the singular and storage cases (D846).
ml_linear_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_linear/src/main.e" "$repo" x64 linux "$test_build/ml-linear-selfhost")
[ "$ml_linear_written" = 'executable written' ]
chmod +x "$test_build/ml-linear-selfhost"
"$test_build/ml-linear-selfhost"
# `e.ml.cluster`: k-means and its seeding, online and LBG forms, k-medoids, three linkages, GMM by EM against scikit-learn, and neighbour joining on the textbook five taxa (D846).
ml_cluster_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_cluster/src/main.e" "$repo" x64 linux "$test_build/ml-cluster-selfhost")
[ "$ml_cluster_written" = 'executable written' ]
chmod +x "$test_build/ml-cluster-selfhost"
"$test_build/ml-cluster-selfhost"
# `e.ml.cluster.density`: DBSCAN and OPTICS on three blobs and a stray point against scikit-learn (D846).
ml_cluster_density_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_cluster_density/src/main.e" "$repo" x64 linux "$test_build/ml-cluster-density-selfhost")
[ "$ml_cluster_density_written" = 'executable written' ]
chmod +x "$test_build/ml-cluster-density-selfhost"
"$test_build/ml-cluster-density-selfhost"
# `e.ml.knn`: the three nearest with distances, majority classification and mean regression against scikit-learn (D846).
ml_knn_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_knn/src/main.e" "$repo" x64 linux "$test_build/ml-knn-selfhost")
[ "$ml_knn_written" = 'executable written' ]
chmod +x "$test_build/ml-knn-selfhost"
"$test_build/ml-knn-selfhost"
# `e.ml.bayes`: Gaussian and multinomial naive Bayes fits and predictions against scikit-learn (D846).
ml_bayes_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_bayes/src/main.e" "$repo" x64 linux "$test_build/ml-bayes-selfhost")
[ "$ml_bayes_written" = 'executable written' ]
chmod +x "$test_build/ml-bayes-selfhost"
"$test_build/ml-bayes-selfhost"
# `e.ml.tree`: a regression tree and a classifier splitting where scikit-learn splits, a random forest classifying three groups, and gradient boosting driving the error down with the rounds (D847).
ml_tree_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_tree/src/main.e" "$repo" x64 linux "$test_build/ml-tree-selfhost")
[ "$ml_tree_written" = 'executable written' ]
chmod +x "$test_build/ml-tree-selfhost"
"$test_build/ml-tree-selfhost"
# `e.ml.svm`: the kernels, SMO finding the maximum-margin line of two squares as scikit-learn does, and an RBF machine learning XOR where a linear one cannot (D847).
ml_svm_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_svm/src/main.e" "$repo" x64 linux "$test_build/ml-svm-selfhost")
[ "$ml_svm_written" = 'executable written' ]
chmod +x "$test_build/ml-svm-selfhost"
"$test_build/ml-svm-selfhost"
# `e.ml.optim`: one step of every rule against hand-worked values, the cosine schedule at its landmarks, and online gradient descent (D847).
ml_optim_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_optim/src/main.e" "$repo" x64 linux "$test_build/ml-optim-selfhost")
[ "$ml_optim_written" = 'executable written' ]
chmod +x "$test_build/ml-optim-selfhost"
"$test_build/ml-optim-selfhost"
# `e.ml.loss`: InfoNCE, the triplet hinge, the distillation KL and CTC against a brute-force sum over alignments (D847).
ml_loss_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_loss/src/main.e" "$repo" x64 linux "$test_build/ml-loss-selfhost")
[ "$ml_loss_written" = 'executable written' ]
chmod +x "$test_build/ml-loss-selfhost"
"$test_build/ml-loss-selfhost"
# `e.ml.sample`: softmax, top-k and nucleus frequencies, contrastive decoding, and beam search finding the best path of a toy chain where greedy does not (D847).
ml_sample_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_sample/src/main.e" "$repo" x64 linux "$test_build/ml-sample-selfhost")
[ "$ml_sample_written" = 'executable written' ]
chmod +x "$test_build/ml-sample-selfhost"
"$test_build/ml-sample-selfhost"
# `e.ml.nn`: the perceptron, autodiff against derivatives by hand, attention and its causal form against NumPy, two heads over identity projections, and rotary embedding (D848).
ml_nn_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_nn/src/main.e" "$repo" x64 linux "$test_build/ml-nn-selfhost")
[ "$ml_nn_written" = 'executable written' ]
chmod +x "$test_build/ml-nn-selfhost"
"$test_build/ml-nn-selfhost"
# `e.ml.hmm`: forward, Viterbi and one Baum-Welch pass on a two-state model against a NumPy reference (D848).
ml_hmm_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_hmm/src/main.e" "$repo" x64 linux "$test_build/ml-hmm-selfhost")
[ "$ml_hmm_written" = 'executable written' ]
chmod +x "$test_build/ml-hmm-selfhost"
"$test_build/ml-hmm-selfhost"
# `e.ml.rl`: Q-learning and SARSA converge on a four-state corridor, and epsilon-greedy explores at the asked rate (D848).
ml_rl_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_rl/src/main.e" "$repo" x64 linux "$test_build/ml-rl-selfhost")
[ "$ml_rl_written" = 'executable written' ]
chmod +x "$test_build/ml-rl-selfhost"
"$test_build/ml-rl-selfhost"
# `e.ml.reduce`: PCA against NumPy, Oja's rule converging on the leading component, frequent directions keeping the dominant direction, and t-SNE keeping three groups apart (D848).
ml_reduce_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_reduce/src/main.e" "$repo" x64 linux "$test_build/ml-reduce-selfhost")
[ "$ml_reduce_written" = 'executable written' ]
chmod +x "$test_build/ml-reduce-selfhost"
"$test_build/ml-reduce-selfhost"
# `e.ml.ann`: MinHash and LSH banding, the small-world graph answering exact neighbours on a cloud, and IVF-PQ finding the nearest within the probed cells (D848).
ml_ann_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_ann/src/main.e" "$repo" x64 linux "$test_build/ml-ann-selfhost")
[ "$ml_ann_written" = 'executable written' ]
chmod +x "$test_build/ml-ann-selfhost"
"$test_build/ml-ann-selfhost"
# `e.data.treap`: keyed and implicit treaps against arrays through random operations, split and merge, and persistent versions (D849).
data_treap_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_treap/src/main.e" "$repo" x64 linux "$test_build/data-treap-selfhost")
[ "$data_treap_written" = 'executable written' ]
chmod +x "$test_build/data-treap-selfhost"
"$test_build/data-treap-selfhost"
# `e.data.skip_list`: random inserts and removals against a sorted array, lower bounds, the chain, and slot reuse (D849).
data_skip_list_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_skip_list/src/main.e" "$repo" x64 linux "$test_build/data-skip-list-selfhost")
[ "$data_skip_list_written" = 'executable written' ]
chmod +x "$test_build/data-skip-list-selfhost"
"$test_build/data-skip-list-selfhost"
# `e.data.splay`: a balanced build, splaying by position, and random range reversals against an array (D849).
data_splay_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_splay/src/main.e" "$repo" x64 linux "$test_build/data-splay-selfhost")
[ "$data_splay_written" = 'executable written' ]
chmod +x "$test_build/data-splay-selfhost"
"$test_build/data-splay-selfhost"
# `e.data.window`: the monotonic queue and the two-stack window against scans, and the exponential histogram within its error bound (D849).
data_window_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_window/src/main.e" "$repo" x64 linux "$test_build/data-window-selfhost")
[ "$data_window_written" = 'executable written' ]
chmod +x "$test_build/data-window-selfhost"
"$test_build/data-window-selfhost"
# `e.data.btree`: a B+ tree against a sorted array through random inserts, overwrites and removals, range scans, and emptying (D849).
data_btree_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_btree/src/main.e" "$repo" x64 linux "$test_build/data-btree-selfhost")
[ "$data_btree_written" = 'executable written' ]
chmod +x "$test_build/data-btree-selfhost"
"$test_build/data-btree-selfhost"
# `e.algo.align`: Needleman-Wunsch, Smith-Waterman and Gotoh scores against a NumPy dynamic programme, and Hirschberg replaying to both strings (D850).
algo_align_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_align/src/main.e" "$repo" x64 linux "$test_build/algo-align-selfhost")
[ "$algo_align_written" = 'executable written' ]
chmod +x "$test_build/algo-align-selfhost"
"$test_build/algo-align-selfhost"
# `e.algo.schedule`: activity selection, interval covering, job sequencing with deadlines and the cooldown bound on textbook cases (D850).
algo_schedule_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_schedule/src/main.e" "$repo" x64 linux "$test_build/algo-schedule-selfhost")
[ "$algo_schedule_written" = 'executable written' ]
chmod +x "$test_build/algo-schedule-selfhost"
"$test_build/algo-schedule-selfhost"
# `e.algo.timeseries`: Holt-Winters and STL on a synthetic seasonal series, three change detectors on a shift, GARCH fit and forecasts on a simulation, and a Hawkes process near its rate (D850).
algo_timeseries_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_timeseries/src/main.e" "$repo" x64 linux "$test_build/algo-timeseries-selfhost")
[ "$algo_timeseries_written" = 'executable written' ]
chmod +x "$test_build/algo-timeseries-selfhost"
"$test_build/algo-timeseries-selfhost"
# `e.algo.exact_cover`: the unique cover of the paper's matrix, an uncoverable one, and a Sudoku solved to its known solution (D850).
algo_exact_cover_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_exact_cover/src/main.e" "$repo" x64 linux "$test_build/algo-exact-cover-selfhost")
[ "$algo_exact_cover_written" = 'executable written' ]
chmod +x "$test_build/algo-exact-cover-selfhost"
"$test_build/algo-exact-cover-selfhost"
# `e.data.bk_tree`: words within one edit of a query under Levenshtein, the empty tree, a full pool and a short stack (D850).
data_bk_tree_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_bk_tree/src/main.e" "$repo" x64 linux "$test_build/data-bk-tree-selfhost")
[ "$data_bk_tree_written" = 'executable written' ]
chmod +x "$test_build/data-bk-tree-selfhost"
"$test_build/data-bk-tree-selfhost"
# `e.algo.graph.centrality`: PageRank, HITS, eigenvector, closeness and betweenness on the unweighted karate club against NetworkX (D855).
algo_graph_centrality_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph_centrality/src/main.e" "$repo" x64 linux "$test_build/algo-graph-centrality-selfhost")
[ "$algo_graph_centrality_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-centrality-selfhost"
"$test_build/algo-graph-centrality-selfhost"
# `e.algo.graph.color`: Welsh-Powell and DSATUR on the karate club, a 6-cycle and K5 (D855).
algo_graph_color_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph_color/src/main.e" "$repo" x64 linux "$test_build/algo-graph-color-selfhost")
[ "$algo_graph_color_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-color-selfhost"
"$test_build/algo-graph-color-selfhost"
# `e.algo.graph.community`: modularity, label propagation, Louvain and Girvan-Newman on the karate club against NetworkX (D855).
algo_graph_community_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph_community/src/main.e" "$repo" x64 linux "$test_build/algo-graph-community-selfhost")
[ "$algo_graph_community_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-community-selfhost"
"$test_build/algo-graph-community-selfhost"
# `e.algo.graph.cut`: Stoer-Wagner and Karger on the karate club and a weighted square (D855).
algo_graph_cut_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph_cut/src/main.e" "$repo" x64 linux "$test_build/algo-graph-cut-selfhost")
[ "$algo_graph_cut_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-cut-selfhost"
"$test_build/algo-graph-cut-selfhost"
# `e.algo.graph.iso`: a triangle and a path inside the karate club, no 4-cycle in a path, two drawings of the Petersen graph isomorphic and a 10-cycle not (D855).
algo_graph_iso_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph_iso/src/main.e" "$repo" x64 linux "$test_build/algo-graph-iso-selfhost")
[ "$algo_graph_iso_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-iso-selfhost"
"$test_build/algo-graph-iso-selfhost"
# `e.algo.combopt`: tours improved to the brute-force optimum, set cover, bin packing, routing, knapsack and generic branch and bound, and LNS on a toy (D856).
algo_combopt_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_combopt/src/main.e" "$repo" x64 linux "$test_build/algo-combopt-selfhost")
[ "$algo_combopt_written" = 'executable written' ]
chmod +x "$test_build/algo-combopt-selfhost"
"$test_build/algo-combopt-selfhost"
# `e.algo.sat`: models and the pigeonhole refusal, at-most and pseudo-boolean encodings against counting, Tseitin circuits told apart by equivalence, WalkSAT and preprocessing (D856).
algo_sat_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_sat/src/main.e" "$repo" x64 linux "$test_build/algo-sat-selfhost")
[ "$algo_sat_written" = 'executable written' ]
chmod +x "$test_build/algo-sat-selfhost"
"$test_build/algo-sat-selfhost"
# `e.algo.csp`: AC-3 on a chain, MAC and limited discrepancy on 4-queens, all-different Hall pruning, element, table and cumulative (D856).
algo_csp_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_csp/src/main.e" "$repo" x64 linux "$test_build/algo-csp-selfhost")
[ "$algo_csp_written" = 'executable written' ]
chmod +x "$test_build/algo-csp-selfhost"
"$test_build/algo-csp-selfhost"
# `e.algo.logic`: the textbook four-variable function reduced to its four primes and a three-term cover (D856).
algo_logic_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_logic/src/main.e" "$repo" x64 linux "$test_build/algo-logic-selfhost")
[ "$algo_logic_written" = 'executable written' ]
chmod +x "$test_build/algo-logic-selfhost"
"$test_build/algo-logic-selfhost"
# `e.algo.bdd`: two functions evaluated on every assignment and counted, canonicity, negation and a full pool (D856).
algo_bdd_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_bdd/src/main.e" "$repo" x64 linux "$test_build/algo-bdd-selfhost")
[ "$algo_bdd_written" = 'executable written' ]
chmod +x "$test_build/algo-bdd-selfhost"
"$test_build/algo-bdd-selfhost"
# `e.fmt.toml`: a 60-line document flattened event by event against tomllib, twelve refusals tomllib shares, and the value corners (D860).
fmt_toml_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_toml/src/main.e" "$repo" x64 linux "$test_build/fmt-toml-selfhost")
[ "$fmt_toml_written" = 'executable written' ]
chmod +x "$test_build/fmt-toml-selfhost"
"$test_build/fmt-toml-selfhost"
# `e.fmt.markdown`: 97 CommonMark 0.31.2 spec examples rendered to the spec's HTML, cross-checked with markdown-it (D860).
fmt_markdown_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_markdown/src/main.e" "$repo" x64 linux "$test_build/fmt-markdown-selfhost")
[ "$fmt_markdown_written" = 'executable written' ]
chmod +x "$test_build/fmt-markdown-selfhost"
"$test_build/fmt-markdown-selfhost"
# `e.time.sync`: forty LCG interval sets against a brute-force count over every endpoint, Berkeley with outliers, Cristian (D860).
time_sync_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/time_sync/src/main.e" "$repo" x64 linux "$test_build/time-sync-selfhost")
[ "$time_sync_written" = 'executable written' ]
chmod +x "$test_build/time-sync-selfhost"
"$test_build/time-sync-selfhost"
# `e.trace`: the spec example round trip, seven invalid headers, drawn ids and tracestate ordering against a replica (D860).
trace_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trace/src/main.e" "$repo" x64 linux "$test_build/trace-selfhost")
[ "$trace_written" = 'executable written' ]
chmod +x "$test_build/trace-selfhost"
"$test_build/trace-selfhost"
# `e.text.hyphen`: twelve words at two minimum settings, exceptions and case folding against pyphen (D860).
text_hyphen_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_hyphen/src/main.e" "$repo" x64 linux "$test_build/text-hyphen-selfhost")
[ "$text_hyphen_written" = 'executable written' ]
chmod +x "$test_build/text-hyphen-selfhost"
"$test_build/text-hyphen-selfhost"
# `e.dist.clock`: Lamport, vector and hybrid clocks over scripted exchanges against a replica (D861).
dist_clock_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_clock/src/main.e" "$repo" x64 linux "$test_build/dist-clock-selfhost")
[ "$dist_clock_written" = 'executable written' ]
chmod +x "$test_build/dist-clock-selfhost"
"$test_build/dist-clock-selfhost"
# `e.dist.election`: leaders and exact message counts for several alive patterns against a replica (D861).
dist_election_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_election/src/main.e" "$repo" x64 linux "$test_build/dist-election-selfhost")
[ "$dist_election_written" = 'executable written' ]
chmod +x "$test_build/dist-election-selfhost"
"$test_build/dist-election-selfhost"
# `e.dist.gossip`: per-round informed counts for three seeds and a merge-rule table against a PCG replica (D861).
dist_gossip_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_gossip/src/main.e" "$repo" x64 linux "$test_build/dist-gossip-selfhost")
[ "$dist_gossip_written" = 'executable written' ]
chmod +x "$test_build/dist-gossip-selfhost"
"$test_build/dist-gossip-selfhost"
# `e.dist.failure_detector`: phi at four gaps and the threshold crossing to the tick against math.erfc (D861).
dist_failure_detector_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_failure_detector/src/main.e" "$repo" x64 linux "$test_build/dist-failure-detector-selfhost")
[ "$dist_failure_detector_written" = 'executable written' ]
chmod +x "$test_build/dist-failure-detector-selfhost"
"$test_build/dist-failure-detector-selfhost"
# `e.parse.ll`: sets, table and derivations of the left-factored expression grammar against a replica, and the conflicts of the left-recursive one (D861).
parse_ll_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/parse_ll/src/main.e" "$repo" x64 linux "$test_build/parse-ll-selfhost")
[ "$parse_ll_written" = 'executable written' ]
chmod +x "$test_build/parse-ll-selfhost"
"$test_build/parse-ll-selfhost"
# `e.parse.lr`: 12/22/12 states on the dragon grammar with equal LALR and SLR tables, the `L = R` grammar not SLR but LALR, ten sentences under each table (D862).
parse_lr_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/parse_lr/src/main.e" "$repo" x64 linux "$test_build/parse-lr-selfhost")
[ "$parse_lr_written" = 'executable written' ]
chmod +x "$test_build/parse-lr-selfhost"
"$test_build/parse-lr-selfhost"
# `e.text.collab`: 200 concurrent pairs converging both ways, two RGA replicas in opposite orders, 100 ordered keys (D862).
text_collab_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_collab/src/main.e" "$repo" x64 linux "$test_build/text-collab-selfhost")
[ "$text_collab_written" = 'executable written' ]
chmod +x "$test_build/text-collab-selfhost"
"$test_build/text-collab-selfhost"
# `e.test.prop`: draws in range and stream-matched, `x > 100` shrinking to 101 from twenty starts, a pair property to two bytes (D862).
test_prop_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/test_prop/src/main.e" "$repo" x64 linux "$test_build/test-prop-selfhost")
[ "$test_prop_written" = 'executable written' ]
chmod +x "$test_build/test-prop-selfhost"
"$test_build/test-prop-selfhost"
# `e.test.sim`: ping-pong counts, identical replay for one seed and a different trace for another, matched to a replica (D862).
test_sim_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/test_sim/src/main.e" "$repo" x64 linux "$test_build/test-sim-selfhost")
[ "$test_sim_written" = 'executable written' ]
chmod +x "$test_build/test-sim-selfhost"
"$test_build/test-sim-selfhost"
# `e.test.linearize`: thirty LCG histories under three models against brute force over permutations, the stale read refused (D862).
test_linearize_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/test_linearize/src/main.e" "$repo" x64 linux "$test_build/test-linearize-selfhost")
[ "$test_linearize_written" = 'executable written' ]
chmod +x "$test_build/test-linearize-selfhost"
"$test_build/test-linearize-selfhost"
# `e.fmt.pretty`: Wadler's tree at four widths and soft-line cases byte-exact against a replica, plus the lazy-versus-strict group case (D863).
fmt_pretty_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_pretty/src/main.e" "$repo" x64 linux "$test_build/fmt-pretty-selfhost")
[ "$fmt_pretty_written" = 'executable written' ]
chmod +x "$test_build/fmt-pretty-selfhost"
"$test_build/fmt-pretty-selfhost"
# `e.fmt.json.schema`: 53 schema and document pairs judged as jsonschema 4.25 does, with the first failing pointer (D863).
fmt_json_schema_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_json_schema/src/main.e" "$repo" x64 linux "$test_build/fmt-json-schema-selfhost")
[ "$fmt_json_schema_written" = 'executable written' ]
chmod +x "$test_build/fmt-json-schema-selfhost"
"$test_build/fmt-json-schema-selfhost"
# `e.fmt.css`: 35 selectors over a 16-element document matched as lxml.cssselect does, spec specificity examples and a twelve-declaration cascade (D863).
fmt_css_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_css/src/main.e" "$repo" x64 linux "$test_build/fmt-css-selfhost")
[ "$fmt_css_written" = 'executable written' ]
chmod +x "$test_build/fmt-css-selfhost"
"$test_build/fmt-css-selfhost"
# `e.dist.consensus`: leaders per phase, logs equal after a healed partition, a snapshot installed, joint membership, duelling Paxos deciding under drops, a VR view change (D863).
dist_consensus_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_consensus/src/main.e" "$repo" x64 linux "$test_build/dist-consensus-selfhost")
[ "$dist_consensus_written" = 'executable written' ]
chmod +x "$test_build/dist-consensus-selfhost"
"$test_build/dist-consensus-selfhost"
# `e.dist.commit`: per-tick state hashes for success, a failing participant and a dead coordinator: 2PC blocks, 3PC resolves (D863).
dist_commit_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_commit/src/main.e" "$repo" x64 linux "$test_build/dist-commit-selfhost")
[ "$dist_commit_written" = 'executable written' ]
chmod +x "$test_build/dist-commit-selfhost"
"$test_build/dist-commit-selfhost"
# `e.dist.replica`: 120 LCG steps on five replicas: no stale reads at r=w=3, two at r=w=2, hint and repair counts matched (D864).
dist_replica_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_replica/src/main.e" "$repo" x64 linux "$test_build/dist-replica-selfhost")
[ "$dist_replica_written" = 'executable written' ]
chmod +x "$test_build/dist-replica-selfhost"
"$test_build/dist-replica-selfhost"
# `e.dist.collective`: results and transfer counts against numpy: 24 moves in 6 steps for a ring of four, 4 transfers in 3 rounds to broadcast to five (D864).
dist_collective_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_collective/src/main.e" "$repo" x64 linux "$test_build/dist-collective-selfhost")
[ "$dist_collective_written" = 'executable written' ]
chmod +x "$test_build/dist-collective-selfhost"
"$test_build/dist-collective-selfhost"
# `e.algo.ecc`: RS errors and erasures corrected and over-budget refused, every BCH(15,7) one- and two-bit pattern, Viterbi bursts, all LDPC singles, exhaustive Hamming and SECDED (D864).
algo_ecc_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_ecc/src/main.e" "$repo" x64 linux "$test_build/algo-ecc-selfhost")
[ "$algo_ecc_written" = 'executable written' ]
chmod +x "$test_build/algo-ecc-selfhost"
"$test_build/algo-ecc-selfhost"
# `e.algo.rand.quasi`: the first 64 Sobol points bit-equal to scipy's unscrambled Sobol and Halton points to zero error (D864).
algo_rand_quasi_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_rand_quasi/src/main.e" "$repo" x64 linux "$test_build/algo-rand-quasi-selfhost")
[ "$algo_rand_quasi_written" = 'executable written' ]
chmod +x "$test_build/algo-rand-quasi-selfhost"
"$test_build/algo-rand-quasi-selfhost"
# `e.algo.geom3`: rays against a replica, 50 tetrahedron pairs where hull, SAT and GJK agree with linprog, EPA depths, Barnes-Hut within 0.52% at theta 0.5, Kabsch equal to scipy, a 68-face hull with scipy's volume (D864).
algo_geom3_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_geom3/src/main.e" "$repo" x64 linux "$test_build/algo-geom3-selfhost")
[ "$algo_geom3_written" = 'executable written' ]
chmod +x "$test_build/algo-geom3-selfhost"
"$test_build/algo-geom3-selfhost"
# A pointer to a float is an integer-class argument after floats, in the seventh slot and beyond, from a field and an element (D867).
pointer_float_args_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/pointer_float_args/src/main.e" "$repo" x64 linux "$test_build/pointer-float-args-selfhost")
[ "$pointer_float_args_written" = 'executable written' ]
chmod +x "$test_build/pointer-float-args-selfhost"
"$test_build/pointer-float-args-selfhost"
# `e.game.nav`: region coverage and portals, funnel corners on three corridors, flow distances against Dijkstra, HPA* within 5% of BFS on 20 maps (D865).
game_nav_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_nav/src/main.e" "$repo" x64 linux "$test_build/game-nav-selfhost")
[ "$game_nav_written" = 'executable written' ]
chmod +x "$test_build/game-nav-selfhost"
"$test_build/game-nav-selfhost"
# `e.game.procgen`: Perlin, simplex and Worley samples to 1e-12 against transcriptions, WFC on five seeds satisfying every adjacency with the replica's grid hash (D865).
game_procgen_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_procgen/src/main.e" "$repo" x64 linux "$test_build/game-procgen-selfhost")
[ "$game_procgen_written" = 'executable written' ]
chmod +x "$test_build/game-procgen-selfhost"
"$test_build/game-procgen-selfhost"
# `e.game.physics`: a PBD chain at rest, XPBD, Gauss-Seidel, SPH and MAC steps equal to replicas, CCD against the analytic time, sweep-and-prune equal to brute force (D865).
game_physics_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_physics/src/main.e" "$repo" x64 linux "$test_build/game-physics-selfhost")
[ "$game_physics_written" = 'executable written' ]
chmod +x "$test_build/game-physics-selfhost"
"$test_build/game-physics-selfhost"
# `e.game.anim`: quaternions against scipy, FABRIK and CCD tips against replicas, LBS against numpy and DQS equal to it on a single bone (D865).
game_anim_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_anim/src/main.e" "$repo" x64 linux "$test_build/game-anim-selfhost")
[ "$game_anim_written" = 'executable written' ]
chmod +x "$test_build/game-anim-selfhost"
"$test_build/game-anim-selfhost"
# `e.gfx.curve`: Bezier, B-spline, Catmull-Rom and NURBS points against scipy and numpy to 1e-12 (D865).
gfx_curve_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_curve/src/main.e" "$repo" x64 linux "$test_build/gfx-curve-selfhost")
[ "$gfx_curve_written" = 'executable written' ]
chmod +x "$test_build/gfx-curve-selfhost"
"$test_build/gfx-curve-selfhost"
# `e.robot.kinematics`: odometry over 100 tick pairs, planar and six-axis forward kinematics, transpose and damped-least-squares IK against numpy (D866).
robot_kinematics_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/robot_kinematics/src/main.e" "$repo" x64 linux "$test_build/robot-kinematics-selfhost")
[ "$robot_kinematics_written" = 'executable written' ]
chmod +x "$test_build/robot-kinematics-selfhost"
"$test_build/robot-kinematics-selfhost"
# `e.robot.motion`: profile samples, splines against scipy, trackers on a circle, DWA and VO choices, four-agent ORCA to 1e-9, potential fields and a smoothed band (D866).
robot_motion_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/robot_motion/src/main.e" "$repo" x64 linux "$test_build/robot-motion-selfhost")
[ "$robot_motion_written" = 'executable written' ]
chmod +x "$test_build/robot-motion-selfhost"
"$test_build/robot-motion-selfhost"
# `e.robot.plan`: tree sizes, costs and waypoint hashes of six planners on two maps matched to a replica on the same generator stream; exact lattice and hybrid A* lengths (D866).
robot_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/robot_plan/src/main.e" "$repo" x64 linux "$test_build/robot-plan-selfhost")
[ "$robot_plan_written" = 'executable written' ]
chmod +x "$test_build/robot-plan-selfhost"
"$test_build/robot-plan-selfhost"
# `e.robot.map`: cell counts after twenty scans, ICP to 1e-6, AMCL within 0.1 of the truth with matched weights, a ten-pose loop closed to 1e-31 (D866).
robot_map_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/robot_map/src/main.e" "$repo" x64 linux "$test_build/robot-map-selfhost")
[ "$robot_map_written" = 'executable written' ]
chmod +x "$test_build/robot-map-selfhost"
"$test_build/robot-map-selfhost"
# `e.dsp`: filter designs and outputs against scipy.signal to 1e-9, Remez on two band sets, an STFT round trip, MFCC, DTW, LPC, adaptive filters and resamplers against replicas (D866).
dsp_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dsp/src/main.e" "$repo" x64 linux "$test_build/dsp-selfhost")
[ "$dsp_written" = 'executable written' ]
chmod +x "$test_build/dsp-selfhost"
"$test_build/dsp-selfhost"
# `e.gfx.mesh`: Euler characteristics and volumes through subdivision, decimation and booleans, marching cubes equal to scikit-image on a sphere, geodesics within a few percent of great circles, LSCM recovering a flat patch, Poisson and ball-pivot reconstructions closed (D868).
gfx_mesh_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_mesh/src/main.e" "$repo" x64 linux "$test_build/gfx-mesh-selfhost")
[ "$gfx_mesh_written" = 'executable written' ]
chmod +x "$test_build/gfx-mesh-selfhost"
"$test_build/gfx-mesh-selfhost"
# `e.gfx.raster`: pixel sets equal to scikit-image for lines and circles, Wu coverage against a replica, two triangles partitioning a rectangle exactly (D868).
gfx_raster_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_raster/src/main.e" "$repo" x64 linux "$test_build/gfx-raster-selfhost")
[ "$gfx_raster_written" = 'executable written' ]
chmod +x "$test_build/gfx-raster-selfhost"
"$test_build/gfx-raster-selfhost"
# `e.gfx.shade`: thirty configurations to 1e-12 against numpy and a white furnace at roughness 0.5 integrating to 0.909 (D868).
gfx_shade_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_shade/src/main.e" "$repo" x64 linux "$test_build/gfx-shade-selfhost")
[ "$gfx_shade_written" = 'executable written' ]
chmod +x "$test_build/gfx-shade-selfhost"
"$test_build/gfx-shade-selfhost"
# `e.gfx.trace`: furnace tests exact in all three modes, sixty CSG queries against a membership oracle, 16x16 renders equal to the replica's image hash (D868).
gfx_trace_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_trace/src/main.e" "$repo" x64 linux "$test_build/gfx-trace-selfhost")
[ "$gfx_trace_written" = 'executable written' ]
chmod +x "$test_build/gfx-trace-selfhost"
"$test_build/gfx-trace-selfhost"
# `e.gfx.texture`: BC blocks against a replica and fifty astcenc blocks over six footprints decoded to astcenc's own output (D868).
gfx_texture_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_texture/src/main.e" "$repo" x64 linux "$test_build/gfx-texture-selfhost")
[ "$gfx_texture_written" = 'executable written' ]
chmod +x "$test_build/gfx-texture-selfhost"
"$test_build/gfx-texture-selfhost"
# `e.dist.anti_entropy`: 500 keys with seven differences: exactly the differing buckets, 53 comparisons and the seven keys (D869).
dist_anti_entropy_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_anti_entropy/src/main.e" "$repo" x64 linux "$test_build/dist-anti-entropy-selfhost")
[ "$dist_anti_entropy_written" = 'executable written' ]
chmod +x "$test_build/dist-anti-entropy-selfhost"
"$test_build/dist-anti-entropy-selfhost"
# `e.dist.crdt`: per-site values, both merge orders, self-merge and the dispatch against a replica (D869).
dist_crdt_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_crdt/src/main.e" "$repo" x64 linux "$test_build/dist-crdt-selfhost")
[ "$dist_crdt_written" = 'executable written' ]
chmod +x "$test_build/dist-crdt-selfhost"
"$test_build/dist-crdt-selfhost"
# `e.dist.deadlock`: verdicts and probe counts on four graphs, including the initiator outside the cycle (D869).
dist_deadlock_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_deadlock/src/main.e" "$repo" x64 linux "$test_build/dist-deadlock-selfhost")
[ "$dist_deadlock_written" = 'executable written' ]
chmod +x "$test_build/dist-deadlock-selfhost"
"$test_build/dist-deadlock-selfhost"
# `e.dist.dht`: forty Chord and forty Kademlia lookups folded to one word each against a replica (D869).
dist_dht_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_dht/src/main.e" "$repo" x64 linux "$test_build/dist-dht-selfhost")
[ "$dist_dht_written" = 'executable written' ]
chmod +x "$test_build/dist-dht-selfhost"
"$test_build/dist-dht-selfhost"
# `e.dist.lock`: a scripted sequence with instances down and clocks skewed against a replica (D869).
dist_lock_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_lock/src/main.e" "$repo" x64 linux "$test_build/dist-lock-selfhost")
[ "$dist_lock_written" = 'executable written' ]
chmod +x "$test_build/dist-lock-selfhost"
"$test_build/dist-lock-selfhost"
# `e.dist.mutex`: mutual exclusion and exact message counts (30 and 24 for five entries) over a scripted schedule (D870).
dist_mutex_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_mutex/src/main.e" "$repo" x64 linux "$test_build/dist-mutex-selfhost")
[ "$dist_mutex_written" = 'executable written' ]
chmod +x "$test_build/dist-mutex-selfhost"
"$test_build/dist-mutex-selfhost"
# `e.dist.snapshot`: a token-passing computation snapshotted mid-flight with 67 tokens in channels: recorded states plus channels equal the 400 live (D870).
dist_snapshot_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_snapshot/src/main.e" "$repo" x64 linux "$test_build/dist-snapshot-selfhost")
[ "$dist_snapshot_written" = 'executable written' ]
chmod +x "$test_build/dist-snapshot-selfhost"
"$test_build/dist-snapshot-selfhost"
# `e.gfx.filter`: every filter pixel-exact or within 1e-9 of scipy.ndimage and scikit-image on a 32x32 image, Canny and watershed included (D870).
gfx_filter_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_filter/src/main.e" "$repo" x64 linux "$test_build/gfx-filter-selfhost")
[ "$gfx_filter_written" = 'executable written' ]
chmod +x "$test_build/gfx-filter-selfhost"
"$test_build/gfx-filter-selfhost"
# `e.gfx.vision`: a homography to 5e-14, epipolar residuals to 1e-8, RANSAC finding the planted inliers, a known shift and flow recovered, Zhang intrinsics to 1e-10, ORB and SIFT descriptors equal to a replica (D870).
gfx_vision_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_vision/src/main.e" "$repo" x64 linux "$test_build/gfx-vision-selfhost")
[ "$gfx_vision_written" = 'executable written' ]
chmod +x "$test_build/gfx-vision-selfhost"
"$test_build/gfx-vision-selfhost"
# `e.audio.analysis`: four pitch trackers within 0.5 Hz, a click train's onsets, tempo and beats exact, chroma of a C-major chord, a calibrated sine reading -23 LUFS (D870).
audio_analysis_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/audio_analysis/src/main.e" "$repo" x64 linux "$test_build/audio-analysis-selfhost")
[ "$audio_analysis_written" = 'executable written' ]
chmod +x "$test_build/audio-analysis-selfhost"
"$test_build/audio-analysis-selfhost"
# `e.audio.fx`: the static compressor curve, a limiter at its ceiling, EQ and reverb digests to 1e-9, an echo cancelled by 20 dB, a stretch keeping its pitch and a shift moving it (D871).
audio_fx_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/audio_fx/src/main.e" "$repo" x64 linux "$test_build/audio-fx-selfhost")
[ "$audio_fx_written" = 'executable written' ]
chmod +x "$test_build/audio-fx-selfhost"
"$test_build/audio-fx-selfhost"
# `e.audio.synth`: samples to 1e-12 against replicas and a PolyBLEP saw with a third of the naive aliasing energy (D871).
audio_synth_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/audio_synth/src/main.e" "$repo" x64 linux "$test_build/audio-synth-selfhost")
[ "$audio_synth_written" = 'executable written' ]
chmod +x "$test_build/audio-synth-selfhost"
"$test_build/audio-synth-selfhost"
# A generic instance's parameter or local named like a module-scope function of the instantiating module: the checker's local table starts empty when a body is lowered (D872).
instance_local_names_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/instance_local_names/src/main.e" "$repo" x64 linux "$test_build/instance-local-names-selfhost")
[ "$instance_local_names_written" = 'executable written' ]
chmod +x "$test_build/instance-local-names-selfhost"
"$test_build/instance-local-names-selfhost"
# `e.crypto.classic`: eight ciphers against a replica, the ROT13, LEMON and Playfair textbook vectors, every decrypt a roundtrip (D873).
crypto_classic_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_classic/src/main.e" "$repo" x64 linux "$test_build/crypto-classic-selfhost")
[ "$crypto_classic_written" = 'executable written' ]
chmod +x "$test_build/crypto-classic-selfhost"
"$test_build/crypto-classic-selfhost"
# `e.crypto.merkle`: the RFC 6962 eight-leaf roots, every inclusion proof, four consistency proofs, tampering rejected (D873).
crypto_merkle_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_merkle/src/main.e" "$repo" x64 linux "$test_build/crypto-merkle-selfhost")
[ "$crypto_merkle_written" = 'executable written' ]
chmod +x "$test_build/crypto-merkle-selfhost"
"$test_build/crypto-merkle-selfhost"
# `e.crypto.secret`: a 3-of-5 split equal to a replica row for row, all ten subsets reconstructing, two shares not (D873).
crypto_secret_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_secret/src/main.e" "$repo" x64 linux "$test_build/crypto-secret-selfhost")
[ "$crypto_secret_written" = 'executable written' ]
chmod +x "$test_build/crypto-secret-selfhost"
"$test_build/crypto-secret-selfhost"
# `e.fmt.lz4`: cramjam blocks and frames decoded, our blocks and frames decoded by cramjam, roundtrips of compressible, incompressible and empty input (D873).
fmt_lz4_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_lz4/src/main.e" "$repo" x64 linux "$test_build/fmt-lz4-selfhost")
[ "$fmt_lz4_written" = 'executable written' ]
chmod +x "$test_build/fmt-lz4-selfhost"
"$test_build/fmt-lz4-selfhost"
# `e.fmt.snappy`: byte-identical to cramjam on six inputs including three-block streams, CRC32C vector, a flipped checksum refused (D873).
fmt_snappy_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_snappy/src/main.e" "$repo" x64 linux "$test_build/fmt-snappy-selfhost")
[ "$fmt_snappy_written" = 'executable written' ]
chmod +x "$test_build/fmt-snappy-selfhost"
"$test_build/fmt-snappy-selfhost"
# `e.algo.egraph`: the egg README example saturating `(a*2)/2` to `a` in the replica's four iterations with its node and class counts, upward congruence after a merge, a capped associativity run still joining the two parenthesisations (D874).
algo_egraph_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_egraph/src/main.e" "$repo" x64 linux "$test_build/algo-egraph-selfhost")
[ "$algo_egraph_written" = 'executable written' ]
chmod +x "$test_build/algo-egraph-selfhost"
"$test_build/algo-egraph-selfhost"
# `e.algo.geo`: twenty-four cells bit-identical to s2sphere including poles, face centres, the antimeridian and level 30; parents, children, ranges, neighbours and tokens; London to Paris within a metre (D874).
algo_geo_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_geo/src/main.e" "$repo" x64 linux "$test_build/algo-geo-selfhost")
[ "$algo_geo_written" = 'executable written' ]
chmod +x "$test_build/algo-geo-selfhost"
"$test_build/algo-geo-selfhost"
# `e.algo.privacy`: noise samples equal to a PCG replica to 1e-12, 4000-sample moments within 5%, the exponential mechanism's picks and frequencies, composition bounds (D874).
algo_privacy_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_privacy/src/main.e" "$repo" x64 linux "$test_build/algo-privacy-selfhost")
[ "$algo_privacy_written" = 'executable written' ]
chmod +x "$test_build/algo-privacy-selfhost"
"$test_build/algo-privacy-selfhost"
# `e.algo.query`: orders and pointer-move counts equal to a replica (1372 against 3948 naive), distinct counts over sixty ranges equal to brute force (D874).
algo_query_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_query/src/main.e" "$repo" x64 linux "$test_build/algo-query-selfhost")
[ "$algo_query_written" = 'executable written' ]
chmod +x "$test_build/algo-query-selfhost"
"$test_build/algo-query-selfhost"
# `e.algo.smt`: the f^3(a)=a, f^5(a)=a textbook entailment, an unsatisfiable EUF instance, a forty-term partition equal to a replica, factoring 145 by bit-blasting, x<y<x unsatisfiable (D874).
algo_smt_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_smt/src/main.e" "$repo" x64 linux "$test_build/algo-smt-selfhost")
[ "$algo_smt_written" = 'executable written' ]
chmod +x "$test_build/algo-smt-selfhost"
"$test_build/algo-smt-selfhost"
# `e.crypto.cipher`: FIPS-197 and SP 800-38A vectors both ways, RFC 8439 block and sunscreen text, a CTR seek, PKCS#7 against cryptography, refusals (D875).
crypto_cipher_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_cipher/src/main.e" "$repo" x64 linux "$test_build/crypto-cipher-selfhost")
[ "$crypto_cipher_written" = 'executable written' ]
chmod +x "$test_build/crypto-cipher-selfhost"
"$test_build/crypto-cipher-selfhost"
# `e.fmt.avro`: zigzag vectors, a record resolved across promotions, dropped and defaulted fields and reordering to fastavro's bytes, union reindexing, `Mismatch` and `Malformed` (D875).
fmt_avro_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_avro/src/main.e" "$repo" x64 linux "$test_build/fmt-avro-selfhost")
[ "$fmt_avro_written" = 'executable written' ]
chmod +x "$test_build/fmt-avro-selfhost"
"$test_build/fmt-avro-selfhost"
# `e.fmt.flatbuffers`: the Monster built by the Python package read field by field including defaults, a struct, a vector of tables and a union; truncation and range errors answered, not trapped; a Neper-built Monster reading back equal (D875).
fmt_flatbuffers_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_flatbuffers/src/main.e" "$repo" x64 linux "$test_build/fmt-flatbuffers-selfhost")
[ "$fmt_flatbuffers_written" = 'executable written' ]
chmod +x "$test_build/fmt-flatbuffers-selfhost"
"$test_build/fmt-flatbuffers-selfhost"
# `e.fmt.jwt`: the RFC 7515 A.1 token, PyJWT tokens for four algorithms verified and every tamper refused, `alg: none` refused, claim windows, and signatures byte-equal to PyJWT (D875).
fmt_jwt_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_jwt/src/main.e" "$repo" x64 linux "$test_build/fmt-jwt-selfhost")
[ "$fmt_jwt_written" = 'executable written' ]
chmod +x "$test_build/fmt-jwt-selfhost"
"$test_build/fmt-jwt-selfhost"
# `e.net.idna`: all nineteen RFC 3492 samples both ways, eight domains against the idna package and back, every refusal (D875).
net_idna_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_idna/src/main.e" "$repo" x64 linux "$test_build/net-idna-selfhost")
[ "$net_idna_written" = 'executable written' ]
chmod +x "$test_build/net-idna-selfhost"
"$test_build/net-idna-selfhost"
# `e.fmt.arrow`: a seven-row pyarrow stream of ten columns including nulls, a list and a struct read value for value, a dictionary stream refused, truncation reported (D876).
fmt_arrow_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_arrow/src/main.e" "$repo" x64 linux "$test_build/fmt-arrow-selfhost")
[ "$fmt_arrow_written" = 'executable written' ]
chmod +x "$test_build/fmt-arrow-selfhost"
"$test_build/fmt-arrow-selfhost"
# `e.net.balance`: the `aabacaa` sequence, P2C picks equal to a PCG replica, a 65537-slot Maglev table equal to the replica with one backend's removal moving a fifth of the slots (D876).
net_balance_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_balance/src/main.e" "$repo" x64 linux "$test_build/net-balance-selfhost")
[ "$net_balance_written" = 'executable written' ]
chmod +x "$test_build/net-balance-selfhost"
"$test_build/net-balance-selfhost"
# `e.net.reliable`: a twenty-packet transfer losing two packets under Go-Back-N and Selective Repeat with the replica's retransmission lists, Jacobson's estimator step for step, Karn holding the backed-off RTO (D876).
net_reliable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_reliable/src/main.e" "$repo" x64 linux "$test_build/net-reliable-selfhost")
[ "$net_reliable_written" = 'executable written' ]
chmod +x "$test_build/net-reliable-selfhost"
"$test_build/net-reliable-selfhost"
# `e.ui.state`: the diamond running its sink once per change, a threshold memo, a batch collapsing three sets, a dependency dropped when a flag clears, run counts equal to a replica (D876).
ui_state_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_state/src/main.e" "$repo" x64 linux "$test_build/ui-state-selfhost")
[ "$ui_state_written" = 'executable written' ]
chmod +x "$test_build/ui-state-selfhost"
"$test_build/ui-state-selfhost"
# `e.ui.undo`: a 200-step scripted document equal to a replica's hash, capacity eviction, groups undone as one, coalesced typing, the dirty flag across the save point (D876).
ui_undo_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_undo/src/main.e" "$repo" x64 linux "$test_build/ui-undo-selfhost")
[ "$ui_undo_written" = 'executable written' ]
chmod +x "$test_build/ui-undo-selfhost"
"$test_build/ui-undo-selfhost"
# `e.fmt.lzma`: liblzma's alone, raw and .xz streams of a text and a 4 KB generated buffer decoded exactly, a flipped check byte refused (D877).
fmt_lzma_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_lzma/src/main.e" "$repo" x64 linux "$test_build/fmt-lzma-selfhost")
[ "$fmt_lzma_written" = 'executable written' ]
chmod +x "$test_build/fmt-lzma-selfhost"
"$test_build/fmt-lzma-selfhost"
# `e.fmt.parquet`: two pyarrow files (plain and Snappy) read column by column including nulls, dictionaries and delta encoding, hybrid vectors against a replica, truncation and bad magic reported (D877).
fmt_parquet_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_parquet/src/main.e" "$repo" x64 linux "$test_build/fmt-parquet-selfhost")
[ "$fmt_parquet_written" = 'executable written' ]
chmod +x "$test_build/fmt-parquet-selfhost"
"$test_build/fmt-parquet-selfhost"
# `e.net.coap`: the Appendix A GET byte for byte, a message with extended options round-tripped, the 3-9-21-45-93 s schedule, block options (D877).
net_coap_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_coap/src/main.e" "$repo" x64 linux "$test_build/net-coap-selfhost")
[ "$net_coap_written" = 'executable written' ]
chmod +x "$test_build/net-coap-selfhost"
"$test_build/net-coap-selfhost"
# `e.net.mqtt`: the specification's CONNECT bytes, remaining-length limits, fourteen topic-filter cases, QoS 1 and 2 flows producing the replica's byte stream, a duplicated QoS 2 publish delivered once (D877).
net_mqtt_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_mqtt/src/main.e" "$repo" x64 linux "$test_build/net-mqtt-selfhost")
[ "$net_mqtt_written" = 'executable written' ]
chmod +x "$test_build/net-mqtt-selfhost"
"$test_build/net-mqtt-selfhost"
# `e.net.stun`: the RFC 5769 request and both responses decoded with integrity and fingerprint verified, host and reflexive candidates with RFC 8445 priorities, pair ordering against a replica (D877).
net_stun_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_stun/src/main.e" "$repo" x64 linux "$test_build/net-stun-selfhost")
[ "$net_stun_written" = 'executable written' ]
chmod +x "$test_build/net-stun-selfhost"
"$test_build/net-stun-selfhost"
# `e.crypto.noise`: BLAKE2s against hashlib, IK messages byte-equal to a cryptography replica, both sides splitting to the same keys, a transport message crossing, tampering and a wrong psk refused (D878).
crypto_noise_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_noise/src/main.e" "$repo" x64 linux "$test_build/crypto-noise-selfhost")
[ "$crypto_noise_written" = 'executable written' ]
chmod +x "$test_build/crypto-noise-selfhost"
"$test_build/crypto-noise-selfhost"
# `e.fmt.brotli`: streams from the brotli package at qualities 0 to 11 including 29 dictionary references and multi-block texts decoded exactly; truncation, trailing bytes and short buffers reported (D878).
fmt_brotli_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_brotli/src/main.e" "$repo" x64 linux "$test_build/fmt-brotli-selfhost")
[ "$fmt_brotli_written" = 'executable written' ]
chmod +x "$test_build/fmt-brotli-selfhost"
"$test_build/fmt-brotli-selfhost"
# `e.net.dns`: the RFC 8080 key tag and a re-signed MX RRset validated in mixed case, expiry and tampering refused, a P-256 signature, DS digests against hashlib, DoH GET and POST bytes (D878).
net_dns_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_dns/src/main.e" "$repo" x64 linux "$test_build/net-dns-selfhost")
[ "$net_dns_written" = 'executable written' ]
chmod +x "$test_build/net-dns-selfhost"
"$test_build/net-dns-selfhost"
# `e.net.http3`: the RFC 9000 varint vectors, a control stream split into frames with a partial tail, a six-header request block byte-equal to a replica and decoded back (D878).
net_http3_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_http3/src/main.e" "$repo" x64 linux "$test_build/net-http3-selfhost")
[ "$net_http3_written" = 'executable written' ]
chmod +x "$test_build/net-http3-selfhost"
"$test_build/net-http3-selfhost"
# `e.net.quic`: the RFC 9001 client Initial header, a scripted migration whose probe bytes equal a replica, validation switching the path and retiring the old id, no unused id refused, a timed-out probe failing (D878).
net_quic_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_quic/src/main.e" "$repo" x64 linux "$test_build/net-quic-selfhost")
[ "$net_quic_written" = 'executable written' ]
chmod +x "$test_build/net-quic-selfhost"
"$test_build/net-quic-selfhost"
# `e.db.pool`: MRU reuse, FIFO hand-off to waiters, a broken release replaced, the housekeeper's evictions, a 300-event script equal to a replica's fold and final counts (D879).
db_pool_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/db_pool/src/main.e" "$repo" x64 linux "$test_build/db-pool-selfhost")
[ "$db_pool_written" = 'executable written' ]
chmod +x "$test_build/db-pool-selfhost"
"$test_build/db-pool-selfhost"
# `e.db.query`: iterator and vectorized results equal, six joins equal to brute force as multisets, the four-relation Selinger order and cost, pushdowns producing the expected plan arrays, pruning and covering-index counts (D879).
db_query_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/db_query/src/main.e" "$repo" x64 linux "$test_build/db-query-selfhost")
[ "$db_query_written" = 'executable written' ]
chmod +x "$test_build/db-query-selfhost"
"$test_build/db-query-selfhost"
# `e.db.storage`: twenty-one checks against Python replicas: range scans, index lookups, both hash indexes, LSM finds through compaction, WAL recovery after truncation, eviction hit counts, a 2PL deadlock, snapshot reads, OCC outcomes (D879).
db_storage_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/db_storage/src/main.e" "$repo" x64 linux "$test_build/db-storage-selfhost")
[ "$db_storage_written" = 'executable written' ]
chmod +x "$test_build/db-storage-selfhost"
"$test_build/db-storage-selfhost"
# `e.fmt.flac`: seven libFLAC streams covering every channel assignment and subframe kind decoded sample for sample with the STREAMINFO MD5 verified; flipped and truncated streams reported (D879).
fmt_flac_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_flac/src/main.e" "$repo" x64 linux "$test_build/fmt-flac-selfhost")
[ "$fmt_flac_written" = 'executable written' ]
chmod +x "$test_build/fmt-flac-selfhost"
"$test_build/fmt-flac-selfhost"
# `e.text.bidi`: 150 BidiCharacterTest lines in the fixture, and the module passes all 91,707 lines of BidiCharacterTest.txt and all 770,241 cases of BidiTest.txt through a scratch driver (D879).
text_bidi_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_bidi/src/main.e" "$repo" x64 linux "$test_build/text-bidi-selfhost")
[ "$text_bidi_written" = 'executable written' ]
chmod +x "$test_build/text-bidi-selfhost"
"$test_build/text-bidi-selfhost"
# `e.concurrent.deque` and `e.concurrent.stack`: scripted single-thread sequences equal to a replica, then one owner and three thieves taking twenty thousand items exactly once, and four threads pushing and popping through a Treiber stack with every value seen once (D880).
concurrent_deque_stack_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/concurrent_deque_stack/src/main.e" "$repo" x64 linux "$test_build/concurrent-deque-stack-selfhost")
[ "$concurrent_deque_stack_written" = 'executable written' ]
chmod +x "$test_build/concurrent-deque-stack-selfhost"
"$test_build/concurrent-deque-stack-selfhost"
# `e.concurrent.reclaim`: the replica's exact free sets after each epoch advance and each scan, then four threads pushing, popping and retiring through the list under each scheme with a per-node reader count reporting zero frees while in use (D880).
concurrent_reclaim_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/concurrent_reclaim/src/main.e" "$repo" x64 linux "$test_build/concurrent-reclaim-selfhost")
[ "$concurrent_reclaim_written" = 'executable written' ]
chmod +x "$test_build/concurrent-reclaim-selfhost"
"$test_build/concurrent-reclaim-selfhost"
# `e.text.segment`: sampled test lines in the fixture, and the module passes all 1,823 WordBreakTest and 7,654 LineBreakTest lines through a scratch driver (D880).
text_segment_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_segment/src/main.e" "$repo" x64 linux "$test_build/text-segment-selfhost")
[ "$text_segment_written" = 'executable written' ]
chmod +x "$test_build/text-segment-selfhost"
"$test_build/text-segment-selfhost"
# `e.thread.pool`: a thousand tasks summing once each, a fork-join sum equal to the sequential one, uneven tasks spread over at least two stealing workers, two hundred DAG edges all ordered, deadlines in order (D880).
thread_pool_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/thread_pool/src/main.e" "$repo" x64 linux "$test_build/thread-pool-selfhost")
[ "$thread_pool_written" = 'executable written' ]
chmod +x "$test_build/thread-pool-selfhost"
"$test_build/thread-pool-selfhost"
# `e.algo.geom` planned functions: Bowyer-Watson Delaunay equal to scipy's triangles, Voronoi cells against a half-plane replica, Graham and quickhull equal to the existing hull, Greiner-Hormann booleans checked on a point grid, Minkowski sums, calipers, monotone triangulation, offsets (D881).
algo_geom_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_geom_plan/src/main.e" "$repo" x64 linux "$test_build/algo-geom-plan-selfhost")
[ "$algo_geom_plan_written" = 'executable written' ]
chmod +x "$test_build/algo-geom-plan-selfhost"
"$test_build/algo-geom-plan-selfhost"
# `e.algo.graph` planned functions: Bellman-Ford, Floyd-Warshall, Johnson, Dial, a radix-heap Dijkstra, three MSTs agreeing with networkx, an arborescence, articulation points and bridges, cores and trusses, triangles, maximal cliques, Euler paths (D881).
algo_graph_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_graph_plan/src/main.e" "$repo" x64 linux "$test_build/algo-graph-plan-selfhost")
[ "$algo_graph_plan_written" = 'executable written' ]
chmod +x "$test_build/algo-graph-plan-selfhost"
"$test_build/algo-graph-plan-selfhost"
# `e.algo.sketch` planned functions: thirty-one sketches and filters against a bit-exact replica: xor, binary fuse, ribbon, cuckoo and quotient filters, KLL, t-digest, DDSketch, GK, P-square, theta, KMV, sparse and sliding HLL, LSH (D881).
algo_sketch_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_sketch_plan/src/main.e" "$repo" x64 linux "$test_build/algo-sketch-plan-selfhost")
[ "$algo_sketch_plan_written" = 'executable written' ]
chmod +x "$test_build/algo-sketch-plan-selfhost"
"$test_build/algo-sketch-plan-selfhost"
# `e.algo.stat` planned functions: numpy's nine quantile methods bit-exact, moments, entropies, covariance and Ledoit-Wolf shrinkage, three correlations, KDE, bootstrap and jackknife, Wilson and Clopper-Pearson intervals, expected shortfall, moment and likelihood fits (D881).
algo_stat_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_stat_plan/src/main.e" "$repo" x64 linux "$test_build/algo-stat-plan-selfhost")
[ "$algo_stat_plan_written" = 'executable written' ]
chmod +x "$test_build/algo-stat-plan-selfhost"
"$test_build/algo-stat-plan-selfhost"
# `e.algo.linalg.matrix` planned functions: LU with pivoting, solves and an inverse equal to the old one, Cholesky, Householder QR, Givens, Gram-Schmidt, RREF, powers, power iteration, Jacobi eigenpairs, one-sided Jacobi SVD and a Poisson V-cycle, against numpy, scipy and sympy (D882).
algo_matrix_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_matrix_plan/src/main.e" "$repo" x64 linux "$test_build/algo-matrix-plan-selfhost")
[ "$algo_matrix_plan_written" = 'executable written' ]
chmod +x "$test_build/algo-matrix-plan-selfhost"
"$test_build/algo-matrix-plan-selfhost"
# `e.algo.sort` and `e.algo.rand` planned functions: twelve sorters agreeing with the existing order and keeping stability where promised, cycle-sort write counts and patience piles equal to a replica; LCG, xorshift and LFSR generators bit-exact, alias tables, stratified and Latin-hypercube points, weighted, decayed, priority and VarOpt sampling over a bit-exact PCG64 (D882).
algo_sort_rand_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_sort_rand_plan/src/main.e" "$repo" x64 linux "$test_build/algo-sort-rand-plan-selfhost")
[ "$algo_sort_rand_plan_written" = 'executable written' ]
chmod +x "$test_build/algo-sort-rand-plan-selfhost"
"$test_build/algo-sort-rand-plan-selfhost"
# `e.bytes` planned functions: byte and bit reversal, parity, the zero-byte trick, integer logarithms, powers of two, sign extension, Gray codes, hex and Base58 codecs, streaming Base64 equal to the one-shot codec at every chunk size (D882).
bytes_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/bytes_plan/src/main.e" "$repo" x64 linux "$test_build/bytes-plan-selfhost")
[ "$bytes_plan_written" = 'executable written' ]
chmod +x "$test_build/bytes-plan-selfhost"
"$test_build/bytes-plan-selfhost"
# `e.algo.coding` and `e.algo.dp` planned functions: whole-buffer Elias-gamma, Rice, move-to-front and BWT entries, an adaptive arithmetic coder and a rANS coder byte-exact with replicas, LZ78 through a table reset, simple8b words; both-direction monotonic stacks, the convex hull trick and a batched Li Chao tree against brute force (D883).
algo_coding_dp_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_coding_dp_plan/src/main.e" "$repo" x64 linux "$test_build/algo-coding-dp-plan-selfhost")
[ "$algo_coding_dp_plan_written" = 'executable written' ]
chmod +x "$test_build/algo-coding-dp-plan-selfhost"
"$test_build/algo-coding-dp-plan-selfhost"
# `e.data.cache` planned functions: one access operation per policy over the existing steps, and ARC in full, seven policies replayed over Zipf and hot-plus-scan traces with hit counts and resident sets equal to replicas and ARC ahead of LRU (D883).
data_cache_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_cache_plan/src/main.e" "$repo" x64 linux "$test_build/data-cache-plan-selfhost")
[ "$data_cache_plan_written" = 'executable written' ]
chmod +x "$test_build/data-cache-plan-selfhost"
"$test_build/data-cache-plan-selfhost"
# `e.data.heap` planned functions: heapify under its planned name, a min-max heap, and leftist, skew, randomized meldable, pairing and binomial heaps over one caller node pool, two thousand scripted operations each popping the replica's sequence with invariants checked throughout (D883).
data_heap_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_heap_plan/src/main.e" "$repo" x64 linux "$test_build/data-heap-plan-selfhost")
[ "$data_heap_plan_written" = 'executable written' ]
chmod +x "$test_build/data-heap-plan-selfhost"
"$test_build/data-heap-plan-selfhost"
# `e.game.ai` planned functions: minimax, alpha-beta, PVS, iterative deepening and quiescence agreeing on a forced tic-tac-toe win with the replica's node counts, expectimax, a transposition table, UCT search with integer confidence bounds and a bit-exact rollout stream, resumable behaviour trees, GOAP plans, utility curves and boids in fixed point (D883).
game_ai_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/game_ai_plan/src/main.e" "$repo" x64 linux "$test_build/game-ai-plan-selfhost")
[ "$game_ai_plan_written" = 'executable written' ]
chmod +x "$test_build/game-ai-plan-selfhost"
"$test_build/game-ai-plan-selfhost"
# `e.crypto.kdf` planned functions: PBKDF2 over both HMACs, scrypt on the RFC 7914 vector, bcrypt with Blowfish tables generated from pi and checked against the bcrypt package, Argon2id on the RFC 9106 vector and against cryptography, BLAKE2b against hashlib (D884).
crypto_kdf_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_kdf_plan/src/main.e" "$repo" x64 linux "$test_build/crypto-kdf-plan-selfhost")
[ "$crypto_kdf_plan_written" = 'executable written' ]
chmod +x "$test_build/crypto-kdf-plan-selfhost"
"$test_build/crypto-kdf-plan-selfhost"
# `e.crypto.sign` planned functions: RFC 6979 P-256 signing on the RFC's vectors, BIP-340 Schnorr over secp256k1 on all nineteen published rows, RSA-PSS byte-equal to a replica and verified by cryptography, ffdhe2048 DH, Poly1305 on the RFC 8439 vector, BLAKE3 on the official vectors in all three modes (D884).
crypto_sign_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_sign_plan/src/main.e" "$repo" x64 linux "$test_build/crypto-sign-plan-selfhost")
[ "$crypto_sign_plan_written" = 'executable written' ]
chmod +x "$test_build/crypto-sign-plan-selfhost"
"$test_build/crypto-sign-plan-selfhost"
# `e.gfx.paint`, `e.gfx.image` and `e.gfx.geometry` planned functions: path flattening and stroking, the sRGB transfer pair, gradients with three spreads, all thirteen Porter-Duff operators, scanline coverage fills, subpixel glyph rendering and glyph distance fields, PSNR and an SSIM replica checked against scikit-image, average, difference and DCT hashes (D884).
gfx_paint_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_paint_plan/src/main.e" "$repo" x64 linux "$test_build/gfx-paint-plan-selfhost")
[ "$gfx_paint_plan_written" = 'executable written' ]
chmod +x "$test_build/gfx-paint-plan-selfhost"
"$test_build/gfx-paint-plan-selfhost"
# `e.gfx.scene` planned functions: a perspective-correct rasterizer, painter's ordering, deferred shading, clustered lights, cascaded and PCF shadows, SSAO, screen-space reflections, temporal and FXAA anti-aliasing, depth peeling, sphere tracing and volumetric fog, each on a sixteen-pixel-square buffer against a numpy replica (D884).
gfx_scene_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_scene_plan/src/main.e" "$repo" x64 linux "$test_build/gfx-scene-plan-selfhost")
[ "$gfx_scene_plan_written" = 'executable written' ]
chmod +x "$test_build/gfx-scene-plan-selfhost"
"$test_build/gfx-scene-plan-selfhost"
# `e.math.fft` and `e.math.filter` planned functions: orthonormal DCT-II/III/IV against SciPy, an MDCT with exact overlap-add reconstruction, Haar and Daubechies-4 wavelets against PyWavelets, and one-call EKF, scaled UKF and particle filter steps over a tracking problem (D884).
math_fft_filter_plan_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/math_fft_filter_plan/src/main.e" "$repo" x64 linux "$test_build/math-fft-filter-plan-selfhost")
[ "$math_fft_filter_plan_written" = 'executable written' ]
chmod +x "$test_build/math-fft-filter-plan-selfhost"
"$test_build/math-fft-filter-plan-selfhost"
# `e.algo.hash` planned functions across eleven `e.algo` modules: Fletcher, LRC, MurmurHash3 and Zobrist hashing, bitset set operations, BDD building from an expression tree, ECM factoring splitting two semiprimes, Christofides, 3-opt and Lin-Kernighan tours reaching the brute-force optimum, virtual ring nodes, a global cardinality propagator, a rollback union-find, Barnes-Hut within one percent of direct summation, ternary search (D910).
algo_gaps_a_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_gaps_a/src/main.e" "$repo" x64 linux "$test_build/algo-gaps-a-selfhost")
[ "$algo_gaps_a_written" = 'executable written' ]
chmod +x "$test_build/algo-gaps-a-selfhost"
"$test_build/algo-gaps-a-selfhost"
# `e.algo.rand` planned functions across six `e.algo` modules: decayed reservoirs, polar normals, importance weights and a Gaussian copula, Tseitin and cardinality encodings, Kolmogorov-Smirnov, Anderson-Darling and Shapiro-Wilk against SciPy, GARCH and Hawkes recursions, UUID v5, ULID, snowflake and nanoid (D910).
algo_gaps_b_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/algo_gaps_b/src/main.e" "$repo" x64 linux "$test_build/algo-gaps-b-selfhost")
[ "$algo_gaps_b_written" = 'executable written' ]
chmod +x "$test_build/algo-gaps-b-selfhost"
"$test_build/algo-gaps-b-selfhost"
# `e.algo.graph.community` planned functions across six `e.algo.graph` sub-modules: Leiden communities, max-min fair rates, LR planarity agreeing with networkx on twenty-five graphs, the auction assignment equal to the Hungarian optimum, greedy best-first, Suurballe's disjoint pair, Yen's k shortest paths equal to networkx, binary-lifting and RMQ lowest common ancestors, tree isomorphism (D910).
graph_gaps_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/graph_gaps/src/main.e" "$repo" x64 linux "$test_build/graph-gaps-selfhost")
[ "$graph_gaps_written" = 'executable written' ]
chmod +x "$test_build/graph-gaps-selfhost"
"$test_build/graph-gaps-selfhost"
# `e.data.linked` planned functions across eight `e.data` modules: list splicing, sublist search and move-to-front, queue watermarks with hysteresis, lazy range updates and persistent roots, range-tree counting, the succinct structures' planned entry points, trees rebuilt from traversals, a compacted radix trie, and the DABA sliding-window aggregator equal to brute force at every step (D910).
data_gaps_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/data_gaps/src/main.e" "$repo" x64 linux "$test_build/data-gaps-selfhost")
[ "$data_gaps_written" = 'executable written' ]
chmod +x "$test_build/data-gaps-selfhost"
"$test_build/data-gaps-selfhost"
# `e.dist.clock` planned entry points across eleven distributed and network modules: vector clocks, Raft election and replication rounds, wait-for graphs from a lock table, the phi accrual detector, gossip dissemination, one-call Redlock, Ricart-Agrawala, Raymond's tree and Chandy-Lamport, and the constructors the plan names for hazard pointers, Maglev and the ARQ senders (D910).
dist_gaps_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/dist_gaps/src/main.e" "$repo" x64 linux "$test_build/dist-gaps-selfhost")
[ "$dist_gaps_written" = 'executable written' ]
chmod +x "$test_build/dist-gaps-selfhost"
"$test_build/dist-gaps-selfhost"
# `e.fmt.asn1` planned functions across seven `e.fmt` modules: a DER writer and a BER reader, canonical CBOR equal to cbor2, a CSV writer equal to Python's, HTML escaping and an HTML tokenizer equal to html.parser's events, JSON canonicalization byte-equal to RFC 8785's reference, all fifteen merge-patch rows, a JSON tokenizer, quoted-printable encoding equal to quopri, query strings equal to urllib (D911).
fmt_gaps_a_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_gaps_a/src/main.e" "$repo" x64 linux "$test_build/fmt-gaps-a-selfhost")
[ "$fmt_gaps_a_written" = 'executable written' ]
chmod +x "$test_build/fmt-gaps-a-selfhost"
"$test_build/fmt-gaps-a-selfhost"
# `e.fmt.xml` planned functions across four `e.fmt` modules: an XML DOM, pull reader, namespace resolver and XPath subset checked against ElementTree, a schema-less protobuf decoder re-encoding byte-equal, whole-buffer LZW, and a Zstandard encoder with predefined FSE sequences whose frames python-zstandard decompresses (D911).
fmt_gaps_b_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_gaps_b/src/main.e" "$repo" x64 linux "$test_build/fmt-gaps-b-selfhost")
[ "$fmt_gaps_b_written" = 'executable written' ]
chmod +x "$test_build/fmt-gaps-b-selfhost"
"$test_build/fmt-gaps-b-selfhost"
# `e.text.regex` planned functions across twelve `e.text` modules: Thompson NFA, Pike VM, subset-construction DFA, Moore minimization and DFA runs agreeing with Python's re, Aho-Corasick and collation entry points, charset detection, Elias-Fano postings, ellipsis truncation, ROUGE, font fallback runs, Porter2 stemming equal to Snowball on two hundred words, byte-pair encoding, identifier checks, UTF-16 conversion (D911).
text_gaps_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_gaps/src/main.e" "$repo" x64 linux "$test_build/text-gaps-selfhost")
[ "$text_gaps_written" = 'executable written' ]
chmod +x "$test_build/text-gaps-selfhost"
"$test_build/text-gaps-selfhost"
# `e.ml.ann` planned functions across seven `e.ml` modules: HNSW with recall one against brute force and a bit-exact structure, IVF-PQ, MinHash LSH, one-call naive Bayes, DBSCAN, OPTICS and BIRCH equal to scikit-learn, streaming k-means, KL and JS divergences, margin and averaged perceptrons, reverse-mode autodiff checked by finite differences, Frequent Directions within its error bound, temperature sampling (D911).
ml_gaps_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ml_gaps/src/main.e" "$repo" x64 linux "$test_build/ml-gaps-selfhost")
[ "$ml_gaps_written" = 'executable written' ]
chmod +x "$test_build/ml-gaps-selfhost"
"$test_build/ml-gaps-selfhost"
# `e.net.http.auth` and planned functions across sixteen modules and the new `e.net.http.auth`: TPDF dither, a Luenberger observer, AES-GCM and CBC dispatch names, Certificate Transparency SCT verification, Neper and Itanium demangling, grid BFS, Theta* and Amanatides-Woo rays, saturating arithmetic, float unpacking, CIDR and private-address tests, SameSite, CORS preflight and CSP nonces, PKCE and WebAuthn assertions signed in Python, grammar-constrained decoding, LPA*, D* Lite and PRM, string padding, interval merging and Julian days (D911).
misc_gaps_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/misc_gaps/src/main.e" "$repo" x64 linux "$test_build/misc-gaps-selfhost")
[ "$misc_gaps_written" = 'executable written' ]
chmod +x "$test_build/misc-gaps-selfhost"
"$test_build/misc-gaps-selfhost"
# `e.crypto.kx` post-quantum entries: ML-KEM-768 with keys, ciphertexts and shared secrets equal to kyber-py including implicit rejection, ML-DSA-44 keys and deterministic signatures equal to dilithium-py with malformed hints refused, XMSS (RFC 8391) against a byte-level replica at height four in the fixture and height ten once, SHAKE128/256 against hashlib (D912).
crypto_pq_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/crypto_pq/src/main.e" "$repo" x64 linux "$test_build/crypto-pq-selfhost")
[ "$crypto_pq_written" = 'executable written' ]
chmod +x "$test_build/crypto-pq-selfhost"
"$test_build/crypto-pq-selfhost"
# `e.test.coverage` planned functions: block, branch and MC/DC coverage from counters, grammar-based generation and hierarchical delta debugging, golden files with a Myers diff, normalised snapshots, fault injection plans over readers and writers, HTTP cassettes recorded and replayed (D912).
test_gaps_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/test_gaps/src/main.e" "$repo" x64 linux "$test_build/test-gaps-selfhost")
[ "$test_gaps_written" = 'executable written' ]
chmod +x "$test_build/test-gaps-selfhost"
"$test_build/test-gaps-selfhost"
# `e.mem` planned functions: pool, slab and buddy allocators over caller storage (offsets, checked against a replica), a backoff spin lock, an epoch-based RCU cell with four readers seeing no retired index, and the mmap `map`/`unmap` names; the C bootstrap still builds the compiler (D912).
runtime_gaps_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/runtime_gaps/src/main.e" "$repo" x64 linux "$test_build/runtime-gaps-selfhost")
[ "$runtime_gaps_written" = 'executable written' ]
chmod +x "$test_build/runtime-gaps-selfhost"
"$test_build/runtime-gaps-selfhost"
# `e.gpu` planned kernels on the CPU backend: a bitonic sorting network launched once per stage and pass over a device buffer, and a tiled online-softmax attention within 1e-4 of numpy with the tile count visible (D912).
gpu_gaps_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gpu_gaps/src/main.e" "$repo" x64 linux "$test_build/gpu-gaps-selfhost")
[ "$gpu_gaps_written" = 'executable written' ]
chmod +x "$test_build/gpu-gaps-selfhost"
"$test_build/gpu-gaps-selfhost"
# `e.thread.fiber`: a cooperative scheduler whose hand-off leaves exactly one fiber running, a round-robin order equal to a replica over two hundred switches, suspend, resume and join, every thread joined at the end (D926).
thread_fiber_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/thread_fiber/src/main.e" "$repo" x64 linux "$test_build/thread-fiber-selfhost")
[ "$thread_fiber_written" = 'executable written' ]
chmod +x "$test_build/thread-fiber-selfhost"
"$test_build/thread-fiber-selfhost"
# `e.os.send_file`, `e.os.signal` and `e.os.sandbox`: a file's bytes moved to a loopback socket by the kernel, a raised signal reaching its handler and the default restored, and a sandboxed child refused its forbidden syscall or its child process (D926).
os_gaps_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_gaps/src/main.e" "$repo" x64 linux "$test_build/os-gaps-selfhost")
[ "$os_gaps_written" = 'executable written' ]
chmod +x "$test_build/os-gaps-selfhost"
"$test_build/os-gaps-selfhost"
# `e.fmt.opus`: SILK-only packets decoded bit-exactly against libopus across every bandwidth, frame size and channel count, hybrid and CELT-only within 1.53e-5 of it, the framing refusals, and the unsupported rates named (D928).
fmt_opus_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_opus/src/main.e" "$repo" x64 linux "$test_build/fmt-opus-selfhost")
[ "$fmt_opus_written" = 'executable written' ]
chmod +x "$test_build/fmt-opus-selfhost"
"$test_build/fmt-opus-selfhost"
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
# `e.net` covers strict IP values, real TCP/UDP, stream adapters, portable native-error
# mapping and honest poll-based control; synchronous controlled DNS refuses unsupported bounds.
net_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net/src/main.e" "$repo" x64 linux "$test_build/net-selfhost")
[ "$net_written" = 'executable written' ]
chmod +x "$test_build/net-selfhost"
"$test_build/net-selfhost"
# The delivered `e.net.http` codecs run over a one-byte source, and real loopback clients
# pin bounded GET/HEAD plus chunked streaming and cancellation. SSE pins split UTF-8/CRLF,
# retained state, the EOF rule and flat memory over ten thousand events.
http_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_http/src/main.e" "$repo" x64 linux "$test_build/net-http-selfhost")
[ "$http_written" = 'executable written' ]
chmod +x "$test_build/net-http-selfhost"
"$test_build/net-http-selfhost"
# `e.net.ws` pins both RFC handshakes plus bounded inbound and outbound frames.
ws_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_ws/src/main.e" "$repo" x64 linux "$test_build/net-ws-selfhost")
[ "$ws_written" = 'executable written' ]
chmod +x "$test_build/net-ws-selfhost"
"$test_build/net-ws-selfhost"
# `e.net.tls` constructors are inert until handshake and expose pinned metadata.
tls_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/net_tls/src/main.e" "$repo" x64 linux "$test_build/net-tls-selfhost")
[ "$tls_written" = 'executable written' ]
chmod +x "$test_build/net-tls-selfhost"
"$test_build/net-tls-selfhost"
# `e.text.collate` pins code-point and overflow-free natural ordering.
collate_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_collate/src/main.e" "$repo" x64 linux "$test_build/text-collate-selfhost")
[ "$collate_written" = 'executable written' ]
chmod +x "$test_build/text-collate-selfhost"
"$test_build/text-collate-selfhost"
# `e.time.cron` pins six-field parsing, day rules, offsets and next-time search.
cron_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/time_cron/src/main.e" "$repo" x64 linux "$test_build/time-cron-selfhost")
[ "$cron_written" = 'executable written' ]
chmod +x "$test_build/time-cron-selfhost"
"$test_build/time-cron-selfhost"
# `e.grep` pins recursive literal matches and its stateless index contract.
grep_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/grep/src/main.e" "$repo" x64 linux "$test_build/grep-selfhost")
[ "$grep_written" = 'executable written' ]
chmod +x "$test_build/grep-selfhost"
(cd "$fs_scratch" && "$test_build/grep-selfhost")
# `e.audio` pins interleaved PCM views and host-independent sample conversion.
audio_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/audio/src/main.e" "$repo" x64 linux "$test_build/audio-selfhost")
[ "$audio_written" = 'executable written' ]
chmod +x "$test_build/audio-selfhost"
"$test_build/audio-selfhost"
# `e.audio.mixer` pins lifecycle, deterministic clipped mixing and integer resampling.
audio_mixer_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/audio_mixer/src/main.e" "$repo" x64 linux "$test_build/audio-mixer-selfhost")
[ "$audio_mixer_written" = 'executable written' ]
chmod +x "$test_build/audio-mixer-selfhost"
"$test_build/audio-mixer-selfhost"
# `e.audio.spatial` (D767) pins integer pan at the four bearings, linear attenuation over a
# source's range, gain-only placement on a live voice, and cues that draw a variant from the
# caller's generator and respect their cooldown.
audio_spatial_surface=$(grep -E '^(type|fn|error|const|var) ' "$repo/lib/e/audio/spatial.e" | sed -E 's/^(type|fn|error|const|var) ([A-Za-z_][A-Za-z0-9_]*).*/\2/')
expected_audio_spatial_surface='Listener
Source
Cue
Unknown
pan
attenuate
place
trigger
step_cues'
[ "$audio_spatial_surface" = "$expected_audio_spatial_surface" ]
audio_spatial_parsed=$($test_build/neper-self parse-file "$repo/lib/e/audio/spatial.e")
[ "$audio_spatial_parsed" = 'parse file ok' ]
audio_spatial_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/audio_spatial/src/main.e" "$repo" x64 linux "$test_build/audio-spatial-selfhost")
[ "$audio_spatial_written" = 'executable written' ]
chmod +x "$test_build/audio-spatial-selfhost"
audio_spatial_output=$("$test_build/audio-spatial-selfhost")
[ "$audio_spatial_output" = 'audio spatial ok' ]
# `e.fmt.wav` pins bounded PCM RIFF parsing, streaming decode, seek and exact encoding.
wav_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_wav/src/main.e" "$repo" x64 linux "$test_build/fmt-wav-selfhost")
[ "$wav_written" = 'executable written' ]
chmod +x "$test_build/fmt-wav-selfhost"
"$test_build/fmt-wav-selfhost"
# `e.fmt.mp3` (D770): Layer III against minimp3 -- three LAME streams whole, chunked and after a seek, within two LSB.
mp3_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_mp3/src/main.e" "$repo" x64 linux "$test_build/fmt-mp3-selfhost")
[ "$mp3_written" = 'executable written' ]
chmod +x "$test_build/fmt-mp3-selfhost"
mp3_output=$("$test_build/fmt-mp3-selfhost")
[ "$mp3_output" = 'fmt mp3 ok' ]
# `e.gfx.geometry`, `e.gfx.paint`, `e.gfx.image` (D774): rectangles, transforms and a bounded path
# builder; sRGB, premultiplication and brush validation; images sized, cleared, blitted with clipping.
gfx_core_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_core/src/main.e" "$repo" x64 linux "$test_build/gfx-core-selfhost")
[ "$gfx_core_written" = 'executable written' ]
chmod +x "$test_build/gfx-core-selfhost"
gfx_core_output=$("$test_build/gfx-core-selfhost")
[ "$gfx_core_output" = 'gfx core ok' ]
# `e.fmt.png` (D774): every colour type and depth, tRNS and Adam7 decoded identically to libpng
# through Pillow; an exact encode read back by both decoders; refusals for APNG and bounds.
fmt_png_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_png/src/main.e" "$repo" x64 linux "$test_build/fmt-png-selfhost")
[ "$fmt_png_written" = 'executable written' ]
chmod +x "$test_build/fmt-png-selfhost"
fmt_png_output=$("$test_build/fmt-png-selfhost")
[ "$fmt_png_output" = 'fmt png ok' ]
# `e.fmt.jpeg` (D774): baseline 4:4:4 and 4:2:0, progressive, greyscale and restart intervals within
# a few steps of libjpeg; a baseline encode decoded back within libjpeg's own error.
fmt_jpeg_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_jpeg/src/main.e" "$repo" x64 linux "$test_build/fmt-jpeg-selfhost")
[ "$fmt_jpeg_written" = 'executable written' ]
chmod +x "$test_build/fmt-jpeg-selfhost"
fmt_jpeg_output=$("$test_build/fmt-jpeg-selfhost")
[ "$fmt_jpeg_output" = 'fmt jpeg ok' ]
# `e.fmt.webp` (D774): VP8L decoded exactly and VP8 with ALPH within a few steps of libwebp, an
# animation inspected and decoded first-frame-only, an exact lossless encode libwebp reads back.
fmt_webp_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/fmt_webp/src/main.e" "$repo" x64 linux "$test_build/fmt-webp-selfhost")
[ "$fmt_webp_written" = 'executable written' ]
chmod +x "$test_build/fmt-webp-selfhost"
fmt_webp_output=$("$test_build/fmt-webp-selfhost")
[ "$fmt_webp_output" = 'fmt webp ok' ]
# `e.text.layout` (D775): paragraphs over two synthetic fonts -- wrapping, alignment, justification,
# fallback and two-level bidi, a line budget with an ellipsis, hit testing, carets and selections.
text_layout_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/text_layout/src/main.e" "$repo" x64 linux "$test_build/text-layout-selfhost")
[ "$text_layout_written" = 'executable written' ]
chmod +x "$test_build/text-layout-selfhost"
text_layout_output=$("$test_build/text-layout-selfhost")
[ "$text_layout_output" = 'text layout ok' ]
# `e.ui.style`, `e.ui.layout` (D775): style defaults and validation; flex growth, shrinking, every
# alignment, unbounded limits; grid tracks fixed, auto and flexible with gaps; Invalid and Overflow.
ui_core_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_core/src/main.e" "$repo" x64 linux "$test_build/ui-core-selfhost")
[ "$ui_core_written" = 'executable written' ]
chmod +x "$test_build/ui-core-selfhost"
ui_core_output=$("$test_build/ui-core-selfhost")
[ "$ui_core_output" = 'ui core ok' ]
# `e.test.fuzz` (D776): deterministic mutation from the seed finds a two-byte failure twice alike,
# minimization lands on those two bytes, budgets and deadlines stop, corpus and bound refusals.
test_fuzz_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/test_fuzz/src/main.e" "$repo" x64 linux "$test_build/test-fuzz-selfhost")
[ "$test_fuzz_written" = 'executable written' ]
chmod +x "$test_build/test-fuzz-selfhost"
test_fuzz_output=$("$test_build/test-fuzz-selfhost")
[ "$test_fuzz_output" = 'test fuzz ok' ]
# `e.test.coverage` (D776): hits through the instrumentation entry, snapshot, reset, merge sorted
# by file and region with a duplicate refused, and the JSON shape.
test_coverage_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/test_coverage/src/main.e" "$repo" x64 linux "$test_build/test-coverage-selfhost")
[ "$test_coverage_written" = 'executable written' ]
chmod +x "$test_build/test-coverage-selfhost"
test_coverage_output=$("$test_build/test-coverage-selfhost")
[ "$test_coverage_output" = 'test coverage ok' ]
# `e.asset` (D777): the fixture project's `project.yaml` assets become the registry --
# sorted, hashed, typed, attributed -- through the compiler-generated overlay; a project
# without a manifest has the empty registry; a manifest entry the loader does not accept
# is reported at the manifest under E-MODULE-9999.
asset_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/asset/src/main.e" "$repo" x64 linux "$test_build/asset-selfhost")
[ "$asset_written" = 'executable written' ]
chmod +x "$test_build/asset-selfhost"
asset_output=$("$test_build/asset-selfhost")
[ "$asset_output" = 'asset ok' ]
# The build manifest lists every declared asset (D792): sorted by name, with the
# project-relative path, media type, attributes, size and SHA-256.
asset_manifest=$(cat "$repo/tests/selfhost/fixtures/link/asset/.neper/debug/build-manifest.json")
case "$asset_manifest" in
    *'"assets":[{"name":"bytes/all@1x","source":{"root":"project","path":"assets/all.bin"},"media_type":"application/octet-stream","attributes":[{"name":"base","value":"bytes/all"},{"name":"scale","value":"1"}],"size":256,"sha256":"40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880"},{"name":"bytes/empty",'*'{"name":"text/hello","source":{"root":"project","path":"assets/hello.txt"},"media_type":"text/plain","attributes":[{"name":"base","value":"text/hello"},{"name":"locale","value":""},{"name":"theme","value":"any"}],"size":18,"sha256":"30d428be3e8f02a9e56e7d2363a421eb0f883382216df0c6c9c34e639d7ac9b0"}]'*) ;;
    *) printf '%s\n' "the build manifest does not list the declared assets: $asset_manifest" >&2; exit 1 ;;
esac
asset_empty_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/asset_empty/src/main.e" "$repo" x64 linux "$test_build/asset-empty-selfhost")
[ "$asset_empty_written" = 'executable written' ]
chmod +x "$test_build/asset-empty-selfhost"
asset_empty_output=$("$test_build/asset-empty-selfhost")
[ "$asset_empty_output" = 'asset empty ok' ]
if asset_invalid_output=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/asset_invalid/src/main.e" "$repo" x64 linux "$test_build/asset-invalid-selfhost" 2>&1); then
    printf '%s\n' 'an asset manifest entry with an unknown key unexpectedly compiled' >&2
    exit 1
fi
case "$asset_invalid_output" in
    *'project.yaml:1:1: error[E-MODULE-9999]: `project.yaml` has an `assets:` entry the loader does not accept'*) ;;
    *) printf '%s\n' 'an asset manifest entry with an unknown key was not rejected at the manifest' >&2; exit 1 ;;
esac
# `e.gpu` on the CPU backend (D778): the device, queues, buffers, `gpu.launch[K]` over
# a 1-D and a 2-D kernel with the ids, tokens and every refusal; `examples/saxpy.e`
# prints the CPU checksum; a kernel called directly, a bare `@gpu` and a host slice
# in a launch pack are refused at the call.
gpu_cpu_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gpu_cpu/src/main.e" "$repo" x64 linux "$test_build/gpu-cpu-selfhost")
[ "$gpu_cpu_written" = 'executable written' ]
chmod +x "$test_build/gpu-cpu-selfhost"
gpu_cpu_output=$("$test_build/gpu-cpu-selfhost")
[ "$gpu_cpu_output" = 'gpu cpu ok' ]
saxpy_written=$($test_build/neper-self emit-executable "$repo/examples/saxpy.e" "$repo" x64 linux "$test_build/saxpy-selfhost")
[ "$saxpy_written" = 'executable written' ]
chmod +x "$test_build/saxpy-selfhost"
saxpy_output=$("$test_build/saxpy-selfhost")
[ "$saxpy_output" = 'cpu    checksum 16777216' ]
gpu_direct=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/gpu_direct_call/src/main.e" "$repo" x64 linux 2>&1 || true)
case "$gpu_direct" in
    *'main.e:9:5: error[E-TYPE-9999]: `fill` is a kernel and can only be run through `gpu.launch`'*) ;;
    *) printf '%s\n' "a direct kernel call was not refused: $gpu_direct" >&2; exit 1 ;;
esac
gpu_bare=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/gpu_bare_attribute/src/main.e" "$repo" x64 linux 2>&1 || true)
case "$gpu_bare" in
    *'main.e:4:1: error[E-TYPE-9999]: `fill` carries `@gpu` without a usable workgroup size'*) ;;
    *) printf '%s\n' "a bare @gpu was not refused: $gpu_bare" >&2; exit 1 ;;
esac
gpu_argument=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/gpu_launch_argument/src/main.e" "$repo" x64 linux 2>&1 || true)
case "$gpu_argument" in
    *'main.e:9:9: error[E-TYPE-9999]: `fill` takes a device slice at this position'*) ;;
    *) printf '%s\n' "a host slice in a launch pack was not refused: $gpu_argument" >&2; exit 1 ;;
esac
# `e.gpu.tensor` (D779): a strided host view uploaded contiguous, `add` and `matmul` as
# launches agreeing with the host tensor module and the plain formula, an i64 kernel,
# every `Shape` refusal, a released tensor stale.
gpu_tensor_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gpu_tensor/src/main.e" "$repo" x64 linux "$test_build/gpu-tensor-selfhost")
[ "$gpu_tensor_written" = 'executable written' ]
chmod +x "$test_build/gpu-tensor-selfhost"
gpu_tensor_output=$("$test_build/gpu-tensor-selfhost")
[ "$gpu_tensor_output" = 'gpu tensor ok' ]
# `gpu.barrier()` on the CPU backend (D780): the barrier loop-fission machine over device
# memory, a barrier in a loop, two workgroups apart, a barrier-free kernel under the same
# frames; an invocation returning before a barrier its peers reach traps as `barrier`;
# a barrier outside a kernel is refused.
gpu_barrier_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gpu_barrier/src/main.e" "$repo" x64 linux "$test_build/gpu-barrier-selfhost")
[ "$gpu_barrier_written" = 'executable written' ]
chmod +x "$test_build/gpu-barrier-selfhost"
gpu_barrier_output=$("$test_build/gpu-barrier-selfhost")
[ "$gpu_barrier_output" = 'gpu barrier ok' ]
gpu_divergence_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gpu_divergence/src/main.e" "$repo" x64 linux "$test_build/gpu-divergence-selfhost")
[ "$gpu_divergence_written" = 'executable written' ]
chmod +x "$test_build/gpu-divergence-selfhost"
gpu_divergence_status=0
gpu_divergence_output=$("$test_build/gpu-divergence-selfhost" 2>&1) || gpu_divergence_status=$?
[ "$gpu_divergence_status" = 134 ]
case "$gpu_divergence_output" in
    *'trap[barrier]: invocation (2, 0, 0) of workgroup (0, 0, 0) returned before barrier 1 that invocation (0, 0, 0)'*) ;;
    *) printf '%s\n' "a divergent workgroup did not trap as barrier: $gpu_divergence_output" >&2; exit 1 ;;
esac
gpu_outside=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/gpu_barrier_outside/src/main.e" "$repo" x64 linux 2>&1 || true)
case "$gpu_outside" in
    *'main.e:4:5: error[E-TYPE-9999]: `gpu.barrier()` is written outside a kernel'*) ;;
    *) printf '%s\n' "a barrier outside a kernel was not refused: $gpu_outside" >&2; exit 1 ;;
esac
# `shared var` on the CPU backend (D781): the spec's block sum through workgroup memory
# over three workgroups, a struct-typed shared var, the 0xCD fill before the publishing
# barrier; a shared var outside a kernel and one with an initialiser are refused.
gpu_shared_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gpu_shared/src/main.e" "$repo" x64 linux "$test_build/gpu-shared-selfhost")
[ "$gpu_shared_written" = 'executable written' ]
chmod +x "$test_build/gpu-shared-selfhost"
gpu_shared_output=$("$test_build/gpu-shared-selfhost")
[ "$gpu_shared_output" = 'gpu shared ok' ]
gpu_shared_outside=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/gpu_shared_outside/src/main.e" "$repo" x64 linux 2>&1 || true)
case "$gpu_shared_outside" in
    *'main.e:4:5: error[E-TYPE-9999]: `shared var` is legal only directly in a kernel'*) ;;
    *) printf '%s\n' "a shared var outside a kernel was not refused: $gpu_shared_outside" >&2; exit 1 ;;
esac
gpu_shared_init=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/gpu_shared_initializer/src/main.e" "$repo" x64 linux 2>&1 || true)
case "$gpu_shared_init" in
    *'main.e:5:5: error[E-TYPE-9999]: `tile` is a `shared var` with an initialiser'*) ;;
    *) printf '%s\n' "a shared var with an initialiser was not refused: $gpu_shared_init" >&2; exit 1 ;;
esac
# `meta.signed[T]()` (D782): folded like `meta.kind`, a bare or negated bool question
# settles an `if`; `link/gpu_tensor` reaches the unsigned kernels through it.
meta_signed_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/meta_signed/src/main.e" "$repo" x64 linux "$test_build/meta-signed-selfhost")
[ "$meta_signed_written" = 'executable written' ]
chmod +x "$test_build/meta-signed-selfhost"
meta_signed_output=$("$test_build/meta-signed-selfhost")
[ "$meta_signed_output" = 'meta signed ok' ]
# `printf` and `format` inside a generic of another module (D784): the template body
# accepts a `T` it cannot format yet, and each instance's expansion is the caller's.
format_generic_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/format_generic/src/main.e" "$repo" x64 linux "$test_build/format-generic-selfhost")
[ "$format_generic_written" = 'executable written' ]
chmod +x "$test_build/format-generic-selfhost"
format_generic_output=$("$test_build/format-generic-selfhost")
[ "$format_generic_output" = 'n=42;m=-7;x=2.5;format generic ok' ]
# The fault buffer (D785): a kernel's failed bounds check is a record `sync` and
# `download` answer as `Fault` once, the invocation gone and the others finished;
# a `@nocheck` block carries no check and no record.
for fault_case in 'gpu_fault_bounds:gpu fault ok' 'gpu_fault_nocheck:gpu nocheck ok'; do
    fault_name=${fault_case%%:*}
    fault_expected=${fault_case#*:}
    fault_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/$fault_name/src/main.e" "$repo" x64 linux "$test_build/$fault_name-selfhost")
    [ "$fault_written" = 'executable written' ]
    chmod +x "$test_build/$fault_name-selfhost"
    fault_output=$("$test_build/$fault_name-selfhost")
    [ "$fault_output" = "$fault_expected" ]
done
# Presentation (D791): images a kernel writes, an offscreen target's frames acquired,
# presented and read back as the snapshot, resize, and the refusals.
gpu_present_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gpu_present/src/main.e" "$repo" x64 linux "$test_build/gpu-present-selfhost")
[ "$gpu_present_written" = 'executable written' ]
chmod +x "$test_build/gpu-present-selfhost"
gpu_present_output=$("$test_build/gpu-present-selfhost")
[ "$gpu_present_output" = 'gpu present ok' ]
# The native window primitives (D795, D803): over the X11 socket of the display the
# suite runs under (WSLg), the same surface as Windows.
os_window_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_window/src/main.e" "$repo" x64 linux "$test_build/os-window-selfhost")
[ "$os_window_written" = 'executable written' ]
chmod +x "$test_build/os-window-selfhost"
os_window_output=$("$test_build/os-window-selfhost")
[ "$os_window_output" = 'os window ok' ]
# `e.gfx.scene` (D796): the CPU reference renderer over an offscreen target -- fills,
# an anti-aliased edge, clips, a gradient, a stroke, an image, a glyph, a layer, a
# rotation -- checked pixel by pixel, and the refusals.
gfx_scene_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/gfx_scene/src/main.e" "$repo" x64 linux "$test_build/gfx-scene-selfhost")
[ "$gfx_scene_written" = 'executable written' ]
chmod +x "$test_build/gfx-scene-selfhost"
gfx_scene_output=$("$test_build/gfx-scene-selfhost")
[ "$gfx_scene_output" = 'gfx scene ok' ]
# `e.ui.window` and `e.ui.input` (D797): a window over the X11 backend (D803).
ui_window_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_window/src/main.e" "$repo" x64 linux "$test_build/ui-window-selfhost")
[ "$ui_window_written" = 'executable written' ]
chmod +x "$test_build/ui-window-selfhost"
ui_window_output=$("$test_build/ui-window-selfhost")
[ "$ui_window_output" = 'ui window ok' ]
# `e.ui.asset` (D798): variants chosen by locale, theme and scale from the fixture
# project's registry, a font from it, and the texture cache over a renderer.
ui_asset_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_asset/src/main.e" "$repo" x64 linux "$test_build/ui-asset-selfhost")
[ "$ui_asset_written" = 'executable written' ]
chmod +x "$test_build/ui-asset-selfhost"
ui_asset_output=$("$test_build/ui-asset-selfhost")
[ "$ui_asset_output" = 'ui asset ok' ]
# `e.ui.widget` (D799): a tree reconciled, laid out, painted and read back; state by
# key across frames and a keyed reorder; a press dispatched; retirement; refusals.
ui_widget_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_widget/src/main.e" "$repo" x64 linux "$test_build/ui-widget-selfhost")
[ "$ui_widget_written" = 'executable written' ]
chmod +x "$test_build/ui-widget-selfhost"
ui_widget_output=$("$test_build/ui-widget-selfhost")
[ "$ui_widget_output" = 'ui widget ok' ]
# `e.ui.testing` and `e.ui.animation` (D801): a harness pumping frames without a
# window, elements by key, a press sent, a snapshot compared; curves and controllers.
ui_testing_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_testing/src/main.e" "$repo" x64 linux "$test_build/ui-testing-selfhost")
[ "$ui_testing_written" = 'executable written' ]
chmod +x "$test_build/ui-testing-selfhost"
ui_testing_output=$("$test_build/ui-testing-selfhost")
[ "$ui_testing_output" = 'ui testing ok' ]
# `e.ui.accessibility` and `e.ui.app` (D802): the semantic tree, and the app over the
# X11 backend (D803).
ui_accessibility_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_accessibility/src/main.e" "$repo" x64 linux "$test_build/ui-accessibility-selfhost")
[ "$ui_accessibility_written" = 'executable written' ]
chmod +x "$test_build/ui-accessibility-selfhost"
ui_accessibility_output=$("$test_build/ui-accessibility-selfhost")
[ "$ui_accessibility_output" = 'ui accessibility ok' ]
ui_app_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_app/src/main.e" "$repo" x64 linux "$test_build/ui-app-selfhost")
[ "$ui_app_written" = 'executable written' ]
chmod +x "$test_build/ui-app-selfhost"
ui_app_output=$("$test_build/ui-app-selfhost")
[ "$ui_app_output" = 'ui app ok' ]
# Theme tokens (D805, widget plan P0-01): the reference palettes, role lookups, control
# state resolution, size classes and host adaptation.
ui_theme_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_theme/src/main.e" "$repo" x64 linux "$test_build/ui-theme-selfhost")
[ "$ui_theme_written" = 'executable written' ]
chmod +x "$test_build/ui-theme-selfhost"
ui_theme_output=$("$test_build/ui-theme-selfhost")
[ "$ui_theme_output" = 'ui theme ok' ]
# Typed actions, gesture regions and scopes (D806, widget plan P0-02/P0-03): the
# arena settling taps, drags and hovers; Tab within a trapping scope; shortcuts.
ui_gesture_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_gesture/src/main.e" "$repo" x64 linux "$test_build/ui-gesture-selfhost")
[ "$ui_gesture_written" = 'executable written' ]
chmod +x "$test_build/ui-gesture-selfhost"
ui_gesture_output=$("$test_build/ui-gesture-selfhost")
[ "$ui_gesture_output" = 'ui gesture ok' ]
# Editable text (D807, widget plan P0-04): caret and selection by hit test, typed
# text, clipboard, undo and redo, a multiline editor and a composition.
ui_edit_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_edit/src/main.e" "$repo" x64 linux "$test_build/ui-edit-selfhost")
[ "$ui_edit_written" = 'executable written' ]
chmod +x "$test_build/ui-edit-selfhost"
ui_edit_output=$("$test_build/ui-edit-selfhost")
[ "$ui_edit_output" = 'ui edit ok' ]
# Viewports (D808, widget plan P0-05): the wheel, a drag with momentum, a bounce
# springing back, a scrollbar thumb, and a lazy viewport recycling its items.
ui_scroll_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_scroll/src/main.e" "$repo" x64 linux "$test_build/ui-scroll-selfhost")
[ "$ui_scroll_written" = 'executable written' ]
chmod +x "$test_build/ui-scroll-selfhost"
ui_scroll_output=$("$test_build/ui-scroll-selfhost")
[ "$ui_scroll_output" = 'ui scroll ok' ]
# Semantics (D809, widget plan P0-06): roles, states, relationships, live regions,
# collection places, hidden subtrees, an editor's value and platform actions.
ui_semantics_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_semantics/src/main.e" "$repo" x64 linux "$test_build/ui-semantics-selfhost")
[ "$ui_semantics_written" = 'executable written' ]
chmod +x "$test_build/ui-semantics-selfhost"
ui_semantics_output=$("$test_build/ui-semantics-selfhost")
[ "$ui_semantics_output" = 'ui semantics ok' ]
# Overlays (D810, widget plan P0-07): root-level paint against an anchor, kept in the
# window, presses routed by the topmost, a modal taking and returning the focus.
ui_overlay_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_overlay/src/main.e" "$repo" x64 linux "$test_build/ui-overlay-selfhost")
[ "$ui_overlay_written" = 'executable written' ]
chmod +x "$test_build/ui-overlay-selfhost"
ui_overlay_output=$("$test_build/ui-overlay-selfhost")
[ "$ui_overlay_output" = 'ui overlay ok' ]
# The host capability model (D811, widget plan P0-08): capabilities, insets,
# orientation, screens, lifecycle, and the lifecycle, insets and back events.
ui_host_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_host/src/main.e" "$repo" x64 linux "$test_build/ui-host-selfhost")
[ "$ui_host_written" = 'executable written' ]
chmod +x "$test_build/ui-host-selfhost"
ui_host_output=$("$test_build/ui-host-selfhost")
[ "$ui_host_output" = 'ui host ok' ]
# The widget harness and the gallery (D812, widget plan P0-09): semantic queries,
# gestures, focus traversal, the fake IME, viewport visibility, overlays, a faked host.
ui_gallery_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_gallery/src/main.e" "$repo" x64 linux "$test_build/ui-gallery-selfhost")
[ "$ui_gallery_written" = 'executable written' ]
chmod +x "$test_build/ui-gallery-selfhost"
ui_gallery_output=$("$test_build/ui-gallery-selfhost")
[ "$ui_gallery_output" = 'ui gallery ok' ]
# Content controls (D813, widget plan P1-01): text under roles with a line budget,
# selectable text, rich text with links, icon, image and canvas under a theme.
ui_content_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_content/src/main.e" "$repo" x64 linux "$test_build/ui-content-selfhost")
[ "$ui_content_written" = 'executable written' ]
chmod +x "$test_build/ui-content-selfhost"
ui_content_output=$("$test_build/ui-content-selfhost")
[ "$ui_content_output" = 'ui content ok' ]
# Surfaces (D814, widget plan P1-02): card, panel, group box, divider, badge, avatar
# and placeholder under a theme, with borders, radii and shadows painted.
ui_surface_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_surface/src/main.e" "$repo" x64 linux "$test_build/ui-surface-selfhost")
[ "$ui_surface_written" = 'executable written' ]
chmod +x "$test_build/ui-surface-selfhost"
ui_surface_output=$("$test_build/ui-surface-selfhost")
[ "$ui_surface_output" = 'ui surface ok' ]
# Primary layouts (D815, widget plan P1-03): row, column, wrap and positioned.
ui_layout_primary_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_layout_primary/src/main.e" "$repo" x64 linux "$test_build/ui-layout-primary-selfhost")
[ "$ui_layout_primary_written" = 'executable written' ]
chmod +x "$test_build/ui-layout-primary-selfhost"
ui_layout_primary_output=$("$test_build/ui-layout-primary-selfhost")
[ "$ui_layout_primary_output" = 'ui layout primary ok' ]
# Layout adapters (D816, widget plan P1-04): centred, padded, spacer, constrained,
# aspect, fitted and responsive.
ui_layout_adapters_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_layout_adapters/src/main.e" "$repo" x64 linux "$test_build/ui-layout-adapters-selfhost")
[ "$ui_layout_adapters_written" = 'executable written' ]
chmod +x "$test_build/ui-layout-adapters-selfhost"
ui_layout_adapters_output=$("$test_build/ui-layout-adapters-selfhost")
[ "$ui_layout_adapters_output" = 'ui layout adapters ok' ]
# Scrolling and insets (D817, widget plan P1-05): scroll view, a dragged scrollbar,
# safe area and keyboard avoiding.
ui_scroll_view_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_scroll_view/src/main.e" "$repo" x64 linux "$test_build/ui-scroll-view-selfhost")
[ "$ui_scroll_view_written" = 'executable written' ]
chmod +x "$test_build/ui-scroll-view-selfhost"
ui_scroll_view_output=$("$test_build/ui-scroll-view-selfhost")
[ "$ui_scroll_view_output" = 'ui scroll view ok' ]
# The button family (D818, widget plan P1-06): button, icon button, toggle and link
# under a theme, pressed by tap, Enter and Space, hovered, disabled.
ui_button_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_button/src/main.e" "$repo" x64 linux "$test_build/ui-button-selfhost")
[ "$ui_button_written" = 'executable written' ]
chmod +x "$test_build/ui-button-selfhost"
ui_button_output=$("$test_build/ui-button-selfhost")
[ "$ui_button_output" = 'ui button ok' ]
# The focus ring and state layers (D940, widget plan P5-02).
ui_focus_ring_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_focus_ring/src/main.e" "$repo" x64 linux "$test_build/ui-focus-ring-selfhost")
[ "$ui_focus_ring_written" = 'executable written' ]
chmod +x "$test_build/ui-focus-ring-selfhost"
ui_focus_ring_output=$("$test_build/ui-focus-ring-selfhost")
[ "$ui_focus_ring_output" = 'ui focus ring ok' ]
# The v2 button (D942, widget plan P5-03).
ui_button_v2_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_button_v2/src/main.e" "$repo" x64 linux "$test_build/ui-button-v2-selfhost")
[ "$ui_button_v2_written" = 'executable written' ]
chmod +x "$test_build/ui-button-v2-selfhost"
ui_button_v2_output=$("$test_build/ui-button-v2-selfhost")
[ "$ui_button_v2_output" = 'ui button v2 ok' ]
# The v2 action controls (D944, widget plan P5-03).
ui_actions_v2_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_actions_v2/src/main.e" "$repo" x64 linux "$test_build/ui-actions-v2-selfhost")
[ "$ui_actions_v2_written" = 'executable written' ]
chmod +x "$test_build/ui-actions-v2-selfhost"
ui_actions_v2_output=$("$test_build/ui-actions-v2-selfhost")
[ "$ui_actions_v2_output" = 'ui actions v2 ok' ]
# Discrete selection (D819, widget plan P1-07): checkbox, radio group, switch and
# segmented control under a theme, tapped, with their states in the tree.
ui_selection_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_selection/src/main.e" "$repo" x64 linux "$test_build/ui-selection-selfhost")
[ "$ui_selection_written" = 'executable written' ]
chmod +x "$test_build/ui-selection-selfhost"
ui_selection_output=$("$test_build/ui-selection-selfhost")
[ "$ui_selection_output" = 'ui selection ok' ]
# Range selection (D820, widget plan P1-08): a slider pressed, dragged, stepped and
# keyed, a range slider's nearer thumb.
ui_slider_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_slider/src/main.e" "$repo" x64 linux "$test_build/ui-slider-selfhost")
[ "$ui_slider_written" = 'executable written' ]
chmod +x "$test_build/ui-slider-selfhost"
ui_slider_output=$("$test_build/ui-slider-selfhost")
[ "$ui_slider_output" = 'ui slider ok' ]
# Progress (D822, widget plan P1-09): a bar, an indeterminate bar and a ring.
ui_progress_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_progress/src/main.e" "$repo" x64 linux "$test_build/ui-progress-selfhost")
[ "$ui_progress_written" = 'executable written' ]
chmod +x "$test_build/ui-progress-selfhost"
ui_progress_output=$("$test_build/ui-progress-selfhost")
[ "$ui_progress_output" = 'ui progress ok' ]
# Text fields (D823, widget plan P1-10): text, password, search and area fields.
ui_field_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_field/src/main.e" "$repo" x64 linux "$test_build/ui-field-selfhost")
[ "$ui_field_written" = 'executable written' ]
chmod +x "$test_build/ui-field-selfhost"
ui_field_output=$("$test_build/ui-field-selfhost")
[ "$ui_field_output" = 'ui field ok' ]
# Basic choice (D824, widget plan P1-11): a select with its menu, a list box.
ui_choice_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_choice/src/main.e" "$repo" x64 linux "$test_build/ui-choice-selfhost")
[ "$ui_choice_written" = 'executable written' ]
chmod +x "$test_build/ui-choice-selfhost"
ui_choice_output=$("$test_build/ui-choice-selfhost")
[ "$ui_choice_output" = 'ui choice ok' ]
# Forms (D825, widget plan P1-12): a field with its label and message, a form whose
# Enter and Escape are the caller's, a validation summary of links.
ui_form_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_form/src/main.e" "$repo" x64 linux "$test_build/ui-form-selfhost")
[ "$ui_form_written" = 'executable written' ]
chmod +x "$test_build/ui-form-selfhost"
ui_form_output=$("$test_build/ui-form-selfhost")
[ "$ui_form_output" = 'ui form ok' ]
# Disclosure and panes (D826, widget plan P1-13): a disclosure and an expander, tabs
# and a tab view, a split view's dragged and nudged handle.
ui_panes_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_panes/src/main.e" "$repo" x64 linux "$test_build/ui-panes-selfhost")
[ "$ui_panes_written" = 'executable written' ]
chmod +x "$test_build/ui-panes-selfhost"
ui_panes_output=$("$test_build/ui-panes-selfhost")
[ "$ui_panes_output" = 'ui panes ok' ]
# Transient UI (D827, widget plan P1-14): a tooltip, a menu button's modal menu, an
# alert dialog.
ui_transient_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_transient/src/main.e" "$repo" x64 linux "$test_build/ui-transient-selfhost")
[ "$ui_transient_written" = 'executable written' ]
chmod +x "$test_build/ui-transient-selfhost"
ui_transient_output=$("$test_build/ui-transient-selfhost")
[ "$ui_transient_output" = 'ui transient ok' ]
# Application navigation (D828, widget plan P1-15): app bar, toolbar, status bar, a
# navigation stack and the adaptive destination bar.
ui_navigation_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_navigation/src/main.e" "$repo" x64 linux "$test_build/ui-navigation-selfhost")
[ "$ui_navigation_written" = 'executable written' ]
chmod +x "$test_build/ui-navigation-selfhost"
ui_navigation_output=$("$test_build/ui-navigation-selfhost")
[ "$ui_navigation_output" = 'ui navigation ok' ]
# Advanced actions (D829, widget plan P2-01): rating, split button, speed dial, chips.
ui_actions_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_actions/src/main.e" "$repo" x64 linux "$test_build/ui-actions-selfhost")
[ "$ui_actions_written" = 'executable written' ]
chmod +x "$test_build/ui-actions-selfhost"
ui_actions_output=$("$test_build/ui-actions-selfhost")
[ "$ui_actions_output" = 'ui actions ok' ]
# Numeric and shortcut input (D830, widget plan P2-02): stepper, spin box, dial,
# shortcut recorder.
ui_numeric_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_numeric/src/main.e" "$repo" x64 linux "$test_build/ui-numeric-selfhost")
[ "$ui_numeric_written" = 'executable written' ]
chmod +x "$test_build/ui-numeric-selfhost"
ui_numeric_output=$("$test_build/ui-numeric-selfhost")
[ "$ui_numeric_output" = 'ui numeric ok' ]
# Advanced text and choice input (D831, widget plan P2-03): formatted field,
# autocomplete, combo box, token field, picker sheet, multi-select list.
ui_entry_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_entry/src/main.e" "$repo" x64 linux "$test_build/ui-entry-selfhost")
[ "$ui_entry_written" = 'executable written' ]
chmod +x "$test_build/ui-entry-selfhost"
ui_entry_output=$("$test_build/ui-entry-selfhost")
[ "$ui_entry_output" = 'ui entry ok' ]
# Feedback and disclosure (D832, widget plan P2-04): gauge, level, snackbar, toast,
# banner, info bar, skeleton, empty state, accordion.
ui_feedback_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_feedback/src/main.e" "$repo" x64 linux "$test_build/ui-feedback-selfhost")
[ "$ui_feedback_written" = 'executable written' ]
chmod +x "$test_build/ui-feedback-selfhost"
ui_feedback_output=$("$test_build/ui-feedback-selfhost")
[ "$ui_feedback_output" = 'ui feedback ok' ]
# Virtual collections (D833, widget plan P2-05): list, virtual list, grid view,
# virtual grid over a bounded source.
ui_collection_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_collection/src/main.e" "$repo" x64 linux "$test_build/ui-collection-selfhost")
[ "$ui_collection_written" = 'executable written' ]
chmod +x "$test_build/ui-collection-selfhost"
ui_collection_output=$("$test_build/ui-collection-selfhost")
[ "$ui_collection_output" = 'ui collection ok' ]
# Paged collections (D835, widget plan P2-06): page view, page indicator, pagination,
# carousel.
ui_paged_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_paged/src/main.e" "$repo" x64 linux "$test_build/ui-paged-selfhost")
[ "$ui_paged_written" = 'executable written' ]
chmod +x "$test_build/ui-paged-selfhost"
ui_paged_output=$("$test_build/ui-paged-selfhost")
[ "$ui_paged_output" = 'ui paged ok' ]
# Collection interaction (D839, widget plan P2-07): reorderable list, pull to refresh,
# swipe actions.
ui_interaction_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_interaction/src/main.e" "$repo" x64 linux "$test_build/ui-interaction-selfhost")
[ "$ui_interaction_written" = 'executable written' ]
chmod +x "$test_build/ui-interaction-selfhost"
ui_interaction_output=$("$test_build/ui-interaction-selfhost")
[ "$ui_interaction_output" = 'ui interaction ok' ]
# Adaptive navigation (D840, widget plan P2-08): menu bar, context menu, navigation
# split, drawer, rail, breadcrumbs.
ui_adaptive_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_adaptive/src/main.e" "$repo" x64 linux "$test_build/ui-adaptive-selfhost")
[ "$ui_adaptive_written" = 'executable written' ]
chmod +x "$test_build/ui-adaptive-selfhost"
ui_adaptive_output=$("$test_build/ui-adaptive-selfhost")
[ "$ui_adaptive_output" = 'ui adaptive ok' ]
# Transient presentation (D841, widget plan P2-09): popup, flyout, popover, dialog,
# sheet, bottom sheet, action sheet.
ui_presentation_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_presentation/src/main.e" "$repo" x64 linux "$test_build/ui-presentation-selfhost")
[ "$ui_presentation_written" = 'executable written' ]
chmod +x "$test_build/ui-presentation-selfhost"
ui_presentation_output=$("$test_build/ui-presentation-selfhost")
[ "$ui_presentation_output" = 'ui presentation ok' ]
# Pickers (D842, widget plan P2-10): calendar, date and range pickers, time and
# duration pickers, colour picker.
ui_pickers_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_pickers/src/main.e" "$repo" x64 linux "$test_build/ui-pickers-selfhost")
[ "$ui_pickers_written" = 'executable written' ]
chmod +x "$test_build/ui-pickers-selfhost"
ui_pickers_output=$("$test_build/ui-pickers-selfhost")
[ "$ui_pickers_output" = 'ui pickers ok' ]
# Content manipulation (D844, widget plan P2-11): the zoom view, in-application
# drag and drop, the clipboard commands.
ui_manipulation_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_manipulation/src/main.e" "$repo" x64 linux "$test_build/ui-manipulation-selfhost")
[ "$ui_manipulation_written" = 'executable written' ]
chmod +x "$test_build/ui-manipulation-selfhost"
ui_manipulation_output=$("$test_build/ui-manipulation-selfhost")
[ "$ui_manipulation_output" = 'ui manipulation ok' ]
# Rich tabular data (D845, widget plan P3-01): table, data grid, tree, outline, tree table.
ui_tabular_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_tabular/src/main.e" "$repo" x64 linux "$test_build/ui-tabular-selfhost")
[ "$ui_tabular_written" = 'executable written' ]
chmod +x "$test_build/ui-tabular-selfhost"
ui_tabular_output=$("$test_build/ui-tabular-selfhost")
[ "$ui_tabular_output" = 'ui tabular ok' ]
# Property editing (D851, widget plan P3-02): property grid, key-value editor.
ui_property_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_property/src/main.e" "$repo" x64 linux "$test_build/ui-property-selfhost")
[ "$ui_property_written" = 'executable written' ]
chmod +x "$test_build/ui-property-selfhost"
ui_property_output=$("$test_build/ui-property-selfhost")
[ "$ui_property_output" = 'ui property ok' ]
# Document workspace (D852, widget plan P3-03): document tabs, dock panel, dock
# layout, multi-document workspace.
ui_workspace_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_workspace/src/main.e" "$repo" x64 linux "$test_build/ui-workspace-selfhost")
[ "$ui_workspace_written" = 'executable written' ]
chmod +x "$test_build/ui-workspace-selfhost"
ui_workspace_output=$("$test_build/ui-workspace-selfhost")
[ "$ui_workspace_output" = 'ui workspace ok' ]
# Productivity navigation (D853, widget plan P3-04): wizard, window switcher, command palette.
ui_productivity_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_productivity/src/main.e" "$repo" x64 linux "$test_build/ui-productivity-selfhost")
[ "$ui_productivity_written" = 'executable written' ]
chmod +x "$test_build/ui-productivity-selfhost"
ui_productivity_output=$("$test_build/ui-productivity-selfhost")
[ "$ui_productivity_output" = 'ui productivity ok' ]
# Desktop selection and history (D854, widget plan P3-05): font picker, notification list.
ui_desktop_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_desktop/src/main.e" "$repo" x64 linux "$test_build/ui-desktop-selfhost")
[ "$ui_desktop_written" = 'executable written' ]
chmod +x "$test_build/ui-desktop-selfhost"
ui_desktop_output=$("$test_build/ui-desktop-selfhost")
[ "$ui_desktop_output" = 'ui desktop ok' ]
# `e.os.shell` (D885, native-shell-api): the capability record per host, refusals before the
# host is asked, and the freedesktop trash under a scratch data home.
os_shell_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_shell/src/main.e" "$repo" x64 linux "$test_build/os-shell-selfhost")
[ "$os_shell_written" = 'executable written' ]
chmod +x "$test_build/os-shell-selfhost"
rm -rf "$test_build/shell-home"
mkdir -p "$test_build/shell-home"
os_shell_output=$(XDG_DATA_HOME="$test_build/shell-home" NEPER_SHELL_TRASH_HOME="$test_build/shell-home" "$test_build/os-shell-selfhost")
[ "$os_shell_output" = 'os shell ok' ]
# The tray controller (D886, widget plan P4-01): the badge composed, the menu attached, and
# `Unsupported` throughout where the host has no tray.
ui_tray_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_tray/src/main.e" "$repo" x64 linux "$test_build/ui-tray-selfhost")
[ "$ui_tray_written" = 'executable written' ]
chmod +x "$test_build/ui-tray-selfhost"
ui_tray_output=$("$test_build/ui-tray-selfhost")
[ "$ui_tray_output" = 'ui tray ok' ]
# The taskbar and jump list controllers (D887, widget plan P4-02): `Unsupported` throughout
# on a host without a taskbar, and the capability record saying so first.
ui_taskbar_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_taskbar/src/main.e" "$repo" x64 linux "$test_build/ui-taskbar-selfhost")
[ "$ui_taskbar_written" = 'executable written' ]
chmod +x "$test_build/ui-taskbar-selfhost"
ui_taskbar_output=$("$test_build/ui-taskbar-selfhost")
[ "$ui_taskbar_output" = 'ui taskbar ok' ]
# The shell file operations (D888, widget plan P4-09): the app's verbs are the shell's answers,
# and a file the app trashes lands in the scratch data home's trash.
ui_shell_ops_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_shell_ops/src/main.e" "$repo" x64 linux "$test_build/ui-shell-ops-selfhost")
[ "$ui_shell_ops_written" = 'executable written' ]
chmod +x "$test_build/ui-shell-ops-selfhost"
rm -rf "$test_build/shell-home"
mkdir -p "$test_build/shell-home"
ui_shell_ops_output=$(XDG_DATA_HOME="$test_build/shell-home" NEPER_SHELL_TRASH_HOME="$test_build/shell-home" "$test_build/ui-shell-ops-selfhost")
[ "$ui_shell_ops_output" = 'ui shell ops ok' ]
# Notifications (D889, widget plan P4-03): the permission asked first, a notice through the
# desktop's daemon where there is one, and the refusals either way.
ui_notification_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_notification/src/main.e" "$repo" x64 linux "$test_build/ui-notification-selfhost")
[ "$ui_notification_written" = 'executable written' ]
chmod +x "$test_build/ui-notification-selfhost"
ui_notification_output=$("$test_build/ui-notification-selfhost")
[ "$ui_notification_output" = 'ui notification ok' ]
# Data exchange (D890, native-data-exchange-api): a host without a selection says so at every verb.
os_exchange_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/os_exchange/src/main.e" "$repo" x64 linux "$test_build/os-exchange-selfhost")
[ "$os_exchange_written" = 'executable written' ]
chmod +x "$test_build/os-exchange-selfhost"
os_exchange_output=$("$test_build/os-exchange-selfhost")
[ "$os_exchange_output" = 'os exchange ok' ]
# The typed data exchange model (D891, widget plan P4-04): pure, so the same on every host.
ui_exchange_model_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_exchange_model/src/main.e" "$repo" x64 linux "$test_build/ui-exchange-model-selfhost")
[ "$ui_exchange_model_written" = 'executable written' ]
chmod +x "$test_build/ui-exchange-model-selfhost"
ui_exchange_model_output=$("$test_build/ui-exchange-model-selfhost")
[ "$ui_exchange_model_output" = 'ui exchange model ok' ]
# Cross-application drag and drop (D892, widget plan P4-05): `Unsupported` on a host without OLE.
ui_drag_drop_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_drag_drop/src/main.e" "$repo" x64 linux "$test_build/ui-drag-drop-selfhost")
[ "$ui_drag_drop_written" = 'executable written' ]
chmod +x "$test_build/ui-drag-drop-selfhost"
ui_drag_drop_output=$("$test_build/ui-drag-drop-selfhost")
[ "$ui_drag_drop_output" = 'ui drag drop ok' ]
# The system clipboard and sharing (D893, widget plan P4-06): a host without a clipboard says so.
ui_clipboard_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_clipboard/src/main.e" "$repo" x64 linux "$test_build/ui-clipboard-selfhost")
[ "$ui_clipboard_written" = 'executable written' ]
chmod +x "$test_build/ui-clipboard-selfhost"
ui_clipboard_output=$("$test_build/ui-clipboard-selfhost")
[ "$ui_clipboard_output" = 'ui clipboard ok' ]
# File and document access (D894/D895, widget plan P4-07): refusals first, `Unsupported` without dialogs.
ui_file_access_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_file_access/src/main.e" "$repo" x64 linux "$test_build/ui-file-access-selfhost")
[ "$ui_file_access_written" = 'executable written' ]
chmod +x "$test_build/ui-file-access-selfhost"
ui_file_access_output=$("$test_build/ui-file-access-selfhost")
[ "$ui_file_access_output" = 'ui file access ok' ]
# Activation and associations (D896/D897, widget plan P4-08): the command line read three ways,
# the autostart entry under a scratch config home, and `Unsupported` for the rest.
ui_activation_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_activation/src/main.e" "$repo" x64 linux "$test_build/ui-activation-selfhost")
[ "$ui_activation_written" = 'executable written' ]
chmod +x "$test_build/ui-activation-selfhost"
rm -rf "$test_build/shell-home"
mkdir -p "$test_build/shell-home"
ui_activation_output=$(XDG_CONFIG_HOME="$test_build/shell-home" "$test_build/ui-activation-selfhost")
[ "$ui_activation_output" = 'ui activation ok' ]
# Global input and lifecycle (D898/D899, widget plan P4-10): the permission answered, the inhibitor
# through systemd-inhibit where a session has one, and `Unsupported` for the rest.
ui_lifecycle_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_lifecycle/src/main.e" "$repo" x64 linux "$test_build/ui-lifecycle-selfhost")
[ "$ui_lifecycle_written" = 'executable written' ]
chmod +x "$test_build/ui-lifecycle-selfhost"
ui_lifecycle_output=$("$test_build/ui-lifecycle-selfhost")
[ "$ui_lifecycle_output" = 'ui lifecycle ok' ]
# Printing (D900/D901, widget plan P4-11): a bad range refused first, `Unsupported` without a printer.
ui_print_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_print/src/main.e" "$repo" x64 linux "$test_build/ui-print-selfhost")
[ "$ui_print_written" = 'executable written' ]
chmod +x "$test_build/ui-print-selfhost"
ui_print_output=$("$test_build/ui-print-selfhost")
[ "$ui_print_output" = 'ui print ok' ]
# Hardware and security services (D902/D903, widget plan P4-12): statuses answered, the rest
# `Unsupported` behind the predicates.
ui_permissions_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_permissions/src/main.e" "$repo" x64 linux "$test_build/ui-permissions-selfhost")
[ "$ui_permissions_written" = 'executable written' ]
chmod +x "$test_build/ui-permissions-selfhost"
ui_permissions_output=$("$test_build/ui-permissions-selfhost")
[ "$ui_permissions_output" = 'ui permissions ok' ]
# The thirteen e.ui.* algorithms docs/algos.md names (D904): layout, tree and clock parts on every
# host; the app and window parts need a real window and are skipped without one.
ui_algorithms_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/ui_algorithms/src/main.e" "$repo" x64 linux "$test_build/ui-algorithms-selfhost")
[ "$ui_algorithms_written" = 'executable written' ]
chmod +x "$test_build/ui-algorithms-selfhost"
ui_algorithms_output=$("$test_build/ui-algorithms-selfhost")
[ "$ui_algorithms_output" = 'ui algorithms ok' ]
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
check_protocol_diagnostic protocol_signature 'main.e:6:9: error[E-TYPE-0003]: protocol `point_cmp` requires `fn(main.Point, main.Point) -> i32`, found `fn(*main.Point, main.Point) -> i32`'
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
# A `...` parameter outside the three intrinsic packs (D787): refused at the
# parameter, naming the function.
pack_refused=$($test_build/neper-self check-file "$repo/tests/selfhost/fixtures/check/argument_pack/src/main.e" "$repo" x64 linux 2>&1 || true)
case "$pack_refused" in
    *'main.e:6:10: error[E-TYPE-9999]: `total` declares a `...` parameter: an argument pack belongs to the three intrinsics'*) ;;
    *) printf '%s\n' "a user-declared argument pack was not refused: $pack_refused" >&2; exit 1 ;;
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
# the minimum divided by -1, and a shift count past the width -- scalar and over a
# vector's lanes, which is the same check -- each with its record.
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
arithmetic_status=0
arithmetic_output=$("$arithmetic_path" vshift 2>&1) || arithmetic_status=$?
[ "$arithmetic_status" -eq 134 ]
case "$arithmetic_output" in
    *'main.e:32:18: trap[shift]: shift by 40 on a width of 32'*) ;;
    *) printf '%s\n' "the vector shift case did not trap as section 11 says: $arithmetic_output" >&2; exit 1 ;;
esac
"$arithmetic_path" none
# `--unchecked` in a debug build (D929): every row but the always-on ones out of the
# image -- the shift runs on -- while `divide` still traps.
arithmetic_unchecked_path="$test_build/trap-arithmetic-unchecked-selfhost"
arithmetic_unchecked_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_arithmetic/src/main.e" "$repo" x64 linux "$arithmetic_unchecked_path" --unchecked)
[ "$arithmetic_unchecked_written" = 'executable written' ]
chmod +x "$arithmetic_unchecked_path"
"$arithmetic_unchecked_path" shift
arithmetic_unchecked_status=0
arithmetic_unchecked_output=$("$arithmetic_unchecked_path" zero 2>&1) || arithmetic_unchecked_status=$?
[ "$arithmetic_unchecked_status" -eq 134 ]
case "$arithmetic_unchecked_output" in
    *'main.e:14:17: trap[divide]: 7 / 0 divides by zero'*) ;;
    *) echo "a debug --unchecked build dropped the always-on divide check: $arithmetic_unchecked_output" >&2; exit 1 ;;
esac
# The `enum` row, which traps in every mode: `Kind(x)` naming no member, unsigned and
# signed, and the same casts naming members untouched.
enum_trap_path="$test_build/trap-enum-selfhost"
# The `invalid` row for a representation (D548, D554, H03): bytes read as a bool,
# an enum or a tagged union through mem.bitcast trap, debug and release, not unchecked.
for invalid_mode in "debug" "release --release" "unchecked --release --unchecked"; do
    set -- $invalid_mode
    invalid_name="$1"
    shift
    invalid_trap_path="$test_build/trap-invalid-$invalid_name"
    [ "$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_invalid/src/main.e" "$repo" x64 linux "$invalid_trap_path" "$@")" = 'executable written' ]
    chmod +x "$invalid_trap_path"
    invalid_status=0
    invalid_output=$("$invalid_trap_path" bool 2>&1) || invalid_status=$?
    if [ "$invalid_name" = unchecked ]; then
        [ "$invalid_status" -eq 0 ]
        for unchecked_representation in color bool-bytes color-bytes union; do
            "$invalid_trap_path" "$unchecked_representation" > /dev/null 2>&1
        done
    else
        [ "$invalid_status" -eq 134 ]
        case "$invalid_output" in
            *'main.e:16:17: trap[invalid]: no bool has value 7'*) ;;
            *) printf '%s\n' "the bool case did not trap as section 11 says ($invalid_name): $invalid_output" >&2; exit 1 ;;
        esac
        invalid_status=0
        invalid_output=$("$invalid_trap_path" color 2>&1) || invalid_status=$?
        [ "$invalid_status" -eq 134 ]
        case "$invalid_output" in
            *'main.e:20:17: trap[invalid]: no member of Color has value 7'*) ;;
            *) printf '%s\n' "the color case did not trap as section 11 says ($invalid_name): $invalid_output" >&2; exit 1 ;;
        esac
        invalid_status=0
        invalid_output=$("$invalid_trap_path" bool-bytes 2>&1) || invalid_status=$?
        [ "$invalid_status" -eq 134 ]
        case "$invalid_output" in
            *'main.e:25:17: trap[invalid]: no bool has value 7'*) ;;
            *) printf '%s\n' "the bool byte-array case did not trap as section 11 says ($invalid_name): $invalid_output" >&2; exit 1 ;;
        esac
        invalid_status=0
        invalid_output=$("$invalid_trap_path" color-bytes 2>&1) || invalid_status=$?
        [ "$invalid_status" -eq 134 ]
        case "$invalid_output" in
            *'main.e:30:17: trap[invalid]: no member of Color has value 7'*) ;;
            *) printf '%s\n' "the enum byte-array case did not trap as section 11 says ($invalid_name): $invalid_output" >&2; exit 1 ;;
        esac
        invalid_status=0
        invalid_output=$("$invalid_trap_path" union 2>&1) || invalid_status=$?
        [ "$invalid_status" -eq 134 ]
        case "$invalid_output" in
            *'main.e:35:21: trap[invalid]: no member of Maybe has value 7'*) ;;
            *) printf '%s\n' "the tagged-union case did not trap as section 11 says ($invalid_name): $invalid_output" >&2; exit 1 ;;
        esac
    fi
    "$invalid_trap_path" none > /dev/null 2>&1
done
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
# D923: a null check another check of the same pointer dominates is not made; a nil
# pointer still traps at its first dereference, and one checked only inside an `if`
# still traps at the later dereference.
elided_path="$test_build/trap-null-elided-selfhost"
elided_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/trap_null_elided/src/main.e" "$repo" x64 linux "$elided_path")
[ "$elided_written" = 'executable written' ]
chmod +x "$elided_path"
elided_status=0
elided_output=$("$elided_path" twice 2>&1) || elided_status=$?
[ "$elided_status" -eq 134 ]
case "$elided_output" in
    *'main.e:12:17: trap[null]: nil dereferenced as *Pair'*) ;;
    *) echo "the twice case did not trap at its first read: $elided_output" >&2; exit 1 ;;
esac
elided_status=0
elided_output=$("$elided_path" branchy 2>&1) || elided_status=$?
[ "$elided_status" -eq 134 ]
case "$elided_output" in
    *'main.e:19:15: trap[null]: nil dereferenced as *Pair'*) ;;
    *) echo "the branchy case did not trap at its later read: $elided_output" >&2; exit 1 ;;
esac
"$elided_path" none
# D925: section 4's `@packed` and `@align(N)` lay a struct and a union out as the spec
# says -- sizes, alignments and a packed value's bytes -- in debug and release.
layout_path="$test_build/layout-packed-selfhost"
for layout_mode in '' '--release'; do
    layout_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/layout_packed/src/main.e" "$repo" x64 linux "$layout_path" $layout_mode)
    [ "$layout_written" = 'executable written' ]
    chmod +x "$layout_path"
    "$layout_path"
done
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
    # Artifact-only enumeration (D557, H27): the first artifact is the root, every
    # artifact is hashed, and their Inventory sections reproduce the source manifest.
    inventory_artifact_dir="$inventory_scratch/.neper/$hot_manifest_mode/em"
    # A word list, not a bash array: this runner is POSIX sh, and no path here holds a
    # space, so the unquoted expansions below are the argument list.
    inventory_root="$inventory_artifact_dir/main.x64-linux.em"
    inventory_artifacts="$inventory_root"
    for inventory_artifact in "$inventory_artifact_dir"/*.em; do
        [ "$inventory_artifact" = "$inventory_root" ] || inventory_artifacts="$inventory_artifacts $inventory_artifact"
    done
    "$test_build/neper-self" manifest-em $inventory_artifacts --json > "$test_build/inventory-artifacts.json"
    python3 -c "import hashlib,json,sys; source=json.load(open(sys.argv[1])); artifact=json.load(open(sys.argv[2])); paths=sys.argv[3:]; assert artifact['unsafe']==source['unsafe']; assert artifact['mode']==sys.argv[3]; assert artifact['root_module']=='main' and artifact['inputs']==[] and artifact['options']['checks']=='retained'; paths=paths[1:]; assert len(artifact['artifacts'])==len(paths); assert all(row['path']==path and row['sha256']==hashlib.sha256(open(path,'rb').read()).hexdigest() for row,path in zip(artifact['artifacts'],paths))" "$inventory_scratch/.neper/$hot_manifest_mode/build-manifest.json" "$test_build/inventory-artifacts.json" "$hot_manifest_mode" $inventory_artifacts
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
        hot_unchecked_artifact_dir="$hot_scratch/.neper/release/em"
        hot_unchecked_root="$hot_unchecked_artifact_dir/main.x64-linux.em"
        hot_unchecked_artifacts="$hot_unchecked_root"
        for hot_unchecked_artifact in "$hot_unchecked_artifact_dir"/*.em; do
            [ "$hot_unchecked_artifact" = "$hot_unchecked_root" ] || hot_unchecked_artifacts="$hot_unchecked_artifacts $hot_unchecked_artifact"
        done
        "$test_build/neper-self" manifest-em $hot_unchecked_artifacts --json > "$test_build/hot-unchecked-artifacts.json"
        python3 -c "import json,sys; manifest=json.load(open(sys.argv[1])); assert manifest['mode']=='release' and manifest['options']['checks']=='off'" "$test_build/hot-unchecked-artifacts.json"
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
for conformance_case in 'accept scalar 0' 'accept aggregate 0' 'reject enum_values 1' 'reject lexical 1' 'reject when_local 1' 'reject scope 1' 'reject barrier 1' 'reject module_missing 1' 'reject qualifier_collision 1' 'reject reserved_local 1' 'reject try_not_fallible 1' 'reject return_count 1' 'reject generic_inference 1' 'reject condition_type 1' 'reject atomic_ordering 1' 'reject nesting 1' 'accept safety 0' 'reject safety_use_after_move 1' 'reject safety_cleanup_forgotten 1' 'reject safety_overwrite 1' 'reject safety_undef 1' 'reject safety_unchecked 1' 'reject safety_deferred_consumed 1' 'reject safety_moved_in_loop 1' 'reject safety_partial_move 1' 'reject safety_cleanup_signature 1' 'reject safety_borrowed 1' 'reject safety_borrowed_return 1' 'reject safety_copy 1' 'reject safety_copy_elements 1' 'reject safety_copy_generic 1' 'reject safety_handle_leak 1' 'reject safety_moved_while_borrowed 1' 'reject safety_arena_moved 1' 'reject safety_pushed_twice 1' 'accept regions 0' 'reject regions_reset 1' 'reject regions_view 1' 'reject regions_pointer_mutation 1' 'reject regions_join 1' 'reject safety_detached_frame 1' 'reject safety_thread_shared 1' 'reject safety_guard_leak 1' 'reject safety_thread_alias 1' 'reject regions_alias 1' 'reject safety_thread_slice 1' 'reject type_mismatch 1' 'reject safety_thread_field 1' 'reject safety_thread_reassign 1' 'reject safety_copy_toolchain 1' 'reject safety_rwguard_leak 1' 'reject safety_thread_group_leak 1' 'reject type_mismatch_fix 1' 'reject name_near 1' 'reject member_near 1' 'reject field_near 1' 'reject instance_site 1' 'reject instance_chain 1' 'reject each_function 1' 'reject safety_undef_value 1' 'reject type_near 1' 'reject type_mismatch_call 1' 'accept safety_undef_written 0' 'reject safety_undef_reference 1' 'reject safety_undef_branch 1' 'accept safety_cast_representation 0' 'reject safety_cast_representation 1' 'reject safety_cast_placement 1' 'accept safety_foreign_representation 0' 'reject safety_foreign_representation 1' 'reject safety_foreign_callback 1' 'reject safety_union_representation 1' 'reject safety_union_generic 1' 'reject layout_attribute 1' 'reject safety_codec_decode_resource 1' 'reject safety_codec_encode_resource 1'; do
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
# D672-D715: alias-aware region/thread identity and deferred-reset timing.
for conformance_case in 'reject regions_pointer_chain 1' 'reject regions_arena_alias 1' 'reject safety_thread_context_alias 1' 'accept regions_deferred_after_alloc 0' 'reject regions_deferred_escape 1' 'reject regions_arena_pointer_copy 1' 'reject regions_mark_copy 1' 'reject regions_accessor_alias 1' 'reject safety_thread_slice_context 1' 'reject regions_deferred_slice_escape 1' 'reject regions_deferred_pointer_escape 1' 'reject regions_deferred_pointer_alias_escape 1' 'reject regions_deferred_aggregate_escape 1' 'reject regions_deferred_aggregate_copy_escape 1' 'reject regions_deferred_aggregate_assignment_escape 1' 'reject safety_thread_aggregate_field_context 1' 'reject regions_aggregate_field_mutation 1' 'reject regions_aggregate_field_accessor 1' 'reject regions_deferred_nested_aggregate_escape 1' 'reject regions_deferred_nested_field_assignment_escape 1' 'reject regions_second_aggregate_field_alias 1' 'reject regions_deferred_second_aggregate_escape 1' 'reject regions_deferred_second_aggregate_copy_escape 1' 'reject regions_deferred_second_field_assignment_escape 1' 'reject safety_thread_second_aggregate_field_context 1' 'reject regions_third_aggregate_field_alias 1' 'reject regions_deferred_third_aggregate_escape 1' 'reject regions_deferred_third_aggregate_copy_escape 1' 'reject regions_deferred_third_field_assignment_escape 1' 'reject safety_thread_third_aggregate_field_context 1' 'reject regions_nested_second_field_alias 1' 'reject regions_deferred_nested_second_escape 1' 'reject regions_deferred_nested_second_copy_escape 1' 'reject regions_deferred_nested_pointer_assignment_escape 1' 'reject safety_thread_nested_second_field_context 1' 'reject regions_array_second_element_alias 1' 'reject regions_deferred_array_escape 1' 'reject regions_deferred_array_copy_escape 1' 'reject regions_deferred_array_element_assignment_escape 1' 'reject safety_thread_array_element_context 1' 'reject regions_dynamic_array_element_alias 1' 'reject regions_deferred_dynamic_array_element_escape 1' 'reject regions_dynamic_array_element_mutation 1' 'reject safety_thread_dynamic_array_element_context 1' 'reject regions_nested_dynamic_array_element_alias 1'; do
    set -- $conformance_case
    conformance_status=0
    $test_build/neper-self check-file "$conformance_root/$1/$2.e" "$repo" x64 linux --json > "$test_build/conformance-$1-$2.jsonl" || conformance_status=$?
    [ "$conformance_status" -eq "$3" ]
    cmp -s "$test_build/conformance-$1-$2.jsonl" "$conformance_root/$1/$2.expected.jsonl" || { printf '%s\n' "check-file --json on $1/$2.e differs from the conformance corpus" >&2; exit 1; }
done
# D716-D720: runtime-indexed affine fixed-array ownership and slice candidates.
for conformance_case in 'reject safety_dynamic_array_read 1' 'reject safety_dynamic_array_move 1' 'reject safety_dynamic_array_overwrite 1' 'reject safety_dynamic_array_store_leak 1' 'reject safety_dynamic_array_slice_offset 1'; do
    set -- $conformance_case
    conformance_status=0
    $test_build/neper-self check-file "$conformance_root/$1/$2.e" "$repo" x64 linux --json > "$test_build/conformance-$1-$2.jsonl" || conformance_status=$?
    [ "$conformance_status" -eq "$3" ]
    cmp -s "$test_build/conformance-$1-$2.jsonl" "$conformance_root/$1/$2.expected.jsonl" || { printf '%s\n' "check-file --json on $1/$2.e differs from the conformance corpus" >&2; exit 1; }
done
# D721-D725: explicit ownership transfer and exhaustive cleanup for resource slices.
for conformance_case in 'reject safety_owned_slice_leak 1' 'reject safety_owned_slice_partial 1' 'accept safety_owned_slice_sweep 0' 'accept safety_owned_slice_transfer 0' 'accept safety_owned_slice_offset_transfer 0'; do
    set -- $conformance_case
    conformance_status=0
    $test_build/neper-self check-file "$conformance_root/$1/$2.e" "$repo" x64 linux --json > "$test_build/conformance-$1-$2.jsonl" || conformance_status=$?
    [ "$conformance_status" -eq "$3" ]
    cmp -s "$test_build/conformance-$1-$2.jsonl" "$conformance_root/$1/$2.expected.jsonl" || { printf '%s\n' "check-file --json on $1/$2.e differs from the conformance corpus" >&2; exit 1; }
done
# D731-D735: declared, proved, propagated and serialized result-borrow summaries.
for conformance_case in 'reject regions_borrow_contract_name 1' 'reject regions_borrow_contract_body 1' 'accept regions_borrow_contract_aggregate 0' 'reject regions_borrow_contract_call 1' 'reject regions_borrow_contract_generic 1' 'accept regions_borrow_contract_artifact 0'; do
    set -- $conformance_case
    conformance_status=0
    $test_build/neper-self check-file "$conformance_root/$1/$2.e" "$repo" x64 linux --json > "$test_build/conformance-$1-$2.jsonl" || conformance_status=$?
    [ "$conformance_status" -eq "$3" ]
    cmp -s "$test_build/conformance-$1-$2.jsonl" "$conformance_root/$1/$2.expected.jsonl" || { printf '%s\n' "check-file --json on $1/$2.e differs from the conformance corpus" >&2; exit 1; }
done
borrow_summary_artifact="$test_build/borrow-summary.x64-linux.em"
[ "$($test_build/neper-self emit-em "$conformance_root/accept/regions_borrow_contract_artifact.e" "$repo" x64 linux "$borrow_summary_artifact")" = 'compiled module written' ]
borrow_summary_interface=$(od -An -tu8 -j64 -N8 "$borrow_summary_artifact" | tr -d ' ')
[ "$(od -An -tu4 -j$((borrow_summary_interface + 44)) -N4 "$borrow_summary_artifact" | tr -d ' ')" = '2' ]
# D736-D740: declared, proved, propagated and serialized no-escape inputs.
for conformance_case in 'accept regions_noescape_contract 0' 'reject regions_noescape_contract_name 1' 'accept regions_noescape_multi_contract 0' 'reject regions_noescape_multi_contract_duplicate 1' 'reject regions_noescape_contract_return 1' 'reject regions_noescape_multi_return 1' 'reject regions_noescape_contract_global 1' 'reject regions_noescape_multi_global 1' 'accept regions_noescape_contract_forward 0' 'accept regions_noescape_multi_forward 0' 'reject regions_noescape_contract_call 1' 'reject regions_noescape_multi_call 1' 'reject regions_noescape_contract_callback 1' 'reject regions_noescape_contract_thread 1' 'accept regions_noescape_contract_generic 0' 'accept regions_noescape_contract_artifact 0' 'accept regions_noescape_multi_artifact 0'; do
    set -- $conformance_case
    conformance_status=0
    $test_build/neper-self check-file "$conformance_root/$1/$2.e" "$repo" x64 linux --json > "$test_build/conformance-$1-$2.jsonl" || conformance_status=$?
    [ "$conformance_status" -eq "$3" ]
    cmp -s "$test_build/conformance-$1-$2.jsonl" "$conformance_root/$1/$2.expected.jsonl" || { printf '%s\n' "check-file --json on $1/$2.e differs from the conformance corpus" >&2; exit 1; }
done
noescape_summary_artifact="$test_build/noescape-summary.x64-linux.em"
[ "$($test_build/neper-self emit-em "$conformance_root/accept/regions_noescape_contract_artifact.e" "$repo" x64 linux "$noescape_summary_artifact")" = 'compiled module written' ]
noescape_summary_interface=$(od -An -tu8 -j64 -N8 "$noescape_summary_artifact" | tr -d ' ')
[ "$(od -An -tu2 -j4 -N2 "$noescape_summary_artifact" | tr -d ' ')" = '14' ]
[ "$(od -An -tu4 -j$((noescape_summary_interface + 48)) -N4 "$noescape_summary_artifact" | tr -d ' ')" = '1' ]
[ "$(od -An -tu4 -j$((noescape_summary_interface + 52)) -N4 "$noescape_summary_artifact" | tr -d ' ')" = '2' ]
noescape_multi_artifact="$test_build/noescape-multi.x64-linux.em"
[ "$($test_build/neper-self emit-em "$conformance_root/accept/regions_noescape_multi_artifact.e" "$repo" x64 linux "$noescape_multi_artifact")" = 'compiled module written' ]
noescape_multi_interface=$(od -An -tu8 -j64 -N8 "$noescape_multi_artifact" | tr -d ' ')
[ "$(od -An -tu4 -j$((noescape_multi_interface + 48)) -N4 "$noescape_multi_artifact" | tr -d ' ')" = '2' ]
[ "$(od -An -tu4 -j$((noescape_multi_interface + 52)) -N4 "$noescape_multi_artifact" | tr -d ' ')" = '1' ]
[ "$(od -An -tu4 -j$((noescape_multi_interface + 56)) -N4 "$noescape_multi_artifact" | tr -d ' ')" = '2' ]
# A consuming dereference follows its lexical pointer alias to the pinned resource
# (D610, H01).
pointer_move_status=0
$test_build/neper-self check-file "$conformance_root/reject/safety_pointer_move.e" "$repo" x64 linux --json > "$test_build/conformance-reject-safety_pointer_move.jsonl" || pointer_move_status=$?
[ "$pointer_move_status" -eq 1 ]
cmp -s "$test_build/conformance-reject-safety_pointer_move.jsonl" "$conformance_root/reject/safety_pointer_move.expected.jsonl" || { printf '%s
' "check-file --json on reject/safety_pointer_move.e differs from the conformance corpus" >&2; exit 1; }
# A concrete generic aggregate is classified from its substituted resource fields
# (D611, H01).
generic_aggregate_status=0
$test_build/neper-self check-file "$conformance_root/reject/safety_generic_aggregate.e" "$repo" x64 linux --json > "$test_build/conformance-reject-safety_generic_aggregate.jsonl" || generic_aggregate_status=$?
[ "$generic_aggregate_status" -eq 1 ]
cmp -s "$test_build/conformance-reject-safety_generic_aggregate.jsonl" "$conformance_root/reject/safety_generic_aggregate.expected.jsonl" || { printf '%s
' "check-file --json on reject/safety_generic_aggregate.e differs from the conformance corpus" >&2; exit 1; }
# A tagged union is affine as a whole when one of its payloads is affine
# (D612, H01).
tagged_resource_status=0
$test_build/neper-self check-file "$conformance_root/reject/safety_tagged_resource.e" "$repo" x64 linux --json > "$test_build/conformance-reject-safety_tagged_resource.jsonl" || tagged_resource_status=$?
[ "$tagged_resource_status" -eq 1 ]
cmp -s "$test_build/conformance-reject-safety_tagged_resource.jsonl" "$conformance_root/reject/safety_tagged_resource.expected.jsonl" || { printf '%s
' "check-file --json on reject/safety_tagged_resource.e differs from the conformance corpus" >&2; exit 1; }
# A resource closer may take context before its final owned parameter, but the
# owned resource must be last (D613, H01/H13).
for closer_case in 'accept safety_resource_closer 0' 'reject safety_cleanup_position 1'; do
    set -- $closer_case
    closer_status=0
    $test_build/neper-self check-file "$conformance_root/$1/$2.e" "$repo" x64 linux --json > "$test_build/conformance-$1-$2.jsonl" || closer_status=$?
    [ "$closer_status" -eq "$3" ]
    cmp -s "$test_build/conformance-$1-$2.jsonl" "$conformance_root/$1/$2.expected.jsonl" || { printf '%s
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
# The runtime's arena (D552, H05): a project whose own e.mem lays Arena out otherwise is refused at the build, E-LINK-0002.
for build_case in 'tools/build.e build 0' 'reject/scope.e build_reject 1' 'reject/arena_layout/src/main.e arena_layout 1'; do
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
# The image's digest reused when the image is the one on disk (D332): a third build of
# the same source into the same output finds its own bytes at the output path, skips the
# write -- the file's mtime stays -- and takes the digest from the manifest that
# recorded it, which is still the executable's.
image_stamp=$(stat -c %y "$test_build/conformance-tools-build-again.out")
(cd "$test_build" && ./neper-self emit-executable "$conformance_root/tools/build.e" "$repo" x64 linux "conformance-tools-build-again.out" > /dev/null)
[ "$(stat -c %y "$test_build/conformance-tools-build-again.out")" = "$image_stamp" ] || { printf '%s
' "a build whose image is already the file at the output path rewrote it" >&2; exit 1; }
manifest_reused=$(sed -n 's/.*"artifacts":\[{"path":"build\/linux\/tests\/selfhost\/conformance-tools-build-again.out","kind":"executable","target":"x64-linux","sha256":"\([0-9a-f]*\)".*/\1/p' "$repo/.neper/debug/build-manifest.json")
[ "$manifest_reused" = "$(sha256sum "$test_build/conformance-tools-build-again.out" | cut -c1-64)" ] || { printf '%s
' "the digest reused from the previous manifest is not the image's" >&2; exit 1; }
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
# `index-project --json` (D298, D544 leaves another target's variant out): every module under a project's src and lib, each
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
# Progress records (D454, D561, H18): every phase has a contiguous one-based sequence.
(cd "$test_build" && ./neper-self emit-executable ../../../../tests/conformance/tools/contract.e "$repo" x64 linux conformance-tools-progress.out --json --time > "conformance-tools-progress.jsonl")
grep -q '"record":"progress","phase":"lower and codegen"' "$test_build/conformance-tools-progress.jsonl"
python3 -c "import json,sys; rows=[json.loads(x) for x in open(sys.argv[1])]; progress=[r for r in rows if r.get('record')=='progress']; assert len(progress)>1 and [r['sequence'] for r in progress]==list(range(1,len(progress)+1)) and rows[-1].get('record')=='result'" "$test_build/conformance-tools-progress.jsonl"
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
# A resource closer is a semantic reference (D560, H17), though its contextual
# `resource(close)` spelling is neither an expression nor an ordinary type use.
$test_build/neper-self index-file "$conformance_root/tools/index_resource.e" "$repo" x64 linux --json | python3 -c "import json,sys; refs=[r for r in map(json.loads,sys.stdin) if r.get('record')=='reference' and r.get('role')=='protocol' and r.get('target_qualified_name')=='index_resource.close']; assert len(refs)==1 and refs[0]['spelling']=='close'"
# `dis --json` (D233): one record of hex bytes per emitted function, byte for byte per host.
dis_actual="$test_build/conformance-tools-dis.jsonl"
$test_build/neper-self dis-file "$conformance_root/tools/dis.e" "$repo" x64 linux --json > "$dis_actual"
# `dis-file --json --release` (D542, D565, H19): inlined runs retain a nested copy's chain.
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
# A record naming no declaration keeps naming none after an instance is made
# (D821): the thread start's call fact and the threads fact stand although
# `helper.fill[u8]` landed at the index the function count had.
nested_actual="$test_build/conformance-tools-nested-instance.jsonl"
(cd "$conformance_root/tools/nested_instance" && $test_build/neper-self context-file src/main.e "$repo" x64 linux --json --symbol main.main --budget 16 > "$nested_actual")
cmp -s "$nested_actual" "$conformance_root/tools/nested_instance.x64-linux.expected.jsonl" || { printf '%s\n' "context-file --json over a call before the first instance differs from the conformance corpus" >&2; exit 1; }
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
# A batch retains nothing between lines (D410, D558, H16): `memory` separates
# the checked snapshot, the session baseline and the largest temporary request.
batch_memory=$($test_build/neper-self query-batch "$conformance_root/tools/contract.e" "$repo" x64 linux --json --batch "$conformance_root/tools/batch_memory.txt")
printf '%s\n' "$batch_memory" | python3 -c "import json,sys; rows=[json.loads(line)['data'] for line in sys.stdin if '\"arena_used\"' in line]; assert len(rows)==2; assert rows[0]['request_peak']==0 and rows[1]['request_peak']>0; assert rows[0]['session_used']==rows[1]['session_used']==rows[1]['arena_used']; assert rows[1]['snapshot_used']<rows[1]['session_used']; assert rows[1]['arena_capacity']>=rows[1]['arena_used']"
# Ten thousand queries under one fixed snapshot (D559, H16): all complete and
# live allocation returns to the session baseline after a nonzero request peak.
batch_soak_input="$test_build/batch-soak.txt"
batch_soak_output="$test_build/batch-soak.jsonl"
{
    printf 'memory\n'
    batch_soak_at=0
    while [ "$batch_soak_at" -lt 10000 ]; do
        printf 'context contract.main 8\n'
        batch_soak_at=$((batch_soak_at + 1))
    done
    printf 'memory\n'
} > "$batch_soak_input"
"$test_build/neper-self" query-batch "$conformance_root/tools/contract.e" "$repo" x64 linux --json --batch "$batch_soak_input" > "$batch_soak_output"
python3 -c "import json,sys; rows=[json.loads(line)['data'] for line in open(sys.argv[1]) if '\"arena_used\"' in line]; assert len(rows)==2; assert rows[0]['queries_completed']==0 and rows[1]['queries_completed']==10000; assert rows[1]['request_peak']>0; assert rows[0]['session_used']==rows[1]['session_used']==rows[1]['arena_used']" "$batch_soak_output"
# The catalogue (D397, H11): every function of the module, subjects and facts under one
# budget; the byte budget (D400, H08) ends the page at the record that crosses it.
catalog_actual="$test_build/conformance-tools-catalog.jsonl"
(cd "$conformance_root/tools" && $test_build/neper-self context-file contract.e "$repo" x64 linux --json --module contract --budget 64 --bytes 3000 > "$catalog_actual")
cmp -s "$catalog_actual" "$conformance_root/tools/catalog.x64-linux.expected.jsonl" || { printf '%s
' "context-file --module differs from the conformance corpus" >&2; exit 1; }
# A planned-only module (D571, H11/SL11) is named and unavailable, never callable.
unavailable_catalog_actual="$test_build/conformance-tools-catalog-unavailable.jsonl"
unavailable_catalog_status=0
(cd "$conformance_root/tools" && $test_build/neper-self context-file contract.e "$repo" x64 linux --json --module e.gpu --budget 64 > "$unavailable_catalog_actual") || unavailable_catalog_status=$?
[ "$unavailable_catalog_status" -eq 2 ]
cmp -s "$unavailable_catalog_actual" "$conformance_root/tools/catalog_unavailable.expected.jsonl" || { echo "the unavailable module catalogue differs from the conformance corpus" >&2; exit 1; }
# API verification (D570, D574, H11): a non-test function reached by an executable
# @test is verified and names one witness; an unused generic template stays present.
verified_catalog_actual="$test_build/conformance-tools-catalog-verified.jsonl"
(cd "$conformance_root/tools" && $test_build/neper-self context-file test_project/src/nested/deep.e "$repo" x64 linux --json --module helper --budget 64 > "$verified_catalog_actual")
cmp -s "$verified_catalog_actual" "$conformance_root/tools/catalog_verified.x64-linux.expected.jsonl" || { printf '%s
' "the verified API catalogue differs from the conformance corpus" >&2; exit 1; }
# `--unchecked` as context (D555, H27): every subject kind says the image's checks
# are off and carries exactly one whole-image boundary. The standalone flag works
# on either side of a paging pair; the catalogue repeats the boundary per subject.
for unchecked_case in "contract.e contract.main before" "contract.e contract.Counter after" "subjects.e subjects.LIMIT before" "subjects.e subjects.counter after"; do
    set -- $unchecked_case
    if [ "$3" = before ]; then
        unchecked_context=$("$test_build/neper-self" context-file "$conformance_root/tools/$1" "$repo" x64 linux --json --symbol "$2" --unchecked --budget 64)
    else
        unchecked_context=$("$test_build/neper-self" context-file "$conformance_root/tools/$1" "$repo" x64 linux --json --symbol "$2" --budget 64 --unchecked)
    fi
    [ "$(printf '%s\n' "$unchecked_context" | grep -c '"checks":"off"')" -eq 1 ] || { echo "context-file --unchecked did not mark $2 checks off" >&2; exit 1; }
    [ "$(printf '%s\n' "$unchecked_context" | grep -c '"value":"--unchecked: runtime safety checks are omitted from the whole image; values produced by it cross a trusted boundary"')" -eq 1 ] || { echo "context-file --unchecked did not emit exactly one whole-image boundary for $2" >&2; exit 1; }
done
unchecked_catalog=$("$test_build/neper-self" context-file "$conformance_root/tools/contract.e" "$repo" x64 linux --json --module contract --unchecked --budget 64)
unchecked_catalog_subjects=$(printf '%s\n' "$unchecked_catalog" | grep -c '"record":"subject"')
[ "$unchecked_catalog_subjects" -eq 4 ] || { echo "context-file --module --unchecked returned $unchecked_catalog_subjects subjects, not 4" >&2; exit 1; }
[ "$(printf '%s\n' "$unchecked_catalog" | grep -c '"checks":"off"')" -eq "$unchecked_catalog_subjects" ] || { echo "context-file --module --unchecked did not mark every subject checks off" >&2; exit 1; }
[ "$(printf '%s\n' "$unchecked_catalog" | grep -c '"value":"--unchecked: runtime safety checks are omitted from the whole image; values produced by it cross a trusted boundary"')" -eq "$unchecked_catalog_subjects" ] || { echo "context-file --module --unchecked did not emit one whole-image boundary per subject" >&2; exit 1; }
# The batch path carries one intended image policy across every context/catalog
# line without giving up its one load and check (D556, H27).
unchecked_batch=$("$test_build/neper-self" query-batch "$conformance_root/tools/contract.e" "$repo" x64 linux --json --batch "$conformance_root/tools/batch_unchecked.txt" --unchecked)
unchecked_batch_subjects=$(printf '%s\n' "$unchecked_batch" | grep -c '"record":"subject"')
[ "$unchecked_batch_subjects" -eq 6 ] || { echo "query-batch --unchecked returned $unchecked_batch_subjects subjects, not 6" >&2; exit 1; }
[ "$(printf '%s\n' "$unchecked_batch" | grep -c '"checks":"off"')" -eq "$unchecked_batch_subjects" ] || { echo "query-batch --unchecked did not mark every subject checks off" >&2; exit 1; }
[ "$(printf '%s\n' "$unchecked_batch" | grep -c '"value":"--unchecked: runtime safety checks are omitted from the whole image; values produced by it cross a trusted boundary"')" -eq "$unchecked_batch_subjects" ] || { echo "query-batch --unchecked did not emit one whole-image boundary per subject" >&2; exit 1; }
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
# The deadline has to outlast load and parse -- `e.os` on Linux is read from a
# mounted drive under WSL, and its window backend (D803) put that past 50 ms -- and
# fall well inside the six seconds the evaluation takes: 250 ms does both.
long_started=$(date +%s%N)
long_status=0
(cd "$conformance_root/tools" && $test_build/neper-self emit-executable comptime_long.e "$repo" x64 linux "$test_build/comptime-long" --json --deadline 250 > "$test_build/conformance-tools-comptime-long.jsonl") || long_status=$?
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
(cd "$conformance_root/tools" && $test_build/neper-self explain-file explain_when.e "$repo" x64 linux --json > "$test_build/conformance-tools-explain-when.jsonl")
cmp -s "$test_build/conformance-tools-explain-when.jsonl" "$conformance_root/tools/explain_when.expected.jsonl" || { printf '%s\n' "the when phase record differs from the conformance corpus" >&2; exit 1; }
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
"$test_build/neper-self" apply-plan "$test_build/conformance-tools-plan-rename.jsonl" --root "$plan_scratch/src" --json > "$test_build/plan-stale.jsonl" 2>/dev/null || plan_again=$?
# The file named (D547, H29).
grep -q '"code":"E-TOOL-0003","message":"`explain.e` changed since the plan was made; nothing applied","symbol":"explain.e"' "$test_build/plan-stale.jsonl"
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
# A plan into generated text (D512, D563, H17/H19): owned edits in the operand
# and a dependency are named, and apply-plan refuses the whole plan.
generated_fixture="$conformance_root/tools/plan_generated"
(cd "$generated_fixture" && "$test_build/neper-self" plan-rename-file src/main.e "$repo" x64 linux --json --symbol deep.pick --to choose > "$test_build/conformance-tools-plan-generated.jsonl")
cmp -s "$test_build/conformance-tools-plan-generated.jsonl" "$conformance_root/tools/plan_generated.x64-linux.expected.jsonl" || { echo "plan-rename-file --json over generated modules differs from the conformance corpus" >&2; exit 1; }
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
# Combined inputs (D464, H19), and a four-level nested chain (D564).
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
# Section 4's register-only rule: a `Mask[T, N]` has no storage form, so every position
# that would store one is refused while checking, each naming the position it is.
check_protocol_diagnostic mask_field 'main.e:4:23: error[E-TYPE-9999]: `Mask[T, N]` is register-only (section 4): a field may not hold one'
check_protocol_diagnostic mask_array 'main.e:5:18: error[E-TYPE-9999]: `Mask[T, N]` is register-only (section 4): an array element may not hold one'
check_protocol_diagnostic mask_pointer 'main.e:4:14: error[E-TYPE-9999]: `Mask[T, N]` is register-only (section 4): a pointer may not point at one'
check_protocol_diagnostic mask_address 'main.e:6:13: error[E-TYPE-9999]: `Mask[T, N]` is register-only (section 4): a pointer may not point at one'
check_protocol_diagnostic mask_size_of 'main.e:6:29: error[E-TYPE-9999]: `Mask[T, N]` is register-only (section 4): `mem.size_of` and `mem.align_of` have no answer for one'
check_protocol_diagnostic mask_alloc 'main.e:6:31: error[E-TYPE-9999]: `Mask[T, N]` is register-only (section 4): a slice element may not hold one'
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
# A module's code records, less the trap data and stub functions (D927), `trap.N`,
# which every module with a check carries beside its own functions.
em_code_count() {
    python3 -c 'import struct, sys
b = open(sys.argv[1], "rb").read()
strings = struct.unpack_from("<Q", b, 40)[0]
code = struct.unpack_from("<Q", b, 112)[0]
count = struct.unpack_from("<I", b, code)[0]
cursor = code + 4
own = 0
for _ in range(count):
    name_index = struct.unpack_from("<I", b, cursor)[0]
    length, relocations = struct.unpack_from("<II", b, cursor + 16)
    name_at = strings + struct.unpack_from("<I", b, strings + 4 + name_index * 4)[0]
    name_length = struct.unpack_from("<I", b, name_at)[0]
    if not b[name_at + 4:name_at + 4 + name_length].startswith(b"trap."):
        own += 1
    cursor += 24 + length + relocations * 28
print(own)' "$1"
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
# `@reorder` (D239): the opt-in alignment sort. The reordered struct is 16 bytes where
# declaration order pads the same three fields to 24, and every field still reads and
# writes through its own offset; a value of one crossing an FFI boundary is refused.
reorder_executable_path="$test_build/reorder-selfhost"
reorder_executable_written=$($test_build/neper-self emit-executable "$repo/tests/selfhost/fixtures/link/reorder/src/main.e" "$repo" x64 linux "$reorder_executable_path")
[ "$reorder_executable_written" = 'executable written' ]
chmod +x "$reorder_executable_path"
"$reorder_executable_path"
check_protocol_diagnostic reorder_extern 'main.e:11:1: error[E-TYPE-9999]: @reorder is legal on a struct or a union that crosses no FFI boundary'
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
adler32
fletcher16
fletcher32
fletcher64
lrc
murmur3_32
murmur3_load64
murmur3_fmix64
murmur3_x64_128
zobrist
zobrist_hash
zobrist_toggle
fletcher
murmur3'
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
eq
intersect
union_into
difference'
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
expected_sort_surface='TooSmall
Invalid
in_place
in_place_by
stable_in_place
stable_in_place_by
radix_u32_in_place
radix_u64_in_place
is_sorted
insertion
shell
heap
merge
quick
cycle
patience
counting
bucket
radix_bytes
external_merge
strings
strings_from'
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
iter_next
TooSmall
MinMax
Pool
heapify
heapify_by
min_max
min_max_level
min_max_down
min_max_push
peek_min
peek_max
pop_min
pop_max
pool
pool_node
leftist_merge
leftist_insert
leftist_pop
skew_merge
skew_insert
skew_pop
meldable
meldable_merge
meldable_insert
meldable_pop
pairing_merge
pairing_insert
pairing_pop
pairing_decrease_key
binomial_link
binomial_merge
binomial_insert
binomial_peek
binomial_pop'
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
# The arena dry (D546, H07): a compiler with a 96 MB arena names the limit under the header, exit 1.
[ "$($test_build/neper-self emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-small" --arena 96m)" = 'executable written' ]
chmod +x "$test_build/neper-small"
small_status=0
"$test_build/neper-small" check-file "$repo/src/main.e" "$repo" x64 linux --json > "$test_build/neper-small.jsonl" 2>/dev/null || small_status=$?
[ "$small_status" -eq 1 ]
[ "$(wc -l < "$test_build/neper-small.jsonl")" -eq 3 ]
grep -q '"record":"header","command":"check"' "$test_build/neper-small.jsonl"
grep -q '"code":"E-TYPE-9999","message":"resource limit: the compiler'"'"'s arena is exhausted' "$test_build/neper-small.jsonl"
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
# The compiler with its functions and types renamed (D529, D560, H10, H17): built
# from `src/` and `lib/` renamed through one cross-root index, it builds the stable stage.
python3 "$repo/benchmarks/metamorphic/rename_symbols.py" "$test_build/neper-self" "$repo" "$repo/src" "$test_build/resymbolled-src/src" linux "$repo/lib" "$test_build/resymbolled-src/lib"
resymbolled_written=$("$own_compiler_path" emit-executable "$test_build/resymbolled-src/src/main.e" "$test_build/resymbolled-src" x64 linux "$test_build/neper-resymbolled")
[ "$resymbolled_written" = 'executable written' ]
chmod +x "$test_build/neper-resymbolled"
by_resymbolled_written=$("$test_build/neper-resymbolled" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-by-resymbolled")
[ "$by_resymbolled_written" = 'executable written' ]
cmp "$test_build/neper-by-resymbolled" "$stable_compiler_path"
# The compiler with a conflict-free set of parameter lists reversed (D562, H10,
# H17): one checked query batch supplies the structured plans, apply-plan commits
# their edits together, and the result builds the stable stage.
python3 "$repo/benchmarks/metamorphic/reorder_parameters.py" "$test_build/neper-self" "$repo" "$repo/src" "$test_build/parameter-src/src" linux
parameter_written=$("$own_compiler_path" emit-executable "$test_build/parameter-src/src/main.e" "$repo" x64 linux "$test_build/neper-parameters")
[ "$parameter_written" = 'executable written' ]
chmod +x "$test_build/neper-parameters"
by_parameters_written=$("$test_build/neper-parameters" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-by-parameters")
[ "$by_parameters_written" = 'executable written' ]
cmp "$test_build/neper-by-parameters" "$stable_compiler_path"
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
# The standard library turned too (D532, H10): the compiler built against `lib/` blanked, then hoisted, then its locals renamed (D550), is the stable stage.
for lib_turn in "strip_comments.py lib-blanked" "hoist_constants.py lib-hoisted" "rename_locals.py lib-renamed $repo"; do
    set -- $lib_turn
    lib_project="$test_build/$2"
    rm -rf "$lib_project"
    mkdir -p "$lib_project"
    cp -r "$repo/src" "$lib_project/src"
    if [ "$1" = rename_locals.py ]; then
        python3 "$repo/benchmarks/metamorphic/$1" "$test_build/neper-self" "$repo" "$repo/lib" "$lib_project/lib" linux > /dev/null
    else
        python3 "$repo/benchmarks/metamorphic/$1" "$test_build/neper-self" "$repo/lib" "$lib_project/lib"
    fi
    lib_written=$("$own_compiler_path" emit-executable "$lib_project/src/main.e" "$lib_project" x64 linux "$test_build/neper-$2")
    [ "$lib_written" = 'executable written' ]
    cmp "$test_build/neper-$2" "$stable_compiler_path"
done
# The formatted library (D549, H10): the compiler built against `lib/` formatted builds the stable stage from the original tree.
rm -rf "$test_build/lib-formatted"
mkdir -p "$test_build/lib-formatted"
cp -r "$repo/src" "$test_build/lib-formatted/src"
python3 "$repo/benchmarks/metamorphic/format_tree.py" "$test_build/neper-self" "$repo/lib" "$test_build/lib-formatted/lib" > /dev/null
[ "$("$own_compiler_path" emit-executable "$test_build/lib-formatted/src/main.e" "$test_build/lib-formatted" x64 linux "$test_build/neper-lib-formatted")" = 'executable written' ]
chmod +x "$test_build/neper-lib-formatted"
[ "$("$test_build/neper-lib-formatted" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-by-lib-formatted")" = 'executable written' ]
cmp "$test_build/neper-by-lib-formatted" "$stable_compiler_path"
# The library's fields reversed and its declarations reordered (D551, H10): the compiler built against each builds the stable stage.
for lib_on_turn in "reverse_fields.py lib-fields" "reorder_declarations.py lib-order"; do
    set -- $lib_on_turn
    rm -rf "$test_build/$2"
    mkdir -p "$test_build/$2"
    cp -r "$repo/src" "$test_build/$2/src"
    if [ "$1" = reverse_fields.py ]; then
        python3 "$repo/benchmarks/metamorphic/$1" "$test_build/neper-self" "$repo/lib" "$test_build/$2/lib" > /dev/null
    else
        python3 "$repo/benchmarks/metamorphic/$1" "$repo/lib" "$test_build/$2/lib" > /dev/null
    fi
    [ "$("$own_compiler_path" emit-executable "$test_build/$2/src/main.e" "$test_build/$2" x64 linux "$test_build/neper-$2")" = 'executable written' ]
    chmod +x "$test_build/neper-$2"
    [ "$("$test_build/neper-$2" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-by-$2")" = 'executable written' ]
    cmp "$test_build/neper-by-$2" "$stable_compiler_path"
done
# The turns in release (D533, H10): the release self-build twice, the image-holding trees, the turn compilers, the library.
[ "$("$own_compiler_path" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-own-release" --release)" = 'executable written' ]
[ "$("$own_compiler_path" emit-executable "$repo/src/main.e" "$repo" x64 linux "$test_build/neper-own-release-again" --release)" = 'executable written' ]
cmp "$test_build/neper-own-release-again" "$test_build/neper-own-release"
for release_tree in blanked-src hoisted-src renamed-src; do
    [ "$("$own_compiler_path" emit-executable "$test_build/$release_tree/src/main.e" "$repo" x64 linux "$test_build/neper-release-$release_tree" --release)" = 'executable written' ]
    cmp "$test_build/neper-release-$release_tree" "$test_build/neper-own-release"
done
for turn_compiler in neper-formatted neper-resymbolled neper-parameters neper-reversed neper-reordered; do
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
[ "$(od -An -tu2 -j4 -N2 "$module_artifact_path" | tr -d ' ')" = '14' ]
[ "$(od -An -tu2 -j6 -N2 "$module_artifact_path" | tr -d ' ')" = '32' ]
[ "$(od -An -tu4 -j20 -N4 "$module_artifact_path" | tr -d ' ')" = '9' ]
[ "$(od -An -tu8 -j96 -N8 "$module_artifact_path" | tr -d ' ')" -gt 4 ]
interface_artifact_path="$test_build/interface.x64-linux.em"
interface_artifact_written=$($test_build/neper-self emit-em "$repo/tests/selfhost/fixtures/em/interface/src/main.e" "$repo" x64 linux "$interface_artifact_path")
[ "$interface_artifact_written" = 'compiled module written' ]
interface_offset=$(od -An -tu8 -j64 -N8 "$interface_artifact_path" | tr -d ' ')
[ "$(od -An -tu4 -j$((interface_offset + 8)) -N4 "$interface_artifact_path" | tr -d ' ')" = '6' ]
[ "$(od -An -tu8 -j$((interface_offset + 28)) -N8 "$interface_artifact_path" | tr -d ' ')" != '0' ]
hash_module_artifacts="$test_build/hash-module"
mkdir -p "$hash_module_artifacts"
hash_module_artifacts_written=$($test_build/neper-self emit-em-all "$repo/tests/selfhost/fixtures/em/hash_module/src/main.e" "$repo" x64 linux "$hash_module_artifacts")
[ "$hash_module_artifacts_written" = 'compiled modules written' ]
[ -f "$hash_module_artifacts/main.x64-linux.em" ]
[ -f "$hash_module_artifacts/e.algo.hash.x64-linux.em" ]
hash_module_validation=$($test_build/neper-self validate-em "$hash_module_artifacts/main.x64-linux.em")
[ "$hash_module_validation" = 'compiled module valid' ]
hash_module_interface_offset=$(od -An -tu8 -j64 -N8 "$hash_module_artifacts/e.algo.hash.x64-linux.em" | tr -d ' ')
[ "$(od -An -tu4 -j$((hash_module_interface_offset + 8)) -N4 "$hash_module_artifacts/e.algo.hash.x64-linux.em" | tr -d ' ')" = '26' ]
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
legacy_value_abi_artifact="$test_build/main.value-abi-v0.x64-linux.em"
cp "$test_build/main.x64-linux.em" "$legacy_value_abi_artifact"
printf '\012\000' | dd of="$legacy_value_abi_artifact" bs=1 seek=4 conv=notrunc status=none
if legacy_value_abi_output=$($test_build/neper-self validate-em "$legacy_value_abi_artifact" 2>&1); then
    printf '%s\n' 'pre-snapshot value ABI artifact unexpectedly validated' >&2
    exit 1
fi
case "$legacy_value_abi_output" in *'UnsupportedVersion'*) ;; *) printf '%s\n' 'pre-snapshot value ABI artifact returned the wrong error' >&2; exit 1 ;; esac
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
# A toolchain module the project replaced (D821): the missing member's diagnostic
# names the project's file, since every module is resolved against it.
replaced_checked=$($test_build/neper-self check-file "$check_root/replaced_module/src/main.e" "$repo" x64 linux 2>&1 || true)
case "$replaced_checked" in
    *'`mem` has no member `arena_from`; `e.mem` is `'*replaced_module/src/e/mem.e*"the project's replacement of the toolchain's"*) ;;
    *) printf '%s\n' "the replaced-module diagnostic did not name the project's file: $replaced_checked" >&2; exit 1 ;;
esac
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
