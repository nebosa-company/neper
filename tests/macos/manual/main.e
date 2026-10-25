// The checks no CI runner can do, for a person at a real Mac (queue item C192). Build and run it on the Mac:
//   neper-self emit-executable tests/macos/manual/main.e . aarch64 macos manual     (x64 on an Intel Mac)
//   ./manual
// It goes through one check at a time, says what to do, waits for the answer where a person is needed, and writes what it saw to
// ~/neper-manual-results.txt. Answer y or n at a prompt; an empty answer skips. Nothing here changes the system beyond a menu-bar
// icon, a registered .neperx file type and a Dock menu entry, which the last step removes.
use e.fs
use e.mem
use e.os
use e.os.shell
use e.str

var results_path: str = zero
var passed: usize = zero
var failed: usize = zero
var skipped: usize = zero

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn number(value: usize) {
    if value >= 10usize { number(value / 10usize) }
    var one: [1]u8 = zero
    one[0usize] = u8(48usize + value % 10usize)
    let (written, write_error) = os.write(os.stdout(), one[..])
}

// One line from the terminal, the first byte of it (0 when there is none).
fn answer() -> u8 {
    var line: [64]u8 = zero
    var used = 0usize
    var done = false
    while !done && used < 64usize {
        var one: [1]u8 = zero
        let (got, read_error) = os.read(os.stdin(), one[..])
        if read_error != ok || got == 0usize { done = true } else if one[0usize] == 10u8 { done = true } else {
            line[used] = one[0usize]
            used += 1usize
        }
    }
    if used == 0usize { ret 0u8 }
    ret line[0usize]
}

fn record(a: *mem.Arena, name: str, verdict: str) {
    say(name)
    say(": ")
    say(verdict)
    say("\n")
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.append = true
    let (file, open_error) = os.open(a, results_path, flags)
    if open_error != ok { ret }
    let (w1, e1) = os.write(file, name)
    let (w2, e2) = os.write(file, ": ")
    let (w3, e3) = os.write(file, verdict)
    let (w4, e4) = os.write(file, "\n")
    let closed = os.close(file)
}

fn pass(a: *mem.Arena, name: str) {
    passed += 1usize
    record(a, name, "PASS")
}

fn fail(a: *mem.Arena, name: str, why: str) {
    failed += 1usize
    var text: [160]u8 = zero
    var at = 0usize
    let head = "FAIL, "
    while at < head.len {
        text[at] = head[at]
        at += 1usize
    }
    var k = 0usize
    while k < why.len && at < 160usize {
        text[at] = why[k]
        at += 1usize
        k += 1usize
    }
    record(a, name, text[0usize..at])
}

fn skip(a: *mem.Arena, name: str) {
    skipped += 1usize
    record(a, name, "skipped")
}

// Asks the person a yes or no question about what they saw.
fn ask(a: *mem.Arena, name: str, question: str) {
    say(question)
    say(" [y/n/Enter to skip] ")
    let reply = answer()
    if reply == 121u8 || reply == 89u8 { pass(a, name) } else if reply == 0u8 { skip(a, name) } else { fail(a, name, "answered no") }
}

fn pump_for(seconds: usize) {
    var spins = 0usize
    while spins < seconds * 10usize {
        os.cocoa_pump(100000000i64)
        spins += 1usize
    }
}

fn red_icon() -> shell.Icon {
    var pixels: [484]u32 = zero
    var i = 0usize
    while i < 484usize {
        pixels[i] = 4294901760u32
        i += 1usize
    }
    ret shell.Icon { width: 22u32, height: 22u32, pixels: pixels[..] }
}

