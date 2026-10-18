// Ground truth for the Windows look's text: real GDI ClearType glyphs, one font and size at a time.
// glyphs.exe <outdir> <face> <weight> <px> <quality> [fg bg ...]
//   writes <outdir>/<tag>.outline.txt (GetGlyphOutline GGO_NATIVE of every code 32..255, raw 16.16 points, the advance)
//   and <outdir>/<tag>.<fg>-<bg>.bgra (a 16 x 14 atlas of TextOut cells, BGRA, top down, header: w h cellw cellh ascent pad)
// fg and bg are 6-digit hex RGB colours (default 000000 and FFFFFF). quality is the LOGFONT lfQuality (5 CLEARTYPE, 6 NATURAL, 4 ANTIALIASED).
// glyphs.exe <outdir> --blend <quality>   writes the blend ramp: 'W' in Segoe UI 24 px for a grid of grey fg and bg (blend.bgra).
// No window is shown; nothing reads the screen. Build: zig cc -target x86_64-windows-gnu -O1 glyphs.c -lgdi32 -luser32.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static HFONT make_font(const wchar_t *face, int weight, int px, int quality) {
  return CreateFontW(-px, 0, 0, 0, weight, 0, 0, 0, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, quality, DEFAULT_PITCH | FF_DONTCARE, face);
}

static int fix_raw(FIXED f) { return ((int)f.value << 16) | (int)f.fract; }

static void dump_outline(HDC dc, FILE *o, int code) {
  GLYPHMETRICS gm;
  MAT2 m = {{0, 1}, {0, 0}, {0, 0}, {0, 1}};
  DWORD n = GetGlyphOutlineW(dc, (UINT)code, GGO_NATIVE, &gm, 0, NULL, &m);
  if (n == GDI_ERROR) { fprintf(o, "G %d ERR\n", code); return; }
  unsigned char *buf = (unsigned char *)malloc(n ? n : 1);
  if (n) GetGlyphOutlineW(dc, (UINT)code, GGO_NATIVE, &gm, n, buf, &m);
  fprintf(o, "G %d adv %d %d box %u %u org %d %d\n", code, gm.gmCellIncX, gm.gmCellIncY, gm.gmBlackBoxX, gm.gmBlackBoxY, gm.gmptGlyphOrigin.x, gm.gmptGlyphOrigin.y);
  unsigned char *p = buf, *end = buf + n;
  while (p < end) {
    TTPOLYGONHEADER *h = (TTPOLYGONHEADER *)p;
    fprintf(o, "H %d %d\n", fix_raw(h->pfxStart.x), fix_raw(h->pfxStart.y));
    unsigned char *q = p + sizeof(TTPOLYGONHEADER), *qe = p + h->cb;
    while (q < qe) {
      TTPOLYCURVE *c = (TTPOLYCURVE *)q;
      for (int i = 0; i < c->cpfx; i++) fprintf(o, "%c %d %d\n", c->wType == TT_PRIM_LINE ? 'L' : 'Q', fix_raw(c->apfx[i].x), fix_raw(c->apfx[i].y));
      q += sizeof(WORD) * 2 + sizeof(POINTFX) * c->cpfx;
    }
    p += h->cb;
  }
  free(buf);
}

