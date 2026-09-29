# Builds the synthetic dumps for tests/selfhost/fixtures/link/debug_dump byte for byte
# and writes them, with the values the fixture checks, to src/vectors.e:
#   python vectors.py
# An ELF64 x86-64 core (NT_PRSTATUS x2, NT_PRPSINFO, NT_SIGINFO, NT_FILE, a LINUX note
# to skip, PT_LOADs including a contiguous pair and an empty one) and a Windows
# minidump (thread list, module list with UTF-16 names, memory list, memory64 list,
# exception, system info, misc info, an unused stream to skip). Every dumped memory
# byte is `pattern(address)`, so a read is checked against the address it came from.
import os
import struct


def pattern(address):
    return (address * 31 + 7) & 255


def memory(address, size):
    return bytes(pattern(address + i) for i in range(size))


# Canonical register order: rax rbx rcx rdx rsi rdi rbp rsp r8..r15 rip flags.
def registers(thread, rip, rsp, rbp, flags):
    r = [0xA000000000000000 + thread * 0x100 + i for i in range(18)]
    r[16], r[7], r[6], r[17] = rip, rsp, rbp, flags
    return r


# ---- ELF core ----------------------------------------------------------------
CORE_THREADS = [(4242, 11, registers(0, 0x401234, 0x7FFD0010, 0x7FFD0030, 0x246)),
                (4243, 0, registers(1, 0x401800, 0x7FFD0020, 0x7FFD0038, 0x202))]
CORE_LOADS = [(0x400000, 0x20, 0x1000), (0x400020, 0x10, 0x10), (0x7FFD0000, 0x40, 0x40), (0x500000, 0, 0x1000)]
CORE_FILES = [(0x400000, 0x401000, 0, b"/usr/bin/crasher"), (0x7F0000000000, 0x7F0000002000, 2, b"/usr/lib/libc.so.6")]


def note(name, kind, desc):
    n = name + b"\0"
    pad = lambda b: b + b"\0" * (-len(b) % 4)
    return struct.pack("<III", len(n), len(desc), kind) + pad(n) + pad(desc)


def prstatus(tid, sig, r):
    # user_regs_struct: r15 r14 r13 r12 rbp rbx r11 r10 r9 r8 rax rcx rdx rsi rdi orig_rax rip cs eflags rsp ss fs_base gs_base ds es fs gs
    rax, rbx, rcx, rdx, rsi, rdi, rbp, rsp = r[0:8]
    r8, r9, r10, r11, r12, r13, r14, r15 = r[8:16]
    rip, flags = r[16], r[17]
    regs = [r15, r14, r13, r12, rbp, rbx, r11, r10, r9, r8, rax, rcx, rdx, rsi, rdi, 0xFFFFFFFFFFFFFFFF, rip, 0x33, flags, rsp, 0x2B, 0, 0, 0, 0, 0, 0]
    head = struct.pack("<iiih2xQQiiii", sig, 0, 0, sig, 0, 0, tid, 1, tid, tid) + bytes(64)
    assert len(head) == 112
    body = head + struct.pack("<27Q", *regs) + struct.pack("<i4x", 1)
    assert len(body) == 336
    return body


def prpsinfo(pid, name):
    body = struct.pack("<bbbbxxxxQIIiiii", 0, ord("R"), 0, 0, 0, 1000, 1000, pid, 1, pid, pid)
    body += name.ljust(16, b"\0") + b"./crasher --now".ljust(80, b"\0")
    assert len(body) == 136
    return body


def siginfo(signo, code, addr):
    return (struct.pack("<iiixxxxQ", signo, 0, code, addr) + bytes(128))[:128]


def nt_file(files, page):
    body = struct.pack("<QQ", len(files), page)
    for start, end, ofs, _ in files:
        body += struct.pack("<QQQ", start, end, ofs)
    for *_, name in files:
        body += name + b"\0"
    return body


notes = b""
for tid, sig, r in CORE_THREADS:
    notes += note(b"CORE", 1, prstatus(tid, sig, r))
notes += note(b"CORE", 3, prpsinfo(4242, b"crasher"))
notes += note(b"CORE", 0x53494749, siginfo(11, 1, 0xDEADBEEF))
notes += note(b"CORE", 0x46494C45, nt_file(CORE_FILES, 4096))
notes += note(b"LINUX", 0x202, bytes(24))

PH_OFF, PH_SIZE = 64, 56
phnum = 1 + len(CORE_LOADS)
data_at = PH_OFF + PH_SIZE * phnum
phdrs = struct.pack("<IIQQQQQQ", 4, 4, data_at, 0, 0, len(notes), 0, 4)
cursor = data_at + len(notes)
blobs = notes
for vaddr, filesz, memsz in CORE_LOADS:
    phdrs += struct.pack("<IIQQQQQQ", 1, 6, cursor, vaddr, 0, filesz, memsz, 4096)
    blobs += memory(vaddr, filesz)
    cursor += filesz
