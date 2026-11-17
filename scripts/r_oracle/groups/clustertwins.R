# cluster::agnes (all seven methods, flexible and gaverage with their par.method forms) and cluster::diana against
# e.algo.stat.clustertwins, from a data matrix (euclidean or manhattan, stand, missing values) and from a dissimilarity.
#   args: (kind, n, p, method, stand, metric, diss, kcut, npar, par[1..npar], data)
#     kind 1 agnes / 2 diana; method 1..7 = average single complete ward weighted flexible gaverage; metric 1 euclidean 2 manhattan;
#     data is x row-major (NA as -999999), or the R dist vector when diss is 1; kcut is the k of cutree(as.hclust(.), k)
#   fn names the answer: order, m1, m2 (merge columns), height (position-weighted sums; height is the package's, unsorted),
#     coef (ac or dc), hheight (the sorted heights as.hclust answers), hcoef (coef.hclust of as.hclust), cut (cutree labels)
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(as.numeric(v) * seq_along(v))
set.seed(20270104)
METH <- c("average", "single", "complete", "ward", "weighted", "flexible", "gaverage")

onetwins <- function(x, kind, method, stand, metric, kcut, par = numeric(0), diss = FALSE) {
  n <- if (diss) attr(x, "Size") else nrow(x)
  p <- if (diss) 1 else ncol(x)
  data <- if (diss) as.vector(x) else as.vector(t(ifelse(is.na(x), -999999, x)))
  a <- c(kind, n, p, method, stand, metric, diss, kcut, length(par), par, data)
  m <- c("euclidean", "manhattan")[metric]
  r <- tryCatch(suppressWarnings(
    if (kind == 1) {
      if (method %in% 6:7 && length(par)) agnes(x, diss = diss, metric = m, stand = stand == 1, method = METH[method], par.method = par)
      else agnes(x, diss = diss, metric = m, stand = stand == 1, method = METH[method])
    } else diana(x, diss = diss, metric = m, stand = stand == 1)), error = function(e) NULL)
  if (is.null(r)) return(invisible())
  add("order", a, wsum(r$order), 0, 0)
  add("m1", a, wsum(r$merge[, 1]), 0, 0); add("m2", a, wsum(r$merge[, 2]), 0, 0)
  add("height", a, wsum(r$height))
  add("coef", a, if (kind == 1) r$ac else r$dc)
  h <- as.hclust(r)
  add("hheight", a, wsum(h$height))
  add("cut", a, wsum(cutree(h, kcut)), 0, 0)
  hc <- tryCatch(coef.hclust(h), error = function(e) NULL)
  if (!is.null(hc)) add("hcoef", a, hc)
}

gen <- function(n, p, grid, na = 0) {
  g <- sample(2:4, 1)
  x <- matrix(rnorm(n * p) * 2, n, p) + matrix(rep(sample(0:(g - 1), n, replace = TRUE) * 4, p), n, p)
  x <- if (grid) round(x * 4) / 4 else x
  if (na > 0) { idx <- sample(n * p, na); x[idx] <- NA; for (i in which(rowSums(!is.na(x)) == 0)) x[i, 1] <- 1 }
  x
}

# every agnes method, continuous and tie-prone
for (method in 1:5) for (rep in 1:8) {
  n <- sample(5:30, 1); x <- gen(n, sample(1:3, 1), rep %% 2 == 0)
  onetwins(x, 1, method, rep %% 3 == 0 && rep %% 2 == 1, sample(1:2, 1), sample(2:min(5, n - 1), 1))
}
# flexible and gaverage with every par.method form
for (rep in 1:10) {
  n <- sample(6:28, 1); x <- gen(n, 2, rep %% 2 == 0)
  onetwins(x, 1, 6, 0, 1, sample(2:5, 1), par = runif(1, 0.2, 0.9))
  onetwins(x, 1, 6, 0, 1, sample(2:5, 1), par = c(runif(1, 0.3, 0.7), runif(1, 0.3, 0.7), runif(1, -0.3, 0.2)))
  onetwins(x, 1, 6, 0, 2, sample(2:5, 1), par = c(0.5, 0.5, -0.25, 0.25))
  onetwins(x, 1, 7, 0, 1, sample(2:5, 1))
  onetwins(x, 1, 7, 0, 1, sample(2:5, 1), par = runif(1, -0.3, 0.5))
  onetwins(x, 1, 7, 0, 2, sample(2:5, 1), par = c(0.6, 0.6, -0.2, 0))
}
# diana
for (rep in 1:20) {
  n <- sample(4:34, 1); x <- gen(n, sample(1:3, 1), rep %% 2 == 0)
  onetwins(x, 2, 0, rep %% 3 == 0 && rep %% 2 == 1, sample(1:2, 1), sample(2:min(5, n - 1), 1))
}
# missing values
for (rep in 1:10) {
  n <- sample(10:24, 1); x <- gen(n, 3, rep %% 2 == 0, na = sample(2:6, 1))
  onetwins(x, 1 + rep %% 2, sample(1:5, 1), 0, sample(1:2, 1), 3)
}
# a dissimilarity as input
for (rep in 1:14) {
  n <- sample(5:22, 1)
  v <- if (rep %% 2) round(runif(n * (n - 1) / 2, 0.5, 9) * 4) / 4 else runif(n * (n - 1) / 2, 0.5, 9)
  d <- structure(v, Size = n, class = "dist")
  onetwins(d, 1 + rep %% 2, sample(1:5, 1), 0, 1, sample(2:min(4, n - 1), 1), diss = TRUE)
}
emit("clustertwins", "cluster", list(cases))
