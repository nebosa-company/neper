# hetGP mleHomGP with known theta and g (Gaussian kernel): profiled beta0, nu_hat, log-likelihood and predictions.
#   args: (n, d, m, g, theta[d], X[n*d] row-major, z[n], Xt[m*d] row-major)
#   fn "beta0" "nu" "ll", "mean" "sd2" "nugs" (weighted by position)
suppressMessages(library(hetGP))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-10)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20270109)
for (rep in 1:20) {
  n <- sample(8:40, 1); d <- sample(1:3, 1); m <- sample(2:6, 1); X <- matrix(runif(n * d), n); z <- sin(3 * X[, 1]) + rowSums(X) + rnorm(n, 0, 0.15)
  th <- runif(d, 0.15, 1.2); g <- runif(1, 0.005, 0.1); Xt <- matrix(runif(m * d), m)
  mo <- tryCatch(mleHomGP(X, z, known = list(theta = th, g = g), covtype = "Gaussian"), error = function(e) NULL); if (is.null(mo)) next
  pr <- predict(mo, Xt); a <- c(n, d, m, g, th, as.vector(t(X)), z, as.vector(t(Xt)))
  add("beta0", a, mo$beta0); add("nu", a, mo$nu_hat); add("ll", a, as.numeric(mo$ll))
  add("mean", a, ws(pr$mean)); add("sd2", a, ws(pr$sd2)); add("nugs", a, ws(pr$nugs))
}
emit("hetgp", "hetGP", list(cases))
