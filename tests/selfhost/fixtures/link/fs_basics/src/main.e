// `e.fs` end to end on a real filesystem. Every path is relative, so the runner's
// working directory decides where these entries land and nothing here writes outside
// it. The same source runs on both hosts: what differs is behind `e.os`, and this
// fixture is what says the two behave alike.

use e.mem
use e.fs
use e.os

// 2020-01-01 and 2100-01-01 in Unix nanoseconds. A timestamp is checked against both:
// against zero it would pass while still carrying the wrong epoch or the wrong scale.
const YEAR_2020_NS: i64 = 1577836800000000000i64
const YEAR_2100_NS: i64 = 4102444800000000000i64

// Whole seconds, so the round trip is exact wherever it runs: one of the filesystems this
// suite uses keeps seconds and drops the nanoseconds, which is precision it never
// promised and not what these assertions are about.
const STAMP_ACCESSED: i64 = 1700000000000000000i64
const STAMP_MODIFIED: i64 = 1700000060000000000i64
const STAMP_SECOND: i64 = 1700000120000000000i64

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

// A previous failing run leaves its scratch behind, and `Exists` from that would fail
// the next run for a reason that is not the one being tested.
fn clear(a: *mem.Arena) {
    let leaf = fs.remove_file(a, "np-fs/deep/leaf.txt")
    let one = fs.remove_file(a, "np-fs/one.txt")
    let two = fs.remove_file(a, "np-fs/two.txt")
    let copy = fs.remove_file(a, "np-fs/copy.txt")
    let link = fs.remove_file(a, "np-fs/link.txt")
    let from_file = fs.remove_file(a, "np-fs/from.txt")
    let landed_file = fs.remove_file(a, "np-fs/landed.txt")
    let scratch = fs.remove_file(a, "np-fs/scratch.txt")
    let moved_deep = fs.remove_file(a, "np-fs/deep/moved.txt")
    let root_probe = fs.remove_file(a, "np-fs/deep/root-probe.txt")
    let root_landed = fs.remove_file(a, "np-fs/deep/root-landed.txt")
    let deep = fs.remove_dir(a, "np-fs/deep")
    let outer = fs.remove_dir(a, "np-fs")
    // A failure in the moved-root assertions below can leave the whole fixture tree
    // under its temporary name. Clear exactly the entries that block the next run.
    let moved_leaf = fs.remove_file(a, "np-fs-moved/deep/leaf.txt")
    let moved_one = fs.remove_file(a, "np-fs-moved/one.txt")
    let moved_link = fs.remove_file(a, "np-fs-moved/link.txt")
    let moved_probe = fs.remove_file(a, "np-fs-moved/deep/root-probe.txt")
    let moved_landed = fs.remove_file(a, "np-fs-moved/deep/root-landed.txt")
    let moved_nested = fs.remove_file(a, "np-fs-moved/deep/moved.txt")
    let moved_deep_dir = fs.remove_dir(a, "np-fs-moved/deep")
    let moved_outer = fs.remove_dir(a, "np-fs-moved")
}

// A leading separator, or a drive letter and a colon: the two ways a path on either host
// does not depend on where it is read from.
fn rooted(text: str) -> bool {
    if text.len == 0usize { ret false }
    if text[0usize] == 47u8 || text[0usize] == 92u8 { ret true }
    if text.len >= 2usize && text[1usize] == 58u8 { ret true }
    ret false
}

