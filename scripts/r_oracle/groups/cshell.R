# e1071::cshell with given centres under set.seed (the random row permutation is the first draw).
#   args: (seed, n, d, nc, dist 0 euclidean 1 manhattan, iter.max, m, x col-major[n*d], centers col-major[nc*d])
#   q is the last arg: 0 sum(i + nc*j) weighted centres, 1 sum radius * index, 2 iter, 3 withinerror, 4 sum membership weighted by position
suppressMessages(library(e1071))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("cs", args, want, rel = 5e-4, abs = 1e-7)
set.seed(20261117)
for (rep in 1:60) {
  nc <- sample(2:3, 1); d <- sample(2:3, 1); n <- sample(24:60, 1)
  cen <- matrix(rnorm(nc * d, 0, 3), nc, d)
  grp <- sample(nc, n, TRUE); rad <- runif(nc, 0.5, 2)
  x <- matrix(0, n, d)
  for (i in seq_len(n)) { dir <- rnorm(d); dir <- dir / sqrt(sum(dir^2)); x[i, ] <- cen[grp[i], ] + dir * (rad[grp[i]] + rnorm(1, 0, 0.1)) }
  start <- cen + matrix(rnorm(nc * d, 0, 0.3), nc, d)
  seed <- sample(1e6, 1); dist <- sample(0:1, 1); itmax <- sample(c(20, 100), 1)
  set.seed(seed)
  r <- tryCatch(suppressWarnings(cshell(x, start, iter.max = itmax, dist = c("euclidean", "manhattan")[dist + 1], m = 2)), error = function(e) NULL)
  if (is.null(r) || any(!is.finite(r$membership))) next
  base <- c(seed, n, d, nc, dist, itmax, 2, as.vector(x), as.vector(start))
  vals <- c(sum(seq_along(r$centers) * as.vector(r$centers)), sum(seq_along(r$radius) * r$radius), r$iter, r$withinerror, sum(seq_along(r$membership) * as.vector(r$membership)))
  for (q in 0:4) add(c(base, q), vals[q + 1])
}
emit("cshell", "e1071", list(cases))
