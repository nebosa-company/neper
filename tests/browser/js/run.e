// Runs JavaScript files in a fresh realm (browser tracker 5.14): `run FILE...` evaluates each file in order in one realm and
// prints an uncaught exception as `Uncaught: <message>`.

use e.fs
use e.io
use e.js.interp as js
use e.js.realm as realm
use e.mem
use e.os
use e.str

fn describe(it: *js.Interp, v: js.Value) -> str {
    if js.is_object(v) {
        let (m, me) = js.get_value(it, v, js.key_of("message"))
        let (n, ne) = js.get_value(it, v, js.key_of("name"))
        if me == ok && ne == ok && js.is_string(n) {
            let (ms, mse) = js.to_string(it, m)
            if mse == ok { ret js.str_concat3(it, js.value_str(n), ": ", ms) }
        }
    }
    let (s, se) = js.to_string(it, v)
    if se == ok { ret s }
    ret "<error>"
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (it, re) = realm.new_realm(a)
    if re != ok { os.exit(3i32) }
    var failed = false
    var i = 0usize
    while i < args.len {
        if str.ends_with(args[i], ".js") {
            let (src, fe) = fs.read_file(a, args[i], 8388608usize)
            if fe != ok { os.exit(2i32) }
            let (v, e0) = realm.run(it, src)
            var e = e0
            if e == ok { e = js.run_jobs(it) }
            if e == js.Throw {
                let p = io.printf["Uncaught: {}\n"](describe(it, it.thrown))
                failed = true
            } else if e != ok {
                let p2 = io.printf["error in {}\n"](args[i])
                failed = true
            }
        }
        i += 1usize
    }
    if failed { os.exit(1i32) }
    ret ok
}
