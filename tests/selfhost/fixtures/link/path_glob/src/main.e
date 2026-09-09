// `e.path`'s globs: pure matching over relative paths, with no filesystem anywhere near it.
//
// The interesting cases are the boundaries between the three wildcards. `*` and `?` stay inside a
// component and `**` crosses them, so every check that a `*` does not span a separator is a check
// that the two are not the same thing.

use e.mem
use e.os
use e.path

fn options(case_sensitive: bool, style: path.Style) -> path.GlobOptions {
    var o: path.GlobOptions = zero
    o.style = style
    o.case_sensitive = case_sensitive
    ret o
}

// Compiles the pattern and answers whether it matched, with any error folded into a code the
// caller can tell apart from a plain "no".
fn matches(a: *mem.Arena, pattern: str, subject: str) -> i32 {
    let (compiled, compile_error) = path.glob(a, pattern, options(true, .Posix))
    if compile_error != ok { ret -1i32 }
    let (matched, match_error) = path.glob_match(&compiled, subject)
    if match_error != ok { ret -2i32 }
    if matched { ret 1i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    // --- A pattern with no wildcards is a comparison.
    if matches(a, "a/b/c", "a/b/c") != 1i32 { os.exit(10i32) }
    if matches(a, "a/b/c", "a/b/d") != 0i32 { os.exit(11i32) }
    if matches(a, "a/b", "a/b/c") != 0i32 { os.exit(12i32) }
    if matches(a, "a/b/c", "a/b") != 0i32 { os.exit(13i32) }
    // Empty components and `.` are not components: they name the same relative path.
    if matches(a, "a/b", "a//b") != 1i32 { os.exit(14i32) }
    if matches(a, "a/b", "./a/b") != 1i32 { os.exit(15i32) }
    if matches(a, "./a/b", "a/b") != 1i32 { os.exit(16i32) }
    if matches(a, "a/b", "a/b/") != 1i32 { os.exit(17i32) }

    // --- `*` matches within one component and never across a separator, which is the line
    // between it and `**`.
    if matches(a, "*.txt", "notes.txt") != 1i32 { os.exit(20i32) }
    if matches(a, "*.txt", "notes.md") != 0i32 { os.exit(21i32) }
    if matches(a, "*", "a") != 1i32 { os.exit(22i32) }
    if matches(a, "*", "a/b") != 0i32 { os.exit(23i32) }
    if matches(a, "src/*.e", "src/main.e") != 1i32 { os.exit(24i32) }
    if matches(a, "src/*.e", "src/deep/main.e") != 0i32 { os.exit(25i32) }
    // A leading dot is not special: nothing is implicitly excluded.
    if matches(a, "*", ".hidden") != 1i32 { os.exit(26i32) }
    if matches(a, ".*", ".hidden") != 1i32 { os.exit(27i32) }
    // A star matches nothing at all as happily as it matches something.
    if matches(a, "a*b", "ab") != 1i32 { os.exit(28i32) }
    if matches(a, "a*b*c", "abc") != 1i32 { os.exit(29i32) }
    // And the backtracking has to give bytes back: the last `b` is the one that ends it.
    if matches(a, "a*b", "abxbxb") != 1i32 { os.exit(30i32) }
    if matches(a, "a*b", "abxbxc") != 0i32 { os.exit(31i32) }

    // --- `?` is exactly one byte, and not a separator.
    if matches(a, "?", "a") != 1i32 { os.exit(35i32) }
    if matches(a, "?", "ab") != 0i32 { os.exit(36i32) }
    if matches(a, "a?c", "abc") != 1i32 { os.exit(37i32) }
    if matches(a, "a?c", "ac") != 0i32 { os.exit(38i32) }
    if matches(a, "a?c", "a/c") != 0i32 { os.exit(39i32) }

    // --- A whole `**` component matches zero or more components. Zero is the case most
    // implementations get wrong.
    if matches(a, "a/**/b", "a/b") != 1i32 { os.exit(40i32) }
    if matches(a, "a/**/b", "a/x/b") != 1i32 { os.exit(41i32) }
    if matches(a, "a/**/b", "a/x/y/z/b") != 1i32 { os.exit(42i32) }
    if matches(a, "a/**/b", "a/x/y/c") != 0i32 { os.exit(43i32) }
    if matches(a, "**", "a") != 1i32 { os.exit(44i32) }
    if matches(a, "**", "a/b/c") != 1i32 { os.exit(45i32) }
    if matches(a, "**/*.e", "main.e") != 1i32 { os.exit(46i32) }
    if matches(a, "**/*.e", "src/lib/main.e") != 1i32 { os.exit(47i32) }
    if matches(a, "**/*.e", "src/lib/main.c") != 0i32 { os.exit(48i32) }
    if matches(a, "src/**", "src/a/b") != 1i32 { os.exit(49i32) }
    // A `**` at the end still needs the components before it to be there.
    if matches(a, "src/**", "lib/a") != 0i32 { os.exit(50i32) }
    // Two of them, which is where a single remembered position is not enough.
    if matches(a, "**/x/**/y", "a/b/x/c/d/y") != 1i32 { os.exit(51i32) }
    if matches(a, "**/x/**/y", "a/b/x/c/d/z") != 0i32 { os.exit(52i32) }
    // `**` inside a component is not the whole-component form: there it is just a star, so it
    // stays inside that component.
    if matches(a, "a**b", "axxb") != 1i32 { os.exit(53i32) }
    if matches(a, "a**b", "ax/xb") != 0i32 { os.exit(54i32) }

    // --- Bracket classes: members, ASCII ranges, and `!` negation.
    if matches(a, "[abc].e", "b.e") != 1i32 { os.exit(60i32) }
    if matches(a, "[abc].e", "d.e") != 0i32 { os.exit(61i32) }
    if matches(a, "[a-f].e", "c.e") != 1i32 { os.exit(62i32) }
    if matches(a, "[a-f].e", "g.e") != 0i32 { os.exit(63i32) }
    if matches(a, "[0-9][0-9].log", "42.log") != 1i32 { os.exit(64i32) }
    if matches(a, "[0-9][0-9].log", "4x.log") != 0i32 { os.exit(65i32) }
    if matches(a, "[!abc].e", "d.e") != 1i32 { os.exit(66i32) }
    if matches(a, "[!abc].e", "a.e") != 0i32 { os.exit(67i32) }
    // A `-` at either end of the class is a literal one, not half a range.
    if matches(a, "[-a].e", "-.e") != 1i32 { os.exit(68i32) }
    if matches(a, "[a-].e", "-.e") != 1i32 { os.exit(69i32) }
    // A class cannot hold a separator at all: the pattern is cut into components before any
    // class is read, so `a[/]b` is the two components `a[` and `]b`, and the first of them has an
    // unterminated class. Refused rather than matched, which is stronger than never matching.
    if matches(a, "a[/]b", "a/b") != -1i32 { os.exit(70i32) }

    // --- A pattern that cannot be read is refused when it is compiled.
    let (unterminated, unterminated_error) = path.glob(a, "[abc.e", options(true, .Posix))
    if unterminated_error != path.Invalid { os.exit(80i32) }
    let (absolute, absolute_error) = path.glob(a, "/etc/*", options(true, .Posix))
    if absolute_error != path.Invalid { os.exit(81i32) }
    let (drive, drive_error) = path.glob(a, "C:/x/*", options(true, .Posix))
    if drive_error != path.Invalid { os.exit(82i32) }
    let (parent, parent_error) = path.glob(a, "../*", options(true, .Posix))
    if parent_error != path.Invalid { os.exit(83i32) }
    let (nothing, nothing_error) = path.glob(a, "", options(true, .Posix))
    if nothing_error != path.Invalid { os.exit(84i32) }

    // --- And a path that is not a relative path is refused when it is matched, which is a
    // different answer from not matching.
    let (any, any_error) = path.glob(a, "**", options(true, .Posix))
    if any_error != ok { os.exit(85i32) }
    let (absolute_matched, absolute_match_error) = path.glob_match(&any, "/etc/passwd")
    if absolute_match_error != path.Invalid { os.exit(86i32) }
    let (parent_matched, parent_match_error) = path.glob_match(&any, "../secret")
    if parent_match_error != path.Invalid { os.exit(87i32) }
    let (inner_parent, inner_parent_error) = path.glob_match(&any, "a/../b")
    if inner_parent_error != path.Invalid { os.exit(88i32) }

    // --- Case folding is asked for, never assumed.
    let (sensitive, sensitive_error) = path.glob(a, "readme.md", options(true, .Posix))
    if sensitive_error != ok { os.exit(90i32) }
    let (sensitive_matched, sensitive_match_error) = path.glob_match(&sensitive, "README.md")
    if sensitive_match_error != ok { os.exit(91i32) }
    if sensitive_matched { os.exit(92i32) }
    let (folded, folded_error) = path.glob(a, "readme.md", options(false, .Posix))
    if folded_error != ok { os.exit(93i32) }
    let (folded_matched, folded_match_error) = path.glob_match(&folded, "README.md")
    if folded_match_error != ok { os.exit(94i32) }
    if !folded_matched { os.exit(95i32) }
    // Folding reaches inside a class and a range as well.
    let (folded_class, folded_class_error) = path.glob(a, "[a-f].e", options(false, .Posix))
    if folded_class_error != ok { os.exit(96i32) }
    let (class_matched, class_match_error) = path.glob_match(&folded_class, "C.e")
    if class_match_error != ok { os.exit(97i32) }
    if !class_matched { os.exit(98i32) }

    // --- The pattern is `/`-separated whatever the paths are. One compiled pattern matches the
    // Windows spelling of the same relative path when it is told to read paths that way.
    let (windows, windows_error) = path.glob(a, "src/**/*.e", options(true, .Windows))
    if windows_error != ok { os.exit(100i32) }
    let (windows_matched, windows_match_error) = path.glob_match(&windows, "src\\lib\\main.e")
    if windows_match_error != ok { os.exit(101i32) }
    if !windows_matched { os.exit(102i32) }
    // And under Posix a backslash is an ordinary byte in a name, so the same path is one
    // component and does not match.
    let (posix, posix_error) = path.glob(a, "src/**/*.e", options(true, .Posix))
    if posix_error != ok { os.exit(103i32) }
    let (posix_matched, posix_match_error) = path.glob_match(&posix, "src\\lib\\main.e")
    if posix_match_error != ok { os.exit(104i32) }
    if posix_matched { os.exit(105i32) }

    // --- The limits. A pattern past its byte budget is `TooLarge` rather than `Invalid`: it is
    // a refusal to do the work, not a complaint about the syntax.
    var small: path.GlobOptions = zero
    small.style = .Posix
    small.case_sensitive = true
    small.max_pattern_bytes = 4usize
    let (long, long_error) = path.glob(a, "abcdefgh", small)
    if long_error != path.TooLarge { os.exit(110i32) }
    let (short, short_error) = path.glob(a, "ab", small)
    if short_error != ok { os.exit(111i32) }

    // Work exhaustion is `TooLarge` too, and never a quiet false. The pattern below is the shape
    // that makes a backtracking matcher work hardest.
    var stingy: path.GlobOptions = zero
    stingy.style = .Posix
    stingy.case_sensitive = true
    stingy.max_steps = 8usize
    let (hungry, hungry_error) = path.glob(a, "*a*a*a*a*b", stingy)
    if hungry_error != ok { os.exit(112i32) }
    let (hungry_matched, hungry_match_error) = path.glob_match(&hungry, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaac")
    if hungry_match_error != path.TooLarge { os.exit(113i32) }
    if hungry_matched { os.exit(114i32) }
    // With no limit set at all the same pattern answers, which is what says the limit was the
    // reason and not the pattern.
    let (patient, patient_error) = path.glob(a, "*a*a*a*a*b", options(true, .Posix))
    if patient_error != ok { os.exit(115i32) }
    let (patient_matched, patient_match_error) = path.glob_match(&patient, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaac")
    if patient_match_error != ok { os.exit(116i32) }
    if patient_matched { os.exit(117i32) }
    let (patient_hit, patient_hit_error) = path.glob_match(&patient, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaab")
    if patient_hit_error != ok { os.exit(118i32) }
    if !patient_hit { os.exit(119i32) }
    ret ok
}
