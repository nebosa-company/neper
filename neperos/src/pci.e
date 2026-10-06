// PCI over the ECAM window (D2129): the generic ECAM host the device tree names at /pcie,
// its configuration space one 4 KB page per function, addressed
// `base + (bus << 20) + (slot << 15) + (function << 12) + offset`. NeperOS enumerates bus 0
// to find the virtio devices QEMU attaches; a modern virtio-pci function has vendor 0x1af4
// and a device id of 0x1040 plus the virtio device type.
use e.os
use fdt

error NoHost

const VIRTIO_VENDOR: u32 = 6900u32
const VIRTIO_BASE_ID: u32 = 4160u32
const NO_FUNCTION: u32 = 65535u32

// The virtio device types this stage drives.
const VIRTIO_NET: usize = 1usize
const VIRTIO_BLOCK: usize = 2usize
const VIRTIO_CONSOLE: usize = 3usize
const VIRTIO_ENTROPY: usize = 4usize

// The ECAM configuration base, and the 32-bit MMIO window the host forwards to devices --
// where BAR assignment places the virtio registers, within the kernel's identity map.
type Host = struct { ecam: usize, mmio: usize, mmio_size: usize }

// A PCI range is seven cells: child flags, child address (2), parent address (2), size (2).
// The 32-bit memory window has `0x02000000` in the flags' top byte.
fn mmio_window(t: fdt.Tree, node: usize) -> (usize, usize, err) {
    let (ranges, ranges_error) = fdt.property(t, node, "ranges")
    if ranges_error != ok { ret (0usize, 0usize, ranges_error) }
    var at = 0usize
    while at + 28usize <= ranges.len {
        let flags = fdt.be32(ranges, at)
        if (flags & 50331648u32) == 33554432u32 {
            ret (usize(fdt.cells_at(ranges, at + 12usize, 2usize)), usize(fdt.cells_at(ranges, at + 20usize, 2usize)), ok)
        }
        at += 28usize
    }
    ret (0usize, 0usize, NoHost)
}

fn find(t: fdt.Tree) -> (Host, err) {
    let (node, node_error) = fdt.find_path(t, "/pcie")
    if node_error != ok { ret (zero, NoHost) }
    let (base, size, region_error) = fdt.region(t, node)
    if region_error != ok { ret (zero, region_error) }
    let (mmio, mmio_size, mmio_error) = mmio_window(t, node)
    if mmio_error != ok { ret (zero, mmio_error) }
    ret (Host { ecam: usize(base), mmio: mmio, mmio_size: mmio_size }, ok)
}

fn config_address(host: Host, bus: usize, slot: usize, function: usize, offset: usize) -> usize {
    ret host.ecam + (bus << 20usize) + (slot << 15usize) + (function << 12usize) + offset
}

fn config_read32(host: Host, bus: usize, slot: usize, function: usize, offset: usize) -> u32 {
    ret os.load32(config_address(host, bus, slot, function, offset))
}

fn config_read8(host: Host, bus: usize, slot: usize, function: usize, offset: usize) -> u8 {
    ret os.load8(config_address(host, bus, slot, function, offset))
}

fn config_read16(host: Host, bus: usize, slot: usize, function: usize, offset: usize) -> u16 {
    ret os.load16(config_address(host, bus, slot, function, offset))
}

fn config_write32(host: Host, slot: usize, offset: usize, value: u32) {
    os.store32(config_address(host, 0usize, slot, 0usize, offset), value)
}

fn config_write16(host: Host, slot: usize, offset: usize, value: u16) {
    os.store16(config_address(host, 0usize, slot, 0usize, offset), value)
}

// The MMIO base a memory BAR holds: the low word masked, joined with the next word for a
// 64-bit BAR. A BAR's low bits are type flags, not address.
fn bar_base(host: Host, slot: usize, bar: usize) -> usize {
    let low = config_read32(host, 0usize, slot, 0usize, 16usize + bar * 4usize)
    var base = usize(low & 4294967280u32)
    if (low & 6u32) == 4u32 {
        let high = config_read32(host, 0usize, slot, 0usize, 16usize + (bar + 1usize) * 4usize)
        base = base | (usize(high) << 32usize)
    }
    ret base
}

// Enable a device's memory space and bus-mastering (DMA): the command register's bits 1
// and 2. The ECAM host leaves BARs unassigned and the device disabled at reset.
fn enable_device(host: Host, slot: usize) {
    config_write16(host, slot, 4usize, config_read16(host, 0usize, slot, 0usize, 4usize) | 6u16)
}

// Assign one memory BAR a base from `next` in the 32-bit MMIO window, aligned to its size,
// and return where the next BAR may go. A 64-bit BAR takes the following word too; its high
// word is zero since the window is below 4 GB. An unimplemented BAR is left alone.
fn assign_bar(host: Host, slot: usize, bar: usize, next: usize) -> usize {
    config_write32(host, slot, 16usize + bar * 4usize, 4294967295u32)
    let probe = config_read32(host, 0usize, slot, 0usize, 16usize + bar * 4usize)
    if probe == 0u32 { ret next }
    let wide = (probe & 6u32) == 4u32
    if wide { config_write32(host, slot, 16usize + (bar + 1usize) * 4usize, 4294967295u32) }
    let size = usize((~(probe & 4294967280u32)) + 1u32)
    let base = (next + size - 1usize) & ~(size - 1usize)
    config_write32(host, slot, 16usize + bar * 4usize, u32(base))
    if wide { config_write32(host, slot, 16usize + (bar + 1usize) * 4usize, 0u32) }
    ret base + size
}

// The vendor id in a function's configuration space, or 0xffff for an absent function.
fn vendor_of(host: Host, bus: usize, slot: usize, function: usize) -> u32 {
    ret config_read32(host, bus, slot, function, 0usize) & 65535u32
}

fn device_of(host: Host, bus: usize, slot: usize, function: usize) -> u32 {
    ret config_read32(host, bus, slot, function, 0usize) >> 16u32
}

// The virtio device type of a function, if it is a modern virtio-pci device.
fn virtio_type(host: Host, bus: usize, slot: usize, function: usize) -> (usize, bool) {
    if vendor_of(host, bus, slot, function) != VIRTIO_VENDOR { ret (0usize, false) }
    let device = device_of(host, bus, slot, function)
    if device < VIRTIO_BASE_ID || device >= VIRTIO_BASE_ID + 64u32 { ret (0usize, false) }
    ret (usize(device - VIRTIO_BASE_ID), true)
}
