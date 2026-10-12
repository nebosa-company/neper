// Modbus (L151): the application protocol over caller buffers, no transport. Function codes 1, 2, 3, 4, 5, 6, 15,
// 16, 22 and 23 as request encoders and request/response parsers over the PDU, the exception responses, the three
// framings (TCP's MBAP header, RTU with CRC-16, ASCII with LRC), typed register access (16, 32 and 64-bit integers
// and floats across consecutive registers in either word order), and a slave model that executes a request against
// register banks in caller storage with the specification's exception order (function, then value, then address).
// A client keeps its own transaction numbers; a transport reads bytes (a serial port or a TCP socket) and hands whole
// frames in. OPC UA and Siemens S7 are separate slices (L151 follow-ons).
//
// Memory: parsers borrow the input; encoders write into the buffer given; the slave's banks are the caller's.
use e.mem

error Truncated
error Invalid
error BadChecksum
error TooSmall

const READ_COILS: u8 = 1u8
const READ_DISCRETE_INPUTS: u8 = 2u8
const READ_HOLDING_REGISTERS: u8 = 3u8
const READ_INPUT_REGISTERS: u8 = 4u8
const WRITE_SINGLE_COIL: u8 = 5u8
const WRITE_SINGLE_REGISTER: u8 = 6u8
const WRITE_MULTIPLE_COILS: u8 = 15u8
const WRITE_MULTIPLE_REGISTERS: u8 = 16u8
const MASK_WRITE_REGISTER: u8 = 22u8
const READ_WRITE_REGISTERS: u8 = 23u8

const ILLEGAL_FUNCTION: u8 = 1u8
const ILLEGAL_ADDRESS: u8 = 2u8
const ILLEGAL_VALUE: u8 = 3u8
const DEVICE_FAILURE: u8 = 4u8

type Frame = struct { transaction: u16, unit: u8, pdu: []const u8 }
// One parsed request. `data` is the packed coil bytes or big-endian register bytes of a write.
type Request = struct { function: u8, address: u16, count: u16, value: u16, and_mask: u16, or_mask: u16, read_address: u16, read_count: u16, data: []const u8 }
// One parsed response; `exception` is nonzero for an exception response (and `function` the original code).
type Response = struct { function: u8, exception: u8, address: u16, count: u16, value: u16, and_mask: u16, or_mask: u16, data: []const u8 }
type Slave = struct { coils: []u8, discrete: []u8, holding: []u16, input: []u16 }

fn be16(b: []const u8, at: usize) -> u16 { ret (u16(b[at]) << 8u16) | u16(b[at + 1usize]) }

fn put16(b: []u8, at: usize, v: u16) {
    b[at] = u8(v >> 8u16)
    b[at + 1usize] = u8(v & 255u16)
}

// --- checksums ---------------------------------------------------------------------------------------------------

// CRC-16/MODBUS (polynomial 0xA001 reflected, initial 0xFFFF).
fn crc16(data: []const u8) -> u16 {
    var crc = 65535u16
    var i = 0usize
    while i < data.len {
        crc = crc ^ u16(data[i])
        var bit = 0u8
        while bit < 8u8 {
            if (crc & 1u16) != 0u16 {
                crc = (crc >> 1u16) ^ 40961u16
            } else {
                crc = crc >> 1u16
            }
            bit += 1u8
        }
        i += 1usize
    }
    ret crc
}

// The ASCII framing's longitudinal redundancy check: the two's complement of the byte sum.
fn lrc(data: []const u8) -> u8 {
    var sum = 0u32
    var i = 0usize
    while i < data.len {
        sum += u32(data[i])
        i += 1usize
    }
    ret u8((256u32 - (sum & 255u32)) & 255u32)
}

// --- PDU encoders ------------------------------------------------------------------------------------------------

fn encode_read(dst: []u8, function: u8, address: u16, count: u16) -> (usize, err) {
    if dst.len < 5usize { ret (0usize, TooSmall) }
    dst[0usize] = function
    put16(dst, 1usize, address)
    put16(dst, 3usize, count)
    ret (5usize, ok)
}

