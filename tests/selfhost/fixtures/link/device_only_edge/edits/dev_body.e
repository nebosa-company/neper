// Device-only itself (it reads `gpu.gid`), so it may call `lane.helper` either way.
use e.gpu
use lane

fn tap() -> u32 {
    ret lane.helper() + gpu.gid.x
}
