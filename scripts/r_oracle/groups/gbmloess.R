# stats::loess with one predictor: the fitted values.
#   args: (seed, n, span, enp, degree, mode, i)   enp > 0 gives enp.target (span unused); mode 0: x = round(rnorm(n), 3), mode 1: x = 1:n
r3 <- function(x, d = 3) floor(x * 10^d + 0.5) / 10^d
cases <- list()
set.seed(1)
cfgs <- list()
for (k in 1:40) cfgs[[k]] <- list(seed = 500 + k, n = sample(c(20, 33, 50, 80, 120, 200, 400), 1), span = c(0.3, 0.5, 0.75, 0.9)[k %% 4 + 1], enp = if (k %% 3 == 0) c(4, 6, 10, 20)[k %% 4 + 1] else 0, degree = c(2, 2, 1, 2, 0)[k %% 5 + 1], mode = k %% 2)
for (cf in cfgs) {
  set.seed(cf$seed)
  x <- if (cf$mode == 0) r3(rnorm(cf$n)) else as.numeric(seq_len(cf$n))
  y <- sin(x / (if (cf$mode == 0) 1 else cf$n / 6)) + rnorm(cf$n) * 0.4
  f <- suppressWarnings(if (cf$enp > 0) loess(y ~ x, enp.target = cf$enp, degree = cf$degree) else loess(y ~ x, span = cf$span, degree = cf$degree))
  for (i in unique(c(1, 2, cf$n %/% 3, cf$n %/% 2, cf$n - 1, cf$n)))
    cases[[length(cases) + 1]] <- case("loess", c(cf$seed, cf$n, cf$span, cf$enp, cf$degree, cf$mode, i - 1), f$fitted[i], rel = 1e-9, abs = 1e-11)
}
emit("gbmloess", character(), list(cases))
