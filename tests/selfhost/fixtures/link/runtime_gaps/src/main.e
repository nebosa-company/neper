// The planned names of the runtime gaps: `mem.pool`, `mem.slab`, `mem.buddy` against
// a Python replica (scratch ref.py: same LIFO free lists, same LCG script), the arena
// `mark`/`reset` pair, `sync.spin_lock` under four threads, `sync.rcu` with four
// readers and a writer that retires indexes and counts a reader seeing one, and
// `mmap.map`/`unmap`. Every check has its own exit code.
use e.atomic
use e.fs.mmap as mmap
use e.io
use e.mem
use e.os
use e.sync
use e.thread

type SpinShared = struct { lock: sync.SpinLock, plain: u64 }
type SpinCtx = struct { s: *SpinShared }

fn spin_worker(c: *SpinCtx) {
    var at = 0usize
    while at < 20000usize {
        sync.spin_lock(&c.s.lock)
        c.s.plain += 1u64
        sync.spin_unlock(&c.s.lock)
        at += 1usize
    }
}

type RcuShared = struct { r: sync.Rcu, retired: [4]Atomic[u32], violations: Atomic[u64] }
type ReaderCtx = struct { s: *RcuShared, thread: usize }

fn rcu_reader(c: *ReaderCtx) {
    var at = 0usize
    while at < 40000usize {
        let index = sync.rcu_read_lock(&c.s.r, c.thread)
        if atomic.load(&c.s.retired[usize(index)], .SeqCst) == 1u32 {
            let ignored = atomic.add(&c.s.violations, 1u64, .Relaxed)
        }
        sync.rcu_read_unlock(&c.s.r, c.thread)
        at += 1usize
    }
}

fn write_whole(a: *mem.Arena, path: str, data: []const u8) -> err {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.truncate = true
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret open_error }
    let (written, write_error) = os.write(file, data)
    let close_error = os.close(file)
    if write_error != ok { ret write_error }
    if written != data.len { ret os.Failed }
    ret close_error
}

