"""Strict per-cell audit (round 12): `python -I scripts/looks_strict.py <sheet> ... [--dir windows-dark]`.

Same as looks_cells.py -v, whose structural mask is now the reference's alone (audit 4: ANDing it with ours' hid a reference
flat pixel where ours is not flat, i.e. an anti-aliased corner). A flat reference pixel counts as off whenever ours differs by
more than 2 levels there. Prints every cell with its numbers.
"""
import os
import runpy
import sys

sys.argv.append("-v")
runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "looks_cells.py"), run_name="__main__")
