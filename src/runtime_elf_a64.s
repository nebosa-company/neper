.text

// The aarch64 Linux runtime: raw system calls, no libc (D2123). One file, embedded whole
// into `runtime_elf_a64.e` by scripts/embed-elf-runtime.ps1 -Arch a64.
//
// Order matters as on x64 (D150): the linker appends this runtime as a prefix, cut after
// the last function the program reaches, so a function may call only what precedes it.
// The entry stub comes first and is always kept. A call between functions goes to a local
// label: a branch to a global symbol would be a relocation the embedding does not apply.
//
// Every function takes Neper's convention on this target, which is AAPCS64: arguments in
// x0-x7, an aggregate by its address, an aggregate result through the address in x0, and
// a pair of results in x0 and x1. System call numbers are aarch64's.

// The entry: the root arena mapped (its size the literal the linker patches), the
// arguments copied into it as a table of slices, `main(&arena, &args)` called, and the
// program ended with exit_group -- status 1 when main returned an error, 111 when the
// arena could not be had. x29 is zero in main's caller: the end of the frame chain.
.global neper_start
neper_start:
    mov x19, sp
    ldr x20, .Lstart_arena
    mov x0, #0
    mov x1, x20
    mov x2, #3
    mov x3, #0x4022
    mov x4, #-1
    mov x5, #0
    mov x8, #222
    svc #0
    tbnz x0, #63, .Lstart_fail
    mov x21, x0
    ldr x22, [x19]
    lsl x23, x22, #4
    cmp x23, x20
    b.hi .Lstart_fail
    mov x24, #0
