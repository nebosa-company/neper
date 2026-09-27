#!/usr/bin/env bash
# The e.db driver benchmark on Linux: builds the C baseline, starts throwaway servers, runs
# run.py, stops the servers. The Neper benchmarks are built beforehand (cross-emitted or native)
# as <prefix>-sqlite, <prefix>-postgresql and <prefix>-mysql; the results JSON goes to $2.
#
#   bash benchmarks/db/run-linux.sh <prefix> <results.json> [runs]
#
# Needs: gcc, libsqlite3-dev, libpq-dev, libmysqlclient-dev, postgresql, mysql-server.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
work=/tmp/neper-db-bench
rm -rf "$work"
mkdir -p "$work"
for driver in sqlite postgresql mysql; do cp "$1-$driver" "$work/bench-$driver"; chmod +x "$work/bench-$driver"; done
gcc -O2 -o "$work/bench-c" "$here/c/bench.c" -I/usr/include/postgresql $(mysql_config --cflags) \
    -lsqlite3 -lpq $(mysql_config --libs)
bash "$repo/tests/selfhost/db_servers.sh" start "$work/servers"
# The ports the servers settled on (D1596): the defaults unless something else holds them.
. "$work/servers/ports"
status=0
python3 "$here/run.py" --neper "$work/bench" --c "$work/bench-c" --runs "${3:-9}" --scratch "$work" \
    --pg-port "$pg_port" --mysql-port "$mysql_port" --out "$2" || status=$?
bash "$repo/tests/selfhost/db_servers.sh" stop "$work/servers"
exit $status
