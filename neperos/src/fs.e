// A minimal persistent filesystem on a virtio-block device (D2152, C106). The on-disk layout is
// 512-byte blocks: block 0 the superblock (a magic word, then the next free block as a bump
// allocator), block 1 the root directory, blocks 2+ handed out for file data. A directory is one
// block of sixteen 32-byte entries -- a 20-byte NUL-padded name, a kind byte (empty, file), the
// data block, and the size in bytes. This foundation keeps a flat root directory and single-block
// files (<= 512 bytes); directories, larger files and reclaiming removed blocks come with the
// server.
// ponytail: single-block files and a flat root; an inode with block pointers and a free bitmap are
// the upgrade when files outgrow a block or the directory outgrows sixteen names.
use e.os
use virtio

error NotFormatted
error DirFull
error NotFound
error NameTooLong

const SUPER_MAGIC: u32 = 0x4653454Eu32
const ROOT_DIR: u64 = 1u64
const FIRST_DATA: u32 = 2u32
const ENTRY_SIZE: usize = 32usize
const ENTRIES: usize = 16usize
const KIND_EMPTY: u8 = 0u8
const KIND_FILE: u8 = 1u8
const NAME_OFF: usize = 0usize
const KIND_OFF: usize = 20usize
const BLOCK_OFF: usize = 24usize
const SIZE_OFF: usize = 28usize
const NAME_MAX: usize = 20usize
const BLOCK_SIZE: usize = 512usize

// Fill the block's sector buffer with zeros, 8 bytes at a time.
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

// Whether block 0 carries the filesystem magic.
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

// Whether the 20-byte name at `addr` equals `name` (NUL-padded).
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

// Find a file `name` in the root directory: its data block and size come back, found or not. The
// root directory is left in the sector buffer.
fn find(blk: virtio.Block, name: str) -> (u64, usize, bool) {
    if virtio.block_read(blk, ROOT_DIR) != ok { ret (0u64, 0usize, false) }
    var i = 0usize
    while i < ENTRIES {
        let off = i * ENTRY_SIZE
        if os.load8(blk.data + off + KIND_OFF) == KIND_FILE && name_eq(blk.data + off + NAME_OFF, name) {
            ret (u64(os.load32(blk.data + off + BLOCK_OFF)), usize(os.load32(blk.data + off + SIZE_OFF)), true)
        }
        i += 1usize
    }
    ret (0u64, 0usize, false)
}

// Create an empty file `name` in the root directory, returning its data block. The directory is
// full when its sixteen entries are all taken.
fn create(blk: virtio.Block, name: str) -> (u64, err) {
    if name.len > NAME_MAX { ret (0u64, NameTooLong) }
    let (data_block, alloc_error) = alloc_block(blk)
    if alloc_error != ok { ret (0u64, alloc_error) }
    if virtio.block_read(blk, ROOT_DIR) != ok { ret (0u64, NotFormatted) }
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
    os.store8(blk.data + off + KIND_OFF, KIND_FILE)
    os.store32(blk.data + off + BLOCK_OFF, u32(data_block))
    os.store32(blk.data + off + SIZE_OFF, 0u32)
    let write_error = virtio.block_write(blk, ROOT_DIR)
    if write_error != ok { ret (0u64, write_error) }
    ret (data_block, ok)
}

// Set the recorded size of `name` in the root directory.
fn set_size(blk: virtio.Block, name: str, size: usize) -> err {
    if virtio.block_read(blk, ROOT_DIR) != ok { ret NotFormatted }
    var i = 0usize
    while i < ENTRIES {
        let off = i * ENTRY_SIZE
        if os.load8(blk.data + off + KIND_OFF) == KIND_FILE && name_eq(blk.data + off + NAME_OFF, name) {
            os.store32(blk.data + off + SIZE_OFF, u32(size))
            ret virtio.block_write(blk, ROOT_DIR)
        }
        i += 1usize
    }
    ret NotFound
}

// Write `len` bytes from `src` to the file `name`, capped at a block, and record the size.
fn write(blk: virtio.Block, name: str, src: usize, len: usize) -> err {
    let (data_block, size, found) = find(blk, name)
    if !found { ret NotFound }
    var count = len
    if count > BLOCK_SIZE { count = BLOCK_SIZE }
    zero_data(blk)
    var i = 0usize
    while i < count {
        os.store8(blk.data + i, os.load8(src + i))
        i += 1usize
    }
    let write_error = virtio.block_write(blk, data_block)
    if write_error != ok { ret write_error }
    ret set_size(blk, name, count)
}

// Read the file `name` into `dst`, up to `max` bytes; the number read comes back.
fn read(blk: virtio.Block, name: str, dst: usize, max: usize) -> (usize, err) {
    let (data_block, size, found) = find(blk, name)
    if !found { ret (0usize, NotFound) }
    var count = size
    if count > max { count = max }
    if virtio.block_read(blk, data_block) != ok { ret (0usize, NotFormatted) }
    var i = 0usize
    while i < count {
        os.store8(dst + i, os.load8(blk.data + i))
        i += 1usize
    }
    ret (count, ok)
}
