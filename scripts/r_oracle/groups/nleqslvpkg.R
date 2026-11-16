# nleqslvpkg: the root nleqslv (Newton, default strategy) finds for five fixed systems from random starts, checked against rootSolve::multiroot too.
#   args: "root" (system, coordinate, x0 (n)); "grad" and "hess" (function, centered, row, column, x) are rootSolve::gradient and hessian on polynomial functions written with products only (R's ^ goes through libm pow, which would change the last bit and the 1e8-amplified difference)
suppressMessages(library(nleqslv)); suppressMessages(library(rootSolve))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = if (fn == "root") 1e-6 else 1e-9, abs = if (fn == "root") 1e-6 else 1e-9)
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
fgrad <- list(function(x) x[1] * x[1] * x[1] * x[2] + 2 * x[2] * x[2] - x[1] * x[2] * 3,
              function(x) c(x[1] * x[1] * x[2] - x[3], x[1] + x[2] * x[3] * x[3]))
for (rep in 1:30) {
  fid <- rep %% 2; nx <- c(2, 3)[fid + 1]; x <- round(runif(nx, -2, 2), 4)
  for (cen in 0:1) {
    g <- gradient(fgrad[[fid + 1]], x, centered = cen == 1); g <- matrix(g, nrow = if (fid == 0) 1 else 2)
    for (r in seq_len(nrow(g))) for (j in seq_len(nx)) add("grad", c(fid, cen, r - 1, j - 1, x), g[r, j])
    if (fid == 0) { h <- hessian(fgrad[[1]], x, centered = cen == 1); for (r in 1:2) for (j in 1:2) add("hess", c(0, cen, r - 1, j - 1, x), h[r, j]) }
  }
}
emit("nleqslvpkg", "nleqslv", list(cases))
