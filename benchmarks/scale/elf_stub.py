# Reassembles the ELF startup stub in src/link_elf.e with 64-bit arena immediates (D330):
# link_elf.e's blob, patch offsets and call offset.
import struct, capstone

ARENA = 0x40000000
code = bytearray()
labels = {}
fix = []  # (pos, size, label)

def emit(b): code.extend(b)
def label(n): labels[n] = len(code)
def rel32(op, n):
    emit(op); fix.append((len(code), 4, n)); emit(b'\0\0\0\0')
def rel8(op, n):
    emit(op); fix.append((len(code), 1, n)); emit(b'\0')

arena_at = []
def movabs(reg_bytes):  # movabs REG, imm64 ; records the immediate's offset
    emit(reg_bytes); arena_at.append(len(code)); emit(struct.pack('<Q', ARENA))

emit(bytes.fromhex('4989e4'))            # mov r12, rsp
emit(bytes.fromhex('31ff'))              # xor edi, edi
movabs(bytes.fromhex('48be'))            # movabs rsi, ARENA
emit(bytes.fromhex('ba03000000'))        # mov edx, 3 (PROT_READ|PROT_WRITE)
emit(bytes.fromhex('41ba22400000'))      # mov r10d, 0x4022 (MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE)
emit(bytes.fromhex('49c7c0ffffffff'))    # mov r8, -1
emit(bytes.fromhex('4531c9'))            # xor r9d, r9d
emit(bytes.fromhex('b809000000'))        # mov eax, 9 (mmap)
emit(bytes.fromhex('0f05'))              # syscall
emit(bytes.fromhex('4885c0'))            # test rax, rax
rel32(bytes.fromhex('0f88'), 'fail')     # js fail
emit(bytes.fromhex('4989c5'))            # mov r13, rax
emit(bytes.fromhex('4d8b3424'))          # mov r14, [r12]  (argc)
emit(bytes.fromhex('4c89f3'))            # mov rbx, r14
emit(bytes.fromhex('48c1e304'))          # shl rbx, 4
movabs(bytes.fromhex('48b8'))            # movabs rax, ARENA
emit(bytes.fromhex('4839c3'))            # cmp rbx, rax
rel32(bytes.fromhex('0f87'), 'fail')     # ja fail
emit(bytes.fromhex('4531ff'))            # xor r15d, r15d
label('loop')
emit(bytes.fromhex('4d39f7'))            # cmp r15, r14
rel8(bytes.fromhex('73'), 'done')        # jae done
emit(bytes.fromhex('4f8b44fc08'))        # mov r8, [r12 + r15*8 + 8]
emit(bytes.fromhex('31c9'))              # xor ecx, ecx
label('scan')
emit(bytes.fromhex('41803c0800'))        # cmp byte [r8 + rcx], 0
rel8(bytes.fromhex('74'), 'scanned')     # je scanned
emit(bytes.fromhex('48ffc1'))            # inc rcx
rel8(bytes.fromhex('eb'), 'scan')        # jmp scan
label('scanned')
emit(bytes.fromhex('4889d8'))            # mov rax, rbx
emit(bytes.fromhex('4801c8'))            # add rax, rcx
rel32(bytes.fromhex('0f82'), 'fail')     # jb fail
movabs(bytes.fromhex('49bb'))            # movabs r11, ARENA
emit(bytes.fromhex('4c39d8'))            # cmp rax, r11
rel32(bytes.fromhex('0f87'), 'fail')     # ja fail
emit(bytes.fromhex('4d8d4c1d00'))        # lea r9, [r13 + rbx]
emit(bytes.fromhex('4d89fa'))            # mov r10, r15
emit(bytes.fromhex('49c1e204'))          # shl r10, 4
emit(bytes.fromhex('4f894c1500'))        # mov [r13 + r10], r9
emit(bytes.fromhex('4b894c1508'))        # mov [r13 + r10 + 8], rcx
emit(bytes.fromhex('4889ca'))            # mov rdx, rcx
emit(bytes.fromhex('4c89c6'))            # mov rsi, r8
emit(bytes.fromhex('4c89cf'))            # mov rdi, r9
emit(bytes.fromhex('f3a4'))              # rep movsb
emit(bytes.fromhex('4801d3'))            # add rbx, rdx
emit(bytes.fromhex('49ffc7'))            # inc r15
rel8(bytes.fromhex('eb'), 'loop')        # jmp loop
label('done')
emit(bytes.fromhex('4883ec30'))          # sub rsp, 0x30
emit(bytes.fromhex('4c892c24'))          # mov [rsp], r13
movabs(bytes.fromhex('48b8'))            # movabs rax, ARENA
emit(bytes.fromhex('4889442408'))        # mov [rsp+8], rax
emit(bytes.fromhex('48895c2410'))        # mov [rsp+0x10], rbx
emit(bytes.fromhex('4c896c2418'))        # mov [rsp+0x18], r13
emit(bytes.fromhex('4c89742420'))        # mov [rsp+0x20], r14
emit(bytes.fromhex('488d3c24'))          # lea rdi, [rsp]
emit(bytes.fromhex('488d742418'))        # lea rsi, [rsp+0x18]
call_at = len(code) + 1
emit(bytes.fromhex('e800000000'))        # call main
emit(bytes.fromhex('85c0'))              # test eax, eax
emit(bytes.fromhex('400f95c7'))          # setne dil
emit(bytes.fromhex('400fb6ff'))          # movzx edi, dil
emit(bytes.fromhex('b83c000000'))        # mov eax, 60
emit(bytes.fromhex('0f05'))              # syscall
label('fail')
emit(bytes.fromhex('bf6f000000'))        # mov edi, 111
emit(bytes.fromhex('b83c000000'))        # mov eax, 60
emit(bytes.fromhex('0f05'))              # syscall
emit(bytes.fromhex('0f0b'))              # ud2