ehdr = b"\x7fELF" + bytes([2, 1, 1, 0]) + bytes(8)
ehdr += struct.pack("<HHIQQQIHHHHHH", 4, 62, 1, 0, PH_OFF, 0, 0, 64, PH_SIZE, phnum, 0, 0, 0)
assert len(ehdr) == 64
core = ehdr + phdrs + blobs

# ---- Minidump ----------------------------------------------------------------
MD_THREADS = [(7001, registers(2, 0x140001234, 0x10010, 0x10030, 0x10246)),
              (7002, registers(3, 0x140001800, 0x10020, 0x10038, 0x202))]
MD_EXCEPTION = (7001, 0xC0000005, 0x140001234, registers(4, 0x140001234, 0x10008, 0x10030, 0x10246))
MD_MODULES = [(0x140000000, 0x5000, "C:\\Apps\\crash\u00e9\u4e2d.exe"), (0x7FFA00000000, 0x1F0000, "C:\\Windows\\System32\\ntdll.dll")]
MD_MEMORY = [(0x10000, 0x40)]
MD_MEMORY64 = [(0x20000, 0x10), (0x20010, 0x10), (0x30000, 0x08)]
MD_PID = 5150
MD_SYSTEM = (9, 8, 10, 0, 26200)


def context(r):
    c = bytearray(1232)
    struct.pack_into("<I", c, 0x30, 0x10000F)
    struct.pack_into("<I", c, 0x44, r[17])
    order = [r[0], r[2], r[3], r[1], r[7], r[6], r[4], r[5]] + r[8:16] + [r[16]]  # rax rcx rdx rbx rsp rbp rsi rdi r8..r15 rip
    struct.pack_into("<17Q", c, 0x78, *order)
    return bytes(c)


class Out:
    def __init__(self, size):
        self.b = bytearray(size)

    def add(self, data, align=8):
        while len(self.b) % align:
            self.b.append(0)
        at = len(self.b)
        self.b += data
        return at


streams = 8
out = Out(32 + 12 * streams)
thread_ctx = [out.add(context(r)) for _, r in MD_THREADS]
exc_ctx = out.add(context(MD_EXCEPTION[3]))
mem_rva = [out.add(memory(a, n)) for a, n in MD_MEMORY]
thread_list = struct.pack("<I", len(MD_THREADS))
for i, (tid, r) in enumerate(MD_THREADS):
    thread_list += struct.pack("<IIIIQQIIII", tid, 0, 32, 8, 0x7FF0000 + i * 0x1000, MD_MEMORY[0][0], MD_MEMORY[0][1], mem_rva[0], 1232, thread_ctx[i])
name_rva = [out.add(struct.pack("<I", len(n.encode("utf-16-le"))) + n.encode("utf-16-le") + b"\0\0", 4) for _, _, n in MD_MODULES]
module_list = struct.pack("<I", len(MD_MODULES))
for (base, size, _), rva in zip(MD_MODULES, name_rva):
    m = struct.pack("<QIIII", base, size, 0, 0x5F000000, rva) + bytes(52) + bytes(16) + bytes(16)
    assert len(m) == 108
    module_list += m
memory_list = struct.pack("<I", len(MD_MEMORY)) + b"".join(struct.pack("<QII", a, n, r) for (a, n), r in zip(MD_MEMORY, mem_rva))
exception = struct.pack("<IIIIQQII", MD_EXCEPTION[0], 0, MD_EXCEPTION[1], 0, 0, MD_EXCEPTION[2], 2, 0)
exception += struct.pack("<15Q", 1, 0xDEADBEEF, *([0] * 13)) + struct.pack("<II", 1232, exc_ctx)
assert len(exception) == 168
system = struct.pack("<HHHBBIIIII", MD_SYSTEM[0], 6, 0x5507, MD_SYSTEM[1], 1, MD_SYSTEM[2], MD_SYSTEM[3], MD_SYSTEM[4], 2, 0) + bytes(28)
assert len(system) == 56
misc = struct.pack("<IIIIII", 24, 1, MD_PID, 0, 0, 0)
entries = [(3, out.add(thread_list, 4), len(thread_list)),
           (4, out.add(module_list, 4), len(module_list)),
           (5, out.add(memory_list, 4), len(memory_list)),
           (6, out.add(exception), len(exception)),
           (7, out.add(system, 4), len(system)),
           (15, out.add(misc, 4), len(misc)),
           (0, 0, 0)]
