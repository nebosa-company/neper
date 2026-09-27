#!/usr/bin/env bash
# Throwaway PostgreSQL and MySQL servers for the x.postgresql.libpq and x.oracle.mysql fixtures.
#
#   db_servers.sh start <dir>   initialise fresh data directories under <dir> and start both
#   db_servers.sh stop <dir>    stop both (safe to run when they are not running)
#
# Both listen on 127.0.0.1 only: PostgreSQL on 55432 (user `neper`, trust auth, database
# `postgres`), MySQL on 53306 (user `root`, no password, database `neper`). <dir> must be on a
# native Linux file system (PostgreSQL refuses a data directory whose permissions 9p cannot
# keep), so the suite passes one under /tmp. The binaries are the distribution's
# (`postgresql` and `mysql-server`): the newest /usr/lib/postgresql/*/bin, and /usr/sbin/mysqld.
set -eu
action=$1
dir=$2
pg_bin=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -n 1)
pg_port=55432
my_port=53306

stop_servers() {
    if [ -n "$pg_bin" ] && [ -f "$dir/pg/postmaster.pid" ]; then
        "$pg_bin/pg_ctl" -D "$dir/pg" -m fast -w stop >/dev/null 2>&1 || true
    fi
    mysqladmin --user=root --host=127.0.0.1 --port=$my_port --connect-timeout=2 shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 50); do
        [ -f "$dir/my.pid" ] && kill -0 "$(cat "$dir/my.pid")" 2>/dev/null || break
        sleep 0.2
    done
}

if [ "$action" = stop ]; then stop_servers; exit 0; fi

if [ -z "$pg_bin" ] || [ ! -x /usr/sbin/mysqld ]; then
    echo "db_servers: install the postgresql and mysql-server packages" >&2
    exit 1
fi
stop_servers
rm -rf "$dir"
mkdir -p "$dir"

"$pg_bin/initdb" -D "$dir/pg" -U neper -A trust -E UTF8 --no-locale -N > "$dir/pg-init.log" 2>&1
"$pg_bin/pg_ctl" -D "$dir/pg" -l "$dir/pg.log" -o "-p $pg_port -c listen_addresses=127.0.0.1 -k $dir -c fsync=off" -w start > "$dir/pg-start.log" 2>&1

/usr/sbin/mysqld --no-defaults --initialize-insecure --datadir="$dir/my" --log-error="$dir/my-init.log"
/usr/sbin/mysqld --no-defaults --datadir="$dir/my" --port=$my_port --bind-address=127.0.0.1 \
    --socket="$dir/my.sock" --pid-file="$dir/my.pid" --mysqlx=OFF --skip-log-bin \
    --log-error="$dir/my.log" --daemonize > "$dir/my-start.log" 2>&1
for _ in $(seq 1 150); do
    if mysqladmin --user=root --host=127.0.0.1 --port=$my_port --connect-timeout=2 ping >/dev/null 2>&1; then break; fi
    sleep 0.2
done
mysql --user=root --host=127.0.0.1 --port=$my_port -e 'CREATE DATABASE neper'
