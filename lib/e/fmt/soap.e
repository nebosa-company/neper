// SOAP 1.1 and 1.2 envelopes, faults and a WSDL 1.1 operation reader, over e.fmt.xml and
// nothing else: no HTTP client or server (the caller sends `content_type` and, for 1.1, the
// SOAPAction header), no schema validation (that is XSD work), no WS-* headers beyond reading
// `mustUnderstand`. A fault is data (`Fault`) and `fault_error` maps its code to a typed error.
// Namespaces are resolved through the document's xmlns bindings, so any prefix works.

use e.fmt.xml as xml
use e.io
use e.mem
use e.str

error Invalid
error NotSoap
error VersionMismatch
error MustUnderstand
error DataEncodingUnknown
error Sender
error Receiver
error OtherFault
error TooLarge

type Version = enum u8 { Soap11, Soap12 }
type FaultCode = enum u8 { VersionMismatch, MustUnderstand, DataEncodingUnknown, Sender, Receiver, Other }

// The envelope namespace of a version.
fn namespace(v: Version) -> str {
    if v == .Soap11 { ret "http://schemas.xmlsoap.org/soap/envelope/" }
    ret "http://www.w3.org/2003/05/soap-envelope"
}

fn content_type(a: *mem.Arena, v: Version, action: str) -> (str, err) {
    if v == .Soap11 { ret ("text/xml; charset=utf-8", ok) }
    if action.len == 0usize { ret ("application/soap+xml; charset=utf-8", ok) }
    let (head, head_error) = str.concat(a, "application/soap+xml; charset=utf-8; action=\"", action)
    if head_error != ok { ret ("", head_error) }
    let (whole, whole_error) = str.concat(a, head, "\"")
    ret (whole, whole_error)
}

// ---- building ----

type Builder = struct { w: xml.Writer, version: Version, prefix: str, scratch: *mem.Arena }

fn builder(a: *mem.Arena, sink: io.Writer, version: Version, prefix: str) -> (Builder, err) {
    if prefix.len == 0usize { ret (zero, Invalid) }
    ret (Builder { w: xml.writer(sink), version: version, prefix: prefix, scratch: a }, ok)
}

fn qualified(b: *const Builder, local: str) -> (str, err) {
    let (head, head_error) = str.concat(b.scratch, b.prefix, ":")
    if head_error != ok { ret ("", head_error) }
    let (name, name_error) = str.concat(b.scratch, head, local)
    ret (name, name_error)
}

// `<p:Envelope xmlns:p="...">`
fn begin(b: *Builder) -> err {
    let (name, name_error) = qualified(b, "Envelope")
    if name_error != ok { ret name_error }
    let (declaration, declaration_error) = str.concat(b.scratch, "xmlns:", b.prefix)
    if declaration_error != ok { ret declaration_error }
    var attributes = [1]xml.Attribute{ xml.Attribute { name: declaration, value: namespace(b.version) } }
    ret xml.start(&b.w, name, attributes[..])
}

fn open_part(b: *Builder, local: str) -> err {
    let (name, name_error) = qualified(b, local)
    if name_error != ok { ret name_error }
    ret xml.start(&b.w, name, zero)
}

fn close_part(b: *Builder, local: str) -> err {
    let (name, name_error) = qualified(b, local)
    if name_error != ok { ret name_error }
    ret xml.end(&b.w, name)
}

fn header_start(b: *Builder) -> err { ret open_part(b, "Header") }
fn header_end(b: *Builder) -> err { ret close_part(b, "Header") }
fn body_start(b: *Builder) -> err { ret open_part(b, "Body") }

// The `p:mustUnderstand="1"` attribute for a header block's start tag (`true` in 1.2 is accepted on
// parse, but "1" is valid in both versions).
fn must_understand_attribute(b: *const Builder) -> (xml.Attribute, err) {
    let (name, name_error) = qualified(b, "mustUnderstand")
    ret (xml.Attribute { name: name, value: "1" }, name_error)
}

