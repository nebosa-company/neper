# ks kroc with the bandwidths given, in one and two dimensions.
#   args: (d, n1, n2, which, idx, hy, H d*d, x1 row-major, x2 row-major); which 0 = ROC estimate at index idx (0-based of 401), 1 = auc, youden, LR minus, LR plus at idx 0..3
suppressMessages(library(ks))
cases <- list()
add <- function(args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case("kroc", args, want, rel = rel, abs = 1e-12)
rowvec <- function(m) as.vector(t(m))
spd <- function(d) { B <- matrix(runif(d * d, -0.3, 0.3), d, d); crossprod(B) + diag(runif(d, 0.08, 0.3), d) }
set.seed(20262015)
for (spec in list(c(1, 60, 80), c(1, 120, 90), c(1, 200, 150), c(2, 60, 70), c(2, 100, 80), c(2, 600, 120))) {
  d <- spec[1]; n1 <- spec[2]; n2 <- spec[3]
  x1 <- round(matrix(rnorm(n1 * d), n1, d), 5)
  x2 <- round(matrix(rnorm(n2 * d, 0.8, 1.2), n2, d), 5)
  H <- spd(d); hy <- runif(1, 0.15, 0.4)
  r <- if (d == 1) kroc(as.vector(x1), as.vector(x2), h1 = sqrt(H[1, 1]), hy = hy) else kroc(x1, x2, H1 = H, hy = hy)
  tail <- c(hy, rowvec(H), rowvec(x1), rowvec(x2))
  for (k in c(1, 2, 20, 60, 100, 150, 200, 250, 300, 350, 390, 400, 401)) add(c(d, n1, n2, 0, k - 1, tail), r$estimate[k])
  ind <- c(r$indices$auc, r$indices$youden, r$indices$LR$minus, r$indices$LR$plus)
  for (k in 1:4) add(c(d, n1, n2, 1, k - 1, tail), ind[k])
}
emit("ksroc", "ks", list(cases))
