// JSON-RPC 2.0 and the Model Context Protocol handshake (L049), after Appdor's `src/mcp/protocol.js`: message
// classification (request, notification, or the reference's refusal tokens), the three supported protocol versions and
// their negotiation, the server capabilities, result and error envelopes, the three built-in prompts and their rendering,
// the `appdor://table/<id>/schema|records` resource URIs, newline-delimited stdio framing (encode, and decode with the
// unterminated remainder), batch handling, and the protocol-level half of the server state machine
// (`initialize`, `ping`, notifications, `prompts/list`, `prompts/get`, unknown methods, the initialize-first guard and
// the argument checks). Tool, resource and curated dispatch go to the caller's accessor, so those methods answer
// `delegate`.
//
// Memory: the arena is retained.

use e.algo.formula as f
use e.algo.ir as ir
use e.fmt.encode as encode
use e.fmt.json as json
use e.mem
use e.str

type Classified = struct { valid: bool, code: i64, reason: str, notification: bool, method: str, has_id: bool, id: json.Value }

type Prompt = struct { found: bool, valid: bool, message: str, description: str, text: str }

type Resource = struct { valid: bool, message: str, table_id: str, kind: str }

type Server = struct { initialized: bool, version: str, has_client: bool }

// 0 reply (`response`), 1 no reply (a notification), 2 delegate to the accessor.
type Handled = struct { kind: u8, response: json.Value }

type Chunk = struct { messages: []const json.Value, errors: []const str, remainder: str }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn sv(s: str) -> json.Value { ret json.Value{ String: s } }

fn int_value(a: *mem.Arena, n: i64) -> json.Value { ret json.Value{ Number: json.Number{ lexeme: f.number_text(a, f64(n)) } } }

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn new_obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    ret o
}

fn parse_error() -> i64 { ret -32700i64 }
fn invalid_request() -> i64 { ret -32600i64 }
fn method_not_found() -> i64 { ret -32601i64 }
fn invalid_params() -> i64 { ret -32602i64 }
fn internal_error() -> i64 { ret -32603i64 }

fn supported_versions() -> [3]str { ret [3]str{ "2025-06-18", "2025-03-26", "2024-11-05" } }

// A JSON-RPC result envelope.
fn rpc_result(a: *mem.Arena, id: json.Value, result: json.Value) -> json.Value {
    var o = new_obj(a)
    put(&o, "jsonrpc", sv("2.0"))
    put(&o, "id", id)
    put(&o, "result", result)
    ret ir.obj_value(&o)
}

// A JSON-RPC error envelope; an absent id is `null`.
fn rpc_error(a: *mem.Arena, id: json.Value, code: i64, message: str) -> json.Value {
    var e = new_obj(a)
    put(&e, "code", int_value(a, code))
    put(&e, "message", sv(message))
    var o = new_obj(a)
    put(&o, "jsonrpc", sv("2.0"))
    put(&o, "id", id)
    put(&o, "error", ir.obj_value(&e))
    ret ir.obj_value(&o)
}

// Whether a message is a request, a notification, or malformed (with the reference's token).
fn classify_message(message: json.Value) -> Classified {
    let none = Classified { valid: false, code: 0i64, reason: "", notification: false, method: "", has_id: false, id: .Null }
    var is_object = false
    switch message {
    case .Object as m:
        is_object = true
    default:
        is_object = false
    }
    if !is_object { ret Classified { valid: false, code: invalid_request(), reason: "message-not-an-object", notification: false, method: "", has_id: false, id: .Null } }
    let (jv, has_j) = ir.get(message, "jsonrpc")
    var version_ok = false
    if has_j {
        let (s, is_text) = ir.string_of(jv)
        version_ok = is_text && str.eq(s, "2.0")
    }
    if !version_ok { ret Classified { valid: false, code: invalid_request(), reason: "jsonrpc-must-be-2.0", notification: false, method: "", has_id: false, id: .Null } }
    let (mv, has_m) = ir.get(message, "method")
    var method = ""
    if has_m {
        let (s, is_text) = ir.string_of(mv)
        if is_text { method = s }
    }
    if method.len == 0usize { ret Classified { valid: false, code: invalid_request(), reason: "method-required", notification: false, method: "", has_id: false, id: .Null } }
    let (idv, has_id_key) = ir.get(message, "id")
    var has_id = has_id_key && !ir.is_null(idv)
    if has_id {
        var typed = false
        switch idv {
        case .String as s:
            typed = true
        case .Number as n:
            typed = true
        default:
            typed = false
        }
        if !typed { ret Classified { valid: false, code: invalid_request(), reason: "id-not-string-or-number", notification: false, method: "", has_id: false, id: .Null } }
    }
    ret Classified { valid: true, code: 0i64, reason: "", notification: !has_id, method: method, has_id: has_id, id: idv }
}

