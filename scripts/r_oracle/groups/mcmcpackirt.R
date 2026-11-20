# MCMCpack item response samplers under an integer seed (Scythe Mersenne stream). Every case passes (seed, ...) and wants a position-weighted sum of the stored matrix (row-major).
#   irt1d "irt1d": (seed, J, K, burnin, mcmc, thin, t0, T0, ab0[2], AB0[2*2], theta0[J], alpha0[K], beta0[K], eq[J], ineq[J], x[J*K] row-major, 9 = missing)
suppressMessages(library(MCMCpack))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(m) sum(seq_along(m) * as.vector(t(m)))
rowm <- function(m) as.vector(t(m))
set.seed(20261122)
for (rep in 1:12) {
  J <- sample(6:14, 1); K <- sample(5:12, 1)
  th <- rnorm(J); a <- rnorm(K, 0, 0.5); b <- rnorm(K, 0, 1)
  X <- matrix(rbinom(J * K, 1, pnorm(outer(th, b) - rep(a, each = J))), J, K)
  if (rep %% 3 == 0) X[sample(J * K, 3)] <- NA
  X <- X[, apply(X, 2, function(v) var(v, na.rm = TRUE)) > 0, drop = FALSE]; K <- ncol(X)
  if (K < 3) next
  rownames(X) <- paste0("s", 1:J)
  theta0 <- round(rnorm(J, 0, 0.5), 3); alpha0 <- round(rnorm(1, 0, 0.3), 3); beta0 <- round(rnorm(1, 0.5, 0.3), 3)
  eq <- rep(-999, J); ineq <- rep(0, J); cons <- list(); theta0[1] <- abs(theta0[1]) + 0.1; theta0[2] <- -0.5; theta0[3] <- -abs(theta0[3]) - 0.1
  if (rep %% 2 == 0) { cons[["s1"]] <- "+"; ineq[1] <- 1; cons[["s2"]] <- -0.5; eq[2] <- -0.5 }
  if (rep %% 4 == 1) { cons[["s3"]] <- "-"; ineq[3] <- -1 }
  t0 <- round(rnorm(1, 0, 0.3), 2); T0 <- round(runif(1, 0.5, 2), 2); ab0 <- round(rnorm(2, 0, 0.3), 2)
  AB0 <- round(crossprod(matrix(round(rnorm(4), 2), 2)) * 0.3 + diag(2) * 0.2, 4)
  burn <- sample(5:30, 1); thin <- sample(1:3, 1); mc <- thin * sample(15:40, 1); seed <- sample(1:100000, 1)
  o <- MCMCirt1d(X, theta.constraints = cons, burnin = burn, mcmc = mc, thin = thin, seed = seed, theta.start = theta0, alpha.start = alpha0, beta.start = beta0,
                 t0 = t0, T0 = T0, ab0 = ab0, AB0 = AB0, store.item = TRUE, store.ability = TRUE, drop.constant.items = FALSE)
  Xi <- X; Xi[is.na(Xi)] <- 9
  add("irt1d", c(seed, J, K, burn, mc, thin, t0, T0, ab0, rowm(AB0), theta0, rep(alpha0, K), rep(beta0, K), eq, ineq, rowm(Xi)), wsum(as.matrix(o)))
}
emit("mcmcpackirt", "MCMCpack", list(cases))
