.intel_syntax noprefix
.text

# The x86-64 macOS runtime: raw BSD system calls (class 2, number 0x2000000 + n), no
# libSystem. One file, embedded whole into `runtime_macos_x64.e` by
# scripts/embed-elf-runtime.ps1 -Arch macosx64. The functions from `np_error` on are
# runtime_elf_x64.s with the Linux call numbers replaced.
#
# Order matters as in the Linux runtime: the linker appends this as a prefix, cut after the
# last function the program reaches, so a function may call only what precedes it. The
# entry comes first and is always kept.

# A BSD system call: the number in eax. The kernel answers an error with the carry flag set
# and the positive errno in rax; the callers test the sign as on Linux, so it is negated.
.macro darwin_syscall
    syscall
    jnc 1f
    neg rax
1:
.endm

# The entry, called by dyld as main(argc, argv): the root arena mapped (its size the literal
# the linker patches), the arguments copied into it as a table of slices, `main(&arena,
# &args)` called, and the program ended with exit -- status 1 when main returned an error,
# 111 when the arena could not be had.
.global neper_start
neper_start:
    # The environment pointer (rdx) is kept beside the argument table for `os.env_block`.
    lea rax, [rip+.Lstart_args]
    add rax, QWORD PTR [rip+.Lstart_args]
    mov QWORD PTR [rax+16], rdx
    mov r12, rdi
    mov r13, rsi
    mov r14, QWORD PTR [rip+.Lstart_arena]
    xor edi, edi
    mov rsi, r14
    mov edx, 3
    mov r10d, 0x1002
    mov r8, -1
    xor r9d, r9d
    mov eax, 0x20000c5
    darwin_syscall
    test rax, rax
    js .Lstart_fail
    mov r15, rax
    mov rbx, r12
    shl rbx, 4
    cmp rbx, r14
    ja .Lstart_fail
    xor ebp, ebp
.Lstart_argument:
    cmp rbp, r12
    jae .Lstart_main
    mov r8, QWORD PTR [r13+rbp*8]
    xor ecx, ecx
.Lstart_length:
    cmp BYTE PTR [r8+rcx], 0
    je .Lstart_counted
    inc rcx
    jmp .Lstart_length
.Lstart_counted:
    mov rax, rbx
    add rax, rcx
    jc .Lstart_fail
    cmp rax, r14
    ja .Lstart_fail
    lea r9, [r15+rbx]
    mov rdx, rbp
    shl rdx, 4
    mov QWORD PTR [r15+rdx], r9
    mov QWORD PTR [r15+rdx+8], rcx
    mov rsi, r8
    mov rdi, r9
    rep movsb
    mov rbx, rax
    inc rbp
    jmp .Lstart_argument
.Lstart_main:
    # The table is kept in the slot at the start of __DATA for `os.args`; the literal beside
    # the arena's holds its distance from itself, patched by the linker.
    lea rax, [rip+.Lstart_args]
    add rax, QWORD PTR [rip+.Lstart_args]
    mov QWORD PTR [rax], r15
    mov QWORD PTR [rax+8], r12
    sub rsp, 56
    mov QWORD PTR [rsp], r15
    mov QWORD PTR [rsp+8], r14
    mov QWORD PTR [rsp+16], rbx
    mov QWORD PTR [rsp+24], r15
    mov QWORD PTR [rsp+32], r12
    mov rdi, rsp
    lea rsi, [rsp+24]
    xor ebp, ebp
.global neper_start_main
neper_start_main:
    call .
    test eax, eax
    setne dil
    movzx edi, dil
    mov eax, 0x2000001
    syscall
.Lstart_fail:
    mov edi, 111
    mov eax, 0x2000001
    syscall
    ud2
.global neper_start_args
neper_start_args:
.Lstart_args:
    .quad 0
.global neper_start_arena
neper_start_arena:
.Lstart_arena:
    .quad 0x40000000


# errno to the `e.os` error code: rax gets the code for the errno in edi, with the
# generic code for anything unlisted.

np_error:
    mov eax,0x6f777ebf
    cmp edi,0x2
    je .Lerror_1
    cmp edi,0x14
    je .Lerror_1
    cmp edi,0xd
    je .Lerror_2
    cmp edi,0x1
    je .Lerror_2
    cmp edi,0x11
    je .Lerror_3
    cmp edi,0x4
    je .Lerror_4
    cmp edi,0xc
    je .Lerror_5
    cmp edi,0x6e
    je .Lerror_6
    cmp edi,0xb
    je .Lerror_7
    cmp edi,0x26
    je .Lerror_8
    cmp edi,0x5f
    je .Lerror_8
    ret
.Lerror_1:
    mov eax,0x7683e2cd
    ret
.Lerror_2:
    mov eax,0xb0cb971d
    ret
.Lerror_3:
    mov eax,0x197f5566
    ret
.Lerror_4:
    mov eax,0xb66d7668
    ret
.Lerror_5:
    mov eax,0x6979aadc
    ret
.Lerror_6:
    mov eax,0x52812f09
    ret
.Lerror_7:
    mov eax,0xa18174bc
    ret
.Lerror_8:
    mov eax,0x2f8bb651
    ret

np_alloc:
    test rdi,rdi
    je .Lalloc_1
    test rdx,rdx
    je .Lalloc_1
    lea rcx,[rdx-0x1]
    test rdx,rcx
    jne .Lalloc_1
    mov rax,QWORD PTR [rdi+0x10]
    mov r8,rax
    add r8,rcx
    jb .Lalloc_1
    neg rdx
    and r8,rdx
    mov r9,QWORD PTR [rdi+0x8]
    cmp r8,r9
    ja .Lalloc_1
    sub r9,r8
    cmp rsi,r9
    ja .Lalloc_1
    lea rcx,[r8+rsi*1]
    mov QWORD PTR [rdi+0x10],rcx
    mov rax,QWORD PTR [rdi]
    test rax,rax
    je .Lalloc_1
    add rax,r8
    ret
.Lalloc_1:
    xor eax,eax
    ret

.global neper_mem_alloc
neper_mem_alloc:
np_mem_alloc:
    push r12
    push r13
    push r14
    mov r12,rdi
    mov r13,rsi
    mov r14,rdx
    mov QWORD PTR [r12],0x0
    mov QWORD PTR [r12+0x8],0x0
    mov DWORD PTR [r12+0x10],0x0
    mov rax,r14
    mul rcx
    test rdx,rdx
    jne .Lmem_alloc_1
    mov rsi,rax
    mov rdi,r13
    mov rdx,r8
    call np_alloc
    test rax,rax
    je .Lmem_alloc_1
    mov QWORD PTR [r12],rax
    mov QWORD PTR [r12+0x8],r14
    jmp .Lmem_alloc_2
.Lmem_alloc_1:
    mov DWORD PTR [r12+0x10],0x8f63623a
.Lmem_alloc_2:
    pop r14
    pop r13
    pop r12
    ret

# Section 11's debug fill (D217): the allocation, then every byte of it 0xCD, so a
# read before a write is recognisable. A debug build calls this; release the one above.
.global neper_mem_alloc_fill
neper_mem_alloc_fill:
    push rbx
    push r12
    sub rsp,8
    mov rbx,rdi
    mov rax,rdx
    imul rax,rcx
# A local name: a call to the global would be a relocation the embedding does not apply.
    mov r12,rax
    call np_mem_alloc
    cmp DWORD PTR [rbx+0x10],0x0
    jne .Lalloc_fill_done
    mov rdi,QWORD PTR [rbx]
    mov rcx,r12
    mov al,0xCD
    rep stosb
.Lalloc_fill_done:
    add rsp,8
    pop r12
    pop rbx
    ret

.global neper_mem_mark
neper_mem_mark:
    mov rax,QWORD PTR [rdi+0x10]
    ret

.global neper_mem_reset
neper_mem_reset:
    mov QWORD PTR [rdi+0x10],rsi
    ret

# The other debug fill (D217): what the reset gives back is 0xDD before the offset
# moves, so a slice that outlived its reset reads as such.
.global neper_mem_reset_fill
neper_mem_reset_fill:
    mov rdx,QWORD PTR [rdi+0x10]
    cmp rsi,rdx
    jae .Lreset_fill_store
    mov r8,rdi
    mov rdi,QWORD PTR [r8]
    add rdi,rsi
    mov rcx,rdx
    sub rcx,rsi
    mov al,0xDD
    rep stosb
    mov rdi,r8
.Lreset_fill_store:
    mov QWORD PTR [rdi+0x10],rsi
    ret

