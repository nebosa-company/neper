// An `e.db` driver for Microsoft SQL Server that speaks TDS itself: TDS 7.4 inside TLS 1.3, the
// way TDS 8.0's strict encryption has it. The TLS handshake (ALPN `tds/8.0`) comes before the
// first TDS byte, so the login, like everything after it, never crosses the wire in the clear.
// `open` takes an `Options` and answers a `db.Connection` whose table is this module's;
// `detail` is the only other call a program makes here. Written from MS-TDS and celvyx's Dart
// client (D1643).
//
// Trust: the server's certificate must chain to `trust_roots` (DER certificates, as
// `e.net.tls` takes them) and name `host`; nothing skips the check. A failed handshake is
// `e.net.tls`'s error (`tls.InvalidCertificate`, ...); a login SQL Server refuses is
// `CannotConnect`.
//
// Memory: the arena handed to `open` is retained and borrowed for the connection's life. The
// connection's own buffers, about 130 KB, are allocated there once, by `open`, and never grow:
// a request of any size is written a packet at a time, and a reply is read a packet at a time.
// So a caller may mark and reset the arena around any call. Statement, reader and transaction
// contexts, column names and a reader's row buffers come from the arena at the call. A
// reader's values are copied into a buffer of the reader's that is valid until its next row
// -- for `db.reader_next_borrowed` too, since the next packet overwrites the last.
//
// Parameters: `?`, positional, rewritten to `@p1`...`@pN` and sent through `sp_executesql`; a
// `?` inside a string, a quoted identifier or a comment is not one. Text with no parameters
// goes as a plain SQL batch. A value travels as `bit`, `bigint` (a `U64` past `i64` as
// `decimal(38,0)`), `float`, `nvarchar(4000)` or `nvarchar(max)`, `varbinary(8000)` or
// `varbinary(max)`, or `datetime2(7)` in UTC, and SQL Server converts each to its column's
// type. A NULL is written into the text as the literal `NULL`, which fits any column.
//
// Values come back by column type: the integers are `I64`, `bit` is `Bool`, `real` and `float`
// are `F64`, the binary types are `Bytes`; `date`, `datetime`, `smalldatetime`, `datetime2` and
// `datetimeoffset` are `Time` in UTC; `decimal`, `numeric`, `money`, `time`,
// `uniqueidentifier`, `xml` and the character types are `Text`, a `varchar` decoded as UTF-8
// under a UTF-8 collation and as Windows-1252 under a Latin-1 one. A `sql_variant` value is
// read as its base type.
//
// Statements: `prepare` keeps the text and counts its placeholders; SQL Server compiles it at
// the first execution, which is where a statement that cannot run fails. A query streams its
// first result set as the packets arrive. While a reader is open the connection is busy:
// another call on it answers `db.Busy`. Closing a reader early reads and discards what is left
// of the reply. Transactions are `BEGIN TRANSACTION` batches; one SQL Server ends by itself (a
// deadlock victim, `XACT_ABORT`) answers `Aborted` until it is committed or rolled back.
use e.mem
use e.os
use e.io
use e.time
use e.net
use e.net.tls
use e.db
use e.text.utf8
use e.bytes as octets

type Options = struct { host: str, port: u16, user: str, password: str, database: str, trust_roots: []const u8 }
type Detail = struct { number: i32, state: u8, severity: u8, message: str }
error CannotConnect
error Failed
error Aborted
error Protocol

// One column's TYPE_INFO: the type, its length (65535 for a `(max)` type), precision and
// scale, whether its values are PLP-chunked, and the collation's five bytes, little-endian.
type Col = struct { id: u8, size: u32, precision: u8, scale: u8, plp: bool, collation: u64 }
// Every buffer a connection keeps is allocated once, by `open`: the packet being written
// (`body`, `used` bytes of it filled), the packet being read (`pkt`, from `at` to `stop`), a
// token buffer for what crosses from one packet into the next, the error text and the
// transaction descriptor.
type Conn = struct { socket: net.Socket, stream: tls.Stream, source: io.Reader, sink: io.Writer, arena: *mem.Arena, driver: *const db.Driver, packet_size: usize, body: []u8, used: usize, kind: u8, packet_id: usize, pkt: []u8, at: usize, stop: usize, eom: bool, in_reply: bool, broken: bool, token: []u8, transaction: []u8, collation: u64, in_transaction: bool, server_transaction: bool, active: *Reader, login_ack: bool, failed: bool, note: str, number: i32, state: u8, severity: u8, message: []u8, message_len: usize }
type Stmt = struct { conn: *Conn, sql: str, placeholders: usize, closed: bool }
// `long` holds a PLP or `text` value too long for the token buffer.
type Reader = struct { conn: *Conn, statement: *Stmt, done: bool, closed: bool, types: []Col, columns: []db.Column, bitmap: []u8, buffer: []u8, used: usize, long: []u8 }
type Tx = struct { conn: *Conn }

// Asked for at login; the server may answer another size up to the TDS limit.
const PACKET_SIZE: usize = 16384usize
const PACKET_CAP: usize = 32768usize
// A token's length field is two bytes.
const TOKEN_CAP: usize = 65536usize
// 0x74000004, TDS 7.4.
const TDS_VERSION: u64 = 1946157060u64

const SQL_BATCH: u8 = 1u8
const RPC: u8 = 3u8
const REPLY: u8 = 4u8
const LOGIN7: u8 = 16u8
const PRELOGIN: u8 = 18u8
// sp_executesql's well-known procedure id.
const SP_EXECUTESQL: u64 = 10u64

const COLMETADATA: u8 = 129u8
const ROW: u8 = 209u8
const NBCROW: u8 = 210u8
const DONE: u8 = 253u8
const DONEPROC: u8 = 254u8
const DONEINPROC: u8 = 255u8
const ERROR_TOKEN: u8 = 170u8
const INFO: u8 = 171u8
const LOGINACK: u8 = 173u8
const ENVCHANGE: u8 = 227u8
const RETURNSTATUS: u8 = 121u8
const ORDER: u8 = 169u8
const TABNAME: u8 = 164u8
const COLINFO: u8 = 165u8
const SESSIONSTATE: u8 = 228u8
const FEATUREEXTACK: u8 = 174u8

const DONE_COUNT: u64 = 16u64
const SELECT_COMMAND: u64 = 193u64
const PLP_NULL: u64 = 18446744073709551615u64
const I64_MAX: u64 = 9223372036854775807u64

// Error text is at most 2048 UTF-16 units; this keeps 1024 of them.
const MESSAGE_CAP: usize = 3072usize
const NANOS_PER_DAY: i64 = 86400000000000i64
const NANOS_PER_SECOND: i64 = 1000000000i64
// Day 0 of `date`/`datetime2` (0001-01-01) and of `datetime` (1900-01-01), from 1970-01-01.
const DAYS_TO_0001: i64 = -719162i64
const DAYS_TO_1900: i64 = -25567i64
// The day numbers whose every instant an `i64` of nanoseconds holds.
const FIRST_DAY: i64 = -106751i64
const LAST_DAY: i64 = 106750i64

// Connects, completes TLS, then PRELOGIN and LOGIN7 inside it.
fn open(a: *mem.Arena, options: Options) -> (db.Connection, err) {
    let (connection, open_error) = connect(a, options, nil)
    ret (connection, open_error)
}

// `open`, with the TLS records sealed and opened by `cipher` rather than `e.crypto.aead`'s
// portable AES-GCM, such as `x.openssl.crypto`'s from the host's OpenSSL (D1646). The handshake
// and the certificate checks are `e.net.tls`'s either way. `cipher` must outlive the connection.
fn open_with_cipher(a: *mem.Arena, options: Options, cipher: tls.Aead) -> (db.Connection, err) {
    let (connection, open_error) = connect(a, options, &cipher)
    ret (connection, open_error)
}

fn connect(a: *mem.Arena, options: Options, cipher: *const tls.Aead) -> (db.Connection, err) {
    var connection: db.Connection = zero
    if options.trust_roots.len == 0usize { ret (connection, CannotConnect) }
    let (v4, v4_error) = net.resolve(a, options.host, options.port, .Ip4)
    var endpoints = v4
    if v4_error != ok || v4.len == 0usize {
        let (v6, v6_error) = net.resolve(a, options.host, options.port, .Ip6)
        if v6_error != ok || v6.len == 0usize { ret (connection, CannotConnect) }
        endpoints = v6
    }
    let (opened, connect_error) = net.tcp_connect(endpoints[0usize])
    if connect_error != ok { ret (connection, CannotConnect) }
    let (conns, conn_error) = mem.alloc[Conn](a, 1usize)
    let (drivers, driver_error) = mem.alloc[db.Driver](a, 1usize)
    let (pkt, pkt_error) = mem.alloc[u8](a, PACKET_CAP)
    let (body, body_error) = mem.alloc[u8](a, PACKET_CAP)
    let (token, token_error) = mem.alloc[u8](a, TOKEN_CAP)
    let (fixed, fixed_error) = mem.alloc[u8](a, MESSAGE_CAP + 72usize)
    let (alpn, alpn_error) = mem.alloc[str](a, 1usize)
    if conn_error != ok || driver_error != ok || pkt_error != ok || body_error != ok || token_error != ok || fixed_error != ok || alpn_error != ok {
        let unused = net.close(opened)
        ret (connection, mem.Exhausted)
    }
    drivers[0usize] = db.Driver { close: d_close, prepare: d_prepare, execute: d_execute, query: d_query, begin: d_begin, statement_close: d_statement_close, statement_execute: d_statement_execute, statement_query: d_statement_query, rows_columns: d_rows_columns, rows_next: d_rows_next, rows_next_borrowed: d_rows_next, rows_close: d_rows_close, transaction_execute: d_transaction_execute, transaction_query: d_transaction_query, transaction_commit: d_transaction_commit, transaction_rollback: d_transaction_rollback }
    // Arena memory is not cleared, so every field is written.
    let c = &conns[0usize]
    c.socket = opened
    c.arena = a
    c.driver = &drivers[0usize]
    c.packet_size = 4096usize
    c.body = body
    c.used = 8usize
    c.kind = 0u8
    c.packet_id = 1usize
    c.pkt = pkt
    c.at = 0usize
    c.stop = 0usize
    c.eom = false
    c.in_reply = false
    c.broken = false
    c.token = token
    c.message = fixed[0usize..MESSAGE_CAP]
    c.transaction = fixed[MESSAGE_CAP..MESSAGE_CAP + 8usize]
    zero_bytes(c.transaction)
    c.collation = 0u64
    c.in_transaction = false
    c.server_transaction = false
    c.active = nil
    c.login_ack = false
    clear(c)
    let entropy = fixed[MESSAGE_CAP + 8usize..MESSAGE_CAP + 72usize]
    let random_error = os.random(entropy)
    let (now, now_error) = time.now()
    alpn[0usize] = "tds/8.0"
    let config = tls.ClientConfig { server_name: options.host, trust_roots: options.trust_roots, alpn: alpn, entropy: entropy, now: now }
    let (stream, client_error) = tls.client(a, net.reader(&c.socket), net.writer(&c.socket), config)
    if random_error != ok || now_error != ok || client_error != ok {
        let unused_socket = net.close(c.socket)
        ret (connection, CannotConnect)
    }
    c.stream = stream
    if cipher != nil {
        let cipher_error = tls.use_aead(&c.stream, *cipher)
        if cipher_error != ok {
            let unused_cipher = net.close(c.socket)
            ret (connection, cipher_error)
        }
    }
    let handshake_error = tls.handshake(&c.stream)
    if handshake_error != ok {
        let unused_handshake = net.close(c.socket)
        ret (connection, handshake_error)
    }
    c.source = tls.reader(&c.stream)
    c.sink = tls.writer(&c.stream)
    let login_error = login(c, options)
    if login_error != ok {
        let unused_login = hang_up(c)
        ret (connection, login_error)
    }
    clear(c)
    connection.ctx = mem.cast[*void](c)
    connection.driver = c.driver
    ret (connection, ok)
}

