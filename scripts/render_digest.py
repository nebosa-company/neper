# -*- coding: utf-8 -*-
"""Render the agent-ingestible digests of the work queue and the decision log (T038).

Usage:  python scripts/render_digest.py [--check]     (from the repository root)

docs/decisions.md is megabytes and a queue item's evidence runs to kilobytes, so
neither can be read whole and a routine grep overflows a tool's output cap. This
writes two small indexes beside them and leaves the long text where it is:

  docs/digest/queue.tsv      one row per open queue item: id, category, score,
                             evidence bytes, title, one-line status
  docs/digest/decisions.tsv  one row per `## D<n>` entry: number, bytes, title
                             (the line number comes from `grep -n "^## D<n> "`)

The one-line status is the sentence after `NOT DONE:`, `REMAINING:` or `Not yet:`
when the evidence has one, else its first sentence, cut at STATUS_WIDTH. The
evidence budget is advisory: items over EVIDENCE_BUDGET bytes are listed so the
next editor shortens them; `--check` fails when a digest is stale, not when an item
is long. Never edit the output by hand.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIGEST = ROOT / "docs" / "digest"
STATUS_WIDTH = 200
EVIDENCE_BUDGET = 4000
MARKERS = ("NOT DONE:", "REMAINING:", "Not yet:", "Not done:")


def clean(text):
    return re.sub(r"\s+", " ", text).strip()


def status_of(evidence):
    for marker in MARKERS:
        at = evidence.rfind(marker)
        if at >= 0:
            return clean(evidence[at + len(marker):])[:STATUS_WIDTH]
    text = clean(evidence)
    # Provenance sentences say who asked and when, not what is true.
    text = re.sub(r"^(?:(?:Queued by the user|Planning only|Queued)\s*\([^)]*\)\.?\s*)+", "", text)
    first = re.split(r"(?<=[.;])\s", text, maxsplit=1)[0]
    return first[:STATUS_WIDTH]


def queue_rows():
    items = json.loads((ROOT / "docs" / "work-queue.json").read_text(encoding="utf-8"))["items"]
    rows = ["id\tcategory\tscore\tevidence_bytes\ttitle\tstatus"]
    over = []
    for item in items:
        evidence = item.get("evidence", "")
        size = len(evidence.encode("utf-8"))
        if size > EVIDENCE_BUDGET:
            over.append((item["id"], size))
        rows.append("\t".join([
            item["id"], item["category"], str(item["score"]), str(size),
            clean(item["title"]), status_of(evidence),
        ]))
    return rows, over


def decision_rows():
    text = (ROOT / "docs" / "decisions.md").read_text(encoding="utf-8")
    heads = list(re.finditer(r"^## D(\d+)\b[^\n]*$", text, re.M))
    rows = ["id\tbytes\ttitle"]
    for at, head in enumerate(heads):
        end = heads[at + 1].start() if at + 1 < len(heads) else len(text)
        title = re.sub(r"^## D\d+\s*[—–-]?\s*", "", head.group(0)).strip()
        rows.append("D%s\t%d\t%s" % (head.group(1), len(text[head.start():end].encode("utf-8")), clean(title)))
    return rows


def main(argv):
    queue, over = queue_rows()
    outputs = {"queue.tsv": "\n".join(queue) + "\n", "decisions.tsv": "\n".join(decision_rows()) + "\n"}
    if "--check" in argv:
        stale = [name for name, body in outputs.items()
                 if not (DIGEST / name).exists() or (DIGEST / name).read_text(encoding="utf-8") != body]
        if stale:
            print("stale digest: %s; run python scripts/render_digest.py" % ", ".join(stale))
            return 1
        return 0
    DIGEST.mkdir(parents=True, exist_ok=True)
    for name, body in outputs.items():
        (DIGEST / name).write_text(body, encoding="utf-8", newline="\n")
    print("wrote docs/digest/queue.tsv (%d items) and docs/digest/decisions.tsv (%d entries)"
          % (len(queue) - 1, len(outputs["decisions.tsv"].splitlines()) - 1))
    if over:
        print("evidence over the %d-byte budget: %s" % (EVIDENCE_BUDGET, ", ".join("%s (%d)" % o for o in over)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
