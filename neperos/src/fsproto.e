// The filesystem IPC protocol (D2153, C106), shared by the server and its clients. A client and
// the server rendezvous over two endpoints: requests travel client->server on one, replies
// server->client on the other (thread.e's IPC is one word per rendezvous, so a byte string is a
// length word then that many one-byte words). A request is an op word, then the path as a byte
// string, and for a write the data as a second byte string. A reply is a result word (0 ok, else
// 1), then for a read or a list the payload as a byte string, and for an open the file size word.
// Op 0 is quit: the server returns, and with every process exited the kernel powers off.
use e.os

const OP_QUIT: usize = 0usize
const OP_MKDIR: usize = 1usize
const OP_WRITE: usize = 2usize
const OP_READ: usize = 3usize
const OP_LIST: usize = 4usize
const OP_OPEN: usize = 5usize
const OP_CLOSE: usize = 6usize
const OP_REMOVE: usize = 7usize
// (C126) The space in use and the device's size, in blocks: no path follows the op; the reply is a result
// word, the blocks allocated (the superblock's counter) and the blocks the device holds.
const OP_STATS: usize = 8usize
// (C125) RENAME path, new name (a leaf, in the same directory) -> result; STAT path -> result, size, kind
// (0 none, 1 file, 2 directory).
const OP_RENAME: usize = 9usize
const OP_STAT: usize = 10usize
// MOVE path, destination directory -> result (the entry keeps its name and its blocks).
const OP_MOVE: usize = 11usize
// (C150) Files of any size, in pieces. RESERVE path, size word -> result: the file is made (or kept when its run
// is big enough) with a run of blocks for `size` bytes and that size. WRITE_AT path, offset word, packed bytes ->
// result. READ_AT path, offset word, max word -> result, packed bytes (eight bytes a word, little end first, so a
// kilobyte costs 130 rendezvous rather than 1025).
const OP_RESERVE: usize = 12usize
const OP_WRITE_AT: usize = 13usize
const OP_READ_AT: usize = 14usize

// A client's calls over its own two endpoint slots (`req` out, `rep` in), for processes that are not in vaultfs.e's
// fixed slots (the shell uses 6 and 7).
const REFUSED_SEND: usize = 18446744073709551615usize

// (C173) REMOVE path -> whether it was removed (a file, or an empty directory).
fn remove(req: usize, rep: usize, path: str) -> bool {
    let sent = os.send(req, OP_REMOVE, NO_SLOT)
    if sent == REFUSED_SEND { ret false }
    send_str(req, path)
    ret os.recv(rep, NO_SLOT) == RESULT_OK
}

fn mkdir(req: usize, rep: usize, path: str) -> bool {
    let sent = os.send(req, OP_MKDIR, NO_SLOT)
    if sent == REFUSED_SEND { ret false }
    send_str(req, path)
    ret os.recv(rep, NO_SLOT) == RESULT_OK
}

fn stat(req: usize, rep: usize, path: str) -> (usize, usize, usize, bool) {
    let sent = os.send(req, OP_STAT, NO_SLOT)
    if sent == REFUSED_SEND { ret (0usize, 0usize, 0usize, false) }
    send_str(req, path)
    let result = os.recv(rep, NO_SLOT)
    let size = os.recv(rep, NO_SLOT)
    let kind = os.recv(rep, NO_SLOT)
    let day = os.recv(rep, NO_SLOT)
    ret (size, kind, day, result == RESULT_OK)
}

fn list(req: usize, rep: usize, path: str, addr: usize, cap: usize) -> (usize, bool) {
    let sent = os.send(req, OP_LIST, NO_SLOT)
    if sent == REFUSED_SEND { ret (0usize, false) }
    send_str(req, path)
    let result = os.recv(rep, NO_SLOT)
    let count = recv_bytes(rep, addr, cap)
    ret (count, result == RESULT_OK)
}

