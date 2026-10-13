// The NeperOS filesystem server (D2153, C106): an EL0 user-mode server that alone holds the block
// device's capability -- the kernel maps the device and a DMA pool into its space and grants it the
// request endpoint (slot 2, receive) and the reply endpoint (slot 3, send). It opens the block
// device, then serves open, read, write, close, list, mkdir and remove over IPC (fsproto.e) until a
// client sends the quit op. No client touches the block device; every operation is a capability-
// gated request, and a client the kernel granted no endpoint capability is refused by the kernel
// before it reaches the server.
use e.mem
use e.os
use e.time
use virtio
use fs
use fsproto

// The aux area the kernel fills for a driver server, at USER_BASE + vm.AUX_OFF (D2138).
const AUX: usize = 548684165120usize
// The endpoint capability slots the kernel grants this server: requests arrive on 2, replies go on
// 3 (slots 0 and 1 are the console and the device notification from start_driver_server).
const REQ: usize = 2usize
const REP: usize = 3usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn read_device() -> virtio.Device {
    var device: virtio.Device = zero
    device.common = usize(os.load64(AUX))
    device.notify = usize(os.load64(AUX + 8usize))
    device.notify_multiplier = u32(os.load64(AUX + 16usize))
    virtio.pool_set(usize(os.load64(AUX + 24usize)), usize(os.load64(AUX + 32usize)))
    device.config = usize(os.load64(AUX + 40usize))
    ret device
}

// A one-word result reply: ok or err for the operations that carry no payload back.
fn reply(result_error: err) {
    if result_error == ok {
        let sent = os.send(REP, fsproto.RESULT_OK, fsproto.NO_SLOT)
    } else {
        let sent = os.send(REP, fsproto.RESULT_ERR, fsproto.NO_SLOT)
    }
}

// (D4810) The apps numbered from here are installed apps, confined to their own directory.
const CONFINED_FROM: usize = 100usize

// The decimal digits of `n` (at most three) after the `/d` of a confined app's directory: `/d101`; its length.
fn scope_root_len(app: usize) -> usize {
    if app >= 100usize { ret 5usize }
    if app >= 10usize { ret 4usize }
    ret 3usize
}

