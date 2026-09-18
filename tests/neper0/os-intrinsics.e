use e.mem
use e.os

fn main(a: *mem.Arena, startup_args: []str) -> err {
    let (args, args_error) = os.args(a)
    if args_error != ok { ret args_error }
    if args.len != startup_args.len || args.len < 4usize { ret os.Failed }

    let flags = os.OpenFlags{ read: false, write: true, create: true, truncate: true, append: false }
    let (created, create_error) = os.open(a, args[1usize], flags)
    if create_error != ok { ret create_error }
    let (written, write_error) = os.write(created, "neper os")
    let close_write_error = os.close(created)
    if write_error != ok { ret write_error }
    if close_write_error != ok { ret close_write_error }

    let append_flags = os.OpenFlags{ read: false, write: true, create: false, truncate: false, append: true }
    let (appended_file, append_open_error) = os.open(a, args[1usize], append_flags)
    if append_open_error != ok { ret append_open_error }
    let (appended, append_error) = os.write(appended_file, "!")
    let append_close_error = os.close(appended_file)
    if append_error != ok { ret append_error }
    if append_close_error != ok { ret append_close_error }

    let read_flags = os.OpenFlags{ read: true, write: false, create: false, truncate: false, append: false }
    let (opened, open_error) = os.open(a, args[1usize], read_flags)
    if open_error != ok { ret open_error }
    var buffer: [9]u8 = zero
    let (read_count, read_error) = os.read(opened, buffer[..])
    let close_read_error = os.close(opened)
    if read_error != ok { ret read_error }
    if close_read_error != ok { ret close_read_error }
    if written != 8usize || appended != 1usize || read_count != 9usize || buffer[0usize] != 110u8 || buffer[7usize] != 115u8 || buffer[8usize] != 33u8 {
        ret os.Failed
    }

    let (entries, directory_error) = os.readdir(a, args[2usize])
    if directory_error != ok { ret directory_error }
    if entries.len == 0usize { ret os.Failed }
    if entries[0usize].name.len == 0usize { ret os.Failed }
    // `mkdir` on a directory that exists answers `Exists`, on both hosts (D287).
    if os.mkdir(a, args[2usize]) != os.Exists { ret os.Failed }

    let (page, reserve_error) = os.reserve(4096usize)
    if reserve_error != ok { ret reserve_error }
    let commit_error = os.commit(page, 4096usize)
    if commit_error != ok { ret commit_error }
    if *page != 0u8 { ret os.Failed }
    *page = 77u8
    if *page != 77u8 { ret os.Failed }

    let (wall, wall_error) = os.clock(.Wall)
    if wall_error != ok { ret wall_error }
    let (before, before_error) = os.clock(.Monotonic)
    if before_error != ok { ret before_error }
    let (after, after_error) = os.clock(.Monotonic)
    if after_error != ok { ret after_error }
    if wall <= 0i64 || after < before { ret os.Failed }

    let output = os.stdout()
    let errors = os.stderr()
    var child_args = [5]str{ args[3usize], "alpha beta", "gamma", "quote\"slash\\tail\\", "" }
    var inherited = [1]os.Handle{ os.file_handle(output) }
    let stdio = os.Stdio{
        stdin: os.stdin(),
        stdout: output,
        stderr: errors,
        inherit: inherited[..],
    }
    let (child, spawn_error) = os.spawn(a, child_args[..], stdio)
    if spawn_error != ok { ret spawn_error }
    let (status, wait_error) = os.wait(child)
    if wait_error != ok { ret wait_error }
    if status != 0i32 { ret os.Failed }

    let (output_count, output_error) = os.write(output, "intrinsic ok\n")
    if output_error != ok { ret output_error }
    if output_count != 13usize { ret os.Failed }
    ret ok
}
