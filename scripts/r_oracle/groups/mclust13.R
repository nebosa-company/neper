# mclust, thirteenth part: MclustDR from a Mclust and a MclustDA fit.
# "dr" (id, lambda, normalized, n, p, g, f[g], mean[p g], sigma[g p p], X[n p]) with the mixture of the fit (dr$pro, dr$mu, dr$sigma);
# id 0 sum(q * M), 1 M.I, 2 M.II, 3 evalues, 4 numdir, 5 sum(q * basis), 6 std.basis, 7 dir
suppressMessages(library(mclust))
cases <- list()
set.seed(20261220)
one <- function(n, p, G, kind) {
  cl <- sample(G, n, TRUE)
  X <- matrix(rnorm(n * p), n, p) * rep(runif(p, 0.6, 1.6), each = n) + 2.5 * (cl - 1)
  if (p > 1) X[, 2] <- X[, 2] + 0.5 * X[, 1]
  obj <- tryCatch(suppressWarnings(if (kind == 1) Mclust(X, G = G, modelNames = "VVV", verbose = FALSE) else MclustDA(X, class = cl, modelType = "EDDA", verbose = FALSE)), error = function(e) NULL)
  if (is.null(obj)) return(invisible(NULL))
  for (lam in c(1, 0.5, 0)) for (nz in c(TRUE, FALSE)) {
    dr <- tryCatch(suppressWarnings(MclustDR(obj, lambda = lam, normalized = nz)), error = function(e) NULL)
    if (is.null(dr)) next
    sg <- dr$sigma; g <- dr$G
    args <- c(lam, as.numeric(nz), n, p, g, dr$pro, as.vector(dr$mu), as.vector(sg), X)
    add <- function(id, want) cases[[length(cases) + 1]] <<- case("dr", c(id, args), want, rel = 1e-7, abs = 1e-9)
    sq <- function(m) sum(seq_along(m) * as.vector(m))
    add(0, sq(dr$M)); add(1, sq(dr$M.I)); add(2, sq(dr$M.II)); add(3, sq(dr$evalues)); add(4, dr$numdir)
    add(5, sq(dr$basis)); add(6, sq(dr$std.basis)); add(7, sq(dr$dir))
  }
}
for (rep in 1:3) one(sample(40:70, 1), sample(2:4, 1), sample(2:3, 1), 1)
for (rep in 1:3) one(sample(40:70, 1), sample(2:4, 1), sample(2:3, 1), 2)
emit("mclust13", "mclust", list(cases))
