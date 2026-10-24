// A job on the virtual PDF printer: one 64x64 page of pixels written to a file, its size and first bytes printed.
use e.fs
use e.mem
use e.os
use e.os.shell

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena) -> err {
    let (printer, open_error) = shell.printer_open(a, "")
    if open_error != ok { os.exit(2i32) }
    var pixels: [4096]u32 = zero
    var i = 0usize
    while i < 4096usize {
        pixels[i] = 4294901760u32
        if (i / 64usize + i % 64usize) % 8usize == 0usize { pixels[i] = 4278190335u32 }
        i += 1usize
    }
    let page = shell.Icon { width: 64u32, height: 64u32, pixels: pixels[..] }
    let output = "/tmp/neper-probe.pdf"
    var removed = fs.remove_file(a, output)
    let (job0, start_error) = shell.print_job_start(a, printer, "probe", output)
    if start_error != ok { os.exit(3i32) }
    var job = job0
    if shell.print_page(a, &job, page) != ok || job.pages != 1u32 { os.exit(4i32) }
    if shell.print_job_end(a, &job) != ok { os.exit(5i32) }
    let (info, stat_error) = fs.stat(a, output)
    if stat_error != ok || info.size == 0u64 { os.exit(6i32) }
    let (bytes, read_error) = fs.read_file(a, output, 1048576usize)
    if read_error != ok || bytes.len < 5usize { os.exit(7i32) }
    if bytes[0usize] != 37u8 || bytes[1usize] != 80u8 || bytes[2usize] != 68u8 || bytes[3usize] != 70u8 { os.exit(8i32) }
    say("pdf written ok\n")
    ret ok
}
