# bayesm Gibbs samplers under set.seed, keep = 1: rnmixGibbs, rivGibbs, rhierLinearModel, rmnpGibbs, rmvpGibbs, rhierMnlRwMixture, rscaleUsage.
#   Each sampler is one fn; args end with an id into the flattened draws (layout in the fixture), id -1 is a weighted checksum over all of them.
suppressMessages(library(bayesm))
cases <- list()
add2 <- function(fn, args, out, tol = 1e-9) {
  L <- length(out); ids <- unique(c(0, floor(L / 3), floor(2 * L / 3), L - 1))
  for (q in ids) cases[[length(cases) + 1]] <<- case(fn, c(args, q), out[q + 1], rel = tol, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case(fn, c(args, -1), sum(out * (1 + (0:(L - 1)) %% 5)), rel = tol, abs = 1e-12)
}
set.seed(20261120)
rspd <- function(k) { M <- matrix(rnorm(k * k), k); crossprod(M) + diag(k) * 0.5 }

# "nmix" (seed, n, d, nc, R, A00, nu, Mubar[d], V[d d], a[nc], y[n d], id); draw: p[nc], z[n], then per component mu[d], rooti[d d]
for (rep in 1:8) {
  n <- sample(c(12, 30, 60), 1); d <- sample(1:3, 1); nc <- sample(2:5, 1); R <- 6
  y <- matrix(rnorm(n * d), n, d) + matrix(sample(c(0, 4), n, TRUE), n, d)
  A00 <- runif(1, 0.01, 0.5); nu <- d + sample(2:6, 1); Mubar <- rnorm(d); V <- rspd(d) * nu; a <- runif(nc, 1, 6)
  sd <- sample(1:100000, 1); set.seed(sd)
  o <- rnmixGibbs(Data = list(y = y), Prior = list(ncomp = nc, Mubar = matrix(Mubar, 1), A = matrix(A00, 1), nu = nu, V = V, a = a), Mcmc = list(R = R, keep = 1, nprint = 0))$nmix
  flat <- unlist(lapply(1:R, function(i) c(o$probdraw[i, ], o$zdraw[i, ], unlist(lapply(o$compdraw[[i]], function(cc) c(cc$mu, as.vector(cc$rooti)))))))
  add2("nmix", c(sd, n, d, nc, R, A00, nu, Mubar, V, a, y), flat)
}

# "iv" (seed, n, dd, dg, R, nu, md[dd], Ad[dd dd], mbg[1+dg], Abg[(1+dg)^2], V[4], y, x, z[n dd], w[n dg], id); draw: delta[dd], beta, gamma[dg], Sigma[4]
for (rep in 1:8) {
  n <- sample(30:120, 1); dd <- sample(1:3, 1); dg <- sample(1:2, 1)
  z <- matrix(rnorm(n * dd), n, dd); w <- cbind(1, matrix(rnorm(n * (dg - 1)), n, dg - 1)); e <- matrix(rnorm(2 * n), n, 2) %*% chol(matrix(c(1, .6, .6, 1), 2))
  x <- as.vector(z %*% rnorm(dd) + e[, 1]); y <- as.vector(0.7 * x + w %*% rnorm(dg) + e[, 2])
  md <- rnorm(dd) * 0.1; Ad <- rspd(dd) * 0.01; mbg <- rnorm(1 + dg) * 0.1; Abg <- rspd(1 + dg) * 0.01; nu <- 3 + sample(0:4, 1); V <- rspd(2) * nu; R <- 6
  sd <- sample(1:100000, 1); set.seed(sd)
  o <- rivGibbs(Data = list(z = z, w = w, x = x, y = y), Prior = list(md = md, Ad = Ad, mbg = mbg, Abg = Abg, nu = nu, V = V), Mcmc = list(R = R, keep = 1, nprint = 0))
  flat <- as.vector(t(cbind(o$deltadraw, o$betadraw, o$gammadraw, o$Sigmadraw)))
  add2("iv", c(sd, n, dd, dg, R, nu, md, Ad, mbg, Abg, V, y, x, z, w), flat)
}
# "hlin" (seed, nreg, nvar, nz, R, nu, nu.e, Z[nreg nz], Deltabar[nz nvar], A[nz nz], V[nvar nvar], ssq[nreg], tau0[nreg], ns[nreg], y (concatenated), X (concatenated, each n_i by nvar), id); draw: Vbeta, Delta, tau[nreg], betas[nreg nvar]
for (rep in 1:8) {
  nreg <- sample(5:12, 1); nvar <- sample(2:3, 1); nz <- sample(1:2, 1); R <- 6
  Z <- cbind(1, matrix(rnorm(nreg * (nz - 1)), nreg, nz - 1)); ns <- sample(10:30, nreg, TRUE)
  regdata <- lapply(1:nreg, function(i) { X <- cbind(1, matrix(rnorm(ns[i] * (nvar - 1)), ns[i], nvar - 1)); list(y = as.vector(X %*% rnorm(nvar) + rnorm(ns[i])), X = X) })
  nu <- nvar + sample(1:5, 1); nue <- sample(3:8, 1); V <- rspd(nvar) * nu; A <- rspd(nz) * 0.05; Dbar <- matrix(rnorm(nz * nvar) * 0.2, nz, nvar); ssq <- runif(nreg, 0.5, 3)
  tau0 <- sapply(regdata, function(l) var(l$y))
  sd <- sample(1:100000, 1); set.seed(sd)
  o <- rhierLinearModel(Data = list(regdata = regdata, Z = Z), Prior = list(Deltabar = Dbar, A = A, nu.e = nue, ssq = ssq, nu = nu, V = V), Mcmc = list(R = R, keep = 1, nprint = 0))
  flat <- unlist(lapply(1:R, function(i) c(o$Vbetadraw[i, ], o$Deltadraw[i, ], o$taudraw[i, ], as.vector(o$betadraw[, , i]))))
  add2("hlin", c(sd, nreg, nvar, nz, R, nu, nue, Z, Dbar, A, V, ssq, tau0, ns, unlist(lapply(regdata, function(l) l$y)), unlist(lapply(regdata, function(l) as.vector(l$X)))), flat)
}
# "mnp" (seed, mvp, p, n, k, R, nu, beta0[k], sigma0[p p], V[p p], betabar[k], A[k k], y[n, or n p when mvp], X[n p, k], id): rmnpGibbs (mvp 0, p = number of alternatives - 1) and rmvpGibbs (mvp 1); draw: beta[k], Sigma[p p]
for (rep in 1:10) {
  mvp <- rep %% 2; p <- sample(2:3, 1); n <- sample(25:80, 1); k <- sample(2:4, 1); R <- 5
  X <- matrix(rnorm(n * p * k), n * p, k); nu <- p + sample(2:5, 1); V <- rspd(p) * nu; betabar <- rnorm(k) * 0.2; A <- rspd(k) * 0.05; beta0 <- rnorm(k) * 0.3; sigma0 <- diag(runif(p, 0.5, 2), p)
  sd <- sample(1:100000, 1)
  if (mvp) {
    y <- as.vector(X %*% rnorm(k) + rnorm(n * p) > 0) * 1; set.seed(sd)
    o <- rmvpGibbs(Data = list(p = p, y = y, X = X), Prior = list(betabar = betabar, A = A, nu = nu, V = V), Mcmc = list(R = R, keep = 1, nprint = 0, beta0 = beta0, sigma0 = sigma0))
  } else {
    y <- c(1:(p + 1), sample(p + 1, n - p - 1, TRUE)); set.seed(sd)
    o <- rmnpGibbs(Data = list(p = p + 1, y = y, X = X), Prior = list(betabar = betabar, A = A, nu = nu, V = V), Mcmc = list(R = R, keep = 1, nprint = 0, beta0 = beta0, sigma0 = sigma0))
  }
  flat <- as.vector(t(cbind(o$betadraw, o$sigmadraw)))
  add2("mnp", c(sd, mvp, p, n, k, R, nu, beta0, sigma0, V, betabar, A, y, X), flat)
}
emit("bayesm2", "bayesm", list(cases))
