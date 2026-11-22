# kernlab gausspr classification (Laplace approximation, one-against-one, solveiter), rbfdot kernel, with and without scaling, votes and the coupled probabilities.
#   args: (n, p, K, sigma, scaled, tol, nt, cls[n] 1-based, x[n*p] row-major, xt[nt*p] row-major); fn "alpha" (all pairs' coefficients, position-weighted), "resp", "prob", "prob_pkpd", "prob_vote"
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20261801)
for (rep in 1:30) {
  K <- c(2, 3, 4)[(rep - 1) %% 3 + 1]; p <- sample(2:4, 1); per <- sample(8:14, 1); n <- K * per
  ctr <- matrix(rnorm(K * p, 0, 1.2), K); cls <- rep(1:K, per)[sample(n)]
  x <- ctr[cls, , drop = FALSE] + matrix(rnorm(n * p), n); nt <- 8; xt <- matrix(rnorm(nt * p, 0, 1.5), nt)
  sg <- runif(1, 0.1, 1.0); sc <- rep %% 2 == 0
  m <- gausspr(x, factor(cls), kernel = "rbfdot", kpar = list(sigma = sg), scaled = sc)
  a <- c(n, p, K, sg, sc, 0.0005, nt, cls, as.vector(t(x)), as.vector(t(xt)))
  full <- unlist(lapply(seq_along(alphaindex(m)), function(q) { f <- numeric(n); f[alphaindex(m)[[q]]] <- alpha(m)[[q]]; f }))
  add("alpha", a, ws(full))
  add("resp", a, ws(as.integer(predict(m, xt))))
  add("prob", a, ws(t(predict(m, xt, type = "probabilities"))))
  add("prob_pkpd", a, ws(t(predict(m, xt, type = "probabilities", coupler = "pkpd"))))
  add("prob_vote", a, ws(t(predict(m, xt, type = "probabilities", coupler = "vote"))))
}
emit("kernlabgpc", "kernlab", list(cases))
