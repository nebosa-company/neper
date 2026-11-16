# pcaPP: cor.fk, l1median_HoCr, l1median_VaZh and the default l1median (nlm). hocr and nlm are compared to the tolerance: HoCr stops on a
# strict decrease of a sum of 100 square roots, which the last bit of pow decides; code and iterations are compared for vazh only.
#   corfk: (n, x[n], y[n])
#   hocr, vazh, nlm: (n, p, maxit, tol, zero.tol, X[n*p column-major], m0[p], what) what 0..p-1 par, p value, p+1 code, p+2 iterations
suppressMessages(library(pcaPP))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261120)
for (rep in 1:60) {
  n <- sample(c(5, 8, 20, 50, 200), 1)
  x <- if (rep %% 3 == 0) round(rnorm(n) * 2) else rnorm(n)
  y <- if (rep %% 4 == 0) round(x + rnorm(n)) else x * 0.5 + rnorm(n)
  add("corfk", c(n, x, y), cor.fk(x, y))
}
for (rep in 1:40) {
  p <- sample(1:5, 1); n <- sample(c(10, 30, 60, 120), 1)
  X <- matrix(if (rep %% 2 == 0) rnorm(n * p) else rt(n * p, 3), n, p)
  m0 <- apply(X, 2, median)
  hc <- l1median_HoCr(X, m.init = m0)
  vz <- l1median_VaZh(X, m.init = m0)
  nl <- tryCatch(l1median_NLM(X, m.init = m0), error = function(e) NULL)
  a <- c(n, p, 200, 1e-8, 1e-15, X, m0)
  for (j in 1:p) { add("hocr", c(a, j - 1), hc$par[j], rel = 1e-6, abs = 1e-7); add("vazh", c(a, j - 1), vz$par[j]) }
  add("hocr", c(a, p), hc$value); add("vazh", c(a, p), vz$value)
  add("vazh", c(a, p + 1), vz$code)
  add("vazh", c(a, p + 2), vz$iterations)
  if (!is.null(nl)) {
    for (j in 1:p) add("nlm", c(a, j - 1), nl$par[j], rel = 1e-5, abs = 1e-6)
    add("nlm", c(a, p), nl$value, rel = 1e-7, abs = 1e-8)
  }
}
emit("pcapp", "pcaPP", list(cases))
