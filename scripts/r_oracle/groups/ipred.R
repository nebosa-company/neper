# ipred: sbrier at one time with numeric predictions, kfoldcv.
#   "sb" (n, btime, time[n], cens[n], pred[n]) "kf" (k, N, index)
suppressMessages(library(ipred)); suppressMessages(library(survival))
cases <- list()
add <- function(fn, args, want, tol = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-12)
set.seed(20261118)
for (rep in 1:40) {
  n <- sample(10:80, 1); time <- rexp(n, 0.5); cens <- rbinom(n, 1, 0.7); pred <- runif(n); bt <- quantile(time, runif(1, 0.2, 0.8))
  s <- sbrier(Surv(time, cens), pred, btime = bt); add("sb", c(n, bt, time, cens, pred), s[[1]])
}
for (rep in 1:40) {
  n <- sample(10:80, 1); time <- round(rexp(n, 0.5), 1); cens <- rbinom(n, 1, 0.6); pred <- runif(n); bt <- sample(time, 1)
  s <- sbrier(Surv(time, cens), pred, btime = bt); add("sb", c(n, bt, time, cens, pred), s[[1]])
}
for (rep in 1:30) { k <- sample(2:12, 1); N <- sample(1:100, 1); v <- kfoldcv(k, N); for (j in seq_along(v)) add("kf", c(k, N, j - 1), v[j]) }
emit("ipred", "ipred", list(cases))
