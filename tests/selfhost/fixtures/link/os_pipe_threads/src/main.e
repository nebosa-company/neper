// Pipes between threads (D5677's pipe subset, C204): a write then a read in one thread; the
// nonblocking probe answering WouldBlock on an empty pipe; 300000 bytes written by one thread while
// main reads them (the writer blocks on a full pipe, the reader on an empty one); the end of the
// stream after the writer closes; a reader thread woken by main's late write.
use e.atomic
use e.mem
use e.os


type Sleeper = struct { word: Atomic[u32] }


type Job = struct { out: os.File, total: usize, failure: i32 }


type Late = struct { source: os.File, got: [16]u8, got_len: usize, failure: i32 }

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn pattern(i: usize) -> u8 { ret u8((i * 7usize + 3usize) % 251usize) }

fn pump(job: *Job) {
    var chunk: [1000]u8 = zero
    var sent = 0usize
    while sent < job.total {
        var k = 0usize
        while k < chunk.len {
            chunk[k] = pattern(sent + k)
            k += 1usize
        }
        let (n, write_error) = os.write(job.out, chunk[0usize..])
        if write_error != ok || n != chunk.len {
            job.failure = 1i32
            ret
        }
        sent += chunk.len
    }
    if os.close(job.out) != ok { job.failure = 2i32 }
}

fn late(l: *Late) {
    var buffer: [16]u8 = zero
    let (n, read_error) = os.read(l.source, buffer[0usize..])
    if read_error != ok {
        l.failure = 1i32
        ret
    }
    l.got_len = n
    var k = 0usize
    while k < n {
        l.got[k] = buffer[k]
        k += 1usize
    }
}

fn main(a: *mem.Arena) -> err {
    let (r0, w0, pipe_error) = os.pipe()
    if pipe_error != ok {
        say("pipe failed\n")
        os.exit(1i32)
    }
    var r = r0
    var w = w0
    var small: [8]u8 = zero
    let (wrote, write_error) = os.write(w, "hello")
    if write_error != ok || wrote != 5usize { os.exit(2i32) }
    let (got, read_error) = os.read(r, small[0usize..])
    if read_error != ok || got != 5usize || small[0usize] != 104u8 || small[4usize] != 111u8 { os.exit(3i32) }
    say("write then read\n")

    let (probed, probe_error) = os.pipe_read(r, small[0usize..])
    if probe_error != os.WouldBlock || probed != 0usize { os.exit(4i32) }
    say("empty probe would block\n")

    let (r2, w2, second_error) = os.pipe()
    if second_error != ok { os.exit(5i32) }
    var job: Job = zero
    job.out = w2
    job.total = 300000usize
    let (writer, spawn_error) = os.thread_create[Job](pump, &job, 262144usize)
    if spawn_error != ok { os.exit(6i32) }
    var reader = r2
    var chunk: [777]u8 = zero
    var seen = 0usize
    var bad = 0usize
    while true {
        let (n, chunk_error) = os.read(reader, chunk[0usize..])
        if chunk_error != ok { os.exit(7i32) }
        if n == 0usize { break }
        var k = 0usize
        while k < n {
            if chunk[k] != pattern(seen + k) { bad += 1usize }
            k += 1usize
        }
        seen += n
    }
    if os.thread_join(writer) != ok || job.failure != 0i32 { os.exit(8i32) }
    if seen != 300000usize || bad != 0usize { os.exit(9i32) }
    say("300000 bytes across threads\nend of stream after close\n")

    let (r3, w3, third_error) = os.pipe()
    if third_error != ok { os.exit(10i32) }
    var l: Late = zero
    l.source = r3
    let (waiter, waiter_error) = os.thread_create[Late](late, &l, 262144usize)
    if waiter_error != ok { os.exit(11i32) }
    var sleeper: Sleeper = zero
    let _ = os.wait_u32(&sleeper.word, 0u32, 50000000i64)
    var late_writer = w3
    let (sent, sent_error) = os.write(late_writer, "late")
    if sent_error != ok || sent != 4usize { os.exit(12i32) }
    if os.thread_join(waiter) != ok || l.failure != 0i32 || l.got_len != 4usize || l.got[0usize] != 108u8 { os.exit(13i32) }
    say("a blocked reader woke\n")
    let _ = os.close(r)
    let _ = os.close(reader)
    let _ = os.close(w)
    let _ = os.close(l.source)
    let _ = os.close(late_writer)
    ret ok
}
