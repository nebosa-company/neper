/* Native Win32 control gallery: renders the standard Windows controls in every state, light and dark, and saves each state with PrintWindow.
   No screen access, no real mouse or keyboard: states come from posted/sent messages, and "hot" looks from the pointer hook (scripts\v3_hook\v3hook.dll,
   loaded INTO THIS PROCESS) that fakes GetCursorPos/WindowFromPoint/GetKeyState/TrackMouseEvent. See README.md.
   usage: gallery.exe <outdir> <light|dark> <100|150> [only-substring]   -> <outdir>\<theme>\<name>@<scale>.bmp + index-<theme>-<dpi>.tsv */
#define WINVER 0x0A00
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <commctrl.h>
#include <uxtheme.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef PW_RENDERFULLCONTENT
#define PW_RENDERFULLCONTENT 2
#endif
#ifndef BS_SPLITBUTTON
#define BS_SPLITBUTTON 0x0000000C
#endif
#ifndef BCM_SETIMAGELIST
#define BCM_SETIMAGELIST 0x1602
#endif

typedef struct { volatile LONG x, y, enabled, lbtn, nCursor, nPatched, nWfp, nKey, ready, nExe, nGpa, lastWfp, lastPtX, lastPtY, nTme, tmeAll; } SH;
static SH *sh;

static int g_dark, g_dpi = 96;
static const char *g_out, *g_only, *g_theme;
static FILE *g_idx;
static HFONT g_font;
static HBRUSH g_bgbr;
static COLORREF g_bg, g_fg;
static HWND g_stage;
static int g_cur_dark_menu;
#define S(x) MulDiv((x), g_dpi, 96)
#define MAXC 64
static struct { HWND h; } g_ctl[MAXC];
static int g_nctl;
static HWND g_main, g_base;   /* the control the pointer helpers and the rects refer to by default */

/* ---- uxtheme dark-mode ordinals (undocumented; ordinals are the same on x86 and x64) ---- */
static void (WINAPI *pAllowDarkWin)(HWND, BOOL);            /* 133 */
static int (WINAPI *pSetPrefMode)(int);                     /* 135: 0 default, 1 AllowDark, 2 ForceDark, 3 ForceLight */
static void (WINAPI *pFlushMenuThemes)(void);               /* 136 */
static void (WINAPI *pRefreshPolicy)(void);                 /* 104 */
static UINT (WINAPI *pGetDpiForWindow)(HWND);
static BOOL (WINAPI *pSysParamsForDpi)(UINT, UINT, PVOID, UINT, UINT);

static void pump(int ms) {
  DWORD t = GetTickCount();
  do {
    MSG m;
    while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&m); DispatchMessageW(&m); }
    Sleep(8);
  } while (GetTickCount() - t < (DWORD)ms);
}

/* ---- fake pointer ---- */
static void fake_at(int x, int y) { sh->x = x; sh->y = y; sh->enabled = 1; }
static void fake_away(void) { sh->lbtn = 0; fake_at(-5000, -5000); }
static void lbtn(int d) { sh->lbtn = d; }
static POINT scr(HWND h, int lx, int ly) { POINT p = { S(lx), S(ly) }; ClientToScreen(h, &p); return p; }
/* pointer at logical (lx,ly) in the client area of h: fake pointer, then WM_MOUSEMOVE to h */
static void hover_px(HWND h, int px, int py) {   /* physical client coordinates */
  POINT p = { px, py }; ClientToScreen(h, &p); fake_at(p.x, p.y);
  PostMessageW(h, WM_MOUSEMOVE, 0, MAKELPARAM(px, py)); pump(40);
  SendMessageW(h, WM_MOUSEMOVE, 0, MAKELPARAM(px, py)); pump(220);
}
static void hover(HWND h, int lx, int ly) { hover_px(h, S(lx), S(ly)); }
/* pointer at a fraction (0..1000) of the client rectangle of h */
static void hover_f(HWND h, int fx, int fy) { RECT r; GetClientRect(h, &r); hover_px(h, r.right * fx / 1000, r.bottom * fy / 1000); }
static void unhover(HWND h) { fake_away(); if (h) SendMessageW(h, WM_MOUSELEAVE, 0, 0); pump(220); }
static void press_msg(HWND h, int lx, int ly) { lbtn(1); SendMessageW(h, WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(S(lx), S(ly))); }
static void release_msg(HWND h, int lx, int ly) { lbtn(0); SendMessageW(h, WM_LBUTTONUP, 0, MAKELPARAM(S(lx), S(ly))); }

/* ---- dark theme ---- */
static const wchar_t *dark_theme_for(const wchar_t *cls) {
  if (!wcsicmp(cls, L"Edit") || !wcsicmp(cls, L"ComboBox")) return L"DarkMode_CFD";
  if (!wcsicmp(cls, L"SysHeader32")) return L"DarkMode_ItemsView";   /* list view itself: DarkMode_Explorer (dark scroll bars), its header: ItemsView */
  /* no dark theme for these: a theme makes the highlight of list boxes (and the combo drop list) white on white, and the progress fill white */
  if (!wcsicmp(cls, L"msctls_progress32") || !wcsicmp(cls, L"ListBox")) return NULL;
  return L"DarkMode_Explorer";
}
static void dark_one(HWND h, const wchar_t *theme) {
  if (pAllowDarkWin) pAllowDarkWin(h, TRUE);
  SetWindowTheme(h, theme, NULL);
  SendMessageW(h, WM_THEMECHANGED, 0, 0);
}
static void dark_ctl(HWND h) {
  wchar_t cls[64]; GetClassNameW(h, cls, 64);
  { const wchar_t *th = dark_theme_for(cls); if (th) dark_one(h, th); else if (pAllowDarkWin) pAllowDarkWin(h, TRUE); }
  if (!wcsicmp(cls, L"ComboBox")) {
    COMBOBOXINFO ci = { sizeof ci }; GetComboBoxInfo(h, &ci);
    if (ci.hwndList && pAllowDarkWin) pAllowDarkWin(ci.hwndList, TRUE);
    if (ci.hwndItem) dark_one(ci.hwndItem, L"DarkMode_CFD");
  }
  if (!wcsicmp(cls, L"SysListView32")) {
    ListView_SetBkColor(h, g_bg); ListView_SetTextBkColor(h, g_bg); ListView_SetTextColor(h, g_fg);
    HWND hd = ListView_GetHeader(h); if (hd) dark_one(hd, L"DarkMode_ItemsView");
  }
  if (!wcsicmp(cls, L"SysTreeView32")) { TreeView_SetBkColor(h, g_bg); TreeView_SetTextColor(h, g_fg); }
}
static void light_ctl(HWND h) {   /* Explorer style list/tree views, as every modern Windows app uses */
  wchar_t cls[64]; GetClassNameW(h, cls, 64);
  if (!wcsicmp(cls, L"SysListView32") || !wcsicmp(cls, L"SysTreeView32")) SetWindowTheme(h, L"Explorer", NULL);
}
static void dark_top(HWND h) {
  BOOL d = TRUE; DwmSetWindowAttribute(h, DWMWA_USE_IMMERSIVE_DARK_MODE, &d, sizeof d);
  if (pAllowDarkWin) pAllowDarkWin(h, TRUE);
}
/* every top-level window of this thread (stage, message box, task dialog, popup menu, tooltip) gets the dark caption */
static LRESULT CALLBACK cbt(int code, WPARAM w, LPARAM l) {
  if (code == HCBT_CREATEWND && g_dark) {
    HWND h = (HWND)w; wchar_t cls[64]; GetClassNameW(h, cls, 64);
    if (!(((CBT_CREATEWNDW *)l)->lpcs->style & WS_CHILD)) dark_top(h);   /* owned dialogs too */
  }
  return CallNextHookEx(NULL, code, w, l);
}

