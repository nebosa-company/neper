// The modern virtio-pci transport (virtio 1.x, D2131): a virtio device exposes its
// registers through PCI capabilities that name a BAR and an offset. NeperOS assigns the
// device a BAR in the 32-bit MMIO window, walks the capabilities to find the common
// configuration, the notify region and the ISR, negotiates VIRTIO_F_VERSION_1, builds one
// split virtqueue in its own RAM (identity-mapped, so a virtual address is the physical one
// the device DMAs to), and drives it. The entropy device fills a buffer with random bytes.
use e.os
use pci

error NoCapabilities
error NoQueue
error FeaturesRejected
error NoData
error BlockStatus
error BlockMismatch
error PoolExhausted
error GpuError

// Common-configuration field offsets (virtio 1.x 4.1.4.3).
const DEVICE_FEATURE_SELECT: usize = 0usize
const DEVICE_FEATURE: usize = 4usize
const DRIVER_FEATURE_SELECT: usize = 8usize
const DRIVER_FEATURE: usize = 12usize
const DEVICE_STATUS: usize = 20usize
const QUEUE_SELECT: usize = 22usize
const QUEUE_SIZE: usize = 24usize
const QUEUE_ENABLE: usize = 28usize
const QUEUE_NOTIFY_OFF: usize = 30usize
const QUEUE_DESC: usize = 32usize
const QUEUE_DRIVER: usize = 40usize
const QUEUE_DEVICE: usize = 48usize

const STATUS_ACKNOWLEDGE: u8 = 1u8
const STATUS_DRIVER: u8 = 2u8
const STATUS_DRIVER_OK: u8 = 4u8
const STATUS_FEATURES_OK: u8 = 8u8

// A capability's cfg_type byte: which structure it points at.
const CAP_COMMON: u8 = 1u8
const CAP_NOTIFY: u8 = 2u8
const CAP_ISR: u8 = 3u8
const CAP_DEVICE: u8 = 4u8
// Descriptor flags: the device writes into this buffer, and the chain continues at `next`.
const DESC_WRITE: u16 = 2u16
const DESC_NEXT: u16 = 1u16

// virtio-blk request types (virtio 1.x 5.2.6): read from, and write to, the device.
const VIRTIO_BLK_T_IN: u32 = 0u32
const VIRTIO_BLK_T_OUT: u32 = 1u32
const SECTOR: usize = 512usize

// virtio-vsock (virtio 1.x 5.10): three virtqueues -- receive (0), transmit (1) and event (2) --
// a 44-byte packet header, and a 64-bit guest CID in device config. The host is always CID 2. A
// STREAM connection opens with a REQUEST the host answers RESPONSE (a listener) or RST (none).
const VSOCK_RX: u16 = 0u16
const VSOCK_TX: u16 = 1u16
const VSOCK_EVENT: u16 = 2u16
const VSOCK_HDR: usize = 44usize
const VSOCK_TYPE_STREAM: u16 = 1u16
const VSOCK_OP_REQUEST: u16 = 1u16
const VSOCK_OP_RESPONSE: u16 = 2u16
const VSOCK_OP_RST: u16 = 3u16
const VSOCK_OP_RW: u16 = 5u16
const VSOCK_HOST_CID: u64 = 2u64

const PAGE: usize = 4096usize

// The DMA pool: one contiguous, identity-mapped region the driver carves its rings and buffers
// from, set by `pool_set` before a driver runs. In the kernel it is a slice of the kernel's own
// RAM; in an EL0 user-mode server it is the pool the kernel maps into the server identity
// (D2134+). Either way a region's virtual address is the physical address the device DMAs to.
var pool_next: usize = 0usize
var pool_end: usize = 0usize

type Device = struct { common: usize, notify: usize, notify_multiplier: u32, isr: usize, config: usize, bar: usize, bar_size: usize }

// One enabled split virtqueue: the three rings in identity-mapped RAM, the notify register the
// device watches, the value to write there (the queue index, absent NOTIFICATION_DATA), and the
// ring length.
type Ring = struct { desc: usize, avail: usize, used: usize, notify: usize, index: u16, size: usize }

// Point the DMA pool at `[base, base+size)`, an identity-mapped region, and reset it. Called
// before each driver runs; one driver's abandoned rings are reclaimed by the next.
fn pool_set(base: usize, size: usize) {
    pool_next = base
    pool_end = base + size
}

// A zeroed, page-aligned region carved from the pool, whose virtual address is its physical one
// (identity), so the device can DMA to it. One request is in flight at a time, so a page-aligned
// bump suffices; the pool refuses rather than overrun.
fn dma_region(bytes: usize) -> (usize, err) {
    let at = (pool_next + PAGE - 1usize) & ~(PAGE - 1usize)
    if at + bytes > pool_end { ret (0usize, PoolExhausted) }
    pool_next = at + bytes
    var i = 0usize
    while i < bytes {
        os.store8(at + i, 0u8)
        i += 1usize
    }
    ret (at, ok)
}

fn status_add(device: Device, bits: u8) {
    os.store8(device.common + DEVICE_STATUS, os.load8(device.common + DEVICE_STATUS) | bits)
}

