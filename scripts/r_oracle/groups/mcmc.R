# mcmc 0.9-8 under set.seed, every case value-for-value. A chain's cases are position-weighted sums of its outputs (sum(seq_along(v) * v) over the non-NaN entries, v as vector()), plus the next uniform drawn after the chain
# ("next", which checks the generator was consumed exactly as the package consumes it).
#  metrop:  fns batch (row-major batch means), acc (accept.batch), accall (accept), fin (final), next;
#           args (seed, target 0 normal 1 quartic 2 laplace, d, nbatch, blen, nspac, nbatch2 (> 0: continue the run with metrop(obj, nbatch = nbatch2)), initial[d], scale pack, outfun pack)
#  pack of a scale: length then the values (a scalar, a vector of d or a d by d matrix column-major); pack of an outfun: kind (0 none, 1 numeric index, 2 logical index, 3 function(x) c(x, x^2)), length, values
#  initseq: fn iseq args (n, x..., j) j 0 gamma0, 1 var.pos, 2 var.dec, 3 var.con, 4 the sequence length, 5.. sum of Gamma.pos / dec / con (j 5, 6, 7)
#  olbm:    fn olbm args (n, p, blen, demean, i, j, x column-major) the (i, j) entry (0-based) of olbm(x, blen, demean)
#  morph:   fns mtr (transform), minv (inverse), mjac (log.jacobian) args (use_b, b, use_expo, r, p, d, center[d], x[d]); mtr and minv are position-weighted sums, mjac the value
#  morph.metrop: fns mbatch macc maccall mfin mfinm mnext args (seed, target, d, nbatch, blen, nspac, nbatch2, use_b, b, use_expo, r, p, initial[d], center[d], scale pack, outfun pack)
#  temper:  fns tb (batch), ti (ibatch, serial), tax (acceptx), tai (accepti), tnan (number of NaN in acceptx and accepti), tf (final), tnext
#           args (seed, target 0 -b s2/2 + c, 1 -b (s2/2 + s4/10) + c, 2 -b sum|x| + c, parallel, ncomp, nx, nbatch, blen, nspac, outid (0 none, 1 serial c(x^2, i) / parallel rowSums(s^2)), nbatch2, scale is list, beta[ncomp], c[ncomp], neighbors[ncomp^2], initial, scale blocks)
suppressMessages(library(mcmc))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-12)
wsum <- function(v) { v <- as.vector(v); k <- !is.na(v); sum(seq_along(v)[k] * v[k]) }
luds <- list(function(x) -0.5 * sum(x^2), function(x) -0.5 * sum(x^2) - 0.1 * sum(x^4), function(x) -sum(abs(x)))
mkscale <- function(d, kind) switch(kind + 1, round(runif(1, 0.4, 1.6), 2), round(runif(d, 0.4, 1.6), 2), matrix(round(runif(d * d, -0.8, 1.2), 2), d, d))
packscale <- function(s) c(length(s), as.vector(s))
mkout <- function(d, kind, rsub) {
  if (kind == 0) return(NULL)
  if (kind == 1) { if (d >= 2 && runif(1) < 0.5) return(-sample(1:d, 1)); return(if (rsub) sample(1:d, sample(1:d, 1)) else sort(sample(1:d, sample(1:d, 1)))) }
  if (kind == 2) { f <- runif(d) < 0.5; f[sample(1:d, 1)] <- TRUE; return(f) }
  function(x) c(x, x^2)
}
packout <- function(o) if (is.null(o)) c(0, 0) else if (is.function(o)) c(3, 0) else if (is.logical(o)) c(2, length(o), as.numeric(o)) else c(1, length(o), o)
callout <- function(f, o, ...) if (is.null(o)) f(...) else f(..., outfun = o)
set.seed(20261120)
for (rep in 1:36) {
  id <- rep %% 3; d <- sample(1:3, 1); nb <- sample(5:30, 1); bl <- sample(1:4, 1); ns <- sample(1:3, 1); init <- round(rnorm(d), 2); seed <- sample(1:1e6, 1)
  sk <- if (d == 1) rep %% 2 else (rep %/% 3) %% 3; sc <- mkscale(d, sk); ok <- (rep %/% 3) %% 4; ot <- mkout(d, ok, FALSE)
  nb2 <- if (rep %% 5 == 0) sample(4:12, 1) else 0
  set.seed(seed); o <- callout(metrop, ot, luds[[id + 1]], init, nb, blen = bl, nspac = ns, scale = sc)
  if (nb2 > 0) o <- metrop(o, nbatch = nb2)
  nx <- runif(1)
  a <- c(seed, id, d, nb, bl, ns, nb2, init, packscale(sc), packout(ot))
  add("batch", a, wsum(t(o$batch))); add("acc", a, wsum(o$accept.batch)); add("accall", a, o$accept); add("fin", a, wsum(o$final)); add("next", a, nx)
}
# initseq and olbm on an AR(1) chain
for (rep in 1:25) {
  n <- sample(60:300, 1); x <- round(as.numeric(arima.sim(list(ar = runif(1, 0.3, 0.8)), n)), 4)
  r <- initseq(x); if (length(r$Gamma.pos) < 2) next
  v <- c(r$gamma0, r$var.pos, r$var.dec, r$var.con, length(r$Gamma.pos), sum(r$Gamma.pos), sum(r$Gamma.dec), sum(r$Gamma.con))
  for (j in 0:7) add("iseq", c(n, x, j), v[j + 1])
}
for (rep in 1:24) {
  n <- sample(30:90, 1); p <- sample(1:3, 1); dm <- rep %% 3 != 0
  x <- sapply(1:p, function(k) round(as.numeric(arima.sim(list(ar = runif(1, 0.2, 0.8)), n)) + k, 4)); x <- matrix(x, n, p)
  x[, p] <- x[, p] + round(x[, 1] * 0.5, 4)
  for (bl in sample(c(3, 5, 10, 20, n), 2)) {
    v <- olbm(x, bl, demean = dm)
    for (i in 0:(p - 1)) for (j in 0:i) add("olbm", c(n, p, bl, as.numeric(dm), i, j, as.vector(x)), v[i + 1, j + 1], rel = 1e-10)
  }
}
# the morph maps themselves (b subexponential, r and p exponential, p = 3 closed form, else Newton-Raphson), on states of several magnitudes
mkmorph <- function(cfg, b, r, p, ce) {
  a <- list(center = ce)
  if (cfg %in% c(0, 1, 2, 7)) a$b <- b
  if (cfg %in% c(1, 2, 3, 4)) a$r <- r
  if (cfg %in% c(2, 4, 5, 7)) a$p <- p
  do.call(morph, a)
}
cfgflags <- function(cfg) c(as.numeric(cfg %in% c(0, 1, 2, 7)), as.numeric(cfg %in% c(1, 2, 3, 4, 5, 7)))
for (rep in 1:96) {
  cfg <- rep %% 8; d <- sample(1:3, 1); b <- round(runif(1, 0.3, 2), 2); r <- if (cfg %in% c(5, 7)) 0 else round(runif(1, 0, 2), 2); p <- if (cfg %in% c(2, 4, 5, 7)) sample(c(2.5, 3, 4, 5), 1) else 3
  ce <- round(rnorm(d, 0, 0.5), 2); x <- round(rnorm(d) * sample(c(0.2, 1, 3, 12), 1), 3); fl <- cfgflags(cfg); mo <- mkmorph(cfg, b, r, p, ce)
  a <- c(fl[1], b, fl[2], r, p, d, ce, x)
  add("mtr", a, wsum(mo$transform(x))); add("minv", a, wsum(mo$inverse(x))); add("mjac", a, mo$log.jacobian(x))
}
# morph.metrop
for (rep in 1:36) {
  id <- rep %% 3; d <- sample(1:3, 1); nb <- sample(5:25, 1); bl <- sample(1:3, 1); ns <- sample(1:2, 1); init <- round(rnorm(d), 2); seed <- sample(1:1e6, 1)
  cfg <- c(0, 1, 2, 3, 4, 5, 6, 7, 3)[1 + rep %% 9]; b <- round(runif(1, 0.3, 2), 2); r <- if (cfg %in% c(5, 7)) 0 else round(runif(1, 0, 2), 2); p <- if (cfg %in% c(2, 4, 5, 7)) sample(c(2.5, 3, 4), 1) else 3
  ce <- round(rnorm(d, 0, 0.5), 2); mo <- mkmorph(cfg, b, r, p, ce); fl <- cfgflags(cfg)
  sk <- if (d == 1) rep %% 2 else (rep %/% 3) %% 3; sc <- mkscale(d, sk); ok <- c(0, 1, 3, 0)[1 + (rep %/% 3) %% 4]; ot <- mkout(d, ok, TRUE)
  nb2 <- if (rep %% 6 == 0) sample(4:10, 1) else 0
  set.seed(seed); o <- callout(morph.metrop, ot, luds[[id + 1]], init, nb, blen = bl, nspac = ns, scale = sc, morph = mo)
  if (nb2 > 0) o <- morph.metrop(o, nbatch = nb2)
  nx <- runif(1)
  a <- c(seed, id, d, nb, bl, ns, nb2, fl[1], b, fl[2], r, p, init, ce, packscale(sc), packout(ot))
  add("mbatch", a, wsum(t(o$batch))); add("macc", a, wsum(o$accept.batch)); add("maccall", a, o$accept); add("mfin", a, wsum(o$final)); add("mfinm", a, wsum(o$morph.final)); add("mnext", a, nx)
}
# temper, serial and parallel
tlud <- function(id, beta, cc) function(s) {
  i <- s[1]; x <- s[-1]; y <- x^2
  if (id == 0) -0.5 * beta[i] * sum(y) + cc[i] else if (id == 1) -beta[i] * (0.5 * sum(y) + 0.1 * sum(y * y)) + cc[i] else -beta[i] * sum(abs(x)) + cc[i]
}
for (rep in 1:48) {
  id <- rep %% 3; par <- (rep %/% 3) %% 2; nc <- sample(2:4, 1); nx <- sample(1:3, 1); nb <- sample(5:25, 1); bl <- sample(1:3, 1); ns <- sample(1:3, 1)
  beta <- round(sort(runif(nc, 0.15, 1), decreasing = TRUE), 2); beta[1] <- 1; cc <- round(rnorm(nc, 0, 0.5), 2)
  nei <- matrix(FALSE, nc, nc); for (i in 1:(nc - 1)) nei[i, i + 1] <- nei[i + 1, i] <- TRUE
  if (nc >= 3 && rep %% 2 == 0) nei[1, nc] <- nei[nc, 1] <- TRUE
  sk <- (rep %/% 6) %% 4; sblk <- function() mkscale(nx, sample(0:(if (nx == 1) 1 else 2), 1))
  scl <- if (sk == 3) lapply(1:nc, function(i) sblk()) else mkscale(nx, min(sk, if (nx == 1) 1 else 2))
  packed <- if (sk == 3) unlist(lapply(scl, packscale)) else packscale(scl)
  init <- if (par == 1) matrix(round(rnorm(nc * nx), 2), nc, nx) else c(sample(1:nc, 1), round(rnorm(nx), 2))
  outid <- as.numeric(rep %% 4 == 1); seed <- sample(1:1e6, 1); nb2 <- if (rep %% 7 == 0) sample(4:12, 1) else 0
  of <- if (outid == 0) NULL else if (par == 1) function(s) rowSums(s * s) else function(s) c(s[-1]^2, s[1])
  set.seed(seed); o <- callout(temper, of, tlud(id, beta, cc), init, nei, nb, blen = bl, nspac = ns, scale = scl, parallel = par == 1)
  if (nb2 > 0) o <- temper(o, nbatch = nb2)
  nx2 <- runif(1)
  a <- c(seed, id, par, nc, nx, nb, bl, ns, outid, nb2, as.numeric(sk == 3), beta, cc, as.vector(nei), as.vector(init), packed)
  add("tb", a, wsum(o$batch)); if (par == 0) add("ti", a, wsum(o$ibatch)); add("tax", a, wsum(o$acceptx)); add("tai", a, wsum(o$accepti))
  add("tnan", a, sum(is.na(o$acceptx)) + sum(is.na(o$accepti))); add("tf", a, wsum(o$final)); add("tnext", a, nx2)
}
emit("mcmc", "mcmc", list(cases))