// Close the body and the envelope.
fn finish(b: *Builder) -> err {
    try close_part(b, "Body")
    ret close_part(b, "Envelope")
}

type FaultOut = struct { code: FaultCode, reason: str, language: str, actor: str, detail: str, subcode: str }

fn code_local(v: Version, code: FaultCode) -> str {
    if code == .VersionMismatch { ret "VersionMismatch" }
    if code == .MustUnderstand { ret "MustUnderstand" }
    if code == .DataEncodingUnknown { ret "DataEncodingUnknown" }
    if code == .Sender { if v == .Soap11 { ret "Client" } else { ret "Sender" } }
    if code == .Receiver { if v == .Soap11 { ret "Server" } else { ret "Receiver" } }
    ret ""
}

fn simple_element(b: *Builder, name: str, value: str) -> err {
    try xml.start(&b.w, name, zero)
    try xml.text(&b.w, value)
    ret xml.end(&b.w, name)
}

// The whole `<p:Fault>` inside an open body. 1.1: faultcode, faultstring, faultactor, detail. 1.2: Code
// (with an optional Subcode), Reason/Text with xml:lang, Role, Detail. `detail` is text; a richer detail
// is written by the caller around `fault_start`/`fault_end` instead. Refused: `DataEncodingUnknown` in
// 1.1 (it has no such code), `Other` (a code the caller names itself), or an empty reason.
fn fault_write(b: *Builder, f: FaultOut) -> err {
    if f.code == .Other || f.reason.len == 0usize { ret Invalid }
    if b.version == .Soap11 && f.code == .DataEncodingUnknown { ret Invalid }
    let (fault_name, fault_name_error) = qualified(b, "Fault")
    if fault_name_error != ok { ret fault_name_error }
    try xml.start(&b.w, fault_name, zero)
    let (code_value, code_error) = qualified(b, code_local(b.version, f.code))
    if code_error != ok { ret code_error }
    if b.version == .Soap11 {
        try simple_element(b, "faultcode", code_value)
        try simple_element(b, "faultstring", f.reason)
        if f.actor.len > 0usize { try simple_element(b, "faultactor", f.actor) }
        if f.detail.len > 0usize { try simple_element(b, "detail", f.detail) }
    } else {
        let (code_name, code_name_error) = qualified(b, "Code")
        if code_name_error != ok { ret code_name_error }
        let (value_name, value_name_error) = qualified(b, "Value")
        if value_name_error != ok { ret value_name_error }
        try xml.start(&b.w, code_name, zero)
        try simple_element(b, value_name, code_value)
        if f.subcode.len > 0usize {
            let (sub_name, sub_error) = qualified(b, "Subcode")
            if sub_error != ok { ret sub_error }
            try xml.start(&b.w, sub_name, zero)
            try simple_element(b, value_name, f.subcode)
            try xml.end(&b.w, sub_name)
        }
        try xml.end(&b.w, code_name)
        let (reason_name, reason_error) = qualified(b, "Reason")
        if reason_error != ok { ret reason_error }
        let (text_name, text_error) = qualified(b, "Text")
        if text_error != ok { ret text_error }
        try xml.start(&b.w, reason_name, zero)
        var language = f.language
        if language.len == 0usize { language = "en" }
        var lang = [1]xml.Attribute{ xml.Attribute { name: "xml:lang", value: language } }
        try xml.start(&b.w, text_name, lang[..])
        try xml.text(&b.w, f.reason)
        try xml.end(&b.w, text_name)
        try xml.end(&b.w, reason_name)
        if f.actor.len > 0usize {
            let (role_name, role_error) = qualified(b, "Role")
            if role_error != ok { ret role_error }
            try simple_element(b, role_name, f.actor)
        }
        if f.detail.len > 0usize {
            let (detail_name, detail_error) = qualified(b, "Detail")
            if detail_error != ok { ret detail_error }
            try simple_element(b, detail_name, f.detail)
        }
    }
    ret xml.end(&b.w, fault_name)
}