/* ---- stage window ---- */
typedef LRESULT (*NOTIFYFN)(NMHDR *, LPARAM);
static NOTIFYFN g_notify;
static LRESULT CALLBACK stage_proc(HWND h, UINT m, WPARAM w, LPARAM l) {
  switch (m) {
  case WM_CTLCOLORSTATIC: case WM_CTLCOLOREDIT: case WM_CTLCOLORLISTBOX: case WM_CTLCOLORBTN: case WM_CTLCOLORDLG:
    if (g_dark) {
      HDC dc = (HDC)w; HWND c = (HWND)l;
      SetTextColor(dc, (c && !IsWindowEnabled(c)) ? RGB(109, 109, 109) : g_fg);
      SetBkColor(dc, g_bg); SetBkMode(dc, OPAQUE);
      return (LRESULT)g_bgbr;
    }
    break;
  case WM_NOTIFY: if (g_notify) { LRESULT r = g_notify((NMHDR *)l, l); if (r) return r; } break;
  case WM_SYSCOMMAND: { UINT c = (UINT)(w & 0xFFF0); if (c == SC_CLOSE || c == SC_MINIMIZE || c == SC_MAXIMIZE || c == SC_RESTORE) return 0; } break;
  case WM_CLOSE: return 0;
  }
  return DefWindowProcW(h, m, w, l);
}
static void ensure_class(void) {
  static int done; if (done) return; done = 1;
  WNDCLASSW wc = { 0 }; wc.lpfnWndProc = stage_proc; wc.hInstance = GetModuleHandleW(NULL); wc.lpszClassName = L"GStage";
  wc.hbrBackground = g_dark ? g_bgbr : GetSysColorBrush(COLOR_BTNFACE); wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  RegisterClassW(&wc);
}
/* client size w x h (logical). style 0 = borderless popup; otherwise a captioned window whose CLIENT is w x h. */
static void begin_w(int w, int h, DWORD style, DWORD ex, const wchar_t *title, HMENU menu) {
  ensure_class();
  RECT r = { 0, 0, S(w), S(h) };
  if (style) { typedef BOOL (WINAPI * ADJ)(LPRECT, DWORD, BOOL, DWORD, UINT); ADJ a = (ADJ)GetProcAddress(GetModuleHandleW(L"user32"), "AdjustWindowRectExForDpi");
    if (a) a(&r, style, menu != NULL, ex, g_dpi); else AdjustWindowRectEx(&r, style, menu != NULL, ex); }
  g_stage = CreateWindowExW(ex, L"GStage", title ? title : L"", style ? style : WS_POPUP, S(60), S(60), r.right - r.left, r.bottom - r.top, NULL, menu, GetModuleHandleW(NULL), NULL);
  if (g_dark) dark_top(g_stage);
  g_nctl = 0; g_main = NULL; g_notify = NULL; sh->tmeAll = 1; fake_away();
  ShowWindow(g_stage, SW_SHOW); SetActiveWindow(g_stage);
  SendMessageW(g_stage, WM_NCACTIVATE, TRUE, 0);
  pump(60);
}
static void begin(int w, int h) { begin_w(w, h, 0, 0, NULL, NULL); }
static void end(void) { fake_away(); if (g_stage) DestroyWindow(g_stage); g_stage = NULL; pump(30); }
static HWND ctl(const wchar_t *cls, const wchar_t *text, DWORD style, DWORD ex, int x, int y, int w, int h) {
  HWND c = CreateWindowExW(ex, cls, text, WS_CHILD | WS_VISIBLE | style, S(x), S(y), S(w), S(h), g_stage, NULL, GetModuleHandleW(NULL), NULL);
  SendMessageW(c, WM_SETFONT, (WPARAM)g_font, TRUE);
  if (g_dark) dark_ctl(c); else light_ctl(c);
  if (g_nctl < MAXC) g_ctl[g_nctl++].h = c;
  if (!g_main) g_main = c;
  return c;
}
static void kill(HWND c) { for (int i = 0; i < g_nctl; i++) if (g_ctl[i].h == c) { g_ctl[i] = g_ctl[--g_nctl]; break; } if (g_main == c) g_main = NULL; DestroyWindow(c); }
/* focus cues + focus: the stage is the thread's active window, UI cues are shown as after a key press */
static void focus(HWND c) {
  SetActiveWindow(g_stage); SendMessageW(g_stage, WM_NCACTIVATE, TRUE, 0);
  SendMessageW(g_stage, WM_CHANGEUISTATE, MAKEWPARAM(UIS_CLEAR, UISF_HIDEFOCUS | UISF_HIDEACCEL), 0);
  SetFocus(c); pump(120);
}
static void unfocus(void) { SetFocus(g_stage); pump(60); }
static void enable(HWND c, BOOL e) { EnableWindow(c, e); pump(60); }

/* ---- capture ---- */
/* visible rectangle of a top-level window: GetWindowRect minus the invisible resize borders DWM adds to framed windows (PrintWindow paints them black) */
static void vrect(HWND w, RECT *r) {
  GetWindowRect(w, r);
  if (!(GetWindowLongW(w, GWL_STYLE) & WS_THICKFRAME)) return;
  RECT e, p; if (DwmGetWindowAttribute(w, 9, &e, sizeof e) != S_OK) return;
  typedef HANDLE (WINAPI * TD)(HANDLE); TD td = (TD)GetProcAddress(GetModuleHandleW(L"user32"), "SetThreadDpiAwarenessContext");
  HANDLE old = td ? td((HANDLE)-4) : NULL; GetWindowRect(w, &p); if (td) td(old);   /* physical window rect, same space as the DWM bounds */
  int pw = p.right - p.left, ph = p.bottom - p.top, lw = r->right - r->left, lh = r->bottom - r->top; if (pw <= 0 || ph <= 0) return;
  RECT n = { r->left + (e.left - p.left) * lw / pw, r->top + (e.top - p.top) * lh / ph, r->right - (p.right - e.right) * lw / pw, r->bottom - (p.bottom - e.bottom) * lh / ph };
  *r = n;
}
static void blit_win(HDC cdc, HWND w, int ox, int oy, int cw, int ch) {
  RECT full, r; GetWindowRect(w, &full); vrect(w, &r); int ww = full.right - full.left, hh = full.bottom - full.top;
  BITMAPINFO bi = { { sizeof(BITMAPINFOHEADER), ww, -hh, 1, 32, BI_RGB } }; void *bits;
  HDC m = CreateCompatibleDC(cdc); HBITMAP b = CreateDIBSection(cdc, &bi, DIB_RGB_COLORS, &bits, NULL, 0); HGDIOBJ o = SelectObject(m, b);
  PatBlt(m, 0, 0, ww, hh, BLACKNESS);
  PrintWindow(w, m, PW_RENDERFULLCONTENT);
  BitBlt(cdc, r.left - ox, r.top - oy, r.right - r.left, r.bottom - r.top, m, r.left - full.left, r.top - full.top, SRCCOPY);
  SelectObject(m, o); DeleteObject(b); DeleteDC(m);
}
static void json_rect(char *buf, size_t n, HWND h, int ox, int oy) {
  RECT r; GetWindowRect(h, &r); if (!GetParent(h)) vrect(h, &r); wchar_t cls[64], tx[64]; GetClassNameW(h, cls, 64); GetWindowTextW(h, tx, 64);
  char c8[64], t8[64]; WideCharToMultiByte(CP_UTF8, 0, cls, -1, c8, 64, 0, 0); WideCharToMultiByte(CP_UTF8, 0, tx, -1, t8, 64, 0, 0);
  for (char *p = t8; *p; p++) if ((unsigned char)*p < 32 || *p == 34 || *p == 92) *p = ' ';
  size_t l = strlen(buf);
  snprintf(buf + l, n - l, "%s{\"class\":\"%s\",\"text\":\"%s\",\"x\":%d,\"y\":%d,\"w\":%d,\"h\":%d}", l ? "," : "", c8, t8, (int)r.left - ox, (int)r.top - oy, (int)(r.right - r.left), (int)(r.bottom - r.top));
}
/* save the stage (+ extra top-level popup windows) as <out>\<theme>\<name>@<1x|1.5x>.bmp and one index line */
static void snapx(const char *name, HWND *extra, int nextra) {
  if (g_only && !strstr(name, g_only)) return;
  { HWND rb = g_base ? g_base : g_stage; pump(60); RedrawWindow(rb, NULL, NULL, RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW | RDW_ERASE); pump(160); }
  HWND base = g_base ? g_base : g_stage; RECT u; vrect(base, &u);
  for (int i = 0; i < nextra; i++) if (extra[i] && IsWindow(extra[i])) { RECT r; vrect(extra[i], &r); UnionRect(&u, &u, &r); }
  int cw = u.right - u.left, ch = u.bottom - u.top;
  HDC sd = GetDC(NULL); HDC m = CreateCompatibleDC(sd);
  BITMAPINFO bi = { { sizeof(BITMAPINFOHEADER), cw, -ch, 1, 24, BI_RGB } }; void *bits;
  HBITMAP b = CreateDIBSection(sd, &bi, DIB_RGB_COLORS, &bits, NULL, 0); HGDIOBJ o = SelectObject(m, b);
  HBRUSH fill = CreateSolidBrush(g_dark ? g_bg : GetSysColor(COLOR_BTNFACE)); RECT all = { 0, 0, cw, ch }; FillRect(m, &all, fill); DeleteObject(fill);
  blit_win(m, base, u.left, u.top, cw, ch);
  for (int i = 0; i < nextra; i++) if (extra[i] && IsWindow(extra[i])) blit_win(m, extra[i], u.left, u.top, cw, ch);
  char path[600], rects[4096] = "";
  snprintf(path, sizeof path, "%s\\%s\\%s@%s.bmp", g_out, g_theme, name, g_dpi == 96 ? "1x" : g_dpi == 144 ? "1.5x" : "2x");
  FILE *f = fopen(path, "wb");
  if (f) {
    int stride = (cw * 3 + 3) & ~3; BITMAPFILEHEADER fh = { 0x4D42, 54 + stride * ch, 0, 0, 54 };
    BITMAPINFOHEADER ih = { sizeof ih, cw, -ch, 1, 24, BI_RGB, stride * ch };
    fwrite(&fh, 1, 14, f); fwrite(&ih, 1, 40, f); fwrite(bits, 1, stride * ch, f); fclose(f);
  }
  for (int i = 0; i < g_nctl; i++) if (IsWindow(g_ctl[i].h) && IsWindowVisible(g_ctl[i].h)) json_rect(rects, sizeof rects, g_ctl[i].h, u.left, u.top);
  for (int i = 0; i < nextra; i++) if (extra[i] && IsWindow(extra[i])) json_rect(rects, sizeof rects, extra[i], u.left, u.top);
  fprintf(g_idx, "%s\t%d\t%d\t%d\t[%s]\n", name, cw, ch, g_dpi, rects); fflush(g_idx);
  SelectObject(m, o); DeleteObject(b); DeleteDC(m); ReleaseDC(NULL, sd);
  printf("  %s (%dx%d)\n", name, cw, ch);
}
static void snap(const char *name) { snapx(name, NULL, 0); }

