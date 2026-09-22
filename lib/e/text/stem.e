// Suffix strippers for English words in caller storage: `porter` is Martin
// Porter's 1980 algorithm as published (the original rule set, no later
// extensions), `lancaster` the Paice/Husk stemmer over its standard 115
// rules, and `strip_affixes` removes the caller's own prefixes and suffixes
// (longest first, repeatedly) down to a minimum stem length. Every stemmer
// lowercases ASCII and answers the stem as a slice of `out`.

error TooSmall

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn is_vowel_letter(c: u8) -> bool { ret c == 97u8 || c == 101u8 || c == 105u8 || c == 111u8 || c == 117u8 }

// A consonant is any letter but a, e, i, o, u, and y after a consonant.
fn is_consonant(w: []const u8, i: usize) -> bool {
    if is_vowel_letter(w[i]) { ret false }
    if w[i] == 121u8 {
        if i == 0usize { ret true }
        ret !is_consonant(w, i - 1usize)
    }
    ret true
}

// The measure m of `w[..n]`: the count of vowel-consonant sequences.
fn measure(w: []const u8, n: usize) -> usize {
    var m = 0usize
    var i = 0usize
    while i < n && is_consonant(w, i) { i += 1usize }
    while i < n {
        while i < n && !is_consonant(w, i) { i += 1usize }
        if i >= n { ret m }
        m += 1usize
        while i < n && is_consonant(w, i) { i += 1usize }
    }
    ret m
}

fn contains_vowel(w: []const u8, n: usize) -> bool {
    var i = 0usize
    while i < n {
        if !is_consonant(w, i) { ret true }
        i += 1usize
    }
    ret false
}

fn ends_double_consonant(w: []const u8, n: usize) -> bool {
    ret n >= 2usize && w[n - 1usize] == w[n - 2usize] && is_consonant(w, n - 1usize)
}

// *o: the stem ends consonant-vowel-consonant with the last not w, x or y.
fn ends_cvc(w: []const u8, n: usize) -> bool {
    if n < 3usize { ret false }
    let last = w[n - 1usize]
    ret is_consonant(w, n - 3usize) && !is_consonant(w, n - 2usize) && is_consonant(w, n - 1usize) && last != 119u8 && last != 120u8 && last != 121u8
}

fn ends_with(w: []const u8, n: usize, suffix: str) -> bool {
    if n < suffix.len { ret false }
    var i = 0usize
    while i < suffix.len {
        if w[n - suffix.len + i] != suffix[i] { ret false }
        i += 1usize
    }
    ret true
}

fn append(w: []u8, n: usize, s: str) -> usize {
    var i = 0usize
    while i < s.len {
        w[n + i] = s[i]
        i += 1usize
    }
    ret n + s.len
}

// Apply the first rule of `rules` (`suffix=replacement;...`) whose suffix
// matches, when the stem satisfies `condition` (0 always, 1 m > 0, 2 m > 1,
// 3 m > 1 and the stem ends in s or t); a matching suffix whose condition
// fails ends the search, as in the paper. Answers the new length.
fn apply_rules(w: []u8, n: usize, rules: str, condition: u8) -> usize {
    var i = 0usize
    while i < rules.len {
        var j = i
        while rules[j] != 61u8 { j += 1usize }
        var k = j + 1usize
        while k < rules.len && rules[k] != 59u8 { k += 1usize }
        let suffix = rules[i..j]
        let replacement = rules[j + 1usize..k]
        if ends_with(w, n, suffix) {
            let stem = n - suffix.len
            var allowed = true
            if condition == 1u8 { allowed = measure(w, stem) > 0usize }
            if condition == 2u8 { allowed = measure(w, stem) > 1usize }
            if condition == 3u8 { allowed = measure(w, stem) > 1usize && stem > 0usize && (w[stem - 1usize] == 115u8 || w[stem - 1usize] == 116u8) }
            if !allowed { ret n }
            ret append(w, stem, replacement)
        }
        i = k + 1usize
    }
    ret n
}