// Write single coil (5, `value` 0xFF00 on or 0x0000 off) or single register (6).
fn encode_write_single(dst: []u8, function: u8, address: u16, value: u16) -> (usize, err) {
    if dst.len < 5usize { ret (0usize, TooSmall) }
    dst[0usize] = function
    put16(dst, 1usize, address)
    put16(dst, 3usize, value)
    ret (5usize, ok)
}

// Write multiple coils: `packed` holds the bits, least significant bit of the first byte first.
fn encode_write_coils(dst: []u8, address: u16, count: u16, packed: []const u8) -> (usize, err) {
    let bytes = (usize(count) + 7usize) / 8usize
    if packed.len != bytes { ret (0usize, Invalid) }
    if dst.len < 6usize + bytes { ret (0usize, TooSmall) }
    dst[0usize] = WRITE_MULTIPLE_COILS
    put16(dst, 1usize, address)
    put16(dst, 3usize, count)
    dst[5usize] = u8(bytes)
    mem.copy[u8](dst[6usize..6usize + bytes], packed)
    ret (6usize + bytes, ok)
}

fn encode_write_registers(dst: []u8, address: u16, values: []const u16) -> (usize, err) {
    if dst.len < 6usize + values.len * 2usize { ret (0usize, TooSmall) }
    dst[0usize] = WRITE_MULTIPLE_REGISTERS
    put16(dst, 1usize, address)
    put16(dst, 3usize, u16(values.len))
    dst[5usize] = u8(values.len * 2usize)
    var i = 0usize
    while i < values.len {
        put16(dst, 6usize + i * 2usize, values[i])
        i += 1usize
    }
    ret (6usize + values.len * 2usize, ok)
}

fn encode_mask_write(dst: []u8, address: u16, and_mask: u16, or_mask: u16) -> (usize, err) {
    if dst.len < 7usize { ret (0usize, TooSmall) }
    dst[0usize] = MASK_WRITE_REGISTER
    put16(dst, 1usize, address)
    put16(dst, 3usize, and_mask)
    put16(dst, 5usize, or_mask)
    ret (7usize, ok)
}

fn encode_read_write(dst: []u8, read_address: u16, read_count: u16, write_address: u16, values: []const u16) -> (usize, err) {
    if dst.len < 10usize + values.len * 2usize { ret (0usize, TooSmall) }
    dst[0usize] = READ_WRITE_REGISTERS
    put16(dst, 1usize, read_address)
    put16(dst, 3usize, read_count)
    put16(dst, 5usize, write_address)
    put16(dst, 7usize, u16(values.len))
    dst[9usize] = u8(values.len * 2usize)
    var i = 0usize
    while i < values.len {
        put16(dst, 10usize + i * 2usize, values[i])
        i += 1usize
    }
    ret (10usize + values.len * 2usize, ok)
}

fn encode_exception(dst: []u8, function: u8, code: u8) -> (usize, err) {
    if dst.len < 2usize { ret (0usize, TooSmall) }
    dst[0usize] = function | 128u8
    dst[1usize] = code
    ret (2usize, ok)
}

// --- PDU parsers -------------------------------------------------------------------------------------------------

