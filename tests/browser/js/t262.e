// test262 runner (browser tracker 5.14): `t262 TEST262_DIR LIST [--show] [--floor N] [--strict]`.
//
// LIST names test files (one path per line). Each test runs in a fresh realm with the harness (`assert.js`, `sta.js`,
// `doneprintHandle.js` for async tests, and the metadata `includes`) evaluated first. A test passes when it finishes without an
// uncaught exception, or -- for `negative` metadata -- when it throws the expected error type (parse-phase negatives are checked
// by parsing alone). Tests that need unimplemented features are counted as skipped.

use e.data.list as list
use e.fs
use e.io
use e.js.b_atomics as b_atomics
use e.js.interp as js
use e.js.module as module
use e.js.parser as jsparse
use e.js.realm as realm
use e.mem
use e.os
use e.str
use e.thread

// The `features:` entry of the metadata (a flow list on one line or a block list), so words in prose never match.
fn features_of(meta: str) -> str {
    let (at, found) = str.find(meta, "\nfeatures:")
    if !found { ret "" }
    var end = at + 1usize
    while end < meta.len && meta[end] != 10u8 { end += 1usize }
    while end + 1usize < meta.len && (meta[end + 1usize] == 32u8 || meta[end + 1usize] == 45u8) {
        end += 1usize
        while end < meta.len && meta[end] != 10u8 { end += 1usize }
    }
    ret meta[at..end]
}

fn skipped_feature(full_meta: str) -> bool {
    let (cb0, cant_block) = str.find(full_meta, "CanBlockIsFalse")
    if cant_block { ret true }
    let meta = features_of(full_meta)
    let feats = "source-phase-imports-module-source|"
    var start = 0usize
    var i = 0usize
    while i < feats.len {
        if feats[i] == 124u8 {
            let (at, found) = str.find(meta, feats[start..i])
            if found { ret true }
            start = i + 1usize
        }
        i += 1usize
    }
    ret false
}

// The `includes` listed in the metadata.
fn includes_of(a: *mem.Arena, meta: str) -> []const str {
    let (l, le) = list.init[str](a, 4usize)
    var out = l
    let (at, found) = str.find(meta, "includes:")
    if !found { ret list.slice_const[str](&out) }
    var pos = at + 9usize
    while pos < meta.len && meta[pos] == 32u8 { pos += 1usize }
    if pos < meta.len && meta[pos] == 91u8 {
        pos += 1usize
        while pos < meta.len && meta[pos] != 93u8 {
            let start = pos
            while pos < meta.len && meta[pos] != 44u8 && meta[pos] != 93u8 { pos += 1usize }
            let name = str.trim(meta[start..pos])
            if name.len > 0usize { let pe = list.push[str](&out, name) }
            if pos < meta.len && meta[pos] == 44u8 { pos += 1usize }
        }
    } else {
        while pos < meta.len {
            while pos < meta.len && meta[pos] != 10u8 { pos += 1usize }
            pos += 1usize
            var q = pos
            while q < meta.len && (meta[q] == 32u8 || meta[q] == 9u8) { q += 1usize }
            if q < meta.len && meta[q] == 45u8 {
                q += 1usize
                var e = q
                while e < meta.len && meta[e] != 10u8 && meta[e] != 13u8 { e += 1usize }
                let name2 = str.trim(meta[q..e])
                if name2.len > 0usize { let pe2 = list.push[str](&out, name2) }
                pos = e
            } else {
                break
            }
        }
    }
    ret list.slice_const[str](&out)
}

fn field_of(meta: str, from: usize, key: str) -> str {
    let (p, found) = str.find_from(meta, key, from)
    if !found { ret "" }
    var s = p + key.len
    while s < meta.len && meta[s] == 32u8 { s += 1usize }
    var e = s
    while e < meta.len && meta[e] != 10u8 && meta[e] != 13u8 { e += 1usize }
    ret meta[s..e]
}

fn cat3(a: *mem.Arena, x: str, y: str, z: str) -> str {
    let (r1, e1) = str.concat(a, x, y)
    if e1 != ok { ret x }
    let (r2, e2) = str.concat(a, r1, z)
    if e2 != ok { ret r1 }
    ret r2
}