// The version a client's request is answered with: the requested one if supported, else the newest.
fn negotiate_version(requested: str) -> str {
    let v = supported_versions()
    var i = 0usize
    while i < 3usize {
        if str.eq(v[i], requested) { ret requested }
        i += 1usize
    }
    ret v[0]
}

fn capabilities(a: *mem.Arena, resources: bool, with_prompts: bool, tool_list_changed: bool) -> json.Value {
    var tools = new_obj(a)
    put(&tools, "listChanged", json.Value{ Bool: tool_list_changed })
    var o = new_obj(a)
    put(&o, "tools", ir.obj_value(&tools))
    if resources {
        var r = new_obj(a)
        put(&r, "subscribe", json.Value{ Bool: false })
        put(&r, "listChanged", json.Value{ Bool: false })
        put(&o, "resources", ir.obj_value(&r))
    }
    if with_prompts {
        var p = new_obj(a)
        put(&p, "listChanged", json.Value{ Bool: false })
        put(&o, "prompts", ir.obj_value(&p))
    }
    ret ir.obj_value(&o)
}

fn argument(a: *mem.Arena, name: str, description: str, required: bool) -> json.Value {
    var o = new_obj(a)
    put(&o, "name", sv(name))
    put(&o, "description", sv(description))
    put(&o, "required", json.Value{ Bool: required })
    ret ir.obj_value(&o)
}

fn prompt_entry(a: *mem.Arena, name: str, description: str, arguments: []const json.Value) -> json.Value {
    var o = new_obj(a)
    put(&o, "name", sv(name))
    put(&o, "description", sv(description))
    put(&o, "arguments", json.Value{ Array: arguments })
    ret ir.obj_value(&o)
}

// The three built-in prompts.
fn prompts(a: *mem.Arena) -> json.Value {
    let (out, e) = mem.alloc[json.Value](a, 3usize)
    let none: []const json.Value = zero
    out[0] = prompt_entry(a, "explore_base", "Survey this base: list its tables, read each schema, and summarise what the base is for.", none)
    let (two, te) = mem.alloc[json.Value](a, 2usize)
    two[0] = argument(a, "table", "The table name or id to search.", true)
    two[1] = argument(a, "criteria", "What to look for, in plain language.", true)
    out[1] = prompt_entry(a, "find_records", "Find records in a table matching a plain-language description.", two[0usize..2usize])
    let (one, oe) = mem.alloc[json.Value](a, 1usize)
    one[0] = argument(a, "table", "The table name or id.", true)
    out[2] = prompt_entry(a, "summarize_table", "Summarise a table: its shape, its row count, and what the data appears to represent.", one[0usize..1usize])
    ret json.Value{ Array: out[0usize..3usize] }
}

fn arg_truthy(args: json.Value, name: str) -> bool { ret ir.truthy(ir.value_of(args, name)) }

fn arg_text(a: *mem.Arena, args: json.Value, name: str) -> str {
    let v = ir.value_of(args, name)
    switch v {
    case .String as s:
        ret s
    case .Number as n:
        ret n.lexeme
    case .Bool as b:
        if b { ret "true" }
        ret "false"
    case .Null:
        ret "undefined"
    default:
        ret "[object Object]"
    }
}

