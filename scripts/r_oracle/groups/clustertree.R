# cluster 2.1.8.2: agnes (every method and par.method), diana, mona, with the coefficients and cutree. Every case is one number: a position-weighted
# checksum sum(v * seq_along(v)) of a result vector, or a scalar. NA in an input is sent as -999999 (mona: 2).
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
cs <- function(v) sum(as.numeric(v) * seq_along(v))
enc <- function(x) { x[is.na(x)] <- -999999; as.vector(x) }
set.seed(20261120)
# ---- agnes (all methods, par.method, NA, stand, manhattan), diana: heights, order, merge, coefficient, cutree, coef.hclust, coefHier
#   agnes_*  args: (n, p, metric, stand, method 1..7, npar, par..., kcut, x column-major)    diana_*  the same with method 0 and npar 0
METH <- c("average", "single", "complete", "ward", "weighted", "flexible", "gaverage")
twins_cases <- function(tag, ag, a, kcut) {
  add(paste0(tag, "_height"), a, cs(ag$height)); add(paste0(tag, "_order"), a, cs(ag$order))
  add(paste0(tag, "_merge"), a, cs(as.vector(ag$merge))); add(paste0(tag, "_coef"), a, coef(ag))
  add(paste0(tag, "_cutree"), a, cs(cutree(as.hclust(ag), kcut)))
  add(paste0(tag, "_coefhier"), a, coefHier(ag))
  ch <- try(coef.hclust(as.hclust(ag)), silent = TRUE)
  if (!inherits(ch, "try-error")) add(paste0(tag, "_coefhclust"), a, ch)
}
for (rep in 1:84) {
  n <- sample(c(4:12, 20, 35), 1); p <- sample(1:3, 1); metric <- sample(c("euclidean", "manhattan"), 1); stand <- rep %% 5 == 0
  mi <- (rep %% 7) + 1; method <- METH[mi]
  X <- matrix(round(rnorm(n * p) * 3, sample(1:3, 1)), n, p) + matrix(rep(sample(0:3, n, replace = TRUE) * 3, p), n, p)
  if (rep %% 9 == 0) X[sample(n * p, max(1, n %/% 5))] <- NA
  if (any(rowSums(!is.na(X)) == 0)) next
  par <- numeric(0)
  if (method == "flexible") par <- switch(sample(1:3, 1), 0.625, c(0.6, 0.6, -0.2), c(0.5, 0.5, -0.25, 0.1))
  if (method == "gaverage" && rep %% 2 == 0) par <- switch(sample(1:3, 1), -0.2, c(1.1, 1.1, -0.1), c(1.2, 1, -0.1, 0.05))
  kcut <- sample(1:n, 1)
  ag <- try(if (length(par)) agnes(X, metric = metric, stand = stand, method = method, par.method = par, keep.diss = FALSE, keep.data = FALSE)
            else agnes(X, metric = metric, stand = stand, method = method, keep.diss = FALSE, keep.data = FALSE), silent = TRUE)
  if (inherits(ag, "try-error")) next
  a <- c(n, p, if (metric == "euclidean") 1 else 2, stand, mi, length(par), par, kcut, enc(X))
  twins_cases("agnes", ag, a, kcut)
  dv <- try(diana(X, metric = metric, stand = stand, keep.diss = FALSE, keep.data = FALSE), silent = TRUE)
  if (inherits(dv, "try-error")) next
  a <- c(n, p, if (metric == "euclidean") 1 else 2, stand, 0, 0, kcut, enc(X))
  twins_cases("diana", dv, a, kcut)
}
# ---- mona: binary data with and without NA
#   mona_*  args: (n, p, x column-major with 0, 1, NA = 2)
for (rep in 1:60) {
  n <- sample(6:30, 1); p <- sample(2:7, 1)
  X <- matrix(sample(0:1, n * p, replace = TRUE, prob = c(runif(1, .3, .7), 1)), n, p)
  if (rep %% 3 == 0) X[sample(n * p, sample(1:3, 1))] <- NA
  mo <- try(mona(X), silent = TRUE)
  if (inherits(mo, "try-error")) next
  Xi <- X; Xi[is.na(Xi)] <- 2
  a <- c(n, p, as.vector(Xi))
  add("mona_order", a, cs(mo$order)); add("mona_variable", a, cs(as.integer(ifelse(mo$variable == "NULL", 0, mo$variable))))
  add("mona_step", a, cs(mo$step)); add("mona_data", a, cs(as.vector(mo$data)))
}
emit("clustertree", "cluster", list(cases))