.global neper_mem_stats
neper_mem_stats:
    mov rax,QWORD PTR [rsi+0x10]
    mov QWORD PTR [rdi],rax
    mov rax,QWORD PTR [rsi+0x8]
    mov QWORD PTR [rdi+0x8],rax
    ret

.global neper_os_stdout
neper_os_stdout:
    mov QWORD PTR [rdi],0x1
    ret

.global neper_os_stderr
neper_os_stderr:
    mov QWORD PTR [rdi],0x2
    ret

.global neper_os_exit
neper_os_exit:
    // `exit_group`, not `exit`: section 8's exit ends the program, and syscall 60 would
    // end only the calling thread -- so a thread that exits while another runs left the
    // process alive (D246). A thread that merely finishes still leaves by syscall 60, in
    // the trampoline below. Windows already had this: `ExitProcess` takes the process.
    mov eax,0x2000001
    darwin_syscall
    ud2

.global neper_os_write
neper_os_write:
    push rbx
    mov rdx,QWORD PTR [rsi+0x8]
    mov rsi,QWORD PTR [rsi]
    mov rdi,QWORD PTR [rdi]
    mov eax,0x2000004
    darwin_syscall
    test rax,rax
    js .Los_write_1
    xor edx,edx
    pop rbx
    ret
.Los_write_1:
    neg eax
    mov edi,eax
    call np_error
    mov edx,eax
    xor eax,eax
    pop rbx
    ret

# os.copy_bytes(dst: []u8, src: []const u8) (D329): the shorter length's worth of
# bytes, forwards. rdi = &dst, rsi = &src.
.global neper_os_copy_bytes
neper_os_copy_bytes:
    mov rcx,QWORD PTR [rdi+0x8]
    mov rdx,QWORD PTR [rsi+0x8]
    cmp rdx,rcx
    cmovb rcx,rdx
    mov rdi,QWORD PTR [rdi]
    mov rsi,QWORD PTR [rsi]
    rep movsb
    ret

# os.sha256_blocks(state: []usize, bytes: []const u8) -> usize (D332): the whole
# 64-byte blocks of `bytes` compressed into the eight 32-bit words `state` holds one
# per slot, with the SHA extensions; how many blocks were done, none when the CPU has
# no SHA extensions and the caller keeps its own rounds. rdi = &state, rsi = &bytes.
.global neper_os_sha256_blocks
neper_os_sha256_blocks:
    push rbx
    sub rsp, 40
    mov r10, rdi
    mov r11, rsi
    mov eax, 7
    xor ecx, ecx
    cpuid
    xor eax, eax
    bt ebx, 29
    jnc .Lsha_done
    mov r8, qword ptr [r11+8]
    shr r8, 6
    mov rax, r8
    test r8, r8
    jz .Lsha_done
    mov rcx, qword ptr [r10]
    mov edx, dword ptr [rcx+0]
    mov dword ptr [rsp+0], edx
    mov edx, dword ptr [rcx+8]
    mov dword ptr [rsp+4], edx
    mov edx, dword ptr [rcx+16]
    mov dword ptr [rsp+8], edx
    mov edx, dword ptr [rcx+24]
    mov dword ptr [rsp+12], edx
    mov edx, dword ptr [rcx+32]
    mov dword ptr [rsp+16], edx
    mov edx, dword ptr [rcx+40]
    mov dword ptr [rsp+20], edx
    mov edx, dword ptr [rcx+48]
    mov dword ptr [rsp+24], edx
    mov edx, dword ptr [rcx+56]
    mov dword ptr [rsp+28], edx
    movdqu xmm1, xmmword ptr [rsp]
    movdqu xmm2, xmmword ptr [rsp+16]
    pshufd xmm1, xmm1, 0xB1
    pshufd xmm2, xmm2, 0x1B
    movdqa xmm7, xmm1
    palignr xmm1, xmm2, 8
    pblendw xmm2, xmm7, 0xF0
    lea r9, [rip + .Lsha_k]
    movdqu xmm8, xmmword ptr [rip + .Lsha_flip]
    mov rdx, qword ptr [r11]
.Lsha_loop:
    movdqa xmm9, xmm1
    movdqa xmm10, xmm2
    movdqu xmm0, xmmword ptr [rdx+0]
    pshufb xmm0, xmm8
    movdqa xmm3, xmm0
    movdqu xmm7, xmmword ptr [r9+0]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    movdqu xmm0, xmmword ptr [rdx+16]
    pshufb xmm0, xmm8
    movdqa xmm4, xmm0
    movdqu xmm7, xmmword ptr [r9+16]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm3, xmm4
    movdqu xmm0, xmmword ptr [rdx+32]
    pshufb xmm0, xmm8
    movdqa xmm5, xmm0
    movdqu xmm7, xmmword ptr [r9+32]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm4, xmm5
    movdqu xmm0, xmmword ptr [rdx+48]
    pshufb xmm0, xmm8
    movdqa xmm6, xmm0
    movdqu xmm7, xmmword ptr [r9+48]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm6
    palignr xmm7, xmm5, 4
    paddd xmm3, xmm7
    sha256msg2 xmm3, xmm6
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm5, xmm6
    movdqa xmm0, xmm3
    movdqu xmm7, xmmword ptr [r9+64]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm3
    palignr xmm7, xmm6, 4
    paddd xmm4, xmm7
    sha256msg2 xmm4, xmm3
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm6, xmm3
    movdqa xmm0, xmm4
    movdqu xmm7, xmmword ptr [r9+80]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm4
    palignr xmm7, xmm3, 4
    paddd xmm5, xmm7
    sha256msg2 xmm5, xmm4
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm3, xmm4
    movdqa xmm0, xmm5
    movdqu xmm7, xmmword ptr [r9+96]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm5
    palignr xmm7, xmm4, 4
    paddd xmm6, xmm7
    sha256msg2 xmm6, xmm5
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm4, xmm5
    movdqa xmm0, xmm6
    movdqu xmm7, xmmword ptr [r9+112]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm6
    palignr xmm7, xmm5, 4
    paddd xmm3, xmm7
    sha256msg2 xmm3, xmm6
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm5, xmm6
    movdqa xmm0, xmm3
    movdqu xmm7, xmmword ptr [r9+128]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm3
    palignr xmm7, xmm6, 4
    paddd xmm4, xmm7
    sha256msg2 xmm4, xmm3
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm6, xmm3
    movdqa xmm0, xmm4
    movdqu xmm7, xmmword ptr [r9+144]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm4
    palignr xmm7, xmm3, 4
    paddd xmm5, xmm7
    sha256msg2 xmm5, xmm4
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm3, xmm4
    movdqa xmm0, xmm5
    movdqu xmm7, xmmword ptr [r9+160]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm5
    palignr xmm7, xmm4, 4
    paddd xmm6, xmm7
    sha256msg2 xmm6, xmm5
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm4, xmm5
    movdqa xmm0, xmm6
    movdqu xmm7, xmmword ptr [r9+176]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm6
    palignr xmm7, xmm5, 4
    paddd xmm3, xmm7
    sha256msg2 xmm3, xmm6
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm5, xmm6
    movdqa xmm0, xmm3
    movdqu xmm7, xmmword ptr [r9+192]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm3
    palignr xmm7, xmm6, 4
    paddd xmm4, xmm7
    sha256msg2 xmm4, xmm3
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    sha256msg1 xmm6, xmm3
    movdqa xmm0, xmm4
    movdqu xmm7, xmmword ptr [r9+208]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm4
    palignr xmm7, xmm3, 4
    paddd xmm5, xmm7
    sha256msg2 xmm5, xmm4
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    movdqa xmm0, xmm5
    movdqu xmm7, xmmword ptr [r9+224]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    movdqa xmm7, xmm5
    palignr xmm7, xmm4, 4
    paddd xmm6, xmm7
    sha256msg2 xmm6, xmm5
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    movdqa xmm0, xmm6
    movdqu xmm7, xmmword ptr [r9+240]
    paddd xmm0, xmm7
    sha256rnds2 xmm2, xmm1
    pshufd xmm0, xmm0, 0x0E
    sha256rnds2 xmm1, xmm2
    paddd xmm1, xmm9
    paddd xmm2, xmm10
    add rdx, 64
    dec r8
    jnz .Lsha_loop
    pshufd xmm1, xmm1, 0x1B
    pshufd xmm2, xmm2, 0xB1
    movdqa xmm7, xmm1
    pblendw xmm1, xmm2, 0xF0
    palignr xmm2, xmm7, 8
    movdqu xmmword ptr [rsp], xmm1
    movdqu xmmword ptr [rsp+16], xmm2
    mov edx, dword ptr [rsp+0]
    mov qword ptr [rcx+0], rdx
    mov edx, dword ptr [rsp+4]
    mov qword ptr [rcx+8], rdx
    mov edx, dword ptr [rsp+8]
    mov qword ptr [rcx+16], rdx
    mov edx, dword ptr [rsp+12]
    mov qword ptr [rcx+24], rdx
    mov edx, dword ptr [rsp+16]
    mov qword ptr [rcx+32], rdx
    mov edx, dword ptr [rsp+20]
    mov qword ptr [rcx+40], rdx
    mov edx, dword ptr [rsp+24]
    mov qword ptr [rcx+48], rdx
    mov edx, dword ptr [rsp+28]
    mov qword ptr [rcx+56], rdx
