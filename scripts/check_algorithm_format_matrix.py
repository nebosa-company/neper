"""Validate the algorithm/file-format semantic coverage matrix."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / "docs/algorithm-format-coverage.json").read_text())
required = {"golden vectors", "round-trip tests", "malformed-input tests", "streaming/limits tests"}
errors = []
seen = set()
for row in data.get("items", []):
    key = row.get("id")
    if not key or key in seen:
        errors.append(f"duplicate or missing id: {key!r}")
    seen.add(key)
    if row.get("status") not in {"planned", "equivalent", "adaptation", "partial", "missing", "unknown"}:
        errors.append(f"{key}: invalid status")
    missing = required - set(row.get("required_evidence", []))
    if missing:
        errors.append(f"{key}: missing evidence categories: {', '.join(sorted(missing))}")
if errors:
    print("FAIL: algorithm/format matrix")
    print("\n".join(f"- {e}" for e in errors))
    raise SystemExit(1)
print(f"PASS: {len(seen)} algorithm/format rows satisfy matrix schema and A0 evidence requirements")