// A prompt rendered for its arguments; `found` false when the name is unknown, `valid` false when arguments are missing.
fn render_prompt(a: *mem.Arena, name: str, args: json.Value) -> Prompt {
    if str.eq(name, "explore_base") {
        ret Prompt { found: true, valid: true, message: "", description: "Survey this base: list its tables, read each schema, and summarise what the base is for.", text: "List every table in this base with list_tables, read each one's schema with get_schema, then describe in a few sentences what this base is for and how its tables relate." }
    }
    if str.eq(name, "find_records") {
        var missing = ""
        if !arg_truthy(args, "table") { missing = "table" }
        if !arg_truthy(args, "criteria") {
            if missing.len > 0usize {
                missing = join(a, missing, ", criteria")
            } else {
                missing = "criteria"
            }
        }
        if missing.len > 0usize { ret Prompt { found: true, valid: false, message: join(a, "missing-arguments: ", missing), description: "", text: "" } }
        var text = join(a, join(a, "Find records in the table \"", arg_text(a, args, "table")), join(a, "\" matching: ", arg_text(a, args, "criteria")))
        text = join(a, text, ". Use get_schema first to learn the field names, then query_records with an exact field→value filter. The filter matches on the field's text form and is exact — narrow with one field, then filter further yourself.")
        ret Prompt { found: true, valid: true, message: "", description: "Find records in a table matching a plain-language description.", text: text }
    }
    if str.eq(name, "summarize_table") {
        if !arg_truthy(args, "table") { ret Prompt { found: true, valid: false, message: "missing-arguments: table", description: "", text: "" } }
        var text = join(a, join(a, "Read the schema of \"", arg_text(a, args, "table")), "\" with get_schema, query a sample of its records, and summarise the table: what each field holds, roughly how many records there are, and what the table represents.")
        ret Prompt { found: true, valid: true, message: "", description: "Summarise a table: its shape, its row count, and what the data appears to represent.", text: text }
    }
    ret Prompt { found: false, valid: false, message: join(a, "unknown-prompt: ", name), description: "", text: "" }
}

fn table_resource_uri(a: *mem.Arena, table_id: str) -> str { ret join(a, join(a, "appdor://table/", table_id), "/schema") }

// `appdor://table/<id>/schema` or `/records`.
fn parse_resource_uri(a: *mem.Arena, uri: str) -> Resource {
    let prefix = "appdor://table/"
    var ok_shape = str.starts_with(uri, prefix)
    var table = ""
    var kind = ""
    if ok_shape {
        let rest = uri[prefix.len..]
        var slash = -1i64
        var i = 0usize
        while i < rest.len {
            if rest[i] == 47u8 {
                slash = i64(i)
                break
            }
            i += 1usize
        }
        if slash <= 0i64 {
            ok_shape = false
        } else {
            table = rest[0usize..usize(slash)]
            kind = rest[usize(slash) + 1usize..]
            if !str.eq(kind, "schema") && !str.eq(kind, "records") { ok_shape = false }
        }
    }
    if !ok_shape { ret Resource { valid: false, message: join(a, "unrecognised-resource-uri: ", uri), table_id: "", kind: "" } }
    ret Resource { valid: true, message: "", table_id: table, kind: kind }
}

// One message as a newline-terminated line.
fn encode_stdio_message(a: *mem.Arena, message: json.Value) -> str {
    let (text, e) = encode.json_encode(a, message)
    ret join(a, text, "\n")
}

// The messages in a buffer of newline-delimited JSON, the lines that were not JSON, and the unterminated tail.
fn decode_stdio_chunk(a: *mem.Arena, buffer: str) -> Chunk {
    let (messages, e1) = mem.alloc[json.Value](a, buffer.len + 1usize)
    let (errors, e2) = mem.alloc[str](a, buffer.len + 1usize)
    var nm = 0usize
    var ne = 0usize
    var start = 0usize
    var last = 0usize
    var i = 0usize
    while i < buffer.len {
        if buffer[i] == 10u8 {
            let line = buffer[start..i]
            var blank = true
            var k = 0usize
            while k < line.len {
                let c = line[k]
                if !(c == 32u8 || c == 9u8 || c == 13u8 || c == 11u8 || c == 12u8) { blank = false }
                k += 1usize
            }
            if !blank {
                let (v, pe) = json.parse(a, line, json.Options { allow_duplicate_keys: true, max_depth: 64u16 })
                if pe == ok {
                    messages[nm] = v
                    nm += 1usize
                } else {
                    errors[ne] = line
                    ne += 1usize
                }
            }
            start = i + 1usize
            last = start
        }
        i += 1usize
    }
    ret Chunk { messages: messages[0usize..nm], errors: errors[0usize..ne], remainder: buffer[last..] }
}

fn new_server() -> Server { ret Server { initialized: false, version: "", has_client: false } }

fn pending(a: *mem.Arena, id: json.Value) -> json.Value { ret rpc_error(a, id, invalid_request(), "initialize-first") }

