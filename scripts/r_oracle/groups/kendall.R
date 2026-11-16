# Kendall::Kendall and MannKendall (single precision in the package): tau, sl, S, D, varS.
#   args: (kind 0 Kendall 1 MannKendall, n, x[n], y[n], q)  fn "k" q 0 tau 1 sl 2 S 3 D 4 varS  (MannKendall passes y = 1:n); "ks": (freq, n, x[n], q) SeasonalMannKendall
suppressMessages(library(Kendall))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 2e-6, abs = 1e-7)
set.seed(20261116)
for (rep in 1:60) {
  n <- sample(6:80, 1)
  x <- round(rnorm(n), if (rep %% 2 == 0) 1 else 4); y <- round(0.4 * x + rnorm(n), if (rep %% 3 == 0) 1 else 4)
  for (kind in 0:1) {
    r <- if (kind == 0) Kendall(x, y) else MannKendall(x)
    yy <- if (kind == 0) y else seq_len(n)
    vals <- c(r$tau, r$sl, r$S, r$D, r$varS)
    for (q in 1:5) add("k", c(kind, n, x, yy, q - 1), as.numeric(vals[q]))
  }
}
for (rep in 1:30) {
  fr <- sample(c(4, 7, 12), 1); n <- fr * sample(5:12, 1); x <- round(cumsum(rnorm(n)) + sin(seq_len(n) * 2 * pi / fr), 3)
  r <- SeasonalMannKendall(ts(x, frequency = fr))
  vals <- c(r$tau, r$sl, r$S, r$D, r$varS)
  for (q in 1:5) add("ks", c(fr, n, x, q - 1), as.numeric(vals[q]))
}
emit("kendall", "Kendall", list(cases))
