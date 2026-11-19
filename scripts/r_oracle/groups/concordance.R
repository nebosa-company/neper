# survival::concordance(Surv(time, status) ~ x): "conc" args (n, time[n], status[n], x[n], k) k 0 concordant, 1 discordant, 2 tied in x, 3 tied in time with different x, 4 tied in both, 5 the concordance; times with ties and censoring
suppressMessages(library(survival))
cases <- list()
set.seed(20271220)
for (rep in 1:25) {
  n <- sample(30:120, 1); x <- if (rep %% 3 == 0) sample(1:4, n, TRUE) else round(rnorm(n), 2)
  time <- if (rep %% 2 == 0) sample(1:20, n, TRUE) else round(rexp(n, exp(0.3 * x)), 3); status <- rbinom(n, 1, 0.7)
  cc <- concordance(Surv(time, status) ~ x)
  v <- c(cc$count[["concordant"]], cc$count[["discordant"]], cc$count[["tied.x"]], cc$count[["tied.y"]], cc$count[["tied.xy"]], cc$concordance)
  for (k in 1:6) cases[[length(cases) + 1]] <- case("conc", c(n, time, status, x, k - 1), as.numeric(v[k]), rel = 1e-9, abs = 1e-9)
}
emit("concordance", "survival", list(cases))