/* a timer that also fires inside modal loops (menus, scroll bar tracking, task dialogs): step callback, called every `ms` until it returns 0 */
typedef int (*STEPFN)(int step);
static STEPFN g_step; static int g_stepn, g_stepdone; static UINT_PTR g_stepid;
static VOID CALLBACK step_tick(HWND h, UINT m, UINT_PTR id, DWORD t) {
  static int busy; if (!g_step || busy) return;
  busy = 1; int more = g_step(g_stepn++); busy = 0;
  if (!more) { KillTimer(NULL, g_stepid); g_step = NULL; g_stepdone = 1; }
}
static void stepper(STEPFN f, int ms) { g_step = f; g_stepn = 0; g_stepdone = 0; g_stepid = SetTimer(NULL, 0, ms, step_tick); }
static void wait_steps(void) { DWORD t = GetTickCount(); while (!g_stepdone && GetTickCount() - t < 20000) pump(20); if (!g_stepdone && g_step) { KillTimer(NULL, g_stepid); g_step = NULL; } pump(60); }

/* ================= cases ================= */
static const wchar_t *L1[] = { L"Alpha", L"Bravo", L"Charlie", L"Delta", L"Echo", L"Foxtrot", L"Golf", L"Hotel", L"India", L"Juliet" };
static HICON small_icon(LPCWSTR id) { return (HICON)LoadImageW(NULL, id, IMAGE_ICON, S(16), S(16), LR_SHARED); }
static HIMAGELIST icons16(void) {
  HIMAGELIST il = ImageList_Create(S(16), S(16), ILC_COLOR32 | ILC_MASK, 6, 0);
  LPCWSTR ids[6] = { MAKEINTRESOURCEW(32516), MAKEINTRESOURCEW(32515), MAKEINTRESOURCEW(32513), MAKEINTRESOURCEW(32514), MAKEINTRESOURCEW(32518), MAKEINTRESOURCEW(32512) };
  for (int i = 0; i < 6; i++) ImageList_AddIcon(il, small_icon(ids[i]));
  return il;
}
static void cb_strings(HWND c, int n) { for (int i = 0; i < n; i++) SendMessageW(c, CB_ADDSTRING, 0, (LPARAM)L1[i]); }
static void lb_strings(HWND c, int n) { for (int i = 0; i < n; i++) SendMessageW(c, LB_ADDSTRING, 0, (LPARAM)L1[i]); }

static void case_button(void) {
  begin(150, 56);
  HWND b = ctl(L"Button", L"Button", WS_TABSTOP | BS_PUSHBUTTON, 0, 20, 12, 110, 32);
  snap("button-rest");
  SendMessageW(b, BM_SETSTYLE, BS_DEFPUSHBUTTON, TRUE); pump(60); snap("button-default");
  hover(b, 55, 16); snap("button-default-hover"); unhover(b);
  SendMessageW(b, BM_SETSTATE, TRUE, 0); pump(80); snap("button-default-pressed"); SendMessageW(b, BM_SETSTATE, FALSE, 0);
  SendMessageW(b, BM_SETSTYLE, BS_PUSHBUTTON, TRUE); pump(60);
  hover(b, 55, 16); snap("button-hover"); unhover(b);
  SendMessageW(b, BM_SETSTATE, TRUE, 0); pump(80); snap("button-pressed"); SendMessageW(b, BM_SETSTATE, FALSE, 0);
  pump(60);
  hover(b, 55, 16); press_msg(b, 55, 16); pump(150); snap("button-hover-pressed"); release_msg(b, 55, 16); unhover(b);
  focus(b); snap("button-focus");
  SendMessageW(b, BM_SETSTYLE, BS_DEFPUSHBUTTON, TRUE); pump(60); snap("button-default-focus"); SendMessageW(b, BM_SETSTYLE, BS_PUSHBUTTON, TRUE); unfocus();
  enable(b, FALSE); snap("button-disabled");
  end();

  begin(170, 56);
  b = ctl(L"Button", L"Open", WS_TABSTOP | BS_PUSHBUTTON, 0, 20, 12, 130, 32);
  HIMAGELIST il = ImageList_Create(S(16), S(16), ILC_COLOR32 | ILC_MASK, 1, 0); ImageList_AddIcon(il, small_icon(MAKEINTRESOURCEW(32516)));
  BUTTON_IMAGELIST bil = { il, { 8, 0, 0, 0 }, BUTTON_IMAGELIST_ALIGN_LEFT };
  SendMessageW(b, BCM_SETIMAGELIST, 0, (LPARAM)&bil); pump(60);
  snap("button-icon"); hover(b, 65, 16); snap("button-icon-hover"); unhover(b);
  enable(b, FALSE); snap("button-icon-disabled");
  end();

  begin(190, 56);
  b = ctl(L"Button", L"Save", WS_TABSTOP | BS_SPLITBUTTON, 0, 20, 12, 150, 32);
  snap("button-split"); hover(b, 50, 16); snap("button-split-hover-main"); unhover(b);
  hover(b, 138, 16); snap("button-split-hover-arrow"); unhover(b);
  SendMessageW(b, BM_SETSTATE, TRUE, 0); pump(80); snap("button-split-pressed"); SendMessageW(b, BM_SETSTATE, FALSE, 0);
  enable(b, FALSE); snap("button-split-disabled");
  end();
}

/* kind: BS_AUTOCHECKBOX / BS_AUTO3STATE (checkbox: unchecked, checked, indeterminate) or BS_AUTORADIOBUTTON (unchecked, checked) */
static void case_check_like(const char *base, DWORD style, int nstates, const char **sn, const int *sv) {
  char nm[96];
  for (int s = 0; s < nstates; s++) {
    begin(170, 40);
    HWND b = ctl(L"Button", L"Sample label", WS_TABSTOP | style, 0, 16, 9, 140, 22);
    SendMessageW(b, BM_SETCHECK, sv[s], 0); pump(60);
    snprintf(nm, sizeof nm, "%s-%s-rest", base, sn[s]); snap(nm);
    hover(b, 20, 11); snprintf(nm, sizeof nm, "%s-%s-hover", base, sn[s]); snap(nm); unhover(b);
    SendMessageW(b, BM_SETSTATE, TRUE, 0); pump(80); snprintf(nm, sizeof nm, "%s-%s-pressed", base, sn[s]); snap(nm); SendMessageW(b, BM_SETSTATE, FALSE, 0); pump(60);
    focus(b); snprintf(nm, sizeof nm, "%s-%s-focus", base, sn[s]); snap(nm); unfocus();
    enable(b, FALSE); snprintf(nm, sizeof nm, "%s-%s-disabled", base, sn[s]); snap(nm);
    end();
  }
}
static void case_checkbox(void) { const char *n[] = { "unchecked", "checked", "indeterminate" }; const int v[] = { 0, 1, 2 }; case_check_like("checkbox", BS_AUTO3STATE, 3, n, v); }
static void case_radio(void) { const char *n[] = { "unchecked", "checked" }; const int v[] = { 0, 1 }; case_check_like("radio", BS_AUTORADIOBUTTON, 2, n, v); }

static void case_groupbox(void) {
  begin(200, 90);
  HWND g = ctl(L"Button", L"Group", BS_GROUPBOX, 0, 12, 8, 176, 72);
  ctl(L"Static", L"Inside the group", 0, 0, 28, 36, 130, 20);
  snap("groupbox-rest"); enable(g, FALSE); snap("groupbox-disabled");
  end();
}

static void case_edit(void) {
  begin(190, 56);
  HWND e = ctl(L"Edit", L"Text value", WS_TABSTOP | ES_AUTOHSCROLL, WS_EX_CLIENTEDGE, 20, 14, 150, 24);
  snap("edit-rest"); hover(e, 60, 10); snap("edit-hover"); unhover(e);
  focus(e); SendMessageW(e, EM_SETSEL, 10, 10); pump(100); snap("edit-focus");
  SendMessageW(e, EM_SETSEL, 0, 4); pump(100); snap("edit-selected");
  SendMessageW(e, EM_SETSEL, 0, 0); unfocus();
  SendMessageW(e, EM_SETREADONLY, TRUE, 0); pump(60); snap("edit-readonly"); SendMessageW(e, EM_SETREADONLY, FALSE, 0);
  enable(e, FALSE); snap("edit-disabled");
  end();

  begin(190, 56);
  e = ctl(L"Edit", L"secret", WS_TABSTOP | ES_PASSWORD | ES_AUTOHSCROLL, WS_EX_CLIENTEDGE, 20, 14, 150, 24);
  snap("edit-password"); end();

  begin(200, 110);
  e = ctl(L"Edit", L"Line one\r\nLine two\r\nLine three\r\nLine four\r\nLine five\r\nLine six\r\nLine seven\r\nLine eight", WS_TABSTOP | ES_MULTILINE | WS_VSCROLL | ES_AUTOVSCROLL, WS_EX_CLIENTEDGE, 16, 10, 168, 90);
  snap("edit-multiline-vscroll"); end();
}

