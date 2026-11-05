// JS number edge cases: asinh/acosh overflow (#808), toFixed with 100 fraction
// digits (#807), and the negative-to-zero sign (#354). toLocaleString (#355) is
// not covered here. Each check has its own exit code.
use e.io
use e.js.realm as realm
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let (it, realm_error) = realm.new_realm(a)
    if realm_error != ok { os.exit(90i32) }
    // #808: the true value is about 691.47; a squared overflow would answer infinity.
    let (_, e1) = realm.run(it, "if (!(Math.asinh(1e300) > 690 && Math.asinh(1e300) < 700)) throw new Error('asinh')")
    if e1 != ok { os.exit(1i32) }
    let (_, e2) = realm.run(it, "if (!(Math.acosh(1e300) > 690 && Math.acosh(1e300) < 700)) throw new Error('acosh')")
    if e2 != ok { os.exit(2i32) }
    // #807: the 100th fraction digit of 9e-100 must be 9, not a rounded 0.
    let (_, e3) = realm.run(it, "var s = (9e-100).toFixed(100); if (s.length !== 102 || s.charAt(101) !== '9') throw new Error('toFixed100')")
    if e3 != ok { os.exit(3i32) }
    // #354: a negative nonzero value rounded to zero keeps its sign.
    let (_, e4) = realm.run(it, "if ((-0.01).toFixed(0) !== '-0') throw new Error('negZero')")
    if e4 != ok { os.exit(4i32) }
    let (_, e5) = realm.run(it, "if ((-0.0001).toFixed(2) !== '-0.00') throw new Error('negZero2')")
    if e5 != ok { os.exit(5i32) }
    try io.print("audit js number ok")
    ret ok
}
