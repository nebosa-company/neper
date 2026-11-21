"""Ask the local Qwen3.5-9B (llama-server, OpenAI API) a small mechanical question.

  python scripts/localllm.py "question" [file ...]      files and stdin are appended as context
  python scripts/localllm.py --json "extract ..." f     ask for JSON only (validated, exit 4 if invalid)

Exit codes: 0 answer printed, 3 server unreachable (do the task yourself), 4 --json answer invalid.
Thinking is off, temperature 0. Context is 32k tokens: input is cut to --max-chars (default 60000) from the
head and tail. Never send secrets or anything that must be right without checking: the answer is a
9B model's, so verify anything that is acted on.
"""
import argparse, json, os, sys, urllib.request

URL = os.environ.get("LOCALLLM_URL", "http://127.0.0.1:8080/v1/chat/completions")
MODEL = os.environ.get("LOCALLLM_MODEL", "Qwen3.5-9B-Q8_0")


def cut(text, n):
    if len(text) <= n:
        return text
    h = n * 2 // 3
    return text[:h] + "\n...[cut]...\n" + text[-(n - h):]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("question")
    ap.add_argument("files", nargs="*")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--max-chars", type=int, default=60000)
    ap.add_argument("--max-tokens", type=int, default=1200)
    a = ap.parse_args()
    ctx = []
    for f in a.files:
        with open(f, encoding="utf8", errors="replace") as fh:
            ctx.append("=== " + f + " ===\n" + fh.read())
    if not sys.stdin.isatty():
        ctx.append("=== stdin ===\n" + sys.stdin.read())
    body = cut("\n".join(ctx), a.max_chars)
    sysmsg = "You answer briefly and exactly. No preamble."
    if a.json:
        sysmsg += " Reply with valid JSON only, no code fence."
    req = {
        "model": MODEL,
        "messages": [{"role": "system", "content": sysmsg},
                     {"role": "user", "content": a.question + ("\n\n" + body if body else "")}],
        "temperature": 0,
        "max_tokens": a.max_tokens,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    try:
        r = urllib.request.Request(URL, json.dumps(req).encode(), {"Content-Type": "application/json"})
        out = json.load(urllib.request.urlopen(r, timeout=300))["choices"][0]["message"]["content"].strip()
    except Exception as e:
        print("localllm unavailable: %s" % e, file=sys.stderr)
        sys.exit(3)
    if a.json:
        t = out.strip("`").removeprefix("json").strip()
        try:
            json.loads(t)
        except ValueError:
            print(out)
            sys.exit(4)
        out = t
    print(out)


if __name__ == "__main__":
    main()
