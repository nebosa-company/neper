# norm: em.norm (mean and covariance on the original scale, default criterion 1e-4) and loglik.norm, for data with missing values.
#   args: (n, p, criterion, x[n*p] column-major, NaN = missing, q)  q 0..p-1 mu, p..p+p*p-1 sigma (row-major), then loglik
suppressMessages(library(norm))
cases <- list()
set.seed(20261116)
for (rep in 1:25) {
  n <- sample(30:120, 1); p <- sample(2:4, 1)
  L <- matrix(rnorm(p * p), p, p); S <- crossprod(L) + diag(p)
  x <- matrix(rnorm(n * p), n, p) %*% chol(S) + rep(1:p, each = n)
  x <- round(x, 3); miss <- sample(n * p, round(0.15 * n * p)); x[miss] <- NA
  keep <- rowSums(!is.na(x)) > 0; x <- x[keep, , drop = FALSE]; n <- nrow(x)
  crit <- c(1e-4, 1e-8)[rep %% 2 + 1]
  s <- prelim.norm(x); th <- em.norm(s, showits = FALSE, criterion = crit); g <- getparam.norm(s, th)
  xa <- ifelse(is.na(x), NaN, x)
  out <- c(g$mu, as.vector(t(g$sigma)), loglik.norm(s, th))
  a <- c(n, p, crit, as.vector(xa))
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("em", c(a, q - 1), out[q], rel = 1e-8, abs = 1e-9)
}
# logpost.norm ("post": args (n, p, 0, x, tau, m, mu0[p], lambdainv[p*p] row-major, 0), at the em.norm estimate; prior absent in every third case, i.e. tau 0, m -1, zero lambdainv)
for (rep in 1:12) {
  n <- sample(30:100, 1); p <- sample(2:3, 1)
  L <- matrix(rnorm(p * p), p, p); S <- crossprod(L) + diag(p)
  x <- round(matrix(rnorm(n * p), n, p) %*% chol(S) + rep(1:p, each = n), 3); miss <- sample(n * p, round(0.15 * n * p)); x[miss] <- NA
  keep <- rowSums(!is.na(x)) > 0; x <- x[keep, , drop = FALSE]; n <- nrow(x)
  s <- prelim.norm(x); th <- em.norm(s, showits = FALSE)
  tau <- round(runif(1, 0.1, 4), 2); m <- round(runif(1, 1, 8), 2); mu0 <- round(rnorm(p, 0, 0.5), 2); li <- crossprod(matrix(round(rnorm(p * p, 0, 0.5), 2), p, p)) + diag(p)
  v <- if (rep %% 3 == 0) logpost.norm(s, th) else logpost.norm(s, th, list(tau, m, mu0, li))
  if (rep %% 3 == 0) { tau <- 0; m <- -1; mu0 <- numeric(p); li <- matrix(0, p, p) }
  xa <- ifelse(is.na(x), NaN, x)
  cases[[length(cases) + 1]] <- case("post", c(n, p, 0, as.vector(xa), tau, m, mu0, as.vector(t(li)), 0), v, rel = 1e-8, abs = 1e-8)
}
# mi.inference over two quantities ("mi": args (M, conf, est[M*2] by imputation, se[M*2], quantity, which 0..7 est std.err df signif lower upper r fminf))
for (rep in 1:10) {
  M <- sample(3:8, 1); est <- lapply(1:M, function(i) c(a = round(rnorm(1, 2, 0.4), 4), b = round(rnorm(1, 2, 0.4), 4))); se <- lapply(1:M, function(i) c(a = round(runif(1, 0.2, 0.6), 4), b = round(runif(1, 0.2, 0.6), 4))); conf <- c(0.9, 0.95, 0.99)[rep %% 3 + 1]
  r <- mi.inference(est, se, conf)
  vals <- cbind(r$est, r$std.err, r$df, r$signif, r$lower, r$upper, r$r, r$fminf)
  for (qq in 1:2) for (w in 1:8) cases[[length(cases) + 1]] <- case("mi", c(M, conf, unlist(est), unlist(se), qq - 1, w - 1), vals[qq, w], rel = 1e-8, abs = 1e-10)
}
emit("norm", "norm", list(cases))
