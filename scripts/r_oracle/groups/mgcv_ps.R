# mgcv: the P-spline smooth, smoothCon(s(x, bs = "ps", k = k, m = c(m1, m2)), absorb.cons = FALSE). Args: (n, k, m1, m2, what, idx, x[n]): what 0 knot[idx], 1 X[idx] (n by k row-major), 2 S[idx] (k by k, scaled by smoothCon).
suppressMessages(library(mgcv))
cases <- list()
set.seed(20262302)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("ps", args, want, rel = 1e-9, abs = 1e-11)
for (rep in 1:12) {
  n <- sample(25:70, 1); m1 <- sample(1:3, 1); m2 <- sample(1:3, 1); k <- sample((m1 + 3):(m1 + 10), 1)
  x <- round(runif(n, 0, 10), 3)
  sm <- smoothCon(s(x, bs = "ps", k = k, m = c(m1, m2)), data.frame(x = x), absorb.cons = FALSE)[[1]]
  hdr <- function(w, i) c(n, k, m1, m2, w, i, x)
  for (i in seq_along(sm$knots)) add(hdr(0, i - 1), sm$knots[i])
  X <- as.vector(t(sm$X)); for (i in seq_along(X)) add(hdr(1, i - 1), X[i])
  S <- as.vector(t(sm$S[[1]])); for (i in seq_along(S)) add(hdr(2, i - 1), S[i])
}
emit("mgcv_ps", "mgcv", list(cases))
