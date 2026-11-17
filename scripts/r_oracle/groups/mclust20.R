# mclust, twentieth part: predict.Mclust of a fit with a noise component (E step with the noise column).
# "pnz" (id, n, p, g, vinv, pro[g + 1], mean[p g], sigma[g p p], Xnew[n p]): id 0 sum(q * z) (n by g + 1), 1 sum(i * classification) (noise 0), 2 loglik of the E step is not reported by predict
suppressMessages(library(mclust))
cases <- list()
set.seed(20261228)
for (rep in 1:30) {
  p <- sample(1:3, 1); n0 <- sample(80:120, 1); nn <- 15; m <- n0 - nn
  cl <- sample(2, m, TRUE)
  X1 <- matrix(rnorm(m * p), m, p) + 4 * (cl - 1); X2 <- matrix(runif(nn * p, min(X1) - 2, max(X1) + 2), nn, p)
  X <- rbind(X1, X2)
  mn <- if (p == 1) "V" else c("VVV", "EEE", "VII", "EEV")[rep %% 4 + 1]
  fit <- tryCatch(suppressWarnings(Mclust(X, G = 2, modelNames = mn, initialization = list(noise = (m + 1):n0), verbose = FALSE)), error = function(e) NULL)
  if (is.null(fit) || fit$G != 2) next
  P <- fit$parameters; sg <- P$variance$sigma; if (p == 1) sg <- P$variance$sigmasq; if (length(sg) < 2 * p * p) sg <- rep(sg, length.out = 2 * p * p)
  Xn <- matrix(runif(40 * p, min(X) - 1, max(X) + 1), 40, p)
  pr <- predict(fit, Xn)
  args <- c(40, p, 2, (1 / fit$hypvol), P$pro, as.vector(P$mean), as.vector(sg), Xn)
  add <- function(id, want) cases[[length(cases) + 1]] <<- case("pnz", c(id, args), want, rel = 1e-9, abs = 1e-12)
  add(0, sum(seq_along(pr$z) * as.vector(pr$z))); add(1, sum(seq_len(40) * pr$classification))
}
emit("mclust20", "mclust", list(cases))
