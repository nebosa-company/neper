# cluster::daisy (euclidean, manhattan, stand, gower, every variable type, weights, missing values) and cluster::silhouette
# (sildist on a dist and on a matrix, recoded cluster codes, sortSilhouette and summary) against e.algo.stat.clusterdiss.
#   daisy args: (n, p, metric, stand, vtype[1..p], weights[1..p], data)   metric 1 euclidean 2 manhattan 3 gower; vtype 1 A (asymmetric
#     binary) 2 S (symmetric binary) 3 N (nominal, factor codes) 4 O (ordered codes) 5 I (interval) 6 T (ordratio) 7 logratio (an
#     interval column given log10); data is x row-major with the codes a data frame holds, NA as -999999
#     fn: dsum (the dissimilarities in dist order, position-weighted, NA counted as 0) and dna (the sum of the positions holding NA)
#   silhouette args: (n, ismat, ncl, cluster codes[1..n], d)   d is the n by n matrix row-major or the dist vector
#     fn: silna (1 when R answers NA), sw (widths), sn (neighbors), sorder (the sortSilhouette permutation), savg (avg.width),
#     sclus (clus.avg.widths by sorted cluster code), ssize (cluster sizes), all position-weighted
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(as.numeric(v) * seq_along(v))
set.seed(20270107)

onedaisy <- function(df, vt, metric, stand, w, type) {
  n <- nrow(df); p <- ncol(df)
  m <- data.matrix(df)
  a <- c(n, p, metric, stand, vt, w, as.vector(t(ifelse(is.na(m), -999999, m))))
  d <- tryCatch(suppressWarnings(daisy(df, metric = c("euclidean", "manhattan", "gower")[metric], stand = stand == 1, type = type, weights = w)),
                error = function(e) NULL)
  if (is.null(d)) return(invisible())
  v <- as.vector(d); na <- is.na(v)
  add("dsum", a, wsum(ifelse(na, 0, v))); add("dna", a, sum(which(na)), 0, 0)
}

# numeric matrices: euclidean, manhattan, standardised, gower
for (rep in 1:24) {
  n <- sample(4:20, 1); p <- sample(1:4, 1)
  m <- matrix(round(rnorm(n * p) * 3, 3), n, p)
  if (rep %% 3 == 0) m[sample(n * p, sample(1:4, 1))] <- NA
  df <- as.data.frame(m)
  onedaisy(df, rep(5, p), 1 + rep %% 3, as.integer(rep %% 2 == 1), runif(p, 0.5, 2), list())
}
# mixed types
mixed <- function(n, p, na) {
  vt <- sample(c(1, 2, 3, 4, 5, 6, 7), p, replace = TRUE)
  cols <- list(); type <- list(asymm = c(), symm = c(), ordratio = c(), logratio = c())
  for (j in 1:p) {
    v <- NULL
    if (vt[j] == 1) { v <- rbinom(n, 1, 0.4); v[1:2] <- c(0, 1); type$asymm <- c(type$asymm, j) }
    if (vt[j] == 2) { v <- rbinom(n, 1, 0.5); v[1:2] <- c(0, 1); type$symm <- c(type$symm, j) }
    if (vt[j] == 3) { u <- sample(1:sample(2:4, 1), n, replace = TRUE); v <- match(u, sort(unique(u))) }
    if (vt[j] == 4) { u <- sample(1:sample(2:5, 1), n, replace = TRUE); v <- ordered(match(u, sort(unique(u)))) }
    if (vt[j] == 5) v <- round(rnorm(n) * 2, 3)
    if (vt[j] == 6) { type$ordratio <- c(type$ordratio, j); v <- round(rexp(n) * 5, 3) }
    if (vt[j] == 7) { type$logratio <- c(type$logratio, j); v <- round(rexp(n) * 5 + 0.1, 3) }
    if (vt[j] == 3) v <- factor(v)
    cols[[j]] <- v
  }
  df <- as.data.frame(cols); names(df) <- paste0("V", 1:p)
  if (na > 0) for (k in 1:na) df[sample(n, 1), sample(p, 1)] <- NA
  type <- lapply(type, function(i) if (length(i)) names(df)[i]); type <- type[!vapply(type, is.null, NA)]
  list(df = df, vt = vt, type = type)
}
for (rep in 1:40) {
  n <- sample(5:22, 1); p <- sample(2:6, 1)
  g <- mixed(n, p, if (rep %% 2) sample(1:5, 1) else 0)
  onedaisy(g$df, g$vt, 3, 0, runif(p, 0.5, 2.5), g$type)
}
# a logical column is asymmetric, weights of 1
for (rep in 1:6) {
  n <- sample(6:15, 1)
  df <- data.frame(a = round(rnorm(n), 3), b = rbinom(n, 1, 0.5) == 1, c = factor(sample(letters[1:3], n, replace = TRUE)))
  df$b[1:2] <- c(TRUE, FALSE)
  onedaisy(df, c(5, 1, 3), 3, 0, c(1, 1, 1), list())
}

# silhouette
onesil <- function(n, codes, ismat, cl = sample(codes, n, replace = TRUE)) {
  x <- matrix(rnorm(n * 2), n, 2); d <- dist(x)
  dd <- if (ismat) as.vector(t(as.matrix(d))) else as.vector(d)
  a <- c(n, ismat, length(codes), cl, dd)
  s <- if (ismat) silhouette(cl, dmatrix = as.matrix(d)) else silhouette(cl, d)
  if (!inherits(s, "silhouette")) { add("silna", a, 1, 0, 0); return(invisible()) }
  add("silna", a, 0, 0, 0)
  add("sw", a, wsum(s[, 3])); add("sn", a, wsum(s[, 2]), 0, 0)
  so <- sortSilhouette(s); add("sorder", a, wsum(attr(so, "iOrd")), 0, 0)
  sm <- summary(s)
  add("savg", a, sm$avg.width); add("sclus", a, wsum(sm$clus.avg.widths)); add("ssize", a, wsum(as.integer(sm$clus.sizes)), 0, 0)
}
for (rep in 1:24) {
  n <- sample(6:22, 1); k <- sample(2:5, 1)
  codes <- if (rep %% 3 == 0) sort(sample(c(-2, 0, 3, 5, 9, 11), k)) else 1:k
  onesil(n, codes, rep %% 2)
}
onesil(10, 1, 0, cl = rep(1, 10)); onesil(8, 1:8, 1, cl = 1:8)
emit("clusterdaisy", "cluster", list(cases))