// Why the connection's last call failed: SQL Server's error number, state, severity and
// message, or -- when this driver refused before sending anything -- number 0 and its reason.
// After a success every field is empty. The text is copied into `a`.
fn detail(a: *mem.Arena, connection: *const db.Connection) -> (Detail, err) {
    var out: Detail = zero
    if connection.ctx == nil { ret (out, db.Closed) }
    let c = conn_of(connection.ctx)
    if c.note.len != 0usize {
        out.message = c.note
        ret (out, ok)
    }
    let (message, message_error) = keep(a, c.message[0usize..c.message_len])
    if message_error != ok { ret (out, message_error) }
    out = Detail { number: c.number, state: c.state, severity: c.severity, message: message }
    ret (out, ok)
}

fn conn_of(ctx: *void) -> *Conn { ret mem.cast[*Conn](ctx) }
fn stmt_of(ctx: *void) -> *Stmt { ret mem.cast[*Stmt](ctx) }
fn reader_of(ctx: *void) -> *Reader { ret mem.cast[*Reader](ctx) }
fn tx_of(ctx: *void) -> *Tx { ret mem.cast[*Tx](ctx) }

// The server rolls back a transaction still open when its connection ends.
fn hang_up(c: *Conn) -> err {
    let notified = tls.close(&c.stream)
    ret net.close(c.socket)
}

// --- the login

// PRELOGIN asks for no encryption of its own (NOT_SUP): TLS is already the outer layer, and ON
// would ask for a second handshake inside it. LOGIN7 carries the SQL login; SQL Server answers
// LOGINACK, or an ERROR and no LOGINACK when it refuses.
fn login(c: *Conn, options: Options) -> err {
    let prelogin: [18]u8 = [18]u8{ 0, 0, 11, 0, 6, 1, 0, 17, 0, 1, 255, 0, 0, 0, 0, 0, 0, 2 }
    begin_message(c, PRELOGIN)
    let prelogin_error = put_bytes(c, prelogin[0..])
    if prelogin_error != ok { ret prelogin_error }
    let send_prelogin_error = end_message(c)
    if send_prelogin_error != ok { ret send_prelogin_error }
    while !c.eom {
        let packet_error = next_packet(c)
        if packet_error != ok { ret packet_error }
    }
    c.in_reply = false
    let build_error = put_login(c, options)
    if build_error != ok { ret build_error }
    let send_login_error = end_message(c)
    if send_login_error != ok { ret send_login_error }
    let (ignored, reply_error) = finish(c, zero)
    if !c.login_ack { ret CannotConnect }
    ret reply_error
}

// LOGIN7 (MS-TDS 2.2.6.4): a 94-byte header whose table from byte 36 gives each variable
// field's offset and length in UTF-16 units, then the fields. It fits one packet, so its
// offsets are filled in within the packet as the fields are written.
fn put_login(c: *Conn, options: Options) -> err {
    if !utf8.validate(options.user) || !utf8.validate(options.password) || !utf8.validate(options.host) || !utf8.validate(options.database) { ret refuse(c, "the login's text is not UTF-8", CannotConnect) }
    let fields = units_of(options.user) + units_of(options.password) + units_of(options.host) + units_of(options.database) + 10usize
    if 94usize + fields * 2usize > c.packet_size - 8usize { ret refuse(c, "the login's text does not fit one packet", CannotConnect) }
    begin_message(c, LOGIN7)
    let base = c.used
    zero_bytes(c.body[base..base + 94usize])
    c.used = base + 94usize
    var i = 0usize
    while i < 9usize {
        var text = ""
        if i == 1usize { text = options.user }
        if i == 2usize { text = options.password }
        if i == 3usize || i == 6usize { text = "neper" }
        if i == 4usize { text = options.host }
        if i == 8usize { text = options.database }
        let start = c.used
        let (written, text_error) = put_utf16(c, text)
        if text_error != ok { ret text_error }
        // The password is scrambled: each byte's nibbles swapped, then XOR 0xA5.
        if i == 2usize {
            var k = start
            while k < c.used {
                let b = u32(c.body[k])
                c.body[k] = u8(((b << 4u32) | (b >> 4u32)) & 255u32) ^ 165u8
                k += 1usize
            }
        }
        set_le(c.body, base + 36usize + i * 4usize, u64(start - base), 2usize)
        set_le(c.body, base + 38usize + i * 4usize, u64(written / 2usize), 2usize)
        i += 1usize
    }
    // SSPI, AtchDBFile and ChangePassword are empty but still point at the end of the data.
    let length = c.used - base
    set_le(c.body, base + 78usize, u64(length), 2usize)
    set_le(c.body, base + 82usize, u64(length), 2usize)
    set_le(c.body, base + 86usize, u64(length), 2usize)
    set_le(c.body, base, u64(length), 4usize)
    set_le(c.body, base + 4usize, TDS_VERSION, 4usize)
    set_le(c.body, base + 8usize, u64(PACKET_SIZE), 4usize)
    // fUseDB | fDatabase | fSetLang; fLanguage | fODBC, which also turns the ANSI options on.
    c.body[base + 24usize] = 224u8
    c.body[base + 25usize] = 3u8
    set_le(c.body, base + 32usize, 1033u64, 4usize)
    ret ok
}

// --- errors

fn clear(c: *Conn) {
    c.failed = false
    c.note = ""
    c.number = 0i32
    c.state = 0u8
    c.severity = 0u8
    c.message_len = 0usize
}

fn refuse(c: *Conn, note: str, e: err) -> err {
    clear(c)
    c.note = note
    ret e
}

fn protocol(c: *Conn, note: str) -> err {
    c.broken = true
    ret refuse(c, note, Protocol)
}

fn lost(c: *Conn) -> err {
    c.broken = true
    ret refuse(c, "the connection to SQL Server was lost", Failed)
}

// The first ERROR token of a reply is the one kept: a failed statement's cause comes before
// the "statement has been terminated" that follows it.
fn record(c: *Conn, body: []const u8) {
    if c.failed || body.len < 8usize { ret }
    c.failed = true
    c.note = ""
    c.number = mem.bitcast[i32](u32(le(body[0usize..4usize])))
    c.state = body[4usize]
    c.severity = body[5usize]
    var bytes = usize(le(body[6usize..8usize])) * 2usize
    if 8usize + bytes > body.len { bytes = body.len - 8usize }
    if bytes / 2usize * 3usize > c.message.len { bytes = c.message.len / 3usize * 2usize }
    let (written, narrow_error) = narrow(body[8usize..8usize + bytes], c.message)
    c.message_len = written
}

fn outcome(c: *Conn) -> err {
    if !c.failed { ret ok }
    ret classify(c.number, c.severity)
}

// Error numbers onto `e.db`: unique, foreign-key, NOT NULL and CHECK violations are
// constraints; a deadlock victim and a lock timeout are `Busy`; syntax (severity 15), missing
// objects, conversions and arithmetic are `InvalidQuery`; everything else is `Failed`.
fn classify(number: i32, severity: u8) -> err {
    if number == 2627i32 || number == 2601i32 || number == 547i32 || number == 515i32 { ret db.Constraint }
    if number == 1205i32 || number == 1222i32 { ret db.Busy }
    if severity == 15u8 { ret db.InvalidQuery }
    if number == 102i32 || number == 105i32 || number == 137i32 || number == 156i32 || number == 201i32 || number == 207i32 || number == 208i32 || number == 2812i32 || number == 8144i32 { ret db.InvalidQuery }
    if number == 8134i32 || number == 245i32 || number == 8114i32 || number == 8115i32 || number == 241i32 || number == 242i32 || number == 2628i32 || number == 8152i32 || number == 206i32 || number == 257i32 { ret db.InvalidQuery }
    ret Failed
}

// --- bytes

fn zero_bytes(b: []u8) {
    var i = 0usize
    while i < b.len {
        b[i] = 0u8
        i += 1usize
    }
}

fn le(v: []const u8) -> u64 {
    var x = 0u64
    var i = v.len
    while i > 0usize {
        i -= 1usize
        x = (x << 8u64) | u64(v[i])
    }
    ret x
}

fn set_le(b: []u8, at: usize, value: u64, n: usize) {
    var i = 0usize
    while i < n {
        b[at + i] = u8((value >> u64(i * 8usize)) & 255u64)
        i += 1usize
    }
}

fn keep(a: *mem.Arena, bytes: []const u8) -> (str, err) {
    if bytes.len == 0usize { ret ("", ok) }
    let (copy, allocation_error) = mem.alloc[u8](a, bytes.len)
    if allocation_error != ok { ret ("", allocation_error) }
    mem.copy[u8](copy, bytes)
    ret (copy, ok)
}

// A buffer of at least `n` bytes that keeps the first `kept` of `old`.
fn grown(a: *mem.Arena, old: []u8, kept: usize, n: usize) -> ([]u8, err) {
    var size = old.len * 2usize
    if size < n { size = n }
    if size < 256usize { size = 256usize }
    let (bytes, grow_error) = mem.alloc[u8](a, size)
    if grow_error != ok { ret (old, grow_error) }
    if kept != 0usize { mem.copy[u8](bytes[0usize..kept], old[0usize..kept]) }
    ret (bytes, ok)
}

