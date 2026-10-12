// robots.txt (RFC 9309): parse a file once, then ask whether a crawler may fetch a path.
//
// Syntax. Lines are `field: value`; field names are case-insensitive (`User-agent`, `Allow`,
// `Disallow`, `Sitemap`, `Crawl-delay`; the colon may be a space); `#` starts a comment;
// blank lines and unknown fields are skipped. Consecutive `User-agent` lines share the rules
// that follow them (a group); a `User-agent` line after a rule starts a new group; a rule
// before any `User-agent` is ignored; an empty `Allow`/`Disallow` value is ignored (it
// allows everything). `Sitemap` is site-wide and may appear anywhere.
//
// Matching. The group is chosen by the crawler's product token: an exact case-insensitive
// match with a `User-agent` value, else `*`, else no rules (allowed). Groups naming the same
// agent are merged. Among the group's rules the one with the longest pattern wins and `Allow`
// beats `Disallow` at equal length. A pattern is a prefix of the path-and-query, `*` matches
// any run, and a trailing `$` anchors the end. Percent escapes are compared as written with
// their hex digits upper-cased (no further decoding). `/robots.txt` itself is always allowed.
// `Crawl-delay` is seconds, decimal, answered in milliseconds.
//
// Everything is a slice of the source text or of arena arrays, so the text must outlive the
// `Robots`.

use e.mem

type Group = struct { first_agent: usize, agent_count: usize, first_rule: usize, rule_count: usize, has_delay: bool, delay_millis: u32 }
type Rule = struct { allow: bool, pattern: str }
type Robots = struct { groups: []Group, agents: []str, rules: []Rule, sitemaps: []str, group_count: usize, agent_count: usize, rule_count: usize, sitemap_count: usize }
error Invalid

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn same_fold(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if lower(a[i]) != lower(b[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 13u8 }

fn trim(s: str) -> str {
    var a = 0usize
    var b = s.len
    while a < b && is_space(s[a]) { a += 1usize }
    while b > a && is_space(s[b - 1usize]) { b -= 1usize }
    ret s[a..b]
}

// 1 user-agent, 2 allow, 3 disallow, 4 sitemap, 5 crawl-delay, 0 unknown.
fn field_kind(name: str) -> u8 {
    if same_fold(name, "user-agent") || same_fold(name, "useragent") || same_fold(name, "user agent") { ret 1u8 }
    if same_fold(name, "allow") { ret 2u8 }
    if same_fold(name, "disallow") { ret 3u8 }
    if same_fold(name, "sitemap") { ret 4u8 }
    if same_fold(name, "crawl-delay") || same_fold(name, "crawl delay") { ret 5u8 }
    ret 0u8
}

// `3`, `0.5`, `10.25` to milliseconds; false for anything else.
fn parse_millis(s: str) -> (u32, bool) {
    if s.len == 0usize { ret (0u32, false) }
    var whole = 0u64
    var i = 0usize
    var digits = 0usize
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        whole = whole * 10u64 + u64(s[i] - 48u8)
        if whole > 4000000u64 { ret (0u32, false) }
        digits += 1usize
        i += 1usize
    }
    var millis = whole * 1000u64
    var seen = 0usize
    if i < s.len {
        if s[i] != 46u8 { ret (0u32, false) }
        i += 1usize
        var scale = 100u64
        while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
            millis += u64(s[i] - 48u8) * scale
            scale = scale / 10u64
            seen += 1usize
            i += 1usize
        }
        if i != s.len { ret (0u32, false) }
    }
    // `5`, `5.`, `.5` and `5.5` read as numbers; `.` alone does not
    if digits == 0usize && seen == 0usize { ret (0u32, false) }
    if millis > 4294967295u64 { ret (0u32, false) }
    ret (u32(millis), true)
}