fn main(a: *mem.Arena) -> err {
    if os.cocoa_start() != ok { os.exit(2i32) }
    let (home, home_error) = fs.home_dir(a)
    if home_error != ok { os.exit(3i32) }
    let (path, path_error) = str.concat(a, home, "/neper-manual-results.txt")
    if path_error != ok { os.exit(4i32) }
    results_path = path
    let cleared = fs.remove_file(a, results_path)
    say("Neper on a Mac: the checks that need a person.\n\n")

    // Retina: a window on this display reports its scale.
    var options: os.WindowOptions = zero
    options.title = "Neper manual checks"
    options.width = 480u32
    options.height = 300u32
    options.visible = true
    let (window, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(5i32) }
    pump_for(1usize)
    let (metrics, metrics_error) = os.window_metrics(window)
    say("This window's scale is ")
    number(usize(metrics.scale_percent))
    say(" percent (200 on a Retina display).\n")
    ask(a, "retina scale", "Is that the scale you expect for this display?")

    // The menu-bar icon, its clicks and a pop-up menu.
    if shell.tray_add(a, 1u32, red_icon(), "Neper manual") != ok { os.exit(6i32) }
    say("\nA red square is in the menu bar. LEFT-click it within 20 seconds.\n")
    var tries = 0usize
    var left = false
    while tries < 200usize && !left {
        let (event, got) = shell.tray_poll()
        if got && event.kind == .Select { left = true }
        os.cocoa_pump(100000000i64)
        tries += 1usize
    }
    if left { pass(a, "tray click") } else { fail(a, "tray click", "no Select event") }
    say("RIGHT-click it within 20 seconds.\n")
    tries = 0usize
    var right = false
    while tries < 200usize && !right {
        let (event, got) = shell.tray_poll()
        if got && event.kind == .Context { right = true }
        os.cocoa_pump(100000000i64)
        tries += 1usize
    }
    if right { pass(a, "tray context click") } else { fail(a, "tray context click", "no Context event") }
    let removed = shell.tray_remove(a, 1u32)
    say("\nA menu will appear at the top left of the screen. Choose \"Second\".\n")
    var items: [3]shell.MenuItem = zero
    items[0usize] = shell.MenuItem { id: 1u32, label: "First", enabled: true, checked: false, separator: false }
    items[1usize] = shell.MenuItem { id: 0u32, label: "", enabled: true, checked: false, separator: true }
    items[2usize] = shell.MenuItem { id: 2u32, label: "Second", enabled: true, checked: true, separator: false }
    let (chosen, has_chosen, menu_error) = shell.popup_menu(a, items[..], 100i32, 100i32)
    if menu_error == ok && has_chosen && chosen == 2u32 { pass(a, "pop-up menu choice") } else { fail(a, "pop-up menu choice", "the chosen id was not 2") }

    // A global shortcut.
    if shell.hotkey_register(a, 7u32, shell.Hotkey { control: true, alt: true, shift: true, super: false, key: 123u32 }) == ok {
        say("\nPress Control-Option-Shift-F12 within 20 seconds (any application in front).\n")
        tries = 0usize
        var pressed = false
        while tries < 200usize && !pressed {
            let (id, got) = shell.hotkey_poll()
            if got && id == 7u32 { pressed = true }
            os.cocoa_pump(100000000i64)
            tries += 1usize
        }
        if pressed { pass(a, "global shortcut") } else { fail(a, "global shortcut", "no press seen") }
        let gone = shell.hotkey_unregister(a, 7u32)
    } else {
        fail(a, "global shortcut", "registration failed")
    }

    // File panels with a confirmed answer.
    say("\nAn Open panel will appear: select TWO files and press Open.\n")
    var filters: [1]shell.FileFilter = zero
    let (picked, open_panel_error) = shell.file_dialog(a, window, shell.FileDialog { kind: .Open, title: "Select two files", filters: filters[0usize..0usize], multiple: true, initial: "", default_extension: "", folder: "" })
    if open_panel_error == ok && picked.len == 2usize { pass(a, "open panel, two files") } else { fail(a, "open panel, two files", "did not answer two paths") }
    say("A Save panel will appear: type the name report and press Save.\n")
    let (saved, save_error) = shell.file_dialog(a, window, shell.FileDialog { kind: .Save, title: "Save as report", filters: filters[0usize..0usize], multiple: false, initial: "", default_extension: "txt", folder: "" })
    if save_error == ok && saved.len == 1usize && saved[0usize].len > 4usize { pass(a, "save panel, a name") } else { fail(a, "save panel, a name", "did not answer a path") }
    if save_error == ok && saved.len == 1usize {
        say("  the panel answered ")
        say(saved[0usize])
        say("\n  (it should end in .txt)\n")
    }

    // A drop from Finder.
    let (store, store_error) = mem.alloc[u8](a, 262144usize)
    if store_error != ok { os.exit(7i32) }
    var storage = mem.arena_from(store)
    if shell.drop_target_register(a, window, &storage) == ok {
        say("\nDrag a file from Finder onto the window \"Neper manual checks\" within 30 seconds.\n")
        tries = 0usize
        var dropped = false
        while tries < 300usize && !dropped {
            let (landed, got) = shell.drop_poll()
            if got && landed.items.len != 0usize {
                dropped = true
                say("  dropped: ")
                if landed.items[0usize].paths.len != 0usize { say(landed.items[0usize].paths[0usize]) }
                say("\n")
            }
            os.cocoa_pump(100000000i64)
            tries += 1usize
        }
        if dropped { pass(a, "drop from Finder") } else { fail(a, "drop from Finder", "nothing dropped") }
        let undropped = shell.drop_target_unregister(a, window)
    }

    // The clipboard with another application.
    var texts: [1]shell.Content = zero
    texts[0usize] = shell.Content { kind: .Text, mime: "", text: "from Neper", paths: zero, image: zero, bytes: zero }
    let wrote = shell.clipboard_write(a, texts[..])
    ask(a, "clipboard to another app", "Paste into TextEdit: does it say 'from Neper'?")

    // A notice, from this program (a banner through osascript unless it runs in a bundle).
    let (notice, notice_error) = shell.notice_publish(a, 0u32, "Neper", "A notice from the manual checks", false)
    ask(a, "notice banner", "Did a notification banner appear?")

    // The Dock menu: a task that makes a file.
    var tasks: [1]shell.JumpTask = zero
    tasks[0usize] = shell.JumpTask { title: "Make a Neper file", program: "/usr/bin/touch", arguments: "/tmp/neper-manual-dock", description: "" }
    let removed_file = fs.remove_file(a, "/tmp/neper-manual-dock")
    if shell.jump_list(a, tasks[..]) == ok {
        let badge = shell.taskbar_progress(a, window, .Normal, 1u64, 2u64)
        say("\nRight-click this program's Dock icon and choose \"Make a Neper file\"; the badge should read 50%.\n")
        pump_for(25usize)
        let (made, exists_error) = fs.exists(a, "/tmp/neper-manual-dock")
        if exists_error == ok && made { pass(a, "dock menu task") } else { fail(a, "dock menu task", "the file was not made") }
        let cleared_jump = shell.jump_list_clear(a)
        let cleared_badge = shell.taskbar_progress(a, window, .None, 0u64, 0u64)
    }

    // A file type: Finder opens a file with this program.
    let wrote_doc = fs.write_file(a, "/tmp/neper-manual.neperx", "document")
    if shell.associate_file(a, ".neperx", "neper.Manual", "Neper manual document") == ok {
        say("\nIn Finder, open /tmp/neper-manual.neperx (double-click, or Open With the program Neper Manual) within 60 seconds.\n")
        say("(The opened copy is a second process; this check watches only the single-instance route, so also look for it in the Dock.)\n")
        ask(a, "Finder opens an associated file", "Did Finder start a program for the file?")
        let dissociated = shell.dissociate_file(a, ".neperx", "neper.Manual")
    }

    // The system's own dialogs and permission prompts.
    say("\nA Print panel will appear: set pages 2 to 3 and 2 copies, then press the PDF button's Save as PDF... or Cancel.\n")
    let (printer, print_error) = shell.print_dialog(a, window, 1u32, 9u32)
    if print_error == ok {
        say("  chosen: from page ")
        number(usize(printer.from_page))
        say(" to ")
        number(usize(printer.to_page))
        say(", copies ")
        number(usize(printer.copies))
        say("\n")
    }
    ask(a, "print panel range and copies", "Did the answer above match what you set (or did Cancel answer nothing)?")
    let (camera, camera_error) = shell.permission_request(a, .Camera)
    if camera == .Granted { say("The camera is allowed.\n") } else if camera == .Denied { say("The camera is refused.\n") } else { say("The camera has no answer on this Mac.\n") }
    ask(a, "camera permission", "Did the system ask (or already answer) in a way that matches the line above?")
    if shell.capabilities().biometrics {
        say("\nTouch ID: touch the sensor when the sheet appears.\n")
        let (verdict, bio_error) = shell.biometric_verify(a, "Neper manual check")
        if verdict == .Granted { pass(a, "touch id") } else { fail(a, "touch id", "not granted") }
    } else {
        skip(a, "touch id")
    }

    // Screen capture and VoiceOver.
    let (shot, shot_error) = shell.screen_capture(a)
    if shot_error == ok && shot.width != 0u32 {
        say("\nA screen capture is ")
        number(usize(shot.width))
        say(" by ")
        number(usize(shot.height))
        say(" pixels.\n")
    }
    ask(a, "screen capture size", "Is that the size of this display in pixels?")
    var nodes: [2]os.AccessibleNode = zero
    nodes[0usize].id = 1u32
    nodes[0usize].generation = 1u32
    nodes[0usize].role = 2u8
    nodes[0usize].label = "Manual panel"
    nodes[0usize].width = 480.0f32
    nodes[0usize].height = 300.0f32
    nodes[1usize].id = 2u32
    nodes[1usize].generation = 1u32
    nodes[1usize].parent = 1u32
    nodes[1usize].parent_generation = 1u32
    nodes[1usize].has_parent = true
    nodes[1usize].role = 3u8
    nodes[1usize].label = "Press me"
    nodes[1usize].x = 20.0f32
    nodes[1usize].y = 20.0f32
    nodes[1usize].width = 120.0f32
    nodes[1usize].height = 40.0f32
    let published = os.accessibility_publish(window, nodes[..])
    say("\nTurn VoiceOver on (Command-F5), focus this window and move through it: does it read 'Manual panel' and a button 'Press me'?\n")
    pump_for(5usize)
    ask(a, "voiceover reads the tree", "Did VoiceOver read both?")
    let (request, any) = os.accessibility_take(window)
    ask(a, "voiceover press", "Now press the button with VO-Space: (look at the next line) -- did a press arrive?")
    let (pressed_request, pressed_any) = os.accessibility_take(window)
    if pressed_any {
        say("  a press of node ")
        number(usize(pressed_request.id))
        say(" arrived\n")
    }

    say("\nDone: ")
    number(passed)
    say(" passed, ")
    number(failed)
    say(" failed, ")
    number(skipped)
    say(" skipped. Results are in ")
    say(results_path)
    say("\n")
    let closed = os.window_close(window)
    ret ok
}
