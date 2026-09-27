#!/usr/bin/env bash
# The e.db benchmark on Linux against C, Go and Rust: builds the C, Go and Rust programs, starts
# throwaway servers on free ports, runs run.py over all four, stops the servers.
#
#   bash benchmarks/db/run-linux-all.sh <neper-prefix> <results.json> [runs]
#
# <neper-prefix>-{sqlite,postgresql,mysql} are the Neper benchmarks, built beforehand (native or
# cross-emitted). Go and Rust build with benchmarks/db/tools-env.sh, which keeps their toolchains
# and caches under $NEPER_DB_TOOLS. Go uses cgo with the `libsqlite3` tag, so every language here
# binds the system libsqlite3.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
. "$here/tools-env.sh"
work=/tmp/neper-db-bench-all
rm -rf "$work"
mkdir -p "$work"
for driver in sqlite postgresql mysql; do cp "$1-$driver" "$work/bench-$driver"; chmod +x "$work/bench-$driver"; done
gcc -O2 -o "$work/bench-c" "$here/c/bench.c" -I/usr/include/postgresql $(mysql_config --cflags) \
    -lsqlite3 -lpq $(mysql_config --libs)
(cd "$here/go" && CGO_ENABLED=1 go build -tags libsqlite3 -o "$work/bench-go" .)
(cd "$here/rust" && cargo build --release --quiet)
cp "$CARGO_TARGET_DIR/release/bench-rust" "$work/bench-rust"
bash "$repo/tests/selfhost/db_servers.sh" start "$work/servers"
. "$work/servers/ports"
status=0
python3 "$here/run.py" --neper "$work/bench" --c "$work/bench-c" --go "$work/bench-go" --rust "$work/bench-rust" \
    --runs "${3:-9}" --scratch "$work" --pg-port "$pg_port" --mysql-port "$mysql_port" --out "$2" || status=$?
bash "$repo/tests/selfhost/db_servers.sh" stop "$work/servers"
exit $status
