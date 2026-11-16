# mvtnorm::pmvnorm with algorithm = TVPACK() in two dimensions (the analytic bivariate routine, which needs all lower = -Inf or all upper = Inf).
#   args: (l0, u0, l1, u1, m0, m1, s00, s01, s11)   fn "p"; infinite bounds are passed as +-Inf encoded as 1e300
suppressMessages(library(mvtnorm))
cases <- list()
set.seed(20261116)
enc <- function(v) ifelse(is.infinite(v), sign(v) * 1e300, v)
for (rep in 1:200) {
  s0 <- runif(1, 0.5, 3); s1 <- runif(1, 0.5, 3); r <- runif(1, -0.95, 0.95); S <- matrix(c(s0^2, r * s0 * s1, r * s0 * s1, s1^2), 2)
  mu <- round(rnorm(2), 2)
  if (rep %% 2 == 0) { lo <- c(-Inf, -Inf); up <- round(mu + rnorm(2) * 1.5, 2); if (rep %% 8 == 0) up[2] <- Inf }
  else { up <- c(Inf, Inf); lo <- round(mu + rnorm(2) * 1.5, 2); if (rep %% 9 == 1) lo[1] <- -Inf }
  p <- as.numeric(pmvnorm(lower = lo, upper = up, mean = mu, sigma = S, algorithm = TVPACK()))
  cases[[length(cases) + 1]] <- case("p", c(enc(lo[1]), enc(up[1]), enc(lo[2]), enc(up[2]), mu, S[1, 1], S[1, 2], S[2, 2]), p, rel = 1e-9, abs = 1e-12)
}
emit("pmvnorm", "mvtnorm", list(cases))
