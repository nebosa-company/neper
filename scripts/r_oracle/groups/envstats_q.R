# EnvStats: eqnorm and eqlnorm with confidence intervals for the quantile. Args: (fam 0 eqnorm 1 eqlnorm, ci_type 0 two-sided 1 lower 2 upper, p, conf, what 0 quantile 1 LCL 2 UCL, x[n]).
suppressMessages(library(EnvStats))
cases <- list()
set.seed(20262337)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("eq", args, want, rel = 1e-8, abs = 1e-10)
ty <- c("two-sided", "lower", "upper")
for (rep in 1:40) {
  fam <- (rep - 1) %% 2; t <- sample(0:2, 1); p <- sample(c(0.1, 0.5, 0.9, 0.95), 1); cl <- sample(c(0.9, 0.95), 1); n <- sample(10:40, 1)
  x <- if (fam == 0) round(rnorm(n, 10, 3), 4) else round(rlnorm(n, 1, 0.5), 4)
  e <- if (fam == 0) eqnorm(x, p = p, ci = TRUE, ci.type = ty[t + 1], conf.level = cl) else eqlnorm(x, p = p, ci = TRUE, ci.type = ty[t + 1], conf.level = cl)
  lim <- unname(e$interval$limits); q <- unname(e$quantiles)
  add(c(fam, t, p, cl, 0, x), q[1]); add(c(fam, t, p, cl, 1, x), lim[1]); add(c(fam, t, p, cl, 2, x), lim[2])
}
emit("envstats_q", "EnvStats", list(cases))
