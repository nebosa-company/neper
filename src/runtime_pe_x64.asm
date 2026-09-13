option casemap:none

EXTERN main:PROC
EXTERN __imp_CloseHandle:QWORD
EXTERN __imp_CreateFileW:QWORD
EXTERN __imp_CreateThread:QWORD
EXTERN __imp_CreateProcessW:QWORD
EXTERN __imp_ExitProcess:QWORD
EXTERN __imp_FindClose:QWORD
EXTERN __imp_FindFirstFileW:QWORD
EXTERN __imp_FindNextFileW:QWORD
EXTERN __imp_GetCommandLineW:QWORD
EXTERN __imp_GetLastError:QWORD
EXTERN __imp_GetModuleHandleW:QWORD
EXTERN __imp_GetProcAddress:QWORD
EXTERN __imp_GetExitCodeProcess:QWORD
EXTERN __imp_GetStdHandle:QWORD
EXTERN __imp_GetSystemTimeAsFileTime:QWORD
EXTERN __imp_MultiByteToWideChar:QWORD
EXTERN __imp_QueryPerformanceCounter:QWORD
EXTERN __imp_QueryPerformanceFrequency:QWORD
EXTERN __imp_SetHandleInformation:QWORD
EXTERN __imp_WaitForSingleObject:QWORD
EXTERN __imp_ReadFile:QWORD
EXTERN __imp_VirtualAlloc:QWORD
EXTERN __imp_WideCharToMultiByte:QWORD
EXTERN __imp_WriteFile:QWORD
EXTERN __imp_SetFilePointerEx:QWORD

; The root arena is reserved rather than committed, and grows a chunk at a time as it is
; allocated from. Committing it whole would charge the whole of it against the commit limit
; before `main` runs, for every process, however little it goes on to allocate.
NP_ARENA_BYTES EQU 20000000h
NP_ARENA_CHUNK EQU 100000h

.code

PUBLIC neper_entry

; Order matters: the linker places this runtime as a prefix, cut after the last procedure
; the program reaches (D150). The entry and its two callees come first, since every
; program runs them; then the procedures from the ones nearly every program needs to
; the ones few do, each helper directly before its first caller. A procedure may call
; only what precedes it here.

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
    mov edx, NP_ARENA_BYTES
    mov r8d, 2000h
    mov r9d, 4
    call qword ptr [__imp_VirtualAlloc]
    test rax, rax
    jz entry_fail
    mov r12, rax

    mov rcx, r12
    mov edx, NP_ARENA_CHUNK
    mov r8d, 1000h
    mov r9d, 4
    call qword ptr [__imp_VirtualAlloc]
    test rax, rax
    jz entry_fail

    lea r13, [rsp+48]
    mov [r13], r12
    mov qword ptr [r13+8], NP_ARENA_BYTES
    mov qword ptr [r13+16], 1000h
    lea r14, [rsp+72]
    mov [r14], r12
    mov qword ptr [r14+8], 0
    xor r15d, r15d

    call qword ptr [__imp_GetCommandLineW]
    test rax, rax
    jz entry_fail
    mov rbx, rax

    xor edi, edi
entry_command_length:
    cmp word ptr [rbx+rdi*2], 0
    je entry_command_scratch
    inc rdi
    jmp entry_command_length
entry_command_scratch:
    lea rdx, [rdi+1]
    shl rdx, 1
    mov rcx, r13
    mov r8d, 2
    call np_arena_alloc
    test rax, rax
    jz entry_fail
    mov [rsp+32], rax

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
    mov rsi, [rsp+32]
    xor edi, edi
    xor r11d, r11d
entry_decode_char:
    movzx eax, word ptr [rbx]
    test eax, eax
    jz entry_convert
    cmp eax, 5ch
    je entry_decode_slashes
    cmp eax, 22h
    je entry_decode_quote
    cmp eax, 20h
    je entry_decode_space
    cmp eax, 9
    je entry_decode_space
entry_decode_copy:
    mov [rsi+rdi*2], ax
    add rbx, 2
    inc rdi
    jmp entry_decode_char

entry_decode_space:
    test r11d, r11d
    jz entry_convert
    jmp entry_decode_copy

entry_decode_quote:
    xor r11d, 1
    add rbx, 2
    jmp entry_decode_char

