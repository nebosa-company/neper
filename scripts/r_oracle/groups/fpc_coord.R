# fpc: adcoord, mvdcoord, awcoord (method "classical") and ancoord (method "classical"), signs included.
#   "co": (fn, what, idx, n, p, K, nn, flag1, flag2, alpha, x n by p row-major, lab[n], cov p by p row-major when fn = 2 and flag1 = 1)
#   fn 1 adcoord, 2 mvdcoord (flag1 1: sphere = the given covariance matrix), 3 awcoord (flag1 1: mahal "md"; flag2 1: clweight), 4 ancoord;
#   lab is the 0/1 class indicator, for mvdcoord the labels 1..K; what 0 ev[idx], 1 units[idx] (row-major), 3 sum of (row + 1) * proj[row, idx], 4 sum of (i + 1) * wg[i]
suppressMessages(library(fpc))
cases <- list()
set.seed(20269931)
flat <- function(m) as.vector(t(unclass(m)))
tol <- list(rel = 1e-9, abs = 1e-10)
emitfn <- function(fn, n, p, K, nn, f1, f2, alpha, x, lab, cvm, r) {
  hdr <- function(w, i) c(fn, w, i, n, p, K, nn, f1, f2, alpha, flat(x), lab, if (!is.null(cvm)) flat(cvm))
  add <- function(w, i, v) cases[[length(cases) + 1]] <<- case("co", hdr(w, i), v, rel = tol$rel, abs = tol$abs)
  for (i in seq_len(p)) add(0, i - 1, r$ev[i])
  for (rr in seq_len(p)) for (cc in seq_len(p)) add(1, (rr - 1) * p + cc - 1, r$units[rr, cc])
  for (cc in seq_len(p)) add(3, cc - 1, sum(seq_len(n) * r$proj[, cc]))
  if (!is.null(r$wg)) add(4, 0, sum(seq_along(r$wg) * r$wg))
}
for (rep in 1:8) {
  p <- c(2, 3, 4)[rep %% 3 + 1]; n <- sample(36:60, 1)
  ci <- c(rep(1, sample(12:20, 1)), rep(0, n))[1:n]; ci[1:2] <- 1; ci[3:4] <- 0
  x <- matrix(rnorm(n * p), n, p) + outer(ci, seq_len(p)) * 0.8 + matrix(rnorm(p * p), p, p)[sample(p, n, TRUE), ] * 0.3
  x <- round(x, 4)
  # adcoord
  emitfn(1, n, p, 2, 0, 0, 0, 0, x, ci, NULL, adcoord(x, ci, clnum = 1))
  # awcoord
  md <- rep %% 2; cw <- (rep %/% 2) %% 2
  r <- awcoord(x, ci, clnum = 1, mahal = c("square", "md")[md + 1], method = "classical", clweight = cw == 1, alpha = 0.95, countmode = 100000)
  emitfn(3, n, p, 2, 0, md, cw, 0.95, x, ci, NULL, r)
  # ancoord
  nn <- c(10, 14, 18)[rep %% 3 + 1]
  emitfn(4, n, p, 2, nn, 0, 0, 0, x, ci, NULL, ancoord(x, ci, clnum = 1, nn = nn, method = "classical", countmode = 100000))
  # mvdcoord
  K <- sample(2:3, 1); lab <- sample(rep(1:K, length.out = n)); lab[1:K] <- 1:K
  x2 <- round(matrix(rnorm(n * p), n, p) + outer(lab, seq_len(p)) * 0.7, 4)
  sph <- rep %% 2
  cvm <- if (sph == 1) cov(x2) else NULL
  r <- mvdcoord(x2, lab, sphere = if (sph == 1) cvm else "none")
  emitfn(2, n, p, K, 0, sph, 0, 0, x2, lab, cvm, r)
}
emit("fpc_coord", "fpc", list(cases))
