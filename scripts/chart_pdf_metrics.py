"""Helvetica advance widths (per 1000 em) for WinAnsiEncoding bytes 32..255, and the
Unicode code points that WinAnsi places in 128..159, for e.gfx.chart.pdf (D2107).
Widths come from reportlab's copy of Adobe's Helvetica AFM."""
from reportlab.pdfbase.pdfmetrics import stringWidth

widths, specials = [], []
for byte in range(32, 256):
    try:
        char = bytes([byte]).decode("cp1252")
    except UnicodeDecodeError:
        widths.append(0)
        continue
    widths.append(round(stringWidth(char, "Helvetica", 1000)))
    if 128 <= byte <= 159:
        specials.append((ord(char), byte))
print("widths", widths)
print("specials", specials)
