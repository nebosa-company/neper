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
use ns16550
use psci
use thread
use timer
use virtio
use vm

// The deliberate fault never reached the handler, or the load did not answer its zero.
error FaultNotTaken
// The device tree carried no initrd, so there is no user program to run.
error NoInitrd
// The initrd the shell boot was handed is not a program archive (D2151).
error BadArchive

// Ten preemptions a second: a QEMU timer slice short enough for threads to interleave
// visibly, long enough that the switch is a sliver of each slice.
const TICKS_PER_SECOND: usize = 100usize

var console: usize = 0usize
// The console UART kind, chosen from the device tree (D2144): the PL011 of QEMU's virt, or the
// ns16550/8250 of crosvm's AVF guest, whose registers are `console_shift` bytes apart.
var console_ns16550: bool = zero
var console_shift: usize = 0usize
var firmware_smc: bool = zero
// The address the deliberate fault reads, and the syndrome the handler saw for it.
var probe: usize = 0usize
var probe_taken: bool = zero
var probe_esr: u64 = 0u64
// The interrupt controller, and how many timer interrupts have arrived.
var controller: gic.Controller = zero
var ticks: usize = 0usize
// The ISR-status registers of the enumerated virtio devices, and how many device interrupts the
// kernel has taken (D2141). On a PCIe INTx the handler reads each ISR to acknowledge the line
// and signals notification 1, which a driver server waits on instead of polling.
var virtio_isrs: [8]usize = zero
var virtio_isr_count: usize = 0usize
var device_irqs: usize = 0usize
// (D2151) The C105 shell's initrd archive -- base, program count, and each program's offset and
// length within it -- parsed when `-append shell` selects the shell boot; and the arena the
// kernel allocates from, kept so the `launch` system call can build a new process's space, with
// a running ASID so each process's TLB entries stay its own.
const ARCHIVE_MAGIC: u32 = 0x4E455041u32
const MAX_ARCHIVE: usize = 16usize
var kernel_arena: *mem.Arena = zero
var archive_base: usize = 0usize
var archive_count: usize = 0usize
var archive_offset: [16]usize = zero
var archive_length: [16]usize = zero
var next_asid: usize = 0usize
// (D2153) The thread index of the last driver server started, so the filesystem-server boot can
// grant it the endpoint capabilities it serves clients over.
var last_server_index: usize = 24usize
// (D2155) The PL031 real-time clock's base address from the device tree, for the wall-clock system
// call; zero when the machine names no RTC, where wall time falls back to the monotonic counter.
var rtc_base: usize = 0usize
// (D2159, C108) The DMA pool size start_driver_server maps into a driver server. 128 KB suits the
// small-buffer drivers; the GPU server needs its display's framebuffer, so its boot raises this.
var driver_pool_bytes: usize = 131072usize
// (D2166, C110) The program arena size. Zero means the 64 KB in-window arena vm.create lays down;
// a non-zero value maps a separate EL0 region of that size and points the program's arena at it,
// for the e.ui/e.gpu stack whose allocations dwarf 64 KB. Set before a start, reset to 0 after.
var driver_arena_bytes: usize = 0usize

// (D2166) Give `space` a large arena in its own mapped EL0 region (identity VA=PA) when
// driver_arena_bytes is set; otherwise leave vm.create's in-window arena. The updated space comes
// back.
fn with_big_arena(space: vm.Space) -> (vm.Space, err) {
    if driver_arena_bytes == 0usize { ret (space, ok) }
    let (arena_storage, arena_error) = mem.alloc[u8](kernel_arena, driver_arena_bytes + 4096usize)
    if arena_error != ok { ret (space, arena_error) }
    let region = (mem.address_of(&arena_storage[0usize]) + 4095usize) & ~4095usize
    let map_error = vm.map_range_el0(kernel_arena, space.ttbr, region, driver_arena_bytes, false)
    if map_error != ok { ret (space, map_error) }
    var updated = space
    updated.arena_addr = region
    updated.arena_size = driver_arena_bytes
    ret (updated, ok)
}
// The four QEMU-virt PCIe INTx lines are GIC SPIs 3-6, that is INTIDs 35-38.
const PCIE_INTX_FIRST: usize = 35usize
const PCIE_INTX_LAST: usize = 38usize
const DEVICE_NOTIFICATION: usize = 1usize