// ---- parsing ----

type Envelope = struct { version: Version, document: xml.Document, root: xml.NodeId, header: xml.NodeId, body: xml.NodeId }

fn node(d: *const xml.Document, id: xml.NodeId) -> xml.Node { ret d.nodes[usize(id)] }

// The prefix of a qualified name ("" when there is none) and its local part.
fn split_name(name: str) -> (str, str) {
    let (at, found) = str.find(name, ":")
    if !found { ret ("", name) }
    ret (name[..at], name[at + 1usize..])
}

fn declares(attribute_name: str, prefix: str) -> bool {
    if prefix.len == 0usize { ret str.eq(attribute_name, "xmlns") }
    ret attribute_name.len == prefix.len + 6usize && str.starts_with(attribute_name, "xmlns:") && str.eq(attribute_name[6usize..], prefix)
}

// The namespace bound to `prefix` at element `id` ("" for an unbound default namespace); an unbound
// non-empty prefix is `Invalid`.
fn resolve(d: *const xml.Document, id: xml.NodeId, prefix: str) -> (str, err) {
    if str.eq(prefix, "xml") { ret ("http://www.w3.org/XML/1998/namespace", ok) }
    var at = id
    while at != 4294967295u32 {
        let n = node(d, at)
        if n.kind == .Element {
            var i = 0usize
            while i < n.attributes.len {
                if declares(n.attributes[i].name, prefix) { ret (n.attributes[i].value, ok) }
                i += 1usize
            }
        }
        at = n.parent
    }
    if prefix.len == 0usize { ret ("", ok) }
    ret ("", Invalid)
}

// An element's namespace and local name.
fn expand(d: *const xml.Document, id: xml.NodeId) -> (str, str, err) {
    let (prefix, local) = split_name(node(d, id).name)
    let (uri, resolve_error) = resolve(d, id, prefix)
    ret (uri, local, resolve_error)
}

fn is_named(d: *const xml.Document, id: xml.NodeId, uri: str, local: str) -> bool {
    if node(d, id).kind != .Element { ret false }
    let (found_uri, found_local, expand_error) = expand(d, id)
    ret expand_error == ok && str.eq(found_uri, uri) && str.eq(found_local, local)
}

// The first child element of `parent` that is not a text, comment or processing node, from `from`.
fn next_element(d: *const xml.Document, from: xml.NodeId) -> xml.NodeId {
    var at = from
    while at != 4294967295u32 {
        if node(d, at).kind == .Element { ret at }
        at = node(d, at).next_sibling
    }
    ret 4294967295u32
}

fn first_child_element(d: *const xml.Document, parent: xml.NodeId) -> xml.NodeId {
    ret next_element(d, node(d, parent).first_child)
}

fn next_sibling_element(d: *const xml.Document, id: xml.NodeId) -> xml.NodeId {
    ret next_element(d, node(d, id).next_sibling)
}

// The text of an element: its text children joined.
fn element_text(a: *mem.Arena, d: *const xml.Document, id: xml.NodeId) -> (str, err) {
    var out = ""
    var at = node(d, id).first_child
    while at != 4294967295u32 {
        if node(d, at).kind == .Text {
            let (joined, join_error) = str.concat(a, out, node(d, at).value)
            if join_error != ok { ret ("", join_error) }
            out = joined
        }
        at = node(d, at).next_sibling
    }
    ret (out, ok)
}

