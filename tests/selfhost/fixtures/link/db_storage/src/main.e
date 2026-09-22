// `e.db.storage`: a B+tree agrees with a dictionary through random inserts
// (finds, ranges, leaf chain, shape), dense/sparse/bitmap indexes answer
// the reference lookups, linear and extendible hashing reach the reference
// shape and answers, an LSM run flushed from the tree and compacted with a
// newer run answers last-writer lookups, a WAL truncates at a checkpoint
// and recovers a torn or corrupt tail as the reference replay does, three
// eviction policies count the reference hits, and 2PL, MVCC and OCC scripts
// play out. Expected values: scratchpad db_storage/ref.py.

use e.db.storage
use e.dist.deadlock as dl
use e.io
use e.mem
use e.os

fn lcg(state: *u64) -> u64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret *state >> 33u32
}

fn sum_btree(t: *const storage.BTree) -> i64 {
    var total = 0i64
    var q = 0u64
    while q < 1000u64 {
        let (v, found) = storage.btree_find(t, q)
        if found { total += v + 1i64 }
        q += 1u64
    }
    ret total
}

fn sum_sstable(s: *const storage.SsTable) -> i64 {
    var total = 0i64
    var q = 0u64
    while q < 1000u64 {
        let (v, found) = storage.sstable_find(s, q)
        if found { total += v + 1i64 }
        q += 1u64
    }
    ret total
}

fn sum_lsm(levels: []const storage.SsTable) -> i64 {
    var total = 0i64
    var q = 0u64
    while q < 1000u64 {
        let (v, found) = storage.lsm_find(levels, q)
        if found { total += v + 1i64 }
        q += 1u64
    }
    ret total
}

fn sum_table(t: *const storage.Table) -> i64 {
    var total = 0i64
    var q = 0u64
    while q < 50u64 {
        let (v, found) = storage.table_get(t, q)
        if found { total += v + 1i64 }
        q += 1u64
    }
    ret total
}

