# MCMCpack::MCMChregress under an integer seed (Scythe Mersenne stream). Starts are handed over (beta.start, sigma2.start, Vb.start).
#   "hreg" and "hregpred": (seed, n, ng, np, nq, burnin, mcmc, thin, r, s1, s2, sig0, grp[n] 0-based, y[n], X[n*np] row-major, W[n*nq], mubeta[np], Vbeta[np*np], R[nq*nq], beta0[np], Vb0[nq*nq])
#   "hreg" wants the position-weighted sum of the stored matrix (row-major, R's column order); "hregpred" the same of Y.pred
suppressMessages(library(MCMCpack))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(m) sum(seq_along(m) * as.vector(t(m)))
rowm <- function(m) as.vector(t(m))
set.seed(20261124)
for (rep in 1:14) {
  ng <- sample(3:7, 1); per <- sample(3:8, ng, replace = TRUE); n <- sum(per)
  g <- rep(seq_len(ng), per); np <- sample(1:3, 1); nq <- sample(1:2, 1)
  x <- matrix(round(rnorm(n * np), 3), n); if (np > 0) x[, 1] <- 1
  W <- cbind(1, matrix(round(rnorm(n), 3), n))[, seq_len(nq), drop = FALSE]
  y <- round(rowSums(x) * 0.5 + rnorm(ng)[g] + rnorm(n), 3)
  d <- data.frame(y = y, grp = sprintf("g%02d", g)); for (j in seq_len(np)) d[[paste0("x", j)]] <- x[, j]; for (j in seq_len(nq)) d[[paste0("w", j)]] <- W[, j]
  fx <- as.formula(paste("y ~ -1 +", paste0("x", seq_len(np), collapse = " + ")))
  rd <- as.formula(paste("~ -1 +", paste0("w", seq_len(nq), collapse = " + ")))
  mubeta <- round(rnorm(np, 0, 0.5), 2); Vbeta <- round(crossprod(matrix(round(rnorm(np * np), 2), np)) + diag(np), 4)
  r <- sample(nq:(nq + 3), 1); R <- round(crossprod(matrix(round(rnorm(nq * nq), 2), nq)) + diag(nq), 4)
  s1 <- round(runif(1, 0.5, 3), 2); s2 <- round(runif(1, 0.5, 3), 2)
  beta0 <- round(rnorm(np), 2); sig0 <- round(runif(1, 1, 3.9), 2); Vb0 <- diag(nq) * round(runif(1, 0.5, 2), 2)
  burn <- 10 * sample(1:4, 1); thin <- sample(c(1, 2, 5), 1); mc <- 10 * sample(10:16, 1); seed <- sample(1:100000, 1)
  o <- MCMChregress(fixed = fx, random = rd, group = "grp", data = d, burnin = burn, mcmc = mc, thin = thin, verbose = 0, seed = seed,
    beta.start = beta0, sigma2.start = sig0, Vb.start = Vb0, mubeta = mubeta, Vbeta = Vbeta, r = r, R = R, nu = s1, delta = s2)
  a <- c(seed, n, ng, np, nq, burn, mc, thin, r, s1, s2, sig0, g - 1, y, rowm(x), rowm(W), mubeta, rowm(Vbeta), rowm(R), beta0, rowm(Vb0))
  add("hreg", a, wsum(as.matrix(o$mcmc))); add("hregpred", a, wsum(matrix(o$Y.pred, 1)))
}
emit("mcmcpackhreg", "MCMCpack", list(cases))
