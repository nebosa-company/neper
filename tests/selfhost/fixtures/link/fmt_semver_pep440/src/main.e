// e.fmt.semver.pep440 against python packaging: version normalization and formatting, the total order,
// specifier sets with prerelease modes, and requirement-line acceptance. A line is `V|text|normalized`,
// `C|a|b|-1/0/1`, `S|version|specifiers|mode|1/0` (mode 0 auto, 1 allow, 2 deny) or `R|text|ok`; `E` is refused.
use e.io
use e.mem
use e.os
use e.fmt.semver.pep440
use e.str

fn field(line: str, index: usize) -> str {
    var at = 0usize
    var current = 0usize
    var start = 0usize
    while at <= line.len {
        if at == line.len || line[at] == 124u8 {
            if current == index { ret line[start..at] }
            current += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    ret ""
}

fn sign(c: i32) -> str {
    if c < 0i32 { ret "-1" }
    if c > 0i32 { ret "1" }
    ret "0"
}

fn allow_of(text: str) -> bool { ret !str.eq(text, "2") }

// The answer in the vector's own terms.
fn answer(a: *mem.Arena, line: str) -> str {
    let kind = field(line, 0usize)
    if str.eq(kind, "V") {
        let (v, v_error) = pep440.parse(field(line, 1usize))
        if v_error != ok { ret "E" }
        var buffer: [256]u8 = zero
        let (n, format_error) = pep440.format(v, buffer[0usize..256usize])
        if format_error != ok { ret "F" }
        let (copy, copy_error) = str.concat(a, buffer[0usize..n], "")
        if copy_error != ok { ret "M" }
        ret copy
    }
    if str.eq(kind, "C") {
        let (x, x_error) = pep440.parse(field(line, 1usize))
        let (y, y_error) = pep440.parse(field(line, 2usize))
        if x_error != ok || y_error != ok { ret "E" }
        ret sign(pep440.cmp(x, y))
    }
    if str.eq(kind, "S") {
        let (hit, hit_error) = pep440.contains(field(line, 1usize), field(line, 2usize), allow_of(field(line, 3usize)))
        if hit_error != ok { ret "E" }
        if hit { ret "1" }
        ret "0"
    }
    let (r, r_error) = pep440.parse_requirement(field(line, 1usize))
    if r_error != ok { ret "E" }
    ret "ok"
}

fn run(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let line = text[start..i]
            let mark = mem.mark(a)
            let got = answer(a, line)
            var want = field(line, 2usize)
            let kind = field(line, 0usize)
            if str.eq(kind, "C") { want = field(line, 3usize) }
            if str.eq(kind, "S") { want = field(line, 4usize) }
            if !str.eq(got, want) {
                let shown = io.print(line)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}
fn pep_vectors_0() -> str {
    ret "V| 1.1.1.r-0 |1.1.1.post0\nV|1.10.b10|1.10b10\nV|0.0.1.3r|0.0.1.3.post0\nV|10|10\nV|0.0.0.25|0.0.0.25\nV|v0.25.0.1a-1|0.25.0.1a1\nV|v0-b-2.post1+abc|0b2.post1+abc\nV| 10.25.2.0 |10.25.2.0\nV|0-4dev4|0.post4.dev4\nV|1.10.2.2|1.10.2.2\nV|10.10.2.10|10.10.2.10\nV|1!0.1.0+x.abc.1|1!0.1.0+x.abc.1\nV|0.2.0.3+x-abc-20|0.2.0.3+x.abc.20\nV|0.0.0.10-rev-0+Local|0.0.0.10.post0+local\nV|1.3.3.25-RC-10|1.3.3.25rc10\nV|3.3.10_c1.dev.1|3.3.10rc1.dev1\nV|25.rev|25.post0\nV|0.25.3.25_DEV4|0.25.3.25.dev4\nV|0.0.10.3|0.0.10.3\nV|1!0.25|1!0.25\nV|2!0.25.0.10_a+ubuntu|2!0.25.0.10a0+ubuntu\nV|v1|1\nV|1.1.a_10-post-3|1.1a10.post3\nV|25.0.3.1-alpha.10|25.0.3.1a10\nV|0_alpha.dev-4|0a0.dev4\nV| 3_DEV4 |3.dev4\nV| 2!2.25.0.2 |2!2.25.0.2\nV|1.0.1.2-dev1|1.0.1.2.dev1\nV|0.25-0|0.25.post0\nV|2|2\nV|0.1.0.0_rev|0.1.0.0.post0\nV|v0.3.1.10|0.3.1.10\nV|0|0\nV|1.2-4DEV.4|1.2.post4.dev4\nV| 10 |10\nV|v2.0|2.0\nV|3.0.0.2+007.1.1|3.0.0.2+7.1.1\nV|25_rev|25.post0\nV|1.0_DEV1+Local|1.0.dev1+local\nV|1|1\n"
}

fn pep_vectors_1() -> str {
    ret "V|v10|10\nV|0!25.c.0|25rc0\nV|1|1\nV|1.1.1.1|1.1.1.1\nV|0.0.25.25-DEV.0+007|0.0.25.25.dev0+7\nV|2.0.10DEV|2.0.10.dev0\nV|2.0.25dev1+20_ubuntu|2.0.25.dev1+20.ubuntu\nV|10.3.0.0.post-3|10.3.0.0.post3\nV|2.0.10.c|2.0.10rc0\nV|2!1.3.0.3a-POST_DEV-0|2!1.3.0.3a0.post0.dev0\nV|25.0.2|25.0.2\nV|1|1\nV|10.25.25.1|10.25.25.1\nV|1.25.3.0.A-0|1.25.3.0a0\nV|1.0_DEV.4|1.0.dev4\nV|3!0.3.0.25|3!0.3.0.25\nV|v0-alpha10.dev.0|0a10.dev0\nV| 2.3.pre_0 |2.3rc0\nV|0.2.10.0|0.2.10.0\nV|0.1.0-3|0.1.0.post3\nV|25.3.1.alpha0r.1|25.3.1a0.post1\nV|3.0.3rev_dev-0+abc.ubuntu.007|3.0.3.post0.dev0+abc.ubuntu.7\nV|2.1.0pre.0|2.1.0rc0\nV|2-Beta10|2b10\nV|0beta1|0b1\nV|v0!25DEV-0|25.dev0\nV|0.2-preview-10+abc-x-ubuntu|0.2rc10+abc.x.ubuntu\nV|0.0-DEV.1|0.0.dev1\nV|0-4|0.post4\nV|3.25.10+20.ubuntu|3.25.10+20.ubuntu\nV|3|3\nV|3|3\nV|10DEV.1|10.dev1\nV|0.rev|0.post0\nV|2!10.3.25rc_10-POST.1|2!10.3.25rc10.post1\nV|25|25\nV|1.25.0|1.25.0\nV|1.dev-4+20|1.dev4+20\nV|3.25.3-beta.2|3.25.3b2\nV|v2.2.25rc1DEV|2.2.25rc1.dev0\n"
}

fn pep_vectors_2() -> str {
    ret "V|0.25b2|0.25b2\nV|10.10.1POST-3|10.10.1.post3\nV|3!0_b0|3!0b0\nV|0.c-1+abc-007-Local|0rc1+abc.7.local\nV|2.2.1-alphadev|2.2.1a0.dev0\nV|3.3.0.0|3.3.0.0\nV|0.1.1|0.1.1\nV|0.3.1|0.3.1\nV|v0.3.2.1.alpha1|0.3.2.1a1\nV|3!25.2.0.25|3!25.2.0.25\nV|3!0.0.0-4_DEV0|3!0.0.0.post4.dev0\nV|1.3|1.3\nV|3.1.25-Beta0.post|3.1.25b0.post0\nV|v3|3\nV|10.0.0.1+ubuntu|10.0.0.1+ubuntu\nV|25.0.2.2beta_0_DEV4|25.0.2.2b0.dev4\nV|3.25.2.1-alpha0|3.25.2.1a0\nV|1.0.10|1.0.10\nV|1.0.0|1.0.0\nV|2!2.0|2!2.0\nV|1.0|1.0\nV|2.0.0rc0_r.0|2.0.0rc0.post0\nV|1.0.1_pre-10|1.0.1rc10\nV|1.2.2.25_dev.0|1.2.2.25.dev0\nV|3-POST-dev-4|3.post0.dev4\nV|25_POST.0_DEV0|25.post0.dev0\nV|3!2.25.1.2|3!2.25.1.2\nV|3.10.3+007|3.10.3+7\nV|0.25.1RC_2-dev0|0.25.1rc2.dev0\nV|v10.10.3.1|10.10.3.1\nV|0.10.0.0|0.10.0.0\nV|3.10.2_DEV|3.10.2.dev0\nV|1!2.0.25|1!2.0.25\nV|3.0DEV.1|3.0.dev1\nV|v2.2_DEV4|2.2.dev4\nV| 1.1.10 |1.1.10\nV|3!1.10-a.10|3!1.10a10\nV|1-0|1.post0\nV|1.1preview|1.1rc0\nV|v25|25\n"
}

fn pep_vectors_3() -> str {
    ret "V|3.10.2.0|3.10.2.0\nV|3.3rc|3.3rc0\nV|0_Beta-1|0b1\nV|0!0.1.r|0.1.post0\nV|0.2DEV4|0.2.dev4\nV|1.10|1.10\nV|3!0preview-1|3!0rc1\nV|3.1.3a0|3.1.3a0\nV|10.post0|10.post0\nV|0.2.0b.10+007_20|0.2.0b10+7.20\nV|0.0.0_rev+007.20|0.0.0.post0+7.20\nV|0.25|0.25\nV|1|1\nV|0.a-10post|0a10.post0\nV|2|2\nV| 0alpha-0 |0a0\nV|1.0.1+x-Local-20|1.0.1+x.local.20\nV|25|25\nV|1|1\nV|1.1|1.1\nV|1_POST.0.dev-4|1.post0.dev4\nV| 2!3.25.2+ubuntu |2!3.25.2+ubuntu\nV|0.b-0.r.3|0b0.post3\nV|1.1rc10|1.1rc10\nV|1.3.dev-0|1.3.dev0\nV|3.10.2.10Beta-2|3.10.2.10b2\nV|1.2.3.1|1.2.3.1\nV|0-dev-4+Local_Local_007|0.dev4+local.local.7\nV|1_preview2_DEV.4|1rc2.dev4\nV|v0|0\nV||E\nV|1.|E\nV|.1|E\nV|1..2|E\nV|1.0+|E\nV|1.0+_x|E\nV|1.0a1.|E\nV|abc|E\nV|1.0.0.0.0.0.0.0.0|1.0.0.0.0.0.0.0.0\nV|1.0-|E\n"
}

fn pep_vectors_4() -> str {
    ret "V|1!|E\nV|!1|E\nV|1.0.post.1|1.0.post1\nV|1 0|E\nV|1.0+a..b|E\nV|1.0rc|1.0rc0\nV|1.0.dev|1.0.dev0\nV|1.0.post|1.0.post0\nV|v|E\nV|1.0-1-2|E\nC|1.2.2.25_dev.0|0!0.1.r|1\nC|10.3.0.0.post-3|10.post0|1\nC| 0alpha-0 |25.3.1.alpha0r.1|-1\nC|v3| 2!2.25.0.2 |-1\nC|1.0.post|1.0|1\nC|v2.0|3!0preview-1|-1\nC| 3_DEV4 |3.25.2.1-alpha0|-1\nC|1.25.0|10.3.0.0.post-3|-1\nC|1.3.dev-0|10.10.2.10|-1\nC|1.3.dev-0|3|-1\nC|0.2-preview-10+abc-x-ubuntu|3!1.10-a.10|-1\nC|25.0.3.1-alpha.10|1.2-4DEV.4|1\nC|1!2.0.25|2.0.25dev1+20_ubuntu|1\nC|0.10.0.0|v25|-1\nC|2.0.25dev1+20_ubuntu|10.post0|-1\nC|25.0.2.2beta_0_DEV4|v2.0|1\nC|0_Beta-1|25_POST.0_DEV0|-1\nC|1.0_DEV.4|0!25.c.0|-1\nC|0-4|0.2-preview-10+abc-x-ubuntu|-1\nC|3!0_b0|1.2.2.25_dev.0|1\nC|3.10.2_DEV|3|1\nC|0.2-preview-10+abc-x-ubuntu|v0!25DEV-0|-1\nC|3.1.3a0|0-4dev4|1\nC|v3|25_rev|-1\nC|v2.0|v25|-1\nC|0.2-preview-10+abc-x-ubuntu|v25|-1\nC|v10|1.2-4DEV.4|1\nC|v0|1.1.1.1|-1\nC|1.0_DEV1+Local|3!0_b0|-1\nC|3.25.3-beta.2|0.25b2|1\n"
}

fn pep_vectors_5() -> str {
    ret "C|0.c-1+abc-007-Local|1.25.0|-1\nC|3.10.2_DEV|3|1\nC| 1.1.1.r-0 |0.2.0.3+x-abc-20|1\nC|2|1.1|1\nC|3.25.3-beta.2|3.3.10_c1.dev.1|1\nC|3!0.0.0-4_DEV0|0|1\nC|25_rev|10.3.0.0.post-3|1\nC|2.0.0rc0_r.0|0!0.1.r|1\nC|0.0.0.25|0_Beta-1|1\nC|0_Beta-1|10.10.1POST-3|-1\nC| 2!2.25.0.2 |0-dev-4+Local_Local_007|1\nC|v0|1.dev-4+20|-1\nC|1.25.3.0.A-0|0.0.0.25|1\nC|2.0.0rc0_r.0|3.10.3+007|-1\nC|10.post0|1!0.25|-1\nC|10.10.1POST-3| 10.25.2.0 |-1\nC|0.0.25.25-DEV.0+007|v2.2.25rc1DEV|-1\nC|1|25.3.1.alpha0r.1|-1\nC|3.1.3a0|1.0.0|1\nC|1_POST.0.dev-4|3.3rc|-1\nC|1.0.0|25|-1\nC|2.0.25dev1+20_ubuntu|1.0.post|1\nC|25|2!10.3.25rc_10-POST.1|-1\nC|3.10.2.0|v0-alpha10.dev.0|1\nC|0.rev|2.0.0rc0_r.0|-1\nC|0.0.0.10-rev-0+Local|1.10|-1\nC|2.0.10.c|0.25-0|1\nC|v2.2_DEV4|1!2.0.25|-1\nC|0_Beta-1|1.10|-1\nC|3.25.2.1-alpha0|3.25.2.1-alpha0|0\nC|2.1.0pre.0|1.3.dev-0|1\nC|0!0.1.r|10.post0|-1\nC|1!0.1.0+x.abc.1|2.0.0rc0_r.0|1\nC|1.0|0!0.1.r|1\nC|v1|0.2.0.3+x-abc-20|1\nC|3.3rc|v0.3.2.1.alpha1|1\nC|0.3.1| 1.1.1.r-0 |-1\nC|0.3.1|v10.10.3.1|-1\nC| 10 |v2.2.25rc1DEV|1\nC|v0-alpha10.dev.0|0!25.c.0|-1\n"
}

fn pep_vectors_6() -> str {
    ret "C|0.0.1.3r|2|-1\nC|2!2.0|3!0preview-1|-1\nC|1.2-4DEV.4|1|1\nC|3.0.3rev_dev-0+abc.ubuntu.007|0.0.10.3|1\nC|1.dev-4+20|0.0.0.25|1\nC|3.25.3-beta.2|3!2.25.1.2|-1\nC|1.1rc10|0beta1|1\nC|0.1.1|0.0.0_rev+007.20|1\nC|v3|10.10.2.10|-1\nC|1-0|25.3.1.alpha0r.1|-1\nC|0.25-0|1.25.0|-1\nC|10.10.1POST-3|0beta1|1\nC|1.2.2.25_dev.0|3.3.10_c1.dev.1|-1\nC|1-0|2-Beta10|-1\nC|1|3!2.25.1.2|-1\nC|2.0.25dev1+20_ubuntu|0.25-0|1\nC|1.0.1.2-dev1|3.0.3rev_dev-0+abc.ubuntu.007|-1\nC|1.0.1_pre-10|1.0.dev|1\nC|1-0|v0-b-2.post1+abc|1\nC|3|3.10.2.0|-1\nC|3!0.0.0-4_DEV0|v0.3.2.1.alpha1|1\nC|3!0.0.0-4_DEV0| 0alpha-0 |1\nC|3!2.25.1.2|1!0.1.0+x.abc.1|1\nC|1.0_DEV1+Local|v10.10.3.1|-1\nC|25|1.10|1\nC|0_alpha.dev-4|3|-1\nC|2.0.0rc0_r.0|3.10.2.0|-1\nC|0.1.0-3|10.10.2.10|-1\nC|3!1.10-a.10|0-4dev4|1\nC|0.2.0b.10+007_20|0_alpha.dev-4|1\nC|2.0.10DEV|0.0.0.10-rev-0+Local|1\nC|3!0_b0|1.0.1_pre-10|1\nC|1.0rc|v10.10.3.1|-1\nC|1.1rc10|0.3.1|1\nC|0|0.3.1|-1\nC|1.0.dev|3|-1\nC|1.3|0_Beta-1|1\nC|3.25.10+20.ubuntu|1.25.3.0.A-0|1\nC|1.3.dev-0|0.0.1.3r|1\nC|2-Beta10|1.1.1.1|1\n"
}

fn pep_vectors_7() -> str {
    ret "C|v2.2_DEV4|25.rev|-1\nC|3.0.0.2+007.1.1|1_preview2_DEV.4|1\nC|3!1.10-a.10|1.1rc10|1\nC|0.b-0.r.3|0-4|-1\nC|25.0.2.2beta_0_DEV4|2.0.10DEV|1\nC|1.0.0|1.10|-1\nC|3.3.0.0|0.2-preview-10+abc-x-ubuntu|1\nC|3.10.2.10Beta-2|0-4dev4|1\nC|v1|v0-b-2.post1+abc|1\nC|1.dev-4+20|1.0.post.1|-1\nC|1|3!1.10-a.10|-1\nC|1.25.3.0.A-0|2!0.25.0.10_a+ubuntu|-1\nC|25_POST.0_DEV0| 1.1.1.r-0 |1\nC|0-4|v10|-1\nC|0.2.0b.10+007_20|2!2.0|-1\nC|0.c-1+abc-007-Local|0.0.0.25|-1\nC|0_alpha.dev-4|1!0.1.0+x.abc.1|-1\nC|25.0.2.2beta_0_DEV4|1_preview2_DEV.4|1\nC|2.0.25dev1+20_ubuntu|0.10.0.0|1\nC|0.25-0|1.0.dev|-1\nC| 10.25.2.0 |0.10.0.0|1\nC|0.0.10.3|0.2.10.0|-1\nC|0.25.3.25_DEV4|2.1.0pre.0|-1\nC|3.25.3-beta.2|v0.25.0.1a-1|1\nC|0.rev|10DEV.1|-1\nC|0.0.0_rev+007.20|1.dev-4+20|-1\nC|3!0.0.0-4_DEV0|1|1\nC|v1|3!0preview-1|-1\nC| 2.3.pre_0 |3.1.3a0|-1\nC|0.1.1|10.10.2.10|-1\nC|3.3rc|v2.2.25rc1DEV|1\nC| 3_DEV4 |v0!25DEV-0|-1\nC|3.10.3+007|1_preview2_DEV.4|1\nC|3.3.0.0|3.10.2_DEV|-1\nC|25_POST.0_DEV0|1.0.0.0.0.0.0.0.0|1\nC|1-0|3.25.3-beta.2|-1\nC|1.1preview|0.0-DEV.1|1\nC|3.3rc|0-dev-4+Local_Local_007|1\nC|2.0.0rc0_r.0|1.0.1.2-dev1|1\nC|v2.0|2.0.10.c|-1\n"
}

fn pep_vectors_8() -> str {
    ret "C|0.0.25.25-DEV.0+007|1|-1\nC|1.2.3.1|1.3.dev-0|-1\nC|1.1.1.1|3-POST-dev-4|-1\nC|0.25| 2!3.25.2+ubuntu |-1\nC|v1|1.3|-1\nC|1.0|v3|-1\nC|0.2.10.0|3|-1\nC|25.3.1.alpha0r.1|0.2-preview-10+abc-x-ubuntu|1\nC|3!0.0.0-4_DEV0|25|1\nC|2.1.0pre.0|3.10.2.10Beta-2|-1\nC|1|1.3.3.25-RC-10|-1\nC|v25|3!0.0.0-4_DEV0|-1\nC|0-dev-4+Local_Local_007|3!0.3.0.25|-1\nC|25.0.2.2beta_0_DEV4|1.1|1\nC|0.3.1|v0.3.2.1.alpha1|-1\nC|1.1rc10|0-4dev4|1\nC|25_rev|2.2.1-alphadev|1\nC| 2!3.25.2+ubuntu |1.dev-4+20|1\nC|0beta1|0!25.c.0|-1\nC|3.10.3+007|v10.10.3.1|-1\nC|1.1|25.3.1.alpha0r.1|-1\nC|10.post0|1.25.3.0.A-0|1\nC|0!25.c.0|1_POST.0.dev-4|1\nC|0.2.0.3+x-abc-20|25.0.2|-1\nC|0.2.0b.10+007_20|v3|-1\nC|v10.10.3.1|1.0.0.0.0.0.0.0.0|1\nC|3!1.10-a.10|1.0.dev|1\nC|10.10.2.10|3.10.2.10Beta-2|1\nC|3.25.3-beta.2|0.2.0.3+x-abc-20|1\nC|3.25.10+20.ubuntu|3.0.3rev_dev-0+abc.ubuntu.007|1\nC|v1|0.a-10post|1\nC|1.dev-4+20|3.10.2.0|-1\nC|0!25.c.0|3.10.2.10Beta-2|1\nC|2!1.3.0.3a-POST_DEV-0|2|1\nC| 2!3.25.2+ubuntu |25.3.1.alpha0r.1|1\nC|2-Beta10|3!0preview-1|-1\nC|1.0.1_pre-10|0.c-1+abc-007-Local|1\nC|3!2.25.1.2|1!2.0.25|1\nC|0_Beta-1|0.0.25.25-DEV.0+007|-1\nC|0-4|1.0.10|-1\n"
}

fn pep_vectors_9() -> str {
    ret "C|3.25.10+20.ubuntu|3.10.3+007|1\nC|0.2-preview-10+abc-x-ubuntu|0.3.1|-1\nC|0.10.0.0|v1|-1\nC|0!0.1.r|3.1.25-Beta0.post|-1\nC|3!0.0.0-4_DEV0|0.0.10.3|1\nC|v10|3.10.2.0|1\nC|0!25.c.0|1.1preview|1\nC|1!0.25|0.1.0.0_rev|1\nC|v0-alpha10.dev.0|v2.0|-1\nC|1.3.3.25-RC-10|0.0.25.25-DEV.0+007|1\nS|25.3|== 0.2.0.* , ~=0.2.3.r.1-DEV-0|0|0\nS|0.1.10.3|~=1.10.0-RC-rev.1|0|0\nS|1.0.25beta.0rev-1|<=3.25.3.0,~= 1a10dev-1|0|E\nS|10|~=1_preview.10,>10.1.0A,>=25.10.25.10-beta-2.POST.1|2|E\nS|0.1pre-0|>= 3-rev|1|0\nS|v25.25.2_DEV0|== 0.2.*,=== 1.0.post1,== 25.10.1_preview|2|0\nS|0.1.0.0c0|=== 1.0.post1|2|0\nS|0.0.25.2|<10.25.1_pre10-POST.1 , < 3.1.25.2_alpha.post.1DEV , ~= 0.1.dev|0|0\nS|v1.25a.2|< 25.3-rc10,~= 0.3|2|0\nS|25.25.10.1alpha|>10.3.rc_10post1|2|0\nS|10.1.1_b0-DEV1|>=3.2.1.c-2, <=1.0-RC_1, == 2.0.2.*|0|0\nS|2.0dev.1|>= 1.25rc-10, > 1.10.25.1.alpha-10|0|1\nS|1RC1.dev.0|>=0.0.3, ~=2.DEV-1|2|E\nS|1!2rev0|>=3,>=25_DEV1|0|1\nS|0+Local|===1.0.post1, >=0_DEV-4|0|0\nS|0.0.1.25-post|<25.2.0-POST_dev.1|0|1\nS|1.10.1.25_alpha.10-r-1|~= v3.2_dev0|0|0\nS|1.3.0.3-pre-post-0|!=2.1.1.3_dev,>=10.1.2,!=2.1.0.*|1|0\nS|0.1.1|>= 25_pre0, ==1.0.*, > 25.10|0|0\nS|1.1c_0|<0.1.0DEV0,>0.3.25alpha1,<3.0rc10-DEV|2|0\nS|0.0.post.0|<= 2.10.3.2|1|1\nS|1.0.3DEV.1|== 25.0.3|0|0\nS|2.0-RC1|<=0.0.25RC-post3 , >= 3 , < 1.0-alpha.2rev.3|0|0\nS|0.25.1.0_rc_10_dev-1|~= v25, >=10-DEV4, === 1.0.post1|0|E\nS|0.1A-0|< 1.0.1,~=0.10,===1.0.dev1|0|0\nS|3.10-rev-0|== 0.1.1.1-r-0-dev-0, >=1-pre.POST.1, ~=2.1-beta10rev|0|0\nS|0.1.3-r1|>= v1.25.1post|0|0\nS|3-r3|>= 10.3.DEV , ==10.1.0.1 , < 0_pre0_dev|1|0\nS|v1.0.1.3-cpost1|~= 3.10.2.25a, == 1.2.1.*|0|0\nS|2!3.0.1.25|===1.0, ~= 1.0, !=3.*|0|0\n"
}

fn pep_vectors_10() -> str {
    ret "S|0!3|> 0.25.0.25_DEV.0,~= v1,>=10.1.25|0|E\nS|3|>=10.2-POST0, ~=2-c_1_POST0_DEV.0, != 25.3.3_Beta1-3|0|E\nS|0.3.0|>= 0.0.0_rcdev, >=25.10.0DEV4|0|0\nS|3-4|== 3.0-rev0, <=10.2.0-dev0, == 10dev|0|0\nS|3.1.2.10|<0.2.beta.2-3_dev4|0|0\nS|0!0.10.2.r|>3.0.2A0 , >=1.25.0.0Beta.rev.0_DEV-4|2|0\nS|1.0.3b.0|<25.25.1|0|1\nS|0.3.0.25a-1-4|~=0|0|E\nS|0.25.3beta0.rev0+007_abc_1|<25.0.25.DEV,=== 1.0.dev1,<= 10.25|1|0\nS|1.25b.0|!=1.3.*|1|1\nS|0.3.3-alpha10|>=2.1.0.1.Beta.2-dev-1|0|0\nS|10.0.25.1|== 1.* , >0_A-10|2|0\nS|0.3.25.0-dev|~=25 , ==3.1.*|0|E\nS|0.0beta_POST0|>=2.1.0.1RC1 , ==2.0.0_pre0_POST-1+local.1|2|0\nS|1.r-1|==2.1.3.*,<3c_r_DEV.0|0|0\nS|10.0.0.0RC-1|==1.*+local.1|0|E\nS|3.1-DEV0|< 1.25.2.0.a.10|2|0\nS|1.1.0.2|~=1.0|1|1\nS|1-Beta_0|<10 , >= v2-preview.rev.3-dev|0|0\nS|0.Beta_10.POST-0|~= 3,===1.0a1,~=0.0.1.post.1|0|E\nS|2.10.DEV.1|> v10.1.0_b2-dev.0|0|0\nS|10.0.10-rc-2-post3|~=10.25.2 , >=1.0.1.1alpha|0|0\nS|0-c1|!= 1.0.3.*|0|1\nS|25.10.0.0|=== 1.0|0|0\nS|v0!0|===2.0.0,===1.0.post1|0|0\nS|2.DEV|<3.3.3|1|1\nS|1.25.1.1|<2,==3-0|1|0\nS|1.25|>10, >=3|2|0\nS|10.1-dev-1|!= 25.25.25|0|1\nS|1.1_dev-4|>=1.0|0|1\nS|0.0|~=1.1.0.0_a2post.DEV|0|0\nS|0.2.3.1|==2.2.0.*,<=1_pre,==25.25.10.1dev|0|0\nS|v1|==2-DEV|0|0\nS|3.c10|==10.0.1.10_pre-10_dev.4 , >25 , >= 3|2|0\nS|10.3.2DEV|<0.3|1|0\nS|1|==0.0.3.DEV0,>=0Beta.rev1|0|0\nS|1.3_post3DEV4|~=10.1.10.rev-1|0|0\nS|2!10.0b2|==10.2.0,~= 25.0.10.0c-DEV-0,~= 0.2.25.1.preview-0-post-3_dev0|0|0\nS|10b0|~=25.10.0-Beta-0-DEV, < 0.1-pre10-r.0|0|0\nS|3.b10|~= 0-DEV1 , >= 0.10.25-r-1 , >=3.1_alpha|1|E\n"
}

fn pep_vectors_11() -> str {
    ret "S|1!10DEV1|<3pre-0,===1.0.dev1,<=1.0-DEV-4|0|0\nS|3.0DEV-1|~= 3.2-2,>=10-rc_0.post,<1.0|0|0\nS|10.10.1.0_RC_0_r.DEV|<= 0.1pre_r , < 1.3_rev.0|0|0\nS|1.0preDEV.0|!= 25.0.0.0c2,==3.1.3.25+local.1,>= 3.1.2.1|0|0\nS|2|!= 0.* , == v0.0.a-10 , < 2.0dev-0|2|0\nS|0.r.1|<25,==2.0.0.*,== v0|2|0\nS|3.10.10|!=0POST0|0|1\nS|0.1.1pre.2|~= 0.3.3-alpha-10-3 , == 25.0|0|0\nS|3.0.alpha|==2.1|1|0\nS|1-dev.0|>=10.3.1.0, == 2, !=3.25.10.1.rev-0dev.4|2|0\nS|1_b-0|~= 0.0Beta.0,<= 0.3_DEV4,<=3alpha0|0|0\nS|1.2.10.1-POST1-dev-0|==3.1.3.a_0, <=0.0-pre10|1|0\nS|1.2.3|<= 0, >1.0.25.2, >1.10.10_c-DEV1|0|0\nS|10|<2.0Beta.2.DEV, >=0, ==0.3.0.2beta-0-post-0-dev1+local.1|0|0\nS|3.0.2alpha|~=0.0.25.0_a.2-DEV-0|2|0\nS|2.3.25.0.alpha|< 0DEV-0, <1.25.10.1-rc.10, ===1.0.post1|0|0\nS|0.1.0.0|~=1.0.2RC , ~=1.0 , >=1.10|0|0\nS|3.2beta|<0.dev4 , ~=1.25.rc|0|0\nS|3|==1.0+local.1|1|0\nS|1.1pre10.post|>=v0-pre.10|0|1\nS|10.25|<1.1-rc.1|0|0\nS|0.0-rev|=== 2.0.0|0|0\nS|3.2.3preview0-dev.4|==3.2.1.*, ~=1.0.10.2, <=1.0pre.2.dev-0|2|0\nS|0.2.pre1|~=2.10.0.3 , < 0.25.0_r , >1.3.1.1_alpha10|0|0\nS|2_rdev.0|=== 1.0.post1|1|0\nS|1.25.1|~=2.1-DEV|0|0\nS|0!2|>=1.10,< 0.25,~=10|0|E\nS|2.0_alpha_0|<0.10.10beta-2_dev,~=0.25.1.10|0|0\nS|3b_1|< 1.1-preview1 , ==3 , >1.25.0.1|0|0\nS|10.1.1|==3.1, <v1.10c_2|1|0\nS|0.25.0.0post-1|~=25|1|E\nS|2.3.3RC_10|>= 3.10.r,>= 25.1,<= 1.1.25.2.post0|0|0\nS|10.10|~=3.0, ~=0c2, <= 1.1-3|0|E\nS|10.0.1|==25.3.0-post.3,==1.0.1.2_beta+local.1|1|0\nS|25.1a_10|<=1.1.25-preDEV|1|0\nS|1.3.0.3|~=0.1.0, < 1.0.2-a.1r1, ~= 3.3.2.0|0|0\nS|0-dev.1|< 1.0c.1r1|1|1\nS|3.0-post0.dev-1|==3.*|2|0\nS|0.0.0POST|<0.0 , ~= 3.1.0 , === 1.0.post1|1|0\nS|3.dev4|~=25.1.10.0Beta_1-DEV , >= 25.3.2.0preview.2 , <=2.1.3rc_10|1|0\n"
}

fn pep_vectors_12() -> str {
    ret "S|0|> 3.10.3, >= 0a_rev.1|0|0\nS|1.3|<= 25 , ==3.3.*|0|0\nS|v10pre.2|<v0.3.0.2, != 3.3|1|0\nS|1.2.25_post|===1.0, == 0+local.1|0|0\nS|0.10|>= 2.1.10.10-DEV-4|1|0\nS|2.25.0_rev-0|>=0.10.10.10_beta|0|1\nS|1.25.post.1|>=0.2.1|0|1\nS|1.10.25|<v1.2.1.0_b.0|0|0\nS|1.0.1.2|~=0.0.3.10, ==1-DEV.1, >=0.25|2|0\nS|1.0.3r-1|<10_preview-0DEV, >1.10dev1, > 25r1|0|0\nS|1_a2|< 0.3.25.2-rev,>=2.0.10|0|0\nS|0.10.2.0post-1|>=0.10.0.1 , < 2.1.1_alpha2 , >=2|0|0\nS|0.3.25.25POST-0_dev-4|>=25, >=1.1.3, ==3.1.2.*|0|0\nS|1.0.1.a.1|!=0.1.10.1A-post.0|0|1\nS|2.2.0.10|>= 1.0.10.0.preview1-dev-1|0|1\nS|2-4|>=2.3-beta-2 , ==0.1.1.* , >= 0.0.2.3|0|0\nS|25a_1|===1.0|0|0\nS|1.2.3_DEV4|!=1.0,>3RC_2,=== 1.0|0|0\nS|v10.0.alpha-10|>=1.25.0b1post-3.DEV.4 , < 1.1.25.3 , <3.10.25-dev.1|0|0\nS|10.10_b10|<=0.0preview.2,>10.POST1.dev-0,>2.10-rc1|0|0\nS|v25.beta2|>= 1.2.25.0A-1r.0, >=25.2|0|0\nS|25.0|< 0, ~=25, <= 1.10.1rev.1|2|E\nS|2.beta|!= 1.25,<2.25.10.0-DEV.4,==2.0|2|0\nS|1beta-0-post3|<=1.0.2.1 , ==0-3|2|0\nS|2-0|!=10.1_DEV-0,< 1.25|0|0\nS|0!25.1.0.0|< 3.0|1|0\nS|v0.10|< 1.3.0-DEV-4,==25a-1,~=2.1.1.10|0|0\nS|0.0|<= 3.0.2.a1, >= 0.0.10-dev|2|0\nS|10.1.1.10-rc10|~= 10.0.25.3-0|2|0\nS|2.1.0.0_b|<=3.0.0_alpha-1-2 , ===2.0.0 , <= 0|2|0\nS|10|== 2.0.*|1|0\nS|2.25-Beta-10POST.3dev-1|>= 0.1.25.2|2|0\nS|3!0.1.10.0DEV|<= 2.3.0|2|0\nS|0.1.3|=== 1.0|1|0\nS|v25.10.1.2.post.3|< 25.10A.0,<1rev-1,>=v0-beta1|0|0\nS|1-beta-1|==10.3.10.0-3dev.1 , !=1.3.3 , !=10.10|1|0\nS|25.1DEV.4|===1.0|0|0\nS|10.25.1_dev|~=0.1r-3DEV4,>=0.2,== 10.2|0|0\nS|v0.3.10.3.beta_dev|<=25 , >=0.10.25.0-0|0|0\nS|0.10.1.2.r0|==3.0.*, ~=1.10.1.25_RC, ~=1_RC0|2|E\n"
}

fn pep_vectors_13() -> str {
    ret "S|0.2.10.0|~=2.2.3.2|1|0\nS|0.1.DEV-4|!= 1.1.3-a-10+local.1,!=2.2.2.*,>=25.0.2_a|0|0\nS|1.10|<1.25.1_r,!= 0.2.0.3-dev.4,== 2.1.*|0|0\nS|1.3|==3.2.1RC1-dev , !=3.* , >25.1.1.2_rc10|0|0\nS|1.25.25|!=2.1.0.*|0|1\nS|3.0.10beta2|~= 1.1.beta-1POST.0|0|0\nS|3b2-post0-dev1|>0.0.1.0|0|1\nS|0.1|>=0 , ~= 1.3.3.1|0|0\nS|10.0.1.1-b0|<=3RC1.DEV.4,>=0.10.3.3_b1,~=0.25.3alpha_0DEV.4|2|0\nS|10Beta-2|!=2.0.0.1beta2-post.1, == 1_alpha10|0|0\nS|0.25.2.rev.1|>=2.2_beta_0, ~=2.25.dev-0|0|0\nS|1-1|~=0.2c0|1|0\nS|1.3.1_DEV|>= 1.25.0, === 1.0.dev1, >=3.0_dev-0|2|0\nS|10DEV|>= 2.2c_1|0|1\nS|0.2|~= 2.25.2.10,>=0.b-rev-1|0|0\nS|2.1.2.1RC.0.dev-0|~= v1.2.10 , == 0.1.0.*|1|0\nS|25|<= 25.0.0.1_post0|0|1\nS|3.10_rev|> 1, ===1.0|0|0\nS|0|~= 10.2.10.0, ==0.3.2.*, ===2.0.0|0|0\nS|1.10.1.0|> 10.25.0.10, < 1_post-0|0|0\nS|v2.3.0|!=10_revDEV-0,===2.0.0|2|0\nS|25r.1|>= 10.0.3.2RC_2DEV-0|2|1\nS|1.2.2.10|~=25|2|E\nS|1.0.2-rev3|<2,>= 1.0|0|1\nS|25.0_rc2_post1|>=0.1-POST.0 , < 3.0_beta1_post-DEV-4 , >=0.10.25.10.preview.10-DEV0|2|0\nS|1.1|<3.10-1dev4,=== 2.0.0,>10.25.2.0|2|0\nS|25-rev1|<= 1.1.25.3.beta10POST1, ~=1.2.25.1|2|0\nS|0|== 0.10.1A10,==1-DEV1,<=1.0.0|0|0\nS|2.0.0|~=25.1.25_dev-1,~= 2|1|E\nS|3.25.3_c_1|< 2.10.1-3.dev|1|0\nS|0.25.25_DEV-4|===1.0.dev1|1|0\nS|3|~=0.0.10-1 , == 3.1.2.1.dev-0|2|0\nS|2.0.0.r|== 0.3.2.* , ~=1.0.DEV.4 , <=1_beta_1-post-3.dev4|2|0\nS|3.1_alpha0|==10.0pre , ===1.0.dev1|0|0\nS|2.10.0.25.rev|<v3.1.25.3.DEV.1,>= 10_pre-1-DEV-0,== 1-post|2|0\nS|0!25DEV.0|!= 0.3.2.* , <=1.0.3.0.DEV1|1|0\nS|1.0.3.25|~=10.3.2_DEV|0|0\nS|3-post0|>=3.3.0alpha2, === 2.0.0, ~=25.3.25|0|0\nS|0.0.0.2_c_10|===1.0.post1 , == 25.10.1.1A_1+local.1|1|0\nS|0.0.0|!=1.2|1|1\n"
}

fn pep_vectors_14() -> str {
    ret "S|1.r|!=0.2-RC , >=1.0_alpha-10 , < 3Beta2|0|1\nS|10|!=3.25.1.Beta.post|0|1\nS|0beta.2|~=3.c, >= 1.0.1, ==1.1.0|2|E\nS|0.25.1|<25.1.0DEV, <=2.25.0, >=25.0.3.0.DEV4|2|0\nS|2.beta2r-0|>=10.2.0RC.2,!= 1.3_dev-1|0|0\nS|v3.1.rev-1_dev-1|<= 1.1_POST,!=25.0a1|1|0\nS|v1.1.25_rc|!= 1.25.3-post.0|0|1\nS|10.2-dev1|== 25.1.10.25.beta-10 , != 10.0 , <=1.0|0|0\nS|25.3.r-3|===1.0.post1|0|0\nS|10.10.25DEV-4|<=3.25.25|2|0\nS|0_alpha.1|>=10.10.25.1,~= v3.0-DEV-4|0|0\nS|1.0.1preview|==2.post, === 1.0.dev1, <=1.25.1.2-rc0_dev-1|0|0\nS|0_dev-0|~=25.25.25.3 , <3.10.1.1|2|0\nS|3.1.25.0b0|== 0.*+local.1,~= 25.25.0.2.DEV-4|2|E\nS|0.1.25|<=0.1_rc10, <=3.1.25|0|0\nS|1.25.2|~=10.2.1.10_RCdev-1,!=2A2_DEV|0|0\nS|v1.2.3.2-r.0|>1.0.3.1-0,== 25.25.10_alpha-1_DEV-0+local.1,>= 10.1|0|0\nS|2.0.0.1beta-2|<= 0.3-DEV, == 0.25.0.0, ==25.0.0|2|0\nS|1c.1-dev-0+007-20-abc|!=0.2.1.*|0|1\nS|1.1.10|>=25.3.3, == 0.0-DEV, >=25.25pre1|0|0\nS|25.2.3|!=3A_10dev-1,==1.3,>=1.0.25.10|0|0\nS|0post3|<0.0a_POST0_DEV-0 , <= v3|0|0\nS|3.1.0.2.DEV.4|==1.1.0.25-POST3-DEV-0 , ~= 25|2|E\nS|v25.2-post.1|===1.0a1|2|0\nS|10.1.3.3-RC-10|>= 0.10.3.0, >= 25|2|0\nS|0.1.0.3.DEV.4|~= 0bdev , ~=10 , ===1.0|0|E\nS|1_POST1|===1.0 , ==10.25.2.3 , >3.1|0|0\nS|25.3.2.A_10|<= 25alpha.0-post.1, ===1.0|0|0\nS|25beta-2|===1.0.dev1,!= 1|1|0\nS|0.1.10.10-A.DEV.4|>25.0.0-A10.dev|1|0\nS|10.0.3.3pre2|> 1.1,===1.0.post1,==1.10.0.0-a2.r1|2|0\nS|0.1.1A0|<10.0.2.1beta1.dev4, !=1.25.1_dev, == 0dev.0|1|0\nS|1.2.0.1.pre.0-3_DEV.4|~=0.0alpha_10-r.1|0|0\nS|2.1.rev-1-DEV1|~=2,>10|0|E\nS|0.2.2POST-3_DEV-0|==2 , ~=v10.25-a , <= 0.0.1r|2|0\nS|1.c|== 3.0.25_DEV-0|2|0\nS|0|>=25, ===2.0.0|0|0\nS|3.2.1_preview_10.DEV|<= 1.3.2.3POST0.dev.4 , >=2.10.1alpha-2|1|0\nS|1.1|< 0.3dev1|1|0\nS|2.1.25|>v1.2.0_DEV,<=1.0.1.10|0|0\n"
}

fn pep_vectors_15() -> str {
    ret "S|10.0dev-1|>=1.1|1|1\nS|1.10.0.1|>=10.25.0.A.1 , ==25 , > 1.0.10.0|0|0\nS|10.25.10.2|== 2.1.2.*|0|0\nS|1|===1.0, >25.1.0.25.post, ==1.2.10.2|1|0\nS|1_DEV|~=0.10.0|2|0\nS|25.1|~= 0.1.10,!=2.0,==3.*|0|0\nS|25.25.1.25_rev.1.DEV.0|<0.1-preview-r3.dev0, !=2.0preview0, ~=10.0.1|0|0\nS|1!2.1.10|== 10.10.0Beta-10+local.1 , !=3.2.* , >3-r3|0|0\nS|0.1|~=10,==1.3.0.2_dev-4|0|E\nS|10.3.3.2|~=0.0.1preview_10|0|0\nS|1.1.3.0|==25.1+local.1|0|0\nS|v2.1.1.10.a.r.1|~=0.0.1_A.2.rev-3dev, >=3.0|1|0\nS|v2.0.1.0-c_0-dev|===1.0.post1|0|0\nS|1.2.3-alpha10|~=0_DEV-4,< 25.25A-dev|2|E\nS|2.0RC2|=== 2.0.0|0|0\nS|0.1|<= 0.3.0.1,==1.0.*+local.1,~=1.3.3.2.DEV.1|0|E\nS|3.0.1.10-DEV0|< 1.A_1,>10,=== 1.0a1|1|0\nS|0.3.2.1_rc.0|!=10.1.2.10-dev-4 , ===1.0.dev1|0|0\nS|3.rev|<=1.0.0.25.DEV, ===1.0.dev1|0|0\nS|1r0_dev-4|!=1.1.2.3, === 2.0.0, >=10.1.1.1|1|0\nS|v0.0.1|~=0_rc_10|0|E\nS|1.0c-POST3_dev|==2.1.1,<v25.0.A,!=0.0.3.1beta0|0|0\nS|10.3.0.0alpha.0|===2.0.0|0|0\nS|1!3.1pre-10-post1|~=0.25.3 , ===1.0a1 , ~= 1.3.3-A_10post-0_dev-1|2|0\nS|25.0.POST|< 0DEV1,>0.25,~= v3|1|E\nS|v0a.2_DEV1|~=1beta2 , ~=0_A2|0|E\nS|0.25.1|<= 25 , >=3|0|0\nS|0.1.2.3|=== 2.0.0,>=25.10-rev-0,~=0.1.1|0|0\nS|10.0.0|>=25.2.0|0|0\nS|1.10.rc|>=v2.10.10.3.RC1DEV1|1|0\nS|3.25.1a-1_DEV1|== 25|0|0\nS|v25.1.0.25b_0|== v3.1.25A-2|1|0\nS|2.3.2-rev|==10.10.3.3 , >0.0|0|0\nS|0.10.10.0-rc|>=0.1.3RC-dev1,=== 1.0.post1|0|0\nS|1Beta_10|>=0.1.0preview10post1,==1.1.2.0a2.DEV0,>25.1.10|2|0\nS|1.0.0-r|~= 1.10_POST1dev|0|0\nS|1.1.10pre_0|< 0.1preview-2, < 0.0.2.10.Beta-2|0|0\nS|0.0.POST|>25.0.3.1, !=0.2.0.10.r|0|0\nS|v1.0|<1.1-RC, <=1|1|1\nS|0.2.10|<0, !=1, <10.25.10.1|2|0\n"
}

fn pep_vectors_16() -> str {
    ret "S|10|<1.1|0|0\nS|1c2_rev.3|!= 3.0.*,>=10.2.1.0_r.0-dev,~= v25.1.1|0|0\nS|10.3.0.10.rev-1|===1.0.post1, > 0.25.0|1|0\nS|1.3.1.1_DEV0|<=1.0_DEV.1,< 25.10.10.r0|0|0\nS|0.0.0|!=v0.3.0.0_POST0,!=v1.1.0alpha,< 1.1.rev.1|0|1\nS|1|>= 25.1 , ~= 3.0.2_beta_1 , ~=3RC-10DEV|0|E\nS|0.2.3|!=10.1.10.1, >= 3.10.0.0.POST0|0|0\nS|0.3.10_a|> 1.1.25_preview2,==0.rc_2|0|0\nS|25.10|~= 0 , >= 10.0.1.1 , > 0.3|0|E\nS|10.1.10.2b.1|~=0.1-rc10|2|0\nS|1.25.1.2.rev-1|~= 0.1.0.2-Beta_2,~= 3.10.3|1|0\nS|1.0.3_r-0|>0.2-post,=== 1.0,< 1c_2.DEV-1|2|0\nS|v1.DEV.0|~=0.10A.1DEV.4,<=10.25-2,<10.10.1|0|0\nS|0.1.1.1|~= 2A2-dev.4,<0.1.10_rev.0_DEV,==3.25.25+local.1|2|E\nS|2|<=0.0-2,> 3.0.25.1.dev.0,>25|0|0\nS|1.1.0.3DEV1|== 2.10.1.0.r,==0.*|0|0\nS|0!3.0.0-1|>2POST.3|1|1\nS|3.0.3.1|<=2.3|2|0\nS|1.1.25.10b1|>= 0.0.25.25-post0|0|1\nS|3.2.b-2|==0.1_dev , ==10.3-2|1|0\nS|25_DEV-0|~=2.3post, <10.1.1|0|0\nS|0.3|<10preview-2-dev|0|1\nS|1.10|== 2.3.post.3,===1.0a1,~=2.1.2-b0|0|0\nS|25.1.2.Beta.2|==2.2+local.1,~=0.10.1,<3.25.2.r-3|2|0\nS|0.1dev|<10.2.1preview_DEV4, == 1dev-0, == 25_dev4|0|0\nS|0.10.1|>= 10.3.1.2-0_DEV-1|0|0\nS|0.10DEV-4|== 10_preview2, ~= 1|0|E\nS|2.3.2.post.3-DEV|~=2.1.2.10r-0,!=0.10-post_dev.1,>=0-pre|0|0\nS|10|>3|0|1\nS|0|>1.3.0.1, ~= 2.25.2.10b, ~=1.25.0A|0|0\nS|1.2.2.10|< 3.2.1.2.r-0 , <25.c0-post|1|1\nS|10.1.1.3preview.DEV.4|==1.1.*,>1.3.3|2|0\nS|v1rc|>25.0.0-1|2|0\nS|0.0.1.25.post-3|>=3.10 , ==0.2 , >=3.beta.2_r.1|0|0\nS|2.10.25.10post|==0.25.1.25beta-1, > 2.0, !=0.0beta.1|0|0\nS|v1.DEV.1|> 10.3.1.1|1|0\nS|25.1.25.1A_2.rev-dev1|>= 0.2_r.DEV|0|1\nS|1.3.1.10|<25.1|0|1\nS|25.0|<1|0|0\nS|1_post3|==0.1.2.*+local.1|1|E\n"
}

fn pep_vectors_17() -> str {
    ret "S|2!1.2.0_POST-0|==3.1.1-0|0|0\nS|2.3.0.25|~=1.1.1|0|0\nS|v25-POST-3|~=v1.25.0beta.10|1|0\nS|1.3A1-POST|~=3.0-Beta0,<=3.10.0.3,=== 1.0a1|0|0\nS|0.b_1dev.0|!= 25.0+local.1 , <25.1beta10|0|1\nS|25.0.1pre_10_DEV.1|< 25.1.0.DEV-4|0|1\nS|v0.25.25-A-1|>=25.0,~=1.0|0|0\nS|1|=== 1.0.dev1, < 0.3.10.3|0|0\nS|0.10.3.1_alpha.10|> 25.1.25.1.rc2, ~=0.3.0.10r_dev-4|0|0\nS|1.1.25beta.0|>=1.10.1alpha10_post , ~= 0.2.25dev1|0|0\nS|1|>=3.3.10preview10|1|0\nS|2Beta|~=10.25.0|0|0\nS|25.2_a.dev|>0-rev.0, ~=10.25, ==2.2.2.*|0|0\nS|1|<= 1POST , <3.3_dev.0|1|1\nS|1|>=3.25.25|0|0\nS|2.0RC|===1.0.dev1 , <= 0.3.1.10-DEV.1 , ~=3.0|0|0\nS|10.1|!=1.25.10_dev.1 , ~= 1 , <1.3.0.0preview.10-post|2|E\nS|2.25.2.10-2|==3.0.2.25.Betapost-0, >= 25, ==1.1.2.0_DEV|0|0\nS|1.1-rc_0|==1_r-0_DEV+local.1|0|0\nS|3alpha10POST.3|==1.0.* , ~= 1.RC.2 , <10.1-A_0r-0|1|E\nS|3.3.25-beta|== 1rev.3DEV0|1|0\nS|0.2.0-dev.1|== 1.25-RC.0|1|0\nS|3|>=2|1|1\nS|v3.2.1|=== 2.0.0|0|0\nS|1.1.b-10|<3-beta_1.POSTdev4|0|1\nS|0_alpha.2-post|~=1.r3,<= 3.1|1|E\nS|v1.0.1.rDEV1|<1.1-b-10-rev-0 , ==2.*+local.1 , >1.2.1-3|0|E\nS|3.1.b.2rev0|> 10.3.0.0.r , ~= 25|0|E\nS|0.1.3.2Beta.2-4|== 1,~= 1.0.2c0r.0|0|0\nS|25|>=1.0.0alpha.2 , ==2.10-POST-3|0|0\nS|3!10.1+abc_ubuntu|!= 0.3.1_post+local.1,<2-pre0_dev-0|0|0\nS|25|!= 2.2.1.*|0|1\nS|25.rev0|== 1.25, >= 2.2.2, ~= 3|0|E\nS|3.1|< 10_rc_0,< 0.0.1.POST-0.DEV|0|0\nS|1.1.3r|===1.0.post1,~= 10|1|E\nS|0.1.1|!= 10,!=2.3.*,<10|0|1\nS|v0.1.0|~=2dev1,~=25.1.10.25|0|E\nS|2!1.dev.1|<0.1.25|0|0\nS|1|!=1.25.10pre-1_dev1|2|1\nS|25.0.0.0|>0.10.0.0_alpha-2_dev-4|0|1\n"
}

fn pep_vectors_18() -> str {
    ret "S|0-c|~= 1DEV-4,!=2.2.*,>=0.10.25.25_A2|0|E\nS|25.10.10_DEV.0|<= 0dev4|2|0\nS|v25.1.10.25-r-0|>=2.0_POST0|0|1\nS|10.1-b-0|==25.1.1.10-DEV1|0|0\nS|3.1.3|< v0.3.0preview10,<= 1DEV-4,<0.25.0.25|2|0\nS|0.0.3.0.dev-1|==2.3.3.*|1|0\nS|0.1.1.1|~=0.2.3_a_1|1|0\nS|1.25.3preview-0|<2.25.10|0|1\nS|1.2.3.0_post.1|< 1.1|2|0\nS|10.25.3-postdev.0|<0_A_0|0|0\nS|25.2.0|!=3.1_A-0_dev,~= 0.1.1.1.beta-0-0dev.0|2|0\nS|3.dev-1|<1.rc_dev.1, < 1.10.0.25|2|0\nS|v3.0.0.1-r|>= 0.10.1_pre , == 0.2-alpha10-DEV4|1|0\nS|0.0.2dev0|> 0.25_preview.10, ~=25.3, <0.2.3|0|0\nS|25.1Beta10|< 2A , != 3.2.1.*+local.1|0|E\nS|1.1+007|!=1-a0,>=v0.1,~= 10|0|E\nS|2.25.1_c.0|<= 10.1.0.25|0|1\nS|v1|<0, >2c_1.DEV1, ~=3.3|2|0\nS|1b_1|!=10.0.2.1-2, ==1.1.1.*, == v10.beta0.post0|0|0\nS|v0.25.1-dev0|~=0.1r1, >=v25.3.2.0|1|0\nS|10.rev-0|=== 1.0.post1, >0_pre_2, ==25.0.3.3_Beta_1-4|0|0\nS|3!0.0.10.1|~=2alpha-10,!=1.0.1|0|E\nS|3-1|<0.25,>=1.1.0.2,~=25.1.2.3-b1|0|0\nS|1.10.3.0.DEV.0|~= 0.0,==10|0|0\nS|10.0arev.1|>=1.1.25.25Beta_10 , ===2.0.0|0|0\nS|2!10alpha|===1.0a1|1|0\nS|1.1_b0+ubuntu-ubuntu|>=3.0|0|0\nS|2-A.post|=== 1.0.dev1, <0, >=2.0rc0_r0|0|0\nS|1.1.2.2_pre|< 1.3.1, ===1.0, != 2.10.0.1-dev1|2|0\nS|1.10.1.0-A_1.r|< v1.25.0-4,>=3.dev.4,==3.1.2.*+local.1|1|E\nS|25.1.10dev|>=3.0-dev-0,=== 1.0,!=0.2.0-dev4+local.1|1|0\nS|1.2|>=0.1|0|1\nS|1.2A1|<= 1.1.3.25c-1-4 , >=2.10.3.2 , <=v0.1.10r.DEV|1|0\nS|10alpha1-dev-0|>= 0.0.0.25-a-dev-0 , != 2.*|1|1\nS|0|~=v1.1.10-alpha_2|2|0\nS|25+x.x|==3.25_RC.1|1|0\nS|2.2.3|== 10.b|1|0\nS|0.0.1.2|>1-DEV-1 , <= 10-rev-3|0|0\nS|1.0pre.post-1|<25.2.0alpha.10|0|1\nS|10|==1.0.1 , > 2.25 , <v1.2.10.25|0|0\n"
}

fn pep_vectors_19() -> str {
    ret "S|0.1rc10.dev.4|=== 1.0|0|0\nS|1.0|~= 2.10.0.0b|0|0\nS|1_A|== 1.10.25r.1,<1.0.3.0,>= 1.3.1.25|0|0\nS|1.10.10.10-1|<10.25 , ~=0|2|E\nS|3|~= 1.0.1-POST-3, == 25.0.2.0post|0|0\nS|0.1.0|>= 1.10.dev4, == v1.DEV.1|0|0\nS|1|>2.3.10.3-2 , < 3.10.Beta2 , >=2.0.0b0_POST-1|0|0\nS|0.0.1.25|>0.1-3DEV-0, <25.0dev-1|0|0\nS|v1.10.1|==2 , <=2.1.1 , ~=1.0.1.25|1|0\nS|10.3_c0-DEV|<=0.0|0|0\nR|requests[a,b] |ok\nR|zope.interface[security] ===1.0 ; extra == \"test\" and python_version < \"3.12\"|ok\nR|x-y-z[dev-tools,test_1] ( ==1.0 )|ok\nR|x-y-z ;sys_platform == \"win32\"|ok\nR|Django ( ==1.0 )|ok\nR|My_Pkg.name[a,b]>=1.0|ok\nR|pkg2[ a , b ] >=1.0;sys_platform == \"win32\"|ok\nR|a[a,b] ==1.* ; python_version >= \"3.8\"|ok\nR|requests[a,b]>=1.0,<2|ok\nR|Django[a,b]  ;python_version >= \"3.8\"|ok\nR|My_Pkg.name @ https://example.com/pkg-1.0.whl|ok\nR|x-y-z @ https://example.com/pkg-1.0.whl ; extra == \"test\" and python_version < \"3.12\"|ok\nR|requests[ a , b ](>=1,<2) ;sys_platform == \"win32\"|ok\nR|requests[a,b] ( ==1.0 )|ok\nR|My_Pkg.name[ a , b ] @ https://example.com/pkg-1.0.whl ; sys_platform == \"win32\"|ok\nR|zope.interface >=1.0,<2 ; sys_platform == \"win32\"|ok\nR|x-y-z[security] >=1.0,<2 ; extra == \"test\" and python_version < \"3.12\"|ok\nR|Django[dev-tools,test_1] >=1.0,<2|ok\nR|My_Pkg.name( ==1.0 ) ; extra == \"test\" and python_version < \"3.12\"|ok\nR|zope.interface>= 1.0 , != 1.5 ; python_version >= \"3.8\"|ok\nR|a ===1.0|ok\nR|a[security](>=1,<2)|ok\nR|pkg2[security]  ; sys_platform == \"win32\"|ok\nR|x-y-z[ a , b ]<2.0.dev1;extra == \"test\" and python_version < \"3.12\"|ok\nR|a[ a , b ] ===1.0|ok\nR|My_Pkg.name(>=1,<2)|ok\nR|Django[ a , b ]<2.0.dev1|ok\nR|x-y-z >=1.0,<2 ;python_version >= \"3.8\"|ok\nR|Django >=1.0|ok\nR|x-y-z[dev-tools,test_1]>=1.0,<2|ok\n"
}

fn pep_vectors_20() -> str {
    ret "R|My_Pkg.name[a,b]==1.* ; extra == \"test\" and python_version < \"3.12\"|ok\nR|requests[security] ==1.* ; python_version >= \"3.8\"|ok\nR|x-y-z[dev-tools,test_1]>= 1.0 , != 1.5|ok\nR|Django[a,b]~=2.2 ;python_version >= \"3.8\"|ok\nR|Django[dev-tools,test_1] ===1.0 ;sys_platform == \"win32\"|ok\nR|requests[security]>=1.0 ; extra == \"test\" and python_version < \"3.12\"|ok\nR|pkg2[a,b]~=2.2 ; python_version >= \"3.8\"|ok\nR|requests[a,b](>=1,<2);sys_platform == \"win32\"|ok\nR|My_Pkg.name[security]<2.0.dev1|ok\nR|requests[dev-tools,test_1] <2.0.dev1 ;sys_platform == \"win32\"|ok\nR|pkg2[a,b] ===1.0;sys_platform == \"win32\"|ok\nR|pkg2>=1.0,<2 ; sys_platform == \"win32\"|ok\nR|a[a,b]>=1.0;sys_platform == \"win32\"|ok\nR|x-y-z[security]>=1.0,<2 ;sys_platform == \"win32\"|ok\nR|requests[dev-tools,test_1] @ https://example.com/pkg-1.0.whl ; sys_platform == \"win32\"|ok\nR|a[ a , b ] @ https://example.com/pkg-1.0.whl|ok\nR|My_Pkg.name[ a , b ] ~=2.2;python_version >= \"3.8\"|ok\nR|zope.interface @ https://example.com/pkg-1.0.whl|ok\nR|a>= 1.0 , != 1.5|ok\nR|Django[a,b]>=1.0,<2 ;python_version >= \"3.8\"|ok\nR|a~=2.2|ok\nR|requests(>=1,<2)|ok\nR|pkg2[dev-tools,test_1]>=1.0;python_version >= \"3.8\"|ok\nR|requests[dev-tools,test_1]<2.0.dev1|ok\nR|x-y-z[security] ~=2.2 ; extra == \"test\" and python_version < \"3.12\"|ok\nR|pkg2 ==1.*|ok\nR|a @ https://example.com/pkg-1.0.whl ; extra == \"test\" and python_version < \"3.12\"|ok\nR|requests >=1.0,<2|ok\nR|a[a,b]( ==1.0 ) ; python_version >= \"3.8\"|ok\nR|Django[a,b];python_version >= \"3.8\"|ok\nR|pkg2[a,b] @ https://example.com/pkg-1.0.whl|ok\nR|requests[security] @ https://example.com/pkg-1.0.whl|ok\nR|My_Pkg.name <2.0.dev1;extra == \"test\" and python_version < \"3.12\"|ok\nR|x-y-z;extra == \"test\" and python_version < \"3.12\"|ok\nR|requests>= 1.0 , != 1.5|ok\nR|requests[ a , b ] ( ==1.0 );python_version >= \"3.8\"|ok\nR|requests[ a , b ] ==1.*|ok\nR|My_Pkg.name===1.0|ok\nR|requests[security] |ok\nR|pkg2[ a , b ]>= 1.0 , != 1.5;extra == \"test\" and python_version < \"3.12\"|ok\n"
}

fn pep_vectors_21() -> str {
    ret "R|Django[security]>=1.0,<2|ok\nR|pkg2[ a , b ]<2.0.dev1|ok\nR|zope.interface[ a , b ]  ; extra == \"test\" and python_version < \"3.12\"|ok\nR|pkg2 ==1.*|ok\nR|a[ a , b ]~=2.2 ; sys_platform == \"win32\"|ok\nR|pkg2[security] ( ==1.0 ) ;extra == \"test\" and python_version < \"3.12\"|ok\nR|zope.interface>= 1.0 , != 1.5;extra == \"test\" and python_version < \"3.12\"|ok\nR|pkg2 (>=1,<2)|ok\nR|pkg2[a,b]===1.0;sys_platform == \"win32\"|ok\nR|Django[a,b] >= 1.0 , != 1.5 ; python_version >= \"3.8\"|ok\nR|Django[a,b] >= 1.0 , != 1.5 ;python_version >= \"3.8\"|ok\nR|pkg2[security]~=2.2 ; sys_platform == \"win32\"|ok\nR|pkg2[a,b]>= 1.0 , != 1.5|ok\nR|zope.interface[ a , b ] ( ==1.0 ) ; extra == \"test\" and python_version < \"3.12\"|ok\nR|pkg2 |ok\nR|pkg2[dev-tools,test_1]>= 1.0 , != 1.5 ; sys_platform == \"win32\"|ok\nR|pkg2[dev-tools,test_1];extra == \"test\" and python_version < \"3.12\"|ok\nR|x-y-z ==1.*|ok\nR|Django[security] <2.0.dev1 ;sys_platform == \"win32\"|ok\nR|pkg2[ a , b ]<2.0.dev1 ;python_version >= \"3.8\"|ok\nR|Django[a,b] @ https://example.com/pkg-1.0.whl|ok\nR|My_Pkg.name[a,b] |ok\nR|a[a,b] ( ==1.0 )|ok\nR|a[security] >=1.0,<2 ;python_version >= \"3.8\"|ok\nR|My_Pkg.name[ a , b ] ==1.* ; extra == \"test\" and python_version < \"3.12\"|ok\nR|zope.interface[dev-tools,test_1]<2.0.dev1;python_version >= \"3.8\"|ok\nR|Django[ a , b ](>=1,<2) ;extra == \"test\" and python_version < \"3.12\"|ok\nR|zope.interface>= 1.0 , != 1.5;extra == \"test\" and python_version < \"3.12\"|ok\nR|x-y-z==1.* ;extra == \"test\" and python_version < \"3.12\"|ok\nR|x-y-z[security]>= 1.0 , != 1.5 ;extra == \"test\" and python_version < \"3.12\"|ok\nR||E\nR|>=1.0|E\nR|name>=|E\nR|name[|E\nR|name[a|E\nR|-name|E\nR|name-|E\nR|na me|E\nR|name>=1.0,|ok\nR|name (>=1.0|E\n"
}

fn pep_vectors_22() -> str {
    ret "R|name >= 1.0 ; |E\nR|name @|E\nR|name [a,,b]|E\nR|name>>1|E\nR|name==1.*.2|E\nR|name~=1|E\nR|name>1.0+local|E\n"
}

fn main(a: *mem.Arena, args: []str) -> err {
    if run(a, pep_vectors_0()) != 0u8 { os.exit(1i32) }
    if run(a, pep_vectors_1()) != 0u8 { os.exit(2i32) }
    if run(a, pep_vectors_2()) != 0u8 { os.exit(3i32) }
    if run(a, pep_vectors_3()) != 0u8 { os.exit(4i32) }
    if run(a, pep_vectors_4()) != 0u8 { os.exit(5i32) }
    if run(a, pep_vectors_5()) != 0u8 { os.exit(6i32) }
    if run(a, pep_vectors_6()) != 0u8 { os.exit(7i32) }
    if run(a, pep_vectors_7()) != 0u8 { os.exit(8i32) }
    if run(a, pep_vectors_8()) != 0u8 { os.exit(9i32) }
    if run(a, pep_vectors_9()) != 0u8 { os.exit(10i32) }
    if run(a, pep_vectors_10()) != 0u8 { os.exit(11i32) }
    if run(a, pep_vectors_11()) != 0u8 { os.exit(12i32) }
    if run(a, pep_vectors_12()) != 0u8 { os.exit(13i32) }
    if run(a, pep_vectors_13()) != 0u8 { os.exit(14i32) }
    if run(a, pep_vectors_14()) != 0u8 { os.exit(15i32) }
    if run(a, pep_vectors_15()) != 0u8 { os.exit(16i32) }
    if run(a, pep_vectors_16()) != 0u8 { os.exit(17i32) }
    if run(a, pep_vectors_17()) != 0u8 { os.exit(18i32) }
    if run(a, pep_vectors_18()) != 0u8 { os.exit(19i32) }
    if run(a, pep_vectors_19()) != 0u8 { os.exit(20i32) }
    if run(a, pep_vectors_20()) != 0u8 { os.exit(21i32) }
    if run(a, pep_vectors_21()) != 0u8 { os.exit(22i32) }
    if run(a, pep_vectors_22()) != 0u8 { os.exit(23i32) }
    // The requirement fields, not only acceptance.
    let (r, r_error) = pep440.parse_requirement("Django[security, tests] (>=1.0, <2) ; python_version >= \"3.8\"")
    if r_error != ok || !str.eq(r.name, "Django") || !str.eq(r.extras, "security, tests") || !str.eq(r.specifiers, ">=1.0, <2") || !str.eq(r.marker, "python_version >= \"3.8\"") { os.exit(90i32) }
    let (u, u_error) = pep440.parse_requirement("pkg @ https://example.com/pkg-1.0.whl ; sys_platform == \"win32\"")
    if u_error != ok || !str.eq(u.name, "pkg") || !str.eq(u.url, "https://example.com/pkg-1.0.whl") || u.specifiers.len != 0usize { os.exit(91i32) }
    // The version's own accessors.
    let (v, v_error) = pep440.parse("1!2.0.0rc1.post3.dev4+Ubuntu.1")
    if v_error != ok || v.epoch != 1u64 || v.release_len != 3usize || v.pre_num != 1u64 || !v.has_post || !v.has_dev || !pep440.is_prerelease(v) || !pep440.is_postrelease(v) { os.exit(92i32) }
    if pep440.cmp(pep440.base_version(v), pep440.public(v)) <= 0i32 { os.exit(93i32) }
    try io.print("fmt semver pep440 ok")
    ret ok
}
