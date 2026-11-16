# copula bivariate Archimedean copulas: density, distribution and Kendall's tau.
#   args: (family 0 clayton 1 frank 2 gumbel 3 amh 4 joe, theta, u, v)
#   fn "d" "p" "tau"
suppressMessages(library(copula))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-9)
set.seed(20261230)
for (rep in 1:60) {
  fam <- (rep - 1) %% 5
  th <- switch(fam + 1, runif(1, 0.1, 6), runif(1, 0.3, 10) * sample(c(-1, 1), 1), 1 + runif(1, 0.1, 5), runif(1, -0.95, 0.95), 1 + runif(1, 0.1, 5))
  cop <- switch(fam + 1, claytonCopula(th), frankCopula(th), gumbelCopula(th), amhCopula(th), joeCopula(th))
  u <- runif(1, 0.02, 0.98); v <- runif(1, 0.02, 0.98); a <- c(fam, th, u, v)
  add("d", a, dCopula(c(u, v), cop)); add("p", a, pCopula(c(u, v), cop))
  if (fam != 3 || abs(th) > 0.01) add("tau", a, tau(cop))
}
emit("copula", "copula", list(cases))
