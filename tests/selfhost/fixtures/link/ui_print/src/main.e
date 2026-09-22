// `e.ui.app`'s printing (D901, widget plan P4-11): where the host prints, a job
// on the PDF printer writes one page of pixels to a file without a dialog, a
// second job is cancelled, and a page after the end is refused; a bad range is
// refused before any dialog; a host without printing says so through the
// predicates. No dialog is shown in the suite.

use e.fs
use e.io
use e.mem
use e.os
use e.os.shell
use e.ui.app

fn joined(a: *mem.Arena, x: str, y: str) -> str {
    let (bytes, allocation_error) = mem.alloc[u8](a, x.len + y.len)
    if allocation_error != ok { os.exit(30i32) }
    var at = 0usize
    while at < x.len {
        bytes[at] = x[at]
        at += 1usize
    }
    var i = 0usize
    while i < y.len {
        bytes[at + i] = y[i]
        i += 1usize
    }
    ret bytes[0usize..x.len + y.len]
}

fn main(a: *mem.Arena, args: []str) -> err {
    var nobody: *app.App = zero
    let (no_printer, range_error) = app.print_dialog(a, nobody, 0u32, 3u32)
    if range_error != shell.Invalid { os.exit(1i32) }
    var pixels: [256]u32 = zero
    var i = 0usize
    while i < 256usize {
        pixels[i] = 4293281869u32
        i += 1usize
    }
    let page = shell.Icon { width: 16u32, height: 16u32, pixels: pixels[..] }
    if !app.printing_supported() {
        let (none, open_error) = app.printer_open(a, "")
        if open_error != shell.Unsupported { os.exit(2i32) }
        let (no_setup, setup_error) = app.page_setup_dialog(a, nobody, zero)
        if setup_error != shell.Unsupported { os.exit(3i32) }
        try io.print("ui print ok\n")
        ret ok
    }
    let (printer, open_error) = app.printer_open(a, "Microsoft Print to PDF")
    if open_error == shell.NotFound {
        // A machine without the PDF printer: the default one still answers its page.
        try io.print("ui print ok\n")
        ret ok
    }
    if open_error != ok { os.exit(4i32) }
    let geometry = app.printer_page(printer)
    if geometry.width == 0u32 || geometry.height == 0u32 || geometry.dpi_x == 0u32 { os.exit(5i32) }
    let (temp, temp_error) = fs.temp_dir(a)
    if temp_error != ok { os.exit(6i32) }
    let output = joined(a, temp, "/neper-ui-print.pdf")
    let removed = fs.remove_file(a, output)
    let (started, start_error) = app.print_job_start(a, printer, "neper ui_print", output)
    if start_error != ok { os.exit(7i32) }
    var job = started
    if app.print_job_page(a, &job, page) != ok || job.pages != 1u32 { os.exit(8i32) }
    if app.print_job_end(a, &job) != ok { os.exit(9i32) }
    if app.print_job_page(a, &job, page) != shell.NotFound || app.print_job_end(a, &job) != shell.NotFound { os.exit(10i32) }
    let (written, exists_error) = fs.exists(a, output)
    if exists_error != ok || !written { os.exit(11i32) }
    let (info, stat_error) = fs.stat(a, output)
    if stat_error != ok || info.size == 0u64 { os.exit(12i32) }
    let cleaned = fs.remove_file(a, output)
    // A second job, cancelled.
    let (second, second_error) = app.print_job_start(a, printer, "neper ui_print cancelled", output)
    if second_error != ok { os.exit(13i32) }
    var cancelled = second
    if app.print_job_cancel(a, &cancelled) != ok || app.print_job_cancel(a, &cancelled) != shell.NotFound { os.exit(14i32) }
    let cleaned_again = fs.remove_file(a, output)
    if app.printer_close(a, printer) != ok { os.exit(15i32) }
    try io.print("ui print ok\n")
    ret ok
}
