# RSpectra svds and eigs_sym (and irlba's values) on random dense matrices; vectors are sign-aligned (largest component positive, u and v of a triplet together), not just compared in modulus.
#   args: (kind, m, n, k, which, x row-major m*n); kind 0 svds, 1 eigs_sym (m = n; which 0 LM 1 LA 2 SA 3 SM 4 sigma 5 BE, sigma last), 2 irlba (values and vectors against irlba at tol 1e-12)
#   fn "d" (values weighted by position), "u" and "v" (sign-aligned vectors weighted by column-major position)
suppressMessages({library(RSpectra); library(irlba)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20261205)
ws <- function(x) sum(as.vector(x) * seq_along(x))
sgn <- function(u, v) { s <- apply(u, 2, function(x) sign(x[which.max(abs(x))])); list(u = t(t(u) * s), v = t(t(v) * s)) }
for (rep in 1:36) {
  kind <- (rep - 1) %% 3
  if (kind == 2) { m <- sample(20:30, 1); n <- sample(14:18, 1); x <- matrix(rnorm(m * n), m) } else if (kind == 1) { n <- sample(14:36, 1); m <- n; B <- matrix(rnorm(n * n), n); x <- (B + t(B)) / 2 } else { m <- sample(24:40, 1); n <- sample(22:min(m, 30), 1); x <- matrix(rnorm(m * n), m) }
  k <- sample(2:4, 1); wh <- if (kind == 1) sample(0:5, 1) else 0; sg <- if (kind == 1 && wh == 4) round(runif(1, -1.5, 1.5), 3) else NULL
  a <- c(kind, m, n, k, wh, as.vector(t(x)), sg)
  if (kind == 1) {
    ev <- eigen(x, symmetric = TRUE)$values
    key <- switch(wh + 1, abs(ev), ev, -ev, -abs(ev), -abs(ev - sg), ev)
    if (wh != 5) { srt <- sort(key, decreasing = TRUE); if (abs(srt[k] - srt[k + 1]) < 1e-6) next }
    o <- if (wh == 4) eigs_sym(x, k, sigma = sg, opts = list(tol = 1e-14, maxitr = 5000)) else eigs_sym(x, k, which = c("LM", "LA", "SA", "SM", NA, "BE")[wh + 1], opts = list(tol = 1e-14, maxitr = 5000))
    R <- rotc <- apply(o$vectors, 2, function(v) v * sign(v[which.max(abs(v))]))
    add("d", a, ws(o$values)); add("v", a, ws(R))
  } else if (kind == 0) {
    o <- svds(x, k, opts = list(tol = 1e-14, maxitr = 5000)); s <- sgn(o$u, o$v)
    add("d", a, ws(o$d)); add("u", a, ws(s$u)); add("v", a, ws(s$v))
  } else {
    o <- irlba(x, nv = k, tol = 1e-12, maxit = 5000); s <- sgn(o$u, o$v)
    add("d", a, ws(o$d)); add("u", a, ws(s$u)); add("v", a, ws(s$v))
  }
}
emit("spectra", c("RSpectra", "irlba"), list(cases))
