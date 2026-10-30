# Runs a program in a job whose processes may commit at most -Megabytes, and prints what it
# wrote and its exit status: the one way to make Windows refuse a commit on demand (D5934).
param([Parameter(Mandatory)][string]$Program, [int]$Megabytes = 256)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class CommitLimit {
  [StructLayout(LayoutKind.Sequential)] struct Basic { public long a, b; public uint Flags; public UIntPtr c, d; public uint e; public UIntPtr f; public uint g, h; }
  [StructLayout(LayoutKind.Sequential)] struct Io { public ulong a, b, c, d, e, f; }
  [StructLayout(LayoutKind.Sequential)] struct Extended { public Basic B; public Io I; public UIntPtr ProcessMemory, JobMemory, PeakProcess, PeakJob; }
  [StructLayout(LayoutKind.Sequential)] struct Startup { public int cb; IntPtr r1, r2, r3; int x, y, w, h, cx, cy, fill, flags; short show, r4; IntPtr r5, i, o, e; }
  [StructLayout(LayoutKind.Sequential)] struct Info { public IntPtr Process, Thread; public int Pid, Tid; }
  [DllImport("kernel32", SetLastError = true)] static extern IntPtr CreateJobObjectW(IntPtr a, IntPtr n);
  [DllImport("kernel32", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr j, int c, ref Extended i, int n);
  [DllImport("kernel32", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
  [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcessW(string a, string c, IntPtr x, IntPtr y, bool inherit, uint flags, IntPtr e, string d, ref Startup s, out Info i);
  [DllImport("kernel32")] static extern uint ResumeThread(IntPtr t);
  [DllImport("kernel32")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32")] static extern bool GetExitCodeProcess(IntPtr h, out uint c);
  public static uint Run(string program, long bytes) {
    IntPtr job = CreateJobObjectW(IntPtr.Zero, IntPtr.Zero);
    var limits = new Extended();
    limits.B.Flags = 0x100;
    limits.ProcessMemory = (UIntPtr)(ulong)bytes;
    if (!SetInformationJobObject(job, 9, ref limits, Marshal.SizeOf(limits))) throw new Win32Exception();
    var startup = new Startup(); startup.cb = Marshal.SizeOf(startup);
    Info info;
    if (!CreateProcessW(program, "\"" + program + "\"", IntPtr.Zero, IntPtr.Zero, false, 4, IntPtr.Zero, null, ref startup, out info)) throw new Win32Exception();
    if (!AssignProcessToJobObject(job, info.Process)) throw new Win32Exception();
    ResumeThread(info.Thread);
    WaitForSingleObject(info.Process, 60000);
    uint code; GetExitCodeProcess(info.Process, out code);
    return code;
  }
}
'@
$started = [Diagnostics.Stopwatch]::StartNew()
$code = [CommitLimit]::Run((Resolve-Path $Program).Path, $Megabytes * 1MB)
"exit=$code seconds=$([math]::Round($started.Elapsed.TotalSeconds, 1))"
