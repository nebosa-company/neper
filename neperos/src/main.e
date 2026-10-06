// NeperOS (D2119), stage 1a (C100, D2126): the kernel boots on QEMU's `virt` from the
// Linux arm64 boot protocol, finds its console, firmware and memory in the device tree,
// turns translation on, and proves its exception path by taking a fault on purpose. A
// boot argument `trap` ends it with a failed bounds check instead, which the runtime
// reports on the console.
use e.mem
use e.os
use a64
use fdt
use mmu
use pl011
use psci

// The deliberate fault never reached the handler, or the load did not answer its zero.
error FaultNotTaken

var console: usize = 0usize
var firmware_smc: bool = zero
// The address the deliberate fault reads, and the syndrome the handler saw for it.
var probe: usize = 0usize
var probe_taken: bool = zero
var probe_esr: u64 = 0u64

fn console_write(bytes: str) {
    if console != 0usize { pl011.write(console, bytes) }
}

fn hex(value: u64) {
    var digits: [18]u8 = zero
    digits[0usize] = 48u8
    digits[1usize] = 120u8
    var at = 0usize
    while at < 16usize {
        let nibble = u8((value >> u64(60usize - at * 4usize)) & 15u64)
        var digit = nibble + 48u8
        if nibble >= 10u8 { digit = nibble + 87u8 }
        digits[2usize + at] = digit
        at += 1usize
    }
    console_write(digits[..])
}

fn power_off(code: i32) {
    console_write("neperos: exit ")
    hex(u64(code))
    console_write("\n")
    psci.system_off(psci.Firmware { smc: firmware_smc })
}

fn exception(raw: *void) {
    let frame = mem.cast[*a64.Frame](raw)
    if probe != 0usize && frame.far == u64(probe) && a64.exception_class(frame.esr) == a64.EC_DATA_ABORT_SAME {
        probe_taken = true
        probe_esr = frame.esr
        frame.x[0usize] = 0u64
        frame.elr = frame.elr + 4u64
        ret
    }
    console_write("neperos: unexpected exception ")
    hex(frame.kind)
    console_write(" esr ")
    hex(frame.esr)
    console_write(" far ")
    hex(frame.far)
    console_write(" elr ")
    hex(frame.elr)
    console_write("\n")
    power_off(135i32)
}

fn has_word(text: str, word: str) -> bool {
    var at = 0usize
    while at + word.len <= text.len {
        if fdt.same(text[at..at + word.len], word) { ret true }
        at += 1usize
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    os.set_exit(power_off)
    if args.len == 0usize { ret fdt.BadTree }
    let (tree, tree_error) = fdt.open(args[0usize])
    if tree_error != ok { ret tree_error }
    let (chosen, chosen_error) = fdt.find_path(tree, "/chosen")
    if chosen_error != ok { ret chosen_error }
    let (stdout_path, stdout_error) = fdt.property_text(tree, chosen, "stdout-path")
    if stdout_error != ok { ret stdout_error }
    var path_end = 0usize
    while path_end < stdout_path.len && stdout_path[path_end] != 58u8 { path_end += 1usize }
    let (uart, uart_error) = fdt.find_path(tree, stdout_path[0usize..path_end])
    if uart_error != ok { ret uart_error }
    let (uart_base, uart_size, uart_region_error) = fdt.region(tree, uart)
    if uart_region_error != ok { ret uart_region_error }
    console = usize(uart_base)
    pl011.enable(console)
    os.set_console(console_write)
    console_write("Welcome to NeperOS\n")
    let (firmware, firmware_error) = psci.find(tree)
    if firmware_error != ok { ret firmware_error }
    firmware_smc = firmware.smc
    console_write("psci ")
    hex(u64(psci.version(firmware)))
    if firmware.smc { console_write(" over smc\n") } else { console_write(" over hvc\n") }
    let (memory, memory_error) = fdt.find_path(tree, "/memory")
    if memory_error != ok { ret memory_error }
    let (ram_start, ram_size, ram_error) = fdt.region(tree, memory)
    if ram_error != ok { ret ram_error }
    console_write("memory ")
    hex(ram_start)
    console_write(" size ")
    hex(ram_size)
    console_write("\n")
    console_write("console ")
    hex(uart_base)
    console_write("\n")
    os.set_exception(exception)
    try mmu.enable(a, usize(ram_start), usize(ram_size))
    if !mmu.enabled() { ret mmu.NotEnabled }
    console_write("mmu on\n")
    // Past the 39-bit space nothing translates: the read faults, the handler sees its
    // address, and the load answers zero.
    probe = 1usize << 40usize
    let probed = os.load64(probe)
    if !probe_taken || probed != 0u64 { ret FaultNotTaken }
    console_write("fault at ")
    hex(u64(probe))
    console_write(" esr ")
    hex(probe_esr)
    console_write(" taken and returned\n")
    let (bootargs, bootargs_error) = fdt.property_text(tree, chosen, "bootargs")
    if bootargs_error == ok && has_word(bootargs, "trap") {
        let index = args.len + 1usize
        console_write(args[index])
    }
    // An event already sent is one a wait returns on at once, so this does not stop.
    os.send_event()
    os.wait_for_event()
    os.memory_barrier()
    console_write("halting\n")
    ret ok
}
