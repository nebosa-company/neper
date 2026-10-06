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

type Host = struct { ecam: usize }

fn find(t: fdt.Tree) -> (Host, err) {
    let (node, node_error) = fdt.find_path(t, "/pcie")
    if node_error != ok { ret (zero, NoHost) }
    let (base, size, region_error) = fdt.region(t, node)
    if region_error != ok { ret (zero, region_error) }
    ret (Host { ecam: usize(base) }, ok)
}

fn config_address(host: Host, bus: usize, slot: usize, function: usize, offset: usize) -> usize {
    ret host.ecam + (bus << 20usize) + (slot << 15usize) + (function << 12usize) + offset
}

fn config_read32(host: Host, bus: usize, slot: usize, function: usize, offset: usize) -> u32 {
    ret os.load32(config_address(host, bus, slot, function, offset))
}

fn config_write32(host: Host, bus: usize, slot: usize, function: usize, offset: usize, value: u32) {
    os.store32(config_address(host, bus, slot, function, offset), value)
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
