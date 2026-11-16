# fitdistrplus: maximum-likelihood fits (norm, lnorm, exp, gamma, weibull) and gofstat.
#   args: (kind, n, x...)   kind 0 norm 1 lnorm 2 exp 3 gamma 4 weibull; fn "p1" "p2" (estimates; p2 absent for exp) "ll" "aic" "bic" "ks" "cvm" "ad"
#   gamma and weibull come from optim (reltol 1e-8) in the package, so their parameters and statistics are compared at 2e-3, the likelihood summaries at 1e-6
suppressMessages(library(fitdistrplus))
cases <- list()
add <- function(fn, args, want, rel = 1e-6) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-8)
set.seed(20261232 %% 100000)
nm <- c("norm", "lnorm", "exp", "gamma", "weibull")
for (rep in 1:30) {
  kind <- (rep - 1) %% 5; n <- sample(20:80, 1); x <- round(rlnorm(n, 1, 0.5), 4)
  f <- suppressWarnings(fitdist(x, nm[kind + 1])); g <- suppressWarnings(gofstat(f)); a <- c(kind, n, x); tl <- if (kind >= 3) 2e-3 else 1e-6
  add("p1", a, as.numeric(f$estimate[1]), tl); if (kind != 2) add("p2", a, as.numeric(f$estimate[2]), tl)
  add("ll", a, f$loglik, 1e-6); add("aic", a, f$aic, 1e-6); add("bic", a, f$bic, 1e-6)
  add("ks", a, as.numeric(g$ks), tl); add("cvm", a, as.numeric(g$cvm), tl); add("ad", a, as.numeric(g$ad), tl)
}
emit("fitdist", "fitdistrplus", list(cases))
