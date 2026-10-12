// A protocol buffer descriptor reader (L164): the bytes of a `FileDescriptorSet` (what `protoc --descriptor_set_out`
// writes and a server's reflection answers) or of one `FileDescriptorProto`, read into JSON the way protobuf's own JSON
// mapping writes the same message -- lower-camel member names, enums by their name, a set field present even at its
// default and an unset one absent -- so that a stub generator, a validator or a reflection client can walk the schema.
//
// The schema read is descriptor.proto's structure of files, messages (nested, with fields, oneof declarations, reserved
// and extension ranges), enums, services and methods: for a file its name, package, dependencies, syntax and edition;
// for a field its name, number, label, type, type name, extendee, default value, oneof index, JSON name and the
// proto3-optional flag; for a method its input and output type names and its streaming flags. Of the option messages
// only the members a code generator needs are kept: a message's `mapEntry` and `deprecated`, a field's `packed` and
// `deprecated`, an enum's `allowAlias` and `deprecated`. Source-code info and every other option member are skipped, as
// is an unknown field or one whose wire type does not match its declaration (protobuf's rule).
//
// Nesting deeper than 32 messages is `Invalid`, as is any malformed wire data (`e.fmt.protobuf`'s rules).
//
// Memory: the arena is retained; the JSON value and every text in it live there.

use e.algo.ir as ir
use e.algo.sync as sync
use e.bytes
use e.data.list as list
use e.fmt.json as json
use e.fmt.protobuf as pb
use e.mem
use e.str

error Invalid

fn max_depth() -> u32 { ret 32u32 }

// --- field names of the enums ---------------------------------------------------------------------------------------

fn type_name(code: i64) -> str {
    if code == 1i64 { ret "TYPE_DOUBLE" }
    if code == 2i64 { ret "TYPE_FLOAT" }
    if code == 3i64 { ret "TYPE_INT64" }
    if code == 4i64 { ret "TYPE_UINT64" }
    if code == 5i64 { ret "TYPE_INT32" }
    if code == 6i64 { ret "TYPE_FIXED64" }
    if code == 7i64 { ret "TYPE_FIXED32" }
    if code == 8i64 { ret "TYPE_BOOL" }
    if code == 9i64 { ret "TYPE_STRING" }
    if code == 10i64 { ret "TYPE_GROUP" }
    if code == 11i64 { ret "TYPE_MESSAGE" }
    if code == 12i64 { ret "TYPE_BYTES" }
    if code == 13i64 { ret "TYPE_UINT32" }
    if code == 14i64 { ret "TYPE_ENUM" }
    if code == 15i64 { ret "TYPE_SFIXED32" }
    if code == 16i64 { ret "TYPE_SFIXED64" }
    if code == 17i64 { ret "TYPE_SINT32" }
    if code == 18i64 { ret "TYPE_SINT64" }
    ret ""
}

fn label_name(code: i64) -> str {
    if code == 1i64 { ret "LABEL_OPTIONAL" }
    if code == 2i64 { ret "LABEL_REQUIRED" }
    if code == 3i64 { ret "LABEL_REPEATED" }
    ret ""
}

// --- reading ---------------------------------------------------------------------------------------------------------

fn put_number(a: *mem.Arena, o: *ir.Obj, key: str, value: i64) { sync.put(o, key, sync.number(a, value)) }

// A varint field read as a signed 32-bit number (negatives arrive sign-extended to 64 bits).
fn read_int(r: *pb.Reader) -> (i64, err) {
    let (value, e) = pb.read_i64(r)
    if e != ok { ret (0i64, Invalid) }
    ret (value, ok)
}

fn read_flag(r: *pb.Reader) -> (bool, err) {
    let (value, e) = pb.read_u64(r)
    if e != ok { ret (false, Invalid) }
    ret (value != 0u64, ok)
}

fn read_text(a: *mem.Arena, r: *pb.Reader) -> (json.Value, err) {
    let (data, e) = pb.read_bytes(r)
    if e != ok { ret (.Null, Invalid) }
    ret (sync.text(data), ok)
}

fn push_array(l: *list.List[json.Value], v: json.Value) { sync.push_value(l, v) }

fn array_of(l: list.List[json.Value]) -> json.Value { ret json.Value{ Array: list.slice_const[json.Value](&l) } }

fn finished(o: *ir.Obj) -> json.Value { ret ir.obj_value(o) }

