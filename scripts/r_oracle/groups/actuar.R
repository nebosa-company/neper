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
