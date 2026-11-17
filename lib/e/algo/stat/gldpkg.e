// R gld, the generalised lambda distribution: the quantile function `qgl` and the density at the quantile `dqgl` in the FKML (Freimer, Kollia, Mudholkar and Lin) and Ramberg-Schmeiser parameterisations, and the generator `rgl` (the quantile function at a uniform).
//
// Not here: pgl and dgl (they invert the quantile function numerically), the other parameterisations, the starship and FKML fits, the moments and L-moments.

use e.algo.rand.r as rng
use e.math

// qgl(p, lambda1 .. lambda4, "fkml"): the zero values of lambda3 and lambda4 take their logarithmic limits; NaN outside [0, 1]
fn qgl_fkml(p: f64, l1: f64, l2: f64, l3: f64, l4: f64) -> f64 {
    if !(p <= 1.0f64 && p >= 0.0f64) { ret 0.0f64 / 0.0f64 }
    if l3 == 0.0f64 {
        if l4 == 0.0f64 { ret l1 + (math.log[f64](p) - math.log[f64](1.0f64 - p)) / l2 }
        ret l1 + (math.log[f64](p) - (math.pow[f64](1.0f64 - p, l4) - 1.0f64) / l4) / l2
    }
    if l4 == 0.0f64 { ret l1 + ((math.pow[f64](p, l3) - 1.0f64) / l3 - math.log[f64](1.0f64 - p)) / l2 }
    ret l1 + ((math.pow[f64](p, l3) - 1.0f64) / l3 - (math.pow[f64](1.0f64 - p, l4) - 1.0f64) / l4) / l2
}

// qgl(p, ..., "rs")
fn qgl_rs(p: f64, l1: f64, l2: f64, l3: f64, l4: f64) -> f64 {
    ret l1 + (math.pow[f64](p, l3) - math.pow[f64](1.0f64 - p, l4)) / l2
}

// dqgl(p, ..., "fkml") and "rs": the density at the p quantile
fn dqgl_fkml(p: f64, l2: f64, l3: f64, l4: f64) -> f64 { ret l2 / (math.pow[f64](p, l3 - 1.0f64) + math.pow[f64](1.0f64 - p, l4 - 1.0f64)) }

fn dqgl_rs(p: f64, l2: f64, l3: f64, l4: f64) -> f64 { ret l2 / (l3 * math.pow[f64](p, l3 - 1.0f64) + l4 * math.pow[f64](1.0f64 - p, l4 - 1.0f64)) }

// rgl(n, ...): one value, the quantile function at the next uniform
fn rgl(r: *rng.Rng, rs: bool, l1: f64, l2: f64, l3: f64, l4: f64) -> f64 {
    let u = rng.unif(r)
    if rs { ret qgl_rs(u, l1, l2, l3, l4) }
    ret qgl_fkml(u, l1, l2, l3, l4)
}
