// The C106 filesystem test program (D2152): an EL0 block-device server the kernel starts on the
// `-append fswrite` / `fsread` boots. On write it formats the disk if blank, creates a file and
// writes a greeting; on read it reads the greeting back. Booting fswrite then fsread on the same
// disk image proves the filesystem persists across a reboot. The mode is its name's third letter
// (`fswrite` vs `fsread`).
use e.mem
use e.os
use virtio
use fs

// The aux area the kernel fills for a driver server (D2138), at USER_BASE + vm.AUX_OFF.
const AUX: usize = 548684165120usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

// The block device from the aux area the kernel filled: common-config, notify, multiplier, DMA
// pool and device-config addresses (D2146, D2149). Reading it also points the transport's pool.
fn read_device() -> virtio.Device {
    var device: virtio.Device = zero
    device.common = usize(os.load64(AUX))
    device.notify = usize(os.load64(AUX + 8usize))
    device.notify_multiplier = u32(os.load64(AUX + 16usize))
    virtio.pool_set(usize(os.load64(AUX + 24usize)), usize(os.load64(AUX + 32usize)))
    device.config = usize(os.load64(AUX + 40usize))
    ret device
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 0usize { ret mem.Exhausted }
    let name = args[0usize]
    let write_mode = name.len > 2usize && name[2usize] == 119u8
    let device = read_device()
    let (blk, open_error) = virtio.block_open(device)
    if open_error != ok {
        say("fs block open failed\n")
        ret ok
    }
    if write_mode {
        if !fs.is_formatted(blk) {
            let format_error = fs.format(blk)
            if format_error != ok {
                say("fs format failed\n")
                ret ok
            }
            say("fs formatted\n")
        }
        let mkdir_error = fs.mkdir(blk, "/docs")
        if mkdir_error != ok {
            say("fs mkdir failed\n")
            ret ok
        }
        let greeting = "hello neperos fs\n"
        let (buffer, buffer_error) = mem.alloc[u8](a, greeting.len)
        if buffer_error != ok { ret buffer_error }
        var i = 0usize
        while i < greeting.len {
            buffer[i] = greeting[i]
            i += 1usize
        }
        let write_error = fs.write(blk, "/docs/greeting", mem.address_of(&buffer[0usize]), greeting.len)
        if write_error != ok {
            say("fs write failed\n")
            ret ok
        }
        say("fs wrote /docs/greeting\n")
        ret ok
    }
    let (out, out_error) = mem.alloc[u8](a, 64usize)
    if out_error != ok { ret out_error }
    let (count, read_error) = fs.read(blk, "/docs/greeting", mem.address_of(&out[0usize]), 64usize)
    if read_error != ok {
        say("fs read failed\n")
        ret ok
    }
    say("fs read: ")
    say(out[0usize..count])
    ret ok
}
