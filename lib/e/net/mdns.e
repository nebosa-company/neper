// Multicast DNS and DNS-SD (RFC 6762, RFC 6763) over the packet codec of e.net.dns, sans network: the caller moves
// datagrams. `answer` is the responder, turning a query packet into the response a host that offers `Service`s
// should send (PTR for a service type, SRV and TXT for an instance, A and AAAA for a host, the service type
// enumeration `_services._dns-sd._udp`, related records in the additional section, known-answer suppression for
// PTR, the QU bit, and the legacy-unicast form of RFC 6762 section 6.7 that echoes the id and the question and
// caps TTLs at 10 seconds). `announce` builds the unsolicited response for startup and, with `goodbye`, the TTL 0
// form for shutdown. `query` builds a question, optionally with known answers, and `learn` reads any response
// into a `Cache` that honours TTLs, TTL-0 goodbyes and the cache-flush bit; `discover` lists the instances of a
// service type with host, port, TXT strings and addresses once the cache holds them. `serve_once` is the
// responder over a UDP socket from e.net: it answers one datagram, to the sender when the question asked for a
// unicast reply, the sender used a port other than 5353, or the caller has no multicast endpoint. Names are kept in
// wire form, so an instance label may hold spaces, UTF-8 and dots without escaping.
// Left out: joining the multicast group (e.net has no group membership call yet, so the socket the caller binds
// must already receive the datagrams), probing and conflict resolution, NSEC negative answers, outgoing name
// compression (incoming compression is read), and known-answer suppression for records other than PTR.

use e.mem
use e.net
use e.net.dns as dns
use e.str

type Address = struct { v6: bool, bytes: [16]u8 }
type Service = struct {
    instance: str, service: str, domain: str, host: str, port: u16, priority: u16, weight: u16,
    txt: []const str, addresses: []const Address, ttl_host: u32, ttl_other: u32,
}
type Reply = struct { len: usize, unicast: bool }
type Known = struct { target: []const u8, ttl: u32 }
type Record = struct {
    name: []const u8, kind: u16, born: u64, expires: u64, target: []const u8, port: u16, priority: u16,
    weight: u16, data: []const u8, address: Address,
}
type Cache = struct { a: *mem.Arena, records: []Record, count: usize }
type Found = struct {
    instance_wire: []const u8, instance: str, host_wire: []const u8, host: str, port: u16, priority: u16,
    weight: u16, txt: []const str, addresses: []const Address, resolved: bool,
}
type Names = struct { service_type: []const u8, instance: []const u8, host: []const u8, domain_enum: []const u8 }
type Out = struct { buf: []u8, at: usize, count: u16 }

error Invalid
error Malformed
error TooSmall
error TooLarge

const PORT: u16 = 5353u16
const FLAG_RESPONSE: u16 = 33792u16
const CACHE_FLUSH: u16 = 32768u16
const KIND_PTR: usize = 0usize
const KIND_SRV: usize = 1usize
const KIND_TXT: usize = 2usize
const KIND_A: usize = 3usize
const KIND_AAAA: usize = 4usize
const KIND_ENUM: usize = 5usize
const KINDS: usize = 6usize
const CACHE_LIMIT: usize = 1024usize

// The IPv4 group 224.0.0.251 and port 5353 as an endpoint.
fn group_v4() -> net.Endpoint {
    var ip: net.Ip4 = zero
    ip.bytes[0] = 224u8
    ip.bytes[3] = 251u8
    ret net.Endpoint { address: net.Address{ Ip4: ip }, port: PORT }
}

// ---- wire names -----------------------------------------------------------------------------------------

