# EnvStats: enorm, eexp and epois with confidence intervals. Args: (fam 0 enorm mean CI 1 enorm variance CI 2 eexp 3 epois, ci_type 0 two-sided 1 lower 2 upper, conf, what, x[n]):
# what 0 the first parameter (mean, rate or lambda), 1 the sd (enorm only), 2 LCL, 3 UCL (infinite limits compare as infinities).
suppressMessages(library(EnvStats))
cases <- list()
set.seed(20262334)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("es", args, want, rel = 1e-9, abs = 1e-12)
ty <- c("two-sided", "lower", "upper")
for (rep in 1:60) {
  fam <- (rep - 1) %% 4; t <- sample(0:2, 1); cl <- sample(c(0.9, 0.95, 0.99), 1); n <- sample(8:40, 1)
  x <- if (fam < 2) round(rnorm(n, 5, 2), 4) else if (fam == 2) round(rexp(n, 0.5), 4) else rpois(n, 3)
  if (fam == 3 && sum(x) == 0) next
  e <- switch(fam + 1, enorm(x, ci = TRUE, ci.type = ty[t + 1], conf.level = cl), enorm(x, ci = TRUE, ci.param = "variance", ci.type = ty[t + 1], conf.level = cl),
              eexp(x, ci = TRUE, ci.type = ty[t + 1], conf.level = cl), epois(x, ci = TRUE, ci.type = ty[t + 1], conf.level = cl))
  lim <- unname(e$interval$limits); p <- unname(e$parameters)
  base <- function(w) c(fam, t, cl, w, x)
  add(base(0), p[1]); if (fam < 2) add(base(1), p[2]); add(base(2), lim[1]); add(base(3), lim[2])
}
emit("envstats_est", "EnvStats", list(cases))
