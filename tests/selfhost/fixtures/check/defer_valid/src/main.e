error Failed

fn cleanup() {
}

fn fallible() -> err {
    ret Failed
}

fn run() -> err {
    defer cleanup()
    defer let _ = fallible()
    defer {
        while true {
            break
        }
        cleanup()
    }
    ret ok
}
