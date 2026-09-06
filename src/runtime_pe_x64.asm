option casemap:none

EXTERN main:PROC
EXTERN __imp_CloseHandle:QWORD
EXTERN __imp_CreateFileW:QWORD
EXTERN __imp_ExitProcess:QWORD
EXTERN __imp_FindClose:QWORD
EXTERN __imp_FindFirstFileW:QWORD
EXTERN __imp_FindNextFileW:QWORD
EXTERN __imp_GetCommandLineW:QWORD
EXTERN __imp_GetLastError:QWORD
EXTERN __imp_GetStdHandle:QWORD
EXTERN __imp_GetSystemTimeAsFileTime:QWORD
EXTERN __imp_MultiByteToWideChar:QWORD
EXTERN __imp_QueryPerformanceCounter:QWORD
EXTERN __imp_QueryPerformanceFrequency:QWORD
EXTERN __imp_ReadFile:QWORD
EXTERN __imp_VirtualAlloc:QWORD
EXTERN __imp_WideCharToMultiByte:QWORD
EXTERN __imp_WriteFile:QWORD

.code

PUBLIC neper_entry
neper_entry PROC
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 96

    xor ecx, ecx
    mov edx, 20000000h
    mov r8d, 3000h
    mov r9d, 4
    call qword ptr [__imp_VirtualAlloc]
    test rax, rax
    jz entry_fail
    mov r12, rax

    lea r13, [rsp+48]
    mov [r13], r12
    mov qword ptr [r13+8], 20000000h
    mov qword ptr [r13+16], 1000h
    lea r14, [rsp+72]
    mov [r14], r12
    mov qword ptr [r14+8], 0
    xor r15d, r15d

    call qword ptr [__imp_GetCommandLineW]
    test rax, rax
    jz entry_fail
    mov rbx, rax

entry_skip_space:
    movzx eax, word ptr [rbx]
    cmp eax, 20h
    je entry_skip_one
    cmp eax, 9
    jne entry_arg_start
entry_skip_one:
    add rbx, 2
    jmp entry_skip_space

entry_arg_start:
    cmp word ptr [rbx], 0
    je entry_args_done
    cmp r15, 256
    jae entry_fail
    xor edi, edi
    cmp word ptr [rbx], 22h
    jne entry_plain_arg
    add rbx, 2
    mov rsi, rbx
entry_quoted_scan:
    movzx eax, word ptr [rbx]
    test eax, eax
    jz entry_fail
    cmp eax, 22h
    je entry_quoted_done
    add rbx, 2
    inc rdi
    jmp entry_quoted_scan
entry_quoted_done:
    add rbx, 2
    jmp entry_convert

entry_plain_arg:
    mov rsi, rbx
entry_plain_scan:
    movzx eax, word ptr [rbx]
    test eax, eax
    jz entry_convert
    cmp eax, 20h
    je entry_convert
    cmp eax, 9
    je entry_convert
    add rbx, 2
    inc rdi
    jmp entry_plain_scan

entry_convert:
    mov rcx, r13
    mov rdx, rsi
    mov r8, rdi
    call np_utf16_to_utf8
    test rax, rax
    jz entry_fail
    mov rcx, r15
    shl rcx, 4
    mov [r12+rcx], rax
    mov [r12+rcx+8], rdx
    inc r15
    jmp entry_skip_space

entry_args_done:
    mov [r14+8], r15
    mov rcx, r13
    mov rdx, r14
entry_main_call:
    call main
    test eax, eax
    setne cl
    movzx ecx, cl
    call qword ptr [__imp_ExitProcess]

entry_fail:
    mov ecx, 111
    call qword ptr [__imp_ExitProcess]
    int 3
neper_entry ENDP

np_error PROC
    mov eax, 06F777EBFh
    cmp ecx, 2
    je error_not_found
    cmp ecx, 3
    je error_not_found
    cmp ecx, 15
    je error_not_found
    cmp ecx, 5
    je error_denied
    cmp ecx, 32
    je error_denied
    cmp ecx, 80
    je error_exists
    cmp ecx, 183
    je error_exists
    cmp ecx, 995
    je error_interrupted
    cmp ecx, 8
    je error_oom
    cmp ecx, 14
    je error_oom
    cmp ecx, 1460
    je error_timeout
    cmp ecx, 258
    je error_timeout
    cmp ecx, 50
    je error_unsupported
    cmp ecx, 120
    je error_unsupported
    ret
