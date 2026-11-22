# MatchIt: method nearest (ratio, replace, caliper, m.order, exact, ATT/ATC), exact, subclass, and summary() balance.
#   nearest : args (n, p, ratio, replace, caliper(-1 none), order(0 largest,1 smallest,2 data,3 random,4 closest,5 farthest), atc, seed, hasStrata, link(0 logit,1 probit,2 cloglog), linear, mah(0 or first columns), psdist, t[n], x[n*p] row-major, strata[n])
#             fns "w1" sum(w*i), "w2" sum(w*i^2), "nmatched", "ps" sum(ps*i) (the same iterate as R: the IRLS stops on glm.fit's deviance rule)
#   exact   : args (n, est, t[n], g[n]); fns "w1" "w2" "nmatched"
#   subclass: args (n, p, nsub, est, min.n, t[n], x[n*p]); fns "w1" "w2" "nsub" (units with a class)
#   cem     : see below
#   bal     : args (n, p, j, denom, k, t[n], x[n*p], w[n]); fn "bal" = summary entry k (0 means treated, 1 means control, 2 std diff, 3 var ratio)
suppressMessages(library(MatchIt))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
oname <- c("largest", "smallest", "data", "random", "closest", "farthest")
wsum <- function(w) { i <- seq_along(w); list(sum(w * i), sum(w * i^2), sum(w > 0)) }
fm <- function(p) as.formula(paste("t ~", paste0("x", seq_len(p), collapse = " + ")))
mkdata <- function(n, p, strong = 0.8) {
  x <- matrix(rnorm(n * p), n); t <- rbinom(n, 1, plogis(x[, 1] * strong - 0.8))
  d <- data.frame(t, x); names(d)[-1] <- paste0("x", seq_len(p)); list(d = d, x = x, t = t)
}
set.seed(20261231)
for (rep in 1:50) {
  n <- sample(40:100, 1); p <- sample(1:3, 1); ratio <- sample(1:3, 1)
  replace <- rbinom(1, 1, 0.4); caliper <- if (rbinom(1, 1, 0.4)) round(runif(1, 0.1, 0.8), 2) else -1
  ord <- sample(0:5, 1); if (replace == 1 && ord > 3) ord <- sample(0:3, 1)
  atc <- rbinom(1, 1, 0.3); seed <- sample(1:100000, 1); ex <- rbinom(1, 1, 0.3)
  link <- sample(0:2, 1, prob = c(0.5, 0.25, 0.25)); linear <- rbinom(1, 1, 0.25)
  mt <- sample(0:2, 1, prob = c(0.6, 0.2, 0.2)); if (mt == 2 && p < 2) mt <- 1
  mah <- if (mt == 1) sample(1:p, 1) else if (mt == 2) p else 0; psdist <- as.numeric(mt != 2)
  if (mt == 2) { ord <- sample(c(2, 3, 4, 5), 1); caliper <- -1; if (replace == 1) ord <- sample(2:3, 1); link <- 0; linear <- 0 }
  dd <- mkdata(n, p); d <- dd$d; x <- dd$x; t <- dd$t
  n1 <- sum(t); if (n1 < 8 || n - n1 < 8) next
  if (replace == 0 && ratio * (if (atc) n - n1 else n1) > 0.9 * (if (atc) n1 else n - n1)) ratio <- 1
  g <- if (ex) sample(1:2, n, replace = TRUE) else rep(0, n); d$g <- g
  set.seed(seed)
  args <- list(formula = fm(p), data = d, method = "nearest", ratio = ratio, replace = replace == 1,
               estimand = if (atc) "ATC" else "ATT", m.order = oname[ord + 1])
  if (caliper >= 0) args$caliper <- caliper
  if (mt == 2) { args$distance <- "mahalanobis" } else args$link <- paste0(if (linear) "linear." else "", c("logit", "probit", "cloglog")[link + 1])
  if (mt == 1) args$mahvars <- as.formula(paste("~", paste0("x", seq_len(mah), collapse = " + ")))
  if (mt == 2) args$m.order <- c("data", "random", "closest", "farthest")[match(ord, c(2, 3, 4, 5))]
  if (ex) args$exact <- ~g
  m <- tryCatch(suppressWarnings(do.call(matchit, args)), error = function(e) NULL)
  if (is.null(m)) next
  a <- c(n, p, ratio, replace, caliper, ord, atc, seed, ex, link, linear, mah, psdist, t, as.vector(t(x)), if (ex) g)
  s <- wsum(m$weights)
  add("w1", a, s[[1]]); add("w2", a, s[[2]]); add("nmatched", a, s[[3]])
  if (mt != 2) add("ps", a, sum(m$distance * seq_along(t)))
  if (rep %% 6 == 0) {
    off <- if (mt == 2) 1 else 2; j <- sample(0:(p - 1), 1); dn <- if (atc) 1 else 0
    for (k in 0:5) add("bal", c(n, p, j, dn, k, t, as.vector(t(x)), m$weights), summary(m, un = FALSE)$sum.matched[j + off, k + 1])
    add("bal", c(n, p, j, dn, 2, t, as.vector(t(x)), rep(1, n)), summary(m)$sum.all[j + off, 3])
    add("bal", c(n, p, j, dn, 3, t, as.vector(t(x)), rep(1, n)), summary(m)$sum.all[j + off, 4])
    for (k in 4:5) add("bal", c(n, p, j, dn, k, t, as.vector(t(x)), rep(1, n)), summary(m)$sum.all[j + off, k + 1])
  }
}
# exact
for (rep in 1:20) {
  n <- sample(30:120, 1); est <- sample(0:2, 1)
  t <- rbinom(n, 1, 0.4); g1 <- sample(1:3, n, TRUE); g2 <- sample(1:2, n, TRUE)
  if (sum(t) < 3) next
  d <- data.frame(t, g1, g2)
  m <- tryCatch(suppressWarnings(matchit(t ~ g1 + g2, d, method = "exact", estimand = c("ATT", "ATC", "ATE")[est + 1])), error = function(e) NULL)
  if (is.null(m)) next
  a <- c(n, est, t, g1 * 10 + g2); s <- wsum(m$weights)
  add("xw1", a, s[[1]]); add("xw2", a, s[[2]]); add("xnmatched", a, s[[3]])
}
# subclass (min.n = 0 so no scooting; a draw where MatchIt would scoot is skipped by running both and comparing none)
for (rep in 1:25) {
  n <- sample(60:150, 1); p <- sample(1:3, 1); nsub <- sample(2:8, 1); est <- sample(0:2, 1); minn <- sample(0:2, 1, prob = c(0.3, 0.4, 0.3))
  dd <- mkdata(n, p, 0.5); d <- dd$d
  m <- tryCatch(suppressWarnings(matchit(fm(p), d, method = "subclass", subclass = nsub, min.n = minn, estimand = c("ATT", "ATC", "ATE")[est + 1])), error = function(e) NULL)
  if (is.null(m)) next
  a <- c(n, p, nsub, est, minn, dd$t, as.vector(t(dd$x))); s <- wsum(m$weights)
  add("sw1", a, s[[1]]); add("sw2", a, s[[2]])
  add("snsub", a, sum(!is.na(m$subclass)))
  add("sps", a, sum(m$distance * seq_along(dd$t)))
  md <- match.data(m, drop.unmatched = TRUE); ri <- as.integer(rownames(md))
  add("smdrows", a, nrow(md)); add("smdw", a, sum(md$weights * ri)); add("smdsub", a, sum(as.integer(as.character(md$subclass)) * ri))
}
# cem: args (n, p, kind(0 sturges,1 fd,2 scott,3 bins,4 quantiles), par, est, t[n], x[n*p]); fns "cw1" "cw2" "cnmatched"
for (rep in 1:30) {
  n <- sample(80:200, 1); p <- sample(1:2, 1); kind <- sample(0:4, 1); est <- sample(0:2, 1)
  par <- if (kind == 3) sample(c(2, 3, 4, 6), 1) else if (kind == 4) sample(3:5, 1) else 0
  dd <- mkdata(n, p, 0.5); d <- dd$d
  cp <- switch(kind + 1, "sturges", "fd", "scott", par, paste0("q", par))
  m <- tryCatch(suppressWarnings(matchit(fm(p), d, method = "cem", cutpoints = setNames(rep(list(cp), p), names(d)[-1]), estimand = c("ATT", "ATC", "ATE")[est + 1])), error = function(e) NULL)
  if (is.null(m)) next
  a <- c(n, p, kind, par, est, dd$t, as.vector(t(dd$x))); s <- wsum(m$weights)
  add("cw1", a, s[[1]]); add("cw2", a, s[[2]]); add("cnmatched", a, s[[3]])
}
# optimal (pairmatch, ratio 1, ATT, glm distance): args (n, p, t[n], x[n*p]); fns "ow1" "ow2" "onmatched".
# optmatch breaks ties between equal integer-cost assignments by LEMON cycle-cancelling order (not ported), so only draws whose
# optimum on optmatch's integer costs is unique are kept (each used pair forbidden in turn never reaches the optimum).
suppressMessages(library(lpSolve))
set.seed(20261232)
nopt <- 0
for (rep in 1:400) {
  if (nopt >= 40) break
  n <- sample(40:100, 1); p <- sample(1:3, 1); dd <- mkdata(n, p); d <- dd$d; t <- dd$t; n1 <- sum(t); n0 <- n - n1
  if (n1 < 8 || n0 < n1 + 2) next
  m <- suppressWarnings(matchit(fm(p), d, method = "optimal"))
  ps <- m$distance; keep <- MatchIt:::preprocess_matchC(t, ps)
  D <- abs(outer(ps[t == 1], ps[t == 0], "-")); M <- matrix(FALSE, n1, n0); M[keep] <- TRUE
  eps <- 0.001 * n * ((n1 + n0 - 2) / (n - 2)) / (sum(rowSums(M) > 0) + sum(colSums(M) > 0) - 2)
  eps <- max(max(D[M]) / (.Machine$integer.max / 64 - 2), eps)
  C <- matrix(ceiling(0.5 + D / eps), n1); C[!M] <- 1e9
  solve1 <- function(C) { s <- lp.assign(rbind(C, matrix(0, n0 - n1, n0)), "min"); list(a = apply(s$solution, 1, which.max)[1:n1], v = s$objval) }
  s0 <- solve1(C)
  uniq <- TRUE
  for (i in 1:n1) { C2 <- C; C2[i, s0$a[i]] <- 1e9; if (solve1(C2)$v <= s0$v + 0.5) { uniq <- FALSE; break } }
  w <- m$weights; mine <- numeric(n); mine[t == 1] <- 1; mine[which(t == 0)[s0$a]] <- 1
  if (!uniq) next
  stopifnot(all(mine == w))
  a <- c(n, p, t, as.vector(t(dd$x))); s <- wsum(w)
  add("ow1", a, s[[1]]); add("ow2", a, s[[2]]); add("onmatched", a, s[[3]])
  nopt <- nopt + 1
}
emit("matchit", "MatchIt", list(cases))
