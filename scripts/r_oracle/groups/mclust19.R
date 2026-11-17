# mclust, nineteenth part: Mclust with a noise component, initialization = list(noise = idx), Vinv = hypvol(data, reciprocal = TRUE).
# "mfit" (id, n, p, gmin, gmax, nm, models[nm], nn, noise[nn] 1-based, X[n p]); ids as mclust8: 0 bic, 1 G, 2 model, 3 loglik, 5 df,
# 10 + j / 40 + j BIC column j (finite sum / NA pattern), 100 sum(i * classification) (noise 0), 101 uncertainty, 102 sum(q * z) (G + 1 columns), 103 pro (G + 1), 104 mean, 105 sigma
suppressMessages(library(mclust))
cases <- list()
set.seed(20261227)
tbl <- c("E", "V", "EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EVE", "VEE", "VVE", "EEV", "VEV", "EVV", "VVV")
add <- function(args, id, want, rel = 1e-6, abs = 1e-9) cases[[length(cases) + 1]] <<- case("mfit", c(id, args), want, rel = rel, abs = abs)
one <- function(n, p, gmin, gmax, mm) {
  G0 <- sample(2:3, 1); nn <- max(6, n %/% 6); m <- n - nn
  cl <- sample(G0, m, TRUE)
  X1 <- matrix(rnorm(m * p), m, p) * rep(runif(p, 0.5, 1.2), each = m) + 4 * (cl - 1)
  X2 <- matrix(runif(nn * p, min(X1) - 2, max(X1) + 2), nn, p)
  X <- rbind(X1, X2); noise <- (m + 1):n
  fit <- tryCatch(suppressWarnings(Mclust(X, G = gmin:gmax, modelNames = mm, initialization = list(noise = noise), verbose = FALSE)), error = function(e) NULL)
  if (is.null(fit)) return(invisible(NULL))
  args <- c(n, p, gmin, gmax, length(mm), match(mm, tbl) - 1, nn, noise, X)
  B <- unclass(fit$BIC)[, mm, drop = FALSE]
  Gn <- fit$G
  add(args, 0, fit$bic); add(args, 1, Gn); add(args, 2, match(sub(",.*", "", names(pickBIC(fit$BIC, 1))), tbl) - 1)
  if (Gn > 0) {
    sg <- fit$parameters$variance$sigma; if (fit$modelName == "E") sg <- rep(sg, Gn)
    add(args, 3, fit$loglik); add(args, 5, fit$df)
    add(args, 100, sum(seq_len(n) * fit$classification), rel = 0, abs = 0); add(args, 101, sum(seq_len(n) * fit$uncertainty))
    add(args, 102, sum(seq_along(fit$z) * as.vector(fit$z))); add(args, 103, sum(seq_along(fit$parameters$pro) * fit$parameters$pro))
    add(args, 104, sum(seq_along(fit$parameters$mean) * as.vector(fit$parameters$mean))); add(args, 105, sum(seq_along(sg) * as.vector(sg)))
  }
  for (j in seq_along(mm)) { b <- B[, j]; add(args, 10 + j - 1, sum(seq_along(b) * ifelse(is.na(b), 0, b))); add(args, 40 + j - 1, sum(seq_along(b) * is.na(b)), rel = 0, abs = 0) }
}
for (mn in c("EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EVE", "VEE", "VVE", "EEV", "VEV", "EVV", "VVV"))
  one(sample(70:100, 1), 2, 0, 4, mn)
one(sample(80:110, 1), 1, 0, 4, c("E", "V"))
one(sample(60:90, 1), 2, 0, 4, c("EII", "VII", "EEI", "VVI", "EEE", "VVV"))
emit("mclust19", "mclust", list(cases))
