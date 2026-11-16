# logistf: Firth penalized logistic regression, coefficients, standard errors, profile likelihood-ratio p values and penalized log-likelihoods.
#   args: (n, p, which, y[n]..., x row-major n by p with the intercept column...)   fn "fit"
#   which: 0.. a coefficient, 10.. its standard error, 20.. its profile p value, 30 the full penalized log-likelihood, 31 the null one
#   R stops at gconv 1e-5, so the tolerances are looser than elsewhere
suppressMessages(library(logistf))
cases <- list()
add <- function(args, want, rel) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("fit", args, want, rel = rel, abs = 1e-6)
set.seed(20261210)
for (rep in 1:10) {
  n <- sample(25:70, 1); k <- sample(1:3, 1)
  X <- matrix(rnorm(n * k), n, k); if (k > 1) X[, 2] <- rbinom(n, 1, 0.4)
  eta <- 0.3 + X %*% c(1.2, -1.5, 0.7)[1:k]; y <- rbinom(n, 1, plogis(eta))
  if (rep %% 4 == 0) { y <- as.numeric(X[, 1] > 0.3) ; y[sample(n, 3)] <- 1 - y[sample(n, 3)] }
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("x", seq_len(k)))
  warned <- FALSE
  f <- withCallingHandlers(logistf(y ~ ., data = d, control = logistf.control(gconv = 1e-10, xconv = 1e-10, maxit = 500)), warning = function(w) { warned <<- TRUE; invokeRestart("muffleWarning") })
  if (warned) next
  p <- k + 1; design <- cbind(1, X)
  mk <- function(w) c(n, p, w, y, as.vector(t(design)))
  for (j in seq_len(p)) { add(mk(j - 1), f$coefficients[j], 1e-5); add(mk(10 + j - 1), sqrt(f$var[j, j]), 1e-5); add(mk(20 + j - 1), f$prob[j], 1e-4) }
  add(mk(30), f$loglik[["full"]], 1e-7); add(mk(31), f$loglik[["null"]], 1e-7)
}
emit("logistf", "logistf", list(cases))
