// Deterministic x64 machine-code byte encoding shared by both host ABIs.

error Capacity
error InvalidByte
error InvalidRegister

type Buffer = struct {
    bytes: []usize,
    count: usize,
}

fn init(buffer: *Buffer, bytes: []usize) -> err {
    if bytes.len == 0usize { ret Capacity }
    buffer.bytes = bytes
    buffer.count = 0usize
    ret ok
}

fn byte(buffer: *Buffer, value: usize) -> err {
    if value > 255usize { ret InvalidByte }
    if buffer.count == buffer.bytes.len { ret Capacity }
    buffer.bytes[buffer.count] = value
    buffer.count += 1usize
    ret ok
}

fn little_u64(buffer: *Buffer, value: usize) -> err {
    var remaining = value
    var count = 0usize
    while count < 8usize {
        let octet = remaining % 256usize
        try byte(buffer, octet)
        remaining = remaining / 256usize
        count += 1usize
    }
    ret ok
}

fn check_register(index: usize) -> err {
    if index >= 16usize { ret InvalidRegister }
    ret ok
}

fn rex(buffer: *Buffer, reg: usize, rm: usize) -> err {
    try check_register(reg)
    try check_register(rm)
    let value = 72usize + reg / 8usize * 4usize + rm / 8usize
    ret byte(buffer, value)
}

fn modrm(buffer: *Buffer, reg: usize, rm: usize) -> err {
    let value = 192usize + reg % 8usize * 8usize + rm % 8usize
    ret byte(buffer, value)
}

fn mov_immediate(buffer: *Buffer, destination: usize, value: usize) -> err {
    try check_register(destination)
    try byte(buffer, 72usize + destination / 8usize)
    try byte(buffer, 184usize + destination % 8usize)
    ret little_u64(buffer, value)
}

fn binary_register(buffer: *Buffer, opcode: usize, destination: usize, source: usize) -> err {
    try rex(buffer, source, destination)
    try byte(buffer, opcode)
    ret modrm(buffer, source, destination)
}

fn mov_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 137usize, destination, source)
}

fn add_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 1usize, destination, source)
}

fn subtract_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 41usize, destination, source)
}

fn multiply_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    try rex(buffer, destination, source)
    try byte(buffer, 15usize)
    try byte(buffer, 175usize)
    ret modrm(buffer, destination, source)
}

fn return_instruction(buffer: *Buffer) -> err {
    ret byte(buffer, 195usize)
}

fn self_test() -> err {
    var storage: [64]usize = zero
    var buffer: Buffer = zero
    try init(&buffer, storage[..])
    try mov_immediate(&buffer, 0usize, 0x0102030405060708usize)
    try mov_register(&buffer, 9usize, 10usize)
    try add_register(&buffer, 9usize, 10usize)
    try subtract_register(&buffer, 9usize, 10usize)
    try multiply_register(&buffer, 9usize, 10usize)
    try return_instruction(&buffer)
    let expected = [24]usize{
        72usize, 184usize, 8usize, 7usize, 6usize, 5usize, 4usize, 3usize, 2usize, 1usize,
        77usize, 137usize, 209usize,
        77usize, 1usize, 209usize,
        77usize, 41usize, 209usize,
        77usize, 15usize, 175usize, 202usize,
        195usize,
    }
    if buffer.count != expected.len { ret InvalidRegister }
    var at = 0usize
    while at < expected.len {
        if buffer.bytes[at] != expected[at] { ret InvalidRegister }
        at += 1usize
    }
    ret ok
}