// A request PDU (what a slave receives). Lengths are checked against the function's layout; a byte count that does
// not match the quantity is left to the slave (it answers an exception), so `parse_request` only refuses what cannot
// be read at all.
fn parse_request(pdu: []const u8) -> (Request, err) {
    var r: Request = zero
    if pdu.len < 1usize { ret (r, Truncated) }
    r.function = pdu[0usize]
    let f = r.function
    if f == READ_COILS || f == READ_DISCRETE_INPUTS || f == READ_HOLDING_REGISTERS || f == READ_INPUT_REGISTERS {
        if pdu.len != 5usize { ret (r, Invalid) }
        r.address = be16(pdu, 1usize)
        r.count = be16(pdu, 3usize)
        ret (r, ok)
    }
    if f == WRITE_SINGLE_COIL || f == WRITE_SINGLE_REGISTER {
        if pdu.len != 5usize { ret (r, Invalid) }
        r.address = be16(pdu, 1usize)
        r.value = be16(pdu, 3usize)
        ret (r, ok)
    }
    if f == WRITE_MULTIPLE_COILS || f == WRITE_MULTIPLE_REGISTERS {
        if pdu.len < 6usize { ret (r, Truncated) }
        r.address = be16(pdu, 1usize)
        r.count = be16(pdu, 3usize)
        r.value = u16(pdu[5usize])
        if pdu.len != 6usize + usize(pdu[5usize]) { ret (r, Invalid) }
        r.data = pdu[6usize..]
        ret (r, ok)
    }
    if f == MASK_WRITE_REGISTER {
        if pdu.len != 7usize { ret (r, Invalid) }
        r.address = be16(pdu, 1usize)
        r.and_mask = be16(pdu, 3usize)
        r.or_mask = be16(pdu, 5usize)
        ret (r, ok)
    }
    if f == READ_WRITE_REGISTERS {
        if pdu.len < 10usize { ret (r, Truncated) }
        r.read_address = be16(pdu, 1usize)
        r.read_count = be16(pdu, 3usize)
        r.address = be16(pdu, 5usize)
        r.count = be16(pdu, 7usize)
        r.value = u16(pdu[9usize])
        if pdu.len != 10usize + usize(pdu[9usize]) { ret (r, Invalid) }
        r.data = pdu[10usize..]
        ret (r, ok)
    }
    ret (r, Invalid)
}

// A response PDU (what a master receives): an exception (function code with the high bit set), or the layout of the
// original function. For reads `data` is the packed bits or register bytes; for echoes the fields repeat the request.
fn parse_response(pdu: []const u8) -> (Response, err) {
    var r: Response = zero
    if pdu.len < 2usize { ret (r, Truncated) }
    if pdu[0usize] >= 128u8 {
        if pdu.len != 2usize { ret (r, Invalid) }
        r.function = pdu[0usize] & 127u8
        r.exception = pdu[1usize]
        ret (r, ok)
    }
    r.function = pdu[0usize]
    let f = r.function
    if f == READ_COILS || f == READ_DISCRETE_INPUTS || f == READ_HOLDING_REGISTERS || f == READ_INPUT_REGISTERS || f == READ_WRITE_REGISTERS {
        let n = usize(pdu[1usize])
        if pdu.len != 2usize + n { ret (r, Invalid) }
        if f != READ_COILS && f != READ_DISCRETE_INPUTS && n % 2usize != 0usize { ret (r, Invalid) }
        r.data = pdu[2usize..]
        ret (r, ok)
    }
    if f == WRITE_SINGLE_COIL || f == WRITE_SINGLE_REGISTER {
        if pdu.len != 5usize { ret (r, Invalid) }
        r.address = be16(pdu, 1usize)
        r.value = be16(pdu, 3usize)
        ret (r, ok)
    }
    if f == WRITE_MULTIPLE_COILS || f == WRITE_MULTIPLE_REGISTERS {
        if pdu.len != 5usize { ret (r, Invalid) }
        r.address = be16(pdu, 1usize)
        r.count = be16(pdu, 3usize)
        ret (r, ok)
    }
    if f == MASK_WRITE_REGISTER {
        if pdu.len != 7usize { ret (r, Invalid) }
        r.address = be16(pdu, 1usize)
        r.and_mask = be16(pdu, 3usize)
        r.or_mask = be16(pdu, 5usize)
        ret (r, ok)
    }
    ret (r, Invalid)
}

// Coil `i` of packed read data.
fn bit_at(data: []const u8, i: usize) -> bool {
    ret ((data[i / 8usize] >> u8(i % 8usize)) & 1u8) != 0u8
}

// Register `i` of read data (big-endian pairs).
fn register_at(data: []const u8, i: usize) -> u16 { ret be16(data, i * 2usize) }

// --- framing -----------------------------------------------------------------------------------------------------

