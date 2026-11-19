# psych: alpha, KMO, cortest.bartlett, ICC (six forms), cohen.kappa, mardia.
#   data: (n, p, X[n*p] column-major, q); fn "alpha_raw" "alpha_std" "kmo" (overall) "kmo_i" (item q) "bart_chi" "bart_df" "icc1".."icc6" "mardia_b1" "mardia_b2"
#   kappa: (k, table[k*k] row-major)  fn "kappa"
suppressMessages(library(psych))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261116)
for (rep in 1:12) {
  n <- sample(30:80, 1); p <- sample(3:6, 1)
  f <- rnorm(n); X <- sapply(1:p, function(j) round(f * runif(1, 0.5, 1.5) + rnorm(n), 3))
  a <- c(n, p, X)
  al <- suppressWarnings(alpha(X, check.keys = FALSE))$total
  add("alpha_raw", c(a, 0), al$raw_alpha); add("alpha_std", c(a, 0), al$std.alpha)
  R <- cor(X)
  add("kmo", c(a, 0), KMO(R)$MSA)
  for (q in 1:p) add("kmo_i", c(a, q - 1), KMO(R)$MSAi[q])
  b <- cortest.bartlett(R, n = n)
  add("bart_chi", c(a, 0), b$chisq); add("bart_df", c(a, 0), b$df)
  ic <- suppressWarnings(ICC(X)$results$ICC[1:6])
  for (q in 1:6) cases[[length(cases) + 1]] <- case(paste0("icc", q), c(a, 0), ic[q], rel = 1e-5, abs = 1e-7)
  pp <- min(p, 3)
  m <- mardia(X[, 1:pp], plot = FALSE)
  add("mardia_b1", c(n, pp, X[, 1:pp], 0), m$b1p); add("mardia_b2", c(n, pp, X[, 1:pp], 0), m$b2p)
}
for (rep in 1:8) {
  k <- sample(2:4, 1); tb <- matrix(rpois(k * k, 6) + diag(k) * 10, k, k)
  add("kappa", c(k, t(tb)), cohen.kappa(tb)$kappa)
}
# describe of one column ("desc": n, x..., which): n mean sd median trimmed mad min max range skew kurtosis se
for (rep in 1:25) {
  n <- sample(10:80, 1); x <- round(rexp(n, 0.2) + rnorm(n), 3)
  ds <- describe(x)
  v <- c(ds$n, ds$mean, ds$sd, ds$median, ds$trimmed, ds$mad, ds$min, ds$max, ds$range, ds$skew, ds$kurtosis, ds$se)
  for (w in 0:11) cases[[length(cases) + 1]] <- case("desc", c(n, x, w), as.numeric(v[w + 1]), rel = 1e-8, abs = 1e-10)
}
# describeBy of one column by a grouping variable: "descby" (n, x[n], g[n] 0-based, group, which) with which as for "desc"
for (rep in 1:15) {
  n <- sample(40:120, 1); k <- sample(2:3, 1); g <- sample(0:(k - 1), n, TRUE); x <- round(rexp(n, 0.2) + rnorm(n) + g, 3)
  db <- suppressWarnings(psych::describeBy(x, g, mat = TRUE))
  for (gr in 0:(k - 1)) {
    row <- db[db$group1 == gr, ]
    v <- c(row$n, row$mean, row$sd, row$median, row$trimmed, row$mad, row$min, row$max, row$range, row$skew, row$kurtosis, row$se)
    for (w in 0:11) cases[[length(cases) + 1]] <- case("descby", c(n, x, g, gr, w), as.numeric(v[w + 1]), rel = 1e-8, abs = 1e-10)
  }
}
# corr.test: "ctest" args (n, p, X column-major, i, j, which) with i < j 0-based; which 0 r, 1 t, 2 p, 3 lower, 4 upper, 5 Holm-adjusted p
for (rep in 1:15) {
  n <- sample(20:60, 1); p <- sample(3:5, 1); f <- rnorm(n); X <- sapply(1:p, function(j) round(f * runif(1, 0, 1) + rnorm(n), 3)); colnames(X) <- paste0("v", 1:p)
  ct <- corr.test(X, adjust = "holm"); ci <- ct$ci2
  rn <- rownames(ci); r0 <- 0
  for (u in 1:(p - 1)) for (v in (u + 1):p) {
    r0 <- r0 + 1; base <- c(n, p, X, u - 1, v - 1)
    vals <- c(ct$r[u, v], ct$r[u, v] * sqrt((n - 2) / (1 - ct$r[u, v]^2)), 2 * pt(-abs(ct$r[u, v] * sqrt((n - 2) / (1 - ct$r[u, v]^2))), n - 2), ci$lower[r0], ci$upper[r0], ci$p.adj[r0])
    for (w in 0:5) cases[[length(cases) + 1]] <- case("ctest", c(base, w), as.numeric(vals[w + 1]), rel = 1e-8, abs = 1e-10)
  }
}
# 2 x 2 tables: "yule" "yuleY" "phi" (a, c, b, d column-major, 0); "tetra" (counts, q) q 0 rho 1 row tau 2 column tau; biserial: "bis" (n, x[n], y[n], 0)
for (rep in 1:25) {
  tb <- matrix(rpois(4, 20) + c(10, 0, 0, 10), 2)
  if (rep %% 5 == 0) tb[sample(4, 1)] <- 0
  if (all(tb > 0)) {
    add("yule", c(tb, 0), Yule(tb)); add("yuleY", c(tb, 0), Yule(tb, Y = TRUE)); add("phi", c(tb, 0), psych::phi(tb, digits = 12))
  }
  tc <- suppressMessages(tetrachoric(tb, correct = 0.5))
  cases[[length(cases) + 1]] <- case("tetra", c(tb, 0), tc$rho, rel = 1e-6, abs = 1e-7)
  cases[[length(cases) + 1]] <- case("tetra", c(tb, 1), tc$tau[1], rel = 1e-9, abs = 1e-10)
  cases[[length(cases) + 1]] <- case("tetra", c(tb, 2), tc$tau[2], rel = 1e-9, abs = 1e-10)
}
for (rep in 1:15) {
  n <- sample(30:90, 1); yy <- rbinom(n, 1, runif(1, 0.3, 0.7)); xx <- round(rnorm(n) + 0.6 * yy, 3)
  r <- suppressMessages(suppressWarnings(biserial(xx, yy)))
  add("bis", c(n, xx, yy, 0), as.numeric(r))
}
# tetrachoric of two 0 / 1 columns inside a data matrix (global thresholds): "tetrap" (n, x[n], y[n], 0)
for (rep in 1:12) {
  n <- sample(60:200, 1); p <- 3; f <- rnorm(n)
  X <- sapply(1:p, function(j) as.numeric(f * runif(1, 0.5, 1.2) + rnorm(n) > rnorm(1, 0, 0.5)))
  if (any(colMeans(X) %in% c(0, 1))) next
  tt <- suppressMessages(suppressWarnings(tetrachoric(X, smooth = FALSE)))$rho
  for (u in 1:(p - 1)) for (v in (u + 1):p) cases[[length(cases) + 1]] <- case("tetrap", c(n, X[, u], X[, v], 0), tt[u, v], rel = 1e-6, abs = 1e-7)
}
# polychoric of two columns coded 1..k inside a data matrix: "polyp" (n, k, x[n], y[n], 0); psych's sadmvn is accurate to about 1e-6
for (rep in 1:16) {
  n <- sample(150:400, 1); k <- sample(3:5, 1); f <- rnorm(n)
  X <- sapply(1:3, function(j) { z <- f * runif(1, 0.5, 1.2) + rnorm(n); as.numeric(cut(z, c(-Inf, sort(rnorm(k - 1, 0, 0.8)), Inf))) })
  if (any(apply(X, 2, function(v) length(unique(v))) != k)) next
  pc <- suppressMessages(suppressWarnings(polychoric(X, smooth = FALSE, progress = FALSE)))$rho
  for (u in 1:2) for (v in (u + 1):3) cases[[length(cases) + 1]] <- case("polyp", c(n, k, X[, u], X[, v], 0), pc[u, v], rel = 1e-4, abs = 1e-5)
}
# principal components, unrotated: "pca" (p, nf, R[p*p column-major], q) q < p*nf loading q (item q %% p, component q %/% p), then p*nf + k eigenvalue k, then p*nf + p + i communality i
for (rep in 1:14) {
  n <- sample(40:120, 1); p <- sample(3:7, 1); f <- rnorm(n); X <- sapply(1:p, function(j) f * runif(1, 0.3, 1.2) + rnorm(n)); R <- cor(X)
  nf <- sample(1:min(3, p - 1), 1)
  pc <- suppressMessages(principal(R, nfactors = nf, rotate = "none", residuals = FALSE))
  L <- unclass(pc$loadings)
  for (q in 0:(p * nf - 1)) cases[[length(cases) + 1]] <- case("pca", c(p, nf, R, q), L[(q %% p) + 1, (q %/% p) + 1], rel = 1e-8, abs = 1e-9)
  for (k in 1:p) cases[[length(cases) + 1]] <- case("pca", c(p, nf, R, p * nf + k - 1), pc$values[k], rel = 1e-8, abs = 1e-9)
  for (i in 1:p) cases[[length(cases) + 1]] <- case("pca", c(p, nf, R, p * nf + p + i - 1), pc$communality[i], rel = 1e-8, abs = 1e-9)
}
# varimax-rotated principal components: "pcav" (p, nf, R, q) q < p*nf the loading q as in "pca"
for (rep in 1:14) {
  n <- sample(40:120, 1); p <- sample(4:8, 1); f <- rnorm(n); g <- rnorm(n); X <- sapply(1:p, function(j) f * runif(1, 0, 1) + g * runif(1, 0, 1) + rnorm(n)); R <- cor(X)
  nf <- sample(2:min(3, p - 1), 1)
  pc <- suppressMessages(principal(R, nfactors = nf, rotate = "varimax", residuals = FALSE))
  L <- unclass(pc$loadings)
  for (q in 0:(p * nf - 1)) cases[[length(cases) + 1]] <- case("pcav", c(p, nf, R, q), L[(q %% p) + 1, (q %/% p) + 1], rel = 1e-6, abs = 1e-7)
}
# principal-axis factor analysis, unrotated: "fapa" (p, nf, R, q) q < p*nf loading q, p*nf + i communality i
for (rep in 1:14) {
  n <- sample(60:160, 1); p <- sample(5:8, 1); f <- rnorm(n); g <- rnorm(n); X <- sapply(1:p, function(j) f * runif(1, 0.2, 1) + g * runif(1, 0, 0.8) + rnorm(n)); R <- cor(X)
  nf <- sample(1:2, 1)
  fa1 <- suppressMessages(suppressWarnings(fa(R, nfactors = nf, fm = "pa", rotate = "none", n.obs = n, warnings = FALSE)))
  L <- unclass(fa1$loadings)
  for (q in 0:(p * nf - 1)) cases[[length(cases) + 1]] <- case("fapa", c(p, nf, R, q), L[(q %% p) + 1, (q %/% p) + 1], rel = 1e-7, abs = 1e-8)
  for (i in 1:p) cases[[length(cases) + 1]] <- case("fapa", c(p, nf, R, p * nf + i - 1), fa1$communality[i], rel = 1e-7, abs = 1e-8)
}
# scoreItems, complete data, totals = FALSE: "score" (n, p, S, min, max, X[n*p], keys[p*S], q) q < n*S score; n*S + s alpha s; + S av.r s; + 2S G6 s; + 3S + u + v*S correlation of scale scores u, v
for (rep in 1:10) {
  n <- sample(40:100, 1); p <- sample(5:9, 1); f <- rnorm(n); X <- sapply(1:p, function(j) round(f * runif(1, 0.3, 1) + rnorm(n), 2)); colnames(X) <- paste0("V", 1:p)
  S <- 2; keys <- matrix(0, p, S); h <- p %/% 2; keys[1:h, 1] <- 1; keys[(h + 1):p, 2] <- sample(c(1, -1), p - h, TRUE); if (all(keys[, 2] <= 0)) keys[h + 1, 2] <- 1
  kl <- list(a = which(keys[, 1] != 0) * keys[keys[, 1] != 0, 1], b = which(keys[, 2] != 0) * keys[keys[, 2] != 0, 2])
  s <- suppressMessages(suppressWarnings(scoreItems(kl, X, totals = FALSE, min = -6, max = 6, impute = "none")))
  base <- c(n, p, S, -6, 6, X, keys)
  for (q in 0:(n * S - 1)) cases[[length(cases) + 1]] <- case("score", c(base, q), s$scores[(q %% n) + 1, (q %/% n) + 1], rel = 1e-8, abs = 1e-10)
  for (u in 1:S) {
    cases[[length(cases) + 1]] <- case("score", c(base, n * S + u - 1), s$alpha[1, u], rel = 1e-8, abs = 1e-10)
    cases[[length(cases) + 1]] <- case("score", c(base, n * S + S + u - 1), s$av.r[u], rel = 1e-8, abs = 1e-10)
    if (is.finite(s$G6[1, u])) cases[[length(cases) + 1]] <- case("score", c(base, n * S + 2 * S + u - 1), s$G6[1, u], rel = 1e-8, abs = 1e-10)
  }
  for (u in 1:S) for (v in 1:S) cases[[length(cases) + 1]] <- case("score", c(base, n * S + 3 * S + (u - 1) + (v - 1) * S), s$cor[u, v], rel = 1e-8, abs = 1e-10)
}
emit("psych", "psych", list(cases))
