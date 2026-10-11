// Seeded fake-data generators over `e.algo.rand`'s PCG: names, cities, addresses, e-mail
// and user names, phone numbers, UUID v4, IPv4, MAC, colours, Luhn-valid card numbers,
// ISO dates and lorem-ipsum text, with locale overlays for the lookup tables (En, De,
// Fr, Es). Everything is a pure function of the seed: one `Faker` is one stream, the
// same seed and call sequence answer the same text on every host, and there is no
// network data source. Tables are comma separated strings picked by index, kept inside
// functions because a module-scope string constant does not check.
//
// Text is built into the caller's `str.Builder`; a single pick (`first_name`, `city`,
// `word`) answers a borrowed string with the lifetime of the static table.

use e.algo.rand
use e.str

type Locale = enum u8 { En, De, Fr, Es }
type Faker = struct { rng: rand.Pcg64, locale: Locale }

fn faker(seed: u64, locale: Locale) -> Faker {
    ret Faker { rng: rand.pcg64(seed, 54u64), locale: locale }
}

// An index in [0, n), unbiased.
fn below(f: *Faker, n: usize) -> usize {
    if n == 0usize { ret 0usize }
    ret usize(rand.pcg64_bounded(&f.rng, u64(n)))
}

// An integer in [lo, hi] inclusive; `lo > hi` answers `lo`.
fn int_between(f: *Faker, lo: i64, hi: i64) -> i64 {
    if hi <= lo { ret lo }
    let span = u64(hi - lo) + 1u64
    ret lo + i64(rand.pcg64_bounded(&f.rng, span))
}

// True `percent` times in a hundred.
fn chance(f: *Faker, percent: u32) -> bool {
    ret below(f, 100usize) < usize(percent)
}

fn blob_count(blob: str) -> usize {
    ret str.count(blob, ",") + 1usize
}

