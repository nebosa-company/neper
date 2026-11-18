# survdiff: the G-rho test of two groups. args (rho, na, nb, time A, time B, event A, event B), fn "sd_chisq" and "sd_p"
suppressMessages(library(survival))
cases <- list()
set.seed(20262801)
for (rep in 1:40) {
  na <- sample(10:40, 1); nb <- sample(10:40, 1); rho <- sample(c(0, 0.5, 1, 2), 1)
  ta <- round(rexp(na, 0.1), 2) + 0.01; tb <- round(rexp(nb, runif(1, 0.06, 0.2)), 2) + 0.01
  ea <- rbinom(na, 1, 0.75); eb <- rbinom(nb, 1, 0.75); if (sum(ea) + sum(eb) < 4) next
  d <- data.frame(t = c(ta, tb), e = c(ea, eb), g = rep(1:2, c(na, nb)))
  r <- survdiff(Surv(t, e) ~ g, data = d, rho = rho)
  a <- c(rho, na, nb, ta, tb, ea, eb)
  cases[[length(cases) + 1]] <- case("sd_chisq", a, as.numeric(r$chisq), rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("sd_p", a, as.numeric(pchisq(r$chisq, 1, lower.tail = FALSE)), rel = 1e-8, abs = 1e-12)
}
# K groups: "sdk" args (rho, k, n, time..., event..., group 0-based...), the chi-square
for (rep in 1:30) {
  k <- sample(3:4, 1); sz <- sample(8:25, k, TRUE); n <- sum(sz); rho <- sample(c(0, 1), 1)
  g <- rep(0:(k - 1), sz); t <- round(rexp(n, 0.1 * (1 + 0.3 * g)), 2) + 0.01; e <- rbinom(n, 1, 0.75); if (sum(e) < 6) next
  d <- data.frame(t = t, e = e, g = g)
  r <- survdiff(Surv(t, e) ~ g, data = d, rho = rho)
  cases[[length(cases) + 1]] <- case("sd_k", c(rho, k, n, t, e, g), as.numeric(r$chisq), rel = 1e-7, abs = 1e-10)
}
emit("survdiff", "survival", list(cases))
