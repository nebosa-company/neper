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
- The video is published on YouTube, https://youtu.be/S5dMLUpOtRg, and embedded
  from there. `rebuild.py` still writes `../gtm/neper-capabilities.mp4` for
  upload, but MP4 files are ignored by git; only the poster is committed.

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

# Neper promo (30 s)

`neper-promo/` builds `../gtm/neper-promo.mp4` and its poster for senior
developers: hook, speed, library, then a finish on the same basement setup.

| Time | Source | Audio |
| --- | --- | --- |
| 0–10 s | `clip-a.mp4`, the user's Higgsfield clip | its own narration |
| 10–20 s | `clip-b.mp4`, the user's Higgsfield clip | its own narration, minus the mangled opening "Direct composition. No L-X." (muted to 1.92 s, drone under the gap) |
| 20–25 s | `bridge.mp4`, Kling 3.0 pro job `2ebbbc6c-1f63-40ee-8e5a-4b4682884693`, 1.9–6.9 s of the original (start/end frames: clip A's last, clip B's first) | `vo-closer.wav` over a synthesized bed |
| 25–30 s | `closer.mp4`, Kling 3.0 pro job `b0bae93d-40ca-4153-9f97-39642856a19b`, started from clip B's last frame | same |

`vo-closer.wav` is Seed Audio job `ff2720c6-32ca-49a1-8106-8012b6f592cb`, cloned
from clip A's narration so the whole video has one narrator: "Twelve hundred
algorithms. A hundred and twelve native controls. Charts, crypto, GPU, one MIT
library. Neper. A model writes it. The compiler proves it."

On-screen numbers are measured, not targets: the `neper run hello.e` output is
the landing page's, and 47 ms, Go's 300 ms, 2.73 MiB and 920,554 lines are the
sc1m post's. The 1,232 / 112 / 344 counts are the landing page's.

MP4 files are ignored by git, so the four source clips and the output are not
committed; keep them beside `build.py` locally (the job IDs above identify the
generated ones) and publish the result on YouTube. Rebuild from the repository
root (FFmpeg or `imageio-ffmpeg`, and JetBrains Mono installed; no Higgsfield
credit needed):

```powershell
python docs/video/neper-promo/build.py
```
