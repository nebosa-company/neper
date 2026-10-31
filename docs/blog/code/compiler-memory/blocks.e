// Objects with lifetimes of their own: freed one at a time, in any order.
use e.io
use e.mem
use e.mem.heap

fn main(a: *mem.Arena, args: []str) -> err {
    let (h, open_error) = heap.open(8589934592usize)
    if open_error != ok { ret open_error }

    let (session, session_error) = heap.alloc(h, 256usize)
    if session_error != ok { ret session_error }
    let (request, request_error) = heap.alloc(h, 4096usize)
    if request_error != ok {
        heap.free(session)
        ret request_error
    }

    let kept = heap.bytes(&session)
    kept[0usize] = 7u8

    // The older block goes first, which a stack of lifetimes cannot do.
    heap.free(session)
    let working = heap.bytes(&request)
    working[0usize] = 9u8
    let shown = io.printf["request still holds {}\n"](working[0usize])
    heap.free(request)
    if shown != ok { ret shown }
    ret heap.close(h)
}
