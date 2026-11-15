# rstatix's numeric core (and the base R tests it stands on): p.adjust, games_howell_test, dunn_test,
# pairwise.t.test, oneway.test (Welch), friedman.test, kruskal_effsize, cohens_d, eta_squared,
# is_outlier and mahalanobis. One case per number; the first argument is the kind.
#   0 p.adjust:    (0, method 0 none 1 bonferroni 2 holm 3 hochberg 4 hommel 5 BH 6 BY, n, p..., i)
#   1 games_howell:(1, k, sizes..., values..., conf, group1, group2, col 0 estimate 1 low 2 high 3 se 4 statistic 5 df 6 p.adj)
#   2 dunn:        (2, method, k, sizes..., values..., group1, group2, col 0 estimate 1 statistic 2 p 3 p.adj)
#   4 welch anova: (4, k, sizes..., values..., col 0 statistic 1 df1 2 df2 3 p)
#   5 friedman:    (5, blocks, k, values row-major..., col 0 statistic 1 df 2 p)
#   7 kruskal effsize: (7, epsilon2, k, sizes..., values...)
#   8 cohens_d:    (8, mode 0 one 1 two 2 paired, var.equal, hedges, mu, n1, n2, x..., y...)
#   9 eta squared: (9, k, sizes..., values...)
#  10 outlier:     (10, coef, n, x..., i)
#  11 mahalanobis: (11, n, p, x row-major..., i, col 0 distance 1 outlier flag)
#  12 pairwise t:  (12, mode 0 pooled 1 welch 2 paired, method, k, sizes..., values..., group1, group2, col 0 p 1 p.adj)
suppressMessages({ library(rstatix); library(dplyr) })
set.seed(20261115)
cases <- list()
add <- function(args, want, rel = 1e-10, abs = 1e-14) cases[[length(cases) + 1]] <<- case("rstatix", args, want, rel = rel, abs = abs)
methods <- c("none", "bonferroni", "holm", "hochberg", "hommel", "BH", "BY")

for (n in c(1, 2, 3, 4, 5, 7, 10, 20, 40)) for (rep in 1:5) {
  p <- switch(rep, runif(n), round(runif(n), 1), runif(n)^3, rep(0.04, n), c(runif(max(n - 2, 0)), 1, 1)[seq_len(n)])
  for (m in 0:6) {
    v <- p.adjust(p, methods[m + 1])
    for (i in seq_len(n)) add(c(0, m, n, p, i - 1), v[i], 1e-12, 1e-15)
  }
}

mkgroups <- function(k, kind) {
  sizes <- sample(3:12, k, replace = TRUE)
  mu <- rnorm(k, 0, 1.5)
  sdv <- runif(k, 0.5, 3)
  x <- unlist(lapply(seq_len(k), function(g) rnorm(sizes[g], mu[g], sdv[g])))
  if (kind == "ties") x <- round(x)
  list(sizes = sizes, x = x, g = factor(rep(seq_len(k), sizes)))
}
trials <- list()
for (k in c(2, 3, 4, 5, 6)) for (kind in c("cont", "cont", "ties")) trials[[length(trials) + 1]] <- c(list(k = k), mkgroups(k, kind))

for (t in trials) {
  k <- t$k; df <- data.frame(y = t$x, g = t$g); sz <- t$sizes
  for (conf in c(0.95, 0.99)) {
    r <- suppressWarnings(games_howell_test(df, y ~ g, conf.level = conf, detailed = TRUE))
    for (row in seq_len(nrow(r))) {
      g1 <- as.numeric(r$group1[row]); g2 <- as.numeric(r$group2[row])
      vals <- as.numeric(r[row, c("estimate", "conf.low", "conf.high", "se", "statistic", "df", "p.adj")])
      for (col in 0:6) add(c(1, k, sz, t$x, conf, g1, g2, col), vals[col + 1], 1e-8, 1e-9)
    }
  }
  for (m in 0:6) {
    r <- dunn_test(df, y ~ g, p.adjust.method = methods[m + 1], detailed = TRUE)
    for (row in seq_len(nrow(r))) {
      g1 <- as.numeric(r$group1[row]); g2 <- as.numeric(r$group2[row])
      vals <- as.numeric(r[row, c("estimate", "statistic", "p", "p.adj")])
      for (col in 0:3) add(c(2, m, k, sz, t$x, g1, g2, col), vals[col + 1])
    }
  }
  w <- oneway.test(y ~ g, data = df, var.equal = FALSE)
  vals <- c(w$statistic, w$parameter[1], w$parameter[2], w$p.value)
  for (col in 0:3) add(c(4, k, sz, t$x, col), vals[col + 1])
  for (eps in 0:1) add(c(7, eps, k, sz, t$x), kruskal_effsize(df, y ~ g, method = if (eps) "epsilon2" else "eta2")$effsize)
  add(c(9, k, sz, t$x), as.numeric(eta_squared(aov(y ~ g, data = df))[1]))
  for (m in c(0, 2, 5)) for (mode in 0:1) {
    pt <- pairwise.t.test(t$x, t$g, p.adjust.method = "none", pool.sd = mode == 0)$p.value
    pa <- pairwise.t.test(t$x, t$g, p.adjust.method = methods[m + 1], pool.sd = mode == 0)$p.value
    for (g1 in 1:(k - 1)) for (g2 in (g1 + 1):k) for (col in 0:1)
      add(c(12, mode, m, k, sz, t$x, g1, g2, col), c(pt[g2 - 1, g1], pa[g2 - 1, g1])[col + 1])
  }
}

