// NeperOS (D2119), stage 1a (C100, D2126): the kernel boots on QEMU's `virt` from the
// Linux arm64 boot protocol, finds its console, firmware and memory in the device tree,
// turns translation on, and proves its exception path by taking a fault on purpose. A
// boot argument `trap` ends it with a failed bounds check instead, which the runtime
// reports on the console.
use e.mem
use e.os
use a64
use fdt
use gic
use mmu
use pci
use pl011
use psci
use thread
use timer
use virtio
use vm

// The deliberate fault never reached the handler, or the load did not answer its zero.
error FaultNotTaken
// The device tree carried no initrd, so there is no user program to run.
error NoInitrd

// Ten preemptions a second: a QEMU timer slice short enough for threads to interleave
// visibly, long enough that the switch is a sliver of each slice.
const TICKS_PER_SECOND: usize = 100usize

var console: usize = 0usize
var firmware_smc: bool = zero
// The address the deliberate fault reads, and the syndrome the handler saw for it.
var probe: usize = 0usize
var probe_taken: bool = zero
var probe_esr: u64 = 0u64
// The interrupt controller, and how many timer interrupts have arrived.
var controller: gic.Controller = zero
var ticks: usize = 0usize

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

// A thread's console write (call 0): refused unless the thread holds a console capability
// with the write right (D2128), so the console is reached only through a capability. The
// bytes it names are copied out of its own region a chunk at a time and never from anywhere
// else, so a thread cannot read the kernel through the kernel. The count written goes back
// in x0, or all-ones when the thread has no console capability.
fn write_user(frame: *a64.Frame) {
    if !thread.current_holds(thread.CAP_CONSOLE, thread.RIGHT_WRITE) {
        console_write("neperos: thread ")
        console_write(thread.current_name())
        console_write(" denied console\n")
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    let ptr = usize(frame.x[0usize])
    let len = usize(frame.x[1usize])
    frame.x[0usize] = 0u64
    if ptr < vm.USER_BASE || ptr + len > vm.USER_BASE + vm.USER_SIZE { ret }
    var buffer: [256]u8 = zero
    var done = 0usize
    while done < len {
        var chunk = len - done
        if chunk > 256usize { chunk = 256usize }
        var i = 0usize
        while i < chunk {
            buffer[i] = os.load8(ptr + done + i)
            i += 1usize
        }
        console_write(buffer[0usize..chunk])
        done += chunk
    }
    frame.x[0usize] = u64(len)
}

// A system call from an EL0 thread: console write (0), exit (1) or yield (2). Exit and
// yield rewrite the frame to the next thread.
fn syscall(frame: *a64.Frame) {
    let number = frame.x[8usize]
    if number == 0u64 {
        write_user(frame)
        ret
    }
    if number == 1u64 {
        let more = thread.finish_current(frame)
        ret
    }
    if number == 2u64 {
        thread.on_yield(frame)
        ret
    }
    if number == 3u64 {
        thread.ipc_send(frame)
        ret
    }
    if number == 4u64 {
        thread.ipc_recv(frame)
        ret
    }
    if number == 5u64 {
        thread.cap_derive(frame)
        ret
    }
    if number == 6u64 {
        thread.cap_revoke(frame)
        ret
    }
    if number == 7u64 {
        thread.frame_protect(frame)
        ret
    }
    if number == 8u64 {
        thread.notify_wait(frame)
        ret
    }
    if number == 9u64 {
        device_write(frame)
        ret
    }
    if number == 10u64 {
        thread.retype(frame)
        ret
    }
}

// The console server's bytes to its device (call 9): the run at (x1, x2) in the server's own
// region written to the UART, only when the thread holds a device capability for it. This is
// how the console moves to a user-mode server -- the server owns the device capability and no
// other thread reaches the UART. The run is written whole with interrupts masked (an
// exception handler runs so), so the server's output is never split by a preemption.
fn device_write(frame: *a64.Frame) {
    let (uart, allowed) = thread.device_base(usize(frame.x[0usize]))
    let ptr = usize(frame.x[1usize])
    let len = usize(frame.x[2usize])
    frame.x[0usize] = 18446744073709551615u64
    if !allowed { ret }
    if ptr < vm.USER_BASE || ptr + len > vm.USER_BASE + vm.USER_SIZE { ret }
    var i = 0usize
    while i < len {
        pl011.put(uart, os.load8(ptr + i))
        i += 1usize
    }
    frame.x[0usize] = 0u64
}

fn exception(raw: *void) {
    let frame = mem.cast[*a64.Frame](raw)
    if a64.is_irq(frame.kind) {
        let intid = gic.acknowledge()
        if !gic.is_spurious(intid) {
            if intid == timer.INTID {
                timer.rearm(TICKS_PER_SECOND)
                ticks += 1usize
                // The timer interrupt is delivered to a user driver too (D2128): notification
                // 0 is signalled, waking any thread waiting on it before the switch.
                thread.signal_notification(0usize, 1usize)
                thread.on_timer(frame)
            }
            gic.finish(intid)
        }
        ret
    }
    let ec = a64.exception_class(frame.esr)
    if frame.kind == a64.VECTOR_SYNC_LOWER {
        if ec == a64.EC_SVC {
            syscall(frame)
            ret
        }
        if ec == a64.EC_DATA_ABORT_LOWER {
            // An EL0 thread reached memory it has no right to. The page tables turned the
            // access into this fault; the kernel ends the thread and the rest run on.
            console_write("neperos: thread ")
            console_write(thread.current_name())
            console_write(" killed, el0 fault at ")
            hex(frame.far)
            console_write("\n")
            let more = thread.finish_current(frame)
            ret
        }
    }
    if probe != 0usize && frame.far == u64(probe) && ec == a64.EC_DATA_ABORT_SAME {
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

// A thread's argument table written into its region: the names, then entries of
// (pointer, length). A hostile thread gets a second argument that points into the kernel,
// to prove the read of it faults.
fn setup_args(space: vm.Space, name: str, kernel_pointer: usize, hostile: bool) -> (usize, usize) {
    var count = 1usize
    if hostile { count = 2usize }
    let strings = vm.ARG_OFF + count * 16usize
    var i = 0usize
    while i < name.len {
        vm.put_byte(space, strings + i, name[i])
        i += 1usize
    }
    vm.put_word(space, vm.ARG_OFF, vm.address(strings))
    vm.put_word(space, vm.ARG_OFF + 8usize, name.len)
    if hostile {
        vm.put_word(space, vm.ARG_OFF + 16usize, kernel_pointer)
        vm.put_word(space, vm.ARG_OFF + 24usize, 8usize)
    }
    ret (vm.address(vm.ARG_OFF), count)
}

// One thread from the initrd image, its arguments set up, added to the scheduler, and its
// capability space granted: a console capability in slot 0 when `console`, and an endpoint
// capability on endpoint 0 in slot 1 with `endpoint_rights` (none, send or receive). A
// thread granted no console capability cannot print.
fn start_thread(a: *mem.Arena, image_addr: usize, image_len: usize, asid: usize, name: str, kernel_pointer: usize, hostile: bool, may_print: bool, endpoint_rights: u8, endpoint_object: usize, frame_cap: bool, notification: bool, device: bool, untyped_budget: usize) -> err {
    let (space, space_error) = vm.create(a, image_addr, image_len, asid)
    if space_error != ok { ret space_error }
    let (arg_table, arg_count) = setup_args(space, name, kernel_pointer, hostile)
    let index = thread.add(space, name, arg_table, arg_count)
    if index == thread.MAX_THREADS { ret vm.NoSpace }
    if may_print { thread.grant(index, 0usize, thread.CAP_CONSOLE, thread.RIGHT_WRITE, 0usize) }
    if endpoint_rights != 0u8 { thread.grant(index, 1usize, thread.CAP_ENDPOINT, endpoint_rights, endpoint_object) }
    // A frame capability over the thread's own arena page, writable; a thread may derive a
    // read-only copy and re-protect through it.
    if frame_cap { thread.grant(index, 2usize, thread.CAP_FRAME, thread.RIGHT_WRITE, space.arena_addr) }
    // A notification capability on notification 0, which the timer interrupt signals.
    if notification { thread.grant(index, 3usize, thread.CAP_NOTIFICATION, thread.RIGHT_RECV, 0usize) }
    // The device capability for the UART: the console server's alone, so it is the only
    // thread that reaches the console device.
    if device { thread.grant(index, 4usize, thread.CAP_DEVICE, thread.RIGHT_WRITE, console) }
    // An untyped-memory capability with a budget of objects to retype.
    if untyped_budget != 0usize { thread.grant(index, 5usize, thread.CAP_UNTYPED, thread.RIGHT_WRITE, untyped_budget) }
    ret ok
}

fn decimal(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    console_write(digits[at..20usize])
}

fn hex_digit(value: u8) -> u8 {
    if value < 10u8 { ret value + 48u8 }
    ret value + 87u8
}

fn hex_byte(value: u8) {
    var pair: [2]u8 = zero
    pair[0usize] = hex_digit((value >> 4u8) & 15u8)
    pair[1usize] = hex_digit(value & 15u8)
    console_write(pair[..])
}

// The entropy device driven through the modern virtio-pci transport: its BAR assigned, the
// device negotiated, a buffer filled with random bytes over one virtqueue, the bytes printed.
fn drive_entropy(a: *mem.Arena, host: pci.Host) {
    var slot = 0usize
    while slot < 32usize {
        let (device_type, is_virtio) = pci.virtio_type(host, 0usize, slot, 0usize)
        if is_virtio && device_type == pci.VIRTIO_ENTROPY {
            let (device, cursor, discover_error) = virtio.discover(host, slot, host.mmio)
            if discover_error != ok {
                console_write("virtio entropy: discover failed\n")
                ret
            }
            let (buffer, written, read_error) = virtio.read_entropy(a, device, 8usize)
            if read_error != ok {
                console_write("virtio entropy: read failed\n")
                ret
            }
            console_write("entropy ")
            decimal(written)
            console_write(" bytes:")
            var i = 0usize
            while i < written && i < 8usize {
                console_write(" ")
                hex_byte(os.load8(buffer + i))
                i += 1usize
            }
            console_write("\n")
            ret
        }
        slot += 1usize
    }
}

fn virtio_name(device_type: usize) -> str {
    if device_type == pci.VIRTIO_BLOCK { ret "block" }
    if device_type == pci.VIRTIO_CONSOLE { ret "console" }
    if device_type == pci.VIRTIO_ENTROPY { ret "entropy" }
    if device_type == pci.VIRTIO_NET { ret "net" }
    ret "other"
}

// Bus 0 of the ECAM scanned for virtio functions, each reported with its type and slot.
fn enumerate_pci(tree: fdt.Tree) {
    let (host, host_error) = pci.find(tree)
    if host_error != ok {
        console_write("no pci\n")
        ret
    }
    var slot = 0usize
    while slot < 32usize {
        let (device_type, is_virtio) = pci.virtio_type(host, 0usize, slot, 0usize)
        if is_virtio {
            console_write("virtio ")
            console_write(virtio_name(device_type))
            console_write(" at pci slot ")
            decimal(slot)
            console_write("\n")
        }
        slot += 1usize
    }
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
    enumerate_pci(tree)
    let (pci_host, pci_host_error) = pci.find(tree)
    if pci_host_error == ok { drive_entropy(a, pci_host) }
    // The interrupt controller and the timer: enable the controller, let this core take the
    // virtual-timer PPI, and arm it. Each firing preempts whatever runs.
    let (found, controller_error) = gic.find(tree)
    if controller_error != ok { ret controller_error }
    controller = found
    gic.enable(controller)
    gic.enable_private(controller, timer.INTID)
    timer.arm(TICKS_PER_SECOND)
    // The user program the loader placed in memory: `/chosen` names its bounds.
    let (initrd_start, initrd_start_error) = fdt.integer(tree, chosen, "linux,initrd-start")
    if initrd_start_error != ok { ret NoInitrd }
    let (initrd_end, initrd_end_error) = fdt.integer(tree, chosen, "linux,initrd-end")
    if initrd_end_error != ok { ret NoInitrd }
    let image_addr = usize(initrd_start)
    let image_len = usize(initrd_end - initrd_start)
    console_write("initrd ")
    hex(initrd_start)
    console_write(" len ")
    hex(u64(image_len))
    console_write("\n")
    // A and B interleave under the timer, and X is handed a reference to kernel RAM --
    // mapped into its space without EL0 access -- so its read faults and it alone is killed.
    // The RAM base is as good a kernel address as any. S and R rendezvous over endpoint 0
    // (D2128): S sends three words and R prints each, interleaved with the rest.
    let protected_pointer = usize(ram_start)
    let send_right = thread.RIGHT_SEND
    let recv_right = thread.RIGHT_RECV
    let grant_send = thread.RIGHT_SEND | thread.RIGHT_GRANT
    try start_thread(a, image_addr, image_len, 1usize, "A", 0usize, false, true, 0u8, 0usize, false, false, false, 0usize)
    try start_thread(a, image_addr, image_len, 2usize, "B", 0usize, false, true, 0u8, 0usize, false, false, false, 0usize)
    try start_thread(a, image_addr, image_len, 3usize, "X", protected_pointer, true, true, 0u8, 0usize, false, false, false, 0usize)
    try start_thread(a, image_addr, image_len, 4usize, "S", 0usize, false, false, send_right, 0usize, false, false, false, 0usize)
    try start_thread(a, image_addr, image_len, 5usize, "R", 0usize, false, true, recv_right, 0usize, false, false, false, 0usize)
    // N holds no console capability: its write is refused, which it is meant to prove.
    try start_thread(a, image_addr, image_len, 6usize, "N", 0usize, false, false, 0u8, 0usize, false, false, false, 0usize)
    // V derives a chain from its endpoint capability and revokes it, proving the
    // derivations are gone.
    try start_thread(a, image_addr, image_len, 7usize, "V", 0usize, false, true, recv_right, 0usize, false, false, false, 0usize)
    // W holds a writable frame capability over its arena; it derives a read-only copy,
    // re-protects through it, and the next write faults, so it is killed.
    try start_thread(a, image_addr, image_len, 8usize, "W", 0usize, false, true, 0u8, 0usize, true, false, false, 0usize)
    // G holds a console capability and a grant-bearing endpoint on endpoint 2; it grants its
    // console capability to H, which holds none until then and only then may print.
    try start_thread(a, image_addr, image_len, 9usize, "G", 0usize, false, true, grant_send, 2usize, false, false, false, 0usize)
    try start_thread(a, image_addr, image_len, 10usize, "H", 0usize, false, false, recv_right, 2usize, false, false, false, 0usize)
    // D is a user driver: it waits on a notification the timer interrupt signals, so a
    // hardware interrupt reaches an EL0 thread.
    try start_thread(a, image_addr, image_len, 11usize, "D", 0usize, false, true, 0u8, 0usize, false, true, false, 0usize)
    // K is the user-mode console server: it alone holds the UART device capability, and P, a
    // client with no console access, sends it a line to print over endpoint 3.
    try start_thread(a, image_addr, image_len, 12usize, "K", 0usize, false, false, recv_right, 3usize, false, false, true, 0usize)
    try start_thread(a, image_addr, image_len, 13usize, "P", 0usize, false, false, send_right, 3usize, false, false, false, 0usize)
    // U retypes endpoints from an untyped capability with a budget of two, and the third
    // retype is refused -- the kernel allocates nothing, the budget bounds it.
    try start_thread(a, image_addr, image_len, 14usize, "U", 0usize, false, true, 0u8, 0usize, false, false, false, 2usize)
    console_write("scheduling\n")
    // The scheduler runs from here: the first timer tick leaves this loop for a thread, and
    // the last thread to finish returns the kernel here with nothing left to run.
    a64.enable_irq()
    while thread.running() != 0usize { os.wait_for_interrupt() }
    a64.disable_irq()
    timer.stop()
    console_write("all threads done\n")
    ret ok
}