// MBAP: transaction (2), protocol 0 (2), length (2: unit and PDU), unit (1), then the PDU.
fn tcp_frame(dst: []u8, transaction: u16, unit: u8, pdu: []const u8) -> (usize, err) {
    if pdu.len < 1usize || pdu.len > 253usize { ret (0usize, Invalid) }
    if dst.len < 7usize + pdu.len { ret (0usize, TooSmall) }
    put16(dst, 0usize, transaction)
    put16(dst, 2usize, 0u16)
    put16(dst, 4usize, u16(pdu.len + 1usize))
    dst[6usize] = unit
    mem.copy[u8](dst[7usize..7usize + pdu.len], pdu)
    ret (7usize + pdu.len, ok)
}

// One TCP frame at the front of `buf` and the bytes it used; `Truncated` until it is all there.
fn tcp_parse(buf: []const u8) -> (Frame, usize, err) {
    var f: Frame = zero
    if buf.len < 7usize { ret (f, 0usize, Truncated) }
    if be16(buf, 2usize) != 0u16 { ret (f, 0usize, Invalid) }
    let length = usize(be16(buf, 4usize))
    if length < 2usize || length > 254usize { ret (f, 0usize, Invalid) }
    if buf.len < 6usize + length { ret (f, 0usize, Truncated) }
    f.transaction = be16(buf, 0usize)
    f.unit = buf[6usize]
    f.pdu = buf[7usize..6usize + length]
    ret (f, 6usize + length, ok)
}

// RTU: address, PDU, CRC-16 low byte first.
fn rtu_frame(dst: []u8, unit: u8, pdu: []const u8) -> (usize, err) {
    if pdu.len < 1usize || pdu.len > 253usize { ret (0usize, Invalid) }
    if dst.len < 3usize + pdu.len { ret (0usize, TooSmall) }
    dst[0usize] = unit
    mem.copy[u8](dst[1usize..1usize + pdu.len], pdu)
    let crc = crc16(dst[0usize..1usize + pdu.len])
    dst[1usize + pdu.len] = u8(crc & 255u16)
    dst[2usize + pdu.len] = u8(crc >> 8u16)
    ret (3usize + pdu.len, ok)
}

// A whole RTU frame (the transport delimits it by silence); `BadChecksum` when the CRC does not match.
fn rtu_parse(buf: []const u8) -> (Frame, err) {
    var f: Frame = zero
    if buf.len < 4usize { ret (f, Truncated) }
    if buf.len > 256usize { ret (f, Invalid) }
    let crc = crc16(buf[0usize..buf.len - 2usize])
    if u16(buf[buf.len - 2usize]) != (crc & 255u16) || u16(buf[buf.len - 1usize]) != (crc >> 8u16) { ret (f, BadChecksum) }
    f.unit = buf[0usize]
    f.pdu = buf[1usize..buf.len - 2usize]
    ret (f, ok)
}

fn hex_upper(v: u8) -> u8 {
    if v < 10u8 { ret 48u8 + v }
    ret 55u8 + v
}

fn hex_value(c: u8) -> (u8, bool) {
    if c >= 48u8 && c <= 57u8 { ret (c - 48u8, true) }
    if c >= 65u8 && c <= 70u8 { ret (c - 55u8, true) }
    if c >= 97u8 && c <= 102u8 { ret (c - 87u8, true) }
    ret (0u8, false)
}

// ASCII: `:`, the unit, PDU and LRC as upper-case hex pairs, CR LF.
fn ascii_frame(dst: []u8, unit: u8, pdu: []const u8) -> (usize, err) {
    if pdu.len < 1usize || pdu.len > 253usize { ret (0usize, Invalid) }
    let n = 1usize + (pdu.len + 2usize) * 2usize + 2usize
    if dst.len < n { ret (0usize, TooSmall) }
    var raw: [256]u8 = zero
    raw[0usize] = unit
    mem.copy[u8](raw[1usize..1usize + pdu.len], pdu)
    let check = lrc(raw[0usize..1usize + pdu.len])
    raw[1usize + pdu.len] = check
    dst[0usize] = 58u8
    var i = 0usize
    while i < pdu.len + 2usize {
        dst[1usize + i * 2usize] = hex_upper(raw[i] >> 4u8)
        dst[2usize + i * 2usize] = hex_upper(raw[i] & 15u8)
        i += 1usize
    }
    dst[n - 2usize] = 13u8
    dst[n - 1usize] = 10u8
    ret (n, ok)
}

