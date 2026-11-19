# actuar: d, p, q, moments and limited moments of the transformed beta family, the transformed gamma family, its inverse and pareto1.
#   args: (family, kind, s1, s2, s3, scale, v, k) fn "d" "p" "q" "m" "lev"; v is x, the probability (q) or the limit (lev); k the order (m, lev)
#   family 0 transformed beta, kind 0 burr 1 invburr 2 pareto 3 invpareto 4 llogis 5 paralogis 6 invparalogis 7 genpareto 8 trbeta
#   family 1 trgamma (kind 0); family 2 inverse transformed gamma, kind 0 invtrgamma 1 invgamma 2 invweibull 3 invexp; family 3 pareto1 (s1 shape, scale the min)
suppressMessages(library(actuar))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-12)
set.seed(20261129)
names0 <- c("burr", "invburr", "pareto", "invpareto", "llogis", "paralogis", "invparalogis", "genpareto", "trbeta")
call_fn <- function(pre, nm, v, s, sc, ...) do.call(get(paste0(pre, nm)), c(list(v), as.list(s), list(scale = sc), list(...)))
for (rep in 1:6) {
  for (kind in 0:8) {
    nm <- names0[kind + 1]
    s <- switch(kind + 1, c(2.5, 1.8), c(1.7, 2.2), 3.2, 2.4, 2.8, 2.1, 1.9, c(2.6, 1.4), c(2.3, 1.6, 1.3)); sc <- runif(1, 0.5, 3)
    s <- s * runif(length(s), 0.9, 1.2)
    # shape parameters as (a, g, t) for the validity ranges of the orders
    ag <- switch(kind + 1, c(s[1], s[2], 1), c(1, s[2], s[1]), c(s[1], 1, 1), c(1, 1, s[1]), c(1, s[1], 1), c(s[1], s[1], 1), c(1, s[1], s[1]), c(s[1], 1, s[2]), s[1:3])
    kmax <- ag[1] * ag[2] * 0.8; kmin <- -ag[3] * ag[2] * 0.8
    for (xx in c(0.3, 1, 2.5, 7)) {
      a0 <- function(v, k) c(0, kind, s, rep(0, 3 - length(s)), sc, v, k)
      add("d", a0(xx, 0), call_fn("d", nm, xx, s, sc)); add("p", a0(xx, 0), call_fn("p", nm, xx, s, sc))
      for (k in c(kmin * 0.5, kmax * 0.5, kmax)) {
        add("m", a0(xx, k), do.call(get(paste0("m", nm)), c(list(k), as.list(s), list(scale = sc))))
        add("lev", a0(xx, k), do.call(get(paste0("lev", nm)), c(list(xx), as.list(s), list(scale = sc, order = k))), rel = if (kind == 3) 1e-5 else 1e-9)  # levinvpareto integrates numerically at eps^0.25
      }
    }
    for (pp in c(0.05, 0.4, 0.9)) add("q", c(0, kind, s, rep(0, 3 - length(s)), sc, pp, 0), call_fn("q", nm, pp, s, sc))
  }
  s <- c(runif(1, 0.8, 3), runif(1, 0.6, 2.5)); sc <- runif(1, 0.5, 3)
  for (xx in c(0.3, 1, 2.5, 7)) {
    a0 <- function(v, k) c(1, 0, s, 0, sc, v, k)
    add("d", a0(xx, 0), dtrgamma(xx, s[1], s[2], scale = sc)); add("p", a0(xx, 0), ptrgamma(xx, s[1], s[2], scale = sc))
    for (k in c(-0.5 * s[1] * s[2], 0.7, 2)) { add("m", a0(xx, k), mtrgamma(k, s[1], s[2], scale = sc)); add("lev", a0(xx, k), levtrgamma(xx, s[1], s[2], scale = sc, order = k)) }
  }
  for (pp in c(0.05, 0.4, 0.9)) add("q", c(1, 0, s, 0, sc, pp, 0), qtrgamma(pp, s[1], s[2], scale = sc))
  for (kind in 0:3) {
    s <- c(runif(1, 2.2, 5), runif(1, 1.1, 3)); sc <- runif(1, 0.5, 3)
    f <- switch(kind + 1, list("invtrgamma", c(s[1], s[2]), c(s[1], s[2])), list("invgamma", s[1], c(s[1], 1)), list("invweibull", s[2], c(1, s[2])), list("invexp", numeric(0), c(1, 1)))
    ia <- f[[3]]; for (xx in c(0.3, 1, 2.5, 7)) {
      a0 <- function(v, k) c(2, kind, f[[2]], rep(0, 2 - length(f[[2]])), 0, sc, v, k)
      add("d", a0(xx, 0), call_fn("d", f[[1]], xx, f[[2]], sc)); add("p", a0(xx, 0), call_fn("p", f[[1]], xx, f[[2]], sc))
      for (k in c(-1, 0.4, 0.75 * ia[1] * ia[2])) {
        add("m", a0(xx, k), do.call(get(paste0("m", f[[1]])), c(list(k), as.list(f[[2]]), list(scale = sc))))
        add("lev", a0(xx, k), do.call(get(paste0("lev", f[[1]])), c(list(xx), as.list(f[[2]]), list(scale = sc, order = k))))
      }
    }
    for (pp in c(0.05, 0.4, 0.9)) add("q", c(2, kind, f[[2]], rep(0, 2 - length(f[[2]])), 0, sc, pp, 0), call_fn("q", f[[1]], pp, f[[2]], sc))
  }
  al <- runif(1, 1.5, 4); mn <- runif(1, 0.5, 2)
  for (xx in c(0.3, 1, 2.5, 7)) {
    a0 <- function(v, k) c(3, 0, al, 0, 0, mn, v, k)
    add("d", a0(xx, 0), dpareto1(xx, al, mn)); add("p", a0(xx, 0), ppareto1(xx, al, mn))
    for (k in c(-1, 0.5, al * 0.6)) { add("m", a0(xx, k), mpareto1(k, al, mn)); if (xx >= mn) add("lev", a0(xx, k), levpareto1(xx, al, mn, order = k)) }
  }
  for (pp in c(0.05, 0.4, 0.9)) add("q", c(3, 0, al, 0, 0, mn, pp, 0), qpareto1(pp, al, mn))
}
# aggregateDist("recursive") (Panjer): "pj" args (kind, p1, p2, m, fx[m], nn): the cdf at nn and the pmf-weighted sum of the first nn + 1 cdf values
suppressMessages(library(actuar))
set.seed(20262500)
for (rep in 1:40) {
  kd <- rep %% 4; m <- sample(3:8, 1); fx <- c(runif(1, 0, 0.5), runif(m - 1)); fx <- fx / sum(fx); nn <- sample(8:25, 1)
  F <- switch(kd + 1, { l <- runif(1, 0.5, 4); p1 <- l; p2 <- 0; aggregateDist("recursive", model.freq = "poisson", model.sev = fx, lambda = l, x.scale = 1) },
    { s <- sample(2:10, 1); pr <- runif(1, 0.1, 0.7); p1 <- s; p2 <- pr; aggregateDist("recursive", model.freq = "binomial", model.sev = fx, size = s, prob = pr, x.scale = 1) },
    { s <- runif(1, 0.5, 5); pr <- runif(1, 0.2, 0.8); p1 <- s; p2 <- pr; aggregateDist("recursive", model.freq = "negative binomial", model.sev = fx, size = s, prob = pr, x.scale = 1) },
    { pr <- runif(1, 0.2, 0.8); p1 <- pr; p2 <- 0; aggregateDist("recursive", model.freq = "geometric", model.sev = fx, prob = pr, x.scale = 1) })
  v <- F(0:nn)
  if (any(!is.finite(v)) || max(knots(F)) < nn) next
  cases[[length(cases) + 1]] <- case("pj", c(kd, p1, p2, m, fx, nn, 0), v[nn + 1], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("pj", c(kd, p1, p2, m, fx, nn, 1), sum(v * seq_along(v)), rel = 1e-9, abs = 1e-12)
}
# discretize(cdf, method upper / lower / rounding): "dz" args (method 0 upper 1 lower 2 rounding, n, ff[2 n + 1] the cdf at from + k h / 2); the answer is the length and, in a second case, the position-weighted sum of the values
for (rep in 1:40) {
  md <- rep %% 3; n <- sample(4:20, 1); h <- runif(1, 0.3, 2); from <- runif(1, 0, 2); to <- from + n * h
  cdfs <- c("lnorm", "gamma", "weibull")[sample(1:3, 1)]
  Fn <- switch(cdfs, lnorm = function(x) plnorm(x, 0.3, 0.8), gamma = function(x) pgamma(x, 2.2, 0.5), weibull = function(x) pweibull(x, 1.7, 3))
  ff <- Fn(from + (0:(2 * n)) * h / 2)
  d <- discretize(Fn(x), method = c("upper", "lower", "rounding")[md + 1], from = from, to = to, step = h)
  cases[[length(cases) + 1]] <- case("dz", c(md, n, ff, 0), length(d), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("dz", c(md, n, ff, 1), sum(d * seq_along(d)), rel = 1e-9, abs = 1e-13)
}
# discretize(method = "unbiased"): "du" args (n, h, F(from), F(to), lev at from + k h [n + 1], stat); the answer is the first mass or the position-weighted sum
for (rep in 1:40) {
  n <- sample(4:20, 1); h <- runif(1, 0.3, 2); from <- runif(1, 0, 2); to <- from + n * h
  a <- runif(1, 1.5, 4); s <- runif(1, 0.3, 1.5)
  d <- discretize(pgamma(x, a, s), method = "unbiased", lev = levgamma(x, a, s), from = from, to = to, step = h)
  ex <- levgamma(from + (0:n) * h, a, s)
  cs <- c(n, h, pgamma(from, a, s), pgamma(to, a, s), ex)
  cases[[length(cases) + 1]] <- case("du", c(cs, 0), d[1], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("du", c(cs, 1), sum(d * seq_along(d)), rel = 1e-9, abs = 1e-12)
}
# cm(): Buhlmann-Straub: "cm" args (I, n[I], x[N], w[N], stat); the answer is s2, a, k, the collective mean or the first contract's credibility factor
for (rep in 1:30) {
  I <- sample(3:8, 1); ns <- sample(3:7, I, TRUE); mu <- rnorm(I, 10, 3); N <- sum(ns)
  id <- rep(1:I, ns); w <- runif(N, 1, 5); x <- mu[id] + rnorm(N, 0, 1) / sqrt(w)
  mx <- max(ns); X <- matrix(NA, I, mx); W <- X
  for (i in 1:I) { j <- which(id == i); X[i, seq_along(j)] <- x[j]; W[i, seq_along(j)] <- w[j] }
  dd <- data.frame(contract = 1:I, X, W); names(dd) <- c("contract", paste0("x", 1:mx), paste0("w", 1:mx))
  f <- tryCatch(suppressWarnings(cm(~contract, dd, ratios = paste0("x", 1:mx), weights = paste0("w", 1:mx))), error = function(e) NULL)
  if (is.null(f) || !is.finite(f$unbiased[1]) || f$unbiased[1] <= 0) next
  vals <- c(f$unbiased[2], f$unbiased[1], f$unbiased[2] / f$unbiased[1], f$means[[1]], f$cred[1])
  for (st in 0:4) cases[[length(cases) + 1]] <- case("cm", c(I, ns, x, w, st), unname(vals[st + 1]), rel = 1e-9, abs = 1e-12)
}
# ruin(): exponential claims and waiting times: "rx" args (beta, lambda, c, u)
for (rep in 1:40) {
  b <- runif(1, 0.5, 3); cc <- runif(1, 0.5, 2); l <- runif(1, 0.1, 0.95) * b * cc; u <- runif(1, 0, 8)
  f <- ruin(claims = "exponential", par.claims = list(rate = b), wait = "exponential", par.wait = list(rate = l), premium.rate = cc)
  cases[[length(cases) + 1]] <- case("rx", c(b, l, cc, u), f(u), rel = 1e-9, abs = 1e-13)
}
# dphtype / pphtype: "ph" args (m, prob[m], T[m m] row-major, x, stat 0 density 1 survival)
for (rep in 1:40) {
  m <- sample(1:4, 1); pr <- runif(m); pr <- pr / sum(pr) * runif(1, 0.8, 1)
  T <- matrix(runif(m * m, 0, 1.5), m); diag(T) <- 0; ex <- runif(m, 0.2, 2); diag(T) <- -(rowSums(T) + ex); x <- runif(1, 0.05, 4)
  cases[[length(cases) + 1]] <- case("ph", c(m, pr, as.vector(t(T)), x, 0), dphtype(x, pr, T), rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("ph", c(m, pr, as.vector(t(T)), x, 1), pphtype(x, pr, T, lower.tail = FALSE), rel = 1e-8, abs = 1e-12)
}
# mphtype: "pm" args (m, prob[m], T[m m], k)
for (rep in 1:30) {
  m <- sample(1:4, 1); pr <- runif(m); pr <- pr / sum(pr) * runif(1, 0.8, 1)
  T <- matrix(runif(m * m, 0, 1.5), m); diag(T) <- 0; ex <- runif(m, 0.2, 2); diag(T) <- -(rowSums(T) + ex); k <- sample(1:4, 1)
  cases[[length(cases) + 1]] <- case("pm", c(m, pr, as.vector(t(T)), k), mphtype(k, pr, T), rel = 1e-9, abs = 1e-12)
}
# loggamma and Gumbel: "lf" args (kind 0 loggamma 1 gumbel, p1, p2, x, stat 0 d 1 p 2 q 3 moment (loggamma)), q takes the probability as x
for (rep in 1:30) {
  a <- runif(1, 0.8, 4); r <- runif(1, 2.5, 6); xx <- exp(runif(1, 0.05, 1.5)); pp <- runif(1, 0.05, 0.95); k <- runif(1, 0.1, 0.9) * r
  cases[[length(cases) + 1]] <- case("lf", c(0, a, r, xx, 0), dlgamma(xx, a, r), rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("lf", c(0, a, r, xx, 1), plgamma(xx, a, r), rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("lf", c(0, a, r, pp, 2), qlgamma(pp, a, r), rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("lf", c(0, a, r, k, 3), mlgamma(k, a, r), rel = 1e-9, abs = 1e-13)
  al <- rnorm(1, 0, 2); sc <- runif(1, 0.4, 3); x2 <- al + rnorm(1) * sc
  cases[[length(cases) + 1]] <- case("lf", c(1, al, sc, x2, 0), dgumbel(x2, al, sc), rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("lf", c(1, al, sc, x2, 1), pgumbel(x2, al, sc), rel = 1e-9, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("lf", c(1, al, sc, pp, 2), qgumbel(pp, al, sc), rel = 1e-9, abs = 1e-12)
}
# zero-truncated and zero-modified Poisson and negative binomial: "zc" args (kind 0 Poisson 1 nbinom, a, b, p0, x, stat 0 zt d 1 zt p 2 zm d 3 zm p)
for (rep in 1:40) {
  kd <- rep %% 2; a <- if (kd == 0) runif(1, 0.3, 6) else runif(1, 0.5, 5); b <- runif(1, 0.2, 0.9); p0 <- runif(1, 0.05, 0.8); xx <- sample(0:12, 1)
  zt <- if (kd == 0) c(dztpois(xx, a), pztpois(xx, a)) else c(dztnbinom(xx, a, b), pztnbinom(xx, a, b))
  zm <- if (kd == 0) c(dzmpois(xx, a, p0), pzmpois(xx, a, p0)) else c(dzmnbinom(xx, a, b, p0), pzmnbinom(xx, a, b, p0))
  for (st in 0:3) cases[[length(cases) + 1]] <- case("zc", c(kd, a, b, p0, xx, st), c(zt, zm)[st + 1], rel = 1e-9, abs = 1e-13)
}
# inverse Gaussian and logarithmic: "ig" args (kind 0 invgauss 1 logarithmic, p1, p2, x, stat 0 d 1 p)
for (rep in 1:40) {
  mu <- runif(1, 0.5, 4); s <- runif(1, 0.4, 5); xx <- runif(1, 0.1, 6); q <- runif(1, 0.1, 0.95); k <- sample(1:15, 1)
  for (st in 0:1) {
    cases[[length(cases) + 1]] <- case("ig", c(0, mu, s, xx, st), if (st == 0) dinvgauss(xx, mu, s) else pinvgauss(xx, mu, s), rel = 1e-8, abs = 1e-13)
    cases[[length(cases) + 1]] <- case("ig", c(1, q, 0, k, st), if (st == 0) dlogarithmic(k, q) else plogarithmic(k, q), rel = 1e-8, abs = 1e-13)
  }
}
# generalised beta: "gb" args (a, b, t, scale, x, stat 0 d 1 p 2 q 3 m (x is the order))
for (rep in 1:40) {
  a <- runif(1, 0.6, 4); b <- runif(1, 0.6, 4); tt <- runif(1, 0.5, 3); sc <- runif(1, 0.5, 5); xx <- sc * runif(1, 0.05, 0.95); pp <- runif(1, 0.05, 0.95); k <- runif(1, -0.4 * a * tt, 3)
  vals <- c(dgenbeta(xx, a, b, tt, scale = sc), pgenbeta(xx, a, b, tt, scale = sc), qgenbeta(pp, a, b, tt, scale = sc), mgenbeta(k, a, b, tt, scale = sc))
  args <- c(xx, xx, pp, k)
  for (st in 0:3) cases[[length(cases) + 1]] <- case("gb", c(a, b, tt, sc, args[st + 1], st), vals[st + 1], rel = 1e-8, abs = 1e-13)
}
# loggamma limited moments and inverse Gaussian moments: "lm" args (kind 0 levlgamma 1 minvgauss, p1, p2, x or limit, order)
for (rep in 1:40) {
  a <- runif(1, 0.8, 4); r <- runif(1, 3, 7); xx <- exp(runif(1, -0.3, 1.5)); k <- runif(1, 0.1, 0.9) * r
  cases[[length(cases) + 1]] <- case("lm", c(0, a, r, xx, k), levlgamma(xx, a, r, order = k), rel = 1e-8, abs = 1e-13)
  mu <- runif(1, 0.5, 4); s <- runif(1, 0.4, 5); kk <- sample(1:3, 1)
  cases[[length(cases) + 1]] <- case("lm", c(1, mu, s, 0, kk), minvgauss(kk, mu, s), rel = 1e-9, abs = 1e-13)
}
# zero-truncated and zero-modified binomial and geometric: "zc" with kind 2 and 3
for (rep in 1:40) {
  kd <- 2 + rep %% 2; a <- sample(2:12, 1); b <- runif(1, 0.2, 0.9); p0 <- runif(1, 0.05, 0.8); xx <- sample(0:12, 1)
  zt <- if (kd == 2) c(dztbinom(xx, a, b), pztbinom(xx, a, b)) else c(dztgeom(xx, b), pztgeom(xx, b))
  zm <- if (kd == 2) c(dzmbinom(xx, a, b, p0), pzmbinom(xx, a, b, p0)) else c(dzmgeom(xx, b, p0), pzmgeom(xx, b, p0))
  for (st in 0:3) cases[[length(cases) + 1]] <- case("zc", c(kd, a, b, p0, xx, st), c(zt, zm)[st + 1], rel = 1e-9, abs = 1e-13)
}
# generalised beta limited moments and Gumbel moments: "gl" args (kind 0 levgenbeta 1 mgumbel, p1, p2, p3, scale, x, order)
for (rep in 1:40) {
  a <- runif(1, 0.6, 4); b <- runif(1, 0.6, 4); tt <- runif(1, 0.5, 3); sc <- runif(1, 0.5, 5); xx <- sc * runif(1, 0.05, 1.2); k <- runif(1, 0.1, 3)
  cases[[length(cases) + 1]] <- case("gl", c(0, a, b, tt, sc, xx, k), levgenbeta(xx, a, b, tt, scale = sc, order = k), rel = 1e-8, abs = 1e-13)
  al <- rnorm(1, 0, 2); s2 <- runif(1, 0.4, 3); kk <- sample(1:2, 1)
  cases[[length(cases) + 1]] <- case("gl", c(1, al, s2, 0, 0, 0, kk), mgumbel(kk, al, s2), rel = 1e-8, abs = 1e-11)
}
# zero-truncated and zero-modified count quantiles: "zq" args (kind 0 pois 1 nbinom 2 binom 3 geom, a, b, p0, p, stat 0 zt 1 zm)
for (rep in 1:60) {
  kd <- rep %% 4; a <- if (kd == 2) sample(2:12, 1) else runif(1, 0.5, 5); b <- runif(1, 0.2, 0.9); p0 <- runif(1, 0.05, 0.8); pp <- runif(1, 0.02, 0.98)
  zt <- switch(kd + 1, qztpois(pp, a), qztnbinom(pp, a, b), qztbinom(pp, a, b), qztgeom(pp, b))
  zm <- switch(kd + 1, qzmpois(pp, a, p0), qzmnbinom(pp, a, b, p0), qzmbinom(pp, a, b, p0), qzmgeom(pp, b, p0))
  cases[[length(cases) + 1]] <- case("zq", c(kd, a, b, p0, pp, 0), zt, rel = 0, abs = 0)
  if (is.finite(zm)) cases[[length(cases) + 1]] <- case("zq", c(kd, a, b, p0, pp, 1), zm, rel = 0, abs = 0)
}
# inverse Gaussian quantile: "iq" args (mean, shape, p)
for (rep in 1:40) {
  mu <- runif(1, 0.5, 4); s <- runif(1, 0.4, 5); pp <- runif(1, 0.02, 0.98)
  cases[[length(cases) + 1]] <- case("iq", c(mu, s, pp), qinvgauss(pp, mu, s), rel = 1e-7, abs = 1e-10)
}
# random generators under set.seed: "rg" args (seed, kind 0 rburr 1 rtrgamma 2 rinvgamma 3 rgumbel 4 rlgamma 5 rpareto1 6 rinvtrgamma 7 rinvweibull 8 rinvexp 9 rgenbeta 10 rtrbeta 11 rgenpareto, p1, p2, p3, sc, n); the answer is the position-weighted sum of n draws
for (rep in 1:120) {
  kd <- rep %% 12; sd <- sample(1:100000, 1); n <- sample(3:12, 1); p1 <- runif(1, 1, 4); p2 <- runif(1, 1, 3); p3 <- runif(1, 0.7, 2.5); sc <- runif(1, 0.5, 3)
  set.seed(sd)
  v <- switch(kd + 1, rburr(n, p1, p2, scale = sc), rtrgamma(n, p1, p2, scale = sc), rinvgamma(n, p1, scale = sc), rgumbel(n, p1, p2), rlgamma(n, p1, p2 + 2), rpareto1(n, p1, p2), rinvtrgamma(n, p1, p2, scale = sc), rinvweibull(n, p1, scale = sc), rinvexp(n, scale = sc), rgenbeta(n, p1, p2, p3, scale = sc), rtrbeta(n, p1, p2, p3, scale = sc), rgenpareto(n, p1, p2, scale = sc))
  if (kd == 4) p2 <- p2 + 2
  cases[[length(cases) + 1]] <- case("rg", c(sd, kd, p1, p2, p3, sc, n), sum(v * seq_along(v)), rel = 1e-9, abs = 1e-12)
}
# transformed beta generators under set.seed: "rt" args (seed, kind 0 burr 1 invburr 2 pareto 3 invpareto 4 llogis 5 paralogis 6 invparalogis, s1, s2, sc, n)
for (rep in 1:70) {
  kd <- rep %% 7; sd <- sample(1:100000, 1); n <- sample(3:10, 1); s1 <- runif(1, 1, 4); s2 <- runif(1, 1, 3); sc <- runif(1, 0.5, 3)
  set.seed(sd)
  v <- switch(kd + 1, rburr(n, s1, s2, scale = sc), rinvburr(n, s1, s2, scale = sc), rpareto(n, s1, scale = sc), rinvpareto(n, s1, scale = sc), rllogis(n, s1, scale = sc), rparalogis(n, s1, scale = sc), rinvparalogis(n, s1, scale = sc))
  cases[[length(cases) + 1]] <- case("rt", c(sd, kd, s1, s2, sc, n), sum(v * seq_along(v)), rel = 1e-9, abs = 1e-12)
}
# zero-truncated and logarithmic generators under set.seed: "rc" args (seed, kind 0 ztpois 1 ztnbinom 2 ztbinom 4 logarithmic, a, b, n); rztgeom is not an inversion and is not compared
for (rep in 1:50) {
  kd <- c(0, 1, 2, 4)[rep %% 4 + 1]; sd <- sample(1:100000, 1); n <- sample(3:15, 1); a <- if (kd == 2) sample(2:12, 1) else runif(1, 0.5, 5); b <- runif(1, 0.2, 0.9)
  set.seed(sd)
  v <- switch(kd + 1, rztpois(n, a), rztnbinom(n, a, b), rztbinom(n, a, b), rztgeom(n, b), rlogarithmic(n, b))
  cases[[length(cases) + 1]] <- case("rc", c(sd, kd, a, b, n), sum(v * seq_along(v)), rel = 0, abs = 0)
}
# ruin() with phase-type claims and exponential waiting: "rp" args (m, prob[m], T[m m], lambda, c, u)
for (rep in 1:30) {
  m <- sample(1:4, 1); pr <- runif(m); pr <- pr / sum(pr)
  T <- matrix(runif(m * m, 0, 1.5), m); diag(T) <- 0; ex <- runif(m, 0.5, 2); diag(T) <- -(rowSums(T) + ex)
  mean.claim <- sum(pr %*% solve(-T)); cc <- runif(1, 1.2, 2.5); lam <- runif(1, 0.2, 0.8) * cc / mean.claim; u <- runif(1, 0, 6)
  f <- ruin(claims = "phase-type", par.claims = list(prob = pr, rates = T), wait = "exponential", par.wait = list(rate = lam), premium.rate = cc)
  cases[[length(cases) + 1]] <- case("rp", c(m, pr, as.vector(t(T)), lam, cc, u), f(u), rel = 1e-7, abs = 1e-12)
}
# aggregateDist("convolution"): "cv" args (m, fx[m], np, pn[np], nn, stat 0 cdf at nn 1 position-weighted sum of the cdf)
for (rep in 1:40) {
  m <- sample(3:7, 1); fx <- c(runif(1, 0, 0.4), runif(m - 1)); fx <- fx / sum(fx); np <- sample(3:8, 1); pn <- runif(np); pn <- pn / sum(pn); nn <- sample(6:20, 1)
  F <- aggregateDist("convolution", model.freq = pn, model.sev = fx, x.scale = 1)
  v <- F(0:nn)
  if (any(!is.finite(v))) next
  cases[[length(cases) + 1]] <- case("cv", c(m, fx, np, pn, nn, 0), v[nn + 1], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("cv", c(m, fx, np, pn, nn, 1), sum(v * seq_along(v)), rel = 1e-9, abs = 1e-12)
}
# aggregateDist("normal") and ("npower"): "an" (mean, variance, x), "ap" (mean, variance, skewness, x)
for (rep in 1:40) {
  mu <- runif(1, 1, 20); v <- runif(1, 0.5, 30); sk <- runif(1, 0.3, 3); xx <- mu + rnorm(1) * sqrt(v) * 1.5
  Fn <- aggregateDist("normal", moments = c(mu, v)); cases[[length(cases) + 1]] <- case("an", c(mu, v, xx), Fn(xx), rel = 1e-10, abs = 1e-13)
  Fp <- suppressWarnings(aggregateDist("npower", moments = c(mu, v, sk))); r <- suppressWarnings(Fp(xx))
  if (is.finite(r)) cases[[length(cases) + 1]] <- case("ap", c(mu, v, sk, xx), r, rel = 1e-10, abs = 1e-13)
}
# grouped data: "gg" args (r, cj[r + 1], nj[r], stat 0 ogive 1 emm 2 elev, argument)
for (rep in 1:40) {
  r <- sample(3:9, 1); cj <- c(0, cumsum(runif(r, 5, 60))); nj <- sample(3:80, r, TRUE)
  gd <- grouped.data(Group = cj, Frequency = nj); xx <- runif(1, -5, max(cj) * 1.1); kk <- sample(1:4, 1)
  cases[[length(cases) + 1]] <- case("gg", c(r, cj, nj, 0, xx), ogive(gd)(xx), rel = 1e-10, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("gg", c(r, cj, nj, 1, kk), emm(gd, kk), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("gg", c(r, cj, nj, 2, abs(xx)), elev(gd)(abs(xx)), rel = 1e-10, abs = 1e-12)
}
emit("actuar", "actuar", list(cases))
