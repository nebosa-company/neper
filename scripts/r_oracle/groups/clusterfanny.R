# cluster::fanny against e.algo.stat.clusterfanny: memb.exp, tol and maxit, the three metrics, standardisation, missing values,
# starting memberships, a dissimilarity input and the silhouette of the crisp clustering.
#   args: (n, p, k, metric, stand, diss, membexp, tol, maxit, nini, ini[1..nini], data)   metric 1 euclidean 2 manhattan 3 SqEuclidean
#     ini is iniMem.p column-major (nini = n * k, or 0); data is x row-major (NA as -999999) or the R dist vector when diss is 1
#   fn names the answer: memb (position-weighted sum of the membership matrix, column-major), coef1 and coef2 (coeff),
#     obj (objective), kcrisp, clu (clustering, position-weighted), iter (iterations), conv (converged), sil1..sil4 (silinfo
#     widths columns and observation numbers, position-weighted), avsil, ttsil
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(as.numeric(v) * seq_along(v))
set.seed(20270105)

onefanny <- function(x, k, metric, stand, membexp, tol, maxit, ini = NULL, diss = FALSE, checkiter = TRUE) {
  n <- if (diss) attr(x, "Size") else nrow(x)
  p <- if (diss) 1 else ncol(x)
  data <- if (diss) as.vector(x) else as.vector(t(ifelse(is.na(x), -999999, x)))
  a <- c(n, p, k, metric, stand, diss, membexp, tol, maxit, length(ini), as.vector(ini), data)
  m <- c("euclidean", "manhattan", "SqEuclidean")[metric]
  r <- tryCatch(suppressWarnings(if (diss) fanny(x, k, diss = TRUE, memb.exp = membexp, iniMem.p = ini, maxit = maxit, tol = tol)
                                 else fanny(x, k, metric = m, stand = stand == 1, memb.exp = membexp, iniMem.p = ini, maxit = maxit, tol = tol)),
                error = function(e) NULL)
  if (is.null(r)) return(invisible())
  add("memb", a, wsum(as.vector(r$membership)))
  add("coef1", a, r$coeff[1]); add("coef2", a, r$coeff[2])
  add("obj", a, r$objective[1]); add("kcrisp", a, r$k.crisp, 0, 0)
  add("clu", a, wsum(r$clustering), 0, 0)
  if (checkiter) { add("iter", a, r$convergence[1], 0, 0) }
  add("conv", a, as.numeric(r$convergence[2]), 0, 0)
  if (!is.null(r$silinfo)) {
    w <- r$silinfo$widths
    add("sil1", a, wsum(w[, 1]), 0, 0); add("sil2", a, wsum(w[, 2]), 0, 0); add("sil3", a, wsum(w[, 3]))
    add("sil4", a, wsum(as.integer(rownames(w))), 0, 0)
    add("avsil", a, wsum(r$silinfo$clus.avg.widths)); add("ttsil", a, r$silinfo$avg.width)
  }
}

gen <- function(n, p, na = 0) {
  g <- sample(2:4, 1)
  x <- matrix(rnorm(n * p) * 2, n, p) + matrix(rep(sample(0:(g - 1), n, replace = TRUE) * 5, p), n, p)
  if (na > 0) { idx <- sample(n * p, na); x[idx] <- NA; for (i in which(rowSums(!is.na(x)) == 0)) x[i, 1] <- 1 }
  x
}

# default tolerance: the iteration count may differ by the last bit of rounding, so it is not compared
for (rep in 1:12) {
  n <- sample(10:34, 1); k <- sample(2:max(2, min(5, n %/% 2 - 1)), 1)
  onefanny(gen(n, sample(1:3, 1)), k, sample(1:3, 1), rep %% 3 == 0, 2, 1e-15, 500, checkiter = FALSE)
}
# a looser tolerance, with the iteration count
for (rep in 1:14) {
  n <- sample(10:34, 1); k <- sample(2:max(2, min(5, n %/% 2 - 1)), 1)
  onefanny(gen(n, sample(1:3, 1)), k, sample(1:3, 1), rep %% 3 == 0, sample(c(1.5, 2, 2.5, 3), 1), 10^-sample(6:10, 1), 500)
}
# a small iteration limit: not converged
for (rep in 1:4) onefanny(gen(sample(12:25, 1), 2), 3, 1, 0, 2, 1e-12, sample(2:5, 1))
# starting memberships
for (rep in 1:8) {
  n <- sample(10:28, 1); k <- sample(2:4, 1)
  ini <- matrix(runif(n * k), n, k); ini <- ini / rowSums(ini)
  onefanny(gen(n, 2), k, 1, 0, sample(c(1.5, 2, 2.5), 1), 1e-9, 500, ini = ini)
}
# missing values
for (rep in 1:8) {
  n <- sample(12:30, 1)
  onefanny(gen(n, 3, na = sample(2:6, 1)), sample(2:3, 1), sample(1:3, 1), 0, 2, 1e-9, 500)
}
# a dissimilarity as input
for (rep in 1:8) {
  n <- sample(10:26, 1)
  d <- structure(runif(n * (n - 1) / 2, 0.5, 9), Size = n, class = "dist")
  onefanny(d, sample(2:max(2, min(4, n %/% 2 - 1)), 1), 1, 0, sample(c(1.5, 2), 1), 1e-9, 500, diss = TRUE)
}
emit("clusterfanny", "cluster", list(cases))