// Item `index` of a comma separated table; an index past the end answers the last.
fn blob_item(blob: str, index: usize) -> str {
    var start = 0usize
    var seen = 0usize
    var i = 0usize
    while i < blob.len {
        if blob[i] == 44u8 {
            if seen == index { ret blob[start..i] }
            seen += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret blob[start..]
}

fn pick(f: *Faker, blob: str) -> str {
    ret blob_item(blob, below(f, blob_count(blob)))
}

fn first_names(l: Locale) -> str {
    switch l {
    case .De:
        ret "Hans,Klaus,Peter,Jurgen,Wolfgang,Anna,Greta,Ursula,Heidi,Monika,Lukas,Sabine"
    case .Fr:
        ret "Jean,Pierre,Michel,Luc,Antoine,Marie,Camille,Sophie,Chloe,Louise,Hugo,Margaux"
    case .Es:
        ret "Jose,Antonio,Manuel,Javier,Carlos,Maria,Carmen,Lucia,Elena,Paula,Pablo,Marta"
    default:
        ret "James,Mary,Robert,Patricia,John,Jennifer,Michael,Linda,William,Elizabeth,David,Susan"
    }
}

fn last_names(l: Locale) -> str {
    switch l {
    case .De:
        ret "Mueller,Schmidt,Schneider,Fischer,Weber,Meyer,Wagner,Becker,Hoffmann,Schaefer"
    case .Fr:
        ret "Martin,Bernard,Dubois,Thomas,Robert,Richard,Petit,Durand,Leroy,Moreau"
    case .Es:
        ret "Garcia,Fernandez,Gonzalez,Rodriguez,Lopez,Martinez,Sanchez,Perez,Gomez,Ruiz"
    default:
        ret "Smith,Johnson,Williams,Brown,Jones,Garcia,Miller,Davis,Wilson,Anderson"
    }
}

fn cities(l: Locale) -> str {
    switch l {
    case .De:
        ret "Berlin,Hamburg,Muenchen,Koeln,Frankfurt,Stuttgart,Dresden,Leipzig"
    case .Fr:
        ret "Paris,Marseille,Lyon,Toulouse,Nice,Nantes,Strasbourg,Bordeaux"
    case .Es:
        ret "Madrid,Barcelona,Valencia,Sevilla,Zaragoza,Malaga,Bilbao,Murcia"
    default:
        ret "Springfield,Franklin,Clinton,Madison,Georgetown,Salem,Fairview,Riverton"
    }
}

fn streets(l: Locale) -> str {
    switch l {
    case .De:
        ret "Hauptstrasse,Bahnhofstrasse,Gartenstrasse,Schulstrasse,Dorfstrasse,Lindenweg"
    case .Fr:
        ret "Rue de la Paix,Rue Victor Hugo,Avenue des Champs,Rue du Moulin,Rue Pasteur"
    case .Es:
        ret "Calle Mayor,Calle Real,Avenida de la Paz,Calle del Sol,Plaza Nueva"
    default:
        ret "Main Street,Oak Avenue,Maple Drive,Cedar Lane,Elm Street,Park Road"
    }
}

fn countries(l: Locale) -> str {
    switch l {
    case .De:
        ret "Deutschland,Oesterreich,Schweiz,Frankreich,Spanien,Italien"
    case .Fr:
        ret "France,Belgique,Suisse,Allemagne,Espagne,Italie"
    case .Es:
        ret "Espana,Mexico,Argentina,Chile,Colombia,Peru"
    default:
        ret "United States,Canada,United Kingdom,Australia,Ireland,New Zealand"
    }
}

fn company_suffixes(l: Locale) -> str {
    switch l {
    case .De:
        ret "GmbH,AG,KG,und Soehne"
    case .Fr:
        ret "SARL,SA,et Fils,Groupe"
    case .Es:
        ret "SL,SA,e Hijos,Grupo"
    default:
        ret "Inc,LLC,Ltd,Group,and Sons"
    }
}

fn domains() -> str {
    ret "example.com,example.org,example.net,mail.test,corp.test,inbox.test"
}

fn lorem_words() -> str {
    ret "lorem,ipsum,dolor,sit,amet,consectetur,adipiscing,elit,sed,do,eiusmod,tempor,incididunt,ut,labore,et,dolore,magna,aliqua,enim,ad,minim,veniam,quis,nostrud,exercitation,ullamco,laboris,nisi,aliquip,ex,ea,commodo,consequat,duis,aute,irure,in,reprehenderit,voluptate,velit,esse,cillum,fugiat,nulla,pariatur,excepteur,sint,occaecat,cupidatat,non,proident,sunt,culpa,qui,officia,deserunt,mollit,anim,id,est,laborum"
}

fn first_name(f: *Faker) -> str { ret pick(f, first_names(f.locale)) }
fn last_name(f: *Faker) -> str { ret pick(f, last_names(f.locale)) }
fn city(f: *Faker) -> str { ret pick(f, cities(f.locale)) }
fn country(f: *Faker) -> str { ret pick(f, countries(f.locale)) }
fn word(f: *Faker) -> str { ret pick(f, lorem_words()) }

// `push` with ASCII letters folded to lower case and spaces dropped.
fn push_slug(b: *str.Builder, s: str) -> err {
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        if c != 32u8 { try str.push_byte(b, c) }
        i += 1usize
    }
    ret ok
}

fn push_digits(f: *Faker, b: *str.Builder, count: usize) -> err {
    var i = 0usize
    while i < count {
        try str.push_byte(b, 48u8 + u8(below(f, 10usize)))
        i += 1usize
    }
    ret ok
}

fn hex_digit(v: u8) -> u8 {
    if v < 10u8 { ret 48u8 + v }
    ret 87u8 + v
}

fn push_hex_byte(b: *str.Builder, v: u8) -> err {
    try str.push_byte(b, hex_digit(v >> 4u8))
    try str.push_byte(b, hex_digit(v & 15u8))
    ret ok
}

fn name(f: *Faker, b: *str.Builder) -> err {
    try str.push(b, first_name(f))
    try str.push(b, " ")
    try str.push(b, last_name(f))
    ret ok
}

fn company(f: *Faker, b: *str.Builder) -> err {
    try str.push(b, last_name(f))
    try str.push(b, " ")
    try str.push(b, pick(f, company_suffixes(f.locale)))
    ret ok
}

fn username(f: *Faker, b: *str.Builder) -> err {
    try push_slug(b, first_name(f))
    try str.push(b, ".")
    try push_slug(b, last_name(f))
    try push_digits(f, b, 2usize)
    ret ok
}

fn email(f: *Faker, b: *str.Builder) -> err {
    try push_slug(b, first_name(f))
    try str.push(b, ".")
    try push_slug(b, last_name(f))
    try str.push(b, "@")
    try str.push(b, pick(f, domains()))
    ret ok
}

// `12 Main Street, Springfield` in En; the number follows the street elsewhere.
fn address(f: *Faker, b: *str.Builder) -> err {
    let number = u64(int_between(f, 1i64, 199i64))
    let street = pick(f, streets(f.locale))
    if f.locale == .En {
        try str.push_u64(b, number)
        try str.push(b, " ")
        try str.push(b, street)
    } else {
        try str.push(b, street)
        try str.push(b, " ")
        try str.push_u64(b, number)
    }
    try str.push(b, ", ")
    try str.push(b, city(f))
    ret ok
}

fn phone(f: *Faker, b: *str.Builder) -> err {
    switch f.locale {
    case .De:
        try str.push(b, "+49 ")
        try push_digits(f, b, 3usize)
        try str.push(b, " ")
        try push_digits(f, b, 8usize)
    case .Fr:
        try str.push(b, "+33 ")
        try push_digits(f, b, 1usize)
        var i = 0usize
        while i < 4usize {
            try str.push(b, " ")
            try push_digits(f, b, 2usize)
            i += 1usize
        }
    case .Es:
        try str.push(b, "+34 ")
        try push_digits(f, b, 3usize)
        var j = 0usize
        while j < 3usize {
            try str.push(b, " ")
            try push_digits(f, b, 2usize)
            j += 1usize
        }
    default:
        try str.push(b, "+1 ")
        try push_digits(f, b, 3usize)
        try str.push(b, " ")
        try push_digits(f, b, 3usize)
        try str.push(b, " ")
        try push_digits(f, b, 4usize)
    }
    ret ok
}

// RFC 4122 version 4: 122 random bits, version nibble 4, variant 10xx.
fn uuid4(f: *Faker, b: *str.Builder) -> err {
    var bytes: [16]u8 = zero
    var i = 0usize
    while i < 16usize {
        bytes[i] = u8(below(f, 256usize))
        i += 1usize
    }
    bytes[6] = (bytes[6] & 15u8) | 64u8
    bytes[8] = (bytes[8] & 63u8) | 128u8
    var k = 0usize
    while k < 16usize {
        if k == 4usize || k == 6usize || k == 8usize || k == 10usize { try str.push(b, "-") }
        try push_hex_byte(b, bytes[k])
        k += 1usize
    }
    ret ok
}

fn ipv4(f: *Faker, b: *str.Builder) -> err {
    try str.push_u64(b, u64(int_between(f, 1i64, 223i64)))
    var i = 0usize
    while i < 3usize {
        try str.push(b, ".")
        try str.push_u64(b, u64(below(f, 256usize)))
        i += 1usize
    }
    ret ok
}

// Locally administered unicast: bit 1 of the first byte set, bit 0 clear.
fn mac_address(f: *Faker, b: *str.Builder) -> err {
    var i = 0usize
    while i < 6usize {
        var v = u8(below(f, 256usize))
        if i == 0usize { v = (v & 252u8) | 2u8 }
        if i > 0usize { try str.push(b, ":") }
        try push_hex_byte(b, v)
        i += 1usize
    }
    ret ok
}

fn hex_color(f: *Faker, b: *str.Builder) -> err {
    try str.push(b, "#")
    var i = 0usize
    while i < 3usize {
        try push_hex_byte(b, u8(below(f, 256usize)))
        i += 1usize
    }
    ret ok
}

// Luhn check digit for the digits `s` (the payload, without the check digit).
fn luhn_check_digit(s: str) -> u8 {
    var sum = 0u32
    var i = 0usize
    while i < s.len {
        let pos = s.len - 1usize - i
        var d = u32(s[pos] - 48u8)
        if i % 2usize == 0usize {
            d = d * 2u32
            if d > 9u32 { d = d - 9u32 }
        }
        sum += d
        i += 1usize
    }
    ret u8((10u32 - sum % 10u32) % 10u32)
}

fn luhn_valid(s: str) -> bool {
    if s.len < 2usize { ret false }
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret false }
        i += 1usize
    }
    ret luhn_check_digit(s[..s.len - 1usize]) == s[s.len - 1usize] - 48u8
}

