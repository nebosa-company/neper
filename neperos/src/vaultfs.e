// What the Secure app reaches outside itself (D2252, C116): the filesystem server over two endpoints
// (slots 5 and 6) and the random server over two more (slots 7 and 8). The kernel grants them to this app
// alone and only when the machine has a disk (the filesystem server) and an entropy device (the random
// server); an app that was granted neither gets the kernel's refusal on its first send, which is how the
// app learns it has no storage and runs its sample vault instead. The protocol is fsproto.e: a file is one
// 512-byte block, a path at most 64 bytes.
use e.os
use fsproto

const FS_REQ: usize = 5usize
const FS_REP: usize = 6usize
const RNG_REQ: usize = 7usize
const RNG_REP: usize = 8usize
const REFUSED: usize = 18446744073709551615usize

// Whether the filesystem is reachable at all, and if so whether `path` exists.
fn probe(path: str) -> (bool, bool) {
    let sent = os.send(FS_REQ, fsproto.OP_OPEN, fsproto.NO_SLOT)
    if sent == REFUSED { ret (false, false) }
    fsproto.send_str(FS_REQ, path)
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
    let size = os.recv(FS_REP, fsproto.NO_SLOT)
    ret (true, result == fsproto.RESULT_OK)
}

// Read `path` into [addr, addr + cap); the byte count, and whether it was read.
fn read(path: str, addr: usize, cap: usize) -> (usize, bool) {
    let sent = os.send(FS_REQ, fsproto.OP_READ, fsproto.NO_SLOT)
    if sent == REFUSED { ret (0usize, false) }
    fsproto.send_str(FS_REQ, path)
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
    let count = fsproto.recv_bytes(FS_REP, addr, cap)
    ret (count, result == fsproto.RESULT_OK)
}

// Write `len` bytes at `addr` to `path` (the directory must exist); true when the server stored it.
fn write(path: str, addr: usize, len: usize) -> bool {
    let sent = os.send(FS_REQ, fsproto.OP_WRITE, fsproto.NO_SLOT)
    if sent == REFUSED { ret false }
    fsproto.send_str(FS_REQ, path)
    fsproto.send_bytes(FS_REQ, addr, len)
    ret os.recv(FS_REP, fsproto.NO_SLOT) == fsproto.RESULT_OK
}

// (C126) The blocks allocated and the blocks the disk holds, and whether the filesystem answered.
fn stats() -> (usize, usize, bool) {
    let sent = os.send(FS_REQ, fsproto.OP_STATS, fsproto.NO_SLOT)
    if sent == REFUSED { ret (0usize, 0usize, false) }
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
    let used = os.recv(FS_REP, fsproto.NO_SLOT)
    let total = os.recv(FS_REP, fsproto.NO_SLOT)
    ret (used, total, result == fsproto.RESULT_OK)
}

// (C150) A file of any size in pieces: reserve it, then write 2 KB at a time from [addr, addr + len).
fn write_big(path: str, addr: usize, len: usize) -> bool {
    let sent = os.send(FS_REQ, fsproto.OP_RESERVE, fsproto.NO_SLOT)
    if sent == REFUSED { ret false }
    fsproto.send_str(FS_REQ, path)
    let size_sent = os.send(FS_REQ, len, fsproto.NO_SLOT)
    if os.recv(FS_REP, fsproto.NO_SLOT) != fsproto.RESULT_OK { ret false }
    var at = 0usize
    while at < len {
        var piece = len - at
        if piece > 2048usize { piece = 2048usize }
        let op_sent = os.send(FS_REQ, fsproto.OP_WRITE_AT, fsproto.NO_SLOT)
        fsproto.send_str(FS_REQ, path)
        let offset_sent = os.send(FS_REQ, at, fsproto.NO_SLOT)
        fsproto.send_packed(FS_REQ, addr + at, piece)
        if os.recv(FS_REP, fsproto.NO_SLOT) != fsproto.RESULT_OK { ret false }
        at += piece
    }
    ret true
}

// (C150) A file of any size in pieces into [addr, addr + cap): the bytes read, and whether it read.
fn read_big(path: str, addr: usize, cap: usize) -> (usize, bool) {
    var at = 0usize
    while at < cap {
        var want = cap - at
        if want > 2048usize { want = 2048usize }
        let sent = os.send(FS_REQ, fsproto.OP_READ_AT, fsproto.NO_SLOT)
        if sent == REFUSED { ret (0usize, false) }
        fsproto.send_str(FS_REQ, path)
        let offset_sent = os.send(FS_REQ, at, fsproto.NO_SLOT)
        let want_sent = os.send(FS_REQ, want, fsproto.NO_SLOT)
        let result = os.recv(FS_REP, fsproto.NO_SLOT)
        let got = fsproto.recv_packed(FS_REP, addr + at, want)
        if result != fsproto.RESULT_OK { ret (at, false) }
        at += got
        if got < want { ret (at, true) }
    }
    ret (at, true)
}