static void case_label(void) {
  begin(190, 70);
  HWND s = ctl(L"Static", L"Static text label", SS_LEFT, 0, 20, 10, 150, 20);
  snap("label-rest"); enable(s, FALSE); snap("label-disabled");
  end();
}

/* ---- press with a modal tracking loop: post the button down, snap from a timer inside the loop, then release ---- */
static const char *g_pname; static HWND g_pex[4]; static int g_pnex; static HWND g_ph;
static int press_step(int s) {
  snapx(g_pname, g_pex, g_pnex); lbtn(0);
  PostMessageW(g_ph, WM_LBUTTONUP, 0, 0); PostMessageW(g_ph, WM_CANCELMODE, 0, 0); return 0;
}
static void press_snap(HWND h, int px, int py, const char *name) {
  POINT p = { px, py }; ClientToScreen(h, &p); fake_at(p.x, p.y);
  PostMessageW(h, WM_MOUSEMOVE, 0, MAKELPARAM(px, py)); pump(60);
  g_pname = name; g_ph = h; g_pnex = 0; lbtn(1);
  stepper(press_step, 350); PostMessageW(h, WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(px, py)); wait_steps();
  lbtn(0); SendMessageW(h, WM_CANCELMODE, 0, 0); pump(100);
}
static void press_f(HWND h, int fx, int fy, const char *name) { RECT r; GetClientRect(h, &r); press_snap(h, r.right * fx / 1000, r.bottom * fy / 1000, name); }

static void case_spin(void) {
  begin(150, 56);
  HWND e = ctl(L"Edit", L"5", WS_TABSTOP | ES_AUTOHSCROLL | ES_NUMBER, WS_EX_CLIENTEDGE, 20, 14, 90, 24);
  HWND u = ctl(UPDOWN_CLASSW, L"", UDS_SETBUDDYINT | UDS_ALIGNRIGHT | UDS_AUTOBUDDY | UDS_ARROWKEYS, 0, 0, 0, 0, 0);
  SendMessageW(u, UDM_SETBUDDY, (WPARAM)e, 0); SendMessageW(u, UDM_SETRANGE32, 0, 20); SendMessageW(u, UDM_SETPOS32, 0, 5); pump(80);
  snap("spin-rest");
  hover_f(u, 500, 250); snap("spin-hover-up"); unhover(u);
  hover_f(u, 500, 750); snap("spin-hover-down"); unhover(u);
  press_f(u, 500, 250, "spin-pressed-up"); unhover(u);
  press_f(u, 500, 750, "spin-pressed-down"); unhover(u);
  focus(e); snap("spin-focus"); unfocus();
  enable(u, FALSE); enable(e, FALSE); snap("spin-disabled");
  end();
}

static void case_combo(void) {
  for (int kind = 0; kind < 2; kind++) {   /* 0 = dropdown list, 1 = dropdown with edit */
    const char *k = kind ? "combo-edit" : "combo-list"; char nm[64];
    begin(190, 60);
    HWND c = ctl(L"ComboBox", L"", WS_TABSTOP | WS_VSCROLL | (kind ? CBS_DROPDOWN : CBS_DROPDOWNLIST), 0, 20, 14, 150, 200);
    cb_strings(c, 8); SendMessageW(c, CB_SETCURSEL, 1, 0); pump(60);
    snprintf(nm, sizeof nm, "%s-rest", k); snap(nm);
    hover(c, 60, 10); snprintf(nm, sizeof nm, "%s-hover", k); snap(nm); unhover(c);
    hover(c, 138, 10); snprintf(nm, sizeof nm, "%s-hover-arrow", k); snap(nm); unhover(c);
    focus(c); snprintf(nm, sizeof nm, "%s-focus", k); snap(nm);
    SendMessageW(c, CB_SHOWDROPDOWN, TRUE, 0); pump(250);
    COMBOBOXINFO ci = { sizeof ci }; GetComboBoxInfo(c, &ci); HWND lb = ci.hwndList; HWND ex[1] = { lb };
    snprintf(nm, sizeof nm, "%s-open", k); snapx(nm, ex, 1);
    hover_f(lb, 500, 500); snprintf(nm, sizeof nm, "%s-open-hover-row", k); snapx(nm, ex, 1);
    SendMessageW(c, CB_SHOWDROPDOWN, FALSE, 0); pump(150); unhover(NULL); unfocus();
    enable(c, FALSE); snprintf(nm, sizeof nm, "%s-disabled", k); snap(nm);
    end();
  }
}

static void case_listbox(void) {
  begin(150, 130);
  HWND l = ctl(L"ListBox", L"", WS_TABSTOP | WS_VSCROLL | LBS_NOINTEGRALHEIGHT | LBS_NOTIFY, WS_EX_CLIENTEDGE, 16, 10, 118, 110);
  lb_strings(l, 10); pump(60); snap("listbox-rest");
  SendMessageW(l, LB_SETCURSEL, 2, 0); focus(l); snap("listbox-selected-focused");
  unfocus(); snap("listbox-selected-unfocused");
  hover(l, 50, 70); snap("listbox-hover"); unhover(l);
  enable(l, FALSE); snap("listbox-disabled");
  end();
}

static HWND mk_lv(int x, int y, int w, int h, DWORD style, DWORD exs, int ncols, int nrows) {
  HWND l = ctl(WC_LISTVIEWW, L"", WS_TABSTOP | LVS_REPORT | LVS_SHOWSELALWAYS | style, WS_EX_CLIENTEDGE, x, y, w, h);
  ListView_SetExtendedListViewStyle(l, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | exs);
  static const wchar_t *cn[] = { L"Name", L"Size", L"Kind" }; static const wchar_t *kinds[] = { L"File", L"Folder", L"Image" };
  for (int i = 0; i < ncols; i++) { LVCOLUMNW c = { LVCF_TEXT | LVCF_WIDTH, 0, S(i == 0 ? 90 : 60), (LPWSTR)cn[i] }; SendMessageW(l, LVM_INSERTCOLUMNW, i, (LPARAM)&c); }
  for (int r = 0; r < nrows; r++) {
    LVITEMW it = { LVIF_TEXT, r, 0, 0, 0, (LPWSTR)L1[r % 10] }; SendMessageW(l, LVM_INSERTITEMW, 0, (LPARAM)&it);
    wchar_t sz[16]; swprintf(sz, 16, L"%d KB", 10 + r * 7);
    if (ncols > 1) { it.iSubItem = 1; it.pszText = sz; SendMessageW(l, LVM_SETITEMTEXTW, r, (LPARAM)&it); }
    if (ncols > 2) { it.iSubItem = 2; it.pszText = (LPWSTR)kinds[r % 3]; SendMessageW(l, LVM_SETITEMTEXTW, r, (LPARAM)&it); }
  }
  return l;
}
static void lv_select(HWND l, int i) { ListView_SetItemState(l, i, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED); }
static void case_checklist(void) {
  begin(190, 130);
  HWND l = mk_lv(16, 10, 158, 110, LVS_NOCOLUMNHEADER | LVS_SINGLESEL, LVS_EX_CHECKBOXES, 1, 8);
  ListView_SetColumnWidth(l, 0, S(120)); ListView_SetCheckState(l, 1, TRUE); ListView_SetCheckState(l, 3, TRUE); pump(60);
  snap("checklist-rest");
  hover(l, 60, 20); snap("checklist-hover"); unhover(l);
  lv_select(l, 1); focus(l); snap("checklist-selected-focused"); unfocus(); snap("checklist-selected-unfocused");
  enable(l, FALSE); snap("checklist-disabled");
  end();
}

static void case_tab(void) {
  begin(230, 120);
  HWND t = ctl(WC_TABCONTROLW, L"", WS_TABSTOP | WS_CLIPSIBLINGS, 0, 12, 10, 206, 100);
  static const wchar_t *tn[] = { L"General", L"View", L"Advanced" };
  for (int i = 0; i < 3; i++) { TCITEMW it = { TCIF_TEXT, 0, 0, (LPWSTR)tn[i] }; SendMessageW(t, TCM_INSERTITEMW, i, (LPARAM)&it); }
  pump(80); snap("tab-rest");
  RECT r; SendMessageW(t, TCM_GETITEMRECT, 1, (LPARAM)&r);
  hover_px(t, (r.left + r.right) / 2, (r.top + r.bottom) / 2); snap("tab-hot"); unhover(t);
  SendMessageW(t, TCM_SETCURSEL, 1, 0); pump(60); snap("tab-selected-second");
  hover_px(t, (r.left + r.right) / 2, (r.top + r.bottom) / 2); snap("tab-selected-hot"); unhover(t);
  focus(t); snap("tab-focus");
  unfocus(); enable(t, FALSE); snap("tab-disabled");
  end();
}

