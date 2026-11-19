# mcmc::metrop under set.seed on three fixed targets: args (seed, target 0 normal 1 quartic 2 laplace, d, nbatch, blen, nspac, initial[d], scale[d]);
# fn "batch" (position-weighted sum of the batch-means matrix, row-major), "acc" (position-weighted accept.batch), "fin" (position-weighted final state)
suppressMessages(library(mcmc))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
luds <- list(function(x) -0.5 * sum(x^2), function(x) -0.5 * sum(x^2) - 0.1 * sum(x^4), function(x) -sum(abs(x)))
set.seed(20261120)
for (rep in 1:30) {
  id <- rep %% 3; d <- sample(1:3, 1); nb <- sample(5:30, 1); bl <- sample(1:4, 1); ns <- sample(1:3, 1); init <- round(rnorm(d), 2); sc <- round(runif(d, 0.4, 1.6), 2); seed <- sample(1:1e6, 1)
  set.seed(seed); o <- metrop(luds[[id + 1]], init, nb, blen = bl, nspac = ns, scale = sc); a <- c(seed, id, d, nb, bl, ns, init, sc)
  add("batch", a, sum(seq_along(o$batch) * as.vector(t(o$batch)))); add("acc", a, sum(seq_along(o$accept.batch) * o$accept.batch)); add("fin", a, sum(seq_along(o$final) * o$final))
}
# initseq and olbm on an AR(1) chain: "iseq" args (n, x..., j) j 0 gamma0, 1 var.pos, 2 var.dec, 3 var.con, 4 the sequence length, 5.. sum of Gamma.pos / dec / con (j 5, 6, 7); "olbm" args (n, blen, x...)
for (rep in 1:25) {
  n <- sample(60:300, 1); x <- round(as.numeric(arima.sim(list(ar = runif(1, 0.3, 0.8)), n)), 4)
  r <- initseq(x); if (length(r$Gamma.pos) < 2) next
  v <- c(r$gamma0, r$var.pos, r$var.dec, r$var.con, length(r$Gamma.pos), sum(r$Gamma.pos), sum(r$Gamma.dec), sum(r$Gamma.con))
  for (j in 0:7) cases[[length(cases) + 1]] <- case("iseq", c(n, x, j), v[j + 1], rel = 1e-9, abs = 1e-12)
  for (bl in sample(c(3, 5, 10, 20), 2)) cases[[length(cases) + 1]] <- case("olbm", c(n, bl, x), as.numeric(olbm(x, bl)), rel = 1e-10, abs = 1e-13)
}
# morph.metrop: "mbatch" "macc" "mfin" args (seed, target, d, nbatch, blen, nspac, use_b, b, use_expo, r, initial[d], scale[d], center[d]); the same position-weighted sums
for (rep in 1:24) {
  id <- rep %% 3; d <- sample(1:3, 1); nb <- sample(5:25, 1); bl <- sample(1:3, 1); ns <- sample(1:2, 1); init <- round(rnorm(d), 2); sc <- round(runif(d, 0.4, 1.4), 2); seed <- sample(1:1e6, 1)
  ub <- rep %% 4 %in% c(0, 1); ue <- rep %% 4 %in% c(1, 2, 3); b <- round(runif(1, 0.3, 2), 2); r <- round(runif(1, 0, 2), 2); ce <- round(rnorm(d, 0, 0.5), 2)
  mo <- if (ub && ue) morph(b = b, r = r, center = ce) else if (ub) morph(b = b, center = ce) else morph(r = r, center = ce)
  set.seed(seed); o <- morph.metrop(luds[[id + 1]], init, nb, blen = bl, nspac = ns, scale = sc, morph = mo)
  a <- c(seed, id, d, nb, bl, ns, as.numeric(ub), b, as.numeric(ue), r, init, sc, ce)
  add("mbatch", a, sum(seq_along(o$batch) * as.vector(t(o$batch)))); add("macc", a, sum(seq_along(o$accept.batch) * o$accept.batch)); add("mfin", a, sum(seq_along(o$final) * o$final))
}
emit("mcmc", "mcmc", list(cases))