// The Porter stemmer; `out.len >= word.len + 1`.
fn porter(word: str, out: []u8) -> (str, err) {
    if out.len < word.len + 1usize { ret ("", TooSmall) }
    var w = out
    var n = word.len
    var i = 0usize
    while i < n {
        w[i] = lower(word[i])
        i += 1usize
    }
    // Step 1a.
    n = apply_rules(w, n, "sses=ss;ies=i;ss=ss;s=", 0u8)
    // Step 1b.
    if ends_with(w, n, "eed") {
        if measure(w, n - 3usize) > 0usize { n -= 1usize }
    } else {
        var stripped = n
        if ends_with(w, n, "ed") && contains_vowel(w, n - 2usize) {
            stripped = n - 2usize
        } else if ends_with(w, n, "ing") && contains_vowel(w, n - 3usize) {
            stripped = n - 3usize
        }
        if stripped != n {
            n = stripped
            if ends_with(w, n, "at") || ends_with(w, n, "bl") || ends_with(w, n, "iz") {
                n = append(w, n, "e")
            } else if ends_double_consonant(w, n) {
                let last = w[n - 1usize]
                if last != 108u8 && last != 115u8 && last != 122u8 { n -= 1usize }
            } else if measure(w, n) == 1usize && ends_cvc(w, n) {
                n = append(w, n, "e")
            }
        }
    }
    // Step 1c.
    if ends_with(w, n, "y") && contains_vowel(w, n - 1usize) { w[n - 1usize] = 105u8 }
    // Steps 2 to 4.
    n = apply_rules(w, n, "ational=ate;tional=tion;enci=ence;anci=ance;izer=ize;abli=able;alli=al;entli=ent;eli=e;ousli=ous;ization=ize;ation=ate;ator=ate;alism=al;iveness=ive;fulness=ful;ousness=ous;aliti=al;iviti=ive;biliti=ble", 1u8)
    n = apply_rules(w, n, "icate=ic;ative=;alize=al;iciti=ic;ical=ic;ful=;ness=", 1u8)
    n = apply_rules(w, n, "al=;ance=;ence=;er=;ic=;able=;ible=;ant=;ement=;ment=;ent=", 2u8)
    let before_ion = n
    n = apply_rules(w, n, "ion=", 3u8)
    if n == before_ion { n = apply_rules(w, n, "ou=;ism=;ate=;iti=;ous=;ive=;ize=", 2u8) }
    // Step 5a.
    if ends_with(w, n, "e") {
        let m = measure(w, n - 1usize)
        if m > 1usize || (m == 1usize && !ends_cvc(w, n - 1usize)) { n -= 1usize }
    }
    // Step 5b.
    if ends_with(w, n, "ll") && measure(w, n - 1usize) > 1usize { n -= 1usize }
    ret (w[..n], ok)
}

fn is_lancaster_vowel(c: u8) -> bool { ret is_vowel_letter(c) || c == 121u8 }

// A stem of `n - remove` letters is acceptable when it keeps two letters
// after an initial vowel, or three with a vowel in the second or third.
fn lancaster_acceptable(w: []const u8, n: usize, remove: usize) -> bool {
    if remove > n { ret false }
    let left = n - remove
    if is_lancaster_vowel(w[0usize]) { ret left >= 2usize }
    if left < 3usize { ret false }
    ret is_lancaster_vowel(w[1usize]) || is_lancaster_vowel(w[2usize])
}

