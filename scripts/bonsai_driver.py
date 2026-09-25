# -*- coding: utf-8 -*-
"""Drive a local LM Studio model through docs/tasks/, one task per session.

Usage:  python scripts/bonsai_driver.py [--endpoint http://localhost:8080/v1] [--model KEY]
                                        [--kind modules|queue|all] [--max-tasks N] [--rounds 60]
                                        [--session-minutes 120] [--skip-linux] [--dry-run]
                                        [--unsafe-compatibility]

Each session: pick the next eligible task (README rules), give the model the README,
the language card and the task file, let it work with repository-scoped read, search
and edit tools until it says DONE, then leave the changes unexecuted and uncommitted
for review. `--unsafe-compatibility` restores the old shell, automatic suite and
commit workflow. Talks either to an
OpenAI-compatible server (`--endpoint`, e.g. the PrismML llama.cpp fork's llama-server)
or to LM Studio through `pip install lmstudio` and `lms server start`.
"""
import argparse, datetime, json, shlex, subprocess, sys, time
from pathlib import Path
from urllib.parse import urlsplit

try:
    import lmstudio as lms
except ImportError:  # only needed without --endpoint
    lms = None

ROOT = Path(__file__).resolve().parent.parent
TASKS = ROOT / "docs" / "tasks"
STATE = ROOT / "build" / "bonsai" / "state.json"
LOGS = ROOT / "build" / "bonsai"
PROTECTED = ("docs/tasks/", "docs/progress.html", "docs/work-done.jsonl", "scripts/bonsai_driver.py", ".git/")


