.text

// The aarch64 kernel runtime, OS `none` (D2126): no system calls and no memory but the
// image's own. One file, embedded whole into `runtime_none_a64.e` by
// scripts/embed-elf-runtime.ps1 -Arch none.
//
// Order matters as in runtime_elf_a64.s: the linker appends this runtime cut after the
// last function the program reaches, so a function may call only what precedes it. All
// up to and including `neper_start_arena` is always kept: the entry, its literals, the
// hooks and the exception vectors.
//
// The kernel reaches the machine through three hooks it sets with `os.set_console`,
// `os.set_exit` and `os.set_exception`: the console takes every byte `os.write` and a trap
// print, `exit` ends the program (a kernel powers off through PSCI there), and an exception
// gets the interrupted state as a frame it may change before the return. A hook not set
// drops the text, waits for an interrupt forever, or reports the exception and exits 135.
//
// The bss the linker lays after the image's data: the three hook slots and a fourth word,
// then the stack, then the root arena; the image's `image_size` covers all three, so the
// loader keeps the device tree out of them.

// The entry, reached through the header's branch with the MMU off and x0 = the device
// tree's physical address: the bss's hook slots cleared, the stack set, floating point and
// SIMD let through (CPACR_EL1.FPEN), the vectors installed, and `main(&arena, &args)`
// called with one argument, the device tree's bytes (its length the header's big-endian
// `totalsize`). main's return goes to `exit`: status 1 when it returned an error.
.global neper_start
neper_start:
.Lstart:
    mov x19, x0
    adr x20, .Lstart
    ldr x9, .Lstart_bss
    add x21, x20, x9
    stp xzr, xzr, [x21]
    stp xzr, xzr, [x21, #16]
    ldr x9, .Lstart_stack
    add x22, x21, #32
    add x22, x22, x9
    mov sp, x22
    mov x9, #0x300000
    msr cpacr_el1, x9
    adr x9, np_vectors
    msr vbar_el1, x9
    isb
    ldr x23, .Lstart_arena
    mov x10, #0
    cbz x19, .Lstart_tree
    ldr w10, [x19, #4]
    rev w10, w10
.Lstart_tree:
    stp x19, x10, [x22]
    sub sp, sp, #48
    stp x22, x23, [sp]
    mov x9, #16
    str x9, [sp, #16]
    mov x9, #1
    stp x22, x9, [sp, #24]
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

// Bytes from neper_start to the bss, the stack's size, and neper_start's offset in the image
// (the trap subtracts the image's address from a return address to find its function).
// Eight-byte aligned: with the MMU off every access is to Device memory, which faults on
// an unaligned one.
    .p2align 3
.global neper_start_bss
neper_start_bss:
.Lstart_bss:
    .quad 0
.global neper_start_stack
neper_start_stack:
.Lstart_stack:
    .quad 65536
.global neper_start_image
neper_start_image:
.Lstart_image:
    .quad 0

// The bss's address into x9; nothing else is touched.
np_bss:
    adr x9, .Lstart
    ldr x10, .Lstart_bss
    add x9, x9, x10
    ret

// The exit hook with the status in w0, or, without one, wait for an interrupt forever.
np_exit:
    mov x19, x0
    bl np_bss
    ldr x9, [x9, #8]
    mov x0, x19
    cbz x9, .Lexit_wait
    blr x9
.Lexit_wait:
    wfi
    b .Lexit_wait

// x1 and x2 bytes to the console hook, if one is set, as the slice it takes by address.
np_text:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x1, x2, [sp, #16]
    bl np_bss
    ldr x9, [x9]
    cbz x9, .Ltext_done
    add x0, sp, #16
    blr x9
.Ltext_done:
    ldp x29, x30, [sp], #32
    ret

// The byte in w0 to the console.
np_char:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #16
    strb w0, [sp]
    mov x1, sp
    mov x2, #1
    bl np_text
    add sp, sp, #16
    ldp x29, x30, [sp], #16
    ret

// x0 in hexadecimal to the console, sixteen digits.
np_hex:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    add x9, sp, #16
    mov x10, #60
.Lhex_digit:
    lsr x11, x0, x10
    and x11, x11, #15
    cmp x11, #10
    add x12, x11, #48
    add x13, x11, #87
    csel x11, x12, x13, lo
    strb w11, [x9], #1
    subs x10, x10, #4
    b.pl .Lhex_digit
    add x1, sp, #16
    mov x2, #16
    bl np_text
    ldp x29, x30, [sp], #48
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

// Sixteen entries of 128 bytes, the table 2 KB aligned: current EL with SP_EL0, current EL
// with SP_ELx, a lower EL in AArch64 and one in AArch32, each synchronous, IRQ, FIQ and
// SError. Every entry makes the frame, keeps x0 and x1 in it, and passes its number.
//
// The frame, 304 bytes on the EL1 stack: x0-x30 at 0, SP_EL0 at 248, ELR_EL1 at 256,
// SPSR_EL1 at 264, ESR_EL1 at 272, FAR_EL1 at 280, the entry's number at 288. The hook
// may rewrite any of it; ELR, SPSR, SP_EL0 and the registers are restored from it.
    .balign 2048
np_vectors:
    .irp kind, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
    .balign 128
    sub sp, sp, #304
    stp x0, x1, [sp]
    mov x0, #\kind
    b np_vector
    .endr

np_vector:
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    stp x8, x9, [sp, #64]
    stp x10, x11, [sp, #80]
    stp x12, x13, [sp, #96]
    stp x14, x15, [sp, #112]
    stp x16, x17, [sp, #128]
    stp x18, x19, [sp, #144]
    stp x20, x21, [sp, #160]
    stp x22, x23, [sp, #176]
    stp x24, x25, [sp, #192]
    stp x26, x27, [sp, #208]
    stp x28, x29, [sp, #224]
    mrs x9, sp_el0
    stp x30, x9, [sp, #240]
    mrs x9, elr_el1
    mrs x10, spsr_el1
    stp x9, x10, [sp, #256]
    mrs x9, esr_el1
    mrs x10, far_el1
    stp x9, x10, [sp, #272]
    str x0, [sp, #288]
    bl np_bss
    ldr x9, [x9, #16]
    cbz x9, np_unhandled
    mov x0, sp
    mov x29, #0
    blr x9
    ldp x9, x10, [sp, #256]
    msr elr_el1, x9
    msr spsr_el1, x10
    ldp x30, x9, [sp, #240]
    msr sp_el0, x9
    ldp x2, x3, [sp, #16]
    ldp x4, x5, [sp, #32]
    ldp x6, x7, [sp, #48]
    ldp x8, x9, [sp, #64]
    ldp x10, x11, [sp, #80]
    ldp x12, x13, [sp, #96]
    ldp x14, x15, [sp, #112]
    ldp x16, x17, [sp, #128]
    ldp x18, x19, [sp, #144]
    ldp x20, x21, [sp, #160]
    ldp x22, x23, [sp, #176]
    ldp x24, x25, [sp, #192]
    ldp x26, x27, [sp, #208]
    ldp x28, x29, [sp, #224]
    ldp x0, x1, [sp]
    add sp, sp, #304
    eret

// No exception hook: the entry, ESR, FAR and ELR on the console, and exit 135.
np_unhandled:
    mov x19, sp
    adr x1, .Lunhandled_text
    mov x2, #10
    bl np_text
    ldr x0, [x19, #288]
    bl np_number
    adr x1, .Lunhandled_esr
    mov x2, #5
    bl np_text
    ldr x0, [x19, #272]
    bl np_hex
    adr x1, .Lunhandled_far
    mov x2, #5
    bl np_text
    ldr x0, [x19, #280]
    bl np_hex
    adr x1, .Lunhandled_elr
    mov x2, #5
    bl np_text
    ldr x0, [x19, #256]
    bl np_hex
    mov w0, #10
    bl np_char
    mov x0, #135
    b np_exit
.Lunhandled_text:
    .ascii "exception "
.Lunhandled_esr:
    .ascii " esr "
.Lunhandled_far:
    .ascii " far "
.Lunhandled_elr:
    .ascii " elr "
    .p2align 3

// The root arena's size, patched by the linker from --arena.
.global neper_start_arena
neper_start_arena:
.Lstart_arena:
    .quad 0x1000000

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

// os.write(file: *File, bytes: *[]const u8) -> (usize, err): every byte to the console,
// whichever file.
.global neper_os_write
neper_os_write:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    ldr x2, [x1, #8]
    ldr x1, [x1]
    mov x19, x2
    bl np_text
    mov x0, x19
    mov x1, #0
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
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

// The hooks: each stores the function's address in its slot.
.global neper_os_set_console
neper_os_set_console:
    mov x11, x0
    mov x12, x30
    bl np_bss
    str x11, [x9]
    ret x12

.global neper_os_set_exit
neper_os_set_exit:
    mov x11, x0
    mov x12, x30
    bl np_bss
    str x11, [x9, #8]
    ret x12

.global neper_os_set_exception
neper_os_set_exception:
    mov x11, x0
    mov x12, x30
    bl np_bss
    str x11, [x9, #16]
    ret x12

// The machine, one instruction behind each call. Device memory is reached through these
// alone, so no access is merged, split, reordered past another or left out.
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

// A full barrier: every access before it complete, and the instruction stream refetched.
.global neper_os_barrier
neper_os_barrier:
    dsb sy
    isb
    ret

// Memory accesses ordered across the barrier, without waiting for them to complete.
.global neper_os_memory_barrier
neper_os_memory_barrier:
    dmb sy
    ret

.global neper_os_wait_for_interrupt
neper_os_wait_for_interrupt:
    wfi
    ret

// The other side of `send_event`: a core waits here until one is sent, or an interrupt.
.global neper_os_wait_for_event
neper_os_wait_for_event:
    wfe
    ret

.global neper_os_send_event
neper_os_send_event:
    sev
    ret

// Every EL1&0 translation of this VMID dropped, inner shareable, and waited for.
.global neper_os_tlb_flush
neper_os_tlb_flush:
    dsb ishst
    tlbi vmalle1is
    dsb ish
    isb
    ret

// A firmware call: x0 the function, x1-x3 its arguments, x0 the answer (SMCCC).
.global neper_os_hvc
neper_os_hvc:
    hvc #0
    ret

.global neper_os_smc
neper_os_smc:
    smc #0
    ret

// A system register by its `op0:op1:CRn:CRm:op2` number in x0, one table entry per register
// the kernel may reach: the number, then the access, then the return. A number not in the
// table goes to the console and exits 136.
.macro np_register op0, op1, crn, crm, op2
    .word (\op0 << 14) | (\op1 << 11) | (\crn << 7) | (\crm << 3) | \op2
    np_access s\op0\()_\op1\()_c\crn\()_c\crm\()_\op2
    ret
.endm

.macro np_registers
    np_register 3, 0, 0, 0, 0
    np_register 3, 0, 0, 0, 5
    np_register 3, 0, 0, 4, 0
    np_register 3, 0, 0, 6, 0
    np_register 3, 0, 0, 7, 0
    np_register 3, 0, 1, 0, 0
    np_register 3, 0, 1, 0, 2
    np_register 3, 0, 2, 0, 0
    np_register 3, 0, 2, 0, 1
    np_register 3, 0, 2, 0, 2
    np_register 3, 0, 4, 0, 0
    np_register 3, 0, 4, 0, 1
    np_register 3, 0, 4, 1, 0
    np_register 3, 0, 4, 2, 2
    np_register 3, 0, 4, 2, 3
    np_register 3, 0, 4, 6, 0
    np_register 3, 0, 5, 2, 0
    np_register 3, 0, 6, 0, 0
    np_register 3, 0, 7, 4, 0
    np_register 3, 0, 10, 2, 0
    np_register 3, 0, 12, 0, 0
    np_register 3, 0, 12, 11, 1
    np_register 3, 0, 12, 11, 3
    np_register 3, 0, 12, 11, 5
    np_register 3, 0, 12, 12, 0
    np_register 3, 0, 12, 12, 1
    np_register 3, 0, 12, 12, 3
    np_register 3, 0, 12, 12, 4
    np_register 3, 0, 12, 12, 5
    np_register 3, 0, 12, 12, 7
    np_register 3, 0, 13, 0, 1
    np_register 3, 0, 13, 0, 4
    np_register 3, 0, 14, 1, 0
    np_register 3, 3, 4, 2, 1
    np_register 3, 3, 13, 0, 2
    np_register 3, 3, 13, 0, 3
    np_register 3, 3, 14, 0, 0
    np_register 3, 3, 14, 0, 1
    np_register 3, 3, 14, 0, 2
    np_register 3, 3, 14, 2, 0
    np_register 3, 3, 14, 2, 1
    np_register 3, 3, 14, 2, 2
    np_register 3, 3, 14, 3, 0
    np_register 3, 3, 14, 3, 1
    np_register 3, 3, 14, 3, 2
    .word 0
.endm

// The entry for the number in w0 found from x9, then entered; x10 is used.
np_register_find:
    ldr w10, [x9]
    cbz w10, .Lregister_unknown
    cmp w10, w0
    b.eq .Lregister_found
    add x9, x9, #12
    b np_register_find
.Lregister_found:
    add x9, x9, #4
    br x9
.Lregister_unknown:
    mov x19, x0
    adr x1, .Lregister_text
    mov x2, #24
    bl np_text
    mov x0, x19
    bl np_number
    mov w0, #10
    bl np_char
    mov x0, #136
    b np_exit
.Lregister_text:
    .ascii "unknown system register "
    .p2align 2

// os.mrs(register: usize) -> usize.
.global neper_os_mrs
neper_os_mrs:
    adr x9, .Lmrs_table
    b np_register_find
.macro np_access name
    mrs x0, \name
.endm
.Lmrs_table:
    np_registers
.purgem np_access

// os.msr(register: usize, value: usize).
.global neper_os_msr
neper_os_msr:
    adr x9, .Lmsr_table
    b np_register_find
.macro np_access name
    msr \name, x1
.endm
.Lmsr_table:
    np_registers
.purgem np_access

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

// A failed check (spec section 11), as runtime_elf_a64.s prints it but to the console:
// the site's path, `:line:column`, the message with its operands, a newline, the
// backtrace looked up in the table at x5 -- whose addresses are offsets into the image, so
// each return address has the image's own address taken off first -- and exit 134.
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
// The image's address: neper_start's own less its offset in the image. It stays in
// [sp, #40] and comes off every address looked up.
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
