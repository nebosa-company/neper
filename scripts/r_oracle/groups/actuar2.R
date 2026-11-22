# actuar, second group: hache.barycenter and iterative Buhlmann-Straub, ruin with phase-type waiting times, adjCoef, base-law moments, Pareto II to Feller-Pareto. Layouts at each block.
suppressMessages(library(actuar))
cases <- list()
set.seed(20267001)
# cm() Buhlmann-Straub with method = "iterative": "cmi" args (I, n[I], x[N], w[N], stat 0 s2, 1 a, 2 collective mean, 3 first credibility factor)
for (rep in 1:30) {
  I <- sample(3:8, 1); ns <- sample(3:7, I, TRUE); mu <- rnorm(I, 10, 3); N <- sum(ns)
  id <- rep(1:I, ns); w <- runif(N, 1, 5); x <- mu[id] + rnorm(N, 0, 1) / sqrt(w)
  mx <- max(ns); X <- matrix(NA, I, mx); W <- X
  for (i in 1:I) { j <- which(id == i); X[i, seq_along(j)] <- x[j]; W[i, seq_along(j)] <- w[j] }
  dd <- data.frame(contract = 1:I, X, W); names(dd) <- c("contract", paste0("x", 1:mx), paste0("w", 1:mx))
  f <- tryCatch(suppressWarnings(cm(~contract, dd, ratios = paste0("x", 1:mx), weights = paste0("w", 1:mx), method = "iterative")), error = function(e) NULL)
  if (is.null(f) || !is.finite(f$iterative[1]) || f$iterative[1] <= 0) next
  vals <- c(f$iterative[2], f$iterative[1], f$means[[1]], f$cred[1])
  for (st in 0:3) cases[[length(cases) + 1]] <- case("cmi", c(I, ns, x, w, st), unname(vals[st + 1]), rel = 1e-10, abs = 1e-12)
}
# ruin() with phase-type waiting times (iterative Q): "rpp" args (n, probc[n], Tc[n n] row-major, m, probw[m], Tw[m m], c, u)
erl <- function(k, r) { T <- diag(-r, k); if (k > 1) T[cbind(1:(k - 1), 2:k)] <- r; list(prob = c(1, rep(0, k - 1)), T = T) }
phrand <- function(m) { pr <- runif(m); pr <- pr / sum(pr); T <- matrix(runif(m * m, 0, 1.5), m); diag(T) <- 0; ex <- runif(m, 0.5, 2); diag(T) <- -(rowSums(T) + ex); list(prob = pr, T = T) }
phmean <- function(p) sum(p$prob %*% solve(-p$T))
for (rep in 1:36) {
  kc <- rep %% 3; kw <- (rep %/% 3) %% 4
  pc <- switch(kc + 1, phrand(sample(1:3, 1)), erl(sample(1:3, 1), runif(1, 0.8, 2)), { r <- runif(2, 0.8, 3); list(prob = c(0.4, 0.6), T = diag(-r)) })
  pw <- switch(kw + 1, phrand(sample(1:3, 1)), erl(sample(2:3, 1), runif(1, 1, 3)), erl(sample(1:2, 1), runif(1, 0.5, 2)), { r <- runif(2, 0.5, 2); list(prob = c(0.7, 0.3), T = diag(-r)) })
  n <- length(pc$prob); m <- length(pw$prob)
  cc <- phmean(pc) / phmean(pw) * runif(1, 1.2, 2); u <- runif(1, 0, 6)
  f <- ruin(claims = "phase-type", par.claims = list(prob = pc$prob, rates = pc$T), wait = "phase-type", par.wait = list(prob = pw$prob, rates = pw$T), premium.rate = cc)
  cases[[length(cases) + 1]] <- case("rpp", c(n, pc$prob, as.vector(t(pc$T)), m, pw$prob, as.vector(t(pw$T)), cc, u), f(u), rel = 1e-9, abs = 1e-12)
}
# adjCoef(): "adj" args (mode 0 none 1 proportional 2 excess-of-loss, claim kind 0 exp 1 gamma 2 unif 3 norm, c1, c2, wait kind (0 exp 1 gamma), w1, w2, pa, pb, y (unused), upper, from, to, n, v)
# claims mgf kinds as mgf_k; the premium rate is pa (mode 0) or pa + pb y
mgfk <- list(function(x, a, b) mgfexp(x, a), function(x, a, b) mgfgamma(x, a, b), function(x, a, b) mgfunif(x, a, b), function(x, a, b) mgfnorm(x, a, b))
for (rep in 1:40) {
  ck <- rep %% 4; wk <- (rep %/% 4) %% 2
  c1 <- switch(ck + 1, runif(1, 0.8, 3), runif(1, 1, 4), runif(1, 0, 1), runif(1, 0.2, 1)); c2 <- switch(ck + 1, 0, runif(1, 1, 4), runif(1, 1.5, 3), runif(1, 0.5, 1.5))
  w1 <- if (wk == 0) runif(1, 0.5, 2) else runif(1, 1, 3); w2 <- if (wk == 0) 0 else runif(1, 1, 4)
  EX <- switch(ck + 1, 1 / c1, c1 / c2, (c1 + c2) / 2, c1); EW <- if (wk == 0) 1 / w1 else w1 / w2
  cc <- EX / EW * runif(1, 1.2, 2)
  hh <- function(r) mgfk[[ck + 1]](r, c1, c2) * mgfk[[wk + 1]](-r * cc, w1, w2)
  upper <- switch(ck + 1, c1, c2, 1, 1)
  if (ck >= 2) { upper <- 0.5; while (is.finite(hh(upper)) && hh(upper) <= 1 && upper < 200) upper <- upper * 2 }
  want <- eval(bquote(adjCoef(mgf.claim = .(mgfk[[ck + 1]])(x, .(c1), .(c2)), mgf.wait = .(mgfk[[wk + 1]])(x, .(w1), .(w2)), premium.rate = .(cc), upper.bound = .(upper))))
  cases[[length(cases) + 1]] <- case("adj", c(0, ck, c1, c2, wk, w1, w2, cc, 0, 0, upper, 0, 1, 2, 0), want, rel = 1e-9, abs = 1e-12)
}
for (rep in 1:12) {
  mode <- 1 + rep %% 2; beta <- runif(1, 0.8, 2.5); lam <- runif(1, 0.5, 2)
  th <- runif(1, 0.2, 0.8); from <- runif(1, 0.2, 0.5); to <- runif(1, 0.8, 1); nn <- 11
  pb <- if (mode == 1) lam / beta * (1 + th) else runif(1, 0, 0.2); pa <- if (mode == 1) runif(1, 0.05, 0.3) else lam / beta * (1 + th)
  v <- runif(1, from, to); assign("premfn", eval(bquote(function(y) .(pa) + .(pb) * y)), envir = globalenv())
  want <- if (mode == 1) eval(bquote(adjCoef(mgf.claim = mgfexp(x * y, .(beta)), mgf.wait = mgfexp(x, .(lam)), premium.rate = premfn, upper.bound = .(beta / to), reinsurance = "proportional", from = .(from), to = .(to), n = .(nn))))(v)
  else eval(bquote(adjCoef(mgf.claim = .(beta) * (1 - exp(-(.(beta) - x) * y)) / (.(beta) - x) + exp(-(.(beta) - x) * y), mgf.wait = mgfexp(x, .(lam)), premium.rate = premfn, upper.bound = .(3 * beta), reinsurance = "excess-of-loss", from = .(from), to = .(to), n = .(nn))))(v)
  cases[[length(cases) + 1]] <- case("adj", c(mode, 0, beta, 0, 0, lam, 0, pa, pb, 0, if (mode == 1) beta / to else 3 * beta, from, to, nn, v), want, rel = 1e-9, abs = 1e-12)
}
# base laws: "bm" args (stat 0 raw moment 1 limited expected value 2 mgf, kind 0 lnorm 1 beta 2 unif 3 norm 4 exp 5 gamma 6 weibull 7 chisq 8 invgauss (mgf), p1, p2, v, order)
bmf <- function(stat, kind, p1, p2, v, k) {
  nm <- c("lnorm", "beta", "unif", "norm", "exp", "gamma", "weibull", "chisq", "invgauss")[kind + 1]
  pr <- switch(kind + 1, list(p1, p2), list(p1, p2), list(p1, p2), list(p1, p2), list(p1), list(p1, rate = p2), list(p1, scale = p2), list(p1), list(p1, p2))
  if (stat == 0) do.call(get(paste0("m", nm)), c(list(k), pr)) else if (stat == 1) do.call(get(paste0("lev", nm)), c(list(v), pr, list(order = k))) else do.call(get(paste0("mgf", nm)), c(list(v), pr))
}
for (rep in 1:4) for (kind in 0:8) {
  p <- switch(kind + 1, c(runif(1, -0.5, 1), runif(1, 0.3, 1.2)), c(runif(1, 1, 4), runif(1, 1, 4)), { mn <- runif(1, 0.1, 1); c(mn, mn + runif(1, 1, 3)) }, c(runif(1, -1, 2), runif(1, 0.3, 2)),
              runif(1, 0.5, 3), c(runif(1, 1, 4), runif(1, 0.5, 3)), c(runif(1, 1, 4), runif(1, 0.5, 3)), runif(1, 2, 8), c(runif(1, 0.5, 3), runif(1, 0.5, 3)))
  p1 <- p[1]; p2 <- if (length(p) > 1) p[2] else 0
  ks <- switch(kind + 1, c(-1, 0.5, 1, 2, 3), c(-0.5, 1, 2.5), c(-0.5, 1, 2, 3), 0:6, c(-0.5, 1, 2.5), c(-0.5, 1, 3), c(-0.5, 1, 2), c(-0.5, 1, 2), 0)
  vs <- switch(kind + 1, c(0.5, 1.5, 4), c(0.2, 0.5, 0.9), p1 + (p2 - p1) * c(0.2, 0.6, 0.95), 0, c(0.3, 1, 3), c(0.3, 1, 3), c(0.3, 1, 3), c(0.3, 1, 3), 0)
  if (kind != 8) for (k in ks) {
    cases[[length(cases) + 1]] <- case("bm", c(0, kind, p1, p2, 0, k), bmf(0, kind, p1, p2, 0, k), rel = 1e-10, abs = 1e-12)
    if (kind != 3) for (v in vs) cases[[length(cases) + 1]] <- case("bm", c(1, kind, p1, p2, v, k), bmf(1, kind, p1, p2, v, k), rel = 1e-10, abs = 1e-12)
  }
  ts <- switch(kind + 1, 0, 0, c(0.4, 1.5), c(-1, 0.3), c(-2, -0.4, 0.3 * p1), c(-2, -0.4, 0.3 * p2), 0, c(-1, -0.2, 0.2), c(-1, -0.2, 0.1 * p2 / p1^2))
  if (kind %in% c(2, 3, 4, 5, 7, 8)) for (tt in ts) cases[[length(cases) + 1]] <- case("bm", c(2, kind, p1, p2, tt, 0), bmf(2, kind, p1, p2, tt, 0), rel = 1e-10, abs = 1e-12)
}
# mgfphtype: "mp" args (m, prob, T, t)
for (rep in 1:20) {
  p <- phrand(sample(1:4, 1)); m <- length(p$prob)
  for (tt in c(-1.5, -0.3, 0.1 * min(-diag(p$T)))) if (is.finite(mgfphtype(tt, p$prob, p$T))) cases[[length(cases) + 1]] <- case("mp", c(m, p$prob, as.vector(t(p$T)), tt), mgfphtype(tt, p$prob, p$T), rel = 1e-10, abs = 1e-12)
}
# Pareto II, III, IV and Feller-Pareto: "sh" args (kind 0 pareto2 1 pareto3 2 pareto4 3 fpareto, min, s1, s2, s3, scale, v, order, stat 0 d 1 p 2 q 3 m (v unused) 4 lev); "shr" args (seed, kind, min, s1, s2, s3, scale, n) -> sum(v * seq_along(v))
shf <- function(kind, fn, v, mn, s, sc, order = 0) {
  nm <- c("pareto2", "pareto3", "pareto4", "fpareto")[kind + 1]
  f <- get(paste0(fn, nm))
  a <- switch(kind + 1, list(mn, s[1], scale = sc), list(mn, s[1], scale = sc), list(mn, s[1], s[2], scale = sc), list(mn, s[1], s[2], s[3], scale = sc))
  if (fn == "m") do.call(f, c(list(order), a)) else if (fn == "lev") do.call(f, c(list(v), a, list(order = order))) else do.call(f, c(list(v), a))
}
for (rep in 1:5) for (kind in 0:3) for (mn in c(0, runif(1, 0.3, 2))) {
  s <- switch(kind + 1, c(runif(1, 3.2, 6), 1, 1), c(runif(1, 2.5, 6), 1, 1), c(runif(1, 2.5, 5), runif(1, 1, 2), 1), c(runif(1, 2.2, 4), runif(1, 1, 2), runif(1, 0.8, 2.5)))
  sc <- runif(1, 0.5, 3)
  ss <- if (kind == 0) s[1] else if (kind == 1) s[1] else if (kind == 2) s[1:2] else s[1:3]
  s5 <- c(0, 0, 0, 0)
  for (xx in mn + c(0.2, 1, 3, 8)) {
    ar <- function(st, ord) c(kind, mn, s, sc, xx, ord, st)
    cases[[length(cases) + 1]] <- case("sh", ar(0, 0), shf(kind, "d", xx, mn, ss, sc), rel = 1e-10, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("sh", ar(1, 0), shf(kind, "p", xx, mn, ss, sc), rel = 1e-10, abs = 1e-12)
    ords <- if (mn == 0) c(-0.4, 0.7, 1.3) else c(0, 1, 2)
    if (mn == 0) { ords <- ords[ords < s[1] * s[2] * 0.9] }
    for (o in ords) {
      lv <- tryCatch(shf(kind, "lev", xx, mn, ss, sc, o), error = function(e) NA)
      if (is.finite(lv)) cases[[length(cases) + 1]] <- case("sh", ar(4, o), lv, rel = 1e-9, abs = 1e-12)
    }
  }
  for (o in if (mn == 0) c(-0.4, 0.7, 1.3) else c(0, 1, 2)) { if (mn != 0 && o >= s[1] * s[2]) next; if (mn == 0 && (o >= s[1] * s[2] * 0.9)) next
    cases[[length(cases) + 1]] <- case("sh", c(kind, mn, s, sc, 0, o, 3), shf(kind, "m", 0, mn, ss, sc, o), rel = 1e-10, abs = 1e-12) }
  for (pp in c(0.05, 0.5, 0.93)) cases[[length(cases) + 1]] <- case("sh", c(kind, mn, s, sc, pp, 0, 2), shf(kind, "q", pp, mn, ss, sc), rel = 1e-10, abs = 1e-12)
}
for (rep in 1:40) {
  kind <- rep %% 4; sd <- sample(1:100000, 1); mn <- runif(1, 0, 2); n <- sample(3:12, 1); sc <- runif(1, 0.5, 3)
  s <- c(runif(1, 1, 4), runif(1, 0.8, 2.5), runif(1, 0.8, 2.5))
  a <- switch(kind + 1, list(mn, s[1], scale = sc), list(mn, s[1], scale = sc), list(mn, s[1], s[2], scale = sc), list(mn, s[1], s[2], s[3], scale = sc))
  set.seed(sd); v <- do.call(get(paste0("r", c("pareto2", "pareto3", "pareto4", "fpareto")[kind + 1])), c(list(n), a))
  cases[[length(cases) + 1]] <- case("shr", c(sd, kind, mn, s, sc, n), sum(v * seq_along(v)), rel = 1e-13, abs = 0)
}
# rphtype under set.seed: "rph" args (seed, n, m, prob[m], T[m m] row-major) -> sum(v * seq_along(v))
for (rep in 1:40) {
  p <- if (rep %% 3 == 0) erl(sample(2:4, 1), runif(1, 0.5, 3)) else phrand(sample(1:4, 1)); m <- length(p$prob); sd <- sample(1:100000, 1); n <- sample(3:15, 1)
  set.seed(sd); v <- rphtype(n, p$prob, p$T)
  cases[[length(cases) + 1]] <- case("rph", c(sd, n, m, p$prob, as.vector(t(p$T))), sum(v * seq_along(v)), rel = 1e-13, abs = 0)
}
# Poisson-inverse Gaussian: "pg" args (mean, dispersion, x, stat 0 d 1 p)
for (rep in 1:20) {
  mu <- runif(1, 0.3, 4); ph <- runif(1, 0.2, 3)
  for (x in c(0, 1, 2, 5, 11)) {
    cases[[length(cases) + 1]] <- case("pg", c(mu, ph, x, 0), dpoisinvgauss(x, mu, dispersion = ph), rel = 1e-10, abs = 1e-14)
    cases[[length(cases) + 1]] <- case("pg", c(mu, ph, x, 1), ppoisinvgauss(x, mu, dispersion = ph), rel = 1e-10, abs = 1e-14)
  }
}
emit("actuar2", "actuar", list(cases))