// An envelope from bytes. `NotSoap` when the root is not an Envelope, `VersionMismatch` when it is an
// Envelope in another namespace (the case SOAP answers with a VersionMismatch fault), `Invalid` when the
// body is missing or duplicated, the header follows the body, or something else sits in the envelope.
fn parse(a: *mem.Arena, source: []const u8) -> (Envelope, err) {
    let (d, parse_error) = xml.parse(a, source)
    if parse_error != ok { ret (zero, parse_error) }
    if d.root == 4294967295u32 { ret (zero, NotSoap) }
    let (uri, local, expand_error) = expand(&d, d.root)
    if expand_error != ok { ret (zero, expand_error) }
    if !str.eq(local, "Envelope") { ret (zero, NotSoap) }
    var version = Version.Soap11
    if str.eq(uri, namespace(.Soap12)) {
        version = .Soap12
    } else if !str.eq(uri, namespace(.Soap11)) {
        ret (zero, VersionMismatch)
    }
    var header = 4294967295u32
    var body = 4294967295u32
    var at = first_child_element(&d, d.root)
    while at != 4294967295u32 {
        if is_named(&d, at, uri, "Header") {
            if header != 4294967295u32 || body != 4294967295u32 { ret (zero, Invalid) }
            header = at
        } else if is_named(&d, at, uri, "Body") {
            if body != 4294967295u32 { ret (zero, Invalid) }
            body = at
        } else if body != 4294967295u32 {
            // SOAP 1.1 allows trailing namespaced elements after the body; 1.2 does not.
            if version == .Soap12 { ret (zero, Invalid) }
        } else {
            ret (zero, Invalid)
        }
        at = next_sibling_element(&d, at)
    }
    if body == 4294967295u32 { ret (zero, Invalid) }
    ret (Envelope { version: version, document: d, root: d.root, header: header, body: body }, ok)
}

// The first element in the body, the payload or the fault (`NONE` for an empty body).
fn payload(e: *const Envelope) -> xml.NodeId {
    ret first_child_element(&e.document, e.body)
}

fn is_fault(e: *const Envelope) -> bool {
    let p = payload(e)
    if p == 4294967295u32 { ret false }
    ret is_named(&e.document, p, namespace(e.version), "Fault")
}

// Header blocks the sender marked `mustUnderstand` ("1" or "true"), as node ids in `out`; answers how many
// (`TooLarge` when `out` is short).
fn must_understand_blocks(a: *mem.Arena, e: *const Envelope, out: []xml.NodeId) -> (usize, err) {
    if e.header == 4294967295u32 { ret (0usize, ok) }
    let uri = namespace(e.version)
    var used = 0usize
    var at = first_child_element(&e.document, e.header)
    while at != 4294967295u32 {
        let n = node(&e.document, at)
        var i = 0usize
        while i < n.attributes.len {
            let (prefix, local) = split_name(n.attributes[i].name)
            if str.eq(local, "mustUnderstand") && prefix.len > 0usize {
                let (attribute_uri, resolve_error) = resolve(&e.document, at, prefix)
                if resolve_error != ok { ret (used, resolve_error) }
                let value = n.attributes[i].value
                if str.eq(attribute_uri, uri) && (str.eq(value, "1") || str.eq(value, "true")) {
                    if used >= out.len { ret (used, TooLarge) }
                    out[used] = at
                    used += 1usize
                }
            }
            i += 1usize
        }
        at = next_sibling_element(&e.document, at)
    }
    ret (used, ok)
}

type Fault = struct { version: Version, code: FaultCode, code_text: str, subcode: str, reason: str, language: str, actor: str, detail: xml.NodeId }

fn child_named(d: *const xml.Document, parent: xml.NodeId, uri: str, local: str) -> xml.NodeId {
    var at = first_child_element(d, parent)
    while at != 4294967295u32 {
        if is_named(d, at, uri, local) { ret at }
        at = next_sibling_element(d, at)
    }
    ret 4294967295u32
}

