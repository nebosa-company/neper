.intel_syntax noprefix
.text

# The x86-64 Linux runtime: raw system calls, no libc. One file, embedded whole into
# `runtime_elf_x64.e` by scripts/embed-elf-runtime.ps1.
#
# Order matters: the linker appends this runtime as a prefix, cut after the last function
# the program reaches (D150), so the two shared helpers come first and the functions follow
# from the ones nearly every program needs to the ones few do. A function may call only
# what precedes it here.
#
# The first fourteen -- `np_error` through `neper_os_readdir` -- had lost their source and
# lived as bytes in link_elf.e until D151; they were recovered from those bytes and reassemble
# to them exactly, which is why their spelling differs from the rest.

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

.global neper_mem_mark
neper_mem_mark:
    mov rax,QWORD PTR [rdi+0x10]
    ret

.global neper_mem_reset
neper_mem_reset:
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
    mov eax,0x3c
    syscall
    ud2

.global neper_os_write
neper_os_write:
    push rbx
    mov rdx,QWORD PTR [rsi+0x8]
    mov rsi,QWORD PTR [rsi]
    mov rdi,QWORD PTR [rdi]
    mov eax,0x1
    syscall
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

# A failed check (spec section 11): the record text, then the two operands wherever the
# text holds a byte below 2 -- 0 prints the operand unsigned, 1 signed -- then a
# newline, then the symbolised backtrace from the table r10 points at, all to stderr,
# and exit 134. The generated code
# jumps here with rdi = text, rsi = its length, rdx and rcx = the operands; nothing
# returns, so the stack is simply realigned and the callee-saved registers are not kept.
.global neper_trap
neper_trap:
    mov r11,QWORD PTR [rsp]
    and rsp,-16
    sub rsp,64
    mov QWORD PTR [rsp+32],rbp
    mov QWORD PTR [rsp+40],r10
    mov QWORD PTR [rsp+48],r11
    mov rbx,rdi
    lea r13,[rdi+rsi]
    mov r12,rdx
    mov r14,rcx
    xor r15d,r15d
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
    mov eax,1
    syscall
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
    mov eax,1
    syscall
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
    mov eax,1
    syscall
    jmp .Ltrap_segment
.Ltrap_end:
    mov BYTE PTR [rsp],10
    mov rsi,rsp
    mov edx,1
    mov edi,2
    mov eax,1
    syscall
# The backtrace: every frame is rbp-chained, so from the trapping function's frame and
# the return address into it the walk is [rbp+8] and [rbp], each address looked up in
# the symbol table the linker appended after the code -- entries of a start relative
# to the table, a length, and a name -- until one is not in it, which is the runtime's
# own entry, or thirty-two frames have been printed.
    mov r14d,32
    mov r12,QWORD PTR [rsp+48]
    mov r13,QWORD PTR [rsp+32]
.Ltrap_frame:
    test r14d,r14d
    jz .Ltrap_exit
    dec r14d
    mov rbx,QWORD PTR [rsp+40]
    mov r15d,DWORD PTR [rbx]
    add rbx,4
.Ltrap_lookup:
    test r15d,r15d
    jz .Ltrap_exit
    dec r15d
    movsxd rax,DWORD PTR [rbx]
    add rax,QWORD PTR [rsp+40]
    cmp r12,rax
    jb .Ltrap_next_entry
    mov ecx,DWORD PTR [rbx+4]
    add rax,rcx
    cmp r12,rax
    jb .Ltrap_found
.Ltrap_next_entry:
    add rbx,16
    jmp .Ltrap_lookup
.Ltrap_found:
    mov BYTE PTR [rsp],32
    mov BYTE PTR [rsp+1],32
    mov BYTE PTR [rsp+2],97
    mov BYTE PTR [rsp+3],116
    mov BYTE PTR [rsp+4],32
    mov rsi,rsp
    mov edx,5
    mov edi,2
    mov eax,1
    syscall
    mov esi,DWORD PTR [rbx+8]
    add rsi,QWORD PTR [rsp+40]
    mov edx,DWORD PTR [rbx+12]
    mov edi,2
    mov eax,1
    syscall
    mov BYTE PTR [rsp],10
    mov rsi,rsp
    mov edx,1
    mov edi,2
    mov eax,1
    syscall
    test r13,r13
    jz .Ltrap_exit
    mov r12,QWORD PTR [r13+8]
    mov r13,QWORD PTR [r13]
    jmp .Ltrap_frame