// The Paice/Husk rules, each `ending*count append.` with the ending
// reversed, `*` for intact-only, `.` to stop and `>` to continue.
fn lancaster_rules() -> str {
    ret "ai*2. a*1. bb1. city3s. ci2> cn1t> dd1. dei3y> deec2ss. dee1. de2> dooh4> e1> feil1v. fi2> gni3> gai3y. ga2> gg1. ht*2. hsiug5ct. hsi3> i*1. i1y> ji1d. juf1s. ju1d. jo1d. jeh1r. jrev1t. jsim2t. jn1d. j1s. lbaifi6. lbai4y. lba3> lbi3. lib2l> lc1. lufi4y. luf3> lu2. lai3> lau3> la2> ll1. mui3. mu*2. msi3> mm1. nois4j> noix4ct. noi3> nai3> na2> nee0. ne2> nn1. pihs4> pp1. re2> rae0. ra2. ro2> ru2> rr1. rt1> rei3y> sei3y> sis2. si2> ssen4> ss0. suo3> su*2. s*1> s0. tacilp4y. ta2> tnem4> tne3> tna3> tpir2b. tpro2b. tcud1. tpmus2. tpec2iv. tulo2v. tsis0. tsi3> tt1. uqi3. ugo1. vis3j> vie0. vi2> ylb1> yli3y> ylp0. yl2> ygo1. yhp1. ymo1. ypo1. yti3> yte3> ytl2. yrtsi5. yra3> yro3> yfi3. ycn2t> yca3> zi2> zy1s."
}

// The Lancaster stemmer; `out.len >= word.len + 2` (a rule may append).
fn lancaster(word: str, out: []u8) -> (str, err) {
    if out.len < word.len + 2usize { ret ("", TooSmall) }
    var w = out
    var n = word.len
    var i = 0usize
    while i < n {
        w[i] = lower(word[i])
        i += 1usize
    }
    let rules = lancaster_rules()
    var intact = true
    var proceed = n > 0usize
    while proceed {
        proceed = false
        let last = w[n - 1usize]
        var at = 0usize
        var applied = false
        while at < rules.len && !applied {
            // Parse one rule: reversed ending, optional *, a digit, an append, then . or >.
            var j = at
            while rules[j] >= 97u8 && rules[j] <= 122u8 { j += 1usize }
            let ending_end = j
            var only_intact = false
            if rules[j] == 42u8 {
                only_intact = true
                j += 1usize
            }
            let remove = usize(rules[j] - 48u8)
            j += 1usize
            let append_start = j
            while rules[j] >= 97u8 && rules[j] <= 122u8 { j += 1usize }
            let append_end = j
            let stop = rules[j] == 46u8
            j += 1usize
            let next = j + 1usize
            if rules[at] == last {
                // Does the word end in the ending (spelled backwards in the rule)?
                var matches = ending_end - at <= n
                var k = 0usize
                while matches && k < ending_end - at {
                    if w[n - 1usize - k] != rules[at + k] { matches = false }
                    k += 1usize
                }
                if matches && (!only_intact || intact) && lancaster_acceptable(w, n, remove) {
                    n -= remove
                    n = append(w, n, rules[append_start..append_end])
                    intact = false
                    applied = true
                    proceed = !stop && n > 0usize
                }
            }
            at = next
        }
    }
    ret (w[..n], ok)
}

// Remove any of `prefixes` from the front and any of `suffixes` from the
// back, longest match first and repeatedly, never below `minimum` bytes.
// The word is answered as a slice of itself.
fn strip_affixes(word: str, prefixes: []const str, suffixes: []const str, minimum: usize) -> str {
    var start = 0usize
    var end = word.len
    var changed = true
    while changed {
        changed = false
        var best = 0usize
        var i = 0usize
        while i < prefixes.len {
            let p = prefixes[i]
            if p.len > best && p.len <= end - start && end - start - p.len >= minimum && starts_at(word, start, p) { best = p.len }
            i += 1usize
        }
        if best > 0usize {
            start += best
            changed = true
        }
        best = 0usize
        i = 0usize
        while i < suffixes.len {
            let s = suffixes[i]
            if s.len > best && s.len <= end - start && end - start - s.len >= minimum && ends_with(word, end, s) { best = s.len }
            i += 1usize
        }
        if best > 0usize {
            end -= best
            changed = true
        }
    }
    ret word[start..end]
}

