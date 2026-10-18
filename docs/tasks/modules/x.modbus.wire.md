# x.modbus.wire — 55 of 55 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/modbus/wire.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/modbus/wire.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.mem` | spec | `lib/e/mem.e` | 0 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
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
type Request = struct { function: u8, address: u16, count: u16, value: u16, and_mask: u16, or_mask: u16, read_address: u16, read_count: u16, data: []const u8 }
type Response = struct { function: u8, exception: u8, address: u16, count: u16, value: u16, and_mask: u16, or_mask: u16, data: []const u8 }
type Slave = struct { coils: []u8, discrete: []u8, holding: []u16, input: []u16 }

fn be16(b: []const u8, at: usize) -> u16
fn put16(b: []u8, at: usize, v: u16)
fn crc16(data: []const u8) -> u16
fn lrc(data: []const u8) -> u8
fn encode_read(dst: []u8, function: u8, address: u16, count: u16) -> (usize, err)
fn encode_write_single(dst: []u8, function: u8, address: u16, value: u16) -> (usize, err)
fn encode_write_coils(dst: []u8, address: u16, count: u16, packed: []const u8) -> (usize, err)
fn encode_write_registers(dst: []u8, address: u16, values: []const u16) -> (usize, err)
fn encode_mask_write(dst: []u8, address: u16, and_mask: u16, or_mask: u16) -> (usize, err)
fn encode_read_write(dst: []u8, read_address: u16, read_count: u16, write_address: u16, values: []const u16) -> (usize, err)
fn encode_exception(dst: []u8, function: u8, code: u8) -> (usize, err)
fn parse_request(pdu: []const u8) -> (Request, err)
fn parse_response(pdu: []const u8) -> (Response, err)
fn bit_at(data: []const u8, i: usize) -> bool
fn register_at(data: []const u8, i: usize) -> u16
fn tcp_frame(dst: []u8, transaction: u16, unit: u8, pdu: []const u8) -> (usize, err)
fn tcp_parse(buf: []const u8) -> (Frame, usize, err)
fn rtu_frame(dst: []u8, unit: u8, pdu: []const u8) -> (usize, err)
fn rtu_parse(buf: []const u8) -> (Frame, err)
fn hex_upper(v: u8) -> u8
fn hex_value(c: u8) -> (u8, bool)
fn ascii_frame(dst: []u8, unit: u8, pdu: []const u8) -> (usize, err)
fn ascii_parse(buf: []const u8, out: []u8) -> (Frame, err)
fn get_u32(regs: []const u16, at: usize, little: bool) -> u32
fn get_u64(regs: []const u16, at: usize, little: bool) -> u64
fn get_f32(regs: []const u16, at: usize, little: bool) -> f32
fn get_f64(regs: []const u16, at: usize, little: bool) -> f64
fn put_u32(regs: []u16, at: usize, v: u32, little: bool)
fn put_u64(regs: []u16, at: usize, v: u64, little: bool)
fn put_f32(regs: []u16, at: usize, v: f32, little: bool)
fn put_f64(regs: []u16, at: usize, v: f64, little: bool)
fn fail_pdu(dst: []u8, function: u8, code: u8) -> usize
fn slave_handle(s: *Slave, pdu: []const u8, dst: []u8) -> (usize, err)
```

Modbus (L151) over caller buffers, no transport. PDU encoders and request/response parsers for function codes 1, 2, 3, 4, 5, 6, 15, 16, 22 and 23 and the exception responses; the three framings (`tcp_frame`/`tcp_parse` with the MBAP header, `rtu_frame`/`rtu_parse` with CRC-16, `ascii_frame`/`ascii_parse` with LRC; `Truncated` until a TCP frame is whole, `BadChecksum`, `Invalid` for a non-zero protocol id or a length outside 2 to 254); typed register access (`get_*`/`put_*` for 32 and 64-bit integers and floats in either word order, `bit_at` and `register_at` over read data); and `slave_handle`, which executes a request against register banks in caller storage with the specification's exception order (unknown function 1, a quantity or value out of limits 3, an address range outside the bank 2) and write-before-read for function 23. A client keeps its own transaction numbers and a transport reads bytes; device discovery stays with L086. Checked against pymodbus (its request and response classes, its socket, RTU and ASCII framers, its CRC and LRC helpers and register conversions) and, for the slave, against an independent reference slave written from the specification over 222 vectors on both hosts (D2647). Not done: the file-record, FIFO, diagnostic and device-identification function codes, the serial port and TCP socket loops, RTU frame delimiting by inter-character silence, broadcast and multi-unit gateways, OPC UA and Siemens S7 (separate slices).

## Missing declarations

- [ ] `Truncated`
- [ ] `Invalid`
- [ ] `BadChecksum`
- [ ] `TooSmall`
- [ ] `READ_COILS`
- [ ] `READ_DISCRETE_INPUTS`
- [ ] `READ_HOLDING_REGISTERS`
- [ ] `READ_INPUT_REGISTERS`
- [ ] `WRITE_SINGLE_COIL`
- [ ] `WRITE_SINGLE_REGISTER`
- [ ] `WRITE_MULTIPLE_COILS`
- [ ] `WRITE_MULTIPLE_REGISTERS`
- [ ] `MASK_WRITE_REGISTER`
- [ ] `READ_WRITE_REGISTERS`
- [ ] `ILLEGAL_FUNCTION`
- [ ] `ILLEGAL_ADDRESS`
- [ ] `ILLEGAL_VALUE`
- [ ] `DEVICE_FAILURE`
- [ ] `Frame`
- [ ] `Request`
- [ ] `Response`
- [ ] `Slave`
- [ ] `be16`
- [ ] `put16`
- [ ] `crc16`
- [ ] `lrc`
- [ ] `encode_read`
- [ ] `encode_write_single`
- [ ] `encode_write_coils`
- [ ] `encode_write_registers`
- [ ] `encode_mask_write`
- [ ] `encode_read_write`
- [ ] `encode_exception`
- [ ] `parse_request`
- [ ] `parse_response`
- [ ] `bit_at`
- [ ] `register_at`
- [ ] `tcp_frame`
- [ ] `tcp_parse`
- [ ] `rtu_frame`
- [ ] `rtu_parse`
- [ ] `hex_upper`
- [ ] `hex_value`
- [ ] `ascii_frame`
- [ ] `ascii_parse`
- [ ] `get_u32`
- [ ] `get_u64`
- [ ] `get_f32`
- [ ] `get_f64`
- [ ] `put_u32`
- [ ] `put_u64`
- [ ] `put_f32`
- [ ] `put_f64`
- [ ] `fail_pdu`
- [ ] `slave_handle`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/modbus/wire.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/modbus_wire/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 55.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
