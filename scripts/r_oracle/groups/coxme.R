# coxme::coxme, mixed-effects Cox models (the default coxmeFull variance functions), right-censored data. Helpers: ../coxme_lib.R.
#   fn "coxme", args: q, n, p, efron, hasstrata, hasoffset, hasweights, nterm,
#                     time[n], status[n], strata[n] 0-based (if hasstrata), offset[n] (if hasoffset), weights[n] (if hasweights), X[n*p] column-major,
#                     then per random term: intercept (1 or 0), ng, nvar, codes[ng*n] (column k the 0-based level codes of the k-th expanded nesting factor,
#                     outermost first), z[n*nvar].
#   q = kind * 100000 + i:  0 fixef[i], 1 frail[i] (coefficient order: every intercept block, then every slope block), 2 vcoef[i]
#       (variance per group, innermost group first; a slope term: intercept variance, correlation, slope variance),
#       3 var[r, s] with i = r * 100 + s (the random coefficients first, then the fixed ones), 4 scalar i: loglik NULL / Integrated /
#       Penalized, penalty, df integrated, df penalized, iterations (function evaluations, then inner Newton iterations),
#       5 summary rows 10 * k + (chisq, p, AIC, BIC), k 0 integrated and 1 penalized, 6 fixed coefficient k: 10 * k + (se, z, p).
source(file.path(root, "scripts", "r_oracle", "coxme_lib.R"), local = TRUE)

g1 <- function(seed) {
  set.seed(seed)
  n <- 90; g <- sample(1:12, n, TRUE); x <- round(rnorm(n), 2); b <- rnorm(12, 0, 0.6)
  tm <- rtime(n, 0.5 * x + b[g]); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, g = factor(g))
  list(tm = tm, st = st, X = cbind(x), efron = TRUE, w0 = rep(1, n), terms = list(list(icpt = TRUE, codes = lev1(g), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x + (1 | g), data = d, weights = wp))
}
add_spec(g1, 11, summ = TRUE)

# two covariates, Breslow ties, heavy ties
g2 <- function(seed) {
  set.seed(seed)
  n <- 80; g <- sample(1:10, n, TRUE); x1 <- round(rnorm(n), 1); x2 <- rbinom(n, 1, 0.5); b <- rnorm(10, 0, 0.5)
  tm <- ceiling(rexp(n, exp(0.4 * x1 - 0.5 * x2 + b[g])) * 3); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x1, x2, g = factor(g))
  list(tm = tm, st = st, X = cbind(x1, x2), efron = FALSE, w0 = rep(1, n), terms = list(list(icpt = TRUE, codes = lev1(g), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x1 + x2 + (1 | g), data = d, weights = wp, ties = "breslow"))
}
add_spec(g2, 12, summ = TRUE)

# strata, an offset and case weights
g3 <- function(seed) {
  set.seed(seed)
  n <- 90; g <- sample(1:9, n, TRUE); x <- round(rnorm(n), 2); s <- sample(1:2, n, TRUE); off <- round(rnorm(n, 0, 0.2), 2); w <- sample(c(1, 2, 3), n, TRUE) / 2
  b <- rnorm(9, 0, 0.5)
  tm <- rtime(n, 0.5 * x + b[g] + off); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, g = factor(g), s = s, off = off)
  list(tm = tm, st = st, X = cbind(x), strata = s - 1, offset = off, weights = w, efron = TRUE, w0 = w,
       terms = list(list(icpt = TRUE, codes = lev1(g), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x + strata(s) + offset(off) + (1 | g), data = d, weights = wp))
}
add_spec(g3, 13)

# nested random intercepts (1 | g1/g2)
g4 <- function(seed) {
  set.seed(seed)
  n <- 120; g1 <- sample(1:5, n, TRUE); g2 <- sample(1:3, n, TRUE); x <- round(rnorm(n), 2)
  b1 <- rnorm(5, 0, 0.5); b2 <- matrix(rnorm(15, 0, 0.4), 5)
  tm <- rtime(n, 0.4 * x + b1[g1] + b2[cbind(g1, g2)]); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, g1 = factor(g1), g2 = factor(g2))
  en <- expand(data.frame(g1 = d$g1, g2 = d$g2))
  list(tm = tm, st = st, X = cbind(x), efron = TRUE, w0 = rep(1, n),
       terms = list(list(icpt = TRUE, codes = cbind(as.integer(en[[1]]) - 1L, as.integer(en[[2]]) - 1L), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x + (1 | g1/g2), data = d, weights = wp))
}
add_spec(g4, 14, summ = TRUE)

# crossed random intercepts (1 | a) + (1 | b)
g5 <- function(seed) {
  set.seed(seed)
  n <- 100; ga <- sample(1:8, n, TRUE); gb <- sample(1:5, n, TRUE); x <- round(rnorm(n), 2)
  ba <- rnorm(8, 0, 0.5); bb <- rnorm(5, 0, 0.4)
  tm <- rtime(n, 0.4 * x + ba[ga] + bb[gb]); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, ga = factor(ga), gb = factor(gb))
  list(tm = tm, st = st, X = cbind(x), efron = TRUE, w0 = rep(1, n),
       terms = list(list(icpt = TRUE, codes = lev1(ga), nvar = 0), list(icpt = TRUE, codes = lev1(gb), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x + (1 | ga) + (1 | gb), data = d, weights = wp))
}
add_spec(g5, 15, summ = TRUE)

emit("coxme", c("coxme", "survival", "bdsmatrix"), list(cases))
