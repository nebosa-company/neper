# The x64 ELF entry, embedded as `append_startup` in link_elf.e: the root arena mapped, the
# arguments copied into it as a table of slices, `main(&arena, &args)` called, and the program
# ended with exit_group (D2113) -- status 1 when main returned an error, 111 when the arena
# could not be had. rbp carries the arena's size, patched in the first movabs (D225): a size
# the host refuses is halved down to a mebibyte (D5930). rbp is zero in main's caller.
#
#   as --64 startup_elf_x64.s -o s.o && objcopy -O binary --only-section=.text s.o s.bin
.intel_syntax noprefix
.text
    mov r12, rsp
    movabs rbp, 0x40000000
.Lreserve:
    xor edi, edi
    mov rsi, rbp
    mov edx, 3
    mov r10d, 0x4022
    mov r8, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    test rax, rax
    jns .Lmapped
    shr rbp, 1
    cmp rbp, 0x100000
    jae .Lreserve
    jmp .Lfail
.Lmapped:
    mov r13, rax
    mov r14, QWORD PTR [r12]
    mov rbx, r14
    shl rbx, 4
    cmp rbx, rbp
    ja .Lfail
    xor r15d, r15d
.Largument:
    cmp r15, r14
    jae .Lmain
    mov r8, QWORD PTR [r12+r15*8+8]
    xor ecx, ecx
.Llength:
    cmp BYTE PTR [r8+rcx], 0
    je .Lcounted
    inc rcx
    jmp .Llength
.Lcounted:
    mov rax, rbx
    add rax, rcx
    jc .Lfail
    cmp rax, rbp
    ja .Lfail
    lea r9, [r13+rbx]
    mov r10, r15
    shl r10, 4
    mov QWORD PTR [r13+r10], r9
    mov QWORD PTR [r13+r10+8], rcx
    mov rdx, rcx
    mov rsi, r8
    mov rdi, r9
    rep movsb
    add rbx, rdx
    inc r15
    jmp .Largument
.Lmain:
    sub rsp, 0x30
    mov QWORD PTR [rsp], r13
    mov QWORD PTR [rsp+8], rbp
    mov QWORD PTR [rsp+16], rbx
    mov QWORD PTR [rsp+24], r13
    mov QWORD PTR [rsp+32], r14
    xor ebp, ebp
    lea rdi, [rsp]
    lea rsi, [rsp+24]
    .byte 0xe8
    .long 0
    test eax, eax
    setne dil
    movzx edi, dil
    mov eax, 231
    syscall
.Lfail:
    mov edi, 111
    mov eax, 231
    syscall
    ud2
