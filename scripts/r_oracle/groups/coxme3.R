# coxme::coxme, the third group: deeper nesting, sparse nested and crossed terms, several terms with slopes. Case layout and helpers as in coxme.R.
source(file.path(root, "scripts", "r_oracle", "coxme_lib.R"), local = TRUE)

# three nesting levels (1 | g1/g2/g3)
h1 <- function(seed) {
  set.seed(seed)
  n <- 150; g1 <- sample(1:3, n, TRUE); g2 <- sample(1:3, n, TRUE); g3 <- sample(1:2, n, TRUE); x <- round(rnorm(n), 2)
  tm <- rtime(n, 0.4 * x + rnorm(3, 0, 0.4)[g1] + rnorm(18, 0, 0.3)[g1 * 6 - 6 + g2 * 2 - 2 + g3]); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, g1 = factor(g1), g2 = factor(g2), g3 = factor(g3))
  en <- expand(data.frame(g1 = d$g1, g2 = d$g2, g3 = d$g3))
  list(tm = tm, st = st, X = cbind(x), efron = TRUE, w0 = rep(1, n),
       terms = list(list(icpt = TRUE, codes = sapply(1:3, function(k) as.integer(en[[k]]) - 1L), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x + (1 | g1/g2/g3), data = d, weights = wp))
}
add_spec(h1, 21, light = TRUE, summ = TRUE)

# a nested term whose innermost factor is sparse (64 combinations of 8 by 8, most under 2% of the rows)
h2 <- function(seed) {
  set.seed(seed)
  n <- 320; g1 <- sample(1:8, n, TRUE); g2 <- sample(1:8, n, TRUE); x <- round(rnorm(n), 2)
  tm <- rtime(n, 0.4 * x + rnorm(8, 0, 0.5)[g1] + matrix(rnorm(64, 0, 0.4), 8)[cbind(g1, g2)]); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, g1 = factor(g1), g2 = factor(g2))
  en <- expand(data.frame(g1 = d$g1, g2 = d$g2))
  list(tm = tm, st = st, X = cbind(x), efron = TRUE, w0 = rep(1, n),
       terms = list(list(icpt = TRUE, codes = sapply(1:2, function(k) as.integer(en[[k]]) - 1L), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x + (1 | g1/g2), data = d, weights = wp))
}
add_spec(h2, 22, need_counts = FALSE, count_rel = 0.5, light = TRUE)

# crossed terms where the second has 55 levels that qualify as sparse: only the first term decides the block structure, the second is reordered
h3 <- function(seed) {
  set.seed(seed)
  gb <- rep(1:55, c(rep(5, 45), rep(10, 10))); n <- length(gb); ga <- sample(1:6, n, TRUE); x <- round(rnorm(n), 2)
  tm <- rtime(n, 0.4 * x + rnorm(6, 0, 0.5)[ga] + rnorm(55, 0, 0.4)[gb]); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, ga = factor(ga), gb = factor(gb))
  list(tm = tm, st = st, X = cbind(x), efron = TRUE, w0 = rep(1, n),
       terms = list(list(icpt = TRUE, codes = lev1(ga), nvar = 0), list(icpt = TRUE, codes = lev1(gb), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x + (1 | ga) + (1 | gb), data = d, weights = wp))
}
add_spec(h3, 23, need_counts = FALSE, count_rel = 0.5, light = TRUE)

# the sparse term first, a dense one after it
h4 <- function(seed) {
  set.seed(seed)
  ga <- rep(1:52, c(rep(3, 42), rep(12, 10))); n <- length(ga); gb <- sample(1:5, n, TRUE); x <- round(rnorm(n), 2)
  tm <- rtime(n, 0.4 * x + rnorm(52, 0, 0.5)[ga] + rnorm(5, 0, 0.4)[gb]); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, ga = factor(ga), gb = factor(gb))
  list(tm = tm, st = st, X = cbind(x), efron = TRUE, w0 = rep(1, n),
       terms = list(list(icpt = TRUE, codes = lev1(ga), nvar = 0), list(icpt = TRUE, codes = lev1(gb), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x + (1 | ga) + (1 | gb), data = d, weights = wp))
}
add_spec(h4, 24, need_counts = FALSE, count_rel = 0.5, light = TRUE)

