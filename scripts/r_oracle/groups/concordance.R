# survival::concordance(Surv(time, status) ~ x): "conc" args (n, time[n], status[n], x[n], k) k 0 concordant, 1 discordant, 2 tied in x, 3 tied in time with different x, 4 tied in both, 5 the concordance; times with ties and censoring
suppressMessages(library(survival))
cases <- list()
set.seed(20271220)
for (rep in 1:25) {
  n <- sample(30:120, 1); x <- if (rep %% 3 == 0) sample(1:4, n, TRUE) else round(rnorm(n), 2)
  time <- if (rep %% 2 == 0) sample(1:20, n, TRUE) else round(rexp(n, exp(0.3 * x)), 3); status <- rbinom(n, 1, 0.7)
  cc <- concordance(Surv(time, status) ~ x)
  v <- c(cc$count[["concordant"]], cc$count[["discordant"]], cc$count[["tied.x"]], cc$count[["tied.y"]], cc$count[["tied.xy"]], cc$concordance)
  for (k in 1:6) cases[[length(cases) + 1]] <- case("conc", c(n, time, status, x, k - 1), as.numeric(v[k]), rel = 1e-9, abs = 1e-9)
}
# survSplit(Surv(tstart, time, event) ~ ., cut): "ssplit" args (n, start[n], time[n], event[n], nc, cuts[nc], r, c) r the row (0 based), c 0 subject, 1 tstart, 2 tstop, 3 event, 4 episode; row r = -1 gives the number of rows in c = 0
for (rep in 1:25) {
  n <- sample(5:30, 1); st <- if (rep %% 2 == 0) round(runif(n, 0, 6)) else rep(0, n); tm <- st + sample(1:15, n, TRUE); ev <- rbinom(n, 1, 0.6)
  nc <- sample(1:4, 1); cuts <- sort(sample(1:20, nc)); d <- data.frame(id = 0:(n - 1), t0 = st, time = tm, event = ev)
  s <- if (all(st == 0)) survSplit(Surv(time, event) ~ ., data = d, cut = cuts, episode = "ep", start = "tstart") else survSplit(Surv(t0, time, event) ~ ., data = d, cut = cuts, episode = "ep")
  s <- s[order(s$id, s$ep), ]; tsn <- if (all(st == 0)) "tstart" else "t0"
  cases[[length(cases) + 1]] <- case("ssplit", c(n, st, tm, ev, nc, cuts, -1, 0), nrow(s), rel = 0, abs = 1e-9)
  for (r in seq_len(nrow(s))) { v <- c(s$id[r], s[[tsn]][r], s$time[r], s$event[r], s$ep[r]); for (cc in 0:4) cases[[length(cases) + 1]] <- case("ssplit", c(n, st, tm, ev, nc, cuts, r - 1, cc), as.numeric(v[cc + 1]), rel = 0, abs = 1e-9) }
}
emit("concordance", "survival", list(cases))
