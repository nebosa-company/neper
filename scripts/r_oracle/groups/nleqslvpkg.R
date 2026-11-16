# nleqslvpkg: the root nleqslv (Newton, default strategy) finds for five fixed systems from random starts, checked against rootSolve::multiroot too.
#   args: (system, coordinate, x0 (n))
suppressMessages(library(nleqslv)); suppressMessages(library(rootSolve))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-6)
fs <- list(
  function(x) c(x[1]^2 + x[2]^2 - 4, exp(x[1]) + x[2] - 1),
  function(x) c(x[1] + x[2] + x[3] - 3, x[1]^2 + x[2]^2 + x[3]^2 - 5, exp(x[1]) + x[1] * x[2] - x[3] - 1),
  function(x) c(sin(x[1]) + x[2] - 1.2, x[1] - cos(x[2]) + 0.3),
  function(x) c(-400 * x[1] * (x[2] - x[1]^2) - 2 * (1 - x[1]), 200 * (x[2] - x[1]^2)),
  function(x) c(1 / (1 + exp(-x[1])) + x[2] - 1.5, x[1] * x[2] - 0.5 - exp(-x[2])))
nd <- c(2, 3, 2, 2, 2)
set.seed(20262019)
for (rep in 1:60) {
  s <- (rep - 1) %% 5; x0 <- runif(nd[s + 1], -1.5, 1.5)
  r <- tryCatch(nleqslv(x0, fs[[s + 1]]), error = function(e) NULL); m <- tryCatch(multiroot(fs[[s + 1]], x0), error = function(e) NULL, warning = function(w) NULL)
  if (is.null(r) || is.null(m) || r$termcd != 1 || max(abs(fs[[s + 1]](r$x))) > 1e-7 || max(abs(r$x - m$root)) > 1e-6) next
  for (j in seq_along(r$x)) add("root", c(s, j - 1, x0), r$x[j])
}
emit("nleqslvpkg", "nleqslv", list(cases))
