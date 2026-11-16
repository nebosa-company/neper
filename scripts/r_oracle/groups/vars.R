# vars: VAR(type = "const") coefficients, the residual covariance and VARselect's criteria.
#   args: (T0, K, p, lag_max, y row-major T0 by K...)   fn "coef" "sigma" (sums weighted by position), "aic" "hq" "sc" "fpe" (VARselect at lag p)
suppressMessages(library(vars))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261234 %% 100000)
for (rep in 1:20) {
  K <- sample(2:3, 1); T0 <- sample(50:120, 1); p <- sample(1:3, 1); lm_ <- p + sample(0:2, 1)
  A <- matrix(runif(K * K, -0.3, 0.3), K, K); y <- matrix(0, T0, K); for (t in 2:T0) y[t, ] <- A %*% y[t - 1, ] + rnorm(K); y <- round(y, 5)
  colnames(y) <- paste0("s", 1:K)
  a <- c(T0, K, p, lm_, as.vector(t(y)))
  v <- VAR(y, p = p, type = "const"); B <- Bcoef(v); add("coef", a, sum(as.vector(t(B)) * seq_len(length(B))))
  S <- summary(v)$covres; add("sigma", a, sum(as.vector(S) * seq_len(length(S))))
  vs <- VARselect(y, lag.max = lm_, type = "const")$criteria
  add("aic", a, vs[1, p]); add("hq", a, vs[2, p]); add("sc", a, vs[3, p]); add("fpe", a, vs[4, p])
}
for (rep in 1:15) {
  K <- sample(2:3, 1); T0 <- sample(60:120, 1); p <- sample(1:3, 1); h <- 5
  A <- matrix(runif(K * K, -0.3, 0.3), K, K); y <- matrix(0, T0, K); for (t in 2:T0) y[t, ] <- A %*% y[t - 1, ] + rnorm(K); y <- round(y, 5); colnames(y) <- paste0("s", 1:K)
  a <- c(T0, K, p, p, y2 <- as.vector(t(y)))
  v <- VAR(y, p = p, type = "const"); fc <- predict(v, n.ahead = h)$fcst
  fm <- sapply(fc, function(m) m[, "fcst"]); add("fcst", a, sum(as.vector(t(fm)) * seq_len(length(fm))))
  ir <- irf(v, n.ahead = h, ortho = FALSE, boot = FALSE)$irf
  tot <- 0; pos <- 0; for (imp in names(ir)) for (i in 0:h) for (j in seq_len(K)) { pos <- pos + 1; tot <- tot + ir[[imp]][i + 1, j] * pos }
  add("irf", a, tot)
  io <- irf(v, n.ahead = h, ortho = TRUE, boot = FALSE)$irf
  tot <- 0; pos <- 0; for (imp in names(io)) for (i in 0:h) for (j in seq_len(K)) { pos <- pos + 1; tot <- tot + io[[imp]][i + 1, j] * pos }
  add("oirf", a, tot)
}
emit("vars", "vars", list(cases))
