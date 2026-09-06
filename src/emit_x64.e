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

fn little_u32(buffer: *Buffer, value: usize) -> err {
    var remaining = value
    var count = 0usize
    while count < 4usize {
        try byte(buffer, remaining % 256usize)
        remaining = remaining / 256usize
        count += 1usize
    }
    ret ok
}

fn patch_little_u32(buffer: *Buffer, at: usize, value: usize) -> err {
    if at + 4usize > buffer.count { ret Capacity }
    var remaining = value
    var offset = 0usize
    while offset < 4usize {
        buffer.bytes[at + offset] = remaining % 256usize
        remaining = remaining / 256usize
        offset += 1usize
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

fn compare_register(buffer: *Buffer, left: usize, right: usize) -> err {
    ret binary_register(buffer, 57usize, left, right)
}

fn set_condition(buffer: *Buffer, destination: usize, condition: usize) -> err {
    try check_register(destination)
    if condition >= 16usize { ret InvalidByte }
    try byte(buffer, 64usize + destination / 8usize)
    try byte(buffer, 15usize)
    try byte(buffer, 144usize + condition)
    ret byte(buffer, 192usize + destination % 8usize)
}

fn multiply_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    try rex(buffer, destination, source)
    try byte(buffer, 15usize)
    try byte(buffer, 175usize)
    ret modrm(buffer, destination, source)
}

fn frame_size(stack_slots: usize) -> usize {
    let bytes = stack_slots * 8usize
    let rounded = bytes + 15usize
    ret rounded / 16usize * 16usize
}

fn function_prologue(buffer: *Buffer, stack_slots: usize) -> err {
    try byte(buffer, 85usize)
    try mov_register(buffer, 5usize, 4usize)
    let bytes = frame_size(stack_slots)
    if bytes != 0usize {
        try byte(buffer, 72usize)
        try byte(buffer, 129usize)
        try byte(buffer, 236usize)
        try little_u32(buffer, bytes)
    }
    ret ok
}

fn function_epilogue(buffer: *Buffer) -> err {
    try mov_register(buffer, 4usize, 5usize)
    try byte(buffer, 93usize)
    ret return_instruction(buffer)
}

fn stack_displacement(slot: usize) -> usize {
    let next = slot + 1usize
    let magnitude = next * 8usize
    ret 4294967296usize - magnitude
}

fn load_stack(buffer: *Buffer, destination: usize, slot: usize) -> err {
    try check_register(destination)
    try byte(buffer, 72usize + destination / 8usize * 4usize)
    try byte(buffer, 139usize)
    try byte(buffer, 133usize + destination % 8usize * 8usize)
    ret little_u32(buffer, stack_displacement(slot))
}

fn store_stack(buffer: *Buffer, slot: usize, source: usize) -> err {
    try check_register(source)
    try byte(buffer, 72usize + source / 8usize * 4usize)
    try byte(buffer, 137usize)
    try byte(buffer, 133usize + source % 8usize * 8usize)
    ret little_u32(buffer, stack_displacement(slot))
}

fn test_register(buffer: *Buffer, value: usize) -> err {
    try rex(buffer, value, value)
    try byte(buffer, 133usize)
    ret modrm(buffer, value, value)
}

fn jump(buffer: *Buffer) -> (usize, err) {
    let displacement = buffer.count + 1usize
    let byte_error = byte(buffer, 233usize)
    if byte_error != ok { ret (0usize, byte_error) }
    let displacement_error = little_u32(buffer, 0usize)
    ret (displacement, displacement_error)
}

fn call(buffer: *Buffer) -> (usize, err) {
    let displacement = buffer.count + 1usize
    let byte_error = byte(buffer, 232usize)
    if byte_error != ok { ret (0usize, byte_error) }
    let displacement_error = little_u32(buffer, 0usize)
    ret (displacement, displacement_error)
}

fn jump_nonzero(buffer: *Buffer, value: usize) -> (usize, err) {
    let test_error = test_register(buffer, value)
    if test_error != ok { ret (0usize, test_error) }
    let first_error = byte(buffer, 15usize)
    if first_error != ok { ret (0usize, first_error) }
    let second_error = byte(buffer, 133usize)
    if second_error != ok { ret (0usize, second_error) }
    let displacement = buffer.count
    let displacement_error = little_u32(buffer, 0usize)
    ret (displacement, displacement_error)
}

fn patch_relative32(buffer: *Buffer, displacement_at: usize, destination: usize) -> err {
    let following = displacement_at + 4usize
    var displacement = 0usize
    if destination >= following {
        displacement = destination - following
    } else {
        let magnitude = following - destination
        displacement = 4294967296usize - magnitude
    }
    ret patch_little_u32(buffer, displacement_at, displacement)
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
    try compare_register(&buffer, 9usize, 10usize)
    try set_condition(&buffer, 9usize, 12usize)
    try return_instruction(&buffer)
    let expected = [31]usize{
        72usize, 184usize, 8usize, 7usize, 6usize, 5usize, 4usize, 3usize, 2usize, 1usize,
        77usize, 137usize, 209usize,
        77usize, 1usize, 209usize,
        77usize, 41usize, 209usize,
        77usize, 15usize, 175usize, 202usize,
        77usize, 57usize, 209usize,
        65usize, 15usize, 156usize, 193usize,
        195usize,
    }
    if buffer.count != expected.len { ret InvalidRegister }
    var at = 0usize
    while at < expected.len {
        if buffer.bytes[at] != expected[at] { ret InvalidRegister }
        at += 1usize
    }
    var frame_storage: [64]usize = zero
    var frame: Buffer = zero
    try init(&frame, frame_storage[..])
    try function_prologue(&frame, 2usize)
    try store_stack(&frame, 1usize, 10usize)
    try load_stack(&frame, 11usize, 1usize)
    try function_epilogue(&frame)
    if frame.count != 30usize { ret InvalidRegister }
    if frame.bytes[0usize] != 85usize || frame.bytes[4usize] != 72usize || frame.bytes[11usize] != 76usize || frame.bytes[18usize] != 76usize || frame.bytes[29usize] != 195usize { ret InvalidRegister }
    ret ok
}
