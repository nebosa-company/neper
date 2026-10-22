# Sourced by run.sh. With NEPER_REFRESH_GOLDENS=1, an x64 tool golden that differs from the actual output only in
# its "snapshot" hashes is overwritten instead of failing the comparison. Each hash folds the text of every module
# the subject reaches, so any library edit moves it; any other difference still fails.
cmp() {
    if [ "${NEPER_REFRESH_GOLDENS:-}" = 1 ] && [ "$#" -eq 3 ] && [ "$1" = -s ]; then
        golden_actual=$2 golden_path=$3
    elif [ "${NEPER_REFRESH_GOLDENS:-}" = 1 ] && [ "$#" -eq 2 ]; then
        golden_actual=$1 golden_path=$2
    else
        command cmp "$@"
        return
    fi
    command cmp -s "$golden_actual" "$golden_path" && return 0
    case $golden_path in
        */tests/conformance/tools/*.expected.jsonl) ;;
        *) command cmp "$@"; return ;;
    esac
    golden_masked=$(mktemp) && actual_masked=$(mktemp) || return 1
    sed 's/"snapshot":"[0-9a-f]*"/"snapshot":"-"/g' "$golden_path" > "$golden_masked"
    sed 's/"snapshot":"[0-9a-f]*"/"snapshot":"-"/g' "$golden_actual" > "$actual_masked"
    if command cmp -s "$golden_masked" "$actual_masked"; then
        cp "$golden_actual" "$golden_path"
        printf 'refreshed %s\n' "$golden_path"
        rm -f "$golden_masked" "$actual_masked"
        return 0
    fi
    rm -f "$golden_masked" "$actual_masked"
    command cmp "$@"
}