entry_decode_slashes:
    xor r10d, r10d
entry_count_slashes:
    cmp word ptr [rbx], 5ch
    jne entry_after_slashes
    inc r10
    add rbx, 2
    jmp entry_count_slashes
entry_after_slashes:
    cmp word ptr [rbx], 22h
    jne entry_copy_all_slashes
    mov rdx, r10
    shr rdx, 1
entry_copy_half_slashes:
    test rdx, rdx
    jz entry_slash_quote
    mov word ptr [rsi+rdi*2], 5ch
    inc rdi
    dec rdx
    jmp entry_copy_half_slashes
entry_slash_quote:
    test r10b, 1
    jz entry_slash_delimiter
    mov word ptr [rsi+rdi*2], 22h
    inc rdi
    add rbx, 2
    jmp entry_decode_char
entry_slash_delimiter:
    xor r11d, 1
    add rbx, 2
    jmp entry_decode_char
entry_copy_all_slashes:
    test r10, r10
    jz entry_decode_char
    mov word ptr [rsi+rdi*2], 5ch
    inc rdi
    dec r10
    jmp entry_copy_all_slashes

entry_convert:
    mov word ptr [rsi+rdi*2], 0
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

; The reserved arena grows here, because this is the one place its offset moves. What was
; committed is whatever the old offset reached rounded up to a chunk, so no watermark has to
; be kept anywhere -- which matters, since the runtime is embedded as bare text with nowhere
; writable to keep one. A reset moves the offset back and the next growth re-commits pages
; that are already committed, which Windows allows and answers immediately.
    cmp qword ptr [rcx+8], NP_ARENA_BYTES
    jne arena_store
    mov rax, [rcx+16]
    add rax, NP_ARENA_CHUNK-1
    and rax, -NP_ARENA_CHUNK
    mov r11, r9
    add r11, NP_ARENA_CHUNK-1
    and r11, -NP_ARENA_CHUNK
    cmp r11, rax
    jbe arena_store
    push rcx
    push r9
    push r10
    push r11
    sub rsp, 40
    mov rdx, r11
    sub rdx, rax
    mov rcx, [rcx]
    add rcx, rax
    mov r8d, 1000h
    mov r9d, 4
    call qword ptr [__imp_VirtualAlloc]
    add rsp, 40
    pop r11
    pop r10
    pop r9
    pop rcx
    test rax, rax
    jz arena_fail
arena_store:
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

neper_mem_mark PROC
    mov rax, [rcx+16]
    ret
neper_mem_mark ENDP

neper_mem_reset PROC
    mov [rcx+16], rdx
    ret
neper_mem_reset ENDP

neper_mem_stats PROC
    mov rax, [rdx+16]
    mov [rcx], rax
    mov rax, [rdx+8]
    mov [rcx+8], rax
    ret
neper_mem_stats ENDP

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

neper_os_exit PROC
    sub rsp, 40
    call qword ptr [__imp_ExitProcess]
    int 3
neper_os_exit ENDP

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

; A failed check (spec section 11): the record text, then the two operands wherever the
; text holds a NUL, then a newline, all to stderr, and exit 134. The generated code
; jumps here with rcx = text, rdx = its length, r8 and r9 = the operands; nothing
; returns, so the stack is simply realigned and the callee-saved registers are not kept.
np_trap_write PROC
    sub rsp, 56
    mov rcx, rdi
    lea r9, [rsp+40]
    mov qword ptr [rsp+32], 0
    call qword ptr [__imp_WriteFile]
    add rsp, 56
    ret
np_trap_write ENDP

neper_trap PROC
    and rsp, -16
    sub rsp, 64
    mov rbx, rcx
    lea rsi, [rcx+rdx]
    mov r12, r8
    mov r13, r9
    xor r14d, r14d
    mov ecx, -12
    call qword ptr [__imp_GetStdHandle]
    mov rdi, rax
trap_segment:
    mov rdx, rbx
trap_scan:
    cmp rbx, rsi
    jae trap_scanned
    cmp byte ptr [rbx], 0
    je trap_scanned
    inc rbx
    jmp trap_scan
trap_scanned:
    mov r8, rbx
    sub r8, rdx
    call np_trap_write
    cmp rbx, rsi
    jae trap_end
    inc rbx
    mov rax, r12
    test r14d, r14d
    jz trap_digits
    mov rax, r13
