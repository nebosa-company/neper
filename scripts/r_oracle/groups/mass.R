# MASS: mad, huber, hubers, fitdistr (normal, exponential, poisson, geometric, log-normal), boxcox log-likelihood, bandwidth.nrd.
#   args: (n, x..., p1, p2)   fn "mad" "bw" (no extra); "huber_mu" "huber_s" "hubers_mu" "hubers_s" (p1 = k); "fd" (p1 = family 0..4, p2 = quantity 0 est1 1 est2 2 se1 3 se2 4 loglik)
#   "boxcox": (n, y..., x1..., lambda): the log-likelihood with a design of an intercept and one covariate
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261115)
for (rep in 1:10) {
  n <- sample(10:40, 1); x <- round(c(rnorm(n - 2, 5, 2), 20, -9) + 0, 3); x2 <- round(rexp(n, 0.4) + 0.1, 3)
  add("mad", c(n, x, 0, 0), mad(x)); add("bw", c(n, x, 0, 0), bandwidth.nrd(x))
  for (k in c(1, 1.5, 2)) {
    add("huber_mu", c(n, x, k, 0), huber(x, k)$mu); add("huber_s", c(n, x, k, 0), huber(x, k)$s)
    h <- hubers(x, k); add("hubers_mu", c(n, x, k, 0), h$mu); add("hubers_s", c(n, x, k, 0), h$s)
  }
  for (fam in 0:4) {
    d <- switch(fam + 1, x, x2, rpois(n, 3), rgeom(n, 0.3), x2)
    f <- suppressWarnings(fitdistr(d, c("normal", "exponential", "poisson", "geometric", "log-normal")[fam + 1]))
    est <- unname(f$estimate); se <- unname(f$sd)
    add("fd", c(n, d, fam, 0), est[1]); add("fd", c(n, d, fam, 2), se[1]); add("fd", c(n, d, fam, 4), f$loglik)
    if (length(est) > 1) { add("fd", c(n, d, fam, 1), est[2]); add("fd", c(n, d, fam, 3), se[2]) }
  }
  y <- round(x2 * 2 + rexp(n), 3); cv <- round(rnorm(n), 3)
  lm0 <- lm(y ~ cv, y = TRUE, qr = TRUE)
  for (lam in c(-1, -0.5, 0, 0.01, 0.3, 1, 2)) add("boxcox", c(n, y, cv, lam), boxcox(lm0, lambda = lam, plotit = FALSE)$y)
}
emit("mass", "MASS", list(cases))
