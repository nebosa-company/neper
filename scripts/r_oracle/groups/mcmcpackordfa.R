# MCMCpack ordinal data factor analysis and K-dimensional item response (Scythe Mersenne stream). Every case wants the position-weighted sum of the matrix R returns (row-major,
# the columns R drops for not moving removed; for MCMCirtKd R has negated the alpha columns, which the Neper side must do too).
#   "ord" and "irtkd": (seed, type 0 ord 1 irtkd, n, K, D = factors + 1, maxc, burnin, mcmc, thin, store.lambda, store.scores, tune[K], ncat[K], x[n*K] row-major 1-based, -999 missing,
#                       eq[K*D], ineq[K*D], l0[K*D], L0[K*D] (as handed to R), lam0[K*D], gm0[(maxc+1)*K] row-major)
#   "ordd" (same layout, lam0 and gm0 ignored): R's own default start values (the intercept-only probit and polr fits), so only as exact as glm (deviance epsilon 1e-8) and polr (reltol 1.5e-8) allow: 1e-5
suppressMessages(library(MCMCpack)); suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
rowm <- function(m) as.vector(t(m))
wkeep <- function(m, K, D, irt, storelam) {
  m <- as.matrix(m)
  sum(seq_along(m) * as.vector(t(m)))
}
set.seed(20261124)
for (rep in 1:16) {
  type <- rep %% 2; n <- sample(40:80, 1); K <- sample(4:6, 1); D <- sample(2:3, 1); fac <- D - 1
  Fs <- matrix(rnorm(n * fac), n, fac); L <- matrix(round(rnorm(K * fac, 0, 0.9), 2), K, fac); ic <- round(rnorm(K, 0, 0.5), 2)
  lat <- Fs %*% t(L) + matrix(rep(ic, each = n), n, K) + matrix(rnorm(n * K), n, K)
  ncat <- if (type == 1) rep(2, K) else sample(2:4, K, replace = TRUE)
  x <- matrix(NA, n, K)
  for (j in 1:K) x[, j] <- findInterval(lat[, j], if (ncat[j] == 2) 0 else sort(quantile(lat[, j], seq_len(ncat[j] - 1) / ncat[j])), rightmost.closed = FALSE) + 1
  if (rep %% 3 == 0) x[sample(n * K, 4)] <- NA
  ok <- TRUE; for (j in 1:K) if (length(unique(na.omit(x[, j]))) != ncat[j]) ok <- FALSE
  if (!ok) next
  cons <- list(V1 = list(2, "+")); eq <- matrix(-999, K, D); ineq <- matrix(0, K, D); ineq[1, 2] <- 1
  if (D == 3) { cons <- c(cons, list(V1 = list(3, 0), V2 = list(3, "+"))); eq[1, 3] <- 0; ineq[2, 3] <- 1 }
  l0 <- matrix(round(rnorm(K * D, 0, 0.3), 2), K, D); L0 <- matrix(round(runif(K * D, 0, 0.8), 2), K, D)
  burn <- sample(5:25, 1); thin <- sample(1:3, 1); mc <- thin * sample(15:35, 1); seed <- sample(1:100000, 1)
  ss <- rep %% 3 != 1; sl <- (rep %% 4 < 2) || !ss
  tn <- if (rep %% 5 == 0) round(runif(1, 0.1, 0.6), 2) else NA
  tuneK <- if (is.na(tn)) 0.05 / ncat else rep(tn, K) / ncat
  maxc <- max(ncat)
  # R's start values as MCMCordfactanal derives them
  lam0 <- matrix(0, K, D); gm0 <- matrix(0, maxc + 1, K)
  for (i in 1:K) {
    xi <- x[!is.na(x[, i]), i]
    for (j in 1:D) {
      if (eq[i, j] == -999) {
        if (ineq[i, j] == 0 && j == 1) lam0[i, j] <- if (ncat[i] == 2) unname(coef(glm(as.factor(xi) ~ 1, family = binomial(link = "probit")))[1]) else -polr(ordered(xi) ~ 1)$zeta[1] * 0.588
        if (ineq[i, j] > 0) lam0[i, j] <- 1
        if (ineq[i, j] < 0) lam0[i, j] <- -1
      } else lam0[i, j] <- eq[i, j]
    }
    if (ncat[i] <= 2) gm0[1:3, i] <- c(-300, 0, 300) else { z <- polr(ordered(xi) ~ 1)$zeta; gm0[1:2, i] <- c(-300, 0); gm0[3:ncat[i], i] <- (z[2:(ncat[i] - 1)] - z[1]) * 0.588; gm0[ncat[i] + 1, i] <- 300 }
  }
  s0 <- round(runif(1, -0.4, 0.6), 2); lam0 <- matrix(s0, K, D); lam0[eq != -999] <- eq[eq != -999]
  xr <- x; xr[is.na(xr)] <- -999
  a <- c(seed, type, n, K, D, maxc, burn, mc, thin, sl, ss, tuneK, ncat, rowm(xr), rowm(eq), rowm(ineq), rowm(l0), rowm(L0), rowm(lam0), rowm(gm0))
  tuneArg <- if (is.na(tn)) NA else tn
  if (type == 0) {
    run <- function(ls) suppressMessages(capture.output(o <<- MCMCordfactanal(x, factors = fac, lambda.constraints = cons, burnin = burn, mcmc = mc, thin = thin, seed = seed, tune = tuneArg, lambda.start = ls, l0 = l0, L0 = L0, store.lambda = sl, store.scores = ss, drop.constantvars = FALSE)))
  } else {
    run <- function(ls) { o <<- MCMCirtKd(x - 1, dimensions = fac, item.constraints = cons, burnin = burn, mcmc = mc, thin = thin, seed = seed, alphabeta.start = ls, b0 = l0, B0 = L0, store.item = sl, store.ability = ss, drop.constant.items = FALSE) }
  }
  o <- NULL
  if (type == 0) { invisible(run(s0)) } else { run(s0) }
  add(if (type == 0) "ord" else "irtkd", a, wkeep(o, K, D, type == 1, sl))
  if (rep %% 4 == 0 || type == 1) { o <- NULL; if (type == 0) invisible(run(NA)) else run(NA); add("ordd", a, wkeep(o, K, D, type == 1, sl), rel = 1e-5) }
}
emit("mcmcpackordfa", "MCMCpack", list(cases))