# a slope term and an intercept term
h5 <- function(seed) {
  set.seed(seed)
  n <- 130; g <- sample(1:8, n, TRUE); h <- sample(1:6, n, TRUE); x <- round(rnorm(n), 2); z <- round(rnorm(n), 2)
  tm <- rtime(n, 0.4 * x + rnorm(8, 0, 0.4)[g] + rnorm(8, 0, 0.3)[g] * z + rnorm(6, 0, 0.4)[h]); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, z, g = factor(g), h = factor(h))
  list(tm = tm, st = st, X = cbind(x), efron = TRUE, w0 = rep(1, n),
       terms = list(list(icpt = TRUE, codes = lev1(g), nvar = 1, z = cbind(z)), list(icpt = TRUE, codes = lev1(h), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x + (1 + z | g) + (1 | h), data = d, weights = wp))
}
add_spec(h5, 25, light = TRUE)

# an intercept and an uncorrelated slope over the same groups, (1 | g) + (0 + z | g)
h6 <- function(seed) {
  set.seed(seed)
  n <- 110; g <- sample(1:9, n, TRUE); x <- round(rnorm(n), 2); z <- round(rnorm(n), 2)
  tm <- rtime(n, 0.4 * x + rnorm(9, 0, 0.5)[g] + rnorm(9, 0, 0.4)[g] * z); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x, z, g = factor(g))
  list(tm = tm, st = st, X = cbind(x), efron = TRUE, w0 = rep(1, n),
       terms = list(list(icpt = TRUE, codes = lev1(g), nvar = 0), list(icpt = FALSE, codes = lev1(g), nvar = 1, z = cbind(z))),
       mk = function(wp) fit(Surv(tm, st) ~ x + (1 | g) + (0 + z | g), data = d, weights = wp))
}
add_spec(h6, 26, light = TRUE)

# Breslow ties with nested terms and a stratum
h7 <- function(seed) {
  set.seed(seed)
  n <- 140; g1 <- sample(1:4, n, TRUE); g2 <- sample(1:3, n, TRUE); x <- round(rnorm(n), 2); s <- sample(1:3, n, TRUE)
  tm <- ceiling(rexp(n, exp(0.4 * x + rnorm(4, 0, 0.5)[g1] + matrix(rnorm(12, 0, 0.4), 4)[cbind(g1, g2)])) * 4); st <- rbinom(n, 1, 0.75)
  d <- data.frame(tm, st, x, s, g1 = factor(g1), g2 = factor(g2))
  en <- expand(data.frame(g1 = d$g1, g2 = d$g2))
  list(tm = tm, st = st, X = cbind(x), strata = s - 1, efron = FALSE, w0 = rep(1, n),
       terms = list(list(icpt = TRUE, codes = sapply(1:2, function(k) as.integer(en[[k]]) - 1L), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x + strata(s) + (1 | g1/g2), data = d, weights = wp, ties = "breslow"))
}
add_spec(h7, 27, light = TRUE)

# a large variance and heavy Efron ties
h8 <- function(seed) {
  set.seed(seed)
  n <- 100; g <- sample(1:10, n, TRUE); x1 <- round(rnorm(n), 1); x2 <- round(runif(n), 1)
  tm <- ceiling(rexp(n, exp(0.3 * x1 - 0.4 * x2 + rnorm(10, 0, 1.3)[g])) * 4); st <- rbinom(n, 1, 0.8)
  d <- data.frame(tm, st, x1, x2, g = factor(g))
  list(tm = tm, st = st, X = cbind(x1, x2), efron = TRUE, w0 = rep(1, n), terms = list(list(icpt = TRUE, codes = lev1(g), nvar = 0)),
       mk = function(wp) fit(Surv(tm, st) ~ x1 + x2 + (1 | g), data = d, weights = wp))
}
add_spec(h8, 28, light = TRUE, summ = TRUE)

emit("coxme3", c("coxme", "survival", "bdsmatrix"), list(cases))