// The device at `slot` set up: the BAR its capabilities name assigned if the VMM left it unset
// (QEMU's virt leaves it for the guest; crosvm pre-assigns one), the device enabled, and its
// capability structures located. A virtio device keeps all its structures in one BAR, so that BAR
// -- its base and decoded size -- comes back in the Device for the kernel to map into the EL0
// server (D2146); QEMU names BAR 4, crosvm BAR 0, so the index is read from the capability, never
// assumed. The updated MMIO cursor comes back too.
fn discover(host: pci.Host, slot: usize, next: usize) -> (Device, usize, err) {
    var device: Device = zero
    if (pci.config_read16(host, 0usize, slot, 0usize, 6usize) & 16u16) == 0u16 { ret (device, next, NoCapabilities) }
    // First pass: the BAR index the common-configuration capability names.
    var cfg_bar = 0usize
    var found_cfg = false
    var scout = usize(pci.config_read8(host, 0usize, slot, 0usize, 52usize))
    var scout_guard = 0usize
    while scout != 0usize && scout_guard < 48usize {
        if pci.config_read8(host, 0usize, slot, 0usize, scout) == 9u8 && pci.config_read8(host, 0usize, slot, 0usize, scout + 3usize) == CAP_COMMON {
            cfg_bar = usize(pci.config_read8(host, 0usize, slot, 0usize, scout + 4usize))
            found_cfg = true
        }
        scout = usize(pci.config_read8(host, 0usize, slot, 0usize, scout + 1usize))
        scout_guard += 1usize
    }
    if !found_cfg { ret (device, next, NoCapabilities) }
    var cursor = next
    if pci.bar_base(host, slot, cfg_bar) == 0usize { cursor = pci.assign_bar(host, slot, cfg_bar, next) }
    pci.enable_device(host, slot)
    device.bar = pci.bar_base(host, slot, cfg_bar)
    device.bar_size = pci.bar_size(host, slot, cfg_bar)
    // Second pass: locate each structure at its capability's BAR + offset.
    var pointer = usize(pci.config_read8(host, 0usize, slot, 0usize, 52usize))
    var guard = 0usize
    while pointer != 0usize && guard < 48usize {
        if pci.config_read8(host, 0usize, slot, 0usize, pointer) == 9u8 {
            let cfg_type = pci.config_read8(host, 0usize, slot, 0usize, pointer + 3usize)
            let bar = usize(pci.config_read8(host, 0usize, slot, 0usize, pointer + 4usize))
            let offset = usize(pci.config_read32(host, 0usize, slot, 0usize, pointer + 8usize))
            let address = pci.bar_base(host, slot, bar) + offset
            if cfg_type == CAP_COMMON { device.common = address }
            if cfg_type == CAP_NOTIFY {
                device.notify = address
                device.notify_multiplier = pci.config_read32(host, 0usize, slot, 0usize, pointer + 16usize)
            }
            if cfg_type == CAP_ISR { device.isr = address }
            if cfg_type == CAP_DEVICE { device.config = address }
        }
        pointer = usize(pci.config_read8(host, 0usize, slot, 0usize, pointer + 1usize))
        guard += 1usize
    }
    ret (device, cursor, ok)
}

// Reset, acknowledge, accept only VIRTIO_F_VERSION_1 (feature bit 32), and confirm the
// device kept FEATURES_OK.
fn negotiate(device: Device) -> err {
    os.store8(device.common + DEVICE_STATUS, 0u8)
    status_add(device, STATUS_ACKNOWLEDGE)
    status_add(device, STATUS_DRIVER)
    os.store32(device.common + DRIVER_FEATURE_SELECT, 1u32)
    os.store32(device.common + DRIVER_FEATURE, 1u32)
    os.store32(device.common + DRIVER_FEATURE_SELECT, 0u32)
    os.store32(device.common + DRIVER_FEATURE, 0u32)
    status_add(device, STATUS_FEATURES_OK)
    if (os.load8(device.common + DEVICE_STATUS) & STATUS_FEATURES_OK) == 0u8 { ret FeaturesRejected }
    ret ok
}

// Select queue `selector`, allocate its descriptor table and available and used rings in
// identity-mapped RAM, hand the device their addresses, enable it, and resolve the notify
// register. The avail ring is {flags:u16, idx:u16, ring:[u16;size]}; the used ring is
// {flags:u16, idx:u16, ring:[{id:u32, len:u32};size]}.
fn setup_queue(device: Device, selector: u16) -> (Ring, err) {
    os.store16(device.common + QUEUE_SELECT, selector)
    let size = usize(os.load16(device.common + QUEUE_SIZE))
    if size == 0usize { ret (zero, NoQueue) }
    let (desc, desc_error) = dma_region(16usize * size)
    if desc_error != ok { ret (zero, desc_error) }
    let (avail, avail_error) = dma_region(6usize + 2usize * size)
    if avail_error != ok { ret (zero, avail_error) }
    let (used, used_error) = dma_region(6usize + 8usize * size)
    if used_error != ok { ret (zero, used_error) }
    os.store64(device.common + QUEUE_DESC, u64(desc))
    os.store64(device.common + QUEUE_DRIVER, u64(avail))
    os.store64(device.common + QUEUE_DEVICE, u64(used))
    os.store16(device.common + QUEUE_ENABLE, 1u16)
    let notify_offset = usize(os.load16(device.common + QUEUE_NOTIFY_OFF))
    ret (Ring { desc: desc, avail: avail, used: used, notify: device.notify + notify_offset * usize(device.notify_multiplier), index: selector, size: size }, ok)
}

// Offer descriptor-chain head 0 in the `nth` available slot (0-based) and notify the device
// (D2141). The wait is a separate step so a user-mode server can block on its interrupt between
// submitting and collecting.
fn ring_submit(ring: Ring, nth: u16) {
    os.store16(ring.avail + 4usize + 2usize * usize(nth), 0u16)
    os.barrier()
    os.store16(ring.avail + 2usize, nth + 1u16)
    os.barrier()
    os.store16(ring.notify, ring.index)
}

