# MCMCoprobit with mcmc.method "AC" (Scythe BFGS + multivariate t proposal) and the Cowles method under a user beta.start, under an integer seed (Scythe Mersenne stream).
#   "ac" and "cowles_user": (seed, n, k, ncat, burnin, mcmc, thin, tune, tdf, y[n] in 1..ncat, X[n*k] row-major with intercept first, b0[k], B0[k*k], a0[ncat-1], A0[(ncat-1)^2], beta.start[k], gamma.start[ncat+1])
#   beta.start is a scalar recycled over k (the only user start R 4.6 accepts); gamma.start is the one R derives from polr (its value is not user-settable), handed over; the weighted sum of the stored matrix (row-major) is wanted
suppressMessages(library(MCMCpack))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(m) sum(seq_along(m) * as.vector(t(m)))
rowm <- function(m) as.vector(t(m))
set.seed(20261125)
for (rep in 1:40) {
  n <- sample(40:80, 1); k <- sample(1:3, 1); ncat <- sample(3:5, 1)
  X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 3), n)); X <- X[, seq_len(k), drop = FALSE]
  tb <- round(rnorm(k, 0, 0.8), 2); cuts <- sort(round(rnorm(ncat - 1, 0, 1), 2))
  lat <- as.vector(X %*% tb) + rnorm(n); y <- 1 + rowSums(outer(lat, cuts, ">"))
  if (length(unique(y)) < ncat) next
  b0 <- round(rnorm(k, 0, 0.3), 2); B0 <- round(crossprod(matrix(round(rnorm(k * k), 2), k)) * 0.2 + diag(k) * 0.1, 4)
  m <- ncat - 1; a0 <- round(rnorm(m, 0, 0.5), 2); A0 <- round(crossprod(matrix(round(rnorm(m * m), 2), m)) * 0.2 + diag(m) * 0.3, 4)
  burn <- sample(5:15, 1); thin <- sample(1:2, 1); mc <- thin * sample(10:25, 1); seed <- sample(1:100000, 1)
  tune <- round(runif(1, 0.5, 1.2), 3); tdf <- sample(c(3, 5, 8), 1)
  sb <- round(rnorm(1, 0, 0.5), 2); beta0 <- rep(sb, k) # R 4.6 rejects a vector beta.start (is.na of length > 1), so the user start is a scalar R recycles
  d <- data.frame(y = y); if (k > 1) d <- cbind(d, as.data.frame(X[, -1, drop = FALSE]))
  fm <- if (k > 1) y ~ . else y ~ 1
  pf <- tryCatch(if (k > 1) MASS::polr(ordered(y) ~ X[, -1, drop = FALSE]) else MASS::polr(ordered(y) ~ 1), error = function(e) NULL)
  if (is.null(pf)) next
  g00 <- c(-300, 0, if (ncat > 2) (pf$zeta[-1] - pf$zeta[1]) * 0.588, 300)
  a <- c(seed, n, k, ncat, burn, mc, thin, tune, tdf, y, rowm(X), b0, rowm(B0), a0, rowm(A0), beta0, g00)
  # The Scythe BFGS runs on finite differences of step eps^(1/4), so its minimum moves with the last bits of exp, log and pnorm of the platform's libm: the same C++ compiled with
  # another compiler gave a chain 4e-6 to 1 away from R's, and Neper's trace of one iteration agrees with that build to 1e-6. Long chains therefore cannot be matched; a short chain
  # (4 draws after a burn-in of 0 to 2) is kept when R's own answer is stable under a nudge of the start, and is compared at 1e-4.
  runac <- function(b, tn) tryCatch(MCMCoprobit(fm, data = d, burnin = bs, mcmc = 4, thin = 1, seed = seed, tune = tn, tdf = tdf, b0 = b0, B0 = B0, a0 = a0, A0 = A0, beta.start = b, mcmc.method = "AC"), error = function(e) NULL)
  bs <- sample(0:2, 1); as_ <- a; as_[5] <- bs; as_[6] <- 4; as_[7] <- 1
  o <- runac(sb, tune); op <- runac(sb * (1 + 1e-12), tune * (1 + 1e-12))
  if (!is.null(o) && !is.null(op) && max(abs(as.matrix(o) - as.matrix(op))) < 1e-6) add("ac", as_, wsum(as.matrix(o)), rel = 1e-4)
  # a tiny tune rejects every proposal (the start is far from the minimum), which pins the stream consumption of the optimiser (1e-6: its draws sit at the minimum, so they inherit the optimiser noise)
  a3 <- a; a3[5] <- 0; a3[6] <- 2; a3[7] <- 1; a3[8] <- 1e-7
  o3 <- tryCatch(MCMCoprobit(fm, data = d, burnin = 0, mcmc = 2, thin = 1, seed = seed, tune = 1e-7, tdf = tdf, b0 = b0, B0 = B0, a0 = a0, A0 = A0, beta.start = sb, mcmc.method = "AC"), error = function(e) NULL)
  if (!is.null(o3)) add("ac", a3, wsum(as.matrix(o3)), rel = 1e-6)
  o2 <- MCMCoprobit(fm, data = d, burnin = burn, mcmc = mc, thin = thin, seed = seed, tune = 0.05 / ncat, b0 = b0, B0 = B0, a0 = a0, A0 = A0, beta.start = sb, mcmc.method = "Cowles")
  a2 <- a; a2[8] <- 0.05 / ncat
  add("cowles_user", a2, wsum(as.matrix(o2)))
}
emit("mcmcpackac", "MCMCpack", list(cases))
