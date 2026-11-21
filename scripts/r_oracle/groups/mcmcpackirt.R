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
# default starts (theta.start, alpha.start, beta.start left to R): "irt1d_def" has the irt1d layout without the three start blocks
set.seed(20261123)
nacc <- 0
for (rep in 1:80) {
  if (nacc >= 14) break
  J <- sample(10:20, 1); K <- sample(5:12, 1)
  th <- rnorm(J); a <- rnorm(K, 0, 0.5); b <- rnorm(K, 0, 0.6)
  X <- matrix(rbinom(J * K, 1, pnorm(outer(th, b) - rep(a, each = J))), J, K)
  if (rep %% 3 == 0) X[sample(J * K, 3)] <- NA
  keep <- apply(X, 2, function(v) var(v, na.rm = TRUE)) > 0
  if (rep %% 5 == 0) keep[1] <- FALSE
  X <- X[, keep | seq_len(K) == 1, drop = FALSE]
  if (rep %% 5 == 0) X[, 1] <- 1
  K <- ncol(X)
  if (K < 3) next
  rownames(X) <- paste0("s", 1:J)
  eq <- rep(-999, J); ineq <- rep(0, J); cons <- list()
  if (rep %% 2 == 0) { cons[["s1"]] <- "+"; ineq[1] <- 1; cons[["s2"]] <- -0.5; eq[2] <- -0.5 }
  if (rep %% 4 == 1) { cons[["s3"]] <- "-"; ineq[3] <- -1 }
  t0 <- round(rnorm(1, 0, 0.3), 2); T0 <- round(runif(1, 0.5, 2), 2); ab0 <- round(rnorm(2, 0, 0.3), 2)
  AB0 <- round(crossprod(matrix(round(rnorm(4), 2), 2)) * 0.3 + diag(2) * 0.2, 4)
  # short chains: the default start is bit-identical to R's ("irt1d_st"), but a Gibbs chain amplifies the last-bit libm differences, about 1e-14 after 15 sweeps and 1e-6 after 100, so 1e-9 holds for burn-in up to 8 and 20 draws
  burn <- sample(2:8, 1); thin <- sample(1:3, 1); mc <- thin * sample(8:20, 1); seed <- sample(1:100000, 1)
  Xi <- X; Xi[is.na(Xi)] <- 9
  # only well-conditioned default starts (every item probit fit converges in under 6 IRLS steps) so the case runs at the repo tolerance
  ts <- MCMCpack:::factor.score.start.check(NA, Xi, t0, matrix(T0), matrix(eq), matrix(ineq), 1)
  its <- 0
  for (i in 1:K) { y <- X[, i]; if (isTRUE(var(y, na.rm = TRUE) > 0)) its <- max(its, suppressWarnings(glm(y ~ ts, family = binomial("probit"), control = glm.control(maxit = 8, epsilon = 0.001)))$iter) }
  if (its >= 6) next
  o <- try(MCMCirt1d(X, theta.constraints = cons, burnin = burn, mcmc = mc, thin = thin, seed = seed,
                     t0 = t0, T0 = T0, ab0 = ab0, AB0 = AB0, store.item = TRUE, store.ability = TRUE, drop.constant.items = FALSE), silent = TRUE)
  if (inherits(o, "try-error")) next
  nacc <- nacc + 1
  ab <- matrix(NA, K, 2)
  for (i in 1:K) { y <- Xi[, i]; y[y == 9] <- NA
    ab[i, ] <- if (var(na.omit(y)) == 0) c(0, 10) else coef(suppressWarnings(glm(y ~ ts, family = binomial("probit"), control = glm.control(maxit = 8, epsilon = 0.001)))) }
  ab[, 1] <- -ab[, 1]
  add("irt1d_st", c(seed, J, K, burn, mc, thin, t0, T0, ab0, rowm(AB0), eq, ineq, rowm(Xi)), sum(seq_len(J + 2 * K) * c(as.vector(ts), ab[, 1], ab[, 2])), rel = 1e-9, abs = 1e-11)
  add("irt1d_def", c(seed, J, K, burn, mc, thin, t0, T0, ab0, rowm(AB0), eq, ineq, rowm(Xi)), wsum(as.matrix(o)), rel = 1e-9, abs = 1e-11)
}
# probit glm start fit alone ("glm1": (0, maxit, eps, m, y[m], t[m]), want coef[1] + 2 coef[2]): eps sits 2 percent either side of one iteration's deviance criterion so the stop test, the deviance
# scale and its denominator constant decide the answer; the separated data push |eta| past the mu.eta floor (2.22e-16 clamp)
g1 <- function(y, t, maxit, eps) { cf <- coef(suppressWarnings(glm(y ~ t, family = binomial("probit"), control = glm.control(maxit = maxit, epsilon = eps)))); unname(cf[1] + 2 * cf[2]) }
set.seed(20261125)
for (rep in 1:10) {
  m <- sample(12:40, 1); t <- round(rnorm(m), 3)
  y <- rbinom(m, 1, pnorm(0.3 + 1.1 * t)); if (var(y) == 0) next
  mu <- pnorm(qnorm((y + 0.5) / 2)); dv <- function(mu) sum(binomial()$dev.resids(y, mu, 1))
  devs <- dv(mu)
  for (k in 1:6) devs <- c(devs, deviance(suppressWarnings(glm(y ~ t, family = binomial("probit"), control = glm.control(maxit = k, epsilon = 1e-300)))))
  r <- abs(diff(devs)) / (abs(devs[-1]) + 0.1)
  for (k in 1:3) for (f in c(1.003, 0.997)) add("glm1", c(0, 50, r[k] * f, m, y, t), g1(y, t, 50, r[k] * f), rel = 1e-9, abs = 1e-11)
}
for (rep in 1:4) {
  m <- sample(8:14, 1); t <- round(sort(rnorm(m)), 3); y <- as.numeric(t > t[m %/% 2] - 0.01)
  for (mx in c(12, 25)) add("glm1", c(0, mx, 1e-14, m, y, t), g1(y, t, mx, 1e-14), rel = 1e-9, abs = 1e-11)
}
emit("mcmcpackirt", "MCMCpack", list(cases))