.Lsha_done:
    add rsp, 40
    pop rbx
    ret
.Lsha_flip: .byte 3, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12
.Lsha_k:
    .long 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    .long 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    .long 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    .long 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    .long 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    .long 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    .long 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    .long 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2

# os.crc32c_bytes(crc: []usize, bytes: []const u8) -> usize (D332): the bytes folded
# into the CRC-32C in `crc`'s first slot with the CRC32 instruction, eight at a time;
# how many bytes were folded, none when the CPU has no SSE4.2 and the caller keeps its
# own tables. rdi = &crc, rsi = &bytes.
.global neper_os_crc32c_bytes
neper_os_crc32c_bytes:
    push rbx
    mov r10, rdi
    mov r11, rsi
    mov eax, 1
    cpuid
    xor eax, eax
    bt ecx, 20
    jnc .Lcrc_done
    mov r8, qword ptr [r11+8]
    mov rax, r8
    mov rdx, qword ptr [r11]
    mov rcx, qword ptr [r10]
    mov r9d, dword ptr [rcx]
    mov r10, r8
    shr r10, 3
    jz .Lcrc_tail
.Lcrc_words:
    crc32 r9, qword ptr [rdx]
    add rdx, 8
    dec r10
    jnz .Lcrc_words
.Lcrc_tail:
    and r8, 7
    jz .Lcrc_store
.Lcrc_bytes:
    crc32 r9d, byte ptr [rdx]
    inc rdx
    dec r8
    jnz .Lcrc_bytes
.Lcrc_store:
    mov qword ptr [rcx], r9
.Lcrc_done:
    pop rbx
    ret

# A failed check (spec section 11): the site's path, `:line:column`, then the message
# with the two operands wherever it holds a byte below 2 -- 0 prints the operand
# unsigned, 1 signed -- then a newline, then the symbolised backtrace from the table
# r10 points at, all to stderr, and exit 134. The generated code calls its function's
# stub, which jumps here, with rdi = the path's record and rax = the message's -- each
# a 16-bit length and the bytes (D922) -- rsi = line << 16 | column, and rdx and rcx =
# the operands; nothing returns, so the stack is simply realigned and the callee-saved
# registers are not kept.
# rax in decimal to stderr; a subroutine of neper_trap alone.
np_trap_number:
    sub rsp,32
    lea r9,[rsp+32]
    mov ecx,10
.Lnp_number_digit:
    xor edx,edx
    div rcx
    add dl,48
    dec r9
    mov BYTE PTR [r9],dl
    test rax,rax
    jnz .Lnp_number_digit
    mov rsi,r9
    lea rdx,[rsp+32]
    sub rdx,r9
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
    add rsp,32
    ret

# A ULEB128 at rbp into rax, rbp past it; rcx and rdx are used. A subroutine of
# neper_trap alone (D1586).
np_trap_uleb:
    xor eax,eax
    xor ecx,ecx
.Lnp_uleb_byte:
    movzx edx,BYTE PTR [rbp]
    inc rbp
    test dl,dl
    js .Lnp_uleb_more
    shl rdx,cl
    or rax,rdx
    ret
.Lnp_uleb_more:
    and edx,127
    shl rdx,cl
    or rax,rdx
    add ecx,7
    jmp .Lnp_uleb_byte

.global neper_trap
neper_trap:
    mov r11,QWORD PTR [rsp]
    and rsp,-16
    sub rsp,64
    mov QWORD PTR [rsp+32],rbp
    mov QWORD PTR [rsp+40],r10
    mov QWORD PTR [rsp+48],r11
    mov QWORD PTR [rsp+56],rsi
    mov rbx,rdi
    mov r13,rax
    mov r12,rdx
    mov r14,rcx
    xor r15d,r15d
    movzx edx,WORD PTR [rbx]
    lea rsi,[rbx+2]
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
    mov BYTE PTR [rsp],58
    mov rsi,rsp
    mov edx,1
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
    mov rax,QWORD PTR [rsp+56]
    shr rax,16
    call np_trap_number
    mov BYTE PTR [rsp],58
    mov rsi,rsp
    mov edx,1
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
    movzx eax,WORD PTR [rsp+56]
    call np_trap_number
    movzx eax,WORD PTR [r13]
    lea rbx,[r13+2]
    lea r13,[rbx+rax]
.Ltrap_segment:
    mov rsi,rbx
.Ltrap_scan:
    cmp rbx,r13
    jae .Ltrap_scanned
    cmp BYTE PTR [rbx],2
    jb .Ltrap_scanned
    inc rbx
    jmp .Ltrap_scan
.Ltrap_scanned:
    mov rdx,rbx
    sub rdx,rsi
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
    cmp rbx,r13
    jae .Ltrap_end
    movzx ebp,BYTE PTR [rbx]
    inc rbx
    mov rax,r12
    test r15d,r15d
    jz .Ltrap_digits
    mov rax,r14
.Ltrap_digits:
    inc r15d
    test ebp,ebp
    jz .Ltrap_unsigned
    test rax,rax
    jns .Ltrap_unsigned
    neg rax
    mov rbp,rax
    mov BYTE PTR [rsp],45
    mov rsi,rsp
    mov edx,1
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
    mov rax,rbp
.Ltrap_unsigned:
    lea r9,[rsp+24]
    mov ecx,10
.Ltrap_digit:
    xor edx,edx
    div rcx
    add dl,48
    dec r9
    mov BYTE PTR [r9],dl
    test rax,rax
    jnz .Ltrap_digit
    mov rsi,r9
    lea rdx,[rsp+24]
    sub rdx,r9
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
    jmp .Ltrap_segment
.Ltrap_end:
    mov BYTE PTR [rsp],10
    mov rsi,rsp
    mov edx,1
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
# The backtrace: every frame is rbp-chained, so from the trapping function's frame and
# the return address into it the walk is [rbp+8] and [rbp], each address looked up in
# the `.nepersym` table r10 points at (D1586) -- a binary search over its entries, which
# are sorted by start, for the one whose [start, end) holds it -- until none does,
# which is the runtime's own entry, or thirty-two frames have been printed.
# Each return address is looked up one byte back, at its call: a trap that ends a
# function returns to the function's end, which no range holds (D212).
    mov r14d,32
    mov r12,QWORD PTR [rsp+48]
    dec r12
    mov r13,QWORD PTR [rsp+32]
.Ltrap_frame:
    test r14d,r14d
    jz .Ltrap_exit
    dec r14d
    mov rbx,QWORD PTR [rsp+40]
    # The table's entries are relative to the table (the image slides), so the address looked
    # up is too.
    sub r12,rbx
    xor r8d,r8d
    mov r9d,DWORD PTR [rbx+8]
.Ltrap_search:
    cmp r8,r9
    jae .Ltrap_exit
    lea rax,[r8+r9]
    shr rax,1
    mov r10,rax
    shl r10,5
    lea r10,[rbx+r10+12]
    cmp r12,QWORD PTR [r10]
    jb .Ltrap_lower
    cmp r12,QWORD PTR [r10+8]
    jae .Ltrap_upper
    jmp .Ltrap_found
.Ltrap_lower:
    mov r9,rax
    jmp .Ltrap_search
.Ltrap_upper:
    lea r8,[rax+1]
    jmp .Ltrap_search
