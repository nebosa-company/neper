# fitdistrplus: closed-form maximum-likelihood fits (norm, lnorm, exp) and gofstat.
#   args: (kind, n, x...)   kind 0 norm 1 lnorm 2 exp; fn "p1" "p2" (estimates; p2 absent for exp) "ll" "aic" "bic" "ks" "cvm" "ad"
suppressMessages(library(fitdistrplus))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-8)
set.seed(20261232 %% 100000)
nm <- c("norm", "lnorm", "exp")
for (rep in 1:18) {
  kind <- (rep - 1) %% 3; n <- sample(15:60, 1); x <- round(rlnorm(n, 1, 0.5), 4)
  f <- suppressWarnings(fitdist(x, nm[kind + 1])); g <- suppressWarnings(gofstat(f)); a <- c(kind, n, x)
  add("p1", a, as.numeric(f$estimate[1])); if (kind < 2) add("p2", a, as.numeric(f$estimate[2]))
  add("ll", a, f$loglik); add("aic", a, f$aic); add("bic", a, f$bic)
  add("ks", a, as.numeric(g$ks)); add("cvm", a, as.numeric(g$cvm)); add("ad", a, as.numeric(g$ad))
}
emit("fitdist", "fitdistrplus", list(cases))
