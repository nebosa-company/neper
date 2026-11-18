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
emit("survfit", "survival", list(cases))
