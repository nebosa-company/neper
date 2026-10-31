// `e.fmt.css.sheet`: a style sheet with @media (types, min/max, range syntax, not/only, colour scheme, resolution),
// @supports, nested and statement @layer, @container, @scope, @font-face (best source), @keyframes (sorted stops),
// @property and @import, loaded into the flat rule list the cascade ranks. Each check has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.css.cascade as cascade
use e.fmt.css.container as container
use e.fmt.css.sheet as sheet
use e.fmt.css.syntax as syntax

fn count_with(rules: []const cascade.Rule, name: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < rules.len {
        var d = 0usize
        while d < rules[i].declarations.len {
            if str.eq(rules[i].declarations[d].property, name) { n += 1usize }
            d += 1usize
        }
        i += 1usize
    }
    ret n
}

fn value_of(rules: []const cascade.Rule, name: str) -> str {
    var i = 0usize
    while i < rules.len {
        var d = 0usize
        while d < rules[i].declarations.len {
            if str.eq(rules[i].declarations[d].property, name) { ret rules[i].declarations[d].value }
            d += 1usize
        }
        i += 1usize
    }
    ret ""
}

fn main(a: *mem.Arena, args: []str) -> err {
    var env = sheet.media_env(800.0f64, 600.0f64)
    // @media
    let media = "a{--m1:1} @media (min-width: 700px){b{--m2:1}} @media (min-width: 900px){c{--m3:1}} @media screen and (max-width: 800px) and (min-height: 500px){d{--m4:1}} @media print{e{--m5:1}} @media not print{f{--m6:1}} @media (width >= 600px){g{--m7:1}} @media (400px <= width < 800px){h{--m8:1}} @media (400px <= width <= 800px){i{--m9:1}} @media (prefers-color-scheme: dark){j{--m10:1}} @media (orientation: landscape), (min-width: 5000px){k{--m11:1}} @media only screen and (-webkit-min-device-pixel-ratio: 1){l{--m12:1}} @media (unknown-feature: 1){m{--m13:1}} @media (not (min-width: 900px)){n{--m14:1}} @media (min-width: 900px) or (max-width: 810px){o{--m15:1}}"
    let (m, me) = sheet.parse_sheet(a, env, media)
    if me != ok { os.exit(1) }
    if count_with(m.rules, "--m1") != 1usize || count_with(m.rules, "--m2") != 1usize { os.exit(2) }
    if count_with(m.rules, "--m3") != 0usize || count_with(m.rules, "--m4") != 1usize { os.exit(3) }
    if count_with(m.rules, "--m5") != 0usize || count_with(m.rules, "--m6") != 1usize { os.exit(4) }
    if count_with(m.rules, "--m7") != 1usize || count_with(m.rules, "--m8") != 0usize || count_with(m.rules, "--m9") != 1usize { os.exit(5) }
    if count_with(m.rules, "--m10") != 0usize || count_with(m.rules, "--m11") != 1usize || count_with(m.rules, "--m12") != 1usize { os.exit(6) }
    if count_with(m.rules, "--m13") != 0usize || count_with(m.rules, "--m14") != 1usize || count_with(m.rules, "--m15") != 1usize { os.exit(7) }
    env.dark = true
    let (dark, de) = sheet.parse_sheet(a, env, media)
    if de != ok || count_with(dark.rules, "--m10") != 1usize { os.exit(8) }

    // @supports
    let sup = "@supports (display: grid){a{--s1:1}} @supports not (display: grid){b{--s2:1}} @supports (display: grid) and (color: red){c{--s3:1}} @supports (display: grid) or (nonsense){d{--s4:1}} @supports selector(a > b){e{--s5:1}} @supports selector(>>){f{--s6:1}} @supports not (selector(a > b)){g{--s7:1}}"
    let (s, se) = sheet.parse_sheet(a, sheet.media_env(800.0f64, 600.0f64), sup)
    if se != ok { os.exit(9) }
    if count_with(s.rules, "--s1") != 1usize || count_with(s.rules, "--s2") != 0usize || count_with(s.rules, "--s3") != 1usize || count_with(s.rules, "--s4") != 1usize { os.exit(10) }
    if count_with(s.rules, "--s5") != 1usize || count_with(s.rules, "--s6") != 0usize || count_with(s.rules, "--s7") != 0usize { os.exit(11) }

    // @layer: the statement fixes the order, a block joins it, nesting joins the names with a dot.
    let lay = "@layer base, theme; @layer theme{a{--l1:1}} @layer base{b{--l2:1} @layer inner{c{--l3:1}}} d{--l4:1}"
    let (l, le) = sheet.parse_sheet(a, sheet.media_env(800.0f64, 600.0f64), lay)
    if le != ok || l.rules.len != 4usize { os.exit(12) }
    if !l.rules[0usize].has_layer || l.rules[0usize].layer != 1i64 { os.exit(13) }
    if !l.rules[1usize].has_layer || l.rules[1usize].layer != 0i64 { os.exit(14) }
    if !l.rules[2usize].has_layer || l.rules[2usize].layer != 2i64 || l.layers.len != 3usize || !str.eq(l.layers[2usize], "base.inner") { os.exit(15) }
    if l.rules[3usize].has_layer { os.exit(16) }

    // @container and @scope ride on the rules inside.
    let ctr = "@container sidebar (min-width: 400px) and (max-height: 100px){a{--c1:1}} @container (width > 10px){b{--c2:1}} @scope (.card) to (.limit){c{--c3:1}}"
    let (c, ce) = sheet.parse_sheet(a, sheet.media_env(800.0f64, 600.0f64), ctr)
    if ce != ok || c.rules.len != 3usize { os.exit(17) }
    if c.rules[0usize].containers.len != 1usize || !c.rules[0usize].containers[0usize].has_name || !str.eq(c.rules[0usize].containers[0usize].name, "sidebar") { os.exit(18) }
    if c.rules[0usize].containers[0usize].condition.kind != container.CondKind.And || c.rules[0usize].containers[0usize].condition.parts.len != 2usize { os.exit(19) }
    if c.rules[1usize].containers.len != 1usize || c.rules[1usize].containers[0usize].has_name || c.rules[1usize].containers[0usize].condition.op != container.Op.Gt { os.exit(20) }
    if c.rules[2usize].scopes.len != 1usize || c.rules[2usize].scopes[0usize].starts.len != 1usize || c.rules[2usize].scopes[0usize].limits.len != 1usize { os.exit(21) }

    // #1187: a name without a condition is invalid, so its declaration cannot become global.
    let guarded = "@container sidebar{a{--outside:1}} @container (width > 10px){b{--matches:1}} @container (width > 1000px){c{--misses:1}}"
    let (guarded_sheet, guarded_error) = sheet.parse_sheet(a, sheet.media_env(800.0f64, 600.0f64), guarded)
    if guarded_error != ok || guarded_sheet.rules.len != 2usize { os.exit(47) }
    if count_with(guarded_sheet.rules, "--outside") != 0usize || count_with(guarded_sheet.rules, "--matches") != 1usize || count_with(guarded_sheet.rules, "--misses") != 1usize { os.exit(48) }
    let guarded_size = container.Size { has_width: true, width: 20.0f64, has_height: false, height: 0.0f64 }
    if !container.matches(guarded_sheet.rules[0usize].containers[0usize].condition, guarded_size) { os.exit(49) }
    if container.matches(guarded_sheet.rules[1usize].containers[0usize].condition, guarded_size) { os.exit(50) }

    // #1188: an explicit invalid scope selector is not the implicit root scope.
    let scoped_guard = "@scope (::before){a{--scope-outside:1}} @scope (.card){b{--scope-card:1}} @scope to (.limit){c{--scope-implicit:1}} @scope (.card) to (::after){d{--scope-limit:1}}"
    let (scoped_guard_sheet, scoped_guard_error) = sheet.parse_sheet(a, sheet.media_env(800.0f64, 600.0f64), scoped_guard)
    if scoped_guard_error != ok || scoped_guard_sheet.rules.len != 2usize { os.exit(51) }
    if count_with(scoped_guard_sheet.rules, "--scope-outside") != 0usize || count_with(scoped_guard_sheet.rules, "--scope-limit") != 0usize { os.exit(52) }
    if count_with(scoped_guard_sheet.rules, "--scope-card") != 1usize || count_with(scoped_guard_sheet.rules, "--scope-implicit") != 1usize { os.exit(53) }
    if scoped_guard_sheet.rules[0usize].scopes[0usize].starts.len != 1usize || scoped_guard_sheet.rules[1usize].scopes[0usize].starts.len != 0usize || scoped_guard_sheet.rules[1usize].scopes[0usize].limits.len != 1usize { os.exit(54) }

    // #1189: failure to extend the context cannot turn a nested group into an
    // unconditional rule. The extension reports its allocation failure instead.
    var tiny_storage: [1]u8 = zero
    var tiny_arena = mem.arena_from(tiny_storage[..])
    var tiny_loader: sheet.Loader = zero
    tiny_loader.a = &tiny_arena
    var tiny_ctx: sheet.Ctx = zero
    let (container_ctx, container_error) = sheet.with_container(&tiny_loader, tiny_ctx, zero)
    if container_error == ok || container_ctx.containers.len != 0usize { os.exit(55) }
    let (scope_ctx, scope_error) = sheet.with_scope(&tiny_loader, tiny_ctx, zero)
    if scope_error == ok || scope_ctx.scopes.len != 0usize { os.exit(56) }

    // Every grouping kind can nest, and the rule keeps the accumulated context.
    let nested = "@media (min-width: 1px){@supports (display: grid){@container (width > 10px){@scope (.card){@layer nested{a{--nested:1}}}}}}"
    let (nested_sheet, nested_error) = sheet.parse_sheet(a, sheet.media_env(800.0f64, 600.0f64), nested)
    if nested_error != ok || nested_sheet.rules.len != 1usize { os.exit(40) }
    if !nested_sheet.rules[0usize].has_layer || nested_sheet.rules[0usize].containers.len != 1usize || nested_sheet.rules[0usize].scopes.len != 1usize || count_with(nested_sheet.rules, "--nested") != 1usize { os.exit(41) }

    // The loader refuses a 17th grouping level instead of recursing without bound.
    var deep_bytes: [4096]u8 = zero
    var deep_arena = mem.arena_from(deep_bytes[..])
    let (deep_builder, deep_build_error) = str.builder(&deep_arena, 4096usize)
    if deep_build_error != ok { os.exit(42) }
    var deep_out = deep_builder
    var deep_levels = 0usize
    while deep_levels < 17usize {
        let open_error = str.push(&deep_out, "@layer x{")
        if open_error != ok { os.exit(43) }
        deep_levels += 1usize
    }
    let body_error = str.push(&deep_out, "a{--too-deep:1}")
    if body_error != ok { os.exit(44) }
    deep_levels = 0usize
    while deep_levels < 17usize {
        let close_error = str.push(&deep_out, "}")
        if close_error != ok { os.exit(45) }
        deep_levels += 1usize
    }
    let deep_source = str.done(&deep_out)
    let (_deep_sheet, deep_error) = sheet.parse_sheet(a, sheet.media_env(800.0f64, 600.0f64), deep_source)
    if deep_error != sheet.TooDeep { os.exit(46) }

    // Fonts, keyframes, @property, @import.
    let misc = "@import url(\"a.css\"); @import 'b.css' print; @import \"c.css\" screen; @font-face{font-family:'Foo';src:url(a.eot) format('embedded-opentype'), url(a.woff) format('woff'), url(a.woff2) format('woff2');font-weight:700;font-display:swap} @font-face{font-family:Bar;src:url(b.woff2) format(\"woff2\"), url(b.ttf)} @keyframes spin{to{transform:rotate(360deg)} from{transform:rotate(0)} 50%{opacity:.5}} @property --x{syntax:'<length>';inherits:false;initial-value:0px}"
    let (x, xe) = sheet.parse_sheet(a, sheet.media_env(800.0f64, 600.0f64), misc)
    if xe != ok { os.exit(22) }
    if x.imports.len != 2usize || !str.eq(x.imports[0usize], "a.css") || !str.eq(x.imports[1usize], "c.css") { os.exit(23) }
    if x.fonts.len != 2usize || !str.eq(x.fonts[0usize].family, "Foo") || !str.eq(x.fonts[0usize].url, "a.woff2") || !str.eq(x.fonts[0usize].weight, "700") || !str.eq(x.fonts[0usize].display, "swap") { os.exit(24) }
    if !str.eq(x.fonts[1usize].family, "Bar") || !str.eq(x.fonts[1usize].url, "b.ttf") { os.exit(25) }
    if x.keyframes.len != 1usize || !str.eq(x.keyframes[0usize].name, "spin") || x.keyframes[0usize].stops.len != 3usize { os.exit(26) }
    if x.keyframes[0usize].stops[0usize].offset != 0.0f64 || x.keyframes[0usize].stops[1usize].offset != 0.5f64 || x.keyframes[0usize].stops[2usize].offset != 1.0f64 { os.exit(27) }
    if x.properties.len != 1usize || !str.eq(x.properties[0usize].name, "--x") || x.properties[0usize].inherits || !str.eq(x.properties[0usize].syntax, "<length>") { os.exit(28) }

    // Semantic token names are decoded in declaration values, including hashes and an escaped URL function name.
    let escaped = "a{width:\\63 alc(50px);height:10\\70 x;color:#\\66 0f;background-image:\\75 rl(\"foo.svg\")}"
    let (escaped_sheet, escaped_error) = sheet.parse_sheet(a, sheet.media_env(800.0f64, 600.0f64), escaped)
    if escaped_error != ok { os.exit(29) }
    if !str.eq(value_of(escaped_sheet.rules, "width"), "calc(50px)") || !str.eq(value_of(escaped_sheet.rules, "height"), "10px") || !str.eq(value_of(escaped_sheet.rules, "color"), "#f0f") || !str.eq(value_of(escaped_sheet.rules, "background-image"), "url(\"foo.svg\")") { os.exit(30) }

    // A long escaped custom-property value is decoded with bounded retained storage.
    var source_bytes: [16384]u8 = zero
    var source_arena = mem.arena_from(source_bytes[..])
    let (source_builder, source_error) = str.builder(&source_arena, 16384usize)
    if source_error != ok { os.exit(31) }
    var source_out = source_builder
    let open_error = str.push(&source_out, "a{--x:")
    if open_error != ok { os.exit(32) }
    var repeats = 0usize
    while repeats < 256usize {
        let piece_error = str.push(&source_out, "\\61+")
        if piece_error != ok { os.exit(33) }
        repeats += 1usize
    }
    let close_error = str.push(&source_out, ";}")
    if close_error != ok { os.exit(34) }
    let long_source = str.done(&source_out)
    var token_bytes: [1048576]u8 = zero
    var token_arena = mem.arena_from(token_bytes[..])
    let (long_tokens, token_error) = syntax.tokenize(&token_arena, long_source)
    if token_error != ok { os.exit(35) }
    let (long_rules, rule_error) = syntax.parse_rules(&token_arena, long_tokens, true)
    if rule_error != ok || long_rules.len != 1usize { os.exit(36) }
    let (long_decls, decl_error) = syntax.parse_declarations(&token_arena, long_rules[0usize].block.inner)
    if decl_error != ok || long_decls.len != 1usize { os.exit(37) }
    var decoded_bytes: [32768]u8 = zero
    var decoded_arena = mem.arena_from(decoded_bytes[..])
    let decoded = syntax.decoded_text(&decoded_arena, long_source, long_decls[0usize].value)
    if decoded.len != 512usize || decoded[0usize] != 97u8 || decoded[1usize] != 43u8 || decoded[510usize] != 97u8 || decoded[511usize] != 43u8 { os.exit(38) }
    if mem.mark(&decoded_arena) != 512usize { os.exit(39) }
    ret ok
}
