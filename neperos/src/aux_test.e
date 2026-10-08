// The aux area must not alias the program's own image (D2248): a driver server reads its device
// addresses from a page the kernel maps at USER_BASE + vm.AUX_OFF, and the program image can be larger
// than 256 KB. The fixture pads this program's image with 0xA5 bytes to 300,000 bytes, so the old
// location (a fixed 64 bytes at 262,080) lies inside the padding; this program checks that the
// padding there is untouched and that the aux page really holds its device (a non-zero common
// configuration address). Started like the filesystem test, as the sole holder of the block device.
use e.mem
use e.os

const USER_BASE: usize = 548682072064usize
const AUX: usize = 548684165120usize
const OLD_AUX: usize = 548682334144usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var damaged = 0usize
    var i = 0usize
    while i < 64usize {
        if os.load8(OLD_AUX + i) != 165u8 { damaged += 1usize }
        i += 1usize
    }
    if damaged != 0usize {
        say("aux test: image bytes overwritten\n")
        ret ok
    }
    if os.load64(AUX) == 0u64 {
        say("aux test: aux page empty\n")
        ret ok
    }
    say("aux test: image intact, aux page filled\n")
    ret ok
}
