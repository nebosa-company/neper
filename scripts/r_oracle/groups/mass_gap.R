# MASS arguments and helpers the other mass_* groups leave out: ginv tol, psi.huber / psi.hampel / psi.bisquare called directly, bw.ucv / bw.bcv / bw.SJ and
# MASS::ucv / bcv / width.SJ with nb, lower, upper and method, kde2d grids and defaults, nclass.freq / scott / FD and hist.* / frequency.polygon,
# mvrnorm with tol and empirical, lqs and cov.rob with nsamp "exact" and "sample", lmsreg, ltsreg, cov.mve, cov.mcd, cor = TRUE and the lqs formula interface.
#   "ginv"  (m, n, tol, X[m n] col-major)                      the position-weighted sum of ginv(X, tol)
#   "psi"   (kind 0 huber 1 hampel 2 bisquare, deriv, a, b, c, u)
#   "bw"    (fn 0 bw.ucv 1 bw.bcv 2 bw.SJ ste 3 bw.SJ dpi 4 ucv 5 bcv 6 width.SJ ste 7 width.SJ dpi, nb, lower, upper, tol (-1 missing), x[n])
#   "kde2d" (mode 0 x grid 1 y grid 2 z, n, n1, n2, hmode 0 default 1 scalar 2 pair, h1, h2, lims given, x[n], y[n]); the grids and z are position-weighted sums
#   "hist"  (fn 0 nclass.freq 1 nclass.scott 2 nclass.FD 3 breaks 4 counts 5 number of breaks 6 midpoints, src 0 k given 1 freq 2 scott 3 FD, k, x[n])
#   "mv"    (seed, n, p, tol, empirical, mu[p], Sigma[p p] row-major, mode 0 sum 1 weighted sum 2 sum of squares)
#   "lqs"   (seed, n, p0, method 0 lqs 1 lts 2 lms 3 S, nsamp (-1 best, -2 exact, -3 sample), adjust, k0, mode, X[n p0], y[n])
#           mode 0 crit 1 weighted coef 2 scale 3 scale2 4 weighted residuals 5 weighted fitted 6 weighted bestone 7 singular samples
#   "covrob" (seed, n, p, method 0 mve 1 mcd, nsamp (-1 best, -2 exact, -3 sample), cor, mode, X[n p])   mode 0 crit 1 center 2 cov-or-cor 3 best 4 singular 5 n.obs
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(seq_along(v) * as.numeric(v))
set.seed(20262601)

# ginv with tol
for (rep in 1:24) {
  m <- sample(3:7, 1); n <- sample(2:6, 1); r <- sample(1:min(m, n), 1)
  X <- matrix(rnorm(m * r), m, r) %*% matrix(rnorm(r * n), r, n) + (rep %% 3 == 0) * matrix(rnorm(m * n, 0, 1e-3), m, n)
  tol <- c(sqrt(.Machine$double.eps), 1e-3, 0.05, 0.3, 1e-12, 1e-10)[rep %% 6 + 1]
  add("ginv", c(m, n, tol, as.vector(X)), wsum(ginv(X, tol = tol)), 1e-8, 1e-9)
}

# psi functions called directly
us <- c(0, 1e-9, -1e-9, 0.3, -0.3, 1, -1, 1.345, -1.345, 2, 2.5, -2.5, 4, 4.685, -4.685, 5.5, 8, -8, 9, 12, -30)
for (u in us) for (deriv in 0:2) {
  for (k in c(0.5, 1.345, 3)) add("psi", c(0, deriv, k, 0, 0, u), psi.huber(u, k, deriv))
  for (abc in list(c(2, 4, 8), c(1.5, 3.5, 7), c(0.5, 1, 6))) add("psi", c(1, deriv, abc, u), psi.hampel(u, abc[1], abc[2], abc[3], deriv))
  for (cc in c(1.5, 4.685, 9)) add("psi", c(2, deriv, cc, 0, 0, u), psi.bisquare(u, cc, deriv))
}

# bandwidth selectors, every argument
gx <- function(n) switch(sample(1:3, 1), rnorm(n), rexp(n), c(rnorm(n %/% 2), rnorm(n - n %/% 2, 4, 0.7)))
for (rep in 1:48) {
  n <- sample(c(15, 40, 120, 300, 420, 600, 800), 1); x <- gx(n)
  fn <- (rep - 1) %% 8; nb <- c(1000, 1000, 400, 200, 1000, 2000)[sample(1:6, 1)]
  if (fn >= 4) nb <- c(1000, 300, 600)[sample(1:3, 1)]
  hmax <- 1.144 * sqrt(var(x)) * n^(-1/5) * (if (fn %in% c(4, 5)) 4 else 1)
  lo <- -1; up <- -1; tl <- -1
  if (rep %% 3 == 0) { lo <- 0.05 * hmax; up <- 1.5 * hmax }
  if (rep %% 5 == 0 && lo > 0) tl <- 0.2 * lo
  args <- list(x, nb = nb)
  if (lo > 0) { args$lower <- lo; args$upper <- up }
  if (tl > 0 && fn < 4) args$tol <- tl
  if (fn == 3 || fn == 7) args$method <- "dpi"
  f <- list(bw.ucv, bw.bcv, bw.SJ, bw.SJ, ucv, bcv, width.SJ, width.SJ)[[fn + 1]]
  if (fn %in% c(4, 5, 6, 7)) { args$tol <- NULL }
  v <- tryCatch(suppressWarnings(do.call(f, args)), error = function(e) NA)
  add("bw", c(fn, nb, lo, up, tl, x), v, 1e-8, 1e-10)
}

