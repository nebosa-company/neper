// The app side of the NeperOS network (D2247, C117): a connection by host name through the two
// endpoint capabilities the kernel grants an app that may use the network (slot 3 sends requests, slot
// 4 receives replies). An app that was granted neither cannot reach the server -- the kernel refuses
// its send -- so the capability is the only switch. The protocol is netproto.e.
use e.os
use netproto

const REQ: usize = 3usize
const REP: usize = 4usize

fn result() -> usize {
    ret os.recv(REP, netproto.NO_SLOT)
}

// Open a connection to `host`:`port`; `secure` runs TLS 1.3 against the bundled roots with `host`
// as the name to match. A name is resolved by the server. Returns a netproto.R_* result, R_OK on success.
fn connect(host: str, port: u16, secure: bool) -> usize {
    let op = os.send(REQ, netproto.OP_CONNECT, netproto.NO_SLOT)
    netproto.send_text(REQ, host)
    let port_word = os.send(REQ, usize(port), netproto.NO_SLOT)
    var secure_word = 0usize
    if secure { secure_word = 1usize }
    let secure_sent = os.send(REQ, secure_word, netproto.NO_SLOT)
    ret result()
}

// Send `len` bytes at `addr`, in chunks the server accepts.
fn send(addr: usize, len: usize) -> usize {
    var at = 0usize
    while at < len {
        var n = len - at
        if n > netproto.CHUNK { n = netproto.CHUNK }
        let op = os.send(REQ, netproto.OP_SEND, netproto.NO_SLOT)
        netproto.send_bytes(REQ, addr + at, n)
        let r = result()
        if r != netproto.R_OK { ret r }
        at += n
    }
    ret netproto.R_OK
}

// Receive up to `max` bytes into `dst` (at most netproto.CHUNK per call). Zero bytes with R_OK is the
// peer's close.
fn recv(dst: usize, max: usize) -> (usize, usize) {
    let op = os.send(REQ, netproto.OP_RECV, netproto.NO_SLOT)
    let want = os.send(REQ, max, netproto.NO_SLOT)
    let r = result()
    if r != netproto.R_OK { ret (0usize, r) }
    ret (netproto.recv_bytes(REP, dst, max), netproto.R_OK)
}

fn close() -> usize {
    let op = os.send(REQ, netproto.OP_CLOSE, netproto.NO_SLOT)
    ret result()
}

// Point the server at a resolver other than DHCP's (the test boot's DNS responder on the host).
fn set_dns(address: u32, port: u16) -> usize {
    let op = os.send(REQ, netproto.OP_SET_DNS, netproto.NO_SLOT)
    let a = os.send(REQ, usize(address), netproto.NO_SLOT)
    let p = os.send(REQ, usize(port), netproto.NO_SLOT)
    ret result()
}

fn quit() {
    let op = os.send(REQ, netproto.OP_QUIT, netproto.NO_SLOT)
}