.Ltrap_found:
# The call's offset within the function, for its line program: the last row at or
# below it is the frame's line. The entry is kept at [rsp+8].
    mov r15,r12
    sub r15,QWORD PTR [r10]
    mov QWORD PTR [rsp+8],r10
    mov BYTE PTR [rsp],32
    mov BYTE PTR [rsp+1],32
    mov BYTE PTR [rsp+2],97
    mov BYTE PTR [rsp+3],116
    mov BYTE PTR [rsp+4],32
    mov rsi,rsp
    mov edx,5
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
# The name: a string index, the string a 32-bit length and its bytes.
    mov r10,QWORD PTR [rsp+8]
    mov esi,DWORD PTR [r10+16]
    add rsi,rbx
    mov edx,DWORD PTR [rsi]
    add rsi,4
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
# The line program: a row count, then per row a ULEB128 offset delta, a ULEB128 of the
# zigzag line delta times two plus a file-change bit, and then the new file. rbp walks
# it, r10 and r11 are the row's offset and line, rsi its file; [rsp+16] and [rsp+56]
# keep the last row at or below the call, [rsp+24] whether there is one.
    mov r10,QWORD PTR [rsp+8]
    mov esi,DWORD PTR [r10+20]
    mov ebp,DWORD PTR [r10+24]
    add rbp,rbx
    mov r8d,DWORD PTR [rbp]
    add rbp,4
    xor r10d,r10d
    xor r11d,r11d
    mov QWORD PTR [rsp+24],0
.Ltrap_row:
    test r8d,r8d
    jz .Ltrap_rows_done
    dec r8d
    call np_trap_uleb
    add r10,rax
    call np_trap_uleb
    mov r9,rax
    shr rax,1
    mov rcx,rax
    shr rcx,1
    and eax,1
    neg rax
    xor rax,rcx
    add r11,rax
    test r9d,1
    jz .Ltrap_row_file
    call np_trap_uleb
    mov rsi,rax
.Ltrap_row_file:
    cmp r10,r15
    ja .Ltrap_rows_done
    mov QWORD PTR [rsp+16],rsi
    mov QWORD PTR [rsp+56],r11
    mov QWORD PTR [rsp+24],1
    jmp .Ltrap_row
.Ltrap_rows_done:
    cmp QWORD PTR [rsp+24],0
    je .Ltrap_line_done
    mov BYTE PTR [rsp],32
    mov BYTE PTR [rsp+1],40
    mov rsi,rsp
    mov edx,2
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
    mov rsi,QWORD PTR [rsp+16]
    add rsi,rbx
    mov edx,DWORD PTR [rsi]
    add rsi,4
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
    mov BYTE PTR [rsp],58
    mov rsi,rsp
    mov edx,1
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
    mov rax,QWORD PTR [rsp+56]
    push r9
    push r9
    call np_trap_number
    pop r9
    pop r9
    mov BYTE PTR [rsp],41
    mov rsi,rsp
    mov edx,1
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
.Ltrap_line_done:
    mov BYTE PTR [rsp],10
    mov rsi,rsp
    mov edx,1
    mov edi,2
    mov eax,0x2000004
    darwin_syscall
    test r13,r13
    jz .Ltrap_exit
    mov r12,QWORD PTR [r13+8]
    dec r12
    mov r13,QWORD PTR [r13]
    jmp .Ltrap_frame
.Ltrap_exit:
    mov edi,134
    mov eax,0x2000001
    darwin_syscall
    ud2

.global neper_os_read
neper_os_read:
    push rbx
    mov rdx,QWORD PTR [rsi+0x8]
    mov rsi,QWORD PTR [rsi]
    mov rdi,QWORD PTR [rdi]
    mov eax,0x2000003
    darwin_syscall
    test rax,rax
    js .Los_read_1
    xor edx,edx
    pop rbx
    ret
.Los_read_1:
    neg eax
    mov edi,eax
    call np_error
    mov edx,eax
    xor eax,eax
    pop rbx
    ret

.global neper_os_close
neper_os_close:
    push rbx
    mov rdi,QWORD PTR [rdi]
    mov eax,0x2000006
    darwin_syscall
    test rax,rax
    js .Los_close_1
    xor eax,eax
    pop rbx
    ret
.Los_close_1:
    neg eax
    mov edi,eax
    call np_error
    pop rbx
    ret

.global neper_os_open
neper_os_open:
    push r12
    push r13
    push r14
    push r15
    sub rsp,0x8
    mov r12,rdi
    mov r13,rsi
    mov r14,rdx
    mov r15,rcx
    mov QWORD PTR [r12],0x0
    mov DWORD PTR [r12+0x8],0x0
    mov rax,QWORD PTR [r13+0x10]
    mov QWORD PTR [rsp],rax
    mov rsi,QWORD PTR [r14+0x8]
    inc rsi
    je .Los_open_7
    mov rdi,r13
    mov edx,0x1
    call np_alloc
    test rax,rax
    je .Los_open_7
    mov r8,rax
    mov rcx,QWORD PTR [r14+0x8]
    mov rsi,QWORD PTR [r14]
    mov rdi,r8
    rep movs BYTE PTR es:[rdi],BYTE PTR ds:[rsi]
    mov BYTE PTR [rdi],0x0
    xor edx,edx
    mov al,BYTE PTR [r15]
    test al,al
    je .Los_open_1
    mov al,BYTE PTR [r15+0x1]
    test al,al
    je .Los_open_1
    mov edx,0x2
    jmp .Los_open_2
.Los_open_1:
    mov al,BYTE PTR [r15+0x1]
    test al,al
    je .Los_open_2
    mov edx,0x1
.Los_open_2:
    cmp BYTE PTR [r15+0x2],0x0
    je .Los_open_3
    or edx,0x200
.Los_open_3:
    cmp BYTE PTR [r15+0x3],0x0
    je .Los_open_4
    or edx,0x400
.Los_open_4:
    cmp BYTE PTR [r15+0x4],0x0
    je .Los_open_5
    or edx,0x8
.Los_open_5:
    or edx,0x1000000
    mov esi,edx
    mov rdi,r8
    mov edx,0x1b6
    mov eax,0x2000005
    darwin_syscall
    mov r9,QWORD PTR [rsp]
    mov QWORD PTR [r13+0x10],r9
    test rax,rax
    js .Los_open_6
    mov QWORD PTR [r12],rax
    jmp .Los_open_8
.Los_open_6:
    neg eax
    mov edi,eax
    call np_error
    mov DWORD PTR [r12+0x8],eax
    jmp .Los_open_8
.Los_open_7:
    mov r9,QWORD PTR [rsp]
    mov QWORD PTR [r13+0x10],r9
    mov DWORD PTR [r12+0x8],0x6979aadc
.Los_open_8:
    add rsp,0x8
    pop r15
    pop r14
    pop r13
    pop r12
    ret


# os.args: the table `neper_start` built, from the slot at the start of __DATA. rdi = the
# result ([]str, err).
.global neper_os_args
neper_os_args:
    lea rax, [rip+.Lstart_args]
    add rax, QWORD PTR [rip+.Lstart_args]
    mov rcx, QWORD PTR [rax]
    mov rdx, QWORD PTR [rax+8]
    mov QWORD PTR [rdi], rcx
    mov QWORD PTR [rdi+8], rdx
    mov DWORD PTR [rdi+16], 0
    ret

# The raw BSD call: the caller's convention is SysV (rdi, rsi, rdx, rcx, r8, r9, then the
# stack) and the kernel's is (rax = 0x2000000 + n, rdi, rsi, rdx, r10, r8, r9). The result
# is the kernel's own: a negative errno on failure.
.global neper_os_syscall
neper_os_syscall:
    # pipe(2) answers with two descriptors, in eax and edx; for it the first argument is the
    # address of two 32-bit slots they are stored to, and the result is zero.
    push rsi
    push rdi
    mov rax, rdi
    or rax, 0x2000000
    mov r10, r8
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    mov r11, r9
    mov r9, qword ptr [rsp + 24]
    mov r8, r11
    syscall
    jc .Lsys_error
    cmp qword ptr [rsp], 42
    jne .Lsys_done
    mov rcx, qword ptr [rsp + 8]
    mov dword ptr [rcx], eax
    mov dword ptr [rcx + 4], edx
    xor eax, eax
.Lsys_done:
    add rsp, 16
    ret
.Lsys_error:
    neg rax
    add rsp, 16
    ret

# The runtime calls libSystem for threads (pthread_create, pthread_join, pthread_detach) and for
# the monotonic clock (clock_gettime_nsec_np), which dyld binds
# into four slots the linker adds after the program's own imports whenever one of the
# functions below is reached. Each word of this table holds its distance from itself to its
# slot, patched by the linker.
.global neper_runtime_imports
neper_runtime_imports:
.Lruntime_imports:
    .quad 0, 0, 0, 0, 0, 0, 0

# rax = 8 * the index of the pthread function: its address, in rax. Clobbers r10.
np_pthread:
    lea r10, [rip+.Lruntime_imports]
    add r10, rax
    mov rax, QWORD PTR [r10]
    add r10, rax
    mov rax, QWORD PTR [r10]
    ret