// UTF-16LE bytes as UTF-8 in `out`, which needs three bytes for every two. A leading U+FEFF is
// text, not a byte-order mark. An unpaired surrogate is `utf8.Invalid`.
fn narrow(src: []const u8, out: []u8) -> (usize, err) {
    var at = 0usize
    var used = 0usize
    while at + 1usize < src.len {
        var scalar = u32(src[at]) | (u32(src[at + 1usize]) << 8u32)
        at += 2usize
        if scalar >= 55296u32 && scalar <= 57343u32 {
            if scalar > 56319u32 || at + 1usize >= src.len { ret (used, utf8.Invalid) }
            let low = u32(src[at]) | (u32(src[at + 1usize]) << 8u32)
            if low < 56320u32 || low > 57343u32 { ret (used, utf8.Invalid) }
            at += 2usize
            scalar = 65536u32 + ((scalar - 55296u32) << 10u32) + (low - 56320u32)
        }
        let (width, width_error) = utf8.encode(scalar, out[used..])
        if width_error != ok { ret (used, width_error) }
        used += usize(width)
    }
    ret (used, ok)
}

// UTF-16 units in a UTF-8 string: one per lead byte, two for a four-byte sequence.
fn units_of(s: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let b = s[i]
        if (b & 192u8) != 128u8 { n += 1usize }
        if b >= 240u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

// --- building a request

// A request is written straight into packets: `body` holds the packet being filled, its
// eight-byte header included, and a full packet goes out before the next begins. Every length
// is known before the bytes it counts, so nothing written is ever patched, and a request of
// any size needs no buffer beyond one packet.
fn begin_message(c: *Conn, kind: u8) {
    c.kind = kind
    c.packet_id = 1usize
    c.used = 8usize
}

// Each packet is a TLS record of its own: SQL Server reads a TDS 8.0 packet from one record
// (it caps the packet size at 16192, under TLS's 16384) and drops a connection whose packet
// spans two.
fn flush_packet(c: *Conn, last_one: bool) -> err {
    let length = c.used
    c.body[0usize] = c.kind
    c.body[1usize] = 0u8
    if last_one { c.body[1usize] = 1u8 }
    c.body[2usize] = u8(length >> 8usize)
    c.body[3usize] = u8(length & 255usize)
    c.body[4usize] = 0u8
    c.body[5usize] = 0u8
    c.body[6usize] = u8(c.packet_id & 255usize)
    c.body[7usize] = 0u8
    let write_error = io.write_all(&c.sink, c.body[0usize..length])
    if write_error != ok { ret lost(c) }
    c.packet_id += 1usize
    c.used = 8usize
    ret ok
}

// Sends the last packet and leaves the reply to be read.
fn end_message(c: *Conn) -> err {
    let last_error = flush_packet(c, true)
    if last_error != ok { ret last_error }
    let flush_error = io.flush(&c.sink)
    if flush_error != ok { ret lost(c) }
    c.in_reply = true
    c.eom = false
    c.at = 0usize
    c.stop = 0usize
    ret ok
}

fn put8(c: *Conn, v: u8) -> err {
    if c.used == c.packet_size {
        let flush_error = flush_packet(c, false)
        if flush_error != ok { ret flush_error }
    }
    c.body[c.used] = v
    c.used += 1usize
    ret ok
}

fn put_le(c: *Conn, value: u64, n: usize) -> err {
    var i = 0usize
    while i < n {
        let byte_error = put8(c, u8((value >> u64(i * 8usize)) & 255u64))
        if byte_error != ok { ret byte_error }
        i += 1usize
    }
    ret ok
}

fn put_bytes(c: *Conn, v: []const u8) -> err {
    var at = 0usize
    while at < v.len {
        if c.used == c.packet_size {
            let flush_error = flush_packet(c, false)
            if flush_error != ok { ret flush_error }
        }
        var n = v.len - at
        if n > c.packet_size - c.used { n = c.packet_size - c.used }
        mem.copy[u8](c.body[c.used..c.used + n], v[at..at + n])
        c.used += n
        at += n
    }
    ret ok
}

// `s`, already checked to be UTF-8, as UTF-16LE; answers the bytes written. Whole runs of
// characters are encoded straight into the packet; the few at its end go one at a time,
// across the boundary.
fn put_utf16(c: *Conn, s: str) -> (usize, err) {
    var total = 0usize
    var off = 0usize
    while off < s.len {
        if c.packet_size - c.used < 8usize {
            let (d, d_error) = utf8.decode(s, off)
            if d_error != ok { ret (total, utf8.Invalid) }
            off += usize(d.width)
            if d.scalar < 65536u32 {
                let unit_error = put_le(c, u64(d.scalar), 2usize)
                if unit_error != ok { ret (total, unit_error) }
                total += 2usize
            } else {
                let v = d.scalar - 65536u32
                let high_error = put_le(c, u64(55296u32 + (v >> 10u32)), 2usize)
                if high_error != ok { ret (total, high_error) }
                let low_error = put_le(c, u64(56320u32 + (v & 1023u32)), 2usize)
                if low_error != ok { ret (total, low_error) }
                total += 4usize
            }
        } else {
            // At most half the room in UTF-8 bytes, cut back to a character's start: each byte
            // is at most two bytes of UTF-16, and at least four bytes always hold a character.
            var n = (c.packet_size - c.used) / 2usize
            if n > s.len - off { n = s.len - off }
            while off + n < s.len && (s[off + n] & 192u8) == 128u8 { n -= 1usize }
            let (written, encode_error) = utf8.encode_utf16(s[off..off + n], false, c.body[c.used..c.used + n * 2usize])
            if encode_error != ok { ret (total, encode_error) }
            c.used += written
            total += written
            off += n
        }
    }
    ret (total, ok)
}

// ASCII text as UTF-16LE.
fn put_ascii(c: *Conn, s: str) -> err {
    var i = 0usize
    while i < s.len {
        let high_error = put8(c, s[i])
        if high_error != ok { ret high_error }
        let low_error = put8(c, 0u8)
        if low_error != ok { ret low_error }
        i += 1usize
    }
    ret ok
}

fn digit_count(n: usize) -> usize {
    var count = 1usize
    var v = n
    while v >= 10usize {
        v /= 10usize
        count += 1usize
    }
    ret count
}

// A parameter's name, `@p<number>`, as UTF-16.
fn put_name(c: *Conn, number: usize) -> err {
    var digits: [20]u8 = zero
    let n = write_digits(digits[0..], 0usize, u64(number), 1usize)
    let at_error = put_ascii(c, "@p")
    if at_error != ok { ret at_error }
    let digits_text: str = digits[0usize..n]
    ret put_ascii(c, digits_text)
}

// ALL_HEADERS with the transaction descriptor (zero outside a transaction) and one outstanding
// request (MS-TDS 2.2.5.3).
fn put_headers(c: *Conn) -> err {
    let head: [10]u8 = [10]u8{ 22, 0, 0, 0, 18, 0, 0, 0, 2, 0 }
    let head_error = put_bytes(c, head[0..])
    if head_error != ok { ret head_error }
    let transaction_error = put_bytes(c, c.transaction)
    if transaction_error != ok { ret transaction_error }
    ret put_le(c, 1u64, 4usize)
}

// --- reading a reply

// The reply's next packet into `pkt`. Every payload byte is read through here.
fn next_packet(c: *Conn) -> err {
    if c.eom { ret protocol(c, "SQL Server's reply ended inside a token") }
    var head: [8]u8 = zero
    let head_error = io.read_exact(&c.source, head[0..])
    if head_error != ok { ret lost(c) }
    let length = (usize(head[2]) << 8usize) | usize(head[3])
    if head[0] != REPLY || length < 8usize || length - 8usize > c.pkt.len { ret protocol(c, "SQL Server answered a packet this client does not read") }
    let body_error = io.read_exact(&c.source, c.pkt[0usize..length - 8usize])
    if body_error != ok { ret lost(c) }
    c.at = 0usize
    c.stop = length - 8usize
    c.eom = (head[1] & 1u8) != 0u8
    ret ok
}

fn reply_over(c: *Conn) -> bool { ret c.eom && c.at == c.stop }

fn get8(c: *Conn) -> (u8, err) {
    while c.at == c.stop {
        let packet_error = next_packet(c)
        if packet_error != ok { ret (0u8, packet_error) }
    }
    let b = c.pkt[c.at]
    c.at += 1usize
    ret (b, ok)
}

// `dst.len` bytes of the reply, across packets.
fn take(c: *Conn, dst: []u8) -> err {
    var got = 0usize
    while got < dst.len {
        if c.at == c.stop {
            let packet_error = next_packet(c)
            if packet_error != ok { ret packet_error }
        } else {
            var n = dst.len - got
            if n > c.stop - c.at { n = c.stop - c.at }
            mem.copy[u8](dst[got..got + n], c.pkt[c.at..c.at + n])
            c.at += n
            got += n
        }
    }
    ret ok
}

fn skip(c: *Conn, count: usize) -> err {
    var left = count
    while left != 0usize {
        if c.at == c.stop {
            let packet_error = next_packet(c)
            if packet_error != ok { ret packet_error }
        } else {
            var n = left
            if n > c.stop - c.at { n = c.stop - c.at }
            c.at += n
            left -= n
        }
    }
    ret ok
}

// `n` bytes of the reply, valid until the next read: a view of the packet when they lie in it,
// a copy in the connection's token buffer when they cross into the next. Every caller asks for
// at most a token's two-byte length, which the buffer holds.
fn get(c: *Conn, n: usize) -> ([]const u8, err) {
    if c.stop - c.at >= n {
        let v = c.pkt[c.at..c.at + n]
        c.at += n
        ret (v, ok)
    }
    if n > c.token.len { ret (c.token[0usize..0usize], protocol(c, "SQL Server sent a token longer than its length field")) }
    let take_error = take(c, c.token[0usize..n])
    ret (c.token[0usize..n], take_error)
}

fn get_le(c: *Conn, n: usize) -> (u64, err) {
    let (v, get_error) = get(c, n)
    if get_error != ok { ret (0u64, get_error) }
    ret (le(v), ok)
}

// A B_VARCHAR or US_VARCHAR read past: a one- or two-byte count of UTF-16 units, then them.
fn skip_text(c: *Conn, count_bytes: usize) -> err {
    let (units, count_error) = get_le(c, count_bytes)
    if count_error != ok { ret count_error }
    ret skip(c, usize(units) * 2usize)
}

// Every token that is not rows or DONE. RETURNVALUE never comes, since no parameter is output.
fn other_token(c: *Conn, token: u8) -> err {
    if token == ENVCHANGE || token == ERROR_TOKEN || token == INFO {
        let (n, length_error) = get_le(c, 2usize)
        if length_error != ok { ret length_error }
        let (body, body_error) = get(c, usize(n))
        if body_error != ok { ret body_error }
        if token == ENVCHANGE { env_change(c, body) }
        if token == ERROR_TOKEN { record(c, body) }
        ret ok
    }
    if token == RETURNSTATUS { ret skip(c, 4usize) }
    if token == LOGINACK || token == ORDER || token == TABNAME || token == COLINFO {
        if token == LOGINACK { c.login_ack = true }
        let (n, length_error) = get_le(c, 2usize)
        if length_error != ok { ret length_error }
        ret skip(c, usize(n))
    }
    if token == SESSIONSTATE {
        let (n, length_error) = get_le(c, 4usize)
        if length_error != ok { ret length_error }
        ret skip(c, usize(n))
    }
    if token == FEATUREEXTACK {
        while true {
            let (feature, feature_error) = get8(c)
            if feature_error != ok { ret feature_error }
            if feature == 255u8 { break }
            let (n, length_error) = get_le(c, 4usize)
            if length_error != ok { ret length_error }
            let skip_error = skip(c, usize(n))
            if skip_error != ok { ret skip_error }
        }
        ret ok
    }
    ret protocol(c, "SQL Server answered a token this client does not read")
}

// ENVCHANGE: the packet size and collation the server chose, and a transaction's descriptor as
// it begins (8) and its end (9 commit, 10 rollback, 17 ended by the server).
fn env_change(c: *Conn, body: []const u8) {
    if body.len < 2usize { ret }
    let kind = body[0usize]
    if kind == 4u8 {
        let units = usize(body[1usize])
        var value = 0usize
        var i = 0usize
        while i < units && 3usize + i * 2usize < body.len {
            let digit = body[2usize + i * 2usize]
            if digit >= 48u8 && digit <= 57u8 { value = value * 10usize + usize(digit - 48u8) }
            i += 1usize
        }
        if value >= 512usize && value <= PACKET_CAP { c.packet_size = value }
    } else if kind == 7u8 {
        if body[1usize] == 5u8 && body.len >= 7usize { c.collation = le(body[2usize..7usize]) }
    } else if kind == 8u8 {
        if body[1usize] == 8u8 && body.len >= 10usize {
            mem.copy[u8](c.transaction, body[2usize..10usize])
            c.server_transaction = true
        }
    } else if kind == 9u8 || kind == 10u8 || kind == 17u8 {
        zero_bytes(c.transaction)
        c.server_transaction = false
    }
}

// --- column types

// The types whose values have a length fixed by the type: NULL, tinyint, bit, smallint, int,
// smalldatetime, real, money, datetime, float, smallmoney, bigint.
fn fixed_size(id: u8) -> (u32, bool) {
    if id == 31u8 { ret (0u32, true) }
    if id == 48u8 || id == 50u8 { ret (1u32, true) }
    if id == 52u8 { ret (2u32, true) }
    if id == 56u8 || id == 58u8 || id == 59u8 || id == 122u8 { ret (4u32, true) }
    if id == 60u8 || id == 61u8 || id == 62u8 || id == 127u8 { ret (8u32, true) }
    ret (0u32, false)
}

// guid, intn, bitn, floatn, moneyn, datetimen: a one-byte length in TYPE_INFO and in the value.
fn byte_length(id: u8) -> bool { ret id == 36u8 || id == 38u8 || id == 104u8 || id == 109u8 || id == 110u8 || id == 111u8 }
fn is_decimal(id: u8) -> bool { ret id == 55u8 || id == 63u8 || id == 106u8 || id == 108u8 }
// time, datetime2, datetimeoffset: a scale in TYPE_INFO.
fn is_scaled(id: u8) -> bool { ret id == 41u8 || id == 42u8 || id == 43u8 }
// varbinary, varchar, binary, char, nvarchar, nchar: a two-byte length.
fn short_length(id: u8) -> bool { ret id == 165u8 || id == 167u8 || id == 173u8 || id == 175u8 || id == 231u8 || id == 239u8 }
// image, text, ntext: a four-byte length and a text pointer.
fn is_long(id: u8) -> bool { ret id == 34u8 || id == 35u8 || id == 99u8 }
fn is_collated(id: u8) -> bool { ret id == 167u8 || id == 175u8 || id == 231u8 || id == 239u8 || id == 35u8 || id == 99u8 }
// nvarchar, nchar, ntext, xml.
fn is_unicode(id: u8) -> bool { ret id == 231u8 || id == 239u8 || id == 99u8 || id == 241u8 }
fn is_binary(id: u8) -> bool { ret id == 165u8 || id == 173u8 || id == 34u8 || id == 240u8 }

fn read_type(c: *Conn) -> (Col, err) {
    let (id, id_error) = get8(c)
    var col = Col { id: id, size: 0u32, precision: 0u8, scale: 0u8, plp: false, collation: 0u64 }
    if id_error != ok { ret (col, id_error) }
    let (size, fixed) = fixed_size(id)
    if fixed {
        col.size = size
        ret (col, ok)
    }
    if byte_length(id) {
        let (n, n_error) = get8(c)
        col.size = u32(n)
        ret (col, n_error)
    }
    if is_decimal(id) {
        let (v, v_error) = get(c, 3usize)
        if v_error != ok { ret (col, v_error) }
        col.size = u32(v[0usize])
        col.precision = v[1usize]
        col.scale = v[2usize]
        ret (col, ok)
    }
    if id == 40u8 { ret (col, ok) }
    if is_scaled(id) {
        let (scale, scale_error) = get8(c)
        col.scale = scale
        ret (col, scale_error)
    }
    if short_length(id) || is_long(id) {
        var width = 2usize
        if is_long(id) { width = 4usize }
        let (n, n_error) = get_le(c, width)
        if n_error != ok { ret (col, n_error) }
        col.size = u32(n)
        col.plp = width == 2usize && n == 65535u64
        if is_collated(id) {
            let (collation, collation_error) = get_le(c, 5usize)
            col.collation = collation
            ret (col, collation_error)
        }
        ret (col, ok)
    }
    if id == 241u8 {
        col.plp = true
        let (schema, schema_error) = get8(c)
        if schema_error != ok || schema == 0u8 { ret (col, schema_error) }
        let database_error = skip_text(c, 1usize)
        if database_error != ok { ret (col, database_error) }
        let owner_error = skip_text(c, 1usize)
        if owner_error != ok { ret (col, owner_error) }
        ret (col, skip_text(c, 2usize))
    }
    if id == 98u8 {
        let (n, n_error) = get_le(c, 4usize)
        col.size = u32(n)
        ret (col, n_error)
    }
    if id == 240u8 {
        col.plp = true
        let max_error = skip(c, 2usize)
        if max_error != ok { ret (col, max_error) }
        var part = 0usize
        while part < 3usize {
            let name_error = skip_text(c, 1usize)
            if name_error != ok { ret (col, name_error) }
            part += 1usize
        }
        ret (col, skip_text(c, 2usize))
    }
    ret (col, protocol(c, "a result column has a TDS type this client does not read; CAST it in the query"))
}

fn kind_of(col: Col) -> db.ValueKind {
    let id = col.id
    if id == 31u8 { ret .Null }
    if id == 48u8 || id == 52u8 || id == 56u8 || id == 127u8 || id == 38u8 { ret .I64 }
    if id == 50u8 || id == 104u8 { ret .Bool }
    if id == 59u8 || id == 62u8 || id == 109u8 { ret .F64 }
    if id == 58u8 || id == 61u8 || id == 111u8 || id == 40u8 || id == 42u8 || id == 43u8 { ret .Time }
    if is_binary(id) { ret .Bytes }
    ret .Text
}

// COLMETADATA's count; `true` for 0xFFFF, which is no metadata at all.
fn read_count(c: *Conn) -> (usize, bool, err) {
    let (n, n_error) = get_le(c, 2usize)
    ret (usize(n), n == 65535u64, n_error)
}

// The columns of a COLMETADATA token; names are kept only when `columns` has room for them.
fn read_columns(c: *Conn, types: []Col, columns: []db.Column) -> err {
    var i = 0usize
    while i < types.len {
        let user_error = skip(c, 4usize)
        if user_error != ok { ret user_error }
        let (flags, flags_error) = get_le(c, 2usize)
        if flags_error != ok { ret flags_error }
        let (col, type_error) = read_type(c)
        if type_error != ok { ret type_error }
        types[i] = col
        if is_long(col.id) {
            let (parts, parts_error) = get8(c)
            if parts_error != ok { ret parts_error }
            var p = 0u8
            while p < parts {
                let part_error = skip_text(c, 2usize)
                if part_error != ok { ret part_error }
                p += 1u8
            }
        }
        let (units, units_error) = get8(c)
        if units_error != ok { ret units_error }
        if columns.len == 0usize {
            let name_error = skip(c, usize(units) * 2usize)
            if name_error != ok { ret name_error }
        } else {
            let (raw, raw_error) = get(c, usize(units) * 2usize)
            if raw_error != ok { ret raw_error }
            let (spelled, spelled_error) = mem.alloc[u8](c.arena, usize(units) * 3usize)
            if spelled_error != ok { ret spelled_error }
            let (written, narrow_error) = narrow(raw, spelled)
            let name: str = spelled[0usize..written]
            columns[i] = db.Column { name: name, kind: kind_of(col), nullable: (flags & 1u64) != 0u64 }
        }
        i += 1usize
    }
    ret ok
}

// One value's bytes and whether it is NULL. With a reader, the bytes are valid until the next
// read: a view of the packet, a copy in the token buffer when they cross into the next packet,
// or -- for a PLP or `text` value too long for that -- the reader's own buffer. Without one
// the value is read past and nothing is kept.
fn read_value(c: *Conn, col: Col, r: *Reader) -> ([]const u8, bool, err) {
    let nothing = c.pkt[0usize..0usize]
    if col.plp {
        let (total, total_error) = get_le(c, 8usize)
        if total_error != ok { ret (nothing, false, total_error) }
        if total == PLP_NULL { ret (nothing, true, ok) }
        var got = 0usize
        while true {
            let (chunk, chunk_error) = get_le(c, 4usize)
            if chunk_error != ok { ret (nothing, false, chunk_error) }
            if chunk == 0u64 { break }
            let n = usize(chunk)
            if r == nil {
                let chunk_skip_error = skip(c, n)
                if chunk_skip_error != ok { ret (nothing, false, chunk_skip_error) }
            } else {
                if r.long.len < got + n {
                    let (bigger, grow_error) = grown(c.arena, r.long, got, got + n)
                    if grow_error != ok { ret (nothing, false, grow_error) }
                    r.long = bigger
                }
                let take_error = take(c, r.long[got..got + n])
                if take_error != ok { ret (nothing, false, take_error) }
                got += n
            }
        }
        if r == nil { ret (nothing, false, ok) }
        ret (r.long[0usize..got], false, ok)
    }
    var n = 0usize
    let (size, fixed) = fixed_size(col.id)
    if fixed {
        if col.id == 31u8 { ret (nothing, true, ok) }
        n = usize(size)
    } else {
        var width = 1usize
        if is_long(col.id) {
            let (pointer, pointer_error) = get8(c)
            if pointer_error != ok { ret (nothing, false, pointer_error) }
            if pointer == 0u8 { ret (nothing, true, ok) }
            // The text pointer and its timestamp.
            let pointer_skip_error = skip(c, usize(pointer) + 8usize)
            if pointer_skip_error != ok { ret (nothing, false, pointer_skip_error) }
            width = 4usize
        } else if col.id == 98u8 {
            width = 4usize
        } else if short_length(col.id) {
            width = 2usize
        }
        let (length, length_error) = get_le(c, width)
        if length_error != ok { ret (nothing, false, length_error) }
        if width == 2usize && length == 65535u64 { ret (nothing, true, ok) }
        if length == 0u64 && (width == 1usize || col.id == 98u8) { ret (nothing, true, ok) }
        n = usize(length)
    }
    if r == nil {
        let value_skip_error = skip(c, n)
        ret (nothing, false, value_skip_error)
    }
    if c.stop - c.at >= n || n <= c.token.len {
        let (v, v_error) = get(c, n)
        ret (v, false, v_error)
    }
    if r.long.len < n {
        let (bigger, grow_error) = grown(c.arena, r.long, 0usize, n)
        if grow_error != ok { ret (nothing, false, grow_error) }
        r.long = bigger
    }
    let long_error = take(c, r.long[0usize..n])
    ret (r.long[0usize..n], false, long_error)
}

fn is_null_bit(bitmap: []const u8, i: usize) -> bool { ret ((bitmap[i / 8usize] >> u8(i % 8usize)) & 1u8) != 0u8 }

// A row read past, for a reply nobody reads; `bitmap` has room for an NBCROW's.
fn skip_row(c: *Conn, types: []const Col, bitmap: []u8, nbc: bool) -> err {
    let n = types.len
    if nbc {
        let bitmap_error = take(c, bitmap[0usize..(n + 7usize) / 8usize])
        if bitmap_error != ok { ret bitmap_error }
    }
    var i = 0usize
    while i < n {
        if !nbc || !is_null_bit(bitmap, i) {
            let (v, is_null, value_error) = read_value(c, types[i], nil)
            if value_error != ok { ret value_error }
        }
        i += 1usize
    }
    ret ok
}

// Reads the rest of the reply: result sets are read past, and the rows each DONE counts for a
// statement other than a SELECT are summed. `current` is the metadata of rows still to come.
// The metadata of result sets nobody reads lives only for this call.
fn finish(c: *Conn, current: []const Col) -> (u64, err) {
    let mark = mem.mark(c.arena)
    let (affected, finish_error) = drain(c, current)
    mem.reset(c.arena, mark)
    ret (affected, finish_error)
}

fn drain(c: *Conn, current: []const Col) -> (u64, err) {
    var affected = 0u64
    var types = current
    let (first_bitmap, first_bitmap_error) = mem.alloc[u8](c.arena, (current.len + 7usize) / 8usize)
    if first_bitmap_error != ok { ret (affected, lost(c)) }
    var bitmap = first_bitmap
    while !reply_over(c) {
        let (token, token_error) = get8(c)
        if token_error != ok { ret (affected, token_error) }
        if token == COLMETADATA {
            let (n, absent, count_error) = read_count(c)
            if count_error != ok { ret (affected, count_error) }
            if !absent {
                let (fresh, fresh_error) = mem.alloc[Col](c.arena, n)
                let (fresh_bitmap, fresh_bitmap_error) = mem.alloc[u8](c.arena, (n + 7usize) / 8usize)
                if fresh_error != ok || fresh_bitmap_error != ok { ret (affected, lost(c)) }
                var names: []db.Column = zero
                let columns_error = read_columns(c, fresh, names)
                if columns_error != ok { ret (affected, columns_error) }
                types = fresh
                bitmap = fresh_bitmap
            }
        } else if token == ROW || token == NBCROW {
            let row_error = skip_row(c, types, bitmap, token == NBCROW)
            if row_error != ok { ret (affected, row_error) }
        } else if token == DONE || token == DONEINPROC || token == DONEPROC {
            let (v, done_error) = get(c, 12usize)
            if done_error != ok { ret (affected, done_error) }
            let status = le(v[0usize..2usize])
            let command = le(v[2usize..4usize])
            if token != DONEPROC && (status & DONE_COUNT) != 0u64 && command != SELECT_COMMAND { affected += le(v[4usize..12usize]) }
        } else {
            let other_error = other_token(c, token)
            if other_error != ok { ret (affected, other_error) }
        }
    }
    c.in_reply = false
    ret (affected, outcome(c))
}

// --- statements

// Counts the `?` placeholders in `sql` and, with a connection, writes the text into its request
// as UTF-16 with the kth placeholder spelled `@pk` -- or `NULL` when the kth parameter is NULL,
// since a NULL literal converts to any column's type and a typed NULL parameter does not (an
// nvarchar one is refused by a varbinary column). Strings ('...', with '' inside), quoted
// identifiers ("..." and [...]) and comments (-- to the line's end, and /* */, which nest in
// T-SQL) hold none.
fn walk(sql: str, c: *Conn, params: []const db.Parameter) -> (usize, err) {
    var count = 0usize
    var start = 0usize
    var i = 0usize
    while i < sql.len {
        let b = sql[i]
        if b == 39u8 || b == 34u8 || b == 91u8 {
            var close = b
            if b == 91u8 { close = 93u8 }
            var j = i + 1usize
            while j < sql.len {
                if sql[j] != close {
                    j += 1usize
                } else if j + 1usize < sql.len && sql[j + 1usize] == close {
                    j += 2usize
                } else {
                    j += 1usize
                    break
                }
            }
            i = j
        } else if b == 45u8 && i + 1usize < sql.len && sql[i + 1usize] == 45u8 {
            while i < sql.len && sql[i] != 10u8 { i += 1usize }
        } else if b == 47u8 && i + 1usize < sql.len && sql[i + 1usize] == 42u8 {
            var depth = 1usize
            i += 2usize
            while i < sql.len && depth != 0usize {
                if sql[i] == 47u8 && i + 1usize < sql.len && sql[i + 1usize] == 42u8 {
                    depth += 1usize
                    i += 2usize
                } else if sql[i] == 42u8 && i + 1usize < sql.len && sql[i + 1usize] == 47u8 {
                    depth -= 1usize
                    i += 2usize
                } else {
                    i += 1usize
                }
            }
        } else if b == 63u8 {
            count += 1usize
            if c != nil {
                let (piece, piece_error) = put_utf16(c, sql[start..i])
                if piece_error != ok { ret (count, piece_error) }
                var name_error = ok
                if count <= params.len && wire_kind(params[count - 1usize].value) == 0u8 {
                    name_error = put_ascii(c, "NULL")
                } else {
                    name_error = put_name(c, count)
                }
                if name_error != ok { ret (count, name_error) }
                start = i + 1usize
            }
            i += 1usize
        } else {
            i += 1usize
        }
    }
    if c != nil && start < sql.len {
        let (rest, rest_error) = put_utf16(c, sql[start..])
        if rest_error != ok { ret (count, rest_error) }
    }
    ret (count, ok)
}

// How a value travels: 0 NULL (nvarchar), 1 bit, 2 bigint, 3 decimal(38,0), 4 float,
// 5 nvarchar(4000), 6 nvarchar(max), 7 varbinary(8000), 8 varbinary(max), 9 datetime2(7).
fn wire_kind(value: db.Value) -> u8 {
    switch value {
    case .Null:
        ret 0u8
    case .Bool:
        ret 1u8
    case .I64:
        ret 2u8
    case .U64 as unsigned:
        if unsigned > I64_MAX { ret 3u8 }
        ret 2u8
    case .F64:
        ret 4u8
    case .Text as s:
        if units_of(s) > 4000usize { ret 6u8 }
        ret 5u8
    case .Bytes as bytes:
        if bytes.len > 8000usize { ret 8u8 }
        ret 7u8
    case .Time:
        ret 9u8
    }
    ret 0u8
}

fn declaration(kind: u8) -> str {
    if kind == 1u8 { ret "bit" }
    if kind == 2u8 { ret "bigint" }
    if kind == 3u8 { ret "decimal(38,0)" }
    if kind == 4u8 { ret "float" }
    if kind == 6u8 { ret "nvarchar(max)" }
    if kind == 7u8 { ret "varbinary(8000)" }
    if kind == 8u8 { ret "varbinary(max)" }
    if kind == 9u8 { ret "datetime2(7)" }
    ret "nvarchar(4000)"
}

// A PLP value of `n` bytes, known before they are written: its total and one chunk of all of
// them, which `end_plp` terminates. An empty value has no chunk at all, since a zero-length
// chunk is the terminator.
fn begin_plp(c: *Conn, n: usize) -> err {
    let total_error = put_le(c, u64(n), 8usize)
    if total_error != ok { ret total_error }
    if n == 0usize { ret ok }
    ret put_le(c, u64(n), 4usize)
}

fn end_plp(c: *Conn) -> err { ret put_le(c, 0u64, 4usize) }

fn put_collation(c: *Conn) -> err { ret put_le(c, c.collation, 5usize) }

// An unnamed input parameter's name and status, then nvarchar(max)'s TYPE_INFO and the start
// of a value of `n` bytes.
fn begin_text_param(c: *Conn, n: usize) -> err {
    let flags_error = put_le(c, 0u64, 2usize)
    if flags_error != ok { ret flags_error }
    let head: [3]u8 = [3]u8{ 231, 255, 255 }
    let head_error = put_bytes(c, head[0..])
    if head_error != ok { ret head_error }
    let collation_error = put_collation(c)
    if collation_error != ok { ret collation_error }
    ret begin_plp(c, n)
}

fn put_value(c: *Conn, value: db.Value, kind: u8) -> err {
    switch value {
    case .Bool as truth:
        // BITN: TYPE_INFO 1, then a one-byte value.
        var bit: [4]u8 = [4]u8{ 104, 1, 1, 0 }
        if truth { bit[3] = 1u8 }
        ret put_bytes(c, bit[0..])
    case .I64 as signed:
        let head_error = put_le(c, 526374u64, 3usize)
        if head_error != ok { ret head_error }
        ret put_le(c, mem.bitcast[u64](signed), 8usize)
    case .U64 as unsigned:
        if kind == 2u8 {
            let small_error = put_le(c, 526374u64, 3usize)
            if small_error != ok { ret small_error }
            ret put_le(c, unsigned, 8usize)
        }
        // DECIMALN(38,0): TYPE_INFO 17, 38, 0; then 17 bytes, a positive sign and the magnitude.
        let decimal: [6]u8 = [6]u8{ 106, 17, 38, 0, 17, 1 }
        let decimal_error = put_bytes(c, decimal[0..])
        if decimal_error != ok { ret decimal_error }
        let low_error = put_le(c, unsigned, 8usize)
        if low_error != ok { ret low_error }
        ret put_le(c, 0u64, 8usize)
    case .F64 as real:
        let float_error = put_le(c, 526445u64, 3usize)
        if float_error != ok { ret float_error }
        ret put_le(c, mem.bitcast[u64](real), 8usize)
    case .Text as s:
        let text_bytes = units_of(s) * 2usize
        if kind == 6u8 {
            let long_head: [3]u8 = [3]u8{ 231, 255, 255 }
            let long_error = put_bytes(c, long_head[0..])
            if long_error != ok { ret long_error }
            let long_collation_error = put_collation(c)
            if long_collation_error != ok { ret long_collation_error }
            let plp_error = begin_plp(c, text_bytes)
            if plp_error != ok { ret plp_error }
            let (long_written, long_text_error) = put_utf16(c, s)
            if long_text_error != ok { ret long_text_error }
            ret end_plp(c)
        }
        let head: [3]u8 = [3]u8{ 231, 64, 31 }
        let text_head_error = put_bytes(c, head[0..])
        if text_head_error != ok { ret text_head_error }
        let text_collation_error = put_collation(c)
        if text_collation_error != ok { ret text_collation_error }
        let length_error = put_le(c, u64(text_bytes), 2usize)
        if length_error != ok { ret length_error }
        let (written, text_error) = put_utf16(c, s)
        ret text_error
    case .Bytes as bytes:
        if kind == 8u8 {
            let long_binary: [3]u8 = [3]u8{ 165, 255, 255 }
            let long_binary_error = put_bytes(c, long_binary[0..])
            if long_binary_error != ok { ret long_binary_error }
            let binary_plp_error = begin_plp(c, bytes.len)
            if binary_plp_error != ok { ret binary_plp_error }
            let long_bytes_error = put_bytes(c, bytes)
            if long_bytes_error != ok { ret long_bytes_error }
            ret end_plp(c)
        }
        let binary: [3]u8 = [3]u8{ 165, 64, 31 }
        let binary_error = put_bytes(c, binary[0..])
        if binary_error != ok { ret binary_error }
        let binary_length_error = put_le(c, u64(bytes.len), 2usize)
        if binary_length_error != ok { ret binary_length_error }
        ret put_bytes(c, bytes)
    case .Time as instant:
        // datetime2(7): 100 ns units into the day in five bytes, then days from 0001-01-01.
        let day = time.floor_div(instant.nanos, NANOS_PER_DAY)
        let within = instant.nanos - day * NANOS_PER_DAY
        let stamp_head_error = put_le(c, 526122u64, 3usize)
        if stamp_head_error != ok { ret stamp_head_error }
        let units_error = put_le(c, u64(within / 100i64), 5usize)
        if units_error != ok { ret units_error }
        ret put_le(c, u64(day - DAYS_TO_0001), 3usize)
    default:
        // NULL as nvarchar(4000).
        let null_head: [3]u8 = [3]u8{ 231, 64, 31 }
        let null_error = put_bytes(c, null_head[0..])
        if null_error != ok { ret null_error }
        let null_collation_error = put_collation(c)
        if null_collation_error != ok { ret null_collation_error }
        ret put_le(c, 65535u64, 2usize)
    }
    ret ok
}

// `sp_executesql` with the statement, its declarations and the values. The rewritten text is
// the original less its `?`s plus each `@pN` or `NULL`; the declarations are ASCII.
fn put_rpc(c: *Conn, sql: str, params: []const db.Parameter) -> err {
    let proc_error = put_le(c, 65535u64 | (SP_EXECUTESQL << 16u64), 6usize)
    if proc_error != ok { ret proc_error }
    var text_units = units_of(sql) - params.len
    var declared_units = 0usize
    var typed = 0usize
    var k = 0usize
    while k < params.len {
        let kind = wire_kind(params[k].value)
        if kind == 0u8 {
            text_units += 4usize
        } else {
            text_units += 2usize + digit_count(k + 1usize)
            if typed != 0usize { declared_units += 2usize }
            declared_units += 3usize + digit_count(k + 1usize) + declaration(kind).len
            typed += 1usize
        }
        k += 1usize
    }
    let statement_error = begin_text_param(c, text_units * 2usize)
    if statement_error != ok { ret statement_error }
    let (count, walk_error) = walk(sql, c, params)
    if walk_error != ok { ret walk_error }
    let statement_end_error = end_plp(c)
    if statement_end_error != ok { ret statement_end_error }
    // NULLs are literals in the text, so they are neither declared nor sent.
    if typed == 0usize { ret ok }
    let declared_error = begin_text_param(c, declared_units * 2usize)
    if declared_error != ok { ret declared_error }
    var i = 0usize
    var first = true
    while i < params.len {
        if wire_kind(params[i].value) == 0u8 {
            i += 1usize
            continue
        }
        if !first {
            let comma_error = put_ascii(c, ", ")
            if comma_error != ok { ret comma_error }
        }
        first = false
        let name_error = put_name(c, i + 1usize)
        if name_error != ok { ret name_error }
        let space_error = put_ascii(c, " ")
        if space_error != ok { ret space_error }
        let type_error = put_ascii(c, declaration(wire_kind(params[i].value)))
        if type_error != ok { ret type_error }
        i += 1usize
    }
    let declared_end_error = end_plp(c)
    if declared_end_error != ok { ret declared_end_error }
    i = 0usize
    while i < params.len {
        if wire_kind(params[i].value) == 0u8 {
            i += 1usize
            continue
        }
        let units_error = put8(c, u8(2usize + digit_count(i + 1usize)))
        if units_error != ok { ret units_error }
        let name_error = put_name(c, i + 1usize)
        if name_error != ok { ret name_error }
        let status_error = put8(c, 0u8)
        if status_error != ok { ret status_error }
        let value = params[i].value
        let value_error = put_value(c, value, wire_kind(value))
        if value_error != ok { ret value_error }
        i += 1usize
    }
    ret ok
}

fn text_valid(value: db.Value) -> bool {
    switch value {
    case .Text as s:
        ret utf8.validate(s)
    default:
        ret true
    }
    ret true
}

// Sends `sql` -- as a batch without parameters, through `sp_executesql` with them -- leaving
// the reply to be read.
fn run(c: *Conn, sql: str, placeholders: usize, params: []const db.Parameter) -> err {
    if c.broken { ret refuse(c, "the connection to SQL Server is broken", Failed) }
    if c.active != nil { ret refuse(c, "a row reader is still open on this connection", db.Busy) }
    if placeholders != params.len { ret refuse(c, "the statement's parameter count differs from the parameters given", db.InvalidQuery) }
    if params.len > 65535usize { ret refuse(c, "SQL Server takes at most 65535 parameters", db.InvalidQuery) }
    // Packets go out as the request is written, so everything that could refuse it is checked
    // before the first one.
    if !utf8.validate(sql) { ret refuse(c, "the SQL text is not UTF-8", db.InvalidQuery) }
    var i = 0usize
    while i < params.len {
        if params[i].name.len != 0usize { ret refuse(c, "parameters are positional (`?`); a named one is refused", db.InvalidQuery) }
        if !text_valid(params[i].value) { ret refuse(c, "a text value is not UTF-8", db.InvalidQuery) }
        i += 1usize
    }
    if c.in_reply {
        let (ignored, drain_error) = finish(c, zero)
        if c.broken { ret drain_error }
    }
    clear(c)
    var kind = SQL_BATCH
    if params.len != 0usize { kind = RPC }
    begin_message(c, kind)
    let headers_error = put_headers(c)
    if headers_error != ok { ret headers_error }
    var build_error = ok
    if params.len == 0usize {
        let (written, batch_error) = put_utf16(c, sql)
        build_error = batch_error
    } else {
        build_error = put_rpc(c, sql, params)
    }
    if build_error != ok { ret build_error }
    ret end_message(c)
}

fn execute_text(c: *Conn, sql: str, placeholders: usize, params: []const db.Parameter) -> (u64, err) {
    let run_error = run(c, sql, placeholders, params)
    if run_error != ok { ret (0u64, run_error) }
    let (affected, finish_error) = finish(c, zero)
    ret (affected, finish_error)
}

fn count_placeholders(sql: str) -> usize {
    let (count, count_error) = walk(sql, nil, zero)
    ret count
}

// --- row readers

// Reads up to the first result set's metadata. A reply with none answers a reader of no
// columns; an error before it answers the error.
fn open_reply(c: *Conn, statement: *Stmt) -> (db.Rows, err) {
    var rows: db.Rows = zero
    while !reply_over(c) {
        let (token, token_error) = get8(c)
        if token_error != ok { ret (rows, token_error) }
        if token == COLMETADATA {
            let (n, absent, count_error) = read_count(c)
            if count_error != ok { ret (rows, count_error) }
            if !absent {
                let (r, reader_error) = new_reader(c, statement, n)
                if reader_error != ok { ret (rows, lost(c)) }
                let columns_error = read_columns(c, r.types, r.columns)
                if columns_error != ok { ret (rows, columns_error) }
                if c.failed {
                    let (ignored, failed_error) = finish(c, r.types)
                    ret (rows, failed_error)
                }
                r.done = false
                c.active = r
                rows.ctx = mem.cast[*void](r)
                ret (rows, ok)
            }
        } else if token == ROW || token == NBCROW {
            ret (rows, protocol(c, "SQL Server sent a row before its columns"))
        } else if token == DONE || token == DONEINPROC || token == DONEPROC {
            let done_error = skip(c, 12usize)
            if done_error != ok { ret (rows, done_error) }
        } else {
            let other_error = other_token(c, token)
            if other_error != ok { ret (rows, other_error) }
        }
    }
    c.in_reply = false
    if c.failed { ret (rows, outcome(c)) }
    let (empty, empty_error) = new_reader(c, statement, 0usize)
    if empty_error != ok { ret (rows, empty_error) }
    rows.ctx = mem.cast[*void](empty)
    ret (rows, ok)
}

fn new_reader(c: *Conn, statement: *Stmt, n: usize) -> (*Reader, err) {
    let (readers, reader_error) = mem.alloc[Reader](c.arena, 1usize)
    let (types, types_error) = mem.alloc[Col](c.arena, n)
    let (cols, cols_error) = mem.alloc[db.Column](c.arena, n)
    let (bitmap, bitmap_error) = mem.alloc[u8](c.arena, (n + 7usize) / 8usize)
    if reader_error != ok || types_error != ok || cols_error != ok || bitmap_error != ok { ret (nil, mem.Exhausted) }
    var no_bytes: []u8 = zero
    readers[0usize] = Reader { conn: c, statement: statement, done: true, closed: false, types: types, columns: cols, bitmap: bitmap, buffer: no_bytes, used: 0usize, long: no_bytes }
    ret (&readers[0usize], ok)
}

// Room for `n` more bytes of this row. A grown buffer is a new one: the values already
// filled keep pointing at the old, which the arena still holds.
fn reserve(r: *Reader, n: usize) -> err {
    if r.used + n <= r.buffer.len { ret ok }
    var size = r.buffer.len * 2usize
    if size < 256usize { size = 256usize }
    if size < n { size = n }
    let (bytes, grow_error) = mem.alloc[u8](r.conn.arena, size)
    if grow_error != ok { ret grow_error }
    r.buffer = bytes
    r.used = 0usize
    ret ok
}

fn next_row(r: *Reader, dst: []db.Value) -> (bool, err) {
    if r.closed { ret (false, db.Closed) }
    if r.done { ret (false, ok) }
    let c = r.conn
    if dst.len < r.columns.len { ret (false, refuse(c, "the row buffer is shorter than the row", db.InvalidQuery)) }
    while true {
        let (token, token_error) = get8(c)
        if token_error != ok {
            end_reader(r)
            ret (false, token_error)
        }
        if token == ROW || token == NBCROW {
            let fill_error = fill(r, dst, token == NBCROW)
            if fill_error != ok {
                if c.broken { end_reader(r) }
                ret (false, fill_error)
            }
            ret (true, ok)
        }
        if token == DONE || token == DONEINPROC || token == DONEPROC {
            end_reader(r)
            let done_error = skip(c, 12usize)
            if done_error != ok { ret (false, done_error) }
            let (ignored, rest_error) = finish(c, zero)
            ret (false, rest_error)
        }
        if token == COLMETADATA {
            end_reader(r)
            ret (false, protocol(c, "SQL Server sent columns inside a result set"))
        }
        let other_error = other_token(c, token)
        if other_error != ok {
            end_reader(r)
            ret (false, other_error)
        }
    }
    ret (false, ok)
}

fn end_reader(r: *Reader) {
    r.done = true
    if r.conn.active == r { r.conn.active = nil }
}

// One row into `dst`. A value this client cannot turn into a `db.Value` is left NULL and the
// row read to its end, so the reply stays in step; the first such failure is answered.
fn fill(r: *Reader, dst: []db.Value, nbc: bool) -> err {
    let c = r.conn
    let n = r.types.len
    if nbc {
        let bitmap_error = take(c, r.bitmap)
        if bitmap_error != ok { ret bitmap_error }
    }
    r.used = 0usize
    var first_error = ok
    var i = 0usize
    while i < n {
        dst[i] = .Null
        if !nbc || !is_null_bit(r.bitmap, i) {
            let (v, is_null, read_error) = read_value(c, r.types[i], r)
            if read_error != ok { ret read_error }
            if !is_null {
                let decode_error = decode(r, r.types[i], v, dst, i)
                if decode_error != ok && first_error == ok { first_error = decode_error }
            }
        }
        i += 1usize
    }
    ret first_error
}

// --- values

fn signed_le(v: []const u8) -> i64 { ret octets.sign_extend(le(v), u32(v.len * 8usize)) }

fn pow10(n: u8) -> i64 {
    var x = 1i64
    var i = 0u8
    while i < n {
        x *= 10i64
        i += 1u8
    }
    ret x
}

// `value` in decimal at `at`, at least `width` digits; answers the end.
fn write_digits(buf: []u8, at: usize, value: u64, width: usize) -> usize {
    var digits: [20]u8 = zero
    var n = 0usize
    var v = value
    while v != 0u64 || n < width {
        digits[n] = u8(48u64 + v % 10u64)
        v /= 10u64
        n += 1usize
    }
    var i = 0usize
    while i < n {
        buf[at + i] = digits[n - 1usize - i]
        i += 1usize
    }
    ret at + n
}

fn put_text(r: *Reader, start: usize, stop: usize, dst: []db.Value, i: usize) {
    r.used = stop
    let s: str = r.buffer[start..stop]
    dst[i] = db.Value{ Text: s }
}

// A decimal or money value: `negative`, a magnitude of up to 128 bits in little-endian 32-bit
// limbs, and `scale` digits after the point.
fn put_scaled(r: *Reader, negative: bool, limbs: [4]u32, scale: u8, dst: []db.Value, i: usize) -> err {
    var digits: [48]u8 = zero
    var parts = limbs
    var n = 0usize
    while true {
        var rest = 0u64
        var k = 4usize
        while k > 0usize {
            k -= 1usize
            let current = (rest << 32u64) | u64(parts[k])
            parts[k] = u32(current / 10u64)
            rest = current % 10u64
        }
        digits[n] = u8(48u64 + rest)
        n += 1usize
        let more = parts[0usize] != 0u32 || parts[1usize] != 0u32 || parts[2usize] != 0u32 || parts[3usize] != 0u32
        if !more && n > usize(scale) { break }
    }
    let reserve_error = reserve(r, n + 2usize)
    if reserve_error != ok { ret reserve_error }
    let start = r.used
    var at = start
    if negative {
        r.buffer[at] = 45u8
        at += 1usize
    }
    while n > 0usize {
        if n == usize(scale) {
            r.buffer[at] = 46u8
            at += 1usize
        }
        n -= 1usize
        r.buffer[at] = digits[n]
        at += 1usize
    }
    put_text(r, start, at, dst, i)
    ret ok
}

fn put_instant(r: *Reader, day: i64, within: i64, dst: []db.Value, i: usize) -> err {
    if day < FIRST_DAY || day > LAST_DAY { ret refuse(r.conn, "a date or time names no instant an i64 of nanoseconds holds", Failed) }
    dst[i] = db.Value{ Time: time.Instant { nanos: day * NANOS_PER_DAY + within } }
    ret ok
}

fn put_bytes_value(r: *Reader, v: []const u8, dst: []db.Value, i: usize) -> err {
    let reserve_error = reserve(r, v.len)
    if reserve_error != ok { ret reserve_error }
    let start = r.used
    if v.len != 0usize { mem.copy[u8](r.buffer[start..start + v.len], v) }
    r.used = start + v.len
    dst[i] = db.Value{ Bytes: r.buffer[start..start + v.len] }
    ret ok
}

fn hex_digit(v: u8) -> u8 {
    if v < 10u8 { ret 48u8 + v }
    ret 55u8 + v
}

// Windows-1252 for a Latin-1 collation: a sort id of the SQL_Latin1 family, or a Windows
// collation whose language's ANSI code page is 1252.
fn is_cp1252(collation: u64) -> bool {
    let sort_id = (collation >> 32u64) & 255u64
    if sort_id != 0u64 { ret sort_id >= 51u64 && sort_id <= 54u64 }
    let language = collation & 1023u64
    ret language == 3u64 || language == 6u64 || language == 7u64 || language == 9u64 || language == 10u64 || language == 11u64 || language == 12u64 || language == 15u64 || language == 16u64 || language == 19u64 || language == 20u64 || language == 22u64 || language == 29u64 || language == 33u64 || language == 45u64 || language == 54u64 || language == 56u64 || language == 62u64 || language == 65u64 || language == 86u64
}

// Windows-1252's 0x80..0x9F; the rest of its high half is Latin-1.
fn cp1252_scalar(b: u8) -> u32 {
    let table: [32]u32 = [32]u32{ 8364, 129, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 352, 8249, 338, 141, 381, 143, 144, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, 353, 8250, 339, 157, 382, 376 }
    if b >= 128u8 && b < 160u8 { ret table[usize(b - 128u8)] }
    ret u32(b)
}

// char, varchar and text: UTF-8 under a UTF-8 collation, Windows-1252 under a Latin-1 one.
fn put_single_byte(r: *Reader, col: Col, v: []const u8, dst: []db.Value, i: usize) -> err {
    let utf8_collation = ((col.collation >> 24u64) & 4u64) != 0u64
    let reserve_error = reserve(r, v.len * 3usize)
    if reserve_error != ok { ret reserve_error }
    let start = r.used
    var at = start
    var k = 0usize
    while k < v.len {
        let b = v[k]
        if b < 128u8 || utf8_collation {
            r.buffer[at] = b
            at += 1usize
        } else {
            if !is_cp1252(col.collation) { ret refuse(r.conn, "a varchar holds non-ASCII text in a code page this client does not decode; CAST it to nvarchar", Failed) }
            let (width, width_error) = utf8.encode(cp1252_scalar(b), r.buffer[at..])
            if width_error != ok { ret width_error }
            at += usize(width)
        }
        k += 1usize
    }
    put_text(r, start, at, dst, i)
    ret ok
}

// A time of day (`time`, and the front of `datetime2`/`datetimeoffset`) in 10^-scale seconds.
fn time_units(v: []const u8) -> i64 { ret i64(le(v)) }

fn decode(r: *Reader, col: Col, v: []const u8, dst: []db.Value, i: usize) -> err {
    let id = col.id
    if id == 48u8 || (id == 38u8 && v.len == 1usize) {
        dst[i] = db.Value{ I64: i64(v[0usize]) }
        ret ok
    }
    if id == 52u8 || id == 56u8 || id == 127u8 || id == 38u8 {
        dst[i] = db.Value{ I64: signed_le(v) }
        ret ok
    }
    if id == 50u8 || id == 104u8 {
        dst[i] = db.Value{ Bool: v[0usize] != 0u8 }
        ret ok
    }
    if id == 59u8 || id == 62u8 || id == 109u8 {
        if v.len == 4usize {
            dst[i] = db.Value{ F64: f64(mem.bitcast[f32](u32(le(v)))) }
        } else {
            dst[i] = db.Value{ F64: mem.bitcast[f64](le(v)) }
        }
        ret ok
    }
    if id == 60u8 || id == 122u8 || id == 110u8 {
        // money: the high 32 bits come first; units of 1/10000.
        var amount = signed_le(v)
        if v.len == 8usize { amount = i64.trunc((le(v[0usize..4usize]) << 32u64) | le(v[4usize..8usize])) }
        var magnitude = mem.bitcast[u64](amount)
        if amount < 0i64 { magnitude = 0u64 -% magnitude }
        let limbs: [4]u32 = [4]u32{ u32(magnitude & 4294967295u64), u32(magnitude >> 32u64), 0u32, 0u32 }
        ret put_scaled(r, amount < 0i64, limbs, 4u8, dst, i)
    }
    if is_decimal(id) {
        var limbs: [4]u32 = zero
        var k = 1usize
        while k < v.len && k <= 16usize {
            limbs[(k - 1usize) / 4usize] |= u32(v[k]) << u32(((k - 1usize) % 4usize) * 8usize)
            k += 1usize
        }
        ret put_scaled(r, v[0usize] == 0u8, limbs, col.scale, dst, i)
    }
    if id == 58u8 || id == 61u8 || id == 111u8 {
        if v.len == 4usize {
            // smalldatetime: days and minutes from 1900-01-01.
            let minutes = i64(le(v[2usize..4usize]))
            ret put_instant(r, DAYS_TO_1900 + i64(le(v[0usize..2usize])), minutes * 60i64 * NANOS_PER_SECOND, dst, i)
        }
        // datetime: days from 1900-01-01, then 1/300 s ticks, rounded to SQL Server's milliseconds.
        let days = signed_le(v[0usize..4usize])
        let ticks = i64(le(v[4usize..8usize]))
        let millis = (ticks * 10i64 + 1i64) / 3i64
        ret put_instant(r, DAYS_TO_1900 + days, millis * 1000000i64, dst, i)
    }
    if id == 40u8 { ret put_instant(r, DAYS_TO_0001 + i64(le(v)), 0i64, dst, i) }
    if id == 42u8 || id == 43u8 {
        var time_len = v.len - 3usize
        if id == 43u8 { time_len = v.len - 5usize }
        let within = time_units(v[0usize..time_len]) * pow10(9u8 - col.scale)
        ret put_instant(r, DAYS_TO_0001 + i64(le(v[time_len..time_len + 3usize])), within, dst, i)
    }
    if id == 41u8 {
        let units = time_units(v)
        let per_second = pow10(col.scale)
        let seconds = units / per_second
        let reserve_error = reserve(r, 17usize)
        if reserve_error != ok { ret reserve_error }
        let start = r.used
        var at = write_digits(r.buffer, start, u64(seconds / 3600i64), 2usize)
        r.buffer[at] = 58u8
        at = write_digits(r.buffer, at + 1usize, u64((seconds / 60i64) % 60i64), 2usize)
        r.buffer[at] = 58u8
        at = write_digits(r.buffer, at + 1usize, u64(seconds % 60i64), 2usize)
        if col.scale != 0u8 {
            r.buffer[at] = 46u8
            at = write_digits(r.buffer, at + 1usize, u64(units % per_second), usize(col.scale))
        }
        put_text(r, start, at, dst, i)
        ret ok
    }
    if id == 36u8 {
        // uniqueidentifier: the first three groups little-endian.
        let order: [16]u8 = [16]u8{ 3, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15 }
        let reserve_error = reserve(r, 36usize)
        if reserve_error != ok { ret reserve_error }
        let start = r.used
        var at = start
        var k = 0usize
        while k < 16usize {
            if k == 4usize || k == 6usize || k == 8usize || k == 10usize {
                r.buffer[at] = 45u8
                at += 1usize
            }
            let b = v[usize(order[k])]
            r.buffer[at] = hex_digit(b >> 4u8)
            r.buffer[at + 1usize] = hex_digit(b & 15u8)
            at += 2usize
            k += 1usize
        }
        put_text(r, start, at, dst, i)
        ret ok
    }
    if is_unicode(id) {
        let most = v.len / 2usize * 3usize
        let reserve_error = reserve(r, most)
        if reserve_error != ok { ret reserve_error }
        let start = r.used
        let (written, narrow_error) = narrow(v, r.buffer[start..start + most])
        if narrow_error != ok { ret refuse(r.conn, "SQL Server sent text that is not UTF-16", Failed) }
        put_text(r, start, start + written, dst, i)
        ret ok
    }
    if id == 167u8 || id == 175u8 || id == 35u8 { ret put_single_byte(r, col, v, dst, i) }
    if is_binary(id) { ret put_bytes_value(r, v, dst, i) }
    if id == 98u8 && v.len >= 2usize {
        // sql_variant: the base type, its properties, then the value as that type would send it.
        let base = v[0usize]
        let props = usize(v[1usize])
        if 2usize + props > v.len || base == 98u8 { ret refuse(r.conn, "SQL Server sent a sql_variant this client does not read", Failed) }
        var inner = Col { id: base, size: u32(v.len - 2usize - props), precision: 0u8, scale: 0u8, plp: false, collation: 0u64 }
        if is_decimal(base) && props >= 2usize {
            inner.precision = v[2usize]
            inner.scale = v[3usize]
        }
        if is_scaled(base) && props >= 1usize { inner.scale = v[2usize] }
        if is_collated(base) && props >= 5usize { inner.collation = le(v[2usize..7usize]) }
        ret decode(r, inner, v[2usize + props..], dst, i)
    }
    ret refuse(r.conn, "a result column has a type this client does not decode; CAST it in the query", Failed)
}

// --- the driver table

fn d_close(ctx: *void) -> err {
    let c = conn_of(ctx)
    c.active = nil
    ret hang_up(c)
}

// Keeps the text and counts its placeholders; nothing reaches the server until it runs.
fn d_prepare(ctx: *void, sql: str) -> (db.Statement, err) {
    let c = conn_of(ctx)
    var statement: db.Statement = zero
    let (stmts, stmt_error) = mem.alloc[Stmt](c.arena, 1usize)
    if stmt_error != ok { ret (statement, stmt_error) }
    let (kept, kept_error) = keep(c.arena, sql)
    if kept_error != ok { ret (statement, kept_error) }
    stmts[0usize] = Stmt { conn: c, sql: kept, placeholders: count_placeholders(sql), closed: false }
    clear(c)
    statement.ctx = mem.cast[*void](&stmts[0usize])
    ret (statement, ok)
}

fn d_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let (affected, execute_error) = execute_text(conn_of(ctx), sql, count_placeholders(sql), params)
    ret (affected, execute_error)
}

