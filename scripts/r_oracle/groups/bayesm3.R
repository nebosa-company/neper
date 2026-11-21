# bayesm rhierMnlRwMixture under set.seed, keep = 1. The tuning pass (optim) is replicated here and its outputs (starting betas, Hessians) are arguments:
#   "hmnl" (seed, nlgt, nvar, nz, p, nc, R, nu, Amu, s, mubar[nvar], V[nvar nvar], a[nc], SignRes[nvar], deltabar[nz nvar], Ad[(nz nvar)^2], Z[nlgt nz], oldbetas[nlgt nvar], ns[nlgt], y (concatenated), X (concatenated, each n_i p by nvar), hess[nlgt nvar nvar], id)
#   draw: betas[nlgt nvar], prob[nc], loglike, Delta[nz nvar], then per component mu[nvar], rooti[nvar nvar]; nz = 0 is the no-Z form.
suppressMessages(library(bayesm))
cases <- list()
add2 <- function(fn, args, out, tol = 1e-9) {
  L <- length(out); ids <- unique(c(0, floor(L / 3), floor(2 * L / 3), L - 1))
  for (q in ids) cases[[length(cases) + 1]] <<- case(fn, c(args, q), out[q + 1], rel = tol, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case(fn, c(args, -1), sum(out * (1 + (0:(L - 1)) %% 5)), rel = tol, abs = 1e-12)
}
set.seed(20261121)
rspd <- function(k) { M <- matrix(rnorm(k * k), k); crossprod(M) + diag(k) * 0.5 }
llmnl_con <- bayesm:::llmnl_con
mnlHess_con <- function(betastar, y, X, SignRes = rep(0, ncol(X))) {
  beta <- betastar; beta[SignRes != 0] <- SignRes[SignRes != 0] * exp(betastar[SignRes != 0])
  n <- length(y); j <- nrow(X) / n; k <- ncol(X)
  Xbeta <- exp(matrix(X %*% beta, byrow = TRUE, ncol = j)); Prob <- Xbeta / as.vector(Xbeta %*% rep(1, j))
  Hess <- matrix(0, k, k)
  for (i in 1:n) { pp <- as.vector(Prob[i, ]); A <- diag(pp) - outer(pp, pp); Xt <- X[(j * (i - 1) + 1):(j * i), ]; Hess <- Hess + crossprod(Xt, A) %*% Xt }
  lambda <- rep(1, length(SignRes)); lambda[SignRes == 1] <- beta[SignRes == 1]; lambda[SignRes == -1] <- -beta[SignRes == -1]
  Hess * crossprod(t(lambda))
}
llmnlFract <- function(beta, y, X, betapooled, rootH, w, wgt, SignRes = rep(0, ncol(X))) {
  z <- as.vector(rootH %*% (beta - betapooled)); (1 - w) * llmnl_con(beta, y, X, SignRes) + w * wgt * (-.5 * (z %*% z))
}
tune <- function(lgtdata, nvar, SignRes, w) {
  ypooled <- unlist(lapply(lgtdata, function(l) l$y)); Xpooled <- do.call(rbind, lapply(lgtdata, function(l) l$X))
  out <- optim(rep(0, nvar), llmnl_con, method = "BFGS", control = list(fnscale = -1, trace = 0, reltol = 1e-6), X = Xpooled, y = ypooled, SignRes = rep(0, nvar))
  bi <- out$par; bi[SignRes != 0] <- 0
  out <- optim(bi, llmnl_con, control = list(fnscale = -1, trace = 0, reltol = 1e-6), X = Xpooled, y = ypooled, SignRes = SignRes)
  bp <- out$par; H <- mnlHess_con(bp, ypooled, Xpooled, SignRes); rootH <- chol(H)
  hess <- list(); ob <- matrix(0, length(lgtdata), nvar)
  for (i in seq_along(lgtdata)) {
    wgt <- length(lgtdata[[i]]$y) / length(ypooled)
    out <- optim(bp, llmnlFract, method = "BFGS", control = list(fnscale = -1, trace = 0, reltol = 1e-4), X = lgtdata[[i]]$X, y = lgtdata[[i]]$y, betapooled = bp, rootH = rootH, w = w, wgt = wgt, SignRes = SignRes)
    if (out$convergence == 0) { hess[[i]] <- mnlHess_con(out$par, lgtdata[[i]]$y, lgtdata[[i]]$X, SignRes); ob[i, ] <- out$par } else { hess[[i]] <- diag(nvar) }
  }
  list(oldbetas = ob, hess = hess)
}
for (rep in 1:8) {
  nlgt <- sample(8:14, 1); nvar <- sample(2:3, 1); p <- sample(3:4, 1); nz <- if (rep %% 2 == 0) sample(1:2, 1) else 0; nc <- sample(1:3, 1); R <- 5
  sres <- rep(0, nvar); if (rep %in% c(3, 4)) sres[1] <- 1
  ns <- sample(6:12, nlgt, TRUE); btrue <- rnorm(nvar) * 0.7
  lgtdata <- lapply(1:nlgt, function(i) { X <- matrix(rnorm(ns[i] * p * nvar), ns[i] * p, nvar); b <- btrue + rnorm(nvar) * 0.4; if (sres[1] == 1) b[1] <- abs(b[1])
    pr <- matrix(exp(X %*% b), ns[i], p, byrow = TRUE); y <- apply(pr, 1, function(q) sample(p, 1, prob = q)); list(y = y, X = X) })
  Z <- if (nz > 0) scale(matrix(rnorm(nlgt * nz), nlgt, nz), scale = FALSE) else NULL
  nu <- nvar + sample(3:6, 1); V <- rspd(nvar) * nu * 0.3; Amu <- runif(1, 0.02, 0.2); a <- runif(nc, 2, 6); mubar <- rnorm(nvar) * 0.3 + 2 * abs(sres)
  Ad <- if (nz > 0) rspd(nz * nvar) * 0.05 else matrix(0); dbar <- if (nz > 0) rnorm(nz * nvar) * 0.1 else 0
  s <- bayesm:::BayesmConstant.RRScaling / sqrt(nvar) * runif(1, 0.5, 1)
  tn <- tune(lgtdata, nvar, sres, bayesm:::BayesmConstant.w)
  sd <- sample(1:100000, 1); set.seed(sd)
  Data <- list(p = p, lgtdata = lgtdata); if (nz > 0) Data$Z <- Z
  Prior <- list(ncomp = nc, mubar = mubar, Amu = matrix(Amu), nu = nu, V = V, a = a, SignRes = sres); if (nz > 0) { Prior$Ad <- Ad; Prior$deltabar <- dbar }
  o <- rhierMnlRwMixture(Data = Data, Prior = Prior, Mcmc = list(R = R, keep = 1, nprint = 0, s = s))
  flat <- unlist(lapply(1:R, function(i) c(as.vector(o$betadraw[, , i]), o$nmix$probdraw[i, ], o$loglike[i], if (nz > 0) o$Deltadraw[i, ], unlist(lapply(o$nmix$compdraw[[i]], function(cc) c(cc$mu, as.vector(cc$rooti)))))))
  add2("hmnl", c(sd, nlgt, nvar, nz, p, nc, R, nu, Amu, s, mubar, V, a, sres, if (nz > 0) dbar, if (nz > 0) Ad, Z, tn$oldbetas, ns, unlist(lapply(lgtdata, function(l) l$y)), unlist(lapply(lgtdata, function(l) as.vector(l$X))), unlist(lapply(tn$hess, as.vector))), flat)
}
emit("bayesm3", "bayesm", list(cases))