# os.clock(kind) -> (i64, err): nanoseconds. The wall clock is gettimeofday; the monotonic one
# is libSystem's clock_gettime_nsec_np(CLOCK_UPTIME_RAW), the same counter mach_absolute_time
# reads, through the fourth runtime import slot.
.global neper_os_clock
neper_os_clock:
    sub rsp, 24
    cmp edi, 1
    ja .Lclock_unsupported
    je .Lclock_monotonic
    mov rdi, rsp
    xor esi, esi
    xor edx, edx
    mov eax, 0x2000074
    darwin_syscall
    test rax, rax
    js .Lclock_failed
    mov rax, qword ptr [rsp]
    imul rax, rax, 1000000000
    mov ecx, dword ptr [rsp + 8]
    imul rcx, rcx, 1000
    add rax, rcx
    xor edx, edx
    add rsp, 24
    ret
.Lclock_monotonic:
    mov eax, 24
    call np_pthread
    mov edi, 8
    call rax
    test rax, rax
    je .Lclock_failed
    xor edx, edx
    add rsp, 24
    ret
.Lclock_unsupported:
    xor eax, eax
    mov edx, 0x2f8bb651
    add rsp, 24
    ret
.Lclock_failed:
    xor eax, eax
    mov edx, 0x6f777ebf
    add rsp, 24
    ret

.global neper_os_seek
neper_os_seek:
    cmp edx, 2
    ja .Lseek_failed
    mov rdi, qword ptr [rdi]
    mov eax, 0x20000c7
    darwin_syscall
    test rax, rax
    js .Lseek_failed
    xor edx, edx
    ret
.Lseek_failed:
    xor eax, eax
    mov edx, 0x6f777ebf
    ret

# os.env_block: rdi = the result (str, err), rsi = the arena. The environment as the kernel
# gave it, NAME=VALUE records each ended by a NUL, copied into the arena.
.global neper_os_env_block
neper_os_env_block:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov QWORD PTR [r12], 0
    mov QWORD PTR [r12+8], 0
    mov DWORD PTR [r12+16], 0
    lea rax, [rip+.Lstart_args]
    add rax, QWORD PTR [rip+.Lstart_args]
    mov r14, QWORD PTR [rax+16]
    xor ebx, ebx
    xor ecx, ecx
.Lenv_measure:
    mov rsi, QWORD PTR [r14+rcx*8]
    test rsi, rsi
    je .Lenv_measured
.Lenv_length:
    inc rbx
    cmp BYTE PTR [rsi], 0
    lea rsi, [rsi+1]
    jne .Lenv_length
    inc rcx
    jmp .Lenv_measure
.Lenv_measured:
    mov rdi, r13
    lea rsi, [rbx+1]
    mov edx, 1
    call np_alloc
    test rax, rax
    je .Lenv_oom
    mov rdi, rax
    mov r8, rax
    xor ecx, ecx
.Lenv_copy:
    mov rsi, QWORD PTR [r14+rcx*8]
    test rsi, rsi
    je .Lenv_done
.Lenv_byte:
    mov dl, BYTE PTR [rsi]
    mov BYTE PTR [rdi], dl
    inc rsi
    inc rdi
    test dl, dl
    jne .Lenv_byte
    inc rcx
    jmp .Lenv_copy
.Lenv_done:
    mov QWORD PTR [r12], r8
    mov QWORD PTR [r12+8], rbx
    jmp .Lenv_out
.Lenv_oom:
    mov DWORD PTR [r12+16], 0x6979aadc
.Lenv_out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# os.spawn: runtime_elf_x64.s's, with the BSD calls: fork (2: rdx is 1 in the child), dup2 (90),
# execve (59) and exit (1).
.global neper_os_spawn
neper_os_spawn:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov r12, rdi
    mov r13, rsi
    mov r14, QWORD PTR [rdx]
    mov r15, QWORD PTR [rdx + 8]
    mov rbx, rcx
    mov QWORD PTR [r12], 0
    mov DWORD PTR [r12 + 8], 0
    test r15, r15
    jz .Lspawn_not_found
    mov rax, QWORD PTR [r13 + 16]
    mov QWORD PTR [rsp], rax
    lea rsi, [r15 + 1]
    shl rsi, 3
    mov rdi, r13
    mov edx, 8
    call np_alloc
    test rax, rax
    jz .Lspawn_oom
    mov QWORD PTR [rsp + 8], rax
    xor r10d, r10d
.Lspawn_copy_arg:
    cmp r10, r15
    jae .Lspawn_copied
    mov rcx, r10
    shl rcx, 4
    mov r11, QWORD PTR [r14 + rcx]
    mov rsi, QWORD PTR [r14 + rcx + 8]
    inc rsi
    mov rdi, r13
    mov edx, 1
    push r10
    push r11
    call np_alloc
    pop r11
    pop r10
    test rax, rax
    jz .Lspawn_oom
    mov rcx, r10
    shl rcx, 4
    mov rdx, QWORD PTR [r14 + rcx + 8]
    mov rdi, rax
    mov rsi, r11
    mov rcx, rdx
    rep movsb
    mov BYTE PTR [rdi], 0
    mov r8, QWORD PTR [rsp + 8]
    mov QWORD PTR [r8 + r10 * 8], rax
    inc r10
    jmp .Lspawn_copy_arg
.Lspawn_copied:
    mov r8, QWORD PTR [rsp + 8]
    mov QWORD PTR [r8 + r15 * 8], 0
    mov eax, 0x2000002
    darwin_syscall
    test rax, rax
    js .Lspawn_failed
    test edx, edx
    jnz .Lspawn_child
    mov rcx, QWORD PTR [rsp]
    mov QWORD PTR [r13 + 16], rcx
    mov QWORD PTR [r12], rax
    jmp .Lspawn_done
.Lspawn_child:
    mov rdi, QWORD PTR [rbx]
    test rdi, rdi
    jz .Lspawn_stdout
    xor esi, esi
    mov eax, 0x200005a
    syscall
.Lspawn_stdout:
    mov rdi, QWORD PTR [rbx + 8]
    cmp rdi, 1
    je .Lspawn_stderr
    mov esi, 1
    mov eax, 0x200005a
    syscall
.Lspawn_stderr:
    mov rdi, QWORD PTR [rbx + 16]
    cmp rdi, 2
    je .Lspawn_exec
    mov esi, 2
    mov eax, 0x200005a
    syscall
.Lspawn_exec:
    mov rsi, QWORD PTR [rsp + 8]
    mov rdi, QWORD PTR [rsi]
    xor edx, edx
    mov eax, 0x200003b
    syscall
    mov edi, 127
    mov eax, 0x2000001
    syscall
.Lspawn_failed:
    mov rcx, QWORD PTR [rsp]
    mov QWORD PTR [r13 + 16], rcx
    mov DWORD PTR [r12 + 8], 0x6f777ebf
    jmp .Lspawn_done
.Lspawn_not_found:
    mov DWORD PTR [r12 + 8], 0x7683e2cd
    jmp .Lspawn_done
.Lspawn_oom:
    mov rcx, QWORD PTR [rsp]
    mov QWORD PTR [r13 + 16], rcx
    mov DWORD PTR [r12 + 8], 0x6979aadc
.Lspawn_done:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# os.wait(proc: *Proc) -> (i32, err): the exit status, or 128 plus the signal that ended it.
.global neper_os_wait
neper_os_wait:
    sub rsp, 24
    mov rdi, QWORD PTR [rdi]
    lea rsi, [rsp]
    xor edx, edx
    xor r10d, r10d
    mov eax, 0x2000007
    darwin_syscall
    test rax, rax
    js .Lwait_failed
    mov eax, DWORD PTR [rsp]
    mov ecx, eax
    and ecx, 0x7f
    jne .Lwait_signal
    shr eax, 8
    and eax, 0xff
    xor edx, edx
    add rsp, 24
    ret
.Lwait_signal:
    lea eax, [rcx+128]
    xor edx, edx
    add rsp, 24
    ret
.Lwait_failed:
    mov eax, -1
    mov edx, 0x6f777ebf
    add rsp, 24
    ret

