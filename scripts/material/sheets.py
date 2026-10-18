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

S6 = ["rest", "hover", "focus", "pressed", "disabled", "error"]
SHEETS["checkbox"] = {"columns": 6, "cell_w": 72, "cell_h": 64, "cells": ["checkbox-%s-%s" % (k, s) for k in ["unchecked", "checked", "indeterminate"] for s in S6]}
SHEETS["radio"] = {"columns": 6, "cell_w": 72, "cell_h": 64, "cells": ["radio-%s-%s" % (k, s) if s != "error" else None for k in ["unchecked", "checked"] for s in S6]}
SHEETS["switch"] = {"columns": 5, "cell_w": 90, "cell_h": 56, "cells": ["switch-%s-%s" % (k, s) for k in ["off", "on", "off-icons", "on-icons"] for s in S5]}

SHEETS["text_field"] = {"columns": 6, "cell_w": 270, "cell_h": 96, "cells": [
    "text-field-%s-%s" % (v, k) for v in ["filled", "outlined"] for k in
    ["empty-rest", "empty-hover", "empty-focus", "value-focus", "value-disabled", "value-error"]]}

SHEETS["combo_box"] = {"columns": 3, "cell_w": 270, "cell_h": 96, "cells": [
    "select-outlined-value-rest", "select-outlined-value-hover", "select-outlined-value-focus", "select-outlined-value-disabled",
    "select-outlined-value-error", "select-filled-value-rest", "select-filled-value-hover", "select-filled-value-focus"]}

SHEETS["chips"] = {"columns": 4, "cell_w": 130, "cell_h": 48, "cells": [
    "chip-%s-%s" % (k, s) for k in ["assist", "filter", "filter-selected", "input", "suggestion"] for s in ["rest", "hover", "focus", "pressed"]]}

SHEETS["progress"] = {"columns": 5, "cell_w": 270, "cell_h": 64, "cells": [
    "progress-linear-0", "progress-linear-30", "progress-linear-60", "progress-linear-100", None,
    "progress-circular-0", "progress-circular-30", "progress-circular-60", "progress-circular-100", None]}

SHEETS["tabs"] = {"columns": 2, "cell_w": 310, "cell_h": 73, "cells": [
    "tabs-primary-rest", "tabs-primary-icons-rest", "tabs-secondary-rest", "tabs-secondary-second-rest", "tabs-primary-disabled",
    "tabs-primary-hover", "tabs-primary-pressed"]}

SHEETS["menu"] = {"columns": 1, "cell_w": 220, "cell_h": 345, "at": (18, 8), "cells": ["menu-rest"]}
SHEETS["menu_hover"] = {"columns": 1, "cell_w": 220, "cell_h": 345, "at": (18, 8), "cells": ["menu-hover"]}

SHEETS["list"] = {"columns": 4, "cell_w": 350, "cell_h": 96, "cells": [
    "list-item-one-rest", "list-item-two-rest", None, "list-item-two-hover", "list-item-two-focus", "list-item-two-pressed", None, "list-item-two-disabled"]}

SHEETS["dialog"] = {"columns": 1, "cell_w": 330, "cell_h": 300, "at": (-9, 16), "cells": ["dialog-rest"]}
SHEETS["dialog_icon"] = {"columns": 1, "cell_w": 330, "cell_h": 340, "at": (-9, 26), "cells": ["dialog-icon"]}

SHEETS["snackbar"] = {"columns": 2, "cell_w": 360, "cell_h": 84, "cells": [
    "snackbar-rest", "snackbar-action", "snackbar-action-close", "snackbar-two-lines", None, None]}