trap_digits:
    inc r14d
    lea r9, [rsp+56]
    mov ecx, 10
trap_digit:
    xor edx, edx
    div rcx
    add dl, 48
    dec r9
    mov [r9], dl
    test rax, rax
    jnz trap_digit
    mov rdx, r9
    lea r8, [rsp+56]
    sub r8, r9
    call np_trap_write
    jmp trap_segment
trap_end:
    mov byte ptr [rsp+32], 10
    lea rdx, [rsp+32]
    mov r8d, 1
    call np_trap_write
    mov ecx, 134
    call qword ptr [__imp_ExitProcess]
    int 3
neper_trap ENDP

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
    ; ERROR_BROKEN_PIPE: the writer is gone, which is the end of the stream and not a
    ; failure. Without this a pipe read reports an error where the other platform reports
    ; zero bytes, so a caller reading to the end cannot be written once.
    cmp eax, 109
    je read_at_end
    mov ecx, eax
    call np_error
    mov edx, eax
    xor eax, eax
    jmp read_done
read_at_end:
    xor eax, eax
    xor edx, edx
read_done:
    add rsp, 48
    pop rbx
    ret
neper_os_read ENDP

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

neper_os_seek PROC
    push rbx
    sub rsp, 48
    mov qword ptr [rsp+40], 0
    movzx r9d, r8b
    cmp r9d, 2
    ja seek_failed
    mov rcx, [rcx]
    lea r8, [rsp+40]
    call qword ptr [__imp_SetFilePointerEx]
    test eax, eax
    jz seek_last_error
    mov rax, [rsp+40]
    xor edx, edx
    jmp seek_done
seek_last_error:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    mov edx, eax
    xor eax, eax
    jmp seek_done
seek_failed:
    mov ecx, 87
    call np_error
    mov edx, eax
    xor eax, eax
seek_done:
    add rsp, 48
    pop rbx
    ret
neper_os_seek ENDP

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

neper_os_args PROC
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48
    mov r13, rcx
    mov r14, rdx
    mov rbx, r12
    mov rax, [r14+16]
    mov [rsp+32], rax
    mov qword ptr [r13], 0
    mov qword ptr [r13+8], 0
    mov dword ptr [r13+16], 0
    mov rax, r15
    shl rax, 4
    jc args_oom
    mov rdx, rax
    mov rcx, r14
    mov r8d, 8
    call np_arena_alloc
    test rax, rax
    jz args_oom
    mov [r13], rax
    mov [r13+8], r15
    mov r12, rax
args_copy_loop:
    test r15, r15
    jz args_copied
    mov rdx, [rbx+8]
    mov rcx, r14
    mov r8d, 1
    call np_arena_alloc
    test rax, rax
    jz args_oom
    mov [r12], rax
    mov rcx, [rbx+8]
    mov [r12+8], rcx
    mov rdi, rax
    mov rsi, [rbx]
    rep movsb
    add rbx, 16
    add r12, 16
    dec r15
    jmp args_copy_loop
args_copied:
    jmp args_done
args_oom:
    mov rax, [rsp+32]
    mov [r14+16], rax
    mov qword ptr [r13], 0
    mov qword ptr [r13+8], 0
    mov dword ptr [r13+16], 06979AADCh
args_done:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
neper_os_args ENDP

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

neper_hash_bytes PROC
    mov r8, rcx
    mov r9, rdx
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r13, 11400714785074694791
    mov r14, 14029467366897019727
    xor ecx, ecx
    cmp r9, 32
    jb Lhash_small
    mov r10, r13
    add r10, r14
    mov r11, r14
    xor ebx, ebx
    xor r12d, r12d
    sub r12, r13
    mov rdx, r9
    sub rdx, 32
Lhash_block:
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
    jbe Lhash_block
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
    mov rax, 9650029242287828579
    add r15, rax
    mov rax, r11
    imul rax, r14
    rol rax, 31
    imul rax, r13
    xor r15, rax
    imul r15, r13
    mov rax, 9650029242287828579
    add r15, rax
    mov rax, rbx
    imul rax, r14
    rol rax, 31
    imul rax, r13
    xor r15, rax
    imul r15, r13
    mov rax, 9650029242287828579
    add r15, rax
    mov rax, r12
    imul rax, r14
    rol rax, 31
    imul rax, r13
    xor r15, rax
    imul r15, r13
    mov rax, 9650029242287828579
    add r15, rax
    jmp Lhash_sized
