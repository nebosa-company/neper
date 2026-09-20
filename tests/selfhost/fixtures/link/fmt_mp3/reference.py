"""Regenerates the vectors in src/main.e and the tables in lib/e/fmt/mp3.e.

Needs an ffmpeg with libmp3lame (`pip install imageio-ffmpeg` provides one) and a copy
of minimp3.h (https://github.com/lieff/minimp3, CC0) beside this script for the tables
and the reference decode. Run from the repository root:

    python tests/selfhost/fixtures/link/fmt_mp3/reference.py

The streams are short synthetic tones encoded without a Xing frame, so every frame is
audio and the reference decoders (minimp3 and ffmpeg, which agree within one LSB) and
`e.fmt.mp3` count the same PCM frames. The fixture pins the decoded samples against
minimp3's to a tolerance of two LSB.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..', '..'))
FFMPEG = None
try:
    import imageio_ffmpeg
    FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
except ImportError:
    FFMPEG = 'ffmpeg'

STREAMS = [
    # name, channels, rate, bitrate, lavfi expression
    ('mono', 1, 44100, '32k', '0.5*sin(2*PI*440*t)+0.25*sin(2*PI*2000*t)'),
    ('stereo', 2, 44100, '64k', '0.5*sin(2*PI*440*t)|0.4*sin(2*PI*660*t)+0.2*sin(2*PI*3000*t)'),
    ('lsf', 1, 22050, '24k', '0.6*sin(2*PI*330*t)'),
]


def lit(b):
    out = []
    for c in b:
        if c == 34:
            out.append(chr(92) + '"')
        elif c == 92:
            out.append(chr(92) + chr(92))
        elif 32 <= c < 127:
            out.append(chr(c))
        else:
            out.append(chr(92) + 'x%02x' % c)
    return '"' + ''.join(out) + '"'


def encode(name, channels, rate, bitrate, expr):
    path = os.path.join(HERE, name + '.mp3')
    subprocess.check_call([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i',
                           'aevalsrc=%s:s=%d:d=0.24' % (expr, rate), '-ac', str(channels), '-ar', str(rate),
                           '-c:a', 'libmp3lame', '-b:a', bitrate, '-write_xing', '0', path])
    return open(path, 'rb').read()


def main():
    minimp3 = os.path.join(HERE, 'minimp3.h')
    if not os.path.exists(minimp3):
        sys.exit('minimp3.h is needed beside reference.py for the reference decode')
    # reference decoder: minimp3 built with the local C compiler (see README traps for MSVC)
    refdec = os.path.join(HERE, 'refdec.exe')
    if not os.path.exists(refdec):
        sys.exit('build refdec.exe from refdec.c (a whole-file minimp3 driver) beside this script first')
    vectors = []
    for name, channels, rate, bitrate, expr in STREAMS:
        mp3 = encode(name, channels, rate, bitrate, expr)
        pcm_path = os.path.join(HERE, name + '.pcm')
        subprocess.check_call([refdec, os.path.join(HERE, name + '.mp3'), pcm_path])
        pcm = open(pcm_path, 'rb').read()
        vectors.append((name, channels, rate, mp3, pcm))
    main_e = os.path.join(HERE, 'src', 'main.e')
    text = open(main_e, encoding='utf-8').read()
    for name, channels, rate, mp3, pcm in vectors:
        text = re.sub(r'fn %s_mp3\(\) -> str \{ ret ".*?" \}' % name,
                      lambda m: 'fn %s_mp3() -> str { ret %s }' % (name, lit(mp3)), text, flags=re.S)
        text = re.sub(r'fn %s_pcm\(\) -> str \{ ret ".*?" \}' % name,
                      lambda m: 'fn %s_pcm() -> str { ret %s }' % (name, lit(pcm)), text, flags=re.S)
    open(main_e, 'w', encoding='utf-8', newline='\n').write(text)
    print('wrote', main_e)


if __name__ == '__main__':
    main()