type Ctx = struct { a: *mem.Arena, args: []str, status: i32 }

// The directory part of a path ("" when there is none), with the trailing slash.
fn dir_part(path: str) -> str {
    var i = path.len
    while i > 0usize && path[i - 1usize] != 47u8 { i -= 1usize }
    ret path[0usize..i]
}

// Joins `base` (a directory with a trailing slash) and a relative path and removes "." and ".." segments.
fn join_path(a: *mem.Arena, base: str, rel: str) -> str {
    var full = rel
    if !(rel.len > 0usize && rel[0usize] == 47u8) { full = cat3(a, base, rel, "") }
    var segs: [96]str = zero
    var n = 0usize
    var pos = 0usize
    var drive = ""
    if full.len > 2usize && full[1usize] == 58u8 {
        drive = full[0usize..2usize]
        full = full[2usize..]
    }
    while pos <= full.len {
        var end = pos
        while end < full.len && full[end] != 47u8 { end += 1usize }
        let seg = full[pos..end]
        if str.eq(seg, "..") {
            if n > 0usize { n -= 1usize }
        } else if seg.len > 0usize && !str.eq(seg, ".") {
            if n < 96usize {
                segs[n] = seg
                n += 1usize
            }
        }
        pos = end + 1usize
    }
    var out = drive
    var i = 0usize
    while i < n {
        out = cat3(a, out, "/", segs[i])
        i += 1usize
    }
    ret out
}

// Resolves a module specifier against the referring module's file and loads it from disk.
fn load_module(it: *js.Interp, referrer: str, spec_in: str) -> (*void, err) {
    let (spec, kind) = module.split_spec(spec_in)
    var rel_ok = false
    if spec.len > 1usize && spec[0usize] == 46u8 && (spec[1usize] == 47u8 || spec[1usize] == 46u8) { rel_ok = true }
    if spec.len > 0usize && spec[0usize] == 47u8 { rel_ok = true }
    if !rel_ok { ret (zero, js.throw_type(it, cat3(it.a, "Cannot resolve module specifier ", spec, ""))) }
    let resolved = join_path(it.a, dir_part(referrer), spec)
    let (found, has) = module.find_typed(it, resolved, kind)
    if has { ret (mem.cast[*void](found), ok) }
    let (src, fe) = fs.read_file(it.a, resolved, 8388608usize)
    if fe != ok { ret (zero, js.throw_type(it, cat3(it.a, "Cannot find module ", resolved, ""))) }
    let text: str = src
    if kind.len > 0usize {
        let (sm, sme) = module.new_synthetic_module(it, resolved, text, kind)
        if sme != ok { ret (zero, sme) }
        ret (mem.cast[*void](sm), ok)
    }
    let (m, me) = module.new_module(it, resolved, text)
    if me != ok { ret (zero, me) }
    ret (mem.cast[*void](m), ok)
}

fn name_of_thrown(it: *js.Interp, v: js.Value) -> str {
    if js.is_object(v) {
        let (cv, ce) = js.get_value(it, v, js.key_of("constructor"))
        if ce == ok && js.is_object(cv) {
            let (nv, ne) = js.get_value(it, cv, js.key_of("name"))
            if ne == ok && js.is_string(nv) { ret js.value_str(nv) }
        }
    }
    ret ""
}

fn main(a: *mem.Arena, args: []str) -> err {
    // The interpreter recurses deeply, so it runs on a thread with a large stack.
    var ctx = Ctx { a: a, args: args, status: 0i32 }
    let (th, te) = thread.spawn[Ctx](run_all, &ctx, 536870912usize)
    if te != ok { os.exit(5i32) }
    let je = thread.join(th)
    if ctx.status != 0i32 { os.exit(ctx.status) }
    ret ok
}