static void case_progress(void) {
  begin(210, 44);
  HWND p = ctl(PROGRESS_CLASSW, L"", 0, 0, 16, 14, 178, 16);
  SendMessageW(p, PBM_SETPOS, 0, 0); pump(60); snap("progress-empty");
  SendMessageW(p, PBM_SETPOS, 60, 0); pump(300); snap("progress-determinate");
  SendMessageW(p, PBM_SETSTATE, PBST_PAUSED, 0); pump(200); snap("progress-paused");
  SendMessageW(p, PBM_SETSTATE, PBST_ERROR, 0); pump(200); snap("progress-error");
  SendMessageW(p, PBM_SETSTATE, PBST_NORMAL, 0); SendMessageW(p, PBM_SETPOS, 100, 0); pump(300); snap("progress-full");
  enable(p, FALSE); snap("progress-disabled"); enable(p, TRUE);
  end();
  begin(210, 44);
  p = ctl(PROGRESS_CLASSW, L"", PBS_MARQUEE, 0, 16, 14, 178, 16);
  SendMessageW(p, PBM_SETMARQUEE, TRUE, 30); pump(500); snap("progress-marquee"); pump(300); snap("progress-marquee-later");
  end();
  begin(60, 150);
  p = ctl(PROGRESS_CLASSW, L"", PBS_VERTICAL, 0, 22, 10, 16, 130);
  SendMessageW(p, PBM_SETPOS, 60, 0); pump(300); snap("progress-vertical");
  end();
}

static void case_trackbar(void) {
  begin(230, 80);
  HWND t = ctl(TRACKBAR_CLASSW, L"", WS_TABSTOP | TBS_AUTOTICKS, 0, 16, 12, 198, 40);
  SendMessageW(t, TBM_SETRANGE, TRUE, MAKELONG(0, 10)); SendMessageW(t, TBM_SETPOS, TRUE, 4); pump(80);
  snap("trackbar-rest");
  RECT r; SendMessageW(t, TBM_GETTHUMBRECT, 0, (LPARAM)&r); int cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
  hover_px(t, cx, cy); snap("trackbar-hover-thumb"); unhover(t);
  hover_px(t, cx + S(60), cy); snap("trackbar-hover-track"); unhover(t);
  press_snap(t, cx, cy, "trackbar-pressed-thumb"); unhover(t);
  focus(t); snap("trackbar-focus"); unfocus();
  enable(t, FALSE); snap("trackbar-disabled");
  end();
  begin(80, 150);
  t = ctl(TRACKBAR_CLASSW, L"", WS_TABSTOP | TBS_VERT | TBS_AUTOTICKS, 0, 20, 10, 40, 130);
  SendMessageW(t, TBM_SETRANGE, TRUE, MAKELONG(0, 10)); SendMessageW(t, TBM_SETPOS, TRUE, 4); pump(80); snap("trackbar-vertical");
  end();
}

static void case_scroll(void) {
  for (int v = 1; v >= 0; v--) {
    const char *k = v ? "vscroll" : "hscroll"; char nm[64];
    begin(v ? 60 : 210, v ? 190 : 60);
    HWND sb = ctl(L"ScrollBar", L"", v ? SBS_VERT : SBS_HORZ, 0, v ? 20 : 16, v ? 10 : 20, v ? 17 : 178, v ? 170 : 17);
    SCROLLINFO si = { sizeof si, SIF_ALL, 0, 100, 30, 25, 0 }; SetScrollInfo(sb, SB_CTL, &si, TRUE); pump(80);
    snprintf(nm, sizeof nm, "%s-rest", k); snap(nm);
    SCROLLBARINFO bi = { sizeof bi }; GetScrollBarInfo(sb, OBJID_CLIENT, &bi);
    RECT cr; GetClientRect(sb, &cr);
    int th = (bi.xyThumbTop + bi.xyThumbBottom) / 2, mid = v ? cr.right / 2 : cr.bottom / 2;
    int tx = v ? mid : th, ty = v ? th : mid;
    int len = v ? cr.bottom : cr.right, ax = v ? mid : S(8), ay = v ? S(8) : mid;     /* near the first arrow */
    hover_px(sb, tx, ty); snprintf(nm, sizeof nm, "%s-hover-thumb", k); snap(nm); unhover(sb);
    hover_px(sb, ax, ay); snprintf(nm, sizeof nm, "%s-hover-arrow", k); snap(nm); unhover(sb);
    hover_px(sb, v ? mid : len - S(40), v ? len - S(40) : mid); snprintf(nm, sizeof nm, "%s-hover-track", k); snap(nm); unhover(sb);
    snprintf(nm, sizeof nm, "%s-pressed-thumb", k); press_snap(sb, tx, ty, nm); unhover(sb);
    snprintf(nm, sizeof nm, "%s-pressed-arrow", k); press_snap(sb, ax, ay, nm); unhover(sb);
    enable(sb, FALSE); snprintf(nm, sizeof nm, "%s-disabled", k); snap(nm);
    end();
  }
}

static void case_status(void) {
  begin(300, 60);
  HWND s = ctl(STATUSCLASSNAMEW, L"", SBARS_SIZEGRIP | CCS_BOTTOM, 0, 0, 0, 0, 0);
  int parts[3] = { S(120), S(210), -1 }; SendMessageW(s, SB_SETPARTS, 3, (LPARAM)parts);
  SendMessageW(s, SB_SETTEXTW, 0, (LPARAM)L"Ready"); SendMessageW(s, SB_SETTEXTW, 1, (LPARAM)L"12 items"); SendMessageW(s, SB_SETTEXTW, 2 | SBT_NOBORDERS, (LPARAM)L"100%");
  pump(80); snap("statusbar-panels"); end();
  begin(300, 60);
  s = ctl(STATUSCLASSNAMEW, L"", CCS_BOTTOM, 0, 0, 0, 0, 0); SendMessageW(s, SB_SETTEXTW, 0, (LPARAM)L"Simple status text"); pump(80); snap("statusbar-nogrip"); end();
}

static void case_toolbar(void) {
  begin(260, 64);
  HWND t = ctl(TOOLBARCLASSNAMEW, L"", TBSTYLE_FLAT | TBSTYLE_LIST | TBSTYLE_TOOLTIPS | CCS_NODIVIDER | CCS_TOP, 0, 0, 0, 0, 0);
  SendMessageW(t, TB_BUTTONSTRUCTSIZE, sizeof(TBBUTTON), 0);
  HIMAGELIST il = icons16(); SendMessageW(t, TB_SETIMAGELIST, 0, (LPARAM)il);
  SendMessageW(t, TB_SETEXTENDEDSTYLE, 0, TBSTYLE_EX_MIXEDBUTTONS | TBSTYLE_EX_DRAWDDARROWS);
  static const wchar_t *nm[] = { L"New", L"Open", L"Save", L"Print" };
  TBBUTTON b[4] = { { 0, 101, TBSTATE_ENABLED, BTNS_BUTTON | BTNS_SHOWTEXT, { 0 }, 0, (INT_PTR)nm[0] }, { 1, 102, TBSTATE_ENABLED, BTNS_CHECK | BTNS_SHOWTEXT, { 0 }, 0, (INT_PTR)nm[1] },
    { 2, 103, TBSTATE_ENABLED, BTNS_DROPDOWN | BTNS_SHOWTEXT, { 0 }, 0, (INT_PTR)nm[2] }, { 3, 104, TBSTATE_ENABLED, BTNS_BUTTON | BTNS_SHOWTEXT, { 0 }, 0, (INT_PTR)nm[3] } };
  SendMessageW(t, TB_ADDBUTTONSW, 4, (LPARAM)b); SendMessageW(t, TB_AUTOSIZE, 0, 0); pump(100);
  snap("toolbar-rest");
  SendMessageW(t, TB_SETHOTITEM, 0, 0); pump(120); snap("toolbar-hot"); SendMessageW(t, TB_SETHOTITEM, -1, 0);
  SendMessageW(t, TB_PRESSBUTTON, 101, TRUE); pump(80); snap("toolbar-pressed"); SendMessageW(t, TB_PRESSBUTTON, 101, FALSE);
  SendMessageW(t, TB_CHECKBUTTON, 102, TRUE); pump(80); snap("toolbar-checked");
  SendMessageW(t, TB_SETHOTITEM, 1, 0); pump(120); snap("toolbar-checked-hot"); SendMessageW(t, TB_SETHOTITEM, -1, 0); SendMessageW(t, TB_CHECKBUTTON, 102, FALSE);
  SendMessageW(t, TB_SETHOTITEM, 2, 0); pump(120); snap("toolbar-dropdown-hot"); SendMessageW(t, TB_SETHOTITEM, -1, 0);
  SendMessageW(t, TB_ENABLEBUTTON, 104, FALSE); pump(80); snap("toolbar-disabled");
  end();
}

