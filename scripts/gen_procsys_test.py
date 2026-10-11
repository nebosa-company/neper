"""Vectors of tests/selfhost/fixtures/link/proc_sys/src/main.e (L102): canned /proc files run
through e.proc.sys.format against an independent regex-based reader, plus a few real files
captured from WSL2 Ubuntu. The live host half is checked by shape in the fixture itself and
against psutil by scripts/check_procsys_live.py.

    python scripts/gen_procsys_test.py
"""
import os, random, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "proc_sys", "src", "main.e")


def hx(s):
    return s.encode("utf-8").hex()


# ---- the independent reader (regex, not the fixture's scanner) ----
def exp_meminfo(src):
    def kb(key):
        m = re.search(r"^%s:\s+(\d+) kB" % key, src, re.M)
        return int(m.group(1)) * 1024 if m else None
    total = kb("MemTotal")
    if total is None:
        return None
    avail = kb("MemAvailable")
    if avail is None:
        avail = sum(kb(k) or 0 for k in ("MemFree", "Buffers", "Cached"))
    return total, avail, kb("SwapTotal") or 0, kb("SwapFree") or 0


def exp_cpu(src, hz=100):
    m = re.search(r"^cpu +([\d ]+)$", src, re.M)
    if not m:
        return None
    f = [int(x) for x in m.group(1).split()]
    if len(f) < 4:
        return None
    f += [0] * (8 - len(f))
    k = 1000 // hz
    cpus = len(re.findall(r"^cpu\d+", src, re.M))
    return (f[0] + f[1]) * k, (f[2] + f[5] + f[6]) * k, f[3] * k, f[4] * k, cpus


def exp_uptime(src):
    m = re.match(r"\s*(\d+)(?:\.(\d+))?", src)
    if not m:
        return None
    frac = (m.group(2) or "")[:3].ljust(3, "0")[:3]
    # the scanner reads at most three decimals: .5 = 500, .56 = 560, .567 = 567
    return int(m.group(1)) * 1000 + int(frac[:3])


def exp_stat(src):
    m = re.match(r"\s*(\d+) \((.*)\) (\S) (-?\d+) ", src, re.S)
    if not m:
        return None
    rest = src[m.end():].split()
    if len(rest) < 16:
        return None
    return int(m.group(1)), int(m.group(4)), int(rest[15]), m.group(3), m.group(2)


# ---- generators ----
def gen_meminfo(rnd):
    keys = ["MemTotal", "MemFree", "MemAvailable", "Buffers", "Cached", "SwapTotal", "SwapFree", "Dirty", "Active(anon)"]
    rnd.shuffle(keys)
    drop = rnd.random()
    lines = []
    for k in keys:
        if k == "MemAvailable" and drop < 0.3:
            continue
        if k == "MemTotal" and drop > 0.93:
            continue
        lines.append("%s:%s%d kB" % (k, " " * rnd.randint(1, 9), rnd.randint(0, 40_000_000)))
    return "\n".join(lines) + "\n"


def gen_stat(rnd):
    n = rnd.randint(1, 5)
    agg = [rnd.randint(0, 10 ** rnd.randint(2, 7)) for _ in range(rnd.choice([4, 7, 8, 10]))]
    out = ["cpu  " + " ".join(map(str, agg))]
    for i in range(n):
        out.append("cpu%d " % i + " ".join(str(rnd.randint(0, 99999)) for _ in range(10)))
    out += ["intr 12345 1 2 3", "ctxt 99", "btime 1700000000", "processes 4242"]
    return "\n".join(out) + "\n"


