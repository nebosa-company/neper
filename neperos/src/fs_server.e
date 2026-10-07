// The NeperOS filesystem server (D2153, C106): an EL0 user-mode server that alone holds the block
// device's capability -- the kernel maps the device and a DMA pool into its space and grants it the
// request endpoint (slot 2, receive) and the reply endpoint (slot 3, send). It opens the block
// device, then serves open, read, write, close, list, mkdir and remove over IPC (fsproto.e) until a
// client sends the quit op. No client touches the block device; every operation is a capability-
// gated request, and a client the kernel granted no endpoint capability is refused by the kernel
// before it reaches the server.
use e.mem
use e.os
use virtio
use fs
use fsproto

// The aux area the kernel fills for a driver server, at USER_BASE + vm.AUX_OFF (D2138).
const AUX: usize = 548682334144usize
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
    var databuf: [512]u8 = zero
    var namebuf: [512]u8 = zero
    var filebuf: [512]u8 = zero
    let path_addr = mem.address_of(&pathbuf[0usize])
    let data_addr = mem.address_of(&databuf[0usize])
    let name_addr = mem.address_of(&namebuf[0usize])
    let file_addr = mem.address_of(&filebuf[0usize])
    var running = true
    while running {
        let op = os.recv(REQ, fsproto.NO_SLOT)
        if op == fsproto.OP_QUIT {
            running = false
        } else {
            let plen = fsproto.recv_bytes(REQ, path_addr, 64usize)
            let path = pathbuf[0usize..plen]
            if op == fsproto.OP_MKDIR {
                reply(fs.mkdir(blk, path))
            } else {
                if op == fsproto.OP_WRITE {
                    let dlen = fsproto.recv_bytes(REQ, data_addr, 512usize)
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
                                    let (count, read_error) = fs.read(blk, path, file_addr, 512usize)
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
