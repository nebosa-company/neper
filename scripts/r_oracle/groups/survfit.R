# survfit for one sample: args (conf, ctype 0 log / 1 plain / 2 log-log, n, time..., event..., row 0-based, column) with columns 0 time, 1 n.risk, 2 n.event, 3 surv, 4 std.err, 5 lower, 6 upper
suppressMessages(library(survival))
cases <- list()
set.seed(20262802)
ct <- c("log", "plain", "log-log")
for (rep in 1:30) {
  n <- sample(12:40, 1); t <- round(rexp(n, 0.1), 1) + 0.1; e <- rbinom(n, 1, 0.7); if (sum(e) < 3) next
  cf <- sample(c(0.9, 0.95, 0.99), 1); k <- sample(1:3, 1)
  fit <- survfit(Surv(t, e) ~ 1, conf.int = cf, conf.type = ct[k])
  s <- summary(fit, censored = FALSE)
  nr <- length(s$time)
  for (r in sample(seq_len(nr), min(4, nr))) {
    vals <- c(s$time[r], s$n.risk[r], s$n.event[r], s$surv[r], fit$std.err[fit$time == s$time[r]][1], s$lower[r], s$upper[r])
    for (col in 0:6) {
      if (!is.finite(vals[col + 1])) next
      cases[[length(cases) + 1]] <- case("kmt", c(cf, k - 1, n, t, e, r - 1, col), vals[col + 1], rel = 1e-8, abs = 1e-10)
    }
  }
}
# the Nelson-Aalen / Fleming-Harrington forms (ctype codes 10 = type "fleming-harrington", 11 = "fh2"), log interval
for (rep in 1:20) {
  n <- sample(12:40, 1); t <- round(rexp(n, 0.1), 1) + 0.1; e <- rbinom(n, 1, 0.7); if (sum(e) < 3) next
  cf <- sample(c(0.9, 0.95), 1); k <- sample(10:11, 1)
  fit <- survfit(Surv(t, e) ~ 1, conf.int = cf, conf.type = "log", type = c("fleming-harrington", "fh2")[k - 9])
  s <- summary(fit, censored = FALSE); nr <- length(s$time)
  for (r in sample(seq_len(nr), min(4, nr))) {
    vals <- c(s$time[r], s$n.risk[r], s$n.event[r], s$surv[r], fit$std.err[fit$time == s$time[r]][1], s$lower[r], s$upper[r])
    for (col in 0:6) {
      if (!is.finite(vals[col + 1])) next
      cases[[length(cases) + 1]] <- case("kmt", c(cf, k, n, t, e, r - 1, col), vals[col + 1], rel = 1e-8, abs = 1e-10)
    }
  }
}
# concordance(Surv ~ x): "conc" args (n, time..., event..., x..., index) index 0 concordant, 1 discordant, 2 tied.x, 3 C
for (rep in 1:25) {
  n <- sample(15:50, 1); t <- sample(seq(0.5, 60, by = 0.25), n); e <- rbinom(n, 1, 0.7); if (sum(e) < 4) next
  x <- round(rnorm(n) + 0.4 * log(t), 1)
  cc <- concordance(Surv(t, e) ~ x)
  v <- c(cc$count[["concordant"]], cc$count[["discordant"]], cc$count[["tied.x"]], cc$concordance)
  for (j in 0:3) cases[[length(cases) + 1]] <- case("conc", c(n, t, e, x, j), v[j + 1], rel = 1e-10, abs = 1e-12)
}
# survSplit: "ssplit" args (n, ncut, time..., event..., cuts..., row, col) col 0 subject (0-based), 1 tstart, 2 tstop, 3 status; the row count at row -1
for (rep in 1:20) {
  n <- sample(5:20, 1); tm <- round(rexp(n, 0.1) + 0.5, 1); ev <- rbinom(n, 1, 0.7); cuts <- sort(sample(c(2, 4, 6.5, 9, 12, 15), sample(1:4, 1)))
  d <- data.frame(id = 1:n, tm = tm, ev = ev)
  sp <- survSplit(Surv(tm, ev) ~ ., data = d, cut = cuts, episode = "ep")
  sp <- sp[order(sp$id, sp$tstart), ]
  cases[[length(cases) + 1]] <- case("ssplit", c(n, length(cuts), tm, ev, cuts, -1, 0), nrow(sp), rel = 0, abs = 0)
  for (r in sample(seq_len(nrow(sp)), min(6, nrow(sp)))) {
    v <- c(sp$id[r] - 1, sp$tstart[r], sp$tm[r], sp$ev[r])
    for (col in 0:3) cases[[length(cases) + 1]] <- case("ssplit", c(n, length(cuts), tm, ev, cuts, r - 1, col), v[col + 1], rel = 1e-12, abs = 1e-12)
  }
}
# pyears by a factor: "pyr" args (k, n, scale, time..., status..., group 0-based..., g, col) col 0 pyears, 1 n, 2 event
for (rep in 1:15) {
  k <- sample(2:4, 1); n <- sample(20:60, 1); sc <- sample(c(1, 365.25), 1); gr <- c(0:(k - 1), sample(0:(k - 1), n - k, TRUE))
  tm <- round(rexp(n, 0.002) + 1, 1); st <- rbinom(n, 1, 0.7); d <- data.frame(tm = tm, st = st, g = factor(gr))
  py <- pyears(Surv(tm, st) ~ g, data = d, scale = sc)
  for (g in 0:(k - 1)) { v <- c(py$pyears[g + 1], py$n[g + 1], py$event[g + 1])
    for (col in 0:2) cases[[length(cases) + 1]] <- case("pyr", c(k, n, sc, tm, st, gr, g, col), as.numeric(v[col + 1]), rel = 1e-12, abs = 1e-12) }
}
emit("survfit", "survival", list(cases))
