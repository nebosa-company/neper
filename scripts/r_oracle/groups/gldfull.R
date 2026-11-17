# gldfull: qgl, dqgl, pgl, dgl, rgl in the fkml, rs, fm5 and gpd parameterisations, gld.moments, gld.lmoments, fit.gpd.lmom.given.
#   param: 0 fkml 1 rs 2 fm5 3 gpd.   "q" (param, p, np, lam..)  "dq" (param, p, np, lam..)  "p" (param, x, np, lam..)  "d" (param, x, np, lam..)
#   "r" (param, seed, np, lam.., j)  "mom" (ratios, np, par.., q)  "lmom" (ratios, high, order, np, pars..)  "gpdfit" (n, l1, l2, t3, t4, idx) idx 0..3 est A, 4..7 est B, 8..11 se A, 12..15 se B
suppressMessages(library(gld))
cases <- list()
pn <- c("fkml", "rs", "fm5", "gpd")
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261121)
mklam <- function(pm, rep) {
  l1 <- round(rnorm(1), 2); l2 <- round(runif(1, 0.3, 3), 2)
  l3 <- if (rep %% 7 == 0) 0 else round(runif(1, -0.4, 1.5), 3); l4 <- if (rep %% 11 == 0) 0 else round(runif(1, -0.4, 1.5), 3)
  switch(pm + 1, c(l1, l2, l3, l4), c(l1, l2, round(runif(1, 0.1, 1.5), 3), round(runif(1, 0.1, 1.5), 3)), c(l1, l2, l3, l4, round(runif(1, -0.8, 0.8), 2)),
    c(l1, l2, round(runif(1, 0.05, 0.95), 2), if (rep %% 9 == 0) 0 else round(runif(1, -0.45, 1.5), 3)))
}
for (rep in 1:60) {
  pm <- rep %% 4; lam <- mklam(pm, rep); np <- length(lam)
  ok <- tryCatch({ suppressWarnings(qgl(0.5, lam, param = pn[pm + 1])); TRUE }, error = function(e) FALSE); if (!ok) next
  for (p in c(0.01, 0.2, 0.5, 0.83, 0.99)) {
    q <- qgl(p, lam, param = pn[pm + 1]); add("q", c(pm, p, np, lam), q); add("dq", c(pm, p, np, lam), dqgl(p, lam, param = pn[pm + 1]))
    pv <- tryCatch(pgl(q, lam, param = pn[pm + 1]), error = function(e) NA); add("p", c(pm, q, np, lam), pv, rel = 1e-9, abs = 1e-9)
    dv <- tryCatch(dgl(q, lam, param = pn[pm + 1]), error = function(e) NA); add("d", c(pm, q, np, lam), dv, rel = 1e-8, abs = 1e-9)
  }
  ex <- qgl(c(0.001, 0.999), lam, param = pn[pm + 1])
  if (all(is.finite(ex))) for (x in c(ex[1] - 1, ex[2] + 1)) { add("p", c(pm, x, np, lam), pgl(x, lam, param = pn[pm + 1])); add("d", c(pm, x, np, lam), dgl(x, lam, param = pn[pm + 1])) }
  sd <- sample(1:100000, 1); set.seed(sd); v <- rgl(5, lam, param = pn[pm + 1]); for (j in 1:5) add("r", c(pm, sd, np, lam, j - 1), v[j])
  set.seed(20261121 + rep)
}
for (rep in 1:30) {
  l3 <- c(round(runif(1, -0.9, 1.5), 3), 0)[1 + (rep %% 6 == 0)]; l4 <- c(round(runif(1, -0.9, 1.5), 3), 0)[1 + (rep %% 8 == 0)]; par <- c(round(rnorm(1), 2), round(runif(1, 0.3, 3), 2), l3, l4)
  for (ra in c(TRUE, FALSE)) { m <- tryCatch(gld.moments(par, ratios = ra), error = function(e) rep(NA, 4)); for (q in 1:4) add("mom", c(as.integer(ra), 4, par, q - 1), m[q], rel = 1e-8) }
}
for (rep in 1:25) {
  par <- c(round(rnorm(1), 2), round(runif(1, 0.3, 3), 2), round(runif(1, 0.05, 0.95), 2), c(round(runif(1, -0.6, 2), 3), 0)[1 + (rep %% 7 == 0)])
  for (ra in c(TRUE, FALSE)) for (ord in list(1:4, c(1, 2, 3, 4, 5, 6, 8))) {
    m <- suppressWarnings(gld.lmoments(par, order = ord, ratios = ra)); for (j in seq_along(ord)) add("lmom", c(as.integer(ra), as.integer(max(ord) > 4), ord[j], 4, par), m[j])
  }
}
getest <- function(e) { if (is.null(e) || (length(e) == 1 && is.na(e))) return(list(est = rep(NA, 4), se = rep(NA, 4)))
  if (is.matrix(e)) list(est = e[, 1], se = if (ncol(e) > 1) e[, 2] else rep(NA, 4)) else list(est = unname(e), se = rep(NA, 4)) }
for (rep in 1:60) {
  x <- rexp(30 + rep) * runif(1, 0.5, 3) + rnorm(30 + rep); lm <- lmom::samlmu(x, 4); n <- sample(c(20, 100, 500), 1)
  if (rep %% 3 == 0) lm <- c(lm[1], lm[2], runif(1, -0.9, 0.9), runif(1, -0.05, 0.6))
  fit <- suppressWarnings(fit.gpd.lmom.given(lm, n = n)); a <- getest(fit$estA); b <- getest(fit$estB)
  v <- c(a$est, b$est, a$se, b$se); for (j in 1:16) add("gpdfit", c(n, lm, j - 1), v[j], rel = 1e-8)
}
emit("gldfull", "gld", list(cases))