// `{start, end}` of an extension or reserved range (extension ranges may carry options, which are skipped).
fn parse_range(a: *mem.Arena, source: []const u8) -> (json.Value, err) {
    var r = pb.reader(source)
    var o = sync.obj(a)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (.Null, Invalid) }
        if !more { break }
        if key.wire == .Varint && key.number == 1u32 {
            let (v, e) = read_int(&r)
            if e != ok { ret (.Null, e) }
            put_number(a, &o, "start", v)
        } else if key.wire == .Varint && key.number == 2u32 {
            let (v, e) = read_int(&r)
            if e != ok { ret (.Null, e) }
            put_number(a, &o, "end", v)
        } else {
            if pb.skip(&r, key.wire) != ok { ret (.Null, Invalid) }
        }
    }
    ret (finished(&o), ok)
}

// An option message reduced to the flags a generator reads: `numbers` are `(field number, name)` pairs of bool fields.
fn parse_flags(a: *mem.Arena, source: []const u8, first: u32, first_name: str, second: u32, second_name: str) -> (json.Value, err) {
    var r = pb.reader(source)
    var o = sync.obj(a)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (.Null, Invalid) }
        if !more { break }
        if key.wire == .Varint && key.number == first {
            let (v, e) = read_flag(&r)
            if e != ok { ret (.Null, e) }
            sync.put(&o, first_name, sync.flag(v))
        } else if key.wire == .Varint && key.number == second {
            let (v, e) = read_flag(&r)
            if e != ok { ret (.Null, e) }
            sync.put(&o, second_name, sync.flag(v))
        } else {
            if pb.skip(&r, key.wire) != ok { ret (.Null, Invalid) }
        }
    }
    ret (finished(&o), ok)
}

fn parse_oneof(a: *mem.Arena, source: []const u8) -> (json.Value, err) {
    var r = pb.reader(source)
    var o = sync.obj(a)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (.Null, Invalid) }
        if !more { break }
        if key.wire == .Bytes && key.number == 1u32 {
            let (v, e) = read_text(a, &r)
            if e != ok { ret (.Null, e) }
            sync.put(&o, "name", v)
        } else {
            if pb.skip(&r, key.wire) != ok { ret (.Null, Invalid) }
        }
    }
    ret (finished(&o), ok)
}

fn parse_field(a: *mem.Arena, source: []const u8) -> (json.Value, err) {
    var r = pb.reader(source)
    var o = sync.obj(a)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (.Null, Invalid) }
        if !more { break }
        if key.wire == .Bytes && (key.number == 1u32 || key.number == 2u32 || key.number == 6u32 || key.number == 7u32 || key.number == 10u32) {
            let (v, e) = read_text(a, &r)
            if e != ok { ret (.Null, e) }
            if key.number == 1u32 { sync.put(&o, "name", v) }
            if key.number == 2u32 { sync.put(&o, "extendee", v) }
            if key.number == 6u32 { sync.put(&o, "typeName", v) }
            if key.number == 7u32 { sync.put(&o, "defaultValue", v) }
            if key.number == 10u32 { sync.put(&o, "jsonName", v) }
        } else if key.wire == .Varint && (key.number == 3u32 || key.number == 4u32 || key.number == 5u32 || key.number == 9u32) {
            let (v, e) = read_int(&r)
            if e != ok { ret (.Null, e) }
            if key.number == 3u32 { put_number(a, &o, "number", v) }
            if key.number == 4u32 {
                let named = label_name(v)
                if named.len > 0usize { sync.put(&o, "label", sync.text(named)) } else { put_number(a, &o, "label", v) }
            }
            if key.number == 5u32 {
                let named = type_name(v)
                if named.len > 0usize { sync.put(&o, "type", sync.text(named)) } else { put_number(a, &o, "type", v) }
            }
            if key.number == 9u32 { put_number(a, &o, "oneofIndex", v) }
        } else if key.wire == .Varint && key.number == 17u32 {
            let (v, e) = read_flag(&r)
            if e != ok { ret (.Null, e) }
            sync.put(&o, "proto3Optional", sync.flag(v))
        } else if key.wire == .Bytes && key.number == 8u32 {
            let (data, e) = pb.read_bytes(&r)
            if e != ok { ret (.Null, Invalid) }
            let (options, options_error) = parse_flags(a, data, 2u32, "packed", 3u32, "deprecated")
            if options_error != ok { ret (.Null, options_error) }
            sync.put(&o, "options", options)
        } else {
            if pb.skip(&r, key.wire) != ok { ret (.Null, Invalid) }
        }
    }
    ret (finished(&o), ok)
}

