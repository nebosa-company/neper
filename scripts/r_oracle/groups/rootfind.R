# rootfind: stats::uniroot (root, iter, estim.prec) and rootSolve::uniroot.all on five fixed functions.
#   "uni" (what 0 root 1 iter 2 estim.prec, function, lo, hi, tol); "all" (k, function, lo, hi) is the k-th root of uniroot.all (sorted) and "allcount" its number of roots
suppressMessages(library(rootSolve))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
tf <- list(function(x) sin(3 * x) + x / 5, function(x) x^3 - 2 * x - 5, function(x) exp(x) - 3 - x / 2, function(x) cos(x) - x, function(x) (x - 1) * (x - 2) * (x + 1.5))
set.seed(20262020)
for (rep in 1:50) {
  id <- (rep - 1) %% 5; f <- tf[[id + 1]]
  lo <- runif(1, -3, 0.5); hi <- lo + runif(1, 1, 5); tol <- c(1e-4, 1e-8, .Machine$double.eps^0.25)[sample(3, 1)]
  if (f(lo) * f(hi) < 0) { u <- uniroot(f, c(lo, hi), tol = tol); add("uni", c(0, id, lo, hi, tol), u$root, 1e-9, 1e-11); add("uni", c(1, id, lo, hi, tol), u$iter, 0, 0); add("uni", c(2, id, lo, hi, tol), u$estim.prec, 1e-6, 1e-12) }
  r <- uniroot.all(f, c(lo, hi)); add("allcount", c(0, id, lo, hi), length(r), 0, 0); for (k in seq_along(r)) add("all", c(k - 1, id, lo, hi), r[k], 1e-9, 1e-11)
}
emit("rootfind", "rootSolve", list(cases))
