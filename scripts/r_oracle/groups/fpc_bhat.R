# fpc: bhattacharyya.dist. Args: (d, mu1[d], mu2[d], Sigma1 row-major [d * d], Sigma2 row-major [d * d])
suppressMessages(library(fpc))
cases <- list()
set.seed(20262390)
rs <- function(d) { A <- matrix(rnorm(d * d), d, d); S <- crossprod(A) + diag(d) * 0.3; S }
for (rep in 1:60) {
  d <- sample(1:4, 1); m1 <- rnorm(d); m2 <- rnorm(d); S1 <- rs(d); S2 <- rs(d)
  cases[[length(cases) + 1]] <- case("bhat", c(d, m1, m2, as.vector(t(S1)), as.vector(t(S2))), bhattacharyya.dist(m1, m2, S1, S2), rel = 1e-10, abs = 1e-12)
}
emit("fpc_bhat", "fpc", list(cases))
