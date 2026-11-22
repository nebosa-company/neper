# ks kde.test for two samples: 2-d with H1, H2 given, 1-d with h1, h2, var.fhat1, var.fhat2 given.
#   args: "kt2" (n1, n2, H1 row-major 4, H2 row-major 4, which, x1 row-major, x2 row-major)
#         "kt1" (n1, n2, h1, h2, v1, v2, which, x1, x2)
#   which: 0 Tstat, 1 zstat, 2 pvalue, 3 var, 4 var.fhat1, 5 mean
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
rowvec <- function(m) as.vector(t(m))
spd <- function() { B <- matrix(runif(4, -0.4, 0.4), 2, 2); crossprod(B) + diag(runif(2, 0.05, 0.3)) }
set.seed(20262010)
for (rep in 1:6) {
  n1 <- sample(30:90, 1); n2 <- sample(30:90, 1)
  x1 <- round(cbind(rnorm(n1), rnorm(n1)), 5); x2 <- round(cbind(rnorm(n2, 0.3), rnorm(n2, 0, 1.2)), 5)
  H1 <- spd(); H2 <- spd()
  r <- kde.test(x1, x2, H1 = H1, H2 = H2)
  vals <- c(r$Tstat, r$zstat, r$pvalue, r$var, r$var.fhat1, r$mean)
  for (w in 0:5) add("kt2", c(n1, n2, rowvec(H1), rowvec(H2), w, rowvec(x1), rowvec(x2)), vals[w + 1])
  a1 <- rnorm(n1); a2 <- rnorm(n2, 0.4, 1.3)
  h1 <- runif(1, 0.2, 0.6); h2 <- runif(1, 0.2, 0.6); v1 <- runif(1, 0.01, 0.05); v2 <- runif(1, 0.01, 0.05)
  r <- kde.test(a1, a2, h1 = h1, h2 = h2, var.fhat1 = v1, var.fhat2 = v2)
  vals <- c(r$Tstat, r$zstat, r$pvalue, r$var, r$var.fhat1, r$mean)
  for (w in 0:5) add("kt1", c(n1, n2, h1, h2, v1, v2, w, a1, a2), vals[w + 1])
}
#   "kt2d" (n1, n2, which, x1 row-major, x2 row-major) and "kt1d" (n1, n2, which, x1, x2): every default (Hpi.kfe / hpi.kfe bandwidths, default var.fhat);
#   which 0..5 as above, 6 the bandwidth of x1 (H1[1, 1] in 2-d), 7 that of x2 (H2[2, 2] in 2-d)
for (rep in 1:5) {
  n1 <- sample(30:90, 1); n2 <- sample(30:90, 1)
  x1 <- round(cbind(rnorm(n1), rnorm(n1)), 5); x2 <- round(cbind(rnorm(n2, 0.3), rnorm(n2, 0, 1.2)), 5)
  r <- kde.test(x1, x2)
  vals <- c(r$Tstat, r$zstat, r$pvalue, r$var, r$var.fhat1, r$mean, r$H1[1, 1], r$H2[2, 2])
  for (w in 0:7) cases[[length(cases) + 1]] <- case("kt2d", c(n1, n2, w, rowvec(x1), rowvec(x2)), vals[w + 1], rel = 1e-9, abs = 1e-13)
  a1 <- rnorm(n1); a2 <- rnorm(n2, 0.4, 1.3)
  r <- kde.test(a1, a2)
  vals <- c(r$Tstat, r$zstat, r$pvalue, r$var, r$var.fhat1, r$mean, r$h1, r$h2)
  for (w in 0:7) cases[[length(cases) + 1]] <- case("kt1d", c(n1, n2, w, a1, a2), vals[w + 1], rel = 1e-9, abs = 1e-13)
}
emit("ks2dtest", "ks", list(cases))
