# mclust, sixth part: MclustDA and EDDA with logLik, BIC, df and predict.
# "mda" (id, type 0 MclustDA 1 EDDA, n, d, nclass, gmax, nm, models[nm], nn, class[n] 0-based, X[n d], Xnew[nn d]); ids: 0 loglik, 1 bic, 2 df, 3 EDDA model index (-1 for MclustDA),
# 4 sum((c) * G_c), 5 sum(c * model index of class c), 6 sum(q * predicted z), 7 sum(i * predicted class)
suppressMessages(library(mclust))
cases <- list()
set.seed(20261204)
tbl <- c("E", "V", "EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EVE", "VEE", "VVE", "EEV", "VEV", "EVV", "VVV")
add <- function(args, id, want, rel = 1e-6, abs = 1e-9) cases[[length(cases) + 1]] <<- case("mda", c(id, args), want, rel = rel, abs = abs)
one <- function(type, n, d, nclass, gmax) {
  cl <- sample(nclass, n, TRUE)
  X <- matrix(rnorm(n * d), n, d) * rep(runif(d, 0.6, 1.5), each = n) + 2.2 * (cl - 1) + (if (d > 1) matrix(rnorm(d), n, d, byrow = TRUE) * 0 else 0)
  if (d > 1) X[, 2] <- X[, 2] + 0.4 * X[, 1]
  mm <- if (d == 1) c("E", "V") else c("EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "VEE", "EVE", "VVE", "EEV", "VEV", "EVV", "VVV")
  nn <- sample(5:12, 1); Xn <- matrix(rnorm(nn * d) * 1.5 + 1, nn, d)
  m <- tryCatch(suppressWarnings(MclustDA(X, factor(cl), G = 1:gmax, modelNames = mm, modelType = c("MclustDA", "EDDA")[type + 1], verbose = FALSE)), error = function(e) NULL)
  if (is.null(m)) return(invisible(NULL))
  pr <- predict(m, Xn)
  args <- c(type, n, d, nclass, gmax, length(mm), match(mm, tbl) - 1, nn, cl - 1, X, Xn)
  Gs <- sapply(m$models, function(q) q$G); Ms <- if (type == 0) sapply(m$models, function(q) match(sub(",.*", "", names(pickBIC(q$BIC, 1))), tbl) - 1) else 0
  if (type == 1) { Ms <- rep(match(m$models[[1]]$modelName, tbl) - 1, nclass) }
  add(args, 0, m$loglik); add(args, 1, m$bic); add(args, 2, m$df); add(args, 3, if (type == 1) Ms[1] else -1)
  add(args, 4, sum(seq_len(nclass) * Gs)); add(args, 5, sum(seq_len(nclass) * Ms))
  add(args, 6, sum(seq_along(pr$z) * as.vector(pr$z))); add(args, 7, sum(seq_len(nn) * as.integer(pr$classification)), rel = 0, abs = 0)
}
for (rep in 1:6) one(0, sample(70:110, 1), sample(2:3, 1), sample(2:3, 1), 2)
for (rep in 1:6) one(1, sample(60:100, 1), sample(2:3, 1), sample(2:3, 1), 1)
for (rep in 1:2) one(0, sample(60:100, 1), 1, 2, 3)
for (rep in 1:2) one(1, sample(60:100, 1), 1, sample(2:3, 1), 1)
emit("mclust6", "mclust", list(cases))
