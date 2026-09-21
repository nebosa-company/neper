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