// The envelope-namespace fault code in "prefix:local" text, resolved at element `at`.
fn code_of(d: *const xml.Document, at: xml.NodeId, raw: str, v: Version) -> (FaultCode, err) {
    let (prefix, local) = split_name(str.trim(raw))
    let (uri, resolve_error) = resolve(d, at, prefix)
    if resolve_error != ok { ret (FaultCode.Other, resolve_error) }
    if !str.eq(uri, namespace(v)) { ret (FaultCode.Other, ok) }
    if str.eq(local, "VersionMismatch") { ret (FaultCode.VersionMismatch, ok) }
    if str.eq(local, "MustUnderstand") { ret (FaultCode.MustUnderstand, ok) }
    if v == .Soap12 && str.eq(local, "DataEncodingUnknown") { ret (FaultCode.DataEncodingUnknown, ok) }
    if (v == .Soap11 && str.eq(local, "Client")) || (v == .Soap12 && str.eq(local, "Sender")) { ret (FaultCode.Sender, ok) }
    if (v == .Soap11 && str.eq(local, "Server")) || (v == .Soap12 && str.eq(local, "Receiver")) { ret (FaultCode.Receiver, ok) }
    ret (FaultCode.Other, ok)
}

// Decode the body's Fault. 1.1 takes faultcode/faultstring/faultactor/detail (unqualified); 1.2 takes
// Code/Value (and the first Subcode/Value), Reason/Text (with its xml:lang), Role and Detail. A code in
// the envelope namespace is mapped (Client and Sender are `.Sender`, Server and Receiver `.Receiver`); any
// other code is `.Other` with `code_text` holding it. `Invalid` when the body is not a fault or lacks a
// code or reason.
fn parse_fault(a: *mem.Arena, e: *const Envelope) -> (Fault, err) {
    if !is_fault(e) { ret (zero, Invalid) }
    let d = &e.document
    let fault_id = payload(e)
    let uri = namespace(e.version)
    var f: Fault = zero
    f.version = e.version
    f.detail = 4294967295u32
    if e.version == .Soap11 {
        let code_id = child_named(d, fault_id, "", "faultcode")
        let reason_id = child_named(d, fault_id, "", "faultstring")
        if code_id == 4294967295u32 || reason_id == 4294967295u32 { ret (zero, Invalid) }
        let (raw, raw_error) = element_text(a, d, code_id)
        if raw_error != ok { ret (zero, raw_error) }
        f.code_text = str.trim(raw)
        let (code, code_error) = code_of(d, code_id, raw, e.version)
        if code_error != ok { ret (zero, code_error) }
        f.code = code
        let (reason, reason_error) = element_text(a, d, reason_id)
        if reason_error != ok { ret (zero, reason_error) }
        f.reason = reason
        let actor_id = child_named(d, fault_id, "", "faultactor")
        if actor_id != 4294967295u32 {
            let (actor, actor_error) = element_text(a, d, actor_id)
            if actor_error != ok { ret (zero, actor_error) }
            f.actor = actor
        }
        f.detail = child_named(d, fault_id, "", "detail")
        ret (f, ok)
    }
    let code_id = child_named(d, fault_id, uri, "Code")
    let reason_id = child_named(d, fault_id, uri, "Reason")
    if code_id == 4294967295u32 || reason_id == 4294967295u32 { ret (zero, Invalid) }
    let value_id = child_named(d, code_id, uri, "Value")
    if value_id == 4294967295u32 { ret (zero, Invalid) }
    let (raw, raw_error) = element_text(a, d, value_id)
    if raw_error != ok { ret (zero, raw_error) }
    f.code_text = str.trim(raw)
    let (code, code_error) = code_of(d, value_id, raw, e.version)
    if code_error != ok { ret (zero, code_error) }
    f.code = code
    let sub_id = child_named(d, code_id, uri, "Subcode")
    if sub_id != 4294967295u32 {
        let sub_value = child_named(d, sub_id, uri, "Value")
        if sub_value != 4294967295u32 {
            let (sub, sub_error) = element_text(a, d, sub_value)
            if sub_error != ok { ret (zero, sub_error) }
            f.subcode = str.trim(sub)
        }
    }
    let text_id = child_named(d, reason_id, uri, "Text")
    if text_id == 4294967295u32 { ret (zero, Invalid) }
    let (reason, reason_error) = element_text(a, d, text_id)
    if reason_error != ok { ret (zero, reason_error) }
    f.reason = reason
    let text_node = node(d, text_id)
    let (language, has_language) = xml.attribute(&text_node, "xml:lang")
    if has_language { f.language = language }
    let role_id = child_named(d, fault_id, uri, "Role")
    if role_id != 4294967295u32 {
        let (role, role_error) = element_text(a, d, role_id)
        if role_error != ok { ret (zero, role_error) }
        f.actor = role
    }
    f.detail = child_named(d, fault_id, uri, "Detail")
    ret (f, ok)
}