// (C152) Up to `cap` bytes of a file from byte `offset` of it, in pieces, into [addr, addr + cap): the bytes read, and
// whether it read. A file over what a viewer holds is read a window at a time.
fn read_from(path: str, offset: usize, addr: usize, cap: usize) -> (usize, bool) {
    var at = 0usize
    while at < cap {
        var want = cap - at
        if want > 2048usize { want = 2048usize }
        let sent = os.send(FS_REQ, fsproto.OP_READ_AT, fsproto.NO_SLOT)
        if sent == REFUSED { ret (0usize, false) }
        fsproto.send_str(FS_REQ, path)
        let offset_sent = os.send(FS_REQ, offset + at, fsproto.NO_SLOT)
        let want_sent = os.send(FS_REQ, want, fsproto.NO_SLOT)
        let result = os.recv(FS_REP, fsproto.NO_SLOT)
        let got = fsproto.recv_packed(FS_REP, addr + at, want)
        if result != fsproto.RESULT_OK { ret (at, false) }
        at += got
        if got < want { ret (at, true) }
    }
    ret (at, true)
}

// (C125) The size and kind (1 file, 2 directory) of `path`, and whether the filesystem answered and has it.
fn stat(path: str) -> (usize, usize, usize, bool) {
    let sent = os.send(FS_REQ, fsproto.OP_STAT, fsproto.NO_SLOT)
    if sent == REFUSED { ret (0usize, 0usize, 0usize, false) }
    fsproto.send_str(FS_REQ, path)
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
    let size = os.recv(FS_REP, fsproto.NO_SLOT)
    let kind = os.recv(FS_REP, fsproto.NO_SLOT)
    let day = os.recv(FS_REP, fsproto.NO_SLOT)
    ret (size, kind, day, result == fsproto.RESULT_OK)
}

// The names in directory `path`, one per line, into [addr, addr + cap): the byte count, and whether it listed.
fn list(path: str, addr: usize, cap: usize) -> (usize, bool) {
    let sent = os.send(FS_REQ, fsproto.OP_LIST, fsproto.NO_SLOT)
    if sent == REFUSED { ret (0usize, false) }
    fsproto.send_str(FS_REQ, path)
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
    let count = fsproto.recv_bytes(FS_REP, addr, cap)
    ret (count, result == fsproto.RESULT_OK)
}

// (C125) Move `path` into directory `dest`.
fn move(path: str, dest: str) -> bool {
    let sent = os.send(FS_REQ, fsproto.OP_MOVE, fsproto.NO_SLOT)
    if sent == REFUSED { ret false }
    fsproto.send_str(FS_REQ, path)
    fsproto.send_str(FS_REQ, dest)
    ret os.recv(FS_REP, fsproto.NO_SLOT) == fsproto.RESULT_OK
}

fn rename(path: str, new_name: str) -> bool {
    let sent = os.send(FS_REQ, fsproto.OP_RENAME, fsproto.NO_SLOT)
    if sent == REFUSED { ret false }
    fsproto.send_str(FS_REQ, path)
    fsproto.send_str(FS_REQ, new_name)
    ret os.recv(FS_REP, fsproto.NO_SLOT) == fsproto.RESULT_OK
}

fn remove(path: str) -> bool {
    let sent = os.send(FS_REQ, fsproto.OP_REMOVE, fsproto.NO_SLOT)
    if sent == REFUSED { ret false }
    fsproto.send_str(FS_REQ, path)
    ret os.recv(FS_REP, fsproto.NO_SLOT) == fsproto.RESULT_OK
}

fn mkdir(path: str) -> bool {
    let sent = os.send(FS_REQ, fsproto.OP_MKDIR, fsproto.NO_SLOT)
    if sent == REFUSED { ret false }
    fsproto.send_str(FS_REQ, path)
    ret os.recv(FS_REP, fsproto.NO_SLOT) == fsproto.RESULT_OK
}

// `words` * 8 random bytes at `addr` from the random server (op 1, a count, then the words); false when
// the app has no such capability.
fn random(addr: usize, words: usize) -> bool {
    let sent = os.send(RNG_REQ, 1usize, fsproto.NO_SLOT)
    if sent == REFUSED { ret false }
    let count = os.send(RNG_REQ, words, fsproto.NO_SLOT)
    var i = 0usize
    while i < words {
        os.store64(addr + i * 8usize, u64(os.recv(RNG_REP, fsproto.NO_SLOT)))
        i += 1usize
    }
    ret true
}
