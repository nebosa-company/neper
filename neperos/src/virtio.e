// The modern virtio-pci transport (virtio 1.x, D2131): a virtio device exposes its
// registers through PCI capabilities that name a BAR and an offset. NeperOS assigns the
// device a BAR in the 32-bit MMIO window, walks the capabilities to find the common
// configuration, the notify region and the ISR, negotiates VIRTIO_F_VERSION_1, builds one
// split virtqueue in its own RAM (identity-mapped, so a virtual address is the physical one
// the device DMAs to), and drives it. The entropy device fills a buffer with random bytes.
use e.mem
use e.os
use pci

error NoCapabilities
error NoQueue
error FeaturesRejected
error NoData
error BlockStatus
error BlockMismatch

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

const PAGE: usize = 4096usize

type Device = struct { common: usize, notify: usize, notify_multiplier: u32, isr: usize, config: usize }

// One enabled split virtqueue: the three rings in identity-mapped RAM, the notify register the
// device watches, and the ring length.
type Ring = struct { desc: usize, avail: usize, used: usize, notify: usize, size: usize }

// A zeroed, page-aligned region whose virtual address is its physical one (identity map), so
// the device can DMA to it.
fn dma_region(a: *mem.Arena, bytes: usize) -> (usize, err) {
    let (storage, storage_error) = mem.alloc[u8](a, bytes + PAGE)
    if storage_error != ok { ret (0usize, storage_error) }
    let at = (mem.address_of(&storage[0usize]) + PAGE - 1usize) & ~(PAGE - 1usize)
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

// The device at `slot` set up: its BAR assigned from `next` in the MMIO window, enabled, and
// its capability structures located. The updated MMIO cursor comes back too.
fn discover(host: pci.Host, slot: usize, next: usize) -> (Device, usize, err) {
    let cursor = pci.assign_bar(host, slot, 4usize, next)
    pci.enable_device(host, slot)
    var device: Device = zero
    if (pci.config_read16(host, 0usize, slot, 0usize, 6usize) & 16u16) == 0u16 { ret (device, cursor, NoCapabilities) }
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
fn setup_queue(a: *mem.Arena, device: Device, selector: u16) -> (Ring, err) {
    os.store16(device.common + QUEUE_SELECT, selector)
    let size = usize(os.load16(device.common + QUEUE_SIZE))
    if size == 0usize { ret (zero, NoQueue) }
    let (desc, desc_error) = dma_region(a, 16usize * size)
    if desc_error != ok { ret (zero, desc_error) }
    let (avail, avail_error) = dma_region(a, 6usize + 2usize * size)
    if avail_error != ok { ret (zero, avail_error) }
    let (used, used_error) = dma_region(a, 6usize + 8usize * size)
    if used_error != ok { ret (zero, used_error) }
    os.store64(device.common + QUEUE_DESC, u64(desc))
    os.store64(device.common + QUEUE_DRIVER, u64(avail))
    os.store64(device.common + QUEUE_DEVICE, u64(used))
    os.store16(device.common + QUEUE_ENABLE, 1u16)
    let notify_offset = usize(os.load16(device.common + QUEUE_NOTIFY_OFF))
    ret (Ring { desc: desc, avail: avail, used: used, notify: device.notify + notify_offset * usize(device.notify_multiplier), size: size }, ok)
}

// Offer descriptor-chain head 0 in the `nth` available slot (0-based) and spin until the device
// has completed `nth + 1` buffers. One request is in flight at a time, so the used index rising
// to `nth + 1` is this request finishing.
fn ring_wait(ring: Ring, nth: u16) -> err {
    os.store16(ring.avail + 4usize + 2usize * usize(nth), 0u16)
    os.barrier()
    os.store16(ring.avail + 2usize, nth + 1u16)
    os.barrier()
    os.store16(ring.notify, 0u16)
    var spins = 0usize
    while os.load16(ring.used + 2usize) != nth + 1u16 && spins < 200000000usize { spins += 1usize }
    if os.load16(ring.used + 2usize) != nth + 1u16 { ret NoData }
    ret ok
}

// One device-writable buffer of `want` bytes submitted on queue 0, filled by the device, the
// buffer's address and the byte count returned. The rings and the buffer are the driver's own
// pages; the device DMAs to their physical (identity) addresses.
fn read_entropy(a: *mem.Arena, device: Device, want: usize) -> (usize, usize, err) {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret (0usize, 0usize, negotiate_error) }
    let (ring, ring_error) = setup_queue(a, device, 0u16)
    if ring_error != ok { ret (0usize, 0usize, ring_error) }
    let (buffer, buffer_error) = dma_region(a, want)
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
fn block_rw(a: *mem.Arena, device: Device, sector: u64) -> (usize, err) {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret (0usize, negotiate_error) }
    let (ring, ring_error) = setup_queue(a, device, 0u16)
    if ring_error != ok { ret (0usize, ring_error) }
    status_add(device, STATUS_DRIVER_OK)
    let (header, header_error) = dma_region(a, 16usize)
    if header_error != ok { ret (0usize, header_error) }
    let (data, data_error) = dma_region(a, SECTOR)
    if data_error != ok { ret (0usize, data_error) }
    let (status, status_error) = dma_region(a, 1usize)
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
