// Arena-backed source loading for the self-hosted compiler.

use e.mem
use e.os

fn load(a: *mem.Arena, path: str) -> (str, err) {
    let flags = os.OpenFlags{ read: true, write: false, create: false, truncate: false, append: false }
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret ("", open_error) }
    let (text, read_error) = read_all(a, file)
    ret (text, read_error)
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
        let close_error = os.close(file)
        ret ("", allocation_error)
    }
    var buffer = initial
    var used = 0usize
    while true {
        if used == capacity {
            capacity = capacity + capacity
            let (grown, grow_error) = mem.alloc[u8](a, capacity)
            if grow_error != ok {
                let close_error = os.close(file)
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
            let close_error = os.close(file)
            ret ("", read_error)
        }
        if count == 0usize { break }
        used += count
    }
    let close_error = os.close(file)
    if close_error != ok { ret ("", close_error) }
    ret (buffer[..used], ok)
}
