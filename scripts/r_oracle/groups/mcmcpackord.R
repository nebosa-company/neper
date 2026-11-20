# MCMCpack ordinal and factor samplers under an integer seed (Scythe Mersenne stream). Every case passes (seed, ...) and wants a position-weighted sum of the stored matrix (row-major).
#   "oprobitpolr" and "oprobit_start": (seed, n, k, ncat, burnin, mcmc, thin, tune, y[n] in 1..ncat, X[n*k] row-major with intercept first, b0[k], B0[k*k]) with the start from polr (1e-7 and 1e-6: polr stops at reltol 1.5e-8)
#   "oprobit": the same then beta.start[k] and gamma.start[ncat+1] as R derives them, handed over (equal to 1e-9)
suppressMessages(library(MCMCpack))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(m) sum(seq_along(m) * as.vector(t(m)))
rowm <- function(m) as.vector(t(m))
set.seed(20261123)
for (rep in 1:14) {
  n <- sample(40:90, 1); k <- sample(1:3, 1); ncat <- sample(3:5, 1)
  X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 3), n)); X <- X[, seq_len(k), drop = FALSE]
  tb <- round(rnorm(k, 0, 0.8), 2); cuts <- sort(round(rnorm(ncat - 1, 0, 1), 2))
  lat <- as.vector(X %*% tb) + rnorm(n); y <- 1 + rowSums(outer(lat, cuts, ">"))
  if (length(unique(y)) < ncat) next
  b0 <- round(rnorm(k, 0, 0.3), 2); B0 <- round(crossprod(matrix(round(rnorm(k * k), 2), k)) * 0.2 + diag(k) * 0.1, 4)
  burn <- sample(5:30, 1); thin <- sample(1:3, 1); mc <- thin * sample(15:50, 1); seed <- sample(1:100000, 1)
  tune <- if (rep %% 2 == 0) 0.05 / ncat else round(runif(1, 0.05, 0.4), 3)
  d <- data.frame(y = y); if (k > 1) d <- cbind(d, as.data.frame(X[, -1, drop = FALSE])); o <- MCMCoprobit(if (k > 1) y ~ . else y ~ 1, data = d, burnin = burn, mcmc = mc, thin = thin, seed = seed, tune = tune, b0 = b0, B0 = B0, mcmc.method = "Cowles")
  a <- c(seed, n, k, ncat, burn, mc, thin, tune, y, rowm(X), b0, rowm(B0)); W <- wsum(as.matrix(o))
  pf <- if (k > 1) MASS::polr(ordered(y) ~ X[, -1, drop = FALSE]) else MASS::polr(ordered(y) ~ 1)
  b00 <- c(-0.588 * pf$zeta[1], if (k > 1) 0.588 * coef(pf)); g00 <- c(-300, 0, if (ncat > 2) (pf$zeta[-1] - pf$zeta[1]) * 0.588, 300)
  add("oprobit_start", a, wsum(c(b00, g00[3:ncat])), rel = 1e-6)
  add("oprobit", c(a, b00, g00), W)
  add("oprobitpolr", a, W, rel = 1e-7)
}
#   factanal "fa": (seed, n, K, D, std.var, burnin, mcmc, thin, store.scores, x[n*K] row-major, eq[K*D] (-999 free), ineq[K*D], l0[K*D], L0[K*D], a0[K], b0[K]) wanting the weighted sum of the stored matrix
#   after R drops the columns that never move (the constrained loadings)
for (rep in 1:12) {
  n <- sample(30:70, 1); K <- sample(4:7, 1); D <- sample(1:2, 1)
  L <- matrix(round(rnorm(K * D, 0, 0.8), 2), K, D); Fs <- matrix(rnorm(n * D), n, D)
  x <- round(Fs %*% t(L) + matrix(rnorm(n * K, 0, 0.6), n, K), 3)
  cons <- list(V1 = list(1, "+")); eq <- matrix(-999, K, D); ineq <- matrix(0, K, D); ineq[1, 1] <- 1
  if (D == 2) { cons <- c(cons, list(V1 = list(2, 0), V2 = list(2, "+"))); eq[1, 2] <- 0; ineq[2, 2] <- 1 }
  if (rep %% 3 == 0) { cons <- c(cons, list(V3 = list(1, 0.5))); eq[3, 1] <- 0.5 }
  l0 <- matrix(round(rnorm(K * D, 0, 0.3), 2), K, D); L0 <- matrix(round(runif(K * D, 0, 1), 2), K, D)
  a0 <- round(runif(K, 0.5, 3), 2); b0 <- round(runif(K, 0.5, 3), 2)
  burn <- sample(5:30, 1); thin <- sample(1:3, 1); mc <- thin * sample(15:40, 1); seed <- sample(1:100000, 1)
  sc <- rep %% 2 == 0; sv <- rep %% 3 != 1
  o <- MCMCfactanal(x, factors = D, lambda.constraints = cons, burnin = burn, mcmc = mc, thin = thin, seed = seed, l0 = l0, L0 = L0, a0 = a0, b0 = b0, store.scores = sc, std.var = sv)
  add("fa", c(seed, n, K, D, sv, burn, mc, thin, sc, rowm(x), rowm(eq), rowm(ineq), rowm(l0), rowm(L0), a0, b0), wsum(as.matrix(o)))
}
emit("mcmcpackord", "MCMCpack", list(cases))
