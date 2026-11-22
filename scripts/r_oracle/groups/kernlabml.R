# kernlab rvm (regression), kfa and ranking.
#   rvm   args: (m, p, kind, par1, alpha0, var0, varfix, iterations, minmaxdiff, nt, y[m], x[m*p], xt[nt*p]); kinds 0 rbfdot(par1), 4 laplacedot(par1)
#         fn "rvm_w" (full-length weights, position-weighted) "index" (RVindex) "nrv" "var" "mlike" "mse" "fitted" "pred"
#   kfa   args: (m, p, kind, par1, subset, features, normalize, seed, nt, x[m*p], xt[nt*p]); fn "alpha" "index" "pred"
#   rank  args: (m, p, kind, par1, lab, alpha, iterations, x[m*p]); fn "score" "rank" (position-weighted over the unlabelled points)
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(v), na.rm = TRUE)
kern <- function(kind, s) if (kind == 0) rbfdot(s) else laplacedot(s)
set.seed(20261401)
for (rep in 1:24) {
  kind <- c(0, 4)[rep %% 2 + 1]
  m <- sample(20:45, 1); p <- sample(1:3, 1); nt <- sample(5:10, 1)
  x <- matrix(rnorm(m * p), m); xt <- matrix(rnorm(nt * p), nt); y <- sin(x[, 1]) + 0.2 * rnorm(m)
  s1 <- runif(1, 0.2, 1.5); a0 <- sample(1:4, 1); v0 <- runif(1, 0.02, 0.4)
  vf <- rep %% 3 == 0; it <- sample(c(30, 60, 100), 1); mm <- c(1e-3, 1e-4)[rep %% 2 + 1]
  r <- suppressWarnings(rvm(x, y, kernel = kern(kind, s1), alpha = a0, var = v0, var.fix = vf, iterations = it, minmaxdiff = mm))
  w <- numeric(m); w[RVindex(r)] <- alpha(r)
  a <- c(m, p, kind, s1, a0, v0, vf, it, mm, nt, y, as.vector(t(x)), as.vector(t(xt)))
  add("rvm_w", a, ws(w)); add("rvm_index", a, ws(RVindex(r))); add("rvm_nrv", a, length(RVindex(r))); add("rvm_var", a, nvar(r))
  add("rvm_mlike", a, mlike(r)); add("rvm_mse", a, error(r)); add("rvm_fitted", a, ws(fitted(r))); add("rvm_pred", a, ws(predict(r, xt)))
}
for (rep in 1:20) {
  kind <- c(0, 4)[rep %% 2 + 1]
  m <- sample(25:60, 1); p <- sample(2:3, 1); nt <- sample(5:10, 1)
  x <- matrix(rnorm(m * p), m); xt <- matrix(rnorm(nt * p), nt)
  s1 <- runif(1, 0.1, 1.0); sub <- sample(8:20, 1); fe <- sample(c(0, 3:7), 1); nm <- rep %% 4 != 0; sd0 <- sample(1000, 1)
  set.seed(sd0)
  k <- kfa(x, kernel = kern(kind, s1), features = fe, subset = sub, normalize = nm)
  a <- c(m, p, kind, s1, sub, fe, nm, sd0, nt, as.vector(t(x)), as.vector(t(xt)))
  add("kfa_alpha", a, ws(t(alpha(k)))); add("kfa_index", a, ws(alphaindex(k))); add("kfa_pred", a, ws(t(predict(k, xt))))
}
for (rep in 1:20) {
  kind <- c(0, 4)[rep %% 2 + 1]
  m <- sample(15:40, 1); p <- sample(1:3, 1)
  x <- matrix(rnorm(m * p), m); s1 <- runif(1, 0.3, 2); lab <- sample(m, 1)
  al <- runif(1, 0.5, 0.99); it <- sample(c(20, 100, 600), 1)
  r <- ranking(x, lab, kernel = if (kind == 0) "rbfdot" else "laplacedot", kpar = list(sigma = s1), alpha = al, iterations = it)
  a <- c(m, p, kind, s1, lab - 1, al, it, as.vector(t(x)))
  add("rank_score", a, ws(r[, 2])); add("rank_rank", a, ws(r[, 3]))
}
emit("kernlabml", "kernlab", list(cases))
