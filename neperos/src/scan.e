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

// ----------------------------------------------------------------------------------------------
// (C173) The strict scan, for an app a server built from a prompt: the three rules above, plus
//   4. no loop that never ends -- `while true { ... }` whose body holds no `break` and no `ret`, which would
//      hold the screen and the compositor for ever;
//   5. only the app kit's modules -- the kit (appkit, ui, text, theme, scenes, icons) and the e.* library
//      except what is the system's own (e.os, e.proc, e.thread, e.dbus, e.debug, e.cli); the capability modules
//      of rule 2 stay allowed when declared.
// It returns every finding (up to the room given) with its line, so the Details screen can list them, and `report`
// renders them as text a person or a model can read.
const KIND_RAW: usize = 1usize
const KIND_NETWORK: usize = 2usize
const KIND_STORAGE: usize = 3usize
const KIND_LOOP: usize = 4usize
const KIND_MODULE: usize = 5usize
// The app kit's level, which a package's `api` is checked against (package.API_LEVEL says the same number).
const KIT_LEVEL: usize = 1usize

type Finding = struct { line: usize, kind: usize, name: [32]u8, name_len: usize }

fn same_name(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    ret starts_at(left, 0usize, right)
}

fn kit_module(name: str) -> bool {
    if same_name(name, "appkit") { ret true }
    if same_name(name, "ui") { ret true }
    if same_name(name, "text") { ret true }
    if same_name(name, "theme") { ret true }
    if same_name(name, "scenes") { ret true }
    if same_name(name, "icons") { ret true }
    ret false
}

fn system_module(name: str) -> bool {
    if same_name(name, "e.os") { ret true }
    if same_name(name, "e.proc") { ret true }
    if same_name(name, "e.thread") { ret true }
    if same_name(name, "e.dbus") { ret true }
    if same_name(name, "e.debug") { ret true }
    if same_name(name, "e.cli") { ret true }
    ret false
}

// Whether `module` is `base` or one of its submodules (`e.net` covers `e.net.http`).
fn under(module: str, base: str) -> bool {
    if base.len == 0usize || !starts_at(module, 0usize, base) { ret false }
    ret module.len == base.len || module[base.len] == 46u8
}

// 1 when `module` is a network module, 2 a storage one, 0 neither.
fn capability_of(module: str) -> usize {
    var k = 0usize
    while k < 4usize {
        if under(module, needs_network(k)) { ret 1usize }
        if under(module, needs_storage(k)) { ret 2usize }
        k += 1usize
    }
    ret 0usize
}

fn note(findings: []Finding, count: usize, line: usize, kind: usize, name: str) -> usize {
    if count < findings.len {
        var f: Finding = zero
        f.line = line
        f.kind = kind
        var i = 0usize
        while i < name.len && i < 32usize {
            f.name[i] = name[i]
            i += 1usize
        }
        f.name_len = i
        findings[count] = f
    }
    ret count + 1usize
}

// The byte after the `}` that closes the `{` at `open` (the end of the source when it is never closed); strings and
// comments are skipped.
fn block_end(source: str, open: usize) -> usize {
    var depth = 0usize
    var at = open
    while at < source.len {
        let c = source[at]
        if c == 47u8 && at + 1usize < source.len && source[at + 1usize] == 47u8 {
            while at < source.len && source[at] != 10u8 { at += 1usize }
        } else if c == 34u8 {
            at += 1usize
            while at < source.len && source[at] != 34u8 {
                if source[at] == 92u8 { at += 1usize }
                at += 1usize
            }
            at += 1usize
        } else {
            if c == 123u8 { depth += 1usize }
            if c == 125u8 {
                depth -= 1usize
                if depth == 0usize { ret at + 1usize }
            }
            at += 1usize
        }
    }
    ret source.len
}