# kde2d: the grids, the default limits and bandwidths, scalar h
for (rep in 1:15) {
  n <- sample(c(20, 60, 150), 1); x <- rnorm(n); y <- 0.5 * x + rnorm(n)
  n1 <- sample(5:20, 1); n2 <- sample(5:20, 1); hm <- (rep - 1) %% 3
  h1 <- runif(1, 0.3, 1.5); h2 <- runif(1, 0.3, 1.5); lims_given <- as.numeric(rep %% 2 == 0)
  args <- list(x, y, n = c(n1, n2))
  if (hm == 1) args$h <- h1 else if (hm == 2) args$h <- c(h1, h2)
  if (lims_given == 1) args$lims <- c(min(x) - 0.5, max(x) + 0.5, min(y) - 0.2, max(y) + 1)
  k <- do.call(kde2d, args)
  a <- c(n, n1, n2, hm, h1, h2, lims_given); tail <- c(x, y)
  if (lims_given == 1) tail <- c(args$lims, tail)
  add("kde2d", c(0, a, tail), wsum(k$x)); add("kde2d", c(1, a, tail), wsum(k$y)); add("kde2d", c(2, a, tail), wsum(as.vector(k$z)))
}

# histogram helpers
for (rep in 1:24) {
  n <- sample(c(10, 30, 100, 200), 1); x <- switch(rep %% 4 + 1, rnorm(n), rexp(n), round(rnorm(n), 1), runif(n, 5, 50))
  if (rep %% 11 == 0) x <- round(x)
  src <- rep %% 4; k <- sample(2:15, 1)
  kk <- switch(src + 1, k, nclass.freq(x), grDevices::nclass.scott(x), grDevices::nclass.FD(x))
  add("hist", c(0, 1, 0, x), nclass.freq(x), 0, 0); add("hist", c(1, 1, 0, x), grDevices::nclass.scott(x), 0, 0); add("hist", c(2, 1, 0, x), grDevices::nclass.FD(x), 0, 0)
  h <- hist(x, kk, plot = FALSE)
  add("hist", c(3, src, k, x), wsum(h$breaks)); add("hist", c(4, src, k, x), wsum(h$counts), 0, 0); add("hist", c(5, src, k, x), length(h$breaks), 0, 0)
  add("hist", c(6, src, k, x), wsum(h$mids))
}

# mvrnorm with tol and empirical
flat <- function(m) as.vector(t(unclass(m)))
for (rep in 1:30) {
  p <- c(2, 3, 4)[rep %% 3 + 1]; n <- c(6, 20, 50, 100)[(rep - 1) %/% 8 + 1]; emp <- as.numeric(rep %% 2 == 0)
  A <- matrix(rnorm(p * p), p); Sigma <- crossprod(A) + diag(p) * 0.5
  tol <- 1e-6
  if (rep %% 5 == 0) { # indefinite by a small amount: passes only a loose tol
    e <- eigen(Sigma, symmetric = TRUE); e$values[p] <- -2e-4 * e$values[1]; Sigma <- e$vectors %*% diag(e$values) %*% t(e$vectors); Sigma <- (Sigma + t(Sigma)) / 2; tol <- c(1e-3, 1e-6)[rep %% 2 + 1]
  }
  mu <- runif(p, -2, 2); seed <- sample(1:1000000, 1); set.seed(seed)
  X <- tryCatch(mvrnorm(n, mu, Sigma, tol = tol, empirical = emp == 1), error = function(e) NULL)
  if (is.null(X)) next
  v <- as.numeric(flat(X)); a <- c(seed, n, p, tol, emp, mu, flat(Sigma))
  add("mv", c(a, 0), sum(v), 1e-8, 1e-10); add("mv", c(a, 1), sum(seq_along(v) * v), 1e-8, 1e-10); add("mv", c(a, 2), sum(v^2), 1e-8, 1e-10)
}
set.seed(20262602)

