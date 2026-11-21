# gmmpkg: gmm's linear one-equation estimator: twoStep, iterated and cue (Nelder-Mead and BFGS), vcov = iid, MDS or HAC, five kernels, a fixed bandwidth, bwAndrews and bwNeweyWest, prewhite 0 or 1, the J test and car::linearHypothesis (Chisq and F).
#   args: (what, index, seed, n, nz, icpt, rho, type, vcov, kernel, bwmode, bw, prewhite, optim, hyp)
#   what 0 coefficient index, 1 covariance entry index (row * p + col), 2 J, 3 J p-value, 4 weight bandwidth (HAC), 5..8 hypothesis chi-square, its p-value, F, its p-value
#   the data are redrawn in Neper from set.seed(seed): Z (n by nz, column-major rnorm), e, v; u = filter(e, rho, "recursive"); x = z1 + (0.5 z2) + 0.5 u + v; y = icpt + 2 x + u (1 + 0.5 |z1|)
#   type 0 twoStep 1 iterated 2 cue; vcov 0 iid 1 MDS 2 HAC; kernel 0 Quadratic Spectral 1 Truncated 2 Bartlett 3 Parzen 4 Tukey-Hanning; bwmode 0 fixed bw 1 bwAndrews 2 bwNeweyWest; optim 0 Nelder-Mead 1 BFGS
#   hyp 0: the last coefficient = 1.95; hyp 1 (two coefficients): b = (1.1, 2)
suppressMessages({library(gmm); library(car)})
cases <- list()
add <- function(args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("gmm", args, want, rel = rel, abs = 1e-12)
kn <- c("Quadratic Spectral", "Truncated", "Bartlett", "Parzen", "Tukey-Hanning")
run <- function(seed, n, nz, icpt, rho, type, vcov, kernel, bwmode, bw, prewhite, optim = 0, rel = 1e-9) {
  set.seed(seed)
  Zm <- matrix(rnorm(n * nz), n, nz); e <- rnorm(n); v <- rnorm(n)
  u <- as.numeric(stats::filter(e, rho, "recursive"))
  x1 <- Zm[, 1] + (if (nz >= 2) 0.5 * Zm[, 2] else 0) + 0.5 * u + v
  y <- icpt + 2 * x1 + u * (1 + 0.5 * abs(Zm[, 1]))
  d <- data.frame(y = y, x = x1); for (j in 1:nz) d[[paste0("z", j)]] <- Zm[, j]
  zn <- paste(paste0("z", 1:nz), collapse = " + ")
  fx <- if (icpt == 1) y ~ x else y ~ x - 1
  fz <- as.formula(paste("~", zn, if (icpt == 1) "" else "- 1"))
  tn <- c("twoStep", "iterative", "cue")[type + 1]
  bwa <- if (bwmode == 0) bw else if (bwmode == 1) sandwich::bwAndrews else sandwich::bwNeweyWest
  vn <- c("iid", "MDS", "HAC")[vcov + 1]
  extra <- if (type == 2 && optim == 1) list(method = "BFGS") else list()
  g <- suppressWarnings(do.call(gmm, c(list(fx, fz, data = d, type = tn, vcov = vn, kernel = kn[kernel + 1], bw = bwa, prewhite = prewhite), extra)))
  p <- 1 + icpt
  hdr <- c(seed, n, nz, icpt, rho, type, vcov, kernel, bwmode, bw, prewhite, optim)
  st <- specTest(g)$test
  for (j in 1:p) add(c(0, j - 1, hdr, 0), unname(coef(g))[j], rel)
  for (i in 1:p) for (j in 1:p) add(c(1, (i - 1) * p + j - 1, hdr, 0), vcov(g)[i, j], rel)
  add(c(2, 0, hdr, 0), as.numeric(st[1, 1]), rel)
  if (g$df > 0) add(c(3, 0, hdr, 0), as.numeric(st[1, 2]), rel)
  if (vcov == 2 && g$df > 0) add(c(4, 0, hdr, 0), attr(g$w0, "Spec")$bw, rel)
  for (h in 0:(if (p == 2) 1 else 0)) {
    R <- if (h == 0) { if (p == 2) matrix(c(0, 1), 1) else matrix(1, 1, 1) } else diag(2)
    rhs <- if (h == 0) 1.95 else c(1.1, 2)
    wc <- unclass(linearHypothesis(g, R, rhs, test = "Chisq")); wf <- unclass(linearHypothesis(g, R, rhs, test = "F"))
    add(c(5, 0, hdr, h), wc$Chisq[2], rel); add(c(6, 0, hdr, h), wc[["Pr(>Chisq)"]][2], rel)
    add(c(7, 0, hdr, h), wf$F[2], rel); add(c(8, 0, hdr, h), wf[["Pr(>F)"]][2], rel)
  }
}
sd <- 20262100
nx <- function() { sd <<- sd + 1; sd }
# twoStep: iid and MDS, then the five kernels at fixed bandwidths, bwAndrews and bwNeweyWest, prewhite 0 and 1
dims <- list(c(150, 3, 1, 0.0), c(300, 2, 1, 0.4), c(220, 3, 0, 0.3), c(400, 4, 1, 0.6))
for (dm in dims) {
  run(nx(), dm[1], dm[2], dm[3], dm[4], 0, 0, 0, 0, 0, 0)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 0, 1, 0, 0, 0, 0)
  for (k in 0:4) for (pw in 0:1) {
    run(nx(), dm[1], dm[2], dm[3], dm[4], 0, 2, k, 0, c(4, 6)[pw + 1], pw)
    run(nx(), dm[1], dm[2], dm[3], dm[4], 0, 2, k, 1, 0, pw)
  }
  for (k in c(0, 2, 3)) for (pw in 0:1) run(nx(), dm[1], dm[2], dm[3], dm[4], 0, 2, k, 2, 0, pw)
}
# just identified
for (dm in list(c(200, 1, 1, 0.3), c(250, 1, 0, 0.5))) {
  run(nx(), dm[1], dm[2], dm[3], dm[4], 0, 0, 0, 0, 0, 0)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 0, 2, 2, 1, 0, 1)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 2, 1, 0, 0, 0, 0)
}
# iterated
for (dm in dims[1:3]) {
  run(nx(), dm[1], dm[2], dm[3], dm[4], 1, 0, 0, 0, 0, 0)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 1, 1, 0, 0, 0, 0)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 1, 2, 2, 0, 5, 0)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 1, 2, 0, 1, 0, 1)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 1, 2, 2, 1, 0, 0)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 1, 2, 3, 2, 0, 1)
}
# cue with Nelder-Mead and BFGS
for (dm in dims[1:3]) for (op in 0:1) {
  run(nx(), dm[1], dm[2], dm[3], dm[4], 2, 0, 0, 0, 0, 0, op)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 2, 1, 0, 0, 0, 0, op)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 2, 2, 2, 0, 5, 0, op)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 2, 2, 0, 1, 0, 1, op)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 2, 2, 2, 2, 0, 1, op)
  run(nx(), dm[1], dm[2], dm[3], dm[4], 2, 2, 3, 1, 0, 0, op)
}
emit("gmmpkg", c("gmm", "car"), list(cases))
