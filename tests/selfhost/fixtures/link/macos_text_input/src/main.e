// The content view answers the text input protocol that input methods speak: committed text becomes Text events (an accented letter
// and a kana), marked text (a composition under way) is held and shown as such to the system and produces none, and the keys still
// go through `interpretKeyEvents:` to the same place. The calls are the input method's, made by hand since a runner has none.
// macOS only; the corpus runs it on a Mac.
use e.mem
use e.os

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_marked(receiver: usize, selector: usize, string: usize, a: usize, b: usize, c: usize, d: usize) -> usize

fn next(code: i32) -> os.WindowEvent {
    var tries = 0usize
    while tries < 40usize {
        let (event, got, poll_error) = os.window_poll(50000000i64)
        if poll_error != ok { os.exit(code) }
        if got { ret event }
        tries += 1usize
    }
    os.exit(code)
    var none: os.WindowEvent = zero
    ret none
}

fn quiet(code: i32) {
    let (event, got, poll_error) = os.window_poll(80000000i64)
    if got && event.kind == .Text { os.exit(code) }
}

fn main(a: *mem.Arena) -> err {
    var options: os.WindowOptions = zero
    options.title = "Neper: text input"
    options.width = 320u32
    options.height = 200u32
    options.visible = true
    let (window, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(2i32) }
    let (handle, view, native_error) = os.window_native(window)
    if native_error != ok { os.exit(3i32) }
    // Drain what opening says.
    var opening = 0usize
    while opening < 3usize {
        let (event, got, poll_error) = os.window_poll(100000000i64)
        opening += 1usize
    }
    let not_found = 9223372036854775807usize
    let accented = os.cocoa_text("\xC3\xA9")
    let inserted = os.msg4(view, os.cocoa_sel("insertText:replacementRange:\x00"), accented, not_found, 0usize, 0usize)
    os.cf_release(accented)
    var event = next(10i32)
    if event.kind != .Text || event.codepoint != 233u32 { os.exit(11i32) }
    // A composition: marked, not committed.
    let kana = os.cocoa_text("\xE3\x81\x82")
    let marked = msg_marked(view, os.cocoa_sel("setMarkedText:selectedRange:replacementRange:\x00"), kana, 0usize, 1usize, not_found, 0usize)
    quiet(20i32)
    if os.msg_bool_ret(view, os.cocoa_sel("hasMarkedText\x00")) == 0u8 { os.exit(21i32) }
    // Committed: the text arrives and the mark is gone.
    let committed = os.msg4(view, os.cocoa_sel("insertText:replacementRange:\x00"), kana, not_found, 0usize, 0usize)
    os.cf_release(kana)
    event = next(30i32)
    if event.kind != .Text || event.codepoint != 12354u32 { os.exit(31i32) }
    if os.msg_bool_ret(view, os.cocoa_sel("hasMarkedText\x00")) != 0u8 { os.exit(32i32) }
    if os.window_close(window) != ok { os.exit(40i32) }
    ret ok
}
