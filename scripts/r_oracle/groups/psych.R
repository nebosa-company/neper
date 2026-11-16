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
emit("psych", "psych", list(cases))