Lhash_small:
    mov r15, 2870177450012600261
Lhash_sized:
    add r15, r9
Lhash_tail8:
    mov rax, rcx
    add rax, 8
    cmp rax, r9
    ja Lhash_tail4
    mov rax, qword ptr [r8 + rcx]
    imul rax, r14
    rol rax, 31
    imul rax, r13
    xor r15, rax
    rol r15, 27
    imul r15, r13
    mov rax, 9650029242287828579
    add r15, rax
    add rcx, 8
    jmp Lhash_tail8
Lhash_tail4:
    mov rax, rcx
    add rax, 4
    cmp rax, r9
    ja Lhash_tail1
    mov eax, dword ptr [r8 + rcx]
    imul rax, r13
    xor r15, rax
    rol r15, 23
    imul r15, r14
    mov rax, 1609587929392839161
    add r15, rax
    add rcx, 4
Lhash_tail1:
    cmp rcx, r9
    jae Lhash_final
    movzx rax, byte ptr [r8 + rcx]
    mov rdx, 2870177450012600261
    imul rax, rdx
    xor r15, rax
    rol r15, 11
    imul r15, r13
    add rcx, 1
    jmp Lhash_tail1
Lhash_final:
    mov rax, r15
    shr rax, 33
    xor r15, rax
    imul r15, r14
    mov rax, r15
    shr rax, 29
    xor r15, rax
    mov rax, 1609587929392839161
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
neper_hash_bytes ENDP

neper_os_thread_create PROC
    ; (Thread, err) returns through the hidden slot in rcx, as os.open does.
    ; rdx = entry, r8 = ctx, r9 = stack.
    push rbx
    push rsi
    sub rsp, 56
    mov rbx, rcx
    mov rsi, rdx
    mov qword ptr [rsp+32], 0
    mov qword ptr [rsp+40], 0
    xor ecx, ecx
    mov rdx, r9
    mov r9, r8
    mov r8, rsi
    call qword ptr [__imp_CreateThread]
    test rax, rax
    jz thread_create_failed
    mov [rbx], rax
    mov dword ptr [rbx+8], 0
    jmp thread_create_done
thread_create_failed:
    mov qword ptr [rbx], 0
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    mov [rbx+8], eax
thread_create_done:
    add rsp, 56
    pop rsi
    pop rbx
    ret
neper_os_thread_create ENDP

neper_os_thread_join PROC
    push rbx
    sub rsp, 32
    mov rbx, [rcx]
    mov rcx, rbx
    mov edx, 0FFFFFFFFh
    call qword ptr [__imp_WaitForSingleObject]
    cmp eax, 0FFFFFFFFh
    je thread_join_failed
    mov rcx, rbx
    call qword ptr [__imp_CloseHandle]
    test eax, eax
    jz thread_join_failed
    xor eax, eax
    jmp thread_join_done
thread_join_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
thread_join_done:
    add rsp, 32
    pop rbx
    ret
neper_os_thread_join ENDP

neper_os_thread_detach PROC
    sub rsp, 40
    mov rcx, [rcx]
    call qword ptr [__imp_CloseHandle]
    test eax, eax
    jz thread_detach_failed
    xor eax, eax
    jmp thread_detach_done
thread_detach_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
thread_detach_done:
    add rsp, 40
    ret
neper_os_thread_detach ENDP

np_quoted_size PROC
    mov r8, [rcx]
    mov r9, [rcx+8]
    mov eax, 2
    xor r10d, r10d
    xor r11d, r11d
quoted_size_loop:
    cmp r10, r9
    jae quoted_size_tail
    movzx ecx, byte ptr [r8+r10]
    cmp ecx, 5ch
    jne quoted_size_not_slash
    inc r11
    inc rax
    jc quoted_size_overflow
    jmp quoted_size_next
quoted_size_not_slash:
    cmp ecx, 22h
    jne quoted_size_plain
    add rax, r11
    jc quoted_size_overflow
    add rax, 2
    jc quoted_size_overflow
    xor r11d, r11d
    jmp quoted_size_next
quoted_size_plain:
    add rax, 1
    jc quoted_size_overflow
    xor r11d, r11d
