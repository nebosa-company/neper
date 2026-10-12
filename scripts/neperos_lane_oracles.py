#!/usr/bin/env python3
"""Independent recomputations of what the NeperOS lane-C fixtures expect (D4005, D4007, D4008).

Run it and compare with the markers in tests/selfhost/neperos-apps.txt:

  level_selftest   level selftest sum 2516 -1974 985343 noise 240 232 233
  blocks_script    blocks lines 1 score 286            (taps: 3 Left, Drop, Drop, 4 Right, Drop, Left, Drop, 2 Right, Drop)
  clock_ring       audio ring peak 11199               (alarm volume 7, square wave of 16000)
  steps            the recording's 228 steps           (1.9 steps a second for 120 s)
"""
import math


def flat_at(n):
    h = (n * 2246822519 + 3266489917) % 4294967296
    h = ((h ^ (h >> 15)) * 2654435761) % 4294967296
    nx = ((h % 1000) / 1000.0 - 0.5) * 0.08
    ny = (((h // 1000) % 1000) / 1000.0 - 0.5) * 0.08
    nz = (((h // 1000000) % 1000) / 1000.0 - 0.5) * 0.08
    return (0.03 + nx, 0.0 - 0.02 + ny, 9.81 + 0.05 + nz)


def level_selftest():
    cols = [[], [], []]
    for n in range(100):
        for axis, v in enumerate(flat_at(n)):
            cols[axis].append(int(v * 1000))  # the server packs mm/s^2, truncated toward zero

    def sd(v):
        m = sum(v) / len(v)
        return math.sqrt(sum((a - m) ** 2 for a in v) / (len(v) - 1))

    sums = [sum(c) for c in cols]
    noise = [int(sd(c) * 10) for c in cols]
    return sums, noise


COLS, ROWS = 10, 20
MASKS = {0: [0x0F00, 0x2222, 0x00F0, 0x4444], 1: [0x8E00, 0x6440, 0x0E20, 0x44C0], 2: [0x2E00, 0x4460, 0x0E80, 0xC440],
         3: [0x6600] * 4, 4: [0x6C00, 0x4620, 0x06C0, 0x8C40], 5: [0x4E00, 0x4640, 0x0E40, 0x4C40],
         6: [0xC600, 0x2640, 0x0C60, 0x4C80]}


def filled(p, r, i):
    return (MASKS[p][r] >> (15 - i)) & 1 == 1


def fits(b, p, r, x, y):
    for i in range(16):
        if filled(p, r, i):
            cx, cy = x + i % 4, y + i // 4
            if cx < 0 or cx >= COLS or cy >= ROWS:
                return False
            if cy >= 0 and b[cy * COLS + cx]:
                return False
    return True


class Game:
    def __init__(self, seed):
        self.seed, self.bag, self.bag_at = seed, [0] * 7, 7
        self.board, self.score, self.lines, self.level = [0] * 200, 0, 0, 1
        self.next = self.draw()
        self.spawn()

    def draw(self):
        if self.bag_at >= 7:
            self.bag = list(range(7))
            for k in range(6, 0, -1):
                self.seed = (self.seed * 1103515245 + 12345) & 2147483647
                j = (self.seed >> 8) % (k + 1)
                self.bag[k], self.bag[j] = self.bag[j], self.bag[k]
            self.bag_at = 0
        p = self.bag[self.bag_at]
        self.bag_at += 1
        return p

    def spawn(self):
        self.piece, self.next = self.next, self.draw()
        self.rot, self.px, self.py = 0, 3, -1

    def lock(self):
        for i in range(16):
            if filled(self.piece, self.rot, i):
                cx, cy = self.px + i % 4, self.py + i // 4
                if 0 <= cy < ROWS and 0 <= cx < COLS:
                    self.board[cy * COLS + cx] = self.piece + 1
        cleared, row = 0, ROWS
        while row > 0:
            row -= 1
            if all(self.board[row * COLS + c] for c in range(COLS)):
                for r in range(row, 0, -1):
                    for c in range(COLS):
                        self.board[r * COLS + c] = self.board[(r - 1) * COLS + c]
                for c in range(COLS):
                    self.board[c] = 0
                cleared += 1
                row += 1
        if cleared:
            self.score += {1: 100, 2: 300, 3: 500}.get(cleared, 800) * self.level
            self.lines += cleared
            self.level = 1 + self.lines // 10
        self.spawn()

    def left(self):
        if fits(self.board, self.piece, self.rot, self.px - 1, self.py):
            self.px -= 1

    def right(self):
        if fits(self.board, self.piece, self.rot, self.px + 1, self.py):
            self.px += 1

    def drop(self):
        g = 0
        while fits(self.board, self.piece, self.rot, self.px, self.py + 1) and g < 30:
            self.py += 1
            g += 1
        self.score += 2 * g
        self.lock()


def blocks_script():
    g = Game(20261008)
    for step in ("L", "L", "L", "D", "D", "R", "R", "R", "R", "D", "L", "D", "R", "R", "D"):
        {"L": g.left, "R": g.right, "D": g.drop}[step]()
    return g.lines, g.score


def audio_peak(volume):
    gain = volume * 65536 // 10
    return (16000 * 65536 * gain // 65536) // 65536


if __name__ == "__main__":
    sums, noise = level_selftest()
    print("level selftest sum", *sums, "noise", *noise)
    lines, score = blocks_script()
    print("blocks lines", lines, "score", score)
    print("audio ring peak", audio_peak(7))
    print("steps recording", int(1.9 * 120))
