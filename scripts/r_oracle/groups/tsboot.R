# boot::tsboot with fixed and geometric blocks under set.seed.
#   args: (seed, sim 0 fixed 1 geom, endcorr, stat 0 mean 1 median 2 sd 3 var, R, l, n, x...)  fn "t0", "t" (position), "tsum"
suppressMessages(library(boot))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-10, abs = 1e-12)
fs <- list(function(d) mean(d), function(d) median(d), function(d) sd(d), function(d) var(d))
set.seed(20261118)
xs <- list(round(arima.sim(list(ar = 0.5), 40), 3), round(cumsum(rnorm(25)), 3), round(runif(60, 0, 10), 2), round(rnorm(17), 3))
for (x in xs) for (st in 0:3) for (R in c(19, 99)) for (sim in 0:1) for (ec in c(1, 0)) for (l in c(2, 3, 5, 8)) {
  if (sim == 1 && ec == 0) next
  seed <- sample(1:1e6, 1); set.seed(seed)
  b <- tryCatch(tsboot(x, fs[[st + 1]], R, l = l, sim = c("fixed", "geom")[sim + 1], endcorr = ec == 1), error = function(e) NULL)
  if (is.null(b)) next
  a <- c(seed, sim, ec, st, R, l, length(x), x)
  add("t0", a, b$t0)
  for (i in c(1, 2, R %/% 2, R)) add("t", c(a, i - 1), b$t[i, 1])
  add("tsum", a, sum(b$t))
}
emit("tsboot", "boot", list(cases))
