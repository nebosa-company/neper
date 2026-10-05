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
VERTICAL = "--vertical" in sys.argv  # the 1080x1920 cut for Shorts
OUT = HERE.parent.parent / "gtm" / ("neper-promo-vertical.mp4" if VERTICAL else "neper-promo.mp4")
POSTER = OUT.with_name("neper-promo-poster.jpg")
TMP = HERE / "_tmp"
W, H = (1080, 1920) if VERTICAL else (1920, 1080)


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
    (23.6, 25.0, MONO, 30, CYAN, 124, 940, "one MIT library"),
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
LOGO = (560, 110, 84)  # width, x, y

# The Shorts cut crops each clip to a 608-pixel column, x as a function of the clip's own
# t (panning where the subject moves; cuts measured with the scene filter), then scales it
# to 1080x1920. Text stays inside Shorts' safe area: below the top bar, above the bottom
# fifth and left of the right-hand buttons.
CROPS_V = [
    "if(lt(t,4.375),1100-500*t/4.375,if(lt(t,6.5417),1000,if(lt(t,7.9167),760,650)))",
    "if(lt(t,3.4167),520,if(lt(t,6.7083),720,1000+100*(t-6.7083)/3.3))",
    "600",
    "1050-60*min(t,5)/5",
]
TEXT_V = [
    (0.3, 4.3, MONO, 54, CYAN, 80, 280, "02:17 AM"),
    (0.6, 4.3, MONO, 30, MUTED, 82, 352, "SUBLEVEL B2  //  PROJECT: CLASSIFIED"),
    (7.0, 9.95, MONO, 46, WHITE, 100, 1180, "$ neper run hello.e"),
    (7.7, 9.95, MONO, 46, CYAN, 100, 1246, "(32 msec, 3648 bytes)"),
    (8.3, 9.95, MONO, 46, WHITE, 100, 1312, "Hello, Neper"),
    (10.1, 13.2, HEAD, 120, WHITE, 80, 1040, "DIRECT TO"),
    (10.1, 13.2, HEAD, 120, WHITE, 80, 1170, "NATIVE"),
    (10.5, 13.2, MONO, 40, CYAN, 86, 1320, "no LLVM  ·  no VM  ·  no GC"),
    (13.4, 16.5, MONO, 32, MUTED, 86, 960, "MEASURED  ·  sc1m"),
    (13.4, 16.5, MONO, 32, MUTED, 86, 1004, "920,554 lines"),
    (13.5, 16.5, HEAD, 210, WHITE, 76, 1040, "47 ms"),
    (13.8, 16.5, MONO, 40, CYAN, 86, 1300, "runtime  ·  Go 300 ms"),
    (13.8, 16.5, MONO, 40, CYAN, 86, 1356, "2.73 MiB binary"),
    (16.7, 19.85, MONO, 40, RED, 100, 1130, "E-TYPE-0002  main.e:12:9"),
    (17.0, 19.85, MONO, 40, WHITE, 100, 1190, "implicit conversion"),
    (17.0, 19.85, MONO, 40, WHITE, 100, 1246, "i64 -> u32"),
    (17.3, 19.85, MONO, 40, CYAN, 100, 1306, "expected: u32  actual: i64"),
    (19.8, 25.0, HEAD, 130, WHITE, 80, 700, "1,232"),
    (19.9, 25.0, MONO, 42, MUTED, 86, 846, "algorithms"),
    (21.1, 25.0, HEAD, 130, WHITE, 80, 920, "112"),
    (21.2, 25.0, MONO, 42, MUTED, 86, 1066, "native controls"),
    (23.0, 25.0, HEAD, 130, WHITE, 80, 1140, "344"),
    (23.1, 25.0, MONO, 36, MUTED, 86, 1286, "modules  ·  charts  ·  crypto  ·  GPU"),
    (23.6, 25.0, MONO, 42, CYAN, 86, 1350, "one MIT library"),
    (26.6, 30.0, HEAD, 54, WHITE, 80, 1150, "A model writes it."),
    (28.2, 30.0, HEAD, 54, CYAN, 80, 1228, "The compiler proves it."),
    (28.6, 30.0, MONO, 30, MUTED, 84, 1320, "neper.dev  ·  MIT"),
    (28.6, 30.0, MONO, 28, MUTED, 84, 1366, "github.com/nebosa-company/neper"),
]
SHADES_V = [
    ("band", "200*max(0,min(1,(Y-700)/300))*max(0,min(1,(1620-Y)/180))*(1-0.4*X/W)", 6.8, 25.1),
    ("spec", "210*max(0,min(1,(Y-500)/180))*max(0,min(1,(1560-Y)/160))*(1-0.5*X/W)", 19.7, 25.05),
    ("top", "200*pow(max(0,1-Y/700),1.2)", 0.2, 4.4),
    ("top-end", "200*pow(max(0,1-Y/700),1.2)", 25.8, 30.0),
    ("end", "215*max(0,min(1,(Y-950)/250))*max(0,min(1,(1650-Y)/200))", 26.3, 30.0),
]
BARS_V = [(7.0, 9.95, 76, 1180, 190), (16.7, 19.85, 76, 1130, 222)]
LOGO_V = (700, 80, 300)
if VERTICAL:
    TEXT, SHADES, BARS, LOGO = TEXT_V, SHADES_V, BARS_V, LOGO_V


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
                        f"color=black:s={W}x{H},format=rgba,geq=r=0:g=0:b=0:a='{alpha}'",
                        "-frames:v", "1", png], cwd=HERE, check=True)
        # Decode the shade once and loop it inside the graph: a looped input decodes ahead
        # of the slow text chain and queued 8 MB frames at every overlay (6.6 GB peak).
        shade_inputs += ["-framerate", "24", "-i", png]
        fade_out = f",fade=t=out:st={b - 0.3}:d=0.3:alpha=1" if b < 30 else ""
        shade_graph.append(f"[{6 + i}:v]format=rgba,loop=loop=-1:size=1,setpts=N/24/TB,"
                           f"fade=t=in:st={a}:d=0.4:alpha=1{fade_out}[sh{i}];"
                           f"[{last}][sh{i}]overlay=0:0:format=auto[s{i}]")
        last = f"s{i}"

    def frame(i: int) -> str:
        if VERTICAL:
            return f"crop=608:1080:x='{CROPS_V[i]}':y=0,scale={W}:{H}:flags=lanczos"
        return f"scale={W}:{H}"

    graph = ";".join([
        *[f"[{i}:v]trim=0:{d},setpts=PTS-STARTPTS,fps=24,{frame(i)},setsar=1[c{i}]"
          for i, d in enumerate((10, 10, 5, 5))],
        "[c0][c1][c2][c3]concat=n=4:v=1:a=0,format=yuv420p[base]",
        *shade_graph,
        f"color=0xBFFBFF:s={W}x{H}:r=24:d=30,format=rgba,fade=t=in:st={FLASH_AT - 0.08}:d=0.08:alpha=1,"
        f"fade=t=out:st={FLASH_AT}:d=0.25:alpha=1,colorchannelmixer=aa=0.5[flash]",
        f"[{last}][flash]overlay=0:0:format=auto[v2]",
        "[5:v]format=rgba,split[l1][l2];[l1]crop=470:490:0:0[icon];"
        "[l2]crop=1686:490:470:0,lutrgb=r=255:g=255:b=255[word];"
        f"[icon][word]hstack,scale={LOGO[0]}:-1,fade=t=in:st={LOGO_AT}:d=0.5:alpha=1[logo]",
        f"[v2][logo]overlay={LOGO[1]}:{LOGO[2]}:format=auto:shortest=1[v3]",
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
    if not VERTICAL:
        subprocess.run([FF, "-v", "error", "-y", "-ss", "29.2", "-i", str(OUT),
                        "-frames:v", "1", "-q:v", "3", str(POSTER)], check=True)
    shutil.rmtree(TMP)

    probe = subprocess.run([FF, "-hide_banner", "-i", str(OUT)], capture_output=True, text=True).stderr
    if "Video:" not in probe or "Audio:" not in probe or "Duration: 00:00:30.0" not in probe:
        sys.exit(f"invalid output:\n{probe}")
    print(OUT)


if __name__ == "__main__":
    main()