fn run_all(ctx: *Ctx) {
    let a = ctx.a
    let args = ctx.args
    var dir = ""
    var list_path = ""
    var show = false
    var trace = false
    var floor = 0usize
    var strict_all = false
    var i = 0usize
    while i < args.len {
        if i == 0usize {
            // the program name
        } else if str.eq(args[i], "--show") {
            show = true
        } else if str.eq(args[i], "--trace") {
            trace = true
        } else if str.eq(args[i], "--strict") {
            strict_all = true
        } else if str.eq(args[i], "--floor") {
            i += 1usize
            let (n, ne) = str.parse_i64(args[i])
            if ne == ok { floor = usize(n) }
        } else if dir.len == 0usize {
            dir = args[i]
        } else {
            list_path = args[i]
        }
        i += 1usize
    }
    if dir.len == 0usize || list_path.len == 0usize {
        ctx.status = 2i32
        ret
    }
    let (list_text, le) = fs.read_file(a, list_path, 67108864usize)
    if le != ok {
        ctx.status = 3i32
        ret
    }
    let (assert_js, ae) = fs.read_file(a, cat3(a, dir, "/harness/", "assert.js"), 1048576usize)
    let (sta_js, se) = fs.read_file(a, cat3(a, dir, "/harness/", "sta.js"), 1048576usize)
    let (done_js, de) = fs.read_file(a, cat3(a, dir, "/harness/", "doneprintHandle.js"), 1048576usize)
    if ae != ok || se != ok {
        ctx.status = 4i32
        ret
    }
    let base = mem.mark(a)
    var total = 0usize
    var passed = 0usize
    var skipped = 0usize
    var pos = 0usize
    while pos < list_text.len {
        var end = pos
        while end < list_text.len && list_text[end] != 10u8 { end += 1usize }
        let path = str.trim(list_text[pos..end])
        pos = end + 1usize
        if path.len == 0usize { continue }
        let work = mem.mark(a)
        let (src, fe) = fs.read_file(a, cat3(a, dir, "/", path), 8388608usize)
        if fe != ok {
            mem.reset(a, work)
            continue
        }
        var meta = ""
        let (m0, has0) = str.find(src, "/*---")
        if has0 {
            let (m1, has1) = str.find_from(src, "---*/", m0)
            if has1 { meta = src[m0..m1] }
        }
        var flags = ""
        let (ff, has_flags) = str.find(meta, "flags:")
        if has_flags {
            var fe2 = ff
            while fe2 < meta.len && meta[fe2] != 10u8 { fe2 += 1usize }
            flags = meta[ff..fe2]
        }
        let (f1, is_raw) = str.find(flags, "raw")
        let (f2, is_module) = str.find(flags, "module")
        let (f3, is_async) = str.find(flags, "async")
        let (f4, only_strict) = str.find(flags, "onlyStrict")
        let (f5, no_strict) = str.find(flags, "noStrict")
        var expect_phase = ""
        var expect_type = ""
        let (nn, has_neg) = str.find(meta, "negative:")
        if has_neg {
            expect_phase = field_of(meta, nn, "phase:")
            expect_type = field_of(meta, nn, "type:")
        }
        if skipped_feature(meta) || (strict_all && no_strict) {
            skipped += 1usize
            mem.reset(a, work)
            continue
        }
        total += 1usize
        if trace { let tp = io.printf["{}\n"](path) }
        var pass = false
        var why = ""
        let use_strict = only_strict || strict_all
        if is_module && (str.eq(expect_phase, "parse") || str.eq(expect_phase, "early")) {
            let (pr, pe) = jsparse.parse_module(a, src)
            if pe != ok { pass = true } else {
                // Static errors of the module record count as early errors too.
                let (it0, re0) = realm.new_realm(a)
                if re0 == ok {
                    let ie = module.install(it0, load_module)
                    let (mm, me) = module.new_module(it0, cat3(a, dir, cat3(a, "/", path, ""), ""), src)
                    if me != ok { pass = true } else { why = "expected an early error" }
                } else {
                    why = "expected an early error"
                }
            }
        } else if str.eq(expect_phase, "parse") || str.eq(expect_phase, "early") {
            var text: str = src
            if use_strict { text = cat3(a, "\"use strict\";\n", src, "") }
            let (pr, pe) = jsparse.parse_program(a, text)
            if pe != ok { pass = true } else { why = "expected an early error" }
        } else {
            let (it, re) = realm.new_realm(a)
            if re == ok {
                it.quiet = true
                it.step_limit = 40000000u64
                // The calendar sweeps of intl402 walk a century of dates; they need an order of magnitude more.
                let (ip, is_intl) = str.find(path, "intl402/")
                if is_intl { it.step_limit = 400000000u64 }
            }
            if re != ok {
                why = "realm"
            } else {
                var failed = false
                var script: str = src
                if use_strict { script = cat3(a, "\"use strict\";\n", src, "") }
                if !is_raw {
                    let (h1, e1) = realm.run(it, assert_js)
                    let (h2, e2) = realm.run(it, sta_js)
                    if e1 != ok || e2 != ok { failed = true }
                    if is_async && de == ok {
                        let (h3, e3) = realm.run(it, done_js)
                    }
                    let incs = includes_of(a, meta)
                    var k = 0usize
                    while k < incs.len && !failed {
                        let (inc_src, ie) = fs.read_file(a, cat3(a, dir, "/harness/", incs[k]), 1048576usize)
                        if ie == ok {
                            let (h4, e4) = realm.run(it, inc_src)
                            if e4 != ok {
                                failed = true
                                why = cat3(a, "harness ", incs[k], " failed")
                            }
                        }
                        k += 1usize
                    }
                }
                let full_path = cat3(a, dir, cat3(a, "/", path, ""), "")
                if !failed {
                    let ie0 = module.install(it, load_module)
                    it.script_url = full_path
                    var e: err = ok
                    var v0 = js.undefv()
                    if is_module {
                        let (mm, me) = module.new_module(it, full_path, src)
                        e = me
                        if e == ok {
                            let (pv, pe2) = module.run_module(it, mm)
                            e = pe2
                            if e == ok {
                                let je0 = js.run_jobs(it)
                                if je0 != ok { e = je0 }
                                let ps = js.promise_state_of(js.as_object(pv))
                                if e == ok && ps.state == 2u8 {
                                    it.thrown = ps.result
                                    e = js.Throw
                                }
                            }
                        }
                    } else {
                        let (v, e1) = realm.run(it, script)
                        e = e1
                        v0 = v
                        if e == ok {
                            let je = js.run_jobs(it)
                            if je != ok { e = je }
                            b_atomics.settle(it)
                        }
                    }
                    if e == js.Throw {
                        var thrown_name = ""
                        if js.is_object(it.thrown) {
                            let (cv, ce) = js.get_value(it, it.thrown, js.key_of("constructor"))
                            if ce == ok && js.is_object(cv) {
                                let (nv, ne) = js.get_value(it, cv, js.key_of("name"))
                                if ne == ok && js.is_string(nv) { thrown_name = js.value_str(nv) }
                            }
                        }
                        if (str.eq(expect_phase, "runtime") || str.eq(expect_phase, "resolution")) && str.eq(thrown_name, expect_type) {
                            pass = true
                        } else {
                            let (ms, mse) = js.to_string(it, it.thrown)
                            if mse == ok { why = ms } else { why = thrown_name }
                        }
                    } else if e != ok {
                        why = "interpreter error"
                    } else if expect_phase.len == 0usize {
                        if is_async {
                            let (c1, has_ok) = str.find(it.last_print, "Test262:AsyncTestComplete")
                            if has_ok { pass = true } else { why = it.last_print }
                        } else {
                            pass = true
                        }
                    } else {
                        why = "expected an exception"
                    }
                }
                js.agents_shutdown(it)
                js.shutdown_generators(it)
            }
        }
        if pass {
            passed += 1usize
        } else if show {
            let p = io.printf["FAIL {}: {}\n"](path, why)
        }
        mem.reset(a, work)
    }
    mem.reset(a, base)
    let summary = io.printf["test262 {} pass {} skip {}\n"](total, passed, skipped)
    if passed < floor { ctx.status = 1i32 }
}
