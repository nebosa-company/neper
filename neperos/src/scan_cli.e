// The server's scanner as a command (C173, C151): `scan_cli <source.e> [network] [storage]` reads a generated app's
// source, runs the strict scan of scan.e against the capabilities named, prints one line per finding
// (`line 4: os.load8 reaches the machine directly ...`) and exits 0 when there is none, 1 when there are some, 2 when
// the source cannot be read. Built for the host (x64) and run by the build server before it compiles and signs.
use e.os
use e.mem
use e.fs
use scan

fn main(a: *mem.Arena, args: []str) -> err {
    // The program's own name may come first; the source is the first argument that ends in .e.
    var source_at = args.len
    var i = 0usize
    while i < args.len {
        let name = args[i]
        if name.len > 2usize && name[name.len - 2usize] == 46u8 && name[name.len - 1usize] == 101u8 && source_at == args.len { source_at = i }
        i += 1usize
    }
    if source_at == args.len { os.exit(2) }
    let (bytes, read_error) = fs.read_file(a, args[source_at], 1048576usize)
    if read_error != ok { os.exit(2) }
    var declared = 0usize
    i = source_at + 1usize
    while i < args.len {
        if args[i].len == 7usize && args[i][0usize] == 110u8 { declared = declared | scan.NETWORK }
        if args[i].len == 7usize && args[i][0usize] == 115u8 { declared = declared | scan.STORAGE }
        i += 1usize
    }
    var found: [32]scan.Finding = zero
    let count = scan.strict(bytes, declared, found[0usize..32usize])
    var out: [2048]u8 = zero
    let n = scan.report(found[0usize..32usize], count, out[0usize..2048usize])
    if n > 0usize {
        let (written, write_error) = os.write(os.stdout(), out[0usize..n])
    }
    if count > 0usize { os.exit(1) }
    ret ok
}
