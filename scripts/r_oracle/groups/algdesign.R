# AlgDesign: gen.factorial and eval.design on a model matrix.
#   gen: (nf, levels[nf], center, q)  fn "gen_sum" "gen_w": sum and position-weighted sum (row-major) of the grid
#   eval: (n, k, nc, X[n*k], C[nc*k], q) fn "ev": q 0 determinant 1 A 2 I 3 Geff 4 Deffbound 5 diagonality 6 gmean.variances
suppressMessages(library(AlgDesign))
cases <- list()
add <- function(fn, args, want, tol = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = tol)
set.seed(20261116)
for (rep in 1:30) {
  nf <- sample(1:3, 1); lv <- sample(2:5, nf, TRUE); ce <- rbinom(1, 1, 0.5)
  g <- if (nf == 1) gen.factorial(lv, nVars = 1, center = ce == 1) else gen.factorial(lv, center = ce == 1)
  v <- as.vector(t(as.matrix(g)))
  add("gen_sum", c(nf, lv, ce, 0), sum(v)); add("gen_w", c(nf, lv, ce, 0), sum(seq_along(v) * v))
}
for (rep in 1:20) {
  cand <- gen.factorial(c(3, 3, 3), center = TRUE); dc <- data.frame(cand)
  n <- sample(8:20, 1); des <- dc[sort(sample(nrow(dc), n)), ]
  f <- if (rep %% 2 == 0) ~ X1 + X2 + X3 else ~ X1 + X2 + X3 + X1:X2
  X <- model.matrix(f, des); C <- model.matrix(f, dc)
  if (qr(crossprod(X))$rank < ncol(X)) next
  e <- eval.design(f, des, X = dc)
  k <- ncol(X); a <- c(nrow(X), k, nrow(C), as.vector(X), as.vector(C))
  vals <- c(e$determinant, e$A, e$I, e$Geff, e$Deffbound, e$diagonality, e$gmean.variances)
  for (q in seq_along(vals)) add("ev", c(a, q - 1), vals[q], if (q %in% c(4, 5, 6)) 2e-3 else 1e-9)
}
emit("algdesign", "AlgDesign", list(cases))
