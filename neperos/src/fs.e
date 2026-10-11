// A minimal persistent filesystem on a virtio-block device (D2152, C106). The on-disk layout is
// 512-byte blocks: block 0 the superblock (a magic word, then the next free block as a bump
// allocator), block 1 the root directory, blocks 2+ handed out for file data and subdirectories.
// A directory is one block of sixteen 32-byte entries -- a 20-byte NUL-padded name, a kind byte
// (empty, file, dir), the data block, and the size in bytes. Files are a single block (<= 512
// bytes); a directory holds up to sixteen entries. Paths are resolved from the root, so mkdir,
// write and the rest take `/dir/name`. Removed blocks are not reclaimed.
// ponytail: single-block files, sixteen-entry one-block directories, bump allocation with no free
// list -- an inode with block pointers and a free bitmap are the upgrade when a file or directory
// outgrows a block.
use e.os
use virtio

error NotFormatted
error DirFull
error NotFound
error NotDirectory
error NameTooLong
error NameTaken

const SUPER_MAGIC: u32 = 0x4653454Eu32
const ROOT_DIR: u64 = 1u64
const FIRST_DATA: u32 = 2u32
const ENTRY_SIZE: usize = 32usize
const ENTRIES: usize = 16usize
const KIND_EMPTY: u8 = 0u8
const KIND_FILE: u8 = 1u8
const KIND_DIR: u8 = 2u8
const NAME_OFF: usize = 0usize
const KIND_OFF: usize = 20usize
const BLOCK_OFF: usize = 24usize
const SIZE_OFF: usize = 28usize
const NAME_MAX: usize = 20usize
const BLOCK_SIZE: usize = 512usize
const SLASH: u8 = 47u8

fn zero_data(blk: virtio.Block) {
    var i = 0usize
    while i < BLOCK_SIZE {
        os.store64(blk.data + i, 0u64)
        i += 8usize
    }
}

// Lay down an empty filesystem: a superblock with the magic and the first free block, and an empty
// root directory.
fn format(blk: virtio.Block) -> err {
    zero_data(blk)
    os.store32(blk.data, SUPER_MAGIC)
    os.store32(blk.data + 4usize, FIRST_DATA)
    let super_error = virtio.block_write(blk, 0u64)
    if super_error != ok { ret super_error }
    zero_data(blk)
    ret virtio.block_write(blk, ROOT_DIR)
}

fn is_formatted(blk: virtio.Block) -> bool {
    if virtio.block_read(blk, 0u64) != ok { ret false }
    ret u32(os.load32(blk.data)) == SUPER_MAGIC
}

// Hand out the next free block, bumping the superblock's counter. The superblock is left in the
// sector buffer.
fn alloc_block(blk: virtio.Block) -> (u64, err) {
    let read_error = virtio.block_read(blk, 0u64)
    if read_error != ok { ret (0u64, read_error) }
    let next = usize(os.load32(blk.data + 4usize))
    os.store32(blk.data + 4usize, u32(next + 1usize))
    let write_error = virtio.block_write(blk, 0u64)
    if write_error != ok { ret (0u64, write_error) }
    ret (u64(next), ok)
}

fn name_eq(addr: usize, name: str) -> bool {
    if name.len > NAME_MAX { ret false }
    var i = 0usize
    while i < name.len {
        if os.load8(addr + i) != name[i] { ret false }
        i += 1usize
    }
    if name.len < NAME_MAX { ret os.load8(addr + name.len) == 0u8 }
    ret true
}

fn store_name(addr: usize, name: str) {
    var i = 0usize
    while i < NAME_MAX {
        if i < name.len { os.store8(addr + i, name[i]) } else { os.store8(addr + i, 0u8) }
        i += 1usize
    }
}

// Find `name` in the directory at `dir_block` (left in the sector buffer): its entry offset, data
// block, size and kind, found or not.
fn dir_lookup(blk: virtio.Block, dir_block: u64, name: str) -> (usize, u64, usize, u8, bool) {
    if virtio.block_read(blk, dir_block) != ok { ret (0usize, 0u64, 0usize, KIND_EMPTY, false) }
    var i = 0usize
    while i < ENTRIES {
        let off = i * ENTRY_SIZE
        let kind = os.load8(blk.data + off + KIND_OFF)
        if kind != KIND_EMPTY && name_eq(blk.data + off + NAME_OFF, name) {
            ret (off, u64(os.load32(blk.data + off + BLOCK_OFF)), usize(os.load32(blk.data + off + SIZE_OFF)), kind, true)
        }
        i += 1usize
    }
    ret (0usize, 0u64, 0usize, KIND_EMPTY, false)
}

