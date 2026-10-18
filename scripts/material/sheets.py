"""Sheet geometry and the reference crop of each cell (see cmp.py). Keep in step with examples/looks/material_*.e."""


def grid(rows, states, fmt):
    return [fmt % (r, s) if "%s-%s" in fmt or fmt.count("%s") == 2 else None for r in rows for s in states]


S5 = ["rest", "hover", "focus", "pressed", "disabled"]
BTN = ["filled", "tonal", "elevated", "outlined", "text"]

SHEETS = {
    "button": {"columns": 5, "cell_w": 112, "cell_h": 56, "cells": ["button-%s-%s" % (v, s) for v in BTN for s in S5]},
    "button_icon": {"columns": 5, "cell_w": 124, "cell_h": 56, "cells": ["button-%s-icon-%s" % (v, s) for v in BTN for s in S5]},
}

IB = ["standard", "filled", "tonal", "outlined"]
SHEETS["fab"] = {"columns": 6, "cell_w": 150, "cell_h": 108, "cells": [
    "fab-small-rest", "fab-rest", "fab-large-rest", "fab-extended-rest", "fab-extended-hover", "fab-extended-pressed"] + [
    "icon-button-%s-%s" % (v, s) for v in IB for s in ["rest", "toggled", "hover", "focus", "pressed", "disabled"]]}
