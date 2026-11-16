# urca::ca.jo (no exogenous dummies): the eigenvalues, statistics, critical values, V, W, PI and GAMMA.
#   args: (type 0 eigen 1 trace, ecdet 0 none 1 const 2 trend, K, spec 0 longrun 1 transitory, season (0 none), n, p, x col-major[n*p], what, i)
#   what 0 lambda 1 teststat 2 cval (row-major rows 1..p, levels 10 5 1) 3 V 4 W 5 PI 6 GAMMA (row-major flatten); i 0 the sum, 1 the position-weighted sum
suppressMessages(library(urca))
set.seed(20261118)
cases <- list()
add <- function(args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("jo", args, want, rel = 1e-6, abs = 1e-8)
rowmajor <- function(m) as.vector(t(m))
for (rep in 1:8) {
  p <- sample(2:4, 1); n <- sample(70:180, 1)
  common <- cumsum(rnorm(n)); x <- matrix(0, n, p); x[, 1] <- common + rnorm(n, 0, 0.5)
  for (j in 2:p) x[, j] <- if (runif(1) < 0.6) 0.5 * j * common + rnorm(n) else cumsum(rnorm(n))
  x <- round(x, 4); colnames(x) <- paste0("v", 1:p)
  for (ty in 0:1) for (ec in 0:2) for (K in c(2, 3)) for (sp in 0:1) for (se in c(0, 4)) {
    if (se > 0 && rep %% 2 == 1) next
    r <- tryCatch(suppressWarnings(ca.jo(x, type = c("eigen", "trace")[ty + 1], ecdet = c("none", "const", "trend")[ec + 1], K = K, spec = c("longrun", "transitory")[sp + 1], season = if (se > 0) se else NULL)), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(ty, ec, K, sp, se, n, p, x)
    vecs <- list(r@lambda, r@teststat, rowmajor(r@cval), rowmajor(r@V), rowmajor(r@W), rowmajor(r@PI), rowmajor(r@GAMMA))
    for (w in 0:6) { v <- vecs[[w + 1]]; add(c(a, w, 0), sum(v)); add(c(a, w, 1), sum(seq_along(v) * v)) }
  }
}
emit("johansen", "urca", list(cases))