// Splits a line into field and value; false when it is not a directive line.
fn split_line(line: str) -> (u8, str, bool) {
    var colon = 0usize
    while colon < line.len && line[colon] != 58u8 { colon += 1usize }
    if colon < line.len {
        let kind = field_kind(trim(line[0usize..colon]))
        if kind != 0u8 { ret (kind, trim(line[colon + 1usize..line.len]), true) }
    }
    // "Disallow /private": the first word is the field, the rest the value
    var sp = 0usize
    while sp < line.len && !is_space(line[sp]) { sp += 1usize }
    let word_kind = field_kind(line[0usize..sp])
    if word_kind != 0u8 { ret (word_kind, trim(line[sp..line.len]), true) }
    ret (0u8, "", false)
}

fn parse(a: *mem.Arena, text: str) -> (Robots, err) {
    var lines = 1usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 { lines += 1usize }
        i += 1usize
    }
    var r: Robots = zero
    let (groups, groups_error) = mem.alloc[Group](a, lines)
    if groups_error != ok { ret (r, groups_error) }
    let (agents, agents_error) = mem.alloc[str](a, lines)
    if agents_error != ok { ret (r, agents_error) }
    let (rules, rules_error) = mem.alloc[Rule](a, lines)
    if rules_error != ok { ret (r, rules_error) }
    let (sitemaps, sitemaps_error) = mem.alloc[str](a, lines)
    if sitemaps_error != ok { ret (r, sitemaps_error) }
    var in_group = false
    var last_was_agent = false
    var start = 0usize
    var at = 0usize
    while at <= text.len {
        if at == text.len || text[at] == 10u8 {
            var line = text[start..at]
            var hash = 0usize
            while hash < line.len && line[hash] != 35u8 { hash += 1usize }
            line = trim(line[0usize..hash])
            start = at + 1usize
            if line.len > 0usize {
                let (kind, value, good) = split_line(line)
                if good {
                    if kind == 1u8 {
                        if !last_was_agent || !in_group {
                            // a new group
                            var g: Group = zero
                            g.first_agent = r.agent_count
                            g.first_rule = r.rule_count
                            groups[r.group_count] = g
                            r.group_count += 1usize
                            in_group = true
                        }
                        last_was_agent = true
                        if value.len > 0usize {
                            agents[r.agent_count] = value
                            r.agent_count += 1usize
                            groups[r.group_count - 1usize].agent_count += 1usize
                        }
                    } else if kind == 4u8 {
                        if value.len > 0usize {
                            sitemaps[r.sitemap_count] = value
                            r.sitemap_count += 1usize
                        }
                    } else {
                        last_was_agent = false
                        if in_group && value.len > 0usize {
                            if kind == 2u8 || kind == 3u8 {
                                var rule: Rule = zero
                                rule.allow = kind == 2u8
                                rule.pattern = value
                                rules[r.rule_count] = rule
                                r.rule_count += 1usize
                                groups[r.group_count - 1usize].rule_count += 1usize
                            } else if kind == 5u8 {
                                let (ms, ms_ok) = parse_millis(value)
                                if ms_ok {
                                    groups[r.group_count - 1usize].has_delay = true
                                    groups[r.group_count - 1usize].delay_millis = ms
                                }
                            }
                        }
                    }
                }
            }
        }
        at += 1usize
    }
    r.groups = groups[0usize..r.group_count]
    r.agents = agents[0usize..r.agent_count]
    r.rules = rules[0usize..r.rule_count]
    r.sitemaps = sitemaps[0usize..r.sitemap_count]
    ret (r, ok)
}

fn hex_upper(c: u8) -> u8 {
    if c >= 97u8 && c <= 102u8 { ret c - 32u8 }
    ret c
}

fn is_hex(c: u8) -> bool { ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 70u8) || (c >= 97u8 && c <= 102u8) }

// Byte `i` of `s` as the comparison sees it: hex digits of a `%XX` escape upper-cased.
fn norm_at(s: str, i: usize) -> u8 {
    let c = s[i]
    if i >= 1usize && is_hex(c) && s[i - 1usize] == 37u8 { ret hex_upper(c) }
    if i >= 2usize && is_hex(c) && s[i - 2usize] == 37u8 && is_hex(s[i - 1usize]) { ret hex_upper(c) }
    ret c
}

