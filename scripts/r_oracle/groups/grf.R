# grf 2.6.1: regression forests grown under an explicit integer seed (and under set.seed, where the C++ seed is runif(1, 0, .Machine$integer.max)).
#   fn "runif_seed": args = (seed); want = set.seed(seed); runif(1, 0, .Machine$integer.max)
#   fn "grf": args = (sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha, imbalance.penalty,
#                     seed, nnew, hasw, max.depth, decay, 0, 0, y[n], w[n or 0], X (row-major n by p), Xnew (row-major nnew by p))
#   sel: 0 oob predictions, 1 oob debiased.error, 2 oob excess.error, 3 test predictions, 4 test variance.estimates, 5 oob variance.estimates,
#        6 variable_importance. Vectors are position-weighted checksums (sum of (i + 1) * value, NA skipped).
suppressMessages(library(grf))
cases <- list()
cs <- function(v) { v <- as.numeric(v); ok <- !is.na(v); sum((seq_along(v) * v)[ok]) }
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)

set.seed(517)
for (s in c(1, 7, 123, 2026, 99999)) {
  set.seed(s)
  add("runif_seed", s, runif(1, 0, .Machine$integer.max), rel = 0, abs = 0)
}

emit_grf <- function(n, p, num.trees = 60, mtry = NULL, min.node.size = 5, sample.fraction = 0.5, honesty = TRUE, honesty.fraction = 0.5, honesty.prune.leaves = TRUE,
                     ci.group.size = 2, alpha = 0.05, imbalance.penalty = 0, weights = FALSE, nnew = 8, max.depth = 4, decay = 2, noise = 1) {
  X <- matrix(round(rnorm(n * p), 3), n, p)
  if (p >= 2) X[, 2] <- sample(1:4, n, replace = TRUE)
  Y <- round(2 * X[, 1] + (X[, 2] > 2) * 3 + rnorm(n, sd = noise), 3)
  Xnew <- matrix(round(rnorm(nnew * p), 3), nnew, p)
  w <- if (weights) round(runif(n, 0.5, 2), 3) else NULL
  if (is.null(mtry)) mtry <- min(ceiling(sqrt(p) + 20), p)
  seed <- sample(1:1000000, 1)
  f <- regression_forest(X, Y, num.trees = num.trees, mtry = mtry, min.node.size = min.node.size, sample.fraction = sample.fraction, honesty = honesty,
                         honesty.fraction = honesty.fraction, honesty.prune.leaves = honesty.prune.leaves, ci.group.size = ci.group.size, alpha = alpha,
                         imbalance.penalty = imbalance.penalty, sample.weights = w, seed = seed, num.threads = 1)
  oob <- predict(f)
  pt <- predict(f, Xnew, estimate.variance = ci.group.size > 1)
  head <- function(sel) c(sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha,
                          imbalance.penalty, seed, nnew, weights, max.depth, decay, 0, 0)
  a <- function(sel) c(head(sel), Y, if (weights) w else numeric(0), as.vector(t(X)), as.vector(t(Xnew)))
  add("grf", a(0), cs(oob$predictions)); add("grf", a(1), cs(oob$debiased.error)); add("grf", a(2), cs(oob$excess.error))
  add("grf", a(3), cs(pt$predictions))
  if (ci.group.size > 1) {
    add("grf", a(4), cs(pt$variance.estimates))
    ov <- predict(f, estimate.variance = TRUE)
    add("grf", a(5), cs(ov$variance.estimates))
  }
  add("grf", a(6), cs(variable_importance(f, decay.exponent = decay, max.depth = max.depth)))
}

