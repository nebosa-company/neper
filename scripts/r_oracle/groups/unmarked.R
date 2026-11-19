# unmarked occu(~ z ~ x): "occu" args (m, j, p1, p2, y[m * j] row-major, x[m * p1] row-major with the intercept column, z[m * p2] with its own, k) k 0 .. p1 - 1 the occupancy coefficients, p1 .. p1 + p2 - 1 the detection coefficients, p1 + p2 the log-likelihood
suppressMessages(library(unmarked))
cases <- list()
set.seed(20271218)
for (rep in 1:10) {
  m <- sample(100:200, 1); J <- sample(3:5, 1); x <- round(rnorm(m), 3); z <- round(rnorm(m), 3)
  psi <- plogis(0.3 + 0.8 * x); p <- plogis(-0.4 + 0.6 * z); occ <- rbinom(m, 1, psi)
  y <- matrix(rbinom(m * J, 1, rep(occ * p, J)), m, J)
  umf <- unmarkedFrameOccu(y = y, siteCovs = data.frame(x = x, z = z))
  f <- tryCatch(occu(~z ~x, umf), error = function(e) NULL)
  if (is.null(f)) next
  v <- c(coef(f), -f@opt$value)
  X <- cbind(1, x); Z <- cbind(1, z)
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("occu", c(m, J, 2, 2, as.vector(t(y)), as.vector(t(X)), as.vector(t(Z)), k - 1), as.numeric(v[k]), rel = if (k == length(v)) 1e-6 else 3e-3, abs = if (k == length(v)) 1e-4 else 1e-3)
}
# pcount(~ z ~ x, K): "pcnt" args (m, j, p1, p2, K, y[m * j] counts row-major, x, z as above, k) the same coefficient layout, then the log-likelihood
for (rep in 1:5) {
  m <- sample(35:50, 1); J <- sample(3:4, 1); x <- round(rnorm(m), 3); z <- round(rnorm(m), 3); K <- 25
  lam <- exp(0.5 + 0.3 * x); p <- plogis(0.2 + 0.5 * z); N <- rpois(m, lam)
  y <- matrix(rbinom(m * J, rep(N, J), rep(p, J)), m, J)
  umf <- unmarkedFramePCount(y = y, siteCovs = data.frame(x = x, z = z))
  f <- tryCatch(pcount(~z ~x, umf, K = K, control = list(reltol = 1e-14, maxit = 1000)), error = function(e) NULL)
  if (is.null(f) || any(abs(coef(f)) > 8)) next
  v <- c(coef(f), -f@opt$value)
  X <- cbind(1, x); Z <- cbind(1, z)
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("pcount", c(m, J, 2, 2, K, as.vector(t(y)), as.vector(t(X)), as.vector(t(Z)), k - 1), as.numeric(v[k]), rel = if (k == length(v)) 1e-6 else 5e-3, abs = if (k == length(v)) 1e-4 else 2e-3)
}
emit("unmarked", "unmarked", list(cases))
