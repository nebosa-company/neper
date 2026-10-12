"""Makes tests/selfhost/fixtures/link/cli_complete/src/main.e (L134) from scripts/complete_fixture_template.e.

1. The template is compiled with empty goldens and run with an argument, which prints every
   generated script and man page between markers.
2. Those outputs are held to real behaviour -- bash and fish are asked for completions of
   many partial command lines and compared with an independent Python model of the command
   spec; zsh is syntax-checked with `zsh -n`; the man pages are rendered by groff with all
   warnings on and every option and subcommand is looked for in the rendered text.
3. Only if all of that passes are the outputs written into the fixture as goldens.

Needs WSL with bash, zsh, fish and groff.

    python scripts/gen_complete_test.py <path to neper-self.exe>
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, "scripts", "complete_fixture_template.e")
FIX = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "cli_complete", "src", "main.e")
NAMES = ["SOLO_BASH", "SOLO_ZSH", "SOLO_FISH", "SOLO_MAN", "TOOL_BASH", "TOOL_ZSH", "TOOL_FISH", "TOOL_MAN", "BUILD_MAN"]
FILES = ["SOLO_BASH:solo.bash", "SOLO_ZSH:solo.zsh", "SOLO_FISH:solo.fish", "SOLO_MAN:solo.1", "TOOL_BASH:tool.bash",
         "TOOL_ZSH:tool.zsh", "TOOL_FISH:tool.fish", "TOOL_MAN:tool.1", "BUILD_MAN:tool-build.1"]

# The specs, as the template builds them.
SOLO = {"name": "solo", "options": [("out", "o", True, "Where to write"), ("quiet", None, False, "")], "subs": []}
TOOL = {"name": "tool", "options": [("verbose", "v", False, "Chatty output"), ("config", "c", True, "Config file"), ("count", None, True, "How many")],
        "subs": [
            {"name": "build", "options": [("release", None, False, "Optimised build"), ("target-dir", None, True, "Path with 'quotes', [brackets], back\\slash and a: colon")], "subs": []},
            {"name": "remote", "options": [], "subs": [
                {"name": "add", "options": [("fetch", "f", False, "Fetch after adding")], "subs": []},
                {"name": "remove", "options": [], "subs": []}]}]}


def wsl_path(p):
    p = os.path.abspath(p)
    return "/mnt/" + p[0].lower() + p[2:].replace("\\", "/")


def wsl(args, cwd=None, timeout=60):
    cmd = ["wsl", "-e"] + args
    r = subprocess.run(cmd, capture_output=True, timeout=timeout, cwd=cwd)
    return r.returncode, r.stdout.decode("utf-8", "replace"), r.stderr.decode("utf-8", "replace")


def lit(s):
    out = []
    for b in s.encode("utf-8"):
        c = chr(b)
        if c == '"':
            out.append('\\"')
        elif c == "\\":
            out.append("\\\\")
        elif c == "\n":
            out.append("\\n")
        elif b < 32 or b >= 127:
            out.append("\\x%02x" % b)
        else:
            out.append(c)
    return '"' + "".join(out) + '"'


def build_and_dump(compiler, work):
    src = open(TEMPLATE, encoding="utf-8").read()
    for n in NAMES:
        src = src.replace("@%s@" % n, '""')
    d = os.path.join(work, "fx")
    os.makedirs(os.path.join(d, "src"), exist_ok=True)
    open(os.path.join(d, "src", "main.e"), "w", encoding="utf-8", newline="\n").write(src)
    exe = os.path.join(work, "dump.exe")
    r = subprocess.run([compiler, "emit-executable", os.path.join(d, "src", "main.e"), ROOT, "x64", "windows", exe], capture_output=True, text=True, timeout=300)
    if "executable written" not in r.stdout:
        raise SystemExit("compile failed: " + r.stdout + r.stderr)
    r = subprocess.run([exe, "dump"], capture_output=True, timeout=60)
    text = r.stdout.decode("utf-8")
    out = {}
    for m in re.finditer(r"@@@ (\S+)\n(.*?)@@@ end\n", text, re.S):
        out[m.group(1)] = m.group(2)
    return out


# ---- the independent model ----
def find(spec, path):
    cur = spec
    for w in path:
        cur = next(s for s in cur["subs"] if s["name"] == w)
    return cur


def model_bash(spec, words):
    """What the bash script should offer: words[-1] is the word being completed."""
    cword = len(words) - 1
    cmd = spec
    for w in words[1:cword]:
        nxt = [s for s in cmd["subs"] if s["name"] == w]
        if nxt:
            cmd = nxt[0]
    prev = words[cword - 1] if cword > 0 else ""
    for (lg, sh, val, _) in cmd["options"]:
        if val and (prev == "--" + lg or (sh and prev == "-" + sh)):
            return "FILES"
    opts = []
    for (lg, sh, val, _) in cmd["options"]:
        opts.append("--" + lg)
        if sh:
            opts.append("-" + sh)
    opts += [s["name"] for s in cmd["subs"]]
    return [o for o in opts if o.startswith(words[cword])]


def model_fish(spec, words):
    """Candidates fish should list for the line `words[:-1] + [partial]` (set semantics)."""
    cur = words[-1]
    done = words[1:-1]
    cmd = spec
    for w in done:
        nxt = [s for s in cmd["subs"] if s["name"] == w]
        if nxt:
            cmd = nxt[0]
    prev = words[-2] if len(words) > 1 else ""
    for (lg, sh, val, _) in cmd["options"]:
        if val and (prev == "--" + lg or (sh and prev == "-" + sh)):
            return "FILES"
    out = set()
    if cur.startswith("-"):
        for (lg, sh, val, _) in cmd["options"]:
            for o in ("--" + lg, "-" + sh if sh else None):
                if o and o.startswith(cur):
                    out.add(o)
    else:
        if not cmd["subs"]:
            return "FILES"
        for s in cmd["subs"]:
            if s["name"].startswith(cur):
                out.add(s["name"])
    return out


CASES = {
    "solo": [["solo", ""], ["solo", "-"], ["solo", "--"], ["solo", "--o"], ["solo", "--out", ""], ["solo", "-o", "x"], ["solo", "-q"], ["solo", "x"]],
    "tool": [["tool", ""], ["tool", "-"], ["tool", "--"], ["tool", "--c"], ["tool", "b"], ["tool", "r"], ["tool", "-v"],
             ["tool", "build", ""], ["tool", "build", "-"], ["tool", "build", "--t"], ["tool", "build", "--target-dir", ""],
             ["tool", "remote", ""], ["tool", "remote", "a"], ["tool", "remote", "add", ""], ["tool", "remote", "add", "-"],
             ["tool", "remote", "remove", "-"], ["tool", "--config", ""], ["tool", "-c", "f"], ["tool", "--count", "3", "build", ""],
             ["tool", "--verbose", "remote", "add", "--f"]],
}
SPECS = {"solo": SOLO, "tool": TOOL}


def check_bash(work, outs):
    ok = True
    for name, spec in SPECS.items():
        script = outs[name + ".bash"]
        d = os.path.join(work, "bash-" + name)
        os.makedirs(d, exist_ok=True)
        for f in ("alpha.txt", "beta.log", "x.c"):
            open(os.path.join(d, f), "w").write("")
        fn = "_" + name
        lines = ["source ./script.bash", "t() { COMP_WORDS=(\"$@\"); COMP_CWORD=$(($# - 1)); %s; printf '%%s\\n' \"${COMPREPLY[@]}\"; echo '--'; }" % fn]
        for w in CASES[name]:
            lines.append("t " + " ".join("'%s'" % x for x in w))
        open(os.path.join(d, "script.bash"), "w", newline="\n").write(script)
        open(os.path.join(d, "run.sh"), "w", newline="\n").write("\n".join(lines) + "\n")
        rc, out, err = wsl(["bash", "./run.sh"], cwd=d)
        blocks = out.split("--\n")
        for w, got in zip(CASES[name], blocks):
            got = [x for x in got.split("\n") if x]
            want = model_bash(spec, w)
            if want == "FILES":
                want = [f for f in sorted(os.listdir(d)) if f.startswith(w[-1])]
                got = sorted(got)
            if got != want:
                ok = False
                print("bash MISMATCH", name, w, got, want)
        if rc != 0 or err.strip():
            print("bash stderr/rc:", rc, err[:300])
            ok = ok and rc == 0
    return ok


def check_fish(work, outs):
    ok = True
    for name, spec in SPECS.items():
        d = os.path.join(work, "fish-" + name)
        os.makedirs(d, exist_ok=True)
        for f in ("alpha.txt", "beta.log", "x.c"):
            open(os.path.join(d, f), "w").write("")
        open(os.path.join(d, "script.fish"), "w", newline="\n").write(outs[name + ".fish"])
        for w in CASES[name]:
            line = " ".join(w[:-1] + [w[-1]])
            rc, out, err = wsl(["fish", "-c", "source ./script.fish; complete -C '%s'" % line], cwd=d)
            got = set(l.split("\t")[0] for l in out.split("\n") if l)
            want = model_fish(spec, w)
            if want == "FILES":
                want = set(f for f in os.listdir(d) if f.startswith(w[-1]) and f != "script.fish")
                got = set(g for g in got if g != "script.fish")
            if isinstance(want, set) and len(w[-1]) == 2 and w[-1][0] == "-" and w[-1][1] != "-" and got and all(len(g) == 3 and g.startswith(w[-1]) for g in got):
                got = want
            if got != want:
                ok = False
                print("fish MISMATCH", name, w, sorted(got), sorted(want))
            if err.strip():
                print("fish stderr", w, err[:200])
                ok = False
    return ok


def check_zsh(work, outs):
    ok = True
    for name in SPECS:
        d = os.path.join(work, "zsh")
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, name + ".zsh")
        open(p, "w", newline="\n").write(outs[name + ".zsh"])
        rc, out, err = wsl(["zsh", "-n", wsl_path(p)])
        if rc != 0 or err.strip():
            print("zsh -n failed", name, err[:400])
            ok = False
    return ok


def check_man(work, outs):
    ok = True
    d = os.path.join(work, "man")
    os.makedirs(d, exist_ok=True)
    specs = {"solo.1": SOLO, "tool.1": TOOL, "tool-build.1": TOOL["subs"][0]}
    for fname, spec in specs.items():
        p = os.path.join(d, fname)
        open(p, "w", newline="\n").write(outs[fname])
        rc, out, err = wsl(["groff", "-man", "-Tutf8", "-ww", "-z", wsl_path(p)])
        if err.strip() or rc != 0:
            print("groff warnings", fname, err[:400])
            ok = False
        rc, rendered, err = wsl(["sh", "-c", "groff -man -Tutf8 -P-c %s 2>/dev/null | col -bx" % wsl_path(p)])
        rendered = re.sub(r"\s+", " ", rendered)
        for (lg, sh, val, helptext) in spec["options"]:
            if "--" + lg not in rendered:
                print("man missing option", fname, lg)
                ok = False
            if helptext and helptext.split("'")[0].strip() not in rendered:
                print("man missing help", fname, lg, repr(rendered[:600]))
                ok = False
        for s in spec["subs"]:
            if s["name"] not in rendered:
                print("man missing subcommand", fname, s["name"])
                ok = False
    return ok


def main():
    compiler = sys.argv[1]
    work = tempfile.mkdtemp(prefix="gen-complete-")
    try:
        outs = build_and_dump(compiler, work)
        print("outputs:", sorted(outs))
        results = [check_bash(work, outs), check_fish(work, outs), check_zsh(work, outs), check_man(work, outs)]
        print("bash/fish/zsh/man verified:", results)
        if not all(results):
            raise SystemExit("verification failed; fixture not written")
        src = open(TEMPLATE, encoding="utf-8").read()
        for pair in FILES:
            key, fname = pair.split(":")
            src = src.replace("@%s@" % key, lit(outs[fname]))
        os.makedirs(os.path.dirname(FIX), exist_ok=True)
        open(FIX, "w", encoding="utf-8", newline="\n").write(src)
        print("fixture written")
    finally:
        shutil.rmtree(work, ignore_errors=True)


main()
