# ismev rlarg.fit without covariates (Nelder-Mead MLE and the optim Hessian standard errors). args: (rows, r, which, matrix row-major...);
# which 0..2 a parameter, 10..12 its standard error, 99 the negative log-likelihood. Agreement is to the optimiser tolerance of R.
suppressMessages(library(ismev))
cases <- list()
add <- function(args, want, rel) cases[[length(cases) + 1]] <<- case("rl", args, want, rel = rel, abs = 1e-3)
set.seed(20261701)
for (rep in 1:6) {
  rows <- sample(25:60, 1); r <- c(2, 3, 4)[rep %% 3 + 1]
  mu <- runif(1, 5, 20); sc <- runif(1, 1, 4); xi <- c(0.15, -0.15, 0.05)[rep %% 3 + 1]
  # the r largest of a GEV block: the arrival times E_j of a unit Poisson process through the GEV quantile
  m <- t(vapply(seq_len(rows), function(i) { e <- cumsum(rexp(r)); mu + sc * (e^(-xi) - 1) / xi }, numeric(r)))
  if (r == 1) m <- matrix(m, ncol = 1)
  m <- t(apply(m, 1, sort, decreasing = TRUE))
  f <- tryCatch(rlarg.fit(m, r = r, show = FALSE), error = function(e) NULL)
  if (is.null(f) || f$conv != 0) next
  flat <- as.vector(t(m))
  for (k in 1:3) { add(c(rows, r, k - 1, flat), f$mle[k], 2e-2); add(c(rows, r, 10 + k - 1, flat), f$se[k], 5e-2) }
  add(c(rows, r, 99, flat), f$nllh, 1e-6)
}
emit("ismev_rlarg", "ismev", list(cases))
