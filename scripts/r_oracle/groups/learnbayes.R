# LearnBayes: pbetap, discint, mnormt.onesided, normal.select, beta.select and bfexch.
#   args by fn: "pbetap" (a, b, n, s)   "discint" (prob, k, which, p...) -> eprob (which 0) or the size of the set (which 1), p the probabilities in value order
#   "bf" (m0, pm, psd, xbar, n, s)   "nsel" (p1, x1, p2, x2, which)   "bsel" (p1, x1, p2, x2, which)   "bfexch" (theta, K, n, y..., nn...)
suppressMessages(library(LearnBayes))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-10)
set.seed(20261209)
for (rep in 1:20) {
  a <- runif(1, 0.5, 6); b <- runif(1, 0.5, 6); n <- sample(5:30, 1); s <- sample(0:n, 1)
  add("pbetap", c(a, b, n, s), pbetap(c(a, b), n, s))
  k <- sample(4:12, 1); p <- runif(k); p <- p / sum(p); pr <- sample(c(0.5, 0.8, 0.9, 0.95), 1)
  d <- discint(cbind(seq_len(k), p), pr)
  add("discint", c(pr, k, 0, p), d$prob); add("discint", c(pr, k, 1, p), length(d$set))
  m0 <- runif(1, 0, 2); pm <- runif(1, -1, 2); psd <- runif(1, 0.5, 2); xbar <- runif(1, 0, 3); nn <- sample(5:50, 1); s0 <- runif(1, 0.5, 3)
  add("bf", c(m0, pm, psd, xbar, nn, s0), mnormt.onesided(m0, c(pm, psd), c(xbar, nn, s0))$BF)
  q1 <- list(p = 0.5, x = runif(1, 0.2, 0.4)); q2 <- list(p = runif(1, 0.8, 0.95), x = runif(1, 0.5, 0.7))
  ns <- normal.select(list(p = 0.5, x = 100 * q1$x), list(p = q2$p, x = 100 * q2$x))
  add("nsel", c(0.5, 100 * q1$x, q2$p, 100 * q2$x, 0), ns$mu); add("nsel", c(0.5, 100 * q1$x, q2$p, 100 * q2$x, 1), ns$sigma)
  bs <- beta.select(q1, q2)
  add("bsel", c(q1$p, q1$x, q2$p, q2$x, 0), bs[1], 1e-6); add("bsel", c(q1$p, q1$x, q2$p, q2$x, 1), bs[2], 1e-6)
  g <- sample(4:9, 1); yy <- sample(0:20, g, replace = TRUE); nnn <- yy + sample(1:20, g, replace = TRUE)
  th <- runif(1, -2, 2); K <- runif(1, 0.5, 20)
  add("bfexch", c(th, K, g, yy, nnn), bfexch(th, list(data = cbind(yy, nnn), K = K)))
}
# rwmetrop "rwm" and indepmetrop "ind": (seed, kind 0 normals 1 banana, pb, m, scale, index (-1 acceptance rate), par[4], [mu[pb]], var[pb^2] column-major, start[pb])
lp <- function(th, par) { th <- as.vector(th); if (par[5] == 0) -0.5 * sum(((th - par[c(1, 3)]) / par[c(2, 4)])^2) else { u <- th[2] - par[1] * th[1]^2; -0.5 * (th[1]^2 / 4 + u^2) } }
for (rep in 1:20) {
  kd <- rep %% 2; pb <- 2; m <- sample(15:40, 1); vv <- matrix(c(1, 0.3, 0.3, 1.5), 2) * runif(1, 0.5, 2); sc <- runif(1, 0.5, 2); st <- rnorm(2); sd <- sample(1:100000, 1)
  par <- if (kd == 0) c(0.2, 1.3, -0.4, 0.8) else c(0.3, 0, 0, 0); pp <- c(par[1:4], 0); if (kd == 1) pp[5] <- 1
  parv <- if (kd == 0) c(0.2, 1.3, -0.4, 0.8) else c(0.3, 0, 0, 0)
  set.seed(sd); r1 <- rwmetrop(lp, list(var = vv, scale = sc), st, m, c(parv, kd)); 
  for (idx in c(-1, 0:(m * pb - 1))) add("rwm", c(sd, kd, pb, m, sc, idx, parv, as.vector(vv), st), if (idx < 0) r1$accept else as.vector(r1$par)[idx + 1], 1e-9)
  mu <- rnorm(2); set.seed(sd); r2 <- indepmetrop(lp, list(mu = mu, var = vv), st, m, c(parv, kd))
  for (idx in c(-1, 0:(m * pb - 1))) add("ind", c(sd, kd, pb, m, sc, idx, parv, mu, as.vector(vv), st), if (idx < 0) r2$accept else as.vector(r2$par)[idx + 1], 1e-9)
}
# rigamma "rigamma" (seed, a, b, index); rmnorm "rmnorm" (seed, n, d, index, mean, varcov); pdisc "pdisc" (n, s, f, index, p, prior); pbetat "pbetat" (p0, prob, a, b, s, f, 0 bf / 1 post)
for (rep in 1:20) {
  sd <- sample(1:100000, 1); a_ <- runif(1, 1, 6); b_ <- runif(1, 0.5, 4); set.seed(sd); v <- rigamma(5, a_, b_); for (j in 1:5) add("rigamma", c(sd, a_, b_, j - 1), v[j], 1e-10)
  d <- sample(2:3, 1); nn <- sample(2:5, 1); mu <- rnorm(d); vc <- crossprod(matrix(rnorm(d * d), d)) + diag(d); set.seed(sd); y <- rmnorm(nn, mu, vc)
  for (j in seq_len(nn * d)) add("rmnorm", c(sd, nn, d, j - 1, mu, as.vector(vc)), as.vector(y)[j], 1e-10)
  np <- sample(5:15, 1); pp <- c(0, sort(runif(np - 2)), 1); pr <- runif(np); pr <- pr / sum(pr); ss <- sample(0:9, 1); ff <- sample(0:9, 1)
  po <- pdisc(pp, pr, c(ss, ff)); for (j in seq_len(np)) add("pdisc", c(np, ss, ff, j - 1, pp, pr), po[j], 1e-10)
  p0 <- runif(1, 0.1, 0.9); pb <- runif(1, 0.2, 0.8); ab <- runif(2, 0.5, 5); bt <- pbetat(p0, pb, ab, c(ss, ff)); add("pbetat", c(p0, pb, ab, ss, ff, 0), bt$bf, 1e-10); add("pbetat", c(p0, pb, ab, ss, ff, 1), bt$post, 1e-10)
}
# mixtures: "mixb" binomial.beta.mix, "mixn" normal.normal.mix, "mixp" poisson.gamma.mix: (n, which 0 probs 1 par1 2 par2, index, d1, d2, probs[n], par1[n], par2[n], [y, t for mixp])
for (rep in 1:20) {
  nn <- sample(2:4, 1); pr <- runif(nn); pr <- pr / sum(pr)
  ba <- cbind(runif(nn, 0.5, 6), runif(nn, 0.5, 6)); ss <- sample(0:12, 1); ff <- sample(0:12, 1); r1 <- binomial.beta.mix(pr, ba, c(ss, ff))
  for (j in 1:nn) { add("mixb", c(nn, 0, j - 1, ss, ff, pr, ba[, 1], ba[, 2]), r1$probs[j], 1e-10); add("mixb", c(nn, 1, j - 1, ss, ff, pr, ba[, 1], ba[, 2]), r1$betapar[j, 1], 1e-10); add("mixb", c(nn, 2, j - 1, ss, ff, pr, ba[, 1], ba[, 2]), r1$betapar[j, 2], 1e-10) }
  np <- cbind(rnorm(nn), runif(nn, 0.5, 3)); yy <- rnorm(1); s2 <- runif(1, 0.5, 2); r2 <- normal.normal.mix(pr, np, c(yy, s2))
  for (j in 1:nn) { add("mixn", c(nn, 0, j - 1, yy, s2, pr, np[, 1], np[, 2]), r2$probs[j], 1e-10); add("mixn", c(nn, 1, j - 1, yy, s2, pr, np[, 1], np[, 2]), r2$normalpar[j, 1], 1e-10); add("mixn", c(nn, 2, j - 1, yy, s2, pr, np[, 1], np[, 2]), r2$normalpar[j, 2], 1e-10) }
  gp <- cbind(runif(nn, 1, 6), runif(nn, 0.5, 4)); dn <- sample(2:5, 1); y <- rpois(dn, 3); t <- runif(dn, 0.5, 2); r3 <- poisson.gamma.mix(pr, gp, list(y = y, t = t))
  for (j in 1:nn) { add("mixp", c(nn, 0, j - 1, dn, 0, pr, gp[, 1], gp[, 2], y, t), r3$probs[j], 1e-10); add("mixp", c(nn, 1, j - 1, dn, 0, pr, gp[, 1], gp[, 2], y, t), r3$gammapar[j, 1], 1e-10); add("mixp", c(nn, 2, j - 1, dn, 0, pr, gp[, 1], gp[, 2], y, t), r3$gammapar[j, 2], 1e-10) }
}
# the book log posteriors "lpost": (which, a, b, m, y[m], v2[m], z0) which 0 normchi2post 1 betabinexch0 2 betabinexch 3 poissgamexch 4 lbinorm (a, b the point; then m1, m2, v11, v12, v22 from slot 4) 5 cauchyerrorpost
for (rep in 1:15) {
  m <- sample(4:12, 1); yy <- rnorm(m, 1, 2); nn <- sample(10:40, m, TRUE); yb <- sapply(nn, function(q) sample(0:q, 1)); ee <- round(runif(m, 1, 20), 2); yp <- rpois(m, 3 * ee / 10); z0 <- runif(1, 0.5, 3)
  th <- c(rnorm(1), runif(1, 0.5, 2)); add("lpost", c(0, th, m, yy, rep(0, m)), normchi2post(th, yy))
  eta <- runif(1, 0.1, 0.9); K <- runif(1, 0.5, 20); add("lpost", c(1, eta, K, m, yb, nn), betabinexch0(c(eta, K), cbind(yb, nn)))
  t1 <- rnorm(1); t2 <- rnorm(1); add("lpost", c(2, t1, t2, m, yb, nn), betabinexch(c(t1, t2), cbind(yb, nn)))
  add("lpost", c(3, t1, t2, m, yp, ee, z0), poissgamexch(c(t1, t2), list(data = cbind(ee, yp), z0 = z0)))
  mm <- rnorm(2); vv <- crossprod(matrix(rnorm(4), 2)) + diag(2) * 0.5; pt <- rnorm(2)
  add("lpost", c(4, pt, 2, mm, vv[1, 1], vv[1, 2], vv[2, 2], 0), lbinorm(pt, list(m = mm, v = vv)))
  cl <- rnorm(1, 0, 0.5); add("lpost", c(5, th[1], cl, m, yy, rep(0, m)), cauchyerrorpost(c(th[1], cl), yy))
}
# more book posteriors "lpost2": (which, m, p, theta..., data...) 0 logisticpost 1 weibullregpost 2 groupeddatapost 3 logctablepost 4 transplantpost
for (rep in 1:15) {
  m <- sample(5:15, 1); xx <- round(rnorm(m), 2); nn <- sample(10:40, m, TRUE); yb <- sapply(nn, function(q) sample(0:q, 1)); b <- rnorm(2, 0, 0.5)
  add("lpost2", c(0, m, 0, b, xx, nn, yb), logisticpost(b, cbind(xx, nn, yb)))
  pp <- sample(1:3, 1); X <- matrix(round(rnorm(m * pp), 2), m, pp); tt <- round(rexp(m, 0.5) + 0.05, 3); cc <- rbinom(m, 1, 0.7); th <- c(rnorm(1, 0, 0.3), rnorm(1), rnorm(pp, 0, 0.5))
  add("lpost2", c(1, m, pp, th, tt, cc, X), weibullregpost(th, cbind(tt, cc, X)))
  lo <- sort(round(rnorm(m), 1)); hi <- lo + round(runif(m, 0.2, 1), 1); ff <- sample(1:30, m, TRUE); g <- c(rnorm(1), rnorm(1, 0, 0.4))
  add("lpost2", c(2, m, 0, g, ff, lo, hi), groupeddatapost(g, list(int.lo = lo, int.hi = hi, f = ff)))
  s1 <- sample(1:30, 1); f1 <- sample(1:30, 1); s2 <- sample(1:30, 1); f2 <- sample(1:30, 1); g2 <- rnorm(2)
  add("lpost2", c(3, 4, 0, g2, s1, f1, s2, f2), logctablepost(g2, c(s1, f1, s2, f2)))
  xs <- round(rexp(m, 0.2) + 0.1, 2); tr <- rbinom(m, 1, 0.5); ys <- round(rexp(m, 0.3) + 0.1, 2); dd <- rbinom(m, 1, 0.5); g3 <- rnorm(3, 0, 0.5)
  add("lpost2", c(4, m, 0, g3, xs, tr, ys, dd), transplantpost(g3, cbind(xs, tr, ys, dd)))
}
# rejectsampling "rej" and impsampling "imp2" on the logistic posterior with a t proposal
for (rep in 1:10) {
  m <- sample(6:14, 1); xx <- round(rnorm(m), 2); nn <- sample(10:40, m, TRUE); yb <- sapply(nn, function(q) sample(0:q, 1)); dat <- cbind(xx, nn, yb)
  fit <- optim(c(0, 0), logisticpost, control = list(fnscale = -1), hessian = TRUE, data = dat); mu <- fit$par; vv <- -solve(fit$hessian) * 1.5
  tp <- list(m = mu, var = vv, df = 4); sd <- sample(1:100000, 1); ns <- 200
  dmax <- max(sapply(1:50, function(i) { th <- mu + rnorm(2, 0, 0.3); logisticpost(th, dat) - dmt(th, mu, vv, 4, log = TRUE) })) + 0.5
  set.seed(sd); rs <- rejectsampling(logisticpost, tp, dmax, ns, dat)
  add("rej", c(sd, 0, m, ns, 4, dmax, mu, vv, xx, nn, yb), if (is.matrix(rs)) nrow(rs) else length(rs))
  if (is.matrix(rs) && nrow(rs) > 0) add("rej", c(sd, 1, m, ns, 4, dmax, mu, vv, xx, nn, yb), sum(rs[, 1]))
  lp <- laplace(logisticpost, c(0, 0), dat); for (q in 1:4) add("lap", c(q - 1, m, lp$mode, xx, nn, yb), as.vector(lp$var)[q], 1e-7); add("lap", c(4, m, lp$mode, xx, nn, yb), lp$int, 1e-8)
  st <- rnorm(2, 0, 0.5); lq <- laplace(logisticpost, st, dat)
  for (q in 1:2) add("lapf", c(q - 1, m, st, xx, nn, yb), lq$mode[q], 1e-9); for (q in 1:4) add("lapf", c(1 + q, m, st, xx, nn, yb), as.vector(lq$var)[q], 1e-9); add("lapf", c(6, m, st, xx, nn, yb), lq$int, 1e-9)
  mv <- sample(3:8, 1); mus <- rnorm(mv); s2s <- runif(mv, 0.5, 3); ss <- sample(5:20, 1)
  for (kd in 0:2) { fnn <- list(min, max, mean)[[kd + 1]]; set.seed(sd); np <- normpostpred(list(mu = mus, sigma2 = s2s), ss, fnn)
    for (q in c(1, mv)) add("npp", c(sd, mv, ss, kd, q - 1, mus, s2s), np[q], 1e-10) }
  m0 <- rnorm(1); pr0 <- runif(1, 0.2, 0.8); tt <- runif(1, 0.3, 2); xb <- m0 + rnorm(1, 0, 0.5); nn2 <- sample(5:40, 1); hh <- runif(1, 0.5, 2); mt2 <- mnormt.twosided(m0, pr0, tt, c(xb, nn2, hh))
  add("mt2", c(m0, pr0, tt, xb, nn2, hh, 0), mt2$bf); add("mt2", c(m0, pr0, tt, xb, nn2, hh, 1), mt2$post)
  gg <- sample(3:7, 1); pp <- sort(runif(gg)); pw <- runif(gg); pw <- pw / sum(pw); nb2 <- sample(5:20, 1); sv <- sample(0:nb2, 1)
  add("pdp", c(nb2, sv, gg, pp, pw), pdiscp(pp, pw, nb2, sv))
  ti <- sample(2:3, 1); tj <- sample(2:3, 1); yt <- matrix(sample(1:15, ti * tj, TRUE), ti, tj); mm3 <- 50; kk3 <- sample(c(1, 2, 5), 1)
  set.seed(sd); bfi <- bfindep(yt, kk3, mm3); add("bfi", c(sd, ti, tj, kk3, mm3, 0, yt), bfi$bf, 1e-9); add("bfi", c(sd, ti, tj, kk3, mm3, 1, yt), bfi$nse, 1e-9)
  set.seed(sd); gb <- gibbs(logisticpost, c(0, 0), 60, c(0.5, 0.4), dat); for (q in c(1, 30, 60, 61, 90, 120)) add("gib", c(sd, q - 1, m, 60, 0.5, 0.4, 0, 0, xx, nn, yb), as.vector(gb$par)[q], 1e-10)
  add("gib", c(sd, 120, m, 60, 0.5, 0.4, 0, 0, xx, nn, yb), gb$accept[1], 1e-10); add("gib", c(sd, 121, m, 60, 0.5, 0.4, 0, 0, xx, nn, yb), gb$accept[2], 1e-10)
  set.seed(sd); sr <- sir(logisticpost, tp, 150, dat); for (q in c(1, 40, 150, 151, 190, 300)) add("sir", c(sd, q - 1, m, 150, 4, 0, mu, vv, xx, nn, yb), as.vector(sr)[q], 1e-10)
  set.seed(sd); im <- impsampling(logisticpost, tp, function(th) th[2], ns, dat)
  add("imp2", c(sd, 0, m, ns, 4, 1, mu, vv, xx, nn, yb), im$est); add("imp2", c(sd, 1, m, ns, 4, 1, mu, vv, xx, nn, yb), im$se)
}
# normpostsim "nps" and blinreg "blr"
for (rep in 1:10) {
  n <- sample(8:40, 1); yy <- rnorm(n, 2, 1.5); sd <- sample(1:100000, 1); m <- 25; hp <- rep %% 2
  pr <- if (hp) list(sigma2 = c(runif(1, 1, 4), runif(1, 1, 4)), mu = c(rnorm(1), runif(1, 0.5, 3))) else NULL
  set.seed(sd); ns <- normpostsim(yy, pr, m)
  for (q in c(1, 5, 25)) { add("nps", c(sd, hp, m, n, if (hp) pr$sigma2 else c(0, 0), if (hp) pr$mu else c(0, 0), 0, q - 1, yy), ns$mu[q], 1e-9)
    add("nps", c(sd, hp, m, n, if (hp) pr$sigma2 else c(0, 0), if (hp) pr$mu else c(0, 0), 1, q - 1, yy), ns$sigma2[q], 1e-9) }
  p <- sample(1:3, 1); X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 2), n, p - 1)); y2 <- round(X %*% rnorm(p) + rnorm(n), 3); b0 <- rnorm(p); c0 <- runif(1, 0.5, 5)
  set.seed(sd); bl <- blinreg(as.vector(y2), X, m, if (hp) list(c0 = c0, b0 = b0) else NULL)
  for (q in c(1, 12, 25)) { add("blr", c(sd, hp, m, n, p, c0, 0, q - 1, b0, y2, X), bl$sigma[q], 1e-8)
    for (j in 1:p) add("blr", c(sd, hp, m, n, p, c0, 1, (j - 1) * m + q - 1, b0, y2, X), bl$beta[q, j], 1e-8) }
}
# hiergibbs "hg"
for (rep in 1:8) {
  NN <- sample(6:14, 1); nn <- sample(200:600, NN, TRUE); x1 <- round(runif(NN, 20, 40)); x2 <- round(runif(NN, 20, 40)); yy <- round(0.55 + 0.018 * x1 + 0.033 * x2 + rnorm(NN, 0, 0.1), 3)
  yy <- yy / 2; sd <- sample(1:100000, 1); m <- 20; set.seed(sd); hgr <- hiergibbs(cbind(yy, nn, x1, x2), m)
  for (q in c(1, 7, 20, 21, 40, 60)) add("hg", c(sd, m, NN, 0, q - 1, yy, nn, x1, x2), as.vector(hgr$beta)[q], 1e-8)
  for (q in c(1, 25, NN * m)) add("hg", c(sd, m, NN, 1, q - 1, yy, nn, x1, x2), as.vector(hgr$mu)[q], 1e-8)
  for (q in c(1, 10, 20)) add("hg", c(sd, m, NN, 2, q - 1, yy, nn, x1, x2), hgr$var[q], 1e-8)
}
# ordergibbs "og", bradley.terry.post "btp", howardprior "how"
for (rep in 1:6) {
  yy <- sample(2:6, 40, TRUE) / 2 + round(rnorm(40, 0, 0.3), 2); nn <- sample(20:300, 40, TRUE); sd <- sample(1:100000, 1); m <- 15
  set.seed(sd); og <- ordergibbs(cbind(yy, nn), m); for (q in c(1, 8, 40, 41, 100, 300, 600)) add("og", c(sd, m, q - 1, yy, nn), as.vector(og)[q], 1e-8)
}
for (rep in 1:15) {
  nt <- sample(3:6, 1); ng <- sample(4:12, 1); ii <- sample(nt, ng, TRUE); jj <- sapply(ii, function(i) sample(setdiff(1:nt, i), 1)); wi <- sample(0:8, ng, TRUE); wj <- sample(0:8, ng, TRUE); th <- c(rnorm(nt), rnorm(1, 0, 0.5))
  add("btp", c(nt, ng, th, ii, jj, wi, wj), bradley.terry.post(th, cbind(ii, jj, wi, wj)))
  pp <- runif(2, 0.1, 0.9); par <- c(runif(4, 0.5, 3), runif(1, 0.5, 2)); add("how", c(pp, par), howardprior(pp, par))
}
emit("learnbayes", "LearnBayes", list(cases))
