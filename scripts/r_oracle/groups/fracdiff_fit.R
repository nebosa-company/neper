# fracdiff(x, nar, nma): the Haslett-Raftery fit with default start values.
#   args: (n, p, q, M, x[n], what) what 0 d, 1 log.likelihood, 2 fnormMin, 3 sigma, 4..3+p ar, then ma
suppressMessages(library(fracdiff))
cases <- list()
add <- function(args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("fracdiff_fit", args, want, rel = 1e-6, abs = 1e-8)
set.seed(20261122)
for (rep in 1:24) {
  n <- sample(c(60, 100, 150, 250), 1)
  p <- sample(0:2, 1); q <- sample(0:1, 1)
  x <- if (rep %% 3 == 0) fracdiff.sim(n, ar = if (p) 0.3 else NULL, ma = if (q) -0.4 else NULL, d = 0.3)$series else as.numeric(arima.sim(list(ar = 0.5), n))
  x <- round(x, 5)
  M <- sample(c(100, 30), 1)
  r <- tryCatch(suppressWarnings(fracdiff(x, nar = p, nma = q, M = M)), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, p, q, M, x)
  add(c(a, 0), r$d); add(c(a, 1), r$log.likelihood); add(c(a, 2), r$fnormMin); add(c(a, 3), r$sigma)
  for (j in seq_len(p)) add(c(a, 3 + j), r$ar[j])
  for (j in seq_len(q)) add(c(a, 3 + p + j), r$ma[j])
}
emit("fracdiff_fit", "fracdiff", list(cases))
