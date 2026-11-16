# modeest: venter (types 1, 2, dalenius, shorth), hsm, grenander (p), meanshift, asselin.
#   args: (kind, p, n, x[n])  kind 0 venter1 1 venter2 2 dalenius 3 shorth 4 hsm 5 grenander(p) 6 meanshift 7 asselin 8 meanshift iterations
suppressMessages(library(modeest))
cases <- list()
add <- function(a, want) cases[[length(cases) + 1]] <<- case("m", a, want, rel = 1e-9, abs = 1e-10)
set.seed(20261116)
for (rep in 1:50) {
  n <- sample(8:90, 1)
  x <- switch(rep %% 4 + 1, rnorm(n), c(rnorm(n %/% 2, 0), rnorm(n - n %/% 2, 5)), rexp(n), rbeta(n, 2, 5))
  x <- if (rep %% 3 == 0) round(x, 1) else x
  a <- function(kind, p) c(kind, p, n, x)
  add(a(0, 0), suppressWarnings(venter(x, type = 1))); add(a(1, 0), suppressWarnings(venter(x, type = 2)))
  add(a(2, 0), suppressWarnings(venter(x, type = "dalenius"))); add(a(3, 0), suppressWarnings(shorth(x)))
  add(a(4, 0), suppressWarnings(hsm(x)))
  for (p in c(1, 2, 4)) { g <- suppressWarnings(tryCatch(grenander(x, p = p), error = function(e) NA)); if (is.finite(g)) add(a(5, p), g) }
  ms <- tryCatch(meanshift(x), error = function(e) NULL)
  if (!is.null(ms)) { add(a(6, 0), as.numeric(ms)); add(a(8, 0), attr(ms, "iterations")) }
  as_ <- tryCatch(suppressWarnings(asselin(x)), error = function(e) NULL); if (!is.null(as_) && is.finite(as_)) add(a(7, 0), as_)
}
emit("modeest", "modeest", list(cases))
