# cluster::pam on euclidean distances of random points.
#   args: (n, k, x row-major n by 2...)   fn "build" "swap" (the two objectives), "med" (the sum of (medoid index) * position of the SORTED medoids), "lab" (the sum of the labels renumbered by first appearance * position)
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261219)
emu <- function(d, k) { n <- nrow(d); sel <- which.min(rowSums(d)); near <- d[, sel]
  while (length(sel) < k) { g <- sapply(1:n, function(i) if (i %in% sel) -1 else sum(pmax(near[-sel] - d[i, -sel], 0))); b <- which.max(g); sel <- c(sel, b); near <- pmin(near, d[, b]) }
  cost <- function(m) sum(apply(d[, m, drop = FALSE], 1, min))
  repeat { best <- NULL; bc <- cost(sel); for (m in 1:k) for (h in setdiff(1:n, sel)) { mm <- sel; mm[m] <- h; c <- cost(mm); if (c < bc - 1e-12) { bc <- c; best <- c(m, h) } }
    if (is.null(best)) break; sel[best[1]] <- best[2] }
  sort(sel) }
for (rep in 1:20) {
  n <- sample(12:40, 1); k <- sample(2:5, 1)
  X <- matrix(round(rnorm(n * 2) * 3, 4), n, 2) + matrix(rep(sample(0:3, n, replace = TRUE) * 3, 2), n, 2)
  p <- pam(dist(X), k)
  a <- c(n, k, as.vector(t(X)))
  add("build", a, as.numeric(p$objective[1])); add("swap", a, as.numeric(p$objective[2]))
  if (identical(as.integer(emu(as.matrix(dist(X)), k)), as.integer(sort(p$id.med)))) { add("med", a, sum(sort(p$id.med) * seq_along(p$id.med))); add("lab", a, sum(match(p$clustering, unique(p$clustering)) * seq_len(n))) }
}
emit("pamcluster", "cluster", list(cases))
