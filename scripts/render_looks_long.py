"""Run scripts/render_looks.py when status.d overlay paths exceed the 260 character Windows limit.

render_looks.py resolves its root through Path(...).resolve(), which undoes subst drives, so a long
overlay name fails with FileNotFoundError. This wrapper gives it a \\\\?\\ extended-length root instead.
Usage (from any directory): python scripts/render_looks_long.py
"""
import os

base = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
src = open(os.path.join(base, "scripts", "render_looks.py"), encoding="utf-8").read()
src = src.replace("ROOT = Path(__file__).resolve().parents[1]", "ROOT = Path('\\\\\\\\?\\\\' + r'%s')" % base)
src = src.replace('print("wrote", OUT.relative_to(ROOT)', 'print("wrote", OUT.name')
exec(compile(src, "render_looks", "exec"), {"__name__": "__main__", "__file__": os.path.join(base, "scripts", "render_looks.py")})
