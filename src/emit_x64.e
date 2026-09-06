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

fn pack(buffer: *Buffer, destination: []u8) -> err {
    if buffer.count > destination.len { ret Capacity }
    var at = 0usize
    while at < buffer.count {
        destination[at] = u8(buffer.bytes[at])
        at += 1usize
    }
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

fn bit_and_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 33usize, destination, source)
}

fn bit_xor_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 49usize, destination, source)
}

fn bit_or_register(buffer: *Buffer, destination: usize, source: usize) -> err {
    ret binary_register(buffer, 9usize, destination, source)
}

fn extend_dividend_signed(buffer: *Buffer) -> err {
    try byte(buffer, 72usize)
    ret byte(buffer, 153usize)
}

fn extend_dividend_unsigned(buffer: *Buffer) -> err {
    ret binary_register(buffer, 49usize, 2usize, 2usize)
}

fn divide_register(buffer: *Buffer, divisor: usize, signed: bool) -> err {
    try check_register(divisor)
    var extension = 6usize
    if signed { extension = 7usize }
    try rex(buffer, extension, divisor)
    try byte(buffer, 247usize)
    ret modrm(buffer, extension, divisor)
}

fn and_immediate8(buffer: *Buffer, destination: usize, value: usize) -> err {
    try check_register(destination)
    if value > 255usize { ret InvalidByte }
    try rex(buffer, 4usize, destination)
    try byte(buffer, 131usize)
    try modrm(buffer, 4usize, destination)
    ret byte(buffer, value)
}

fn shift_register(buffer: *Buffer, destination: usize, left: bool, signed: bool) -> err {
    try check_register(destination)
    var extension = 5usize
    if left { extension = 4usize }
    if !left && signed { extension = 7usize }
    try rex(buffer, extension, destination)
    try byte(buffer, 211usize)
    ret modrm(buffer, extension, destination)
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

fn negate_register(buffer: *Buffer, value: usize) -> err {
    try check_register(value)
    try rex(buffer, 3usize, value)
    try byte(buffer, 247usize)
    ret modrm(buffer, 3usize, value)
}

fn bit_not_register(buffer: *Buffer, value: usize) -> err {
    try check_register(value)
    try rex(buffer, 2usize, value)
    try byte(buffer, 247usize)
    ret modrm(buffer, 2usize, value)
}

fn normalize_integer(buffer: *Buffer, destination: usize, source: usize, width: usize, signed: bool) -> err {
    try check_register(destination)
    try check_register(source)
    if width == 64usize {
        if destination != source { ret mov_register(buffer, destination, source) }
        ret ok
    }
    if width == 32usize {
        if signed {
            try rex(buffer, destination, source)
            try byte(buffer, 99usize)
            ret modrm(buffer, destination, source)
        }
        try byte(buffer, 64usize + destination / 8usize * 4usize + source / 8usize)
        try byte(buffer, 139usize)
        ret modrm(buffer, destination, source)
    }
    try rex(buffer, destination, source)
    try byte(buffer, 15usize)
    if width == 8usize {
        if signed { try byte(buffer, 190usize) } else { try byte(buffer, 182usize) }
        ret modrm(buffer, destination, source)
    }
    if width == 16usize {
        if signed { try byte(buffer, 191usize) } else { try byte(buffer, 183usize) }
        ret modrm(buffer, destination, source)
    }
    ret InvalidByte
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
    var scalar_storage: [64]usize = zero
    var scalar: Buffer = zero
    try init(&scalar, scalar_storage[..])
    try negate_register(&scalar, 0usize)
    try bit_not_register(&scalar, 9usize)
    try normalize_integer(&scalar, 10usize, 9usize, 32usize, true)
    try normalize_integer(&scalar, 9usize, 10usize, 8usize, false)
    try bit_and_register(&scalar, 9usize, 10usize)
    try bit_xor_register(&scalar, 9usize, 10usize)
    try bit_or_register(&scalar, 9usize, 10usize)
    try extend_dividend_signed(&scalar)
    try extend_dividend_unsigned(&scalar)
    try divide_register(&scalar, 11usize, true)
    try divide_register(&scalar, 11usize, false)
    try and_immediate8(&scalar, 1usize, 31usize)
    try shift_register(&scalar, 10usize, true, false)
    try shift_register(&scalar, 10usize, false, true)
    try shift_register(&scalar, 10usize, false, false)
    let scalar_expected = [46]usize{ 72usize, 247usize, 216usize, 73usize, 247usize, 209usize, 77usize, 99usize, 209usize, 77usize, 15usize, 182usize, 202usize, 77usize, 33usize, 209usize, 77usize, 49usize, 209usize, 77usize, 9usize, 209usize, 72usize, 153usize, 72usize, 49usize, 210usize, 73usize, 247usize, 251usize, 73usize, 247usize, 243usize, 72usize, 131usize, 225usize, 31usize, 73usize, 211usize, 226usize, 73usize, 211usize, 250usize, 73usize, 211usize, 234usize }
    if scalar.count != scalar_expected.len { ret InvalidRegister }
    at = 0usize
    while at < scalar_expected.len {
        if scalar.bytes[at] != scalar_expected[at] { ret InvalidRegister }
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