// `label` as one label, then the dotted `rest`, as an uncompressed wire name at `dst[at..]`.
fn wire_name(dst: []u8, at: usize, label: str, rest: str, rest2: str) -> (usize, err) {
    var out = at
    if label.len > 0usize {
        if label.len > 63usize || out + 1usize + label.len > dst.len { ret (at, TooSmall) }
        dst[out] = u8(label.len)
        mem.copy[u8](dst[out + 1usize..out + 1usize + label.len], label)
        out += 1usize + label.len
    }
    if rest.len > 0usize {
        // the dotted parts are written label by label so the trailing root is added once, after the last part
        var start = 0usize
        while start < rest.len {
            var stop = start
            while stop < rest.len && rest[stop] != 46u8 { stop += 1usize }
            if stop == start || stop - start > 63usize || out + 1usize + (stop - start) > dst.len { ret (at, Invalid) }
            dst[out] = u8(stop - start)
            mem.copy[u8](dst[out + 1usize..out + 1usize + (stop - start)], rest[start..stop])
            out += 1usize + (stop - start)
            start = stop + 1usize
        }
    }
    if rest2.len > 0usize {
        var start = 0usize
        while start < rest2.len {
            var stop = start
            while stop < rest2.len && rest2[stop] != 46u8 { stop += 1usize }
            if stop == start || stop - start > 63usize || out + 1usize + (stop - start) > dst.len { ret (at, Invalid) }
            dst[out] = u8(stop - start)
            mem.copy[u8](dst[out + 1usize..out + 1usize + (stop - start)], rest2[start..stop])
            out += 1usize + (stop - start)
            start = stop + 1usize
        }
    }
    if out + 1usize > dst.len { ret (at, TooSmall) }
    dst[out] = 0u8
    ret (out + 1usize, ok)
}

// mem.alloc does not clear what it hands out.
fn clear_flags(flags: []bool) {
    var i = 0usize
    while i < flags.len {
        flags[i] = false
        i += 1usize
    }
}

fn arena_name(a: *mem.Arena, label: str, rest: str, rest2: str) -> ([]const u8, err) {
    let (buf, alloc_error) = mem.alloc[u8](a, 300usize)
    if alloc_error != ok { ret ("", alloc_error) }
    let (n, name_error) = wire_name(buf, 0usize, label, rest, rest2)
    if name_error != ok { ret ("", name_error) }
    ret (buf[..n], ok)
}

fn names_of(a: *mem.Arena, s: Service) -> (Names, err) {
    var none = Names { service_type: "", instance: "", host: "", domain_enum: "" }
    if s.instance.len == 0usize || s.service.len == 0usize || s.domain.len == 0usize || s.host.len == 0usize { ret (none, Invalid) }
    let (service_type, type_error) = arena_name(a, "", s.service, s.domain)
    if type_error != ok { ret (none, type_error) }
    let (instance, instance_error) = arena_name(a, s.instance, s.service, s.domain)
    if instance_error != ok { ret (none, instance_error) }
    let (host, host_error) = arena_name(a, "", s.host, "")
    if host_error != ok { ret (none, host_error) }
    let (enumeration, enum_error) = arena_name(a, "", "_services._dns-sd._udp", s.domain)
    if enum_error != ok { ret (none, enum_error) }
    ret (Names { service_type: service_type, instance: instance, host: host, domain_enum: enumeration }, ok)
}

// ---- building packets -----------------------------------------------------------------------------------

fn out_bytes(o: *Out, bytes: []const u8) -> err {
    if o.at + bytes.len > o.buf.len { ret TooSmall }
    mem.copy[u8](o.buf[o.at..], bytes)
    o.at += bytes.len
    ret ok
}

fn out_u16(o: *Out, v: u16) -> err {
    if o.at + 2usize > o.buf.len { ret TooSmall }
    dns.store16(o.buf, o.at, v)
    o.at += 2usize
    ret ok
}

fn out_u32(o: *Out, v: u32) -> err {
    if o.at + 4usize > o.buf.len { ret TooSmall }
    dns.store32(o.buf, o.at, v)
    o.at += 4usize
    ret ok
}

// One resource record: name, type, class, ttl and the rdata length followed by `rdata`.
fn out_record(o: *Out, name: []const u8, kind: u16, class: u16, ttl: u32, rdata: []const u8) -> err {
    try out_bytes(o, name)
    try out_u16(o, kind)
    try out_u16(o, class)
    try out_u32(o, ttl)
    try out_u16(o, u16(rdata.len))
    try out_bytes(o, rdata)
    o.count += 1u16
    ret ok
}