def gen_stat_pid(rnd):
    names = ["bash", "node", "a b", "x (y) z", "(", ")", "kworker/0:1-events", "a)b", "sd-pam", "z"]
    name = rnd.choice(names)
    pid = rnd.randint(1, 4000000)
    ppid = rnd.randint(0, 4000000)
    # fields 3..: state ppid, fields 5..17 (13 numbers), priority nice num_threads, then more
    fields = [rnd.choice("RSDZTI"), ppid] + [rnd.randint(0, 9999) for _ in range(13)]
    fields += [rnd.choice([20, 0, 39, -100]), rnd.choice([0, -20, 19, 5]), rnd.randint(1, 600)]
    fields += [rnd.randint(0, 99999) for _ in range(15)]
    return "%d (%s) %s" % (pid, name, " ".join(map(str, fields))) + chr(10)


def gen_uptime(rnd):
    return rnd.choice(["%d.%02d %d.%02d\n" % (rnd.randint(0, 9999999), rnd.randint(0, 99), rnd.randint(0, 99999999), rnd.randint(0, 99)),
                       "%d\n" % rnd.randint(0, 5000), "%d.5 1.0\n" % rnd.randint(0, 5000), "", "abc\n", "  17.25 3.50\n"])


REAL_MEM = """MemTotal:        5036628 kB
MemFree:         2878084 kB
MemAvailable:    4432428 kB
Buffers:           73700 kB
Cached:          1597540 kB
SwapCached:            0 kB
Active:           143944 kB
Inactive:        1627516 kB
SwapTotal:       8388608 kB
SwapFree:        8388608 kB
Dirty:             14424 kB
"""
REAL_STAT = "cpu  652 286 675 34927 915 0 178 0 0 0\ncpu0 53 0 60 2177 41 0 80 0 0 0\ncpu1 23 0 30 2231 45 0 41 0 0 0\nintr 4\n"
REAL_PID = "761 (cat) R 757 757 757 34816 757 4194304 78 0 0 0 0 0 0 0 20 0 1 0 2356 3358720 416 18446744073709551615 96120780976128 96120780993713 140722389041952 0 0 0 0 0 0 0 0 0 17 1 0 0 0 0 0 96120781007504 96120781009000 96121050370048 140722389046534 140722389046554 140722389046554 140722389049323 0\n"


def main():
    rnd = random.Random(102)
    rows = []

    def add(kind, src, exp):
        if exp is None:
            rows.append("%s %s ERR;" % (kind, hx(src) or "-"))
        else:
            rows.append("%s %s %s;" % (kind, hx(src) or "-", " ".join(hx(x) if isinstance(x, str) else str(x) for x in exp)))

    for src in [REAL_MEM] + [gen_meminfo(rnd) for _ in range(60)] + ["", "garbage"]:
        add("m", src, exp_meminfo(src))
    for src in [REAL_STAT] + [gen_stat(rnd) for _ in range(60)] + ["cpu 1 2\n", "nothing"]:
        add("c", src, exp_cpu(src))
    for src in [gen_uptime(rnd) for _ in range(50)] + ["23.56 349.29\n"]:
        v = exp_uptime(src)
        add("u", src, None if v is None else (v,))
    for src in [REAL_PID] + [gen_stat_pid(rnd) for _ in range(80)] + ["", "12 (x", "x (y) R 1"]:
        e = exp_stat(src)
        add("s", src, None if e is None else (e[0], e[1], e[2], ord(e[3]), e[4] if e[4] else "-"))
    chunks, calls = [], []
    per = 60
    for k in range(0, len(rows), per):
        chunks.append('fn vectors_%d() -> str {\n    ret "%s"\n}\n' % (k // per, "".join(rows[k:k + per])))
        calls.append("    if run_chunk(a, vectors_%d()) != 0u32 { os.exit(%di32) }" % (k // per, k // per + 1))
    tpl = open(os.path.join(ROOT, "scripts", "procsys_fixture_template.e"), encoding="utf-8").read()
    src = tpl.replace("@CHUNKS@", "\n".join(chunks)).replace("@CALLS@", "\n".join(calls))
    os.makedirs(os.path.dirname(FIX), exist_ok=True)
    open(FIX, "w", encoding="utf-8", newline="\n").write(src)
    print("vectors:", len(rows))


main()