.Ltrap_exit:
    mov edi,134
    mov eax,231
    syscall
    ud2

.global neper_os_read
neper_os_read:
    push rbx
    mov rdx,QWORD PTR [rsi+0x8]
    mov rsi,QWORD PTR [rsi]
    mov rdi,QWORD PTR [rdi]
    xor eax,eax
    syscall
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
    mov eax,0x3
    syscall
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
    or edx,0x40
.Los_open_3:
    cmp BYTE PTR [r15+0x3],0x0
    je .Los_open_4
    or edx,0x200
.Los_open_4:
    cmp BYTE PTR [r15+0x4],0x0
    je .Los_open_5
    or edx,0x400
.Los_open_5:
    mov eax,0x101
    mov edi,0xffffff9c
    mov rsi,r8
    mov r10d,0x1b6
    syscall
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

.global neper_os_args
neper_os_args:
    push rbx
    push r12
    push r14
    push r15
    sub rsp, 16
    mov r12, rdi
    mov rbx, rsi
    mov r14, r13
    mov r15, qword ptr [r14]
    sub r15, r14
    shr r15, 4
    mov qword ptr [r12], 0
    mov qword ptr [r12 + 8], 0
    mov dword ptr [r12 + 16], 0
    mov rax, qword ptr [rbx + 16]
    mov qword ptr [rsp], rax
    test r15, r15
    jz .Largs_done
    mov rsi, r15
    shl rsi, 4
    mov rdi, rbx
    mov edx, 8
    call np_alloc
    test rax, rax
    jz .Largs_oom
    mov qword ptr [rsp + 8], rax
    xor r10d, r10d
.Largs_copy:
    cmp r10, r15
    jae .Largs_copied
    mov rcx, r10
    shl rcx, 4
    mov r11, qword ptr [r14 + rcx]
    mov rsi, qword ptr [r14 + rcx + 8]
    mov rdi, rbx
    mov edx, 1
    push r10
    push r11
    call np_alloc
    pop r11
    pop r10
    test rax, rax
    jz .Largs_oom
    mov rcx, r10
    shl rcx, 4
    mov rdx, qword ptr [r14 + rcx + 8]
    mov rdi, rax
    mov rsi, r11
    mov rcx, rdx
    rep movsb
    mov r8, qword ptr [rsp + 8]
    mov rcx, r10
    shl rcx, 4
    mov qword ptr [r8 + rcx], rax
    mov qword ptr [r8 + rcx + 8], rdx
    inc r10
    jmp .Largs_copy
.Largs_copied:
    mov rax, qword ptr [rsp + 8]
    mov qword ptr [r12], rax
    mov qword ptr [r12 + 8], r15
    jmp .Largs_done
.Largs_oom:
    mov rax, qword ptr [rsp]
    mov qword ptr [rbx + 16], rax
    mov dword ptr [r12 + 16], 0x6979aadc
.Largs_done:
    add rsp, 16
    pop r15
    pop r14
    pop r12
    pop rbx
    ret

.global neper_os_reserve
neper_os_reserve:
    mov rsi, rdi
    xor edi, edi
    xor edx, edx
    mov r10d, 0x22
    mov r8, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    test rax, rax
    js .Lreserve_failed
    xor edx, edx
    ret
.Lreserve_failed:
    xor eax, eax
    mov edx, 0x6f777ebf
    ret

.global neper_os_commit
neper_os_commit:
    mov edx, 3
    mov eax, 10
    syscall
    test rax, rax
    js .Lcommit_failed
    xor eax, eax
    ret
.Lcommit_failed:
    mov eax, 0x6f777ebf
    ret

# The raw system call, and the reason a Linux executable can import nothing. Six
# arguments always, so nothing here inspects the number to decide how many to move.
#
# Two conventions meet: the caller's is SysV (rdi, rsi, rdx, rcx, r8, r9, then the
# stack) and the kernel's is (rax, rdi, rsi, rdx, r10, r8, r9). Every move below reads
# its source before anything writes it -- a3 is lifted out of r8 before r8 is reloaded,
# and a4 is parked in r11 because r9 is overwritten first. `syscall` clobbers rcx and
# r11, neither of which is live past it.
#
# The result is the kernel's own: a negative errno on failure, which is why the return
# type is `isize` and not an `err`. Turning one into the other is `e.os`'s job.
.global neper_os_syscall
neper_os_syscall:
    mov rax, rdi
    mov r10, r8
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    mov r11, r9
    mov r9, qword ptr [rsp + 8]
    mov r8, r11
    syscall
    ret

