// The WinRM command line a host's variables describe (L048), after Petcow's `transport/winrm.rs`: PowerShell's own
// `Invoke-Command` driven with `-EncodedCommand`, so the program is the whole of what is checked and the process spawn is
// host code over `e.proc`.
//
//   * TLS (port 5986) unless the host says `winrm_allow_http`, then 5985; an explicit `winrm_port`, `ansible_port` or `port`
//     wins over both and does not turn TLS off;
//   * the certificate checks are on unless `winrm_skip_ca_check` or `winrm_skip_cn_check` waives that one;
//   * the password is never an argument: a named user (`winrm_user`, `ansible_user`, `user`) makes the session read
//     `$env:PETCOW_WINRM_PASSWORD` and throw when it is unset, and without a user no credential is passed at all;
//   * the remote payload is UTF-16LE then base64, so nothing in a play can end the string or the script block;
//   * `winrm_auth` / `winrm_authentication` become `-Authentication`.
//
// Memory: the arena is retained.

use e.algo.formula as f
use e.bytes
use e.fmt.json as json
use e.mem
use e.str
use e.text.utf8 as utf8
use x.ssh.args as sargs

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn https_port() -> str { ret "5986" }

fn http_port() -> str { ret "5985" }

fn password_env() -> str { ret "PETCOW_WINRM_PASSWORD" }

// `-EncodedCommand`'s encoding: the script as UTF-16LE, then standard padded base64.
fn encode_command(a: *mem.Arena, script: str) -> str {
    let (units, e) = mem.alloc[u8](a, script.len * 2usize + 4usize)
    if e != ok { ret "" }
    let (used, ue) = utf8.encode_utf16(script, false, units)
    if ue != ok { ret "" }
    let (out, oe) = mem.alloc[u8](a, used / 3usize * 4usize + 8usize)
    if oe != ok { ret "" }
    let (text, be) = bytes.base64_encode(out, units[0usize..used], .Standard, true)
    if be != ok { ret "" }
    ret text
}

// The PowerShell program that performs the remote call.
fn driver_script(a: *mem.Arena, address: str, vars: json.Value, command: str) -> str {
    let (allow, has_allow) = sargs.host_bool(a, vars, "winrm_allow_http")
    var allow_http = false
    if has_allow { allow_http = allow }
    var port = https_port()
    if allow_http { port = http_port() }
    let port_keys = [3]str{ "winrm_port", "ansible_port", "port" }
    let (named_port, has_port) = sargs.host_str(vars, port_keys[0usize..3usize])
    if has_port { port = named_port }

    var script = "$ErrorActionPreference = 'Stop'\n"
    var opts = ""

    var skips = ""
    let (skip_ca, has_ca) = sargs.host_bool(a, vars, "winrm_skip_ca_check")
    if has_ca && skip_ca { skips = "-SkipCACheck" }
    let (skip_cn, has_cn) = sargs.host_bool(a, vars, "winrm_skip_cn_check")
    if has_cn && skip_cn {
        if skips.len > 0usize {
            skips = join(a, skips, " -SkipCNCheck")
        } else {
            skips = "-SkipCNCheck"
        }
    }
    if skips.len > 0usize {
        script = join(a, join(a, join(a, script, "$sessionOpts = New-PSSessionOption "), skips), "\n")
        opts = " -SessionOption $sessionOpts"
    }

    let user_keys = [3]str{ "winrm_user", "ansible_user", "user" }
    let (user, has_user) = sargs.host_str(vars, user_keys[0usize..3usize])
    if has_user {
        let env = password_env()
        script = join(a, script, join(a, join(a, "$pw = $env:", env), "\n"))
        script = join(a, script, join(a, join(a, "if (-not $pw) { throw \"", env), " is not set, but host var 'winrm_user' names a user to authenticate as — set the variable, or remove the user to use the caller's own identity\" }\n"))
        script = join(a, script, join(a, join(a, "$cred = New-Object System.Management.Automation.PSCredential('", user), "', (ConvertTo-SecureString $pw -AsPlainText -Force))\n"))
        opts = join(a, opts, " -Credential $cred")
    }

    let auth_keys = [2]str{ "winrm_auth", "winrm_authentication" }
    let (auth, has_auth) = sargs.host_str(vars, auth_keys[0usize..2usize])
    if has_auth { opts = join(a, join(a, opts, " -Authentication "), auth) }
    if !allow_http { opts = join(a, opts, " -UseSSL") }

    script = join(a, script, join(a, join(a, "$enc = '", encode_command(a, command)), "'\n"))
    script = join(a, script, join(a, "Invoke-Command -ComputerName '", address))
    script = join(a, script, join(a, "' -Port ", port))
    script = join(a, script, opts)
    script = join(a, script, " -ScriptBlock {\n  powershell -NoProfile -NonInteractive -EncodedCommand $using:enc\n}\n")
    ret script
}

// The `powershell` argument list for a host and command, without the program name. The shell of a play does not change the
// payload: a POSIX play against a Windows host runs in the host's own shell.
fn winrm_args(a: *mem.Arena, address: str, vars: json.Value, command: str) -> []const str {
    let (out, e) = mem.alloc[str](a, 4usize)
    out[0] = "-NoProfile"
    out[1] = "-NonInteractive"
    out[2] = "-EncodedCommand"
    out[3] = encode_command(a, driver_script(a, address, vars, command))
    ret out[0usize..4usize]
}
