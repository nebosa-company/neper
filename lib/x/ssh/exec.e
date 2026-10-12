// The SSM and local transports' decisions (L048), after Petcow's `transport/ssm.rs` and `transport/local.rs`: everything that
// is not a call into the AWS SDK or a process spawn, so the loop around the two SDK calls can be driven by a scripted client.
//
//   * SSM: the document for a shell (`AWS-RunShellScript` or `AWS-RunPowerShellScript`), the instance id (the host's
//     `resource_id` if it has that variable at all, else `instance_id`, and a value that is not a string is "no id"), the
//     terminal statuses (`Success`, `Cancelled`, `Failed`, `TimedOut`), and `ssm_run`: send, then poll up to `max_polls`
//     times, an invocation that does not exist yet being waited out, any other error ending the run with its text, a
//     terminal status answering with the invocation's exit code and output and `ok` only for `Success`;
//   * local: the program and arguments for a POSIX command (`sh -c`) or PowerShell (`powershell -NoProfile -NonInteractive
//     -Command`), and the error text of a failed spawn.
//
// The two SDK calls, the interval between polls (1.5 s in the original, 80 polls) and the spawn are host code.
//
// Memory: the arena is retained.

use e.algo.formula as f
use e.fmt.json as json
use e.mem
use e.str

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

// `PetcowError::resource(id, message)` as it is displayed.
fn resource_error(a: *mem.Arena, logical_id: str, message: str) -> str {
    ret join(a, join(a, join(a, "in resource '", logical_id), "': "), message)
}

fn ssm_document(powershell: bool) -> str {
    if powershell { ret "AWS-RunPowerShellScript" }
    ret "AWS-RunShellScript"
}

// The instance id a host is targeted by: `(id, true, "")`, or the displayed error.
fn ssm_instance_id(a: *mem.Arena, host: str, vars: json.Value) -> (str, bool, str) {
    var found = false
    var value = json.Value{ Bool: false }
    let members = object_members(vars)
    var at = 0usize
    while at < members.len && !found {
        if str.eq(members[at].key, "resource_id") {
            found = true
            value = members[at].value
        }
        at += 1usize
    }
    at = 0usize
    while at < members.len && !found {
        if str.eq(members[at].key, "instance_id") {
            found = true
            value = members[at].value
        }
        at += 1usize
    }
    if found {
        switch value {
        case .String as s:
            ret (s, true, "")
        default:
            let nothing = 0u8
        }
    }
    let message = "SSM transport needs an instance id — set a `resource_id`/`instance_id` var or use dynamic inventory (it sets one from discovery)"
    ret ("", false, resource_error(a, host, message))
}

fn object_members(v: json.Value) -> []const json.Member {
    switch v {
    case .Object as m:
        ret m
    default:
        ret zero
    }
}

fn ssm_is_terminal(status: str) -> bool {
    ret str.eq(status, "Success") || str.eq(status, "Cancelled") || str.eq(status, "Failed") || str.eq(status, "TimedOut")
}

// What `send_command` answered: a command id, or the displayed SDK error.
type Sent = struct { good: bool, has_id: bool, id: str, failure: str }

// What `get_command_invocation` answered: `kind` 0 an invocation (status, code and output), 1 "invocation does not exist",
// 2 any other error with its displayed text.
type Invocation = struct { kind: i32, has_status: bool, status: str, code: i32, out: str, err_out: str, failure: str }

type Client = struct { ctx: *void, send: fn(*void, str, str, str) -> Sent, invoke: fn(*void, str, str) -> Invocation }

type Outcome = struct { good: bool, message: str, exit_code: i32, stdout: str, stderr: str, succeeded: bool, polls: usize }

fn failed(message: str, polls: usize) -> Outcome {
    ret Outcome { good: false, message: message, exit_code: 0i32, stdout: "", stderr: "", succeeded: false, polls: polls }
}

// Sends `command` through the SSM document for the shell and polls its invocation to a terminal status.
fn ssm_run(a: *mem.Arena, c: *const Client, host: str, vars: json.Value, command: str, powershell: bool, max_polls: usize) -> Outcome {
    let (id, has_id, why) = ssm_instance_id(a, host, vars)
    if !has_id { ret failed(why, 0usize) }
    let sent = c.send(c.ctx, id, ssm_document(powershell), command)
    if !sent.good { ret failed(resource_error(a, host, join(a, "ssm send_command: ", sent.failure)), 0usize) }
    if !sent.has_id { ret failed(resource_error(a, host, "send_command returned no command id"), 0usize) }
    var polls = 0usize
    while polls < max_polls {
        polls += 1usize
        let inv = c.invoke(c.ctx, sent.id, id)
        if inv.kind == 2i32 {
            ret failed(resource_error(a, host, join(a, "ssm get_command_invocation: ", inv.failure)), polls)
        }
        if inv.kind == 0i32 && inv.has_status && ssm_is_terminal(inv.status) {
            ret Outcome { good: true, message: "", exit_code: inv.code, stdout: inv.out, stderr: inv.err_out, succeeded: str.eq(inv.status, "Success"), polls: polls }
        }
    }
    let (made, e) = str.builder(a, 24usize)
    if e != ok { ret failed("", polls) }
    var b = made
    let pushed = str.push_usize(&b, max_polls)
    let count = str.done(&b)
    ret failed(resource_error(a, host, join(a, join(a, "ssm command timed out after ", count), " polls")), polls)
}

// The program and arguments that run `command` on this machine.
fn local_argv(a: *mem.Arena, command: str, powershell: bool) -> []const str {
    if powershell {
        let (out, e) = mem.alloc[str](a, 5usize)
        out[0] = "powershell"
        out[1] = "-NoProfile"
        out[2] = "-NonInteractive"
        out[3] = "-Command"
        out[4] = command
        ret out[0usize..5usize]
    }
    let (out, e) = mem.alloc[str](a, 3usize)
    out[0] = "sh"
    out[1] = "-c"
    out[2] = command
    ret out[0usize..3usize]
}

// The error of a local spawn that failed.
fn local_error(a: *mem.Arena, host: str, powershell: bool, message: str) -> str {
    var shell = "sh"
    if powershell { shell = "powershell" }
    ret resource_error(a, host, join(a, join(a, join(a, "local exec via ", shell), ": "), message))
}

// The PowerShell a WinRM run drives: Windows ships `powershell`, elsewhere WSMan lives in `pwsh`.
fn winrm_program(windows: bool) -> str {
    if windows { ret "powershell" }
    ret "pwsh"
}

// The error of a WinRM spawn that failed: the client is not installed, or any other message.
fn winrm_error(a: *mem.Arena, host: str, program: str, not_found: bool, message: str) -> str {
    if not_found {
        ret resource_error(a, host, join(a, join(a, "`", program), "` is not installed (needed for the winrm transport)"))
    }
    ret resource_error(a, host, join(a, "winrm exec: ", message))
}