fn starts_at(word: str, start: usize, p: str) -> bool {
    if word.len - start < p.len { ret false }
    var i = 0usize
    while i < p.len {
        if word[start + i] != p[i] { ret false }
        i += 1usize
    }
    ret true
}

// The Snowball English stemmer (Porter2) as Snowball 3.1 defines it: the exception
// list, the y/Y prelude, R1 and R2 (with the prefix exceptions arsen commun emerg
// gener inter later organ past univers), steps 1a to 5 and the short-syllable rule
// with its `past` case. Vowels are a e i o u y; a y turned Y is a consonant.

fn sb_vowel(c: u8) -> bool { ret c == 97u8 || c == 101u8 || c == 105u8 || c == 111u8 || c == 117u8 || c == 121u8 }

fn sb_has_vowel(w: []const u8, from: usize, to: usize) -> bool {
    var i = from
    while i < to {
        if sb_vowel(w[i]) { ret true }
        i += 1usize
    }
    ret false
}

// The position after the first non-vowel that follows a vowel at or past `from`; `n`
// when there is none.
fn sb_region(w: []const u8, n: usize, from: usize) -> usize {
    var i = from
    while i < n && !sb_vowel(w[i]) { i += 1usize }
    while i < n && sb_vowel(w[i]) { i += 1usize }
    if i >= n { ret n }
    ret i + 1usize
}

// Whether `w[..m]` ends in a short syllable: non-vowel, vowel, non-vowel other than
// w x Y; or a vowel then a non-vowel as the whole word; or `past`.
fn sb_short_syllable(w: []const u8, m: usize) -> bool {
    if m >= 3usize {
        let c = w[m - 1usize]
        if !sb_vowel(c) && c != 119u8 && c != 120u8 && c != 89u8 && sb_vowel(w[m - 2usize]) && !sb_vowel(w[m - 3usize]) { ret true }
    }
    if m == 2usize && !sb_vowel(w[1usize]) && sb_vowel(w[0usize]) { ret true }
    ret ends_with(w, m, "past")
}

fn sb_double(w: []const u8, n: usize) -> bool {
    if n < 2usize || w[n - 1usize] != w[n - 2usize] { ret false }
    let c = w[n - 1usize]
    ret c == 98u8 || c == 100u8 || c == 102u8 || c == 103u8 || c == 109u8 || c == 110u8 || c == 112u8 || c == 114u8 || c == 116u8
}

fn sb_valid_li(c: u8) -> bool {
    ret c == 99u8 || c == 100u8 || c == 101u8 || c == 103u8 || c == 104u8 || c == 107u8 || c == 109u8 || c == 110u8 || c == 114u8 || c == 116u8
}

// The first rule of `rules` (`suffix=replacement;...`, longest suffixes first) whose
// suffix ends the word: applied when the stem reaches `region`. Answers the new length
// and whether any suffix matched (a match outside the region ends the step too).
fn sb_rules(w: []u8, n: usize, region: usize, rules: str) -> (usize, bool) {
    var i = 0usize
    while i < rules.len {
        var j = i
        while rules[j] != 61u8 { j += 1usize }
        var k = j + 1usize
        while k < rules.len && rules[k] != 59u8 { k += 1usize }
        let suffix = rules[i..j]
        if ends_with(w, n, suffix) {
            let stem = n - suffix.len
            if stem < region { ret (n, true) }
            ret (append(w, stem, rules[j + 1usize..k]), true)
        }
        i = k + 1usize
    }
    ret (n, false)
}