// Spin, bounded, until the device has completed `nth + 1` buffers. A driver that first waited on
// its interrupt finds this already satisfied; one that did not, or whose interrupt never arrived,
// still completes here -- so a missing or mis-routed interrupt degrades to polling, never a hang.
fn ring_poll(ring: Ring, nth: u16) -> err {
    var spins = 0usize
    while os.load16(ring.used + 2usize) != nth + 1u16 && spins < 200000000usize { spins += 1usize }
    if os.load16(ring.used + 2usize) != nth + 1u16 { ret NoData }
    ret ok
}

// One request in flight at a time, so the used index rising to `nth + 1` is this request
// finishing. Submit and poll together, for the in-kernel path and the poll-only drivers.
fn ring_wait(ring: Ring, nth: u16) -> err {
    ring_submit(ring, nth)
    ret ring_poll(ring, nth)
}

// Set up the entropy device and submit one device-writable buffer WITHOUT waiting (D2141), for a
// notification-driven user-mode server that blocks on its interrupt and then collects. The buffer
// and the ring come back; the caller polls the ring after its wait.
fn entropy_begin(device: Device, want: usize) -> (usize, Ring, err) {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret (0usize, zero, negotiate_error) }
    let (ring, ring_error) = setup_queue(device, 0u16)
    if ring_error != ok { ret (0usize, zero, ring_error) }
    let (buffer, buffer_error) = dma_region(want)
    if buffer_error != ok { ret (0usize, zero, buffer_error) }
    status_add(device, STATUS_DRIVER_OK)
    os.store64(ring.desc, u64(buffer))
    os.store32(ring.desc + 8usize, u32(want))
    os.store16(ring.desc + 12usize, DESC_WRITE)
    os.store16(ring.desc + 14usize, 0u16)
    ring_submit(ring, 0u16)
    ret (buffer, ring, ok)
}

// Collect a completed request begun with `entropy_begin`: poll the ring (the bounded fallback)
// and return the byte count the device wrote (used.ring[0].len at used + 8).
fn collect_written(ring: Ring, nth: u16) -> (usize, err) {
    let poll_error = ring_poll(ring, nth)
    if poll_error != ok { ret (0usize, poll_error) }
    ret (usize(os.load32(ring.used + 8usize)), ok)
}

// One device-writable buffer of `want` bytes submitted on queue 0, filled by the device, the
// buffer's address and the byte count returned. The rings and the buffer are the driver's own
// pages; the device DMAs to their physical (identity) addresses.
fn read_entropy(device: Device, want: usize) -> (usize, usize, err) {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret (0usize, 0usize, negotiate_error) }
    let (ring, ring_error) = setup_queue(device, 0u16)
    if ring_error != ok { ret (0usize, 0usize, ring_error) }
    let (buffer, buffer_error) = dma_region(want)
    if buffer_error != ok { ret (0usize, 0usize, buffer_error) }
    status_add(device, STATUS_DRIVER_OK)
    // Descriptor 0: the device writes `want` bytes into the buffer.
    os.store64(ring.desc, u64(buffer))
    os.store32(ring.desc + 8usize, u32(want))
    os.store16(ring.desc + 12usize, DESC_WRITE)
    os.store16(ring.desc + 14usize, 0u16)
    let wait_error = ring_wait(ring, 0u16)
    if wait_error != ok { ret (0usize, 0usize, wait_error) }
    // used.ring[0] is {id: u32, len: u32} at offset 4; the length is what the device wrote.
    let written = usize(os.load32(ring.used + 8usize))
    ret (buffer, written, ok)
}

// Fill the byte at `data + i` with the deterministic pattern sector 0 is written with, so a
// read-back can be checked byte for byte.
fn pattern(i: usize) -> u8 {
    ret u8((i * 37usize + 17usize) & 255usize)
}