fn txt_rdata(a: *mem.Arena, strings: []const str) -> ([]const u8, err) {
    var total = 1usize
    var i = 0usize
    while i < strings.len {
        if strings[i].len > 255usize { ret ("", Invalid) }
        total += 1usize + strings[i].len
        i += 1usize
    }
    let (buf, alloc_error) = mem.alloc[u8](a, total)
    if alloc_error != ok { ret ("", alloc_error) }
    if strings.len == 0usize {
        buf[0] = 0u8
        ret (buf[..1usize], ok)
    }
    var at = 0usize
    i = 0usize
    while i < strings.len {
        buf[at] = u8(strings[i].len)
        mem.copy[u8](buf[at + 1usize..at + 1usize + strings[i].len], strings[i])
        at += 1usize + strings[i].len
        i += 1usize
    }
    ret (buf[..at], ok)
}

fn srv_rdata(a: *mem.Arena, s: Service, host: []const u8) -> ([]const u8, err) {
    let (buf, alloc_error) = mem.alloc[u8](a, 6usize + host.len)
    if alloc_error != ok { ret ("", alloc_error) }
    dns.store16(buf, 0usize, s.priority)
    dns.store16(buf, 2usize, s.weight)
    dns.store16(buf, 4usize, s.port)
    mem.copy[u8](buf[6usize..], host)
    ret (buf[..6usize + host.len], ok)
}

fn cap(ttl: u32, legacy: bool) -> u32 {
    if legacy && ttl > 10u32 { ret 10u32 }
    ret ttl
}

// The records of one kind for service `index`, into `o`. Returns false when it was already written.
fn add_kind(a: *mem.Arena, o: *Out, services: []const Service, names: []const Names, index: usize, kind: usize, done: []bool, legacy: bool, goodbye: bool) -> err {
    let flat = index * KINDS + kind
    if done[flat] { ret ok }
    done[flat] = true
    let s = services[index]
    var other = s.ttl_other
    var host = s.ttl_host
    if goodbye {
        other = 0u32
        host = 0u32
    }
    var flush = CACHE_FLUSH
    if legacy { flush = 0u16 }
    if kind == KIND_PTR {
        ret out_record(o, names[index].service_type, dns.TYPE_PTR, dns.CLASS_IN, cap(other, legacy), names[index].instance)
    }
    if kind == KIND_ENUM {
        // one enumeration record per distinct service type
        var earlier = 0usize
        while earlier < index {
            if dns.name_equal_fold(names[earlier].service_type, names[index].service_type) { ret ok }
            earlier += 1usize
        }
        ret out_record(o, names[index].domain_enum, dns.TYPE_PTR, dns.CLASS_IN, cap(other, legacy), names[index].service_type)
    }
    if kind == KIND_SRV {
        let (rdata, rdata_error) = srv_rdata(a, s, names[index].host)
        if rdata_error != ok { ret rdata_error }
        ret out_record(o, names[index].instance, dns.TYPE_SRV, dns.CLASS_IN | flush, cap(host, legacy), rdata)
    }
    if kind == KIND_TXT {
        let (rdata, rdata_error) = txt_rdata(a, s.txt)
        if rdata_error != ok { ret rdata_error }
        ret out_record(o, names[index].instance, dns.TYPE_TXT, dns.CLASS_IN | flush, cap(other, legacy), rdata)
    }
    // services sharing a host share its address records: the first of them provides them
    var earlier = 0usize
    while earlier < index {
        if eq_wire(names[earlier].host, names[index].host) { ret ok }
        earlier += 1usize
    }
    var i = 0usize
    while i < s.addresses.len {
        let address = s.addresses[i]
        if kind == KIND_A && !address.v6 {
            try out_record(o, names[index].host, dns.TYPE_A, dns.CLASS_IN | flush, cap(host, legacy), address.bytes[..4usize])
        }
        if kind == KIND_AAAA && address.v6 {
            try out_record(o, names[index].host, dns.TYPE_AAAA, dns.CLASS_IN | flush, cap(host, legacy), address.bytes[0..])
        }
        i += 1usize
    }
    ret ok
}