// Walk `path`'s components as directories from the root, returning the directory block they name.
// An empty path or "/" is the root itself.
fn resolve_dir(blk: virtio.Block, path: str) -> (u64, err) {
    var dir = ROOT_DIR
    var i = 0usize
    while i < path.len {
        if path[i] == SLASH {
            i += 1usize
        } else {
            let start = i
            while i < path.len && path[i] != SLASH { i += 1usize }
            let (off, data_block, size, kind, found) = dir_lookup(blk, dir, path[start..i])
            if !found { ret (0u64, NotFound) }
            if kind != KIND_DIR { ret (0u64, NotDirectory) }
            dir = data_block
        }
    }
    ret (dir, ok)
}

// Split a path into its parent directory and leaf name: "/a/b" -> ("/a", "b"); "/x" -> ("/", "x").
fn parent_leaf(path: str) -> (str, str) {
    var last = 0usize
    var i = 0usize
    while i < path.len {
        if path[i] == SLASH { last = i }
        i += 1usize
    }
    if last == 0usize { ret ("/", path[1usize..path.len]) }
    ret (path[0usize..last], path[last + 1usize..path.len])
}

// Add an entry `name` of `kind` to `dir_block`, allocating its data (or directory) block. A new
// directory block is zeroed. Returns the allocated block.
fn add_entry(blk: virtio.Block, dir_block: u64, name: str, kind: u8) -> (u64, err) {
    if name.len > NAME_MAX { ret (0u64, NameTooLong) }
    let (data_block, alloc_error) = alloc_block(blk)
    if alloc_error != ok { ret (0u64, alloc_error) }
    if kind == KIND_DIR {
        zero_data(blk)
        let dir_write = virtio.block_write(blk, data_block)
        if dir_write != ok { ret (0u64, dir_write) }
    }
    if virtio.block_read(blk, dir_block) != ok { ret (0u64, NotFormatted) }
    var slot = ENTRIES
    var i = 0usize
    while i < ENTRIES {
        if os.load8(blk.data + i * ENTRY_SIZE + KIND_OFF) == KIND_EMPTY {
            slot = i
            i = ENTRIES
        } else {
            i += 1usize
        }
    }
    if slot == ENTRIES { ret (0u64, DirFull) }
    let off = slot * ENTRY_SIZE
    store_name(blk.data + off + NAME_OFF, name)
    os.store8(blk.data + off + KIND_OFF, kind)
    os.store32(blk.data + off + BLOCK_OFF, u32(data_block))
    os.store32(blk.data + off + SIZE_OFF, 0u32)
    let write_error = virtio.block_write(blk, dir_block)
    if write_error != ok { ret (0u64, write_error) }
    ret (data_block, ok)
}

// Record the size of `name` in `dir_block`.
fn set_size(blk: virtio.Block, dir_block: u64, name: str, size: usize) -> err {
    if virtio.block_read(blk, dir_block) != ok { ret NotFormatted }
    var i = 0usize
    while i < ENTRIES {
        let off = i * ENTRY_SIZE
        if os.load8(blk.data + off + KIND_OFF) != KIND_EMPTY && name_eq(blk.data + off + NAME_OFF, name) {
            os.store32(blk.data + off + SIZE_OFF, u32(size))
            ret virtio.block_write(blk, dir_block)
        }
        i += 1usize
    }
    ret NotFound
}

// Create an empty directory at `path`.
fn mkdir(blk: virtio.Block, path: str) -> err {
    let (parent, leaf) = parent_leaf(path)
    let (dir_block, resolve_error) = resolve_dir(blk, parent)
    if resolve_error != ok { ret resolve_error }
    let (new_block, add_error) = add_entry(blk, dir_block, leaf, KIND_DIR)
    ret add_error
}

// Create an empty file at `path`.
fn create(blk: virtio.Block, path: str) -> err {
    let (parent, leaf) = parent_leaf(path)
    let (dir_block, resolve_error) = resolve_dir(blk, parent)
    if resolve_error != ok { ret resolve_error }
    let (new_block, add_error) = add_entry(blk, dir_block, leaf, KIND_FILE)
    ret add_error
}

// (C125) A file is a run of consecutive blocks from its entry's block, as many as its size needs; at most
// MAX_FILE bytes.
const MAX_FILE: usize = 4096usize

// Set the first block of `name` in `dir_block` (a file that outgrew its run moves to a new one).
fn set_block(blk: virtio.Block, dir_block: u64, name: str, data_block: u64) -> err {
    if virtio.block_read(blk, dir_block) != ok { ret NotFormatted }
    var i = 0usize
    while i < ENTRIES {
        let off = i * ENTRY_SIZE
        if os.load8(blk.data + off + KIND_OFF) != KIND_EMPTY && name_eq(blk.data + off + NAME_OFF, name) {
            os.store32(blk.data + off + BLOCK_OFF, u32(data_block))
            ret virtio.block_write(blk, dir_block)
        }
        i += 1usize
    }
    ret NotFound
}

