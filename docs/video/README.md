# Neper capabilities video

Everything needed to reproduce the current landing-page video is stored here.

- `neper-capabilities.jsx` is the canonical Higgsedit composition.
- `neper-capabilities-narration.json` records the Gideon voice, text, job IDs,
  and placement times.
- `voice.lock` pins the Gideon preset.
- `neper-capabilities/` is the editable Higgsedit project snapshot. It contains
  `project.json`, imported media, original input images, the clean render,
  poster, the three original narration MP3 files, and the exact fonts with
  their licenses.
- `../gtm/neper-capabilities.mp4` and its poster are the published outputs.

The archived narration is original Higgsfield output, not audio extracted from
the final MP4. The current starts are 0, 23.25, and 49 seconds; this preserves
the shortened pause between the first two passages.

## Rebuild

Requirements: Python 3, Higgsedit, FFmpeg, and FFprobe on `PATH`.

From the repository root:

```powershell
python docs/video/rebuild.py
```

The script rebuilds the clean 74-second composition, mixes the archived
narration stems, checks that the result has video and audio, and replaces the
published MP4 and poster. No Higgsfield account or generation credit is needed.

If Higgsedit cannot find the fonts, install the two TTF files from
`neper-capabilities/fonts` under their embedded family names, Metropolis and
Montserrat, then rerun the command.
