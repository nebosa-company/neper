# DHARMa: PIT residuals of a simulated response matrix, their KS statistic, the outlier count and the exact binomial outlier test.
#   args: (n, nsim, seed, obs[n]..., sims row-major n by nsim...)   fn "res" (sum of residual * position), "ks" (statistic), "nout" (outlier count), "pout" (binomial p)
suppressMessages(library(DHARMa))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-12)
set.seed(20261218)
for (rep in 1:14) {
  n <- sample(20:80, 1); ns <- sample(c(50, 100, 250), 1); sd <- sample(1:10000, 1)
  mu <- rnorm(n); y <- mu + rnorm(n) * c(1, 1.6, 0.6)[rep %% 3 + 1]
  if (rep %% 2 == 0) { y <- round(y); sims <- matrix(round(rnorm(n * ns, rep(mu, ns))), n, ns) } else sims <- matrix(rnorm(n * ns, rep(mu, ns)), n, ns)
  r <- suppressMessages(suppressWarnings(createDHARMa(sims, y, fittedPredictedResponse = mu, integerResponse = FALSE, seed = sd)))
  a <- c(n, ns, sd, y, as.vector(t(sims)))
  sr <- r$scaledResiduals
  add("res", a, sum(sr * seq_along(sr))); add("ks", a, as.numeric(suppressWarnings(ks.test(sr, "punif")$statistic)))
  to <- suppressMessages(testOutliers(r, plot = FALSE))
  add("nout", a, as.numeric(to$statistic)); add("pout", a, to$p.value)
  add("ksp", a, suppressWarnings(ks.test(sr, "punif")$p.value))
}
for (rep in 1:12) {
  n <- sample(30:90, 1); ns <- sample(c(50, 100, 200), 1); sd <- sample(1:10000, 1)
  mu <- rexp(n) * 2; y <- rpois(n, mu); if (rep %% 2 == 0) y[sample(n, n %/% 4)] <- 0
  sims <- matrix(rpois(n * ns, rep(mu, ns)), n, ns)
  r <- suppressMessages(suppressWarnings(createDHARMa(sims, y, fittedPredictedResponse = mu, integerResponse = TRUE, seed = sd)))
  a <- c(n, ns, sd, y, as.vector(t(sims)), mu)
  for (alt in 0:2) {
    al <- c("two.sided", "greater", "less")[alt + 1]
    z <- suppressMessages(testZeroInflation(r, alternative = al, plot = FALSE)); dsp <- suppressMessages(testDispersion(r, alternative = al, plot = FALSE))
    add("zi_ratio", c(a, alt), as.numeric(z$statistic)); add("zi_p", c(a, alt), z$p.value)
    add("disp_ratio", c(a, alt), as.numeric(dsp$statistic)); add("disp_p", c(a, alt), dsp$p.value)
  }
}
emit("dharma", "DHARMa", list(cases))
