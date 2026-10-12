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

    // (C173) The strict scan: the same three rules with every finding listed, a loop that never ends and a module
    // outside the app kit.
    var found: [8]scan.Finding = zero
    let good = "use appkit\nuse ui\nuse e.mem\nuse e.fmt.json\n\nfn main(a: *mem.Arena, args: []str) -> err {\n    var running = true\n    while running {\n        running = false\n    }\n    while true {\n        if !running { break }\n    }\n    ret ok\n}\n"
    if scan.strict(good, 0usize, found[0usize..8usize]) != 0usize { os.exit(11) }

    let hang = "use appkit\n\nfn main(a: *mem.Arena, args: []str) -> err {\n    while true {\n        let x = 1usize\n    }\n    ret ok\n}\n"
    let hang_count = scan.strict(hang, 0usize, found[0usize..8usize])
    if hang_count != 1usize || found[0usize].line != 4usize || found[0usize].kind != scan.KIND_LOOP { os.exit(12) }

    // A string with a brace and a comment with `ret` in it do not decide the loop.
    let tricky = "fn f() {\n    while true {\n        let s = \"}\"\n        // ret\n    }\n}\n"
    if scan.strict(tricky, 0usize, found[0usize..8usize]) != 1usize { os.exit(13) }

    let system = "use e.os\nuse e.thread\nuse totally_made_up\nuse ui\n"
    let system_count = scan.strict(system, 0usize, found[0usize..8usize])
    if system_count != 3usize || found[0usize].kind != scan.KIND_MODULE || found[2usize].line != 3usize { os.exit(14) }

    // The capability modules follow the manifest here too, with their submodules.
    let capability = "use e.net.http\nuse e.fs.path\nuse httpc\n"
    if scan.strict(capability, 0usize, found[0usize..8usize]) != 3usize { os.exit(15) }
    if scan.strict(capability, scan.NETWORK, found[0usize..8usize]) != 1usize || found[0usize].kind != scan.KIND_STORAGE { os.exit(16) }
    if scan.strict(capability, scan.NETWORK | scan.STORAGE, found[0usize..8usize]) != 0usize { os.exit(17) }

    // More findings than room: the count is the whole, the list is the first ones.
    let many = "use e.os\nuse e.os\nuse e.os\nuse e.os\nuse e.os\n"
    if scan.strict(many, 0usize, found[0usize..2usize]) != 5usize { os.exit(18) }

    // The report is text a person or a model reads: line, name, what is wrong.
    let peek = "fn peek(addr: usize) -> u8 {\n    ret os.load8(addr)\n}\n"
    let one_found = scan.strict(peek, 0usize, found[0usize..8usize])
    var text_out: [160]u8 = zero
    let written = scan.report(found[0usize..8usize], one_found, text_out[0usize..160usize])
    let expected = "line 2: os.load8 reaches the machine directly, which only the app kit may do\n"
    if one_found != 1usize || written != expected.len { os.exit(19) }
    var i = 0usize
    while i < expected.len {
        if text_out[i] != expected[i] { os.exit(20) }
        i += 1usize
    }
    ret ok
}
