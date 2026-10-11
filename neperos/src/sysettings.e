// The client side of the settings server (C126): what an app or the shell holds to read the system
// settings and to change them. The kernel grants a process the two endpoints of the server in slots
// 9 (requests out) and 10 (replies in); a process it did not grant them to gets the kernel's refusal on
// the first send, which is how a caller learns there is no server (a single-app boot, an old archive).
//
// One word per rendezvous. Requests: GET_WORD; GET index; SET index value; RESET. Every reply is one
// word: the system word (theme.e) for GET_WORD, SET and RESET, the value for GET.
use e.os

const REQ: usize = 9usize
const REP: usize = 10usize
const NO_SLOT: usize = 99usize
const REFUSED: usize = 18446744073709551615usize

const OP_QUIT: usize = 0usize
const OP_GET_WORD: usize = 1usize
const OP_GET: usize = 2usize
const OP_SET: usize = 3usize
const OP_RESET: usize = 4usize
// The uninstalled apps, one bit per home-screen icon: GET_HIDDEN -> mask; SET_HIDDEN index flag -> mask.
const OP_GET_HIDDEN: usize = 5usize
const OP_SET_HIDDEN: usize = 6usize

// The system word, or 0 when there is no server.
fn word() -> usize {
    let sent = os.send(REQ, OP_GET_WORD, NO_SLOT)
    if sent == REFUSED { ret 0usize }
    ret os.recv(REP, NO_SLOT)
}

// Setting `index`, and whether the server answered.
fn get(index: usize) -> (usize, bool) {
    let sent = os.send(REQ, OP_GET, NO_SLOT)
    if sent == REFUSED { ret (0usize, false) }
    let sent_index = os.send(REQ, index, NO_SLOT)
    ret (os.recv(REP, NO_SLOT), true)
}

// Change a setting; the system word after it, or 0 when there is no server.
fn set(index: usize, value: usize) -> usize {
    let sent = os.send(REQ, OP_SET, NO_SLOT)
    if sent == REFUSED { ret 0usize }
    let sent_index = os.send(REQ, index, NO_SLOT)
    let sent_value = os.send(REQ, value, NO_SLOT)
    ret os.recv(REP, NO_SLOT)
}

// The mask of uninstalled apps (bit n is the icon with index n), or 0 when there is no server.
fn hidden() -> usize {
    let sent = os.send(REQ, OP_GET_HIDDEN, NO_SLOT)
    if sent == REFUSED { ret 0usize }
    ret os.recv(REP, NO_SLOT)
}

// Uninstall (flag 1) or reinstall (flag 0) icon `index`; the mask after it, or 0 when there is no server.
fn set_hidden(index: usize, flag: usize) -> usize {
    let sent = os.send(REQ, OP_SET_HIDDEN, NO_SLOT)
    if sent == REFUSED { ret 0usize }
    let sent_index = os.send(REQ, index, NO_SLOT)
    let sent_flag = os.send(REQ, flag, NO_SLOT)
    ret os.recv(REP, NO_SLOT)
}

// Every setting back to its default; the system word after it, or 0 when there is no server.
fn reset() -> usize {
    let sent = os.send(REQ, OP_RESET, NO_SLOT)
    if sent == REFUSED { ret 0usize }
    ret os.recv(REP, NO_SLOT)
}
