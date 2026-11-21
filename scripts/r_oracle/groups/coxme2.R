# coxme::coxme, the second group: random slopes, sparse levels and larger structures. Case layout and helpers as in coxme.R.
source(file.path(root, "scripts", "r_oracle", "coxme_lib.R"), local = TRUE)

# random intercept and slope, correlated (1 + z | g)
g6 <- function(seed) {
  set.seed(seed)
  n <- 110; g <- sample(1:10, n, TRUE); x <- round(rnorm(n), 2); z <- round(rnorm(n), 2)
  bi <- rnorm(10, 0, 0.5); bs <- rnorm(10, 0, 0.3)
  tm <- rtime(n, 0.4 * x + bi[g] + bs[g] * z); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, z, g = factor(g))
  list(tm = tm, st = st, X = cbind(x), efron = TRUE, w0 = rep(1, n), terms = list(list(icpt = TRUE, codes = lev1(g), nvar = 1, z = cbind(z))),
       mk = function(wp) fit(Surv(tm, st) ~ x + (1 + z | g), data = d, weights = wp))
}
add_spec(g6, 28, summ = TRUE)

# random slope only (0 + z | g)
g7 <- function(seed) {
  set.seed(seed)
  n <- 100; g <- sample(1:8, n, TRUE); x <- round(rnorm(n), 2); z <- round(rnorm(n), 2)
  bs <- rnorm(8, 0, 0.5)
  tm <- rtime(n, 0.4 * x + bs[g] * z); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, z, g = factor(g))
  list(tm = tm, st = st, X = cbind(x), efron = TRUE, w0 = rep(1, n), terms = list(list(icpt = FALSE, codes = lev1(g), nvar = 1, z = cbind(z))),
       mk = function(wp) fit(Surv(tm, st) ~ x + (0 + z | g), data = d, weights = wp))
}
add_spec(g7, 17)

# no fixed effect, (1 | g)
g8 <- function(seed) {
  set.seed(seed)
  n <- 70; g <- sample(1:9, n, TRUE); b <- rnorm(9, 0, 0.7)
  tm <- rtime(n, b[g]); st <- rbinom(n, 1, 0.85)
  d <- data.frame(tm, st, g = factor(g))
  list(tm = tm, st = st, X = NULL, efron = TRUE, w0 = rep(1, n), terms = list(list(icpt = TRUE, codes = lev1(g), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ 1 + (1 | g), data = d, weights = wp))
}
add_spec(g8, 18)

# sparse: 50 levels, 40 of them under 2% of the rows (R keeps only the block-diagonal part of the information). The iteration counts of
# the sparse fits move with 1e-13 noise in R itself (19 or 18 function evaluations), so they are checked to 50%.
g9 <- function(ties) function(seed) {
  set.seed(seed)
  sizes <- c(rep(3, 40), rep(14, 10)); g <- rep(seq_along(sizes), sizes); n <- length(g)
  x <- round(rnorm(n), 2); b <- rnorm(length(sizes), 0, 0.6)
  tm <- rtime(n, 0.5 * x + b[g]); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, g = factor(g))
  list(tm = tm, st = st, X = cbind(x), efron = ties == "efron", w0 = rep(1, n), terms = list(list(icpt = TRUE, codes = lev1(g), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x + (1 | g), data = d, weights = wp, ties = ties))
}
add_spec(g9("efron"), 19, need_counts = FALSE, count_rel = 0.5)
add_spec(g9("breslow"), 19, need_counts = FALSE, count_rel = 0.5, light = TRUE)


emit("coxme2", c("coxme", "survival", "bdsmatrix"), list(cases))
