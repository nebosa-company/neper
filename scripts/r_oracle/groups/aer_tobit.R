# AER::tobit (gaussian) with left and right censoring.
#   fn "tobit": args (n, p, left, right, which, y[n], x[n*p] row-major, the constant column included); right 1e300 stands for Inf
#   which: 0 coef (position-weighted sum) 1 scale 2 logLik 3 se of coef + Log(scale) (position-weighted sum) 4 Log(scale) estimate
suppressMessages({library(AER)})
cases <- list()
ws <- function(v) sum(v * seq_along(v))
set.seed(20261122)
for (rep in 1:8) {
  n <- sample(60:100, 1); p <- sample(1:2, 1); lo <- sample(c(0, 0.5, 1), 1); hi <- if (rep %% 3 == 0) lo + 3.5 else Inf
  x <- round(matrix(rnorm(n * p), n), 3); b <- runif(p, 0.3, 1.2) * sample(c(-1, 1), p, TRUE)
  y0 <- 1 + as.vector(x %*% b) + rnorm(n) * 1.3
  y <- round(pmin(pmax(y0, lo), hi), 4)
  X <- cbind(1, x); dd <- data.frame(y = y, x)
  m <- tobit(y ~ ., left = lo, right = hi, data = dd)
  s <- summary(m)$coefficients
  add <- function(which, want, rel) cases[[length(cases) + 1]] <<- case("tobit", c(n, p + 1, lo, if (is.finite(hi)) hi else 1e300, which, y, as.vector(t(X))), want, rel = rel, abs = 1e-11)
  r <- 1e-8  # survreg stops at a relative log-likelihood change of 1e-9, so R itself sits about 1e-9 to 1e-8 from the maximum Neper reaches
  add(0, ws(coef(m)), r); add(1, m$scale, r); add(2, as.numeric(logLik(m)), r); add(3, ws(s[, 2]), r); add(4, log(m$scale), r)
}
emit("aer_tobit", "AER", list(cases))