// Write a known pattern to `sector`, read it back, and confirm it round-trips. The request is a
// three-descriptor chain -- a 16-byte header the device reads ({type:u32, reserved:u32,
// sector:u64}), the 512-byte data buffer, and a one-byte status the device writes. Descriptors
// 0-2 are reused for both the write and the read; only descriptor 1's direction flag and the
// header's type change. The read buffer's address comes back.
fn block_rw(device: Device, sector: u64) -> (usize, err) {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret (0usize, negotiate_error) }
    let (ring, ring_error) = setup_queue(device, 0u16)
    if ring_error != ok { ret (0usize, ring_error) }
    status_add(device, STATUS_DRIVER_OK)
    let (header, header_error) = dma_region(16usize)
    if header_error != ok { ret (0usize, header_error) }
    let (data, data_error) = dma_region(SECTOR)
    if data_error != ok { ret (0usize, data_error) }
    let (status, status_error) = dma_region(1usize)
    if status_error != ok { ret (0usize, status_error) }
    // The parts of the chain that never change: desc0 -> desc1 -> desc2, desc2 the status byte.
    os.store64(ring.desc, u64(header))
    os.store32(ring.desc + 8usize, 16u32)
    os.store16(ring.desc + 12usize, DESC_NEXT)
    os.store16(ring.desc + 14usize, 1u16)
    os.store64(ring.desc + 16usize, u64(data))
    os.store32(ring.desc + 24usize, u32(SECTOR))
    os.store16(ring.desc + 30usize, 2u16)
    os.store64(ring.desc + 32usize, u64(status))
    os.store32(ring.desc + 40usize, 1u32)
    os.store16(ring.desc + 44usize, DESC_WRITE)
    os.store16(ring.desc + 46usize, 0u16)
    // Write: the device reads the data buffer out to the disk.
    var i = 0usize
    while i < SECTOR {
        os.store8(data + i, pattern(i))
        i += 1usize
    }
    os.store32(header, VIRTIO_BLK_T_OUT)
    os.store32(header + 4usize, 0u32)
    os.store64(header + 8usize, sector)
    os.store16(ring.desc + 28usize, DESC_NEXT)
    os.store8(status, 255u8)
    let write_error = ring_wait(ring, 0u16)
    if write_error != ok { ret (0usize, write_error) }
    if os.load8(status) != 0u8 { ret (0usize, BlockStatus) }
    // Read: clear the buffer, flip the header type and descriptor 1 to device-writable.
    i = 0usize
    while i < SECTOR {
        os.store8(data + i, 0u8)
        i += 1usize
    }
    os.store32(header, VIRTIO_BLK_T_IN)
    os.store64(header + 8usize, sector)
    os.store16(ring.desc + 28usize, DESC_NEXT | DESC_WRITE)
    os.store8(status, 255u8)
    let read_error = ring_wait(ring, 1u16)
    if read_error != ok { ret (0usize, read_error) }
    if os.load8(status) != 0u8 { ret (0usize, BlockStatus) }
    i = 0usize
    while i < SECTOR {
        if os.load8(data + i) != pattern(i) { ret (data, BlockMismatch) }
        i += 1usize
    }
    ret (data, ok)
}

// (D2152, C106) A block device opened for many reads and writes, for the filesystem server. One
// request is in flight at a time; `header`, `data` (one sector) and `status` are allocated once and
// reused, so the DMA pool does not grow per operation. The caller reads from and writes to `data`.
type Block = struct { ring: Ring, header: usize, data: usize, status: usize }

// The free-running request index: the virtqueue's available and used indices count operations
// across the whole run, and a slot is index-mod-size. One device at a time holds the block, so a
// single counter serves.
var block_seq: u16 = 0u16

// Negotiate the block device, set up its queue, and allocate the reused header, sector and status
// buffers. The opened block comes back for `block_read`/`block_write`.
fn block_open(device: Device) -> (Block, err) {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret (zero, negotiate_error) }
    let (ring, ring_error) = setup_queue(device, 0u16)
    if ring_error != ok { ret (zero, ring_error) }
    status_add(device, STATUS_DRIVER_OK)
    let (header, header_error) = dma_region(16usize)
    if header_error != ok { ret (zero, header_error) }
    let (data, data_error) = dma_region(SECTOR)
    if data_error != ok { ret (zero, data_error) }
    let (status, status_error) = dma_region(1usize)
    if status_error != ok { ret (zero, status_error) }
    ret (Block { ring: ring, header: header, data: data, status: status }, ok)
}

// One block request: the three-descriptor chain (header the device reads, the sector, the status
// the device writes), submitted at the running slot, the available index bumped, the device
// notified, and a bounded spin until the used index reaches it. `write` sends `blk.data` to the
// sector; a read fills `blk.data` from it. The descriptors are reused each call.
fn block_io(blk: Block, sector: u64, write: bool) -> err {
    if write { os.store32(blk.header, VIRTIO_BLK_T_OUT) } else { os.store32(blk.header, VIRTIO_BLK_T_IN) }
    os.store32(blk.header + 4usize, 0u32)
    os.store64(blk.header + 8usize, sector)
    os.store8(blk.status, 255u8)
    os.store64(blk.ring.desc, u64(blk.header))
    os.store32(blk.ring.desc + 8usize, 16u32)
    os.store16(blk.ring.desc + 12usize, DESC_NEXT)
    os.store16(blk.ring.desc + 14usize, 1u16)
    os.store64(blk.ring.desc + 16usize, u64(blk.data))
    os.store32(blk.ring.desc + 24usize, u32(SECTOR))
    if write { os.store16(blk.ring.desc + 28usize, DESC_NEXT) } else { os.store16(blk.ring.desc + 28usize, DESC_NEXT | DESC_WRITE) }
    os.store16(blk.ring.desc + 30usize, 2u16)
    os.store64(blk.ring.desc + 32usize, u64(blk.status))
    os.store32(blk.ring.desc + 40usize, 1u32)
    os.store16(blk.ring.desc + 44usize, DESC_WRITE)
    os.store16(blk.ring.desc + 46usize, 0u16)
    let slot = block_seq % u16(blk.ring.size)
    os.store16(blk.ring.avail + 4usize + 2usize * usize(slot), 0u16)
    os.barrier()
    block_seq += 1u16
    os.store16(blk.ring.avail + 2usize, block_seq)
    os.barrier()
    os.store16(blk.ring.notify, blk.ring.index)
    var spins = 0usize
    while os.load16(blk.ring.used + 2usize) != block_seq && spins < 200000000usize { spins += 1usize }
    if os.load16(blk.ring.used + 2usize) != block_seq { ret NoData }
    if os.load8(blk.status) != 0u8 { ret BlockStatus }
    ret ok
}

// Read `sector` into `blk.data`.
fn block_read(blk: Block, sector: u64) -> err {
    ret block_io(blk, sector, false)
}

// Write `blk.data` to `sector`.
fn block_write(blk: Block, sector: u64) -> err {
    ret block_io(blk, sector, true)
}