quoted_size_next:
    inc r10
    jmp quoted_size_loop
quoted_size_tail:
    add rax, r11
    jc quoted_size_overflow
    ret
quoted_size_overflow:
    xor eax, eax
    ret
np_quoted_size ENDP

np_quote PROC
    mov r8, [rdx]
    mov r9, [rdx+8]
    mov byte ptr [rcx], 22h
    inc rcx
    xor r10d, r10d
    xor r11d, r11d
quote_loop:
    cmp r10, r9
    jae quote_tail
    mov al, [r8+r10]
    cmp al, 5ch
    jne quote_not_slash
    mov [rcx], al
    inc rcx
    inc r11
    jmp quote_next
quote_not_slash:
    cmp al, 22h
    jne quote_plain
    mov rdx, r11
    inc rdx
quote_escape_quote:
    test rdx, rdx
    jz quote_write_quote
    mov byte ptr [rcx], 5ch
    inc rcx
    dec rdx
    jmp quote_escape_quote
quote_write_quote:
    mov byte ptr [rcx], 22h
    inc rcx
    xor r11d, r11d
    jmp quote_next
quote_plain:
    mov [rcx], al
    inc rcx
    xor r11d, r11d
quote_next:
    inc r10
    jmp quote_loop
quote_tail:
    test r11, r11
    jz quote_close
quote_escape_tail:
    mov byte ptr [rcx], 5ch
    inc rcx
    dec r11
    jnz quote_escape_tail
quote_close:
    mov byte ptr [rcx], 22h
    lea rax, [rcx+1]
    ret
np_quote ENDP

neper_os_spawn PROC
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 272
    mov r12, rcx
    mov r13, rdx
    mov rbx, r9
    mov r14, [r8]
    mov r15, [r8+8]
    mov qword ptr [r12], 0
    mov dword ptr [r12+8], 0
    test r15, r15
    je spawn_not_found
    mov [rsp+208], r13
    mov rax, [r13+16]
    mov [rsp+216], rax

    mov edi, 1
    xor esi, esi
spawn_size_arg:
    cmp rsi, r15
    jae spawn_allocate_command
    mov rcx, rsi
    shl rcx, 4
    add rcx, r14
    call np_quoted_size
    test rax, rax
    jz spawn_oom
    test rsi, rsi
    jz spawn_size_add
    inc rax
    jz spawn_oom
spawn_size_add:
    add rdi, rax
    jc spawn_oom
    inc rsi
    jmp spawn_size_arg

spawn_allocate_command:
    mov rdx, rdi
    mov rcx, r13
    mov r8d, 1
    call np_arena_alloc
    test rax, rax
    jz spawn_oom
    mov [rsp+224], rax
    mov rax, rdi
    dec rax
    mov [rsp+232], rax
    mov rdi, [rsp+224]
    xor esi, esi
spawn_quote_arg:
    cmp rsi, r15
    jae spawn_command_done
    test rsi, rsi
    jz spawn_quote_value
    mov byte ptr [rdi], 20h
    inc rdi
spawn_quote_value:
    mov rdx, rsi
    shl rdx, 4
    add rdx, r14
    mov rcx, rdi
    call np_quote
    mov rdi, rax
    inc rsi
    jmp spawn_quote_arg
spawn_command_done:
    mov byte ptr [rdi], 0
    mov rax, [rsp+224]
    mov [rsp+32], rax
    mov rax, [rsp+232]
    mov [rsp+40], rax
    mov rcx, r13
    lea rdx, [rsp+32]
    xor r8d, r8d
    call np_utf8_to_wide
    test rax, rax
    jz spawn_oom
    mov [rsp+240], rax
    xor eax, eax
    lea rdi, [rsp+80]
    mov ecx, 16
    rep stosq
    mov dword ptr [rsp+80], 104
    mov dword ptr [rsp+140], 100h
    mov rax, [rbx]
    mov [rsp+160], rax
    mov rax, [rbx+8]
    mov [rsp+168], rax
    mov rax, [rbx+16]
    mov [rsp+176], rax

    mov rcx, [rbx]
    test rcx, rcx
    jz spawn_set_stdout
    mov edx, 1
    mov r8d, 1
    call qword ptr [__imp_SetHandleInformation]
    test eax, eax
    jz spawn_inherit_failed
