# BayesFactor: ttest.tstat, the JZS Bayes factor of a t statistic (log BF10). The package integrates to about 1e-8 relative error, (its own proportional error estimate reaches 3e-5), so the tolerance is 5e-5 absolute.
#   args: (t, n1, n2, rscale)   fn "logbf"; n2 = 0 is the one-sample test
suppressMessages(library(BayesFactor))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("logbf", args, want, rel = 1e-5, abs = 5e-5)
set.seed(20261223)
for (rep in 1:40) {
  n1 <- sample(6:60, 1); n2 <- if (rep %% 2 == 0) sample(6:60, 1) else 0; t <- round(rnorm(1) * 2.5, 3); rs <- c(0.5, 0.7071068, 1, 1.4142136)[rep %% 4 + 1]
  r <- if (n2 == 0) ttest.tstat(t = t, n1 = n1, rscale = rs) else ttest.tstat(t = t, n1 = n1, n2 = n2, rscale = rs)
  add(c(t, n1, n2, rs), as.numeric(r$bf))
}
emit("bayesfactor", "BayesFactor", list(cases))