// Write `len` bytes from `src` to the file `path`, creating it if absent, capped at MAX_FILE: the file keeps its
// run of blocks when the new content fits it and takes a new run at the end of the disk when it does not.
fn write(blk: virtio.Block, path: str, src: usize, len: usize) -> err {
    let (parent, leaf) = parent_leaf(path)
    let (dir_block, resolve_error) = resolve_dir(blk, parent)
    if resolve_error != ok { ret resolve_error }
    let (off, found_block, size, kind, found) = dir_lookup(blk, dir_block, leaf)
    var data_block = found_block
    if !found {
        let (new_block, add_error) = add_entry(blk, dir_block, leaf, KIND_FILE)
        if add_error != ok { ret add_error }
        data_block = new_block
    }
    var count = len
    if count > MAX_FILE { count = MAX_FILE }
    var needed = (count + BLOCK_SIZE - 1usize) / BLOCK_SIZE
    if needed == 0usize { needed = 1usize }
    let have = (size + BLOCK_SIZE - 1usize) / BLOCK_SIZE
    if found && needed > have && needed > 1usize {
        // A larger run: the first block of it is the one the entry has, so take the first and the rest follow.
        let (first, first_error) = alloc_block(blk)
        if first_error != ok { ret first_error }
        data_block = first
        var extra = 1usize
        while extra < needed {
            let (more, more_error) = alloc_block(blk)
            if more_error != ok { ret more_error }
            extra += 1usize
        }
        let moved = set_block(blk, dir_block, leaf, data_block)
        if moved != ok { ret moved }
    } else if !found && needed > 1usize {
        // A new file got one block from add_entry; the rest of the run is allocated after it.
        var extra = 1usize
        while extra < needed {
            let (more, more_error) = alloc_block(blk)
            if more_error != ok { ret more_error }
            extra += 1usize
        }
    }
    var block_index = 0usize
    while block_index < needed {
        zero_data(blk)
        var i = 0usize
        while i < BLOCK_SIZE && block_index * BLOCK_SIZE + i < count {
            os.store8(blk.data + i, os.load8(src + block_index * BLOCK_SIZE + i))
            i += 1usize
        }
        let write_error = virtio.block_write(blk, data_block + u64(block_index))
        if write_error != ok { ret write_error }
        block_index += 1usize
    }
    ret set_size(blk, dir_block, leaf, count)
}

// Read the file `path` into `dst`, up to `max` bytes; the number read comes back.
fn read(blk: virtio.Block, path: str, dst: usize, max: usize) -> (usize, err) {
    let (parent, leaf) = parent_leaf(path)
    let (dir_block, resolve_error) = resolve_dir(blk, parent)
    if resolve_error != ok { ret (0usize, resolve_error) }
    let (off, data_block, size, kind, found) = dir_lookup(blk, dir_block, leaf)
    if !found { ret (0usize, NotFound) }
    var count = size
    if count > max { count = max }
    var done = 0usize
    var block_index = 0usize
    while done < count {
        if virtio.block_read(blk, data_block + u64(block_index)) != ok { ret (0usize, NotFormatted) }
        var i = 0usize
        while i < BLOCK_SIZE && done < count {
            os.store8(dst + done, os.load8(blk.data + i))
            i += 1usize
            done += 1usize
        }
        block_index += 1usize
    }
    ret (count, ok)
}

// The size and kind of `path`, and whether it exists (the open/stat query).
fn stat(blk: virtio.Block, path: str) -> (usize, u8, bool) {
    let (parent, leaf) = parent_leaf(path)
    let (dir_block, resolve_error) = resolve_dir(blk, parent)
    if resolve_error != ok { ret (0usize, KIND_EMPTY, false) }
    let (off, data_block, size, kind, found) = dir_lookup(blk, dir_block, leaf)
    ret (size, kind, found)
}

// List the directory `path` into `dst` (up to `max` bytes) as its entries' names, each followed by
// a newline. The entry count and the bytes written come back.
fn list(blk: virtio.Block, path: str, dst: usize, max: usize) -> (usize, usize, err) {
    let (dir_block, resolve_error) = resolve_dir(blk, path)
    if resolve_error != ok { ret (0usize, 0usize, resolve_error) }
    if virtio.block_read(blk, dir_block) != ok { ret (0usize, 0usize, NotFormatted) }
    var count = 0usize
    var at = 0usize
    var i = 0usize
    while i < ENTRIES {
        let off = i * ENTRY_SIZE
        if os.load8(blk.data + off + KIND_OFF) != KIND_EMPTY {
            count += 1usize
            var j = 0usize
            var naming = true
            while naming && j < NAME_MAX {
                let c = os.load8(blk.data + off + NAME_OFF + j)
                if c == 0u8 {
                    naming = false
                } else {
                    if at < max { os.store8(dst + at, c) }
                    at += 1usize
                    j += 1usize
                }
            }
            if at < max { os.store8(dst + at, 10u8) }
            at += 1usize
        }
        i += 1usize
    }
    if at > max { at = max }
    ret (count, at, ok)
}

