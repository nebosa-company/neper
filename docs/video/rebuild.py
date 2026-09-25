import json
import shutil
import subprocess
from pathlib import Path


HERE = Path(__file__).resolve().parent
PROJECT = HERE / "neper-capabilities"
PUBLISHED = HERE.parent / "gtm"


def run(*args: str) -> None:
    subprocess.run(args, cwd=HERE, check=True)


for command in ("higgsedit", "ffmpeg", "ffprobe"):
    if not shutil.which(command):
        raise SystemExit(f"missing required command: {command}")

run("higgsedit", "build", "neper-capabilities.jsx")
run(
    "ffmpeg", "-y",
    "-i", str(PROJECT / "renders/neper-capabilities-clean.mp4"),
    "-i", str(PROJECT / "audio/narration-01-prompt-to-native.mp3"),
    "-i", str(PROJECT / "audio/narration-02-llm-contract.mp3"),
    "-i", str(PROJECT / "audio/narration-03-proof.mp3"),
    "-filter_complex",
    "[1:a]adelay=0:all=1[a0];"
    "[2:a]adelay=23250:all=1[a1];"
    "[3:a]adelay=49000:all=1[a2];"
    "[a0][a1][a2]amix=inputs=3:duration=longest:normalize=0,"
    "apad=whole_dur=74[a]",
    "-map", "0:v:0", "-map", "[a]", "-c:v", "copy",
    "-c:a", "aac", "-b:a", "128k", "-t", "74",
    "-movflags", "+faststart",
    str(PUBLISHED / "neper-capabilities.mp4"),
)
shutil.copy2(
    PROJECT / "renders/neper-capabilities-poster.png",
    PUBLISHED / "neper-capabilities-poster.png",
)

probe = json.loads(subprocess.check_output([
    "ffprobe", "-v", "error", "-show_entries",
    "format=duration:stream=codec_type", "-of", "json",
    str(PUBLISHED / "neper-capabilities.mp4"),
], text=True))
types = {stream["codec_type"] for stream in probe["streams"]}
duration = float(probe["format"]["duration"])
if types != {"audio", "video"} or abs(duration - 74) > 0.1:
    raise SystemExit(f"invalid output: streams={types}, duration={duration}")

print(PUBLISHED / "neper-capabilities.mp4")
