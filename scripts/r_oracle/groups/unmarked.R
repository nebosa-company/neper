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
  v <- c(coef(f), -f@opt$value, sqrt(diag(vcov(f))))
  X <- cbind(1, x); Z <- cbind(1, z)
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("occu", c(m, J, 2, 2, as.vector(t(y)), as.vector(t(X)), as.vector(t(Z)), k - 1), as.numeric(v[k]), rel = if (k == 5) 1e-6 else if (k > 5) 1e-2 else 3e-3, abs = if (k == 5) 1e-4 else if (k > 5) 5e-3 else 1e-3)
}
# pcount(~ z ~ x, K): "pcnt" args (m, j, p1, p2, K, y[m * j] counts row-major, x, z as above, k) the same coefficient layout, then the log-likelihood
for (rep in 1:10) {
  m <- sample(60:100, 1); J <- sample(3:4, 1); x <- round(rnorm(m), 3); z <- round(rnorm(m), 3); K <- 40
  lam <- exp(0.5 + 0.3 * x); p <- plogis(0.2 + 0.5 * z); N <- rpois(m, lam)
  y <- matrix(rbinom(m * J, rep(N, J), rep(p, J)), m, J)
  umf <- unmarkedFramePCount(y = y, siteCovs = data.frame(x = x, z = z))
  f <- tryCatch(pcount(~z ~x, umf, K = K, control = list(reltol = 1e-14, maxit = 1000)), error = function(e) NULL)
  if (is.null(f) || any(abs(coef(f)) > 8)) next
  v <- c(coef(f), -f@opt$value, sqrt(diag(vcov(f))))
  X <- cbind(1, x); Z <- cbind(1, z)
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("pcount", c(m, J, 2, 2, K, as.vector(t(y)), as.vector(t(X)), as.vector(t(Z)), k - 1), as.numeric(v[k]), rel = if (k == 5) 1e-6 else if (k > 5) 2e-2 else 5e-3, abs = if (k == 5) 1e-4 else if (k > 5) 1e-2 else 2e-3)
}
# occu with visit-level detection covariates and missing visits: "occuvisit" args (m, J, p1, p2, y[m * J] row-major with -1 for a missing visit, x[m * p1], zv[m * J * p2] row-major by site then visit, k) k 0 .. p1 + p2 - 1 the coefficients, p1 + p2 the log-likelihood
for (rep in 1:10) {
  m <- sample(100:200, 1); J <- sample(3:5, 1); x <- round(rnorm(m), 3); wv <- matrix(round(rnorm(m * J), 3), m, J)
  psi <- plogis(0.3 + 0.8 * x); p <- plogis(-0.4 + 0.6 * wv); occ <- rbinom(m, 1, psi)
  y <- matrix(rbinom(m * J, 1, occ * p), m, J); miss <- matrix(runif(m * J) < 0.1, m, J); y[miss] <- NA
  umf <- unmarkedFrameOccu(y = y, siteCovs = data.frame(x = x), obsCovs = list(w = wv))
  f <- tryCatch(occu(~w ~x, umf), error = function(e) NULL)
  if (is.null(f)) next
  v <- c(coef(f), -f@opt$value, sqrt(diag(vcov(f))))
  X <- cbind(1, x); yy <- y; yy[is.na(yy)] <- -1
  Zv <- do.call(rbind, lapply(1:m, function(i) cbind(1, wv[i, ])))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("occuvisit", c(m, J, 2, 2, as.vector(t(yy)), as.vector(t(X)), as.vector(t(Zv)), k - 1), as.numeric(v[k]), rel = if (k == 5) 1e-6 else if (k > 5) 1e-2 else 3e-3, abs = if (k == 5) 1e-4 else if (k > 5) 5e-3 else 1e-3)
}
# occuRN(~ z ~ x, K): "occurn" args (m, J, p1, p2, K, y[m * J] 0/1, x[m * p1], z[m * p2] site-level, k) k 0 .. p1 + p2 - 1 the coefficients (abundance log link, per-individual detection logit), p1 + p2 the log-likelihood
for (rep in 1:8) {
  m <- sample(60:100, 1); J <- sample(4:6, 1); x <- round(rnorm(m), 3); z <- round(rnorm(m), 3); K <- 30
  lam <- exp(0.4 + 0.3 * x); r <- plogis(-1 + 0.4 * z); N <- rpois(m, lam); y <- matrix(rbinom(m * J, 1, rep(1 - (1 - r)^N, J)), m, J)
  umf <- unmarkedFrameOccu(y = y, siteCovs = data.frame(x = x, z = z))
  f <- tryCatch(occuRN(~z ~x, umf, K = K), error = function(e) NULL)
  if (is.null(f) || any(abs(coef(f)) > 6)) next
  v <- c(coef(f), -f@opt$value, sqrt(diag(vcov(f))))
  X <- cbind(1, x); Z <- cbind(1, z)
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("occurnmodel", c(m, J, 2, 2, K, as.vector(t(y)), as.vector(t(X)), as.vector(t(Z)), k - 1), as.numeric(v[k]), rel = if (k == 5) 1e-6 else if (k > 5) 3e-2 else 1e-2, abs = if (k == 5) 1e-3 else if (k > 5) 2e-2 else 5e-3)
}
emit("unmarked", "unmarked", list(cases))
