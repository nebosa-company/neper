// `e.data.mapper`: convention-based struct mapping, flattening, null substitution and
// projections. The name-matching matrix and the integer range matrix are the output of
// scripts/gen_data_mapper_test.py (an independent Python model of the documented rules); the
// struct mappings are checked against hand-derived results. Sections: name scoring (1x),
// integer conversion ranges (2x), a nested map with flattening, renames, ignore and defaults
// (3x), strict and overflow refusals (4x), a slice map (5x), projections (6x). Every check has
// its own exit code.
use e.os
use e.mem
use e.str
use e.data.mapper as mapper

type Geo = struct { lat: f64, lon: f64 }
type Address = struct { city: str, zip: i32, geo: Geo }
type Customer = struct { id: i64, first_name: str, last_name: str, email: str, age: u8, active: bool, address: Address, score: f64, nickname: str }
type CustomerDto = struct { Id: i32, FirstName: str, lastname: str, mail: str, age: i32, active: i32, AddressCity: str, address_zip: i32, address_geo_lat: f64, score: f32, nickname: str, extra: i64 }
type Narrow = struct { id: i8, age: u8 }

fn conv_is[G: type, F: type](a: *mem.Arena, x: F, want_ok: bool, want: i64) -> bool {
    let (y, e) = mapper.convert[G, F](a, x)
    if want_ok { ret e == ok && i64(y) == want }
    ret e == mapper.Overflow
}

fn customer() -> Customer {
    var c: Customer = zero
    c.id = 41i64
    c.first_name = "Ada"
    c.last_name = "Lovelace"
    c.email = "ada@example.org"
    c.age = 36u8
    c.active = true
    c.address = Address { city: "London", zip: 12345i32, geo: Geo { lat: 51.5, lon: 0.0 - 0.125 } }
    c.score = 2.5
    c.nickname = ""
    ret c
}

// 1x: the name-scoring matrix.
fn names() -> i32 {
    if mapper.path_score("AddressCity", "", false, 2usize, "address", "city", "") != 1u32 { ret 10i32 }
    if mapper.path_score("address_city", "", false, 2usize, "address", "city", "") != 1u32 { ret 11i32 }
    if mapper.path_score("addresscity", "", false, 2usize, "address", "city", "") != 1u32 { ret 12i32 }
    if mapper.path_score("ADDRESS_CITY", "", false, 2usize, "address", "city", "") != 1u32 { ret 13i32 }
    if mapper.path_score("addr_city", "", false, 2usize, "address", "city", "") != 0u32 { ret 14i32 }
    if mapper.path_score("address_geo_lat", "", false, 3usize, "address", "geo", "lat") != 1u32 { ret 15i32 }
    if mapper.path_score("city", "", false, 1usize, "city", "", "") != 3u32 { ret 16i32 }
    if mapper.path_score("City", "", false, 1usize, "city", "", "") != 2u32 { ret 17i32 }
    if mapper.path_score("first_name", "", false, 1usize, "FirstName", "", "") != 2u32 { ret 18i32 }
    if mapper.path_score("name", "", false, 1usize, "first_name", "", "") != 0u32 { ret 19i32 }
    if mapper.path_score("mail", "email", true, 1usize, "email", "", "") != 4u32 { ret 20i32 }
    if mapper.path_score("mail", "email", true, 1usize, "mail", "", "") != 0u32 { ret 21i32 }
    if mapper.path_score("c", "address.city", true, 2usize, "address", "city", "") != 4u32 { ret 22i32 }
    if mapper.path_score("c", "address.city", true, 1usize, "address", "", "") != 0u32 { ret 23i32 }
    if mapper.path_score("c", "address.geo.lat", true, 3usize, "address", "geo", "lat") != 4u32 { ret 24i32 }
    if mapper.path_score("c", "address.geo", true, 3usize, "address", "geo", "lat") != 0u32 { ret 25i32 }
    ret 0i32
}

