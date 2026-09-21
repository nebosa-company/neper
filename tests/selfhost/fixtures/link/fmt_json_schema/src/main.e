// `e.fmt.json.schema`: 53 (schema, document) pairs whose validity agrees with the Python
// `jsonschema` package (draft 2020-12) and whose first-failure pointer agrees with a replica
// of this module's keyword order, then the refusals a malformed schema earns. Each pair exits
// with its own code; the refusals use codes past the pairs.

use e.fmt.json.schema
use e.io
use e.mem
use e.os
use e.str

fn expect(a: *mem.Arena, s: str, d: str, valid: bool, path: str) -> bool {
    var buf: [128]u8 = zero
    let (v, n, e) = schema.validate(a, s, d, buf[..])
    if e != ok { ret false }
    if v != valid { ret false }
    if !str.eq(buf[..n], path) { ret false }
    ret true
}

fn refuse(a: *mem.Arena, s: str, d: str) -> err {
    var buf: [128]u8 = zero
    let (_, _, e) = schema.validate(a, s, d, buf[..])
    ret e
}

fn main(a: *mem.Arena, args: []str) -> err {
    if !expect(a, "{\"type\":\"string\"}", "\"hi\"", true, "") { os.exit(1i32) }
    if !expect(a, "{\"type\":\"string\"}", "12", false, "") { os.exit(2i32) }
    if !expect(a, "{\"type\":[\"string\",\"null\"]}", "null", true, "") { os.exit(3i32) }
    if !expect(a, "{\"type\":[\"string\",\"null\"]}", "true", false, "") { os.exit(4i32) }
    if !expect(a, "{\"type\":\"integer\"}", "1.0", true, "") { os.exit(5i32) }
    if !expect(a, "{\"type\":\"integer\"}", "1.5", false, "") { os.exit(6i32) }
    if !expect(a, "{\"type\":\"number\"}", "-2.5e3", true, "") { os.exit(7i32) }
    if !expect(a, "{\"type\":\"boolean\"}", "0", false, "") { os.exit(8i32) }
    if !expect(a, "{\"enum\":[1,\"a\",null,[1,2]]}", "[1,2]", true, "") { os.exit(9i32) }
    if !expect(a, "{\"enum\":[1,\"a\",null,[1,2]]}", "[2,1]", false, "") { os.exit(10i32) }
    if !expect(a, "{\"const\":{\"a\":1,\"b\":[true]}}", "{\"b\":[true],\"a\":1.0}", true, "") { os.exit(11i32) }
    if !expect(a, "{\"const\":{\"a\":1}}", "{\"a\":true}", false, "") { os.exit(12i32) }
    if !expect(a, "{\"type\":\"object\",\"required\":[\"id\",\"name\"]}", "{\"id\":1,\"name\":\"x\"}", true, "") { os.exit(13i32) }
    if !expect(a, "{\"type\":\"object\",\"required\":[\"id\",\"name\"]}", "{\"id\":1}", false, "") { os.exit(14i32) }
    if !expect(a, "{\"properties\":{\"age\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":150}}}", "{\"age\":42}", true, "") { os.exit(15i32) }
    if !expect(a, "{\"properties\":{\"age\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":150}}}", "{\"age\":-1}", false, "/age") { os.exit(16i32) }
    if !expect(a, "{\"properties\":{\"age\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":150}}}", "{\"age\":151}", false, "/age") { os.exit(17i32) }
    if !expect(a, "{\"properties\":{\"x\":{\"exclusiveMinimum\":0,\"exclusiveMaximum\":10}}}", "{\"x\":0}", false, "/x") { os.exit(18i32) }
    if !expect(a, "{\"properties\":{\"x\":{\"exclusiveMinimum\":0,\"exclusiveMaximum\":10}}}", "{\"x\":9.99}", true, "") { os.exit(19i32) }
    if !expect(a, "{\"multipleOf\":0.5}", "2.5", true, "") { os.exit(20i32) }
    if !expect(a, "{\"multipleOf\":3}", "10", false, "") { os.exit(21i32) }
    if !expect(a, "{\"properties\":{\"a\":{\"type\":\"string\"}},\"additionalProperties\":false}", "{\"a\":\"x\",\"b\":1}", false, "/b") { os.exit(22i32) }
    if !expect(a, "{\"properties\":{\"a\":{\"type\":\"string\"}},\"additionalProperties\":false}", "{\"a\":\"x\"}", true, "") { os.exit(23i32) }
    if !expect(a, "{\"items\":{\"type\":\"integer\"},\"minItems\":2,\"maxItems\":4}", "[1,2,3]", true, "") { os.exit(24i32) }
    if !expect(a, "{\"items\":{\"type\":\"integer\"},\"minItems\":2,\"maxItems\":4}", "[1]", false, "") { os.exit(25i32) }
    if !expect(a, "{\"items\":{\"type\":\"integer\"},\"minItems\":2,\"maxItems\":4}", "[1,2,3,4,5]", false, "") { os.exit(26i32) }
    if !expect(a, "{\"items\":{\"type\":\"integer\"},\"minItems\":2,\"maxItems\":4}", "[1,2,\"3\"]", false, "/2") { os.exit(27i32) }
    if !expect(a, "{\"uniqueItems\":true}", "[1,2,1.0]", false, "") { os.exit(28i32) }
    if !expect(a, "{\"uniqueItems\":true}", "[1,true,\"1\",[1],{\"a\":1}]", true, "") { os.exit(29i32) }
    if !expect(a, "{\"minLength\":2,\"maxLength\":4}", "\"h\\u00e9llo\"", false, "") { os.exit(30i32) }
    if !expect(a, "{\"minLength\":2,\"maxLength\":4}", "\"\\u00e9\\u00e9\"", true, "") { os.exit(31i32) }
    if !expect(a, "{\"minLength\":2,\"maxLength\":4}", "\"\\u00e9\"", false, "") { os.exit(32i32) }
    if !expect(a, "{\"pattern\":\"^[a-z]+[0-9]$\"}", "\"abc7\"", true, "") { os.exit(33i32) }
    if !expect(a, "{\"pattern\":\"^[a-z]+[0-9]$\"}", "\"abc\"", false, "") { os.exit(34i32) }
    if !expect(a, "{\"pattern\":\"b+c\"}", "\"xxbbcx\"", true, "") { os.exit(35i32) }
    if !expect(a, "{\"allOf\":[{\"type\":\"integer\"},{\"minimum\":5}]}", "7", true, "") { os.exit(36i32) }
    if !expect(a, "{\"allOf\":[{\"type\":\"integer\"},{\"minimum\":5}]}", "3", false, "") { os.exit(37i32) }
    if !expect(a, "{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"integer\",\"minimum\":5}]}", "9", true, "") { os.exit(38i32) }
    if !expect(a, "{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"integer\",\"minimum\":5}]}", "3", false, "") { os.exit(39i32) }
    if !expect(a, "{\"oneOf\":[{\"type\":\"integer\"},{\"minimum\":5}]}", "3", true, "") { os.exit(40i32) }
    if !expect(a, "{\"oneOf\":[{\"type\":\"integer\"},{\"minimum\":5}]}", "7", false, "") { os.exit(41i32) }
    if !expect(a, "{\"oneOf\":[{\"type\":\"integer\"},{\"minimum\":5}]}", "5.5", true, "") { os.exit(42i32) }
    if !expect(a, "{\"not\":{\"type\":\"null\"}}", "null", false, "") { os.exit(43i32) }
    if !expect(a, "{\"not\":{\"type\":\"null\"}}", "\"x\"", true, "") { os.exit(44i32) }
    if !expect(a, "{\"$defs\":{\"pos\":{\"type\":\"integer\",\"minimum\":1}},\"properties\":{\"n\":{\"$ref\":\"#/$defs/pos\"}}}", "{\"n\":3}", true, "") { os.exit(45i32) }
    if !expect(a, "{\"$defs\":{\"pos\":{\"type\":\"integer\",\"minimum\":1}},\"properties\":{\"n\":{\"$ref\":\"#/$defs/pos\"}}}", "{\"n\":0}", false, "/n") { os.exit(46i32) }
    if !expect(a, "{\"$defs\":{\"node\":{\"type\":\"object\",\"required\":[\"v\"],\"properties\":{\"v\":{\"type\":\"integer\"},\"kids\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/node\"}}}}},\"$ref\":\"#/$defs/node\"}", "{\"v\":1,\"kids\":[{\"v\":2,\"kids\":[]},{\"v\":3,\"kids\":[{\"v\":\"bad\"}]}]}", false, "/kids/1/kids/0/v") { os.exit(47i32) }
    if !expect(a, "{\"$defs\":{\"node\":{\"type\":\"object\",\"required\":[\"v\"],\"properties\":{\"v\":{\"type\":\"integer\"},\"kids\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/$defs/node\"}}}}},\"$ref\":\"#/$defs/node\"}", "{\"v\":1,\"kids\":[{\"v\":2,\"kids\":[]},{\"v\":3,\"kids\":[{\"v\":4}]}]}", true, "") { os.exit(48i32) }
    if !expect(a, "{\"properties\":{\"a/b\":{\"properties\":{\"c~d\":{\"type\":\"null\"}}}}}", "{\"a/b\":{\"c~d\":1}}", false, "/a~1b/c~0d") { os.exit(49i32) }
    if !expect(a, "true", "{\"anything\":1}", true, "") { os.exit(50i32) }
    if !expect(a, "false", "1", false, "") { os.exit(51i32) }
    if !expect(a, "{\"type\":\"object\",\"properties\":{\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true}},\"required\":[\"tags\"]}", "{\"tags\":[\"a\",\"b\",\"a\"]}", false, "/tags") { os.exit(52i32) }
    if !expect(a, "{\"type\":\"object\",\"properties\":{\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true}},\"required\":[\"tags\"]}", "{\"tags\":[\"a\",\"\"]}", false, "/tags/1") { os.exit(53i32) }

    // Refusals: an unknown type name, a `$ref` outside `#/$defs/`, a missing definition, a
    // schema-valued `additionalProperties`, a bad pattern, a self-referential schema that
    // never consumes the instance, a document that is not JSON, and a path that does not fit.
    if refuse(a, "{\"type\":\"float\"}", "1") != schema.Invalid { os.exit(60i32) }
    if refuse(a, "{\"$ref\":\"#/definitions/x\"}", "1") != schema.Invalid { os.exit(61i32) }
    if refuse(a, "{\"$defs\":{},\"$ref\":\"#/$defs/x\"}", "1") != schema.Invalid { os.exit(62i32) }
    if refuse(a, "{\"additionalProperties\":{\"type\":\"string\"}}", "{\"a\":1}") != schema.Invalid { os.exit(63i32) }
    if refuse(a, "{\"pattern\":\"(\"}", "\"x\"") != schema.Invalid { os.exit(64i32) }
    if refuse(a, "{\"$ref\":\"#\"}", "1") != schema.TooDeep { os.exit(65i32) }
    if refuse(a, "{}", "{") == ok { os.exit(66i32) }
    var tiny: [3]u8 = zero
    let (_, _, short) = schema.validate(a, "{\"properties\":{\"abcdef\":{\"type\":\"null\"}}}", "{\"abcdef\":1}", tiny[..])
    if short != schema.TooSmall { os.exit(67i32) }

    try io.print("fmt json schema ok\n")
    ret ok
}