fn main(a: *mem.Arena, args: []str) -> err {
    // ---- pool: 256 bytes, object 20 at align 8 -> ten 24-byte slots, low first.
    var pool_bytes: [256]u8 = zero
    let (p0, pool_error) = mem.pool(pool_bytes[..], 20usize, 8usize)
    if pool_error != ok { os.exit(1i32) }
    var p = p0
    var at = 0usize
    while at < 10usize {
        let (slot, slot_error) = mem.pool_alloc(&p)
        if slot_error != ok || slot != at * 24usize { os.exit(2i32) }
        let view = mem.pool_slot(&p, slot)
        if view.len != 24usize { os.exit(3i32) }
        at += 1usize
    }
    let (_, eleventh) = mem.pool_alloc(&p)
    if eleventh != mem.Full || mem.pool_free_count(&p) != 0usize { os.exit(4i32) }
    if mem.pool_free(&p, 72usize) != ok || mem.pool_free(&p, 168usize) != ok { os.exit(5i32) }
    if mem.pool_free(&p, 70usize) != mem.Invalid { os.exit(5i32) }
    let (first_reuse, _) = mem.pool_alloc(&p)
    let (second_reuse, _) = mem.pool_alloc(&p)
    let (_, third_reuse) = mem.pool_alloc(&p)
    if first_reuse != 168usize || second_reuse != 72usize || third_reuse != mem.Full { os.exit(6i32) }

    // ---- slab: three 4096-byte pages.
    let (slab_bytes, slab_bytes_error) = mem.alloc[u8](a, 12288usize)
    if slab_bytes_error != ok { os.exit(10i32) }
    let (s0, slab_error) = mem.slab(slab_bytes, 4096usize)
    if slab_error != ok { os.exit(11i32) }
    var s = s0
    let (sa, sa_error) = mem.slab_alloc(&s, 20usize)
    let (sb, sb_error) = mem.slab_alloc(&s, 20usize)
    let (sc, sc_error) = mem.slab_alloc(&s, 100usize)
    if sa_error != ok || sb_error != ok || sc_error != ok { os.exit(12i32) }
    if sa != 0usize || sb != 32usize || sc != 4096usize { os.exit(13i32) }
    if mem.slab_slot(&s, sc, 100usize).len != 128usize { os.exit(14i32) }
    let (_, big) = mem.slab_alloc(&s, 5000usize)
    let (_, none) = mem.slab_alloc(&s, 0usize)
    if big != mem.Invalid || none != mem.Invalid { os.exit(15i32) }
    if mem.slab_free(&s, sa, 20usize) != ok { os.exit(16i32) }
    let (sd, sd_error) = mem.slab_alloc(&s, 30usize)
    let (se, se_error) = mem.slab_alloc(&s, 4096usize)
    let (_, sf_error) = mem.slab_alloc(&s, 4096usize)
    if sd_error != ok || se_error != ok || sd != 0usize || se != 8192usize { os.exit(17i32) }
    if sf_error != mem.Full { os.exit(18i32) }

    // ---- buddy: 1024 bytes of 16-byte blocks under an LCG script of 48 steps.
    var buddy_bytes: [1024]u8 = zero
    let (b0, buddy_error) = mem.buddy(buddy_bytes[..], 16usize)
    if buddy_error != ok { os.exit(20i32) }
    var b = b0
    if mem.buddy_largest_free(&b) != 1024usize { os.exit(21i32) }
    var live_off: [48]usize = zero
    var live_size: [48]usize = zero
    var live = 0usize
    var state = 12345u64
    var h = 0u32
    var step = 0usize
    while step < 48usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        let r = state >> 33u32
        if (r & 1u64) == 1u64 && live > 0usize {
            let index = usize((r >> 1u32) % u64(live))
            if mem.buddy_free(&b, live_off[index], live_size[index]) != ok { os.exit(22i32) }
            var shift = index
            while shift + 1usize < live {
                live_off[shift] = live_off[shift + 1usize]
                live_size[shift] = live_size[shift + 1usize]
                shift += 1usize
            }
            live -= 1usize
            h = h *% 31u32 +% 7u32
        } else {
            let size = usize((r >> 1u32) % 200u64) + 1usize
            let (off, off_error) = mem.buddy_alloc(&b, size)
            if off_error != ok {
                h = h *% 31u32
            } else {
                live_off[live] = off
                live_size[live] = size
                live += 1usize
                h = h *% 31u32 +% u32(off + 1usize)
            }
        }
        h = h *% 31u32 +% u32(mem.buddy_largest_free(&b))
        step += 1usize
    }
    if h != 1447050413u32 || live != 3usize { os.exit(23i32) }
    at = 0usize
    while at < live {
        if mem.buddy_free(&b, live_off[at], live_size[at]) != ok { os.exit(24i32) }
        at += 1usize
    }
    if mem.buddy_largest_free(&b) != 1024usize { os.exit(25i32) }
    if mem.buddy_free(&b, 8usize, 16usize) != mem.Invalid { os.exit(26i32) }

    // ---- mark/reset: the second allocation after a reset lands where the first did.
    let m = mem.mark(a)
    let (first, first_error) = mem.alloc[u8](a, 100usize)
    if first_error != ok { os.exit(30i32) }
    let first_at = mem.address_of(&first[0usize])
    mem.reset(a, m)
    let (again, again_error) = mem.alloc[u8](a, 100usize)
    if again_error != ok || mem.address_of(&again[0usize]) != first_at { os.exit(31i32) }

    // ---- spin lock: four threads, a plain counter, nothing lost.
    var spin: SpinShared = zero
    spin.lock = sync.spinlock()
    if !sync.spin_try_lock(&spin.lock) { os.exit(40i32) }
    if sync.spin_try_lock(&spin.lock) { os.exit(41i32) }
    sync.spin_unlock(&spin.lock)
    var spin_ctx: [4]SpinCtx = zero
    at = 0usize
    while at < 4usize {
        spin_ctx[at] = SpinCtx { s: &spin }
        at += 1usize
    }
    let (spinners, spin_error) = thread.spawn_all[SpinCtx](a, spin_worker, spin_ctx[..], 0usize)
    if spin_error != ok { os.exit(42i32) }
    if thread.join_all(spinners) != ok { os.exit(43i32) }
    if spin.plain != 80000u64 { os.exit(44i32) }

    // ---- rcu: four readers over a ring of four indexes; the writer retires the
    // old index only after `rcu_synchronize`, so no reader may ever hold a retired one.
    var cell: RcuShared = zero
    var reader_words: [4]Atomic[u64] = zero
    let (r0, rcu_error) = sync.rcu(reader_words[..], 0u32)
    if rcu_error != ok { os.exit(50i32) }
    cell.r = r0
    var reader_ctx: [4]ReaderCtx = zero
    at = 0usize
    while at < 4usize {
        reader_ctx[at] = ReaderCtx { s: &cell, thread: at }
        at += 1usize
    }
    let (readers, readers_error) = thread.spawn_all[ReaderCtx](a, rcu_reader, reader_ctx[..], 0usize)
    if readers_error != ok { os.exit(51i32) }
    var current = 0u32
    var update = 0usize
    while update < 3000usize {
        let following = (current + 1u32) % 4u32
        atomic.store(&cell.retired[usize(following)], 0u32, .SeqCst)
        let old = sync.rcu_update(&cell.r, following)
        if old != current { os.exit(52i32) }
        sync.rcu_synchronize(&cell.r)
        atomic.store(&cell.retired[usize(old)], 1u32, .SeqCst)
        current = following
        update += 1usize
    }
    if thread.join_all(readers) != ok { os.exit(53i32) }
    if atomic.load(&cell.violations, .SeqCst) != 0u64 { os.exit(54i32) }
    if sync.rcu_load(&cell.r) != current { os.exit(55i32) }

    // ---- mmap.map: sixteen bytes written, mapped by the planned name, unmapped.
    let stale = os.remove_file(a, "np-runtime-gaps.bin")
    if stale != ok && stale != os.NotFound { os.exit(60i32) }
    var original: [16]u8 = zero
    at = 0usize
    while at < 16usize {
        original[at] = u8(at) + 65u8
        at += 1usize
    }
    if write_whole(a, "np-runtime-gaps.bin", original[..]) != ok { os.exit(61i32) }
    let (mapping, map_error) = mmap.map(a, "np-runtime-gaps.bin", false, 0u64, 16usize)
    if map_error != ok { os.exit(62i32) }
    let seen = mmap.bytes(mapping)
    if seen.len != 16usize || seen[0usize] != 65u8 || seen[15usize] != 80u8 { os.exit(63i32) }
    if mmap.unmap(mapping) != ok { os.exit(64i32) }
    let (_, empty) = mmap.map(a, "np-runtime-gaps.bin", false, 0u64, 0usize)
    if empty != mmap.Empty { os.exit(65i32) }
    if os.remove_file(a, "np-runtime-gaps.bin") != ok { os.exit(66i32) }

    try io.print("runtime gaps ok\n")
    ret ok
}
