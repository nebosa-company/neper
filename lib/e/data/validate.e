// Record validation (L031), after appdor's `src/validation/{validators,index,conditional,bulk,messages}.js`: the
// built-in format validators for field types (email, URL, E.164 phone, IPv4, CIDR, UUID, hashes, base64, ISO 3166-1
// membership, image sources, ratings, locations ...), `validate_record` over a table's field rules (required,
// format, min/max, length, pattern, option membership, validIf, uniqueness among live rows) and record-level
// rules, all violations at once with a severity each; conditional behavior (showIf / editableIf / requireIf, hidden
// fields skipped, containers that hide what they hold, non-constraining suggestions); initial values, auto-set
// rules and computed-write refusals; and set-wise checks (an import under the reject / skip / flag policy with
// intra-batch uniqueness, a backfill count for a candidate rule, fuzzy duplicate warnings).
//
// Rule expressions run through `e.algo.formula` (the registry is passed in, `library.build` makes the full one) and
// error results are false, so a broken rule fails safe. Identifier types (`iban`, `vin`, ...) answer through
// `e.algo.checksum` first, as appdor's `formatValidatorFor` unions them. Values are `e.algo.formula` values read as
// JavaScript reads the JSON they came from: `String(value)` of an array joins with commas, `Number("")` is 0.
//
// Differences from appdor's: an object value is opaque (its keys are not read, so an `{url}` attachment or
// `{lat, lng}` location is neither valid nor invalid on its own); `date` accepts ISO-8601 and the numeric forms V8's
// legacy parser reads; `image` URLs are the http(s) scheme with a non-empty host that does not end in `.invalid`;
// the message catalogue is the `Context.catalog` entries (locale, key, text), else the key itself, which is what
// appdor's answers with no bundle loaded; `pattern` is `e.text.regex`'s backtracking engine.

use e.algo.checksum as checksum
use e.algo.formula as f
use e.algo.formula.text as tx
use e.math
use e.mem
use e.str
use e.text.regex as regex
use e.text.utf8 as utf8

// --- JavaScript value reading -----------------------------------------------------------------------------------

fn js_space(u: u32) -> bool {
    if u == 32u32 || (u >= 9u32 && u <= 13u32) || u == 160u32 || u == 5760u32 || (u >= 8192u32 && u <= 8202u32) { ret true }
    ret u == 8232u32 || u == 8233u32 || u == 8239u32 || u == 8287u32 || u == 12288u32 || u == 65279u32
}

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn is_hex(c: u8) -> bool { ret is_digit(c) || (c >= 65u8 && c <= 70u8) || (c >= 97u8 && c <= 102u8) }

fn is_letter(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) }

fn is_word(c: u8) -> bool { ret is_digit(c) || is_letter(c) || c == 95u8 }

// `String.prototype.trim`.
fn js_trim(s: str) -> str {
    var from = 0usize
    var to = s.len
    var go = true
    while go && from < to {
        var it = utf8.iterator(s[from..to])
        let (scalar, got) = utf8.iterator_next(&it)
        if got && js_space(scalar) {
            if scalar < 128u32 {
                from += 1usize
            } else if scalar < 2048u32 {
                from += 2usize
            } else {
                from += 3usize
            }
        } else {
            go = false
        }
    }
    go = true
    while go && to > from {
        var k = to - 1usize
        while k > from && (s[k] & 192u8) == 128u8 { k -= 1usize }
        var it = utf8.iterator(s[k..to])
        let (scalar, got) = utf8.iterator_next(&it)
        if got && js_space(scalar) {
            to = k
        } else {
            go = false
        }
    }
    ret s[from..to]
}

// Whether the text has any JavaScript white space.
fn has_space(s: str) -> bool {
    var it = utf8.iterator(s)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got { more = false } else if js_space(scalar) { ret true }
    }
    ret false
}

// JavaScript's `String(value)` for a value read from JSON.
fn js_string(a: *mem.Arena, v: f.Value) -> str {
    if v.kind == .Text { ret v.s }
    if v.kind == .Number { ret f.number_text(a, v.n) }
    if v.kind == .Bool {
        if v.n != 0.0f64 { ret "true" }
        ret "false"
    }
    if v.kind == .Blank { ret "null" }
    if v.kind == .Date { ret f.date_js_string(a, v.n) }
    if v.kind == .Array {
        var out = ""
        var i = 0usize
        while i < v.items.len {
            if i > 0usize { out = f.join(a, out, ",") }
            if v.items[i].kind != .Blank { out = f.join(a, out, js_string(a, v.items[i])) }
            i += 1usize
        }
        ret out
    }
    ret "[object Object]"
}

// JavaScript's `Number(value)`.
fn js_number(a: *mem.Arena, v: f.Value) -> f64 {
    if v.kind == .Number || v.kind == .Date || v.kind == .Bool { ret v.n }
    if v.kind == .Blank { ret 0.0f64 }
    if v.kind == .Text {
        let t = js_trim(v.s)
        if t.len == 0usize { ret 0.0f64 }
        let (n, good) = f.parse_number_text(t)
        if good { ret n }
        ret f.nan()
    }
    if v.kind == .Array {
        if v.items.len == 0usize { ret 0.0f64 }
        if v.items.len > 1usize { ret f.nan() }
        let one = v.items[0usize]
        if one.kind == .Bool || one.kind == .Date || one.kind == .Record { ret f.nan() }
        ret js_number(a, one)
    }
    ret f.nan()
}

fn is_nan(x: f64) -> bool { ret x != x }

// JavaScript's `Number.isFinite`.
fn is_finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

// A value is blank when it is null, undefined, `''` or an empty array.
fn is_blank(v: f.Value) -> bool {
    if v.kind == .Blank { ret true }
    if v.kind == .Text && v.s.len == 0usize { ret true }
    ret v.kind == .Array && v.items.len == 0usize
}

// The value of a field of a record; blank when it has none.
fn lookup(fields: []const f.Field, name: str) -> f.Value {
    var i = 0usize
    while i < fields.len {
        if str.eq(fields[i].name, name) { ret fields[i].value }
        i += 1usize
    }
    ret f.blank()
}

fn has_field(fields: []const f.Field, name: str) -> bool {
    var i = 0usize
    while i < fields.len {
        if str.eq(fields[i].name, name) { ret true }
        i += 1usize
    }
    ret false
}

// The record is soft-deleted: `is_deleted === true` or a `deleted_at` that is not null or undefined.
fn is_deleted(fields: []const f.Field) -> bool {
    let flag = lookup(fields, "is_deleted")
    if flag.kind == .Bool && flag.n != 0.0f64 { ret true }
    ret lookup(fields, "deleted_at").kind != .Blank
}

