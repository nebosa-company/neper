.text

// A BSD system call: the number in x16, trapped with svc #0x80. The kernel answers an error with
// the carry flag set and the positive errno in x0; the callers below test the sign as on Linux,
// so the error is negated here.
.macro sys number
    mov x16, #\number
    svc #0x80
    b.cc 1f
    neg x0, x0
1:
.endm

// The aarch64 macOS runtime: raw BSD system calls, no libSystem. One file, embedded whole
// into `runtime_macos_a64.e` by scripts/embed-elf-runtime.ps1 -Arch macos.
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
    // dyld calls LC_MAIN's entry as main(argc, argv): x19 is made to stand where the
    // kernel's initial stack would have put the count, the vector 8 bytes after it.
    mov x22, x0
    sub x19, x1, #8
    ldr x20, .Lstart_arena
    mov x0, #0
    mov x1, x20
    mov x2, #3
    mov x3, #0x1002
    mov x4, #-1
    mov x5, #0
    sys 197
    tbnz x0, #63, .Lstart_fail
    mov x21, x0
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
    sys 1
.Lstart_fail:
    mov x0, #111
    sys 1
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
    .word 60, 0x52812f09
    .word 35, 0xa18174bc
    .word 78, 0x2f8bb651
    .word 45, 0x2f8bb651
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
    sys 1
    brk #0

// os.write(file: *File, bytes: *[]const u8) -> (usize, err).
.global neper_os_write
neper_os_write:
    ldr x2, [x1, #8]
    ldr x1, [x1]
    ldr x0, [x0]
    sys 4
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
    sys 4
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
    sys 4
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
    sys 1
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
    sys 3
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
    sys 6
    tbnz x0, #63, .Los_close_fail
    mov x0, #0
    ret
.Los_close_fail:
    stp x29, x30, [sp, #-16]!
    neg w0, w0
    bl np_error
    ldp x29, x30, [sp], #16
    ret