fn main(a: *mem.Arena) -> err {
    clear(a)

    // `exists` answers rather than failing: a missing path is `false` with no error,
    // which is the whole reason it is not just `stat`.
    let (absent, absent_error) = fs.exists(a, "np-fs")
    if absent_error != ok { os.exit(10i32) }
    if absent { os.exit(11i32) }

    // The same missing path is `NotFound` from `stat`, where the question was different.
    let (nothing, nothing_error) = fs.stat(a, "np-fs")
    if nothing_error != fs.NotFound { os.exit(12i32) }

    // The detail of that failure survives the return: `stat` classified it into `fs.NotFound`
    // and this is the host code behind that word. Zero would mean nothing was recorded, which
    // is the failure this call exists to avoid.
    let detail = fs.last_error_detail("stat", "np-fs")
    if !same(detail.operation, "stat") { os.exit(13i32) }
    if !same(detail.subject, "np-fs") { os.exit(14i32) }
    if detail.native_code == 0i32 { os.exit(15i32) }
    if detail.kind != .NotFound { os.exit(16i32) }

    // `make_dirs` makes every missing component, so one call covers two levels.
    if fs.make_dirs(a, "np-fs/deep") != ok { os.exit(20i32) }
    let (outer, outer_error) = fs.stat(a, "np-fs")
    if outer_error != ok { os.exit(21i32) }
    if outer.kind != .Directory { os.exit(22i32) }
    let (inner, inner_error) = fs.stat(a, "np-fs/deep")
    if inner_error != ok { os.exit(23i32) }
    if inner.kind != .Directory { os.exit(24i32) }

    // Run again: every component is already a directory, which `make_dirs` accepts and
    // `make_dir` does not.
    if fs.make_dirs(a, "np-fs/deep") != ok { os.exit(25i32) }
    if fs.make_dir(a, "np-fs/deep") != fs.Exists { os.exit(26i32) }

    // Write and read back, byte for byte.
    var payload: [11]u8 = zero
    payload[0usize] = 104u8
    payload[1usize] = 101u8
    payload[2usize] = 108u8
    payload[3usize] = 108u8
    payload[4usize] = 111u8
    payload[5usize] = 32u8
    payload[6usize] = 119u8
    payload[7usize] = 111u8
    payload[8usize] = 114u8
    payload[9usize] = 108u8
    payload[10usize] = 100u8
    if fs.write_file(a, "np-fs/one.txt", payload[..]) != ok { os.exit(30i32) }
    let (read_back, read_error) = fs.read_file(a, "np-fs/one.txt", 0usize)
    if read_error != ok { os.exit(31i32) }
    if read_back.len != 11usize { os.exit(32i32) }
    var at = 0usize
    while at < 11usize {
        if read_back[at] != payload[at] { os.exit(33i32) }
        at += 1usize
    }

    // The size the host reports is the size that was written.
    let (written_entry, written_error) = fs.stat(a, "np-fs/one.txt")
    if written_error != ok { os.exit(34i32) }
    if written_entry.kind != .File { os.exit(35i32) }
    if written_entry.size != 11u64 { os.exit(36i32) }

    // `metadata` is everything the host records about one path, and `follow_symlinks`
    // picks which path that is. With no link in the way the two agree, which is what
    // says the flag reached the call rather than that it changed anything.
    let (described, described_error) = fs.metadata(a, "np-fs/one.txt", true)
    if described_error != ok { os.exit(90i32) }
    if described.kind != .File { os.exit(91i32) }
    if described.size != 11u64 { os.exit(92i32) }
    if described.link_count != 1u64 { os.exit(93i32) }
    if described.file_id == 0u64 { os.exit(94i32) }
    if !described.permissions.owner_read { os.exit(95i32) }
    if !described.permissions.owner_write { os.exit(96i32) }
    if described.modified_ns < YEAR_2020_NS || described.modified_ns > YEAR_2100_NS { os.exit(97i32) }
    if described.created_ns != -1i64 {
        if described.created_ns < YEAR_2020_NS || described.created_ns > YEAR_2100_NS { os.exit(98i32) }
    }
    let (direct, direct_error) = fs.metadata(a, "np-fs/one.txt", false)
    if direct_error != ok { os.exit(99i32) }
    if direct.file_id != described.file_id { os.exit(100i32) }

    // A directory is a directory and is traversable, and it is not the same object as
    // the file -- which is what an identity is for.
    let (folder, folder_error) = fs.metadata(a, "np-fs/deep", true)
    if folder_error != ok { os.exit(101i32) }
    if folder.kind != .Directory { os.exit(102i32) }
    if !folder.permissions.owner_exec { os.exit(103i32) }
    if folder.file_id == described.file_id { os.exit(104i32) }

    // A path that is not there fails the same way the rest of the module does.
    let (absent_metadata, absent_metadata_error) = fs.metadata(a, "np-fs/no-such", true)
    if absent_metadata_error != fs.NotFound { os.exit(105i32) }

    // `set_permissions` and `set_times` are the writing half, and `metadata` is how what
    // they did is read. Both directions of the write bit are checked: a call that changed
    // nothing would pass either one on its own.
    var read_only: fs.Permissions = zero
    read_only.owner_read = true
    if fs.set_permissions(a, "np-fs/one.txt", read_only) != ok { os.exit(110i32) }
    let (locked, locked_error) = fs.metadata(a, "np-fs/one.txt", true)
    if locked_error != ok { os.exit(111i32) }
    if locked.permissions.owner_write { os.exit(112i32) }
    if !locked.permissions.owner_read { os.exit(113i32) }
    var writable: fs.Permissions = zero
    writable.owner_read = true
    writable.owner_write = true
    if fs.set_permissions(a, "np-fs/one.txt", writable) != ok { os.exit(114i32) }
    let (freed, freed_error) = fs.metadata(a, "np-fs/one.txt", true)
    if freed_error != ok { os.exit(115i32) }
    if !freed.permissions.owner_write { os.exit(116i32) }

    if fs.set_times(a, "np-fs/one.txt", STAMP_ACCESSED, STAMP_MODIFIED) != ok { os.exit(117i32) }
    let (stamped, stamped_error) = fs.metadata(a, "np-fs/one.txt", true)
    if stamped_error != ok { os.exit(118i32) }
    if stamped.modified_ns != STAMP_MODIFIED { os.exit(119i32) }
    if stamped.accessed_ns != STAMP_ACCESSED { os.exit(120i32) }

    // One of the two alone: a negative stamp is left as it was.
    if fs.set_times(a, "np-fs/one.txt", -1i64, STAMP_SECOND) != ok { os.exit(121i32) }
    let (restamped, restamped_error) = fs.metadata(a, "np-fs/one.txt", true)
    if restamped_error != ok { os.exit(122i32) }
    if restamped.modified_ns != STAMP_SECOND { os.exit(123i32) }
    if restamped.accessed_ns != STAMP_ACCESSED { os.exit(124i32) }

    // Neither succeeds quietly on a path that is not there.
    if fs.set_permissions(a, "np-fs/no-such", writable) != fs.NotFound { os.exit(125i32) }
    if fs.set_times(a, "np-fs/no-such", STAMP_ACCESSED, STAMP_MODIFIED) != fs.NotFound { os.exit(126i32) }

    // A link through the module. Making one is privileged on some hosts, and `Denied` is
    // the one answer that skips what follows -- any other error, or a target that reads
    // back wrong, still fails.
    let symlink_error = fs.symlink(a, "one.txt", "np-fs/link.txt")
    if symlink_error == ok {
        let (stored, stored_error) = fs.read_link(a, "np-fs/link.txt")
        if stored_error != ok { os.exit(130i32) }
        if !same(stored, "one.txt") { os.exit(131i32) }
        // `follow_symlinks` is what decides which of the two is described.
        let (as_link, as_link_error) = fs.metadata(a, "np-fs/link.txt", false)
        if as_link_error != ok { os.exit(132i32) }
        if as_link.kind != .Symlink { os.exit(133i32) }
        let (through, through_error) = fs.metadata(a, "np-fs/link.txt", true)
        if through_error != ok { os.exit(134i32) }
        if through.kind != .File { os.exit(135i32) }
        if through.size != 11u64 { os.exit(136i32) }
        if through.file_id != described.file_id { os.exit(137i32) }
        if fs.remove_file(a, "np-fs/link.txt") != ok { os.exit(138i32) }
    } else {
        if symlink_error != fs.Denied { os.exit(139i32) }
    }

    // A path that is not a link has no target to give.
    let (not_a_link, not_a_link_error) = fs.read_link(a, "np-fs/one.txt")
    if not_a_link_error != fs.Invalid { os.exit(140i32) }

    // The working directory through the module. It is the one pair here that reads and
    // writes state belonging to the whole process, so the fixture moves and moves back --
    // every relative path after this depends on that.
    let (base, base_error) = fs.current_dir(a)
    if base_error != ok { os.exit(150i32) }
    if base.len == 0usize { os.exit(151i32) }
    if fs.set_current_dir(a, "np-fs/deep") != ok { os.exit(152i32) }
    let (inside, inside_error) = fs.current_dir(a)
    if inside_error != ok { os.exit(153i32) }
    if inside.len < 4usize { os.exit(154i32) }
    if !same(inside[inside.len - 4usize..inside.len], "deep") { os.exit(155i32) }
    // What `current_dir` returns is what `set_current_dir` takes.
    if fs.set_current_dir(a, base) != ok { os.exit(156i32) }
    let (back, back_error) = fs.current_dir(a)
    if back_error != ok { os.exit(157i32) }
    if !same(back, base) { os.exit(158i32) }
    if fs.set_current_dir(a, "np-fs/no-such") != fs.NotFound { os.exit(159i32) }

    // The program's own path, through the module. It is absolute, so it says the same
    // thing wherever the working directory has been moved to.
    let (program, program_error) = fs.executable_path(a)
    if program_error != ok { os.exit(160i32) }
    if program.len == 0usize { os.exit(161i32) }
    let (image, image_error) = fs.stat(a, program)
    if image_error != ok { os.exit(162i32) }
    if image.kind != .File { os.exit(163i32) }
    if image.size == 0u64 { os.exit(164i32) }

    // The two directories the host names rather than the program. Whichever variable each
    // came from, what has to be true of it is the same: an absolute path that is really
    // there and is really a directory.
    let (temporary, temporary_error) = fs.temp_dir(a)
    if temporary_error != ok { os.exit(170i32) }
    if temporary.len == 0usize { os.exit(171i32) }
    if !rooted(temporary) { os.exit(172i32) }
    let (temporary_entry, temporary_entry_error) = fs.stat(a, temporary)
    if temporary_entry_error != ok { os.exit(173i32) }
    if temporary_entry.kind != .Directory { os.exit(174i32) }

    let (home, home_error) = fs.home_dir(a)
    if home_error != ok { os.exit(175i32) }
    if home.len == 0usize { os.exit(176i32) }
    if !rooted(home) { os.exit(177i32) }
    let (home_entry, home_entry_error) = fs.stat(a, home)
    if home_entry_error != ok { os.exit(178i32) }
    if home_entry.kind != .Directory { os.exit(179i32) }

    // They are not the same place, which is what says each came from its own name rather
    // than from one lookup answering both.
    if same(temporary, home) { os.exit(180i32) }

    // `canonical` through the module: two spellings of one file are one answer, and the
    // answer is absolute whatever the working directory happens to be.
    let (resolved, resolved_error) = fs.canonical(a, "np-fs/one.txt")
    if resolved_error != ok { os.exit(190i32) }
    if !rooted(resolved) { os.exit(191i32) }
    let (round_about, round_about_error) = fs.canonical(a, "np-fs/deep/../one.txt")
    if round_about_error != ok { os.exit(192i32) }
    if !same(round_about, resolved) { os.exit(193i32) }
    let (unresolvable, unresolvable_error) = fs.canonical(a, "np-fs/no-such")
    if unresolvable_error != fs.NotFound { os.exit(194i32) }

    // `temp_file` hands back a name that already exists, which is the difference between
    // it and building a name and hoping. It comes with the handle that created it, so
    // nothing has to reopen what it was just given.
    var stamp: [3]u8 = zero
    stamp[0usize] = 120u8
    stamp[1usize] = 121u8
    stamp[2usize] = 122u8
    let (first_temp, first_handle, first_temp_error) = fs.temp_file(a, "np-fs", "probe-")
    if first_temp_error != ok { os.exit(200i32) }
    if first_temp.len == 0usize { os.exit(201i32) }
    let (temp_entry, temp_entry_error) = fs.stat(a, first_temp)
    if temp_entry_error != ok { os.exit(202i32) }
    if temp_entry.kind != .File { os.exit(203i32) }
    if temp_entry.size != 0u64 { os.exit(204i32) }
    let (put, put_error) = os.write(first_handle, stamp[..])
    if put_error != ok { os.exit(205i32) }
    if put != 3usize { os.exit(206i32) }
    if os.close(first_handle) != ok { os.exit(207i32) }
    let (written_temp, written_temp_error) = fs.stat(a, first_temp)
    if written_temp_error != ok { os.exit(208i32) }
    if written_temp.size != 3u64 { os.exit(209i32) }

    // A second call is a different name, or the first one would have been guessable.
    let (second_temp, second_handle, second_temp_error) = fs.temp_file(a, "np-fs", "probe-")
    if second_temp_error != ok { os.exit(210i32) }
    if same(second_temp, first_temp) { os.exit(211i32) }
    if os.close(second_handle) != ok { os.exit(212i32) }

    // A directory that is not there is not a collision to retry, so it comes straight
    // back rather than after sixteen attempts.
    let (no_temp, no_handle, no_temp_error) = fs.temp_file(a, "np-fs/no-such-dir", "probe-")
    if no_temp_error != fs.NotFound { os.exit(213i32) }

    if fs.remove_file(a, first_temp) != ok { os.exit(214i32) }
    if fs.remove_file(a, second_temp) != ok { os.exit(215i32) }

    // `replace` through the module, with the options named rather than positional.
    var keep_existing: fs.ReplaceOptions = zero
    var overwriting: fs.ReplaceOptions = zero
    overwriting.overwrite = true
    var durably: fs.ReplaceOptions = zero
    durably.overwrite = true
    durably.durable = true

    if fs.write_file(a, "np-fs/from.txt", stamp[..]) != ok { os.exit(220i32) }
    if fs.replace(a, "np-fs/from.txt", "np-fs/one.txt", keep_existing) != fs.Exists { os.exit(221i32) }
    // The refusal left both files where they were.
    let (from_kept, from_kept_error) = fs.stat(a, "np-fs/from.txt")
    if from_kept_error != ok { os.exit(222i32) }
    if from_kept.size != 3u64 { os.exit(223i32) }

    // Onto a free name, which is the case the two hosts reach differently.
    if fs.replace(a, "np-fs/from.txt", "np-fs/landed.txt", keep_existing) != ok { os.exit(224i32) }
    let (landed, landed_error) = fs.stat(a, "np-fs/landed.txt")
    if landed_error != ok { os.exit(225i32) }
    if landed.size != 3u64 { os.exit(226i32) }

    // Over something that is there, and on the disk before it returns.
    if fs.replace(a, "np-fs/landed.txt", "np-fs/one.txt", durably) != ok { os.exit(227i32) }
    let (swapped, swapped_error) = fs.stat(a, "np-fs/one.txt")
    if swapped_error != ok { os.exit(228i32) }
    if swapped.size != 3u64 { os.exit(229i32) }
    let (landed_gone, landed_gone_error) = fs.exists(a, "np-fs/landed.txt")
    if landed_gone_error != ok { os.exit(230i32) }
    if landed_gone { os.exit(231i32) }

    // Put `one.txt` back to what the rest of this fixture expects of it.
    if fs.write_file(a, "np-fs/one.txt", payload[..]) != ok { os.exit(232i32) }

    // A `Root` is a directory held open, and every name used through it resolves against
    // that handle. The refusals are the reason it exists, so they are what is checked.
    let (opened_root, opened_root_error) = fs.root(a, "np-fs")
    if opened_root_error != ok { os.exit(240i32) }
    var root_holder = opened_root
    var root_flags: os.OpenFlags = zero
    root_flags.read = true

    let (through_root, through_root_error) = fs.open_at(a, &root_holder, "one.txt", root_flags, .NoSymlinks)
    if through_root_error != ok { os.exit(241i32) }
    var root_bytes: [16]u8 = zero
    let (root_read, root_read_error) = os.read(through_root, root_bytes[..])
    if root_read_error != ok { os.exit(242i32) }
    if root_read != 11usize { os.exit(243i32) }
    if os.close(through_root) != ok { os.exit(244i32) }

    // A name that would leave the root, and one that ignores it entirely.
    let (upward, upward_error) = fs.open_at(a, &root_holder, "../np-fs", root_flags, .NoSymlinks)
    if upward_error != fs.Denied { os.exit(245i32) }
    let (rooted_name, rooted_name_error) = fs.open_at(a, &root_holder, "/etc/hosts", root_flags, .NoSymlinks)
    if rooted_name_error != fs.Denied { os.exit(246i32) }

    // A name under a subdirectory of the root is fine -- the refusal is about leaving, not
    // about depth. The file is made here rather than assumed, because what else this
    // fixture has created by now is not this block's business.
    var under: [2]u8 = zero
    under[0usize] = 105u8
    under[1usize] = 110u8
    if fs.write_file(a, "np-fs/deep/leaf.txt", under[..]) != ok { os.exit(250i32) }
    let (deep_file, deep_file_error) = fs.open_at(a, &root_holder, "deep/leaf.txt", root_flags, .NoSymlinks)
    if deep_file_error != ok { os.exit(247i32) }
    if os.close(deep_file) != ok { os.exit(248i32) }


    // `remove_at` and `replace_at` through the same root, which is what makes a `Root` a
    // place to work rather than only a place to read from.
    if fs.write_file(a, "np-fs/scratch.txt", under[..]) != ok { os.exit(251i32) }
    if fs.replace_at(a, &root_holder, "scratch.txt", &root_holder, "deep/moved.txt", keep_existing) != ok { os.exit(252i32) }
    let (moved_in_root, moved_in_root_error) = fs.stat(a, "np-fs/deep/moved.txt")
    if moved_in_root_error != ok { os.exit(253i32) }
    if moved_in_root.size != 2u64 { os.exit(254i32) }
    let (scratch_gone, scratch_gone_error) = fs.exists(a, "np-fs/scratch.txt")
    if scratch_gone_error != ok { os.exit(255i32) }
    if scratch_gone { os.exit(256i32) }

    // A name that would leave the root is refused by both of them as well.
    if fs.remove_at(a, &root_holder, "../np-fs", true) != fs.Denied { os.exit(257i32) }
    if fs.replace_at(a, &root_holder, "deep/moved.txt", &root_holder, "../escaped.txt", keep_existing) != fs.Denied { os.exit(258i32) }

    if fs.remove_at(a, &root_holder, "deep/moved.txt", false) != ok { os.exit(259i32) }
    let (moved_gone, moved_gone_error) = fs.exists(a, "np-fs/deep/moved.txt")
    if moved_gone_error != ok { os.exit(260i32) }
    if moved_gone { os.exit(261i32) }

    // The handle, not the path that first named it, is the authority. Move the directory
    // while `Root` is live, then exercise every relative operation through that same
    // handle. A path-joined implementation would look under the now-missing old name.
    if fs.write_file(a, "np-fs/deep/root-probe.txt", under[..]) != ok { os.exit(181i32) }
    let root_link_error = fs.symlink(a, "one.txt", "np-fs/link.txt")
    if root_link_error != ok && root_link_error != fs.Denied { os.exit(182i32) }
    if fs.move(a, "np-fs", "np-fs-moved") != ok { os.exit(183i32) }

    let (held_file, held_file_error) = fs.open_at(a, &root_holder, "one.txt", root_flags, .NoSymlinks)
    if held_file_error != ok { os.exit(184i32) }
    if os.close(held_file) != ok { os.exit(185i32) }

    if fs.replace_at(a, &root_holder, "deep/root-probe.txt", &root_holder, "deep/root-landed.txt", keep_existing) != ok { os.exit(186i32) }
    if fs.remove_at(a, &root_holder, "deep/root-landed.txt", false) != ok { os.exit(187i32) }

    // The walk to the parent refuses links, but the final link is removed as an entry.
    // Its target remains readable through the root. Hosts that cannot create a link
    // without privilege still have the moved-root coverage above.
    if root_link_error == ok {
        if fs.remove_at(a, &root_holder, "link.txt", false) != ok { os.exit(188i32) }
        let (removed_link, removed_link_error) = fs.metadata(a, "np-fs-moved/link.txt", false)
        if removed_link_error != fs.NotFound { os.exit(189i32) }
        let (kept_target, kept_target_error) = fs.open_at(a, &root_holder, "one.txt", root_flags, .NoSymlinks)
        if kept_target_error != ok { os.exit(195i32) }
        if os.close(kept_target) != ok { os.exit(196i32) }
    }

    if fs.move(a, "np-fs-moved", "np-fs") != ok { os.exit(197i32) }

    if fs.root_close(&root_holder) != ok { os.exit(249i32) }

    // A limit smaller than the file is refused rather than silently truncating, and a
    // limit large enough is not.
    let (capped, capped_error) = fs.read_file(a, "np-fs/one.txt", 10usize)
    if capped_error != fs.Invalid { os.exit(37i32) }
    let (allowed, allowed_error) = fs.read_file(a, "np-fs/one.txt", 11usize)
    if allowed_error != ok { os.exit(38i32) }
    if allowed.len != 11usize { os.exit(39i32) }

    // A directory is not a file to read.
    let (as_file, as_file_error) = fs.read_file(a, "np-fs", 0usize)
    if as_file_error != fs.Invalid { os.exit(40i32) }

    // Truncation: a second write replaces what the first put there rather than adding
    // to it.
    var shorter: [3]u8 = zero
    shorter[0usize] = 97u8
    shorter[1usize] = 98u8
    shorter[2usize] = 99u8
    if fs.write_file(a, "np-fs/one.txt", shorter[..]) != ok { os.exit(41i32) }
    let (shortened, shortened_error) = fs.stat(a, "np-fs/one.txt")
    if shortened_error != ok { os.exit(42i32) }
    if shortened.size != 3u64 { os.exit(43i32) }

    // Copy through a buffer smaller than the file, so the loop runs more than once.
    if fs.write_file(a, "np-fs/one.txt", payload[..]) != ok { os.exit(44i32) }
    var scratch: [4]u8 = zero
    if fs.copy_file(a, "np-fs/one.txt", "np-fs/copy.txt", scratch[..]) != ok { os.exit(45i32) }
    let (copied, copied_error) = fs.read_file(a, "np-fs/copy.txt", 0usize)
    if copied_error != ok { os.exit(46i32) }
    if copied.len != 11usize { os.exit(47i32) }
    at = 0usize
    while at < 11usize {
        if copied[at] != payload[at] { os.exit(48i32) }
        at += 1usize
    }
    // A buffer with no room would make no progress, so it is an error and not a hang.
    var empty: []u8 = zero
    if fs.copy_file(a, "np-fs/one.txt", "np-fs/two.txt", empty) != fs.Invalid { os.exit(49i32) }

    // Move: the new name has the bytes and the old name has nothing.
    if fs.move(a, "np-fs/copy.txt", "np-fs/two.txt") != ok { os.exit(50i32) }
    let (moved, moved_error) = fs.stat(a, "np-fs/two.txt")
    if moved_error != ok { os.exit(51i32) }
    if moved.size != 11u64 { os.exit(52i32) }
    let (vanished, vanished_error) = fs.exists(a, "np-fs/copy.txt")
    if vanished_error != ok { os.exit(53i32) }
    if vanished { os.exit(54i32) }

    // A walk of one level: two files and one directory, and nothing from inside it.
    if fs.write_file(a, "np-fs/deep/leaf.txt", shorter[..]) != ok { os.exit(60i32) }
    var flat: fs.WalkOptions = zero
    let (shallow, shallow_error) = fs.walk(a, "np-fs", flat)
    if shallow_error != ok { os.exit(61i32) }
    var shallow_walk = shallow
    var files = 0usize
    var directories = 0usize
    while true {
        let (entry, more, walk_error) = fs.walk_next_err(&shallow_walk)
        if walk_error != ok { os.exit(62i32) }
        if !more { break }
        if entry.kind == .File { files += 1usize }
        if entry.kind == .Directory { directories += 1usize }
    }
    if files != 2usize { os.exit(63i32) }
    if directories != 1usize { os.exit(64i32) }
    if fs.walk_close(&shallow_walk) != ok { os.exit(65i32) }

    // The same tree walked recursively finds the one inside `deep` as well, and its
    // path is the full one rather than the bare name.
    var deep_options: fs.WalkOptions = zero
    deep_options.recursive = true
    let (deep_start, deep_error) = fs.walk(a, "np-fs", deep_options)
    if deep_error != ok { os.exit(70i32) }
    var deep_walk = deep_start
    var deep_files = 0usize
    var leaf_seen = false
    var leaf_size = 0u64
    while true {
        let (entry, more, walk_error) = fs.walk_next_err(&deep_walk)
        if walk_error != ok { os.exit(71i32) }
        if !more { break }
        if entry.kind == .File { deep_files += 1usize }
        if entry.path.len > 8usize {
            let tail = entry.path[entry.path.len - 8usize..entry.path.len]
            if same(tail, "leaf.txt") {
                leaf_seen = true
                leaf_size = entry.size
            }
        }
    }
    if deep_files != 3usize { os.exit(72i32) }
    if !leaf_seen { os.exit(73i32) }
    if leaf_size != 3u64 { os.exit(74i32) }
    if fs.walk_close(&deep_walk) != ok { os.exit(75i32) }

    // Abandon a fresh recursive walk after one entry. Closing is what makes the rest of
    // the traversal unreachable; it is safe to ask again and safe to close again, so a
    // caller does not need to know whether the host buffered or streamed directories.
    let (abandoned_start, abandoned_error) = fs.walk(a, "np-fs", deep_options)
    if abandoned_error != ok { os.exit(76i32) }
    var abandoned_walk = abandoned_start
    let (abandoned_first, abandoned_more, abandoned_next_error) = fs.walk_next_err(&abandoned_walk)
    if abandoned_next_error != ok { os.exit(77i32) }
    if !abandoned_more { os.exit(78i32) }
    if fs.walk_close(&abandoned_walk) != ok { os.exit(79i32) }
    let (after_close, after_close_more, after_close_error) = fs.walk_next_err(&abandoned_walk)
    if after_close_error != ok { os.exit(88i32) }
    if after_close_more { os.exit(89i32) }
    if fs.walk_close(&abandoned_walk) != ok { os.exit(107i32) }

    // A non-empty directory stays, so a recursive delete is the caller's to write.
    if fs.remove_dir(a, "np-fs") == ok { os.exit(80i32) }
    if fs.remove_file(a, "np-fs/deep/leaf.txt") != ok { os.exit(81i32) }
    if fs.remove_dir(a, "np-fs/deep") != ok { os.exit(82i32) }
    if fs.remove_file(a, "np-fs/one.txt") != ok { os.exit(83i32) }
    if fs.remove_file(a, "np-fs/two.txt") != ok { os.exit(84i32) }
    if fs.remove_dir(a, "np-fs") != ok { os.exit(85i32) }
    let (finally, finally_error) = fs.exists(a, "np-fs")
    if finally_error != ok { os.exit(86i32) }
    if finally { os.exit(87i32) }
    ret ok
}