// Write `text` to the console device's transmit queue (port 0's transmitq is queue 1). We do not
// negotiate MULTIPORT, so the device runs single-port and queue 1 reaches the chardev directly.
// The buffer is one device-readable descriptor; the notify value is the queue index (1).
fn write_console(device: Device, text: str) -> err {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret negotiate_error }
    let (ring, ring_error) = setup_queue(device, 1u16)
    if ring_error != ok { ret ring_error }
    status_add(device, STATUS_DRIVER_OK)
    let (buffer, buffer_error) = dma_region(text.len)
    if buffer_error != ok { ret buffer_error }
    var i = 0usize
    while i < text.len {
        os.store8(buffer + i, text[i])
        i += 1usize
    }
    os.store64(ring.desc, u64(buffer))
    os.store32(ring.desc + 8usize, u32(text.len))
    os.store16(ring.desc + 12usize, 0u16)
    os.store16(ring.desc + 14usize, 0u16)
    ret ring_wait(ring, 0u16)
}

// One descriptor-0 request on `ring` at available slot `nth`: a buffer of `len` bytes, device
// readable (the driver's data goes out) or writable (the device fills it in), submitted and
// waited for (D2142). Used by the console server for its transmit and receive.
fn one_buffer(ring: Ring, nth: u16, buffer: usize, len: usize, writable: bool) -> err {
    os.store64(ring.desc, u64(buffer))
    os.store32(ring.desc + 8usize, u32(len))
    if writable { os.store16(ring.desc + 12usize, DESC_WRITE) } else { os.store16(ring.desc + 12usize, 0u16) }
    os.store16(ring.desc + 14usize, 0u16)
    ret ring_wait(ring, nth)
}

// The console server's full duplex (D2142): transmit `prompt`, receive a line into a buffer the
// device fills from its input, and echo that line back out. Port 0's receiveq is queue 0 and its
// transmitq queue 1; both set up over one negotiation. The received buffer and its length come
// back. QEMU feeds the receiveq from the chardev's input-path and takes the transmitq to its
// output path, so the echoed bytes appear where the fixture can check them.
fn console_echo(device: Device, prompt: str) -> (usize, usize, err) {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret (0usize, 0usize, negotiate_error) }
    let (rx_ring, rx_ring_error) = setup_queue(device, 0u16)
    if rx_ring_error != ok { ret (0usize, 0usize, rx_ring_error) }
    let (tx_ring, tx_ring_error) = setup_queue(device, 1u16)
    if tx_ring_error != ok { ret (0usize, 0usize, tx_ring_error) }
    status_add(device, STATUS_DRIVER_OK)
    let (prompt_buffer, prompt_error) = dma_region(prompt.len)
    if prompt_error != ok { ret (0usize, 0usize, prompt_error) }
    var i = 0usize
    while i < prompt.len {
        os.store8(prompt_buffer + i, prompt[i])
        i += 1usize
    }
    let (line, line_error) = dma_region(64usize)
    if line_error != ok { ret (0usize, 0usize, line_error) }
    let send_error = one_buffer(tx_ring, 0u16, prompt_buffer, prompt.len, false)
    if send_error != ok { ret (0usize, 0usize, send_error) }
    // Receive a line, best-effort: post a device-writable buffer and wait a bounded while. Input
    // is echoed when it arrives (the host fed the chardev); when none comes the transmit still
    // counts as done, so a host whose chardev cannot feed input does not fail the driver.
    os.store64(rx_ring.desc, u64(line))
    os.store32(rx_ring.desc + 8usize, 64u32)
    os.store16(rx_ring.desc + 12usize, DESC_WRITE)
    os.store16(rx_ring.desc + 14usize, 0u16)
    ring_submit(rx_ring, 0u16)
    var spins = 0usize
    while os.load16(rx_ring.used + 2usize) == 0u16 && spins < 30000000usize { spins += 1usize }
    if os.load16(rx_ring.used + 2usize) == 0u16 { ret (line, 0usize, ok) }
    let received = usize(os.load32(rx_ring.used + 8usize))
    let echo_error = one_buffer(tx_ring, 1u16, line, received, false)
    if echo_error != ok { ret (line, received, echo_error) }
    ret (line, received, ok)
}

// Write a virtio-vsock packet header (virtio 1.x 5.10.6) into `buf`: 44 bytes of source and
// destination CID and port, payload length, STREAM type, operation, flags, the receive-buffer
// credit the peer may fill, and the forwarded-byte count.
fn vsock_header(buf: usize, src_cid: u64, dst_cid: u64, src_port: u32, dst_port: u32, length: u32, op: u16, buf_alloc: u32) {
    os.store64(buf + 0usize, src_cid)
    os.store64(buf + 8usize, dst_cid)
    os.store32(buf + 16usize, src_port)
    os.store32(buf + 20usize, dst_port)
    os.store32(buf + 24usize, length)
    os.store16(buf + 28usize, VSOCK_TYPE_STREAM)
    os.store16(buf + 30usize, op)
    os.store32(buf + 32usize, 0u32)
    os.store32(buf + 36usize, buf_alloc)
    os.store32(buf + 40usize, 0u32)
}

