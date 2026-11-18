# psych: alpha, KMO, cortest.bartlett, ICC (six forms), cohen.kappa, mardia.
#   data: (n, p, X[n*p] column-major, q); fn "alpha_raw" "alpha_std" "kmo" (overall) "kmo_i" (item q) "bart_chi" "bart_df" "icc1".."icc6" "mardia_b1" "mardia_b2"
#   kappa: (k, table[k*k] row-major)  fn "kappa"
suppressMessages(library(psych))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261116)
for (rep in 1:12) {
  n <- sample(30:80, 1); p <- sample(3:6, 1)
  f <- rnorm(n); X <- sapply(1:p, function(j) round(f * runif(1, 0.5, 1.5) + rnorm(n), 3))
  a <- c(n, p, X)
  al <- suppressWarnings(alpha(X, check.keys = FALSE))$total
  add("alpha_raw", c(a, 0), al$raw_alpha); add("alpha_std", c(a, 0), al$std.alpha)
  R <- cor(X)
  add("kmo", c(a, 0), KMO(R)$MSA)
  for (q in 1:p) add("kmo_i", c(a, q - 1), KMO(R)$MSAi[q])
  b <- cortest.bartlett(R, n = n)
  add("bart_chi", c(a, 0), b$chisq); add("bart_df", c(a, 0), b$df)
  ic <- suppressWarnings(ICC(X)$results$ICC[1:6])
  for (q in 1:6) cases[[length(cases) + 1]] <- case(paste0("icc", q), c(a, 0), ic[q], rel = 1e-5, abs = 1e-7)
  pp <- min(p, 3)
  m <- mardia(X[, 1:pp], plot = FALSE)
  add("mardia_b1", c(n, pp, X[, 1:pp], 0), m$b1p); add("mardia_b2", c(n, pp, X[, 1:pp], 0), m$b2p)
}
for (rep in 1:8) {
  k <- sample(2:4, 1); tb <- matrix(rpois(k * k, 6) + diag(k) * 10, k, k)
  add("kappa", c(k, t(tb)), cohen.kappa(tb)$kappa)
}
# describe of one column ("desc": n, x..., which): n mean sd median trimmed mad min max range skew kurtosis se
for (rep in 1:25) {
  n <- sample(10:80, 1); x <- round(rexp(n, 0.2) + rnorm(n), 3)
  ds <- describe(x)
  v <- c(ds$n, ds$mean, ds$sd, ds$median, ds$trimmed, ds$mad, ds$min, ds$max, ds$range, ds$skew, ds$kurtosis, ds$se)
  for (w in 0:11) cases[[length(cases) + 1]] <- case("desc", c(n, x, w), as.numeric(v[w + 1]), rel = 1e-8, abs = 1e-10)
}
# corr.test: "ctest" args (n, p, X column-major, i, j, which) with i < j 0-based; which 0 r, 1 t, 2 p, 3 lower, 4 upper, 5 Holm-adjusted p
for (rep in 1:15) {
  n <- sample(20:60, 1); p <- sample(3:5, 1); f <- rnorm(n); X <- sapply(1:p, function(j) round(f * runif(1, 0, 1) + rnorm(n), 3)); colnames(X) <- paste0("v", 1:p)
  ct <- corr.test(X, adjust = "holm"); ci <- ct$ci2
  rn <- rownames(ci); r0 <- 0
  for (u in 1:(p - 1)) for (v in (u + 1):p) {
    r0 <- r0 + 1; base <- c(n, p, X, u - 1, v - 1)
    vals <- c(ct$r[u, v], ct$r[u, v] * sqrt((n - 2) / (1 - ct$r[u, v]^2)), 2 * pt(-abs(ct$r[u, v] * sqrt((n - 2) / (1 - ct$r[u, v]^2))), n - 2), ci$lower[r0], ci$upper[r0], ci$p.adj[r0])
    for (w in 0:5) cases[[length(cases) + 1]] <- case("ctest", c(base, w), as.numeric(vals[w + 1]), rel = 1e-8, abs = 1e-10)
  }
}
emit("psych", "psych", list(cases))
