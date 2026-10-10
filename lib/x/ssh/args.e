// The OpenSSH command line a host's variables describe (L048), after Petcow's `transport/ssh.rs`: key-based, never
// prompting (`BatchMode=yes`), a 15-second connect timeout, host-key checking on unless the host says otherwise, an
// optional pinned known-hosts file, an optional identity file (with `IdentitiesOnly=yes`), an optional port, `user@address`
// when a user is set, and the remote command (wrapped for PowerShell on a Windows target). Host variables answer to both
// PetCow's and Ansible's names. The process spawn itself is host code over `e.proc`.
//
// Memory: the arena is retained.

use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.json as json
use e.mem
use e.str

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn trimmed_empty(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if !(c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 || c == 11u8 || c == 12u8) { ret false }
        i += 1usize
    }
    ret true
}

// The first of `keys` that holds a non-blank string or a number, as text.
fn host_str(vars: json.Value, keys: []const str) -> (str, bool) {
    var i = 0usize
    while i < keys.len {
        let (v, found) = ir.get(vars, keys[i])
        if found {
            switch v {
            case .String as s:
                if !trimmed_empty(s) { ret (s, true) }
            case .Number as n:
                ret (n.lexeme, true)
            default:
                i += 0usize
            }
        }
        i += 1usize
    }
    ret ("", false)
}

fn lower_trim(a: *mem.Arena, s: str) -> str {
    var from = 0usize
    var to = s.len
    while from < to && (s[from] == 32u8 || s[from] == 9u8 || s[from] == 10u8 || s[from] == 13u8) { from += 1usize }
    while to > from && (s[to - 1usize] == 32u8 || s[to - 1usize] == 9u8 || s[to - 1usize] == 10u8 || s[to - 1usize] == 13u8) { to -= 1usize }
    let (out, e) = mem.alloc[u8](a, to - from + 1usize)
    var i = from
    var n = 0usize
    while i < to {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        out[n] = c
        n += 1usize
        i += 1usize
    }
    ret out[0usize..n]
}

// A boolean host variable: a YAML bool, or a string `true`/`yes`/`false`/`no`; false when absent or anything else.
fn host_bool(a: *mem.Arena, vars: json.Value, key: str) -> (bool, bool) {
    let (v, found) = ir.get(vars, key)
    if !found { ret (false, false) }
    switch v {
    case .Bool as b:
        ret (b, true)
    case .String as s:
        let t = lower_trim(a, s)
        if str.eq(t, "true") || str.eq(t, "yes") { ret (true, true) }
        if str.eq(t, "false") || str.eq(t, "no") { ret (false, true) }
        ret (false, false)
    default:
        ret (false, false)
    }
}

// The remote command for a shell: unchanged for POSIX, wrapped for PowerShell.
fn remote_command(a: *mem.Arena, command: str, powershell: bool) -> str {
    if powershell { ret join(a, "powershell -NoProfile -NonInteractive -Command ", command) }
    ret command
}

// The `ssh` argument list for a host (`vars` an object), without the program name.
fn ssh_args(a: *mem.Arena, address: str, vars: json.Value, command: str, powershell: bool) -> []const str {
    let (out, e) = mem.alloc[str](a, 24usize)
    var n = 0usize
    out[n] = "-o"
    out[n + 1usize] = "BatchMode=yes"
    out[n + 2usize] = "-o"
    out[n + 3usize] = "ConnectTimeout=15"
    n += 4usize
    var strict = true
    let (value, has) = host_bool(a, vars, "ssh_strict_host_key_checking")
    if has { strict = value }
    out[n] = "-o"
    if strict {
        out[n + 1usize] = "StrictHostKeyChecking=yes"
    } else {
        out[n + 1usize] = "StrictHostKeyChecking=no"
    }
    n += 2usize
    let known_keys = [2]str{ "ssh_known_hosts", "known_hosts" }
    let (known, has_known) = host_str(vars, known_keys[0usize..2usize])
    if has_known {
        out[n] = "-o"
        out[n + 1usize] = join(a, "UserKnownHostsFile=", known)
        n += 2usize
    }
    let key_keys = [3]str{ "ssh_private_key_file", "ansible_ssh_private_key_file", "ssh_key" }
    let (key, has_key) = host_str(vars, key_keys[0usize..3usize])
    if has_key {
        out[n] = "-o"
        out[n + 1usize] = "IdentitiesOnly=yes"
        out[n + 2usize] = "-i"
        out[n + 3usize] = key
        n += 4usize
    }
    let port_keys = [3]str{ "ssh_port", "ansible_port", "port" }
    let (port, has_port) = host_str(vars, port_keys[0usize..3usize])
    if has_port {
        out[n] = "-p"
        out[n + 1usize] = port
        n += 2usize
    }
    let user_keys = [3]str{ "ssh_user", "ansible_user", "user" }
    let (user, has_user) = host_str(vars, user_keys[0usize..3usize])
    if has_user {
        out[n] = join(a, join(a, user, "@"), address)
    } else {
        out[n] = address
    }
    n += 1usize
    out[n] = remote_command(a, command, powershell)
    n += 1usize
    ret out[0usize..n]
}