/* ---- menus ---- */
static HMENU mk_popup(void) {
  HMENU sub = CreatePopupMenu(); AppendMenuW(sub, MF_STRING, 21, L"Project one"); AppendMenuW(sub, MF_STRING, 22, L"Project two");
  HMENU m = CreatePopupMenu();
  AppendMenuW(m, MF_STRING, 1, L"&New\tCtrl+N"); AppendMenuW(m, MF_STRING | MF_CHECKED, 2, L"&Open\tCtrl+O"); AppendMenuW(m, MF_STRING | MF_GRAYED, 3, L"&Save\tCtrl+S");
  AppendMenuW(m, MF_SEPARATOR, 0, NULL); AppendMenuW(m, MF_POPUP, (UINT_PTR)sub, L"Open &Recent"); AppendMenuW(m, MF_SEPARATOR, 0, NULL); AppendMenuW(m, MF_STRING, 9, L"E&xit");
  return m;
}
typedef struct { HWND w[8]; int n; } WL;
static BOOL CALLBACK en_menu(HWND h, LPARAM l) {
  WL *wl = (WL *)l; wchar_t c[32]; GetClassNameW(h, c, 32);
  if (!wcscmp(c, L"#32768") && IsWindowVisible(h) && wl->n < 8) wl->w[wl->n++] = h; return TRUE;
}
static int menus(HWND *out) { WL wl = { { 0 }, 0 }; EnumThreadWindows(GetCurrentThreadId(), en_menu, (LPARAM)&wl); for (int i = 0; i < wl.n; i++) out[i] = wl.w[i]; return wl.n; }
static void key(WPARAM vk) { PostMessageW(g_stage, WM_KEYDOWN, vk, 0); PostMessageW(g_stage, WM_KEYUP, vk, 0); }
static int popup_step(int s) {
  HWND w[8]; int n = menus(w);
  /* keyboard selection only: MN_SELECTITEM and posted WM_MOUSEMOVE are not honoured by the menu loop (see README); selected rows show the keyboard-cue outline */
  if (s == 0) { snapx("menu-popup-rest", w, n); key(VK_DOWN); return 1; }
  if (s == 1) { snapx("menu-popup-keyboard-first", w, n); key(VK_DOWN); return 1; }
  if (s == 2) { snapx("menu-popup-keyboard-checked", w, n); key(VK_DOWN); return 1; }
  if (s == 3) { snapx("menu-popup-keyboard-disabled", w, n); key(VK_DOWN); key(VK_RIGHT); return 1; }   /* skips the separator onto "Open Recent", opens the submenu */
  if (s == 4) { snapx("menu-popup-submenu", w, n); key(VK_DOWN); return 1; }
  if (s == 5) { snapx("menu-popup-submenu-keyboard-item", w, n); key(VK_ESCAPE); key(VK_ESCAPE); return 1; }
  PostMessageW(g_stage, WM_CANCELMODE, 0, 0); return 0;
}
static void case_popup_menu(void) {
  begin(260, 200); HMENU m = mk_popup();
  stepper(popup_step, 450);
  POINT p = { S(20), S(20) }; ClientToScreen(g_stage, &p);
  SetForegroundWindow(g_stage);
  TrackPopupMenu(m, TPM_LEFTALIGN | TPM_TOPALIGN, p.x, p.y, 0, g_stage, NULL);
  wait_steps(); DestroyMenu(m); end();
}
static int bar_step(int s) {
  HWND w[8]; int n = menus(w);
  if (s == 0) { snapx("menubar-hot-first", w, n); key(VK_DOWN); return 1; }
  if (s == 1) { snapx("menubar-open", w, n); key(VK_DOWN); return 1; }
  if (s == 2) { snapx("menubar-open-hover-item", w, n); key(VK_ESCAPE); return 1; }
  if (s == 3) { snapx("menubar-hot-after-close", w, n); key(VK_RIGHT); return 1; }
  if (s == 4) { snapx("menubar-hot-second", w, n); key(VK_ESCAPE); key(VK_ESCAPE); return 1; }
  return 0;
}
static void case_menubar(void) {
  HMENU bar = CreateMenu();
  AppendMenuW(bar, MF_POPUP, (UINT_PTR)mk_popup(), L"&File"); AppendMenuW(bar, MF_POPUP, (UINT_PTR)mk_popup(), L"&Edit"); AppendMenuW(bar, MF_POPUP, (UINT_PTR)mk_popup(), L"&Help");
  begin_w(300, 120, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_THICKFRAME, 0, L"Menu bar", bar);
  pump(200); snap("menubar-rest");
  stepper(bar_step, 450); SendMessageW(g_stage, WM_SYSCOMMAND, SC_KEYMENU, 0); wait_steps();
  end();
}

/* ---- tooltip ---- */
static void case_tooltip(void) {
  begin(260, 110);
  HWND b = ctl(L"Button", L"Hover me", WS_TABSTOP, 0, 20, 14, 100, 28);
  for (int balloon = 0; balloon < 2; balloon++) {
    HWND tt = CreateWindowExW(WS_EX_TOPMOST, TOOLTIPS_CLASSW, NULL, WS_POPUP | TTS_NOPREFIX | TTS_ALWAYSTIP | (balloon ? TTS_BALLOON : 0), 0, 0, 0, 0, g_stage, NULL, GetModuleHandleW(NULL), NULL);
    SendMessageW(tt, WM_SETFONT, (WPARAM)g_font, 0);
    if (g_dark) { dark_top(tt); SetWindowTheme(tt, L"DarkMode_Explorer", NULL); }
    TOOLINFOW ti = { sizeof ti, TTF_TRACK | TTF_ABSOLUTE, g_stage, 1, { 0 }, NULL, (LPWSTR)L"This is the tooltip text", 0 };
    SendMessageW(tt, TTM_ADDTOOLW, 0, (LPARAM)&ti);
    if (balloon) SendMessageW(tt, TTM_SETTITLEW, TTI_INFO, (LPARAM)L"Tip title");
    POINT p = { S(30), S(52) }; ClientToScreen(g_stage, &p);
    SendMessageW(tt, TTM_TRACKPOSITION, 0, MAKELPARAM(p.x, p.y)); SendMessageW(tt, TTM_TRACKACTIVATE, TRUE, (LPARAM)&ti); pump(300);
    HWND ex[1] = { tt }; snapx(balloon ? "tooltip-balloon" : "tooltip-rest", ex, 1);
    SendMessageW(tt, TTM_TRACKACTIVATE, FALSE, (LPARAM)&ti); DestroyWindow(tt); pump(100);
  }
  end();
}

/* ---- tree ---- */
static HWND mk_tree(DWORD style) {
  HWND t = ctl(WC_TREEVIEWW, L"", WS_TABSTOP | TVS_HASBUTTONS | TVS_SHOWSELALWAYS | style, WS_EX_CLIENTEDGE, 16, 10, 168, 130);
  TreeView_SetExtendedStyle(t, TVS_EX_DOUBLEBUFFER | TVS_EX_FADEINOUTEXPANDOS, TVS_EX_DOUBLEBUFFER | TVS_EX_FADEINOUTEXPANDOS);
  TVINSERTSTRUCTW is = { TVI_ROOT, TVI_LAST, { TVIF_TEXT } }; HTREEITEM root[3];
  static const wchar_t *kids[] = { L"Child one", L"Child two" };
  for (int i = 0; i < 3; i++) { is.hParent = TVI_ROOT; is.item.pszText = (LPWSTR)(i == 0 ? L"Documents" : i == 1 ? L"Pictures" : L"Music"); root[i] = (HTREEITEM)SendMessageW(t, TVM_INSERTITEMW, 0, (LPARAM)&is);
    for (int k = 0; k < 2; k++) { is.hParent = root[i]; is.item.pszText = (LPWSTR)kids[k]; SendMessageW(t, TVM_INSERTITEMW, 0, (LPARAM)&is); } }
  TreeView_Expand(t, root[0], TVE_EXPAND); pump(100);
  return t;
}
static void case_tree(void) {
  begin(200, 150);
  HWND t = mk_tree(TVS_LINESATROOT); snap("tree-rest");
  RECT r; HTREEITEM it = TreeView_GetNextItem(t, TreeView_GetRoot(t), TVGN_CHILD);
  TreeView_GetItemRect(t, it, &r, TRUE);
  hover_px(t, (r.left + r.right) / 2, (r.top + r.bottom) / 2); snap("tree-hover-row"); unhover(t);
  HTREEITEM root = TreeView_GetRoot(t); TreeView_GetItemRect(t, root, &r, FALSE);
  hover_px(t, r.left - S(12), (r.top + r.bottom) / 2); snap("tree-hover-expander"); unhover(t);
  TreeView_SelectItem(t, it); focus(t); snap("tree-selected-focused"); unfocus(); snap("tree-selected-unfocused");
  TreeView_Expand(t, root, TVE_COLLAPSE); pump(150); snap("tree-collapsed");
  enable(t, FALSE); snap("tree-disabled");
  end();
  begin(200, 150);
  t = mk_tree(TVS_LINESATROOT | TVS_HASLINES); SetWindowTheme(t, L"", L""); pump(100); snap("tree-classic-lines");
  end();
}