set.seed(5170)
emit_grf(60, 3)
emit_grf(60, 4, num.trees = 100, min.node.size = 3)
emit_grf(55, 5, num.trees = 80, honesty = FALSE)
emit_grf(65, 4, num.trees = 60, honesty.fraction = 0.7, honesty.prune.leaves = FALSE)
emit_grf(60, 3, num.trees = 40, ci.group.size = 4, sample.fraction = 0.4)
emit_grf(55, 6, num.trees = 60, mtry = 2, alpha = 0.1, imbalance.penalty = 0.5)
emit_grf(60, 4, num.trees = 60, weights = TRUE)
emit_grf(70, 10, num.trees = 40, mtry = 10, max.depth = 3, decay = 1.5)
emit_grf(60, 3, num.trees = 30, ci.group.size = 1)
#   fn "grf_causal" / "grf_iv": args = (sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha,
#                     imbalance.penalty, seed, nnew, hasw, max.depth, decay, stabilize.splits, reduced.form.weight, 0, 0, 0, 0, Y[n], W[n], (Z[n] for iv), (w[n]), X, Xnew)
#   sel 0..8 as above for the effect forest; 9 Y.hat, 10 W.hat, 13 Z.hat (checksums); 11 average_treatment_effect estimate, 12 its std.err
emit_cf <- function(n, p, iv = FALSE, num.trees = 80, mtry = NULL, min.node.size = 5, sample.fraction = 0.5, honesty = TRUE, honesty.fraction = 0.5,
                    honesty.prune.leaves = TRUE, ci.group.size = 2, alpha = 0.05, imbalance.penalty = 0, stabilize.splits = TRUE, rfw = 0, weights = FALSE,
                    nnew = 6, max.depth = 4, decay = 2, ate = TRUE) {
  X <- matrix(round(rnorm(n * p), 3), n, p)
  if (iv) {
    Z <- rbinom(n, 1, 0.5)
    W <- rbinom(n, 1, 0.2 + 0.6 * Z)
  } else {
    W <- rbinom(n, 1, 0.5)
  }
  Y <- round(pmax(X[, 1], 0) * W + X[, 2] + rnorm(n), 3)
  Xnew <- matrix(round(rnorm(nnew * p), 3), nnew, p)
  w <- if (weights) round(runif(n, 0.5, 2), 3) else NULL
  if (is.null(mtry)) mtry <- min(ceiling(sqrt(p) + 20), p)
  seed <- sample(1:1000000, 1)
  common <- list(num.trees = num.trees, mtry = mtry, min.node.size = min.node.size, sample.fraction = sample.fraction, honesty = honesty,
                 honesty.fraction = honesty.fraction, honesty.prune.leaves = honesty.prune.leaves, ci.group.size = ci.group.size, alpha = alpha,
                 imbalance.penalty = imbalance.penalty, stabilize.splits = stabilize.splits, sample.weights = w, seed = seed, num.threads = 1)
  f <- if (iv) do.call(instrumental_forest, c(list(X = X, Y = Y, W = W, Z = Z, reduced.form.weight = rfw), common))
       else do.call(causal_forest, c(list(X = X, Y = Y, W = W), common))
  oob <- predict(f)
  pt <- predict(f, Xnew, estimate.variance = ci.group.size > 1)
  nm <- if (iv) "grf_iv" else "grf_causal"
  head <- function(sel) c(sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha,
                          imbalance.penalty, seed, nnew, weights, max.depth, decay, stabilize.splits, rfw, 0, 0, 0, 0)
  a <- function(sel) c(head(sel), Y, W, if (iv) Z else numeric(0), if (weights) w else numeric(0), as.vector(t(X)), as.vector(t(Xnew)))
  add(nm, a(0), cs(oob$predictions)); add(nm, a(1), cs(oob$debiased.error)); if (!iv) add(nm, a(2), cs(oob$excess.error))
  add(nm, a(3), cs(pt$predictions))
  if (ci.group.size > 1) {
    add(nm, a(4), cs(pt$variance.estimates))
    add(nm, a(5), cs(predict(f, estimate.variance = TRUE)$variance.estimates))
  }
  add(nm, a(6), cs(variable_importance(f, decay.exponent = decay, max.depth = max.depth)))
  add(nm, a(9), cs(f$Y.hat)); add(nm, a(10), cs(f$W.hat))
  if (iv) add(nm, a(13), cs(f$Z.hat))
  if (ate) {
    r <- suppressWarnings(average_treatment_effect(f))
    add(nm, a(11), r[["estimate"]]); add(nm, a(12), r[["std.err"]])
  }
}

set.seed(5171)
emit_cf(60, 3)
emit_cf(70, 4, num.trees = 100, min.node.size = 3)
emit_cf(65, 5, honesty = FALSE)
emit_cf(65, 4, honesty.fraction = 0.7, honesty.prune.leaves = FALSE, stabilize.splits = FALSE)
emit_cf(60, 3, ci.group.size = 4, sample.fraction = 0.4, num.trees = 120)
emit_cf(60, 6, mtry = 2, alpha = 0.1, imbalance.penalty = 0.5)
emit_cf(60, 4, weights = TRUE)
emit_cf(65, 3, iv = TRUE)
emit_cf(70, 4, iv = TRUE, rfw = 0.3, num.trees = 100)
emit_cf(65, 3, iv = TRUE, stabilize.splits = FALSE, weights = TRUE)
emit_cf(60, 3, ci.group.size = 1, num.trees = 60)