// SRV, TXT and addresses of one instance: the related records a PTR or SRV answer carries as additionals.
fn add_related(a: *mem.Arena, o: *Out, services: []const Service, names: []const Names, index: usize, done: []bool, legacy: bool, goodbye: bool) -> err {
    try add_kind(a, o, services, names, index, KIND_SRV, done, legacy, goodbye)
    try add_kind(a, o, services, names, index, KIND_TXT, done, legacy, goodbye)
    try add_kind(a, o, services, names, index, KIND_A, done, legacy, goodbye)
    ret add_kind(a, o, services, names, index, KIND_AAAA, done, legacy, goodbye)
}

// The unsolicited response with every record of `services` (startup), or with TTL 0 when `goodbye`.
fn announce(a: *mem.Arena, dst: []u8, services: []const Service, goodbye: bool) -> (usize, err) {
    if dst.len < 12usize || services.len == 0usize { ret (0usize, Invalid) }
    let (names_all, names_alloc) = mem.alloc[Names](a, services.len)
    if names_alloc != ok { ret (0usize, names_alloc) }
    let (done, done_alloc) = mem.alloc[bool](a, services.len * KINDS)
    if done_alloc != ok { ret (0usize, done_alloc) }
    clear_flags(done)
    var i = 0usize
    while i < services.len {
        let (n, n_error) = names_of(a, services[i])
        if n_error != ok { ret (0usize, n_error) }
        names_all[i] = n
        i += 1usize
    }
    var o = Out { buf: dst, at: 12usize, count: 0u16 }
    i = 0usize
    while i < services.len {
        try add_kind(a, &o, services, names_all, i, KIND_ENUM, done, false, goodbye)
        try add_kind(a, &o, services, names_all, i, KIND_PTR, done, false, goodbye)
        try add_related(a, &o, services, names_all, i, done, false, goodbye)
        i += 1usize
    }
    dns.store16(dst, 0usize, 0u16)
    dns.store16(dst, 2usize, FLAG_RESPONSE)
    dns.store16(dst, 4usize, 0u16)
    dns.store16(dst, 6usize, o.count)
    dns.store16(dst, 8usize, 0u16)
    dns.store16(dst, 10usize, 0u16)
    ret (o.at, ok)
}

// A question for `name` (dotted, such as `_ipp._tcp.local`) of `qtype`, asking for a unicast reply when
// `unicast`, with the known answers `known` (PTR records of `name` already held, so the responder can stay quiet).
fn query(dst: []u8, name: str, qtype: u16, unicast: bool, known: []const Known) -> (usize, err) {
    if dst.len < 12usize { ret (0usize, TooSmall) }
    var o = Out { buf: dst, at: 12usize, count: 0u16 }
    var name_buf: [300]u8 = zero
    let (n, name_error) = wire_name(name_buf[0..], 0usize, "", name, "")
    if name_error != ok { ret (0usize, name_error) }
    try out_bytes(&o, name_buf[..n])
    try out_u16(&o, qtype)
    var class = dns.CLASS_IN
    if unicast { class = class | CACHE_FLUSH }
    try out_u16(&o, class)
    var i = 0usize
    while i < known.len {
        try out_record(&o, name_buf[..n], dns.TYPE_PTR, dns.CLASS_IN, known[i].ttl, known[i].target)
        i += 1usize
    }
    dns.store16(dst, 0usize, 0u16)
    dns.store16(dst, 2usize, 0u16)
    dns.store16(dst, 4usize, 1u16)
    dns.store16(dst, 6usize, o.count)
    dns.store16(dst, 8usize, 0u16)
    dns.store16(dst, 10usize, 0u16)
    ret (o.at, ok)
}

// ---- the responder --------------------------------------------------------------------------------------

fn eq_wire(a: []const u8, b: []const u8) -> bool { ret dns.name_equal_fold(a, b) }

// Whether the query's answer section lists a PTR for `name` pointing at `target` with at least half of `ttl` left.
fn known_answer(query_packet: []const u8, pos_start: usize, answers: usize, name: []const u8, wanted_target: []const u8, ttl: u32) -> bool {
    var pos = pos_start
    var owner: [300]u8 = zero
    var k = 0usize
    while k < answers {
        let (r, rr_error) = dns.decode_rr(query_packet, &pos, owner[0..])
        if rr_error != ok { ret false }
        if r.kind == dns.TYPE_PTR && r.ttl >= ttl / 2u32 && eq_wire(owner[..r.name_len], name) {
            var target_buf: [300]u8 = zero
            let (t_len, t_error) = dns.rdata_name(query_packet, r, target_buf[0..])
            if t_error == ok && eq_wire(target_buf[..t_len], wanted_target) { ret true }
        }
        k += 1usize
    }
    ret false
}

