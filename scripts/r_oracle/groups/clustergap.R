# cluster::clusGap and cluster::maxSE against e.algo.stat.clustergap.
#   clusGap args: (fun, n, p, kmax, B, dpower, pca, seed, V[1..p*p], data)   fun 1 pam, 2 agnes (average) + cutree, 3 diana + cutree,
#     4 clara (samples = 3), 5 fanny; pca 1 is spaceH0 = "scaledPCA" (V is svd(centred x)$v, column-major), 0 is "original";
#     data is x row-major; the reference data come from set.seed(seed)
#     fn: logw, elogw, gap, se (the columns of Tab, position-weighted over k)
#   maxSE args: (method, SE.factor, K, f[1..K], SE.f[1..K])   method 1 firstSEmax 2 Tibs2001SEmax 3 globalSEmax 4 firstmax 5 globalmax
#     fn: maxse (the chosen number of clusters)
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(as.numeric(v) * seq_along(v))
set.seed(20270108)
FUNS <- list(
  function(x, k) list(cluster = pam(x, k, cluster.only = TRUE)),
  function(x, k) list(cluster = cutree(as.hclust(agnes(x, method = "average")), k)),
  function(x, k) list(cluster = cutree(as.hclust(diana(x)), k)),
  function(x, k) list(cluster = clara(x, k, samples = 3, sampsize = min(nrow(x), 40 + 2 * k), cluster.only = TRUE)),
  function(x, k) list(cluster = fanny(x, k)$clustering))
METH <- c("firstSEmax", "Tibs2001SEmax", "globalSEmax", "firstmax", "globalmax")

onegap <- function(x, fun, kmax, B, dpow, pca) {
  n <- nrow(x); p <- ncol(x)
  V <- if (pca) svd(scale(x, center = TRUE, scale = FALSE), nu = 0)$v else diag(p)
  seed <- sample(1:100000, 1)
  a <- c(fun, n, p, kmax, B, dpow, pca, seed, as.vector(V), as.vector(t(x)))
  set.seed(seed)
  g <- tryCatch(suppressWarnings(clusGap(x, FUNS[[fun]], K.max = kmax, B = B, d.power = dpow, spaceH0 = if (pca) "scaledPCA" else "original", verbose = FALSE)),
                error = function(e) NULL)
  if (is.null(g)) return(invisible())
  tab <- g$Tab
  add("logw", a, wsum(tab[, 1])); add("elogw", a, wsum(tab[, 2])); add("gap", a, wsum(tab[, 3])); add("se", a, wsum(tab[, 4]))
}
for (fun in 1:5) for (rep in 1:5) {
  n <- sample(14:26, 1); p <- sample(2:3, 1)
  g <- sample(2:3, 1)
  x <- matrix(rnorm(n * p), n, p) + matrix(rep(sample(0:(g - 1), n, replace = TRUE) * 4, p), n, p)
  onegap(x, fun, sample(3:5, 1), sample(4:8, 1), sample(c(1, 2), 1), rep %% 2)
}

for (rep in 1:60) {
  K <- sample(2:9, 1); f <- cumsum(rnorm(K)) ; se <- runif(K, 0, 1)
  m <- sample(1:5, 1); sf <- sample(c(1, 0.5, 2), 1)
  a <- c(m, sf, K, f, se)
  add("maxse", a, maxSE(f, se, method = METH[m], SE.factor = sf), 0, 0)
}
emit("clustergap", "cluster", list(cases))