// Code points of a text (`[...String(str)].length`).
fn code_point_length(s: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if (s[i] & 192u8) != 128u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

fn upper_ascii(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

fn lower_ascii(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

fn all_chars(s: str, from: usize, to: usize, kind: u8) -> bool {
    if to > s.len { ret false }
    var i = from
    while i < to {
        let c = s[i]
        var ok_char = false
        if kind == 100u8 { ok_char = is_digit(c) }
        if kind == 120u8 { ok_char = is_hex(c) }
        if kind == 65u8 { ok_char = c >= 65u8 && c <= 90u8 }
        if kind == 97u8 { ok_char = c >= 97u8 && c <= 122u8 }
        if kind == 110u8 { ok_char = is_digit(c) || (c >= 65u8 && c <= 90u8) }
        if !ok_char { ret false }
        i += 1usize
    }
    ret true
}

// --- format validators --------------------------------------------------------------------------------------------

// `/^[^\s@]+@[^\s@]+\.[^\s@]+$/`
fn is_email(s: str) -> bool {
    if has_space(s) { ret false }
    var at = s.len
    var count = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] == 64u8 {
            if count == 0usize { at = i }
            count += 1usize
        }
        i += 1usize
    }
    if count != 1usize || at == 0usize || at + 1usize >= s.len { ret false }
    // the domain: X.Y with X and Y non-empty
    let domain = s[at + 1usize..s.len]
    var k = 1usize
    while k + 1usize < domain.len {
        if domain[k] == 46u8 { ret true }
        k += 1usize
    }
    ret false
}

// `/^(https?:\/\/)?([\w-]+\.)+[\w-]+(:\d+)?(\/[^\s]*)?$/i`
fn is_url(a: *mem.Arena, s: str) -> bool {
    var p = 0usize
    let lowered = lower_ascii(a, s)
    if str.starts_with(lowered, "https://") {
        p = 8usize
    } else if str.starts_with(lowered, "http://") {
        p = 7usize
    }
    // host: [\w.-]+ split by `.` into at least two non-empty labels
    var q = p
    while q < s.len && (is_word(s[q]) || s[q] == 45u8 || s[q] == 46u8) { q += 1usize }
    let host = s[p..q]
    if host.len == 0usize { ret false }
    var labels = 0usize
    var start = 0usize
    var i = 0usize
    while i <= host.len {
        if i == host.len || host[i] == 46u8 {
            if i == start { ret false }
            labels += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    if labels < 2usize { ret false }
    var r = q
    if r < s.len && s[r] == 58u8 {
        var d = r + 1usize
        while d < s.len && is_digit(s[d]) { d += 1usize }
        if d == r + 1usize { ret false }
        r = d
    }
    if r == s.len { ret true }
    if s[r] != 47u8 { ret false }
    ret !has_space(s[r..s.len])
}

// `/^\+?[1-9]\d{1,14}$/` over the text with `\s`, `(`, `)` and `-` removed.
fn is_phone(a: *mem.Arena, s: str) -> bool {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret false }
    var n = 0usize
    var it = utf8.iterator(s)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else if !js_space(scalar) && scalar != 40u32 && scalar != 41u32 && scalar != 45u32 {
            if scalar >= 128u32 { ret false }
            out[n] = u8(scalar)
            n += 1usize
        }
    }
    var p = 0usize
    if n > 0usize && out[0usize] == 43u8 { p = 1usize }
    let digits = n - p
    if digits < 2usize || digits > 15usize { ret false }
    if out[p] < 49u8 || out[p] > 57u8 { ret false }
    var i = p
    while i < n {
        if !is_digit(out[i]) { ret false }
        i += 1usize
    }
    ret true
}

// One dotted-quad octet: 0-255 with no leading zero.
fn is_octet(s: str) -> bool {
    if s.len == 0usize || s.len > 3usize || !all_chars(s, 0usize, s.len, 100u8) { ret false }
    if s.len > 1usize && s[0usize] == 48u8 { ret false }
    var v = 0usize
    var i = 0usize
    while i < s.len {
        v = v * 10usize + usize(s[i] - 48u8)
        i += 1usize
    }
    ret v <= 255usize
}

fn is_ipv4(s: str) -> bool {
    var parts = 0usize
    var start = 0usize
    var i = 0usize
    while i <= s.len {
        if i == s.len || s[i] == 46u8 {
            if !is_octet(s[start..i]) { ret false }
            parts += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret parts == 4usize
}

// `/^((ipv4)|[\da-fA-F:]+)\/(\d{1,3})$/` and a prefix of at most 128.
fn is_cidr(s: str) -> bool {
    var slash = s.len
    var i = 0usize
    while i < s.len {
        if s[i] == 47u8 { slash = i }
        i += 1usize
    }
    if slash == s.len { ret false }
    let prefix = s[slash + 1usize..s.len]
    if prefix.len < 1usize || prefix.len > 3usize || !all_chars(prefix, 0usize, prefix.len, 100u8) { ret false }
    // appdor's check reads capture group 4 of its pattern, which is the LAST OCTET of an IPv4 address (undefined for
    // the IPv6 alternative), not the prefix: an IPv4 CIDR is valid when its last octet is at most 128, and an
    // IPv6 one never is. The prefix itself is any one to three digits.
    let head = s[0usize..slash]
    if !is_ipv4(head) { ret false }
    var last_start = 0usize
    i = 0usize
    while i < head.len {
        if head[i] == 46u8 { last_start = i + 1usize }
        i += 1usize
    }
    var last = 0usize
    i = last_start
    while i < head.len {
        last = last * 10usize + usize(head[i] - 48u8)
        i += 1usize
    }
    ret last <= 128usize
}

fn is_uuid(s: str) -> bool {
    if s.len != 36usize { ret false }
    var i = 0usize
    while i < 36usize {
        if i == 8usize || i == 13usize || i == 18usize || i == 23usize {
            if s[i] != 45u8 { ret false }
        } else if !is_hex(s[i]) {
            ret false
        }
        i += 1usize
    }
    ret true
}

fn is_short_uuid(s: str) -> bool {
    if s.len < 8usize || s.len > 22usize { ret false }
    var i = 0usize
    while i < s.len {
        let c = s[i]
        let letter = (c >= 65u8 && c <= 90u8 && c != 73u8 && c != 79u8) || (c >= 97u8 && c <= 122u8 && c != 108u8 && c != 111u8)
        let digit = c >= 50u8 && c <= 57u8
        if !letter && !digit { ret false }
        i += 1usize
    }
    ret true
}

fn is_hex_len(s: str, n: usize) -> bool { ret s.len == n && all_chars(s, 0usize, n, 120u8) }

// `/^[A-Za-z0-9+/]*={0,2}$/`
fn is_base64(s: str) -> bool {
    var end = s.len
    var pad = 0usize
    while end > 0usize && s[end - 1usize] == 61u8 && pad < 2usize {
        end -= 1usize
        pad += 1usize
    }
    var i = 0usize
    while i < end {
        let c = s[i]
        if !(is_digit(c) || is_letter(c) || c == 43u8 || c == 47u8) { ret false }
        i += 1usize
    }
    ret true
}

fn digits_between(s: str, low: usize, high: usize) -> bool { ret s.len >= low && s.len <= high && all_chars(s, 0usize, s.len, 100u8) }

// `/^[A-Z][a-z]+(?:\/[A-Z][a-z_]+)+$/`
fn is_tzdb(s: str) -> bool {
    var segments = 0usize
    var start = 0usize
    var i = 0usize
    while i <= s.len {
        if i == s.len || s[i] == 47u8 {
            let part = s[start..i]
            if part.len < 2usize { ret false }
            if !(part[0usize] >= 65u8 && part[0usize] <= 90u8) { ret false }
            var k = 1usize
            while k < part.len {
                let c = part[k]
                let lower = c >= 97u8 && c <= 122u8
                if !(lower || (segments > 0usize && c == 95u8)) { ret false }
                k += 1usize
            }
            segments += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret segments >= 2usize
}

fn iso3166_pairs() -> str {
    ret "AD/AND AE/ARE AF/AFG AG/ATG AI/AIA AL/ALB AM/ARM AO/AGO AQ/ATA AR/ARG AS/ASM AT/AUT AU/AUS AW/ABW AX/ALA AZ/AZE BA/BIH BB/BRB BD/BGD BE/BEL BF/BFA BG/BGR BH/BHR BI/BDI BJ/BEN BL/BLM BM/BMU BN/BRN BO/BOL BQ/BES BR/BRA BS/BHS BT/BTN BV/BVT BW/BWA BY/BLR BZ/BLZ CA/CAN CC/CCK CD/COD CF/CAF CG/COG CH/CHE CI/CIV CK/COK CL/CHL CM/CMR CN/CHN CO/COL CR/CRI CU/CUB CV/CPV CW/CUW CX/CXR CY/CYP CZ/CZE DE/DEU DJ/DJI DK/DNK DM/DMA DO/DOM DZ/DZA EC/ECU EE/EST EG/EGY EH/ESH ER/ERI ES/ESP ET/ETH FI/FIN FJ/FJI FK/FLK FM/FSM FO/FRO FR/FRA GA/GAB GB/GBR GD/GRD GE/GEO GF/GUF GG/GGY GH/GHA GI/GIB GL/GRL GM/GMB GN/GIN GP/GLP GQ/GNQ GR/GRC GS/SGS GT/GTM GU/GUM GW/GNB GY/GUY HK/HKG HM/HMD HN/HND HR/HRV HT/HTI HU/HUN ID/IDN IE/IRL IL/ISR IM/IMN IN/IND IO/IOT IQ/IRQ IR/IRN IS/ISL IT/ITA JE/JEY JM/JAM JO/JOR JP/JPN KE/KEN KG/KGZ KH/KHM KI/KIR KM/COM KN/KNA KP/PRK KR/KOR KW/KWT KY/CYM KZ/KAZ LA/LAO LB/LBN LC/LCA LI/LIE LK/LKA LR/LBR LS/LSO LT/LTU LU/LUX LV/LVA LY/LBY MA/MAR MC/MCO MD/MDA ME/MNE MF/MAF MG/MDG MH/MHL MK/MKD ML/MLI MM/MMR MN/MNG MO/MAC MP/MNP MQ/MTQ MR/MRT MS/MSR MT/MLT MU/MUS MV/MDV MW/MWI MX/MEX MY/MYS MZ/MOZ NA/NAM NC/NCL NE/NER NF/NFK NG/NGA NI/NIC NL/NLD NO/NOR NP/NPL NR/NRU NU/NIU NZ/NZL OM/OMN PA/PAN PE/PER PF/PYF PG/PNG PH/PHL PK/PAK PL/POL PM/SPM PN/PCN PR/PRI PS/PSE PT/PRT PW/PLW PY/PRY QA/QAT RE/REU RO/ROU RS/SRB RU/RUS RW/RWA SA/SAU SB/SLB SC/SYC SD/SDN SE/SWE SG/SGP SH/SHN SI/SVN SJ/SJM SK/SVK SL/SLE SM/SMR SN/SEN SO/SOM SR/SUR SS/SSD ST/STP SV/SLV SX/SXM SY/SYR SZ/SWZ TC/TCA TD/TCD TF/ATF TG/TGO TH/THA TJ/TJK TK/TKL TL/TLS TM/TKM TN/TUN TO/TON TR/TUR TT/TTO TV/TUV TW/TWN TZ/TZA UA/UKR UG/UGA UM/UMI US/USA UY/URY UZ/UZB VA/VAT VC/VCT VE/VEN VG/VGB VI/VIR VN/VNM VU/VUT WF/WLF WS/WSM YE/YEM YT/MYT ZA/ZAF ZM/ZMB ZW/ZWE XK/XKX XI/"
}

// Membership in ISO 3166-1: alpha-2 (`wide` false) or alpha-3, with the two user-assigned codes in real use.
fn is_iso3166(a: *mem.Arena, value: str, alpha3: bool) -> bool {
    let s = upper_ascii(a, js_trim(value))
    var want = 2usize
    if alpha3 { want = 3usize }
    if s.len != want { ret false }
    let pairs = iso3166_pairs()
    var i = 0usize
    while i + 2usize <= pairs.len {
        var entry_end = i
        while entry_end < pairs.len && pairs[entry_end] != 32u8 { entry_end += 1usize }
        let entry = pairs[i..entry_end]
        if alpha3 {
            if entry.len >= 6usize && str.eq(entry[3usize..entry.len], s) { ret true }
        } else if str.eq(entry[0usize..2usize], s) {
            ret true
        }
        i = entry_end + 1usize
    }
    ret false
}

fn data_uri_image(s: str) -> bool {
    // data:image/<[a-z0-9.+-]+>;base64,<[A-Za-z0-9+/]+>={0,2} (case-insensitive prefix)
    if s.len < 12usize { ret false }
    var buffer: [11]u8 = zero
    var k = 0usize
    while k < 11usize {
        var c = s[k]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        buffer[k] = c
        k += 1usize
    }
    if !(buffer[0usize] == 100u8 && buffer[1usize] == 97u8 && buffer[2usize] == 116u8 && buffer[3usize] == 97u8 && buffer[4usize] == 58u8 && buffer[5usize] == 105u8 && buffer[6usize] == 109u8 && buffer[7usize] == 97u8 && buffer[8usize] == 103u8 && buffer[9usize] == 101u8 && buffer[10usize] == 47u8) { ret false }
    var p = 11usize
    let kind_from = p
    while p < s.len && (is_digit(s[p]) || is_letter(s[p]) || s[p] == 46u8 || s[p] == 43u8 || s[p] == 45u8) { p += 1usize }
    if p == kind_from { ret false }
    let marker = ";base64,"
    if p + marker.len > s.len || !str.eq(s[p..p + marker.len], marker) { ret false }
    p += marker.len
    let payload = s[p..s.len]
    if payload.len == 0usize { ret false }
    var end = payload.len
    var pad = 0usize
    while end > 0usize && payload[end - 1usize] == 61u8 && pad < 2usize {
        end -= 1usize
        pad += 1usize
    }
    if end == 0usize { ret false }
    var i = 0usize
    while i < end {
        let c = payload[i]
        if !(is_digit(c) || is_letter(c) || c == 43u8 || c == 47u8) { ret false }
        i += 1usize
    }
    ret true
}

// An image cell's value: an http(s) URL with a host that can resolve, a root-relative path, or an image data URI.
fn is_image_text(a: *mem.Arena, raw: str) -> bool {
    let s = js_trim(raw)
    if s.len == 0usize { ret true }
    if data_uri_image(s) { ret true }
    if s[0usize] == 47u8 && !(s.len > 1usize && s[1usize] == 47u8) { ret true }
    var lower = lower_ascii(a, s)
    var p = 0usize
    if str.starts_with(lower, "https:") {
        p = 6usize
    } else if str.starts_with(lower, "http:") {
        p = 5usize
    } else {
        ret false
    }
    while p < s.len && (s[p] == 47u8 || s[p] == 92u8) { p += 1usize }
    var q = p
    while q < s.len && s[q] != 47u8 && s[q] != 63u8 && s[q] != 35u8 && s[q] != 92u8 { q += 1usize }
    var authority = s[p..q]
    var at = authority.len
    var i = 0usize
    while i < authority.len {
        if authority[i] == 64u8 { at = i }
        i += 1usize
    }
    if at < authority.len { authority = authority[at + 1usize..authority.len] }
    var host_end = authority.len
    i = 0usize
    while i < authority.len {
        if authority[i] == 58u8 {
            host_end = i
            i = authority.len
        } else {
            i += 1usize
        }
    }
    let host = authority[0usize..host_end]
    if host.len == 0usize || has_space(host) { ret false }
    let host_lower = lower_ascii(a, host)
    ret !str.ends_with(host_lower, ".invalid")
}

fn is_image_value(a: *mem.Arena, v: f.Value) -> bool {
    if v.kind == .Array {
        var i = 0usize
        while i < v.items.len {
            if !is_image_value(a, v.items[i]) { ret false }
            i += 1usize
        }
        ret true
    }
    if v.kind == .Record { ret false }
    if v.kind == .Blank { ret true }
    ret is_image_text(a, js_string(a, v))
}

// `isEarthCoords` over two number texts.
fn on_earth(a: *mem.Arena, lat: f64, lng: f64) -> bool {
    ret is_finite(lat) && is_finite(lng) && lat >= -90.0f64 && lat <= 90.0f64 && lng >= -180.0f64 && lng <= 180.0f64
}

// The "lat,lng" shorthand: `-?\d+(\.\d+)?\s*[,;]\s*-?\d+(\.\d+)?`, both halves (empty when it is not that shape).
fn coord_halves(s: str) -> (str, str, bool) {
    var sep = s.len
    var i = 0usize
    while i < s.len {
        if s[i] == 44u8 || s[i] == 59u8 {
            sep = i
            i = s.len
        } else {
            i += 1usize
        }
    }
    if sep == s.len { ret ("", "", false) }
    let left = trim_end_space(s[0usize..sep])
    let right = js_trim_start(s[sep + 1usize..s.len])
    if !is_decimal_text(left) || !is_decimal_text(right) { ret ("", "", false) }
    ret (left, right, true)
}

fn trim_end_space(s: str) -> str {
    var to = s.len
    while to > 0usize && (s[to - 1usize] == 32u8 || (s[to - 1usize] >= 9u8 && s[to - 1usize] <= 13u8)) { to -= 1usize }
    ret s[0usize..to]
}

fn js_trim_start(s: str) -> str {
    var from = 0usize
    while from < s.len && (s[from] == 32u8 || (s[from] >= 9u8 && s[from] <= 13u8)) { from += 1usize }
    ret s[from..s.len]
}

// `-?\d+(?:\.\d+)?`
fn is_decimal_text(s: str) -> bool {
    var p = 0usize
    if p < s.len && s[p] == 45u8 { p += 1usize }
    let int_from = p
    while p < s.len && is_digit(s[p]) { p += 1usize }
    if p == int_from { ret false }
    if p == s.len { ret true }
    if s[p] != 46u8 { ret false }
    p += 1usize
    let frac_from = p
    while p < s.len && is_digit(s[p]) { p += 1usize }
    ret p > frac_from && p == s.len
}

fn text_number(s: str) -> f64 {
    let (v, e) = str.parse_f64(s)
    if e != ok { ret f.nan() }
    ret v
}

// The format validator of a field type: the answer, and whether there is one.
fn format_check(a: *mem.Arena, type_name: str, v: f.Value) -> (bool, bool) {
    let text = js_string(a, v)
    let (spec_answer, spec_known) = checksum.validate(a, type_name, text)
    if spec_known { ret (spec_answer, true) }
    if str.eq(type_name, "email") { ret (is_email(text), true) }
    if str.eq(type_name, "url") { ret (is_url(a, text), true) }
    if str.eq(type_name, "phone") { ret (is_phone(a, text), true) }
    if str.eq(type_name, "ip") || str.eq(type_name, "ipv4") { ret (is_ipv4(text), true) }
    if str.eq(type_name, "number") || str.eq(type_name, "currency") || str.eq(type_name, "percent") {
        if v.kind == .Blank || (v.kind == .Text && v.s.len == 0usize) { ret (false, true) }
        ret (!is_nan(js_number(a, v)), true)
    }
    if str.eq(type_name, "date") {
        if v.kind == .Number { ret (is_finite(v.n) && v.n <= 8640000000000000.0f64 && v.n >= -8640000000000000.0f64, true) }
        if v.kind == .Bool || v.kind == .Blank { ret (true, true) }
        if v.kind == .Date { ret (v.n == v.n, true) }
        let (ms, good) = f.parse_date_text(js_trim(text))
        ret (good && ms == ms, true)
    }
    if str.eq(type_name, "uuid") { ret (is_uuid(text), true) }
    if str.eq(type_name, "short-uuid") { ret (is_short_uuid(text), true) }
    if str.eq(type_name, "sha-256") { ret (is_hex_len(text, 64usize), true) }
    if str.eq(type_name, "sha-1") { ret (is_hex_len(text, 40usize), true) }
    if str.eq(type_name, "md5") { ret (is_hex_len(text, 32usize), true) }
    if str.eq(type_name, "crc32") { ret (is_hex_len(text, 8usize), true) }
    if str.eq(type_name, "base64") { ret (is_base64(text), true) }
    if str.eq(type_name, "cidr") { ret (is_cidr(text), true) }
    if str.eq(type_name, "imsi") { ret (digits_between(text, 14usize, 15usize), true) }
    if str.eq(type_name, "iccid") { ret (digits_between(text, 19usize, 20usize), true) }
    if str.eq(type_name, "cpt") {
        ret (text.len == 5usize && all_chars(text, 0usize, 4usize, 100u8) && (is_digit(text[4usize]) || is_letter(text[4usize])), true)
    }
    if str.eq(type_name, "ssn") {
        let (out, e) = mem.alloc[u8](a, text.len + 1usize)
        if e != ok { ret (false, true) }
        var n = 0usize
        var i = 0usize
        while i < text.len {
            if text[i] != 45u8 {
                out[n] = text[i]
                n += 1usize
            }
            i += 1usize
        }
        ret (n == 9usize && all_chars(out[0usize..n], 0usize, n, 100u8), true)
    }
    if str.eq(type_name, "pnr") {
        let u = upper_ascii(a, text)
        ret (u.len == 6usize && all_chars(u, 0usize, 6usize, 110u8), true)
    }
    if str.eq(type_name, "airport") || str.eq(type_name, "iso-4217") {
        let u = upper_ascii(a, text)
        ret (u.len == 3usize && all_chars(u, 0usize, 3usize, 65u8), true)
    }
    if str.eq(type_name, "flight") {
        let u = upper_ascii(a, text)
        ret (u.len >= 3usize && u.len <= 6usize && all_chars(u, 0usize, 2usize, 65u8) && all_chars(u, 2usize, u.len, 100u8), true)
    }
    if str.eq(type_name, "ticker") {
        let u = upper_ascii(a, text)
        ret (u.len >= 1usize && u.len <= 5usize && all_chars(u, 0usize, u.len, 65u8), true)
    }
    if str.eq(type_name, "passport") {
        let u = upper_ascii(a, text)
        ret (u.len >= 6usize && u.len <= 9usize && all_chars(u, 0usize, u.len, 110u8), true)
    }
    if str.eq(type_name, "usps-state") {
        let u = upper_ascii(a, text)
        ret (u.len == 2usize && all_chars(u, 0usize, 2usize, 65u8), true)
    }
    if str.eq(type_name, "fips") { ret ((text.len == 2usize || text.len == 5usize) && all_chars(text, 0usize, text.len, 100u8), true) }
    if str.eq(type_name, "unspsc") { ret (text.len == 8usize && all_chars(text, 0usize, 8usize, 100u8), true) }
    if str.eq(type_name, "iso-639") {
        let l = lower_ascii(a, text)
        ret (l.len >= 2usize && l.len <= 3usize && all_chars(l, 0usize, l.len, 97u8), true)
    }
    if str.eq(type_name, "tzdb") { ret (is_tzdb(text), true) }
    if str.eq(type_name, "calling-code") {
        ret (text.len >= 2usize && text.len <= 4usize && text[0usize] == 43u8 && all_chars(text, 1usize, text.len, 100u8), true)
    }
    if str.eq(type_name, "iso-3166-2") { ret (is_iso3166(a, text, false), true) }
    if str.eq(type_name, "iso-3166-3") { ret (is_iso3166(a, text, true), true) }
    if str.eq(type_name, "image") { ret (is_image_value(a, v), true) }
    if str.eq(type_name, "rating") {
        let n = js_number(a, v)
        ret (is_finite(n) && n >= 0.0f64, true)
    }
    if str.eq(type_name, "location") {
        if v.kind == .Record { ret (true, true) }
        let s = js_trim(text)
        if s.len == 0usize { ret (true, true) }
        let (lat, lng, shorthand) = coord_halves(s)
        if !shorthand { ret (true, true) }
        ret (on_earth(a, text_number(lat), text_number(lng)), true)
    }
    ret (false, false)
}

// The field types whose values the engine computes and which reject direct writes.
fn is_computed_type(t: str) -> bool {
    ret str.eq(t, "formula") || str.eq(t, "rollup") || str.eq(t, "count") || str.eq(t, "lookup") || str.eq(t, "autonumber") || str.eq(t, "created-time") || str.eq(t, "last-modified-time") || str.eq(t, "last-modified-by") || str.eq(t, "created-by")
}

// --- definitions --------------------------------------------------------------------------------------------------

// A field definition: what the rules read. `show_if`, `editable_if`, `require_if`, `pattern` and the like are empty
// when absent; a `has_*` flag marks a number or value that may legitimately be zero or blank.
type Definition = struct {
    name: str,
    label: str,
    type_name: str,
    required: bool,
    computed: bool,
    show_if: str,
    editable_if: str,
    require_if: str,
    has_min: bool,
    min: f.Value,
    has_max: bool,
    max: f.Value,
    has_min_length: bool,
    min_length: f64,
    has_max_length: bool,
    max_length: f64,
    pattern: str,
    has_options: bool,
    options: []const f.Value,
    allow_user_input: bool,
    has_limit: bool,
    limit: f64,
    valid_if: []const str,
    unique: bool,
    unique_case_sensitive: bool,
    messages: []const f.Field,
    severities: []const f.Field,
    severity: str,
    has_auto_set: bool,
    auto_when: str,
    auto_value: str,
    auto_replace: bool,
    initial_value: str,
    has_default: bool,
    default_value: f.Value,
    suggested_values: str,
    has_suggestion_limit: bool,
    suggestion_limit: f64,
}

// A record-level rule: an expression that must be true, with an optional field it is reported against.
type Rule = struct {
    id: str,
    has_id: bool,
    field: str,
    has_field: bool,
    expression: str,
    message: str,
    severity: str,
    inactive: bool,
}

type Table = struct { fields: []const Definition, rules: []const Rule }

// One stored or incoming record.
type Row = struct { fields: []const f.Field }

type Message = struct { locale: str, key: str, text: str }

// What a validation runs against: the stored rows (and which of them is the record itself, -1 for none), the
// locale, the formula context (clock, host values) and the message catalogue.
type Context = struct {
    locale: str,
    has_existing: bool,
    existing: []const Row,
    self_index: i64,
    base: f.Context,
    is_new: bool,
    prior: []const f.Field,
    has_prior: bool,
    catalog: []const Message,
}

type Violation = struct { field: str, has_field: bool, code: str, severity: str, rule_id: str, has_rule_id: bool, message: str }

type Outcome = struct { valid: bool, violations: []const Violation }

// A fresh context for a locale.
fn context(locale: str) -> Context {
    var no_rows: []const Row = zero
    var no_fields: []const f.Field = zero
    var no_messages: []const Message = zero
    var base: f.Context = zero
    ret Context { locale: locale, has_existing: false, existing: no_rows, self_index: -1i64, base: base, is_new: false, prior: no_fields, has_prior: false, catalog: no_messages }
}

fn blank_definition() -> Definition {
    var d: Definition = zero
    d.default_value = f.blank()
    d.min = f.blank()
    d.max = f.blank()
    ret d
}

// --- evaluation -----------------------------------------------------------------------------------------------------

// The truth of a rule expression's value: an error is false (a broken rule fails safe).
fn truthy(v: f.Value) -> bool {
    if v.kind == .Error { ret false }
    if v.kind == .Bool { ret v.n != 0.0f64 }
    if v.kind == .Blank { ret false }
    if v.kind == .Text { ret v.s.len > 0usize }
    if v.kind == .Number { ret v.n != 0.0f64 }
    if v.kind == .Array { ret v.items.len > 0usize }
    ret true
}

// Evaluate `expr` over `record`'s fields.
fn eval_expr(a: *mem.Arena, reg: *const f.Registry, expr: str, record: []const f.Field, ctx: *const Context) -> f.Value {
    var fc = ctx.base
    fc.fields = record
    fc.is_new = ctx.is_new
    fc.prior = ctx.prior
    fc.has_prior = ctx.has_prior
    ret f.evaluate(a, expr, &fc, reg)
}

fn is_computed_field(d: Definition) -> bool { ret d.computed || is_computed_type(d.type_name) }

// A field's live behavior against a record.
type Behavior = struct { visible: bool, editable: bool, required: bool }

fn field_behavior(a: *mem.Arena, reg: *const f.Registry, d: Definition, record: []const f.Field, ctx: *const Context) -> Behavior {
    var visible = true
    if d.show_if.len > 0usize { visible = truthy(eval_expr(a, reg, d.show_if, record, ctx)) }
    var editable = true
    if is_computed_field(d) {
        editable = false
    } else if d.editable_if.len > 0usize {
        editable = truthy(eval_expr(a, reg, d.editable_if, record, ctx))
    }
    var required = d.required
    if visible && d.require_if.len > 0usize {
        required = required || truthy(eval_expr(a, reg, d.require_if, record, ctx))
    }
    if !visible { required = false }
    ret Behavior { visible: visible, editable: editable, required: required }
}

// --- messages ---------------------------------------------------------------------------------------------------

// A `{Token}` template filled from `params` (first) then the record's values; a missing token is empty.
fn interpolate(a: *mem.Arena, template: str, params: []const f.Field, record: []const f.Field) -> str {
    var out = ""
    var i = 0usize
    while i < template.len {
        if template[i] == 123u8 {
            var close = template.len
            var k = i + 1usize
            while k < template.len {
                if template[k] == 125u8 {
                    close = k
                    k = template.len
                } else {
                    k += 1usize
                }
            }
            if close < template.len && close > i + 1usize {
                let key = js_trim(template[i + 1usize..close])
                var value = f.blank()
                var found = false
                var p = 0usize
                while p < params.len && !found {
                    if str.eq(params[p].name, key) && params[p].value.kind != .Blank {
                        value = params[p].value
                        found = true
                    }
                    p += 1usize
                }
                if !found {
                    let r = lookup(record, key)
                    if r.kind != .Blank {
                        value = r
                        found = true
                    }
                }
                if found { out = f.join(a, out, js_string(a, value)) }
                i = close + 1usize
            } else {
                // a `{` with no matching `}` or nothing inside is plain text
                out = f.join(a, out, template[i..i + 1usize])
                i += 1usize
            }
        } else {
            var j = i
            while j < template.len && template[j] != 123u8 { j += 1usize }
            out = f.join(a, out, template[i..j])
            i = j
        }
    }
    ret out
}

// The localized default of a rule code: the catalogue entry for the locale, then `en`, then the key itself.
fn default_message(a: *mem.Arena, ctx: *const Context, code: str, params: []const f.Field, record: []const f.Field) -> str {
    var key = "validation.validIf"
    if str.eq(code, "required") || str.eq(code, "requireIf") { key = "validation.required" }
    if str.eq(code, "min") { key = "validation.min" }
    if str.eq(code, "max") { key = "validation.max" }
    if str.eq(code, "minLength") { key = "validation.minLength" }
    if str.eq(code, "maxLength") { key = "validation.maxLength" }
    if str.eq(code, "pattern") { key = "validation.pattern" }
    if str.eq(code, "format") { key = "validation.format" }
    if str.eq(code, "membership") { key = "validation.membership" }
    if str.eq(code, "editableIf") { key = "validation.editableIf" }
    if str.eq(code, "unique") { key = "validation.unique" }
    if str.eq(code, "computed") { key = "validation.computed" }
    if str.eq(code, "record") { key = "validation.record" }
    if str.eq(code, "tooManyFiles") { key = "validation.tooManyFiles" }
    if str.eq(code, "fileTooLarge") { key = "validation.fileTooLarge" }
    if str.eq(code, "fileTypeRejected") { key = "validation.fileTypeRejected" }
    var i = 0usize
    while i < ctx.catalog.len {
        if str.eq(ctx.catalog[i].key, key) && str.eq(ctx.catalog[i].locale, ctx.locale) { ret interpolate(a, ctx.catalog[i].text, params, record) }
        i += 1usize
    }
    i = 0usize
    while i < ctx.catalog.len {
        if str.eq(ctx.catalog[i].key, key) && str.eq(ctx.catalog[i].locale, "en") { ret interpolate(a, ctx.catalog[i].text, params, record) }
        i += 1usize
    }
    ret interpolate(a, key, params, record)
}

// A rule's message: the custom text (interpolated) or the localized default.
fn resolve_message(a: *mem.Arena, ctx: *const Context, custom: str, code: str, params: []const f.Field, record: []const f.Field) -> str {
    if custom.len > 0usize { ret interpolate(a, custom, params, record) }
    ret default_message(a, ctx, code, params, record)
}

// --- validation -------------------------------------------------------------------------------------------------

type Sink = struct { items: []Violation, count: usize }

fn push(s: *Sink, v: Violation) {
    if s.count < s.items.len {
        s.items[s.count] = v
        s.count += 1usize
    }
}

fn named_text(fields: []const f.Field, name: str) -> (str, bool) {
    var i = 0usize
    while i < fields.len {
        if str.eq(fields[i].name, name) && fields[i].value.kind == .Text { ret (fields[i].value.s, true) }
        i += 1usize
    }
    ret ("", false)
}

// A comparable number for range checks: a date's time, else `Number(value)`; false when it is not numeric.
fn comparable(a: *mem.Arena, v: f.Value, type_name: str) -> (f64, bool) {
    if v.kind == .Blank || (v.kind == .Text && v.s.len == 0usize) { ret (0.0f64, false) }
    if str.eq(type_name, "date") || str.eq(type_name, "datetime") {
        var t = f.nan()
        if v.kind == .Number || v.kind == .Date {
            t = v.n
        } else if v.kind == .Text {
            let (ms, good) = f.parse_date_text(js_trim(v.s))
            if good { t = ms }
        } else if v.kind == .Bool {
            t = v.n
        }
        if t != t { ret (0.0f64, false) }
        ret (t, true)
    }
    let n = js_number(a, v)
    if n != n { ret (0.0f64, false) }
    ret (n, true)
}

fn param(name: str, value: f.Value) -> f.Field { ret f.Field { name: name, value: value } }

// Validate a record against a table's field rules and record-level rules; every violation is reported.
fn validate_record(a: *mem.Arena, reg: *const f.Registry, table: Table, record: []const f.Field, ctx: *const Context) -> Outcome {
    let capacity = table.fields.len * 16usize + table.rules.len + 4usize
    let (items, ie) = mem.alloc[Violation](a, capacity)
    var none: []const Violation = zero
    if ie != ok { ret Outcome { valid: false, violations: none } }
    var sink = Sink { items: items, count: 0usize }
    var locale = ctx.locale
    if locale.len == 0usize { locale = "en" }
    var fi = 0usize
    while fi < table.fields.len {
        let d = table.fields[fi]
        fi += 1usize
        if is_computed_field(d) { continue }
        let behavior = field_behavior(a, reg, d, record, ctx)
        if !behavior.visible { continue }
        let value = lookup(record, d.name)
        var label = d.label
        if label.len == 0usize { label = d.name }
        // required
        if behavior.required && is_blank(value) {
            push(&sink, violation(a, ctx, d, "required", severity_of(d, "required"), record, label, zero_params()))
            continue
        }
        if is_blank(value) { continue }
        let (checked, known) = format_check(a, d.type_name, value)
        if known && !checked {
            var shown = value
            if value.kind == .Array { shown = f.text(join_items(a, value, ", ")) }
            var params: [2]f.Field = zero
            params[0usize] = param("type", f.text(d.type_name))
            params[1usize] = param("value", shown)
            push(&sink, violation(a, ctx, d, "format", severity_of(d, "format"), record, label, params[0..]))
        }
        if d.has_min || d.has_max {
            let (n, numeric) = comparable(a, value, d.type_name)
            if numeric {
                if d.has_min {
                    let (lo, lo_ok) = comparable(a, d.min, d.type_name)
                    var bound = 0.0f64
                    if lo_ok { bound = lo }
                    if n < bound {
                        var params: [1]f.Field = zero
                        params[0usize] = param("min", d.min)
                        push(&sink, violation(a, ctx, d, "min", severity_of(d, "min"), record, label, params[0..]))
                    }
                }
                if d.has_max {
                    let (hi, hi_ok) = comparable(a, d.max, d.type_name)
                    var bound = 0.0f64
                    if hi_ok { bound = hi }
                    if n > bound {
                        var params: [1]f.Field = zero
                        params[0usize] = param("max", d.max)
                        push(&sink, violation(a, ctx, d, "max", severity_of(d, "max"), record, label, params[0..]))
                    }
                }
            }
        }
        if value.kind == .Text || d.has_min_length || d.has_max_length {
            let len = f64(code_point_length(js_string(a, value)))
            if d.has_min_length && len < d.min_length {
                var params: [1]f.Field = zero
                params[0usize] = param("minLength", f.number(d.min_length))
                push(&sink, violation(a, ctx, d, "minLength", severity_of(d, "minLength"), record, label, params[0..]))
            }
            if d.has_max_length && len > d.max_length {
                var params: [1]f.Field = zero
                params[0usize] = param("maxLength", f.number(d.max_length))
                push(&sink, violation(a, ctx, d, "maxLength", severity_of(d, "maxLength"), record, label, params[0..]))
            }
        }
        if d.pattern.len > 0usize {
            let (re, re_error) = regex.compile_backtracking(a, tx.annex_b(a, d.pattern), regex.Options { case_insensitive: false, multiline: false, dot_matches_newline: false })
            if re_error == ok && !regex.is_match(&re, js_string(a, value)) {
                push(&sink, violation(a, ctx, d, "pattern", severity_of(d, "pattern"), record, label, zero_params()))
            }
        }
        if (str.eq(d.type_name, "select") || str.eq(d.type_name, "multiselect")) && !d.allow_user_input && d.has_options {
            var picks: []const f.Value = zero
            var single: [1]f.Value = zero
            if value.kind == .Array {
                picks = value.items
            } else {
                single[0usize] = value
                picks = single[0..]
            }
            var pi = 0usize
            while pi < picks.len {
                let shown = js_string(a, picks[pi])
                var allowed = false
                var oi = 0usize
                while oi < d.options.len {
                    if str.eq(js_string(a, d.options[oi]), shown) { allowed = true }
                    oi += 1usize
                }
                if !allowed {
                    var params: [1]f.Field = zero
                    params[0usize] = param("value", picks[pi])
                    push(&sink, violation(a, ctx, d, "membership", severity_of(d, "membership"), record, label, params[0..]))
                }
                pi += 1usize
            }
        }
        if str.eq(d.type_name, "multiselect") && d.has_limit && d.limit > 0.0f64 && value.kind == .Array && f64(value.items.len) > d.limit {
            var params: [1]f.Field = zero
            params[0usize] = param("max", f.number(d.limit))
            push(&sink, violation(a, ctx, d, "max", severity_of(d, "max"), record, label, params[0..]))
        }
        var vi = 0usize
        while vi < d.valid_if.len {
            if !truthy(eval_expr(a, reg, d.valid_if[vi], record, ctx)) {
                push(&sink, violation(a, ctx, d, "validIf", severity_of(d, "validIf"), record, label, zero_params()))
            }
            vi += 1usize
        }
        if d.unique && ctx.has_existing {
            var dup = false
            var ri = 0usize
            while ri < ctx.existing.len && !dup {
                if i64(ri) != ctx.self_index && !is_deleted(ctx.existing[ri].fields) {
                    let other = lookup(ctx.existing[ri].fields, d.name)
                    if !is_blank(other) {
                        var left = js_string(a, other)
                        var right = js_string(a, value)
                        if !d.unique_case_sensitive {
                            left = f.lower_text(a, left)
                            right = f.lower_text(a, right)
                        }
                        if str.eq(left, right) { dup = true }
                    }
                }
                ri += 1usize
            }
            if dup { push(&sink, violation(a, ctx, d, "unique", severity_of(d, "unique"), record, label, zero_params())) }
        }
    }
    var ri = 0usize
    while ri < table.rules.len {
        let rule = table.rules[ri]
        ri += 1usize
        if rule.inactive { continue }
        if truthy(eval_expr(a, reg, rule.expression, record, ctx)) { continue }
        var severity = rule.severity
        if severity.len == 0usize { severity = "error" }
        push(&sink, Violation { field: rule.field, has_field: rule.has_field, code: "record", severity: severity, rule_id: rule.id, has_rule_id: rule.has_id, message: resolve_message(a, ctx, rule.message, "record", zero_params(), record) })
    }
    var valid = true
    var vi2 = 0usize
    while vi2 < sink.count {
        if str.eq(sink.items[vi2].severity, "error") { valid = false }
        vi2 += 1usize
    }
    ret Outcome { valid: valid, violations: sink.items[0usize..sink.count] }
}

fn zero_params() -> []const f.Field {
    var none: []const f.Field = zero
    ret none
}


// `severities[code] ?? severity ?? 'error'`, narrowed to `warning` or `error`.
fn severity_of(d: Definition, code: str) -> str {
    var chosen = "error"
    if d.severity.len > 0usize { chosen = d.severity }
    var i = 0usize
    while i < d.severities.len {
        if str.eq(d.severities[i].name, code) && d.severities[i].value.kind == .Text { chosen = d.severities[i].value.s }
        i += 1usize
    }
    if str.eq(chosen, "warning") { ret "warning" }
    ret "error"
}

fn join_items(a: *mem.Arena, v: f.Value, sep: str) -> str {
    var out = ""
    var i = 0usize
    while i < v.items.len {
        if i > 0usize { out = f.join(a, out, sep) }
        if v.items[i].kind != .Blank { out = f.join(a, out, js_string(a, v.items[i])) }
        i += 1usize
    }
    ret out
}

fn violation(a: *mem.Arena, ctx: *const Context, d: Definition, code: str, severity: str, record: []const f.Field, label: str, params: []const f.Field) -> Violation {
    // the message: the field's custom text for the code, else the localized default; `{Field}` is the label
    let (custom, has_custom) = named_text(d.messages, code)
    var all: [4]f.Field = zero
    all[0usize] = param("Field", f.text(label))
    var n = 1usize
    var i = 0usize
    while i < params.len && n < 4usize {
        all[n] = params[i]
        n += 1usize
        i += 1usize
    }
    var shown = ""
    if has_custom { shown = custom }
    ret Violation { field: d.name, has_field: true, code: code, severity: severity, rule_id: "", has_rule_id: false, message: resolve_message(a, ctx, shown, code, all[0usize..n], record) }
}

// --- initial values, auto-set, computed writes -------------------------------------------------------------------

// Default and dynamic initial values for a new record: an `initial_value` expression wins over a static default
// (an expression that errors leaves the field blank).
fn compute_initial_values(a: *mem.Arena, reg: *const f.Registry, table: Table, ctx: *const Context) -> []const f.Field {
    let (out, e) = mem.alloc[f.Field](a, table.fields.len + 1usize)
    var none: []const f.Field = zero
    if e != ok { ret none }
    var n = 0usize
    var empty: []const f.Field = zero
    var local = copy_context(ctx)
    local.is_new = true
    var i = 0usize
    while i < table.fields.len {
        let d = table.fields[i]
        if d.initial_value.len > 0usize {
            let v = eval_expr(a, reg, d.initial_value, empty, &local)
            if v.kind == .Error {
                out[n] = f.Field { name: d.name, value: f.blank() }
            } else {
                out[n] = f.Field { name: d.name, value: v }
            }
            n += 1usize
        } else if d.has_default {
            out[n] = f.Field { name: d.name, value: d.default_value }
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// Apply the auto-set rules in order, each seeing the earlier results; a rule replaces a non-blank value only when it
// says so. The input record is not changed.
fn apply_auto_set(a: *mem.Arena, reg: *const f.Registry, table: Table, record: []const f.Field, ctx: *const Context) -> []const f.Field {
    let (next, e) = mem.alloc[f.Field](a, record.len + table.fields.len + 1usize)
    if e != ok { ret record }
    var n = 0usize
    var i = 0usize
    while i < record.len {
        next[n] = record[i]
        n += 1usize
        i += 1usize
    }
    var fi = 0usize
    while fi < table.fields.len {
        let d = table.fields[fi]
        fi += 1usize
        if !d.has_auto_set { continue }
        let current = next[0usize..n]
        if d.auto_when.len > 0usize && !truthy(eval_expr(a, reg, d.auto_when, current, ctx)) { continue }
        if !d.auto_replace && !is_blank(lookup(current, d.name)) { continue }
        var v = eval_expr(a, reg, d.auto_value, current, ctx)
        // an error leaves the value as it was, but the key is written either way
        if v.kind == .Error { v = lookup(current, d.name) }
        var placed = false
        var k = 0usize
        while k < n {
            if str.eq(next[k].name, d.name) {
                next[k].value = v
                placed = true
            }
            k += 1usize
        }
        if !placed {
            next[n] = f.Field { name: d.name, value: v }
            n += 1usize
        }
    }
    ret next[0usize..n]
}

// Violations for attempts to write computed (read-only) fields.
fn computed_write_violations(a: *mem.Arena, table: Table, write_keys: []const str, ctx: *const Context) -> []const Violation {
    let (out, e) = mem.alloc[Violation](a, write_keys.len + 1usize)
    var none: []const Violation = zero
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < write_keys.len {
        var j = 0usize
        var found = false
        var at = 0usize
        while j < table.fields.len && !found {
            if str.eq(table.fields[j].name, write_keys[i]) {
                found = true
                at = j
            }
            j += 1usize
        }
        if found && is_computed_field(table.fields[at]) {
            var label = table.fields[at].label
            if label.len == 0usize { label = write_keys[i] }
            var params: [1]f.Field = zero
            params[0usize] = param("Field", f.text(label))
            var empty: []const f.Field = zero
            out[n] = Violation { field: write_keys[i], has_field: true, code: "computed", severity: "error", rule_id: "", has_rule_id: false, message: resolve_message(a, ctx, "", "computed", params[0..], empty) }
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// --- conditional behavior beyond one field ----------------------------------------------------------------------

// A form container: a section, page or step with its own `show_if`, the field names it holds and its children.
type Container = struct { id: str, kind: str, show_if: str, fields: []const str, children: []const Container }

type ContainerState = struct { id: str, visible: bool, self_visible: bool, hidden_by_ancestor: bool, kind: str }

fn walk_containers(a: *mem.Arena, reg: *const f.Registry, nodes: []const Container, parent_visible: bool, record: []const f.Field, ctx: *const Context, out: []ContainerState, n: usize) -> usize {
    var count = n
    var i = 0usize
    while i < nodes.len {
        let node = nodes[i]
        var self_visible = true
        if node.show_if.len > 0usize { self_visible = truthy(eval_expr(a, reg, node.show_if, record, ctx)) }
        let visible = parent_visible && self_visible
        var kind = node.kind
        if kind.len == 0usize { kind = "section" }
        if count < out.len {
            out[count] = ContainerState { id: node.id, visible: visible, self_visible: self_visible, hidden_by_ancestor: self_visible && !parent_visible, kind: kind }
            count += 1usize
        }
        count = walk_containers(a, reg, node.children, visible, record, ctx, out, count)
        i += 1usize
    }
    ret count
}

fn count_containers(nodes: []const Container) -> usize {
    var n = nodes.len
    var i = 0usize
    while i < nodes.len {
        n += count_containers(nodes[i].children)
        i += 1usize
    }
    ret n
}

// Visibility for a nested container tree: a node is visible only when its ancestors are and its own rule holds.
fn evaluate_containers(a: *mem.Arena, reg: *const f.Registry, nodes: []const Container, record: []const f.Field, ctx: *const Context) -> []const ContainerState {
    let (out, e) = mem.alloc[ContainerState](a, count_containers(nodes) + 1usize)
    var none: []const ContainerState = zero
    if e != ok { ret none }
    let n = walk_containers(a, reg, nodes, true, record, ctx, out, 0usize)
    ret out[0usize..n]
}

type FormField = struct { name: str, visible: bool, editable: bool, required: bool, container: str, has_container: bool }

fn holder_of(nodes: []const Container, name: str) -> (str, bool) {
    var i = 0usize
    while i < nodes.len {
        var k = 0usize
        while k < nodes[i].fields.len {
            if str.eq(nodes[i].fields[k], name) { ret (nodes[i].id, true) }
            k += 1usize
        }
        let (inner, found) = holder_of(nodes[i].children, name)
        if found { ret (inner, true) }
        i += 1usize
    }
    ret ("", false)
}

// Field behavior with container visibility folded in: a field in a hidden container is not visible, editable or
// required, whatever its own rules say.
fn evaluate_form_behavior(a: *mem.Arena, reg: *const f.Registry, defs: []const Definition, containers: []const Container, record: []const f.Field, ctx: *const Context) -> []const FormField {
    let states = evaluate_containers(a, reg, containers, record, ctx)
    let (out, e) = mem.alloc[FormField](a, defs.len + 1usize)
    var none: []const FormField = zero
    if e != ok { ret none }
    var i = 0usize
    while i < defs.len {
        let own = field_behavior(a, reg, defs[i], record, ctx)
        let (holder, has_holder) = holder_of(containers, defs[i].name)
        var container_visible = true
        if has_holder {
            var k = 0usize
            while k < states.len {
                if str.eq(states[k].id, holder) { container_visible = states[k].visible }
                k += 1usize
            }
        }
        let visible = own.visible && container_visible
        var required = false
        if visible { required = own.required }
        out[i] = FormField { name: defs[i].name, visible: visible, editable: visible && own.editable, required: required, container: holder, has_container: has_holder }
        i += 1usize
    }
    ret out[0usize..defs.len]
}

type Suggestions = struct { values: []const f.Value, constrained: bool, failed: bool }

// Type-ahead values from an expression. They never constrain what may be saved; a broken expression yields none
// (and says so) rather than breaking the editor. `limit` is the caller's cap, else the field's own (negative means
// all but that many from the end, as `slice(0, limit)` reads it).
fn suggested_values(a: *mem.Arena, reg: *const f.Registry, d: Definition, record: []const f.Field, ctx: *const Context, has_limit: bool, limit: f64) -> Suggestions {
    var none: []const f.Value = zero
    if d.suggested_values.len == 0usize { ret Suggestions { values: none, constrained: false, failed: false } }
    let raw = eval_expr(a, reg, d.suggested_values, record, ctx)
    if raw.kind == .Error { ret Suggestions { values: none, constrained: false, failed: true } }
    var list: []const f.Value = zero
    var single: [1]f.Value = zero
    if raw.kind == .Array {
        list = raw.items
    } else {
        single[0usize] = raw
        list = single[0..]
    }
    let (out, e) = mem.alloc[f.Value](a, list.len + 1usize)
    if e != ok { ret Suggestions { values: none, constrained: false, failed: false } }
    var n = 0usize
    var i = 0usize
    while i < list.len {
        let item = list[i]
        i += 1usize
        if item.kind == .Blank || (item.kind == .Text && item.s.len == 0usize) { continue }
        let key = js_string(a, item)
        var seen = false
        var k = 0usize
        while k < n {
            if str.eq(js_string(a, out[k]), key) { seen = true }
            k += 1usize
        }
        if seen { continue }
        out[n] = item
        n += 1usize
    }
    var cap = 0.0f64
    var capped = false
    if has_limit {
        cap = limit
        capped = true
    } else if d.has_suggestion_limit {
        cap = d.suggestion_limit
        capped = true
    }
    if capped && is_finite(cap) {
        var c = math.trunc[f64](cap)
        if c < 0.0f64 { c = f64(n) + c }
        if c < 0.0f64 { c = 0.0f64 }
        if c < f64(n) { n = usize(c) }
    }
    ret Suggestions { values: out[0usize..n], constrained: false, failed: false }
}

// --- sets of rows ---------------------------------------------------------------------------------------------------

type RowResult = struct { index: usize, violations: []const Violation, valid: bool }

type CodeCount = struct { code: str, count: usize }

type Summary = struct { total: usize, valid: usize, invalid: usize, by_code: []const CodeCount }

// An import under a policy: `reject` (any invalid row fails the whole import), `skip` (drop invalid rows) or
// `flag` (import everything, report the violations). `imported`, `rejected` and `flagged` are row indices.
type ImportReport = struct {
    policy: str,
    imported: []const usize,
    rejected: []const usize,
    flagged: []const usize,
    rows: []const RowResult,
    valid: bool,
    summary: Summary,
}

fn has_error(vs: []const Violation) -> bool {
    var i = 0usize
    while i < vs.len {
        if str.eq(vs[i].severity, "error") { ret true }
        i += 1usize
    }
    ret false
}

// Validate an incoming batch against the stored rows and against each other: under reject and skip a row collides
// with the rows accepted before it; under flag every row is compared with every other, so both halves of a
// duplicate pair are reported.
fn validate_import(a: *mem.Arena, reg: *const f.Registry, table: Table, rows: []const Row, policy_name: str, stored_all: []const Row, ctx: *const Context) -> ImportReport {
    var policy = "reject"
    if str.eq(policy_name, "skip") || str.eq(policy_name, "flag") { policy = policy_name }
    // the stored rows that are live
    let (live, le) = mem.alloc[Row](a, stored_all.len + rows.len + 1usize)
    var no_indices: []const usize = zero
    var no_rows: []const RowResult = zero
    var no_counts: []const CodeCount = zero
    if le != ok {
        ret ImportReport { policy: policy, imported: no_indices, rejected: no_indices, flagged: no_indices, rows: no_rows, valid: false, summary: Summary { total: rows.len, valid: 0usize, invalid: 0usize, by_code: no_counts } }
    }
    var stored_n = 0usize
    var i = 0usize
    while i < stored_all.len {
        if !is_deleted(stored_all[i].fields) {
            live[stored_n] = stored_all[i]
            stored_n += 1usize
        }
        i += 1usize
    }
    let (results, re) = mem.alloc[RowResult](a, rows.len + 1usize)
    let (accepted, ae) = mem.alloc[usize](a, rows.len + 1usize)
    if re != ok || ae != ok {
        ret ImportReport { policy: policy, imported: no_indices, rejected: no_indices, flagged: no_indices, rows: no_rows, valid: false, summary: Summary { total: rows.len, valid: 0usize, invalid: 0usize, by_code: no_counts } }
    }
    var accepted_n = 0usize
    var local = copy_context(ctx)
    var r = 0usize
    while r < rows.len {
        // the comparison set: stored rows, then this batch's share
        var n = stored_n
        if str.eq(policy, "flag") {
            var k = 0usize
            while k < rows.len {
                if k != r {
                    live[n] = rows[k]
                    n += 1usize
                }
                k += 1usize
            }
        } else {
            var k = 0usize
            while k < accepted_n {
                live[n] = rows[accepted[k]]
                n += 1usize
                k += 1usize
            }
        }
        local.has_existing = true
        local.existing = live[0usize..n]
        local.self_index = -1i64
        let outcome = validate_record(a, reg, table, rows[r].fields, &local)
        let failed = has_error(outcome.violations)
        results[r] = RowResult { index: r, violations: outcome.violations, valid: !failed }
        if !failed || str.eq(policy, "flag") {
            accepted[accepted_n] = r
            accepted_n += 1usize
        }
        r += 1usize
    }
    // the summary, with violation codes counted in first-seen order
    let (counts, ce) = mem.alloc[CodeCount](a, rows.len * 8usize + 8usize)
    var count_n = 0usize
    var invalid = 0usize
    r = 0usize
    while r < rows.len {
        if !results[r].valid { invalid += 1usize }
        var v = 0usize
        while v < results[r].violations.len && ce == ok {
            let code = results[r].violations[v].code
            var found = false
            var c = 0usize
            while c < count_n {
                if str.eq(counts[c].code, code) {
                    counts[c].count += 1usize
                    found = true
                }
                c += 1usize
            }
            if !found && count_n < counts.len {
                counts[count_n] = CodeCount { code: code, count: 1usize }
                count_n += 1usize
            }
            v += 1usize
        }
        r += 1usize
    }
    var by_code = no_counts
    if ce == ok { by_code = counts[0usize..count_n] }
    let summary = Summary { total: rows.len, valid: rows.len - invalid, invalid: invalid, by_code: by_code }
    let (all_index, xe) = mem.alloc[usize](a, rows.len + 1usize)
    let (bad_index, be) = mem.alloc[usize](a, rows.len + 1usize)
    let (good_index, ge) = mem.alloc[usize](a, rows.len + 1usize)
    if xe != ok || be != ok || ge != ok {
        ret ImportReport { policy: policy, imported: no_indices, rejected: no_indices, flagged: no_indices, rows: results[0usize..rows.len], valid: false, summary: summary }
    }
    var bad_n = 0usize
    var good_n = 0usize
    r = 0usize
    while r < rows.len {
        all_index[r] = r
        if results[r].valid {
            good_index[good_n] = r
            good_n += 1usize
        } else {
            bad_index[bad_n] = r
            bad_n += 1usize
        }
        r += 1usize
    }
    if str.eq(policy, "reject") && invalid > 0usize {
        ret ImportReport { policy: policy, imported: no_indices, rejected: all_index[0usize..rows.len], flagged: no_indices, rows: results[0usize..rows.len], valid: false, summary: summary }
    }
    if str.eq(policy, "skip") {
        ret ImportReport { policy: policy, imported: good_index[0usize..good_n], rejected: bad_index[0usize..bad_n], flagged: no_indices, rows: results[0usize..rows.len], valid: true, summary: summary }
    }
    ret ImportReport { policy: policy, imported: all_index[0usize..rows.len], rejected: no_indices, flagged: bad_index[0usize..bad_n], rows: results[0usize..rows.len], valid: true, summary: summary }
}

type BackfillHit = struct { index: usize, violation: Violation }

type BackfillReport = struct { checked: usize, violating: usize, violations: []const BackfillHit, sample: []const BackfillHit }

// What a candidate rule would reject among the stored rows, before it is switched on: only the candidate is applied,
// so unrelated existing violations do not drown the answer. `candidate` is a field rule (its `name` the field it
// targets, other keys the rule) or, with `field_rule` false, a record-level rule.
fn backfill_check(a: *mem.Arena, reg: *const f.Registry, table: Table, records: []const Row, candidate: Definition, field_rule: bool, record_rule: Rule, sample_size: usize, ctx: *const Context) -> BackfillReport {
    let (live, le) = mem.alloc[Row](a, records.len + 1usize)
    var none_hits: []const BackfillHit = zero
    if le != ok { ret BackfillReport { checked: 0usize, violating: 0usize, violations: none_hits, sample: none_hits } }
    var n = 0usize
    var i = 0usize
    while i < records.len {
        if !is_deleted(records[i].fields) {
            live[n] = records[i]
            n += 1usize
        }
        i += 1usize
    }
    var probe: Table = zero
    var one_def: [1]Definition = zero
    var one_rule: [1]Rule = zero
    if field_rule {
        var base_found = false
        var j = 0usize
        var base = blank_definition()
        while j < table.fields.len {
            if str.eq(table.fields[j].name, candidate.name) {
                base = table.fields[j]
                base_found = true
            }
            j += 1usize
        }
        if !base_found { ret BackfillReport { checked: 0usize, violating: 0usize, violations: none_hits, sample: none_hits } }
        // the candidate's rule keys over the base field's name, label, type and options
        var probe_def = candidate
        var no_messages: []const f.Field = zero
        probe_def.messages = no_messages
        probe_def.severities = no_messages
        probe_def.severity = ""
        probe_def.name = base.name
        probe_def.label = base.label
        probe_def.type_name = base.type_name
        probe_def.has_options = base.has_options
        probe_def.options = base.options
        one_def[0usize] = probe_def
        probe = Table { fields: one_def[0..1usize], rules: one_rule[0..0usize] }
    } else {
        var rule = record_rule
        if !rule.has_id {
            rule.id = "candidate"
            rule.has_id = true
        }
        one_rule[0usize] = rule
        probe = Table { fields: one_def[0..0usize], rules: one_rule[0..1usize] }
    }
    let (hits, he) = mem.alloc[BackfillHit](a, n * 16usize + 1usize)
    if he != ok { ret BackfillReport { checked: 0usize, violating: 0usize, violations: none_hits, sample: none_hits } }
    var hit_n = 0usize
    var violating = 0usize
    var local = copy_context(ctx)
    local.has_existing = true
    local.existing = live[0usize..n]
    var idx = 0usize
    while idx < n {
        local.self_index = i64(idx)
        let outcome = validate_record(a, reg, probe, live[idx].fields, &local)
        if outcome.violations.len > 0usize { violating += 1usize }
        var v = 0usize
        while v < outcome.violations.len && hit_n < hits.len {
            hits[hit_n] = BackfillHit { index: idx, violation: outcome.violations[v] }
            hit_n += 1usize
            v += 1usize
        }
        idx += 1usize
    }
    var sample_n = hit_n
    if sample_size < sample_n { sample_n = sample_size }
    ret BackfillReport { checked: n, violating: violating, violations: hits[0usize..hit_n], sample: hits[0usize..sample_n] }
}

type Duplicate = struct { index: usize, score: f64, matched: usize, compared: usize }

// The text a duplicate comparison reads: trimmed, case-folded, runs of white space collapsed to one space.
fn duplicate_key(a: *mem.Arena, v: f.Value) -> str {
    let text = f.lower_text(a, js_trim(js_string(a, v)))
    let (out, e) = mem.alloc[u8](a, text.len + 1usize)
    if e != ok { ret text }
    var n = 0usize
    var in_space = false
    var it = utf8.iterator(text)
    var more = true
    while more {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else if js_space(scalar) {
            if !in_space {
                out[n] = 32u8
                n += 1usize
            }
            in_space = true
        } else {
            var piece: [4]u8 = zero
            let (width, we) = utf8.encode(scalar, piece[0..])
            var k = 0usize
            while k < usize(width) {
                out[n] = piece[k]
                n += 1usize
                k += 1usize
            }
            in_space = false
        }
    }
    ret out[0usize..n]
}

// Fuzzy duplicate warnings on create: the stored rows whose compared fields match at least `threshold` of the
// time (1 for all), best first. A field blank on either side is no evidence; `self_index` is the record's own row.
fn find_duplicates(a: *mem.Arena, record: []const f.Field, existing: []const Row, self_index: i64, names: []const str, threshold: f64) -> []const Duplicate {
    var none: []const Duplicate = zero
    if names.len == 0usize { ret none }
    let (out, e) = mem.alloc[Duplicate](a, existing.len + 1usize)
    if e != ok { ret none }
    var n = 0usize
    var i = 0usize
    while i < existing.len {
        if i64(i) != self_index && !is_deleted(existing[i].fields) {
            var compared = 0usize
            var matched = 0usize
            var k = 0usize
            while k < names.len {
                let left = lookup(record, names[k])
                let right = lookup(existing[i].fields, names[k])
                if !is_blank(left) && !is_blank(right) {
                    compared += 1usize
                    if str.eq(duplicate_key(a, left), duplicate_key(a, right)) { matched += 1usize }
                }
                k += 1usize
            }
            if compared > 0usize {
                let score = f64(matched) / f64(compared)
                if score >= threshold {
                    out[n] = Duplicate { index: i, score: score, matched: matched, compared: compared }
                    n += 1usize
                }
            }
        }
        i += 1usize
    }
    // best score first, then most matched; stable
    var x = 1usize
    while x < n {
        let item = out[x]
        var y = x
        while y > 0usize && (out[y - 1usize].score < item.score || (out[y - 1usize].score == item.score && out[y - 1usize].matched < item.matched)) {
            out[y] = out[y - 1usize]
            y -= 1usize
        }
        out[y] = item
        x += 1usize
    }
    ret out[0usize..n]
}

// A copy of a context to adjust (newness, the stored rows) without changing the caller's.
fn copy_context(ctx: *const Context) -> Context {
    ret Context { locale: ctx.locale, has_existing: ctx.has_existing, existing: ctx.existing, self_index: ctx.self_index, base: ctx.base, is_new: ctx.is_new, prior: ctx.prior, has_prior: ctx.has_prior, catalog: ctx.catalog }
}
