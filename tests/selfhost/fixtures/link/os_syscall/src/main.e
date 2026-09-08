// `os.syscall` over Linux calls chosen so that every argument position is exercised and
// every answer is checkable without a filesystem the test does not own.
//
// Nothing here passes an address, because the language has no way to produce one as a
// `usize`: `mmap` takes a null hint and gives its result back as an integer, which is
// what lets a six-argument call be tested at all.

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

    // A call number nothing implements is -ENOSYS, not a crash.
    if os.syscall(9999usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize) != -38isize { ret Failed }
    ret ok
}
