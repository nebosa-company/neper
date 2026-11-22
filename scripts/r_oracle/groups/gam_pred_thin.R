# gam (Hastie) predict after the knot-thinning branch of sknotl_ndk: the existing gam_pred cases all have
# fewer than 200 distinct x, so the n < 800 (divisor 600) and 800..3199 (divisor 2400) branches of
# sknotl_ndk in lib/e/algo/stat/gam.e were never exercised. This group fits one s() term with n around and
# on both sides of those boundaries and emits its predictions at one new x.
# Args: (fam, n, q, m, nn, kind[q], p1[q], p2[q], x[q*n], z[m*n], y[n], w[n], xn[q*nn], zn[m*nn], type, idx)
suppressMessages(library(gam))
cases <- list()
set.seed(20270103)
add <- function(args, want, tol = 1e-9) cases[[length(cases) + 1]] <<- case("gam_pred", args, want, rel = tol, abs = 1e-10)
fitcase <- function(fam, x, z, y, w, xn, zn, kind, p1, p2, tol = 1e-9) {
  n <- length(y); q <- ncol(x); m <- ncol(z); nn <- nrow(xn)
  d <- data.frame(y = y, w = w); dn <- data.frame(row = seq_len(nn))
  for (j in seq_len(q)) { d[[paste0("x", j)]] <- x[, j]; dn[[paste0("x", j)]] <- xn[, j] }
  for (j in seq_len(m)) { d[[paste0("z", j)]] <- z[, j]; dn[[paste0("z", j)]] <- zn[, j] }
  terms <- sapply(seq_len(q), function(j) if (p1[j] > 0) sprintf("s(x%d, df = %g)", j, p1[j]) else sprintf("s(x%d, spar = %g)", j, p2[j]))
  fo <- as.formula(paste("y ~", paste(c(terms, if (m > 0) paste0("z", seq_len(m))), collapse = " + ")))
  famf <- switch(fam + 1, gaussian, binomial, poisson)
  f <- gam(fo, family = famf, data = d, weights = w, control = gam.control(maxit = 30, bf.maxit = 30))
  pl <- suppressWarnings(predict(f, dn)); pr <- suppressWarnings(predict(f, dn, type = "response"))
  mv <- 0
  if (any(p1 > 0)) for (k in 1:4) {
    g <- gam(fo, family = famf, data = d, weights = w * (1 + c(1e-13, 1e-11, 1e-12, 3e-11)[k] * sin(k * seq_len(n))), control = gam.control(maxit = 30, bf.maxit = 30))
    u <- c(pl, pr); v <- c(suppressWarnings(predict(g, dn)), suppressWarnings(predict(g, dn, type = "response")))
    mv <- max(mv, abs(v - u) / (1 + abs(u)))
  }
  if (mv > 1e-10) tol <- max(tol, 20 * mv)
  hdr <- function(type, idx) c(fam, n, q, m, nn, kind, p1, p2, as.vector(x), as.vector(z), y, w, as.vector(xn), as.vector(zn), type, idx)
  for (i in seq_len(nn)) { add(hdr(0, i - 1), pl[i], tol); add(hdr(1, i - 1), pr[i], tol) }
}
# The package Fortran corrupts memory now and then, so every case runs in its own R process
if (nzchar(Sys.getenv("GAM_CHILD"))) {
  do.call(fitcase, readRDS(Sys.getenv("GAM_CHILD")))
  saveRDS(cases, Sys.getenv("GAM_OUT"))
  quit(save = "no")
}
runcase <- function(...) {
  tf <- tempfile(fileext = ".rds"); of <- tempfile(fileext = ".rds")
  saveRDS(list(...), tf)
  Sys.setenv(GAM_CHILD = tf, GAM_OUT = of)
  suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c("scripts/r_oracle/generate.R", "gam_pred_thin"), stdout = FALSE, stderr = FALSE))
  Sys.unsetenv(c("GAM_CHILD", "GAM_OUT"))
  if (file.exists(of)) cases <<- c(cases, readRDS(of)) else message("a case crashed in the package and is skipped")
}
for (n in c(300, 500, 700, 800, 900, 1200)) {
  x <- matrix(round(runif(n, -2, 3), 4), n, 1)
  y <- round(sin(x[, 1]) + rnorm(n, 0, 0.3), 4); w <- rep(1, n)
  xn <- matrix(round(median(x[, 1]), 4), 1, 1); zn <- matrix(0, 1, 0)
  runcase(fam = 0, x = x, z = matrix(0, n, 0), y = y, w = w, xn = xn, zn = zn, kind = 0, p1 = 3, p2 = 1)
}
emit("gam_pred_thin", "gam", list(cases))