error_not_found:
    mov eax, 07683E2CDh
    ret
error_denied:
    mov eax, 0B0CB971Dh
    ret
error_exists:
    mov eax, 0197F5566h
    ret
error_interrupted:
    mov eax, 0B66D7668h
    ret
error_oom:
    mov eax, 06979AADCh
    ret
error_timeout:
    mov eax, 052812F09h
    ret
error_unsupported:
    mov eax, 02F8BB651h
    ret
np_error ENDP

np_arena_alloc PROC
    test rcx, rcx
    jz arena_fail
    test r8, r8
    jz arena_fail
    lea r9, [r8-1]
    test r8, r9
    jnz arena_fail
    mov rax, [rcx+16]
    mov r10, rax
    add r10, r9
    jc arena_fail
    neg r8
    and r10, r8
    mov r11, [rcx+8]
    cmp r10, r11
    ja arena_fail
    sub r11, r10
    cmp rdx, r11
    ja arena_fail
    lea r9, [r10+rdx]
    mov [rcx+16], r9
    mov rax, [rcx]
    test rax, rax
    jz arena_fail
    add rax, r10
    ret
arena_fail:
    xor eax, eax
    ret
np_arena_alloc ENDP

np_utf16_to_utf8 PROC
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov r12, rcx
    mov r13, rdx
    mov r14, r8
    test r14, r14
    jz utf16_empty
    mov rcx, 65001
    mov edx, 80h
    mov r8, r13
    mov r9, r14
    mov qword ptr [rsp+32], 0
    mov qword ptr [rsp+40], 0
    mov qword ptr [rsp+48], 0
    mov qword ptr [rsp+56], 0
    call qword ptr [__imp_WideCharToMultiByte]
    test eax, eax
    jle utf16_fail
    mov r15d, eax
    mov rcx, r12
    mov rdx, r15
    mov r8d, 1
    call np_arena_alloc
    test rax, rax
    jz utf16_fail
    mov r12, rax
    mov rcx, 65001
    mov edx, 80h
    mov r8, r13
    mov r9, r14
    mov [rsp+32], r12
    mov [rsp+40], r15
    mov qword ptr [rsp+48], 0
    mov qword ptr [rsp+56], 0
    call qword ptr [__imp_WideCharToMultiByte]
    cmp eax, r15d
    jne utf16_fail
    mov rax, r12
    mov rdx, r15
    jmp utf16_done
utf16_empty:
    mov rcx, r12
    xor edx, edx
    mov r8d, 1
    call np_arena_alloc
    mov rdx, 0
    jmp utf16_done
utf16_fail:
    xor eax, eax
    xor edx, edx
utf16_done:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    ret
np_utf16_to_utf8 ENDP

np_utf8_to_wide PROC
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56
    mov r12, rcx
    mov r13, rdx
    mov r15, r8
    mov rax, [r13+8]
    cmp rax, 7ffffffeH
    ja wide_fail
    lea rdx, [rax+1]
    add rdx, r15
    shl rdx, 1
    mov rcx, r12
    mov r8d, 2
    call np_arena_alloc
    test rax, rax
    jz wide_fail
    mov r14, rax
    mov r9, [r13+8]
    test r9, r9
    jz wide_empty
    mov rcx, 65001
    mov edx, 8
    mov r8, [r13]
    mov [rsp+32], r14
    mov rax, [r13+8]
    inc rax
    add rax, r15
    mov [rsp+40], rax
    call qword ptr [__imp_MultiByteToWideChar]
    test eax, eax
    jle wide_fail
    mov word ptr [r14+rax*2], 0
    mov rax, r14
    jmp wide_done
wide_empty:
    mov word ptr [r14], 0
    mov rax, r14
    jmp wide_done
wide_fail:
    xor eax, eax
wide_done:
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    ret
np_utf8_to_wide ENDP

