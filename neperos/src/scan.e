// The security scan for a generated app's source (C124): what the server runs before it builds and signs, and
// what its report shows on the Details screen. A source-level scan of the Neper text, by two rules the manifest
// makes checkable:
//   1. no raw machine access -- the intrinsics that read or write memory by address, reach system registers or
//      take exceptions (`os.load8` ... `os.store64`, `os.mrs`, `os.msr`, `os.barrier`, `os.tlb_flush`, `os.svc`,
//      `os.set_exception`, `os.set_console`, `os.thread_*`, `os.launch`, `os.reap`) belong to the app kit and
//      the system, not to a generated app;
//   2. a capability is declared before its module is used -- `network` for `netclient`, `httpc`, `net_real`
//      and `e.net`, `storage` for `vaultfs`, `fsproto`, `fs` and `e.fs`.
// A violation is a line number and a message; `scan` returns how many there are and the first.
// ponytail: it reads tokens, not the program's NIR, so a call hidden behind a name it cannot see (a function
// pointer built from data) is not found; the device's kernel grant is the enforcement either way (D2385), and
// the NIR walk this should become is the rest of C124's scanner.
const NETWORK: usize = 1usize
const STORAGE: usize = 2usize

fn starts_at(source: str, at: usize, word: str) -> bool {
    if at + word.len > source.len { ret false }
    var i = 0usize
    while i < word.len {
        if source[at + i] != word[i] { ret false }
        i += 1usize
    }
    ret true
}

fn ident_byte(c: u8) -> bool {
    ret (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || (c >= 48u8 && c <= 57u8) || c == 95u8
}

// Whether `word` occurs at `at` as a whole name (not inside a longer identifier or a longer path).
fn name_at(source: str, at: usize, word: str) -> bool {
    if !starts_at(source, at, word) { ret false }
    if at > 0usize && ident_byte(source[at - 1usize]) { ret false }
    if at + word.len < source.len && ident_byte(source[at + word.len]) { ret false }
    ret true
}

fn banned(index: usize) -> str {
    if index == 0usize { ret "os.load8" }
    if index == 1usize { ret "os.load16" }
    if index == 2usize { ret "os.load32" }
    if index == 3usize { ret "os.load64" }
    if index == 4usize { ret "os.store8" }
    if index == 5usize { ret "os.store16" }
    if index == 6usize { ret "os.store32" }
    if index == 7usize { ret "os.store64" }
    if index == 8usize { ret "os.mrs" }
    if index == 9usize { ret "os.msr" }
    if index == 10usize { ret "os.barrier" }
    if index == 11usize { ret "os.tlb_flush" }
    if index == 12usize { ret "os.svc" }
    if index == 13usize { ret "os.set_exception" }
    if index == 14usize { ret "os.set_console" }
    if index == 15usize { ret "os.launch" }
    if index == 16usize { ret "os.reap" }
    ret ""
}

const BANNED_COUNT: usize = 17usize

fn needs_network(index: usize) -> str {
    if index == 0usize { ret "netclient" }
    if index == 1usize { ret "httpc" }
    if index == 2usize { ret "net_real" }
    if index == 3usize { ret "e.net" }
    ret ""
}

fn needs_storage(index: usize) -> str {
    if index == 0usize { ret "vaultfs" }
    if index == 1usize { ret "fsproto" }
    if index == 2usize { ret "fs" }
    if index == 3usize { ret "e.fs" }
    ret ""
}

// The line number (from 1) of byte `at`.
fn line_of(source: str, at: usize) -> usize {
    var line = 1usize
    var i = 0usize
    while i < at && i < source.len {
        if source[i] == 10u8 { line += 1usize }
        i += 1usize
    }
    ret line
}

// Scan `source` against the capabilities declared (NETWORK | STORAGE bits). The number of violations, the
// line of the first (0 when none) and its message.
fn scan(source: str, declared: usize) -> (usize, usize, str) {
    var count = 0usize
    var first_line = 0usize
    var first_message = ""
    var at = 0usize
    while at < source.len {
        // A comment to the end of the line is not code.
        if starts_at(source, at, "//") {
            while at < source.len && source[at] != 10u8 { at += 1usize }
        } else {
            var b = 0usize
            while b < BANNED_COUNT {
                if name_at(source, at, banned(b)) {
                    count += 1usize
                    if first_line == 0usize {
                        first_line = line_of(source, at)
                        first_message = "raw machine access is not allowed"
                    }
                }
                b += 1usize
            }
            // `use <module>` lines name the modules the app imports.
            if name_at(source, at, "use") && at + 4usize < source.len && source[at + 3usize] == 32u8 {
                let start = at + 4usize
                var k = 0usize
                while k < 4usize {
                    let net = needs_network(k)
                    if net.len > 0usize && name_at(source, start, net) && (declared & NETWORK) == 0usize {
                        count += 1usize
                        if first_line == 0usize {
                            first_line = line_of(source, at)
                            first_message = "uses the network without declaring it"
                        }
                    }
                    let store = needs_storage(k)
                    if store.len > 0usize && name_at(source, start, store) && (declared & STORAGE) == 0usize {
                        count += 1usize
                        if first_line == 0usize {
                            first_line = line_of(source, at)
                            first_message = "uses storage without declaring it"
                        }
                    }
                    k += 1usize
                }
            }
            at += 1usize
        }
    }
    ret (count, first_line, first_message)
}