// The typed error for a fault code.
fn fault_error(code: FaultCode) -> err {
    if code == .VersionMismatch { ret VersionMismatch }
    if code == .MustUnderstand { ret MustUnderstand }
    if code == .DataEncodingUnknown { ret DataEncodingUnknown }
    if code == .Sender { ret Sender }
    if code == .Receiver { ret Receiver }
    ret OtherFault
}

// ---- WSDL 1.1 ----

type Part = struct { name: str, type_name: str, element: str }
type Operation = struct { name: str, action: str, style: str, input: str, output: str, input_parts: []Part, output_parts: []Part }
type Wsdl = struct { target_namespace: str, location: str, soap: Version, operations: []Operation }

fn wsdl_namespace() -> str { ret "http://schemas.xmlsoap.org/wsdl/" }
fn wsdl_soap11() -> str { ret "http://schemas.xmlsoap.org/wsdl/soap/" }
fn wsdl_soap12() -> str { ret "http://schemas.xmlsoap.org/wsdl/soap12/" }

fn attr(d: *const xml.Document, id: xml.NodeId, name: str) -> str {
    let element_node = node(d, id)
    let (value, found) = xml.attribute(&element_node, name)
    if found { ret value }
    ret ""
}

fn local_of(qname: str) -> str {
    let (_, local) = split_name(qname)
    ret local
}

fn collect_parts(a: *mem.Arena, d: *const xml.Document, definitions: xml.NodeId, message: str) -> ([]Part, err) {
    let ns = wsdl_namespace()
    var count = 0usize
    var at = first_child_element(d, definitions)
    while at != 4294967295u32 {
        if is_named(d, at, ns, "message") && str.eq(attr(d, at, "name"), message) {
            var p = first_child_element(d, at)
            while p != 4294967295u32 {
                if is_named(d, p, ns, "part") { count += 1usize }
                p = next_sibling_element(d, p)
            }
        }
        at = next_sibling_element(d, at)
    }
    if count == 0usize { ret (zero, ok) }
    let (parts, alloc_error) = mem.alloc[Part](a, count)
    if alloc_error != ok { ret (zero, alloc_error) }
    var used = 0usize
    at = first_child_element(d, definitions)
    while at != 4294967295u32 {
        if is_named(d, at, ns, "message") && str.eq(attr(d, at, "name"), message) {
            var p = first_child_element(d, at)
            while p != 4294967295u32 {
                if is_named(d, p, ns, "part") {
                    parts[used] = Part { name: attr(d, p, "name"), type_name: attr(d, p, "type"), element: attr(d, p, "element") }
                    used += 1usize
                }
                p = next_sibling_element(d, p)
            }
        }
        at = next_sibling_element(d, at)
    }
    ret (parts[..used], ok)
}