// The words stemmed by the exception list; answers the new length and whether the word
// was one of them.
fn sb_exception(w: []u8, n: usize) -> (usize, bool) {
    let rules = "andes=andes;atlas=atlas;bias=bias;cosmos=cosmos;early=earli;gently=gentl;howe=howe;idly=idl;news=news;only=onli;singly=singl;skies=sky;skis=ski;sky=sky;ugly=ugli"
    var i = 0usize
    while i < rules.len {
        var j = i
        while rules[j] != 61u8 { j += 1usize }
        var k = j + 1usize
        while k < rules.len && rules[k] != 59u8 { k += 1usize }
        if j - i == n && ends_with(w, n, rules[i..j]) { ret (append(w, 0usize, rules[j + 1usize..k]), true) }
        i = k + 1usize
    }
    ret (n, false)
}

fn sb_prefix_region(w: []const u8, n: usize) -> usize {
    let prefixes = "arsen;commun;emerg;gener;inter;later;organ;past;univers"
    var i = 0usize
    while i < prefixes.len {
        var k = i
        while k < prefixes.len && prefixes[k] != 59u8 { k += 1usize }
        if starts_at(w[..n], 0usize, prefixes[i..k]) { ret k - i }
        i = k + 1usize
    }
    ret sb_region(w, n, 0usize)
}

