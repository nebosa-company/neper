"""Builds docs/gtm/neper-promo.mp4 (30 s) from the clips in this folder.

clip-a.mp4 and clip-b.mp4 carry their own narration. bridge.mp4 (Kling 3.0,
already trimmed to 5 s) and closer.mp4 (Kling 3.0, 5 s) are silent, so the last
ten seconds get the cloned-voice line vo-closer.wav over a synthesized bed.
Requires ffmpeg on PATH (or imageio-ffmpeg) and JetBrains Mono installed.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / "gtm" / "neper-promo.mp4"
POSTER = OUT.with_name("neper-promo-poster.jpg")
TMP = HERE / "_tmp"


def ffmpeg_exe() -> str:
    if shutil.which("ffmpeg"):
        return "ffmpeg"
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        sys.exit("missing ffmpeg (install it or imageio-ffmpeg)")


FF = ffmpeg_exe()
HEAD = "../neper-capabilities/fonts/Montserrat-ExtraBold.ttf"
MONO = "_tmp/mono.ttf"
WHITE, CYAN, MUTED, RED = "0xF2F6FF", "0x62E6F2", "0xB4C3D3", "0xFF7A7A"

# vo-closer.wav speech spans (s), measured with silencedetect -38 dB; the line is
# re-spaced with GAP pauses and sped up by TEMPO so it fits 19.7-29.4 s.
VO_SPANS = [(0.30, 1.59), (2.14, 4.02), (4.42, 6.18), (6.35, 9.86), (10.19, 11.45)]
GAP, TEMPO, VO_AT = 0.15, 1.10, 19.70

# (start, end, font, size, color, x, y, text); x may be "center".
TEXT = [
    # A: the hook
    (0.3, 4.3, MONO, 34, CYAN, 120, 96, "02:17 AM"),
    (0.6, 4.3, MONO, 22, MUTED, 122, 142, "SUBLEVEL B2  //  PROJECT: CLASSIFIED"),
    (7.0, 9.95, MONO, 32, WHITE, 132, 842, "$ neper run hello.e"),
    (7.7, 9.95, MONO, 32, CYAN, 132, 888, "(32 msec, 3648 bytes)"),
    (8.3, 9.95, MONO, 32, WHITE, 132, 934, "Hello, Neper"),
    # B: speed and the compiler contract
    (10.1, 13.2, HEAD, 76, WHITE, 120, 806, "DIRECT TO NATIVE"),
    (10.5, 13.2, MONO, 30, CYAN, 124, 900, "no LLVM  ·  no VM  ·  no GC"),
    (13.4, 16.5, MONO, 24, MUTED, 124, 760, "MEASURED  ·  sc1m  ·  920,554 lines"),
    (13.5, 16.5, HEAD, 112, WHITE, 118, 790, "47 ms"),
    (13.8, 16.5, MONO, 28, CYAN, 124, 920, "runtime  ·  Go 300 ms  ·  2.73 MiB binary"),
    (16.7, 19.85, MONO, 28, RED, 132, 818, "E-TYPE-0002  main.e:12:9"),
    (17.0, 19.85, MONO, 28, WHITE, 132, 862, "implicit conversion i64 -> u32"),
    (17.3, 19.85, MONO, 28, CYAN, 132, 906, "expected: u32   actual: i64"),
    # C: the library, as a spec sheet that builds up over the bridge
    (19.8, 25.0, HEAD, 66, WHITE, 120, 664, "1,232"),
    (19.9, 25.0, MONO, 30, MUTED, 400, 690, "algorithms"),
    (21.1, 25.0, HEAD, 66, WHITE, 120, 750, "112"),
    (21.2, 25.0, MONO, 30, MUTED, 400, 776, "native controls"),
    (23.0, 25.0, HEAD, 66, WHITE, 120, 836, "344"),
    (23.1, 25.0, MONO, 30, MUTED, 400, 862, "modules  ·  charts  ·  crypto  ·  GPU"),
    (24.8, 25.0, MONO, 30, CYAN, 124, 940, "one MIT library"),
    # end card: logo top left, tagline bottom left, holographic charts in between
    (26.6, 30.0, HEAD, 52, WHITE, 120, 856, "A model writes it."),
    (28.2, 30.0, HEAD, 52, CYAN, 120, 922, "The compiler proves it."),
    (28.6, 30.0, MONO, 24, MUTED, 124, 1000, "neper.dev  ·  MIT  ·  github.com/nebosa-company/neper"),
]
# Shades (name, alpha expression, start, end) laid under the text, and the bars
# beside the terminal blocks (start, end, x, y, height).
SHADES = [
    ("low", "190*pow(max(0,min(1,(Y-560)/520)),1.2)*(1-0.55*X/W)", 6.8, 25.1),
    ("left", "200*pow(max(0,1-X/1250),1.3)*max(0,min(1,(Y-470)/220))", 19.7, 25.05),
    ("top", "215*pow(max(0,1-X/1500),1.2)*pow(max(0,1-Y/420),1.1)", 25.8, 30.0),
    ("bottom", "225*pow(max(0,min(1,(Y-680)/400)),1.1)*pow(max(0,1-X/1700),0.8)", 26.3, 30.0),
]
BARS = [(7.0, 9.95, 112, 842, 136), (16.7, 19.85, 112, 818, 130)]
FLASH_AT, LOGO_AT, BOOM_AT = 25.0, 25.95, 25.95


def fade(a: float, b: float, d: float = 0.3) -> str:
    # Fade in at a; fade out before b unless the text holds to the last frame.
    out = f"({b}-t)/{d}" if b < 30 else "1"
    return f"min(1,min((t-{a})/{d},{out}))"


def drawtexts() -> str:
    out = []
    for i, (a, b, font, size, color, x, y, text) in enumerate(TEXT):
        (TMP / f"t{i}.txt").write_text(text, encoding="utf-8")
        x = "(w-text_w)/2" if x == "center" else x
        rise = f"{y}+10*max(0,1-(t-{a})/0.35)"
        out.append(
            f"drawtext=fontfile={font}:textfile=_tmp/t{i}.txt:expansion=none:"
            f"fontsize={size}:fontcolor={color}:x={x}:y='{rise}':"
            f"shadowcolor=black@0.65:shadowx=0:shadowy=3:"
            f"alpha='{fade(a, b)}':enable='between(t,{a},{b})'"
        )
    for a, b, x, y, h in BARS:
        out.append(f"drawbox=x={x}:y={y}:w=4:h={h}:color={CYAN}@0.9:t=fill:enable='between(t,{a},{b})'")
    return ",".join(out)


def vo_chain() -> str:
    parts, labels = [f"[4:a]asplit={len(VO_SPANS)}" + "".join(f"[s{i}]" for i in range(len(VO_SPANS)))], []
    for i, (a, b) in enumerate(VO_SPANS):
        parts.append(f"[s{i}]atrim={a - 0.03}:{b + 0.05},asetpts=PTS-STARTPTS[v{i}]")
        labels.append(f"[v{i}]")
        if i < len(VO_SPANS) - 1:
            parts.append(f"aevalsrc=0|0:s=44100:d={GAP}[g{i}]")
            labels.append(f"[g{i}]")
    ms = int(VO_AT * 1000)
    parts.append("".join(labels) + f"concat=n={len(labels)}:v=0:a=1,atempo={TEMPO},"
                 f"volume=1dB,adelay={ms}|{ms}[vo]")
    return ";".join(parts)


DRONE = ("(0.11*sin(2*PI*55*t)+0.06*sin(2*PI*82.41*t+0.5*sin(2*PI*0.2*t))"
         "+0.035*sin(2*PI*110*t)*(0.5+0.5*sin(2*PI*0.5*t)))")
# Clip B's narration opens with "Direct composition. No L-X." (its generator's
# reading of "Direct compilation. No LLVM."); mute it up to the pause before
# "No virtual machine" and hold the drone under the gap. On-screen text says it.
B_MUTE = 1.92


def gap_chain() -> str:
    t0, d = 9.7, 2.6
    ms = int(t0 * 1000)
    return (f"aevalsrc='0.7*{DRONE}|0.7*{DRONE}':s=48000:d={d},"
            f"afade=t=in:d=0.4,afade=t=out:st={d - 0.5}:d=0.5,adelay={ms}|{ms}[gap]")


def bed_chain() -> str:
    # 10.4 s from 19.6 s: a low drone, a whoosh through the light tunnel, and a sub
    # impact when the logo lands. Times below are relative to the bed start.
    t0, boom = 19.6, BOOM_AT - 19.6
    drone = f"min(1,t/0.6)*(0.6+0.4*min(1,t/5))*{DRONE}"
    hit = (f"if(gte(t,{boom}),0.6*sin(2*PI*(38*(t-{boom})+15*(1-exp(-6*(t-{boom})))))"
           f"*exp(-2.2*(t-{boom})),0)")
    ms = int(t0 * 1000)
    return (
        f"aevalsrc='{drone}+{hit}|{drone}+{hit}':s=48000:d=10.4[tone];"
        f"anoisesrc=d=10.4:c=pink:a=0.35:r=48000,highpass=f=900,lowpass=f=7000,"
        f"volume='if(between(t,2.8,5.4),pow((t-2.8)/2.6,2),0)':eval=frame,aformat=channel_layouts=stereo[whoosh];"
        f"anoisesrc=d=10.4:c=brown:a=0.12:r=48000,lowpass=f=180,aformat=channel_layouts=stereo[rumble];"
        f"[tone][whoosh][rumble]amix=inputs=3:normalize=0,afade=t=in:d=0.4,adelay={ms}|{ms}[bed]"
    )


def main() -> None:
    TMP.mkdir(exist_ok=True)
    mono = Path("C:/Windows/Fonts/JetBrainsMono-Medium.ttf")
    if not mono.exists():
        sys.exit("install JetBrains Mono (JetBrainsMono-Medium.ttf)")
    shutil.copy2(mono, TMP / "mono.ttf")
    shade_inputs, shade_graph, last = [], [], "base"
    for i, (name, alpha, a, b) in enumerate(SHADES):
        png = f"_tmp/shade-{name}.png"
        subprocess.run([FF, "-v", "error", "-y", "-f", "lavfi", "-i",
                        f"color=black:s=1920x1080,format=rgba,geq=r=0:g=0:b=0:a='{alpha}'",
                        "-frames:v", "1", png], cwd=HERE, check=True)
        shade_inputs += ["-loop", "1", "-framerate", "24", "-t", "30", "-i", png]
        fade_out = f",fade=t=out:st={b - 0.3}:d=0.3:alpha=1" if b < 30 else ""
        shade_graph.append(f"[{6 + i}:v]format=rgba,fade=t=in:st={a}:d=0.4:alpha=1{fade_out}[sh{i}];"
                           f"[{last}][sh{i}]overlay=0:0:format=auto[s{i}]")
        last = f"s{i}"

    graph = ";".join([
        "[0:v]trim=0:10,setpts=PTS-STARTPTS,fps=24,scale=1920:1080,setsar=1[c0]",
        "[1:v]trim=0:10,setpts=PTS-STARTPTS,fps=24,scale=1920:1080,setsar=1[c1]",
        "[2:v]trim=0:5,setpts=PTS-STARTPTS,fps=24,scale=1920:1080,setsar=1[c2]",
        "[3:v]trim=0:5,setpts=PTS-STARTPTS,fps=24,scale=1920:1080,setsar=1[c3]",
        "[c0][c1][c2][c3]concat=n=4:v=1:a=0,format=yuv420p[base]",
        *shade_graph,
        f"color=0xBFFBFF:s=1920x1080:r=24:d=30,format=rgba,fade=t=in:st={FLASH_AT - 0.08}:d=0.08:alpha=1,"
        f"fade=t=out:st={FLASH_AT}:d=0.25:alpha=1,colorchannelmixer=aa=0.5[flash]",
        f"[{last}][flash]overlay=0:0:format=auto[v2]",
        "[5:v]format=rgba,split[l1][l2];[l1]crop=470:490:0:0[icon];"
        "[l2]crop=1686:490:470:0,lutrgb=r=255:g=255:b=255[word];"
        f"[icon][word]hstack,scale=560:-1,fade=t=in:st={LOGO_AT}:d=0.5:alpha=1[logo]",
        "[v2][logo]overlay=110:84:format=auto:shortest=1[v3]",
        f"[v3]{drawtexts()}[vout]",
        "[0:a]atrim=0:10,asetpts=PTS-STARTPTS[a0]",
        f"[1:a]atrim=0:10.1,asetpts=PTS-STARTPTS,afade=t=in:st={B_MUTE}:d=0.1,"
        "afade=t=out:st=9.7:d=0.4,adelay=10000|10000[a1]",
        vo_chain(),
        gap_chain(),
        bed_chain(),
        "[a0][a1][gap][bed][vo]amix=inputs=5:normalize=0:duration=longest,atrim=0:30,"
        "loudnorm=I=-15:TP=-1.5:LRA=11,afade=t=out:st=29.5:d=0.5[aout]",
    ])
    (TMP / "graph.txt").write_text(graph, encoding="utf-8")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        FF, "-v", "error", "-y",
        "-i", "clip-a.mp4", "-i", "clip-b.mp4", "-i", "bridge.mp4", "-i", "closer.mp4",
        "-i", "vo-closer.wav",
        "-loop", "1", "-framerate", "24", "-t", "30", "-i", "../../gtm/logo/neper-lockup.png",
        *shade_inputs,
        "-/filter_complex", "_tmp/graph.txt",
        "-map", "[vout]", "-map", "[aout]", "-t", "30",
        "-c:v", "libx264", "-crf", "18", "-preset", "slow", "-pix_fmt", "yuv420p", "-r", "24",
        "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", str(OUT),
    ], cwd=HERE, check=True)
    subprocess.run([FF, "-v", "error", "-y", "-ss", "29.2", "-i", str(OUT),
                    "-frames:v", "1", "-q:v", "3", str(POSTER)], check=True)
    shutil.rmtree(TMP)

    probe = subprocess.run([FF, "-hide_banner", "-i", str(OUT)], capture_output=True, text=True).stderr
    if "Video:" not in probe or "Audio:" not in probe or "Duration: 00:00:30.0" not in probe:
        sys.exit(f"invalid output:\n{probe}")
    print(OUT)


if __name__ == "__main__":
    main()
