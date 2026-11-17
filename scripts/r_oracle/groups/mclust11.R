# mclust, eleventh part: the layout of mclust8 with prior = priorControl() (no EVE, VEE, VVE, EVV, no mclustICL ids).
# "mfit" (id, n, p, gmin, gmax, nm, model indices[nm], X[n p] column-major); ids: 0 bic, 1 G, 2 model index, 3 loglik, 4 icl, 5 df,
# 10 + j the weighted sum of the finite BIC values of column j, 40 + j the weighted sum of its NA pattern (weights are the row numbers),
# 200 + j the weighted sum of the finite ICL values of column j (mclustICL), 100 sum(i * classification), 101 sum(i * uncertainty), 102 sum(q * z), 103 sum(q * pro), 104 sum(q * mean), 105 sum(q * sigma)
suppressMessages(library(mclust))
cases <- list()
set.seed(20261218)
tbl <- c("E", "V", "EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EVE", "VEE", "VVE", "EEV", "VEV", "EVV", "VVV")
add <- function(args, id, want, rel = 1e-6, abs = 1e-9) cases[[length(cases) + 1]] <<- case("mfit", c(id, args), want, rel = rel, abs = abs)
one <- function(n, p, gmin, gmax, kind) {
  G0 <- sample(2:3, 1); cl <- sample(G0, n, TRUE)
  X <- matrix(rnorm(n * p), n, p) * rep(runif(p, 0.6, 1.6), each = n) * (1 + 0.5 * (cl - 1) * (kind == 2)) + 3 * (cl - 1)
  if (p > 1) X[, 2] <- X[, 2] + 0.5 * X[, 1] * (kind == 1)
  mm <- if (p == 1) c("E", "V") else c("EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EEV", "VEV", "VVV")
  m <- tryCatch(suppressWarnings(Mclust(X, G = gmin:gmax, modelNames = mm, prior = priorControl(), verbose = FALSE)), error = function(e) NULL)
  if (is.null(m)) return(invisible(NULL))
  args <- c(n, p, gmin, gmax, length(mm), match(mm, tbl) - 1, X)
  B <- unclass(m$BIC)[, mm, drop = FALSE]
  Gn <- m$G; sg <- m$parameters$variance$sigma; if (m$modelName == "E") sg <- rep(sg, Gn)
  add(args, 0, m$bic); add(args, 1, Gn); add(args, 2, match(sub(",.*", "", names(pickBIC(m$BIC, 1))), tbl) - 1); add(args, 3, m$loglik); add(args, 4, m$icl); add(args, 5, m$df)
  for (j in seq_along(mm)) { b <- B[, j]; add(args, 10 + j - 1, sum(seq_along(b) * ifelse(is.na(b), 0, b))); add(args, 40 + j - 1, sum(seq_along(b) * is.na(b)), rel = 0, abs = 0) }
  add(args, 100, sum(seq_len(n) * m$classification), rel = 0, abs = 0); add(args, 101, sum(seq_len(n) * m$uncertainty), 1e-6, 1e-9)
  add(args, 102, sum(seq_along(m$z) * as.vector(m$z))); add(args, 103, sum(seq_along(m$parameters$pro) * m$parameters$pro))
  add(args, 104, sum(seq_along(m$parameters$mean) * as.vector(m$parameters$mean))); add(args, 105, sum(seq_along(sg) * as.vector(sg)))
}
for (rep in 1:2) one(sample(70:100, 1), 2, 1, 4, 2)
for (rep in 1:2) one(sample(50:70, 1), 3, 1, 4, 1)
for (rep in 1:1) one(sample(60:90, 1), 3, 1, 4, 2)
for (rep in 1:2) one(sample(60:120, 1), 1, 1, 5, 2)
emit("mclust11", "mclust", list(cases))
