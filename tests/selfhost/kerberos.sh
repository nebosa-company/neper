#!/bin/bash
# A throwaway MIT Kerberos KDC for e.net.auth's Linux fixture (net_auth): realm NEPER.TEST on
# 127.0.0.1:18888, run as the calling user with everything under /tmp/neper-krb5 -- the realm's
# database, its own krb5.conf and kdc.conf, a keytab for the service HTTP/localhost@NEPER.TEST
# and a credential cache for the user neper@NEPER.TEST. Nothing outside that directory is
# configured. Only installing the MIT packages (krb5-kdc, krb5-admin-server for kadmin.local,
# krb5-user for kinit) needs root; that is done with `sudo -n`, and when sudo would ask for a
# password the script stops and says so rather than asking.
#
#   kerberos.sh start          set the realm up and start the KDC; prints the environment
#   kerberos.sh stop           stop the KDC and remove /tmp/neper-krb5
#   kerberos.sh run CMD ARGS   start, run CMD with that environment, stop; exits with CMD's code
#
# The fixture reads NEPER_KRB5_SERVICE and NEPER_KRB5_USER; the MIT library reads the rest.
set -euo pipefail
dir=/tmp/neper-krb5
realm=NEPER.TEST
port=18888
service=HTTP/localhost
user=neper

environment() {
    echo "KRB5_CONFIG=$dir/krb5.conf"
    echo "KRB5_KDC_PROFILE=$dir/kdc.conf"
    echo "KRB5_KTNAME=FILE:$dir/service.keytab"
    echo "KRB5CCNAME=FILE:$dir/ccache"
    echo "NEPER_KRB5_SERVICE=$service@$realm"
    echo "NEPER_KRB5_USER=$user@$realm"
}

stop() {
    if [ -f "$dir/kdc.pid" ]; then kill "$(cat "$dir/kdc.pid")" 2>/dev/null || true; fi
    rm -rf "$dir"
}

start() {
    if ! command -v krb5kdc >/dev/null || ! command -v kadmin.local >/dev/null || ! command -v kinit >/dev/null; then
        if ! sudo -n true 2>/dev/null; then
            echo "kerberos.sh: the MIT KDC is not installed and sudo needs a password; run" >&2
            echo "  sudo apt-get install -y krb5-kdc krb5-admin-server krb5-user" >&2
            echo "yourself, then run this script again." >&2
            exit 3
        fi
        sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y -q krb5-kdc krb5-admin-server krb5-user >/dev/null
    fi
    stop
    mkdir -p "$dir"
    cat > "$dir/krb5.conf" <<EOF
[libdefaults]
    default_realm = $realm
    dns_lookup_realm = false
    dns_lookup_kdc = false
    dns_canonicalize_hostname = false
    rdns = false
[realms]
    $realm = {
        kdc = 127.0.0.1:$port
    }
[domain_realm]
    localhost = $realm
EOF
    cat > "$dir/kdc.conf" <<EOF
[kdcdefaults]
    kdc_ports = $port
    kdc_tcp_ports = $port
[realms]
    $realm = {
        database_name = $dir/principal
        key_stash_file = $dir/stash
        acl_file = $dir/kadm5.acl
        max_life = 1h
    }
[logging]
    kdc = FILE:$dir/kdc.log
EOF
    touch "$dir/kadm5.acl"
    set -a
    eval "$(environment)"
    set +a
    kdb5_util create -s -r "$realm" -P "$(head -c 18 /dev/urandom | base64)" >/dev/null
    kadmin.local -r "$realm" -q "addprinc -randkey -clearpolicy $service" >/dev/null
    kadmin.local -r "$realm" -q "addprinc -randkey -clearpolicy $user" >/dev/null
    kadmin.local -r "$realm" -q "ktadd -k $dir/service.keytab $service" >/dev/null
    kadmin.local -r "$realm" -q "ktadd -k $dir/user.keytab $user" >/dev/null
    krb5kdc -r "$realm" -P "$dir/kdc.pid"
    # The KDC forks; wait for it to answer before asking it for a ticket.
    for _ in $(seq 1 50); do
        if kinit -k -t "$dir/user.keytab" "$user@$realm" 2>/dev/null; then
            environment
            return 0
        fi
        sleep 0.2
    done
    echo "kerberos.sh: the KDC did not issue a ticket; see $dir/kdc.log" >&2
    exit 4
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    run)
        shift
        start >/dev/null
        trap stop EXIT
        set -a
        eval "$(environment)"
        set +a
        set +e
        "$@"
        code=$?
        exit $code
        ;;
    *) echo "usage: kerberos.sh start|stop|run CMD [ARGS]" >&2; exit 2 ;;
esac
