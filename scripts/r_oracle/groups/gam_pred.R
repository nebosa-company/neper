# gam (Hastie): predict(fit, newdata) for s() and lo() terms (degree 1), values only (R gives no standard errors at newdata).
# Args: (fam 0 gaussian 1 binomial 2 poisson, n, q smooth terms in formula order, m extra linear columns, nn new rows, kind[q] (0 s, 1 lo), p1[q] (df of s, span of lo), p2[q] (spar of s when df = 0, degree 1 of lo),
# kind 2 is lo() of degree 2 (its model matrix holds x and x^2), x[q * n], z[m * n], y[n], w[n], xn[q * nn], zn[m * nn], type (0 link, 1 response), idx new row)
# new x may lie beyond the data range for s() (linear extension) and lo() (the end cell cubic continued).
suppressMessages(library(gam))
cases <- list()
set.seed(20261201)
add <- function(args, want, tol = 1e-9) cases[[length(cases) + 1]] <<- case("gam_pred", args, want, rel = tol, abs = 1e-10)
fitcase <- function(fam, x, z, y, w, xn, zn, kind, p1, p2, tol = 1e-9) {
  n <- length(y); q <- ncol(x); m <- ncol(z); nn <- nrow(xn)
  d <- data.frame(y = y, w = w); dn <- data.frame(row = seq_len(nn))
  for (j in seq_len(q)) { d[[paste0("x", j)]] <- x[, j]; dn[[paste0("x", j)]] <- xn[, j] }
  for (j in seq_len(m)) { d[[paste0("z", j)]] <- z[, j]; dn[[paste0("z", j)]] <- zn[, j] }
  terms <- sapply(seq_len(q), function(j) if (kind[j] >= 1) sprintf("lo(x%d, span = %g, degree = %d)", j, p1[j], as.integer(kind[j])) else if (p1[j] > 0) sprintf("s(x%d, df = %g)", j, p1[j]) else sprintf("s(x%d, spar = %g)", j, p2[j]))
  fo <- as.formula(paste("y ~", paste(c(terms, if (m > 0) paste0("z", seq_len(m))), collapse = " + ")))
  famf <- switch(fam + 1, gaussian, binomial, poisson)
  ctl <- gam.control(maxit = 30, bf.maxit = 30)
  f <- gam(fo, family = famf, data = d, weights = w, control = ctl)
  pl <- suppressWarnings(predict(f, dn)); pr <- suppressWarnings(predict(f, dn, type = "response"))
  # df matching leaves spar to Brent's search on a criterion flat to rounding: the tolerance is 20 times the move a last-bit change of the weights makes
  mv <- 0
  if (any(kind == 0 & p1 > 0)) for (k in 1:4) {
    g <- gam(fo, family = famf, data = d, weights = w * (1 + c(1e-13, 1e-11, 1e-12, 3e-11)[k] * sin(k * seq_len(n))), control = ctl)
    u <- c(pl, pr); v <- c(suppressWarnings(predict(g, dn)), suppressWarnings(predict(g, dn, type = "response")))
    mv <- max(mv, abs(v - u) / (1 + abs(u)))
  }
  if (mv > 1e-10) tol <- max(tol, 20 * mv)
  hdr <- function(type, idx) c(fam, n, q, m, nn, kind, p1, p2, as.vector(x), as.vector(z), y, w, as.vector(xn), as.vector(zn), type, idx)
  for (i in seq_len(nn)) { add(hdr(0, i - 1), pl[i], tol); add(hdr(1, i - 1), pr[i], tol) }
}
# The package Fortran corrupts memory now and then, so every case runs in its own R process and a crashed one is skipped.
if (nzchar(Sys.getenv("GAM_CHILD"))) {
  do.call(fitcase, readRDS(Sys.getenv("GAM_CHILD")))
  saveRDS(cases, Sys.getenv("GAM_OUT"))
  quit(save = "no")
}
runcase <- function(...) {
  tf <- tempfile(fileext = ".rds"); of <- tempfile(fileext = ".rds")
  saveRDS(list(...), tf)
  Sys.setenv(GAM_CHILD = tf, GAM_OUT = of)
  suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c("scripts/r_oracle/generate.R", "gam_pred"), stdout = FALSE, stderr = FALSE))
  Sys.unsetenv(c("GAM_CHILD", "GAM_OUT"))
  if (file.exists(of)) cases <<- c(cases, readRDS(of)) else message("a case crashed in the package and is skipped")
}
for (rep in 1:18) {
  fam <- rep %% 3; q <- sample(1:3, 1); m <- sample(0:1, 1); n <- sample(25:38, 1); nn <- 4
  x <- matrix(round(runif(n * q, -2, 3), 3), n, q)
  z <- matrix(round(rnorm(n * m), 3), n, m)
  eta <- 0.2 + sin(x[, 1]) * 0.8 + (if (q > 1) 0.3 * x[, 2]^2 / 3 else 0) + (if (m > 0) 0.3 * z[, 1] else 0)
  y <- switch(fam + 1, round(eta + rnorm(n, 0, 0.3), 4), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta)))
  w <- if (rep %% 4 == 1) (if (fam == 1) sample(1:3, n, TRUE) else round(runif(n, 0.5, 2), 3)) else rep(1, n)
  kind <- if (rep %% 3 == 1) rep(0, q) else if (rep %% 3 == 2) rep(1, q) else sample(0:1, q, replace = TRUE)
  if (q == 1 && rep %% 3 == 0) kind <- 1
  p1 <- ifelse(kind == 1, sample(c(0.5, 0.65, 0.8, 0.9), q, replace = TRUE), sample(c(2.5, 3, 4), q, replace = TRUE)); p2 <- rep(1, q)
  if (rep %% 5 == 0 && any(kind == 0)) { j <- which(kind == 0)[1]; p1[j] <- 0; p2[j] <- 0.8 }
  xn <- sapply(seq_len(q), function(j) { r <- range(x[, j]); if (kind[j] >= 1) runif(nn, r[1], r[2]) else runif(nn, r[1] - 0.25 * diff(r), r[2] + 0.25 * diff(r)) })
  xn <- matrix(round(xn, 4), nn, q); zn <- matrix(round(rnorm(nn * m), 3), nn, m)
  runcase(fam = fam, x = x, z = z, y = y, w = w, xn = xn, zn = zn, kind = kind, p1 = p1, p2 = p2)
}
# degree 2 lo(): gam.lo subtracts the fit of the smooth on all the term columns (1, x, x^2) at new x; the package crashes on several mixes, so one lo term, Gaussian
for (rep in 1:30) {
  fam <- 0; q <- sample(1:2, 1); m <- sample(0:1, 1); n <- sample(28:40, 1); nn <- 4
  x <- matrix(round(runif(n * q, -2, 3), 3), n, q)
  z <- matrix(round(rnorm(n * m), 3), n, m)
  eta <- 0.2 + sin(x[, 1]) * 0.8 + (if (q > 1) 0.3 * x[, 2]^2 / 3 else 0) + (if (m > 0) 0.3 * z[, 1] else 0)
  y <- round(eta + rnorm(n, 0, 0.3), 4)
  w <- if (rep %% 3 == 1) round(runif(n, 0.5, 2), 3) else rep(1, n)
  kind <- rep(0, q); kind[sample(q, 1)] <- 2
  p1 <- ifelse(kind == 2, sample(c(0.6, 0.75, 0.9), q, replace = TRUE), sample(c(2.5, 3, 4), q, replace = TRUE)); p2 <- rep(1, q)
  xn <- sapply(seq_len(q), function(j) { r <- range(x[, j]); if (kind[j] >= 1) runif(nn, r[1], r[2]) else runif(nn, r[1] - 0.25 * diff(r), r[2] + 0.25 * diff(r)) })
  xn <- matrix(round(xn, 4), nn, q); zn <- matrix(round(rnorm(nn * m), 3), nn, m)
  runcase(fam = fam, x = x, z = z, y = y, w = w, xn = xn, zn = zn, kind = kind, p1 = p1, p2 = p2)
}
# lo() new x beyond the data box: the package warns "extrapolation not allowed with blending" and goes on with the end cell's cubic past its vertex
for (rep in 1:24) {
  fam <- rep %% 3; q <- sample(1:2, 1); m <- sample(0:1, 1); n <- sample(28:40, 1); nn <- 4
  x <- matrix(round(runif(n * q, -2, 3), 3), n, q)
  z <- matrix(round(rnorm(n * m), 3), n, m)
  eta <- 0.2 + sin(x[, 1]) * 0.8 + (if (q > 1) 0.3 * x[, 2]^2 / 3 else 0) + (if (m > 0) 0.3 * z[, 1] else 0)
  y <- switch(fam + 1, round(eta + rnorm(n, 0, 0.3), 4), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta)))
  w <- rep(1, n)
  kind <- rep(0, q); kind[sample(q, 1)] <- if (rep <= 12) 1 else 2
  if (kind[1] == 2 && fam != 0) next
  p1 <- ifelse(kind >= 1, sample(c(0.6, 0.75, 0.9), q, replace = TRUE), sample(c(2.5, 3, 4), q, replace = TRUE)); p2 <- rep(1, q)
  xn <- sapply(seq_len(q), function(j) { r <- range(x[, j]); runif(nn, r[1] - 0.15 * diff(r), r[2] + 0.15 * diff(r)) })
  xn <- matrix(round(xn, 4), nn, q); zn <- matrix(round(rnorm(nn * m), 3), nn, m)
  runcase(fam = fam, x = x, z = z, y = y, w = w, xn = xn, zn = zn, kind = kind, p1 = p1, p2 = p2)
}
# n between 50 and 199 distinct x: the knot count comes from the thinned sknotl branches, so predict at new x exercises them (one s() term, Gaussian and Poisson)
for (rep in 1:6) {
  fam <- c(0, 2)[rep %% 2 + 1]; n <- c(55, 80, 120, 150, 180, 199)[rep]; nn <- 4
  x <- matrix(round(runif(n, -2, 3), 4), n, 1); z <- matrix(0, n, 0)
  eta <- 0.2 + sin(x[, 1]) * 0.8
  y <- if (fam == 0) round(eta + rnorm(n, 0, 0.3), 4) else rpois(n, exp(eta))
  xn <- matrix(round(runif(nn, -2.3, 3.3), 4), nn, 1); zn <- matrix(0, nn, 0)
  runcase(fam = fam, x = x, z = z, y = y, w = rep(1, n), xn = xn, zn = zn, kind = 0, p1 = 4, p2 = 1)
}
# 800 or more distinct x use the log 140 / log 200 knot constants, 3200 or more the 200 + (n - 3200)^0.2 term (Gaussian, one s() term, df given; one new row keeps the file small)
for (rep in 1:4) {
  n <- c(900, 1200, 3300, 3400)[rep]; nn <- 1
  x <- matrix(round(runif(n, -2, 3), 5), n, 1); z <- matrix(0, n, 0)
  y <- round(0.2 + sin(x[, 1]) * 0.8 + rnorm(n, 0, 0.3), 4)
  xn <- matrix(round(runif(nn, -2.3, 3.3), 4), nn, 1); zn <- matrix(0, nn, 0)
  runcase(fam = 0, x = x, z = z, y = y, w = rep(1, n), xn = xn, zn = zn, kind = 0, p1 = 4, p2 = 1)
}
emit("gam_pred", "gam", list(cases))
