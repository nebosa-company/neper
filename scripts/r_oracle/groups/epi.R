# Epi: twoby2 on a 2 by 2 table.
#   args: (a, b, c, d, which)   fn "m"; which 0..2 row-1 risk (est, lower, upper), 3..5 row-2 risk, 6..8 risk ratio, 9..11 odds ratio, 12..14 probability difference, 15 asymptotic p, 16 exact p
suppressMessages(library(Epi))
cases <- list()
add <- function(which, base, want) cases[[length(cases) + 1]] <<- case("m", c(base, which), want, rel = 1e-9, abs = 1e-12)
set.seed(20261230)
for (rep in 1:25) {
  a <- sample(3:150, 1); b <- sample(30:2500, 1); cc <- sample(2:120, 1); d <- sample(30:3000, 1)
  r <- twoby2(matrix(c(a, cc, b, d), 2), print = FALSE)
  base <- c(a, b, cc, d)
  tb <- r$table; me <- r$measures
  for (i in 1:3) add(i - 1, base, tb[1, 2 + i]); for (i in 1:3) add(2 + i, base, tb[2, 2 + i])
  for (i in 1:3) add(5 + i, base, me[1, i]); for (i in 1:3) add(8 + i, base, me[2, i])
  for (i in 1:3) add(11 + i, base, me[nrow(me), i])
  add(15, base, r$p.value[1]); add(16, base, r$p.value[2])
}
# ROC (test, stat): "roc" args (n, test..., stat..., kind, k, col) with kind 0 table entry (k row from 0, col 0 sens 1 spec 2 pvp 3 pvn 4 cut), 1 AUC, 2 the maximising cutpoint
for (rep in 1:15) {
  n <- sample(20:60, 1); stat <- rbinom(n, 1, 0.4); if (length(unique(stat)) < 2) next
  test <- round(rnorm(n, stat * 0.9, 1), 1)
  r <- suppressWarnings(ROC(test = test, stat = stat, plot = "none"))
  res <- r$res; nr <- nrow(res)
  for (k in sample(0:(nr - 1), min(5, nr))) for (col in 0:4) {
    v <- res[k + 1, col + 1]; if (is.nan(v) || is.infinite(v)) next
    cases[[length(cases) + 1]] <- case("roc", c(n, test, stat, 0, k, col), v, rel = 1e-9, abs = 1e-12)
  }
  cases[[length(cases) + 1]] <- case("roc", c(n, test, stat, 1, 0, 0), r$AUC, rel = 1e-9, abs = 1e-12)
  mxf <- res[which((res[, 1] + res[, 2]) == max(res[, 1] + res[, 2]))[1], 5]
  cases[[length(cases) + 1]] <- case("roc", c(n, test, stat, 2, 0, 0), mxf, rel = 1e-9, abs = 1e-12)
}
# ROC from a formula (the glm's fitted probabilities as the test): "rocf" args (n, p, y, X row-major with the intercept, kind, k, col), kind 0 table entry, 1 AUC, 2 maximising cutpoint
for (rep in 1:10) {
  n <- sample(40:120, 1); p <- sample(2:4, 1); X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 4), n, p - 1))
  y <- rbinom(n, 1, plogis(as.vector(X %*% runif(p, -1, 1)))); if (length(unique(y)) < 2) next
  dfx <- as.data.frame(X[, -1, drop = FALSE]); names(dfx) <- paste0("v", seq_len(p - 1)); dfx$y <- y
  fo <- as.formula(paste("y ~", paste(names(dfx)[-p], collapse = " + ")))
  r <- suppressWarnings(ROC(form = fo, data = dfx, plot = "none")); res <- r$res; nr <- nrow(res)
  for (k in sample(0:(nr - 1), 5)) for (col in 0:3) {
    v <- res[k + 1, col + 1]; if (is.nan(v) || is.infinite(v)) next
    cases[[length(cases) + 1]] <- case("rocf", c(n, p, y, as.vector(t(X)), 0, k, col), v, rel = 1e-9, abs = 1e-12)
  }
  cases[[length(cases) + 1]] <- case("rocf", c(n, p, y, as.vector(t(X)), 1, 0, 0), r$AUC, rel = 1e-9, abs = 1e-12)
  mxf <- res[which((res[, 1] + res[, 2]) == max(res[, 1] + res[, 2]))[1], 5]
  cases[[length(cases) + 1]] <- case("rocf", c(n, p, y, as.vector(t(X)), 2, 0, 0), mxf, rel = 1e-9, abs = 1e-12)
}
# fisher.test's conditional MLE odds ratio and exact interval: "fci" args (a, b, c, d, conf, j) with j 0 estimate, 1 lower, 2 upper
for (rep in 1:30) {
  a <- sample(1:40, 1); b <- sample(2:60, 1); cc <- sample(1:40, 1); d <- sample(2:60, 1); cf <- sample(c(0.9, 0.95, 0.99), 1)
  ft <- fisher.test(matrix(c(a, cc, b, d), 2), conf.level = cf)
  v <- c(ft$estimate, ft$conf.int)
  for (j in 0:2) cases[[length(cases) + 1]] <- case("fci", c(a, b, cc, d, cf, j), v[j + 1], rel = 1e-9, abs = 1e-12)
}
# clogistic (survival::coxph's convergence, so R itself is accurate only to about 1e-6: rel 1e-5) on matched sets of J subjects (the first is the case): "clog" args (n, J, k, x[n*J*k] set, subject, covariate row-major, index) index 0..k-1 coefficients, k..2k-1 standard errors
for (rep in 1:12) {
  n <- sample(40:120, 1); J <- sample(2:5, 1); k <- sample(1:3, 1)
  X <- array(round(rnorm(n * J * k), 3), c(n, J, k)); beta <- rnorm(k, 0, 0.7)
  # the case of each set is drawn by the model, then moved to position 0
  Xs <- X
  for (i in 1:n) {
    eta <- as.vector(matrix(X[i, , ], J, k) %*% beta); pr <- exp(eta) / sum(exp(eta)); cs <- sample(J, 1, prob = pr)
    ord <- c(cs, setdiff(1:J, cs)); Xs[i, , ] <- matrix(X[i, ord, ], J, k)
  }
  d <- data.frame(set = rep(1:n, each = J), y = rep(c(1, rep(0, J - 1)), n))
  for (m in 1:k) d[[paste0("x", m)]] <- as.vector(t(matrix(Xs[, , m], n, J)))
  fo <- as.formula(paste("y ~", paste0("x", 1:k, collapse = " + ")))
  fit <- suppressWarnings(clogistic(fo, strata = set, data = d))
  cf <- as.numeric(fit$coefficients); se <- sqrt(diag(as.matrix(fit$var)))
  for (m in 1:k) {
    cases[[length(cases) + 1]] <- case("clog", c(n, J, k, as.vector(aperm(Xs, c(3, 2, 1))), m - 1), cf[m], rel = 1e-5, abs = 1e-7)
    cases[[length(cases) + 1]] <- case("clog", c(n, J, k, as.vector(aperm(Xs, c(3, 2, 1))), k + m - 1), se[m], rel = 1e-5, abs = 1e-7)
  }
}
emit("epi", "Epi", list(cases))
