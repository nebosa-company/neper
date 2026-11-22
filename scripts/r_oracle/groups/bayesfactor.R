# BayesFactor: log BF10 (the bf slot) for the JZS tests. Neper runs the package's own integrate() calls, so the values agree to
# rounding: rel 1e-9 on log BF, or abs 1e-10 on log BF (that is 1e-10 relative on BF itself) when log BF is near 0.
#   "tstat"  (t, n1, n2, rscale, lo, hi, compl)                        ttest.tstat; n2 = 0 one-sample; lo/hi the null interval
#   "ttest"  (kind, mu, rscale, lo, hi, compl, nx, ny, x..., y...)     ttestBF on data; kind 0 one-sample, 1 paired, 2 two-sample
#   "oneway" (F, N, J, rscale)                                         oneWayAOV.Fstat
#   "linreg" (N, p, R2, rscale)                                        linearReg.R2stat
#   "corr"   (rscale, lo, hi, compl, n, y..., x...)                    correlationBF; lo = -1, hi = 1 for no interval
#   "prop"   (p, rscale, lo, hi, compl, m, y..., N...)                 proportionBF; lo = 0, hi = 1 for no interval
#   "cont"   (kind, a, I, J, cells column-major)                       contingencyTableBF; kind 0 poisson, 1 jointMulti,
#                                                                      2 indepMulti rows, 3 indepMulti cols, 4 hypergeom
#   "reg"    (rscale, n, m, mask[m], y..., X column-major)             regressionBF, one case per model
#   "factor" (rscale, nlev, n, y..., level codes 0..)                  anovaBF on one fixed factor (two levels or balanced)
suppressMessages(library(BayesFactor))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = rel / 10)
# An interval more than 4 posterior sds from delta-hat puts the whole integral in the far tail of the noncentral t, where R's
# dt(ncp) is a difference of two pnt() values near 0 or 1 accumulated in long double and rounded to double; R's own value then
# carries ~1e-8 relative noise, so those cases (only) allow rel 1e-7.
far <- function(t, n, iv) { d <- t / sqrt(n); s <- 1 / sqrt(n); d < iv[1] - 4 * s || d > iv[2] + 4 * s }
ints <- list(c(-Inf, Inf), c(0, Inf), c(-Inf, 0), c(-0.2, 0.2), c(0.1, 0.8))
set.seed(20261223)
for (rep in 1:40) {
  n1 <- sample(6:60, 1); n2 <- if (rep %% 2 == 0) sample(6:60, 1) else 0; t <- round(rnorm(1) * 2.5, 3); rs <- c(0.5, 0.7071068, 1, 1.4142136)[rep %% 4 + 1]
  iv <- ints[[rep %% 5 + 1]]
  for (cp in c(FALSE, TRUE)) {
    if (cp && all(is.infinite(iv))) next
    ni <- if (all(is.infinite(iv))) NULL else iv
    r <- if (n2 == 0) ttest.tstat(t = t, n1 = n1, nullInterval = ni, rscale = rs, complement = cp) else ttest.tstat(t = t, n1 = n1, n2 = n2, nullInterval = ni, rscale = rs, complement = cp)
    ne <- if (n2 == 0) n1 else n1 * n2 / (n1 + n2)
    add("tstat", c(t, n1, n2, rs, iv, cp), as.numeric(r$bf), if (!cp && far(t, ne, iv)) 1e-7 else 1e-9)
  }
}
for (rep in 1:24) {
  kind <- rep %% 3; nx <- sample(5:40, 1); ny <- if (kind == 1) nx else sample(5:40, 1)
  rs <- c(0.5, 0.7071068, 1)[rep %% 3 + 1]; mu <- if (kind == 2) 0 else round(runif(1, -0.3, 0.3), 2); iv <- ints[[rep %% 5 + 1]]
  x <- round(rnorm(nx, 0.3, 1), 4); y <- round(rnorm(ny, 0, 1.2), 4)
  ni <- if (all(is.infinite(iv))) NULL else iv
  b <- if (kind == 0) ttestBF(x, mu = mu, nullInterval = ni, rscale = rs) else if (kind == 1) ttestBF(x, y, mu = mu, paired = TRUE, nullInterval = ni, rscale = rs) else ttestBF(x, y, nullInterval = ni, rscale = rs)
  w <- b@bayesFactor$bf
  yy <- if (kind == 0) numeric(0) else y
  for (k in seq_along(w)) add("ttest", c(kind, mu, rs, iv, k - 1, nx, length(yy), x, yy), w[k])
}
for (rep in 1:30) {
  f <- round(rexp(1) * 3, 3); n <- sample(3:30, 1); j <- sample(2:6, 1); rs <- c(0.5, 0.7071068, 1)[rep %% 3 + 1]
  add("oneway", c(f, n, j, rs), oneWayAOV.Fstat(f, n, j, rscale = rs)$bf)
}
for (rep in 1:30) {
  n <- sample(10:200, 1); p <- sample(1:6, 1); r2 <- round(runif(1, 0, 0.9), 4); rs <- c(0.3535534, 0.5, 0.7071068)[rep %% 3 + 1]
  add("linreg", c(n, p, r2, rs), linearReg.R2stat(n, p, r2, rscale = rs)$bf)
}
for (rep in 1:30) {
  n <- sample(5:60, 1); k <- c(1 / 3, 1 / sqrt(3), 1, 1 / sqrt(27))[rep %% 4 + 1]; x <- round(rnorm(n), 4); y <- round(0.4 * x + rnorm(n), 4)
  iv <- list(c(-1, 1), c(0, 1), c(-1, 0), c(-0.1, 0.1), c(0.2, 0.6))[[rep %% 5 + 1]]
  ni <- if (iv[1] == -1 && iv[2] == 1) NULL else iv
  w <- correlationBF(y, x, rscale = k, nullInterval = ni)@bayesFactor$bf
  for (j in seq_along(w)) add("corr", c(k, iv, j - 1, n, y, x), w[j])
}
for (rep in 1:30) {
  m <- sample(1:3, 1); nn <- sample(5:80, m, replace = TRUE); p <- round(runif(1, 0.1, 0.9), 2); y <- rbinom(m, nn, runif(1, 0.1, 0.9))
  rs <- c(0.5, sqrt(2) / 2, 1)[rep %% 3 + 1]; iv <- list(c(0, 1), c(0, 0.5), c(0.5, 1), c(0.3, 0.6), c(0.05, 0.2))[[rep %% 5 + 1]]
  ni <- if (iv[1] == 0 && iv[2] == 1) NULL else iv
  w <- proportionBF(y, nn, p, rscale = rs, nullInterval = ni)@bayesFactor$bf
  for (j in seq_along(w)) add("prop", c(p, rs, iv, j - 1, m, y, nn), w[j])
}
types <- c("poisson", "jointMulti", "indepMulti", "indepMulti", "hypergeom")
for (rep in 1:40) {
  kind <- rep %% 5; ni <- if (kind == 4) 2 else sample(2:4, 1); nj <- if (kind == 4) 2 else sample(2:4, 1); conc <- c(1, 1.5, 3)[rep %% 3 + 1]
  tb <- matrix(rpois(ni * nj, runif(1, 2, 25)), ni, nj)
  b <- if (kind == 2) contingencyTableBF(tb, sampleType = "indepMulti", fixedMargin = "rows", priorConcentration = conc) else
       if (kind == 3) contingencyTableBF(tb, sampleType = "indepMulti", fixedMargin = "cols", priorConcentration = conc) else
       contingencyTableBF(tb, sampleType = types[kind + 1], priorConcentration = conc)
  add("cont", c(kind, conc, ni, nj, tb), b@bayesFactor$bf)
}
for (rep in 1:6) {
  n <- sample(12:60, 1); X <- matrix(round(rnorm(n * 3), 4), n, 3); y <- round(X %*% c(0.5, 0, -0.3) + rnorm(n), 4)
  d <- data.frame(y = as.vector(y), x1 = X[, 1], x2 = X[, 2], x3 = X[, 3]); rs <- c(0.3535534, 0.5, 0.7071068)[rep %% 3 + 1]
  b <- regressionBF(y ~ x1 + x2 + x3, data = d, rscaleCont = rs, progress = FALSE)
  for (j in seq_len(nrow(b@bayesFactor))) {
    terms <- strsplit(rownames(b@bayesFactor)[j], " + ", fixed = TRUE)[[1]]
    add("reg", c(rs, n, 3, c("x1", "x2", "x3") %in% terms, d$y, X), b@bayesFactor$bf[j])
  }
}
for (rep in 1:16) {
  nlev <- if (rep %% 2 == 0) 2 else sample(3:5, 1); per <- sample(3:12, 1)
  g <- factor(rep(seq_len(nlev), each = per)); if (nlev == 2 && rep %% 4 == 0) g <- factor(c(rep(1, per), rep(2, per + 3)))
  y <- round(rnorm(length(g), as.numeric(g) * 0.3), 4); rs <- c(0.5, sqrt(2) / 2, 1)[rep %% 3 + 1]
  b <- anovaBF(y ~ g, data = data.frame(y = y, g = g), rscaleFixed = rs, progress = FALSE)
  add("factor", c(rs, nlev, length(y), y, as.integer(g) - 1), b@bayesFactor$bf)
}
chain_cases <- function(fn, head, ch) {
  ch <- as.matrix(ch); it <- nrow(ch)
  for (k in seq_len(ncol(ch))) {
    add(fn, c(head, 0, k - 1), sum(ch[, k]))
    for (row in c(1, it)) add(fn, c(head, row, k - 1), ch[row, k])
  }
}
for (rep in 1:12) {
  two <- rep %% 2 == 0; nx <- sample(6:30, 1); ny <- sample(6:30, 1); x <- round(rnorm(nx, 0.4), 4); y <- round(rnorm(ny), 4)
  rs <- c(0.5, sqrt(2) / 2, 1)[rep %% 3 + 1]; iv <- list(NULL, c(0, Inf), c(-0.3, 0.3), c(-Inf, 0.1), c(0.1, 0.9), c(-0.5, -0.1))[[(rep - 1) %/% 2 + 1]]
  idx <- if (!is.null(iv) && rep %% 4 < 2) 2 else 1; it <- 300; seed <- sample(1e6, 1)
  b <- if (two) ttestBF(x, y, nullInterval = iv, rscale = rs) else ttestBF(x, nullInterval = iv, rscale = rs)
  set.seed(seed)
  ch <- posterior(b, index = idx, iterations = it, progress = FALSE)
  on <- !is.null(iv); lim <- if (on) iv else c(0, 0)
  chain_cases(if (two) "post2" else "post1", c(seed, it, rs, on, idx == 2, lim, nx, if (two) ny else 0, x, if (two) y), ch)
}
for (rep in 1:8) {
  kind <- rep %% 4; ni <- sample(2:3, 1); nj <- sample(2:3, 1); conc <- c(1, 2)[rep %% 2 + 1]
  tb <- matrix(rpois(ni * nj, runif(1, 3, 20)), ni, nj); it <- 200; seed <- sample(1e6, 1)
  b <- if (kind == 2) contingencyTableBF(tb, sampleType = "indepMulti", fixedMargin = "rows", priorConcentration = conc) else
       if (kind == 3) contingencyTableBF(tb, sampleType = "indepMulti", fixedMargin = "cols", priorConcentration = conc) else
       contingencyTableBF(tb, sampleType = types[kind + 1], priorConcentration = conc)
  set.seed(seed)
  chain_cases("cpost", c(seed, it, kind, conc, ni, nj, tb), posterior(b, iterations = it, progress = FALSE))
}
for (rep in 1:8) {
  m <- sample(1:2, 1); nn <- sample(10:60, m, replace = TRUE); p <- round(runif(1, 0.2, 0.8), 2); y <- rbinom(m, nn, runif(1, 0.2, 0.8))
  rs <- c(0.5, 1)[rep %% 2 + 1]; iv <- list(NULL, c(0, 0.5), c(0.3, 0.7), c(0.5, 1))[[(rep - 1) %/% 2 + 1]]
  idx <- if (!is.null(iv) && rep %% 2 == 0) 2 else 1; it <- 300; seed <- sample(1e6, 1)
  b <- proportionBF(y, nn, p, rscale = rs, nullInterval = iv)
  set.seed(seed)
  ch <- suppressMessages(posterior(b, index = idx, iterations = it, progress = FALSE))
  on <- !is.null(iv); lim <- if (on) iv else c(0, 0)
  chain_cases("ppost", c(seed, it, p, rs, on, idx == 2, lim, m, y, nn), ch)
}
for (rep in 1:8) {
  n <- sample(8:50, 1); x <- round(rnorm(n), 4); y <- round(0.3 * x + rnorm(n), 4); rs <- c(1 / 3, 1)[rep %% 2 + 1]
  iv <- list(NULL, c(0, 1), c(-0.2, 0.2), c(-1, 0.1))[[(rep - 1) %/% 2 + 1]]
  idx <- if (!is.null(iv) && rep %% 2 == 0) 2 else 1; it <- 300; seed <- sample(1e6, 1)
  b <- correlationBF(y, x, rscale = rs, nullInterval = iv)
  set.seed(seed)
  ch <- suppressMessages(posterior(b, index = idx, iterations = it, progress = FALSE))
  on <- !is.null(iv); lim <- if (on) iv else c(0, 0)
  chain_cases("rpost", c(seed, it, rs, on, idx == 2, lim, n, y, x), ch)
}
for (rep in 1:9) {
  n <- sample(15:50, 1); it <- 200; seed <- sample(1e6, 1); kind <- rep %% 3
  if (kind == 0) {
    x1 <- round(rnorm(n), 4); x2 <- round(rnorm(n), 4); y <- round(0.5 * x1 + rnorm(n), 4); rs <- c(0.3535534, 0.5, 1)[rep %% 3 + 1]
    d <- data.frame(y = y, x1 = x1, x2 = x2)
    b <- lmBF(y ~ x1 + x2, data = d, rscaleCont = rs)
    set.seed(seed); ch <- posterior(b, iterations = it, progress = FALSE)
    X <- cbind(1, x1 - mean(x1), x2 - mean(x2)); gm <- c(0, 0); rsv <- rs; ic <- 2
  } else {
    X0 <- matrix(round(rnorm(n * 4), 3), n, 4); y <- round(X0 %*% c(0.4, 0, 0.3, 0) + rnorm(n), 4)
    gm <- c(0, 0, 1, 1); rsv <- c(0.5, 0.7071068); ic <- 0
    if (kind == 2) { X0[, 1] <- round(rnorm(n), 4); gm <- c(0, 1, 1, 2); rsv <- c(0.3535534, 0.5, 1); ic <- 1 }
    set.seed(seed)
    ch <- nWayAOV(as.vector(y), X0, gMap = gm, rscale = rsv, iterations = it, posterior = TRUE, progress = FALSE,
                  continuous = if (ic) c(TRUE, FALSE, FALSE, FALSE) else FALSE)
    X <- cbind(1, X0)
  }
  if (kind == 0) chain_cases("lpost", c(seed, it, n, 2, rs, y, x1, x2), ch) else
    chain_cases("gibbs", c(seed, it, n, ncol(X), length(rsv), ic, gm, rsv, y, X), ch)
}
for (rep in 1:12) {
  n <- sample(15:50, 1); it <- c(500, 2000)[rep %% 2 + 1]; seed <- sample(1e6, 1)
  X <- matrix(round(rnorm(n * 4), 3), n, 4); y <- round(X %*% c(0.4, 0, 0.3, 0) + rnorm(n), 4)
  gm <- list(c(0, 0, 1, 1), c(0, 1, 1, 2), c(0, 1, 0, 1))[[rep %% 3 + 1]]; rsv <- c(0.5, 0.7071068, 1)[seq_len(max(gm) + 1)]
  ic <- if (rep %% 4 == 0) 1 else 0
  if (ic) { gm <- c(0, 1, 1, 2); rsv <- c(0.3535534, 0.5, 1) }
  set.seed(seed)
  r <- nWayAOV(as.vector(y), X, gMap = gm, rscale = rsv, iterations = it, method = "simple", progress = FALSE,
               continuous = if (ic) c(TRUE, FALSE, FALSE, FALSE) else FALSE)
  add("nway", c(seed, it, n, 4, length(rsv), ic, gm, rsv, y, X), r$bf)
}
# Linear models with factors. H = (n, nv, kind[nv], nlev[nv], y[n], X column-major) with the predictors in formula order,
# kind 0 fixed, 1 random, 2 continuous, factors coded 0..; a term is a bit mask over the predictors. All under method "auto".
#   "anova"  (seed, it, rsF, rsR, row, H)                              anovaBF(y ~ fixed factors crossed [+ random]) row
#   "lmbf"   (seed, it, rsF, rsR, rsC, nt, terms, H)                   lmBF(y ~ terms)
#   "gtest"  (seed, it, rsF, rsR, rsC, nt, terms, row, H)              generalTestBF(y ~ terms) row
#   "lmpost" (seed, it, rsF, rsR, rsC, src, idx, nt, terms, H, row, col)   posterior(): src 0 of anovaBF's model idx, 1 of lmBF
lmh <- function(d, vars) {
  kinds <- sapply(vars, function(v) if (!is.factor(d[[v]])) 2 else if (v == "r") 1 else 0)
  c(nrow(d), length(vars), kinds, sapply(vars, function(v) if (is.factor(d[[v]])) nlevels(d[[v]]) else 0), d$y,
    unlist(lapply(vars, function(v) if (is.factor(d[[v]])) as.integer(d[[v]]) - 1 else d[[v]])))
}
tmask <- function(trm, vars) sum(2^(match(strsplit(trm, ":", fixed = TRUE)[[1]], vars) - 1))
mkdata <- function(n, la, lb, lr, cont) {
  d <- data.frame(a = factor(sample(seq_len(la), n, replace = TRUE)))
  if (lb > 0) d$b <- factor(sample(seq_len(lb), n, replace = TRUE))
  if (lr > 0) d$r <- factor(rep(seq_len(lr), length.out = n))
  if (cont) d$x <- round(rnorm(n), 4)
  if (any(table(d$a) < 2) || (lb > 0 && any(table(d$b) < 2))) return(mkdata(n, la, lb, lr, cont))
  mu <- 0.4 * as.numeric(d$a) + if (lb > 0) 0.3 * as.numeric(d$b) else 0
  if (cont) mu <- mu + 0.5 * d$x
  if (lr > 0) mu <- mu + 0.3 * rnorm(lr)[as.integer(d$r)]
  d$y <- round(mu + rnorm(n), 4)
  d
}
for (rep in 1:12) {
  two <- rep <= 8; rnd <- rep %in% c(3, 6, 7); la <- sample(2:3, 1); lb <- if (two) sample(2:3, 1) else 0
  if (!two) la <- sample(3:5, 1)
  d <- mkdata(if (rep == 11) 6 * la else sample(18:40, 1), la, lb, if (rnd) sample(4:6, 1) else 0, FALSE)
  if (rep == 11) d$a <- factor(rep(seq_len(la), 6))
  vars <- c("a", if (two) "b", if (rnd) "r"); rs <- c(0.5, sqrt(2) / 2, 1)[rep %% 3 + 1]; rr <- c(1, 0.5)[rep %% 2 + 1]
  fm <- as.formula(paste("y ~", if (two) "a * b" else "a", if (rnd) "+ r"))
  it <- 1000; seed <- sample(1e6, 1); set.seed(seed)
  b <- anovaBF(fm, data = d, whichRandom = if (rnd) "r", rscaleFixed = rs, rscaleRandom = rr, iterations = it, progress = FALSE)
  for (j in seq_len(nrow(b@bayesFactor))) add("anova", c(seed, it, rs, rr, j - 1, lmh(d, vars)), b@bayesFactor$bf[j])
}
for (rep in 1:8) {
  kind <- rep %% 4; d <- mkdata(sample(20:40, 1), sample(2:4, 1), if (kind == 1) sample(2:3, 1) else 0, if (kind == 3) 5 else 0, kind != 1)
  trms <- list(c("a", "x"), c("a", "b"), c("a", "x", "a:x"), c("a", "x", "r"))[[kind + 1]]
  vars <- list(c("a", "x"), c("a", "b"), c("a", "x"), c("a", "r", "x"))[[kind + 1]]
  if (kind == 3) d <- d[, c("a", "r", "x", "y")]
  rs <- c(0.5, sqrt(2) / 2)[rep %% 2 + 1]; rc <- c(sqrt(2) / 4, 0.5)[rep %% 2 + 1]; it <- 1000; seed <- sample(1e6, 1); set.seed(seed)
  b <- lmBF(as.formula(paste("y ~", paste(trms, collapse = " + "))), data = d, whichRandom = if (kind == 3) "r",
            rscaleFixed = rs, rscaleRandom = 1, rscaleCont = rc, iterations = it, progress = FALSE)
  add("lmbf", c(seed, it, rs, 1, rc, length(trms), sapply(trms, tmask, vars = vars), lmh(d, vars)), b@bayesFactor$bf)
}
for (rep in 1:6) {
  d <- mkdata(sample(20:40, 1), sample(2:4, 1), 0, 0, TRUE); vars <- c("a", "x")
  trms <- if (rep %% 2 == 0) c("a", "x", "a:x") else c("a", "x")
  rs <- c(0.5, sqrt(2) / 2, 1)[rep %% 3 + 1]; rc <- c(sqrt(2) / 4, 0.5)[rep %% 2 + 1]; it <- 1000; seed <- sample(1e6, 1); set.seed(seed)
  b <- generalTestBF(as.formula(paste("y ~", paste(trms, collapse = " + "))), data = d, rscaleFixed = rs, rscaleCont = rc,
                     iterations = it, progress = FALSE)
  for (j in seq_len(nrow(b@bayesFactor)))
    add("gtest", c(seed, it, rs, 1, rc, length(trms), sapply(trms, tmask, vars = vars), j - 1, lmh(d, vars)), b@bayesFactor$bf[j])
}
for (rep in 1:8) {
  src <- if (rep <= 5) 0 else 1; it <- 200
  if (src == 0) {
    rnd <- rep == 5; d <- mkdata(sample(20:36, 1), sample(2:3, 1), sample(2:3, 1), if (rnd) 4 else 0, FALSE); vars <- c("a", "b", if (rnd) "r")
    b <- anovaBF(as.formula(paste("y ~ a * b", if (rnd) "+ r")), data = d, whichRandom = if (rnd) "r", iterations = 200, progress = FALSE)
    idx <- c(4, 3, 1, 2, 4)[rep]; seed <- sample(1e6, 1); set.seed(seed)
    ch <- posterior(b, index = idx, iterations = it, progress = FALSE); trms <- NULL; rs <- 0.5; rc <- sqrt(2) / 4
  } else {
    d <- mkdata(sample(20:36, 1), sample(2:4, 1), 0, 0, TRUE); vars <- c("a", "x"); trms <- list(c("a", "x"), c("a", "x", "a:x"), "x")[[rep - 5]]
    rs <- 0.5; rc <- 0.5; idx <- 0; seed <- sample(1e6, 1); set.seed(seed)
    ch <- lmBF(as.formula(paste("y ~", paste(trms, collapse = " + "))), data = d, rscaleFixed = rs, rscaleCont = rc, posterior = TRUE,
               iterations = it, progress = FALSE)
  }
  chain_cases("lmpost", c(seed, it, rs, 1, rc, src, idx - 1, length(trms), if (length(trms)) sapply(trms, tmask, vars = vars), lmh(d, vars)), ch)
}
emit("bayesfactor", "BayesFactor", list(cases))
