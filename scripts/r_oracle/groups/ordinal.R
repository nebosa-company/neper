# ordinal::clm, cumulative link models without constant column, at a tight convergence tolerance.
#   args: (n, p, K, link 0 logit 1 probit 2 cloglog, y[n] 0-based, x[n*p] row-major)
#   fn "ll" (log-likelihood), "theta" (thresholds weighted by position), "beta" (coefficients weighted by position)
suppressMessages(library(ordinal))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
set.seed(20261209)
links <- c("logit", "probit", "cloglog")
links5 <- c(links, "loglog", "cauchit")
# draws for links 0 .. 4; covariates are rounded to multiples of 1/32 (short exact decimals) everywhere so the golden stays small
draw_u <- function(lk, n, rep = 0) if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else if (lk == 2) log(-log(runif(n))) else if (lk == 3) -log(-log(runif(n))) else if (rep %% 2 == 0) rcauchy(n) else rnorm(n)
for (rep in 1:24) {
  n <- sample(60:150, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- (rep - 1) %% 3
  x <- matrix(round(rnorm(n * p) * 32) / 32, n); b <- rnorm(p); th <- sort(rnorm(K - 1)) * 1.2
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
  n <- sample(90:180, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- 3
  x <- matrix(round(rnorm(n * p) * 32) / 32, n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- -log(-log(runif(n)))
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(clm(y ~ ., data = d, link = "loglog", control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, K, lk, y, as.vector(t(x)))
  add("ll", a, as.numeric(logLik(f))); add("theta", a, sum(f$alpha * seq_along(f$alpha))); add("beta", a, sum(f$beta * seq_along(f$beta)))
}
# cauchit (link 4): R starts from a loose probit fit, the port repeats that path (set.start) and so reaches R's local maximum
set.seed(20262490)
for (rep in 1:20) {
  n <- sample(90:180, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- 4
  x <- matrix(round(rnorm(n * p) * 32) / 32, n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- if (rep %% 2 == 0) rcauchy(n) else rnorm(n)
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(suppressWarnings(clm(y ~ ., data = d, link = "cauchit", control = clm.control(gradTol = 1e-10, maxIter = 500))), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, K, lk, y, as.vector(t(x)))
  add("ll", a, as.numeric(logLik(f))); add("theta", a, sum(f$alpha * seq_along(f$alpha))); add("beta", a, sum(f$beta * seq_along(f$beta)))
}
# threshold = "equidistant" (links 0 .. 2, K >= 4): "eqll", "eqa" (threshold.1), "eqb" (spacing), "eqbeta" (position-weighted coefficients), args as "ll"
set.seed(20262481)
for (rep in 1:18) {
  n <- sample(90:180, 1); p <- sample(1:3, 1); K <- sample(4:6, 1); lk <- (rep - 1) %% 3
  x <- matrix(round(rnorm(n * p) * 32) / 32, n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1, 0, 0.3)) + seq(-1, 1, length.out = K - 1) * 1.2
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
  n <- sample(120:240, 1); p <- sample(1:3, 1); K <- 3 + (rep - 1) %% 5; lk <- (rep - 1) %% 3
  x <- matrix(round(rnorm(n * p) * 32) / 32, n); b <- rnorm(p) * 0.7; th <- seq(-1.5, 1.5, length.out = K - 1) + rnorm(K - 1, 0, 0.15)
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
  n <- sample(90:180, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- (rep - 1) %% 3
  x <- matrix(round(rnorm(n * p) * 32) / 32, n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else log(-log(runif(n)))
  y <- findInterval(eta + u, th); w <- round(runif(n, 0.3, 3) * 32) / 32
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE); d$w <- w
  f <- tryCatch(clm(y ~ . - w, data = d, weights = w, link = links[lk + 1], control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, K, lk, y, as.vector(t(x)), w)
  add("wll", a, as.numeric(logLik(f))); add("wtheta", a, sum(f$alpha * seq_along(f$alpha))); add("wbeta", a, sum(f$beta * seq_along(f$beta)))
}
# predict(type = "prob") on new data, links 0 .. 4: "pr" with args (n, p, K, link, y, x, m, xnew[m * p]): P(y = class j) of new row i, summed with weight i * j
set.seed(20262484)
for (rep in 1:25) {
  n <- sample(90:180, 1); p <- sample(1:3, 1); K <- sample(3:5, 1); lk <- (rep - 1) %% 5; m <- sample(5:15, 1)
  x <- matrix(round(rnorm(n * p) * 32) / 32, n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- draw_u(lk, n, rep)
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(suppressWarnings(clm(y ~ ., data = d, link = links5[lk + 1], control = clm.control(gradTol = 1e-10, maxIter = 500))), error = function(e) NULL)
  if (is.null(f)) next
  xn <- matrix(round(rnorm(m * p) * 32) / 32, m); dn <- as.data.frame(xn); names(dn) <- paste0("v", seq_len(p))
  pr <- predict(f, newdata = dn, type = "prob")$fit
  a <- c(n, p, K, lk, y, as.vector(t(x)), m, as.vector(t(xn)))
  add("pr", a, sum(pr * outer(seq_len(m), seq_len(K))))
}
# anova of nested fits (drop the last covariate): "an" args (n, p, K, link, y, x) and the statistic ("anst") and p-value ("anp")
set.seed(20262485)
for (rep in 1:25) {
  n <- sample(90:180, 1); p <- sample(2:3, 1); K <- sample(3:5, 1); lk <- (rep - 1) %% 5
  x <- matrix(round(rnorm(n * p) * 32) / 32, n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- draw_u(lk, n, rep)
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); d$y <- factor(y, ordered = TRUE)
  f1 <- tryCatch(suppressWarnings(clm(y ~ ., data = d, link = links5[lk + 1], control = clm.control(gradTol = 1e-10, maxIter = 500))), error = function(e) NULL)
  f0 <- tryCatch(suppressWarnings(clm(as.formula(paste("y ~", paste(paste0("v", seq_len(p - 1)), collapse = " + "))), data = d, link = links5[lk + 1], control = clm.control(gradTol = 1e-10, maxIter = 500))), error = function(e) NULL)
  if (is.null(f1) || is.null(f0)) next
  an <- anova(f0, f1); a <- c(n, p, K, lk, y, as.vector(t(x)))
  add("anst", a, an[["LR.stat"]][2]); add("anp", a, an[["Pr(>Chisq)"]][2])
}
# scale effects: clm(y ~ x, scale = ~ z): "scll", "scth" (thresholds weighted), "scbeta", "sczeta"; args (n, p, K, link, ps, y, x[n p], z[n ps])
set.seed(20262486)
for (rep in 1:18) {
  n <- sample(150:270, 1); p <- sample(1:2, 1); ps <- sample(1:2, 1); K <- sample(3:5, 1); lk <- (rep - 1) %% 3
  x <- matrix(round(rnorm(n * p) * 32) / 32, n); z <- matrix(round(rnorm(n * ps) * 32) / 32, n); b <- rnorm(p) * 0.7; zeta <- rnorm(ps) * 0.35; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); sg <- exp(as.vector(z %*% zeta)); u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else log(-log(runif(n)))
  y <- findInterval(eta + sg * u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); zd <- as.data.frame(z); names(zd) <- paste0("s", seq_len(ps)); d <- cbind(d, zd); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(clm(as.formula(paste("y ~", paste0("v", seq_len(p), collapse = " + "))), scale = as.formula(paste("~", paste0("s", seq_len(ps), collapse = " + "))), data = d, link = links[lk + 1], control = clm.control(gradTol = 1e-10, maxIter = 500)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, p, K, lk, ps, y, as.vector(t(x)), as.vector(t(z)))
  add("scll", a, as.numeric(logLik(f))); add("scth", a, sum(f$alpha * seq_along(f$alpha))); add("scbeta", a, sum(f$beta * seq_along(f$beta))); add("sczeta", a, sum(f$zeta * seq_along(f$zeta)))
}
# nominal effects: clm(y ~ x, nominal = ~ w): "nmll", "nmth" (thresholds weighted), "nmbeta", "nmtau" (the sum of squares of the nominal effects, which does not depend on their sign convention); args (n, p, K, link, pn, y, x[n p], w[n pn])
set.seed(20262487)
for (rep in 1:18) {
  n <- sample(180:300, 1); p <- sample(1:2, 1); pn <- 1; K <- sample(3:4, 1); lk <- (rep - 1) %% 3
  x <- matrix(round(rnorm(n * p) * 32) / 32, n); w <- matrix(round(rnorm(n * pn) * 32) / 32, n); b <- rnorm(p) * 0.7; th <- sort(rnorm(K - 1)) * 1.2
  eta <- as.vector(x %*% b); u <- if (lk == 0) rlogis(n) else if (lk == 1) rnorm(n) else log(-log(runif(n)))
  y <- findInterval(eta + u, th)
  if (length(unique(y)) < K) next
  d <- as.data.frame(x); names(d) <- paste0("v", seq_len(p)); wd <- as.data.frame(w); names(wd) <- paste0("w", seq_len(pn)); d <- cbind(d, wd); d$y <- factor(y, ordered = TRUE)
  f <- tryCatch(suppressWarnings(clm(as.formula(paste("y ~", paste0("v", seq_len(p), collapse = " + "))), nominal = as.formula(paste("~", paste0("w", seq_len(pn), collapse = " + "))), data = d, link = links[lk + 1], control = clm.control(gradTol = 1e-9, maxIter = 500))), error = function(e) NULL)
  if (is.null(f) || is.null(f$alpha)) next
  nm <- f$alpha[grepl("[.]w[0-9]+$", names(f$alpha))]; thr <- f$alpha[grepl("[(]Intercept[)]$", names(f$alpha))]
  if (length(nm) == 0) next
  a <- c(n, p, K, lk, pn, y, as.vector(t(x)), as.vector(t(w)))
  add("nmll", a, as.numeric(logLik(f))); add("nmbeta", a, sum(f$beta * seq_along(f$beta))); add("nmtau", a, sum(nm^2)); add("nmth", a, sum(thr * seq_along(thr)))
}
emit("ordinal", "ordinal", list(cases))