# os.thread_create: rdi = the result {Thread, err}, rsi = the entry, rdx = its context, rcx =
# the stack size. The thread gets that stack through a pthread attribute block (64 bytes at
# rsp), rounded up to the 16 KB page and at least 64 KB as on Linux; a size the library
# refuses leaves the default.
.global neper_os_thread_create
neper_os_thread_create:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 88
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rdi, rsp
    mov eax, 32
    call np_pthread
    call rax
    test eax, eax
    jne .Lthread_create_failed
    mov rax, 65536
    cmp r14, rax
    cmovb r14, rax
    add r14, 16383
    and r14, -16384
    mov rdi, rsp
    mov rsi, r14
    mov eax, 40
    call np_pthread
    call rax
    test eax, eax
    jne .Lthread_create_failed
    lea rdi, [rsp+64]
    mov rsi, rsp
    mov rdx, r12
    mov rcx, r13
    xor eax, eax
    call np_pthread
    call rax
    mov r14d, eax
    mov rdi, rsp
    mov eax, 48
    call np_pthread
    call rax
    test r14d, r14d
    jne .Lthread_create_failed
    mov rax, QWORD PTR [rsp+64]
    mov QWORD PTR [rbx], rax
    mov DWORD PTR [rbx+8], 0
    jmp .Lthread_create_out
.Lthread_create_failed:
    mov QWORD PTR [rbx], 0
    mov DWORD PTR [rbx+8], 0x6f777ebf
.Lthread_create_out:
    add rsp, 88
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
# os.thread_join(thread: *Thread) -> err.
.global neper_os_thread_join
neper_os_thread_join:
    sub rsp, 8
    mov rdi, QWORD PTR [rdi]
    test rdi, rdi
    je .Lthread_join_failed
    xor esi, esi
    mov eax, 8
    call np_pthread
    call rax
    test eax, eax
    jne .Lthread_join_failed
    add rsp, 8
    ret
.Lthread_join_failed:
    mov eax, 0x6f777ebf
    add rsp, 8
    ret

# os.thread_detach(thread: *Thread) -> err.
.global neper_os_thread_detach
neper_os_thread_detach:
    sub rsp, 8
    mov rdi, QWORD PTR [rdi]
    test rdi, rdi
    je .Lthread_detach_failed
    mov eax, 16
    call np_pthread
    call rax
    test eax, eax
    jne .Lthread_detach_failed
    add rsp, 8
    ret
.Lthread_detach_failed:
    mov eax, 0x6f777ebf
    add rsp, 8
    ret

# Section 8's blocking primitives, __ulock_wait (515) and __ulock_wake (516) with
# UL_COMPARE_AND_WAIT (1) and ULF_WAKE_ALL (0x100). wait_u32(p, expected, timeout_ns) -> err:
# a wake, a value that already differs and a signal are all `ok` -- the fence promises
# spurious wakes -- a negative timeout waits for ever, and a zero one polls once: a value that differs is `ok`, the same one times out.
# The kernel's timeout is in microseconds, rounded up and capped at 32 bits.
.global neper_os_wait_u32
neper_os_wait_u32:
    xor r10d, r10d
    mov rcx, rdx
    test rcx, rcx
    js .Lwait_u32_go
    je .Lwait_u32_zero
    add rcx, 999
    mov rax, rcx
    xor edx, edx
    mov r8d, 1000
    div r8
    mov r10, rax
    mov eax, 0xffffffff
    cmp r10, rax
    cmova r10, rax
.Lwait_u32_go:
    mov edx, esi
    mov rsi, rdi
    mov edi, 1
    mov eax, 0x2000203
    darwin_syscall
    test rax, rax
    jns .Lwait_u32_ok
    cmp rax, -4
    je .Lwait_u32_ok
    cmp rax, -35
    je .Lwait_u32_ok
    cmp rax, -60
    je .Lwait_u32_timeout
    mov eax, 0x6f777ebf
    ret
.Lwait_u32_zero:
    cmp dword ptr [rdi], esi
    jne .Lwait_u32_ok
    jmp .Lwait_u32_timeout
.Lwait_u32_ok:
    xor eax, eax
    ret
.Lwait_u32_timeout:
    mov eax, 0x52812f09
    ret

.global neper_os_wake_one_u32
neper_os_wake_one_u32:
    mov rsi, rdi
    mov edi, 1
    xor edx, edx
    mov eax, 0x2000204
    darwin_syscall
    ret

.global neper_os_wake_all_u32
neper_os_wake_all_u32:
    mov rsi, rdi
    mov edi, 0x101
    xor edx, edx
    mov eax, 0x2000204
    darwin_syscall
    ret

# os.reserve(size) -> (usize, err): address space and no memory, PROT_NONE.
.global neper_os_reserve
neper_os_reserve:
    mov rsi, rdi
    xor edi, edi
    xor edx, edx
    mov r10d, 0x1002
    mov r8, -1
    xor r9d, r9d
    mov eax, 0x20000c5
    darwin_syscall
    test rax, rax
    js .Lreserve_failed
    xor edx, edx
    ret
.Lreserve_failed:
    xor eax, eax
    mov edx, 0x6f777ebf
    ret

# os.commit(address, size) -> err: the reserved pages made readable and writable.
.global neper_os_commit
neper_os_commit:
    mov edx, 3
    mov eax, 0x200004a
    darwin_syscall
    test rax, rax
    js .Lcommit_failed
    xor eax, eax
    ret
.Lcommit_failed:
    mov eax, 0x6f777ebf
    ret

.global neper_hash_bytes
neper_hash_bytes:
    mov r8, rdi
    mov r9, rsi
    push rbx
    push r12
    push r13
    push r14
    push r15
    movabs r13, 11400714785074694791
    movabs r14, 14029467366897019727
    xor ecx, ecx
    cmp r9, 32
    jb .Lhash_small
    mov r10, r13
    add r10, r14
    mov r11, r14
    xor ebx, ebx
    xor r12d, r12d
    sub r12, r13
    mov rdx, r9
    sub rdx, 32
.Lhash_block:
    mov rax, qword ptr [r8 + rcx]
    imul rax, r14
    add r10, rax
    rol r10, 31
    imul r10, r13
    add rcx, 8
    mov rax, qword ptr [r8 + rcx]
    imul rax, r14
    add r11, rax
    rol r11, 31
    imul r11, r13
    add rcx, 8
    mov rax, qword ptr [r8 + rcx]
    imul rax, r14
    add rbx, rax
    rol rbx, 31
    imul rbx, r13
    add rcx, 8
    mov rax, qword ptr [r8 + rcx]
    imul rax, r14
    add r12, rax
    rol r12, 31
    imul r12, r13
    add rcx, 8
    cmp rcx, rdx
    jbe .Lhash_block
    mov r15, r10
    rol r15, 1
    mov rax, r11
    rol rax, 7
    add r15, rax
    mov rax, rbx
    rol rax, 12
    add r15, rax
    mov rax, r12
    rol rax, 18
    add r15, rax
    mov rax, r10
    imul rax, r14
    rol rax, 31
    imul rax, r13
    xor r15, rax
    imul r15, r13
    movabs rax, 9650029242287828579
    add r15, rax
    mov rax, r11
    imul rax, r14
    rol rax, 31
    imul rax, r13
    xor r15, rax
    imul r15, r13
    movabs rax, 9650029242287828579
    add r15, rax
    mov rax, rbx
    imul rax, r14
    rol rax, 31
    imul rax, r13
    xor r15, rax
    imul r15, r13
    movabs rax, 9650029242287828579
    add r15, rax
    mov rax, r12
    imul rax, r14
    rol rax, 31
    imul rax, r13
    xor r15, rax
    imul r15, r13
    movabs rax, 9650029242287828579
    add r15, rax
    jmp .Lhash_sized
.Lhash_small:
    movabs r15, 2870177450012600261
.Lhash_sized:
    add r15, r9
.Lhash_tail8:
    mov rax, rcx
    add rax, 8
    cmp rax, r9
    ja .Lhash_tail4
    mov rax, qword ptr [r8 + rcx]
    imul rax, r14
    rol rax, 31
    imul rax, r13
    xor r15, rax
    rol r15, 27
    imul r15, r13
    movabs rax, 9650029242287828579
    add r15, rax
    add rcx, 8
    jmp .Lhash_tail8
.Lhash_tail4:
    mov rax, rcx
    add rax, 4
    cmp rax, r9
    ja .Lhash_tail1
    mov eax, dword ptr [r8 + rcx]
    imul rax, r13
    xor r15, rax
    rol r15, 23
    imul r15, r14
    movabs rax, 1609587929392839161
    add r15, rax
    add rcx, 4
.Lhash_tail1:
    cmp rcx, r9
    jae .Lhash_final
    movzx rax, byte ptr [r8 + rcx]
    movabs rdx, 2870177450012600261
    imul rax, rdx
    xor r15, rax
    rol r15, 11
    imul r15, r13
    add rcx, 1
    jmp .Lhash_tail1