// The operations of a WSDL 1.1 document's port types joined with their SOAP binding (the soapAction and the
// style, a binding default overridden per operation) and the message parts; the first SOAP port's address
// is `location`. `Invalid` when the root is not wsdl:definitions or a port type operation lacks a name.
fn wsdl_parse(a: *mem.Arena, source: []const u8) -> (Wsdl, err) {
    let (d, parse_error) = xml.parse(a, source)
    if parse_error != ok { ret (zero, parse_error) }
    if d.root == 4294967295u32 || !is_named(&d, d.root, wsdl_namespace(), "definitions") { ret (zero, Invalid) }
    let ns = wsdl_namespace()
    var out: Wsdl = zero
    out.target_namespace = attr(&d, d.root, "targetNamespace")
    var count = 0usize
    var at = first_child_element(&d, d.root)
    while at != 4294967295u32 {
        if is_named(&d, at, ns, "portType") {
            var op = first_child_element(&d, at)
            while op != 4294967295u32 {
                if is_named(&d, op, ns, "operation") { count += 1usize }
                op = next_sibling_element(&d, op)
            }
        }
        at = next_sibling_element(&d, at)
    }
    if count == 0usize { ret (out, ok) }
    let (operations, alloc_error) = mem.alloc[Operation](a, count)
    if alloc_error != ok { ret (zero, alloc_error) }
    var used = 0usize
    at = first_child_element(&d, d.root)
    while at != 4294967295u32 {
        if is_named(&d, at, ns, "portType") {
            var op = first_child_element(&d, at)
            while op != 4294967295u32 {
                if is_named(&d, op, ns, "operation") {
                    let name = attr(&d, op, "name")
                    if name.len == 0usize { ret (zero, Invalid) }
                    var o: Operation = zero
                    o.name = name
                    o.style = "document"
                    var io_id = first_child_element(&d, op)
                    while io_id != 4294967295u32 {
                        if is_named(&d, io_id, ns, "input") { o.input = local_of(attr(&d, io_id, "message")) }
                        if is_named(&d, io_id, ns, "output") { o.output = local_of(attr(&d, io_id, "message")) }
                        io_id = next_sibling_element(&d, io_id)
                    }
                    let (input_parts, input_error) = collect_parts(a, &d, d.root, o.input)
                    if input_error != ok { ret (zero, input_error) }
                    o.input_parts = input_parts
                    let (output_parts, output_error) = collect_parts(a, &d, d.root, o.output)
                    if output_error != ok { ret (zero, output_error) }
                    o.output_parts = output_parts
                    operations[used] = o
                    used += 1usize
                }
                op = next_sibling_element(&d, op)
            }
        }
        at = next_sibling_element(&d, at)
    }
    // Bindings: the binding-level style, then each operation's soapAction and style.
    at = first_child_element(&d, d.root)
    while at != 4294967295u32 {
        if is_named(&d, at, ns, "binding") {
            var default_style = "document"
            var version = Version.Soap11
            var child = first_child_element(&d, at)
            while child != 4294967295u32 {
                let (child_uri, child_local, child_error) = expand(&d, child)
                if child_error == ok && str.eq(child_local, "binding") && (str.eq(child_uri, wsdl_soap11()) || str.eq(child_uri, wsdl_soap12())) {
                    if str.eq(child_uri, wsdl_soap12()) { version = .Soap12 }
                    let style = attr(&d, child, "style")
                    if style.len > 0usize { default_style = style }
                    out.soap = version
                }
                if is_named(&d, child, ns, "operation") {
                    let op_name = attr(&d, child, "name")
                    var action = ""
                    var style = default_style
                    var inner = first_child_element(&d, child)
                    while inner != 4294967295u32 {
                        let (inner_uri, inner_local, inner_error) = expand(&d, inner)
                        if inner_error == ok && str.eq(inner_local, "operation") && (str.eq(inner_uri, wsdl_soap11()) || str.eq(inner_uri, wsdl_soap12())) {
                            action = attr(&d, inner, "soapAction")
                            let op_style = attr(&d, inner, "style")
                            if op_style.len > 0usize { style = op_style }
                        }
                        inner = next_sibling_element(&d, inner)
                    }
                    var k = 0usize
                    while k < used {
                        if str.eq(operations[k].name, op_name) {
                            operations[k].action = action
                            operations[k].style = style
                        }
                        k += 1usize
                    }
                }
                child = next_sibling_element(&d, child)
            }
        }
        if is_named(&d, at, ns, "service") {
            var port = first_child_element(&d, at)
            while port != 4294967295u32 {
                var inner = first_child_element(&d, port)
                while inner != 4294967295u32 {
                    let (inner_uri, inner_local, inner_error) = expand(&d, inner)
                    if inner_error == ok && str.eq(inner_local, "address") && (str.eq(inner_uri, wsdl_soap11()) || str.eq(inner_uri, wsdl_soap12())) && out.location.len == 0usize {
                        out.location = attr(&d, inner, "location")
                    }
                    inner = next_sibling_element(&d, inner)
                }
                port = next_sibling_element(&d, port)
            }
        }
        at = next_sibling_element(&d, at)
    }
    out.operations = operations[..used]
    ret (out, ok)
}

