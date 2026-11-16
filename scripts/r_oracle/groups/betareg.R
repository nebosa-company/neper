# betareg: logit-link beta regression with constant precision: coefficients, precision and log-likelihood.
#   args: (n, p, which, y[n]..., x row-major n by p with the intercept column...)   fn "fit"
#   which: 0.. a coefficient, 20 the precision phi, 30 the log-likelihood.  Agreement is to the optimiser tolerance, so the tolerances are looser.
suppressMessages(library(betareg))
cases <- list()
add <- function(args, want, rel) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("fit", args, want, rel = rel, abs = 1e-4)
set.seed(20261211)
for (rep in 1:10) {
  n <- sample(40:120, 1); k <- sample(1:3, 1)
  X <- matrix(rnorm(n * k), n, k)
  mu <- plogis(0.2 + X %*% c(0.8, -0.6, 0.4)[1:k]); phi <- runif(1, 5, 40)
  y <- rbeta(n, mu * phi, (1 - mu) * phi); y <- pmin(pmax(y, 1e-4), 1 - 1e-4)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("x", seq_len(k)))
  f <- betareg(y ~ ., data = d)
  p <- k + 1; design <- cbind(1, X)
  mk <- function(w) c(n, p, w, y, as.vector(t(design)))
  cf <- coef(f, model = "mean")
  for (j in seq_len(p)) add(mk(j - 1), cf[[j]], 1e-3)
  add(mk(20), coef(f, model = "precision")[[1]], 1e-3)
  add(mk(30), as.numeric(logLik(f)), 1e-6)
}
emit("betareg", "betareg", list(cases))
