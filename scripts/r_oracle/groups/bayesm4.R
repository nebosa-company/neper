# bayesm rscaleUsage under set.seed, keep = 1, every draw on, the package's default start and priors (a rep with Prior$gs = 30 changes the grids).
#   "scale" (seed, k, p, n, R, ndghk, nu, e0, nuL, x[n p], y0[n p], mu0[p], Sigma0[p p], tau0[n], sigma0[n], Lambda0[4], V[p p], mubar[p], Am[p p], VL[4], gs, gsigma[gs], gl11[gs], gl22[gs], gl12[gs], ge[gs+1], id)
#   draw: Sigma[p p], mu[p], tau[n], sigma[n], Lambda[4], e, per iteration.
suppressMessages(library(bayesm))
cases <- list()
add2 <- function(fn, args, out, tol = 1e-9) {
  L <- length(out); ids <- unique(c(0, floor(L / 3), floor(2 * L / 3), L - 1))
  for (q in ids) cases[[length(cases) + 1]] <<- case(fn, c(args, q), out[q + 1], rel = tol, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case(fn, c(args, -1), sum(out * (1 + (0:(L - 1)) %% 5)), rel = tol, abs = 1e-12)
}
set.seed(20261122)
for (rep in 1:8) {
  k <- sample(5:7, 1); p <- sample(3:5, 1); n <- sample(15:40, 1); R <- 4; nd <- sample(c(10, 25), 1)
  tr <- rnorm(p) * 0.5 + k / 2; S <- crossprod(matrix(rnorm(p * p), p)) * 0.3 + diag(p) * 0.5
  lat <- matrix(rnorm(n * p), n, p) %*% chol(S) + matrix(tr, n, p, byrow = TRUE) + rnorm(n) * 0.7
  x <- matrix(pmin(k, pmax(1, round(lat))), n, p); storage.mode(x) <- "integer"
  gs <- if (rep %% 2 == 0) 30 else 100
  y0 <- matrix(as.double(x), n); mu0 <- apply(y0, 2, mean); Sigma0 <- var(y0); tau0 <- rep(0, n); sig0 <- rep(1, n); Lam0 <- matrix(c(4, 0, 0, .5), 2)
  nu <- p + bayesm:::BayesmConstant.nuInc; V <- nu * diag(p); mubar <- rep(k / 2, p); Am <- bayesm:::BayesmConstant.A * diag(p)
  gsigma <- 6 * (1:gs) / gs; gl11 <- .1 + 5.9 * (1:gs) / gs; gl22 <- .1 + 2.0 * (1:gs) / gs; gl12 <- -2.0 + 4 * (1:gs) / gs
  nuL <- 20; VL <- (nuL - 3) * Lam0; ge <- -.1 + .2 * (0:gs) / gs
  sd <- sample(1:100000, 1); set.seed(sd)
  Prior <- if (gs == 100) NULL else list(gs = gs)
  o <- suppressWarnings(rscaleUsage(Data = list(k = k, x = x), Prior = Prior, Mcmc = list(R = R, keep = 1, ndghk = nd, nprint = 0)))
  flat <- as.vector(t(cbind(o$Sigmadraw, o$mudraw, o$taudraw, o$sigmadraw, o$Lambdadraw, o$edraw)))
  add2("scale", c(sd, k, p, n, R, nd, nu, 0, nuL, x, y0, mu0, Sigma0, tau0, sig0, Lam0, V, mubar, Am, VL, gs, gsigma, gl11, gl22, gl12, ge), flat)
}
emit("bayesm4", "bayesm", list(cases))
