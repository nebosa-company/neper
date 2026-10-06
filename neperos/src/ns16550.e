// The 8250/ns16550 UART, the console of crosvm's AVF guest (D2144). crosvm's device tree names
// it `compatible = "ns16550a"` with `reg = <addr size>` and no `reg-shift`, so its registers are
// one byte apart (shift 0): the transmit-holding register at offset 0 and the line-status
// register at offset 5, whose bit 5 (THRE) is set when the holding register can take another
// byte. The base and the shift come from the device tree, never hard-coded, so the same driver
// serves any 8250 layout. A newline goes out as CR LF, as the PL011 driver does. The VMM leaves
// the line configured, so there is nothing to enable before transmitting.
use e.os

const THR: usize = 0usize
const LSR: usize = 5usize
const LSR_THRE: u8 = 32u8

fn put(base: usize, shift: usize, byte: u8) {
    while (os.load8(base + (LSR << shift)) & LSR_THRE) == 0u8 {}
    os.store8(base + (THR << shift), byte)
}

fn write(base: usize, shift: usize, bytes: str) {
    for byte in bytes {
        if byte == 10u8 { put(base, shift, 13u8) }
        put(base, shift, byte)
    }
}
