# GPArotation: GPForth (orthogonal) and GPFoblq (oblique), algorithm "bb", over the vgQ criteria.
#   args: (orth 1 or 0, id, normalize, p, k, npar, par..., A by row)   fn "load" (position), "th" (position), "f", "iter"
#   id 0 oblimin(gam) 1 quartimin 2 quartimax 3 cf(kappa) 4 bentler 5 infomax 6 geomin(delta) 7 entropy
#   8 oblimax 9 varimax 10 varimin 11 target(Target) 12 pst(W, Target) 13 tandemI 14 tandemII
library(GPArotation)
set.seed(20261115)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-6)
rowvec <- function(m) as.vector(t(m))
mkA <- function(p, k) {
  A <- matrix(0, p, k); g <- rep(1:k, length.out = p)
  for (i in 1:p) { A[i, ] <- rnorm(k, 0, 0.25); A[i, g[i]] <- runif(1, 0.55, 0.9) }
  round(A, 3)
}
crit <- list(
  list(0, "oblimin", list(gam = 0), 0), list(0, "oblimin", list(gam = 0.5), 0.5), list(1, "quartimin", NULL, NULL),
  list(2, "quartimax", NULL, NULL), list(3, "cf", list(kappa = 0.2), 0.2), list(4, "bentler", NULL, NULL),
  list(5, "infomax", NULL, NULL), list(6, "geomin", list(delta = 0.01), 0.01), list(7, "entropy", NULL, NULL),
  list(8, "oblimax", NULL, NULL), list(9, "varimax", NULL, NULL), list(10, "varimin", NULL, NULL),
  list(13, "tandemI", NULL, NULL), list(14, "tandemII", NULL, NULL))
for (rep in 1:3) {
  p <- c(8, 10, 9)[rep]; k <- c(3, 2, 4)[rep]
  A <- mkA(p, k)
  for (orth in c(1, 0)) for (ci in crit) for (nz in c(0, 1)) {
    if (!orth && ci[[2]] %in% c("varimax", "varimin", "tandemI", "tandemII", "quartimax", "entropy", "oblimax")) next
    f <- if (orth) GPForth else GPFoblq
    r <- tryCatch(suppressWarnings(f(A, normalize = nz == 1, method = ci[[2]], methodArgs = ci[[3]])), error = function(e) NULL)
    if (is.null(r) || !isTRUE(r$convergence) || nrow(r$Table) > 150) next
    par <- if (is.null(ci[[4]])) numeric(0) else ci[[4]]
    a <- c(orth, ci[[1]], nz, p, k, length(par), par, rowvec(A))
    L <- unclass(r$loadings); tb <- r$Table
    for (i in seq_along(rowvec(L))) add("load", c(a, i - 1), rowvec(L)[i])
    for (i in seq_along(rowvec(r$Th))) add("th", c(a, i - 1), rowvec(r$Th)[i])
    add("f", a, tb[nrow(tb), 2]); add("iter", a, nrow(tb) - 1)
  }
}
# target and pst: the target is the clean simple structure of A, NA where the loading is small
for (rep in 1:2) {
  p <- c(8, 9)[rep]; k <- c(3, 2)[rep]
  A <- mkA(p, k)
  Tg <- ifelse(abs(A) > 0.4, 1, 0); Tn <- Tg; Tn[abs(A) < 0.3] <- NA; Tg[is.na(Tg)] <- 0
  W <- ifelse(abs(A) > 0.4, 0, 1)
  for (orth in c(1, 0)) for (nz in c(0, 1)) for (kind in 1:2) {
    f <- if (orth) GPForth else GPFoblq
    if (kind == 1) { r <- tryCatch(suppressWarnings(f(A, normalize = nz == 1, method = "target", methodArgs = list(Target = Tn))), error = function(e) NULL); id <- 11; par <- rowvec(Tn) }
    else { r <- tryCatch(suppressWarnings(f(A, normalize = nz == 1, method = "pst", methodArgs = list(W = W, Target = Tg))), error = function(e) NULL); id <- 12; par <- c(rowvec(W), rowvec(Tg)) }
    if (is.null(r) || !isTRUE(r$convergence) || nrow(r$Table) > 150) next
    a <- c(orth, id, nz, p, k, length(par), par, rowvec(A))
    L <- unclass(r$loadings); tb <- r$Table
    for (i in seq_along(rowvec(L))) add("load", c(a, i - 1), rowvec(L)[i])
    for (i in seq_along(rowvec(r$Th))) add("th", c(a, i - 1), rowvec(r$Th)[i])
    add("f", a, tb[nrow(tb), 2]); add("iter", a, nrow(tb) - 1)
  }
}
emit("gparot", "GPArotation", list(cases))
