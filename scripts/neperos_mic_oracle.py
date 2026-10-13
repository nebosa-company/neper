#!/usr/bin/env python3
# (C166, D5003) The scripted microphone of neperos/src/bgservice.e, written again from its description: a triangle wave
# whose period is 36 + 4 * (seed % 7) frames under a four-step swell (1/4, 2/4, 3/4, 4/4 of full, a step every 4000
# frames), amplitude 9000, 8 kHz mono 16-bit little-endian. Prints the byte sum mod 65521 of the first N frames (the
# number the Recorder and the speaker's sink report), or checks a serial log: with --log FILE it finds every
# "recorder captured N frames checksum C" line and "services recording started seed S" before it and compares.
import re
import sys


def trunc_div(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


def sample(seed, n):
    period = 36 + 4 * (seed % 7)
    half = period // 2
    phase = n % period
    v = period - phase if phase >= half else phase
    base = trunc_div((v * 2 - half) * 9000, half)
    swell = 1 + (n // 4000) % 4
    return trunc_div(base * swell, 4)


def checksum(seed, frames):
    total = 0
    for n in range(frames):
        u = sample(seed, n) & 0xFFFF
        total = (total + (u & 255) + (u >> 8)) % 65521
    return total


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--log":
        text = open(sys.argv[2], encoding="latin-1").read()
        seed = None
        failures = 0
        checked = 0
        for line in text.splitlines():
            m = re.match(r"services recording started seed (\d+)", line)
            if m:
                seed = int(m.group(1))
            m = re.match(r"recorder captured (\d+) frames checksum (\d+)", line)
            if m and seed is not None:
                checked += 1
                want = checksum(seed, int(m.group(1)))
                if want != int(m.group(2)):
                    failures += 1
                    print("MISMATCH seed", seed, "frames", m.group(1), "device", m.group(2), "oracle", want)
        print("checked", checked, "failures", failures)
        sys.exit(1 if failures or checked == 0 else 0)
    seed, frames = int(sys.argv[1]), int(sys.argv[2])
    print(checksum(seed, frames))


if __name__ == "__main__":
    main()
