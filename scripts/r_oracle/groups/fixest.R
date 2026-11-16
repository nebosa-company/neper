# fixest feols with one or two fixed effects: coefficients and the iid, hetero and clustered (by the first fixed effect) standard errors.
#   args: (n, k, G1, G2, y[n], x[n*k] row-major, fe1[n] 0-based, fe2[n] 0-based (G2 > 0 only))
#   fn "coef" "iid" "het" "cl" (each weighted by position)
suppressMessages(library(fixest))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-8)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20261216)
for (rep in 1:24) {
  G1 <- sample(5:15, 1); T <- sample(4:8, 1); two <- rep %% 2; k <- sample(1:3, 1)
  fe1 <- rep(seq_len(G1), each = T); fe2 <- rep(seq_len(T), G1); n <- G1 * T
  keep <- sort(sample(n, round(n * 0.9))); fe1 <- fe1[keep]; fe2 <- fe2[keep]; n <- length(keep)
  x <- matrix(rnorm(n * k), n) + rnorm(G1)[fe1] * 0.3; y <- as.vector(x %*% rnorm(k)) + rnorm(G1)[fe1] + (if (two) rnorm(T)[fe2] else 0) + rnorm(n)
  d <- data.frame(y, x, f1 = factor(fe1), f2 = factor(fe2)); names(d)[2:(1 + k)] <- paste0("x", seq_len(k))
  fm <- as.formula(paste("y ~", paste0("x", seq_len(k), collapse = " + "), "|", if (two) "f1 + f2" else "f1"))
  m <- feols(fm, d, fixef.tol = 3e-12, fixef.iter = 10000)
  g2 <- if (two) length(unique(fe2)) else 0
  fe2c <- match(fe2, sort(unique(fe2))) - 1; fe1c <- match(fe1, sort(unique(fe1))) - 1
  a <- c(n, k, length(unique(fe1)), g2, y, as.vector(t(x)), fe1c, if (two) fe2c else NULL)
  add("coef", a, ws(coef(m))); add("iid", a, ws(se(m, vcov = "iid"))); add("het", a, ws(se(m, vcov = "hetero"))); add("cl", a, ws(se(m, vcov = ~f1)))
}
emit("fixest", "fixest", list(cases))