fn query_text(c: *Conn, sql: str, placeholders: usize, params: []const db.Parameter, statement: *Stmt) -> (db.Rows, err) {
    let run_error = run(c, sql, placeholders, params)
    if run_error != ok { ret (zero, run_error) }
    let (rows, rows_error) = open_reply(c, statement)
    ret (rows, rows_error)
}

fn d_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let (rows, rows_error) = query_text(conn_of(ctx), sql, count_placeholders(sql), params, nil)
    ret (rows, rows_error)
}

// One transaction at a time: a second `begin` is `Busy`.
fn d_begin(ctx: *void) -> (db.Transaction, err) {
    let c = conn_of(ctx)
    var transaction: db.Transaction = zero
    if c.active != nil { ret (transaction, refuse(c, "a row reader is still open on this connection", db.Busy)) }
    if c.in_transaction { ret (transaction, refuse(c, "a transaction is already open on this connection", db.Busy)) }
    let (txs, tx_error) = mem.alloc[Tx](c.arena, 1usize)
    if tx_error != ok { ret (transaction, tx_error) }
    let (ignored, begin_error) = execute_text(c, "BEGIN TRANSACTION", 0usize, zero)
    if begin_error != ok { ret (transaction, begin_error) }
    if !c.server_transaction { ret (transaction, protocol(c, "SQL Server began a transaction without naming it")) }
    c.in_transaction = true
    txs[0usize] = Tx { conn: c }
    transaction.ctx = mem.cast[*void](&txs[0usize])
    ret (transaction, ok)
}

