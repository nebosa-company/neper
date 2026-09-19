"""Validate the frozen M2.5 GPU contract and pending M3 fixture manifest."""
import argparse
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
REQUIREMENT = re.compile(r"H\d\d$")
FIXTURE = re.compile(r"gpu_[a-z0-9_]+$")
PROFILES = {"cpu", "vulkan", "cuda"}


def validate(root=ROOT):
    errors = []
    path = root / "docs/m25-gpu-contracts.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    prose = (root / data.get("authority", "")).read_text(encoding="utf-8")
    api = (root / "docs/module-apis.md").read_text(encoding="utf-8")
    spec = (root / "docs/spec.md").read_text(encoding="utf-8")

    if data.get("schema") != "neper-m25-gpu-contracts-v1" or data.get("version") != 1:
        errors.append("unsupported GPU contract schema/version")
    requirements = data.get("requirements", {})
    if not requirements:
        errors.append("GPU contract has no requirements")

    fixture_ids = set()
    for requirement, contract in requirements.items():
        if not REQUIREMENT.fullmatch(requirement):
            errors.append(f"invalid requirement id: {requirement}")
        if contract.get("design_status") != "closed":
            errors.append(f"{requirement}: design_status must be closed")
        if contract.get("runtime_status") != "pending_m3":
            errors.append(f"{requirement}: runtime_status must be pending_m3")
        if f"## " not in prose or requirement not in prose:
            errors.append(f"{requirement}: missing prose contract")
        for declaration in contract.get("api_declarations", []):
            if declaration not in api:
                errors.append(f"{requirement}: API declaration is missing: {declaration}")
            if declaration not in spec:
                errors.append(f"{requirement}: spec declaration is missing: {declaration}")
        for fixture in contract.get("fixtures", []):
            fixture_id = fixture.get("id", "")
            if not FIXTURE.fullmatch(fixture_id) or fixture_id in fixture_ids:
                errors.append(f"invalid or duplicate fixture id: {fixture_id}")
            fixture_ids.add(fixture_id)
            profiles = fixture.get("profiles", [])
            if not profiles or len(profiles) != len(set(profiles)) or not set(profiles) <= PROFILES:
                errors.append(f"{fixture_id}: invalid profiles")
            if fixture.get("status") != "pending_m3":
                errors.append(f"{fixture_id}: design fixtures must remain pending_m3")
            if not fixture.get("expected"):
                errors.append(f"{fixture_id}: missing expected result")
            if f"`{fixture_id}`" not in prose:
                errors.append(f"{fixture_id}: missing from prose contract")

    h13 = requirements.get("H13", {})
    if h13.get("maps") != [f"H{number:02d}" for number in range(1, 8)]:
        errors.append("H13: CPU/device mapping must cover H01-H07 in order")
    checks = h13.get("checks", {})
    if set(checks) != {"bounds", "null", "tag", "alignment", "overflow", "divide_by_zero"}:
        errors.append("H13: check matrix is incomplete")
    for name in ("bounds", "null", "tag", "alignment"):
        if checks.get(name, {}).get("release") != "fault":
            errors.append(f"H13: {name} must remain checked in release")

    allowed = ["H13", "H21", "H22", "H23"]
    if list(requirements) != [item for item in allowed if item in requirements]:
        errors.append("GPU requirements must appear in H13/H21/H22/H23 order")
    h21 = requirements.get("H21")
    if h21 is not None:
        if h21.get("token_states") != ["queued", "running", "complete", "lost", "stale"]:
            errors.append("H21: token state machine is incomplete or reordered")
        if h21.get("tracking") != "whole_buffer":
            errors.append("H21: the first implementation must freeze whole-buffer tracking")
        if h21.get("cancellation") != "not_in_v1":
            errors.append("H21: cancellation cannot be implied by the v1 token contract")
        required = {"gpu_two_queues_ordered", "gpu_two_queues_race", "gpu_chain_transfers",
                    "gpu_early_release", "gpu_range_overlap", "gpu_failed_launch",
                    "gpu_stale_token", "gpu_device_lost", "gpu_wrong_device_token",
                    "gpu_devices_cpu", "gpu_devices_mock_dup", "gpu_devices_mock_invalid"}
        actual = {item.get("id") for item in h21.get("fixtures", [])}
        if actual != required:
            errors.append("H21: dependency/discovery fixture manifest is incomplete")
    return data, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    data, errors = validate()
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    fixture_count = sum(len(item.get("fixtures", []))
                        for item in data["requirements"].values())
    print(f"PASS: {len(data['requirements'])} GPU contracts; {fixture_count} pending fixtures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
