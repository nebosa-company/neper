#!/usr/bin/env bash
# The SQL Server that x.microsoft.tds's Linux fixture talks to (D1643): the mssql-server package
# in WSL (Microsoft's apt repository, Developer edition), on 127.0.0.1:14331 so it cannot be
# mistaken for a Windows instance, with a TLS certificate so it accepts TDS 8.0 strict
# connections, a `neper` login and a `neper` database.
#
#   bash tests/selfhost/sqlserver.sh setup      once, with sudo: configure, certify, create login
#   bash tests/selfhost/sqlserver.sh start DIR  start it; append tds_* lines to DIR/ports
#   bash tests/selfhost/sqlserver.sh stop DIR   stop it again if `start` started it
#
# Every credential here is a test value for a loopback-only throwaway server.
set -eu
PORT=14331
SA_PASSWORD='Neper-sa-test-1!'
NEPER_PASSWORD='Neper-test-only-1!'
CERT_DIR=/etc/neper-sqlserver
# Strict encryption validates the certificate whatever TrustServerCertificate says; pin ours.
ODBC='Driver={ODBC Driver 18 for SQL Server};Server=tcp:127.0.0.1,'"$PORT"';Encrypt=Strict;ServerCertificate='"$CERT_DIR"'/tls.pem'

sql() {  # one batch as sa through unixODBC's isql and ODBC Driver 18
    printf '%s\n' "$1" | isql -b -k "$ODBC;UID=sa;PWD=$SA_PASSWORD" > /dev/null
}

wait_ready() {  # [login] -- as sa by default; `start` waits until neper's own database opens
    login=${1:-"UID=sa;PWD=$SA_PASSWORD"}
    for _ in $(seq 1 90); do
        if printf 'SELECT 1\n' | timeout 10 isql -b -k "$ODBC;$login" > /dev/null 2>&1; then return 0; fi
        sleep 1
    done
    echo "sqlserver.sh: SQL Server did not answer on $PORT" >&2
    return 1
}

# systemd's stop waits up to 30 minutes in WSL: SIGTERM reaches only the watchdog process, so
# the server itself is signalled too, and asked to shut down as it would on any SIGTERM.
running() { pgrep -x sqlservr > /dev/null; }

stop_server() {
    sudo -n systemctl stop --no-block mssql-server
    sudo -n pkill -TERM -x sqlservr || true
    for _ in $(seq 1 90); do
        running || return 0
        sleep 1
    done
    echo "sqlserver.sh: SQL Server did not stop" >&2
    return 1
}

case "${1:-}" in
setup)
    if running; then stop_server; fi
    sudo -n env ACCEPT_EULA=Y MSSQL_PID=Developer MSSQL_SA_PASSWORD="$SA_PASSWORD" /opt/mssql/bin/mssql-conf -n setup > /dev/null
    if running; then stop_server; fi
    sudo -n /opt/mssql/bin/mssql-conf set network.tcpport "$PORT" > /dev/null
    sudo -n /opt/mssql/bin/mssql-conf set network.ipaddress 127.0.0.1 > /dev/null
    sudo -n /opt/mssql/bin/mssql-conf set memory.memorylimitmb 2048 > /dev/null
    sudo -n mkdir -p "$CERT_DIR"
    # An end-entity certificate (CA:FALSE): rustls, for one, refuses a CA certificate as the
    # server's own, while every client here pins this one as its root.
    sudo -n openssl req -x509 -newkey rsa:2048 -sha256 -days 1825 -nodes -subj /CN=localhost \
        -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' -addext 'extendedKeyUsage=serverAuth' \
        -addext 'basicConstraints=critical,CA:FALSE' -addext 'keyUsage=critical,digitalSignature,keyEncipherment' \
        -keyout "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.pem" 2> /dev/null
    sudo -n openssl x509 -in "$CERT_DIR/tls.pem" -outform der -out "$CERT_DIR/tls.cer"
    sudo -n chmod 755 "$CERT_DIR"
    sudo -n chmod 644 "$CERT_DIR/tls.pem" "$CERT_DIR/tls.cer"
    sudo -n chown mssql:mssql "$CERT_DIR/tls.key"
    sudo -n chmod 600 "$CERT_DIR/tls.key"
    sudo -n /opt/mssql/bin/mssql-conf set network.tlscert "$CERT_DIR/tls.pem" > /dev/null
    sudo -n /opt/mssql/bin/mssql-conf set network.tlskey "$CERT_DIR/tls.key" > /dev/null
    sudo -n /opt/mssql/bin/mssql-conf set network.tlsprotocols 1.2,1.3 > /dev/null
    sudo -n /opt/mssql/bin/mssql-conf set network.forceencryption 0 > /dev/null
    sudo -n systemctl start mssql-server
    wait_ready
    sql "IF SUSER_ID('neper') IS NULL CREATE LOGIN neper WITH PASSWORD = '$NEPER_PASSWORD', CHECK_POLICY = OFF;
IF DB_ID('neper') IS NULL CREATE DATABASE neper;"
    # An existing database may still be recovering after the restart.
    wait_ready "UID=sa;PWD=$SA_PASSWORD;Database=neper"
    sql "USE neper; IF USER_ID('neper') IS NULL CREATE USER neper FOR LOGIN neper; ALTER ROLE db_owner ADD MEMBER neper;"
    stop_server
    sudo -n systemctl disable mssql-server > /dev/null 2>&1 || true
    echo "sqlserver.sh: set up on 127.0.0.1:$PORT, certificate $CERT_DIR/tls.cer"
    ;;
start)
    dir=${2:?usage: sqlserver.sh start DIR}
    mkdir -p "$dir"
    started=0
    if ! running; then sudo -n systemctl start mssql-server; started=1; fi
    wait_ready "UID=neper;PWD=$NEPER_PASSWORD;Database=neper"
    echo "$started" > "$dir/sqlserver-started"
    { echo "tds_port=$PORT"; echo "tds_root=$CERT_DIR/tls.cer"; echo "tds_user=neper"; echo "tds_password=$NEPER_PASSWORD"; } >> "$dir/ports"
    ;;
stop)
    dir=${2:?usage: sqlserver.sh stop DIR}
    if [ "$(cat "$dir/sqlserver-started" 2>/dev/null)" = 1 ]; then stop_server; fi
    rm -f "$dir/sqlserver-started"
    ;;
*)
    echo "usage: sqlserver.sh setup | start DIR | stop DIR" >&2
    exit 2
    ;;
esac