fn parse_enum_value(a: *mem.Arena, source: []const u8) -> (json.Value, err) {
    var r = pb.reader(source)
    var o = sync.obj(a)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (.Null, Invalid) }
        if !more { break }
        if key.wire == .Bytes && key.number == 1u32 {
            let (v, e) = read_text(a, &r)
            if e != ok { ret (.Null, e) }
            sync.put(&o, "name", v)
        } else if key.wire == .Varint && key.number == 2u32 {
            let (v, e) = read_int(&r)
            if e != ok { ret (.Null, e) }
            put_number(a, &o, "number", v)
        } else {
            if pb.skip(&r, key.wire) != ok { ret (.Null, Invalid) }
        }
    }
    ret (finished(&o), ok)
}

fn parse_enum(a: *mem.Arena, source: []const u8) -> (json.Value, err) {
    var r = pb.reader(source)
    var o = sync.obj(a)
    var values = sync.empty_list(a)
    var ranges = sync.empty_list(a)
    var names = sync.empty_list(a)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (.Null, Invalid) }
        if !more { break }
        if key.wire == .Bytes && key.number == 1u32 {
            let (v, e) = read_text(a, &r)
            if e != ok { ret (.Null, e) }
            sync.put(&o, "name", v)
        } else if key.wire == .Bytes && key.number == 2u32 {
            let (data, e) = pb.read_bytes(&r)
            if e != ok { ret (.Null, Invalid) }
            let (v, ve) = parse_enum_value(a, data)
            if ve != ok { ret (.Null, ve) }
            push_array(&values, v)
        } else if key.wire == .Bytes && key.number == 3u32 {
            let (data, e) = pb.read_bytes(&r)
            if e != ok { ret (.Null, Invalid) }
            let (options, oe) = parse_flags(a, data, 2u32, "allowAlias", 3u32, "deprecated")
            if oe != ok { ret (.Null, oe) }
            sync.put(&o, "options", options)
        } else if key.wire == .Bytes && key.number == 4u32 {
            let (data, e) = pb.read_bytes(&r)
            if e != ok { ret (.Null, Invalid) }
            let (v, ve) = parse_range(a, data)
            if ve != ok { ret (.Null, ve) }
            push_array(&ranges, v)
        } else if key.wire == .Bytes && key.number == 5u32 {
            let (v, e) = read_text(a, &r)
            if e != ok { ret (.Null, e) }
            push_array(&names, v)
        } else {
            if pb.skip(&r, key.wire) != ok { ret (.Null, Invalid) }
        }
    }
    if values.len > 0usize { sync.put(&o, "value", array_of(values)) }
    if ranges.len > 0usize { sync.put(&o, "reservedRange", array_of(ranges)) }
    if names.len > 0usize { sync.put(&o, "reservedName", array_of(names)) }
    ret (finished(&o), ok)
}

fn parse_method(a: *mem.Arena, source: []const u8) -> (json.Value, err) {
    var r = pb.reader(source)
    var o = sync.obj(a)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (.Null, Invalid) }
        if !more { break }
        if key.wire == .Bytes && (key.number == 1u32 || key.number == 2u32 || key.number == 3u32) {
            let (v, e) = read_text(a, &r)
            if e != ok { ret (.Null, e) }
            if key.number == 1u32 { sync.put(&o, "name", v) }
            if key.number == 2u32 { sync.put(&o, "inputType", v) }
            if key.number == 3u32 { sync.put(&o, "outputType", v) }
        } else if key.wire == .Varint && key.number == 5u32 {
            let (v, e) = read_flag(&r)
            if e != ok { ret (.Null, e) }
            sync.put(&o, "clientStreaming", sync.flag(v))
        } else if key.wire == .Varint && key.number == 6u32 {
            let (v, e) = read_flag(&r)
            if e != ok { ret (.Null, e) }
            sync.put(&o, "serverStreaming", sync.flag(v))
        } else if key.wire == .Bytes && key.number == 4u32 {
            let (data, e) = pb.read_bytes(&r)
            if e != ok { ret (.Null, Invalid) }
            sync.put(&o, "options", ir.empty_object())
        } else {
            if pb.skip(&r, key.wire) != ok { ret (.Null, Invalid) }
        }
    }
    ret (finished(&o), ok)
}

