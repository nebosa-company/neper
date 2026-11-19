# EnvStats: tolIntNorm and predIntNorm on data. Args: (fam 0 tolIntNorm 1 predIntNorm, type 0 two-sided 1 lower 2 upper, a, b, c, what 0 lower limit 1 upper limit, x[n]): for tolIntNorm
# a = coverage, b = confidence, c = cov.type (0 content 1 expectation); for predIntNorm a = k, b = n.mean, c = confidence.
suppressMessages(library(EnvStats))
cases <- list()
set.seed(20262338)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("ti", args, want, rel = 1e-7, abs = 1e-9)
ty <- c("two-sided", "lower", "upper")
for (rep in 1:50) {
  fam <- (rep - 1) %% 2; t <- sample(0:2, 1); n <- sample(8:40, 1); x <- round(rnorm(n, 10, 2), 4)
  if (fam == 0) {
    cv <- sample(c(0.8, 0.9, 0.95), 1); cf <- sample(c(0.9, 0.95), 1); ct <- sample(0:1, 1)
    if (ct == 0 && t == 0) next
    r <- tolIntNorm(x, coverage = cv, conf.level = cf, ti.type = ty[t + 1], cov.type = c("content", "expectation")[ct + 1]); lim <- unname(r$interval$limits)
    for (w in 0:1) add(c(0, t, cv, cf, ct, w, x), lim[w + 1])
  } else {
    k <- sample(1:3, 1); nm <- sample(1:4, 1); cf <- sample(c(0.9, 0.95), 1)
    r <- predIntNorm(x, k = k, n.mean = nm, conf.level = cf, pi.type = ty[t + 1]); lim <- unname(r$interval$limits)
    for (w in 0:1) add(c(1, t, k, nm, cf, w, x), lim[w + 1])
  }
}
emit("envstats_int", "EnvStats", list(cases))
