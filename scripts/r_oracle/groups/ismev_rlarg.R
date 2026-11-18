# ismev rlarg.fit and pp.fit without covariates (Nelder-Mead MLE and the optim Hessian standard errors). args: (rows, r, which, matrix row-major...);
# which 0..2 a parameter, 10..12 its standard error, 99 the negative log-likelihood. Agreement is to the optimiser tolerance of R.
suppressMessages(library(ismev))
cases <- list()
add <- function(args, want, rel) cases[[length(cases) + 1]] <<- case("rl", args, want, rel = rel, abs = 1e-3)
set.seed(20261701)
for (rep in 1:6) {
  rows <- sample(25:60, 1); r <- c(2, 3, 4)[rep %% 3 + 1]
  mu <- runif(1, 5, 20); sc <- runif(1, 1, 4); xi <- c(0.15, -0.15, 0.05)[rep %% 3 + 1]
  # the r largest of a GEV block: the arrival times E_j of a unit Poisson process through the GEV quantile
  m <- t(vapply(seq_len(rows), function(i) { e <- cumsum(rexp(r)); mu + sc * (e^(-xi) - 1) / xi }, numeric(r)))
  if (r == 1) m <- matrix(m, ncol = 1)
  m <- t(apply(m, 1, sort, decreasing = TRUE))
  f <- tryCatch(rlarg.fit(m, r = r, show = FALSE), error = function(e) NULL)
  if (is.null(f) || f$conv != 0) next
  flat <- as.vector(t(m))
  for (k in 1:3) { add(c(rows, r, k - 1, flat), f$mle[k], 2e-2); add(c(rows, r, 10 + k - 1, flat), f$se[k], 5e-2) }
  add(c(rows, r, 99, flat), f$nllh, 1e-6)
}
# pp.fit with a constant threshold: case "pp", args (n, npy, threshold, which, x...)
for (rep in 1:5) {
  n <- sample(300:700, 1); npy <- c(365, 100, 50)[rep %% 3 + 1]
  x <- rexp(n) * 2 + (rep %% 2) * 0.4 * rexp(n)^2 + 10
  th <- as.numeric(quantile(x, 0.9))
  f <- tryCatch(pp.fit(x, th, npy = npy, show = FALSE), error = function(e) NULL)
  if (is.null(f) || f$conv != 0) next
  addp <- function(which, want, rel) cases[[length(cases) + 1]] <<- case("pp", c(n, npy, th, which, x), want, rel = rel, abs = 1e-3)
  for (k in 1:3) { addp(k - 1, f$mle[k], 3e-2); addp(10 + k - 1, f$se[k], 8e-2) }
  addp(99, f$nllh, 1e-6)
}
# profile likelihoods: ismev only plots them, so the loop of gev.prof and gpd.prof is replayed here; "pr" args (kind, n, m, xlow, xup, nint, threshold or 0, npy, idx, x...)
# kind 0 gev.prof, 1 gpd.prof; the want is the profile negative log-likelihood at grid point idx
oneprof <- function(kind, x, m, nint, th = 0, npy = 365) {
  n <- length(x)
  if (kind == 0) {
    z <- gev.fit(x, show = FALSE); p <- 1 / m
    lo <- gevq(z$mle, 1 - 1 / m) - 0.5 * z$se[1] * 3; xlow <- lo; xup <- lo + 6 * (gevq(z$mle, 1 - 1 / m) - lo)
    sol <- c(z$mle[2], z$mle[3]); v <- numeric(nint); xs <- seq(xlow, xup, length = nint)
    plik <- function(a) {
      if (abs(a[2]) < 1e-6) { mu <- xp + a[1] * log(-log(1 - p)); y <- (z$data - mu) / a[1]
        if (is.infinite(mu) || a[1] <= 0) 1e6 else length(y) * log(a[1]) + sum(exp(-y)) + sum(y) }
      else { mu <- xp - a[1] / a[2] * ((-log(1 - p))^(-a[2]) - 1); y <- 1 + a[2] * (z$data - mu) / a[1]
        if (is.infinite(mu) || a[1] <= 0 || any(y <= 0)) 1e6 else length(y) * log(a[1]) + sum(y^(-1 / a[2])) + sum(log(y)) * (1 / a[2] + 1) } }
    for (i in 1:nint) { xp <- xs[i]; o <- optim(sol, plik); sol <- o$par; v[i] <- o$value }
  } else {
    z <- gpd.fit(x, th, npy = npy, show = FALSE); u <- z$threshold; la <- z$rate; xdat <- z$data
    mm <- m * npy; xlow <- u + 1; xup <- max(x) * 1.6
    sol <- z$mle[2]; v <- numeric(nint); xs <- seq(xlow, xup, length = nint)
    plik <- function(a) { sc <- (a * (xp - u)) / ((mm * la)^a - 1)
      if (abs(a) < 1e-4) length(xdat) * log(sc) + sum(xdat - u) / sc
      else { y <- 1 + a * (xdat - u) / sc; if (any(y <= 0) || sc <= 0) 1e6 else length(xdat) * log(sc) + sum(log(y)) * (1 / a + 1) } }
    for (i in 1:nint) { xp <- xs[i]; o <- optim(sol, plik, method = "BFGS"); sol <- o$par; v[i] <- o$value }
  }
  for (i in which(v < 1e5)) cases[[length(cases) + 1]] <<- case("pr", c(kind, n, m, xs[1], xs[nint], nint, th, npy, i - 1, x), v[i], rel = 2e-4, abs = 1e-3)
}
set.seed(20261703)
xg <- 10 + 2 * ((-log(runif(80)))^(-0.1) - 1) / 0.1
oneprof(0, xg, 50, 12)
xe <- rexp(300) * 2 + 5
oneprof(1, xe, 20, 10, th = as.numeric(quantile(xe, 0.85)), npy = 50)
# gev.fit with covariates on any parameter: "cv" args (n, qm, qs, qx, mulink, siglink, shlink, which, designs..., x): the designs of mu, sigma, xi (each n by q, row-major,
# intercept first) one after another then the data; which 0.. a parameter, 100.. its standard error, 999 the negative log-likelihood
onecov <- function(n, mul, sigl, shl, mulink = 0, siglink = 0, shlink = 0) {
  t <- seq(-1, 1, length = n); yd <- cbind(t, sin(3 * t))
  z <- rnorm(n)
  x <- 12 + 2 * t + (1.5 + 0.3 * (if (siglink == 1) 0 else t)) * ((-log(runif(n)))^(-0.1) - 1) / 0.1 + 0 * z
  lk <- c(identity, exp)
  f <- tryCatch(gev.fit(x, yd, mul = mul, sigl = sigl, shl = shl, mulink = lk[[mulink + 1]], siglink = lk[[siglink + 1]], shlink = lk[[shlink + 1]], show = FALSE), error = function(e) NULL)
  if (is.null(f) || f$conv != 0) return(invisible(NULL))
  des <- function(ix) cbind(1, yd[, ix, drop = FALSE])
  dd <- c(as.vector(t(des(mul))), as.vector(t(des(sigl))), as.vector(t(des(shl))))
  qm <- length(mul) + 1; qs <- length(sigl) + 1; qx <- length(shl) + 1
  addc <- function(which, want, rel) cases[[length(cases) + 1]] <<- case("cv", c(n, qm, qs, qx, mulink, siglink, shlink, which, dd, x), want, rel = rel, abs = 1e-3)
  for (k in seq_along(f$mle)) { addc(k - 1, f$mle[k], 5e-2); addc(100 + k - 1, f$se[k], 1.5e-1) }
  addc(999, f$nllh, 1e-6)
}
set.seed(20261704)
onecov(80, NULL, 1, NULL)
onecov(80, 1, 1, NULL)
onecov(100, NULL, NULL, 1)
onecov(90, 1, 2, NULL, 0, 1, 0)
# rlarg.fit and pp.fit with covariates: "cr" args (n, r, qm, qs, qx, mulink, siglink, shlink, which, designs..., x row-major), "cp" args (n, npy, threshold, qm, qs, qx, mulink, siglink, shlink, which, designs..., x);
# which 0.. a parameter, 100.. its standard error, 999 the negative log-likelihood
lks <- c(identity, exp)
desg <- function(yd, ix) cbind(1, yd[, ix, drop = FALSE])
onecr <- function(n, r, mul, sigl, shl, mulink = 0, siglink = 0, shlink = 0) {
  t <- seq(-1, 1, length = n); yd <- cbind(t, cos(2 * t))
  m <- t(vapply(seq_len(n), function(i) { e <- cumsum(rexp(r)); 12 + 2 * t[i] + 1.5 * (e^(-0.1) - 1) / 0.1 }, numeric(r)))
  f <- tryCatch(rlarg.fit(m, r = r, ydat = yd, mul = mul, sigl = sigl, shl = shl, mulink = lks[[mulink + 1]], siglink = lks[[siglink + 1]], shlink = lks[[shlink + 1]], show = FALSE), error = function(e) NULL)
  if (is.null(f) || f$conv != 0) return(invisible(NULL))
  dd <- c(as.vector(t(desg(yd, mul))), as.vector(t(desg(yd, sigl))), as.vector(t(desg(yd, shl))))
  qm <- length(mul) + 1; qs <- length(sigl) + 1; qx <- length(shl) + 1
  addc <- function(which, want, rel) cases[[length(cases) + 1]] <<- case("cr", c(n, r, qm, qs, qx, mulink, siglink, shlink, which, dd, as.vector(t(m))), want, rel = rel, abs = 1e-3)
  for (k in seq_along(f$mle)) { addc(k - 1, f$mle[k], 5e-2); addc(100 + k - 1, f$se[k], 1.5e-1) }
  addc(999, f$nllh, 1e-6)
}
onecp <- function(n, npy, mul, sigl, shl, mulink = 0, siglink = 0, shlink = 0) {
  t <- seq(-1, 1, length = n); yd <- cbind(t, cos(2 * t))
  x <- 10 + rexp(n) * 2 + 0.5 * t
  th <- as.numeric(quantile(x, 0.9))
  qm <- length(mul) + 1; qs <- length(sigl) + 1; qx <- length(shl) + 1
  fitpp <- function(mi = NULL, si = NULL, hi = NULL) tryCatch(pp.fit(x, th, npy = npy, ydat = yd, mul = mul, sigl = sigl, shl = shl, mulink = lks[[mulink + 1]], siglink = lks[[siglink + 1]], shlink = lks[[shlink + 1]], muinit = mi, siginit = si, shinit = hi, show = FALSE), error = function(e) NULL)
  f <- fitpp()
  if (is.null(f)) return(invisible(NULL))
  # R's Nelder-Mead stalls on these fits: restart from its own solution until the likelihood is stable
  for (it in 1:30) {
    g <- fitpp(f$mle[seq_len(qm)], f$mle[qm + seq_len(qs)], f$mle[qm + qs + seq_len(qx)])
    if (is.null(g)) break
    done <- abs(g$nllh - f$nllh) < 1e-9 * (1 + abs(f$nllh)); f <- g
    if (done) break
  }
  if (f$conv != 0) return(invisible(NULL))
  dd <- c(as.vector(t(desg(yd, mul))), as.vector(t(desg(yd, sigl))), as.vector(t(desg(yd, shl))))
  addc <- function(which, want, rel) cases[[length(cases) + 1]] <<- case("cp", c(n, npy, th, qm, qs, qx, mulink, siglink, shlink, which, dd, x), want, rel = rel, abs = 1e-3)
  for (k in seq_along(f$mle)) { addc(k - 1, f$mle[k], 8e-2); addc(100 + k - 1, f$se[k], 2e-1) }
  addc(999, f$nllh, 1e-6)
}
set.seed(20261705)
onecr(60, 3, 1, NULL, NULL)
onecr(60, 2, NULL, 1, NULL)
onecr(70, 3, 1, 2, NULL)
onecp(400, 100, 1, NULL, NULL)
onecp(400, 100, NULL, 1, NULL)
emit("ismev_rlarg", "ismev", list(cases))