fn parse_service(a: *mem.Arena, source: []const u8) -> (json.Value, err) {
    var r = pb.reader(source)
    var o = sync.obj(a)
    var methods = sync.empty_list(a)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (.Null, Invalid) }
        if !more { break }
        if key.wire == .Bytes && key.number == 1u32 {
            let (v, e) = read_text(a, &r)
            if e != ok { ret (.Null, e) }
            sync.put(&o, "name", v)
        } else if key.wire == .Bytes && key.number == 2u32 {
            let (data, e) = pb.read_bytes(&r)
            if e != ok { ret (.Null, Invalid) }
            let (v, ve) = parse_method(a, data)
            if ve != ok { ret (.Null, ve) }
            push_array(&methods, v)
        } else if key.wire == .Bytes && key.number == 3u32 {
            let (data, e) = pb.read_bytes(&r)
            if e != ok { ret (.Null, Invalid) }
            sync.put(&o, "options", ir.empty_object())
        } else {
            if pb.skip(&r, key.wire) != ok { ret (.Null, Invalid) }
        }
    }
    if methods.len > 0usize { sync.put(&o, "method", array_of(methods)) }
    ret (finished(&o), ok)
}

// One `DescriptorProto`; `depth` counts the messages around it.
fn parse_message(a: *mem.Arena, source: []const u8, depth: u32) -> (json.Value, err) {
    if depth > max_depth() { ret (.Null, Invalid) }
    var r = pb.reader(source)
    var o = sync.obj(a)
    var fields = sync.empty_list(a)
    var nested = sync.empty_list(a)
    var enums = sync.empty_list(a)
    var extension_ranges = sync.empty_list(a)
    var extensions = sync.empty_list(a)
    var oneofs = sync.empty_list(a)
    var ranges = sync.empty_list(a)
    var names = sync.empty_list(a)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (.Null, Invalid) }
        if !more { break }
        if key.wire != .Bytes {
            if pb.skip(&r, key.wire) != ok { ret (.Null, Invalid) }
            continue
        }
        if key.number == 1u32 || key.number == 10u32 {
            let (v, e) = read_text(a, &r)
            if e != ok { ret (.Null, e) }
            if key.number == 1u32 { sync.put(&o, "name", v) } else { push_array(&names, v) }
            continue
        }
        let (data, data_error) = pb.read_bytes(&r)
        if data_error != ok { ret (.Null, Invalid) }
        if key.number == 2u32 {
            let (v, e) = parse_field(a, data)
            if e != ok { ret (.Null, e) }
            push_array(&fields, v)
        } else if key.number == 3u32 {
            let (v, e) = parse_message(a, data, depth + 1u32)
            if e != ok { ret (.Null, e) }
            push_array(&nested, v)
        } else if key.number == 4u32 {
            let (v, e) = parse_enum(a, data)
            if e != ok { ret (.Null, e) }
            push_array(&enums, v)
        } else if key.number == 5u32 {
            let (v, e) = parse_range(a, data)
            if e != ok { ret (.Null, e) }
            push_array(&extension_ranges, v)
        } else if key.number == 6u32 {
            let (v, e) = parse_field(a, data)
            if e != ok { ret (.Null, e) }
            push_array(&extensions, v)
        } else if key.number == 7u32 {
            let (v, e) = parse_flags(a, data, 7u32, "mapEntry", 3u32, "deprecated")
            if e != ok { ret (.Null, e) }
            sync.put(&o, "options", v)
        } else if key.number == 8u32 {
            let (v, e) = parse_oneof(a, data)
            if e != ok { ret (.Null, e) }
            push_array(&oneofs, v)
        } else if key.number == 9u32 {
            let (v, e) = parse_range(a, data)
            if e != ok { ret (.Null, e) }
            push_array(&ranges, v)
        }
    }
    if fields.len > 0usize { sync.put(&o, "field", array_of(fields)) }
    if nested.len > 0usize { sync.put(&o, "nestedType", array_of(nested)) }
    if enums.len > 0usize { sync.put(&o, "enumType", array_of(enums)) }
    if extension_ranges.len > 0usize { sync.put(&o, "extensionRange", array_of(extension_ranges)) }
    if extensions.len > 0usize { sync.put(&o, "extension", array_of(extensions)) }
    if oneofs.len > 0usize { sync.put(&o, "oneofDecl", array_of(oneofs)) }
    if ranges.len > 0usize { sync.put(&o, "reservedRange", array_of(ranges)) }
    if names.len > 0usize { sync.put(&o, "reservedName", array_of(names)) }
    ret (finished(&o), ok)
}

