# kernlab sigest and ksvm's automatic sigma (kernel = "rbfdot" without kpar: mean(sigest(x, scaled = FALSE)[c(1, 3)]) on the already scaled data), on R's stream.
#   sigest args: (m, nf, frac, scaled, seed, x[m*nf] row-major); fn "sigest" (the three values weighted by position)
#   ksvm args: (n, p, K, C, seed, cls[n] 1-based, x[n*p] row-major); fn "sigma" (kpar(kernelf(model))$sigma), "coef" (all pairs' signed coefficients, position-weighted), "b" (position-weighted)
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20261601)
fracs <- c(0.5, 0.3, 0.8, 1, 0.5)
for (rep in 1:30) {
  m <- sample(20:80, 1); nf <- sample(2:5, 1); x <- matrix(rnorm(m * nf, 0, 2), m); frac <- fracs[(rep - 1) %% 5 + 1]; sc <- rep %% 2 == 0
  sd0 <- sample(100000, 1)
  set.seed(sd0)
  sr <- sigest(x, frac = frac, scaled = sc)
  add("sigest", c(m, nf, frac, sc, sd0, as.vector(t(x))), ws(sr))
}
for (rep in 1:18) {
  K <- c(2, 3, 4)[(rep - 1) %% 3 + 1]; p <- sample(2:4, 1); per <- sample(8:14, 1); n <- K * per
  ctr <- matrix(rnorm(K * p, 0, 1.2), K); cls <- rep(1:K, per)[sample(n)]
  x <- ctr[cls, , drop = FALSE] + matrix(rnorm(n * p), n)
  C <- runif(1, 0.5, 8)
  sd0 <- sample(100000, 1)
  set.seed(sd0)
  m <- ksvm(x, factor(cls), type = "C-svc", kernel = "rbfdot", C = C, scaled = TRUE, cross = 0)
  a <- c(n, p, K, C, sd0, cls, as.vector(t(x)))
  full <- unlist(lapply(seq_along(alphaindex(m)), function(q) { f <- numeric(n); f[alphaindex(m)[[q]]] <- coef(m)[[q]]; f }))
  add("sigma", a, kpar(kernelf(m))$sigma); add("coef", a, ws(full)); add("b", a, ws(b(m)))
}
emit("kernlabsig", "kernlab", list(cases))
