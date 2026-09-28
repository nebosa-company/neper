// Plain CPU code: it may call `lane.helper` only while that is not device-only.
use lane

fn run() -> u32 {
    ret lane.helper()
}
