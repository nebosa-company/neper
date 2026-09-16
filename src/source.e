// Arena-backed source loading for the self-hosted compiler.

use e.mem
use e.os

// A file longer than the size its end was at when the read began.
error Grew

fn load(a: *mem.Arena, path: str) -> (str, err) {
    let flags = os.OpenFlags{ read: true, write: false, create: false, truncate: false, append: false }
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret ("", open_error) }
    // The file's size from a seek to its end (D324), so the buffer is one allocation of
    // that size: growing from four kibibytes by doubling allocated and copied twice
    // the file, which a worker's arena has no room for. What cannot seek -- a pipe --
    // is read the growing way.
    // The file is this function's to close (D345): the readers borrow it, and the
    // close's own error stands only where the read succeeded.
    var text = ""
    var read_error = ok
    var sized = false
    let (size, size_error) = os.seek(file, 0i64, .End)
    if size_error == ok {
        let (start, start_error) = os.seek(file, 0i64, .Start)
        if start_error == ok {
            let (sized_text, sized_error) = read_sized(a, file, usize(size))
            text = sized_text
            read_error = sized_error
            sized = true
        }
    }
    if !sized {
        let (all_text, all_error) = read_all(a, file)
        text = all_text
        read_error = all_error
    }
    let close_error = os.close(file)
    if read_error != ok { ret ("", read_error) }
    if close_error != ok { ret ("", close_error) }
    ret (text, ok)
}

fn read_sized(a: *mem.Arena, file: os.File, size: usize) -> (str, err) {
    let (buffer, allocation_error) = mem.alloc[u8](a, size + 1usize)
    if allocation_error != ok { ret ("", allocation_error) }
    var used = 0usize
    while used < size {
        let (count, read_error) = os.read(file, buffer[used..size])
        if read_error != ok { ret ("", read_error) }
        if count == 0usize { break }
        used += count
    }
    // A file that grew past its size as it was read is read to its new end.
    let (extra, extra_error) = os.read(file, buffer[used..size + 1usize])
    if extra_error != ok { ret ("", extra_error) }
    if extra != 0usize { ret ("", Grew) }
    ret (buffer[..used], ok)
}

// The whole of standard input, for a `-` operand (D289). The handle is not closed.
fn load_stdin(a: *mem.Arena) -> (str, err) {
    var capacity = 4096usize
    let (initial, allocation_error) = mem.alloc[u8](a, capacity)
    if allocation_error != ok { ret ("", allocation_error) }
    var buffer = initial
    var used = 0usize
    let file = os.stdin()
    while true {
        if used == capacity {
            capacity = capacity + capacity
            let (grown, grow_error) = mem.alloc[u8](a, capacity)
            if grow_error != ok { ret ("", grow_error) }
            var i = 0usize
            while i < used {
                grown[i] = buffer[i]
                i += 1usize
            }
            buffer = grown
        }
        let (count, read_error) = os.read(file, buffer[used..])
        if read_error != ok { ret ("", read_error) }
        if count == 0usize { break }
        used += count
    }
    ret (buffer[..used], ok)
}

// Every byte of an open file, which is closed after.
fn read_all(a: *mem.Arena, file: os.File) -> (str, err) {
    var capacity = 4096usize
    let (initial, allocation_error) = mem.alloc[u8](a, capacity)
    if allocation_error != ok {
        ret ("", allocation_error)
    }
    var buffer = initial
    var used = 0usize
    while true {
        if used == capacity {
            capacity = capacity + capacity
            let (grown, grow_error) = mem.alloc[u8](a, capacity)
            if grow_error != ok {
                ret ("", grow_error)
            }
            var i = 0usize
            while i < used {
                grown[i] = buffer[i]
                i += 1usize
            }
            buffer = grown
        }
        let (count, read_error) = os.read(file, buffer[used..])
        if read_error != ok {
            ret ("", read_error)
        }
        if count == 0usize { break }
        used += count
    }
    ret (buffer[..used], ok)
}