// Whether `source[from..to]` holds `break` or `ret` as a word.
fn leaves(source: str, from: usize, to: usize) -> bool {
    var at = from
    while at < to {
        if starts_at(source, at, "//") {
            while at < to && source[at] != 10u8 { at += 1usize }
        } else if source[at] == 34u8 {
            at += 1usize
            while at < to && source[at] != 34u8 {
                if source[at] == 92u8 { at += 1usize }
                at += 1usize
            }
            at += 1usize
        } else {
            if name_at(source, at, "break") || name_at(source, at, "ret") { ret true }
            at += 1usize
        }
    }
    ret false
}

// Every finding of the strict scan: how many (it may be more than `findings` holds), the first `findings.len` kept.
fn strict(source: str, declared: usize, findings: []Finding) -> usize {
    var count = 0usize
    var at = 0usize
    while at < source.len {
        if starts_at(source, at, "//") {
            while at < source.len && source[at] != 10u8 { at += 1usize }
        } else {
            var b = 0usize
            while b < BANNED_COUNT {
                if name_at(source, at, banned(b)) { count = note(findings, count, line_of(source, at), KIND_RAW, banned(b)) }
                b += 1usize
            }
            if name_at(source, at, "use") && at + 4usize < source.len && source[at + 3usize] == 32u8 {
                let start = at + 4usize
                var end = start
                while end < source.len && (ident_byte(source[end]) || source[end] == 46u8) { end += 1usize }
                let module = source[start..end]
                let cap = capability_of(module)
                if cap == 1usize {
                    if (declared & NETWORK) == 0usize { count = note(findings, count, line_of(source, at), KIND_NETWORK, module) }
                } else if cap == 2usize {
                    if (declared & STORAGE) == 0usize { count = note(findings, count, line_of(source, at), KIND_STORAGE, module) }
                } else if system_module(module) || (!kit_module(module) && !starts_at(module, 0usize, "e.")) {
                    count = note(findings, count, line_of(source, at), KIND_MODULE, module)
                }
            }
            if name_at(source, at, "while") {
                var p = at + 5usize
                while p < source.len && source[p] == 32u8 { p += 1usize }
                if name_at(source, p, "true") {
                    p += 4usize
                    while p < source.len && (source[p] == 32u8 || source[p] == 10u8) { p += 1usize }
                    if p < source.len && source[p] == 123u8 {
                        let end = block_end(source, p)
                        if !leaves(source, p, end) { count = note(findings, count, line_of(source, at), KIND_LOOP, "while true") }
                    }
                }
            }
            at += 1usize
        }
    }
    ret count
}

fn kind_words(kind: usize) -> str {
    if kind == KIND_RAW { ret "reaches the machine directly, which only the app kit may do" }
    if kind == KIND_NETWORK { ret "uses the network without declaring it" }
    if kind == KIND_STORAGE { ret "uses storage without declaring it" }
    if kind == KIND_LOOP { ret "loops for ever: add a break or a ret" }
    ret "is not part of the app kit"
}

fn put_text(out: []u8, at: usize, piece: str) -> usize {
    var n = at
    var i = 0usize
    while i < piece.len && n < out.len {
        out[n] = piece[i]
        n += 1usize
        i += 1usize
    }
    ret n
}

// The findings as text, one line each: `line 4: os.load8 reaches the machine directly ...`; the length written.
fn report(findings: []Finding, count: usize, out: []u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < count && i < findings.len {
        let f = findings[i]
        n = put_text(out, n, "line ")
        var digits: [8]u8 = zero
        var d = 0usize
        var rest = f.line
        if rest == 0usize {
            digits[0usize] = 48u8
            d = 1usize
        }
        while rest > 0usize && d < 8usize {
            digits[d] = u8(48usize + rest % 10usize)
            rest = rest / 10usize
            d += 1usize
        }
        while d > 0usize && n < out.len {
            d -= 1usize
            out[n] = digits[d]
            n += 1usize
        }
        n = put_text(out, n, ": ")
        n = put_text(out, n, f.name[0usize..f.name_len])
        n = put_text(out, n, " ")
        n = put_text(out, n, kind_words(f.kind))
        n = put_text(out, n, "\n")
        i += 1usize
    }
    ret n
}
