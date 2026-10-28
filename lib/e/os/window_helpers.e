use e.mem

// Convert AppKit's point coordinates with the backing scale and content height
// observed for the event being translated.
fn pointer_pixels(x_points: f64, y_points: f64, height_pixels: u32, scale_percent: u32) -> (i32, i32) {
    let scale = f64(scale_percent) / 100.0f64
    ret (i32(x_points * scale), i32(f64(height_pixels) - y_points * scale))
}

// Remove one window's queued events while retaining the order and ring head of
// every other window. T is the host-specific event record, which has window.raw.
fn purge_closed_window[T: type](events: []T, head: usize, count: usize, raw: usize) -> usize {
    let capacity = events.len
    if capacity == 0usize || head >= capacity || count > capacity { ret 0usize }
    var kept = 0usize
    var at = 0usize
    while at < count {
        let event = events[(head + at) % capacity]
        if event.window.raw != raw {
            events[(head + kept) % capacity] = event
            kept += 1usize
        }
        at += 1usize
    }
    ret kept
}

type TestWindow = struct { raw: usize }
type TestEvent = struct { window: TestWindow, value: u8 }

@test
fn pointer_pixels_use_the_event_scale_and_height(a: *mem.Arena) -> err {
    let (x, y) = pointer_pixels(100.0f64, 220.0f64, 800u32, 200u32)
    if x != 200i32 || y != 360i32 { ret mem.Exhausted }
    let (normal_x, normal_y) = pointer_pixels(100.0f64, 220.0f64, 400u32, 100u32)
    if normal_x != 100i32 || normal_y != 180i32 { ret mem.Exhausted }
    ret ok
}

@test
fn closed_window_purge_keeps_ring_order(a: *mem.Arena) -> err {
    var events: [6]TestEvent = zero
    events[4usize] = TestEvent { window: TestWindow { raw: 7usize }, value: 1u8 }
    events[5usize] = TestEvent { window: TestWindow { raw: 8usize }, value: 2u8 }
    events[0usize] = TestEvent { window: TestWindow { raw: 7usize }, value: 3u8 }
    events[1usize] = TestEvent { window: TestWindow { raw: 9usize }, value: 4u8 }
    let kept = purge_closed_window[TestEvent](events[..], 4usize, 4usize, 7usize)
    if kept != 2usize { ret mem.Exhausted }
    if events[4usize].window.raw != 8usize || events[4usize].value != 2u8 { ret mem.Exhausted }
    if events[5usize].window.raw != 9usize || events[5usize].value != 4u8 { ret mem.Exhausted }
    ret ok
}