.Lhash_final:
    mov rax, r15
    shr rax, 33
    xor r15, rax
    imul r15, r14
    mov rax, r15
    shr rax, 29
    xor r15, rax
    movabs rax, 1609587929392839161
    imul r15, rax
    mov rax, r15
    shr rax, 32
    xor rax, r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Section 8's blocking primitives, futex(2) directly: this runtime has no libc.
# `op` is FUTEX_WAIT_PRIVATE (128) and FUTEX_WAKE_PRIVATE (129) -- the private forms
# skip the shared-mapping lookup, and every address here is process-local.
#
# wait_u32(p, expected, timeout_ns) -> err. A wake, a value that already differs
# (EAGAIN) and a signal (EINTR) are all `ok`: the fence promises spurious wakes, so
# every caller rechecks its own state and none can tell them apart.

# os.cpu_features() -> usize (C098): CPUID leaf 1 ECX in the low half, leaf 7 EBX (when the
# CPU has the leaf) in the high, for the caller to keep: CPUID is a trap under a hypervisor.
.global neper_os_cpu_features
neper_os_cpu_features:
    push rbx
    xor r8d, r8d
    xor eax, eax
    cpuid
    cmp eax, 7
    jb .Lfeatures_leaf1
    mov eax, 7
    xor ecx, ecx
    cpuid
    mov r8d, ebx
    shl r8, 32
.Lfeatures_leaf1:
    mov eax, 1
    xor ecx, ecx
    cpuid
    mov eax, ecx
    or rax, r8
    pop rbx
    ret

# os.aes_expand_key(features: usize, key: []const u8, out: []u8) -> usize (C098): FIPS 197's
# schedule of a 16- or 32-byte key with AESKEYGENASSIST, 176 or 240 bytes into `out`, which
# is how many were written; none without AES-NI, for another key size (AES-192 stays with
# the caller) or a short `out`.
.global neper_os_aes_expand_key
neper_os_aes_expand_key:
    xor eax, eax
    and edi, 0x2000000
    jz .Lexpand_ret
    mov rcx, qword ptr [rsi+8]
    mov r8, qword ptr [rsi]
    mov r9, qword ptr [rdx]
    mov r10, qword ptr [rdx+8]
    lea r11, [rip + .Laes_rcon]
    cmp rcx, 16
    je .Lexpand_128
    cmp rcx, 32
    jne .Lexpand_ret
    cmp r10, 240
    jb .Lexpand_ret
    movdqu xmm1, xmmword ptr [r8]
    movdqu xmm3, xmmword ptr [r8+16]
    movdqu xmmword ptr [r9], xmm1
    movdqu xmmword ptr [r9+16], xmm3
    add r9, 32
    mov ecx, 7
.Lexpand_256_round:
    aeskeygenassist xmm2, xmm3, 0
    pshufd xmm2, xmm2, 0xff
    movzx eax, byte ptr [r11]
    movd xmm4, eax
    pshufd xmm4, xmm4, 0
    pxor xmm2, xmm4
    movdqa xmm5, xmm1
    pslldq xmm5, 4
    pxor xmm1, xmm5
    pslldq xmm5, 4
    pxor xmm1, xmm5
    pslldq xmm5, 4
    pxor xmm1, xmm5
    pxor xmm1, xmm2
    movdqu xmmword ptr [r9], xmm1
    add r9, 16
    inc r11
    dec ecx
    jz .Lexpand_256_done
    aeskeygenassist xmm2, xmm1, 0
    pshufd xmm2, xmm2, 0xaa
    movdqa xmm5, xmm3
    pslldq xmm5, 4
    pxor xmm3, xmm5
    pslldq xmm5, 4
    pxor xmm3, xmm5
    pslldq xmm5, 4
    pxor xmm3, xmm5
    pxor xmm3, xmm2
    movdqu xmmword ptr [r9], xmm3
    add r9, 16
    jmp .Lexpand_256_round
.Lexpand_256_done:
    mov eax, 240
    ret
.Lexpand_128:
    cmp r10, 176
    jb .Lexpand_ret
    movdqu xmm1, xmmword ptr [r8]
    movdqu xmmword ptr [r9], xmm1
    add r9, 16
    mov ecx, 10
.Lexpand_128_round:
    aeskeygenassist xmm2, xmm1, 0
    pshufd xmm2, xmm2, 0xff
    movzx eax, byte ptr [r11]
    movd xmm4, eax
    pshufd xmm4, xmm4, 0
    pxor xmm2, xmm4
    movdqa xmm5, xmm1
    pslldq xmm5, 4
    pxor xmm1, xmm5
    pslldq xmm5, 4
    pxor xmm1, xmm5
    pslldq xmm5, 4
    pxor xmm1, xmm5
    pxor xmm1, xmm2
    movdqu xmmword ptr [r9], xmm1
    add r9, 16
    inc r11
    dec ecx
    jnz .Lexpand_128_round
    mov eax, 176
.Lexpand_ret:
    ret
.Laes_rcon: .byte 1, 2, 4, 8, 16, 32, 64, 128, 27, 54

# os.aes_ctr(features: usize, keys: []const u8, counter: []u8, data: []u8) -> usize (C098):
# AES-NI counter mode over the whole 16-byte blocks of `data`, in place. `keys` is FIPS 197's
# expanded schedule, 176, 208 or 240 bytes; `counter` is the 16-byte counter block, its last
# four bytes a big-endian counter that grows by one a block (GCM's inc32) and is stored back.
# Answers the blocks done: none when `features` (os.cpu_features) lacks AES, PCLMULQDQ,
# SSSE3 and SSE4.1 -- PCLMULQDQ so GCM's two halves agree -- or when a slice is too short or
# the schedule is another size. Four blocks in flight.
.global neper_os_aes_ctr
neper_os_aes_ctr:
    push rbx
    push r12
    push r13
    mov r8, rsi
    mov r9, rdx
    mov r10, rcx
    mov r11, rcx
    xor r12d, r12d
    and edi, 0x2080202
    cmp edi, 0x2080202
    jne .Laes_ret
    mov rax, qword ptr [r8+8]
    mov r13d, 9
    cmp rax, 176
    je .Laes_keys_ok
    mov r13d, 11
    cmp rax, 208
    je .Laes_keys_ok
    mov r13d, 13
    cmp rax, 240
    jne .Laes_ret
.Laes_keys_ok:
    cmp qword ptr [r9+8], 16
    jb .Laes_ret
    mov rbx, qword ptr [r10+8]
    cmp qword ptr [r11+8], rbx
    jb .Laes_ret
    shr rbx, 4
    mov r12, rbx
    jz .Laes_ret
    mov r8, qword ptr [r8]
    mov r9, qword ptr [r9]
    mov r10, qword ptr [r10]
    mov r11, qword ptr [r11]
    mov edx, dword ptr [r9+12]
    bswap edx
    movdqu xmm5, xmmword ptr [r9]
.Laes_four:
    cmp rbx, 4
    jb .Laes_one
    movdqa xmm0, xmm5
    lea eax, [rdx]
    bswap eax
    pinsrd xmm0, eax, 3
    movdqa xmm1, xmm5
    lea eax, [rdx+1]
    bswap eax
    pinsrd xmm1, eax, 3
    movdqa xmm2, xmm5
    lea eax, [rdx+2]
    bswap eax
    pinsrd xmm2, eax, 3
    movdqa xmm3, xmm5
    lea eax, [rdx+3]
    bswap eax
    pinsrd xmm3, eax, 3
    movdqu xmm4, xmmword ptr [r8]
    pxor xmm0, xmm4
    pxor xmm1, xmm4
    pxor xmm2, xmm4
    pxor xmm3, xmm4
    lea rax, [r8+16]
    mov ecx, r13d
.Laes_four_round:
    movdqu xmm4, xmmword ptr [rax]
    aesenc xmm0, xmm4
    aesenc xmm1, xmm4
    aesenc xmm2, xmm4
    aesenc xmm3, xmm4
    add rax, 16
    dec ecx
    jnz .Laes_four_round
    movdqu xmm4, xmmword ptr [rax]
    aesenclast xmm0, xmm4
    aesenclast xmm1, xmm4
    aesenclast xmm2, xmm4
    aesenclast xmm3, xmm4
    movdqu xmm4, xmmword ptr [r10]
    pxor xmm0, xmm4
    movdqu xmm4, xmmword ptr [r10+16]
    pxor xmm1, xmm4
    movdqu xmm4, xmmword ptr [r10+32]
    pxor xmm2, xmm4
    movdqu xmm4, xmmword ptr [r10+48]
    pxor xmm3, xmm4
    movdqu xmmword ptr [r11], xmm0
    movdqu xmmword ptr [r11+16], xmm1
    movdqu xmmword ptr [r11+32], xmm2
    movdqu xmmword ptr [r11+48], xmm3
    add edx, 4
    add r10, 64
    add r11, 64
    sub rbx, 4
    jmp .Laes_four