.global neper_os_clock
neper_os_clock:
    sub rsp, 16
    cmp edi, 1
    ja .Lclock_unsupported
    mov rsi, rsp
    mov eax, 228
    syscall
    test rax, rax
    js .Lclock_failed
    mov rax, qword ptr [rsp]
    imul rax, rax, 1000000000
    add rax, qword ptr [rsp + 8]
    xor edx, edx
    add rsp, 16
    ret
.Lclock_unsupported:
    xor eax, eax
    mov edx, 0x2f8bb651
    add rsp, 16
    ret
.Lclock_failed:
    xor eax, eax
    mov edx, 0x6f777ebf
    add rsp, 16
    ret

.global neper_os_seek
neper_os_seek:
    cmp edx, 2
    ja .Lseek_failed
    mov rdi, qword ptr [rdi]
    mov eax, 8
    syscall
    test rax, rax
    js .Lseek_failed
    xor edx, edx
    ret
.Lseek_failed:
    xor eax, eax
    mov edx, 0x6f777ebf
    ret

// Spec section 9 rule 4: the supplied `hash` is xxHash64 with seed 0 over a
// value's canonical little-endian bytes. This must agree bit for bit with
// algo.hash.xxhash64 and with neper_hash_bytes in bootstrap/runtime.c; a fixture
// asserts all three agree on both platforms.

.global neper_os_readdir
neper_os_readdir:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,0x1040
    mov r12,rdi
    mov r13,rsi
    mov r14,rdx
    mov r15,QWORD PTR [r13+0x10]
    mov QWORD PTR [r12],0x0
    mov QWORD PTR [r12+0x8],0x0
    mov DWORD PTR [r12+0x10],0x0
    mov rsi,QWORD PTR [r14+0x8]
    inc rsi
    je .Los_readdir_15
    mov rdi,r13
    mov edx,0x1
    call np_alloc
    test rax,rax
    je .Los_readdir_15
    mov r8,rax
    mov rcx,QWORD PTR [r14+0x8]
    mov rsi,QWORD PTR [r14]
    mov rdi,r8
    rep movs BYTE PTR es:[rdi],BYTE PTR ds:[rsi]
    mov BYTE PTR [rdi],0x0
    mov eax,0x101
    mov edi,0xffffff9c
    mov rsi,r8
    mov edx,0x90000
    xor r10d,r10d
    syscall
    mov QWORD PTR [r13+0x10],r15
    test rax,rax
    js .Los_readdir_12
    mov rbx,rax
    mov rdi,r13
    mov esi,0x180
    mov edx,0x8
    call np_alloc
    test rax,rax
    je .Los_readdir_14
    mov QWORD PTR [rsp+0x1000],rax
    mov QWORD PTR [rsp+0x1008],0x0
    mov QWORD PTR [rsp+0x1010],0x10
.Los_readdir_1:
    mov eax,0xd9
    mov rdi,rbx
    mov rsi,rsp
    mov edx,0x1000
    syscall
    test rax,rax
    js .Los_readdir_13
    je .Los_readdir_11
    mov QWORD PTR [rsp+0x1018],rax
    xor r8d,r8d
.Los_readdir_2:
    cmp r8,QWORD PTR [rsp+0x1018]
    jae .Los_readdir_1
    lea r10,[rsp+r8*1]
    movzx r11d,WORD PTR [r10+0x10]
    lea rsi,[r10+0x13]
    cmp BYTE PTR [rsi],0x2e
    jne .Los_readdir_3
    cmp BYTE PTR [rsi+0x1],0x0
    je .Los_readdir_10
    cmp BYTE PTR [rsi+0x1],0x2e
    jne .Los_readdir_3
    cmp BYTE PTR [rsi+0x2],0x0
    je .Los_readdir_10
.Los_readdir_3:
    xor ecx,ecx
.Los_readdir_4:
    cmp BYTE PTR [rsi+rcx*1],0x0
    je .Los_readdir_5
    inc rcx
    jmp .Los_readdir_4
