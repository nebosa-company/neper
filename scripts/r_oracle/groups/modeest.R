# modeest: venter (types 1, 2, dalenius, shorth), hsm, grenander (p), meanshift, asselin.
#   kinds 9 tsybakov (p = alpha, triangular, dmp) 10 tsybakov (gaussian, no dmp) 11 lientz (p = bw, the evaluation point after x)
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
for (rep in 1:25) {
  n <- sample(12:80, 1); x <- round(rnorm(n, 2, 1.4), 3); al <- runif(1, 0.6, 1)
  add(c(9, al, n, x), tsybakov(x, alpha = al)); add(c(10, al, n, x), tsybakov(x, kernel = "gaussian", dmp = FALSE, alpha = al))
  bwl <- runif(1, 0.1, 0.6); l <- lientz(x, bwl); zz <- runif(4, min(x) - 0.5, max(x) + 0.5)
  for (z in zz) add(c(11, bwl, n, x, z), l(z))
}
# meanshift with other bandwidths and kernels: kinds 12 (iterate) and 13 (iterations); args (kind, 0, n, x..., mode 0 nrd0 1 nrd 2 numeric, bw, kernel id 0 gaussian 1 uniform 2 triangular 3 epanechnikov 4 biweight 5 cosine 6 optcosine 7 rectangular)
kn2 <- c("gaussian", "uniform", "triangular", "epanechnikov", "biweight", "cosine", "optcosine", "rectangular")
for (rep in 1:90) {
  n <- if (rep > 60) sample(c(15, 40, 600), 1) else sample(15:80, 1); x <- round(c(rnorm(n %/% 2, 1, 1), rnorm(n - n %/% 2, 4, 1.2)), 3); kid <- sample(0:7, 1); mode <- sample(0:6, 1); bw <- if (mode == 2) runif(1, 0.5, 1.5) else 0; if (rep > 60 && mode < 3) mode <- 3 + rep %% 4
  r <- tryCatch(suppressWarnings(meanshift(x, bw = if (mode == 0) "nrd0" else if (mode == 1) "nrd" else if (mode == 3) "ucv" else if (mode == 4) "bcv" else if (mode == 5) "sj-ste" else if (mode == 6) "sj-dpi" else bw, kernel = kn2[kid + 1])), error = function(e) NULL)
  if (is.null(r) || !is.finite(r)) next
  a <- c(12, 0, n, x, mode, bw, kid); add(a, as.numeric(r)); a[1] <- 13; add(a, attr(r, "iterations"))
}
emit("modeest", "modeest", list(cases))
