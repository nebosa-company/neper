// The security scan (neperos/src/scan.e, C124) on sources that should pass and sources that should not. Every
// check has its own exit code.
use e.os
use e.mem
use scan

fn main(a: *mem.Arena, args: []str) -> err {
    let clean = "use e.mem\nuse appkit\nuse text\n\nfn main(a: *mem.Arena, args: []str) -> err {\n    ret ok\n}\n"
    let (n0, l0, m0) = scan.scan(clean, 0usize)
    if n0 != 0usize { os.exit(1) }

    let raw = "use e.os\n\nfn peek(addr: usize) -> u8 {\n    ret os.load8(addr)\n}\n"
    let (n1, l1, m1) = scan.scan(raw, 0usize)
    if n1 != 1usize || l1 != 4usize { os.exit(2) }

    // Declared or not, raw access stays refused.
    let (n2, l2, m2) = scan.scan(raw, scan.NETWORK | scan.STORAGE)
    if n2 != 1usize { os.exit(3) }

    let net = "use e.os\nuse httpc\n\nfn main(a: *mem.Arena, args: []str) -> err { ret ok }\n"
    let (n3, l3, m3) = scan.scan(net, 0usize)
    if n3 != 1usize || l3 != 2usize || m3.len == 0usize { os.exit(4) }
    let (n4, l4, m4) = scan.scan(net, scan.NETWORK)
    if n4 != 0usize { os.exit(5) }
    // A storage declaration does not cover the network.
    let (n5, l5, m5) = scan.scan(net, scan.STORAGE)
    if n5 != 1usize { os.exit(6) }

    let disk = "use vaultfs\nuse fsproto\n"
    let (n6, l6, m6) = scan.scan(disk, 0usize)
    if n6 != 2usize { os.exit(7) }
    let (n7, l7, m7) = scan.scan(disk, scan.STORAGE)
    if n7 != 0usize { os.exit(8) }

    // A comment is not code, and a longer name is not a banned one.
    let quiet = "// os.load64 is how the kit does it\nfn load_value() { let x = os.load640 }\nuse fsx\n"
    let (n8, l8, m8) = scan.scan(quiet, 0usize)
    if n8 != 0usize { os.exit(9) }

    let two = "use e.os\nfn f() {\n    os.store8(1usize, 2u8)\n    os.mrs(3usize)\n}\n"
    let (n9, l9, m9) = scan.scan(two, 0usize)
    if n9 != 2usize || l9 != 3usize { os.exit(10) }
    ret ok
}