// A whole ASCII frame (`:` through CR LF); the PDU is decoded into `out`.
fn ascii_parse(buf: []const u8, out: []u8) -> (Frame, err) {
    var f: Frame = zero
    if buf.len < 9usize || buf[0usize] != 58u8 { ret (f, Invalid) }
    if buf[buf.len - 2usize] != 13u8 || buf[buf.len - 1usize] != 10u8 { ret (f, Invalid) }
    let digits = buf.len - 3usize
    if digits % 2usize != 0usize { ret (f, Invalid) }
    let n = digits / 2usize
    if n < 3usize || n > out.len { ret (f, Invalid) }
    var i = 0usize
    while i < n {
        let (hi, hi_ok) = hex_value(buf[1usize + i * 2usize])
        let (lo, lo_ok) = hex_value(buf[2usize + i * 2usize])
        if !hi_ok || !lo_ok { ret (f, Invalid) }
        out[i] = (hi << 4u8) | lo
        i += 1usize
    }
    if lrc(out[0usize..n - 1usize]) != out[n - 1usize] { ret (f, BadChecksum) }
    f.unit = out[0usize]
    f.pdu = out[1usize..n - 1usize]
    ret (f, ok)
}

// --- typed registers ---------------------------------------------------------------------------------------------

// A 32-bit value from two registers, the high word first unless `little`.
fn get_u32(regs: []const u16, at: usize, little: bool) -> u32 {
    if little { ret (u32(regs[at + 1usize]) << 16u32) | u32(regs[at]) }
    ret (u32(regs[at]) << 16u32) | u32(regs[at + 1usize])
}

fn get_u64(regs: []const u16, at: usize, little: bool) -> u64 {
    if little {
        ret (u64(regs[at + 3usize]) << 48u64) | (u64(regs[at + 2usize]) << 32u64) | (u64(regs[at + 1usize]) << 16u64) | u64(regs[at])
    }
    ret (u64(regs[at]) << 48u64) | (u64(regs[at + 1usize]) << 32u64) | (u64(regs[at + 2usize]) << 16u64) | u64(regs[at + 3usize])
}

fn get_f32(regs: []const u16, at: usize, little: bool) -> f32 { ret mem.bitcast[f32](get_u32(regs, at, little)) }

fn get_f64(regs: []const u16, at: usize, little: bool) -> f64 { ret mem.bitcast[f64](get_u64(regs, at, little)) }

fn put_u32(regs: []u16, at: usize, v: u32, little: bool) {
    let hi = u16(v >> 16u32)
    let lo = u16(v & 65535u32)
    if little {
        regs[at] = lo
        regs[at + 1usize] = hi
    } else {
        regs[at] = hi
        regs[at + 1usize] = lo
    }
}

fn put_u64(regs: []u16, at: usize, v: u64, little: bool) {
    var words: [4]u16 = zero
    words[0usize] = u16(v >> 48u64)
    words[1usize] = u16((v >> 32u64) & 65535u64)
    words[2usize] = u16((v >> 16u64) & 65535u64)
    words[3usize] = u16(v & 65535u64)
    var i = 0usize
    while i < 4usize {
        if little {
            regs[at + i] = words[3usize - i]
        } else {
            regs[at + i] = words[i]
        }
        i += 1usize
    }
}

fn put_f32(regs: []u16, at: usize, v: f32, little: bool) { put_u32(regs, at, mem.bitcast[u32](v), little) }

fn put_f64(regs: []u16, at: usize, v: f64, little: bool) { put_u64(regs, at, mem.bitcast[u64](v), little) }

// --- slave -------------------------------------------------------------------------------------------------------