// `path` inside app `app`'s directory: `/d<app>` then the path (a path of "/" or "" is the directory itself); written
// to `out`, its length.
fn scoped_path(app: usize, path: str, out: []u8) -> usize {
    var n = 0usize
    out[0usize] = 47u8
    out[1usize] = 100u8
    n = 2usize
    if app >= 100usize {
        out[n] = u8(48usize + app / 100usize % 10usize)
        n += 1usize
    }
    if app >= 10usize {
        out[n] = u8(48usize + app / 10usize % 10usize)
        n += 1usize
    }
    out[n] = u8(48usize + app % 10usize)
    n += 1usize
    var i = 0usize
    // A path without a leading slash gets one; "/" alone adds nothing.
    if path.len > 0usize && path[0usize] != 47u8 {
        out[n] = 47u8
        n += 1usize
    }
    while i < path.len && n < out.len {
        if !(i == 0usize && path.len == 1usize && path[0usize] == 47u8) {
            out[n] = path[i]
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    let device = read_device()
    let (blk, open_error) = virtio.block_open(device)
    if open_error != ok {
        say("fs server block open failed\n")
        ret ok
    }
    // Lay down a fresh filesystem on a blank disk; a disk a previous boot already formatted keeps
    // its contents, so a reboot reads back what was written.
    if !fs.is_formatted(blk) {
        let format_error = fs.format(blk)
        if format_error != ok {
            say("fs server format failed\n")
            ret ok
        }
        say("fs server formatted\n")
    }
    say("fs server up\n")
    var pathbuf: [64]u8 = zero
    var databuf: [4096]u8 = zero
    var namebuf: [512]u8 = zero
    var filebuf: [4096]u8 = zero
    let path_addr = mem.address_of(&pathbuf[0usize])
    let data_addr = mem.address_of(&databuf[0usize])
    let name_addr = mem.address_of(&namebuf[0usize])
    let file_addr = mem.address_of(&filebuf[0usize])
    // (D4810) The kernel stamps the sender's app number in the top byte of every word of a request. An installed app (a
    // number of 100 and over: the kernel numbers them 100 to 199 by the image) is confined to its own directory `/d<N>`:
    // every path it sends is that directory's, and it cannot stop the server. Built-in apps (numbers under 100) and the
    // servers (0) see the whole disk as before.
    var scope: [80]u8 = zero
    var scope_two: [80]u8 = zero
    var made: [256]bool = zero
    var running = true
    while running {
        let word = os.recv(REQ, fsproto.NO_SLOT)
        let op = word & fsproto.STAMP_MASK
        let app = word >> 56usize
        let confined = app >= CONFINED_FROM
        // The clock for the entries this request makes or writes.
        let (stamp, clock_error) = time.now()
        if clock_error == ok { fs.set_day(usize(stamp.nanos / 1000000000i64) / 86400usize) }
        if op == fsproto.OP_QUIT {
            if !confined { running = false }
        } else if op == fsproto.OP_STATS {
            var used = 0usize
            if virtio.block_read(blk, 0u64) == ok { used = usize(os.load32(blk.data + 4usize)) }
            let sent = os.send(REP, fsproto.RESULT_OK, fsproto.NO_SLOT)
            let used_sent = os.send(REP, used, fsproto.NO_SLOT)
            let total_sent = os.send(REP, usize(blk.sectors), fsproto.NO_SLOT)
        } else {
            let plen = fsproto.recv_bytes(REQ, path_addr, 64usize)
            var path = pathbuf[0usize..plen]
            if confined {
                let scoped_len = scoped_path(app, path, scope[0usize..80usize])
                path = scope[0usize..scoped_len]
                if !made[app & 255usize] {
                    made[app & 255usize] = true
                    let root_made = fs.mkdir(blk, scope[0usize..scope_root_len(app)])
                }
            }
            if op == fsproto.OP_RENAME {
                let nlen = fsproto.recv_bytes(REQ, data_addr, 64usize)
                reply(fs.rename(blk, path, databuf[0usize..nlen]))
            } else if op == fsproto.OP_RESERVE {
                let size_word = os.recv(REQ, fsproto.NO_SLOT) & fsproto.STAMP_MASK
                reply(fs.reserve(blk, path, size_word))
            } else if op == fsproto.OP_WRITE_AT {
                let offset_word = os.recv(REQ, fsproto.NO_SLOT) & fsproto.STAMP_MASK
                let piece = fsproto.recv_packed7(REQ, data_addr, 4096usize)
                reply(fs.write_at(blk, path, offset_word, data_addr, piece))
            } else if op == fsproto.OP_READ_AT {
                let offset_word = os.recv(REQ, fsproto.NO_SLOT) & fsproto.STAMP_MASK
                var want = os.recv(REQ, fsproto.NO_SLOT) & fsproto.STAMP_MASK
                if want > 4096usize { want = 4096usize }
                let (got, read_error) = fs.read_at(blk, path, offset_word, file_addr, want)
                var n = got
                if read_error == ok {
                    let sent = os.send(REP, fsproto.RESULT_OK, fsproto.NO_SLOT)
                } else {
                    let sent = os.send(REP, fsproto.RESULT_ERR, fsproto.NO_SLOT)
                    n = 0usize
                }
                fsproto.send_packed(REP, file_addr, n)
            } else if op == fsproto.OP_MOVE {
                let dlen = fsproto.recv_bytes(REQ, data_addr, 64usize)
                var destination = databuf[0usize..dlen]
                if confined {
                    let destination_len = scoped_path(app, destination, scope_two[0usize..80usize])
                    destination = scope_two[0usize..destination_len]
                }
                reply(fs.move(blk, path, destination))
            } else if op == fsproto.OP_STAT {
                let (size, kind, found) = fs.stat(blk, path)
                if found {
                    let sent = os.send(REP, fsproto.RESULT_OK, fsproto.NO_SLOT)
                } else {
                    let sent = os.send(REP, fsproto.RESULT_ERR, fsproto.NO_SLOT)
                }
                let size_sent = os.send(REP, size, fsproto.NO_SLOT)
                let kind_sent = os.send(REP, usize(kind), fsproto.NO_SLOT)
                let day_sent = os.send(REP, fs.stat_day(blk, path), fsproto.NO_SLOT)
            } else if op == fsproto.OP_MKDIR {
                reply(fs.mkdir(blk, path))
            } else {
                if op == fsproto.OP_WRITE {
                    let dlen = fsproto.recv_bytes(REQ, data_addr, 4096usize)
                    if confined {
                        say("fs confined write ")
                        say(path)
                        say("\n")
                    }
                    reply(fs.write(blk, path, data_addr, dlen))
                } else {
                    if op == fsproto.OP_REMOVE {
                        reply(fs.remove(blk, path))
                    } else {
                        if op == fsproto.OP_CLOSE {
                            let sent = os.send(REP, fsproto.RESULT_OK, fsproto.NO_SLOT)
                        } else {
                            if op == fsproto.OP_OPEN {
                                let (size, kind, found) = fs.stat(blk, path)
                                if found {
                                    let sent = os.send(REP, fsproto.RESULT_OK, fsproto.NO_SLOT)
                                } else {
                                    let sent = os.send(REP, fsproto.RESULT_ERR, fsproto.NO_SLOT)
                                }
                                let size_sent = os.send(REP, size, fsproto.NO_SLOT)
                            } else {
                                if op == fsproto.OP_READ {
                                    let (count, read_error) = fs.read(blk, path, file_addr, 4096usize)
                                    var n = count
                                    if read_error == ok {
                                        let sent = os.send(REP, fsproto.RESULT_OK, fsproto.NO_SLOT)
                                    } else {
                                        let sent = os.send(REP, fsproto.RESULT_ERR, fsproto.NO_SLOT)
                                        n = 0usize
                                    }
                                    fsproto.send_bytes(REP, file_addr, n)
                                } else {
                                    let (entries, bytes, list_error) = fs.list(blk, path, name_addr, 512usize)
                                    var n = bytes
                                    if list_error == ok {
                                        let sent = os.send(REP, fsproto.RESULT_OK, fsproto.NO_SLOT)
                                    } else {
                                        let sent = os.send(REP, fsproto.RESULT_ERR, fsproto.NO_SLOT)
                                        n = 0usize
                                    }
                                    fsproto.send_bytes(REP, name_addr, n)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    say("fs server done\n")
    ret ok
}