static unsigned parse_hex(const char *s) { return (unsigned)strtoul(s, NULL, 16); }

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: glyphs <outdir> <face> <weight> <px> <quality> [fg bg ...] | <outdir> --blend <quality>\n"); return 2; }
  const char *outdir = argv[1];
  HDC dc = CreateCompatibleDC(NULL);
  if (!strcmp(argv[2], "--settings")) {
    UINT on = 0, type = 0, contrast = 0, orient = 0;
    SystemParametersInfoW(SPI_GETFONTSMOOTHING, 0, &on, 0);
    SystemParametersInfoW(SPI_GETFONTSMOOTHINGTYPE, 0, &type, 0);
    SystemParametersInfoW(SPI_GETFONTSMOOTHINGCONTRAST, 0, &contrast, 0);
    SystemParametersInfoW(SPI_GETFONTSMOOTHINGORIENTATION, 0, &orient, 0);
    printf("SPI_GETFONTSMOOTHING %u\nSPI_GETFONTSMOOTHINGTYPE %u (1 standard, 2 ClearType)\nSPI_GETFONTSMOOTHINGCONTRAST %u\nSPI_GETFONTSMOOTHINGORIENTATION %u (0 BGR, 1 RGB)\n", on, type, contrast, orient);
    NONCLIENTMETRICSW ncm = { sizeof ncm };
    SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof ncm, &ncm, 0);
    LOGFONTW *l = &ncm.lfMessageFont;
    printf("lfMessageFont %ls height %ld weight %ld quality %d charset %d pitch %d\n", l->lfFaceName, l->lfHeight, l->lfWeight, l->lfQuality, l->lfCharSet, l->lfPitchAndFamily);
    l = &ncm.lfCaptionFont;
    printf("lfCaptionFont %ls height %ld weight %ld quality %d\n", l->lfFaceName, l->lfHeight, l->lfWeight, l->lfQuality);
    printf("LOGPIXELSX %d\n", GetDeviceCaps(dc, LOGPIXELSX));
    return 0;
  }
  if (!strcmp(argv[2], "--blend")) {
    int quality = argc > 3 ? atoi(argv[3]) : 5;
    HFONT f = make_font(L"Segoe UI", 400, 24, quality);
    SelectObject(dc, f);
    int steps = 17, cw = 28, ch = 36;
    int w = cw * steps, h = ch * steps;
    BITMAPINFO bi = {0};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER); bi.bmiHeader.biWidth = w; bi.bmiHeader.biHeight = -h; bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
    unsigned *bits; HBITMAP bmp = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, (void **)&bits, NULL, 0);
    SelectObject(dc, bmp);
    SetBkMode(dc, TRANSPARENT);
    for (int fy = 0; fy < steps; fy++) for (int bx = 0; bx < steps; bx++) {
      int fg = fy * 16 > 255 ? 255 : fy * 16, bg = bx * 16 > 255 ? 255 : bx * 16;
      RECT r = {bx * cw, fy * ch, (bx + 1) * cw, (fy + 1) * ch};
      HBRUSH br = CreateSolidBrush(RGB(bg, bg, bg)); FillRect(dc, &r, br); DeleteObject(br);
      SetTextColor(dc, RGB(fg, fg, fg));
      TextOutW(dc, bx * cw + 4, fy * ch + 2, L"Wo", 2);
    }
    char path[1024]; snprintf(path, sizeof path, "%s/blend.q%d.bgra", outdir, quality);
    FILE *o = fopen(path, "wb"); int hdr[6] = {w, h, cw, ch, steps, 16}; fwrite(hdr, 4, 6, o); fwrite(bits, 4, (size_t)w * h, o); fclose(o);
    return 0;
  }
  if (argc < 6) return 2;
  wchar_t face[64]; MultiByteToWideChar(CP_ACP, 0, argv[2], -1, face, 64);
  int weight = atoi(argv[3]), px = atoi(argv[4]), quality = atoi(argv[5]);
  HFONT f = make_font(face, weight, px, quality);
  HFONT old = (HFONT)SelectObject(dc, f);
  wchar_t got[64]; GetTextFaceW(dc, 64, got);
  TEXTMETRICW tm; GetTextMetricsW(dc, &tm);
  char tag[128]; snprintf(tag, sizeof tag, "%s-%d-%d-q%d", argv[2], weight, px, quality);
  for (char *c = tag; *c; c++) if (*c == ' ') *c = '_';
  char path[1024]; snprintf(path, sizeof path, "%s/%s.outline.txt", outdir, tag);
  FILE *o = fopen(path, "wb");
  fprintf(o, "FONT %ls weight %d px %d quality %d ascent %ld descent %ld height %ld\n", got, weight, px, quality, tm.tmAscent, tm.tmDescent, tm.tmHeight);
  int maxadv = 0;
  for (int code = 32; code < 256; code++) {
    dump_outline(dc, o, code);
    int wv = 0; GetCharWidth32W(dc, code, code, &wv);
    ABC abc; GetCharABCWidthsW(dc, code, code, &abc);
    fprintf(o, "W %d %d %d %d\n", wv, abc.abcA, abc.abcB, abc.abcC);
    if (wv > maxadv) maxadv = wv;
  }
  fclose(o);
  int pad = 6, cw = maxadv + 2 * pad, ch = tm.tmHeight + 2 * pad, cols = 16, rows = 14;
  int w = cw * cols, h = ch * rows;
  BITMAPINFO bi = {0};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER); bi.bmiHeader.biWidth = w; bi.bmiHeader.biHeight = -h; bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
  unsigned *bits; HBITMAP bmp = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, (void **)&bits, NULL, 0);
  SelectObject(dc, bmp);
  SetBkMode(dc, TRANSPARENT);
  int pairs = (argc - 6) / 2; if (pairs == 0) pairs = 1;
  for (int k = 0; k < pairs; k++) {
    unsigned fg = 0x000000, bg = 0xFFFFFF;
    char fgs[16] = "000000", bgs[16] = "FFFFFF";
    if (argc > 6) { fg = parse_hex(argv[6 + 2 * k]); bg = parse_hex(argv[7 + 2 * k]); snprintf(fgs, sizeof fgs, "%s", argv[6 + 2 * k]); snprintf(bgs, sizeof bgs, "%s", argv[7 + 2 * k]); }
    RECT all = {0, 0, w, h};
    HBRUSH br = CreateSolidBrush(RGB((bg >> 16) & 255, (bg >> 8) & 255, bg & 255)); FillRect(dc, &all, br); DeleteObject(br);
    SetTextColor(dc, RGB((fg >> 16) & 255, (fg >> 8) & 255, fg & 255));
    for (int code = 32; code < 256; code++) {
      int i = code - 32; wchar_t ch1 = (wchar_t)code;
      TextOutW(dc, (i % cols) * cw + pad, (i / cols) * ch + pad, &ch1, 1);
    }
    GdiFlush();
    snprintf(path, sizeof path, "%s/%s.%s-%s.bgra", outdir, tag, fgs, bgs);
    FILE *b = fopen(path, "wb"); int hdr[6] = {w, h, cw, ch, tm.tmAscent, pad}; fwrite(hdr, 4, 6, b); fwrite(bits, 4, (size_t)w * h, b); fclose(b);
  }
  SelectObject(dc, old);
  return 0;
}
