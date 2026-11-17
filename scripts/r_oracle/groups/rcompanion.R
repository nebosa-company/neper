# rcompanion effect sizes: epsilonSquared, freemanTheta, cliffDelta, vda, cramerV and cohenW.
#   epsilon, freeman: (n, k, x[n], g[n] 0-based);  cliff, vda: (n1, n2, x, y);  cramer: (r, c, bias, table row-major); cohenw: (r, c, table)
suppressMessages(library(rcompanion))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261127)
for (rep in 1:10) {
  k <- c(3, 4, 5)[(rep - 1) %% 3 + 1]; sz <- sample(8:20, k, TRUE); g <- rep(0:(k - 1), sz); n <- sum(sz)
  x <- round(rnorm(n, g * 0.4, 1), 1)
  add("epsilon", c(n, k, x, g), epsilonSquared(x, factor(g))); add("freeman", c(n, k, x, g), freemanTheta(x, factor(g)))
  A <- round(rnorm(sz[1], 0.5, 1), 1); B <- round(rnorm(sz[2], 0, 1.2), 1)
  add("cliff", c(length(A), length(B), A, B), cliffDelta(x = A, y = B)); add("vda", c(length(A), length(B), A, B), vda(x = A, y = B))
  r <- c(2, 3, 4)[(rep - 1) %% 3 + 1]; cc <- c(3, 2, 4)[(rep - 1) %% 3 + 1]
  tb <- matrix(rpois(r * cc, 12) + 1, r, cc)
  add("cramer", c(r, cc, 0, as.vector(t(tb))), cramerV(tb)); add("cramer", c(r, cc, 1, as.vector(t(tb))), cramerV(tb, bias.correct = TRUE))
  add("cohenw", c(r, cc, as.vector(t(tb))), cohenW(tb))
}
# scheirerRayHare(y ~ x1 + x2): "srh" (n, l1, l2, g1[n], g2[n], y[n], index) index 0..2 H of x1, x2, x1:x2; 3..5 their p values
for (rep in 1:30) {
  l1 <- sample(2:4, 1); l2 <- sample(2:3, 1); r <- sample(2:5, 1); bal <- rep %% 2 == 0
  g1 <- rep(rep(1:l1, each = r), l2); g2 <- rep(1:l2, each = r * l1); if (!bal) { k <- sample(length(g1), length(g1) - 2); g1 <- g1[k]; g2 <- g2[k] }
  n <- length(g1); y <- round(rnorm(n) + 0.5 * g1 + 0.3 * g2, if (rep %% 3 == 0) 1 else 3)
  if (any(table(g1, g2) == 0)) next
  d <- data.frame(y = y, x1 = factor(g1), x2 = factor(g2)); z <- tryCatch(scheirerRayHare(y ~ x1 + x2, data = d, verbose = FALSE), error = function(e) NULL); if (is.null(z)) next
  vals <- c(z[1:3, 3], z[1:3, 4]); for (j in 0:5) add("srh", c(n, l1, l2, g1 - 1, g2 - 1, y, j), vals[j + 1])
}
# nominalSymmetryTest global p: "nsym" (n, table row-major)
for (rep in 1:30) {
  n <- sample(2:5, 1); M <- matrix(sample(1:15, n * n, TRUE), n); r <- suppressWarnings(nominalSymmetryTest(M))
  v <- if (n == 2) r$Global.test.for.symmetry$p.value else r$Global.test.for.symmetry$p.value; add("nsym", c(n, as.vector(t(M))), v)
}
# nominalSymmetryTest pairwise: "nsp" (n, index, table row-major) index >= 0 the adjusted p of pair index, index < 0 the raw p of pair -index - 1
for (rep in 1:30) {
  n <- sample(3:5, 1); M <- matrix(sample(0:12, n * n, TRUE), n); r <- suppressWarnings(nominalSymmetryTest(M))$Pairwise.symmetry.tests
  pv <- suppressWarnings(as.numeric(r$p.value)); pa <- suppressWarnings(as.numeric(r$p.adjust))
  for (j in seq_along(pv)) { add("nsp", c(n, -(j), as.vector(t(M))), pv[j]); add("nsp", c(n, j - 1, as.vector(t(M))), pa[j]) }
}
emit("rcompanion", "rcompanion", list(cases))