static LRESULT notify_alt(NMHDR *h, LPARAM l) {
  if (h->code == NM_CUSTOMDRAW) {
    NMLVCUSTOMDRAW *cd = (NMLVCUSTOMDRAW *)l;
    if (cd->nmcd.dwDrawStage == CDDS_PREPAINT) return CDRF_NOTIFYITEMDRAW;
    if (cd->nmcd.dwDrawStage == CDDS_ITEMPREPAINT) {
      if (cd->nmcd.dwItemSpec % 2) cd->clrTextBk = g_dark ? RGB(43, 43, 43) : RGB(243, 243, 243);
      else cd->clrTextBk = g_dark ? RGB(32, 32, 32) : RGB(255, 255, 255);
      return CDRF_NEWFONT;
    }
  }
  return 0;
}
static void hdr_arrow(HWND l, int col, int fmt) {
  HWND hd = ListView_GetHeader(l); HDITEMW hi = { HDI_FORMAT }; SendMessageW(hd, HDM_GETITEMW, col, (LPARAM)&hi);
  hi.fmt = (hi.fmt & ~(HDF_SORTUP | HDF_SORTDOWN)) | fmt; SendMessageW(hd, HDM_SETITEMW, col, (LPARAM)&hi);
}
static void case_listview(void) {
  begin(250, 150);
  HWND l = mk_lv(12, 10, 226, 130, 0, 0, 3, 7); pump(100); snap("listview-rest");
  RECT hr; HWND hd = ListView_GetHeader(l); Header_GetItemRect(hd, 1, &hr);
  hover_px(hd, (hr.left + hr.right) / 2, (hr.top + hr.bottom) / 2); snap("listview-header-hot"); unhover(hd);
  press_snap(hd, (hr.left + hr.right) / 2, (hr.top + hr.bottom) / 2, "listview-header-pressed"); unhover(hd);
  hdr_arrow(l, 1, HDF_SORTUP); pump(100); snap("listview-sort-up"); hdr_arrow(l, 1, HDF_SORTDOWN); pump(100); snap("listview-sort-down"); hdr_arrow(l, 1, 0);
  RECT ir; ListView_GetItemRect(l, 2, &ir, LVIR_BOUNDS);
  hover_px(l, S(40), (ir.top + ir.bottom) / 2); snap("listview-hover-row"); unhover(l);
  lv_select(l, 2); focus(l); snap("listview-selected-focused"); unfocus(); snap("listview-selected-unfocused");
  hover_px(l, S(40), (ir.top + ir.bottom) / 2); snap("listview-selected-hover"); unhover(l);
  ListView_SetItemState(l, 2, 0, LVIS_SELECTED | LVIS_FOCUSED);
  ListView_SetExtendedListViewStyle(l, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_GRIDLINES); pump(100); snap("listview-gridlines");
  ListView_SetExtendedListViewStyle(l, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);
  g_notify = notify_alt; InvalidateRect(l, NULL, TRUE); pump(150); snap("listview-alternating-notify-customdraw"); g_notify = NULL;
  enable(l, FALSE); snap("listview-disabled");
  end();
}

static void case_syslink(void) {
  begin(260, 70);
  HWND s = ctl(L"SysLink", L"Text with <a href=\"a\">a link</a> and <a href=\"b\">another</a>.", WS_TABSTOP, 0, 16, 14, 230, 22);
  pump(100); snap("syslink-rest");
  hover(s, 78, 8); snap("syslink-hover"); unhover(s);
  focus(s); snap("syslink-focus"); unfocus();
  enable(s, FALSE); snap("syslink-disabled");
  end();
}

static void case_datetime(void) {
  begin(230, 60);
  HWND d = ctl(DATETIMEPICK_CLASSW, L"", WS_TABSTOP | DTS_SHORTDATECENTURYFORMAT, 0, 20, 14, 160, 26);
  pump(100); snap("datepicker-rest");
  hover(d, 60, 12); snap("datepicker-hover"); unhover(d);
  hover(d, 148, 12); snap("datepicker-hover-arrow"); unhover(d);
  focus(d); snap("datepicker-focus"); unfocus();
  enable(d, FALSE); snap("datepicker-disabled");
  end();
  begin(230, 240);
  d = ctl(DATETIMEPICK_CLASSW, L"", WS_TABSTOP | DTS_SHORTDATECENTURYFORMAT, 0, 20, 14, 160, 26);
  focus(d); SendMessageW(d, WM_KEYDOWN, VK_F4, 0); pump(400);
  HWND cal = DateTime_GetMonthCal(d); HWND ex[1] = { cal ? GetParent(cal) == g_stage || !GetParent(cal) ? cal : GetParent(cal) : NULL };
  snapx("datepicker-open", ex, 1);
  SendMessageW(d, WM_KEYDOWN, VK_ESCAPE, 0); pump(200);
  end();
}
static void case_monthcal(void) {
  begin(270, 200);
  HWND m = ctl(MONTHCAL_CLASSW, L"", WS_TABSTOP, 0, 16, 12, 238, 176);
  SYSTEMTIME st = { 2026, 10, 0, 16 }; SendMessageW(m, MCM_SETCURSEL, 0, (LPARAM)&st); SendMessageW(m, MCM_SETTODAY, 0, (LPARAM)&st); pump(100);
  if (g_dark) { MonthCal_SetColor(m, MCSC_BACKGROUND, g_bg); MonthCal_SetColor(m, MCSC_MONTHBK, g_bg); MonthCal_SetColor(m, MCSC_TEXT, g_fg); MonthCal_SetColor(m, MCSC_TITLEBK, RGB(43, 43, 43)); MonthCal_SetColor(m, MCSC_TITLETEXT, g_fg); MonthCal_SetColor(m, MCSC_TRAILINGTEXT, RGB(150, 150, 150)); pump(100); }
  snap("monthcal-rest");
  MCHITTESTINFO hi = { sizeof hi }; RECT r; MonthCal_GetMinReqRect(m, &r);
  hover_px(m, r.right * 6 / 10, r.bottom * 7 / 10); snap("monthcal-hover-day"); unhover(m);
  hover_px(m, r.right * 9 / 10, r.bottom * 1 / 12); snap("monthcal-hover-next"); unhover(m);
  focus(m); snap("monthcal-focus"); unfocus();
  enable(m, FALSE); snap("monthcal-disabled");
  end();
}

/* ---- dialog chrome ---- */
static void ncpos(int btn, int *sx, int *sy) {   /* btn 0 min, 1 max, 2 close: centre of the button, screen coordinates */
  RECT wr, cb; GetWindowRect(g_stage, &wr); DwmGetWindowAttribute(g_stage, 5, &cb, sizeof cb);
  int n = 3, w = (cb.right - cb.left) / n; *sx = wr.left + cb.left + w * btn + w / 2; *sy = wr.top + (cb.top + cb.bottom) / 2;
}
static void nc_hover(int btn, int ht) { int x, y; ncpos(btn, &x, &y); fake_at(x, y); SendMessageW(g_stage, WM_NCMOUSEMOVE, ht, MAKELPARAM(x, y)); pump(250); }
static int ncp_step(int s) { snapx(g_pname, NULL, 0); lbtn(0); PostMessageW(g_stage, WM_NCLBUTTONUP, 0, 0); PostMessageW(g_stage, WM_CANCELMODE, 0, 0); return 0; }
static void nc_press(int btn, int ht, const char *name) {
  int x, y; ncpos(btn, &x, &y); nc_hover(btn, ht); g_pname = name; lbtn(1); stepper(ncp_step, 350);
  PostMessageW(g_stage, WM_NCLBUTTONDOWN, ht, MAKELPARAM(x, y)); wait_steps(); lbtn(0); fake_away(); pump(150);
}
static void case_dialog(void) {
  begin_w(300, 110, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_THICKFRAME, 0, L"Window title", NULL);
  ctl(L"Static", L"Window content.", 0, 0, 20, 20, 200, 20);
  HWND ok = ctl(L"Button", L"OK", WS_TABSTOP | BS_DEFPUSHBUTTON, 0, 120, 66, 80, 28); ctl(L"Button", L"Cancel", WS_TABSTOP, 0, 208, 66, 80, 28); (void)ok;
  pump(300); snap("window-active");
  SendMessageW(g_stage, WM_NCACTIVATE, FALSE, 0); pump(250); snap("window-inactive"); SendMessageW(g_stage, WM_NCACTIVATE, TRUE, 0); pump(250);
  nc_hover(0, HTMINBUTTON); snap("window-caption-min-hot"); fake_away(); SendMessageW(g_stage, WM_NCMOUSELEAVE, 0, 0); pump(200);
  nc_hover(1, HTMAXBUTTON); snap("window-caption-max-hot"); fake_away(); SendMessageW(g_stage, WM_NCMOUSELEAVE, 0, 0); pump(200);
  nc_hover(2, HTCLOSE); snap("window-caption-close-hot"); fake_away(); SendMessageW(g_stage, WM_NCMOUSELEAVE, 0, 0); pump(200);
  /* the caption button press runs a tracking loop on the REAL button state in win32k: it cannot be driven by messages (hangs), so no pressed grab */
  end();
  begin_w(280, 90, WS_POPUP | WS_CAPTION | WS_SYSMENU, WS_EX_DLGMODALFRAME, L"Dialog", NULL);
  ctl(L"Static", L"Plain dialog window.", 0, 0, 20, 14, 200, 20); ctl(L"Button", L"OK", WS_TABSTOP | BS_DEFPUSHBUTTON, 0, 190, 50, 80, 28);
  pump(300); snap("dialog-active"); SendMessageW(g_stage, WM_NCACTIVATE, FALSE, 0); pump(250); snap("dialog-inactive");
  end();
}