// The two bytes of an exception response (`dst` holds at least two); the count.
fn fail_pdu(dst: []u8, function: u8, code: u8) -> usize {
    dst[0usize] = function | 128u8
    dst[1usize] = code
    ret 2usize
}

// Execute one request PDU against the banks and write the response PDU. Exceptions follow the specification's
// order: an unknown function is 1, a quantity or value outside its limits is 3, an address range outside the bank
// is 2. A write happens before the read of a read/write request.
fn slave_handle(s: *Slave, pdu: []const u8, dst: []u8) -> (usize, err) {
    if dst.len < 2usize { ret (0usize, TooSmall) }
    let (r, parse_error) = parse_request(pdu)
    if parse_error != ok {
        if pdu.len == 0usize { ret (0usize, parse_error) }
        let f0 = pdu[0usize]
        let known = f0 == READ_COILS || f0 == READ_DISCRETE_INPUTS || f0 == READ_HOLDING_REGISTERS || f0 == READ_INPUT_REGISTERS || f0 == WRITE_SINGLE_COIL || f0 == WRITE_SINGLE_REGISTER || f0 == WRITE_MULTIPLE_COILS || f0 == WRITE_MULTIPLE_REGISTERS || f0 == MASK_WRITE_REGISTER || f0 == READ_WRITE_REGISTERS
        if !known { ret (fail_pdu(dst, f0, ILLEGAL_FUNCTION), ok) }
        ret (fail_pdu(dst, f0, ILLEGAL_VALUE), ok)
    }
    let f = r.function
    if f == READ_COILS || f == READ_DISCRETE_INPUTS {
        if r.count < 1u16 || r.count > 2000u16 { ret (fail_pdu(dst, f, ILLEGAL_VALUE), ok) }
        var bank = s.coils
        if f == READ_DISCRETE_INPUTS { bank = s.discrete }
        if usize(r.address) + usize(r.count) > bank.len { ret (fail_pdu(dst, f, ILLEGAL_ADDRESS), ok) }
        let bytes = (usize(r.count) + 7usize) / 8usize
        if dst.len < 2usize + bytes { ret (0usize, TooSmall) }
        dst[0usize] = f
        dst[1usize] = u8(bytes)
        var b = 0usize
        while b < bytes {
            dst[2usize + b] = 0u8
            b += 1usize
        }
        var i = 0usize
        while i < usize(r.count) {
            if bank[usize(r.address) + i] != 0u8 { dst[2usize + i / 8usize] = dst[2usize + i / 8usize] | (1u8 << u8(i % 8usize)) }
            i += 1usize
        }
        ret (2usize + bytes, ok)
    }
    if f == READ_HOLDING_REGISTERS || f == READ_INPUT_REGISTERS {
        if r.count < 1u16 || r.count > 125u16 { ret (fail_pdu(dst, f, ILLEGAL_VALUE), ok) }
        var bank = s.holding
        if f == READ_INPUT_REGISTERS { bank = s.input }
        if usize(r.address) + usize(r.count) > bank.len { ret (fail_pdu(dst, f, ILLEGAL_ADDRESS), ok) }
        let bytes = usize(r.count) * 2usize
        if dst.len < 2usize + bytes { ret (0usize, TooSmall) }
        dst[0usize] = f
        dst[1usize] = u8(bytes)
        var i = 0usize
        while i < usize(r.count) {
            put16(dst, 2usize + i * 2usize, bank[usize(r.address) + i])
            i += 1usize
        }
        ret (2usize + bytes, ok)
    }
    if f == WRITE_SINGLE_COIL {
        if r.value != 0u16 && r.value != 65280u16 { ret (fail_pdu(dst, f, ILLEGAL_VALUE), ok) }
        if usize(r.address) >= s.coils.len { ret (fail_pdu(dst, f, ILLEGAL_ADDRESS), ok) }
        if r.value == 65280u16 {
            s.coils[usize(r.address)] = 1u8
        } else {
            s.coils[usize(r.address)] = 0u8
        }
        if dst.len < 5usize { ret (0usize, TooSmall) }
        mem.copy[u8](dst[0usize..5usize], pdu)
        ret (5usize, ok)
    }
    if f == WRITE_SINGLE_REGISTER {
        if usize(r.address) >= s.holding.len { ret (fail_pdu(dst, f, ILLEGAL_ADDRESS), ok) }
        s.holding[usize(r.address)] = r.value
        if dst.len < 5usize { ret (0usize, TooSmall) }
        mem.copy[u8](dst[0usize..5usize], pdu)
        ret (5usize, ok)
    }
    if f == WRITE_MULTIPLE_COILS {
        let bytes = (usize(r.count) + 7usize) / 8usize
        if r.count < 1u16 || r.count > 1968u16 || usize(r.value) != bytes || r.data.len != bytes { ret (fail_pdu(dst, f, ILLEGAL_VALUE), ok) }
        if usize(r.address) + usize(r.count) > s.coils.len { ret (fail_pdu(dst, f, ILLEGAL_ADDRESS), ok) }
        var i = 0usize
        while i < usize(r.count) {
            if ((r.data[i / 8usize] >> u8(i % 8usize)) & 1u8) != 0u8 {
                s.coils[usize(r.address) + i] = 1u8
            } else {
                s.coils[usize(r.address) + i] = 0u8
            }
            i += 1usize
        }
        if dst.len < 5usize { ret (0usize, TooSmall) }
        dst[0usize] = f
        put16(dst, 1usize, r.address)
        put16(dst, 3usize, r.count)
        ret (5usize, ok)
    }
    if f == WRITE_MULTIPLE_REGISTERS {
        if r.count < 1u16 || r.count > 123u16 || usize(r.value) != usize(r.count) * 2usize || r.data.len != usize(r.count) * 2usize { ret (fail_pdu(dst, f, ILLEGAL_VALUE), ok) }
        if usize(r.address) + usize(r.count) > s.holding.len { ret (fail_pdu(dst, f, ILLEGAL_ADDRESS), ok) }
        var i = 0usize
        while i < usize(r.count) {
            s.holding[usize(r.address) + i] = be16(r.data, i * 2usize)
            i += 1usize
        }
        if dst.len < 5usize { ret (0usize, TooSmall) }
        dst[0usize] = f
        put16(dst, 1usize, r.address)
        put16(dst, 3usize, r.count)
        ret (5usize, ok)
    }
    if f == MASK_WRITE_REGISTER {
        if usize(r.address) >= s.holding.len { ret (fail_pdu(dst, f, ILLEGAL_ADDRESS), ok) }
        let current = s.holding[usize(r.address)]
        s.holding[usize(r.address)] = (current & r.and_mask) | (r.or_mask & ~r.and_mask)
        if dst.len < 7usize { ret (0usize, TooSmall) }
        mem.copy[u8](dst[0usize..7usize], pdu)
        ret (7usize, ok)
    }
    // READ_WRITE_REGISTERS
    if r.read_count < 1u16 || r.read_count > 125u16 || r.count < 1u16 || r.count > 121u16 || usize(r.value) != usize(r.count) * 2usize || r.data.len != usize(r.count) * 2usize { ret (fail_pdu(dst, f, ILLEGAL_VALUE), ok) }
    if usize(r.read_address) + usize(r.read_count) > s.holding.len || usize(r.address) + usize(r.count) > s.holding.len { ret (fail_pdu(dst, f, ILLEGAL_ADDRESS), ok) }
    var w = 0usize
    while w < usize(r.count) {
        s.holding[usize(r.address) + w] = be16(r.data, w * 2usize)
        w += 1usize
    }
    let bytes = usize(r.read_count) * 2usize
    if dst.len < 2usize + bytes { ret (0usize, TooSmall) }
    dst[0usize] = f
    dst[1usize] = u8(bytes)
    var i = 0usize
    while i < usize(r.read_count) {
        put16(dst, 2usize + i * 2usize, s.holding[usize(r.read_address) + i])
        i += 1usize
    }
    ret (2usize + bytes, ok)
}
