# bayesm: log densities (lndMvn, lndMvst, lndIWishart, lndIChisq, llmnl, condMom) and the samplers rdirichlet, rtrun, rwishart, breg under set.seed.
#   fn "mvn" (k, x, mu, rooti) "mvst" (k, nu, normc, x, mu, rooti) "iw" (k, nu, V, IW) "ic" (nu, ssq, x) "mn" (k, p, n, beta, y, X) "cm" (id, k, i, x, mu, sigi) id 0 mean 1 var
#   "dir" (seed, m, alpha, index) "trun" (seed, mu, sigma, a, b) "wish" (seed, k, nu, V, block * k^2 + position) blocks W IW C CI "breg" (seed, n, k, y, X, betabar, A, index)
suppressMessages(library(bayesm))
cases <- list()
add <- function(fn, args, want, tol = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-12)
set.seed(20261117)
rspd <- function(k) { M <- matrix(rnorm(k * k), k); crossprod(M) + diag(k) * 0.5 }
for (rep in 1:25) {
  k <- sample(2:5, 1); S <- rspd(k); rooti <- backsolve(chol(S), diag(k)); x <- rnorm(k); mu <- rnorm(k); nu <- sample(3:20, 1)
  add("mvn", c(k, x, mu, rooti), lndMvn(x, mu, rooti)); add("mvst", c(k, nu, 0, x, mu, rooti), lndMvst(x, nu, mu, rooti)); add("mvst", c(k, nu, 1, x, mu, rooti), lndMvst(x, nu, mu, rooti, TRUE))
  IW <- rspd(k); add("iw", c(k, nu + k, S, IW), lndIWishart(nu + k, S, IW))
  add("ic", c(nu, 1.3, 0.8 + rep / 10), lndIChisq(nu, 1.3, matrix(0.8 + rep / 10))); 
  si <- solve(S); i <- sample(k, 1); cmo <- condMom(x, mu, si, i); add("cm", c(0, k, i - 1, x, mu, si), cmo$cmean); add("cm", c(1, k, i - 1, x, mu, si), cmo$cvar)
  p <- sample(2:4, 1); kb <- sample(1:3, 1); n <- sample(5:30, 1); y <- sample(p, n, TRUE); X <- matrix(rnorm(n * p * kb), n * p, kb); beta <- rnorm(kb)
  add("mn", c(kb, p, n, beta, y, X), llmnl(beta, y, X))
  H <- mnlHess(beta, y, X); for (q in seq_len(kb * kb)) add("mh", c(kb, p, n, q - 1, beta, y, X), as.vector(H)[q])
  nc <- sample(1:4, 1); kk <- sample(2:4, 1); pv <- runif(nc); pv <- pv / sum(pv); mus <- matrix(rnorm(nc * kk), nc, kk)
  comps <- lapply(1:nc, function(i) list(mus[i, ], backsolve(chol(rspd(kk)), diag(kk)))); rts <- unlist(lapply(comps, function(cc) as.vector(cc[[2]])))
  mo <- momMix(matrix(pv, 1), list(comps)); sg <- mo$sigma; mm <- mo$mu
  for (q in 1:kk) add("mm", c(nc, kk, q - 1, 0, pv, mus, rts), mm[q]); for (q in seq_len(kk * kk)) add("mm", c(nc, kk, kk + q - 1, 0, pv, mus, rts), as.vector(sg)[q])
  xg <- matrix(rnorm(3 * kk), 3, kk); dn <- mixDen(xg, pv, comps); for (d in 1:kk) for (r in 1:3) add("md", c(nc, kk, d - 1, xg[r, d], pv, mus, rts), dn[r, d])
  cp <- sample(3:5, 1); cn <- sample(3:8, 1); cna <- sample(1:3, 1); cnd <- sample(1:3, 1); cb <- sample(1:cp, 1)
  Xa <- matrix(round(rnorm(cn * cp * cna), 3), cn, cp * cna); Xd <- matrix(round(rnorm(cn * cnd), 3), cn, cnd)
  XX <- createX(cp, cna, cnd, Xa, Xd, base = cb); for (q in seq_along(as.vector(XX))) add("cx", c(cn, cp, cna, cnd, cb, q - 1, Xa, Xd), as.vector(XX)[q])
  gg <- sample(2:4, 1); dd <- sample(1:3, 1); pvv <- runif(gg); pvv <- pvv / sum(pvv); mm2 <- matrix(rnorm(gg * dd), gg, dd)
  cps <- lapply(1:gg, function(i) list(mu = mm2[i, ], rooti = backsolve(chol(rspd(dd)), diag(dd)))); rtv <- unlist(lapply(cps, function(cc) as.vector(cc$rooti)))
  sdd <- sample(1:100000, 1); nr <- sample(5:15, 1); set.seed(sdd); rm1 <- rmixture(nr, pvv, cps)
  for (q in unique(pmin(c(1, nr, nr + 2, nr * dd), nr * dd))) add("rmx", c(sdd, nr, gg, dd, q - 1, pvv, mm2, rtv), as.vector(rm1$x)[q], 1e-9)
  for (q in 1:nr) add("rmx", c(sdd, nr, gg, dd, nr * dd + q - 1, pvv, mm2, rtv), as.numeric(rm1$z[q]), 0)
  dv <- sample(1:4, 1); Sv <- rspd(dv); rtv2 <- chol(Sv); muv <- rnorm(dv); nuv <- sample(3:15, 1); sdv <- sample(1:100000, 1); set.seed(sdv); tv <- as.vector(rmvst(nuv, muv, rtv2))
  for (q in seq_len(dv)) add("rmv", c(sdv, dv, nuv, q - 1, muv, rtv2), tv[q], 1e-10)
  nn <- sample(40:300, 1); xs <- as.numeric(arima.sim(list(ar = 0.6), nn)); mm <- sample(2:15, 1); ne <- numEff(xs, mm)
  add("ne", c(nn, mm, 0, xs), ne$stderr); add("ne", c(nn, mm, 1, xs), ne$f)
  sd <- sample(1:100000, 1); m <- sample(2:6, 1); al <- runif(m, 0.3, 4); set.seed(sd); d <- rdirichlet(al); for (j in 1:m) add("dir", c(sd, m, al, j - 1), d[j], 1e-12)
  mu1 <- rnorm(1); s1 <- runif(1, 0.5, 2); a <- mu1 - runif(1, 0.2, 2); b <- mu1 + runif(1, 0.2, 2); set.seed(sd); add("trun", c(sd, mu1, s1, a, b), rtrun(mu1, s1, a, b), 1e-9)
  nuw <- k + sample(1:8, 1); V <- rspd(k); set.seed(sd); w <- rwishart(nuw, V)
  for (b in 1:4) { M <- w[[b]]; for (q in seq_len(k * k)) add("wish", c(sd, k, nuw, V, (b - 1) * k * k + q - 1), as.vector(M)[q], 1e-9) }
  nb <- sample(10:40, 1); kb2 <- sample(1:4, 1); Xb <- matrix(rnorm(nb * kb2), nb, kb2); yb <- rnorm(nb); bb <- rnorm(kb2); Ab <- rspd(kb2)
  set.seed(sd); bd <- breg(yb, Xb, bb, Ab); for (q in 1:kb2) add("breg", c(sd, nb, kb2, yb, Xb, bb, Ab, q - 1), bd[q], 1e-9)
}
# "mreg" (seed, n, k, m, nu, Y, X, Bbar, A, V, id) id 0..k*m-1 B column-major, then Sigma; "ureg" (seed, n, k, R, nu, ssq, y, X, betabar, A, id) id 0..R*k-1 beta (R by k column-major), then sigmasq
for (rep in 1:12) {
  sd <- sample(1:100000, 1); n <- sample(15:50, 1); k <- sample(1:3, 1); m <- sample(2:3, 1); nu <- m + sample(2:8, 1)
  X <- matrix(rnorm(n * k), n, k); Y <- X %*% matrix(rnorm(k * m), k) + matrix(rnorm(n * m), n); Bbar <- matrix(rnorm(k * m), k); A <- rspd(k) * 0.1; V <- rspd(m)
  set.seed(sd); o <- rmultireg(Y, X, Bbar, A, nu, V)
  for (q in seq_len(k * m)) add("mreg", c(sd, n, k, m, nu, Y, X, Bbar, A, V, q - 1), as.vector(o$B)[q], 1e-8)
  for (q in seq_len(m * m)) add("mreg", c(sd, n, k, m, nu, Y, X, Bbar, A, V, k * m + q - 1), as.vector(o$Sigma)[q], 1e-8)
  y1 <- Y[, 1]; nr <- 4; ssq <- var(y1); nu1 <- sample(3:9, 1); bb <- rnorm(k)
  set.seed(sd); o2 <- runireg(Data = list(y = y1, X = X), Prior = list(betabar = bb, A = A, nu = nu1, ssq = ssq), Mcmc = list(R = nr, keep = 1, nprint = 0))
  bd <- as.vector(o2$betadraw); sg <- as.vector(o2$sigmasqdraw)
  for (q in seq_along(bd)) add("ureg", c(sd, n, k, nr, nu1, ssq, y1, X, bb, A, q - 1), bd[q], 1e-8)
  for (q in seq_along(sg)) add("ureg", c(sd, n, k, nr, nu1, ssq, y1, X, bb, A, nr * k + q - 1), sg[q], 1e-8)
}
# "gibbs" (seed, n, k, R, nu, ssq, sigmasq0, y, X, betabar, A, id): runiregGibbs, id as "ureg"
for (rep in 1:12) {
  sd <- sample(1:100000, 1); n <- sample(15:50, 1); k <- sample(1:3, 1); X <- matrix(rnorm(n * k), n, k); y1 <- as.vector(X %*% rnorm(k) + rnorm(n)); A <- rspd(k) * 0.1; bb <- rnorm(k)
  nr <- 5; nu1 <- sample(3:9, 1); ssq <- var(y1); s0 <- runif(1, 0.5, 3)
  set.seed(sd); o3 <- runiregGibbs(Data = list(y = y1, X = X), Prior = list(betabar = bb, A = A, nu = nu1, ssq = ssq), Mcmc = list(R = nr, keep = 1, nprint = 0, sigmasq = s0))
  bd <- as.vector(o3$betadraw); sg <- as.vector(o3$sigmasqdraw)
  for (q in seq_along(bd)) add("gibbs", c(sd, n, k, nr, nu1, ssq, s0, y1, X, bb, A, q - 1), bd[q], 1e-8)
  for (q in seq_along(sg)) add("gibbs", c(sd, n, k, nr, nu1, ssq, s0, y1, X, bb, A, nr * k + q - 1), sg[q], 1e-8)
}
emit("bayesm", "bayesm", list(cases))
