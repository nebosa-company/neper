// Arena-backed source loading for the self-hosted compiler.

use e.mem
use e.os

fn load(a: *mem.Arena, path: str) -> (str, err) {
    let flags = os.OpenFlags{ read: true, write: false, create: false, truncate: false, append: false }
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret ("", open_error) }

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
