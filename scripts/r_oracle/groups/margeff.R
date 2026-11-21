# marginaleffects for glms: avg_slopes, avg_predictions and avg_comparisons (a 0 / 1 variable) with delta-method standard errors, from the fitted coefficients.
#   args: (n, p, j (0-based slope column, or p for the average prediction), which 0 estimate 1 se, link 0 identity 1 logit 2 log, kind 0 slope or prediction 1 comparison, beta[p], vcov[p p], X[n p] with the intercept column)
suppressMessages(library(marginaleffects))
cases <- list()
set.seed(20261204)
add <- function(a, est, tol = 1e-9) cases[[length(cases) + 1]] <<- case("ame", a, est, rel = tol, abs = 1e-10)
for (rep in 1:9) {
  link <- rep %% 3; n <- sample(30:45, 1); k <- sample(2:3, 1); X <- matrix(round(rnorm(n * k), 3), n, k); X[, 1] <- rbinom(n, 1, 0.5)
  eta <- 0.3 + X %*% c(0.6, -0.4, 0.3)[1:k] * 0.8
  y <- if (link == 0) as.vector(eta) + rnorm(n) else if (link == 1) rbinom(n, 1, plogis(eta)) else rpois(n, exp(eta * 0.6))
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("v", 1:k)); fam <- list(gaussian, binomial, poisson)[[link + 1]]
  m <- glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), fam, d)
  Xm <- cbind(1, X); b <- coef(m); V <- vcov(m); p <- length(b)
  sl <- as.data.frame(avg_slopes(m, variables = paste0("v", 1:k))); ap <- as.data.frame(avg_predictions(m))
  for (j in 2:k) for (w in 0:1) add(c(n, p, j, w, link, 0, b, V, Xm), if (w == 0) sl$estimate[j] else sl$std.error[j])
  for (w in 0:1) add(c(n, p, p, w, link, 0, b, V, Xm), if (w == 0) ap$estimate[1] else ap$std.error[1])
  cmp <- as.data.frame(avg_comparisons(m, variables = list(v1 = 0:1)))
  for (w in 0:1) add(c(n, p, 1, w, link, 1, b, V, Xm), if (w == 0) cmp$estimate[1] else cmp$std.error[1])
}
# further links: 3 binomial probit, 4 binomial cloglog, 5 Gamma inverse, 6 poisson sqrt
set.seed(20262493)
for (rep in 1:12) {
  link <- 3 + rep %% 4; n <- sample(30:50, 1); k <- sample(2:3, 1); X <- matrix(round(rnorm(n * k), 3), n, k); X[, 1] <- rbinom(n, 1, 0.5)
  eta <- 0.3 + X %*% c(0.6, -0.4, 0.3)[1:k] * 0.8
  y <- if (link == 3) rbinom(n, 1, pnorm(eta)) else if (link == 4) rbinom(n, 1, 1 - exp(-exp(eta))) else if (link == 5) rgamma(n, 4, 4 * (0.9 + 0.15 * X[, 2])) else rpois(n, (0.8 + 0.15 * X[, 2])^2 * 3)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("v", 1:k))
  fam <- list(binomial(link = "probit"), binomial(link = "cloglog"), Gamma(link = "inverse"), poisson(link = "sqrt"))[[link - 2]]
  m <- tryCatch(suppressWarnings(glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), fam, d)), error = function(e) NULL)
  if (is.null(m) || !m$converged) next
  Xm <- cbind(1, X); b <- coef(m); V <- vcov(m); p <- length(b)
  if (link == 5 && any(Xm %*% b <= 0.05)) next
  sl <- as.data.frame(avg_slopes(m, variables = paste0("v", 1:k))); ap <- as.data.frame(avg_predictions(m))
  for (j in 2:k) for (w in 0:1) add(c(n, p, j, w, link, 0, b, V, Xm), if (w == 0) sl$estimate[j] else sl$std.error[j])
  for (w in 0:1) add(c(n, p, p, w, link, 0, b, V, Xm), if (w == 0) ap$estimate[1] else ap$std.error[1])
  cmp <- as.data.frame(avg_comparisons(m, variables = list(v1 = 0:1)))
  for (w in 0:1) add(c(n, p, 1, w, link, 1, b, V, Xm), if (w == 0) cmp$estimate[1] else cmp$std.error[1])
}
# predictions at new rows: "mpred" args (p, link, beta[p], vcov[p p], x row[p], which 0 estimate 1 se)
set.seed(20262494)
for (rep in 1:30) {
  link <- rep %% 7; n <- sample(30:45, 1); k <- sample(2:3, 1); X <- matrix(round(rnorm(n * k), 3), n, k); X[, 1] <- rbinom(n, 1, 0.5)
  eta <- 0.3 + X %*% c(0.6, -0.4, 0.3)[1:k] * 0.8
  y <- switch(link + 1, as.vector(eta) + rnorm(n), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)), rbinom(n, 1, pnorm(eta)), rbinom(n, 1, 1 - exp(-exp(eta))), rgamma(n, 4, 4 * (0.9 + 0.15 * X[, 2])), rpois(n, (0.8 + 0.15 * X[, 2])^2 * 3))
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("v", 1:k))
  fam <- list(gaussian(), binomial(), poisson(), binomial(link = "probit"), binomial(link = "cloglog"), Gamma(link = "inverse"), poisson(link = "sqrt"))[[link + 1]]
  m <- tryCatch(suppressWarnings(glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), fam, d)), error = function(e) NULL)
  if (is.null(m) || !m$converged) next
  b <- coef(m); V <- vcov(m); p <- length(b)
  nd <- data.frame(matrix(round(rnorm(4 * k), 2), 4, k)); names(nd) <- paste0("v", 1:k)
  pr <- tryCatch(as.data.frame(predictions(m, newdata = nd)), error = function(e) NULL)
  if (is.null(pr)) next
  for (r in 1:4) { xr <- c(1, as.numeric(nd[r, ])); ap1 <- tryCatch(as.data.frame(avg_predictions(m, newdata = nd[r, , drop = FALSE])), error = function(e) NULL); for (w in 0:1) { v <- if (w == 0) pr$estimate[r] else if (!is.null(ap1)) ap1$std.error[1] else NA_real_; if (length(v) == 1 && is.finite(v)) cases[[length(cases) + 1]] <- case("mpred", c(p, link, b, V, xr, w), v, rel = 1e-9, abs = 1e-10) } }
}
# hypotheses with equality constraints: "mhyp" args (p, q, beta[p], vcov[p p], r[p], which 0 estimate 1 se 2 z 3 p)
options(marginaleffects_safe = FALSE)
set.seed(20262495)
for (rep in 1:30) {
  n <- sample(60:150, 1); k <- sample(2:4, 1); X <- matrix(round(rnorm(n * k), 3), n, k); d <- data.frame(y = X %*% c(0.5, -0.3, 0.2, 0.1)[1:k] + rnorm(n), X); names(d) <- c("y", paste0("v", 1:k))
  m <- glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), gaussian, d); b <- coef(m); V <- vcov(m); p <- length(b)
  rv <- sample(c(-2, -1, 0, 1, 2), p, TRUE); if (all(rv == 0)) rv[1] <- 1; qv <- sample(c(0, 0.5, -1), 1)
  hyp <- paste0(paste0(ifelse(rv < 0, "-", "+"), abs(rv), "*b", seq_len(p), collapse = ""), "=", qv)
  h <- tryCatch(as.data.frame(hypotheses(m, hypothesis = hyp)), error = function(e) NULL)
  if (is.null(h)) next
  vals <- c(h$estimate[1], h$std.error[1], h$statistic[1], h$p.value[1])
  for (w in 0:3) if (is.finite(vals[w + 1])) cases[[length(cases) + 1]] <- case("mhyp", c(p, qv, b, V, rv, w), vals[w + 1], rel = 1e-9, abs = 1e-10)
}
# unit-change comparisons of a continuous variable: the "ame" layout with kind 2
options(marginaleffects_safe = FALSE)
set.seed(20262496)
for (rep in 1:21) {
  link <- rep %% 7; n <- sample(30:45, 1); k <- sample(2:3, 1); X <- matrix(round(rnorm(n * k), 3), n, k); X[, 1] <- rbinom(n, 1, 0.5)
  eta <- 0.3 + X %*% c(0.6, -0.4, 0.3)[1:k] * 0.8
  y <- switch(link + 1, as.vector(eta) + rnorm(n), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)), rbinom(n, 1, pnorm(eta)), rbinom(n, 1, 1 - exp(-exp(eta))), rgamma(n, 4, 4 * (0.9 + 0.15 * X[, 2])), rpois(n, (0.8 + 0.15 * X[, 2])^2 * 3))
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("v", 1:k))
  fam <- list(gaussian(), binomial(), poisson(), binomial(link = "probit"), binomial(link = "cloglog"), Gamma(link = "inverse"), poisson(link = "sqrt"))[[link + 1]]
  m <- tryCatch(suppressWarnings(glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), fam, d)), error = function(e) NULL)
  if (is.null(m) || !m$converged) next
  Xm <- cbind(1, X); b <- coef(m); V <- vcov(m); p <- length(b)
  if (link == 5 && any(Xm %*% b <= 0.05)) next
  cmp <- tryCatch(as.data.frame(avg_comparisons(m, variables = list(v2 = 1))), error = function(e) NULL)
  if (is.null(cmp)) next
  for (w in 0:1) { v <- if (w == 0) cmp$estimate[1] else cmp$std.error[1]; if (is.finite(v)) add(c(n, p, 2, w, link, 2, b, V, Xm), v) }
}
# ratio, lnratio and lift comparisons of a 0 / 1 variable: "mrat" args (n, p, link, kind 0 ratio 1 lnratio 2 lift, which, beta[p], vcov[p p], X[n p])
options(marginaleffects_safe = FALSE)
set.seed(20262497)
for (rep in 1:21) {
  link <- c(1, 2, 3, 4, 6)[rep %% 5 + 1]; n <- sample(30:45, 1); k <- sample(2:3, 1); X <- matrix(round(rnorm(n * k), 3), n, k); X[, 1] <- rbinom(n, 1, 0.5)
  eta <- 0.3 + X %*% c(0.6, -0.4, 0.3)[1:k] * 0.8
  y <- switch(link, NA, rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)), rbinom(n, 1, pnorm(eta)), rbinom(n, 1, 1 - exp(-exp(eta))), NA, rpois(n, (0.8 + 0.15 * X[, 2])^2 * 3))
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("v", 1:k))
  fam <- list(NA, binomial(), poisson(), binomial(link = "probit"), binomial(link = "cloglog"), NA, poisson(link = "sqrt"))[[link]]
  m <- tryCatch(suppressWarnings(glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), fam, d)), error = function(e) NULL)
  if (is.null(m) || !m$converged) next
  Xm <- cbind(1, X); b <- coef(m); V <- vcov(m); p <- length(b)
  for (kd in 0:2) {
    cp <- c("ratio", "lnratio", "lift")[kd + 1]
    r <- tryCatch(as.data.frame(avg_comparisons(m, variables = list(v1 = 0:1), comparison = cp)), error = function(e) NULL)
    if (is.null(r)) next
    for (w in 0:1) { v <- if (w == 0) r$estimate[1] else r$std.error[1]; if (is.finite(v)) cases[[length(cases) + 1]] <- case("mrat", c(n, p, link - 1, kd, w, b, V, Xm), v, rel = 1e-9, abs = 1e-10) }
  }
}
# unit-level slopes() and comparisons(): "mrow" args (n, p, j, which, link, kind 0 slope 1 0/1 difference 2 unit difference 3 ratio 4 lnratio 5 lift, row (0-based), beta[p], vcov[p p], X[n p])
options(marginaleffects_safe = FALSE)
set.seed(20262498)
for (rep in 1:7) {
  link <- c(0, 1, 2, 3, 4, 6, 1)[rep %% 7 + 1]; n <- sample(30:40, 1); k <- sample(2:3, 1); X <- matrix(round(rnorm(n * k), 3), n, k); X[, 1] <- rbinom(n, 1, 0.5)
  eta <- 0.3 + X %*% c(0.6, -0.4, 0.3)[1:k] * 0.8
  y <- switch(link + 1, as.vector(eta) + rnorm(n), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)), rbinom(n, 1, pnorm(eta)), rbinom(n, 1, 1 - exp(-exp(eta))), NA, rpois(n, (0.8 + 0.15 * X[, 2])^2 * 3))
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("v", 1:k))
  fam <- list(gaussian(), binomial(), poisson(), binomial(link = "probit"), binomial(link = "cloglog"), NA, poisson(link = "sqrt"))[[link + 1]]
  m <- tryCatch(suppressWarnings(glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), fam, d)), error = function(e) NULL)
  if (is.null(m) || !m$converged) next
  Xm <- cbind(1, X); b <- coef(m); V <- vcov(m); p <- length(b)
  rows <- c(1, n)
  for (kd in 0:5) {
    r <- tryCatch(switch(kd + 1,
      as.data.frame(slopes(m, variables = "v2")),
      as.data.frame(comparisons(m, variables = list(v1 = 0:1))),
      as.data.frame(comparisons(m, variables = list(v2 = 1))),
      as.data.frame(comparisons(m, variables = list(v1 = 0:1), comparison = "ratio")),
      as.data.frame(comparisons(m, variables = list(v1 = 0:1), comparison = "lnratio")),
      as.data.frame(comparisons(m, variables = list(v1 = 0:1), comparison = "lift"))), error = function(e) NULL)
    if (is.null(r) || nrow(r) != n) next
    j <- if (kd == 0 || kd == 2) 2 else 1
    for (rw in rows) for (w in 0:1) { v <- if (w == 0) r$estimate[rw] else r$std.error[rw]; if (is.finite(v)) cases[[length(cases) + 1]] <- case("mrow", c(n, p, j, w, link, kd, rw - 1, b, V, Xm), v, rel = 1e-9, abs = 1e-10) }
  }
}
# factor and other contrasts, "mcon" args (n, p, link, kind 0 difference 1 ratio 2 lnratio 3 lift, which, hi[p], lo[p], beta[p], vcov[p p], X[n p]); 1e300 leaves a column as observed
options(marginaleffects_safe = FALSE)
set.seed(20262499)
for (rep in 1:7) {
  link <- c(0, 1, 2, 3, 6, 1, 2)[rep %% 7 + 1]; n <- sample(25:40, 1)
  f <- factor(sample(c("a", "b", "c"), n, TRUE)); v2 <- round(rnorm(n), 3); v3 <- round(rnorm(n), 3)
  eta <- 0.2 + 0.4 * (f == "b") - 0.3 * (f == "c") + 0.5 * v2 - 0.3 * v3
  y <- switch(link + 1, eta + rnorm(n), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)), rbinom(n, 1, pnorm(eta)), NA, NA, rpois(n, (0.8 + 0.15 * v2)^2 * 3))
  d <- data.frame(y = y, f = f, v2 = v2, v3 = v3)
  fam <- list(gaussian(), binomial(), poisson(), binomial(link = "probit"), NA, NA, poisson(link = "sqrt"))[[link + 1]]
  m <- tryCatch(suppressWarnings(glm(y ~ f + v2 + v3, fam, d)), error = function(e) NULL)
  if (is.null(m) || !m$converged) next
  Xm <- model.matrix(m); b <- unname(coef(m)); V <- unname(vcov(m)); p <- length(b)
  big <- 1e300
  lev <- function(L) { v <- rep(big, p); v[2] <- as.numeric(L == "b"); v[3] <- as.numeric(L == "c"); v }
  cnt <- function(col, val) { v <- rep(big, p); v[col] <- val; v }
  push <- function(r, hi, lo, kd) for (w in 0:1) { v <- if (w == 0) r$estimate else r$std.error; if (is.finite(v)) cases[[length(cases) + 1]] <<- case("mcon", c(n, p, link, kd, w, hi, lo, b, V, Xm), v, rel = 1e-9, abs = 1e-10) }
  for (kd in 0:3) {
    cp <- c("differenceavg", "ratioavg", "lnratioavg", "liftavg")[kd + 1]
    r <- tryCatch(as.data.frame(avg_comparisons(m, variables = list(f = "pairwise"), comparison = cp)), error = function(e) NULL)
    if (is.null(r) || nrow(r) != 3) next
    if (kd == 0) prs <- lapply(1:3, function(i) regmatches(r$contrast[i], gregexpr("[abc]", r$contrast[i]))[[1]])
    for (i in 1:3) push(r[i, ], lev(prs[[i]][1]), lev(prs[[i]][2]), kd)
  }
  s <- sd(v2); mu <- mean(v2)
  for (sp in list(list("iqr", quantile(v2, 0.25), quantile(v2, 0.75)), list("minmax", min(v2), max(v2)), list("sd", mu - s / 2, mu + s / 2), list(c(-0.5, 1.5), -0.5, 1.5))) {
    r <- tryCatch(as.data.frame(avg_comparisons(m, variables = list(v2 = sp[[1]]))), error = function(e) NULL)
    if (is.null(r) || nrow(r) != 1) next
    push(r[1, ], cnt(4, as.numeric(sp[[3]])), cnt(4, as.numeric(sp[[2]])), 0)
  }
}
# predicted-margin tables: "mtabg" = ggeffects predict_response (columns predicted, std.error (link scale), conf.low, conf.high), "mtabe" = effects Effect (fit, se (response scale), lower, upper);
# args (p, link, df (0: normal quantile), level, which 0 estimate 1 link se 2 response se 3 lower 4 upper, beta[p], vcov[p p], x[p])
suppressMessages({library(ggeffects); library(effects)})
set.seed(20262500)
for (rep in 1:8) {
  link <- c(0, 1, 2, 3)[rep %% 4 + 1]; n <- sample(70:120, 1); lvl <- c(0.95, 0.9)[rep %% 2 + 1]
  v1 <- round(rnorm(n), 3); v2 <- round(rnorm(n), 3); f <- factor(sample(c("a", "b", "c"), n, TRUE))
  eta <- 0.2 + 0.5 * v1 - 0.3 * v2 + 0.4 * (f == "b") - 0.3 * (f == "c")
  y <- switch(link + 1, eta + rnorm(n), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)), rbinom(n, 1, pnorm(eta)))
  d <- data.frame(y = y, v1 = v1, v2 = v2, f = f)
  fam <- list(gaussian(), binomial(), poisson(), binomial(link = "probit"))[[link + 1]]
  m <- suppressWarnings(glm(y ~ v1 + v2 + f, fam, d))
  X <- model.matrix(m); b <- unname(coef(m)); V <- unname(vcov(m)); p <- length(b); df <- if (link == 0) df.residual(m) else 0
  gl <- c(-1, 0.5, 1.5); fl <- c("a", "b", "c")
  rowv <- function(base, term, val) { x <- base; if (term == "v1") x[2] <- val else { x[4] <- as.numeric(val == "b"); x[5] <- as.numeric(val == "c") }; x }
  for (term in c("v1", "f")) {
    vals <- if (term == "v1") gl else fl
    g <- as.data.frame(ggpredict(m, terms = if (term == "v1") "v1[-1,0.5,1.5]" else "f", ci_level = lvl))
    e <- as.data.frame(Effect(term, m, xlevels = if (term == "v1") list(v1 = gl) else list(f = fl), confidence.level = lvl))
    for (i in seq_along(vals)) {
      xg <- rowv(c(1, mean(v1), mean(v2), 0, 0), term, vals[i]); xe <- rowv(colMeans(X), term, vals[i])
      gv <- c(g$predicted[i], g$std.error[i], NA, g$conf.low[i], g$conf.high[i]); ev <- c(e$fit[i], NA, e$se[i], e$lower[i], e$upper[i])
      for (w in 0:4) {
        if (!is.na(gv[w + 1])) cases[[length(cases) + 1]] <- case("mtab", c(p, link, df, lvl, w, b, V, xg), gv[w + 1], rel = 1e-9, abs = 1e-10)
        if (!is.na(ev[w + 1])) cases[[length(cases) + 1]] <- case("mtab", c(p, link, df, lvl, w, b, V, xe), ev[w + 1], rel = 1e-9, abs = 1e-10)
      }
    }
  }
}
emit("margeff", "marginaleffects", list(cases))