.Laes_one:
    test rbx, rbx
    jz .Laes_store
    movdqa xmm0, xmm5
    mov eax, edx
    bswap eax
    pinsrd xmm0, eax, 3
    movdqu xmm4, xmmword ptr [r8]
    pxor xmm0, xmm4
    lea rax, [r8+16]
    mov ecx, r13d
.Laes_one_round:
    movdqu xmm4, xmmword ptr [rax]
    aesenc xmm0, xmm4
    add rax, 16
    dec ecx
    jnz .Laes_one_round
    movdqu xmm4, xmmword ptr [rax]
    aesenclast xmm0, xmm4
    movdqu xmm4, xmmword ptr [r10]
    pxor xmm0, xmm4
    movdqu xmmword ptr [r11], xmm0
    inc edx
    add r10, 16
    add r11, 16
    dec rbx
    jmp .Laes_one
.Laes_store:
    bswap edx
    mov dword ptr [r9+12], edx
.Laes_ret:
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret

# os.ghash_blocks(features: usize, state: []u8, h: []const u8, data: []const u8) -> usize
# (C098): GHASH over the whole 16-byte blocks of `data` with PCLMULQDQ -- state = (state ^
# block) * H in GF(2^128), the 16-byte `state` and `h` in GCM's byte order. Answers the
# blocks done: none when `features` (os.cpu_features) lacks PCLMULQDQ and SSSE3, or when
# `state` or `h` is short. Four blocks a step against H^4..H, one reduction for the four
# (Intel's carry-less multiplication paper, 5.2; the products are summed unreduced).
.global neper_os_ghash_blocks
neper_os_ghash_blocks:
    mov r8, rsi
    mov r9, rdx
    mov r10, rcx
    xor eax, eax
    and edi, 0x202
    cmp edi, 0x202
    jne .Lghash_ret
    cmp qword ptr [r8+8], 16
    jb .Lghash_ret
    cmp qword ptr [r9+8], 16
    jb .Lghash_ret
    mov rcx, qword ptr [r10+8]
    shr rcx, 4
    mov rax, rcx
    jz .Lghash_ret
    mov r11, qword ptr [r10]
    mov rdx, qword ptr [r8]
    mov r9, qword ptr [r9]
    movdqu xmm10, xmmword ptr [rip + .Lghash_flip]
    movdqu xmm0, xmmword ptr [rdx]
    pshufb xmm0, xmm10
    movdqu xmm1, xmmword ptr [r9]
    pshufb xmm1, xmm10
    cmp rcx, 4
    jb .Lghash_loop
    movdqa xmm15, xmm0
    movdqa xmm0, xmm1
    call .Lghash_mul
    movdqa xmm11, xmm0
    call .Lghash_mul
    movdqa xmm12, xmm0
    call .Lghash_mul
    movdqa xmm13, xmm0
    movdqa xmm0, xmm15
.Lghash_four:
    movdqu xmm2, xmmword ptr [r11]
    pshufb xmm2, xmm10
    pxor xmm2, xmm0
    movdqu xmm5, xmmword ptr [r11+16]
    pshufb xmm5, xmm10
    movdqu xmm7, xmmword ptr [r11+32]
    pshufb xmm7, xmm10
    movdqu xmm14, xmmword ptr [r11+48]
    pshufb xmm14, xmm10
    movdqa xmm3, xmm2
    pclmulqdq xmm3, xmm13, 0x00
    movdqa xmm6, xmm2
    pclmulqdq xmm6, xmm13, 0x11
    movdqa xmm4, xmm2
    pclmulqdq xmm4, xmm13, 0x10
    movdqa xmm9, xmm2
    pclmulqdq xmm9, xmm13, 0x01
    pxor xmm4, xmm9
    movdqa xmm8, xmm5
    pclmulqdq xmm8, xmm12, 0x00
    pxor xmm3, xmm8
    movdqa xmm8, xmm5
    pclmulqdq xmm8, xmm12, 0x11
    pxor xmm6, xmm8
    movdqa xmm8, xmm5
    pclmulqdq xmm8, xmm12, 0x10
    pxor xmm4, xmm8
    movdqa xmm8, xmm5
    pclmulqdq xmm8, xmm12, 0x01
    pxor xmm4, xmm8
    movdqa xmm8, xmm7
    pclmulqdq xmm8, xmm11, 0x00
    pxor xmm3, xmm8
    movdqa xmm8, xmm7
    pclmulqdq xmm8, xmm11, 0x11
    pxor xmm6, xmm8
    movdqa xmm8, xmm7
    pclmulqdq xmm8, xmm11, 0x10
    pxor xmm4, xmm8
    movdqa xmm8, xmm7
    pclmulqdq xmm8, xmm11, 0x01
    pxor xmm4, xmm8
    movdqa xmm8, xmm14
    pclmulqdq xmm8, xmm1, 0x00
    pxor xmm3, xmm8
    movdqa xmm8, xmm14
    pclmulqdq xmm8, xmm1, 0x11
    pxor xmm6, xmm8
    movdqa xmm8, xmm14
    pclmulqdq xmm8, xmm1, 0x10
    pxor xmm4, xmm8
    movdqa xmm8, xmm14
    pclmulqdq xmm8, xmm1, 0x01
    pxor xmm4, xmm8
    movdqa xmm5, xmm4
    pslldq xmm5, 8
    psrldq xmm4, 8
    pxor xmm3, xmm5
    pxor xmm6, xmm4
    call .Lghash_reduce
    add r11, 64
    sub rcx, 4
    cmp rcx, 4
    jae .Lghash_four
    test rcx, rcx
    jz .Lghash_store
.Lghash_loop:
    movdqu xmm2, xmmword ptr [r11]
    pshufb xmm2, xmm10
    pxor xmm0, xmm2
    call .Lghash_mul
    add r11, 16
    dec rcx
    jnz .Lghash_loop
.Lghash_store:
    pshufb xmm0, xmm10
    movdqu xmmword ptr [rdx], xmm0
.Lghash_ret:
    ret
# xmm0 = xmm0 * xmm1 in GF(2^128) (bit-reflected, both byte-reversed); clobbers xmm2-xmm9.
.Lghash_mul:
    movdqa xmm3, xmm0
    pclmulqdq xmm3, xmm1, 0x00
    movdqa xmm4, xmm0
    pclmulqdq xmm4, xmm1, 0x10
    movdqa xmm5, xmm0
    pclmulqdq xmm5, xmm1, 0x01
    movdqa xmm6, xmm0
    pclmulqdq xmm6, xmm1, 0x11
    pxor xmm4, xmm5
    movdqa xmm5, xmm4
    pslldq xmm5, 8
    psrldq xmm4, 8
    pxor xmm3, xmm5
    pxor xmm6, xmm4
# xmm0 = the 256-bit product xmm6:xmm3, shifted left one bit and reduced by x^128 + x^7 + x^2
# + x + 1; clobbers xmm2-xmm9.
.Lghash_reduce:
    movdqa xmm7, xmm3
    psrld xmm7, 31
    movdqa xmm8, xmm6
    psrld xmm8, 31
    pslld xmm3, 1
    pslld xmm6, 1
    movdqa xmm9, xmm7
    psrldq xmm9, 12
    pslldq xmm8, 4
    pslldq xmm7, 4
    por xmm3, xmm7
    por xmm6, xmm8
    por xmm6, xmm9
    movdqa xmm7, xmm3
    pslld xmm7, 31
    movdqa xmm8, xmm3
    pslld xmm8, 30
    movdqa xmm9, xmm3
    pslld xmm9, 25
    pxor xmm7, xmm8
    pxor xmm7, xmm9
    movdqa xmm8, xmm7
    psrldq xmm8, 4
    pslldq xmm7, 12
    pxor xmm3, xmm7
    movdqa xmm2, xmm3
    psrld xmm2, 1
    movdqa xmm4, xmm3
    psrld xmm4, 2
    movdqa xmm5, xmm3
    psrld xmm5, 7
    pxor xmm2, xmm4
    pxor xmm2, xmm5
    pxor xmm2, xmm8
    pxor xmm3, xmm2
    pxor xmm6, xmm3
    movdqa xmm0, xmm6
    ret
.Lghash_flip: .byte 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0
