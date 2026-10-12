// Common Alerting Protocol 1.2 (OASIS CAP, the format weather services and civil authorities publish alerts in):
// `parse` reads an `<alert>` document over e.fmt.xml and gives the message (identifier, sender, sent time, status,
// message type, scope) and each `<info>` block (language, category, event, urgency, severity, certainty, effective,
// onset, expires, sender name, headline, description, instruction, web) with its first `<area>`'s description and the
// counts of areas. Element names are matched without a namespace prefix and the text of an element is the
// concatenation of its character data, trimmed. Not here: polygons, geocodes, resources, signatures and updates
// (a message that references another is returned as written); a document whose root is not `alert` is `NotCap`.
//
// Memory: everything lives in the arena passed in.
use e.mem
use e.str
use e.fmt.xml as xml

error NotCap
error TooMany

const MAX_INFOS: usize = 16usize

type Info = struct {
    language: str,
    category: str,
    event: str,
    urgency: str,
    severity: str,
    certainty: str,
    effective: str,
    onset: str,
    expires: str,
    sender_name: str,
    headline: str,
    description: str,
    instruction: str,
    web: str,
    area_description: str,
    areas: usize,
}

type Alert = struct { identifier: str, sender: str, sent: str, status: str, message_type: str, scope: str, infos: []Info }

fn local(name: str) -> str {
    var i = name.len
    while i > 0usize {
        if name[i - 1usize] == 58u8 { ret name[i..name.len] }
        i -= 1usize
    }
    ret name
}

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 }

fn trim(s: str) -> str {
    var a = 0usize
    var b = s.len
    while a < b && is_space(s[a]) { a += 1usize }
    while b > a && is_space(s[b - 1usize]) { b -= 1usize }
    ret s[a..b]
}

// The text directly under element `at`: its character-data children in order, trimmed. One text node is returned as
// it is; several are joined in the arena.
fn text_under(a: *mem.Arena, nodes: []const xml.Node, at: usize) -> (str, err) {
    var count = 0usize
    var size = 0usize
    var last = 0usize
    var child = usize(nodes[at].first_child)
    while child < nodes.len && child != 0usize {
        if nodes[child].kind == .Text {
            count += 1usize
            size += nodes[child].value.len
            last = child
        }
        child = usize(nodes[child].next_sibling)
    }
    if count == 0usize { ret ("", ok) }
    if count == 1usize { ret (trim(nodes[last].value), ok) }
    let (buffer, buffer_error) = mem.alloc[u8](a, size + 1usize)
    if buffer_error != ok { ret ("", buffer_error) }
    var n = 0usize
    child = usize(nodes[at].first_child)
    while child < nodes.len && child != 0usize {
        if nodes[child].kind == .Text {
            var i = 0usize
            while i < nodes[child].value.len {
                buffer[n] = nodes[child].value[i]
                n += 1usize
                i += 1usize
            }
        }
        child = usize(nodes[child].next_sibling)
    }
    ret (trim(buffer[0usize..n]), ok)
}

fn set_field(info: *Info, name: str, value: str) {
    if str.eq(name, "language") { info.language = value }
    if str.eq(name, "category") && info.category.len == 0usize { info.category = value }
    if str.eq(name, "event") { info.event = value }
    if str.eq(name, "urgency") { info.urgency = value }
    if str.eq(name, "severity") { info.severity = value }
    if str.eq(name, "certainty") { info.certainty = value }
    if str.eq(name, "effective") { info.effective = value }
    if str.eq(name, "onset") { info.onset = value }
    if str.eq(name, "expires") { info.expires = value }
    if str.eq(name, "senderName") { info.sender_name = value }
    if str.eq(name, "headline") { info.headline = value }
    if str.eq(name, "description") { info.description = value }
    if str.eq(name, "instruction") { info.instruction = value }
    if str.eq(name, "web") { info.web = value }
}

// Read a CAP alert from `source`.
fn parse(a: *mem.Arena, source: []const u8) -> (Alert, err) {
    var alert: Alert = zero
    let (doc, parse_error) = xml.parse(a, source)
    if parse_error != ok { ret (alert, parse_error) }
    let nodes = doc.nodes
    var root = usize(doc.root)
    // The root may be the document node; the alert is its element child.
    if root < nodes.len && nodes[root].kind != .Element {
        var c = usize(nodes[root].first_child)
        var found = false
        while c < nodes.len && c != 0usize && !found {
            if nodes[c].kind == .Element {
                root = c
                found = true
            } else {
                c = usize(nodes[c].next_sibling)
            }
        }
    }
    if root >= nodes.len || nodes[root].kind != .Element || !str.eq(local(nodes[root].name), "alert") { ret (alert, NotCap) }
    var infos: [16]Info = zero
    var info_count = 0usize
    var child = usize(nodes[root].first_child)
    while child < nodes.len && child != 0usize {
        if nodes[child].kind == .Element {
            let name = local(nodes[child].name)
            if str.eq(name, "info") {
                if info_count >= MAX_INFOS { ret (alert, TooMany) }
                var field = usize(nodes[child].first_child)
                while field < nodes.len && field != 0usize {
                    if nodes[field].kind == .Element {
                        let field_name = local(nodes[field].name)
                        if str.eq(field_name, "area") {
                            infos[info_count].areas += 1usize
                            if infos[info_count].areas == 1usize {
                                var part = usize(nodes[field].first_child)
                                while part < nodes.len && part != 0usize {
                                    if nodes[part].kind == .Element && str.eq(local(nodes[part].name), "areaDesc") {
                                        let (desc, desc_error) = text_under(a, nodes, part)
                                        if desc_error != ok { ret (alert, desc_error) }
                                        infos[info_count].area_description = desc
                                    }
                                    part = usize(nodes[part].next_sibling)
                                }
                            }
                        } else {
                            let (value, value_error) = text_under(a, nodes, field)
                            if value_error != ok { ret (alert, value_error) }
                            set_field(&infos[info_count], field_name, value)
                        }
                    }
                    field = usize(nodes[field].next_sibling)
                }
                info_count += 1usize
            } else {
                let (value, value_error) = text_under(a, nodes, child)
                if value_error != ok { ret (alert, value_error) }
                if str.eq(name, "identifier") { alert.identifier = value }
                if str.eq(name, "sender") { alert.sender = value }
                if str.eq(name, "sent") { alert.sent = value }
                if str.eq(name, "status") { alert.status = value }
                if str.eq(name, "msgType") { alert.message_type = value }
                if str.eq(name, "scope") { alert.scope = value }
            }
        }
        child = usize(nodes[child].next_sibling)
    }
    let (out, out_error) = mem.alloc[Info](a, info_count + 1usize)
    if out_error != ok { ret (alert, out_error) }
    var i = 0usize
    while i < info_count {
        out[i] = infos[i]
        i += 1usize
    }
    alert.infos = out[0usize..info_count]
    ret (alert, ok)
}
