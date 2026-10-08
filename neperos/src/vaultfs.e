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