// Open a STREAM connection to a host port over virtio-vsock (D2149): negotiate, set up the three
// queues, read the guest CID from device config, post a receive buffer, transmit a REQUEST to the
// host (CID 2) at `dst_port`, and wait for the device to deliver the reply into the receive buffer.
// The guest CID and the reply's operation come back -- RESPONSE when a host listener accepted,
// RST when none did; either proves the transmit and receive paths and the device itself. The TX
// descriptor is device-readable (the packet goes out); the RX descriptor device-writable.
fn vsock_connect(device: Device, src_port: u32, dst_port: u32) -> (u64, u16, err) {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret (0u64, 0u16, negotiate_error) }
    let (rx_ring, rx_ring_error) = setup_queue(device, VSOCK_RX)
    if rx_ring_error != ok { ret (0u64, 0u16, rx_ring_error) }
    let (tx_ring, tx_ring_error) = setup_queue(device, VSOCK_TX)
    if tx_ring_error != ok { ret (0u64, 0u16, tx_ring_error) }
    let (event_ring, event_ring_error) = setup_queue(device, VSOCK_EVENT)
    if event_ring_error != ok { ret (0u64, 0u16, event_ring_error) }
    status_add(device, STATUS_DRIVER_OK)
    let guest_cid = os.load64(device.config)
    let (rx_buf, rx_buf_error) = dma_region(VSOCK_HDR + 64usize)
    if rx_buf_error != ok { ret (guest_cid, 0u16, rx_buf_error) }
    os.store64(rx_ring.desc, u64(rx_buf))
    os.store32(rx_ring.desc + 8usize, u32(VSOCK_HDR + 64usize))
    os.store16(rx_ring.desc + 12usize, DESC_WRITE)
    os.store16(rx_ring.desc + 14usize, 0u16)
    ring_submit(rx_ring, 0u16)
    let (tx_buf, tx_buf_error) = dma_region(VSOCK_HDR)
    if tx_buf_error != ok { ret (guest_cid, 0u16, tx_buf_error) }
    vsock_header(tx_buf, guest_cid, VSOCK_HOST_CID, src_port, dst_port, 0u32, VSOCK_OP_REQUEST, 65536u32)
    let send_error = one_buffer(tx_ring, 0u16, tx_buf, VSOCK_HDR, false)
    if send_error != ok { ret (guest_cid, 0u16, send_error) }
    let poll_error = ring_poll(rx_ring, 0u16)
    if poll_error != ok { ret (guest_cid, 0u16, poll_error) }
    ret (guest_cid, os.load16(rx_buf + 30usize), ok)
}

// virtio-gpu 2D (virtio 1.x 5.7, C108): the control queue (0) carries a 24-byte control header
// (type, flags, fence_id, ctx_id, padding) followed by the command's own fields; the device
// answers with a header whose type is OK_NODATA or OK_DISPLAY_INFO. The driver reads the display
// mode, creates a BGRA resource the display's size, attaches a framebuffer as its backing, paints
// a pattern, makes the resource the scanout, transfers the backing to the host and flushes it.
const GPU_CMD_GET_DISPLAY_INFO: u32 = 256u32
const GPU_CMD_RESOURCE_CREATE_2D: u32 = 257u32
const GPU_CMD_SET_SCANOUT: u32 = 259u32
const GPU_CMD_RESOURCE_FLUSH: u32 = 260u32
const GPU_CMD_TRANSFER_TO_HOST_2D: u32 = 261u32
const GPU_CMD_RESOURCE_ATTACH_BACKING: u32 = 262u32
const GPU_RESP_OK_NODATA: u32 = 4352u32
const GPU_RESP_OK_DISPLAY_INFO: u32 = 4353u32
const GPU_FORMAT_BGRA: u32 = 1u32
const GPU_RESOURCE: u32 = 1u32

var gpu_seq: u16 = 0u16

fn gpu_zero(cmd: usize, bytes: usize) {
    var i = 0usize
    while i < bytes {
        os.store64(cmd + i, 0u64)
        i += 8usize
    }
}

// Submit the 2-descriptor control request (the command the device reads, then the response it
// writes) on queue 0 and spin, bounded, until it completes. The descriptors are reused each call.
fn gpu_cmd(ring: Ring, cmd: usize, resp: usize, cmd_len: usize, resp_len: usize) -> err {
    os.store64(ring.desc, u64(cmd))
    os.store32(ring.desc + 8usize, u32(cmd_len))
    os.store16(ring.desc + 12usize, DESC_NEXT)
    os.store16(ring.desc + 14usize, 1u16)
    os.store64(ring.desc + 16usize, u64(resp))
    os.store32(ring.desc + 24usize, u32(resp_len))
    os.store16(ring.desc + 28usize, DESC_WRITE)
    os.store16(ring.desc + 30usize, 0u16)
    let slot = gpu_seq % u16(ring.size)
    os.store16(ring.avail + 4usize + 2usize * usize(slot), 0u16)
    os.barrier()
    gpu_seq += 1u16
    os.store16(ring.avail + 2usize, gpu_seq)
    os.barrier()
    os.store16(ring.notify, ring.index)
    var spins = 0usize
    while os.load16(ring.used + 2usize) != gpu_seq && spins < 200000000usize { spins += 1usize }
    if os.load16(ring.used + 2usize) != gpu_seq { ret NoData }
    ret ok
}

// A deterministic test pattern into the BGRA framebuffer: blue rises with x, green with y, red
// with x+y -- varied enough that a screendump of it has a distinctive hash, and reproducible so
// that hash is a golden.
fn gpu_paint(fb: usize, width: usize, height: usize) {
    var y = 0usize
    while y < height {
        var x = 0usize
        while x < width {
            let p = fb + (y * width + x) * 4usize
            os.store8(p, u8(x & 255usize))
            os.store8(p + 1usize, u8(y & 255usize))
            os.store8(p + 2usize, u8((x + y) & 255usize))
            os.store8(p + 3usize, 255u8)
            x += 1usize
        }
        y += 1usize
    }
}