#   fn "grf_quantile": args = (sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, alpha, imbalance.penalty, seed, nnew,
#                     regression.splitting, nq, 0 x 8, quantiles[nq], Y[n], X, Xnew); sel 0 oob quantiles, 1 test quantiles (matrix, column-major checksums), 2 the first oob row summed
emit_q <- function(n, p, qs = c(0.1, 0.5, 0.9), num.trees = 60, mtry = NULL, min.node.size = 5, sample.fraction = 0.5, honesty = TRUE, honesty.fraction = 0.5,
                   honesty.prune.leaves = TRUE, alpha = 0.05, imbalance.penalty = 0, regression.splitting = FALSE, nnew = 8) {
  X <- matrix(round(rnorm(n * p), 3), n, p)
  Y <- round(X[, 1] + (X[, 2] > 0) * rnorm(n, sd = 2) + rnorm(n), 3)
  Xnew <- matrix(round(rnorm(nnew * p), 3), nnew, p)
  if (is.null(mtry)) mtry <- min(ceiling(sqrt(p) + 20), p)
  seed <- sample(1:1000000, 1)
  f <- quantile_forest(X, Y, num.trees = num.trees, quantiles = qs, regression.splitting = regression.splitting, sample.fraction = sample.fraction, mtry = mtry,
                       min.node.size = min.node.size, honesty = honesty, honesty.fraction = honesty.fraction, honesty.prune.leaves = honesty.prune.leaves,
                       alpha = alpha, imbalance.penalty = imbalance.penalty, seed = seed, num.threads = 1)
  oob <- predict(f)$predictions
  pt <- predict(f, Xnew)$predictions
  a <- function(sel) c(sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, alpha, imbalance.penalty, seed, nnew,
                       regression.splitting, length(qs), rep(0, 8), qs, Y, as.vector(t(X)), as.vector(t(Xnew)))
  add("grf_quantile", a(0), cs(as.vector(oob))); add("grf_quantile", a(1), cs(as.vector(pt)))
  add("grf_quantile", a(2), sum(oob[1, ]))
}

set.seed(5172)
emit_q(100, 3)
emit_q(120, 4, qs = c(0.25, 0.75), num.trees = 80)
emit_q(90, 5, honesty = FALSE, qs = c(0.05, 0.5, 0.95, 0.99))
emit_q(100, 4, honesty.fraction = 0.7, honesty.prune.leaves = FALSE)
emit_q(110, 3, regression.splitting = TRUE)
emit_q(100, 6, mtry = 2, alpha = 0.1, imbalance.penalty = 0.5, sample.fraction = 0.6)
emit_q(80, 3, qs = c(0.5), min.node.size = 2)

#   fn "grf_ll": local linear forests. args = (sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha,
#                     imbalance.penalty, seed, nnew, enable.ll.split, ll.split.lambda, ll.split.weight.penalty, ll.split.cutoff, ll.lambda (negative: tuned over the default path),
#                     ll.weight.penalty, nlc, 0, 0, lcv[nlc] (1-based), Y[n], X, Xnew); sel 0 oob predictions, 1 oob variance, 2 test predictions, 3 test variance, 4 the lambda used
emit_ll <- function(n, p, num.trees = 60, mtry = NULL, min.node.size = 5, sample.fraction = 0.5, honesty = TRUE, honesty.fraction = 0.5, honesty.prune.leaves = TRUE,
                    ci.group.size = 2, alpha = 0.05, imbalance.penalty = 0, enable.ll.split = FALSE, ll.split.lambda = 0.1, ll.split.weight.penalty = FALSE,
                    ll.lambda = 0.1, ll.weight.penalty = FALSE, lcv = NULL, nnew = 8, tuned = FALSE, cutoff = floor(sqrt(n))) {
  X <- matrix(round(rnorm(n * p), 3), n, p)
  Y <- round(2 * X[, 1] + sin(X[, 2]) + X[, 3]^2 / 2 + rnorm(n, sd = 0.5), 3)
  Xnew <- matrix(round(rnorm(nnew * p), 3), nnew, p)
  if (is.null(mtry)) mtry <- min(ceiling(sqrt(p) + 20), p)
  if (is.null(lcv)) lcv <- 1:p
  seed <- sample(1:1000000, 1)
  f <- ll_regression_forest(X, Y, enable.ll.split = enable.ll.split, ll.split.weight.penalty = ll.split.weight.penalty, ll.split.lambda = ll.split.lambda,
                            ll.split.cutoff = cutoff, num.trees = num.trees, sample.fraction = sample.fraction, mtry = mtry, min.node.size = min.node.size,
                            honesty = honesty, honesty.fraction = honesty.fraction, honesty.prune.leaves = honesty.prune.leaves, alpha = alpha,
                            imbalance.penalty = imbalance.penalty, ci.group.size = ci.group.size, seed = seed, num.threads = 1)
  ll <- if (tuned) NULL else ll.lambda
  oob <- predict(f, linear.correction.variables = lcv, ll.lambda = ll, ll.weight.penalty = ll.weight.penalty, estimate.variance = TRUE)
  pt <- predict(f, Xnew, linear.correction.variables = lcv, ll.lambda = ll, ll.weight.penalty = ll.weight.penalty, estimate.variance = TRUE)
  a <- function(sel) c(sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha, imbalance.penalty,
                       seed, nnew, enable.ll.split, ll.split.lambda, ll.split.weight.penalty, cutoff, if (tuned) -1 else ll.lambda, ll.weight.penalty, length(lcv), 0, 0,
                       lcv, Y, as.vector(t(X)), as.vector(t(Xnew)))
  add("grf_ll", a(0), cs(oob$predictions)); add("grf_ll", a(1), cs(oob$variance.estimates))
  add("grf_ll", a(2), cs(pt$predictions)); add("grf_ll", a(3), cs(pt$variance.estimates))
  add("grf_ll", a(4), oob$ll.lambda[1], rel = 0, abs = 0)
}