// Does `part` (a pattern run without `*`) occur in `path` at `at`?
fn part_at(pattern: str, from: usize, to: usize, path: str, at: usize) -> bool {
    if at + (to - from) > path.len { ret false }
    var k = 0usize
    while k < to - from {
        if norm_at(pattern, from + k) != norm_at(path, at + k) { ret false }
        k += 1usize
    }
    ret true
}

fn find_part(pattern: str, from: usize, to: usize, path: str, start: usize) -> (usize, bool) {
    var at = start
    while at + (to - from) <= path.len {
        if part_at(pattern, from, to, path, at) { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

// Pattern semantics: `*` any run, a final `$` anchors the end, otherwise a prefix.
fn matches(pattern: str, path: str) -> bool {
    var end = pattern.len
    var anchored = false
    if end > 0usize && pattern[end - 1usize] == 36u8 {
        anchored = true
        end -= 1usize
    }
    // parts between stars: [part_start, part_end)
    var pos = 0usize
    var i = 0usize
    var first = true
    var part_start = 0usize
    while i <= end {
        if i == end || pattern[i] == 42u8 {
            let is_last = i == end
            if first {
                // the first part must be a prefix
                if !is_last || !anchored {
                    if !part_at(pattern, part_start, i, path, 0usize) { ret false }
                    pos = i - part_start
                } else {
                    // no star at all and anchored: the whole path must equal the pattern
                    if i - part_start != path.len { ret false }
                    ret part_at(pattern, part_start, i, path, 0usize)
                }
                first = false
            } else if is_last {
                if anchored {
                    let len = i - part_start
                    if path.len < pos + len { ret false }
                    ret part_at(pattern, part_start, i, path, path.len - len)
                }
                if i == part_start { ret true }
                let (at, found) = find_part(pattern, part_start, i, path, pos)
                ret found
            } else if i > part_start {
                let (at, found) = find_part(pattern, part_start, i, path, pos)
                if !found { ret false }
                pos = at + (i - part_start)
            }
            part_start = i + 1usize
        }
        i += 1usize
    }
    ret true
}

fn group_names(r: *const Robots, g: usize, agent: str) -> bool {
    let grp = r.groups[g]
    var k = 0usize
    while k < grp.agent_count {
        if same_fold(r.agents[grp.first_agent + k], agent) { ret true }
        k += 1usize
    }
    ret false
}

fn knows(r: *const Robots, agent: str) -> bool {
    var g = 0usize
    while g < r.groups.len {
        if group_names(r, g, agent) { ret true }
        g += 1usize
    }
    ret false
}

// Which agent name's rules apply to the crawler `agent`: its own if any group names it,
// else `*`; false when neither exists.
fn applicable(r: *const Robots, agent: str) -> (str, bool) {
    if knows(r, agent) { ret (agent, true) }
    if knows(r, "*") { ret ("*", true) }
    ret ("", false)
}

fn allowed(r: *const Robots, agent: str, path: str) -> bool {
    if same_fold(path, "/robots.txt") { ret true }
    let (name, found) = applicable(r, agent)
    if !found { ret true }
    var best_len = 0usize
    var best_allow = true
    var any = false
    var g = 0usize
    while g < r.groups.len {
        if group_names(r, g, name) {
            let grp = r.groups[g]
            var k = 0usize
            while k < grp.rule_count {
                let rule = r.rules[grp.first_rule + k]
                if matches(rule.pattern, path) {
                    if !any || rule.pattern.len > best_len || (rule.pattern.len == best_len && rule.allow && !best_allow) {
                        best_len = rule.pattern.len
                        best_allow = rule.allow
                        any = true
                    }
                }
                k += 1usize
            }
        }
        g += 1usize
    }
    if !any { ret true }
    ret best_allow
}

// Crawl-delay in milliseconds for the crawler (the last one given in the applicable groups).
fn crawl_delay(r: *const Robots, agent: str) -> (u32, bool) {
    let (name, found) = applicable(r, agent)
    if !found { ret (0u32, false) }
    var millis = 0u32
    var has = false
    var g = 0usize
    while g < r.groups.len {
        if group_names(r, g, name) && r.groups[g].has_delay {
            millis = r.groups[g].delay_millis
            has = true
        }
        g += 1usize
    }
    ret (millis, has)
}
