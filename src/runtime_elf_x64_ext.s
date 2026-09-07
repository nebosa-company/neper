.intel_syntax noprefix
.text

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
    call .Lext_alloc
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
    call .Lext_alloc
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
    call .Lext_alloc
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
    call .Lext_alloc
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

.Lext_alloc:
    test rdi, rdi
    jz .Lalloc_fail
    test rdx, rdx
    jz .Lalloc_fail
    lea rcx, [rdx - 1]
    test rcx, rdx
    jnz .Lalloc_fail
    mov rax, qword ptr [rdi + 16]
    add rcx, rax
    jc .Lalloc_fail
    neg rdx
    and rcx, rdx
    mov r8, qword ptr [rdi + 8]
    sub r8, rcx
    jc .Lalloc_fail
    cmp rsi, r8
    ja .Lalloc_fail
    lea rax, [rcx + rsi]
    mov qword ptr [rdi + 16], rax
    mov rax, qword ptr [rdi]
    add rax, rcx
    ret
.Lalloc_fail:
    xor eax, eax
    ret

// Spec section 9 rule 4: the supplied `hash` is xxHash64 with seed 0 over a
// value's canonical little-endian bytes. This must agree bit for bit with
// algo.hash.xxhash64 and with neper_hash_bytes in bootstrap/runtime.c; a fixture
// asserts all three agree on both platforms.
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
