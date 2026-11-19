# fpc::discrproj (the data behind plotcluster) with the methods dc, mvdc, adc, awc, nc, wnc and anc, with and without ignorepoints.
#   "dp": (method, what, idx, n, p, K, clnum, ignore, nn, md, clweight, alpha, sphere, x n by p row-major, lab[n] (labels 1..K, 0 ignored), cov p by p when sphere = 1)
#   method 1 dc, 2 mvdc, 3 adc, 4 awc (classical), 5 nc, 6 wnc; what 0 ev[idx], 1 units[idx] (row-major), 3 sum (row + 1) * proj[row, idx]
suppressMessages(library(fpc))
cases <- list()
set.seed(20269971)
flat <- function(m) as.vector(t(unclass(m)))
for (rep in 1:24) {
  meth <- (rep - 1) %% 6 + 1; ign <- (rep - 1) %/% 6 %% 2 >= 1; p <- c(2, 3, 4)[rep %% 3 + 1]; n <- sample(40:60, 1); K <- if (meth == 3 || meth == 4) 2 else sample(2:3, 1)
  lab <- sample(rep(1:K, length.out = n)); lab[1:K] <- 1:K
  x <- round(matrix(rnorm(n * p), n, p) + outer(lab, seq_len(p)) * 0.7, 4)
  ignored <- integer(0)
  if (ign) { ignored <- seq(K + 1, n, by = 5); lab[ignored] <- 0 }
  nn <- c(10, 14, 18)[rep %% 3 + 1]; md <- rep %% 2; cw <- (rep %/% 2) %% 2; sph <- (rep %% 2 == 1) && meth %in% c(2, 5, 6)
  cvm <- if (sph) cov(x[lab != 0, ]) else NULL
  sp <- if (sph) cvm else "none"
  r <- switch(meth,
    discrproj(x, lab, "dc", ignorepoints = ign),
    discrproj(x, lab, "mvdc", clnum = 1, ignorepoints = ign, sphere = sp),
    discrproj(x, lab, "adc", clnum = 1, ignorepoints = ign),
    discrproj(x, lab, "awc", clnum = 1, ignorepoints = ign, mahal = c("square", "md")[md + 1], clweight = cw == 1, alpha = 0.95, countmode = 100000),
    discrproj(x, lab, "nc", ignorepoints = ign, nn = nn, sphere = sp, countmode = 100000),
    discrproj(x, lab, "wnc", ignorepoints = ign, nn = nn, sphere = sp, countmode = 100000))
  hdr <- function(w, i) c(meth, w, i, n, p, K, 1, as.numeric(ign), nn, md, cw, 0.95, as.numeric(sph), flat(x), lab, if (sph) flat(cvm))
  add <- function(w, i, v) cases[[length(cases) + 1]] <<- case("dp", hdr(w, i), v, rel = 1e-9, abs = 1e-10)
  na <- if (meth %in% c(1, 5, 6)) K - 1 else p
  for (i in seq_len(na)) add(0, i - 1, r$ev[i])
  for (rr in seq_len(p)) for (cc in seq_len(na)) add(1, (rr - 1) * p + cc - 1, r$units[rr, cc])
  for (cc in seq_len(na)) add(3, cc - 1, sum(seq_len(n) * r$proj[, cc]))
}
emit("fpc_proj", "fpc", list(cases))
