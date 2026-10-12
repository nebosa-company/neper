# C104 — NeperOS stage 2: the kernel as an AVF guest on a Pixel (crosvm bring-up)

| field | value |
|---|---|
| category | compiler / NeperOS |
| score | 0.75 of 1 |
| queue position | 30 of 142 (only position 1 is eligible for the next session; see README) |
| difficulty | very high — the queue rates this for a frontier model at maximum reasoning; a 27B model should take the smallest checklist line per session and expect several sessions per line |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Opened by D2143 when C103 closed D2119 stage 1. Acceptance (D2119 stage 2): the same microkernel boots as an Android Virtualization Framework guest that crosvm starts with the Linux arm64 boot protocol -- device tree in x0, GICv3, PSCI 1.0, an ns16550 serial console, and virtio console, block and vsock over PCI -- first under crosvm, then on a retail Pixel via `adb shell vm run` as a non-protected VM. Device addresses are read from the device tree, never hard-coded; the virtio-pci transport already serves both. Done (D2144): the ns16550/8250 console -- neperos/src/ns16550.e drives the 8250 (THR at 0, LSR at 5 bit 5), the kernel picks it vs PL011 from the stdout uart node's `compatible` (ns16550a for crosvm, arm,pl011 for virt), base and reg-shift from the device tree; console_write and the console server's device_write dispatch by a boot-set flag. Written to crosvm's actual source (aarch64/src/fdt.rs: compatible ns16550a, reg=<addr size>, no reg-shift => shift 0) and regression-verified under QEMU virt (the tree selects PL011, all stage-1 marks pass, ns16550 path inert). Also extracted crosvm's aarch64 memory map from source (RAM 0x80000000, GIC/PCI bases). BLOCKER confirmed (D2144): crosvm is built and runs in this WSL but is KVM-only with no CPU emulation, and the host is x86-64, so it cannot run the aarch64 kernel (rejected as a bad bzImage). Verifying the crosvm/AVF boot -- and the remaining pieces, a virtio-vsock driver and the crosvm memory-map boot -- needs an aarch64 host (a Pixel via adb, or an aarch64 Linux box with KVM); surfaced to the user as a resource decision. Advanced (D2145): the EL0 user window moved to the top of the 39-bit space (index 511, VA 0x7FC0000000) so it no longer collides with crosvm's RAM at 0x80000000, which would otherwise have unmapped the kernel from every user space on the first trap; QEMU-verified -- kernel boots, every EL0 server runs, isolation holds (thread W faults at 0x7FC0040000, X at kernel RAM 0x40000000, Q at ECAM 0x4010000000). The chosen aarch64 host is an AWS Graviton bare-metal instance (only *.metal exposes /dev/kvm for crosvm's KVM backend); the account's configured AWS credentials are invalid and await refresh. The kernel image already carries a valid arm64 Image header. VERIFIED ON REAL HARDWARE (D2146, AWS a1.metal Graviton bare-metal with /dev/kvm): the kernel boots under crosvm/KVM, reads crosvm's DTB (RAM 0x80000000, GICv3, ns16550 at 0x3f8), turns the MMU on and runs the whole EL0/capability suite -- D2145 confirmed, thread W faults at the relocated window 0x7FC0040000. Two crosvm-vs-QEMU gaps found and fixed: crosvm's PCI host is CAM (pci-host-cam-generic, shifts bus<<16/slot<<11/fn<<8) not ECAM, now detected by compatible with a cam flag in pci.Host; and a virtio device's BAR is the one its capabilities name (BAR0 on crosvm, pre-assigned; BAR4 on QEMU, guest-assigned), now discovered and mapped at its real size instead of a hard-coded BAR4/64KB. All three drivers then run under crosvm: entropy returns 8 bytes, block reads/writes sector 0, console writes a virtio-console port; QEMU's ECAM path unchanged (stage-1 boot still green). D2147 then closed the last crosvm functional gap: the EL0 page mappings were global (missing the nG bit), so on a real Cortex-A72 (not QEMU's interpreter) a thread's USER_BASE TLB entry served another thread after the ASID-only context switch, making the console-server client read a neighbour's 0xCD poison and a round-printer re-run. Marking the EL0 leaf descriptors non-global fixed it; the WHOLE stage-2 demo now runs clean under crosvm/KVM on AWS a1.metal -- all three virtio drivers, the capability/isolation threads, `console server up` over the P->K server, `all threads done` and a PSCI power-off with exit 0 -- and QEMU's stage-1 boot is byte-unchanged. D2149 added the virtio-vsock driver (EL0 server T): vsock_connect sets up the three queues (rx/tx/event), reads the guest CID from device config (passed via a new aux slot 5), transmits a STREAM REQUEST to host CID 2, and reads the reply. Verified on AWS a1.metal under crosvm `--vsock cid=3` over /dev/vhost-vsock -- no listener gave op 3 (RST), a Python AF_VSOCK listener on port 1234 gave op 2 (RESPONSE) with the host logging the accept from (3, 1024), a full round trip. QEMU has no vsock device so T is skipped and stage 1 is unchanged. The whole crosvm device list (console, block, vsock over PCI) is now done. Remaining before score 1: the same kernel on a retail Pixel via `adb shell vm run`. NeperOS stages 3 (bare-metal Pixel 6) and 4 follow (D2119).

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Code anchors

Files that mention each identifier from the evidence, with hit counts (`git grep -n -F IDENT FILE` to jump). † = over 40 KB, read by region; ‡ = over 120 KB, never read whole.

- `compatible`: `lib/e/ml/fingerprint.e`×11, `scripts/units_reference.py`×4, `lib/e/math/units.e`×3, `lib/e/fmt/brotli.e`×2‡, `lib/e/os/shell.windows.e`×2‡, `lib/e/algo/collect.e`×1, `lib/e/text/edit.e`×1, `lib/e/ui/navigation.e`×1‡

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- `python scripts/render_progress.py` must run clean after the queue edit.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
