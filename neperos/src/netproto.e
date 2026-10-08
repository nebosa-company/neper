// The NeperOS socket protocol (D2247, C117), shared by the network server and its clients. A client
// holds two endpoint capabilities and nothing else of the network: requests go out on one, replies
// come back on the other, one word per rendezvous. A byte string is a length word and then the bytes
// packed eight to a word, little end first, so a kilobyte costs 130 rendezvous rather than 1025.
//
//   CONNECT  host string, port, secure     -> result       (a name is resolved; secure = TLS 1.3 with
//                                                            the chain and the host name checked)
//   SEND     byte string                   -> result
//   RECV     max                           -> result, byte string  (an empty string is the peer's close)
//   CLOSE                                  -> result
//   SET_DNS  address word, port            -> result       (the resolver to ask; DHCP's by default)
//   QUIT                                    ends the server
//
// One connection is open at a time: apps run one at a time on the phone, and the server refuses a
// CONNECT while another is open.
use e.os

const OP_QUIT: usize = 0usize
const OP_CONNECT: usize = 1usize
const OP_SEND: usize = 2usize
const OP_RECV: usize = 3usize
const OP_CLOSE: usize = 4usize
const OP_SET_DNS: usize = 5usize

const R_OK: usize = 0usize
const R_NO_NETWORK: usize = 1usize
const R_RESOLVE: usize = 2usize
const R_CONNECT: usize = 3usize
const R_TLS: usize = 4usize
const R_IO: usize = 5usize
const R_NOT_CONNECTED: usize = 6usize
const R_BUSY: usize = 7usize
const R_BAD: usize = 8usize

const NO_SLOT: usize = 99usize

// The largest byte string a single SEND or RECV carries.
const CHUNK: usize = 2048usize

// Send `len` bytes at `addr` over `slot`: the length word, then the packed words.
fn send_bytes(slot: usize, addr: usize, len: usize) {
    let header = os.send(slot, len, NO_SLOT)
    var at = 0usize
    while at < len {
        var word = 0usize
        var j = 0usize
        while j < 8usize && at + j < len {
            word = word | (usize(os.load8(addr + at + j)) << usize(8usize * j))
            j += 1usize
        }
        let sent = os.send(slot, word, NO_SLOT)
        at += 8usize
    }
}

// Send a string the same way.
fn send_text(slot: usize, text: str) {
    let header = os.send(slot, text.len, NO_SLOT)
    var at = 0usize
    while at < text.len {
        var word = 0usize
        var j = 0usize
        while j < 8usize && at + j < text.len {
            word = word | (usize(text[at + j]) << usize(8usize * j))
            j += 1usize
        }
        let sent = os.send(slot, word, NO_SLOT)
        at += 8usize
    }
}

// Receive a byte string into `dst`, at most `max` bytes of it kept; the rest of the words are
// drained so the two sides stay in step. Returns the count kept.
fn recv_bytes(slot: usize, dst: usize, max: usize) -> usize {
    let len = os.recv(slot, NO_SLOT)
    var kept = 0usize
    var at = 0usize
    while at < len {
        let word = os.recv(slot, NO_SLOT)
        var j = 0usize
        while j < 8usize && at + j < len {
            if kept < max {
                os.store8(dst + kept, u8((word >> usize(8usize * j)) & 255usize))
                kept += 1usize
            }
            j += 1usize
        }
        at += 8usize
    }
    ret kept
}
