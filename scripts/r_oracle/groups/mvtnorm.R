# mvtnorm: dmvnorm, dmvt (log densities), rmvnorm and rmvt under set.seed.
#   dmvnorm: (p, x[p], mean[p], sigma[p*p] by row)   dmvt: (p, df, x[p], delta[p], sigma[p*p])
#   rmvnorm: (seed, method 0 eigen 1 chol, n, p, mean[p], sigma[p*p], pos)   rmvt: (seed, method, n, p, df, delta[p], sigma[p*p], pos)
#   pos is the 0-based position in the n x p result read by row
library(mvtnorm)
set.seed(20261115)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-11, abs = 1e-12)
rsig <- function(p) { m <- matrix(rnorm(p * p), p); round(crossprod(m) + diag(p) * 0.3, 4) }
rowvec <- function(m) as.vector(t(m))
for (k in 1:30) {
  p <- 1 + k %% 4
  s <- rsig(p); mu <- round(rnorm(p), 3); x <- round(rnorm(p) * 1.5, 3)
  add("dmvnorm", c(p, x, mu, rowvec(s)), dmvnorm(x, mu, s, log = TRUE))
  for (df in c(1, 3, 10.5)) add("dmvt", c(p, df, x, mu, rowvec(s)), dmvt(x, mu, s, df = df, log = TRUE))
}
s0 <- matrix(c(1, 1, 1, 1), 2)
add("dmvnorm", c(2, 0.5, 0.5, 0.5, 0.5, rowvec(s0)), dmvnorm(c(0.5, 0.5), c(0.5, 0.5), s0, log = TRUE))
add("dmvnorm", c(2, 0.1, 0.5, 0.5, 0.5, rowvec(s0)), dmvnorm(c(0.1, 0.5), c(0.5, 0.5), s0, log = TRUE))
for (seed in c(1, 2, 3)) for (p in 2:4) for (method in c("eigen", "chol")) {
  s <- rsig(p); mu <- round(rnorm(p), 2); n <- 4
  set.seed(seed); r <- rmvnorm(n, mu, s, method = method)
  mt <- if (method == "eigen") 0 else 1
  for (i in seq_along(t(r))) add("rmvnorm", c(seed, mt, n, p, mu, rowvec(s), i - 1), as.vector(t(r))[i])
  set.seed(seed); r <- rmvt(n, s, df = 5, delta = mu, method = method)
  for (i in seq_along(t(r))) add("rmvt", c(seed, mt, n, p, 5, mu, rowvec(s), i - 1), as.vector(t(r))[i])
}
set.seed(20261115)
emit("mvtnorm", "mvtnorm", list(cases))