.Los_readdir_5:
    mov QWORD PTR [rsp+0x1020],r8
    mov QWORD PTR [rsp+0x1028],r11
    mov QWORD PTR [rsp+0x1030],rcx
    mov rax,QWORD PTR [rsp+0x1008]
    cmp rax,QWORD PTR [rsp+0x1010]
    jne .Los_readdir_6
    mov rdx,QWORD PTR [rsp+0x1010]
    shl rdx,1
    mov QWORD PTR [rsp+0x1010],rdx
    imul rsi,rdx,0x18
    mov rdi,r13
    mov edx,0x8
    call np_alloc
    test rax,rax
    je .Los_readdir_14
    mov rdi,rax
    mov rsi,QWORD PTR [rsp+0x1000]
    mov rcx,QWORD PTR [rsp+0x1008]
    imul rcx,rcx,0x18
    rep movs BYTE PTR es:[rdi],BYTE PTR ds:[rsi]
    mov QWORD PTR [rsp+0x1000],rax
.Los_readdir_6:
    mov rdi,r13
    mov rsi,QWORD PTR [rsp+0x1030]
    mov edx,0x1
    call np_alloc
    test rax,rax
    je .Los_readdir_14
    mov rdi,rax
    mov r8,QWORD PTR [rsp+0x1020]
    lea rsi,[rsp+r8*1+0x13]
    mov rcx,QWORD PTR [rsp+0x1030]
    rep movs BYTE PTR es:[rdi],BYTE PTR ds:[rsi]
    mov rdx,QWORD PTR [rsp+0x1008]
    imul rdx,rdx,0x18
    add rdx,QWORD PTR [rsp+0x1000]
    mov QWORD PTR [rdx],rax
    mov rcx,QWORD PTR [rsp+0x1030]
    mov QWORD PTR [rdx+0x8],rcx
    mov r8,QWORD PTR [rsp+0x1020]
    mov al,BYTE PTR [rsp+r8*1+0x12]
    mov BYTE PTR [rdx+0x10],0x3
    cmp al,0x8
    jne .Los_readdir_7
    mov BYTE PTR [rdx+0x10],0x0
    jmp .Los_readdir_9
.Los_readdir_7:
    cmp al,0x4
    jne .Los_readdir_8
    mov BYTE PTR [rdx+0x10],0x1
    jmp .Los_readdir_9
.Los_readdir_8:
    cmp al,0xa
    jne .Los_readdir_9
    mov BYTE PTR [rdx+0x10],0x2
.Los_readdir_9:
    inc QWORD PTR [rsp+0x1008]
    mov r8,QWORD PTR [rsp+0x1020]
    add r8,QWORD PTR [rsp+0x1028]
    jmp .Los_readdir_2
.Los_readdir_10:
    add r8,r11
    jmp .Los_readdir_2
.Los_readdir_11:
    mov eax,0x3
    mov rdi,rbx
    syscall
    mov rax,QWORD PTR [rsp+0x1000]
    mov QWORD PTR [r12],rax
    mov rax,QWORD PTR [rsp+0x1008]
    mov QWORD PTR [r12+0x8],rax
    jmp .Los_readdir_16
.Los_readdir_12:
    neg eax
    mov edi,eax
    call np_error
    mov DWORD PTR [r12+0x10],eax
    jmp .Los_readdir_16
.Los_readdir_13:
    neg eax
    mov edi,eax
    call np_error
    mov DWORD PTR [r12+0x10],eax
    mov eax,0x3
    mov rdi,rbx
    syscall
    mov QWORD PTR [r13+0x10],r15
    jmp .Los_readdir_16
.Los_readdir_14:
    mov eax,0x3
    mov rdi,rbx
    syscall
.Los_readdir_15:
    mov QWORD PTR [r13+0x10],r15
    mov DWORD PTR [r12+0x10],0x6979aadc
.Los_readdir_16:
    add rsp,0x1040
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
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
.global neper_os_wait_u32
neper_os_wait_u32:
    sub rsp, 16
    xor r10d, r10d
    test rdx, rdx
    js .Lwait_go
    # A timeout builds a timespec in the red-zone-free frame above; zero nanoseconds
    # is a zero timespec, which futex returns ETIMEDOUT from at once -- one poll.
    mov rax, rdx
    mov rcx, 1000000000
    xor edx, edx
    div rcx
    mov qword ptr [rsp], rax
    mov qword ptr [rsp + 8], rdx
    mov r10, rsp
