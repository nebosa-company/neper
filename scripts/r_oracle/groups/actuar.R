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
emit("actuar", "actuar", list(cases))
