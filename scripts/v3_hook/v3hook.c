/* Pointer-faking hook for a COPY of MTG Studio v3 (32-bit). See README.md.
   Patches the import tables (normal and delay-load) of every module in the process, and GetProcAddress for later lookups, so that
   user32!GetCursorPos / GetMessagePos / WindowFromPoint / GetKeyState / GetAsyncKeyState answer from a shared memory block
   ("Local\v3hover") that scripts\v3_hover_lib.ps1 writes. Nothing touches the real pointer or keyboard. */
#include <windows.h>
#include <psapi.h>
#include <string.h>

/* shared block, all int32: x, y (screen), enabled, lbtn, then counters the harness reads to prove the hooks are hit */
typedef struct { volatile LONG x, y, enabled, lbtn, nCursor, nPatched, nWfp, nKey, ready, nExe, nGpa, lastWfp, lastPtX, lastPtY, nTme, tmeAll; } SH;   /* tmeAll (set by scripts\winnative\gallery.exe) swallows TrackMouseEvent for every class */
static SH *sh;
static BOOL (WINAPI *pGetCursorPos)(LPPOINT);
static DWORD (WINAPI *pGetMessagePos)(void);
static HWND (WINAPI *pWindowFromPoint)(POINT);
static SHORT (WINAPI *pGetKeyState)(int);
static SHORT (WINAPI *pGetAsyncKeyState)(int);
static BOOL (WINAPI *pTrackMouseEvent)(LPTRACKMOUSEEVENT);
static void *pTmeComctl;
static FARPROC (WINAPI *pGetProcAddress)(HMODULE, LPCSTR);
static HMODULE self, user32;

static BOOL on(void) { return sh && sh->enabled; }
static BOOL WINAPI hGetCursorPos(LPPOINT p) {
  if (sh) InterlockedIncrement(&sh->nCursor);   /* counts every call, faked or not */
  if (on() && p) { p->x = sh->x; p->y = sh->y; return TRUE; }
  return pGetCursorPos(p);
}
static DWORD WINAPI hGetMessagePos(void) {
  if (on()) return MAKELONG((WORD)sh->x, (WORD)sh->y);
  return pGetMessagePos();
}
static SHORT hkey(int vk, SHORT real) {
  if (on() && vk == VK_LBUTTON) { InterlockedIncrement(&sh->nKey); return sh->lbtn ? (SHORT)0x8001 : 0; }
  return real;
}
static SHORT WINAPI hGetKeyState(int vk) { return hkey(vk, pGetKeyState(vk)); }
static SHORT WINAPI hGetAsyncKeyState(int vk) { return hkey(vk, pGetAsyncKeyState(vk)); }

/* no real pointer is over the copy, so the system answers a TME_LEAVE request of a native BUTTON window with WM_MOUSELEAVE at once and
   un-hots it. Swallow those requests (only for Button / TcxButton / TButton windows: dxBar and cx controls work without); the harness posts WM_MOUSELEAVE itself. */
static BOOL WINAPI hTrackMouseEvent(LPTRACKMOUSEEVENT t) {
  char cls[32];
  if (on() && t && !(t->dwFlags & TME_QUERY) && (sh->tmeAll || (GetClassNameA(t->hwndTrack, cls, sizeof cls) && (!lstrcmpiA(cls, "Button") || !strncmp(cls, "TcxButton", 9) || !strncmp(cls, "TButton", 7))))) {
    if (sh) InterlockedIncrement(&sh->nTme); return TRUE;
  }
  return pTrackMouseEvent(t);
}

typedef struct { POINT pt; HWND hit; } WALK;
static BOOL CALLBACK walk(HWND h, LPARAM l) { /* EnumWindows is top-down in z-order */
  WALK *w = (WALK *)l; DWORD pid; RECT r;
  GetWindowThreadProcessId(h, &pid);
  if (pid != GetCurrentProcessId() || !IsWindowVisible(h) || !GetWindowRect(h, &r) || !PtInRect(&r, w->pt)) return TRUE;
  w->hit = h; return FALSE;
}
static HWND WINAPI hWindowFromPoint(POINT pt) {
  if (sh) InterlockedIncrement(&sh->nWfp);
  HWND r = pWindowFromPoint(pt);
  if (sh) { sh->lastWfp = (LONG)(LONG_PTR)r; sh->lastPtX = pt.x; sh->lastPtY = pt.y; }
  if (!on() || pt.x != sh->x || pt.y != sh->y) return r;
  DWORD pid = 0; if (r) GetWindowThreadProcessId(r, &pid);
  if (r && pid == GetCurrentProcessId()) return r;
  WALK w = { pt, NULL }; EnumWindows(walk, (LPARAM)&w);   /* another app covers the copy: answer as if the copy were on top */
  HWND cur = w.hit; if (!cur) return r;
  for (int i = 0; i < 20; i++) {
    POINT c = pt; ScreenToClient(cur, &c);
    HWND k = ChildWindowFromPointEx(cur, c, CWP_SKIPINVISIBLE);
    if (!k || k == cur) break; cur = k;
  }
  return cur;
}

