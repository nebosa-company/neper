# cmprsk::cuminc for one group: the step-function corners (time, estimate, variance) of each cause.
#   args: (n, time[n] sorted, status[n] 0 censored 1.. causes, cause, q)  fn "ci" q 0 npoints (q 8..11 est and 12..15 var at the 4 times that follow q in args via timepoints), 1 sum t, 2 sum est, 3 sum var, 4 last est, 5 last var, 6 weighted sum est, 7 weighted sum var
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
    tps <- c(tm[ceiling(n * 0.2)], tm[ceiling(n * 0.5)] + 0.003, tm[n], tm[n] * 1.5); tpo <- timepoints(ci, tps)
    for (j in 1:4) {
      if (is.finite(tpo$est[cs, j])) add("ci", c(n, tm, st, cs, 8 + j - 1, tps), tpo$est[cs, j])
      if (is.finite(tpo$var[cs, j])) add("ci", c(n, tm, st, cs, 12 + j - 1, tps), tpo$var[cs, j])
    }
  }
}
# Gray k-sample test: fn "gray" args (n, ng, nst, rho, cause, time[n], status[n], group[n] 1.., strata[n] 1.., 0) -> statistic of that cause
for (rep in 1:60) {
  n <- sample(30:150, 1); ng <- sample(2:4, 1); nst <- if (rep %% 3 == 0) 2 else 1; rho <- c(0, 1, 0.5)[rep %% 3 + 1]
  tm <- if (rep %% 2 == 0) round(rexp(n, 0.3) + 0.01, 1) else rexp(n, 0.3) + 0.01
  st <- sample(0:2, n, TRUE, prob = c(0.3, 0.4, 0.3)); gr <- sample(seq_len(ng), n, TRUE); sr <- sample(seq_len(nst), n, TRUE)
  o <- order(tm); tm <- tm[o]; st <- st[o]; gr <- gr[o]; sr <- sr[o]
  if (length(unique(gr)) < ng) next
  ci <- cuminc(tm, st, gr, sr, rho = rho)
  for (cs in 1:2) add("gray", c(n, ng, nst, rho, cs, tm, st, gr, sr, 0), ci$Tests[as.character(cs), "stat"])
}
emit("cmprsk", "cmprsk", list(cases))
