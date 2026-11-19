# psych::fa(r, nfactors = q, n.obs, fm = "ml", rotate = "none"): "faml" args (p, q, r[p * p] row-major, k) k 0 .. p - 1 the uniquenesses, p + 1 + i + k p the loading of item i on factor k (signed to a positive column sum)
suppressMessages(library(psych))
cases <- list()
set.seed(20271221)
for (rep in 1:12) {
  p <- sample(5:8, 1); q <- sample(1:2, 1); N <- sample(200:400, 1)
  L <- matrix(runif(p * q, 0.3, 0.8), p, q); Fm <- matrix(rnorm(N * q), N, q); X <- Fm %*% t(L) + matrix(rnorm(N * p, 0, 0.7), N, p)
  R <- cor(X)
  f <- tryCatch(suppressWarnings(fa(R, nfactors = q, n.obs = N, fm = "ml", rotate = "none")), error = function(e) NULL)
  if (is.null(f)) next
  u <- f$uniquenesses; if (any(u < 0.02)) next
  for (k in 1:p) cases[[length(cases) + 1]] <- case("faml", c(p, q, as.vector(t(R)), k - 1), as.numeric(u[k]), rel = 1e-3, abs = 1e-4)
  Ld <- unclass(f$loadings)
  for (kk in 1:q) for (ii in 1:p) cases[[length(cases) + 1]] <- case("faml", c(p, q, as.vector(t(R)), p + 1 + (ii - 1) + (kk - 1) * p), as.numeric(Ld[ii, kk]), rel = 2e-3, abs = 5e-4)
}
# the same with rotate = "varimax", two factors: "famlv" args (p, q, r[p * p], k) k p + i + k p the rotated loading of item i on factor k (columns ordered by sum of squares, signed to a positive sum)
for (rep in 1:8) {
  p <- sample(6:8, 1); q <- 2; N <- sample(250:400, 1)
  L <- matrix(runif(p * q, 0.3, 0.8), p, q); L[1:3, 2] <- 0.05; L[4:6, 1] <- 0.05; Fm <- matrix(rnorm(N * q), N, q); X <- Fm %*% t(L) + matrix(rnorm(N * p, 0, 0.7), N, p)
  R <- cor(X)
  f <- tryCatch(suppressWarnings(fa(R, nfactors = q, n.obs = N, fm = "ml", rotate = "varimax")), error = function(e) NULL)
  if (is.null(f) || any(f$uniquenesses < 0.02)) next
  Ld <- unclass(f$loadings)
  for (kk in 1:q) for (ii in 1:p) cases[[length(cases) + 1]] <- case("famlv", c(p, q, as.vector(t(R)), p + (ii - 1) + (kk - 1) * p), as.numeric(Ld[ii, kk]), rel = 5e-3, abs = 2e-3)
}
# rotate = "promax", two factors: "famlp" args as famlv, the promax pattern loadings
for (rep in 1:8) {
  p <- sample(6:8, 1); q <- 2; N <- sample(250:400, 1)
  L <- matrix(runif(p * q, 0.3, 0.8), p, q); L[1:3, 2] <- 0.05; L[4:6, 1] <- 0.05; Fm <- matrix(rnorm(N * q), N, q); X <- Fm %*% t(L) + matrix(rnorm(N * p, 0, 0.7), N, p)
  R <- cor(X)
  f <- tryCatch(suppressWarnings(fa(R, nfactors = q, n.obs = N, fm = "ml", rotate = "Promax")), error = function(e) NULL)
  if (is.null(f) || any(f$uniquenesses < 0.02)) next
  Ld <- unclass(f$loadings)
  for (kk in 1:q) for (ii in 1:p) cases[[length(cases) + 1]] <- case("famlpro", c(p, q, as.vector(t(R)), p + (ii - 1) + (kk - 1) * p), as.numeric(Ld[ii, kk]), rel = 5e-3, abs = 2e-3)
}
# rotate = "oblimin" (GPArotation::oblimin, gamma 0): "famlobl" args as famlv, the pattern loadings
for (rep in 1:8) {
  p <- sample(6:8, 1); q <- 2; N <- sample(250:400, 1)
  L <- matrix(runif(p * q, 0.3, 0.8), p, q); L[1:3, 2] <- 0.05; L[4:6, 1] <- 0.05; Fm <- matrix(rnorm(N * q), N, q); Fm[, 2] <- 0.3 * Fm[, 1] + 0.95 * Fm[, 2]; X <- Fm %*% t(L) + matrix(rnorm(N * p, 0, 0.7), N, p)
  R <- cor(X)
  f <- tryCatch(suppressWarnings(fa(R, nfactors = q, n.obs = N, fm = "ml", rotate = "oblimin")), error = function(e) NULL)
  if (is.null(f) || any(f$uniquenesses < 0.02)) next
  Ld <- unclass(f$loadings)
  for (kk in 1:q) for (ii in 1:p) cases[[length(cases) + 1]] <- case("famloblimin", c(p, q, as.vector(t(R)), p + (ii - 1) + (kk - 1) * p), as.numeric(Ld[ii, kk]), rel = 5e-3, abs = 2e-3)
  Ph <- f$Phi; for (kk in 1:q) for (ll in 1:q) cases[[length(cases) + 1]] <- case("famloblimin", c(p, q, as.vector(t(R)), p + p * q + q * q + (kk - 1) * q + (ll - 1)), as.numeric(Ph[kk, ll]), rel = 5e-3, abs = 2e-3)
}
# the residual-based methods, no rotation: "faresid" args (p, q, fm 0 minres 1 uls 2 ols, r[p * p], k) k 0 .. p - 1 the uniquenesses
fmn <- c("minres", "uls", "ols", "wls", "gls")
for (rep in 1:10) {
  p <- sample(5:8, 1); q <- sample(1:2, 1); N <- sample(200:400, 1)
  L <- matrix(runif(p * q, 0.3, 0.8), p, q); Fm <- matrix(rnorm(N * q), N, q); X <- Fm %*% t(L) + matrix(rnorm(N * p, 0, 0.7), N, p); R <- cor(X)
  for (fm in 0:2) {
    f <- tryCatch(suppressWarnings(fa(R, nfactors = q, n.obs = N, fm = fmn[fm + 1], rotate = "none")), error = function(e) NULL)
    if (is.null(f) || any(f$uniquenesses < 0.02)) next
    for (k in 1:p) cases[[length(cases) + 1]] <- case("faresidual", c(p, q, fm, as.vector(t(R)), k - 1), as.numeric(f$uniquenesses[k]), rel = 5e-3, abs = 2e-3)
    Ld <- unclass(f$loadings); for (kk in 1:q) for (ii in 1:p) cases[[length(cases) + 1]] <- case("faresidual", c(p, q, fm, as.vector(t(R)), p + 1 + (ii - 1) + (kk - 1) * p), as.numeric(Ld[ii, kk]), rel = 1e-2, abs = 3e-3)
  }
}
# rotated minres fits (the default method of psych::fa): "farotmin" args (p, q = 2, rot 0 varimax 1 Promax 2 oblimin, r[p * p], k) k p + i + k p the rotated loading, and for oblimin p + p q + q q + k q + l the factor correlation
for (rep in 1:8) {
  p <- sample(6:8, 1); q <- 2; N <- sample(250:400, 1)
  L <- matrix(runif(p * q, 0.3, 0.8), p, q); L[1:3, 2] <- 0.05; L[4:6, 1] <- 0.05; Fm <- matrix(rnorm(N * q), N, q); Fm[, 2] <- 0.3 * Fm[, 1] + 0.95 * Fm[, 2]; X <- Fm %*% t(L) + matrix(rnorm(N * p, 0, 0.7), N, p); R <- cor(X)
  for (rot in 0:2) {
    f <- tryCatch(suppressWarnings(fa(R, nfactors = q, n.obs = N, fm = "minres", rotate = c("varimax", "Promax", "oblimin")[rot + 1])), error = function(e) NULL)
    if (is.null(f) || any(f$uniquenesses < 0.02)) next
    Ld <- unclass(f$loadings)
    for (kk in 1:q) for (ii in 1:p) cases[[length(cases) + 1]] <- case("farotmin", c(p, q, rot, as.vector(t(R)), p + (ii - 1) + (kk - 1) * p), as.numeric(Ld[ii, kk]), rel = 1e-2, abs = 4e-3)
    if (rot == 2) { Ph <- f$Phi; for (kk in 1:q) for (ll in 1:q) cases[[length(cases) + 1]] <- case("farotmin", c(p, q, rot, as.vector(t(R)), p + p * q + q * q + (kk - 1) * q + (ll - 1)), as.numeric(Ph[kk, ll]), rel = 1e-2, abs = 4e-3) }
  }
}
# the fit statistics of the maximum likelihood fit: "famlstat" args (p, q, n, r[p * p], k) k 0 objective, 1 STATISTIC, 2 dof, 3 PVAL, 4 BIC, 5 null chi-square, 6 RMSEA, 7 TLI, 8 CFI, 9 rms, 10 crms
for (rep in 1:12) {
  p <- sample(6:9, 1); q <- sample(1:3, 1); N <- sample(200:500, 1)
  L <- matrix(runif(p * q, 0.3, 0.8), p, q); Fm <- matrix(rnorm(N * q), N, q); X <- Fm %*% t(L) + matrix(rnorm(N * p, 0, 0.7), N, p); R <- cor(X)
  f <- tryCatch(suppressWarnings(fa(R, nfactors = q, n.obs = N, fm = "ml", rotate = "none")), error = function(e) NULL)
  if (is.null(f) || any(f$uniquenesses < 0.02) || f$dof < 1) next
  v <- c(f$objective, f$STATISTIC, f$dof, f$PVAL, f$BIC, f$null.chisq, f$RMSEA[1], f$TLI, f$CFI, f$rms, f$crms)
  for (k in 1:11) cases[[length(cases) + 1]] <- case("famlstatistics", c(p, q, N, as.vector(t(R)), k - 1), as.numeric(v[k]), rel = 1e-3, abs = 1e-5)
}
# splitHalf(r, brute = TRUE), any p from 4 to 10 (odd p: halves of floor(p / 2) and the rest): "splithalf" args (p, r[p * p] row-major, k) k 0 maxrb, 1 minrb, 2 meanr, 3 med.r, 4 lambda6
for (rep in 1:12) {
  p <- sample(4:10, 1); N <- sample(150:400, 1); L <- runif(p, 0.3, 0.8); X <- outer(rnorm(N), L) + matrix(rnorm(N * p, 0, 0.7), N, p); R <- cor(X)
  s <- suppressWarnings(splitHalf(R, raw = TRUE, brute = TRUE)); v <- c(s$maxrb, s$minrb, s$meanr, s$med.r, s$lambda6)
  for (k in 1:5) cases[[length(cases) + 1]] <- case("splithalf", c(p, as.vector(t(R)), k - 1), as.numeric(v[k]), rel = 1e-9, abs = 1e-11)
}
emit("psychfa", "psych", list(cases))
