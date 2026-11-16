# boot: balanced and parametric bootstrap under set.seed; the replicates and boot.ci norm, basic, perc (and bca for balanced).
#   args: (seed, sim 0 balanced 1 parametric, stat 0 mean 1 median 2 sd 3 var, R, conf, n, x...)  parametric appends mle (mu, sd)
#   fn "t0", "t" (position), "tsum", "ci_<norm|basic|perc|bca>_<lo|hi>"
library(boot)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-10, abs = 1e-12)
fs <- list(function(d, i) mean(d[i]), function(d, i) median(d[i]), function(d, i) sd(d[i]), function(d, i) var(d[i]))
fp <- list(function(d) mean(d), function(d) median(d), function(d) sd(d), function(d) var(d))
set.seed(20261116)
xs <- list(round(rnorm(25, 10, 3), 3), round(rexp(18) * 4, 3), round(runif(40, 0, 50), 2))
for (x in xs) for (st in 0:3) for (R in c(19, 99, 249)) for (sim in 0:1) {
  conf <- 0.95; seed <- sample(1:1e6, 1); set.seed(seed)
  if (sim == 0) b <- boot(x, fs[[st + 1]], R, sim = "balanced")
  else b <- boot(x, fp[[st + 1]], R, sim = "parametric", ran.gen = function(d, p) rnorm(length(d), p[1], p[2]), mle = c(mean(x), sd(x)))
  a <- c(seed, sim, st, R, conf, length(x), x, if (sim == 1) c(mean(x), sd(x)))
  add("t0", a, b$t0)
  for (i in c(1, 2, R %/% 2, R)) add("t", c(a, i - 1), b$t[i, 1])
  add("tsum", a, sum(b$t))
  types <- if (sim == 0) c("norm", "basic", "perc", "bca") else c("norm", "basic", "perc")
  ci <- tryCatch(suppressWarnings(boot.ci(b, conf = conf, type = types)), error = function(e) NULL)
  if (is.null(ci)) next
  add("ci_norm_lo", a, ci$normal[2]); add("ci_norm_hi", a, ci$normal[3])
  add("ci_basic_lo", a, ci$basic[4]); add("ci_basic_hi", a, ci$basic[5])
  add("ci_perc_lo", a, ci$percent[4]); add("ci_perc_hi", a, ci$percent[5])
  if (sim == 0) { add("ci_bca_lo", a, ci$bca[4]); add("ci_bca_hi", a, ci$bca[5]) }
}
emit("boot2", "boot", list(cases))