typedef struct { const char *name; void *hook; void **orig; } HK;
static HK hooks[] = {
  { "GetCursorPos", hGetCursorPos, (void **)&pGetCursorPos }, { "GetMessagePos", hGetMessagePos, (void **)&pGetMessagePos },
  { "WindowFromPoint", hWindowFromPoint, (void **)&pWindowFromPoint }, { "GetKeyState", hGetKeyState, (void **)&pGetKeyState },
  { "GetAsyncKeyState", hGetAsyncKeyState, (void **)&pGetAsyncKeyState }, { "TrackMouseEvent", hTrackMouseEvent, (void **)&pTrackMouseEvent },
  { "_TrackMouseEvent", hTrackMouseEvent, &pTmeComctl },   /* comctl32's own export, orig looked up in comctl32 */
};
#define NHK ((int)(sizeof hooks / sizeof *hooks))

static FARPROC WINAPI hGetProcAddress(HMODULE m, LPCSTR nm) { /* later / delay-load lookups of the same user32 functions */
  FARPROC r = pGetProcAddress(m, nm);
  if (m == user32 && ((ULONG_PTR)nm >> 16))
    for (int i = 0; i < NHK; i++) if (!strcmp(nm, hooks[i].name)) { InterlockedIncrement(&sh->nGpa); return (FARPROC)hooks[i].hook; }
  return r;
}

static int set_slot(ULONG_PTR *slot, void *val) {
  DWORD old; VirtualProtect(slot, sizeof(void *), PAGE_READWRITE, &old);
  *slot = (ULONG_PTR)val;
  VirtualProtect(slot, sizeof(void *), old, &old);
  InterlockedIncrement(&sh->nPatched); return 1;
}
/* Slots are matched by VALUE (the resolved address of the real function), not by name: linkers that leave OriginalFirstThunk empty
   (Borland style) have no name table to read, and forwarded imports still resolve to the same address. */
static void *hook_for(ULONG_PTR v) {
  for (int i = 0; i < NHK; i++) if (v == (ULONG_PTR)*hooks[i].orig) return hooks[i].hook;
  if (v == (ULONG_PTR)pGetProcAddress) return (void *)hGetProcAddress;
  return NULL;
}

static int patch(HMODULE m) {
  BYTE *b = (BYTE *)m; IMAGE_DOS_HEADER *d = (IMAGE_DOS_HEADER *)b; int n = 0;
  if (m == self || d->e_magic != IMAGE_DOS_SIGNATURE) return 0;
  IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(b + d->e_lfanew);
  DWORD rva = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
  if (!rva) return 0;
  for (IMAGE_IMPORT_DESCRIPTOR *id = (IMAGE_IMPORT_DESCRIPTOR *)(b + rva); id->Name; id++)
    for (IMAGE_THUNK_DATA *ft = (IMAGE_THUNK_DATA *)(b + id->FirstThunk); ft->u1.Function; ft++) {
      void *h = hook_for(ft->u1.Function);
      if (h) n += set_slot(&ft->u1.Function, h);
    }
  return n;
}

static DWORD WINAPI init(LPVOID p) {
  HANDLE map = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, sizeof(SH), L"Local\\v3hover");
  if (!map) return 1;
  sh = (SH *)MapViewOfFile(map, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(SH));
  if (!sh) return 1;
  user32 = GetModuleHandleW(L"user32.dll");
  for (int i = 0; i < NHK; i++) *hooks[i].orig = (void *)GetProcAddress(hooks[i].name[0] == '_' ? GetModuleHandleW(L"comctl32.dll") : user32, hooks[i].name);
  pGetProcAddress = (FARPROC(WINAPI *)(HMODULE, LPCSTR))GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "GetProcAddress");
  sh->x = sh->y = -5000; sh->enabled = 0;
  HMODULE mods[1024]; DWORD need;
  if (EnumProcessModules(GetCurrentProcess(), mods, sizeof mods, &need))
    for (DWORD i = 0; i < need / sizeof(HMODULE); i++) { int c = patch(mods[i]); if (i == 0) sh->nExe = c; }
  sh->ready = 1;
  return 0;
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID r) {
  if (reason == DLL_PROCESS_ATTACH) { self = h; HANDLE t = CreateThread(NULL, 0, init, NULL, 0, NULL); if (t) CloseHandle(t); }
  return TRUE;
}
