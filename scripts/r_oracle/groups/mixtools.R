# mixtools: normalmixEM from given starting values.
#   args: (n, k, x[n]..., lambda0[k]..., mu0[k]..., sd0[k]...)   fn "ll" "iter" "lambda" "mu" "sd" (the last three: the sum of the estimates weighted by component position)
#   components are sorted by mean in both implementations before comparing, since the order follows the starting values (so is the same), kept as is
suppressMessages(library(mixtools))
cases <- list()
add <- function(fn, args, want, rel = 1e-7) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-9)
set.seed(20261227)
for (rep in 1:14) {
  k <- sample(2:3, 1); n <- sample(80:300, 1); mus <- sort(runif(k, -4, 4)) * c(1, 1.5, 2)[1:k]; sds <- runif(k, 0.5, 1.5); lam <- runif(k); lam <- lam / sum(lam)
  comp <- sample(k, n, replace = TRUE, prob = lam); x <- round(rnorm(n, mus[comp], sds[comp]), 4)
  l0 <- rep(1 / k, k); m0 <- quantile(x, seq(0.2, 0.8, length.out = k)); s0 <- rep(sd(x) / 2, k)
  r <- try(suppressWarnings(normalmixEM(x, lambda = l0, mu = m0, sigma = s0, epsilon = 1e-8, maxit = 1000)), silent = TRUE)
  if (inherits(r, "try-error") || length(r$all.loglik) > 1000) next
  a <- c(n, k, x, l0, m0, s0)
  add("ll", a, r$loglik); add("iter", a, length(r$all.loglik) - 1, rel = 0)
  add("lambda", a, sum(r$lambda * seq_len(k))); add("mu", a, sum(r$mu * seq_len(k))); add("sd", a, sum(r$sigma * seq_len(k)))
}
emit("mixtools", "mixtools", list(cases))
