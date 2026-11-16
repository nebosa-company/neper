# flexsurv flexsurvreg: weibull, exponential, lognormal, loglogistic and gompertz with covariates on the location parameter.
#   args: (n, k, model 0 weibull 1 exp 2 lnorm 3 llogis 4 gompertz, time[n], event[n], x[n*k] row-major)
#   fn "ll" (log-likelihood), "par" (res.t estimates weighted by position)
suppressMessages({library(flexsurv); library(survival)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-4, abs = 1e-5)
ds <- c("weibull", "exp", "lnorm", "llogis", "gompertz")
set.seed(20270102)
for (rep in 1:30) {
  model <- (rep - 1) %% 5; n <- sample(60:180, 1); k <- sample(1:2, 1)
  x <- matrix(rnorm(n * k), n); b <- rnorm(k, 0, 0.4); lp <- as.vector(x %*% b)
  tt <- switch(model + 1, rweibull(n, 1.5, exp(1 + lp)), rexp(n, exp(-1 + lp)), exp(rnorm(n, 1 + lp, 0.6)), exp(1 + lp) * (runif(n) / (1 - runif(n)))^(1 / 2), rgompertz(n, 0.4, exp(-1.5 + lp)))
  cc <- runif(n, 0, quantile(tt, 0.9)); y <- pmin(tt, cc); ev <- as.numeric(tt <= cc)
  d <- data.frame(y, ev, x); names(d)[-(1:2)] <- paste0("x", seq_len(k))
  fm <- as.formula(paste("Surv(y, ev) ~", paste0("x", seq_len(k), collapse = " + ")))
  f <- tryCatch(suppressWarnings(flexsurvreg(fm, data = d, dist = ds[model + 1], control = list(reltol = 1e-14, maxit = 5000))), error = function(e) NULL)
  if (is.null(f) || any(!is.finite(f$res.t[, "est"]))) next
  a <- c(n, k, model, y, ev, as.vector(t(x)))
  est <- f$res.t[, "est"]
  add("ll", a, f$loglik)
  cases[[length(cases) + 1]] <- case("par", a, sum(est * seq_along(est)), 1e-3, 1e-4)
}
emit("flexsurv", "flexsurv", list(cases))
