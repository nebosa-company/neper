.text

// The aarch64 runtime of a program NeperOS runs at EL0, OS `neperos` (D2127). One file,
// embedded whole into `runtime_neperos_a64.e` by scripts/embed-elf-runtime.ps1 -Arch
// neperos. Order matters as in runtime_elf_a64.s: the linker appends this runtime cut
// after the last function the program reaches, so a function may call only what precedes
// it; all up to and including `neper_start_arena` is always kept. Every reference to a
// symbol of this file is to a local label.
//
// The kernel is reached by `svc #0` alone, the call's number in x8 and its arguments in
// x0-x3, its answer in x0:
//   0  console write: x0 the bytes' address, x1 their count; the count written
//   1  exit: x0 the status; does not return
//   2  yield: the rest of this time slice to the next thread

// The entry, at EL0 with SP_EL0 the top of the stack the kernel mapped, x0 and x1 the
// argument table (slices into memory the kernel wrote) and its count, x2 and x3 the root
// arena's address and size. `main(&arena, &args)` is called, and its return exits: status
// 1 when it returned an error.
.global neper_start
neper_start:
.Lstart:
    sub sp, sp, #48
    stp x2, x3, [sp]
    str xzr, [sp, #16]
    stp x0, x1, [sp, #24]
    mov x0, sp
    add x1, sp, #24
    mov x29, #0
    mov x30, #0
.global neper_start_main
neper_start_main:
    bl .
    cmp w0, #0
    cset x0, ne
    b np_exit

// neper_start's offset in the image: the trap takes the image's address off a return
// address before looking it up.
    .p2align 3
.global neper_start_image
neper_start_image:
.Lstart_image:
    .quad 0

// The exit call with the status in x0.
np_exit:
    mov x8, #1
    svc #0
    b np_exit

// x1 and x2 bytes to the console.
np_text:
    mov x0, x1
    mov x1, x2
    mov x8, #0
    svc #0
    ret

// The byte in w0 to the console.
np_char:
    sub sp, sp, #16
    strb w0, [sp]
    mov x0, sp
    mov x1, #1
    mov x8, #0
    svc #0
    add sp, sp, #16
    ret

// x0 in decimal to the console.
np_number:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    add x9, sp, #48
    mov x10, #10
.Lnumber_digit:
    udiv x11, x0, x10
    msub x12, x11, x10, x0
    add w12, w12, #48
    strb w12, [x9, #-1]!
    mov x0, x11
    cbnz x0, .Lnumber_digit
    mov x1, x9
    add x2, sp, #48
    sub x2, x2, x9
    bl np_text
    ldp x29, x30, [sp], #48
    ret

// The root arena's size: the kernel's to choose, so the literal the linker patches is
// unused here and kept only for the cut.
    .p2align 3
.global neper_start_arena
neper_start_arena:
    .quad 0

// `size` bytes of the arena at x0, aligned to x2 (a power of two): the address, or zero.
np_alloc:
    cbz x0, .Lalloc_fail
    cbz x2, .Lalloc_fail
    sub x3, x2, #1
    tst x2, x3
    b.ne .Lalloc_fail
    ldr x4, [x0, #16]
    adds x4, x4, x3
    b.cs .Lalloc_fail
    neg x5, x2
    and x4, x4, x5
    ldr x5, [x0, #8]
    cmp x4, x5
    b.hi .Lalloc_fail
    sub x5, x5, x4
    cmp x1, x5
    b.hi .Lalloc_fail
    add x6, x4, x1
    str x6, [x0, #16]
    ldr x7, [x0]
    cbz x7, .Lalloc_fail
    add x0, x7, x4
    ret
.Lalloc_fail:
    mov x0, #0
    ret

// mem.alloc: the result {data, len, err} at x0, from the arena at x1, x2 elements of x3
// bytes aligned to x4.
.global neper_mem_alloc
neper_mem_alloc:
np_mem_alloc:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    mov x20, x2
    stp xzr, xzr, [x19]
    str wzr, [x19, #16]
    umulh x9, x2, x3
    cbnz x9, .Lmem_alloc_fail
    mul x9, x2, x3
    mov x0, x1
    mov x1, x9
    mov x2, x4
    bl np_alloc
    cbz x0, .Lmem_alloc_fail
    stp x0, x20, [x19]
    b .Lmem_alloc_done
.Lmem_alloc_fail:
    movz w9, #0x623a
    movk w9, #0x8f63, lsl #16
    str w9, [x19, #16]
.Lmem_alloc_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// Section 11's debug fill (D217): the allocation, then every byte of it 0xCD.
.global neper_mem_alloc_fill
neper_mem_alloc_fill:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    mul x20, x2, x3
    bl np_mem_alloc
    ldr w9, [x19, #16]
    cbnz w9, .Lalloc_fill_done
    ldr x9, [x19]
    mov w10, #0xcd
.Lalloc_fill_byte:
    cbz x20, .Lalloc_fill_done
    strb w10, [x9], #1
    sub x20, x20, #1
    b .Lalloc_fill_byte
.Lalloc_fill_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.global neper_mem_mark
neper_mem_mark:
    ldr x0, [x0, #16]
    ret

.global neper_mem_reset
neper_mem_reset:
    str x1, [x0, #16]
    ret

// The other debug fill (D217): what the reset gives back is 0xDD before the offset moves.
.global neper_mem_reset_fill
neper_mem_reset_fill:
    ldr x2, [x0, #16]
    cmp x1, x2
    b.hs .Lreset_fill_store
    ldr x3, [x0]
    add x4, x3, x1
    add x5, x3, x2
    mov w6, #0xdd
.Lreset_fill_byte:
    strb w6, [x4], #1
    cmp x4, x5
    b.lo .Lreset_fill_byte
.Lreset_fill_store:
    str x1, [x0, #16]
    ret

.global neper_mem_stats
neper_mem_stats:
    ldr x2, [x1, #16]
    str x2, [x0]
    ldr x2, [x1, #8]
    str x2, [x0, #8]
    ret

// Both standard streams are the console.
.global neper_os_stdout
neper_os_stdout:
    mov x1, #1
    str x1, [x0]
    ret

.global neper_os_stderr
neper_os_stderr:
    mov x1, #2
    str x1, [x0]
    ret

.global neper_os_exit
neper_os_exit:
    b np_exit

// os.write(file: *File, bytes: *[]const u8) -> (usize, err): the bytes to the console,
// whichever file.
.global neper_os_write
neper_os_write:
    ldr x2, [x1, #8]
    ldr x1, [x1]
    mov x0, x1
    mov x1, x2
    mov x8, #0
    svc #0
    mov x1, #0
    ret

// os.copy_bytes(dst: *[]u8, src: *[]const u8) (D329): the shorter length's worth of
// bytes, forwards.
.global neper_os_copy_bytes
neper_os_copy_bytes:
    ldr x2, [x0, #8]
    ldr x3, [x1, #8]
    cmp x3, x2
    csel x2, x3, x2, lo
    ldr x0, [x0]
    ldr x1, [x1]
.Lcopy_bytes_word:
    cmp x2, #8
    b.lo .Lcopy_bytes_byte
    ldr x3, [x1], #8
    str x3, [x0], #8
    sub x2, x2, #8
    b .Lcopy_bytes_word
.Lcopy_bytes_byte:
    cbz x2, .Lcopy_bytes_done
    ldrb w3, [x1], #1
    strb w3, [x0], #1
    sub x2, x2, #1
    b .Lcopy_bytes_byte
.Lcopy_bytes_done:
    ret

.global neper_os_sha256_blocks
neper_os_sha256_blocks:
    mov x0, #0
    ret

.global neper_os_crc32c_bytes
neper_os_crc32c_bytes:
    ldr x2, [x1, #8]
    ldr x3, [x1]
    ldr x4, [x0]
    ldr w5, [x4]
    mov x0, x2
    lsr x6, x2, #3
.Lcrc_words:
    cbz x6, .Lcrc_tail
    ldr x7, [x3], #8
    crc32cx w5, w5, x7
    sub x6, x6, #1
    b .Lcrc_words
.Lcrc_tail:
    and x6, x2, #7
.Lcrc_bytes:
    cbz x6, .Lcrc_store
    ldrb w7, [x3], #1
    crc32cb w5, w5, w7
    sub x6, x6, #1
    b .Lcrc_bytes
.Lcrc_store:
    str x5, [x4]
    ret

// os.yield(): the rest of this time slice to the next thread.
.global neper_os_yield
neper_os_yield:
    mov x8, #2
    svc #0
    ret

// os.send(endpoint: usize, word: usize) -> usize: block until a receiver takes the word;
// x0 the endpoint, x1 the word, x0 the status back.
.global neper_os_send
neper_os_send:
    mov x8, #3
    svc #0
    ret

// os.recv(endpoint: usize) -> usize: block until a sender's word arrives; x0 the endpoint,
// x0 the word back.
.global neper_os_recv
neper_os_recv:
    mov x8, #4
    svc #0
    ret

// os.cap_derive(source, dest, drop_rights) -> usize.
.global neper_os_cap_derive
neper_os_cap_derive:
    mov x8, #5
    svc #0
    ret

// os.cap_revoke(slot) -> usize.
.global neper_os_cap_revoke
neper_os_cap_revoke:
    mov x8, #6
    svc #0
    ret

// os.frame_protect(slot) -> usize.
.global neper_os_frame_protect
neper_os_frame_protect:
    mov x8, #7
    svc #0
    ret

// os.notify_wait(slot) -> usize: block until the notification is signalled, the pending
// bits back in x0.
.global neper_os_notify_wait
neper_os_notify_wait:
    mov x8, #8
    svc #0
    ret

// os.device_write(slot, address, length) -> usize: write a run of bytes to the device the
// capability names.
.global neper_os_device_write
neper_os_device_write:
    mov x8, #9
    svc #0
    ret

// os.retype(untyped, kind, dest) -> usize: carve an object from untyped memory.
.global neper_os_retype
neper_os_retype:
    mov x8, #10
    svc #0
    ret

// (D2134) Raw memory access from EL0, for a user-mode driver reaching its device's MMIO and
// virtqueue rings through pages the kernel mapped into its space. Each is a plain load or
// store -- no svc -- so it faults if the page is not mapped with EL0 access, which is how a
// driver is confined to its own device's frames. Identical bodies to runtime_none_a64.s.
.global neper_os_load8
neper_os_load8:
    ldrb w0, [x0]
    ret

.global neper_os_load16
neper_os_load16:
    ldrh w0, [x0]
    ret

.global neper_os_load32
neper_os_load32:
    ldr w0, [x0]
    ret

.global neper_os_load64
neper_os_load64:
    ldr x0, [x0]
    ret

.global neper_os_store8
neper_os_store8:
    strb w1, [x0]
    ret

.global neper_os_store16
neper_os_store16:
    strh w1, [x0]
    ret

.global neper_os_store32
neper_os_store32:
    str w1, [x0]
    ret

.global neper_os_store64
neper_os_store64:
    str x1, [x0]
    ret

// A full barrier, as runtime_none_a64.s: every access before it completes, instructions
// refetched -- ordering a driver's ring writes before it notifies the device.
.global neper_os_barrier
neper_os_barrier:
    dsb sy
    isb
    ret

// A ULEB128 at x28 into x0, x28 past it; x9 and x10 are used (D1586).
np_trap_uleb:
    mov x0, #0
    mov x10, #0
.Ltrap_uleb_byte:
    ldrb w9, [x28], #1
    tbnz w9, #7, .Ltrap_uleb_more
    lsl x9, x9, x10
    orr x0, x0, x9
    ret
.Ltrap_uleb_more:
    and x9, x9, #127
    lsl x9, x9, x10
    orr x0, x0, x9
    add x10, x10, #7
    b .Ltrap_uleb_byte

// A failed check (spec section 11), as runtime_none_a64.s prints it: the site, the
// message with its operands, the backtrace from the table at x5 (offsets into the image),
// to the console, and exit 134.
.global neper_trap
neper_trap:
    mov x19, x0
    mov x20, x4
    mov x21, x2
    mov x22, x3
    mov x23, x5
    mov x24, x30
    mov x25, x29
    mov x26, x1
    mov x9, sp
    and x9, x9, #-16
    sub x9, x9, #64
    mov sp, x9
    ldrh w2, [x19]
    add x1, x19, #2
    bl np_text
    mov w0, #58
    bl np_char
    lsr x0, x26, #16
    bl np_number
    mov w0, #58
    bl np_char
    and x0, x26, #0xffff
    bl np_number
    ldrh w9, [x20]
    add x19, x20, #2
    add x20, x19, x9
    mov x27, #0
.Ltrap_segment:
    mov x1, x19
.Ltrap_scan:
    cmp x19, x20
    b.hs .Ltrap_scanned
    ldrb w9, [x19]
    cmp w9, #2
    b.lo .Ltrap_scanned
    add x19, x19, #1
    b .Ltrap_scan
.Ltrap_scanned:
    sub x2, x19, x1
    bl np_text
    cmp x19, x20
    b.hs .Ltrap_end
    ldrb w28, [x19]
    add x19, x19, #1
    mov x0, x21
    cbz x27, .Ltrap_digits
    mov x0, x22
.Ltrap_digits:
    add x27, x27, #1
    cbz w28, .Ltrap_unsigned
    tbz x0, #63, .Ltrap_unsigned
    neg x28, x0
    mov w0, #45
    bl np_char
    mov x0, x28
.Ltrap_unsigned:
    bl np_number
    b .Ltrap_segment
.Ltrap_end:
    mov w0, #10
    bl np_char
    adr x9, .Lstart
    ldr x10, .Lstart_image
    sub x9, x9, x10
    str x9, [sp, #40]
    mov x27, #32
    sub x26, x24, #1
    sub x26, x26, x9
.Ltrap_frame:
    cbz x27, .Ltrap_exit
    sub x27, x27, #1
    mov x9, #0
    ldr w10, [x23, #8]
.Ltrap_search:
    cmp x9, x10
    b.hs .Ltrap_exit
    add x11, x9, x10
    lsr x11, x11, #1
    add x12, x23, x11, lsl #5
    add x12, x12, #12
    ldr x13, [x12]
    cmp x26, x13
    b.lo .Ltrap_lower
    ldr x13, [x12, #8]
    cmp x26, x13
    b.hs .Ltrap_upper
    b .Ltrap_found
.Ltrap_lower:
    mov x10, x11
    b .Ltrap_search
.Ltrap_upper:
    add x9, x11, #1
    b .Ltrap_search
.Ltrap_found:
    ldr x13, [x12]
    sub x21, x26, x13
    mov x22, x12
    adr x1, .Ltrap_at
    mov x2, #5
    bl np_text
    ldr w9, [x22, #16]
    add x1, x23, x9
    ldr w2, [x1]
    add x1, x1, #4
    bl np_text
    ldr w19, [x22, #20]
    ldr w9, [x22, #24]
    add x28, x23, x9
    ldr w20, [x28], #4
    mov x24, #0
    mov x11, #0
    str xzr, [sp, #24]
.Ltrap_row:
    cbz x20, .Ltrap_rows_done
    sub x20, x20, #1
    bl np_trap_uleb
    add x24, x24, x0
    bl np_trap_uleb
    mov x12, x0
    lsr x0, x0, #1
    lsr x13, x0, #1
    and x0, x0, #1
    neg x0, x0
    eor x0, x0, x13
    add x11, x11, x0
    tbz x12, #0, .Ltrap_row_file
    bl np_trap_uleb
    mov x19, x0
.Ltrap_row_file:
    cmp x24, x21
    b.hi .Ltrap_rows_done
    str x19, [sp, #16]
    str x11, [sp, #32]
    mov x9, #1
    str x9, [sp, #24]
    b .Ltrap_row
.Ltrap_rows_done:
    ldr x9, [sp, #24]
    cbz x9, .Ltrap_line_done
    mov w0, #32
    bl np_char
    mov w0, #40
    bl np_char
    ldr x9, [sp, #16]
    add x1, x23, x9
    ldr w2, [x1]
    add x1, x1, #4
    bl np_text
    mov w0, #58
    bl np_char
    ldr x0, [sp, #32]
    bl np_number
    mov w0, #41
    bl np_char
.Ltrap_line_done:
    mov w0, #10
    bl np_char
    cbz x25, .Ltrap_exit
    ldr x26, [x25, #8]
    sub x26, x26, #1
    ldr x9, [sp, #40]
    sub x26, x26, x9
    ldr x25, [x25]
    b .Ltrap_frame
.Ltrap_exit:
    mov x0, #134
    b np_exit
.Ltrap_at:
    .ascii "  at "
    .p2align 2
