use genhelp
use lowvals

// Reads a constant of a third module directly, calls a helper of it, and instantiates
// a generic helper of a fourth for two element types.
fn mix(x: u32) -> u32 {
    let doubled = genhelp.twice[u32](x)
    ret genhelp.clamp_to[u32](doubled + lowvals.OFFSET, lowvals.LIMIT) + lowvals.bump(x) + lowvals.cap(x * 9u32) + lowvals.sum_to(x)
}

fn scaled(x: f32) -> f32 {
    ret genhelp.twice[f32](x) * 2.5f32
}