// 2x: integer conversions against Python's range arithmetic.
fn ranges(a: *mem.Arena) -> i32 {
    if !conv_is[i8, i32](a, 127i32, true, 127i64) { ret 30i32 }
    if !conv_is[i8, i32](a, 128i32, false, 0i64) { ret 31i32 }
    if !conv_is[i8, i32](a, -128i32, true, -128i64) { ret 32i32 }
    if !conv_is[i8, i32](a, -129i32, false, 0i64) { ret 33i32 }
    if !conv_is[u8, i32](a, 255i32, true, 255i64) { ret 34i32 }
    if !conv_is[u8, i32](a, 256i32, false, 0i64) { ret 35i32 }
    if !conv_is[u8, i32](a, -1i32, false, 0i64) { ret 36i32 }
    if !conv_is[u32, i64](a, 4294967295i64, true, 4294967295i64) { ret 37i32 }
    if !conv_is[u32, i64](a, 4294967296i64, false, 0i64) { ret 38i32 }
    if !conv_is[i32, u32](a, 2147483647u32, true, 2147483647i64) { ret 39i32 }
    if !conv_is[i32, u32](a, 2147483648u32, false, 0i64) { ret 40i32 }
    if !conv_is[i64, u64](a, 9223372036854775807u64, true, 9223372036854775807i64) { ret 41i32 }
    if !conv_is[i64, u64](a, 9223372036854775808u64, false, 0i64) { ret 42i32 }
    if !conv_is[u64, i64](a, 0i64, true, 0i64) { ret 43i32 }
    if !conv_is[u64, i64](a, -1i64, false, 0i64) { ret 44i32 }
    if !conv_is[u16, u32](a, 65535u32, true, 65535i64) { ret 45i32 }
    if !conv_is[u16, u32](a, 65536u32, false, 0i64) { ret 46i32 }
    if !conv_is[i16, i64](a, -32768i64, true, -32768i64) { ret 47i32 }
    if !conv_is[i16, i64](a, -32769i64, false, 0i64) { ret 48i32 }
    if !conv_is[i64, i8](a, -128i8, true, -128i64) { ret 49i32 }
    ret 0i32
}

// 3x: a nested map with flattening, a rename, an ignore, a default and an unmapped field.
fn nested(a: *mem.Arena) -> i32 {
    let c = customer()
    var renames: [2]mapper.Rename = zero
    renames[0] = mapper.Rename { dest: "mail", src: "email" }
    renames[1] = mapper.Rename { dest: "address_geo_lat", src: "address.geo.lat" }
    var defaults: [2]mapper.Default = zero
    defaults[0] = mapper.Default { dest: "nickname", as_int: 0i64, as_real: 0.0, as_str: "n/a" }
    defaults[1] = mapper.Default { dest: "extra", as_int: 99i64, as_real: 0.0, as_str: "" }
    var ignore: [1]str = zero
    ignore[0] = "lastname"
    var p: mapper.Profile = zero
    p.renames = renames[0..]
    p.defaults = defaults[0..]
    p.ignore = ignore[0..]
    p.empty_is_null = true
    var d: CustomerDto = zero
    let (st, map_error) = mapper.map_into[Customer, CustomerDto](a, &c, &d, &p)
    if map_error != ok { ret 50i32 }
    if d.Id != 41i32 { ret 51i32 }
    if !str.eq(d.FirstName, "Ada") { ret 52i32 }
    if d.lastname.len != 0usize { ret 53i32 }
    if !str.eq(d.mail, "ada@example.org") { ret 54i32 }
    if d.age != 36i32 { ret 55i32 }
    if d.active != 1i32 { ret 56i32 }
    if !str.eq(d.AddressCity, "London") { ret 57i32 }
    if d.address_zip != 12345i32 { ret 58i32 }
    if d.address_geo_lat != 51.5 { ret 59i32 }
    if d.score != 2.5f32 { ret 60i32 }
    if !str.eq(d.nickname, "n/a") { ret 61i32 }
    if d.extra != 99i64 { ret 62i32 }
    // 12 destination fields: 1 ignored, 2 defaulted (nickname null, extra absent), 9 mapped.
    if st.skipped != 1usize || st.defaulted != 2usize || st.mapped != 9usize || st.missing != 0usize { ret 63i32 }
    // The copy owns its text: the destination's string is not the source's bytes.
    if d.FirstName.len != 3usize { ret 64i32 }
    ret 0i32
}