.Lwait_go:
    mov edx, esi
    mov esi, 128
    xor r8d, r8d
    xor r9d, r9d
    mov eax, 202
    syscall
    test rax, rax
    jns .Lwait_ok
    cmp rax, -11
    je .Lwait_ok
    cmp rax, -4
    je .Lwait_ok
    cmp rax, -110
    je .Lwait_timeout
    mov eax, 0x6f777ebf
    add rsp, 16
    ret
.Lwait_ok:
    xor eax, eax
    add rsp, 16
    ret
.Lwait_timeout:
    mov eax, 0x52812f09
    add rsp, 16
    ret

.global neper_os_wake_one_u32
neper_os_wake_one_u32:
    mov esi, 129
    mov edx, 1
    xor r10d, r10d
    xor r8d, r8d
    xor r9d, r9d
    mov eax, 202
    syscall
    ret

.global neper_os_wake_all_u32
neper_os_wake_all_u32:
    mov esi, 129
    mov edx, 2147483647
    xor r10d, r10d
    xor r8d, r8d
    xor r9d, r9d
    mov eax, 202
    syscall
    ret

.global neper_os_thread_create
neper_os_thread_create:
    // rdi = (Thread, err) slot, rsi = entry, rdx = ctx, rcx = stack size.
    //
    // There is no libc here -- the ELF output is a static executable -- so a thread
    // is `clone(2)` over a mapping this allocates. The mapping holds three things:
    // the join word at +0, its own size at +8 so `join` can give it back, and the
    // child's stack growing down from the top.
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rbx, rcx
    cmp rbx, 65536
    jae .Lthread_size_ok
    mov rbx, 65536
.Lthread_size_ok:
    mov rsi, rbx
    xor edi, edi
    mov edx, 3
    mov r10d, 0x22
    mov r8, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    test rax, rax
    js .Lthread_create_failed
    mov r9, rax
    mov qword ptr [r9 + 8], rbx
    // The child finds its entry point and context on the stack it starts on.
    lea r11, [r9 + rbx]
    and r11, -16
    sub r11, 16
    mov qword ptr [r11], r13
    mov qword ptr [r11 + 8], r14
    // CLONE_VM|FS|FILES|SIGHAND|THREAD|SYSVSEM|PARENT_SETTID|CHILD_CLEARTID, with the
    // same word for both. CHILD_CLEARTID alone is not enough: it only zeroes the word
    // when the thread dies and never sets it, so `join` read zero straight away and
    // unmapped a stack the child was still running on. PARENT_SETTID is what puts the
    // tid there to begin with.
    mov edi, 0x350f00
    mov rsi, r11
    mov rdx, r9
    mov r10, r9
    xor r8d, r8d
    mov eax, 56
    syscall
    test rax, rax
    js .Lthread_create_unmap
    jz .Lthread_child
    mov qword ptr [r12], r9
    mov dword ptr [r12 + 8], 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.Lthread_child:
    mov rdi, qword ptr [rsp + 8]
    mov rax, qword ptr [rsp]
    call rax
    xor edi, edi
    mov eax, 60
    syscall
.Lthread_create_unmap:
    mov rdi, r9
    mov rsi, rbx
    mov eax, 11
    syscall
.Lthread_create_failed:
    mov qword ptr [r12], 0
    mov dword ptr [r12 + 8], 0x6f777ebf
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.global neper_os_thread_join
neper_os_thread_join:
    push rbx
    push r12
    mov r12, qword ptr [rdi]
    test r12, r12
    jz .Lthread_join_failed
    mov rbx, qword ptr [r12 + 8]
.Lthread_join_wait:
    mov eax, dword ptr [r12]
    test eax, eax
    jz .Lthread_join_done
    // FUTEX_WAIT on the tid the kernel will clear. A spurious wake or a value that
    // has already changed comes back here, which is why this is a loop.
    mov rdi, r12
    xor esi, esi
    mov edx, eax
    xor r10d, r10d
    mov eax, 202
    syscall
    jmp .Lthread_join_wait
.Lthread_join_done:
    mov rdi, r12
    mov rsi, rbx
    mov eax, 11
    syscall
    xor eax, eax
    pop r12
    pop rbx
    ret