spawn_set_stdout:
    mov rcx, [rbx+8]
    test rcx, rcx
    jz spawn_set_stderr
    mov edx, 1
    mov r8d, 1
    call qword ptr [__imp_SetHandleInformation]
    test eax, eax
    jz spawn_inherit_failed
spawn_set_stderr:
    mov rcx, [rbx+16]
    test rcx, rcx
    jz spawn_set_extra_begin
    mov edx, 1
    mov r8d, 1
    call qword ptr [__imp_SetHandleInformation]
    test eax, eax
    jz spawn_inherit_failed

spawn_set_extra_begin:
    mov r14, [rbx+24]
    mov r15, [rbx+32]
    xor esi, esi
spawn_set_extra:
    cmp rsi, r15
    jae spawn_create
    mov rcx, [r14+rsi*8]
    mov edx, 1
    mov r8d, 1
    call qword ptr [__imp_SetHandleInformation]
    test eax, eax
    jz spawn_extra_inherit_failed
    inc rsi
    jmp spawn_set_extra

spawn_create:
    mov qword ptr [rsp+32], 1
    mov qword ptr [rsp+40], 0
    mov qword ptr [rsp+48], 0
    mov qword ptr [rsp+56], 0
    lea rax, [rsp+80]
    mov [rsp+64], rax
    lea rax, [rsp+184]
    mov [rsp+72], rax
    xor ecx, ecx
    mov rdx, [rsp+240]
    xor r8d, r8d
    xor r9d, r9d
    call qword ptr [__imp_CreateProcessW]
    test eax, eax
    jz spawn_create_failed
    mov dword ptr [rsp+264], 0
    jmp spawn_clear_extra
spawn_create_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    mov [rsp+264], eax

spawn_clear_extra:
    test rsi, rsi
    jz spawn_clear_stdio
    dec rsi
    mov rcx, [r14+rsi*8]
    mov edx, 1
    xor r8d, r8d
    call qword ptr [__imp_SetHandleInformation]
    jmp spawn_clear_extra

spawn_clear_stdio:
    mov rcx, [rbx]
    test rcx, rcx
    jz spawn_clear_stdout
    mov edx, 1
    xor r8d, r8d
    call qword ptr [__imp_SetHandleInformation]
spawn_clear_stdout:
    mov rcx, [rbx+8]
    test rcx, rcx
    jz spawn_clear_stderr
    mov edx, 1
    xor r8d, r8d
    call qword ptr [__imp_SetHandleInformation]
spawn_clear_stderr:
    mov rcx, [rbx+16]
    test rcx, rcx
    jz spawn_finish_create
    mov edx, 1
    xor r8d, r8d
    call qword ptr [__imp_SetHandleInformation]
spawn_finish_create:
    cmp dword ptr [rsp+264], 0
    jne spawn_load_error
    mov rcx, [rsp+192]
    call qword ptr [__imp_CloseHandle]
    mov rax, [rsp+184]
    mov [r12], rax
    jmp spawn_restore
spawn_extra_inherit_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    mov [rsp+264], eax
    jmp spawn_clear_extra
spawn_inherit_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    mov [rsp+264], eax
    xor esi, esi
    jmp spawn_clear_stdio
spawn_load_error:
    mov eax, [rsp+264]
spawn_store_error:
    mov [r12+8], eax
    jmp spawn_restore
spawn_not_found:
    mov dword ptr [r12+8], 07683E2CDh
    jmp spawn_done
spawn_oom:
    mov dword ptr [r12+8], 06979AADCh
spawn_restore:
    mov rcx, [rsp+208]
    mov rax, [rsp+216]
    mov [rcx+16], rax
spawn_done:
    add rsp, 272
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
neper_os_spawn ENDP

neper_os_wait PROC
    push rbx
    sub rsp, 48
    mov rbx, [rcx]
    mov rcx, rbx
    mov edx, 0FFFFFFFFh
    call qword ptr [__imp_WaitForSingleObject]
    test eax, eax
    jnz wait_failed
    mov rcx, rbx
    lea rdx, [rsp+32]
    call qword ptr [__imp_GetExitCodeProcess]
    test eax, eax
    jz wait_failed
    mov rcx, rbx
    call qword ptr [__imp_CloseHandle]
    mov eax, [rsp+32]
    xor edx, edx
    add rsp, 48
    pop rbx
    ret