PUBLIC neper_mem_alloc
neper_mem_alloc PROC
    mov r10, [rsp+40]
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov r12, rcx
    mov r13, rdx
    mov r14, r8
    mov r15, r9
    mov qword ptr [r12], 0
    mov qword ptr [r12+8], 0
    mov dword ptr [r12+16], 0
    mov rax, r14
    mul r15
    test rdx, rdx
    jnz mem_exhausted
    mov rdx, rax
    mov rcx, r13
    mov r8, r10
    call np_arena_alloc
    test rax, rax
    jz mem_exhausted
    mov [r12], rax
    mov [r12+8], r14
    jmp mem_done
mem_exhausted:
    mov dword ptr [r12+16], 08F63623Ah
mem_done:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    ret
neper_mem_alloc ENDP

PUBLIC neper_mem_mark
neper_mem_mark PROC
    mov rax, [rcx+16]
    ret
neper_mem_mark ENDP

PUBLIC neper_mem_reset
neper_mem_reset PROC
    mov [rcx+16], rdx
    ret
neper_mem_reset ENDP

PUBLIC neper_mem_stats
neper_mem_stats PROC
    mov rax, [rdx+16]
    mov [rcx], rax
    mov rax, [rdx+8]
    mov [rcx+8], rax
    ret
neper_mem_stats ENDP

PUBLIC neper_os_open
neper_os_open PROC
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64
    mov r12, rcx
    mov r13, rdx
    mov r14, r8
    mov r15, r9
    mov qword ptr [r12], 0
    mov dword ptr [r12+8], 0
    mov rbx, [r13+16]
    mov rcx, r13
    mov rdx, r14
    xor r8d, r8d
    call np_utf8_to_wide
    test rax, rax
    jz open_oom
    mov r10, rax
    xor edx, edx
    cmp byte ptr [r15], 0
    je open_no_read
    or edx, 80000000h
open_no_read:
    cmp byte ptr [r15+1], 0
    je open_no_write
    cmp byte ptr [r15+4], 0
    je open_generic_write
    or edx, 4
    jmp open_no_write
open_generic_write:
    or edx, 40000000h
open_no_write:
    mov eax, 3
    cmp byte ptr [r15+2], 0
    je open_no_create
    mov eax, 4
    cmp byte ptr [r15+3], 0
    je open_disposition_done
    mov eax, 2
    jmp open_disposition_done
open_no_create:
    cmp byte ptr [r15+3], 0
    je open_disposition_done
    mov eax, 5
open_disposition_done:
    mov [rsp+32], rax
    mov qword ptr [rsp+40], 80h
    mov qword ptr [rsp+48], 0
    mov rcx, r10
    mov r8d, 7
    xor r9d, r9d
    call qword ptr [__imp_CreateFileW]
    mov [r13+16], rbx
    cmp rax, -1
    je open_failed
    mov [r12], rax
    jmp open_done
open_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    mov [r12+8], eax
    jmp open_done
open_oom:
    mov [r13+16], rbx
    mov dword ptr [r12+8], 06979AADCh
open_done:
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
neper_os_open ENDP

PUBLIC neper_os_read
neper_os_read PROC
    push rbx
    sub rsp, 48
    mov dword ptr [rsp+40], 0
    mov rcx, [rcx]
    mov r8, [rdx+8]
    cmp r8, 0ffffffffh
    jbe read_size_ready
    mov r8d, 0ffffffffh
read_size_ready:
    mov rdx, [rdx]
    lea r9, [rsp+40]
    mov qword ptr [rsp+32], 0
    call qword ptr [__imp_ReadFile]
    test eax, eax
    jz read_failed
    mov eax, [rsp+40]
    xor edx, edx
    jmp read_done
read_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    mov edx, eax
    xor eax, eax
read_done:
    add rsp, 48
    pop rbx
    ret
neper_os_read ENDP

PUBLIC neper_os_write
neper_os_write PROC
    push rbx
    sub rsp, 48
    mov dword ptr [rsp+40], 0
    mov rcx, [rcx]
    mov r8, [rdx+8]
    cmp r8, 0ffffffffh
    jbe write_size_ready
    mov r8d, 0ffffffffh
write_size_ready:
    mov rdx, [rdx]
    lea r9, [rsp+40]
    mov qword ptr [rsp+32], 0
    call qword ptr [__imp_WriteFile]
    test eax, eax
    jz write_failed
    mov eax, [rsp+40]
    xor edx, edx
    jmp write_done
write_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    mov edx, eax
    xor eax, eax