// An opened display: the control ring, its command and response buffers, the framebuffer and the
// display size. The caller paints the framebuffer, then gpu_present transfers and flushes it.
type Gpu = struct { ring: Ring, cmd: usize, resp: usize, fb: usize, width: usize, height: usize }

// Bring the display up (D2161): read the mode, create a BGRA resource the display's size, attach a
// framebuffer as its backing and make it the scanout. The framebuffer (in the DMA pool) is returned
// ready to paint; gpu_present shows it. The pool must hold width*height*4 bytes.
fn gpu_begin(device: Device) -> (Gpu, err) {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret (zero, negotiate_error) }
    let (ring, ring_error) = setup_queue(device, 0u16)
    if ring_error != ok { ret (zero, ring_error) }
    status_add(device, STATUS_DRIVER_OK)
    let (cmd, cmd_error) = dma_region(256usize)
    if cmd_error != ok { ret (zero, cmd_error) }
    let (resp, resp_error) = dma_region(512usize)
    if resp_error != ok { ret (zero, resp_error) }
    gpu_zero(cmd, 24usize)
    os.store32(cmd, GPU_CMD_GET_DISPLAY_INFO)
    let info_error = gpu_cmd(ring, cmd, resp, 24usize, 408usize)
    if info_error != ok { ret (zero, info_error) }
    if os.load32(resp) != GPU_RESP_OK_DISPLAY_INFO { ret (zero, GpuError) }
    let width = usize(os.load32(resp + 32usize))
    let height = usize(os.load32(resp + 36usize))
    if width == 0usize || height == 0usize { ret (zero, GpuError) }
    let fb_bytes = width * height * 4usize
    let (fb, fb_error) = dma_region(fb_bytes)
    if fb_error != ok { ret (zero, fb_error) }
    gpu_zero(cmd, 40usize)
    os.store32(cmd, GPU_CMD_RESOURCE_CREATE_2D)
    os.store32(cmd + 24usize, GPU_RESOURCE)
    os.store32(cmd + 28usize, GPU_FORMAT_BGRA)
    os.store32(cmd + 32usize, u32(width))
    os.store32(cmd + 36usize, u32(height))
    let create_error = gpu_cmd(ring, cmd, resp, 40usize, 24usize)
    if create_error != ok { ret (zero, create_error) }
    if os.load32(resp) != GPU_RESP_OK_NODATA { ret (zero, GpuError) }
    gpu_zero(cmd, 48usize)
    os.store32(cmd, GPU_CMD_RESOURCE_ATTACH_BACKING)
    os.store32(cmd + 24usize, GPU_RESOURCE)
    os.store32(cmd + 28usize, 1u32)
    os.store64(cmd + 32usize, u64(fb))
    os.store32(cmd + 40usize, u32(fb_bytes))
    let attach_error = gpu_cmd(ring, cmd, resp, 48usize, 24usize)
    if attach_error != ok { ret (zero, attach_error) }
    if os.load32(resp) != GPU_RESP_OK_NODATA { ret (zero, GpuError) }
    gpu_zero(cmd, 48usize)
    os.store32(cmd, GPU_CMD_SET_SCANOUT)
    os.store32(cmd + 32usize, u32(width))
    os.store32(cmd + 36usize, u32(height))
    os.store32(cmd + 40usize, 0u32)
    os.store32(cmd + 44usize, GPU_RESOURCE)
    let scanout_error = gpu_cmd(ring, cmd, resp, 48usize, 24usize)
    if scanout_error != ok { ret (zero, scanout_error) }
    if os.load32(resp) != GPU_RESP_OK_NODATA { ret (zero, GpuError) }
    ret (Gpu { ring: ring, cmd: cmd, resp: resp, fb: fb, width: width, height: height }, ok)
}

// Transfer and flush only a damaged rectangle (D2163): the sub-rect [x,y,w,h] of the framebuffer,
// its backing offset the rect's first pixel, so a small change costs a small transfer. The rows are
// read with the resource's full width as stride, so the rect lands where it belongs on the screen.
fn gpu_present_rect(gpu: Gpu, x: usize, y: usize, w: usize, h: usize) -> err {
    gpu_zero(gpu.cmd, 56usize)
    os.store32(gpu.cmd, GPU_CMD_TRANSFER_TO_HOST_2D)
    os.store32(gpu.cmd + 24usize, u32(x))
    os.store32(gpu.cmd + 28usize, u32(y))
    os.store32(gpu.cmd + 32usize, u32(w))
    os.store32(gpu.cmd + 36usize, u32(h))
    os.store64(gpu.cmd + 40usize, u64((y * gpu.width + x) * 4usize))
    os.store32(gpu.cmd + 48usize, GPU_RESOURCE)
    let transfer_error = gpu_cmd(gpu.ring, gpu.cmd, gpu.resp, 56usize, 24usize)
    if transfer_error != ok { ret transfer_error }
    if os.load32(gpu.resp) != GPU_RESP_OK_NODATA { ret GpuError }
    gpu_zero(gpu.cmd, 48usize)
    os.store32(gpu.cmd, GPU_CMD_RESOURCE_FLUSH)
    os.store32(gpu.cmd + 24usize, u32(x))
    os.store32(gpu.cmd + 28usize, u32(y))
    os.store32(gpu.cmd + 32usize, u32(w))
    os.store32(gpu.cmd + 36usize, u32(h))
    os.store32(gpu.cmd + 40usize, GPU_RESOURCE)
    let flush_error = gpu_cmd(gpu.ring, gpu.cmd, gpu.resp, 48usize, 24usize)
    if flush_error != ok { ret flush_error }
    if os.load32(gpu.resp) != GPU_RESP_OK_NODATA { ret GpuError }
    ret ok
}

