# fminsearchpkg: pracma::fminsearch (Nelder-Mead) on five fixed functions from random starts.
#   args: (function, what 0 minimiser coordinate k 1 minimum 2 evaluation count 3 restarts, k, x0 (n))
suppressMessages(library(pracma))
cases <- list()
add <- function(fn, args, want, rel, abs) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
fs <- list(function(x) 100 * (x[2] - x[1] * x[1])^2 + (1 - x[1])^2,
           function(x) sum((x - 1:3)^2),
           function(x) (1.5 - x[1] + x[1] * x[2])^2 + (2.25 - x[1] + x[1] * x[2] * x[2])^2 + (2.625 - x[1] + x[1] * x[2] * x[2] * x[2])^2,
           function(x) (x[1] * x[1] + x[2] - 11)^2 + (x[1] + x[2] * x[2] - 7)^2,
           function(x) x[1]^4 + x[2]^4 + x[1] * x[2] + (x[1] - 1)^2)
nd <- c(2, 3, 2, 2, 2)
set.seed(20262021)
for (rep in 1:40) {
  id <- (rep - 1) %% 5; x0 <- round(runif(nd[id + 1], -2, 2), 3)
  r <- fminsearch(fs[[id + 1]], x0)
  for (k in seq_along(r$xmin)) add("nm", c(id, 0, k - 1, x0), r$xmin[k], 1e-6, 1e-7)
  add("nm", c(id, 1, 0, x0), r$fmin, 1e-6, 1e-12)
  add("nm", c(id, 2, 0, x0), r$count, 0, 0)
  add("nm", c(id, 3, 0, x0), r$info$restarts, 0, 0)
}
emit("fminsearchpkg", "pracma", list(cases))
