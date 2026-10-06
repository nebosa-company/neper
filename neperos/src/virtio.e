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
// A descriptor the device writes into.
const DESC_WRITE: u16 = 2u16

const PAGE: usize = 4096usize

type Device = struct { common: usize, notify: usize, notify_multiplier: u32, isr: usize, config: usize }

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

// One device-writable buffer of `want` bytes submitted on queue 0, filled by the device, the
// buffer's address and the byte count returned. The rings and the buffer are the driver's own
// pages; the device DMAs to their physical (identity) addresses.
fn read_entropy(a: *mem.Arena, device: Device, want: usize) -> (usize, usize, err) {
    let negotiate_error = negotiate(device)
    if negotiate_error != ok { ret (0usize, 0usize, negotiate_error) }
    os.store16(device.common + QUEUE_SELECT, 0u16)
    let size = usize(os.load16(device.common + QUEUE_SIZE))
    if size == 0usize { ret (0usize, 0usize, NoQueue) }
    let (desc, desc_error) = dma_region(a, 16usize * size)
    if desc_error != ok { ret (0usize, 0usize, desc_error) }
    let (avail, avail_error) = dma_region(a, 6usize + 2usize * size)
    if avail_error != ok { ret (0usize, 0usize, avail_error) }
    let (used, used_error) = dma_region(a, 6usize + 8usize * size)
    if used_error != ok { ret (0usize, 0usize, used_error) }
    let (buffer, buffer_error) = dma_region(a, want)
    if buffer_error != ok { ret (0usize, 0usize, buffer_error) }
    os.store64(device.common + QUEUE_DESC, u64(desc))
    os.store64(device.common + QUEUE_DRIVER, u64(avail))
    os.store64(device.common + QUEUE_DEVICE, u64(used))
    os.store16(device.common + QUEUE_ENABLE, 1u16)
    let notify_offset = usize(os.load16(device.common + QUEUE_NOTIFY_OFF))
    let notify_address = device.notify + notify_offset * usize(device.notify_multiplier)
    status_add(device, STATUS_DRIVER_OK)
    // Descriptor 0: the device writes `want` bytes into the buffer.
    os.store64(desc, u64(buffer))
    os.store32(desc + 8usize, u32(want))
    os.store16(desc + 12usize, DESC_WRITE)
    os.store16(desc + 14usize, 0u16)
    // Offer it in the available ring, then notify the device.
    os.store16(avail + 4usize, 0u16)
    os.barrier()
    os.store16(avail + 2usize, 1u16)
    os.barrier()
    os.store16(notify_address, 0u16)
    var spins = 0usize
    while os.load16(used + 2usize) == 0u16 && spins < 200000000usize { spins += 1usize }
    if os.load16(used + 2usize) == 0u16 { ret (0usize, 0usize, NoData) }
    // used.ring[0] is {id: u32, len: u32} at offset 4; the length is what the device wrote.
    let written = usize(os.load32(used + 8usize))
    ret (buffer, written, ok)
}