// The Snowball stem of `word`; `out.len >= word.len + 1`.
fn snowball(word: str, out: []u8) -> (str, err) {
    if out.len < word.len + 1usize { ret ("", TooSmall) }
    var w = out
    var n = word.len
    var i = 0usize
    while i < n {
        w[i] = lower(word[i])
        i += 1usize
    }
    let (special, is_special) = sb_exception(w, n)
    if is_special { ret (w[..special], ok) }
    if n < 3usize { ret (w[..n], ok) }
    // Prelude: a leading apostrophe goes; y is Y at the start and after a vowel.
    if w[0usize] == 39u8 {
        i = 1usize
        while i < n {
            w[i - 1usize] = w[i]
            i += 1usize
        }
        n -= 1usize
    }
    if n > 0usize && w[0usize] == 121u8 { w[0usize] = 89u8 }
    i = 1usize
    while i < n {
        if w[i] == 121u8 && sb_vowel(w[i - 1usize]) { w[i] = 89u8 }
        i += 1usize
    }
    let p1 = sb_prefix_region(w, n)
    let p2 = sb_region(w, n, p1)
    // Step 1a: possessives, then sses, ied/ies, s.
    if ends_with(w, n, "'s'") {
        n -= 3usize
    } else if ends_with(w, n, "'s") {
        n -= 2usize
    } else if ends_with(w, n, "'") {
        n -= 1usize
    }
    if ends_with(w, n, "sses") {
        n -= 2usize
    } else if ends_with(w, n, "ied") || ends_with(w, n, "ies") {
        if n - 3usize >= 2usize { n = append(w, n - 3usize, "i") } else { n = append(w, n - 3usize, "ie") }
    } else if ends_with(w, n, "s") && !ends_with(w, n, "ss") && !ends_with(w, n, "us") {
        if n >= 2usize && sb_has_vowel(w, 0usize, n - 2usize) { n -= 1usize }
    }
    // Step 1b: eed/eedly to ee in R1; ed/edly/ing/ingly deleted after a vowel, then
    // the at/bl/iz, double and short-word repairs.
    var suffix = 0usize
    var slen = 0usize
    if ends_with(w, n, "eedly") {
        suffix = 1usize
        slen = 5usize
    } else if ends_with(w, n, "ingly") {
        suffix = 2usize
        slen = 5usize
    } else if ends_with(w, n, "edly") {
        suffix = 2usize
        slen = 4usize
    } else if ends_with(w, n, "eed") {
        suffix = 1usize
        slen = 3usize
    } else if ends_with(w, n, "ing") {
        suffix = 3usize
        slen = 3usize
    } else if ends_with(w, n, "ed") {
        suffix = 2usize
        slen = 2usize
    }
    if suffix == 1usize {
        let stem = n - slen
        if stem >= p1 {
            let keep = (stem == 4usize && (ends_with(w, 4usize, "succ") || ends_with(w, 4usize, "proc"))) || (stem == 3usize && ends_with(w, 3usize, "exc"))
            if !keep { n = append(w, stem, "ee") }
        }
    } else if suffix != 0usize {
        var delete = true
        if suffix == 3usize {
            let stem = n - 3usize
            let whole4 = stem == 4usize && (ends_with(w, 4usize, "even") || ends_with(w, 4usize, "cann") || ends_with(w, 4usize, "earr") || ends_with(w, 4usize, "herr"))
            let whole3 = stem == 3usize && (ends_with(w, 3usize, "inn") || ends_with(w, 3usize, "out"))
            if whole4 || whole3 {
                delete = false
            } else if stem == 2usize && w[1usize] == 121u8 && !sb_vowel(w[0usize]) {
                n = append(w, 1usize, "ie")
                delete = false
            }
        }
        if delete {
            let stem = n - slen
            if sb_has_vowel(w, 0usize, stem) {
                n = stem
                if ends_with(w, n, "at") || ends_with(w, n, "bl") || ends_with(w, n, "iz") {
                    n = append(w, n, "e")
                } else if sb_double(w, n) {
                    let short_aeo = n == 3usize && (w[0usize] == 97u8 || w[0usize] == 101u8 || w[0usize] == 111u8)
                    if !short_aeo { n -= 1usize }
                } else if n == p1 && sb_short_syllable(w, n) {
                    n = append(w, n, "e")
                }
            }
        }
    }
    // Step 1c: a final y after a non-vowel that is not the first letter becomes i.
    if n >= 3usize && (w[n - 1usize] == 121u8 || w[n - 1usize] == 89u8) && !sb_vowel(w[n - 2usize]) { w[n - 1usize] = 105u8 }
    // Step 2, in R1.
    let (n2, matched2) = sb_rules(w, n, p1, "ational=ate;ization=ize;iveness=ive;fulness=ful;ousness=ous;tional=tion;lessli=less;biliti=ble;fulli=ful;ousli=ous;entli=ent;aliti=al;iviti=ive;alism=al;ation=ate;ogist=og;anci=ance;enci=ence;abli=able;alli=al;izer=ize;ator=ate;bli=ble")
    n = n2
    if !matched2 {
        if ends_with(w, n, "ogi") {
            if n - 3usize >= p1 && n >= 4usize && w[n - 4usize] == 108u8 { n = append(w, n - 3usize, "og") }
        } else if ends_with(w, n, "li") {
            if n - 2usize >= p1 && n >= 3usize && sb_valid_li(w[n - 3usize]) { n -= 2usize }
        }
    }
    // Step 3, in R1 (ative in R2).
    let (n3, matched3) = sb_rules(w, n, p1, "ational=ate;tional=tion;alize=al;icate=ic;iciti=ic;ical=ic;ness=;ful=")
    n = n3
    if !matched3 && ends_with(w, n, "ative") && n - 5usize >= p2 { n -= 5usize }
    // Step 4, in R2.
    let (n4, matched4) = sb_rules(w, n, p2, "ement=;ment=;ance=;ence=;able=;ible=;ant=;ent=;ism=;ate=;iti=;ous=;ive=;ize=;al=;er=;ic=")
    n = n4
    if !matched4 && ends_with(w, n, "ion") && n - 3usize >= p2 && n >= 4usize && (w[n - 4usize] == 115u8 || w[n - 4usize] == 116u8) { n -= 3usize }
    // Step 5.
    if ends_with(w, n, "e") {
        let stem = n - 1usize
        if stem >= p2 || (stem >= p1 && !sb_short_syllable(w, stem)) { n = stem }
    } else if ends_with(w, n, "l") && n - 1usize >= p2 && n >= 2usize && w[n - 2usize] == 108u8 {
        n -= 1usize
    }
    i = 0usize
    while i < n {
        if w[i] == 89u8 { w[i] = 121u8 }
        i += 1usize
    }
    ret (w[..n], ok)
}
