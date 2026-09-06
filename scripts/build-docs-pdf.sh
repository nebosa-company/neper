#!/bin/sh
# Build docs/neper.pdf from the neper documentation set.
#
#   scripts/build-docs-pdf.sh                 -> docs/neper.pdf
#   scripts/build-docs-pdf.sh --out other.pdf
#
# Creates .venv-docs-pdf/ at the repository root and installs the pinned
# dependencies in scripts/docs-pdf-requirements.txt. Reinstallation happens only
# when that file changes.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname -- "$script_dir")
venv="$root/.venv-docs-pdf"
requirements="$script_dir/docs-pdf-requirements.txt"
stamp="$venv/requirements.sha256"

# "Scripts" covers running this script from Git Bash / MSYS on Windows.
venv_python="$venv/bin/python"
[ -x "$venv_python" ] || venv_python="$venv/Scripts/python.exe"

if [ ! -x "$venv_python" ]; then
    echo "creating $venv"
    if command -v python3 >/dev/null 2>&1; then
        python3 -m venv "$venv"
    else
        python -m venv "$venv"
    fi
    venv_python="$venv/bin/python"
    [ -x "$venv_python" ] || venv_python="$venv/Scripts/python.exe"
fi

if command -v sha256sum >/dev/null 2>&1; then
    wanted=$(sha256sum "$requirements" | cut -d' ' -f1)
else
    wanted=$(shasum -a 256 "$requirements" | cut -d' ' -f1)
fi
have=""
[ -f "$stamp" ] && have=$(cat "$stamp")

if [ "$wanted" != "$have" ]; then
    echo "installing pinned dependencies"
    "$venv_python" -m pip install --disable-pip-version-check --quiet --upgrade pip
    "$venv_python" -m pip install --disable-pip-version-check --quiet -r "$requirements"
    printf '%s' "$wanted" > "$stamp"
fi

exec "$venv_python" "$script_dir/build-docs-pdf.py" "$@"