// The response to `packet` (a query) for the services this host offers; `len` is 0 when nothing matches.
// `legacy` is a query from a source port other than 5353 (RFC 6762 section 6.7): the response echoes the
// query id and question, clears the cache-flush bit and caps TTLs at 10 seconds. `unicast` is set when a
// question carried the QU bit or the query was legacy.
fn answer(a: *mem.Arena, dst: []u8, services: []const Service, packet: []const u8, legacy: bool) -> (Reply, err) {
    var none = Reply { len: 0usize, unicast: false }
    let (header, header_error) = dns.decode_header(packet)
    if header_error != ok { ret (none, Malformed) }
    if dns.header_is_response(header) || (header.flags & 30720u16) != 0u16 { ret (none, ok) }
    let (names, names_alloc) = mem.alloc[Names](a, services.len + 1usize)
    if names_alloc != ok { ret (none, names_alloc) }
    let (done, done_alloc) = mem.alloc[bool](a, services.len * KINDS + 1usize)
    if done_alloc != ok { ret (none, done_alloc) }
    clear_flags(done)
    var i = 0usize
    while i < services.len {
        let (n, n_error) = names_of(a, services[i])
        if n_error != ok { ret (none, n_error) }
        names[i] = n
        i += 1usize
    }
    let (answer_buf, answer_alloc) = mem.alloc[u8](a, dst.len)
    if answer_alloc != ok { ret (none, answer_alloc) }
    let (extra_buf, extra_alloc) = mem.alloc[u8](a, dst.len)
    if extra_alloc != ok { ret (none, extra_alloc) }
    var answers = Out { buf: answer_buf, at: 0usize, count: 0u16 }
    var extra = Out { buf: extra_buf, at: 0usize, count: 0u16 }
    // the end of the question section, where the known answers begin
    var after_questions = 12usize
    var q = 0usize
    while q < usize(header.qdcount) {
        let skip_error = dns.skip_question(packet, &after_questions)
        if skip_error != ok { ret (none, Malformed) }
        q += 1usize
    }
    var pos = 12usize
    var qname: [300]u8 = zero
    var unicast = legacy
    q = 0usize
    while q < usize(header.qdcount) {
        let (name_len, qtype, qclass, question_error) = dns.decode_question(packet, &pos, qname[0..])
        if question_error != ok { ret (none, Malformed) }
        q += 1usize
        let class = qclass & 32767u16
        if class != dns.CLASS_IN && class != 255u16 { continue }
        let qn = qname[..name_len]
        let any = qtype == 255u16
        var matched = false
        i = 0usize
        while i < services.len {
            if (qtype == dns.TYPE_PTR || any) && eq_wire(qn, names[i].domain_enum) {
                try add_kind(a, &answers, services, names, i, KIND_ENUM, done, legacy, false)
                matched = true
            }
            if (qtype == dns.TYPE_PTR || any) && eq_wire(qn, names[i].service_type) {
                if !known_answer(packet, after_questions, usize(header.ancount), names[i].service_type, names[i].instance, services[i].ttl_other) {
                    try add_kind(a, &answers, services, names, i, KIND_PTR, done, legacy, false)
                    try add_related(a, &extra, services, names, i, done, legacy, false)
                }
                matched = true
            }
            if eq_wire(qn, names[i].instance) {
                if qtype == dns.TYPE_SRV || any {
                    try add_kind(a, &answers, services, names, i, KIND_SRV, done, legacy, false)
                    try add_kind(a, &extra, services, names, i, KIND_A, done, legacy, false)
                    try add_kind(a, &extra, services, names, i, KIND_AAAA, done, legacy, false)
                    matched = true
                }
                if qtype == dns.TYPE_TXT || any {
                    try add_kind(a, &answers, services, names, i, KIND_TXT, done, legacy, false)
                    matched = true
                }
            }
            if eq_wire(qn, names[i].host) {
                if qtype == dns.TYPE_A || any {
                    try add_kind(a, &answers, services, names, i, KIND_A, done, legacy, false)
                    matched = true
                }
                if qtype == dns.TYPE_AAAA || any {
                    try add_kind(a, &answers, services, names, i, KIND_AAAA, done, legacy, false)
                    matched = true
                }
            }
            i += 1usize
        }
        if matched && (qclass & CACHE_FLUSH) != 0u16 { unicast = true }
    }
    if answers.count == 0u16 { ret (none, ok) }
    var o = Out { buf: dst, at: 12usize, count: 0u16 }
    var echoed = 0u16
    if legacy {
        try out_bytes(&o, packet[12usize..after_questions])
        echoed = header.qdcount
    }
    try out_bytes(&o, answers.buf[..answers.at])
    try out_bytes(&o, extra.buf[..extra.at])
    var id = 0u16
    if legacy { id = header.id }
    dns.store16(dst, 0usize, id)
    dns.store16(dst, 2usize, FLAG_RESPONSE)
    dns.store16(dst, 4usize, echoed)
    dns.store16(dst, 6usize, answers.count)
    dns.store16(dst, 8usize, 0u16)
    dns.store16(dst, 10usize, extra.count)
    ret (Reply { len: o.at, unicast: unicast }, ok)
}