// ---- XSD built-in types ----

// The Neper type that carries an XSD built-in simple type, by its local name (`int`, `string`, ...): the
// fixed-width integers map to the matching width, `integer` and its unbounded relatives to i64 (values
// beyond that need the lexical form), `decimal` and the date/time types to their exact text (`str`),
// `base64Binary` and `hexBinary` to bytes. Answers false for a name that is not a built-in.
fn xsd_neper_type(local: str) -> (str, bool) {
    if str.eq(local, "byte") { ret ("i8", true) }
    if str.eq(local, "short") { ret ("i16", true) }
    if str.eq(local, "int") { ret ("i32", true) }
    if str.eq(local, "long") || str.eq(local, "integer") || str.eq(local, "nonNegativeInteger") || str.eq(local, "positiveInteger") || str.eq(local, "negativeInteger") || str.eq(local, "nonPositiveInteger") { ret ("i64", true) }
    if str.eq(local, "unsignedByte") { ret ("u8", true) }
    if str.eq(local, "unsignedShort") { ret ("u16", true) }
    if str.eq(local, "unsignedInt") { ret ("u32", true) }
    if str.eq(local, "unsignedLong") { ret ("u64", true) }
    if str.eq(local, "boolean") { ret ("bool", true) }
    if str.eq(local, "float") { ret ("f32", true) }
    if str.eq(local, "double") { ret ("f64", true) }
    if str.eq(local, "base64Binary") || str.eq(local, "hexBinary") { ret ("[]u8", true) }
    if str.eq(local, "string") || str.eq(local, "normalizedString") || str.eq(local, "token") || str.eq(local, "anyURI") || str.eq(local, "QName") || str.eq(local, "NCName") || str.eq(local, "ID") || str.eq(local, "IDREF") || str.eq(local, "language") || str.eq(local, "Name") || str.eq(local, "NMTOKEN") { ret ("str", true) }
    if str.eq(local, "decimal") || str.eq(local, "dateTime") || str.eq(local, "date") || str.eq(local, "time") || str.eq(local, "duration") || str.eq(local, "gYear") || str.eq(local, "gYearMonth") || str.eq(local, "gMonth") || str.eq(local, "gMonthDay") || str.eq(local, "gDay") { ret ("str", true) }
    if str.eq(local, "anyType") || str.eq(local, "anySimpleType") { ret ("str", true) }
    ret ("", false)
}

// An xsd:boolean lexical value: "true" and "1", "false" and "0", after trimming; anything else is `Invalid`.
fn parse_xsd_boolean(text: str) -> (bool, err) {
    let t = str.trim(text)
    if str.eq(t, "true") || str.eq(t, "1") { ret (true, ok) }
    if str.eq(t, "false") || str.eq(t, "0") { ret (false, ok) }
    ret (false, Invalid)
}
