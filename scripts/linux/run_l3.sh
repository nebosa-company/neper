#!/bin/sh
# Run inside WSL/Linux from the repo root: sh scripts/linux/run_l3.sh [name-substring]
exec xvfb-run -a -s "-screen 0 1280x1024x24" python3 scripts/linux/gallery_l3.py "$@"