// Receive one datagram on `socket` and send the response it calls for. The response goes to the sender when
// the question asked for a unicast reply or the sender is not using port 5353 (legacy unicast), and
// otherwise to `multicast` when the caller has one.
fn serve_once(a: *mem.Arena, socket: net.Socket, services: []const Service, multicast: net.Endpoint, has_multicast: bool) -> err {
    var inbound: [1500]u8 = zero
    var outbound: [9000]u8 = zero
    let (n, from, receive_error) = net.receive_from(socket, inbound[0..])
    if receive_error != ok { ret receive_error }
    let mark = mem.mark(a)
    let (reply, answer_error) = answer(a, outbound[0..], services, inbound[..n], from.port != PORT)
    if answer_error != ok {
        mem.reset(a, mark)
        ret answer_error
    }
    if reply.len == 0usize {
        mem.reset(a, mark)
        ret ok
    }
    var destination = from
    if !reply.unicast && from.port == PORT && has_multicast { destination = multicast }
    let (_, send_error) = net.send_to(socket, destination, outbound[..reply.len])
    mem.reset(a, mark)
    ret send_error
}

// ---- the cache ------------------------------------------------------------------------------------------

fn cache_new(a: *mem.Arena) -> (Cache, err) {
    let (records, alloc_error) = mem.alloc[Record](a, CACHE_LIMIT)
    if alloc_error != ok { ret (Cache { a: a, records: zero, count: 0usize }, alloc_error) }
    ret (Cache { a: a, records: records, count: 0usize }, ok)
}

fn same_address(x: Address, y: Address) -> bool {
    if x.v6 != y.v6 { ret false }
    var n = 4usize
    if x.v6 { n = 16usize }
    var i = 0usize
    while i < n {
        if x.bytes[i] != y.bytes[i] { ret false }
        i += 1usize
    }
    ret true
}