write_done:
    add rsp, 48
    pop rbx
    ret
neper_os_write ENDP

PUBLIC neper_os_close
neper_os_close PROC
    sub rsp, 40
    mov rcx, [rcx]
    call qword ptr [__imp_CloseHandle]
    test eax, eax
    jz close_failed
    xor eax, eax
    jmp close_done
close_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
close_done:
    add rsp, 40
    ret
neper_os_close ENDP

PUBLIC neper_os_stdout
neper_os_stdout PROC
    push rbx
    sub rsp, 32
    mov rbx, rcx
    mov ecx, -11
    call qword ptr [__imp_GetStdHandle]
    mov [rbx], rax
    add rsp, 32
    pop rbx
    ret
neper_os_stdout ENDP

PUBLIC neper_os_stderr
neper_os_stderr PROC
    push rbx
    sub rsp, 32
    mov rbx, rcx
    mov ecx, -12
    call qword ptr [__imp_GetStdHandle]
    mov [rbx], rax
    add rsp, 32
    pop rbx
    ret
neper_os_stderr ENDP

PUBLIC neper_os_exit
neper_os_exit PROC
    sub rsp, 40
    call qword ptr [__imp_ExitProcess]
    int 3
neper_os_exit ENDP

PUBLIC neper_os_readdir
neper_os_readdir PROC
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 672
    mov r12, rcx
    mov r13, rdx
    mov r14, r8
    mov r15, [r13+16]
    mov qword ptr [r12], 0
    mov qword ptr [r12+8], 0
    mov dword ptr [r12+16], 0

    mov rcx, r13
    mov rdx, r14
    mov r8d, 2
    call np_utf8_to_wide
    test rax, rax
    jz dir_oom
    mov rsi, rax
    xor rcx, rcx
dir_pattern_end:
    cmp word ptr [rsi+rcx*2], 0
    je dir_pattern_append
    inc rcx
    jmp dir_pattern_end
dir_pattern_append:
    mov word ptr [rsi+rcx*2], 5ch
    mov word ptr [rsi+rcx*2+2], 2ah
    mov word ptr [rsi+rcx*2+4], 0

    lea rdx, [rsp+64]
    mov rcx, rsi
    call qword ptr [__imp_FindFirstFileW]
    cmp rax, -1
    je dir_find_failed
    mov rbx, rax
    xor edi, edi
dir_count_item:
    lea rcx, [rsp+108]
    cmp word ptr [rcx], 2eh
    jne dir_count_real
    cmp word ptr [rcx+2], 0
    je dir_count_next
    cmp word ptr [rcx+2], 2eh
    jne dir_count_real
    cmp word ptr [rcx+4], 0
    je dir_count_next
dir_count_real:
    inc rdi
dir_count_next:
    mov rcx, rbx
    lea rdx, [rsp+64]
    call qword ptr [__imp_FindNextFileW]
    test eax, eax
    jnz dir_count_item
    call qword ptr [__imp_GetLastError]
    cmp eax, 18
    jne dir_iteration_failed
    mov rcx, rbx
    call qword ptr [__imp_FindClose]

    mov rax, rdi
    mov rdx, 24
    mul rdx
    test rdx, rdx
    jnz dir_oom
    mov rdx, rax
    mov rcx, r13
    mov r8d, 8
    call np_arena_alloc
    test rax, rax
    jz dir_oom
    mov r14, rax

    lea rdx, [rsp+64]
    mov rcx, rsi
    call qword ptr [__imp_FindFirstFileW]
    cmp rax, -1
    je dir_find_failed
    mov rbx, rax
    xor esi, esi
dir_fill_item:
    lea rdx, [rsp+108]
    cmp word ptr [rdx], 2eh
    jne dir_fill_real
    cmp word ptr [rdx+2], 0
    je dir_fill_next
    cmp word ptr [rdx+2], 2eh
    jne dir_fill_real
    cmp word ptr [rdx+4], 0
    je dir_fill_next
dir_fill_real:
    cmp rsi, rdi
    jae dir_bad_count
    xor r8, r8
dir_name_length:
    cmp word ptr [rdx+r8*2], 0
    je dir_name_convert
    inc r8
    jmp dir_name_length
