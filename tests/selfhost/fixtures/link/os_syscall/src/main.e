// `os.syscall` over Linux calls chosen so that every argument position is exercised and
// every answer is checkable without a filesystem the test does not own.
//
// The calls that carry a buffer carry it as `mem.address_of(&b[0])`, which is what makes
// this intrinsic enough for the filesystem primitives: without an address it could reach
// only the calls whose arguments are all numbers.

use e.mem
use e.os

error Failed

fn main(a: *mem.Arena) -> err {
    // getpid: no arguments, and a pid is always positive.
    let pid = os.syscall(39usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize)
    if pid <= 0isize { ret Failed }

    // getuid and geteuid agree for an ordinary process. Two different numbers returning
    // the same value is what catches a call number taken from the wrong register.
    let uid = os.syscall(102usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize)
    if uid < 0isize { ret Failed }
    if os.syscall(107usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize) != uid { ret Failed }

    // One argument, and a failure: fd 1000000 is not open, so close reports -EBADF. The
    // result is the kernel's own errno rather than an `err`, which is the whole point of
    // the signature.
    if os.syscall(3usize, 1000000usize, 0usize, 0usize, 0usize, 0usize, 0usize) != -9isize { ret Failed }

    // Six arguments, every one of them read: mmap(0, 8192, PROT_READ|PROT_WRITE,
    // MAP_PRIVATE|MAP_ANONYMOUS, -1, 0). The fifth and sixth are the ones a register
    // shuffle that stops early drops, and an anonymous mapping fails without both.
    let mapped = os.syscall(9usize, 0usize, 8192usize, 3usize, 34usize, 18446744073709551615usize, 0usize)
    if mapped <= 0isize { ret Failed }

    // The address comes back as an integer and goes straight back in, which is the one
    // way an address reaches this intrinsic today.
    if os.syscall(11usize, usize(mapped), 8192usize, 0usize, 0usize, 0usize, 0usize) != 0isize { ret Failed }

    // A zero length is what munmap rejects, so this one proves the second argument is
    // read rather than assumed. Unmapping twice would not: Linux lets that succeed.
    if os.syscall(11usize, usize(mapped), 0usize, 0usize, 0usize, 0usize, 0usize) != -22isize { ret Failed }

    // An address, which is what the filesystem primitives are waiting for. getcwd
    // fills the buffer and returns its length including the NUL, and a working
    // directory is always absolute -- so byte zero is a separator whatever it is.
    let (directory, directory_error) = mem.alloc[u8](a, 256usize)
    if directory_error != ok { ret directory_error }
    let directory_address = mem.address_of(&directory[0usize])
    if os.syscall(79usize, directory_address, 256usize, 0usize, 0usize, 0usize, 0usize) <= 0isize { ret Failed }
    if directory[0usize] != 47u8 { ret Failed }
    // A buffer too small for the answer is -ERANGE, so the size is read as well as the
    // address rather than the kernel writing wherever it likes.
    if os.syscall(79usize, directory_address, 1usize, 0usize, 0usize, 0usize, 0usize) != -34isize { ret Failed }

    // newfstatat(AT_FDCWD, "/", &status, 0): two addresses in one call, and the shape
    // of the `e.fs.stat` primitive. AT_FDCWD is -100, which is a `usize` here because
    // every argument is one.
    let (status, status_error) = mem.alloc[u8](a, 144usize)
    if status_error != ok { ret status_error }
    let (root, root_error) = mem.alloc[u8](a, 2usize)
    if root_error != ok { ret root_error }
    root[0usize] = 47u8
    root[1usize] = 0u8
    let cwd_fd = 18446744073709551516usize
    let status_address = mem.address_of(&status[0usize])
    if os.syscall(262usize, cwd_fd, mem.address_of(&root[0usize]), status_address, 0usize, 0usize, 0usize) != 0isize { ret Failed }
    // `st_mode` is four bytes at offset 24 of the kernel's `struct stat`, and S_IFDIR is
    // 0x4000 -- so the directory bit is bit 6 of byte 25. `/` is a directory.
    if status[25usize] & 64u8 == 0u8 { ret Failed }

    // A path that is not there is -ENOENT, which proves the path address was read and
    // not ignored in favour of the directory fd.
    let (absent, absent_error) = mem.alloc[u8](a, 16usize)
    if absent_error != ok { ret absent_error }
    absent[0usize] = 47u8
    absent[1usize] = 110u8
    absent[2usize] = 111u8
    absent[3usize] = 45u8
    absent[4usize] = 115u8
    absent[5usize] = 117u8
    absent[6usize] = 99u8
    absent[7usize] = 104u8
    absent[8usize] = 0u8
    if os.syscall(262usize, cwd_fd, mem.address_of(&absent[0usize]), status_address, 0usize, 0usize, 0usize) != -2isize { ret Failed }

    // A call number nothing implements is -ENOSYS, not a crash.
    if os.syscall(9999usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize) != -38isize { ret Failed }
    ret ok
}
