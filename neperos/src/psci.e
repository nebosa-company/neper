// The Power State Coordination Interface (Arm DEN 0022), reached through the conduit the
// device tree's `/psci` node names: `hvc` under QEMU and crosvm, `smc` on bare metal.
use e.os
use fdt

const PSCI_VERSION: usize = 2214592512usize
const SYSTEM_OFF: usize = 2214592520usize

type Firmware = struct { smc: bool }

fn find(t: fdt.Tree) -> (Firmware, err) {
    let (node, node_error) = fdt.find_path(t, "/psci")
    if node_error != ok { ret (zero, node_error) }
    let (method, method_error) = fdt.property_text(t, node, "method")
    if method_error != ok { ret (zero, method_error) }
    ret (Firmware { smc: fdt.same(method, "smc") }, ok)
}

fn call(firmware: Firmware, function: usize, a1: usize, a2: usize, a3: usize) -> usize {
    if firmware.smc { ret os.smc(function, a1, a2, a3) }
    ret os.hvc(function, a1, a2, a3)
}

fn version(firmware: Firmware) -> usize {
    ret call(firmware, PSCI_VERSION, 0usize, 0usize, 0usize)
}

// Does not return when the firmware honours it.
fn system_off(firmware: Firmware) {
    let ignored = call(firmware, SYSTEM_OFF, 0usize, 0usize, 0usize)
}