dir_name_convert:
    mov rcx, r13
    call np_utf16_to_utf8
    test rax, rax
    jz dir_close_oom
    mov rcx, rsi
    imul rcx, 24
    add rcx, r14
    mov [rcx], rax
    mov [rcx+8], rdx
    mov eax, [rsp+64]
    mov byte ptr [rcx+16], 0
    test eax, 400h
    jz dir_not_symlink
    mov byte ptr [rcx+16], 2
    jmp dir_kind_done
dir_not_symlink:
    test eax, 10h
    jz dir_kind_done
    mov byte ptr [rcx+16], 1
dir_kind_done:
    inc rsi
dir_fill_next:
    mov rcx, rbx
    lea rdx, [rsp+64]
    call qword ptr [__imp_FindNextFileW]
    test eax, eax
    jnz dir_fill_item
    call qword ptr [__imp_GetLastError]
    cmp eax, 18
    jne dir_iteration_failed
    cmp rsi, rdi
    jne dir_bad_count
    mov rcx, rbx
    call qword ptr [__imp_FindClose]
    mov [r12], r14
    mov [r12+8], rdi
    jmp dir_done

dir_bad_count:
    mov eax, 06F777EBFh
    jmp dir_close_error_value
dir_iteration_failed:
    mov ecx, eax
    call np_error
dir_close_error_value:
    mov esi, eax
    mov rcx, rbx
    call qword ptr [__imp_FindClose]
    mov eax, esi
    jmp dir_error_value
dir_close_oom:
    mov eax, 06979AADCh
    jmp dir_close_error_value
dir_find_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    jmp dir_error_value
dir_oom:
    mov eax, 06979AADCh
dir_error_value:
    mov [r13+16], r15
    mov [r12+16], eax
dir_done:
    add rsp, 672
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
neper_os_readdir ENDP

PUBLIC neper_os_args
neper_os_args PROC
    mov qword ptr [rcx], r12
    mov qword ptr [rcx+8], r15
    mov dword ptr [rcx+16], 0
    ret
neper_os_args ENDP

PUBLIC neper_os_reserve
neper_os_reserve PROC
    sub rsp, 40
    mov rdx, rcx
    xor ecx, ecx
    mov r8d, 2000h
    mov r9d, 1
    call qword ptr [__imp_VirtualAlloc]
    test rax, rax
    jz reserve_failed
    xor edx, edx
    add rsp, 40
    ret
reserve_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    mov edx, eax
    xor eax, eax
    add rsp, 40
    ret
neper_os_reserve ENDP

PUBLIC neper_os_commit
neper_os_commit PROC
    sub rsp, 40
    mov r8d, 1000h
    mov r9d, 4
    call qword ptr [__imp_VirtualAlloc]
    test rax, rax
    jz commit_failed
    xor eax, eax
    add rsp, 40
    ret
commit_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    add rsp, 40
    ret
neper_os_commit ENDP

PUBLIC neper_os_clock
neper_os_clock PROC
    sub rsp, 56
    cmp ecx, 1
    ja clock_unsupported
    test ecx, ecx
    jnz clock_monotonic
    lea rcx, [rsp+40]
    call qword ptr [__imp_GetSystemTimeAsFileTime]
    mov rax, qword ptr [rsp+40]
    mov rcx, 116444736000000000
    sub rax, rcx
    imul rax, rax, 100
    xor edx, edx
    add rsp, 56
    ret
clock_monotonic:
    lea rcx, [rsp+32]
    call qword ptr [__imp_QueryPerformanceCounter]
    test eax, eax
    jz clock_failed
    lea rcx, [rsp+40]
    call qword ptr [__imp_QueryPerformanceFrequency]
    test eax, eax
    jz clock_failed
    mov rax, qword ptr [rsp+32]
    xor edx, edx
    div qword ptr [rsp+40]
    imul rax, rax, 1000000000
    mov r8, rax
    mov rax, rdx
    imul rax, rax, 1000000000
    xor edx, edx
    div qword ptr [rsp+40]
    add rax, r8
    xor edx, edx
    add rsp, 56
    ret
clock_unsupported:
    xor eax, eax
    mov edx, 02F8BB651h
    add rsp, 56
    ret
clock_failed:
    xor eax, eax
    mov edx, 06F777EBFh
    add rsp, 56
    ret
neper_os_clock ENDP

END