fn record_isr(isr: usize) {
    if virtio_isr_count < 8usize {
        virtio_isrs[virtio_isr_count] = isr
        virtio_isr_count += 1usize
    }
}

// A PCIe INTx: acknowledge every virtio device's line by reading its ISR-status register (read
// clears it), count it, and wake the driver servers waiting on the device notification (D2141).
fn handle_device_irq() {
    var i = 0usize
    while i < virtio_isr_count {
        let status = os.load8(virtio_isrs[i])
        i += 1usize
    }
    device_irqs += 1usize
    thread.signal_notification(DEVICE_NOTIFICATION, 1usize)
}

fn console_write(bytes: str) {
    if console == 0usize { ret }
    if console_ns16550 { ns16550.write(console, console_shift, bytes) } else { pl011.write(console, bytes) }
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
    if ptr < vm.USER_BASE || ptr + len > vm.USER_BASE + thread.current_window() { ret }
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
        let more = thread.finish_current(frame, usize(frame.x[0usize]))
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
    if number == 11u64 {
        launch(frame)
        ret
    }
    if number == 12u64 {
        thread.reap(frame)
        ret
    }
    if number == 13u64 {
        clock(frame)
        ret
    }
    if number == 14u64 {
        thread_spawn(frame)
        ret
    }
    if number == 15u64 {
        thread.detach(frame)
        ret
    }
}

