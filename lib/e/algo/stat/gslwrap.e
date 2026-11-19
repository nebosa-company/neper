// R gsl: the small R-level wrappers that have no gsl routine behind them. legendre_Plm_array, legendre_Plm_deriv_array, legendre_sphPlm_array, legendre_sphPlm_deriv_array and
// legendre_array_size only warn and return the deprecation text; strictify masks a value whose status is nonzero; legendre_check_args validates the arguments of the legendre_array family.

use e.math

fn deprecated_legendre() -> str {
    ret "As of version 2.1, the GSL library has deprecated the following functions:\n\t\tgsl_sf_legendre_Plm_array\n\t\tgsl_sf_legendre_Plm_deriv_array\n     \t\tgsl_sf_legendre_sphPlm_array\n     \t\tgsl_sf_legendre_sphPlm_deriv_array\n     \t\tgsl_sf_legendre_array_size\n\n The functionality is provided in GSL by the gsl_sf_legendre_array suite of functions; in R, use one of:\n                legendre_array()\n                legendre_deriv_array()\n                legendre_deriv_alt_array()\n                legendre_deriv2_array()\n                legendre_deriv2_altarray()\n"
}

// strictify(val, status): NaN where status > 0
fn strictify(v: f64, status: i64) -> f64 {
    if status > 0i64 { ret 0.0f64 / 0.0f64 }
    ret v
}

// legendre_check_args(x, lmax, norm, csphase): true when every argument is acceptable (R stops otherwise)
fn legendre_check_args(lmax: f64, norm: f64, csphase: f64) -> bool {
    if lmax < 0.0f64 { ret false }
    if !(norm == 1.0f64 || norm == 2.0f64 || norm == 3.0f64 || norm == 4.0f64) { ret false }
    if !(csphase == 1.0f64 || csphase == -1.0f64) { ret false }
    ret true
}

// the position-weighted byte sum of a string, the case value for text results
fn text_checksum(s: str) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < s.len {
        sum += f64(i + 1usize) * f64(s[i])
        i += 1usize
    }
    ret sum
}