// A reader of this statement still streaming is ended first, and answers `Closed` after.
fn d_statement_close(ctx: *void) -> err {
    let s = stmt_of(ctx)
    let c = s.conn
    if c.active != nil && c.active.statement == s {
        let r = c.active
        r.closed = true
        let close_error = d_rows_close(mem.cast[*void](r))
    }
    s.closed = true
    ret ok
}

fn d_statement_execute(ctx: *void, params: []const db.Parameter) -> (u64, err) {
    let s = stmt_of(ctx)
    if s.closed { ret (0u64, db.Closed) }
    let (affected, execute_error) = execute_text(s.conn, s.sql, s.placeholders, params)
    ret (affected, execute_error)
}

fn d_statement_query(ctx: *void, params: []const db.Parameter) -> (db.Rows, err) {
    let s = stmt_of(ctx)
    if s.closed { ret (zero, db.Closed) }
    let (rows, rows_error) = query_text(s.conn, s.sql, s.placeholders, params, s)
    ret (rows, rows_error)
}

fn d_rows_columns(ctx: *void) -> []const db.Column { ret reader_of(ctx).columns }

// Values are always copies into the reader's buffer: this is the table's entry for both readers.
fn d_rows_next(ctx: *void, dst: []db.Value) -> (bool, err) {
    let (more, next_error) = next_row(reader_of(ctx), dst)
    ret (more, next_error)
}