// Move the file or directory `path` into the directory `dest`, keeping its blocks and its name: NameTaken when
// `dest` has that name or is where it already is, DirFull when `dest` has no free entry.
fn move(blk: virtio.Block, path: str, dest: str) -> err {
    let (parent, leaf) = parent_leaf(path)
    let (src_dir, src_error) = resolve_dir(blk, parent)
    if src_error != ok { ret src_error }
    let (dst_dir, dst_error) = resolve_dir(blk, dest)
    if dst_error != ok { ret dst_error }
    if src_dir == dst_dir { ret NameTaken }
    let (src_off, data_block, size, kind, found) = dir_lookup(blk, src_dir, leaf)
    if !found { ret NotFound }
    if kind == KIND_DIR && dst_dir == data_block { ret NotDirectory }
    if virtio.block_read(blk, dst_dir) != ok { ret NotFormatted }
    var slot = ENTRIES
    var i = 0usize
    while i < ENTRIES {
        let off = i * ENTRY_SIZE
        let entry_kind = os.load8(blk.data + off + KIND_OFF)
        if entry_kind != KIND_EMPTY && name_eq(blk.data + off + NAME_OFF, leaf) { ret NameTaken }
        if entry_kind == KIND_EMPTY && slot == ENTRIES { slot = i }
        i += 1usize
    }
    if slot == ENTRIES { ret DirFull }
    let at = slot * ENTRY_SIZE
    store_name(blk.data + at + NAME_OFF, leaf)
    os.store8(blk.data + at + KIND_OFF, kind)
    os.store32(blk.data + at + BLOCK_OFF, u32(data_block))
    os.store32(blk.data + at + SIZE_OFF, u32(size))
    let dst_write = virtio.block_write(blk, dst_dir)
    if dst_write != ok { ret dst_write }
    if virtio.block_read(blk, src_dir) != ok { ret NotFormatted }
    os.store8(blk.data + src_off + KIND_OFF, KIND_EMPTY)
    ret virtio.block_write(blk, src_dir)
}

// Give the file or directory `path` a new leaf name in the same directory; NameTaken when that name exists.
fn rename(blk: virtio.Block, path: str, new_name: str) -> err {
    if new_name.len == 0usize || new_name.len > NAME_MAX { ret NameTooLong }
    let (parent, leaf) = parent_leaf(path)
    let (dir_block, resolve_error) = resolve_dir(blk, parent)
    if resolve_error != ok { ret resolve_error }
    if virtio.block_read(blk, dir_block) != ok { ret NotFormatted }
    var i = 0usize
    while i < ENTRIES {
        let off = i * ENTRY_SIZE
        if os.load8(blk.data + off + KIND_OFF) != KIND_EMPTY && name_eq(blk.data + off + NAME_OFF, new_name) { ret NameTaken }
        i += 1usize
    }
    i = 0usize
    while i < ENTRIES {
        let off = i * ENTRY_SIZE
        if os.load8(blk.data + off + KIND_OFF) != KIND_EMPTY && name_eq(blk.data + off + NAME_OFF, leaf) {
            var j = 0usize
            while j < NAME_MAX {
                os.store8(blk.data + off + NAME_OFF + j, 0u8)
                j += 1usize
            }
            store_name(blk.data + off + NAME_OFF, new_name)
            ret virtio.block_write(blk, dir_block)
        }
        i += 1usize
    }
    ret NotFound
}

// Remove the file or directory `path` by clearing its directory entry (its blocks are not
// reclaimed).
fn remove(blk: virtio.Block, path: str) -> err {
    let (parent, leaf) = parent_leaf(path)
    let (dir_block, resolve_error) = resolve_dir(blk, parent)
    if resolve_error != ok { ret resolve_error }
    if virtio.block_read(blk, dir_block) != ok { ret NotFormatted }
    var i = 0usize
    while i < ENTRIES {
        let off = i * ENTRY_SIZE
        if os.load8(blk.data + off + KIND_OFF) != KIND_EMPTY && name_eq(blk.data + off + NAME_OFF, leaf) {
            os.store8(blk.data + off + KIND_OFF, KIND_EMPTY)
            ret virtio.block_write(blk, dir_block)
        }
        i += 1usize
    }
    ret NotFound
}