m64_data = b"".join(memory(a, n) for a, n in MD_MEMORY64)
m64_head_len = 16 + 16 * len(MD_MEMORY64)
m64_at = out.add(bytes(m64_head_len))
m64_base = out.add(m64_data)
m64 = struct.pack("<QQ", len(MD_MEMORY64), m64_base) + b"".join(struct.pack("<QQ", a, n) for a, n in MD_MEMORY64)
out.b[m64_at:m64_at + m64_head_len] = m64
entries.append((9, m64_at, m64_head_len))
assert len(entries) == streams
struct.pack_into("<IIIIIIQ", out.b, 0, 0x504D444D, 0xA793, streams, 32, 0, 0x66000000, 0)
for i, (kind, rva, size) in enumerate(entries):
    struct.pack_into("<III", out.b, 32 + 12 * i, kind, size, rva)
minidump = bytes(out.b)


# ---- src/vectors.e -------------------------------------------------------------
def literal(b):
    return "".join("\\x%02x" % c for c in b)


def u64s(xs):
    return ", ".join("%du64" % x for x in xs)


regs = [r for _, _, r in CORE_THREADS] + [r for _, r in MD_THREADS] + [MD_EXCEPTION[3]]
lines = [
    "// Generated by ../vectors.py -- do not edit. The synthetic dumps and the values",
    "// the fixture checks them against.",
    "fn core_bytes() -> str { ret \"%s\" }" % literal(core),
    "fn minidump_bytes() -> str { ret \"%s\" }" % literal(minidump),
    "// Rows of 18 registers in canonical order: core thread 0, 1; minidump thread 0, 1; exception.",
    "fn expected_registers() -> [90]u64 { ret [90]u64{ %s } }" % u64s(sum(regs, [])),
    "const PH_OFF: usize = %dusize" % PH_OFF,
    "const PH_SIZE: usize = %dusize" % PH_SIZE,
    "const CORE_PHNUM: usize = %dusize" % phnum,
    "const CORE_TID0: u64 = %du64" % CORE_THREADS[0][0],
    "const CORE_TID1: u64 = %du64" % CORE_THREADS[1][0],
    "const CORE_SIGNAL: u32 = 11u32",
    "const CORE_SIGNAL_CODE: i32 = 1i32",
    "const CORE_FAULT: u64 = %du64" % 0xDEADBEEF,
    "const CORE_PID: u64 = 4242u64",
    "const CORE_FILE0_START: u64 = %du64" % CORE_FILES[0][0],
    "const CORE_FILE0_END: u64 = %du64" % CORE_FILES[0][1],
    "const CORE_FILE1_START: u64 = %du64" % CORE_FILES[1][0],
    "const CORE_FILE1_END: u64 = %du64" % CORE_FILES[1][1],
    "const CORE_FILE1_OFFSET: u64 = %du64" % (CORE_FILES[1][2] * 4096),
    "const MD_DIR_RVA: usize = 32usize",
    "const MD_STREAMS: usize = %dusize" % streams,
    "const MD_PID: u64 = %du64" % MD_PID,
    "const MD_TID0: u64 = %du64" % MD_THREADS[0][0],
    "const MD_TID1: u64 = %du64" % MD_THREADS[1][0],
    "const MD_CODE: u32 = %du32" % MD_EXCEPTION[1],
    "const MD_FAULT: u64 = %du64" % MD_EXCEPTION[2],
    "const MD_MODULE0_BASE: u64 = %du64" % MD_MODULES[0][0],
    "const MD_MODULE0_SIZE: u64 = %du64" % MD_MODULES[0][1],
    "const MD_MODULE1_BASE: u64 = %du64" % MD_MODULES[1][0],
    "const MD_MODULE1_SIZE: u64 = %du64" % MD_MODULES[1][1],
    "fn md_module0_name() -> str { ret \"%s\" }" % literal(MD_MODULES[0][2].encode("utf-8")),
    "fn md_module1_name() -> str { ret \"%s\" }" % literal(MD_MODULES[1][2].encode("utf-8")),
    "const MD_PROCESSORS: u32 = %du32" % MD_SYSTEM[1],
    "const MD_OS_MAJOR: u32 = %du32" % MD_SYSTEM[2],
    "const MD_OS_MINOR: u32 = %du32" % MD_SYSTEM[3],
    "const MD_OS_BUILD: u32 = %du32" % MD_SYSTEM[4],
    "const MD_REGIONS: usize = %dusize" % (len(MD_MEMORY) + len(MD_MEMORY64)),
    "",
]
here = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(here, "src", "vectors.e"), "w", newline="\n") as f:
    f.write("\n".join(lines))
print("core", len(core), "minidump", len(minidump))