// An int32 list member that may arrive one per key or packed in one length-delimited field.
fn read_int_list(a: *mem.Arena, r: *pb.Reader, key: pb.Key, out: *list.List[json.Value]) -> err {
    if key.wire == .Varint {
        let (v, e) = read_int(r)
        if e != ok { ret e }
        sync.push_value(out, sync.number(a, v))
        ret ok
    }
    let (data, e) = pb.read_bytes(r)
    if e != ok { ret Invalid }
    var inner = pb.reader(data)
    while true {
        if bytes.remaining_reader(&inner.input) == 0usize { break }
        let (v, ve) = read_int(&inner)
        if ve != ok { ret ve }
        sync.push_value(out, sync.number(a, v))
    }
    ret ok
}

// One `FileDescriptorProto`.
fn parse_file(a: *mem.Arena, source: []const u8) -> (json.Value, err) {
    var r = pb.reader(source)
    var o = sync.obj(a)
    var dependencies = sync.empty_list(a)
    var publics = sync.empty_list(a)
    var weaks = sync.empty_list(a)
    var messages = sync.empty_list(a)
    var enums = sync.empty_list(a)
    var services = sync.empty_list(a)
    var extensions = sync.empty_list(a)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (.Null, Invalid) }
        if !more { break }
        if key.number == 10u32 && (key.wire == .Varint || key.wire == .Bytes) {
            let e = read_int_list(a, &r, key, &publics)
            if e != ok { ret (.Null, e) }
            continue
        }
        if key.number == 11u32 && (key.wire == .Varint || key.wire == .Bytes) {
            let e = read_int_list(a, &r, key, &weaks)
            if e != ok { ret (.Null, e) }
            continue
        }
        if key.number == 14u32 && key.wire == .Varint {
            let (v, e) = read_int(&r)
            if e != ok { ret (.Null, e) }
            put_number(a, &o, "edition", v)
            continue
        }
        if key.wire != .Bytes {
            if pb.skip(&r, key.wire) != ok { ret (.Null, Invalid) }
            continue
        }
        if key.number == 1u32 || key.number == 2u32 || key.number == 3u32 || key.number == 12u32 {
            let (v, e) = read_text(a, &r)
            if e != ok { ret (.Null, e) }
            if key.number == 1u32 { sync.put(&o, "name", v) }
            if key.number == 2u32 { sync.put(&o, "package", v) }
            if key.number == 3u32 { push_array(&dependencies, v) }
            if key.number == 12u32 { sync.put(&o, "syntax", v) }
            continue
        }
        let (data, data_error) = pb.read_bytes(&r)
        if data_error != ok { ret (.Null, Invalid) }
        if key.number == 4u32 {
            let (v, e) = parse_message(a, data, 1u32)
            if e != ok { ret (.Null, e) }
            push_array(&messages, v)
        } else if key.number == 5u32 {
            let (v, e) = parse_enum(a, data)
            if e != ok { ret (.Null, e) }
            push_array(&enums, v)
        } else if key.number == 6u32 {
            let (v, e) = parse_service(a, data)
            if e != ok { ret (.Null, e) }
            push_array(&services, v)
        } else if key.number == 7u32 {
            let (v, e) = parse_field(a, data)
            if e != ok { ret (.Null, e) }
            push_array(&extensions, v)
        }
    }
    if dependencies.len > 0usize { sync.put(&o, "dependency", array_of(dependencies)) }
    if messages.len > 0usize { sync.put(&o, "messageType", array_of(messages)) }
    if enums.len > 0usize { sync.put(&o, "enumType", array_of(enums)) }
    if services.len > 0usize { sync.put(&o, "service", array_of(services)) }
    if extensions.len > 0usize { sync.put(&o, "extension", array_of(extensions)) }
    if publics.len > 0usize { sync.put(&o, "publicDependency", array_of(publics)) }
    if weaks.len > 0usize { sync.put(&o, "weakDependency", array_of(weaks)) }
    ret (finished(&o), ok)
}

// `{file: [FileDescriptorProto ...]}` from the bytes of a `FileDescriptorSet`.
fn parse_set(a: *mem.Arena, source: []const u8) -> (json.Value, err) {
    var r = pb.reader(source)
    var files = sync.empty_list(a)
    while true {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (.Null, Invalid) }
        if !more { break }
        if key.wire == .Bytes && key.number == 1u32 {
            let (data, e) = pb.read_bytes(&r)
            if e != ok { ret (.Null, Invalid) }
            let (v, ve) = parse_file(a, data)
            if ve != ok { ret (.Null, ve) }
            push_array(&files, v)
        } else {
            if pb.skip(&r, key.wire) != ok { ret (.Null, Invalid) }
        }
    }
    var o = sync.obj(a)
    if files.len > 0usize { sync.put(&o, "file", array_of(files)) }
    ret (finished(&o), ok)
}
