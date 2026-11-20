# RSpectra: eigs_sym with a function operator A(x) = D x + u (u' x) + w (w' x) (diagonal plus two rank-one terms, symmetric). R has no sigma for a function; which acts on the operator itself.
# Args: (n, k, which 0 LM 1 LA 2 SA 3 SM 5 BE, part, d[n], u[n], w[n]); part 0 values (sum of value * position), 1 sign-aligned vectors (sum of entry * column-major position).
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262354)
nm <- c("LM", "LA", "SA", "SM", NA, "BE")
for (rep in 1:36) {
  n <- sample(20:40, 1); k <- sample(2:4, 1); wh <- c(0, 1, 2, 3, 5)[(rep - 1) %% 5 + 1]; d <- round(rnorm(n), 4); u <- round(rnorm(n) * 0.3, 4); w <- round(rnorm(n) * 0.3, 4)
  f <- function(x, args) d * x + u * sum(u * x) + w * sum(w * x)
  ev <- eigen(diag(d) + tcrossprod(u) + tcrossprod(w), symmetric = TRUE)$values
  key <- switch(wh + 1, abs(ev), ev, -ev, -abs(ev), NULL, ev)
  if (wh != 5) { srt <- sort(key, decreasing = TRUE); if (abs(srt[k] - srt[k + 1]) < 1e-6) next }
  o <- tryCatch(suppressWarnings(eigs_sym(f, k, n = n, which = nm[wh + 1], opts = list(tol = 1e-14, maxitr = 5000))), error = function(e) NULL)
  if (is.null(o) || length(o$values) != k) next
  V <- apply(o$vectors, 2, function(v) v * sign(v[which.max(abs(v))]))
  cases[[length(cases) + 1]] <- case("op", c(n, k, wh, 0, d, u, w), sum(o$values * seq_along(o$values)), rel = 1e-9, abs = 1e-11)
  cases[[length(cases) + 1]] <- case("op", c(n, k, wh, 1, d, u, w), sum(as.vector(V) * seq_along(V)), rel = 1e-9, abs = 1e-11)
}
emit("spectra_op", "RSpectra", list(cases))
