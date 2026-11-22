# kernlab specc on matrix input, with the automatic sigma search and with a given kernel.
#   args: (m, p, nc, kind, par1, seed, mod_sample, iters, x[m*p] row-major); kind -1 = kpar "automatic" (rbfdot), 0 rbfdot(par1), 4 laplacedot(par1)
#   fn "cl" (labels, position-weighted) "size" "cent" "wss" "sigma" (automatic only)
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20261402)
for (rep in 1:24) {
  kind <- c(-1, 0, 4)[rep %% 3 + 1]
  nc <- sample(2:3, 1); p <- sample(2:3, 1); per <- sample(12:20, 1); m <- nc * per
  ctr <- matrix(rnorm(nc * p, 0, 3), nc)
  x <- do.call(rbind, lapply(1:nc, function(k) matrix(rnorm(per * p, 0, 0.6), per) + rep(ctr[k, ], each = per)))
  x <- x[sample(m), , drop = FALSE]
  s1 <- runif(1, 0.05, 0.6); ms <- 0.75; it <- 200; sd0 <- sample(100000, 1)
  set.seed(sd0)
  r <- tryCatch(if (kind < 0) specc(x, centers = nc, iterations = it, mod.sample = ms) else specc(x, centers = nc, kernel = if (kind == 0) "rbfdot" else "laplacedot", kpar = list(sigma = s1), iterations = it),
                error = function(e) NULL)
  if (is.null(r)) next
  a <- c(m, p, nc, kind, s1, sd0, ms, it, as.vector(t(x)))
  add("cl", a, ws(as.vector(r))); add("size", a, ws(size(r))); add("cent", a, ws(t(centers(r)))); add("wss", a, ws(withinss(r)))
  if (kind < 0) add("sigma", a, kpar(kernelf(r))$sigma)
}
emit("kernlabspecc", "kernlab", list(cases))
