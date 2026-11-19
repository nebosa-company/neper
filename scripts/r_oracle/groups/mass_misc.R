# MASS corresp, mca, .rat (fractions / rational), the numerics of truehist, and hubers with mu or s given.
#   "corresp" (nr, nc, nf, mode 0 cor 1 rscore 2 cscore, X[nr nc] col-major counts)
#   "mca"     (n, p, nf, mode 0 d 1 rs 2 cs 3 fs, levels[p], codes[n p] col-major, 0-based)
#   "rat"     (cycles, max.denominator, mode 0 numerators 1 denominators, n, x[n])   position-weighted sums
#   "th"      (mode 0 Scott 1 FD 2 nbins, nbins, h (0 missing), x0 (1e300 missing), what 0 breaks 1 heights 2 number of breaks, n, data[n])
#   "hs"      (k, mu (1e300 missing), s (1e300 missing), initmu (1e300 missing), tol, mode 0 mu 1 s, n, y[n])
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(seq_along(v) * as.numeric(v))
set.seed(20262405)
for (rep in 1:25) {
  nr <- sample(3:7, 1); nc <- sample(3:6, 1); X <- matrix(rpois(nr * nc, 8) + 1, nr, nc)
  nf <- sample(1:(min(nr, nc) - 1), 1)
  r <- corresp(X, nf = nf)
  a <- c(nr, nc, nf)
  add("corresp", c(a, 0, X), wsum(r$cor)); add("corresp", c(a, 1, X), wsum(r$rscore)); add("corresp", c(a, 2, X), wsum(r$cscore))
}
for (rep in 1:20) {
  n <- sample(c(15, 30, 60), 1); p <- sample(2:4, 1); lv <- sample(2:4, p, replace = TRUE)
  codes <- sapply(lv, function(L) sample(c(0:(L - 1), sample(0:(L - 1), n - L, TRUE))))
  df <- as.data.frame(lapply(seq_len(p), function(j) factor(codes[, j], levels = 0:(lv[j] - 1)))); names(df) <- paste0("V", seq_len(p))
  nf <- 2; m <- mca(df, nf = nf)
  a <- c(n, p, nf)
  add("mca", c(a, 0, lv, codes), wsum(m$d), 1e-8); add("mca", c(a, 1, lv, codes), wsum(m$rs), 1e-8); add("mca", c(a, 2, lv, codes), wsum(m$cs), 1e-8); add("mca", c(a, 3, lv, codes), wsum(m$fs), 1e-8)
}
for (rep in 1:20) {
  n <- 12; x <- c(round(runif(n, -5, 5), sample(1:4, 1)), pi, exp(1), 1 / 3, sqrt(2), 0.5)[1:(n + 5)]
  cyc <- sample(c(3, 5, 10), 1); md <- sample(c(10, 100, 2000), 1)
  r <- MASS:::.rat(x, cyc, md)$rat; a <- c(cyc, md)
  add("rat", c(a, 0, length(x), x), wsum(r[, 1]), 1e-12); add("rat", c(a, 1, length(x), x), wsum(r[, 2]), 1e-12)
}
for (rep in 1:30) {
  n <- sample(c(20, 50, 120), 1); data <- switch(rep %% 3 + 1, rnorm(n), rexp(n), runif(n, 2, 9)); data <- round(data, 3)
  mode <- rep %% 3; nb <- if (mode == 2) sample(4:15, 1) else 0; h <- if (rep %% 5 == 0) 0.4 else 0; x0 <- if (rep %% 4 == 0) 0.05 else 1e300
  hh <- h; nbins <- nb
  if (hh == 0) {
    if (mode == 0) nbins <- nclass.scott(data) else if (mode == 1) nbins <- nclass.FD(data)
    hh <- diff(pretty(data, nbins))[1L]
  }
  xx <- if (x0 == 1e300) -hh / 1000 else x0
  first <- floor((min(data) - xx) / hh); last <- ceiling((max(data) - xx) / hh); br <- xx + hh * c(first:last)
  bin <- cut(data, br, include.lowest = TRUE); est <- tabulate(bin, length(levels(bin))) / (diff(br) * length(data))
  a <- c(mode, nb, h, x0)
  add("th", c(a, 0, n, data), wsum(br)); add("th", c(a, 1, n, data), wsum(est)); add("th", c(a, 2, n, data), length(br), 0, 0)
}
for (rep in 1:30) {
  n <- sample(10:40, 1); y <- round(c(rnorm(n - 2, 5, 2), 25, -12), 3); k <- c(1, 1.5, 2)[rep %% 3 + 1]
  mu <- if (rep %% 3 == 1) round(runif(1, 3, 7), 2) else NULL; s <- if (rep %% 3 == 2) round(runif(1, 1, 3), 2) else NULL
  im <- if (rep %% 4 == 0) 4.5 else NULL
  args <- list(y, k = k, tol = 1e-8); if (!is.null(mu)) args$mu <- mu; if (!is.null(s)) args$s <- s; if (!is.null(im)) args$initmu <- im
  h <- do.call(hubers, args)
  a <- c(k, if (is.null(mu)) 1e300 else mu, if (is.null(s)) 1e300 else s, if (is.null(im)) 1e300 else im, 1e-8)
  add("hs", c(a, 0, n, y), h$mu, 1e-9); add("hs", c(a, 1, n, y), h$s, 1e-9)
}
emit("mass_misc", "MASS", list(cases))