wait_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    mov edx, eax
    mov eax, -1
    add rsp, 48
    pop rbx
    ret
neper_os_wait ENDP

; Section 8's blocking primitives. `WaitOnAddress` and the two wakes are not in
; kernel32, and this linker emits one import descriptor for one DLL, so they are
; resolved through `GetModuleHandleW` on KernelBase -- which exports all three and is
; loaded in every process, so this takes no reference and frees nothing. The lookup
; happens only on the blocking path, where a handle-table probe costs nothing against
; the wait it is about to do, and `.text` is read-only so there is nowhere to cache it.
np_resolve_synch PROC
    ; rcx = the procedure name. Returns the address in rax, or zero.
    push rbx
    sub rsp, 32
    mov rbx, rcx
    lea rcx, np_kernelbase_name
    call qword ptr [__imp_GetModuleHandleW]
    test rax, rax
    jz resolve_synch_done
    mov rcx, rax
    mov rdx, rbx
    call qword ptr [__imp_GetProcAddress]
resolve_synch_done:
    add rsp, 32
    pop rbx
    ret
np_resolve_synch ENDP

; Read-only bytes beside the code they belong to. `.text` is not writable, which is
; exactly why none of the three addresses above is cached.
np_kernelbase_name:
    DW 04Bh, 065h, 072h, 06Eh, 065h, 06Ch, 042h, 061h, 073h, 065h, 02Eh, 064h, 06Ch, 06Ch, 0000h
np_wait_on_address_name:
    DB "WaitOnAddress", 0
np_wake_single_name:
    DB "WakeByAddressSingle", 0
np_wake_all_name:
    DB "WakeByAddressAll", 0

neper_os_wait_u32 PROC
    ; rcx = p, rdx = expected, r8 = timeout_ns. Returns err in eax.
    push rbx
    push rsi
    push rdi
    sub rsp, 48
    mov rbx, rcx
    mov rdi, r8
    ; WaitOnAddress compares against a value in memory, so the expected one needs an
    ; address of its own.
    mov dword ptr [rsp+40], edx
    lea rcx, np_wait_on_address_name
    call np_resolve_synch
    test rax, rax
    jz wait_u32_unsupported
    mov rsi, rax
    ; A negative timeout is INFINITE and zero polls once; anything between rounds up,
    ; so a sub-millisecond wait still waits rather than turning into a poll.
    mov r9d, 0FFFFFFFFh
    test rdi, rdi
    js wait_u32_call
    xor r9d, r9d
    test rdi, rdi
    jz wait_u32_call
    mov rax, rdi
    add rax, 999999
    mov rcx, 1000000
    xor edx, edx
    div rcx
    cmp rax, 0FFFFFFFEh
    jbe wait_u32_millis
    mov eax, 0FFFFFFFEh
wait_u32_millis:
    mov r9d, eax
wait_u32_call:
    mov rcx, rbx
    lea rdx, [rsp+40]
    mov r8d, 4
    call rsi
    test eax, eax
    jz wait_u32_failed
    xor eax, eax
    jmp wait_u32_done
wait_u32_failed:
    call qword ptr [__imp_GetLastError]
    mov ecx, eax
    call np_error
    jmp wait_u32_done
wait_u32_unsupported:
    mov eax, 02F8BB651h
wait_u32_done:
    add rsp, 48
    pop rdi
    pop rsi
    pop rbx
    ret
neper_os_wait_u32 ENDP

neper_os_wake_one_u32 PROC
    push rbx
    sub rsp, 32
    mov rbx, rcx
    lea rcx, np_wake_single_name
    call np_resolve_synch
    test rax, rax
    jz wake_one_done
    mov rcx, rbx
    call rax
wake_one_done:
    add rsp, 32
    pop rbx
    ret
neper_os_wake_one_u32 ENDP

neper_os_wake_all_u32 PROC
    push rbx
    sub rsp, 32
    mov rbx, rcx
    lea rcx, np_wake_all_name
    call np_resolve_synch
    test rax, rax
    jz wake_all_done
    mov rcx, rbx
    call rax
wake_all_done:
    add rsp, 32
    pop rbx
    ret
neper_os_wake_all_u32 ENDP

END