set.seed(5173)
emit_ll(100, 3)
emit_ll(120, 4, num.trees = 80, ll.lambda = 0.5, lcv = c(1, 3))
emit_ll(100, 3, tuned = TRUE)
emit_ll(90, 5, honesty = FALSE, ll.lambda = 0.01)
emit_ll(100, 3, ll.weight.penalty = TRUE, ll.lambda = 0.3, ci.group.size = 4, num.trees = 80)
emit_ll(110, 3, enable.ll.split = TRUE, cutoff = 0)
emit_ll(110, 4, enable.ll.split = TRUE, ll.split.weight.penalty = FALSE, ll.split.lambda = 0.5, ll.lambda = 0.2, cutoff = 0)
emit_ll(100, 3, enable.ll.split = TRUE, ll.split.weight.penalty = TRUE, ll.split.lambda = 0.1, cutoff = 0, num.trees = 40)

#   fn "grf_surv": survival forests. args = (sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, alpha, seed, nnew, hasw,
#                     prediction.type (0 Kaplan-Meier, 1 Nelson-Aalen), 0 x 9, Y[n], D[n], (w[n]), X, Xnew); sel 0 oob survival curves, 1 test curves (row-major checksums),
#                     2 number of failure times, 3 sum of the first oob curve
emit_s <- function(n, p, num.trees = 60, mtry = NULL, min.node.size = 5, sample.fraction = 0.5, honesty = TRUE, honesty.fraction = 0.5, honesty.prune.leaves = TRUE,
                   alpha = 0.05, weights = FALSE, nelson = FALSE, nnew = 8) {
  X <- matrix(round(rnorm(n * p), 3), n, p)
  T <- rexp(n, exp(0.5 * X[, 1])); C <- rexp(n, 0.3)
  Y <- round(pmin(T, C), 2); D <- as.numeric(T <= C)
  Xnew <- matrix(round(rnorm(nnew * p), 3), nnew, p)
  w <- if (weights) round(runif(n, 0.5, 2), 3) else NULL
  if (is.null(mtry)) mtry <- min(ceiling(sqrt(p) + 20), p)
  seed <- sample(1:1000000, 1)
  f <- survival_forest(X, Y, D, num.trees = num.trees, sample.weights = w, sample.fraction = sample.fraction, mtry = mtry, min.node.size = min.node.size,
                       honesty = honesty, honesty.fraction = honesty.fraction, honesty.prune.leaves = honesty.prune.leaves, alpha = alpha,
                       prediction.type = if (nelson) "Nelson-Aalen" else "Kaplan-Meier", seed = seed, num.threads = 1)
  oob <- predict(f)$predictions
  pt <- predict(f, Xnew)$predictions
  a <- function(sel) c(sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, alpha, seed, nnew, weights, nelson, rep(0, 9),
                       Y, D, if (weights) w else numeric(0), as.vector(t(X)), as.vector(t(Xnew)))
  add("grf_surv", a(0), cs(as.vector(t(oob)))); add("grf_surv", a(1), cs(as.vector(t(pt))))
  add("grf_surv", a(2), length(f$failure.times), rel = 0, abs = 0); add("grf_surv", a(3), sum(oob[1, ]))
}

set.seed(5174)
emit_s(100, 3)
emit_s(120, 4, num.trees = 80, nelson = TRUE)
emit_s(90, 5, honesty = FALSE)
emit_s(110, 3, min.node.size = 15, honesty.fraction = 0.6)
emit_s(100, 4, weights = TRUE, nelson = TRUE)
emit_s(100, 6, mtry = 2, alpha = 0.1, honesty.prune.leaves = FALSE, sample.fraction = 0.6)

emit("grf", "grf", list(cases))
