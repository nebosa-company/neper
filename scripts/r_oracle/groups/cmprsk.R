# cmprsk::cuminc for one group: the step-function corners (time, estimate, variance) of each cause.
#   args: (n, time[n] sorted, status[n] 0 censored 1.. causes, cause, q)  fn "ci" q 0 npoints, 1 sum t, 2 sum est, 3 sum var, 4 last est, 5 last var, 6 weighted sum est, 7 weighted sum var
suppressMessages(library(cmprsk))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261116)
for (rep in 1:40) {
  n <- sample(20:150, 1); tm <- if (rep %% 2 == 0) round(rexp(n, 0.3) + 0.01, 1) else rexp(n, 0.3) + 0.01
  st <- sample(0:2, n, TRUE, prob = c(0.3, 0.4, 0.3)); o <- order(tm); tm <- tm[o]; st <- st[o]
  ci <- cuminc(tm, st)
  for (cs in 1:2) {
    p <- ci[[cs]]; k <- length(p$time)
    vals <- c(k, sum(p$time), sum(p$est), sum(p$var), p$est[k], p$var[k], sum(seq_len(k) * p$est), sum(seq_len(k) * p$var))
    for (q in seq_along(vals)) add("ci", c(n, tm, st, cs, q - 1), vals[q])
  }
}
emit("cmprsk", "cmprsk", list(cases))