for (k in c(2, 3, 4, 5)) for (kind in c("cont", "ties")) {
  n <- sample(c(3, 6, 10), 1)
  y <- matrix(rnorm(n * k, rep(seq_len(k) * 0.5, each = n)), n, k)
  if (kind == "ties") y <- round(y)
  f <- friedman.test(y)
  vals <- c(f$statistic, f$parameter, f$p.value)
  yy <- as.vector(t(y))
  for (col in 0:2) add(c(5, n, k, yy, col), vals[col + 1])
  b <- matrix(rbinom(n * k, 1, 0.5), n, k)
  if (all(apply(b, 1, function(r) length(unique(r)) > 0))) {
    f <- friedman.test(b)
    vals <- c(f$statistic, f$parameter, f$p.value)
    for (col in 0:2) add(c(5, n, k, as.vector(t(b)), col), vals[col + 1])
  }
}

for (rep in 1:30) {
  n1 <- sample(4:15, 1); n2 <- if (rep %% 3 == 0) n1 else sample(4:15, 1)
  x <- rnorm(n1, 1, 2); y <- rnorm(n2, 0.3, 1 + runif(1))
  if (rep %% 4 == 0) { x <- round(x); y <- round(y) }
  for (mode in 0:2) {
    if (mode == 2 && n1 != n2) next
    for (ve in 0:1) for (h in 0:1) {
      if (mode == 0 && h == 1) next
      mu <- if (rep %% 5 == 0) 0.4 else 0
      if (mode == 0) { df <- data.frame(y = x, g = 1); d <- cohens_d(df, y ~ 1, mu = mu)$effsize }
      else {
        df <- data.frame(y = c(x, y), g = factor(rep(c("a", "b"), c(n1, n2))))
        d <- cohens_d(df, y ~ g, paired = mode == 2, var.equal = ve == 1, hedges.correction = h == 1, mu = mu)$effsize
      }
      add(c(8, mode, ve, h, mu, n1, if (mode == 0) 0 else n2, x, if (mode == 0) NULL else y), d)
    }
  }
}

for (rep in 1:25) {
  n <- sample(c(5, 8, 12, 25, 40), 1)
  x <- rnorm(n); if (rep %% 2 == 0) x[sample(n, 2)] <- x[sample(n, 2)] * 6
  if (rep %% 5 == 0) x <- round(x * 2)
  for (coef in c(1.5, 3)) {
    o <- rstatix:::is_outlier(x, coef)
    for (i in seq_len(n)) add(c(10, coef, n, x, i - 1), as.numeric(o[i]), 0, 0)
  }
}

for (rep in 1:12) {
  p <- sample(2:4, 1); n <- sample(c(8, 15, 30), 1)
  S <- crossprod(matrix(rnorm(p * p), p, p)) + diag(p)
  x <- matrix(rnorm(n * p), n, p) %*% chol(S)
  x[sample(n, 1), ] <- x[sample(n, 1), ] * 3
  d <- mahalanobis(x, colMeans(x), cov(x))
  thr <- qchisq(0.999, p)
  xs <- as.vector(t(x))
  for (i in seq_len(n)) { add(c(11, n, p, xs, i - 1, 0), d[i], 1e-9, 1e-12); add(c(11, n, p, xs, i - 1, 1), as.numeric(d[i] > thr), 0, 0) }
}
emit("rstatix", c("rstatix", "dplyr"), list(cases))