// A file of any size, reserved and then written 2 KB at a time.
fn write_big(req: usize, rep: usize, path: str, addr: usize, len: usize) -> bool {
    let sent = os.send(req, OP_RESERVE, NO_SLOT)
    if sent == REFUSED_SEND { ret false }
    send_str(req, path)
    let size_sent = os.send(req, len, NO_SLOT)
    if os.recv(rep, NO_SLOT) != RESULT_OK { ret false }
    var at = 0usize
    while at < len {
        var piece = len - at
        if piece > 2048usize { piece = 2048usize }
        let op_sent = os.send(req, OP_WRITE_AT, NO_SLOT)
        send_str(req, path)
        let offset_sent = os.send(req, at, NO_SLOT)
        send_packed(req, addr + at, piece)
        if os.recv(rep, NO_SLOT) != RESULT_OK { ret false }
        at += piece
    }
    ret true
}

// A file of any size into [addr, addr + cap), 2 KB at a time: the bytes read, and whether it read.
fn read_big(req: usize, rep: usize, path: str, addr: usize, cap: usize) -> (usize, bool) {
    var at = 0usize
    while at < cap {
        var want = cap - at
        if want > 2048usize { want = 2048usize }
        let sent = os.send(req, OP_READ_AT, NO_SLOT)
        if sent == REFUSED_SEND { ret (0usize, false) }
        send_str(req, path)
        let offset_sent = os.send(req, at, NO_SLOT)
        let want_sent = os.send(req, want, NO_SLOT)
        let result = os.recv(rep, NO_SLOT)
        let got = recv_packed(rep, addr + at, want)
        if result != RESULT_OK { ret (at, false) }
        at += got
        if got < want { ret (at, true) }
    }
    ret (at, true)
}

// Send `len` bytes at `addr` over `ep_slot` packed eight to a word: the length word, then the words.
fn send_packed(ep_slot: usize, addr: usize, len: usize) {
    let header = os.send(ep_slot, len, NO_SLOT)
    var at = 0usize
    while at < len {
        var word = 0usize
        var j = 0usize
        while j < 8usize && at + j < len {
            word = word | (usize(os.load8(addr + at + j)) << (8usize * j))
            j += 1usize
        }
        let sent = os.send(ep_slot, word, NO_SLOT)
        at += 8usize
    }
}

// Receive a packed byte string into [addr, addr + cap); the byte count kept (the rest is drained).
fn recv_packed(ep_slot: usize, addr: usize, cap: usize) -> usize {
    let len = os.recv(ep_slot, NO_SLOT)
    var kept = 0usize
    var at = 0usize
    while at < len {
        let word = os.recv(ep_slot, NO_SLOT)
        var j = 0usize
        while j < 8usize && at + j < len {
            if kept < cap {
                os.store8(addr + kept, u8((word >> (8usize * j)) & 255usize))
                kept += 1usize
            }
            j += 1usize
        }
        at += 8usize
    }
    ret kept
}

const RESULT_OK: usize = 0usize
const RESULT_ERR: usize = 1usize

// A slot index past the capability space: no capability to grant on a send, nowhere to receive one.
const NO_SLOT: usize = 99usize

// Send `len` bytes of [addr, addr+len) over the endpoint capability in `ep_slot`: the length word,
// then one word per byte.
fn send_bytes(ep_slot: usize, addr: usize, len: usize) {
    let header = os.send(ep_slot, len, NO_SLOT)
    var i = 0usize
    while i < len {
        let sent = os.send(ep_slot, usize(os.load8(addr + i)), NO_SLOT)
        i += 1usize
    }
}

// Send a string over `ep_slot` as a byte string: the length word, then one word per byte. (The
// string's bytes are read with the index operator, so no address is needed -- a client sends path
// and data literals this way.)
fn send_str(ep_slot: usize, text: str) {
    let header = os.send(ep_slot, text.len, NO_SLOT)
    var i = 0usize
    while i < text.len {
        let sent = os.send(ep_slot, usize(text[i]), NO_SLOT)
        i += 1usize
    }
}

// Receive a byte string over `ep_slot` into [addr, addr+cap): read the length word, then that many
// one-byte words, storing the first `cap` of them. Every word is consumed so the stream stays in
// step even when the buffer is smaller; the stored count (min of length and cap) comes back.
fn recv_bytes(ep_slot: usize, addr: usize, cap: usize) -> usize {
    let len = os.recv(ep_slot, NO_SLOT)
    var i = 0usize
    while i < len {
        let byte = os.recv(ep_slot, NO_SLOT)
        if i < cap { os.store8(addr + i, u8(byte)) }
        i += 1usize
    }
    if len < cap { ret len }
    ret cap
}