// The protocol-level handling of one message; the accessor-backed methods are delegated.
fn handle(a: *mem.Arena, s: *Server, message: json.Value, instructions: str) -> Handled {
    let c = classify_message(message)
    var id = ir.value_of(message, "id")
    if !c.valid { ret Handled { kind: 0u8, response: rpc_error(a, id, c.code, c.reason) } }
    id = c.id
    if c.notification {
        if str.eq(c.method, "notifications/initialized") { s.initialized = true }
        ret Handled { kind: 1u8, response: .Null }
    }
    var params = ir.value_of(message, "params")
    if !ir.truthy(params) { params = ir.empty_object() }
    if str.eq(c.method, "initialize") {
        var requested = ""
        let (pv, has_pv) = ir.get(params, "protocolVersion")
        if has_pv {
            let (t, is_text) = ir.string_of(pv)
            if is_text { requested = t }
        }
        s.version = negotiate_version(requested)
        s.has_client = ir.truthy(ir.value_of(params, "clientInfo"))
        s.initialized = true
        var info = new_obj(a)
        put(&info, "name", sv("appdor"))
        put(&info, "version", sv("1.0.0"))
        var r = new_obj(a)
        put(&r, "protocolVersion", sv(s.version))
        put(&r, "capabilities", capabilities(a, true, true, false))
        put(&r, "serverInfo", ir.obj_value(&info))
        if instructions.len > 0usize { put(&r, "instructions", sv(instructions)) }
        ret Handled { kind: 0u8, response: rpc_result(a, id, ir.obj_value(&r)) }
    }
    if str.eq(c.method, "ping") { ret Handled { kind: 0u8, response: rpc_result(a, id, ir.empty_object()) } }
    if str.eq(c.method, "tools/list") || str.eq(c.method, "resources/list") || str.eq(c.method, "prompts/list") || str.eq(c.method, "tools/call") || str.eq(c.method, "resources/read") || str.eq(c.method, "prompts/get") {
        if !s.initialized { ret Handled { kind: 0u8, response: pending(a, id) } }
    }
    if str.eq(c.method, "prompts/list") {
        var r = new_obj(a)
        put(&r, "prompts", prompts(a))
        ret Handled { kind: 0u8, response: rpc_result(a, id, ir.obj_value(&r)) }
    }
    if str.eq(c.method, "prompts/get") {
        var args = ir.value_of(params, "arguments")
        if !ir.truthy(args) { args = ir.empty_object() }
        var name = ""
        let (nv, has_nv) = ir.get(params, "name")
        if has_nv {
            let (t, is_text) = ir.string_of(nv)
            if is_text { name = t }
        }
        let p = render_prompt(a, name, args)
        if !p.valid { ret Handled { kind: 0u8, response: rpc_error(a, id, invalid_params(), p.message) } }
        var content = new_obj(a)
        put(&content, "type", sv("text"))
        put(&content, "text", sv(p.text))
        var msg = new_obj(a)
        put(&msg, "role", sv("user"))
        put(&msg, "content", ir.obj_value(&content))
        let (arr, ae) = mem.alloc[json.Value](a, 1usize)
        arr[0] = ir.obj_value(&msg)
        var r = new_obj(a)
        put(&r, "description", sv(p.description))
        put(&r, "messages", json.Value{ Array: arr[0usize..1usize] })
        ret Handled { kind: 0u8, response: rpc_result(a, id, ir.obj_value(&r)) }
    }
    if str.eq(c.method, "tools/call") {
        let (nv, has_nv) = ir.get(params, "name")
        var is_text = false
        if has_nv {
            let (t, ok_t) = ir.string_of(nv)
            is_text = ok_t
        }
        if !is_text { ret Handled { kind: 0u8, response: rpc_error(a, id, invalid_params(), "params.name-required") } }
        ret Handled { kind: 2u8, response: .Null }
    }
    if str.eq(c.method, "resources/read") {
        var uri = ""
        let uv = ir.value_of(params, "uri")
        if ir.truthy(uv) { uri = arg_text(a, params, "uri") }
        let r = parse_resource_uri(a, uri)
        if !r.valid { ret Handled { kind: 0u8, response: rpc_error(a, id, invalid_params(), r.message) } }
        ret Handled { kind: 2u8, response: .Null }
    }
    if str.eq(c.method, "tools/list") || str.eq(c.method, "resources/list") { ret Handled { kind: 2u8, response: .Null } }
    ret Handled { kind: 0u8, response: rpc_error(a, id, method_not_found(), join(a, "unknown-method: ", c.method)) }
}
