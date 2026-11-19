# ordinal::clm, cumulative link models without constant column, at a tight convergence tolerance.
#   args: (n, p, K, link 0 logit 1 probit 2 cloglog, y[n] 0-based, x[n*p] row-major)
#   fn "ll" (log-likelihood), "theta" (thresholds weighted by position), "beta" (coefficients weighted by position)
suppressMessages(library(ordinal))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-7)
set.seed(20261209)
links <- c("logit", "probit", "cloglog")
for (rep in 1:24) {
  n <- sample(100:250, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- (rep - 1) %% 3
  x <- matrix(rnorm(n * p), n); b <- rnorm(p); th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else log(-log(runif(n)))
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(clm(y ~ ., data = d, link = links[lk + 1], control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, K, lk, y, as.vector(t(x)))
  add("ll", a, as.numeric(logLik(f))); add("theta", a, sum(f$alpha * seq_along(f$alpha))); add("beta", a, sum(f$beta * seq_along(f$beta)))
}
# loglog (link 3); cauchit (link 4) has several local maxima and R and the port reach different ones, see D7508
set.seed(20262480)
for (rep in 1:16) {
  n <- sample(150:300, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- 3
  x <- matrix(rnorm(n * p), n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- -log(-log(runif(n)))
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(clm(y ~ ., data = d, link = "loglog", control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, K, lk, y, as.vector(t(x)))
  add("ll", a, as.numeric(logLik(f))); add("theta", a, sum(f$alpha * seq_along(f$alpha))); add("beta", a, sum(f$beta * seq_along(f$beta)))
}
# threshold = "equidistant" (links 0 .. 2, K >= 4): "eqll", "eqa" (threshold.1), "eqb" (spacing), "eqbeta" (position-weighted coefficients), args as "ll"
set.seed(20262481)
for (rep in 1:18) {
  n <- sample(150:300, 1); p <- sample(1:3, 1); K <- sample(4:6, 1); lk <- (rep - 1) %% 3
  x <- matrix(rnorm(n * p), n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1, 0, 0.3)) + seq(-1, 1, length.out = K - 1) * 1.2
  eta <- as.vector(x %*% b); u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else log(-log(runif(n)))
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(clm(y ~ ., data = d, link = links[lk + 1], threshold = "equidistant", control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, K, lk, y, as.vector(t(x)))
  add("eqll", a, as.numeric(logLik(f))); add("eqa", a, unname(f$alpha[1])); add("eqb", a, unname(f$alpha[2])); add("eqbeta", a, sum(f$beta * seq_along(f$beta)))
}
# threshold = "symmetric" (links 0 .. 2, K 3 .. 7): "syll", "syth" (the full thresholds weighted by position), "sybeta"; args as "ll"
set.seed(20262482)
for (rep in 1:24) {
  n <- sample(200:400, 1); p <- sample(1:3, 1); K <- 3 + (rep - 1) %% 5; lk <- (rep - 1) %% 3
  x <- matrix(rnorm(n * p), n); b <- rnorm(p) * 0.7; th <- seq(-1.5, 1.5, length.out = K - 1) + rnorm(K - 1, 0, 0.15)
  eta <- as.vector(x %*% b); u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else log(-log(runif(n)))
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(clm(y ~ ., data = d, link = links[lk + 1], threshold = "symmetric", control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, K, lk, y, as.vector(t(x)))
  add("syll", a, as.numeric(logLik(f))); add("syth", a, sum(as.numeric(f$Theta) * seq_along(f$Theta))); add("sybeta", a, sum(f$beta * seq_along(f$beta)))
}
# case weights: "wll", "wtheta", "wbeta" with args (n, p, K, link, y, x, w[n])
set.seed(20262483)
for (rep in 1:18) {
  n <- sample(150:300, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- (rep - 1) %% 3
  x <- matrix(rnorm(n * p), n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else log(-log(runif(n)))
  y <- findInterval(eta + u, th); w <- round(runif(n, 0.3, 3), 2)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE); d$w <- w
  f <- tryCatch(clm(y ~ . - w, data = d, weights = w, link = links[lk + 1], control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, K, lk, y, as.vector(t(x)), w)
  add("wll", a, as.numeric(logLik(f))); add("wtheta", a, sum(f$alpha * seq_along(f$alpha))); add("wbeta", a, sum(f$beta * seq_along(f$beta)))
}
# predict(type = "prob") on new data: "pr" with args (n, p, K, link, y, x, m, xnew[m * p], j): P(y = class j) of the new row, summed over rows weighted by position
set.seed(20262484)
for (rep in 1:18) {
  n <- sample(150:300, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- (rep - 1) %% 3; m <- sample(5:15, 1)
  x <- matrix(rnorm(n * p), n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else log(-log(runif(n)))
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(clm(y ~ ., data = d, link = links[lk + 1], control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  if (is.null(f)) next
  xn <- matrix(rnorm(m * p), m); dn <- as.data.frame(xn); names(dn) <- paste0("v", seq_len(p))
  pr <- predict(f, newdata = dn, type = "prob")$fit
  a <- c(n, p, K, lk, y, as.vector(t(x)), m, as.vector(t(xn)))
  for (j in 1:K) add("pr", c(a, j - 1), sum(pr[, j] * seq_len(m)))
}
# anova of nested fits (drop the last covariate): "an" args (n, p, K, link, y, x) and the statistic ("anst") and p-value ("anp")
set.seed(20262485)
for (rep in 1:18) {
  n <- sample(150:300, 1); p <- sample(2:3, 1); K <- sample(3:5, 1); lk <- (rep - 1) %% 3
  x <- matrix(rnorm(n * p), n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else log(-log(runif(n)))
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f1 <- tryCatch(clm(y ~ ., data = d, link = links[lk + 1], control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  f0 <- tryCatch(clm(as.formula(paste("y ~", paste(paste0("v", seq_len(p - 1)), collapse = " + "))), data = d, link = links[lk + 1], control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  if (is.null(f1) || is.null(f0)) next
  an <- anova(f0, f1); a <- c(n, p, K, lk, y, as.vector(t(x)))
  add("anst", a, an[["LR.stat"]][2]); add("anp", a, an[["Pr(>Chisq)"]][2])
}
emit("ordinal", "ordinal", list(cases))
