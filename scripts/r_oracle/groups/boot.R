# boot: ordinary bootstrap of the mean, median, sd and variance; boot.ci norm, basic, perc and bca.
#   args: (seed, stat 0 mean 1 median 2 sd 3 var, R, conf, n, x...)
#   fn "t0", "t" (position), "ci_norm_lo/hi", "ci_basic_lo/hi", "ci_perc_lo/hi", "ci_bca_lo/hi"
library(boot)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-10, abs = 1e-12)
fs <- list(function(d, i) mean(d[i]), function(d, i) median(d[i]), function(d, i) sd(d[i]), function(d, i) var(d[i]))
set.seed(20261115)
xs <- list(round(rnorm(25, 10, 3), 3), round(rexp(18) * 4, 3), round(runif(40, 0, 50), 2), round(rlnorm(12), 3))
for (x in xs) for (st in 0:3) for (R in c(19, 99, 399)) for (conf in c(0.9, 0.95)) {
  seed <- sample(1:1e6, 1)
  set.seed(seed)
  b <- boot(x, fs[[st + 1]], R)
  a <- c(seed, st, R, conf, length(x), x)
  add("t0", a, b$t0)
  for (i in c(1, 2, R %/% 2, R)) add("t", c(a, i - 1), b$t[i, 1])
  add("tsum", a, sum(b$t))
  ci <- tryCatch(suppressWarnings(boot.ci(b, conf = conf, type = c("norm", "basic", "perc", "bca"))), error = function(e) NULL)
  if (is.null(ci)) next
  add("ci_norm_lo", a, ci$normal[2]); add("ci_norm_hi", a, ci$normal[3])
  add("ci_basic_lo", a, ci$basic[4]); add("ci_basic_hi", a, ci$basic[5])
  add("ci_perc_lo", a, ci$percent[4]); add("ci_perc_hi", a, ci$percent[5])
  add("ci_bca_lo", a, ci$bca[4]); add("ci_bca_hi", a, ci$bca[5])
}
emit("boot", "boot", list(cases))