// Transfer the painted framebuffer to the host resource and flush it to the screen (D2161).
fn gpu_present(gpu: Gpu) -> err {
    gpu_zero(gpu.cmd, 56usize)
    os.store32(gpu.cmd, GPU_CMD_TRANSFER_TO_HOST_2D)
    os.store32(gpu.cmd + 32usize, u32(gpu.width))
    os.store32(gpu.cmd + 36usize, u32(gpu.height))
    os.store64(gpu.cmd + 40usize, 0u64)
    os.store32(gpu.cmd + 48usize, GPU_RESOURCE)
    let transfer_error = gpu_cmd(gpu.ring, gpu.cmd, gpu.resp, 56usize, 24usize)
    if transfer_error != ok { ret transfer_error }
    if os.load32(gpu.resp) != GPU_RESP_OK_NODATA { ret GpuError }
    gpu_zero(gpu.cmd, 48usize)
    os.store32(gpu.cmd, GPU_CMD_RESOURCE_FLUSH)
    os.store32(gpu.cmd + 32usize, u32(gpu.width))
    os.store32(gpu.cmd + 36usize, u32(gpu.height))
    os.store32(gpu.cmd + 40usize, GPU_RESOURCE)
    let flush_error = gpu_cmd(gpu.ring, gpu.cmd, gpu.resp, 48usize, 24usize)
    if flush_error != ok { ret flush_error }
    if os.load32(gpu.resp) != GPU_RESP_OK_NODATA { ret GpuError }
    ret ok
}

// Bring the display up and paint the test pattern (C108); the display's width and height come back.
fn gpu_bringup(device: Device) -> (usize, usize, err) {
    let (gpu, begin_error) = gpu_begin(device)
    if begin_error != ok { ret (0usize, 0usize, begin_error) }
    gpu_paint(gpu.fb, gpu.width, gpu.height)
    let present_error = gpu_present(gpu)
    if present_error != ok { ret (gpu.width, gpu.height, present_error) }
    ret (gpu.width, gpu.height, ok)
}

// virtio-input (virtio 1.x 5.8, C109): the event queue (0) carries 8-byte events the device writes
// as input arrives -- virtio_input_event {type: u16, code: u16, value: u32}, the Linux input_event
// shape (EV_SYN 0, EV_KEY 1, EV_ABS 3). The driver posts device-writable buffers and reads the used
// ring as the device fills them. One batch of buffers is posted at open; a bounded run of events
// fits without re-posting.
const INPUT_EVENTS: usize = 64usize

type Input = struct { ring: Ring, buffers: usize, count: usize, seen: u16, posted: u16 }

// Set up the input device: negotiate, enable the event queue, post `count` device-writable 8-byte
// event buffers, and notify. The device writes an event into the next buffer as input arrives.
fn input_open(device: Device, count: usize) -> (Input, err) {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret (zero, negotiate_error) }
    let (ring, ring_error) = setup_queue(device, 0u16)
    if ring_error != ok { ret (zero, ring_error) }
    status_add(device, STATUS_DRIVER_OK)
    let (buffers, buffers_error) = dma_region(count * 8usize)
    if buffers_error != ok { ret (zero, buffers_error) }
    var i = 0usize
    while i < count {
        os.store64(ring.desc + i * 16usize, u64(buffers + i * 8usize))
        os.store32(ring.desc + i * 16usize + 8usize, 8u32)
        os.store16(ring.desc + i * 16usize + 12usize, DESC_WRITE)
        os.store16(ring.desc + i * 16usize + 14usize, 0u16)
        os.store16(ring.avail + 4usize + 2usize * i, u16(i))
        i += 1usize
    }
    os.barrier()
    os.store16(ring.avail + 2usize, u16(count))
    os.barrier()
    os.store16(ring.notify, ring.index)
    ret (Input { ring: ring, buffers: buffers, count: count, seen: 0u16, posted: u16(count) }, ok)
}

// The next event the device has written, if any: (type, code, value, true), or (0, 0, 0, false)
// when none is pending. The used ring names which buffer the device filled; events arrive in order.
fn input_next(input: *Input) -> (u16, u16, u32, bool) {
    if os.load16(input.ring.used + 2usize) == input.seen { ret (0u16, 0u16, 0u32, false) }
    let j = usize(input.seen) % input.ring.size
    let id = usize(os.load32(input.ring.used + 4usize + j * 8usize))
    let event = input.buffers + id * 8usize
    let etype = os.load16(event)
    let ecode = os.load16(event + 2usize)
    let evalue = os.load32(event + 4usize)
    input.seen += 1u16
    // Give the buffer back to the device (D2206): without it the device ran out after `count` events
    // and dropped the rest, which a long session of taps reached.
    let slot = usize(input.posted) % input.ring.size
    os.store16(input.ring.avail + 4usize + 2usize * slot, u16(id))
    input.posted += 1u16
    os.barrier()
    os.store16(input.ring.avail + 2usize, input.posted)
    os.barrier()
    os.store16(input.ring.notify, input.ring.index)
    ret (etype, ecode, evalue, true)
}
