#!/usr/bin/env python3
"""Print the four coefficient arrays of lib/e/algo/magnetic.e (g, h, their yearly changes, 90 values each, index
n(n+1)/2 + m - 1) from NOAA's WMM2025 coefficient file (WMM_2025.COF, as pygeomag ships it).
Usage: gen_wmm_table.py PATH/TO/WMM_2025.COF"""
import sys

rows = [line.split() for line in open(sys.argv[1], encoding="utf-8") if len(line.split()) == 6]
assert len(rows) == 90, len(rows)
for name, column in (("g", 2), ("h", 3), ("g_dot", 4), ("h_dot", 5)):
    values = ", ".join(r[column] + ("" if "." in r[column] else ".0") + "f64" for r in rows)
    print("%s: %s" % (name, values))
