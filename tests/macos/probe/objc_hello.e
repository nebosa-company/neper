// The first Objective-C call from Neper: libobjc's runtime by `@import`, one `objc_msgSend` declaration per
// signature (a symbol named twice is one slot). Run on a Mac by the macos-probe workflow.
use e.mem
use e.os

@import("/usr/lib/libobjc.A.dylib", "objc_getClass")
extern fn objc_get_class(name: *const u8) -> usize

@import("/usr/lib/libobjc.A.dylib", "sel_registerName")
extern fn sel_register(name: *const u8) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn send0(receiver: usize, selector: usize) -> usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn number(value: usize) {
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = value
    if rest == 0usize {
        digits[0usize] = 48u8
        count = 1usize
    }
    while rest > 0usize {
        digits[count] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
        count += 1usize
    }
    var out: [20]u8 = zero
    var at = 0usize
    while count > 0usize {
        count -= 1usize
        out[at] = digits[count]
        at += 1usize
    }
    let (written, write_error) = os.write(os.stdout(), out[0usize..at])
}

fn main(a: *mem.Arena) -> err {
    let class_name = "NSProcessInfo\x00"
    let info_class = objc_get_class(&class_name[0usize])
    if info_class == 0usize { os.exit(2i32) }
    say("class ok\n")
    let process_info_name = "processInfo\x00"
    let info = send0(info_class, sel_register(&process_info_name[0usize]))
    if info == 0usize { os.exit(3i32) }
    let process_name_selector = "processName\x00"
    let name = send0(info, sel_register(&process_name_selector[0usize]))
    if name == 0usize { os.exit(4i32) }
    let length_selector = "length\x00"
    let length = send0(name, sel_register(&length_selector[0usize]))
    say("process name length ")
    number(length)
    say("\n")
    ret ok
}
