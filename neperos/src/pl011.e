// The Arm PL011 UART (DDI 0183), the console of QEMU's `virt`: a byte goes to the data
// register once the transmit FIFO has room. The line settings stay as the loader left
// them; `enable` only turns the UART and its transmitter and receiver on. A newline goes
// out as CR LF.
use e.os

const UARTDR: usize = 0usize
const UARTFR: usize = 24usize
const UARTCR: usize = 48usize
const FR_TXFF: u32 = 32u32
// UARTEN, TXE and RXE.
const CR_ON: u32 = 769u32

fn enable(base: usize) {
    os.store32(base + UARTCR, os.load32(base + UARTCR) | CR_ON)
}

fn put(base: usize, byte: u8) {
    while (os.load32(base + UARTFR) & FR_TXFF) != 0u32 {}
    os.store32(base + UARTDR, u32(byte))
}

fn write(base: usize, bytes: str) {
    for byte in bytes {
        if byte == 10u8 { put(base, 13u8) }
        put(base, byte)
    }
}
