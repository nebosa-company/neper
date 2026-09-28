// The helper `host` and `dev` call. `edits/lane_device.e` makes it device-only (it
// reads `gpu.gid`, D1589), and `edits/lane_body.e` changes its body and keeps it so.
use e.gpu

fn helper() -> u32 {
    ret gpu.gid.x + 1u32
}