# lqs: exact and sample resampling, the fitted values, the wrappers and the formula interface
mnames <- c("lqs", "lts", "lms", "S")
for (rep in 1:60) {
  n <- sample(c(8, 9, 10, 12, 14), 1); p0 <- sample(1:2, 1)
  X <- matrix(rnorm(n * p0), n, p0); b <- rnorm(p0 + 1)
  y <- as.vector(b[1] + X %*% b[-1] + rnorm(n, 0, 0.5))
  bad <- sample(n, max(1, n %/% 4)); y[bad] <- y[bad] + rnorm(length(bad), 8, 3)
  method <- (rep - 1) %% 4; seed <- sample(1:1000000, 1)
  nsamp <- c(-2, -3, -1, -2)[(rep - 1) %/% 4 %% 4 + 1]; adjust <- as.numeric(rep %% 5 != 0); k0 <- if (method == 3) c(1.548, 0.8, 2.5)[rep %% 3 + 1] else 1.548
  ctl <- list(psamp = NA, nsamp = c("exact", "sample", "best")[match(nsamp, c(-2, -3, -1))], adjust = adjust == 1)
  d <- data.frame(y = y, X); names(d)[-1] <- paste0("x", seq_len(p0))
  set.seed(seed)
  z <- tryCatch(suppressWarnings(switch(rep %% 3 + 1,
    lqs(X, y, method = mnames[method + 1], k0 = k0, control = ctl),
    lqs(as.formula(paste("y ~", paste0("x", seq_len(p0), collapse = " + "))), data = d, method = mnames[method + 1], k0 = k0, control = ctl),
    if (method == 2) lmsreg(X, y, control = ctl) else if (method == 1) ltsreg(X, y, control = ctl) else lqs(X, y, method = mnames[method + 1], k0 = k0, control = ctl))), error = function(e) NULL)
  if (is.null(z)) next
  a <- c(seed, n, p0, method, nsamp, adjust, k0); tail <- c(as.vector(X), y)
  nsing <- as.numeric(sub(" .*", "", z$sing))
  add("lqs", c(a, 0, tail), z$crit); add("lqs", c(a, 1, tail), wsum(z$coefficients)); add("lqs", c(a, 2, tail), z$scale[1]); add("lqs", c(a, 3, tail), z$scale[2])
  add("lqs", c(a, 4, tail), wsum(z$residuals), 1e-8, 1e-8); add("lqs", c(a, 5, tail), wsum(z$fitted.values), 1e-8, 1e-8)
  add("lqs", c(a, 6, tail), wsum(z$bestone), 0, 0); add("lqs", c(a, 7, tail), nsing, 0, 0)
}
# S estimates: the scale is sensitive to the initial scale, many seeds, larger n
for (rep in 1:40) {
  n <- sample(c(20, 30, 60), 1); p0 <- sample(1:3, 1)
  X <- matrix(rnorm(n * p0), n, p0); b <- rnorm(p0 + 1); y <- as.vector(b[1] + X %*% b[-1] + rt(n, 3))
  seed <- sample(1:1000000, 1); k0 <- c(1.548, 1.0, 2.2)[rep %% 3 + 1]; nsamp <- c(-1, 300, 1, 2)[rep %% 4 + 1]
  set.seed(seed)
  z <- tryCatch(lqs(X, y, method = "S", k0 = k0, control = list(psamp = NA, adjust = TRUE, nsamp = if (nsamp == -1) "best" else nsamp)), error = function(e) NULL)
  if (is.null(z)) next
  a <- c(seed, n, p0, 3, nsamp, 1, k0); tail <- c(as.vector(X), y)
  add("lqs", c(a, 0, tail), z$crit, 1e-12, 1e-12); add("lqs", c(a, 1, tail), wsum(z$coefficients), 1e-9, 1e-12); add("lqs", c(a, 2, tail), z$scale[1], 1e-12, 1e-12); add("lqs", c(a, 3, tail), z$scale[2], 1e-12, 1e-12)
}

# cov.rob: exact and sample, cor = TRUE, n.obs, the cov.mve and cov.mcd wrappers
for (rep in 1:48) {
  n <- sample(c(10, 12, 15), 1); p <- sample(2:3, 1)
  X <- matrix(rnorm(n * p), n, p) %*% matrix(rnorm(p * p), p); bad <- sample(n, n %/% 5); X[bad, ] <- X[bad, ] + 6
  method <- (rep - 1) %% 2; seed <- sample(1:1000000, 1); nsamp <- c(-2, -3, -1)[(rep - 1) %/% 2 %% 3 + 1]; cr <- as.numeric(rep %% 4 >= 2)
  ns <- c("exact", "sample", "best")[match(nsamp, c(-2, -3, -1))]
  set.seed(seed)
  z <- tryCatch(suppressWarnings(if (method == 0) cov.mve(X, cor = cr == 1, nsamp = ns) else cov.mcd(X, cor = cr == 1, nsamp = ns)), error = function(e) NULL)
  if (is.null(z)) next
  a <- c(seed, n, p, method, nsamp, cr); tail <- as.vector(X)
  add("covrob", c(a, 0, tail), z$crit); add("covrob", c(a, 1, tail), wsum(z$center)); add("covrob", c(a, 2, tail), wsum(if (cr == 1) z$cor else z$cov))
  add("covrob", c(a, 3, tail), wsum(z$best), 0, 0); add("covrob", c(a, 4, tail), as.numeric(sub(" .*", "", z$msg)), 0, 0); add("covrob", c(a, 5, tail), z$n.obs, 0, 0)
}
emit("mass_gap", "MASS", list(cases))