// A sixteen digit Visa-shaped number: leading 4, fourteen random digits, Luhn check.
fn credit_card(f: *Faker, b: *str.Builder) -> err {
    var digits: [15]u8 = zero
    digits[0] = 52u8
    var i = 1usize
    while i < 15usize {
        digits[i] = 48u8 + u8(below(f, 10usize))
        i += 1usize
    }
    try str.push(b, digits[0..])
    try str.push_byte(b, 48u8 + luhn_check_digit(digits[0..]))
    ret ok
}

// Proleptic Gregorian civil date of a day count since 1970-01-01 (Hinnant): (year, month, day).
fn civil(days: i64) -> (i64, i64, i64) {
    let z = days + 719468i64
    var era = z / 146097i64
    if z < 0i64 { era = (z - 146096i64) / 146097i64 }
    let doe = z - era * 146097i64
    let yoe = (doe - doe / 1460i64 + doe / 36524i64 - doe / 146096i64) / 365i64
    let doy = doe - (365i64 * yoe + yoe / 4i64 - yoe / 100i64)
    let mp = (5i64 * doy + 2i64) / 153i64
    let day = doy - (153i64 * mp + 2i64) / 5i64 + 1i64
    var month = mp + 3i64
    if mp >= 10i64 { month = mp - 9i64 }
    var year = yoe + era * 400i64
    if month <= 2i64 { year += 1i64 }
    ret (year, month, day)
}