fn same_bytes(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn same_content(x: Record, y: Record) -> bool {
    if x.kind != y.kind { ret false }
    if x.kind == dns.TYPE_PTR { ret eq_wire(x.target, y.target) }
    if x.kind == dns.TYPE_SRV { ret x.port == y.port && x.priority == y.priority && x.weight == y.weight && eq_wire(x.target, y.target) }
    if x.kind == dns.TYPE_TXT { ret same_bytes(x.data, y.data) }
    ret same_address(x.address, y.address)
}

fn copy_bytes(a: *mem.Arena, bytes: []const u8) -> ([]const u8, err) {
    let (kept, alloc_error) = mem.alloc[u8](a, bytes.len + 1usize)
    if alloc_error != ok { ret ("", alloc_error) }
    mem.copy[u8](kept, bytes)
    ret (kept[..bytes.len], ok)
}

// Fold one record into the cache: refresh an equal one, expire the rivals of a cache-flush record after a
// second, or add it. A TTL of 0 (a goodbye) leaves the record one more second.
fn store(c: *Cache, candidate: Record, flush: bool, ttl: u32, now: u64) -> err {
    var life = u64(ttl) * 1000u64
    if ttl == 0u32 { life = 1000u64 }
    var found = false
    var i = 0usize
    while i < c.count {
        let existing = c.records[i]
        if existing.kind == candidate.kind && eq_wire(existing.name, candidate.name) {
            if same_content(existing, candidate) {
                c.records[i].expires = now + life
                found = true
            } else if flush && existing.born + 1000u64 <= now && existing.expires > now + 1000u64 {
                c.records[i].expires = now + 1000u64
            }
        }
        i += 1usize
    }
    if found { ret ok }
    if c.count >= c.records.len { ret TooLarge }
    var added = candidate
    added.born = now
    added.expires = now + life
    c.records[c.count] = added
    c.count += 1usize
    ret ok
}

// Read a packet's answer, authority and additional records into the cache at time `now` (milliseconds); the
// number of records seen is answered. Questions and unsupported record types are skipped.
fn learn(c: *Cache, packet: []const u8, now: u64) -> (usize, err) {
    let (header, header_error) = dns.decode_header(packet)
    if header_error != ok { ret (0usize, Malformed) }
    if !dns.header_is_response(header) { ret (0usize, ok) }
    var pos = 12usize
    var q = 0usize
    while q < usize(header.qdcount) {
        let skip_error = dns.skip_question(packet, &pos)
        if skip_error != ok { ret (0usize, Malformed) }
        q += 1usize
    }
    let total = usize(header.ancount) + usize(header.nscount) + usize(header.arcount)
    var owner: [300]u8 = zero
    var seen = 0usize
    var k = 0usize
    while k < total {
        let (r, rr_error) = dns.decode_rr(packet, &pos, owner[0..])
        if rr_error != ok { ret (seen, Malformed) }
        k += 1usize
        if (r.class & 32767u16) != dns.CLASS_IN { continue }
        let flush = (r.class & CACHE_FLUSH) != 0u16
        var candidate = Record {
            name: "", kind: r.kind, born: 0u64, expires: 0u64, target: "", port: 0u16, priority: 0u16, weight: 0u16,
            data: "", address: Address { v6: false, bytes: zero },
        }
        var wanted = false
        var target_buf: [300]u8 = zero
        if r.kind == dns.TYPE_PTR {
            let (t_len, t_error) = dns.rdata_name(packet, r, target_buf[0..])
            if t_error != ok { continue }
            let (kept, kept_error) = copy_bytes(c.a, target_buf[..t_len])
            if kept_error != ok { ret (seen, kept_error) }
            candidate.target = kept
            wanted = true
        } else if r.kind == dns.TYPE_SRV {
            if r.rdata.len < 7usize { continue }
            candidate.priority = dns.load16(r.rdata, 0usize)
            candidate.weight = dns.load16(r.rdata, 2usize)
            candidate.port = dns.load16(r.rdata, 4usize)
            var at = r.rdata_at + 6usize
            let (t_len, t_error) = dns.decode_name(packet, &at, target_buf[0..])
            if t_error != ok { continue }
            let (kept, kept_error) = copy_bytes(c.a, target_buf[..t_len])
            if kept_error != ok { ret (seen, kept_error) }
            candidate.target = kept
            wanted = true
        } else if r.kind == dns.TYPE_TXT {
            let (kept, kept_error) = copy_bytes(c.a, r.rdata)
            if kept_error != ok { ret (seen, kept_error) }
            candidate.data = kept
            wanted = true
        } else if r.kind == dns.TYPE_A {
            if r.rdata.len != 4usize { continue }
            mem.copy[u8](candidate.address.bytes[0..], r.rdata)
            wanted = true
        } else if r.kind == dns.TYPE_AAAA {
            if r.rdata.len != 16usize { continue }
            candidate.address.v6 = true
            mem.copy[u8](candidate.address.bytes[0..], r.rdata)
            wanted = true
        }
        if !wanted { continue }
        let (name_kept, name_error) = copy_bytes(c.a, owner[..r.name_len])
        if name_error != ok { ret (seen, name_error) }
        candidate.name = name_kept
        seen += 1usize
        let store_error = store(c, candidate, flush, r.ttl, now)
        if store_error != ok { ret (seen, store_error) }
    }
    ret (seen, ok)
}

fn text_of(a: *mem.Arena, wire: []const u8) -> (str, err) {
    var buf: [300]u8 = zero
    let (n, n_error) = dns.name_text(wire, buf[0..])
    if n_error != ok { ret ("", n_error) }
    let (kept, kept_error) = copy_bytes(a, buf[..n])
    if kept_error != ok { ret ("", kept_error) }
    ret (kept, ok)
}

// The live instances of `service` (such as `_ipp._tcp`) in `domain` (such as `local`): the PTR records, with
// the SRV, TXT and address records that resolve them. `resolved` is false until the SRV record is known.
fn discover(c: *Cache, a: *mem.Arena, service: str, domain: str, now: u64) -> ([]const Found, err) {
    let (type_wire, type_error) = arena_name(a, "", service, domain)
    if type_error != ok { ret (zero, type_error) }
    let (out, out_alloc) = mem.alloc[Found](a, c.count + 1usize)
    if out_alloc != ok { ret (zero, out_alloc) }
    var count = 0usize
    var i = 0usize
    while i < c.count {
        let ptr = c.records[i]
        if ptr.kind == dns.TYPE_PTR && ptr.expires > now && eq_wire(ptr.name, type_wire) {
            var duplicate = false
            var d = 0usize
            while d < count {
                if eq_wire(out[d].instance_wire, ptr.target) { duplicate = true }
                d += 1usize
            }
            if !duplicate {
                var found = Found {
                    instance_wire: ptr.target, instance: "", host_wire: "", host: "", port: 0u16, priority: 0u16, weight: 0u16,
                    txt: zero, addresses: zero, resolved: false,
                }
                let label = usize(ptr.target[0])
                let (label_text, label_error) = copy_bytes(a, ptr.target[1usize..1usize + label])
                if label_error != ok { ret (zero, label_error) }
                found.instance = label_text
                var j = 0usize
                while j < c.count {
                    let r = c.records[j]
                    if r.kind == dns.TYPE_SRV && r.expires > now && !found.resolved && eq_wire(r.name, ptr.target) {
                        found.resolved = true
                        found.host_wire = r.target
                        found.port = r.port
                        found.priority = r.priority
                        found.weight = r.weight
                        let (host_text, host_error) = text_of(a, r.target)
                        if host_error != ok { ret (zero, host_error) }
                        found.host = host_text
                    }
                    j += 1usize
                }
                // TXT strings and addresses
                var strings: []str = zero
                var string_count = 0usize
                var addresses: []Address = zero
                var address_count = 0usize
                j = 0usize
                while j < c.count {
                    let r = c.records[j]
                    if r.kind == dns.TYPE_TXT && r.expires > now && eq_wire(r.name, ptr.target) && string_count == 0usize {
                        let (list, list_alloc) = mem.alloc[str](a, r.data.len + 1usize)
                        if list_alloc != ok { ret (zero, list_alloc) }
                        var at = 0usize
                        while at < r.data.len {
                            let length = usize(r.data[at])
                            if at + 1usize + length > r.data.len { break }
                            if length > 0usize {
                                list[string_count] = r.data[at + 1usize..at + 1usize + length]
                                string_count += 1usize
                            }
                            at += 1usize + length
                        }
                        strings = list
                    }
                    j += 1usize
                }
                if found.resolved {
                    let (list, list_alloc) = mem.alloc[Address](a, c.count + 1usize)
                    if list_alloc != ok { ret (zero, list_alloc) }
                    addresses = list
                    j = 0usize
                    while j < c.count {
                        let r = c.records[j]
                        if (r.kind == dns.TYPE_A || r.kind == dns.TYPE_AAAA) && r.expires > now && eq_wire(r.name, found.host_wire) {
                            addresses[address_count] = r.address
                            address_count += 1usize
                        }
                        j += 1usize
                    }
                }
                if string_count > 0usize { found.txt = strings[..string_count] }
                if address_count > 0usize { found.addresses = addresses[..address_count] }
                out[count] = found
                count += 1usize
            }
        }
        i += 1usize
    }
    ret (out[..count], ok)
}
