/* inject.exe <pid> <dll path>: LoadLibraryW in the target through CreateRemoteThread. Must be 32-bit to hit a 32-bit target's kernel32. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
int wmain(int argc, wchar_t **argv) {
  if (argc < 3) return 2;
  HANDLE p = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION | PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ, FALSE, _wtoi(argv[1]));
  if (!p) { printf("OpenProcess failed %lu\n", GetLastError()); return 1; }
  SIZE_T n = (wcslen(argv[2]) + 1) * sizeof(wchar_t);
  void *mem = VirtualAllocEx(p, NULL, n, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
  if (!mem || !WriteProcessMemory(p, mem, argv[2], n, NULL)) { printf("write failed\n"); return 1; }
  HANDLE t = CreateRemoteThread(p, NULL, 0, (LPTHREAD_START_ROUTINE)GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "LoadLibraryW"), mem, 0, NULL);
  if (!t) { printf("CreateRemoteThread failed %lu\n", GetLastError()); return 1; }
  WaitForSingleObject(t, 10000); DWORD ec = 0; GetExitCodeThread(t, &ec);
  printf("loaded module 0x%08lx\n", ec); return ec ? 0 : 1;
}