fn pool_hits(policy: storage.Policy) -> usize {
    var frames: [4]u64 = zero
    var valid: [4]bool = zero
    var stamp: [4]u64 = zero
    var hist: [4]u64 = zero
    var ref_bit: [4]bool = zero
    let (p0, e) = storage.buffer_pool(frames[..], valid[..], stamp[..], hist[..], ref_bit[..], policy)
    if e != ok { ret 9999usize }
    var p = p0
    var state = 123u64
    var i = 0usize
    while i < 200usize {
        let (_, _) = storage.pool_access(&p, lcg(&state) % 10u64)
        i += 1usize
    }
    ret p.hits
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: B+tree inserts against the dictionary: finds, height and node count.
    var bkeys: [800]u64 = zero
    var bvals: [800]i64 = zero
    var children: [960]u32 = zero
    var next_leaf: [160]u32 = zero
    var counts: [160]u32 = zero
    var leaf: [160]bool = zero
    let (t0, tree_error) = storage.btree(bkeys[..], bvals[..], children[..], next_leaf[..], counts[..], leaf[..], 4usize)
    if tree_error != ok { os.exit(1i32) }
    var t = t0
    var state = 2024u64
    var i = 0usize
    while i < 300usize {
        if storage.btree_insert(&t, lcg(&state) % 1000u64, i64(i)) != ok { os.exit(1i32) }
        i += 1usize
    }
    if sum_btree(&t) != 42464i64 || storage.btree_height(&t) != 5usize || t.used != 123usize { os.exit(1i32) }

    // 2: range scans.
    var rkeys: [512]u64 = zero
    var rvals: [512]i64 = zero
    let in_range = storage.btree_range(&t, 200u64, 400u64, rkeys[..], rvals[..])
    var key_sum = 0u64
    var val_sum = 0i64
    i = 0usize
    while i < in_range {
        key_sum += rkeys[i]
        val_sum += rvals[i]
        i += 1usize
    }
    if in_range != 48usize || key_sum != 14360u64 || val_sum != 8436i64 { os.exit(2i32) }
    if storage.btree_range(&t, 200u64, 400u64, rkeys[..10usize], rvals[..]) != 10usize { os.exit(2i32) }
    let distinct = storage.btree_range(&t, 0u64, storage.FOREVER, rkeys[..], rvals[..])
    if distinct != 263usize { os.exit(2i32) }

    // 3: the leaf chain visits every key in order.
    var node = storage.btree_first_leaf(&t)
    var walked = 0usize
    var more = true
    while more {
        var slot = 0usize
        while slot < usize(t.n[usize(node)]) {
            if t.keys[usize(node) * 5usize + slot] != rkeys[walked] { os.exit(3i32) }
            walked += 1usize
            slot += 1usize
        }
        let (sibling, has) = storage.btree_next_leaf(&t, node)
        node = sibling
        more = has
    }
    if walked != distinct { os.exit(3i32) }

    // 4: dense index over the sorted column, pages of 8.
    var dense: [512]storage.IndexEntry = zero
    let (dense_n, dense_error) = storage.index_dense(rkeys[..distinct], 8usize, dense[..])
    if dense_error != ok || dense_n != distinct { os.exit(4i32) }
    var index_sum = 0u64
    var q = 0u64
    while q < 1000u64 {
        let (page, slot, found) = storage.index_lookup_dense(dense[..dense_n], q)
        if found { index_sum += u64(page) * 16u64 + u64(slot) + 1u64 }
        q += 1u64
    }
    if index_sum != 68252u64 { os.exit(4i32) }

    // 5: sparse index answers the same lookups.
    var sparse: [64]storage.IndexEntry = zero
    let (sparse_n, sparse_error) = storage.index_sparse(rkeys[..distinct], 8usize, sparse[..])
    if sparse_error != ok || sparse_n != 33usize { os.exit(5i32) }
    index_sum = 0u64
    q = 0u64
    while q < 1000u64 {
        let (page, slot, found) = storage.index_lookup_sparse(sparse[..sparse_n], rkeys[..distinct], 8usize, q)
        if found { index_sum += u64(page) * 16u64 + u64(slot) + 1u64 }
        q += 1u64
    }
    if index_sum != 68252u64 { os.exit(5i32) }
    let (_, sparse_room) = storage.index_sparse(rkeys[..distinct], 8usize, sparse[..4usize])
    if sparse_room != storage.TooSmall { os.exit(5i32) }

    // 6: bitmaps over a four-valued column.
    var column: [200]u8 = zero
    state = 77u64
    i = 0usize
    while i < 200usize {
        column[i] = u8(lcg(&state) % 4u64)
        i += 1usize
    }
    var bitmaps: [16]u64 = zero
    var combined: [4]u64 = zero
    let (words, bitmap_error) = storage.index_bitmap(column[..], 4usize, bitmaps[..])
    if bitmap_error != ok || words != 4usize { os.exit(6i32) }
    if storage.bitmap_count(bitmaps[4usize..8usize]) != 53usize { os.exit(6i32) }
    if storage.bitmap_and(bitmaps[4usize..8usize], bitmaps[8usize..12usize], combined[..]) != ok || storage.bitmap_count(combined[..]) != 0usize { os.exit(6i32) }
    if storage.bitmap_or(bitmaps[4usize..8usize], bitmaps[8usize..12usize], combined[..]) != ok || storage.bitmap_count(combined[..]) != 107usize { os.exit(6i32) }
    column[3usize] = 4u8
    let (_, bad_value) = storage.index_bitmap(column[..], 4usize, bitmaps[..])
    if bad_value != storage.Invalid { os.exit(6i32) }

    // 7: linear hashing reaches the reference level, split pointer and overflow top.
    var hslots: [1024]u64 = zero
    var hvals: [1024]i64 = zero
    var hfilled: [1024]bool = zero
    var overflow: [256]u32 = zero
    let (lh0, lh_error) = storage.hash_index_linear(hslots[..], hvals[..], hfilled[..], overflow[..], 4usize, 4usize, 75usize)
    if lh_error != ok { os.exit(7i32) }
    var lh = lh0
    var directory: [1024]u32 = zero
    var eslots: [1024]u64 = zero
    var evals: [1024]i64 = zero
    var efilled: [1024]bool = zero
    var local_depth: [256]u32 = zero
    let (eh0, eh_error) = storage.hash_index_extendible(directory[..], eslots[..], evals[..], efilled[..], local_depth[..], 4usize)
    if eh_error != ok { os.exit(8i32) }
    var eh = eh0
    state = 99u64
    i = 0usize
    var first_key = 0u64
    while i < 300usize {
        let key = lcg(&state) % 5000u64
        if i == 0usize { first_key = key }
        if storage.lh_insert(&lh, key, i64(i)) != ok { os.exit(7i32) }
        if storage.eh_insert(&eh, key, i64(i)) != ok { os.exit(8i32) }
        i += 1usize
    }
    if lh.n != 289usize || lh.level != 4u32 || lh.split_ptr != 33usize || lh.top != 209usize { os.exit(7i32) }
    var hash_sum = 0i64
    var ext_sum = 0i64
    q = 0u64
    while q < 5000u64 {
        let (v, found) = storage.lh_find(&lh, q)
        if found { hash_sum += v + 1i64 }
        let (ev, found_e) = storage.eh_find(&eh, q)
        if found_e { ext_sum += ev + 1i64 }
        q += 1u64
    }
    if hash_sum != 43956i64 { os.exit(7i32) }
    if storage.lh_remove(&lh, 7777u64) || !storage.lh_remove(&lh, first_key) || lh.n != 288usize { os.exit(7i32) }
    let (_, gone) = storage.lh_find(&lh, first_key)
    if gone { os.exit(7i32) }

    // 8: extendible hashing.
    if eh.n != 289usize || eh.global_depth != 9u32 || eh.used != 103usize || ext_sum != 43956i64 { os.exit(8i32) }
    if storage.eh_remove(&eh, 7777u64) || !storage.eh_remove(&eh, first_key) || eh.n != 288usize { os.exit(8i32) }
    let (_, gone_e) = storage.eh_find(&eh, first_key)
    if gone_e { os.exit(8i32) }

    // 9: memtable flush of the tree's sorted run, then SSTable finds.
    var akeys: [512]u64 = zero
    var avals: [512]i64 = zero
    var atomb: [512]bool = zero
    var aindex: [128]u64 = zero
    var apos: [128]u32 = zero
    var abloom: [16]u64 = zero
    let (run_a0, a_error) = storage.sstable(akeys[..], avals[..], atomb[..], aindex[..], apos[..], abloom[..], 4usize)
    if a_error != ok { os.exit(9i32) }
    var run_a = run_a0
    var no_tomb: [512]bool = zero
    if storage.memtable_flush(rkeys[..distinct], rvals[..distinct], no_tomb[..], &run_a) != ok { os.exit(9i32) }
    if run_a.n != distinct || run_a.index_n != 66usize || sum_sstable(&run_a) != 42464i64 { os.exit(9i32) }
    rkeys[distinct] = 5u64
    if storage.memtable_flush(rkeys[..distinct + 1usize], rvals[..], no_tomb[..], &run_a) != storage.Invalid { os.exit(9i32) }
    if storage.memtable_flush(rkeys[..distinct], rvals[..distinct], no_tomb[..], &run_a) != ok { os.exit(9i32) }

    // 10: a newer run with tombstones over the older one: lsm_find newest first.
    var bkeys2: [160]u64 = zero
    var bvals2: [160]i64 = zero
    var btomb2: [160]bool = zero
    var bindex: [40]u64 = zero
    var bpos: [40]u32 = zero
    var bbloom: [8]u64 = zero
    let (run_b0, b_error) = storage.sstable(bkeys2[..], bvals2[..], btomb2[..], bindex[..], bpos[..], bbloom[..], 4usize)
    if b_error != ok { os.exit(10i32) }
    var run_b = run_b0
    var mkeys: [160]u64 = zero
    var mvals: [160]i64 = zero
    var mtomb: [160]bool = zero
    var m = 0usize
    q = 0u64
    while q < 1000u64 {
        mkeys[m] = q
        mvals[m] = 0i64 - i64(q)
        mtomb[m] = q % 3u64 == 0u64
        m += 1usize
        q += 7u64
    }
    if m != 143usize || storage.memtable_flush(mkeys[..m], mvals[..m], mtomb[..m], &run_b) != ok { os.exit(10i32) }
    var levels: [2]storage.SsTable = zero
    levels[0usize] = run_b
    levels[1usize] = run_a
    if sum_lsm(levels[..]) != -10490i64 { os.exit(10i32) }

    // 11: compaction keeps the newest version and drops tombstones at the bottom.
    var okeys: [512]u64 = zero
    var ovals: [512]i64 = zero
    var otomb: [512]bool = zero
    var oindex: [128]u64 = zero
    var opos: [128]u32 = zero
    var obloom: [16]u64 = zero
    let (out0, out_error) = storage.sstable(okeys[..], ovals[..], otomb[..], oindex[..], opos[..], obloom[..], 4usize)
    if out_error != ok { os.exit(11i32) }
    var merged = out0
    var heads: [2]usize = zero
    let (bottom_n, bottom_error) = storage.lsm_compact(levels[..], heads[..], &merged, true)
    if bottom_error != ok || bottom_n != 322usize || sum_sstable(&merged) != -10490i64 { os.exit(11i32) }
    let (keep_n, keep_error) = storage.lsm_compact(levels[..], heads[..], &merged, false)
    if keep_error != ok || keep_n != 370usize || sum_sstable(&merged) != -10490i64 { os.exit(11i32) }
    var single: [1]storage.SsTable = zero
    single[0usize] = merged
    if sum_lsm(single[..]) != -10490i64 { os.exit(11i32) }

    // 12: WAL appends hand out consecutive LSNs.
    var log: [1856]u8 = zero
    var w = storage.wal(log[..])
    state = 5u64
    i = 0usize
    var checkpoint_lsn = 0u64
    while i < 40usize {
        if i == 20usize {
            let (cp, cp_error) = storage.checkpoint(&w)
            if cp_error != ok { os.exit(12i32) }
            checkpoint_lsn = cp
        }
        var kind = storage.KIND_PUT
        if i % 5usize == 4usize { kind = storage.KIND_DELETE }
        let (lsn, append_error) = storage.wal_append(&w, kind, lcg(&state) % 50u64, i64(i))
        if append_error != ok || lsn != w.next_lsn - 1u64 { os.exit(12i32) }
        i += 1usize
    }
    if checkpoint_lsn != 21u64 || w.used != 1189usize { os.exit(12i32) }
    let (_, bad_kind) = storage.wal_append(&w, 9u8, 0u64, 0i64)
    if bad_kind != storage.Invalid { os.exit(12i32) }

    // 13: truncation below the checkpoint.
    if storage.wal_truncate(&w, checkpoint_lsn) != 20usize || w.used != 609usize { os.exit(13i32) }
    if storage.wal_truncate(&w, checkpoint_lsn) != 0usize { os.exit(13i32) }

    // 14: recovery replays the remaining puts and deletes; a torn tail stops
    // cleanly, a corrupt record answers Corrupt.
    var tkeys: [64]u64 = zero
    var tvals: [64]i64 = zero
    var tb = storage.table(tkeys[..], tvals[..])
    let (applied, recover_error) = storage.recover(log[..], w.used, &tb, 0u64)
    if recover_error != ok || applied != 20usize || sum_table(&tb) != 362i64 { os.exit(14i32) }
    var torn = storage.table(tkeys[..], tvals[..])
    let (torn_applied, torn_error) = storage.recover(log[..], w.used - 13usize, &torn, 0u64)
    if torn_error != ok || torn_applied != 19usize || sum_table(&torn) != 362i64 { os.exit(14i32) }
    var skipped = storage.table(tkeys[..], tvals[..])
    let (none_applied, none_error) = storage.recover(log[..], w.used, &skipped, 100u64)
    if none_error != ok || none_applied != 0usize { os.exit(14i32) }
    log[5usize * 29usize + 10usize] = log[5usize * 29usize + 10usize] ^ 1u8
    var partial = storage.table(tkeys[..], tvals[..])
    let (corrupt_applied, corrupt_error) = storage.recover(log[..], w.used, &partial, 0u64)
    if corrupt_error != storage.Corrupt || corrupt_applied != 4usize { os.exit(14i32) }

    // 15-17: buffer pool hit counts under LRU, CLOCK and LRU-2.
    if pool_hits(.Lru) != 77usize { os.exit(15i32) }
    if pool_hits(.Clock) != 83usize { os.exit(16i32) }
    if pool_hits(.LruK) != 73usize { os.exit(17i32) }

    // 18: strict 2PL: a lock cycle is a deadlock; releasing the victim unblocks.
    var lkeys: [16]u64 = zero
    var owners: [16]u32 = zero
    var exclusive: [16]bool = zero
    var waits: [16]dl.Edge = zero
    var scratch: [8]usize = zero
    let (lt0, lt_error) = storage.lock_table(lkeys[..], owners[..], exclusive[..], waits[..], scratch[..], 3usize)
    if lt_error != ok { os.exit(18i32) }
    var lt = lt0
    let (g1, d1, e1) = storage.txn_lock_2pl(&lt, 0u32, 1u64, false)
    let (g2, d2, e2) = storage.txn_lock_2pl(&lt, 1u32, 2u64, true)
    let (g3, d3, e3) = storage.txn_lock_2pl(&lt, 0u32, 2u64, true)
    let (g4, d4, e4) = storage.txn_lock_2pl(&lt, 1u32, 1u64, true)
    let (g5, d5, e5) = storage.txn_lock_2pl(&lt, 2u32, 1u64, false)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(18i32) }
    if !g1 || d1 || !g2 || d2 || g3 || d3 || g4 || !d4 || !g5 || d5 || lt.wait_n != 1usize { os.exit(18i32) }
    if storage.txn_unlock_all(&lt, 1u32) != 1usize || lt.wait_n != 0usize { os.exit(18i32) }
    let (g6, d6, e6) = storage.txn_lock_2pl(&lt, 0u32, 2u64, true)
    if e6 != ok || !g6 || d6 || storage.txn_unlock_all(&lt, 0u32) != 2usize || lt.n != 1usize { os.exit(18i32) }
    let (_, _, bad_txn) = storage.txn_lock_2pl(&lt, 3u32, 2u64, true)
    if bad_txn != storage.Invalid { os.exit(18i32) }

    // 19: MVCC snapshots see committed versions only.
    var vkeys: [16]u64 = zero
    var vvals: [16]i64 = zero
    var vbegin: [16]u64 = zero
    var vend: [16]u64 = zero
    var writer: [16]u32 = zero
    let (mv0, mv_error) = storage.txn_mvcc(vkeys[..], vvals[..], vbegin[..], vend[..], writer[..])
    if mv_error != ok { os.exit(19i32) }
    var mv = mv0
    if storage.mvcc_write(&mv, 1u32, 1u64, 10i64) != ok || storage.mvcc_write(&mv, 1u32, 2u64, 20i64) != ok { os.exit(19i32) }
    let (_, early) = storage.mvcc_read(&mv, 6u64, 1u64)
    if early || storage.mvcc_commit(&mv, 1u32, 5u64) != 2usize { os.exit(19i32) }
    if storage.mvcc_write(&mv, 2u32, 1u64, 11i64) != ok { os.exit(19i32) }
    let (pending, pending_found) = storage.mvcc_read(&mv, 6u64, 1u64)
    if !pending_found || pending != 10i64 || storage.mvcc_commit(&mv, 2u32, 8u64) != 1usize { os.exit(19i32) }
    let (old, old_found) = storage.mvcc_read(&mv, 7u64, 1u64)
    let (fresh, fresh_found) = storage.mvcc_read(&mv, 8u64, 1u64)
    let (_, before) = storage.mvcc_read(&mv, 4u64, 1u64)
    if !old_found || old != 10i64 || !fresh_found || fresh != 11i64 || before { os.exit(19i32) }
    if storage.mvcc_write(&mv, 3u32, 2u64, 21i64) != ok || storage.mvcc_abort(&mv, 3u32) != 1usize { os.exit(19i32) }
    let (second, second_found) = storage.mvcc_read(&mv, 9u64, 2u64)
    if !second_found || second != 20i64 || mv.n != 3usize { os.exit(19i32) }

    // 20: vacuum prunes what no snapshot at or after the oldest active can see.
    if storage.vacuum(&mv, 7u64) != 0usize || storage.vacuum(&mv, 8u64) != 1usize || mv.n != 2usize { os.exit(20i32) }
    let (kept, kept_found) = storage.mvcc_read(&mv, 8u64, 1u64)
    if !kept_found || kept != 11i64 { os.exit(20i32) }

    // 21: OCC: a read invalidated by a later commit fails validation.
    var skeys: [16]u64 = zero
    var svals: [16]i64 = zero
    var store = storage.table(skeys[..], svals[..])
    var ckeys: [16]u64 = zero
    var cts: [16]u64 = zero
    var clog = storage.commit_log(ckeys[..], cts[..])
    var ra: [8]u64 = zero
    var wa: [8]u64 = zero
    var wva: [8]i64 = zero
    var ta = storage.occ_begin(10u64, ra[..], wa[..], wva[..])
    let (_, a_found, a_read) = storage.occ_read(&ta, &store, 1u64)
    if a_read != ok || a_found || storage.occ_write(&ta, 1u64, 5i64) != ok { os.exit(21i32) }
    var rb: [8]u64 = zero
    var wb: [8]u64 = zero
    var wvb: [8]i64 = zero
    var tbx = storage.txn_occ(10u64, rb[..], wb[..], wvb[..])
    if storage.occ_write(&tbx, 1u64, 7i64) != ok { os.exit(21i32) }
    let (b_ok, b_commit_error) = storage.occ_commit(&tbx, &store, &clog, 11u64)
    if b_commit_error != ok || !b_ok || storage.occ_validate(&ta, &clog) { os.exit(21i32) }
    let (a_ok, a_error2) = storage.occ_commit(&ta, &store, &clog, 12u64)
    if a_error2 != ok || a_ok { os.exit(21i32) }
    var tc = storage.occ_begin(12u64, ra[..], wa[..], wva[..])
    let (c_val, c_found, c_read) = storage.occ_read(&tc, &store, 1u64)
    if c_read != ok || !c_found || c_val != 7i64 || storage.occ_write(&tc, 2u64, 9i64) != ok { os.exit(21i32) }
    let (c_own, _, _) = storage.occ_read(&tc, &store, 2u64)
    let (c_ok, c_error) = storage.occ_commit(&tc, &store, &clog, 13u64)
    let (stored, stored_found) = storage.table_get(&store, 2u64)
    if c_own != 9i64 || c_error != ok || !c_ok || !stored_found || stored != 9i64 || clog.n != 2usize { os.exit(21i32) }

    try io.print("db storage ok\n")
    ret ok
}
