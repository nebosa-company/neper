"""Every `.e` under a tree through `neper fmt -` into another tree (D549).

    python format_tree.py COMPILER IN_DIR OUT_DIR

Files that are not sources are copied as they are. `fmt -` reads stdin and writes
stdout, so no file is ever formatted in place. A source the formatter refuses ends
the run with its name on stderr and exit 1.
"""
import os
import shutil
import subprocess
import sys


def main(argv):
    if len(argv) != 4:
        sys.stderr.write("usage: format_tree.py COMPILER IN_DIR OUT_DIR\n")
        return 2
    compiler, source_root, out_root = argv[1:]
    shutil.rmtree(out_root, ignore_errors=True)
    count = 0
    for directory, _, names in os.walk(source_root):
        rel = os.path.relpath(directory, source_root)
        out_dir = os.path.join(out_root, rel) if rel != "." else out_root
        os.makedirs(out_dir, exist_ok=True)
        for name in sorted(names):
            src = os.path.join(directory, name)
            dst = os.path.join(out_dir, name)
            if not name.endswith(".e"):
                shutil.copyfile(src, dst)
                continue
            with open(src, "rb") as stdin:
                run = subprocess.run([compiler, "fmt", "-"], stdin=stdin, capture_output=True)
            if run.returncode != 0:
                sys.stderr.write("fmt refused %s: %s\n" % (src, run.stderr.decode("utf-8", "replace")[:200]))
                return 1
            with open(dst, "wb") as out:
                out.write(run.stdout)
            count += 1
    print("formatted %d sources into %s" % (count, out_root))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