def endpoint_allowed(url):
    """Remote model endpoints require HTTPS; plain HTTP is loopback-only."""
    try:
        parsed = urlsplit(url)
        parsed.port
    except ValueError:
        return False
    if (not parsed.hostname or parsed.username is not None or parsed.password is not None
            or parsed.query or parsed.fragment):
        return False
    return parsed.scheme == "https" or (
        parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1", "::1"})


def sh(cmd, timeout=600, cwd=ROOT):
    p = subprocess.run(cmd, cwd=cwd, shell=False, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def git(*args, timeout=120):
    return sh(["git", *args], timeout=timeout)


def touched_paths():
    _, out = git("status", "--porcelain", "--untracked-files=all")
    return [line[3:].strip().strip('"') for line in out.splitlines() if line.strip()]


# ---------------------------------------------------------------- task selection
def module_tasks():
    """Eligible modules, lowest layer first: no blocker, every dependency on disk."""
    plan = json.loads((ROOT / "docs" / "modules.json").read_text(encoding="utf-8"))
    rows = {m["name"]: m for m in plan["modules"]}
    out = []
    for f in sorted(TASKS.glob("modules/*.md")):
        name = f.stem
        m = rows.get(name)
        if not m or m["blocked_by"] or m["milestone"] in ("M3", "M4", "M5", "M6"):
            continue  # a module of a later compiler milestone waits on that milestone, not on a session
        deps_ok = all(d == "e.os" or (ROOT / "lib" / "e" / (d[2:].replace(".", "/") + ".e")).exists() for d in m["direct_dependencies"])
        if deps_ok:
            out.append((m["layer"], name, f))
    return [(name, f) for _, name, f in sorted(out)]


def queue_task():
    items = json.loads((ROOT / "docs" / "work-queue.json").read_text(encoding="utf-8"))["items"]
    if not items:
        return None
    head = items[0]
    files = list(TASKS.glob("%s/%s-*.md" % (head["category"], head["id"])))
    return (head["id"], files[0]) if files else None


def next_task(kind, state):
    failed = {k for k, v in state.get("failures", {}).items() if v >= 2}
    done = set(state.get("done", []))
    if kind in ("modules", "all"):
        for name, f in module_tasks():
            if name not in failed and name not in done:
                return name, f
    if kind in ("queue", "all"):
        q = queue_task()
        if q and q[0] not in failed:
            return q
    return None


# ---------------------------------------------------------------- tools
def _repo_path(path):
    p = (ROOT / path).resolve()
    try:
        rel = p.relative_to(ROOT).as_posix()
    except ValueError:
        raise ValueError("path escapes repository: " + str(path))
    return p, rel


def _inside(path):
    p, rel = _repo_path(path)
    if any(rel == x.rstrip("/") or rel.startswith(x) for x in PROTECTED):
        raise ValueError("protected path: " + rel)
    return p, rel


def read_lines(path: str, start: int = 1, end: int = 120) -> str:
    """Read lines start..end (1-based, inclusive, at most 400) of a repository file."""
    try:
        p, _ = _inside(path)
    except ValueError as e:
        return "Error: " + str(e)
    lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
    end = min(end, start + 399, len(lines))
    return "\n".join("%d\t%s" % (i, lines[i - 1]) for i in range(max(1, start), end + 1)) or "(empty range; file has %d lines)" % len(lines)


def search(pattern: str, path: str = ".", fixed: bool = True) -> str:
    """git grep -n for a pattern under a path (fixed string by default); at most 60 hits."""
    try:
        _, rel = _inside(path)
    except ValueError as e:
        return "Error: " + str(e)
    args = ["grep", "-n", "-I"] + (["-F"] if fixed else ["-E"]) + ["-e", pattern, "--", rel]
    _, out = git(*args)
    hits = out.splitlines()
    return "\n".join(hits[:60]) + ("\n... %d more" % (len(hits) - 60) if len(hits) > 60 else "") or "(no hits)"


def edit(path: str, old: str, new: str) -> str:
    """Replace one exact, unique occurrence of `old` with `new` in a file; creates the file when old is empty and it does not exist."""
    try:
        p, _ = _inside(path)
    except ValueError as e:
        return "Error: " + str(e)
    if old == "":
        if p.exists():
            return "Error: file exists; pass the exact text to replace."
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(new, encoding="utf-8", newline="\n")
        return "created %s (%d bytes)" % (path, len(new))
    text = p.read_text(encoding="utf-8")
    n = text.count(old)
    if n != 1:
        return "Error: `old` occurs %d times; it must occur exactly once." % n
    p.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
    return "edited %s" % path


BASH = r"C:\Program Files\Git\bin\bash.exe"


def run(command: str, timeout_seconds: int = 900) -> str:
    """Run an unrestricted POSIX shell. Exposed only by --unsafe-compatibility."""
    try:
        code, out = sh([BASH, "-lc", command], timeout=min(timeout_seconds, 3600))
    except subprocess.TimeoutExpired:
        return "Error: timed out after %d s" % timeout_seconds
    if len(out) > 8192:
        out = out[:4096] + "\n... [%d bytes cut] ...\n" % (len(out) - 8192) + out[-4096:]
    return "exit %d\n%s" % (code, out)


# ---------------------------------------------------------------- one session
def prompt_for(task_file, unsafe_compatibility=False, allow_shell=False):
    readme = (TASKS / "README.md").read_text(encoding="utf-8")
    card = (ROOT / "docs" / "llm-neper-card.md").read_text(encoding="utf-8")
    if allow_shell:
        shell_note = " An unrestricted `run` shell and automatic host verification are enabled by the operator."
    elif unsafe_compatibility:
        shell_note = " Automatic host verification is enabled; no command tool is available."
    else:
        shell_note = " No command or network tool is available; finish the edit for operator review and verification."
    completion = ("Reply with a line starting DONE when the task file's fixture passes on this host with the self-hosted compiler"
                  if unsafe_compatibility else
                  "Reply with a line starting DONE when the requested edit and fixture are ready for operator verification")
    action = ("Build with the self-hosted compiler" if unsafe_compatibility else
              "Implement the requested change")
    system = ("You are implementing one feature of the neper compiler and library, alone, in a git checkout at %s.\n"
              "Follow the README and the task file exactly. Tools: read_lines, search, edit.%s Never read a file over 120 KB whole.\n"
              "Budget: read only what the task file names (its dependencies, one sibling module, one sibling fixture and that fixture's "
              "two runner blocks), then WRITE. Reading past the fifth round without an edit is the failure mode to avoid; you can read "
              "more later when a build error asks for it.\n"
              "Do not commit, add, reset or checkout. %s, or BLOCKED: <reason> when you cannot proceed.\n\n"
              "=== docs/tasks/README.md ===\n%s\n\n=== docs/llm-neper-card.md ===\n%s") % (ROOT.as_posix(), shell_note, completion, readme, card)
    user = ("=== %s ===\n%s\n\nTake the first unchecked line of 'Remaining work' (for a module: the whole fence, in order). "
            "%s, add the fixture and both runner entries, then reply DONE or BLOCKED."
            % (task_file.relative_to(ROOT).as_posix(), task_file.read_text(encoding="utf-8"), action))
    return system, user


SAFE_TOOLS = {"read_lines": read_lines, "search": search, "edit": edit}
SAFE_TOOL_SCHEMAS = [
    {"type": "function", "function": {"name": "read_lines", "description": read_lines.__doc__, "parameters": {"type": "object", "properties": {
        "path": {"type": "string"}, "start": {"type": "integer"}, "end": {"type": "integer"}}, "required": ["path"]}}},
    {"type": "function", "function": {"name": "search", "description": search.__doc__, "parameters": {"type": "object", "properties": {
        "pattern": {"type": "string"}, "path": {"type": "string"}, "fixed": {"type": "boolean"}}, "required": ["pattern"]}}},
    {"type": "function", "function": {"name": "edit", "description": edit.__doc__, "parameters": {"type": "object", "properties": {
        "path": {"type": "string"}, "old": {"type": "string"}, "new": {"type": "string"}}, "required": ["path", "old", "new"]}}},
]
RUN_TOOL_SCHEMA = {"type": "function", "function": {"name": "run", "description": run.__doc__, "parameters": {"type": "object", "properties": {
    "command": {"type": "string"}, "timeout_seconds": {"type": "integer"}}, "required": ["command"]}}}


def exposed_tools(unsafe_compatibility=False, allow_shell=False):
    tools = dict(SAFE_TOOLS)
    schemas = list(SAFE_TOOL_SCHEMAS)
    if unsafe_compatibility and allow_shell:
        tools["run"] = run
        schemas.append(RUN_TOOL_SCHEMA)
    return tools, schemas


def endpoint_up(args):
    import urllib.request
    try:
        with urllib.request.urlopen(args.endpoint.rstrip("/") + "/models", timeout=5) as resp:
            return resp.status == 200
    except Exception:
        return False


def restart_server(args, log):
    """Kill any llama-server, relaunch --server-cmd, wait until /v1/models answers."""
    if not args.server_cmd:
        return False
    subprocess.run(["taskkill", "/F", "/IM", "llama-server.exe"], capture_output=True)
    time.sleep(2)
    command = args.server_cmd if sys.platform == "win32" else shlex.split(args.server_cmd)
    with open(LOGS / "llama-server.log", "a") as server_log:
        subprocess.Popen(command, shell=False, cwd=ROOT,
                         stdout=subprocess.DEVNULL, stderr=server_log)
    for _ in range(60):
        time.sleep(3)
        if endpoint_up(args):
            log.write("\n=== server restarted ===\n")
            return True
    log.write("\n!!! server did not come up after restart\n")
    return False


def session_openai(task_file, args, log):
    """The same session over an OpenAI-compatible /v1/chat/completions (llama-server, LM Studio's server)."""
    import urllib.request
    system, user = prompt_for(task_file, args.unsafe_compatibility, args.allow_shell)
    tools, tool_schemas = exposed_tools(args.unsafe_compatibility, args.allow_shell)
    messages = [{"role": "system", "content": system}, {"role": "user", "content": user}]
    deadline = time.time() + args.session_minutes * 60
    restarts = {}
    cut_off = 0
    since_edit = 0
    thinking = open(str(log.name).replace(".log", ".thinking.log"), "a", encoding="utf-8")
    rnd = -1
    while rnd + 1 < args.rounds:
        rnd += 1
        if time.time() > deadline:
            log.write("\n!!! session exceeded %d minutes\n" % args.session_minutes)
            return "error"
        body = json.dumps({"model": args.model, "messages": messages, "tools": tool_schemas, "temperature": 0.6, "top_p": 0.95,
                           "max_tokens": args.max_tokens}).encode("utf-8")
        req = urllib.request.Request(args.endpoint.rstrip("/") + "/chat/completions", data=body, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=3600) as resp:
                choice = json.loads(resp.read().decode("utf-8"))["choices"][0]
                reply = choice["message"]
        except Exception as e:
            # The fork's server dies on a bad allocation now and then; the conversation is
            # ours, so restart it and ask the same round again rather than lose the session.
            log.write("\n!!! %s: %s\n" % (type(e).__name__, e))
            if restarts.get("n", 0) < 2 and restart_server(args, log):
                restarts["n"] = restarts.get("n", 0) + 1
                rnd -= 1  # ask the same round again
                continue
            return "error"
        # Thinking is not fed back (it only bloats the context) but it is kept beside the
        # transcript, so a stalled session can be read.
        thinking.write("\n=== round %d ===\n%s\n" % (rnd, reply.pop("reasoning_content", None) or ""))
        thinking.flush()
        text = reply.get("content") or ""
        calls = reply.get("tool_calls") or []
        if choice.get("finish_reason") == "length" and not calls:
            # The reply ran out of tokens before its tool call: the whole budget went to
            # deliberation. Ask again, once or twice, with the deliberation named as the fault.
            cut_off += 1
            log.write("\n=== round %d === (cut off at %d tokens, retry %d)\n" % (rnd, args.max_tokens, cut_off))
            if cut_off > 2:
                return "error"
            messages.append({"role": "user", "content": "Your reply was cut off at the token limit before any tool call. "
                             "Reply again: decide in a few sentences, then make the tool call. Write the file in two or three "
                             "`edit` calls if it is long."})
            continue
        messages.append(reply)
        log.write("\n=== round %d ===\n%s\n" % (rnd, text))
        if not calls:
            return "done" if text.lstrip().startswith("DONE") else "blocked"
        since_edit = 0 if any(c["function"]["name"] == "edit" for c in calls) else since_edit + 1
        for call in calls:
            fn = call["function"]
            if since_edit > args.read_budget and fn["name"] != "edit" and not touched_paths():
                # Five sessions read for ten to fourteen rounds and wrote nothing; an advisory
                # nudge changed nothing. Past the budget the only tool that answers is `edit`
                # until a file exists, after which reading is allowed again (build errors).
                result = ("Error: read budget exhausted (%d rounds without an edit). Only `edit` answers until a file exists. "
                          "Create the module file now from what you have read; a build error will let you read again." % since_edit)
                log.write("\n--- %s refused (read budget) ---\n" % fn["name"])
                messages.append({"role": "tool", "tool_call_id": call.get("id", ""), "content": result})
                continue
            try:
                kwargs = json.loads(fn.get("arguments") or "{}")
                result = tools[fn["name"]](**kwargs) if fn["name"] in tools else "Error: unknown tool " + fn["name"]
            except Exception as e:
                result = "Error: %s: %s" % (type(e).__name__, e)
            if since_edit >= args.read_budget - 1:
                result = str(result) + "\n\n[driver: %d rounds without an edit; after %d only `edit` will answer. Create the file now.]" % (since_edit, args.read_budget)
            log.write("\n--- %s(%s) ---\n%s\n" % (fn["name"], (fn.get("arguments") or "")[:300], str(result)[:2000]))
            log.flush()
            messages.append({"role": "tool", "tool_call_id": call.get("id", ""), "content": str(result)})
    log.write("\n!!! round cap %d reached\n" % args.rounds)
    return "error"


def session(model, task_id, task_file, args, log):
    if args.endpoint:
        return session_openai(task_file, args, log)
    system, user = prompt_for(task_file, args.unsafe_compatibility, args.allow_shell)
    tools, _ = exposed_tools(args.unsafe_compatibility, args.allow_shell)
    chat = lms.Chat(system)
    chat.add_user_message(user)
    deadline = time.time() + args.session_minutes * 60
    final = {"text": ""}

    def on_message(msg):
        content = getattr(msg, "content", None)
        if isinstance(content, list):
            content = "\n".join(getattr(part, "text", None) or str(part) for part in content)
        text = content if isinstance(content, str) else str(msg)
        log.write("\n--- %s ---\n%s\n" % (type(msg).__name__, text))
        log.flush()
        if type(msg).__name__ == "AssistantResponse":
            final["text"] = text
        chat.append(msg)

    def on_round_start(i):
        if time.time() > deadline:
            raise TimeoutError("session exceeded %d minutes" % args.session_minutes)
        log.write("\n=== round %d ===\n" % i)

    try:
        model.act(chat, list(tools.values()), max_prediction_rounds=args.rounds,
                  config={"temperature": 0.6, "top_p_sampling": 0.95, "context_overflow_policy": "stopAtLimit"},
                  on_message=on_message, on_round_start=on_round_start)
    except Exception as e:  # timeouts, context overflow, server drops: all mean "not proven"
        log.write("\n!!! %s: %s\n" % (type(e).__name__, e))
        return "error"
    return "done" if final["text"].lstrip().startswith("DONE") else "blocked"


def suites(args, log):
    code, out = sh(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "tests/selfhost/run.ps1"], timeout=5400)
    log.write("\n=== windows suite exit %d ===\n%s\n" % (code, out[-4000:]))
    if code != 0 or "selfhost tests passed" not in out:
        return False
    if args.skip_linux:
        return True
    mnt = "/mnt/" + ROOT.drive[0].lower() + ROOT.as_posix()[2:]
    code, out = sh(["wsl", "-d", args.distro, "--", "bash", "-c",
                    "cd %s && bash tests/selfhost/run.sh > build/linux-suite.log 2>&1; echo EXIT=$?; tail -n 40 build/linux-suite.log" % mnt], timeout=5400)
    log.write("\n=== linux suite ===\n%s\n" % out[-4000:])
    return "EXIT=0" in out and "selfhost tests passed" in out


def commit(task_id, title, touched):
    sh([sys.executable, "scripts/render_progress.py"])
    sh([sys.executable, "scripts/render_tasks.py"], timeout=600)
    paths = sorted(set(touched) | set(touched_paths()))
    git("add", "--", *paths)
    msg = "%s\n\nTask: %s, implemented by Bonsai 2 27B under scripts/bonsai_driver.py.\n\nCo-Authored-By: Bonsai 2 27B (LM Studio) <noreply@prismml.com>" % (title, task_id)
    return git("commit", "-q", "-m", msg)[0] == 0


def revert(touched):
    tracked = [p for p in touched if git("ls-files", "--error-unmatch", "--", p)[0] == 0]
    untracked = [p for p in touched if p not in tracked]
    if tracked:
        git("checkout", "--", *tracked)
    for p in untracked:
        git("clean", "-f", "--", p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="prism-ml/bonsai-27b")
    ap.add_argument("--endpoint", default="", help="OpenAI-compatible base URL, e.g. http://localhost:8080/v1 (llama-server); omit for the LM Studio SDK")
    ap.add_argument("--server-cmd", default="", help="command that starts the server behind --endpoint; used to (re)start it when it is down")
    ap.add_argument("--read-budget", type=int, default=6, help="rounds without an edit after which only `edit` answers, until a file exists")
    ap.add_argument("--max-tokens", type=int, default=16384, help="reply cap per round; thinking counts against it, so pair it with the server's --reasoning-budget")
    ap.add_argument("--kind", choices=["modules", "queue", "all"], default="modules")
    ap.add_argument("--max-tasks", type=int, default=1)
    ap.add_argument("--rounds", type=int, default=60)
    ap.add_argument("--session-minutes", type=int, default=120)
    ap.add_argument("--context", type=int, default=131072)
    ap.add_argument("--distro", default="Ubuntu-24.04")
    ap.add_argument("--skip-linux", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="print the next task and exit")
    ap.add_argument("--unsafe-compatibility", action="store_true",
                    help="DANGEROUS: run the model-modified suite and commit it on the host")
    ap.add_argument("--allow-shell", action="store_true",
                    help="DANGEROUS: expose the unrestricted run shell to the model (requires --unsafe-compatibility)")
    args = ap.parse_args()
    if args.endpoint and not endpoint_allowed(args.endpoint):
        ap.error("--endpoint must use HTTPS, or HTTP on localhost/loopback")
    if args.allow_shell and not args.unsafe_compatibility:
        ap.error("--allow-shell requires --unsafe-compatibility")
    if args.unsafe_compatibility:
        print("WARNING: --unsafe-compatibility executes and commits model-modified code on the host", file=sys.stderr)
    if args.allow_shell:
        print("WARNING: --allow-shell gives model output unrestricted host command execution", file=sys.stderr)

    LOGS.mkdir(parents=True, exist_ok=True)
    state = json.loads(STATE.read_text(encoding="utf-8")) if STATE.exists() else {"failures": {}, "done": []}
    model = None
    for _ in range(args.max_tasks):
        pick = next_task(args.kind, state)
        if not pick:
            print("no eligible task left for --kind", args.kind)
            break
        task_id, task_file = pick
        title = task_file.read_text(encoding="utf-8").splitlines()[0].lstrip("# ")
        print("task:", task_id, "->", task_file.relative_to(ROOT).as_posix())
        if args.dry_run:
            break
        if touched_paths():
            sys.exit("working tree is not clean; another session's edits would be committed or reverted - stop.")
        if args.endpoint and not endpoint_up(args):
            with open(LOGS / "driver.log", "a", encoding="utf-8") as boot:
                if not restart_server(args, boot):
                    sys.exit("endpoint %s is down and --server-cmd did not bring it up" % args.endpoint)
        if model is None and not args.endpoint:
            if lms is None:
                sys.exit("pip install lmstudio, or pass --endpoint")
            model = lms.llm(args.model, config={"context_length": args.context})
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        with open(LOGS / ("%s-%s.log" % (task_id.replace(".", "_"), stamp)), "w", encoding="utf-8") as log:
            verdict = session(model, task_id, task_file, args, log)
            touched = touched_paths()
            print("  agent:", verdict, "| touched:", len(touched))
            if verdict == "done" and touched and not args.unsafe_compatibility:
                print("  review: secure mode left the changes unexecuted and uncommitted")
                break
            ok = verdict == "done" and bool(touched) and suites(args, log)
            if ok:
                ok = commit(task_id, title, touched)
            if ok:
                print("  committed")
                state["done"].append(task_id)
                state["failures"].pop(task_id, None)
            else:
                print("  reverted")
                revert(touched)
                state["failures"][task_id] = state["failures"].get(task_id, 0) + 1
        STATE.write_text(json.dumps(state, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