// (D2157, C107) `os.thread_create` system call (14): spawn a thread in the CURRENT address space
// running at `trampoline` (x0) with the user entry (x1) and its context (x2) in x0/x1, on a fresh
// stack of x3 bytes the kernel maps into the space. The thread's id comes back, or all-ones when
// the space has no room for the stack or the thread table is full. The caller is the parent, so a
// later os.thread_join reaps it (the reap system call) and os.thread_detach frees it on exit.
fn thread_spawn(frame: *a64.Frame) {
    let trampoline = usize(frame.x[0usize])
    let entry = usize(frame.x[1usize])
    let ctx = usize(frame.x[2usize])
    var bytes = usize(frame.x[3usize])
    if bytes == 0usize { bytes = 65536usize }
    let pages = (bytes + 4095usize) / 4096usize
    let ttbr = thread.current_ttbr()
    if ttbr == 0usize {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    let (stack_va, stack_top, map_error) = vm.map_stack(kernel_arena, ttbr, pages)
    if map_error != ok {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    let index = thread.add_in_space(ttbr, "thread", trampoline, entry, ctx, stack_top)
    if index == thread.MAX_THREADS {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    frame.x[0usize] = u64(index)
}

// (D2155, C107) `os.clock(kind) -> (i64, err)` (system call 13): the time in nanoseconds, kind 0
// wall and 1 monotonic. Monotonic is the virtual counter converted to nanoseconds by its frequency
// (split so neither multiply overflows 64 bits). Wall reads the PL031 RTC the device tree named --
// its data register holds the seconds since the epoch -- and falls back to the monotonic counter
// when no RTC was found. The counter and the RTC are read here at EL1, so an EL0 program needs no
// access to either.
fn clock(frame: *a64.Frame) {
    let kind = frame.x[0usize]
    var nanos: u64 = 0u64
    if kind == 0u64 && rtc_base != 0usize {
        let seconds = u64(os.load32(rtc_base))
        nanos = seconds * 1000000000u64
    } else {
        let count = u64(os.mrs(a64.CNTVCT_EL0))
        let freq = u64(os.mrs(a64.CNTFRQ_EL0))
        if freq != 0u64 {
            let whole = count / freq
            let frac = count % freq
            nanos = whole * 1000000000u64 + frac * 1000000000u64 / freq
        }
    }
    frame.x[0usize] = nanos
    frame.x[1usize] = 0u64
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
    if ptr < vm.USER_BASE || ptr + len > vm.USER_BASE + thread.current_window() { ret }
    var i = 0usize
    while i < len {
        if console_ns16550 { ns16550.put(uart, console_shift, os.load8(ptr + i)) } else { pl011.put(uart, os.load8(ptr + i)) }
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
                // And the device notification as a wake-up safety net (D2141): a driver server
                // blocked on its interrupt wakes at the next tick even if the device interrupt
                // never arrives, then confirms completion by polling -- so it can never hang on a
                // mis-routed interrupt, while `device_irqs` still records whether the real one came.
                thread.signal_notification(DEVICE_NOTIFICATION, 1usize)
                thread.on_timer(frame)
            }
            // A virtio device's completion interrupt (D2141): acknowledge it and wake its server.
            if intid >= PCIE_INTX_FIRST && intid <= PCIE_INTX_LAST { handle_device_irq() }
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
            let more = thread.finish_current(frame, thread.FAULT_CODE)
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
    let arg_off = space.arg_off
    let strings = arg_off + count * 16usize
    var i = 0usize
    while i < name.len {
        vm.put_byte(space, strings + i, name[i])
        i += 1usize
    }
    vm.put_word(space, arg_off, vm.address(strings))
    vm.put_word(space, arg_off + 8usize, name.len)
    if hostile {
        vm.put_word(space, arg_off + 16usize, kernel_pointer)
        vm.put_word(space, arg_off + 24usize, 8usize)
    }
    ret (vm.address(arg_off), count)
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

// One virtio driver as a real EL0 user-mode server (D2138, D2139): the kernel finds the device
// of `want_type`, discovers it (assigning its BAR from `bar`), maps the BAR region (Device) and
// a fresh 128 KB identity DMA pool (Normal) into the server's space with `map_range_el0`, leaves
// the addresses in the aux area, and adds the thread under `name` with a console capability. The
// server runs the same transport at EL0, holding only its device's frames -- every other
// gigabyte stays privileged in its space, so a stray access faults. Aux: 0 common, 1 notify,
// 2 notify multiplier, 3 pool base, 4 pool size, 5 device config (the vsock CID lives there,
// D2149). The MMIO cursor past this BAR comes back so the
// next server gets a disjoint window. A device that is absent is skipped, cursor unchanged.
fn start_driver_server(a: *mem.Arena, image_addr: usize, image_len: usize, asid: usize, host: pci.Host, bar: usize, want_type: usize, name: str) -> (usize, err) {
    var slot = 0usize
    var found = 32usize
    while slot < 32usize {
        let (device_type, is_virtio) = pci.virtio_type(host, 0usize, slot, 0usize)
        if is_virtio && device_type == want_type { found = slot }
        slot += 1usize
    }
    if found == 32usize { ret (bar, ok) }
    let (device, cursor, discover_error) = virtio.discover(host, found, bar)
    if discover_error != ok { ret (bar, ok) }
    let (space_base, space_error) = vm.create(a, image_addr, image_len, asid)
    if space_error != ok { ret (bar, space_error) }
    let (space, arena_error) = with_big_arena(space_base)
    if arena_error != ok { ret (bar, arena_error) }
    let map_bar_error = vm.map_range_el0(a, space.ttbr, device.bar, device.bar_size, true)
    if map_bar_error != ok { ret (bar, map_bar_error) }
    let pool_bytes = driver_pool_bytes
    let (pool_storage, pool_error) = mem.alloc[u8](a, pool_bytes + 4096usize)
    if pool_error != ok { ret (bar, pool_error) }
    let pool = (mem.address_of(&pool_storage[0usize]) + 4095usize) & ~4095usize
    let map_pool_error = vm.map_range_el0(a, space.ttbr, pool, pool_bytes, false)
    if map_pool_error != ok { ret (bar, map_pool_error) }
    vm.put_aux(space, 0usize, device.common)
    vm.put_aux(space, 1usize, device.notify)
    vm.put_aux(space, 2usize, usize(device.notify_multiplier))
    vm.put_aux(space, 3usize, pool)
    vm.put_aux(space, 4usize, pool_bytes)
    vm.put_aux(space, 5usize, device.config)
    let (arg_table, arg_count) = setup_args(space, name, 0usize, false)
    let index = thread.add(space, name, arg_table, arg_count)
    if index == thread.MAX_THREADS { ret (bar, vm.NoSpace) }
    thread.grant(index, 0usize, thread.CAP_CONSOLE, thread.RIGHT_WRITE, 0usize)
    // The device's ISR register, so the kernel's interrupt handler can acknowledge this device's
    // INTx; and a notification capability (notification 1) the server waits on for its interrupt.
    record_isr(device.isr)
    thread.grant(index, 1usize, thread.CAP_NOTIFICATION, thread.RIGHT_RECV, DEVICE_NOTIFICATION)
    last_server_index = index
    ret (cursor, ok)
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
        // A whole word: `prodshell` must not match `shell` (that started the shell init beside the compositor).
        let starts = at == 0usize || text[at - 1usize] == 32u8
        let ends = at + word.len == text.len || text[at + word.len] == 32u8
        if starts && ends && fdt.same(text[at..at + word.len], word) { ret true }
        at += 1usize
    }
    ret false
}

// (D2151) Parse the initrd as a program archive: a 4-byte magic, a program count, then each
// program's 8-byte offset and length within the archive. False when the magic is wrong.
fn parse_archive(base: usize) -> bool {
    if u32(os.load32(base)) != ARCHIVE_MAGIC { ret false }
    archive_base = base
    var count = usize(os.load32(base + 4usize))
    if count > MAX_ARCHIVE { count = MAX_ARCHIVE }
    archive_count = count
    var i = 0usize
    while i < count {
        archive_offset[i] = usize(os.load64(base + 8usize + i * 16usize))
        archive_length[i] = usize(os.load64(base + 16usize + i * 16usize))
        i += 1usize
    }
    ret true
}

// (D2151) A process from an image at [image_addr, image_addr+image_len): a fresh address space
// over the image, an empty capability space but for a console capability so it can print, and a
// scheduler entry. Its parent is whatever thread is current -- none at boot (the shell `init`),
// the launcher under the `launch` system call. The thread index comes back.
fn start_process(image_addr: usize, image_len: usize, name: str) -> (usize, err) {
    next_asid += 1usize
    let (space_base, space_error) = vm.create(kernel_arena, image_addr, image_len, next_asid)
    if space_error != ok { ret (0usize, space_error) }
    let (space, arena_error) = with_big_arena(space_base)
    if arena_error != ok { ret (0usize, arena_error) }
    let (arg_table, arg_count) = setup_args(space, name, 0usize, false)
    let child = thread.add(space, name, arg_table, arg_count)
    if child == thread.MAX_THREADS { ret (0usize, vm.NoSpace) }
    thread.grant(child, 0usize, thread.CAP_CONSOLE, thread.RIGHT_WRITE, 0usize)
    ret (child, ok)
}

// (D2151) `launch(index) -> child` (system call 11): build a new process from program `index` of
// the initrd archive and return its id, the current thread recorded as its parent so a later
// `reap` collects it. An index past the archive, or a space or table that will not take it, gives
// the all-ones sentinel.
fn launch(frame: *a64.Frame) {
    let index = usize(frame.x[0usize])
    if index >= archive_count {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    let (child, child_error) = start_process(archive_base + archive_offset[index], archive_length[index], "child")
    if child_error != ok {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    frame.x[0usize] = u64(child)
}

fn main(a: *mem.Arena, args: []str) -> err {
    os.set_exit(power_off)
    // (D2151) Keep the arena for the `launch` system call, which builds a new process's space.
    kernel_arena = a
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
    // Which UART: crosvm's AVF guest names it `ns16550a` (D2144), QEMU's virt `arm,pl011`. The
    // ns16550 needs no enable and its registers are `reg-shift` bytes apart (absent means 0);
    // the PL011 is turned on. Everything is read from the device tree, never hard-coded.
    let (uart_compatible, uart_compatible_error) = fdt.property(tree, uart, "compatible")
    if uart_compatible_error == ok && has_word(uart_compatible, "ns16550") {
        console_ns16550 = true
        let (reg_shift, reg_shift_error) = fdt.property(tree, uart, "reg-shift")
        if reg_shift_error == ok && reg_shift.len >= 4usize { console_shift = usize(fdt.be32(reg_shift, 0usize)) }
    } else {
        pl011.enable(console)
    }
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
    // Every virtio driver now runs at EL0 as a user-mode server (D2138, D2139): the kernel only
    // enumerates here and sets up one server per device in the thread section below, threading a
    // BAR cursor so their MMIO windows are disjoint. Nothing is driven in the kernel.
    // The interrupt controller and the timer: enable the controller, let this core take the
    // virtual-timer PPI, and arm it. Each firing preempts whatever runs.
    let (found, controller_error) = gic.find(tree)
    if controller_error != ok { ret controller_error }
    controller = found
    gic.enable(controller)
    gic.enable_private(controller, timer.INTID)
    // The four PCIe INTx lines, so a virtio device's completion wakes its driver server (D2141).
    var intx = PCIE_INTX_FIRST
    while intx <= PCIE_INTX_LAST {
        gic.enable_spi(controller, intx)
        intx += 1usize
    }
    timer.arm(TICKS_PER_SECOND)
    // (D2155, C107) The real-time clock the device tree names (PL031 on QEMU virt), for the
    // wall-clock system call. Absent one, wall time falls back to the monotonic counter.
    let (rtc_node, rtc_node_error) = fdt.find_compatible(tree, "arm,pl031")
    if rtc_node_error == ok {
        let (rtc_addr, rtc_size, rtc_region_error) = fdt.region(tree, rtc_node)
        if rtc_region_error == ok { rtc_base = usize(rtc_addr) }
    }
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
    // (D2151, C105) The shell boot (`-append shell`): the initrd is a program archive, not a
    // single image. Parse it and start program 0 as `init`; init launches the rest with the
    // `launch`/`reap` system calls. The capability demo (A-Z) runs on the default boot instead.
    let shell_mode = bootargs_error == ok && has_word(bootargs, "shell")
    if shell_mode {
        if !parse_archive(image_addr) { ret BadArchive }
        let (shell_init, shell_init_error) = start_process(archive_base + archive_offset[0usize], archive_length[0usize], "init")
        if shell_init_error != ok { ret shell_init_error }
    }
    // (D2153, C106) The filesystem-server boot (`-append fsserver fswrite` / `fsserver fsread`):
    // the initrd is an archive of three programs. Program 0 is the filesystem server, started with
    // start_driver_server so it alone holds the block device's capability; the kernel then grants
    // it the request endpoint (slot 2, receive) and the reply endpoint (slot 3, send). Program 1 is
    // a client, granted the matching endpoints (request-send slot 1, reply-receive slot 2) and a
    // scenario from the boot arg -- `fswrite` writes a file, `fsread` reads it back, so writing on
    // one boot and reading on the next over the same disk proves persistence through the server.
    // Program 2 is a client granted no endpoints: its send is refused, the capability gate.
    let fsserver_mode = bootargs_error == ok && has_word(bootargs, "fsserver")
    if fsserver_mode {
        if pci_host_error != ok { ret NoInitrd }
        if !parse_archive(image_addr) { ret BadArchive }
        last_server_index = thread.MAX_THREADS
        let (srv_bar, srv_error) = start_driver_server(a, archive_base + archive_offset[0usize], archive_length[0usize], 1usize, pci_host, pci_host.mmio, pci.VIRTIO_BLOCK, "fs")
        if srv_error != ok { ret srv_error }
        if last_server_index == thread.MAX_THREADS { ret NoInitrd }
        thread.grant(last_server_index, 2usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 0usize)
        thread.grant(last_server_index, 3usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 1usize)
        // The server took ASID 1; the clients start from 2 so no two spaces share an ASID.
        next_asid = 1usize
        var client_name = "read"
        if has_word(bootargs, "fswrite") { client_name = "write" }
        // A client that renders (e.gpu/e.ui) needs the large arena, like the gpu boot. `bigarena`
        // gives program 1 the 16 MB arena; the server and denied client keep their small arenas.
        if has_word(bootargs, "bigarena") { driver_arena_bytes = 16777216usize }
        let (client, client_error) = start_process(archive_base + archive_offset[1usize], archive_length[1usize], client_name)
        driver_arena_bytes = 0usize
        if client_error != ok { ret client_error }
        thread.grant(client, 1usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 0usize)
        thread.grant(client, 2usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 1usize)
        let (denied, denied_error) = start_process(archive_base + archive_offset[2usize], archive_length[2usize], "denied")
        if denied_error != ok { ret denied_error }
    }
    // (D2152, C106) The filesystem boot (`-append fswrite` / `fsread`): the initrd is the fs test
    // program, started as the sole holder of the block device. `fswrite` formats (if the disk is
    // blank) and writes a file; `fsread` reads it back, so a reboot on the same disk image proves
    // the filesystem persists.
    let fs_mode = bootargs_error == ok && !fsserver_mode && (has_word(bootargs, "fswrite") || has_word(bootargs, "fsread"))
    if fs_mode {
        if pci_host_error != ok { ret NoInitrd }
        var fs_name = "fsread"
        if has_word(bootargs, "fswrite") { fs_name = "fswrite" }
        let (fs_bar, fs_error) = start_driver_server(a, image_addr, image_len, 1usize, pci_host, pci_host.mmio, pci.VIRTIO_BLOCK, fs_name)
        if fs_error != ok { ret fs_error }
    }
    // (D2159, C108) The display boot (`-append gpu`): the initrd is the GPU driver program, started
    // as the sole holder of the virtio-gpu scanout via start_driver_server, with a pool large enough
    // for the display's framebuffer. It reads the mode, draws a test pattern and flushes it; a QEMU
    // screendump of the result is checked against a golden hash.
    let gpu_mode = bootargs_error == ok && has_word(bootargs, "gpu")
    if gpu_mode {
        if pci_host_error != ok { ret NoInitrd }
        driver_pool_bytes = 4194304usize
        // A large arena when the program asks for it (`-append gpu bigarena`), for the e.gpu/e.ui
        // stack; the plain test pattern and gfx.paint scenes keep the small in-window arena.
        if has_word(bootargs, "bigarena") { driver_arena_bytes = 16777216usize }
        let (gpu_bar, gpu_error) = start_driver_server(a, image_addr, image_len, 1usize, pci_host, pci_host.mmio, pci.VIRTIO_GPU, "gpu")
        if gpu_error != ok { ret gpu_error }
        driver_arena_bytes = 0usize
    }
    // (D2160, C109) The input boot (`-append input`): the initrd is an archive of two programs. The
    // input server (program 0) alone holds the virtio-input device and the notification bound to its
    // interrupt, and pushes each event to the client over endpoint 0 (send, slot 2). The client
    // (program 1) holds only that endpoint (receive, slot 1) and prints the events. A QEMU fixture
    // injects taps and keys through the monitor and asserts the stream the client receives.
    let input_mode = bootargs_error == ok && has_word(bootargs, "input")
    if input_mode {
        if pci_host_error != ok { ret NoInitrd }
        if !parse_archive(image_addr) { ret BadArchive }
        last_server_index = thread.MAX_THREADS
        let (input_bar, input_error) = start_driver_server(a, archive_base + archive_offset[0usize], archive_length[0usize], 1usize, pci_host, pci_host.mmio, pci.VIRTIO_INPUT, "input")
        if input_error != ok { ret input_error }
        if last_server_index == thread.MAX_THREADS { ret NoInitrd }
        thread.grant(last_server_index, 2usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 0usize)
        next_asid = 1usize
        let (input_client, input_client_error) = start_process(archive_base + archive_offset[1usize], archive_length[1usize], "client")
        if input_client_error != ok { ret input_client_error }
        thread.grant(input_client, 1usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 0usize)
    }
    // (D2162, C110) The compositor boot (`-append compositor`): the initrd is an archive of two
    // programs. The compositor (program 0) alone holds the virtio-gpu display; an app (program 1)
    // draws a surface into a frame SHARED with the compositor (the same physical pages mapped into
    // both at vm.SHARED_FRAME_VA) and signals it ready over endpoint 0; the compositor composites
    // the surface into the display and flushes. A QEMU screendump is checked against a golden.
    let compositor_mode = bootargs_error == ok && has_word(bootargs, "compositor")
    if compositor_mode {
        if pci_host_error != ok { ret NoInitrd }
        if !parse_archive(image_addr) { ret BadArchive }
        let (shared_storage, shared_error) = mem.alloc[u8](a, vm.SHARED_FRAME_PAGES * 4096usize + 4096usize)
        if shared_error != ok { ret shared_error }
        let shared_phys = (mem.address_of(&shared_storage[0usize]) + 4095usize) & ~4095usize
        // The frame starts as the compositor's dark ground (B 30, G 30, R 45, opaque), two pixels a
        // store, so what an app has not drawn is not allocator fill.
        var shared_at = 0usize
        while shared_at < vm.SHARED_FRAME_BYTES {
            os.store64(shared_phys + shared_at, 18387385972102602270u64)
            shared_at += 8usize
        }
        // The display framebuffer (the whole screen, BGRA) plus the virtio queues and slack.
        driver_pool_bytes = vm.SHARED_FRAME_BYTES + 2097152usize
        last_server_index = thread.MAX_THREADS
        let (comp_bar, comp_error) = start_driver_server(a, archive_base + archive_offset[0usize], archive_length[0usize], 1usize, pci_host, pci_host.mmio, pci.VIRTIO_GPU, "comp")
        if comp_error != ok { ret comp_error }
        if last_server_index == thread.MAX_THREADS { ret NoInitrd }
        let compositor = last_server_index
        try vm.map_shared(a, thread.ttbr_of(compositor), shared_phys, vm.SHARED_FRAME_PAGES)
        // endpoint 0: the app signals a ready frame (app sends, compositor receives).
        thread.grant(compositor, 2usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 0usize)
        // The input server is optional: a third archive program and a virtio-input device wire input
        // routing (endpoint 1 input->compositor, endpoint 2 compositor->app). Without it the
        // compositor's ungranted input receive returns the sentinel at once, so it simply does not
        // route -- the display path alone still works (and its screendump needs no input device).
        var input_present = false
        // The MMIO cursor past the servers started so far, so the next device gets a disjoint window.
        var next_bar = comp_bar
        if archive_count >= 3usize {
            driver_pool_bytes = 131072usize
            last_server_index = thread.MAX_THREADS
            let (input_bar, input_error) = start_driver_server(a, archive_base + archive_offset[2usize], archive_length[2usize], 3usize, pci_host, comp_bar, pci.VIRTIO_INPUT, "input")
            if input_error != ok { ret input_error }
            next_bar = input_bar
            if last_server_index != thread.MAX_THREADS {
                input_present = true
                thread.grant(last_server_index, 2usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 1usize)
                thread.grant(compositor, 3usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 1usize)
                thread.grant(compositor, 4usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 2usize)
            }
        }
        next_asid = 1usize
        // An e.ui app (the window backend over e.gpu) needs the large arena, like the gpu boot; a
        // paint-only app does not. `-append "compositor bigarena"` gives the app 16 MB (the input
        // server above is already started, so it keeps its small arena). Reset after, so nothing else
        // inherits it. Without bigarena the app gets the in-window arena and the comp golden is
        // byte-unchanged.
        // A full-screen window's renderer holds several frame-sized buffers (about 12 bytes a pixel
        // plus the target and its scratch), so the app's arena is sized from the screen: 160 MB at
        // 1280x2856.
        if has_word(bootargs, "bigarena") { driver_arena_bytes = vm.SHARED_FRAME_BYTES * 11usize }
        let (comp_app, comp_app_error) = start_process(archive_base + archive_offset[1usize], archive_length[1usize], "app")
        driver_arena_bytes = 0usize
        if comp_app_error != ok { ret comp_app_error }
        try vm.map_shared(a, thread.ttbr_of(comp_app), shared_phys, vm.SHARED_FRAME_PAGES)
        thread.grant(comp_app, 1usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 0usize)
        if input_present { thread.grant(comp_app, 2usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 2usize) }
        // (D2195) The unified shell's status service: program 4, a second process beside the shell. It
        // serves over endpoints 3 (request, the shell sends) and 4 (reply, the shell receives).
        if has_word(bootargs, "unified") {
            // The input server holds ASID 3, so the status process starts above it.
            next_asid = 3usize
            let (unified_status, unified_status_error) = start_process(archive_base + archive_offset[4usize], archive_length[4usize], "status")
            if unified_status_error != ok { ret unified_status_error }
            thread.grant(unified_status, 2usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 3usize)
            thread.grant(unified_status, 3usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 4usize)
            thread.grant(comp_app, 3usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 3usize)
            thread.grant(comp_app, 4usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 4usize)
            // (D2196) The wallpaper from the C106 filesystem: program 5 is the fs server, the sole
            // holder of the block device (ASID 5), serving endpoints 6 (request) and 7 (reply); program
            // 6 is its client, which reads /wall.png and sends it to the shell over endpoint 5.
            last_server_index = thread.MAX_THREADS
            let (unified_fs_bar, unified_fs_error) = start_driver_server(a, archive_base + archive_offset[5usize], archive_length[5usize], 5usize, pci_host, next_bar, pci.VIRTIO_BLOCK, "fs")
            if unified_fs_error != ok { ret unified_fs_error }
            if last_server_index != thread.MAX_THREADS {
                thread.grant(last_server_index, 2usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 6usize)
                thread.grant(last_server_index, 3usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 7usize)
                next_asid = 5usize
                driver_arena_bytes = 16777216usize
                let (loader, loader_error) = start_process(archive_base + archive_offset[6usize], archive_length[6usize], "wall")
                driver_arena_bytes = 0usize
                if loader_error != ok { ret loader_error }
                thread.grant(loader, 1usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 6usize)
                thread.grant(loader, 2usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 7usize)
                thread.grant(loader, 3usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 5usize)
                thread.grant(comp_app, 5usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 5usize)
            }
        }
    }
    // (D2171, C111) The status-service boot (`-append statussvc`): the initrd is an archive of the
    // status server (program 0) and a client (program 1), no device and no disk. The server holds the
    // system status and serves one protocol over two endpoints (0 request, 1 reply); the client
    // subscribes, reports each field, posts a notification and reports the raised count. On QEMU virt
    // the clock is the only live provider; battery and radio report absent.
    let status_mode = bootargs_error == ok && has_word(bootargs, "statussvc")
    if status_mode {
        if !parse_archive(image_addr) { ret BadArchive }
        next_asid = 0usize
        let (status_server, status_server_error) = start_process(archive_base + archive_offset[0usize], archive_length[0usize], "status")
        if status_server_error != ok { ret status_server_error }
        thread.grant(status_server, 2usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 0usize)
        thread.grant(status_server, 3usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 1usize)
        // A status client that renders (the launcher reading the top-bar status) needs the large
        // arena; a plain reporting client does not. `bigarena` gives program 1 the 16 MB arena.
        if has_word(bootargs, "bigarena") { driver_arena_bytes = 16777216usize }
        let (status_client, status_client_error) = start_process(archive_base + archive_offset[1usize], archive_length[1usize], "app")
        driver_arena_bytes = 0usize
        if status_client_error != ok { ret status_client_error }
        thread.grant(status_client, 1usize, thread.CAP_ENDPOINT, thread.RIGHT_SEND, 0usize)
        thread.grant(status_client, 2usize, thread.CAP_ENDPOINT, thread.RIGHT_RECV, 1usize)
    }
    if !shell_mode && !fs_mode && !fsserver_mode && !gpu_mode && !input_mode && !compositor_mode && !status_mode {
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
    // Z exercises the EL0 raw-memory intrinsics (D2134) on its own stack, the foundation for
    // moving the virtio drivers out of the kernel into EL0 user-mode servers.
    try start_thread(a, image_addr, image_len, 15usize, "Z", 0usize, false, true, 0u8, 0usize, false, false, false, 0usize)
    // E, F and O are the entropy, block and console drivers as real EL0 user-mode servers
    // (D2138, D2139): the kernel maps each device's BAR and a DMA pool into the server's space
    // and hands it off, threading a BAR cursor so the windows are disjoint. Each drives its
    // device from EL0 over the shared transport, holding only its own frames.
    if pci_host_error == ok {
        let (bar_after_e, entropy_error) = start_driver_server(a, image_addr, image_len, 16usize, pci_host, pci_host.mmio, pci.VIRTIO_ENTROPY, "E")
        if entropy_error != ok { ret entropy_error }
        let (bar_after_f, block_error) = start_driver_server(a, image_addr, image_len, 17usize, pci_host, bar_after_e, pci.VIRTIO_BLOCK, "F")
        if block_error != ok { ret block_error }
        let (bar_after_o, console_error) = start_driver_server(a, image_addr, image_len, 18usize, pci_host, bar_after_f, pci.VIRTIO_CONSOLE, "O")
        if console_error != ok { ret console_error }
        // T is the vsock driver server (D2149): it opens a STREAM connection to a host port and
        // reports the guest CID and the host's reply. Absent a vsock device it is skipped.
        let (bar_after_t, vsock_error) = start_driver_server(a, image_addr, image_len, 20usize, pci_host, bar_after_o, pci.VIRTIO_VSOCK, "T")
        if vsock_error != ok { ret vsock_error }
        // Q proves the servers' confinement from the other side (D2140): it is handed the PCI
        // ECAM base -- device memory no driver granted it -- and tries to read it at EL0. That
        // gigabyte is privileged in Q's space, so the read faults and the kernel kills Q before
        // its post-read line prints, exactly as a driver reaching past its own frames would fault.
        try start_thread(a, image_addr, image_len, 19usize, "Q", pci_host.ecam, true, true, 0u8, 0usize, false, false, false, 0usize)
    }
    }
    console_write("scheduling\n")
    // The scheduler runs from here: the first timer tick leaves this loop for a thread, and
    // the last thread to finish returns the kernel here with nothing left to run.
    a64.enable_irq()
    while thread.running() != 0usize { os.wait_for_interrupt() }
    a64.disable_irq()
    timer.stop()
    // Whether any virtio device raised its completion interrupt (D2141): if so the entropy server
    // woke on its notification rather than only the fallback spin, so the interrupt path works.
    if device_irqs != 0usize { console_write("virtio irq ok\n") }
    console_write("all threads done\n")
    ret ok
}