fn push_padded(b: *str.Builder, v: i64, width: usize) -> err {
    var digits: [20]u8 = zero
    var n = 0usize
    var rest = u64(v)
    while rest > 0u64 {
        digits[n] = 48u8 + u8(rest % 10u64)
        rest = rest / 10u64
        n += 1usize
    }
    var pad = width
    if n > width { pad = n }
    var i = pad
    while i > 0usize {
        i -= 1usize
        if i < n { try str.push_byte(b, digits[i]) } else { try str.push_byte(b, 48u8) }
    }
    ret ok
}

// An ISO date drawn uniformly from days `from_day..=to_day` since 1970-01-01.
fn date(f: *Faker, b: *str.Builder, from_day: i64, to_day: i64) -> err {
    let (year, month, day) = civil(int_between(f, from_day, to_day))
    try push_padded(b, year, 4usize)
    try str.push(b, "-")
    try push_padded(b, month, 2usize)
    try str.push(b, "-")
    try push_padded(b, day, 2usize)
    ret ok
}

// `count` lorem words, the first capitalised, ending in a full stop.
fn lorem_sentence(f: *Faker, b: *str.Builder, count: usize) -> err {
    var i = 0usize
    while i < count {
        if i > 0usize { try str.push(b, " ") }
        let w = word(f)
        if i == 0usize && w.len > 0usize {
            try str.push_byte(b, w[0] - 32u8)
            try str.push(b, w[1..])
        } else {
            try str.push(b, w)
        }
        i += 1usize
    }
    try str.push(b, ".")
    ret ok
}

// `sentences` sentences of 5 to 12 words each, separated by a space.
fn lorem_paragraph(f: *Faker, b: *str.Builder, sentences: usize) -> err {
    var i = 0usize
    while i < sentences {
        if i > 0usize { try str.push(b, " ") }
        try lorem_sentence(f, b, usize(int_between(f, 5i64, 12i64)))
        i += 1usize
    }
    ret ok
}
