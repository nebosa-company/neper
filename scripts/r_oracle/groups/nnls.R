# nnls: the Lawson-Hanson non-negative least squares.
#   args: (m, n, A column-major..., b...)    fn "x" (position last), "deviance", "nsetp"
library(nnls)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-9)
set.seed(20261115)
probs <- list()
for (rep in 1:12) {
  m <- c(10, 15, 20, 8, 30, 12)[(rep - 1) %% 6 + 1]; n <- c(3, 5, 8, 4, 10, 6)[(rep - 1) %% 6 + 1]
  A <- matrix(round(rnorm(m * n), 3), m, n)
  xt <- c(runif(ceiling(n / 2), 0.5, 3), rep(0, n - ceiling(n / 2)))
  b <- as.numeric(A %*% xt + round(rnorm(m, 0, if (rep > 6) 2 else 0.3), 3))
  probs[[length(probs) + 1]] <- list(A = A, b = round(b, 3))
}
# ill-conditioned: nearly collinear columns, and a Hilbert-like matrix
H <- outer(1:8, 1:5, function(i, j) 1 / (i + j - 1)); probs[[length(probs) + 1]] <- list(A = H, b = round(H %*% c(1, 0, 2, 0, 1) + rnorm(8, 0, 1e-4), 6))
Ac <- matrix(round(rnorm(20 * 4), 3), 20, 4); Ac[, 4] <- Ac[, 1] + round(rnorm(20, 0, 1e-3), 4); probs[[length(probs) + 1]] <- list(A = Ac, b = round(rnorm(20), 3))
Ad <- matrix(round(rnorm(15 * 4), 3), 15, 4); Ad[, 3] <- Ad[, 1]; probs[[length(probs) + 1]] <- list(A = Ad, b = round(Ad %*% c(1, 2, 0, 0.5) + rnorm(15, 0, 0.1), 3))
Zc <- matrix(round(rnorm(12 * 3), 3), 12, 3); Zc[, 2] <- 0; probs[[length(probs) + 1]] <- list(A = Zc, b = round(rnorm(12), 3))
for (pb in probs) {
  r <- tryCatch(nnls(pb$A, pb$b), error = function(e) NULL)
  if (is.null(r)) next
  m <- nrow(pb$A); n <- ncol(pb$A)
  a <- c(m, n, as.numeric(pb$A), pb$b)
  for (i in seq_len(n)) add("x", c(a, i - 1), r$x[i])
  add("deviance", a, r$deviance); add("nsetp", a, r$nsetp)
}
emit("nnls", "nnls", list(cases))