for pos, size, name in fix:
    d = labels[name] - (pos + size)
    if size == 1:
        assert -128 <= d <= 127, (name, d)
        code[pos] = d & 0xff
    else:
        code[pos:pos + 4] = struct.pack('<i', d)
blob = bytes(code)
print('length', len(blob), 'arena immediates at', arena_at, 'call rel32 at', call_at)
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
for i in md.disasm(blob, 0):
    print(f'{i.address:3}: {i.bytes.hex():24} {i.mnemonic} {i.op_str}')

# rewrite link_elf.e
import re
p = r'D:\repos\neper-lex\src\link_elf.e'
t = open(p, encoding='utf-8').read()
parts = list(re.finditer(r'    (?:try |ret )append_blob\(output, "((?:\\x[0-9a-f]{2})+)"\)\n', t))
assert len(parts) == 3
esc = ''.join('\\x%02x' % b for b in blob)
third = len(esc) // 3
cut1 = esc.rfind('\\x', 0, len(esc) // 3 + 1)
cut2 = esc.rfind('\\x', 0, 2 * len(esc) // 3 + 1)
s1, s2, s3 = esc[:cut1], esc[cut1:cut2], esc[cut2:]
new = f'    try append_blob(output, "{s1}")\n    try append_blob(output, "{s2}")\n    ret append_blob(output, "{s3}")\n'
t = t[:parts[0].start()] + new + t[parts[2].end():]
old = '''// `--arena` (D225): the startup stub carries the root arena's size as four 32-bit
// immediates -- the mapping's length, two bounds and the arena's capacity -- at these
// offsets from its start; a size past what a signed 32-bit immediate holds is refused.
fn patch_arena(output: *emit_x64.Buffer, startup: usize, arena_bytes: usize) -> err {
    if arena_bytes == 0usize { ret ok }
    if arena_bytes >= 2147483648usize { ret InvalidExecutable }
    try emit_x64.patch_little_u32(output, startup + 6usize, arena_bytes)
    try emit_x64.patch_little_u32(output, startup + 64usize, arena_bytes)
    try emit_x64.patch_little_u32(output, startup + 111usize, arena_bytes)
    ret emit_x64.patch_little_u32(output, startup + 171usize, arena_bytes)
}
'''
new_patch = f'''// `--arena` (D225): the startup stub carries the root arena's size as four 64-bit
// immediates (D330; they were 32-bit, and so was the largest arena) -- the mapping's
// length, two bounds and the arena's capacity -- at these offsets from its start.
fn patch_arena(output: *emit_x64.Buffer, startup: usize, arena_bytes: usize) -> err {{
    if arena_bytes == 0usize {{ ret ok }}
    try patch_little_u64(output, startup + {arena_at[0]}usize, arena_bytes)
    try patch_little_u64(output, startup + {arena_at[1]}usize, arena_bytes)
    try patch_little_u64(output, startup + {arena_at[2]}usize, arena_bytes)
    ret patch_little_u64(output, startup + {arena_at[3]}usize, arena_bytes)
}}

fn patch_little_u64(output: *emit_x64.Buffer, at: usize, value: usize) -> err {{
    try emit_x64.patch_little_u32(output, at, value & 4294967295usize)
    ret emit_x64.patch_little_u32(output, at + 4usize, value >> 32usize)
}}
'''
assert t.count(old) == 1
t = t.replace(old, new_patch)
assert t.count('code_offset + 200usize') == 2
t = t.replace('code_offset + 200usize', f'code_offset + {call_at}usize')
open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('link_elf.e rewritten')
