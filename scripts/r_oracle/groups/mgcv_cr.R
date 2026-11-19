# mgcv: the cubic regression spline basis and penalty, smoothCon(s(x, bs = "cr", k = k), absorb.cons = FALSE). Args: (n, k, what, idx, x[n]): what 0 knot[idx], 1 X[idx] (row-major n by k), 2 S[idx] (k by k).
suppressMessages(library(mgcv))
cases <- list()
set.seed(20262301)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("cr", args, want, rel = 1e-9, abs = 1e-11)
for (rep in 1:12) {
  n <- sample(25:70, 1); k <- sample(4:12, 1)
  x <- round(runif(n, 0, 10), 3)
  sm <- smoothCon(s(x, bs = "cr", k = k), data.frame(x = x), absorb.cons = FALSE)[[1]]
  hdr <- function(w, i) c(n, k, w, i, x)
  for (i in seq_len(k)) add(hdr(0, i - 1), sm$xp[i])
  X <- as.vector(t(sm$X)); for (i in seq_along(X)) add(hdr(1, i - 1), X[i])
  S <- as.vector(t(sm$S[[1]])); for (i in seq_along(S)) add(hdr(2, i - 1), S[i])
}
# the same smooth with the sum-to-zero constraint absorbed (the default): what 3 X[idx] (n by k - 1), 4 S[idx] (k - 1 square)
for (rep in 1:12) {
  n <- sample(25:70, 1); k <- sample(4:12, 1)
  x <- round(runif(n, 0, 10), 3)
  sm <- smoothCon(s(x, bs = "cr", k = k), data.frame(x = x), absorb.cons = TRUE)[[1]]
  hdr <- function(w, i) c(n, k, w, i, x)
  X <- as.vector(t(sm$X)); for (i in seq_along(X)) add(hdr(3, i - 1), X[i])
  S <- as.vector(t(sm$S[[1]])); for (i in seq_along(S)) add(hdr(4, i - 1), S[i])
}
emit("mgcv_cr", "mgcv", list(cases))
