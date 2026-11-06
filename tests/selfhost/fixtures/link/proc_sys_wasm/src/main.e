// `e.proc.sys` over WASI (C182, D5877): disk usage resolves the path's own preopen
// (#1587) and uptime only claims host uptime when the runner provides it (#1314).
// The node runner mounts `.` as `/`, `/tmp` and `/home` as additional preopens, so a
// path under `/tmp` must be answered by that preopen, not the first one.
use e.io
use e.os
use e.proc.sys
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    // #1587: paths under the second and third preopens resolve and answer.
    let (tmp_usage, tmp_error) = sys.disk_usage(a, "/tmp")
    if tmp_error != ok || tmp_usage.total == 0u64 || tmp_usage.used > tmp_usage.total { os.exit(1i32) }
    let (home_usage, home_error) = sys.disk_usage(a, "/home")
    if home_error != ok || home_usage.total == 0u64 { os.exit(2i32) }
    let (cwd_usage, cwd_error) = sys.disk_usage(a, ".")
    if cwd_error != ok || cwd_usage.total == 0u64 { os.exit(3i32) }

    // #1314: uptime comes from the runner's uptime text when it has one; without that
    // extension the call must answer Unsupported rather than hand back the monotonic
    // clock. A boot time must then be derived and lie in the past.
    let (up, up_error) = sys.uptime_ms(a)
    if up_error == ok {
        if up == 0u64 { os.exit(4i32) }
        let (boot, boot_error) = sys.boot_time(a)
        if boot_error != ok || boot <= 0i64 { os.exit(5i32) }
        let (wall, wall_error) = os.clock(.Wall)
        if wall_error != ok || i64(wall / 1000000000i64) < boot { os.exit(6i32) }
    } else if up_error != os.Unsupported {
        os.exit(7i32)
    }
    try io.print("proc sys wasm ok")
    ret ok
}