.Lthread_join_failed:
    mov eax, 0x6f777ebf
    pop r12
    pop rbx
    ret

.global neper_os_thread_detach
neper_os_thread_detach:
    // Nothing waits for a detached thread, so nothing can know when its stack stops
    // being in use: the mapping is left alone. A reaper would be the way to give it
    // back, and there is no thread to run one on yet.
    xor eax, eax
    ret

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
    mov r14, qword ptr [rdx]
    mov r15, qword ptr [rdx + 8]
    mov rbx, rcx
    mov qword ptr [r12], 0
    mov dword ptr [r12 + 8], 0
    test r15, r15
    jz .Lspawn_not_found
    mov rax, qword ptr [r13 + 16]
    mov qword ptr [rsp], rax
    lea rsi, [r15 + 1]
    shl rsi, 3
    mov rdi, r13
    mov edx, 8
    call np_alloc
    test rax, rax
    jz .Lspawn_oom
    mov qword ptr [rsp + 8], rax
    xor r10d, r10d
.Lspawn_copy_arg:
    cmp r10, r15
    jae .Lspawn_copied
    mov rcx, r10
    shl rcx, 4
    mov r11, qword ptr [r14 + rcx]
    mov rsi, qword ptr [r14 + rcx + 8]
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
    mov rdx, qword ptr [r14 + rcx + 8]
    mov rdi, rax
    mov rsi, r11
    mov rcx, rdx
    rep movsb
    mov byte ptr [rdi], 0
    mov r8, qword ptr [rsp + 8]
    mov qword ptr [r8 + r10 * 8], rax
    inc r10
    jmp .Lspawn_copy_arg
.Lspawn_copied:
    mov r8, qword ptr [rsp + 8]
    mov qword ptr [r8 + r15 * 8], 0
    mov eax, 57
    syscall
    test rax, rax
    js .Lspawn_failed
    jz .Lspawn_child
    mov rcx, qword ptr [rsp]
    mov qword ptr [r13 + 16], rcx
    mov qword ptr [r12], rax
    jmp .Lspawn_done
.Lspawn_child:
    mov rdi, qword ptr [rbx]
    test rdi, rdi
    jz .Lspawn_stdout
    xor esi, esi
    mov eax, 33
    syscall
.Lspawn_stdout:
    mov rdi, qword ptr [rbx + 8]
    cmp rdi, 1
    je .Lspawn_stderr
    mov esi, 1
    mov eax, 33
    syscall
.Lspawn_stderr:
    mov rdi, qword ptr [rbx + 16]
    cmp rdi, 2
    je .Lspawn_exec
    mov esi, 2
    mov eax, 33
    syscall
.Lspawn_exec:
    mov rsi, qword ptr [rsp + 8]
    mov rdi, qword ptr [rsi]
    xor edx, edx
    mov eax, 59
    syscall
    mov edi, 127
    mov eax, 60
    syscall
.Lspawn_failed:
    mov rcx, qword ptr [rsp]
    mov qword ptr [r13 + 16], rcx
    mov dword ptr [r12 + 8], 0x6f777ebf
    jmp .Lspawn_done
.Lspawn_not_found:
    mov dword ptr [r12 + 8], 0x7683e2cd
    jmp .Lspawn_done
.Lspawn_oom:
    mov rcx, qword ptr [rsp]
    mov qword ptr [r13 + 16], rcx
    mov dword ptr [r12 + 8], 0x6979aadc
.Lspawn_done:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.global neper_os_wait
neper_os_wait:
    push r12
    sub rsp, 16
    mov r12, rdi
    mov rdi, qword ptr [rdi]
    mov rsi, rsp
    xor edx, edx
    xor r10d, r10d
    mov eax, 61
    syscall
    test rax, rax
    js .Lwait_failed
    mov eax, dword ptr [rsp]
    mov ecx, eax
    and ecx, 0x7f
    jnz .Lwait_signal
    shr eax, 8
    and eax, 0xff
    xor edx, edx
    jmp .Lwait_done
.Lwait_signal:
    lea eax, [rcx + 128]
    xor edx, edx
    jmp .Lwait_done
.Lwait_failed:
    mov eax, -1
    mov edx, 0x6f777ebf
.Lwait_done:
    add rsp, 16
    pop r12
    ret
