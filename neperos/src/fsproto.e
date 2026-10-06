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
