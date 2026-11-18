# aod: varbin's non-bootstrap rows, iccbin method C and donner. drs args: (0 rho / 1 X2, 0, 0, k, n..., y..., group codes 0-based..., G) under the name "donner". wald.test: (0 chi2 / 1 P, q, p, b..., sigma row-major..., L row-major...) under the name "wald".
#   args: "varbin" (row 0 binomial, 1 ratio, 2 arithmetic, 3 jackknife; part 0 p, 1 varp, 2 lower, 3 upper; alpha; k; n...; y...); "iccbin" (0, 0, 0, k, n..., y...)
suppressMessages(library(aod))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-13)
set.seed(20262006)
for (rep in 1:25) {
  k <- sample(6:30, 1); n <- sample(3:25, k, TRUE); pr <- runif(k, 0.1, 0.7); y <- rbinom(k, n, pr)
  df <- data.frame(n = n, y = y)
  vb <- suppressWarnings(varbin(n, y, df, alpha = 0.1, R = 200))@tab
  for (r in 0:3) { add("varbin", c(r, 0, 0.1, k, n, y), vb[r + 1, 1]); add("varbin", c(r, 1, 0.1, k, n, y), vb[r + 1, 2]); add("varbin", c(r, 2, 0.1, k, n, y), vb[r + 1, 3]); add("varbin", c(r, 3, 0.1, k, n, y), vb[r + 1, 4]) }
  ic <- iccbin(n, y, df, method = "C")@rho; add("iccbin", c(0, 0, 0, k, n, y), ic)
}
for (rep in 1:20) {
  G <- sample(2:4, 1); k <- sample((2 * G + 2):(5 * G + 6), 1)
  grp <- c(0:(G - 1), sample(0:(G - 1), k - G, TRUE)); n <- sample(3:30, k, TRUE); y <- rbinom(k, n, runif(k, 0.15, 0.65))
  d <- data.frame(r = y / n, g = factor(grp), w = n)
  dr <- donner(r ~ g, weights = w, data = d)
  add("donner", c(0, 0, 0, k, n, y, grp, G), dr@rho); add("donner", c(1, 0, 0, k, n, y, grp, G), dr@X2)
}
for (rep in 1:25) {
  p <- sample(2:6, 1); q <- sample(1:min(p, 3), 1)
  b <- rnorm(p, 0, 2); A <- matrix(rnorm(p * p), p, p); S <- crossprod(A) / p + diag(p) * 0.3
  L <- matrix(rnorm(q * p), q, p)
  w <- wald.test(b = b, Sigma = S, L = L)$result$chi2
  add("wald", c(0, q, p, b, as.vector(t(S)), as.vector(t(L))), w[["chi2"]]); add("wald", c(1, q, p, b, as.vector(t(S)), as.vector(t(L))), w[["P"]])
}
emit("aod", "aod", list(cases))