/* ---- message box / task dialog ---- */
static BOOL CALLBACK en_dlg(HWND h, LPARAM l) { wchar_t c[32]; GetClassNameW(h, c, 32); if (!wcscmp(c, L"#32770") && IsWindowVisible(h)) { *(HWND *)l = h; return FALSE; } return TRUE; }
static HWND find_dlg(void) { HWND r = NULL; EnumThreadWindows(GetCurrentThreadId(), en_dlg, (LPARAM)&r); return r; }
static const char *g_dlgname; static int g_istask;
static int dlg_step(int s) {
  HWND d = find_dlg(); if (!d) return s < 6;
  if (s == 0) { return 1; }
  char nm[64]; g_base = d; g_nctl = 0;
  if (s == 1) { SendMessageW(d, WM_NCACTIVATE, TRUE, 0); pump(150); snprintf(nm, sizeof nm, "%s-active", g_dlgname); snapx(nm, NULL, 0); return 1; }
  if (s == 2) { SendMessageW(d, WM_NCACTIVATE, FALSE, 0); pump(150); snprintf(nm, sizeof nm, "%s-inactive", g_dlgname); snapx(nm, NULL, 0); return 1; }
  g_base = NULL;
  if (g_istask) PostMessageW(d, 0x0400 + 102, IDCANCEL, 0); else PostMessageW(d, WM_COMMAND, IDCANCEL, 0);
  return 0;
}
static void case_messagebox(void) {
  begin(10, 10); ShowWindow(g_stage, SW_HIDE);
  g_dlgname = "messagebox"; g_istask = 0; stepper(dlg_step, 500);
  MessageBoxW(g_stage, L"Do you want to save changes to the document?", L"Confirm", MB_OKCANCEL | MB_ICONQUESTION); wait_steps();
  end();
}
static void case_taskdialog(void) {
  typedef HRESULT (WINAPI * TDI)(const TASKDIALOGCONFIG *, int *, int *, BOOL *);
  TDI td = (TDI)GetProcAddress(GetModuleHandleW(L"comctl32"), "TaskDialogIndirect"); if (!td) return;
  begin(10, 10); ShowWindow(g_stage, SW_HIDE);
  TASKDIALOG_BUTTON bt[2] = { { 100, L"Save\nKeep the changes" }, { 101, L"Discard\nLose the changes" } };
  TASKDIALOGCONFIG c = { sizeof c }; c.hwndParent = g_stage; c.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION | TDF_USE_COMMAND_LINKS | TDF_EXPAND_FOOTER_AREA;
  c.dwCommonButtons = TDCBF_CANCEL_BUTTON; c.pszWindowTitle = L"Task dialog"; c.pszMainInstruction = L"Save changes?"; c.pszContent = L"The document has unsaved changes.";
  c.pszMainIcon = TD_WARNING_ICON; c.cButtons = 2; c.pButtons = bt; c.pszVerificationText = L"Do not ask again"; c.pszExpandedInformation = L"More information."; c.pszFooter = L"Footer text"; c.pszFooterIcon = TD_INFORMATION_ICON;
  g_dlgname = "taskdialog"; g_istask = 1; stepper(dlg_step, 700);
  int btn = 0; td(&c, &btn, NULL, NULL); wait_steps();
  end();
}

/* ================= driver ================= */
typedef struct { const char *name; void (*fn)(void); } CASE;
static CASE CASES[] = {
  { "button", case_button }, { "checkbox", case_checkbox }, { "radio", case_radio }, { "groupbox", case_groupbox },
  { "edit", case_edit }, { "label", case_label }, { "spin", case_spin }, { "combo", case_combo }, { "listbox", case_listbox }, { "checklist", case_checklist },
  { "tab", case_tab }, { "progress", case_progress }, { "trackbar", case_trackbar }, { "scroll", case_scroll }, { "status", case_status }, { "toolbar", case_toolbar },
  { "popup_menu", case_popup_menu }, { "menubar", case_menubar }, { "tooltip", case_tooltip }, { "tree", case_tree }, { "listview", case_listview }, { "syslink", case_syslink },
  { "datetime", case_datetime }, { "monthcal", case_monthcal }, { "dialog", case_dialog }, { "messagebox", case_messagebox }, { "taskdialog", case_taskdialog },
};

static void load_manifest(const wchar_t *dir) {
  wchar_t p[MAX_PATH]; swprintf(p, MAX_PATH, L"%ls\\gallery.manifest", dir);
  ACTCTXW a = { sizeof a, 0, p };
  HANDLE h = CreateActCtxW(&a); ULONG_PTR cookie;
  if (h == INVALID_HANDLE_VALUE || !ActivateActCtx(h, &cookie)) { printf("activation context failed %lu\n", GetLastError()); exit(2); }
}

int main(int argc, char **argv) {
  if (argc < 4) { printf("usage: gallery <outdir> <light|dark> <100|150> [only]\n"); return 2; }
  g_out = argv[1]; g_theme = argv[2]; g_dark = !strcmp(argv[2], "dark"); int want = atoi(argv[3]); g_only = (argc > 4 && argv[4][0] && strcmp(argv[4], "-")) ? argv[4] : NULL;
  wchar_t exe[MAX_PATH]; GetModuleFileNameW(NULL, exe, MAX_PATH); wchar_t *sl = wcsrchr(exe, L'\\'); *sl = 0;
  if (want == 150) { typedef BOOL (WINAPI * F)(HANDLE); F f = (F)GetProcAddress(GetModuleHandleW(L"user32"), "SetProcessDpiAwarenessContext"); if (!f || !f((HANDLE)-4)) printf("PMv2 failed\n"); }
  load_manifest(exe);
  INITCOMMONCONTROLSEX ic = { sizeof ic, 0xFFFF }; InitCommonControlsEx(&ic);
  HMODULE ux = LoadLibraryW(L"uxtheme.dll"); LoadLibraryW(L"dwmapi.dll");
  pAllowDarkWin = (void *)GetProcAddress(ux, MAKEINTRESOURCEA(133)); pSetPrefMode = (void *)GetProcAddress(ux, MAKEINTRESOURCEA(135));
  pFlushMenuThemes = (void *)GetProcAddress(ux, MAKEINTRESOURCEA(136)); pRefreshPolicy = (void *)GetProcAddress(ux, MAKEINTRESOURCEA(104));
  pGetDpiForWindow = (void *)GetProcAddress(GetModuleHandleW(L"user32"), "GetDpiForWindow");
  pSysParamsForDpi = (void *)GetProcAddress(GetModuleHandleW(L"user32"), "SystemParametersInfoForDpi");
  if (g_dark) { if (pSetPrefMode) pSetPrefMode(getenv("GAL_MODE") ? atoi(getenv("GAL_MODE")) : 2); if (pRefreshPolicy) pRefreshPolicy(); if (pFlushMenuThemes) pFlushMenuThemes(); }
  g_bg = RGB(32, 32, 32); g_fg = RGB(255, 255, 255); g_bgbr = CreateSolidBrush(g_bg);

  /* the pointer hook, loaded after every module it should patch is loaded */
  wchar_t hk[MAX_PATH]; swprintf(hk, MAX_PATH, L"%ls\\v3hook.dll", exe);
  if (!LoadLibraryW(hk)) { printf("cannot load %ls\n", hk); return 2; }
  HANDLE mp = NULL; for (int i = 0; i < 50 && !mp; i++) { mp = OpenFileMappingW(FILE_MAP_ALL_ACCESS, FALSE, L"Local\\v3hover"); if (!mp) Sleep(100); }
  if (!mp) { printf("hook mapping missing\n"); return 2; }
  sh = (SH *)MapViewOfFile(mp, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(SH));
  for (int i = 0; i < 50 && !sh->ready; i++) Sleep(100);
  printf("hook ready, slots patched %ld\n", (long)sh->nPatched);

  SetWindowsHookExW(WH_CBT, cbt, NULL, GetCurrentThreadId());
  /* font: the caption/message font of the current DPI (Segoe UI 9 pt) */
  NONCLIENTMETRICSW ncm = { sizeof ncm };
  if (pSysParamsForDpi && pSysParamsForDpi(SPI_GETNONCLIENTMETRICS, sizeof ncm, &ncm, 0, g_dpi == 96 && want == 150 ? 144 : 96)) {} else SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof ncm, &ncm, 0);
  g_font = CreateFontIndirectW(&ncm.lfMessageFont);

  /* real DPI of the window: tells whether the request was met */
  g_dpi = 96;
  if (want == 150) {
    ensure_class(); HWND t = CreateWindowW(L"GStage", L"", WS_POPUP, 60, 60, 10, 10, NULL, NULL, GetModuleHandleW(NULL), NULL);
    g_dpi = pGetDpiForWindow ? pGetDpiForWindow(t) : 96; DestroyWindow(t);
    pSysParamsForDpi(SPI_GETNONCLIENTMETRICS, sizeof ncm, &ncm, 0, g_dpi); DeleteObject(g_font); g_font = CreateFontIndirectW(&ncm.lfMessageFont);
    printf("window DPI %d\n", g_dpi);
  }
  char dir[600]; snprintf(dir, sizeof dir, "%s\\%s", g_out, g_theme); CreateDirectoryA(g_out, NULL); CreateDirectoryA(dir, NULL);
  char ip[700]; snprintf(ip, sizeof ip, "%s\\index-%s-%d.tsv", g_out, g_theme, g_dpi); g_idx = fopen(ip, "w");
  for (int i = 0; i < (int)(sizeof CASES / sizeof *CASES); i++) { if (argc > 5 && strcmp(argv[5], CASES[i].name)) continue; printf("case %s\n", CASES[i].name); CASES[i].fn(); }
  fclose(g_idx); printf("done\n");
  return 0;
}