// The rest of the reply is read and discarded; a server error in it is not this call's.
fn d_rows_close(ctx: *void) -> err {
    let r = reader_of(ctx)
    if r.done { ret ok }
    let c = r.conn
    end_reader(r)
    let (ignored, rest_error) = finish(c, r.types)
    if c.broken { ret rest_error }
    clear(c)
    ret ok
}

fn live(c: *Conn) -> err {
    if !c.server_transaction { ret refuse(c, "SQL Server has already ended this transaction", Aborted) }
    ret ok
}

fn d_transaction_execute(ctx: *void, sql: str, params: []const db.Parameter) -> (u64, err) {
    let c = tx_of(ctx).conn
    let live_error = live(c)
    if live_error != ok { ret (0u64, live_error) }
    let (affected, execute_error) = execute_text(c, sql, count_placeholders(sql), params)
    ret (affected, execute_error)
}

fn d_transaction_query(ctx: *void, sql: str, params: []const db.Parameter) -> (db.Rows, err) {
    let c = tx_of(ctx).conn
    let live_error = live(c)
    if live_error != ok { ret (zero, live_error) }
    let (rows, rows_error) = query_text(c, sql, count_placeholders(sql), params, nil)
    ret (rows, rows_error)
}

fn end_active(c: *Conn) {
    if c.active != nil { let close_error = d_rows_close(mem.cast[*void](c.active)) }
}

// A COMMIT that fails is rolled back, because `e.db` has already closed the handle.
fn d_transaction_commit(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    end_active(c)
    c.in_transaction = false
    let live_error = live(c)
    if live_error != ok { ret live_error }
    let (ignored, commit_error) = execute_text(c, "COMMIT TRANSACTION", 0usize, zero)
    if commit_error != ok && c.server_transaction {
        let (undone, undo_error) = execute_text(c, "ROLLBACK TRANSACTION", 0usize, zero)
    }
    ret commit_error
}

fn d_transaction_rollback(ctx: *void) -> err {
    let c = tx_of(ctx).conn
    end_active(c)
    c.in_transaction = false
    if !c.server_transaction {
        clear(c)
        ret ok
    }
    let (ignored, rollback_error) = execute_text(c, "ROLLBACK TRANSACTION", 0usize, zero)
    ret rollback_error
}