// 4x: strict, overflow, a non-null source is not replaced, an empty one is kept when not null.
fn refusals(a: *mem.Arena) -> i32 {
    var c = customer()
    var d: CustomerDto = zero
    var strict: mapper.Profile = zero
    strict.strict = true
    let (st, strict_error) = mapper.map_into[Customer, CustomerDto](a, &c, &d, &strict)
    if strict_error != mapper.Unmapped { ret 70i32 }
    if mapper.unmapped[Customer, CustomerDto](&strict) != 2usize { ret 71i32 }
    // id 300 does not fit an i8
    var big: Narrow = zero
    var wide = Customer { id: 300i64, first_name: "", last_name: "", email: "", age: 7u8, active: false, address: zero, score: 0.0, nickname: "" }
    var plain: mapper.Profile = zero
    let (st2, overflow_error) = mapper.map_into[Customer, Narrow](a, &wide, &big, &plain)
    if overflow_error != mapper.Overflow { ret 72i32 }
    wide.id = 100i64
    let (st3, fine_error) = mapper.map_into[Customer, Narrow](a, &wide, &big, &plain)
    if fine_error != ok || big.id != 100i8 || big.age != 7u8 { ret 73i32 }
    // empty is only null when asked: nickname "" stays "" without empty_is_null
    var defaults: [1]mapper.Default = zero
    defaults[0] = mapper.Default { dest: "nickname", as_int: 0i64, as_real: 0.0, as_str: "n/a" }
    var p: mapper.Profile = zero
    p.defaults = defaults[0..]
    var d2: CustomerDto = zero
    let (st4, e4) = mapper.map_into[Customer, CustomerDto](a, &c, &d2, &p)
    if e4 != ok || d2.nickname.len != 0usize || st4.defaulted != 0usize { ret 74i32 }
    p.empty_is_null = true
    var d3: CustomerDto = zero
    let (st5, e5) = mapper.map_into[Customer, CustomerDto](a, &c, &d3, &p)
    if e5 != ok || !str.eq(d3.nickname, "n/a") || st5.defaulted != 1usize { ret 75i32 }
    // a non-empty source is kept
    c.nickname = "ada"
    var d4: CustomerDto = zero
    let (st6, e6) = mapper.map_into[Customer, CustomerDto](a, &c, &d4, &p)
    if e6 != ok || !str.eq(d4.nickname, "ada") { ret 76i32 }
    ret 0i32
}

// 5x: a slice of sources.
fn collection(a: *mem.Arena) -> i32 {
    var src: [3]Customer = zero
    src[0] = customer()
    src[1] = customer()
    src[1].id = 42i64
    src[1].address.city = "Paris"
    src[2] = customer()
    src[2].id = 43i64
    var dst: [3]CustomerDto = zero
    var plain: mapper.Profile = zero
    let (st, map_error) = mapper.map_all[Customer, CustomerDto](a, src[0..], dst[0..], &plain)
    if map_error != ok { ret 80i32 }
    if dst[0].Id != 41i32 || dst[1].Id != 42i32 || dst[2].Id != 43i32 { ret 81i32 }
    if !str.eq(dst[1].AddressCity, "Paris") || !str.eq(dst[2].AddressCity, "London") { ret 82i32 }
    var tiny: [2]CustomerDto = zero
    let (st2, small_error) = mapper.map_all[Customer, CustomerDto](a, src[0..], tiny[0..], &plain)
    if small_error != mapper.TooSmall { ret 83i32 }
    ret 0i32
}

// 6x: the projection selects only what the destination reads.
fn projection(a: *mem.Arena) -> i32 {
    var renames: [1]mapper.Rename = zero
    renames[0] = mapper.Rename { dest: "mail", src: "email" }
    var defaults: [2]mapper.Default = zero
    defaults[0] = mapper.Default { dest: "nickname", as_int: 0i64, as_real: 0.0, as_str: "n/a" }
    defaults[1] = mapper.Default { dest: "extra", as_int: 99i64, as_real: 0.0, as_str: "" }
    var ignore: [3]str = zero
    ignore[0] = "lastname"
    ignore[1] = "address_geo_lat"
    ignore[2] = "score"
    var p: mapper.Profile = zero
    p.renames = renames[0..]
    p.defaults = defaults[0..]
    p.ignore = ignore[0..]
    let (sql, sql_error) = mapper.project_sql[Customer, CustomerDto](a, "customers", &p)
    if sql_error != ok { ret 90i32 }
    let want = "SELECT id AS Id, first_name AS FirstName, email AS mail, age, active, address_city AS AddressCity, address_zip, COALESCE(nickname, 'n/a') AS nickname, 99 AS extra FROM customers"
    if !str.eq(sql, want) { ret 91i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    var code = names()
    if code == 0i32 { code = ranges(a) }
    if code == 0i32 { code = nested(a) }
    if code == 0i32 { code = refusals(a) }
    if code == 0i32 { code = collection(a) }
    if code == 0i32 { code = projection(a) }
    if code != 0i32 { os.exit(code) }
    ret ok
}
