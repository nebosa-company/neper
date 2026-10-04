"""Run security regressions with all generated files under --output-dir."""
import argparse
from pathlib import Path
import subprocess
import stat
import tempfile

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ("fmt_xml", "fmt_png", "fmt_jpeg", "fmt_webp",
            "text_template", "fmt_html_template", "fmt_gaps_b", "io_streams", "fs_basics")


def run(command, cwd, expected=0):
    result = subprocess.run([str(arg) for arg in command], cwd=cwd,
                            capture_output=True, text=True, timeout=120)
    if result.returncode != expected:
        raise AssertionError(f"{command}: exit {result.returncode}\n"
                             f"{result.stdout}{result.stderr}")
    return result.stdout + result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--os", choices=("windows", "linux"), required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix="security-", dir=args.output_dir.resolve()))
    extension = ".exe" if args.os == "windows" else ""
    for fixture in FIXTURES:
        source = ROOT / "tests/selfhost/fixtures/link" / fixture / "src/main.e"
        output = scratch / (fixture + extension)
        run([compiler, "emit-executable", source, ROOT, "x64", args.os, output], scratch)
        run([output], scratch)
        print(f"PASS {fixture}")

    # A real compiler publication over a planted staging symlink. Windows often
    # requires elevation for symlinks; Linux is the affected platform.
    if args.os == "linux":
        source = scratch / "source.e"
        source.write_text("fn main() -> err { ret ok }\n", encoding="utf-8")
        victim = scratch / "victim"
        victim.write_bytes(b"keep this file")
        output = scratch / "output.em"
        staged = scratch / "output.em.tmp"
        staged.symlink_to(victim)
        command = [compiler, "emit-em", source, ROOT, "x64", args.os, output]
        run(command, scratch)
        original = output.read_bytes()
        assert victim.read_bytes() == b"keep this file" and staged.is_symlink()
        assert stat.S_IMODE(output.stat().st_mode) == 0o644
        run(command, scratch)
        assert output.read_bytes() == original and victim.read_bytes() == b"keep this file"
        staged.unlink()
        staged.write_bytes(b"a write that died")
        run(command, scratch)
        assert staged.read_bytes() == b"a write that died" and output.read_bytes() == original
        source.write_text("fn main()->err{ret ok}\n", encoding="utf-8")
        source.chmod(0o644)
        run([compiler, "fmt-file", source, "--write"], scratch)
        assert stat.S_IMODE(source.stat().st_mode) == 0o644
        print("PASS staging symlink and stale-file isolation")

    # Failed replacement must not retain a new full-sized staging file per retry.
    bad_output = scratch / "output-directory"
    bad_output.mkdir()
    source = scratch / "failure.e"
    source.write_text("fn main() -> err { ret ok }\n", encoding="utf-8")
    before = set(scratch.glob(".neper-stage-*"))
    for _ in range(3):
        run([compiler, "emit-em", source, ROOT, "x64", args.os, bad_output], scratch, 1)
        assert set(scratch.glob(".neper-stage-*")) == before
    print("PASS failed-publication cleanup")

    # The fault injection must use the same safe staging path, and a subsequent
    # build must ignore the interrupted write and produce the clean image.
    project = scratch / "fault-project"
    (project / "src").mkdir(parents=True)
    (project / "src/main.e").write_text(
        "use dep\nfn main() -> err { let value = dep.value()\nret ok }\n", encoding="utf-8")
    (project / "src/dep.e").write_text("fn value() -> i32 { ret 7i32 }\n", encoding="utf-8")
    source = project / "src/main.e"
    clean = scratch / ("clean" + extension)
    recovered = scratch / ("recovered" + extension)
    command = [compiler, "emit-executable", source, ROOT, "x64", args.os]
    run(command + [clean], scratch)
    fault = run(command + [recovered, "--incremental", "--fault-write", "1"], scratch, 1)
    assert "made to fail by --fault-write" in fault
    leftovers = list(project.rglob(".neper-stage-*"))
    assert leftovers, "fault left no staged file"
    saved = {path: path.read_bytes() for path in leftovers}
    run(command + [recovered, "--incremental"], scratch)
    assert recovered.read_bytes() == clean.read_bytes()
    assert all(path.read_bytes() == data for path, data in saved.items())
    run([recovered], scratch)
    print("PASS interrupted-write recovery")
    print(f"PASS security regressions ({args.os}); outputs: {scratch}")


if __name__ == "__main__":
    main()