.Lstart_argument:
    cmp x24, x22
    b.hs .Lstart_main
    add x9, x19, x24, lsl #3
    ldr x9, [x9, #8]
    mov x10, #0
.Lstart_length:
    ldrb w11, [x9, x10]
    cbz w11, .Lstart_counted
    add x10, x10, #1
    b .Lstart_length
.Lstart_counted:
    adds x12, x23, x10
    b.cs .Lstart_fail
    cmp x12, x20
    b.hi .Lstart_fail
    add x13, x21, x23
    add x14, x21, x24, lsl #4
    stp x13, x10, [x14]
    mov x15, #0
.Lstart_copy:
    cmp x15, x10
    b.hs .Lstart_copied
    ldrb w11, [x9, x15]
    strb w11, [x13, x15]
    add x15, x15, #1
    b .Lstart_copy
.Lstart_copied:
    mov x23, x12
    add x24, x24, #1
    b .Lstart_argument
.Lstart_main:
    sub sp, sp, #48
    stp x21, x20, [sp]
    str x23, [sp, #16]
    stp x21, x22, [sp, #24]
    mov x0, sp
    add x1, sp, #24
    mov x29, #0
    mov x30, #0
.global neper_start_main
neper_start_main:
    bl .
    cmp w0, #0
    cset x0, ne
    mov x8, #94
    svc #0
.Lstart_fail:
    mov x0, #111
    mov x8, #94
    svc #0
    brk #0
.global neper_start_arena
neper_start_arena:
.Lstart_arena:
    .quad 0x40000000

// errno in w0 to the `e.os` error code in w0, the generic code for anything unlisted:
// the table's pairs, ended by errno 0 with the generic code.
np_error:
    adr x10, .Lerror_table
.Lerror_scan:
    ldp w11, w12, [x10], #8
    cbz w11, .Lerror_found
    cmp w11, w0
    b.ne .Lerror_scan
.Lerror_found:
    mov w0, w12
    ret
.Lerror_table:
    .word 2, 0x7683e2cd
    .word 20, 0x7683e2cd
    .word 13, 0xb0cb971d
    .word 1, 0xb0cb971d
    .word 17, 0x197f5566
    .word 4, 0xb66d7668
    .word 12, 0x6979aadc
    .word 110, 0x52812f09
    .word 11, 0xa18174bc
    .word 38, 0x2f8bb651
    .word 95, 0x2f8bb651
    .word 0, 0x6f777ebf

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

// exit_group, not exit: section 8's exit ends the program (D246).
.global neper_os_exit
neper_os_exit:
    mov x8, #94
    svc #0
    brk #0

// os.write(file: *File, bytes: *[]const u8) -> (usize, err).
.global neper_os_write
neper_os_write:
    ldr x2, [x1, #8]
    ldr x1, [x1]
    ldr x0, [x0]
    mov x8, #64
    svc #0
    tbnz x0, #63, .Los_write_fail
    mov x1, #0
    ret
.Los_write_fail:
    stp x29, x30, [sp, #-16]!
    neg w0, w0
    bl np_error
    ldp x29, x30, [sp], #16
    mov w1, w0
    mov x0, #0
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

// os.sha256_blocks (D332): how many 64-byte blocks were compressed in hardware -- none
// yet on this target, and the caller keeps its own rounds.
// ponytail: no SHA2 extension path; ARMv8.2 has SHA256H/SHA256SU0, add when a build is hashed here.
.global neper_os_sha256_blocks
neper_os_sha256_blocks:
    mov x0, #0
    ret

// os.crc32c_bytes(crc: []usize, bytes: []const u8) -> usize (D332): the bytes folded into
// the CRC-32C in `crc`'s first slot with CRC32CX and CRC32CB, mandatory since ARMv8.1;
// every byte is folded.
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

// A failed check (spec section 11): the site's path, `:line:column`, the message with the
// two operands wherever it holds a byte below 2 -- 0 unsigned, 1 signed -- a newline, the
// symbolised backtrace from the table at x5, all to stderr, and exit 134. A stub enters
// with x0 = the path's record and x4 = the message's (a 16-bit length and the bytes,
// D922), x1 = line << 16 | column, x2 and x3 = the operands, and x30 = the site. Nothing
// returns, so the callee-saved registers are not kept.

// x1 and x2 bytes to stderr.
np_trap_text:
    mov x0, #2
    mov x8, #64
    svc #0
    ret

// The byte in w0 to stderr, through [sp].
np_trap_char:
    strb w0, [sp]
    mov x1, sp
    mov x2, #1
    b np_trap_text

// x0 in decimal to stderr.
np_trap_number:
    sub sp, sp, #32
    add x9, sp, #32
    mov x10, #10
.Ltrap_number_digit:
    udiv x11, x0, x10
    msub x12, x11, x10, x0
    add w12, w12, #48
    strb w12, [x9, #-1]!
    mov x0, x11
    cbnz x0, .Ltrap_number_digit
    mov x1, x9
    add x2, sp, #32
    sub x2, x2, x9
    mov x0, #2
    mov x8, #64
    svc #0
    add sp, sp, #32
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
    bl np_trap_text
    mov w0, #58
    bl np_trap_char
    lsr x0, x26, #16
    bl np_trap_number
    mov w0, #58
    bl np_trap_char
    and x0, x26, #0xffff
    bl np_trap_number
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
    bl np_trap_text
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
    bl np_trap_char
    mov x0, x28
.Ltrap_unsigned:
    bl np_trap_number
    b .Ltrap_segment
.Ltrap_end:
    mov w0, #10
    bl np_trap_char
// The backtrace: every frame keeps its x29/x30 record, so from the trapping function's
// frame and the site the walk is [x29 + 8] and [x29], each address looked up one byte
// back -- at its call -- in the `.nepersym` table (D1586) by a binary search over its
// entries, sorted by start, until none holds it, which is the runtime's own entry, or
// thirty-two frames have been printed.
    mov x27, #32
    sub x26, x24, #1
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
    bl np_trap_text
    ldr w9, [x22, #16]
    add x1, x23, x9
    ldr w2, [x1]
    add x1, x1, #4
    bl np_trap_text
// The line program: a row count, then per row a ULEB128 offset delta, a ULEB128 of the
// zigzag line delta times two plus a file-change bit, and then the new file. x24 and x11
// are the row's offset and line, x19 its file; [sp + 16] and [sp + 32] keep the last row
// at or below the call, [sp + 24] whether there is one.
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
    bl np_trap_char
    mov w0, #40
    bl np_trap_char
    ldr x9, [sp, #16]
    add x1, x23, x9
    ldr w2, [x1]
    add x1, x1, #4
    bl np_trap_text
    mov w0, #58
    bl np_trap_char
    ldr x0, [sp, #32]
    bl np_trap_number
    mov w0, #41
    bl np_trap_char
.Ltrap_line_done:
    mov w0, #10
    bl np_trap_char
    cbz x25, .Ltrap_exit
    ldr x26, [x25, #8]
    sub x26, x26, #1
    ldr x25, [x25]
    b .Ltrap_frame
.Ltrap_exit:
    mov x0, #134
    mov x8, #94
    svc #0
    brk #0
.Ltrap_at:
    .ascii "  at "
    .p2align 2

// os.read(file: *File, bytes: *[]u8) -> (usize, err).
.global neper_os_read
neper_os_read:
    ldr x2, [x1, #8]
    ldr x1, [x1]
    ldr x0, [x0]
    mov x8, #63
    svc #0
    tbnz x0, #63, .Los_read_fail
    mov x1, #0
    ret
.Los_read_fail:
    stp x29, x30, [sp, #-16]!
    neg w0, w0
    bl np_error
    ldp x29, x30, [sp], #16
    mov w1, w0
    mov x0, #0
    ret

// os.close(file: *File) -> err.
.global neper_os_close
neper_os_close:
    ldr x0, [x0]
    mov x8, #57
    svc #0
    tbnz x0, #63, .Los_close_fail
    mov x0, #0
    ret
.Los_close_fail:
    stp x29, x30, [sp, #-16]!
    neg w0, w0
    bl np_error
    ldp x29, x30, [sp], #16
    ret

// os.open: the result {File, err} at x0, the arena at x1 (the path's terminated copy is
// taken from it and given back), the path's slice at x2, the OpenFlags at x3 -- read,
// write, create, truncate, append, one byte each.
.global neper_os_open
neper_os_open:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0
    mov x20, x1
    mov x21, x3
    str xzr, [x19]
    str wzr, [x19, #8]
    ldr x22, [x20, #16]
    ldr x9, [x2, #8]
    ldr x10, [x2]
    adds x1, x9, #1
    b.cs .Los_open_oom
    stp x9, x10, [sp, #-16]!
    mov x0, x20
    mov x2, #1
    bl np_alloc
    ldp x9, x10, [sp], #16
    cbz x0, .Los_open_oom
    mov x11, x0
.Los_open_copy:
    cbz x9, .Los_open_copied
    ldrb w12, [x10], #1
    strb w12, [x11], #1
    sub x9, x9, #1
    b .Los_open_copy
.Los_open_copied:
    strb wzr, [x11]
    mov x1, x0
    mov w2, #0
    ldrb w9, [x21]
    ldrb w10, [x21, #1]
    cbz w9, .Los_open_write_only
    cbz w10, .Los_open_flags
    mov w2, #2
    b .Los_open_flags
.Los_open_write_only:
    cbz w10, .Los_open_flags
    mov w2, #1
.Los_open_flags:
    ldrb w9, [x21, #2]
    cbz w9, .Los_open_truncate
    orr w2, w2, #0x40
.Los_open_truncate:
    ldrb w9, [x21, #3]
    cbz w9, .Los_open_append
    orr w2, w2, #0x200
.Los_open_append:
    ldrb w9, [x21, #4]
    cbz w9, .Los_open_call
    orr w2, w2, #0x400
.Los_open_call:
    orr w2, w2, #0x80000
    mov x0, #-100
    mov x3, #0x1b6
    mov x8, #56
    svc #0
    str x22, [x20, #16]
    tbnz x0, #63, .Los_open_errno
    str x0, [x19]
    b .Los_open_done
.Los_open_errno:
    neg w0, w0
    bl np_error
    str w0, [x19, #8]
    b .Los_open_done
.Los_open_oom:
    str x22, [x20, #16]
    movz w9, #0xaadc
    movk w9, #0x6979, lsl #16
    str w9, [x19, #8]
.Los_open_done:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

// os.args: the result ([]str, err) at x0, the arena at x1. The arguments are the kernel's
// own copy, /proc/self/cmdline -- each followed by a NUL -- read into the arena with a
// table of (pointer, length) views into it (D1607). The file is read twice, once to
// measure it, since a /proc file reports no size; the measuring buffer is given back.
.global neper_os_args
neper_os_args:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    str x25, [sp, #64]
    mov x19, x0
    mov x20, x1
    stp xzr, xzr, [x19]
    str wzr, [x19, #16]
    ldr x25, [x20, #16]
    mov x0, #-100
    adr x1, .Largs_path
    mov x2, #0x80000
    mov x3, #0
    mov x8, #56
    svc #0
    tbnz x0, #63, .Largs_errno
    mov x24, x0
    mov x0, x20
    mov x1, #4096
    mov x2, #1
    bl np_alloc
    cbz x0, .Largs_oom_open
    mov x21, x0
    mov x22, #0
.Largs_measure:
    mov x0, x24
    mov x1, x21
    mov x2, #4096
    mov x8, #63
    svc #0
    tbnz x0, #63, .Largs_errno_open
    cbz x0, .Largs_measured
    add x22, x22, x0
    b .Largs_measure
.Largs_measured:
    str x25, [x20, #16]
    mov x0, x24
    mov x1, #0
    mov x2, #0
    mov x8, #62
    svc #0
    tbnz x0, #63, .Largs_errno_open
    mov x0, x20
    mov x1, x22
    mov x2, #1
    bl np_alloc
    cbz x0, .Largs_oom_open
    mov x21, x0
    mov x23, #0
.Largs_fill:
    cmp x23, x22
    b.hs .Largs_filled
    mov x0, x24
    add x1, x21, x23
    sub x2, x22, x23
    mov x8, #63
    svc #0
    tbnz x0, #63, .Largs_errno_open
    cbz x0, .Largs_filled
    add x23, x23, x0
    b .Largs_fill
.Largs_filled:
    mov x22, x23
    mov x0, x24
    mov x8, #57
    svc #0
    mov x9, #0
    mov x23, #0
.Largs_count:
    cmp x9, x22
    b.hs .Largs_counted
    ldrb w10, [x21, x9]
    cbnz w10, .Largs_count_next
    add x23, x23, #1
.Largs_count_next:
    add x9, x9, #1
    b .Largs_count
.Largs_counted:
    cbz x23, .Largs_done
    mov x0, x20
    lsl x1, x23, #4
    mov x2, #8
    bl np_alloc
    cbz x0, .Largs_oom
    stp x0, x23, [x19]
    mov x10, x21
    mov x9, #0
.Largs_split:
    cmp x9, x22
    b.hs .Largs_done
    ldrb w11, [x21, x9]
    cbnz w11, .Largs_split_next
    add x12, x21, x9
    sub x12, x12, x10
    stp x10, x12, [x0], #16
    add x10, x21, x9
    add x10, x10, #1
.Largs_split_next:
    add x9, x9, #1
    b .Largs_split
.Largs_errno_open:
    mov x23, x0
    mov x0, x24
    mov x8, #57
    svc #0
    mov x0, x23
.Largs_errno:
    neg w0, w0
    bl np_error
    str x25, [x20, #16]
    stp xzr, xzr, [x19]
    str w0, [x19, #16]
    b .Largs_done
.Largs_oom_open:
    mov x0, x24
    mov x8, #57
    svc #0
.Largs_oom:
    str x25, [x20, #16]
    stp xzr, xzr, [x19]
    movz w9, #0xaadc
    movk w9, #0x6979, lsl #16
    str w9, [x19, #16]
.Largs_done:
    ldr x25, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #80
    ret
.Largs_path:
    .asciz "/proc/self/cmdline"
    .p2align 2

// os.reserve(size) -> (usize, err): address space and no memory, PROT_NONE.
.global neper_os_reserve
neper_os_reserve:
    mov x1, x0
    mov x0, #0
    mov x2, #0
    mov x3, #0x4022
    mov x4, #-1
    mov x5, #0
    mov x8, #222
    svc #0
    tbnz x0, #63, .Lreserve_failed
    mov x1, #0
    ret
.Lreserve_failed:
    mov x0, #0
    movz w1, #0x7ebf
    movk w1, #0x6f77, lsl #16
    ret

// os.commit(address, size) -> err: the reserved pages made readable and writable.
.global neper_os_commit
neper_os_commit:
    mov x2, #3
    mov x8, #226
    svc #0
    tbnz x0, #63, .Lcommit_failed
    mov x0, #0
    ret
.Lcommit_failed:
    movz w0, #0x7ebf
    movk w0, #0x6f77, lsl #16
    ret

// os.syscall(number, a0..a5) -> isize, the raw system call -- and the reason the library
// needs no per-architecture source (D2123): `e.os` names its calls by their x86-64 numbers,
// flags and structures, and this translates them. Most is a table of numbers. openat and
// openat2 move the O_DIRECTORY, O_NOFOLLOW, O_DIRECT and O_LARGEFILE bits to where this
// architecture keeps them; newfstatat gives back x86-64's `struct stat`; epoll's events are
// packed on x86-64 and padded here; rt_sigaction's restorer is this runtime's; fork is
// clone(SIGCHLD), dup2 is dup3, poll is ppoll and epoll_wait is epoll_pwait. An unlisted
// number answers -ENOSYS. The result is the
// kernel's own: a negative errno on failure.
.global neper_os_syscall
neper_os_syscall:
    stp x29, x30, [sp, #-160]!
    mov x29, sp
    mov x9, x0
    mov x0, x1
    mov x1, x2
    mov x2, x3
    mov x3, x4
    mov x4, x5
    mov x5, x6
    cmp x9, #257
    b.eq .Lsys_openat
    cmp x9, #437
    b.eq .Lsys_openat2
    cmp x9, #262
    b.eq .Lsys_stat
    cmp x9, #57
    b.eq .Lsys_fork
    cmp x9, #33
    b.eq .Lsys_dup2
    cmp x9, #7
    b.eq .Lsys_poll
    cmp x9, #232
    b.eq .Lsys_epoll_wait
    cmp x9, #233
    b.eq .Lsys_epoll_ctl
    cmp x9, #13
    b.eq .Lsys_sigaction
    cmp x9, #157
    b.eq .Lsys_prctl
    adr x10, .Lsys_table
.Lsys_scan:
    ldp w11, w12, [x10], #8
    cmn w11, #1
    b.eq .Lsys_unknown
    cmp w11, w9
    b.ne .Lsys_scan
    mov x8, x12
.Lsys_call:
    svc #0
.Lsys_return:
    mov sp, x29
    ldp x29, x30, [sp], #160
    ret
.Lsys_unknown:
    mov x0, #-38
    b .Lsys_return
.Lsys_openat:
    mov w9, w2
    bl .Lsys_open_bits
    mov w2, w9
    mov x8, #56
    b .Lsys_call
.Lsys_openat2:
    ldp x10, x11, [x2]
    ldr x12, [x2, #16]
    mov w9, w10
    bl .Lsys_open_bits
    mov w10, w9
    stp x10, x11, [x29, #16]
    str x12, [x29, #32]
    add x2, x29, #16
    mov x8, #437
    b .Lsys_call
.Lsys_stat:
    mov x10, x2
    mov x8, #79
    svc #0
    tbnz x0, #63, .Lsys_return
    ldp w11, w12, [x10, #16]
    ldp w13, w14, [x10, #24]
    ldr x15, [x10, #32]
    ldrsw x9, [x10, #56]
    str x12, [x10, #16]
    stp w11, w13, [x10, #24]
    stp w14, wzr, [x10, #32]
    str x15, [x10, #40]
    str x9, [x10, #56]
    b .Lsys_return
.Lsys_fork:
    mov x0, #17
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov x8, #220
    b .Lsys_call
.Lsys_dup2:
    cmp x0, x1
    b.ne .Lsys_dup3
    mov x0, x1
    b .Lsys_return
.Lsys_dup3:
    mov x2, #0
    mov x8, #24
    b .Lsys_call
.Lsys_poll:
    sxtw x2, w2
    tbnz x2, #63, .Lsys_poll_forever
    mov x10, #1000
    udiv x11, x2, x10
    msub x12, x11, x10, x2
    movz x13, #0x4240
    movk x13, #0xf, lsl #16
    mul x12, x12, x13
    stp x11, x12, [x29, #16]
    add x2, x29, #16
    b .Lsys_ppoll
.Lsys_poll_forever:
    mov x2, #0
.Lsys_ppoll:
    mov x3, #0
    mov x4, #8
    mov x8, #73
    b .Lsys_call
.Lsys_epoll_wait:
    mov x10, x1
    cmp x2, #8
    b.ls .Lsys_epoll_wait_room
    mov x2, #8
.Lsys_epoll_wait_room:
    add x1, x29, #16
    mov x4, #0
    mov x5, #8
    mov x8, #22
    svc #0
    cmp x0, #0
    b.le .Lsys_return
    mov x11, #0
    add x12, x29, #16
.Lsys_epoll_pack:
    ldr w13, [x12], #8
    ldr x14, [x12], #8
    str w13, [x10], #4
    str x14, [x10], #8
    add x11, x11, #1
    cmp x11, x0
    b.lo .Lsys_epoll_pack
    b .Lsys_return
.Lsys_epoll_ctl:
    cbz x3, .Lsys_epoll_ctl_call
    ldr w10, [x3]
    ldr x11, [x3, #4]
    str w10, [x29, #16]
    str x11, [x29, #24]
    add x3, x29, #16
.Lsys_epoll_ctl_call:
    mov x8, #21
    b .Lsys_call
// rt_sigaction: the kernel's struct is the same on both, but a restorer `e.os` supplies is
// x86-64 code -- `mov rax, 15; syscall` written into a buffer -- so the copy handed on names
// this runtime's own rt_sigreturn instead.
.Lsys_sigaction:
    cbz x1, .Lsys_sigaction_call
    ldp x10, x11, [x1]
    ldp x12, x13, [x1, #16]
    tbz x11, #26, .Lsys_sigaction_copy
    adr x12, .Lsys_sigreturn
.Lsys_sigaction_copy:
    stp x10, x11, [x29, #16]
    stp x12, x13, [x29, #32]
    add x1, x29, #16
.Lsys_sigaction_call:
    mov x8, #134
    b .Lsys_call
// What a handler returns to: the signal frame is at sp, exactly as the kernel left it.
.Lsys_sigreturn:
    mov x8, #139
    svc #0
// prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program): `e.os` builds its classic BPF filter
// for x86-64 -- the audit architecture it accepts and the call numbers it compares -- so a
// copy on the stack hands the kernel the same filter for this architecture: every JEQ after
// a load of `arch` (offset 4) that names AUDIT_ARCH_X86_64 names AUDIT_ARCH_AARCH64, and
// every JEQ after a load of `nr` (offset 0) compares this architecture's number for the
// call. Any other prctl passes as it is.
.Lsys_prctl:
    mov x8, #167
    cmp x0, #22
    b.ne .Lsys_call
    cmp x1, #2
    b.ne .Lsys_call
    cbz x2, .Lsys_call
    ldrh w10, [x2]
    ldr x11, [x2, #8]
    lsl x12, x10, #3
    add x12, x12, #31
    and x12, x12, #-16
    sub sp, sp, x12
    mov x13, sp
    strh w10, [x13]
    add x14, x13, #16
    str x14, [x13, #8]
    mov x15, #-1
.Lsys_bpf_copy:
    cbz x10, .Lsys_bpf_done
    ldr x16, [x11], #8
    and w17, w16, #0xffff
    lsr x9, x16, #32
    cmp w17, #0x20
    b.ne .Lsys_bpf_jump
    mov x15, x9
    b .Lsys_bpf_store
.Lsys_bpf_jump:
    cmp w17, #0x15
    b.ne .Lsys_bpf_store
    cmp x15, #4
    b.ne .Lsys_bpf_number
    movz w17, #0x003e
    movk w17, #0xc000, lsl #16
    cmp w9, w17
    b.ne .Lsys_bpf_store
    movz w9, #0x00b7
    movk w9, #0xc000, lsl #16
    b .Lsys_bpf_value
.Lsys_bpf_number:
    cbnz x15, .Lsys_bpf_store
    bl .Lsys_number_of
.Lsys_bpf_value:
    and x16, x16, #0xffffffff
    orr x16, x16, x9, lsl #32
.Lsys_bpf_store:
    str x16, [x14], #8
    sub x10, x10, #1
    b .Lsys_bpf_copy
.Lsys_bpf_done:
    mov x2, x13
    mov x8, #167
    b .Lsys_call
// w9: an x86-64 call number into this architecture's, or 0xffffffff for one it has no call
// for; x6, x7 and x17 are used.
.Lsys_number_of:
    adr x17, .Lsys_extra
.Lsys_number_extra:
    ldp w6, w7, [x17], #8
    cmn w6, #1
    b.eq .Lsys_number_table
    cmp w6, w9
    b.ne .Lsys_number_extra
    mov w9, w7
    ret
.Lsys_number_table:
    adr x17, .Lsys_table
.Lsys_number_scan:
    ldp w6, w7, [x17], #8
    cmn w6, #1
    b.eq .Lsys_number_none
    cmp w6, w9
    b.ne .Lsys_number_scan
    mov w9, w7
    ret
.Lsys_number_none:
    mov w9, #-1
    ret
// The calls the translation reshapes, by what each becomes, for a filter to name.
.Lsys_extra:
    .word 7, 73
    .word 13, 134
    .word 33, 24
    .word 56, 220
    .word 57, 220
    .word 58, 220
    .word 157, 167
    .word 232, 22
    .word 233, 21
    .word 257, 56
    .word 262, 79
    .word 322, 281
    .word 435, 435
    .word 437, 437
    .word 0xffffffff, 0
// w9: x86-64's open flags into this architecture's.
.Lsys_open_bits:
    and w10, w9, #0xfffc3fff
    tbz w9, #16, .Lsys_open_nofollow
    orr w10, w10, #0x4000
.Lsys_open_nofollow:
    tbz w9, #17, .Lsys_open_direct
    orr w10, w10, #0x8000
.Lsys_open_direct:
    tbz w9, #14, .Lsys_open_large
    orr w10, w10, #0x10000
.Lsys_open_large:
    tbz w9, #15, .Lsys_open_done
    orr w10, w10, #0x20000
.Lsys_open_done:
    mov w9, w10
    ret
.Lsys_table:
    .word 0, 63
    .word 1, 64
    .word 3, 57
    .word 8, 62
    .word 9, 222
    .word 10, 226
    .word 11, 215
    .word 26, 227
    .word 32, 23
    .word 35, 101
    .word 39, 172
    .word 40, 71
    .word 41, 198
    .word 42, 203
    .word 44, 206
    .word 45, 207
    .word 48, 210
    .word 49, 200
    .word 50, 201
    .word 51, 204
    .word 54, 208
    .word 59, 221
    .word 61, 260
    .word 62, 129
    .word 72, 25
    .word 73, 32
    .word 74, 82
    .word 79, 17
    .word 80, 49
    .word 98, 165
    .word 102, 174
    .word 104, 176
    .word 107, 175
    .word 108, 177
    .word 109, 154
    .word 110, 173
    .word 157, 167
    .word 186, 178
    .word 202, 98
    .word 217, 61
    .word 228, 113
    .word 231, 94
    .word 254, 27
    .word 258, 34
    .word 263, 35
    .word 264, 38
    .word 265, 37
    .word 266, 36
    .word 267, 78
    .word 268, 53
    .word 280, 88
    .word 288, 242
    .word 290, 19
    .word 291, 20
    .word 293, 59
    .word 294, 26
    .word 316, 276
    .word 318, 278
    .word 0xffffffff, 0

// os.clock(kind) -> (u64, err): nanoseconds of the wall or monotonic clock.
.global neper_os_clock
neper_os_clock:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    cmp w0, #1
    b.hi .Lclock_unsupported
    add x1, sp, #16
    mov x8, #113
    svc #0
    tbnz x0, #63, .Lclock_failed
    ldp x0, x2, [sp, #16]
    movz x3, #0xca00
    movk x3, #0x3b9a, lsl #16
    madd x0, x0, x3, x2
    mov x1, #0
    ldp x29, x30, [sp], #32
    ret
.Lclock_unsupported:
    mov x0, #0
    movz w1, #0xb651
    movk w1, #0x2f8b, lsl #16
    ldp x29, x30, [sp], #32
    ret
.Lclock_failed:
    mov x0, #0
    movz w1, #0x7ebf
    movk w1, #0x6f77, lsl #16
    ldp x29, x30, [sp], #32
    ret

// os.seek(file: *File, offset, whence) -> (usize, err).
.global neper_os_seek
neper_os_seek:
    cmp w2, #2
    b.hi .Lseek_failed
    ldr x0, [x0]
    mov x8, #62
    svc #0
    tbnz x0, #63, .Lseek_failed
    mov x1, #0
    ret
.Lseek_failed:
    mov x0, #0
    movz w1, #0x7ebf
    movk w1, #0x6f77, lsl #16
    ret

// os.readdir: the result ([]DirEntry, err) at x0, the arena at x1, the path's slice at
// x2. Every entry but `.` and `..`, its name copied into the arena and its kind from
// d_type; the entry table doubles as it fills. A DirEntry is {name: str, kind: u8}, 24
// bytes.
.global neper_os_readdir
neper_os_readdir:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    str x27, [sp, #80]
    sub sp, sp, #4096
    mov x19, x0
    mov x20, x1
    ldr x21, [x20, #16]
    stp xzr, xzr, [x19]
    str wzr, [x19, #16]
    ldr x9, [x2, #8]
    ldr x10, [x2]
    adds x1, x9, #1
    b.cs .Lreaddir_oom
    stp x9, x10, [sp, #-16]!
    mov x0, x20
    mov x2, #1
    bl np_alloc
    ldp x9, x10, [sp], #16
    cbz x0, .Lreaddir_oom
    mov x11, x0
.Lreaddir_path:
    cbz x9, .Lreaddir_pathed
    ldrb w12, [x10], #1
    strb w12, [x11], #1
    sub x9, x9, #1
    b .Lreaddir_path
.Lreaddir_pathed:
    strb wzr, [x11]
    mov x1, x0
    mov x0, #-100
    mov x2, #0x4000
    orr x2, x2, #0x80000
    mov x3, #0
    mov x8, #56
    svc #0
    str x21, [x20, #16]
    tbnz x0, #63, .Lreaddir_errno
    mov x22, x0
    mov x0, x20
    mov x1, #384
    mov x2, #8
    bl np_alloc
    cbz x0, .Lreaddir_oom_open
    mov x23, x0
    mov x24, #0
    mov x25, #16
.Lreaddir_read:
    mov x0, x22
    mov x1, sp
    mov x2, #4096
    mov x8, #61
    svc #0
    tbnz x0, #63, .Lreaddir_errno_open
    cbz x0, .Lreaddir_end
    mov x26, x0
    mov x27, #0
.Lreaddir_entry:
    cmp x27, x26
    b.hs .Lreaddir_read
    add x10, sp, x27
    ldrh w11, [x10, #16]
    add x12, x10, #19
    ldrb w13, [x12]
    cmp w13, #46
    b.ne .Lreaddir_named
    ldrb w13, [x12, #1]
    cbz w13, .Lreaddir_skip
    cmp w13, #46
    b.ne .Lreaddir_named
    ldrb w13, [x12, #2]
    cbz w13, .Lreaddir_skip
.Lreaddir_named:
    mov x13, #0
.Lreaddir_length:
    ldrb w14, [x12, x13]
    cbz w14, .Lreaddir_measured
    add x13, x13, #1
    b .Lreaddir_length
.Lreaddir_measured:
    cmp x24, x25
    b.ne .Lreaddir_room
    stp x11, x13, [sp, #-16]!
    lsl x25, x25, #1
    mov x0, x20
    mov x9, #24
    mul x1, x25, x9
    mov x2, #8
    bl np_alloc
    ldp x11, x13, [sp], #16
    cbz x0, .Lreaddir_oom_open
    mov x9, #24
    mul x9, x24, x9
    mov x10, x23
    mov x14, x0
.Lreaddir_grow:
    cbz x9, .Lreaddir_grown
    ldrb w15, [x10], #1
    strb w15, [x14], #1
    sub x9, x9, #1
    b .Lreaddir_grow
.Lreaddir_grown:
    mov x23, x0
.Lreaddir_room:
    stp x11, x13, [sp, #-16]!
    mov x0, x20
    mov x1, x13
    mov x2, #1
    bl np_alloc
    ldp x11, x13, [sp], #16
    cbz x0, .Lreaddir_oom_open
    add x10, sp, x27
    add x12, x10, #19
    mov x9, #0
.Lreaddir_name:
    cmp x9, x13
    b.hs .Lreaddir_copied
    ldrb w14, [x12, x9]
    strb w14, [x0, x9]
    add x9, x9, #1
    b .Lreaddir_name
.Lreaddir_copied:
    mov x9, #24
    madd x14, x24, x9, x23
    stp x0, x13, [x14]
    ldrb w15, [x10, #18]
    mov w9, #3
    cmp w15, #8
    b.ne .Lreaddir_not_file
    mov w9, #0
    b .Lreaddir_kind
.Lreaddir_not_file:
    cmp w15, #4
    b.ne .Lreaddir_not_dir
    mov w9, #1
    b .Lreaddir_kind
.Lreaddir_not_dir:
    cmp w15, #10
    b.ne .Lreaddir_kind
    mov w9, #2
.Lreaddir_kind:
    strb w9, [x14, #16]
    add x24, x24, #1
.Lreaddir_skip:
    add x27, x27, x11
    b .Lreaddir_entry
.Lreaddir_end:
    mov x0, x22
    mov x8, #57
    svc #0
    stp x23, x24, [x19]
    b .Lreaddir_done
.Lreaddir_errno:
    neg w0, w0
    bl np_error
    str w0, [x19, #16]
    b .Lreaddir_done
.Lreaddir_errno_open:
    neg w0, w0
    bl np_error
    str w0, [x19, #16]
    mov x0, x22
    mov x8, #57
    svc #0
    str x21, [x20, #16]
    b .Lreaddir_done
.Lreaddir_oom_open:
    mov x0, x22
    mov x8, #57
    svc #0
.Lreaddir_oom:
    str x21, [x20, #16]
    movz w9, #0xaadc
    movk w9, #0x6979, lsl #16
    str w9, [x19, #16]
.Lreaddir_done:
    add sp, sp, #4096
    ldr x27, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

// Spec section 9 rule 4: the supplied `hash` is xxHash64 with seed 0 over a value's
// canonical little-endian bytes; this agrees bit for bit with algo.hash.xxhash64, with
// the x86-64 runtime and with bootstrap/runtime.c. x0 = the bytes, x1 = their length.
.global neper_hash_bytes
neper_hash_bytes:
    ldr x11, .Lhash_p1
    ldr x12, .Lhash_p2
    ldr x13, .Lhash_p3
    ldr x14, .Lhash_p4
    ldr x15, .Lhash_p5
    mov x9, x0
    mov x10, x1
    mov x3, #0
    cmp x10, #32
    b.lo .Lhash_small
    add x5, x11, x12
    mov x6, x12
    mov x7, #0
    neg x8, x11
    sub x2, x10, #32
.Lhash_block:
    ldr x4, [x9, x3]
    mul x4, x4, x12
    add x5, x5, x4
    ror x5, x5, #33
    mul x5, x5, x11
    add x3, x3, #8
    ldr x4, [x9, x3]
    mul x4, x4, x12
    add x6, x6, x4
    ror x6, x6, #33
    mul x6, x6, x11
    add x3, x3, #8
    ldr x4, [x9, x3]
    mul x4, x4, x12
    add x7, x7, x4
    ror x7, x7, #33
    mul x7, x7, x11
    add x3, x3, #8
    ldr x4, [x9, x3]
    mul x4, x4, x12
    add x8, x8, x4
    ror x8, x8, #33
    mul x8, x8, x11
    add x3, x3, #8
    cmp x3, x2
    b.ls .Lhash_block
    ror x16, x5, #63
    ror x4, x6, #57
    add x16, x16, x4
    ror x4, x7, #52
    add x16, x16, x4
    ror x4, x8, #46
    add x16, x16, x4
    mul x4, x5, x12
    ror x4, x4, #33
    mul x4, x4, x11
    eor x16, x16, x4
    madd x16, x16, x11, x14
    mul x4, x6, x12
    ror x4, x4, #33
    mul x4, x4, x11
    eor x16, x16, x4
    madd x16, x16, x11, x14
    mul x4, x7, x12
    ror x4, x4, #33
    mul x4, x4, x11
    eor x16, x16, x4
    madd x16, x16, x11, x14
    mul x4, x8, x12
    ror x4, x4, #33
    mul x4, x4, x11
    eor x16, x16, x4
    madd x16, x16, x11, x14
    b .Lhash_sized
.Lhash_small:
    mov x16, x15
.Lhash_sized:
    add x16, x16, x10
.Lhash_tail8:
    add x4, x3, #8
    cmp x4, x10
    b.hi .Lhash_tail4
    ldr x4, [x9, x3]
    mul x4, x4, x12
    ror x4, x4, #33
    mul x4, x4, x11
    eor x16, x16, x4
    ror x16, x16, #37
    madd x16, x16, x11, x14
    add x3, x3, #8
    b .Lhash_tail8
.Lhash_tail4:
    add x4, x3, #4
    cmp x4, x10
    b.hi .Lhash_tail1
    ldr w4, [x9, x3]
    mul x4, x4, x11
    eor x16, x16, x4
    ror x16, x16, #41
    madd x16, x16, x12, x13
    add x3, x3, #4
.Lhash_tail1:
    cmp x3, x10
    b.hs .Lhash_final
    ldrb w4, [x9, x3]
    mul x4, x4, x15
    eor x16, x16, x4
    ror x16, x16, #53
    mul x16, x16, x11
    add x3, x3, #1
    b .Lhash_tail1
.Lhash_final:
    eor x16, x16, x16, lsr #33
    mul x16, x16, x12
    eor x16, x16, x16, lsr #29
    mul x16, x16, x13
    eor x0, x16, x16, lsr #32
    ret
    .p2align 3
.Lhash_p1:
    .quad 11400714785074694791
.Lhash_p2:
    .quad 14029467366897019727
.Lhash_p3:
    .quad 1609587929392839161
.Lhash_p4:
    .quad 9650029242287828579
.Lhash_p5:
    .quad 2870177450012600261

// Section 8's blocking primitives, futex(2) directly: FUTEX_WAIT_PRIVATE (128) and
// FUTEX_WAKE_PRIVATE (129). wait_u32(p, expected, timeout_ns) -> err: a wake, a value
// that already differs (EAGAIN) and a signal (EINTR) are all `ok` -- the fence promises
// spurious wakes -- and a negative timeout waits for ever.
.global neper_os_wait_u32
neper_os_wait_u32:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    mov x3, #0
    tbnz x2, #63, .Lwait_go
    movz x10, #0xca00
    movk x10, #0x3b9a, lsl #16
    udiv x11, x2, x10
    msub x12, x11, x10, x2
    stp x11, x12, [sp, #16]
    add x3, sp, #16
.Lwait_go:
    mov w2, w1
    mov x1, #128
    mov x4, #0
    mov x5, #0
    mov x8, #98
    svc #0
    tbz x0, #63, .Lwait_ok
    cmn x0, #11
    b.eq .Lwait_ok
    cmn x0, #4
    b.eq .Lwait_ok
    cmn x0, #110
    b.eq .Lwait_timeout
    movz w0, #0x7ebf
    movk w0, #0x6f77, lsl #16
    ldp x29, x30, [sp], #32
    ret
.Lwait_ok:
    mov x0, #0
    ldp x29, x30, [sp], #32
    ret
.Lwait_timeout:
    movz w0, #0x2f09
    movk w0, #0x5281, lsl #16
    ldp x29, x30, [sp], #32
    ret

.global neper_os_wake_one_u32
neper_os_wake_one_u32:
    mov x1, #129
    mov x2, #1
    mov x3, #0
    mov x4, #0
    mov x5, #0
    mov x8, #98
    svc #0
    ret

.global neper_os_wake_all_u32
neper_os_wake_all_u32:
    mov x1, #129
    mov x2, #0x7fffffff
    mov x3, #0
    mov x4, #0
    mov x5, #0
    mov x8, #98
    svc #0
    ret

// os.thread_create: the result {Thread, err} at x0, the entry at x1, its context at x2,
// the stack size at x3. A thread is clone(2) over a mapping this makes: the join word at
// +0, the mapping's size at +8, the child's stack growing down from the top, where the
// child finds its entry and context. CLONE_VM|FS|FILES|SIGHAND|THREAD|SYSVSEM|
// PARENT_SETTID|CHILD_CLEARTID with the join word for both tids: PARENT_SETTID sets it
// before either runs, and the kernel clears it and wakes it when the thread ends.
// aarch64's clone takes (flags, stack, parent_tid, tls, child_tid).
.global neper_os_thread_create
neper_os_thread_create:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
    mov x9, #65536
    cmp x22, x9
    b.hs .Lthread_size_ok
    mov x22, x9
.Lthread_size_ok:
    mov x0, #0
    mov x1, x22
    mov x2, #3
    mov x3, #0x22
    mov x4, #-1
    mov x5, #0
    mov x8, #222
    svc #0
    tbnz x0, #63, .Lthread_create_failed
    mov x9, x0
    str x22, [x9, #8]
    add x10, x9, x22
    and x10, x10, #-16
    sub x10, x10, #16
    stp x20, x21, [x10]
    movz x0, #0x0f00
    movk x0, #0x35, lsl #16
    mov x1, x10
    mov x2, x9
    mov x3, #0
    mov x4, x9
    mov x8, #220
    svc #0
    tbnz x0, #63, .Lthread_create_unmap
    cbz x0, .Lthread_child
    str x9, [x19]
    str wzr, [x19, #8]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret
.Lthread_child:
    ldp x9, x0, [sp]
    mov x29, #0
    mov x30, #0
    blr x9
    mov x0, #0
    mov x8, #93
    svc #0
.Lthread_create_unmap:
    mov x0, x9
    mov x1, x22
    mov x8, #215
    svc #0
.Lthread_create_failed:
    str xzr, [x19]
    movz w9, #0x7ebf
    movk w9, #0x6f77, lsl #16
    str w9, [x19, #8]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

// os.thread_join(thread: *Thread) -> err: FUTEX_WAIT on the tid the kernel clears, then
// the mapping given back.
.global neper_os_thread_join
neper_os_thread_join:
    ldr x9, [x0]
    cbz x9, .Lthread_join_failed
    ldr x10, [x9, #8]
.Lthread_join_wait:
    ldar w2, [x9]
    cbz w2, .Lthread_join_done
    mov x0, x9
    mov x1, #0
    mov x3, #0
    mov x8, #98
    svc #0
    b .Lthread_join_wait
.Lthread_join_done:
    mov x0, x9
    mov x1, x10
    mov x8, #215
    svc #0
    mov x0, #0
    ret
.Lthread_join_failed:
    movz w0, #0x7ebf
    movk w0, #0x6f77, lsl #16
    ret

// Nothing waits for a detached thread, so its stack is left alone.
.global neper_os_thread_detach
neper_os_thread_detach:
    mov x0, #0
    ret

// os.spawn: the result {Proc, err} at x0, the arena at x1, the argument slices at x2, the
// Stdio at x3 (stdin, stdout, stderr). The arguments are copied terminated into the arena,
// a child forked with clone(SIGCHLD), its descriptors set with dup3 and the program run with
// execve; a child whose exec fails ends with 127.
.global neper_os_spawn
neper_os_spawn:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    mov x19, x0
    mov x20, x1
    ldp x21, x22, [x2]
    mov x23, x3
    str xzr, [x19]
    str wzr, [x19, #8]
    cbz x22, .Lspawn_not_found
    ldr x24, [x20, #16]
    add x1, x22, #1
    lsl x1, x1, #3
    mov x0, x20
    mov x2, #8
    bl np_alloc
    cbz x0, .Lspawn_oom
    mov x25, x0
    mov x26, #0
.Lspawn_copy_argument:
    cmp x26, x22
    b.hs .Lspawn_copied
    add x9, x21, x26, lsl #4
    ldr x1, [x9, #8]
    add x1, x1, #1
    mov x0, x20
    mov x2, #1
    bl np_alloc
    cbz x0, .Lspawn_oom
    add x9, x21, x26, lsl #4
    ldp x10, x11, [x9]
    mov x12, x0
.Lspawn_copy_byte:
    cbz x11, .Lspawn_copy_done
    ldrb w13, [x10], #1
    strb w13, [x12], #1
    sub x11, x11, #1
    b .Lspawn_copy_byte
.Lspawn_copy_done:
    strb wzr, [x12]
    str x0, [x25, x26, lsl #3]
    add x26, x26, #1
    b .Lspawn_copy_argument
.Lspawn_copied:
    str xzr, [x25, x22, lsl #3]
    mov x0, #17
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov x8, #220
    svc #0
    tbnz x0, #63, .Lspawn_failed
    cbz x0, .Lspawn_child
    str x24, [x20, #16]
    str x0, [x19]
    b .Lspawn_done
.Lspawn_child:
    ldr x0, [x23]
    cbz x0, .Lspawn_stdout
    mov x1, #0
    mov x2, #0
    mov x8, #24
    svc #0
.Lspawn_stdout:
    ldr x0, [x23, #8]
    cmp x0, #1
    b.eq .Lspawn_stderr
    mov x1, #1
    mov x2, #0
    mov x8, #24
    svc #0
.Lspawn_stderr:
    ldr x0, [x23, #16]
    cmp x0, #2
    b.eq .Lspawn_exec
    mov x1, #2
    mov x2, #0
    mov x8, #24
    svc #0
.Lspawn_exec:
    ldr x0, [x25]
    mov x1, x25
    mov x2, #0
    mov x8, #221
    svc #0
    mov x0, #127
    mov x8, #93
    svc #0
.Lspawn_failed:
    str x24, [x20, #16]
    movz w9, #0x7ebf
    movk w9, #0x6f77, lsl #16
    str w9, [x19, #8]
    b .Lspawn_done
.Lspawn_not_found:
    movz w9, #0xe2cd
    movk w9, #0x7683, lsl #16
    str w9, [x19, #8]
    b .Lspawn_done
.Lspawn_oom:
    str x24, [x20, #16]
    movz w9, #0xaadc
    movk w9, #0x6979, lsl #16
    str w9, [x19, #8]
.Lspawn_done:
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #80
    ret

// os.wait(proc: *Proc) -> (i32, err): the exit status, or 128 plus the signal that ended it.
.global neper_os_wait
neper_os_wait:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    ldr x0, [x0]
    add x1, sp, #16
    mov x2, #0
    mov x3, #0
    mov x8, #260
    svc #0
    tbnz x0, #63, .Lwait_failed
    ldr w0, [sp, #16]
    ands w9, w0, #0x7f
    b.ne .Lwait_signal
    ubfx w0, w0, #8, #8
    mov x1, #0
    ldp x29, x30, [sp], #32
    ret
.Lwait_signal:
    add w0, w9, #128
    mov x1, #0
    ldp x29, x30, [sp], #32
    ret
.Lwait_failed:
    mov x0, #-1
    movz w1, #0x7ebf
    movk w1, #0x6f77, lsl #16
    ldp x29, x30, [sp], #32
    ret
