# grf 2.6.1: regression forests grown under an explicit integer seed (and under set.seed, where the C++ seed is runif(1, 0, .Machine$integer.max)).
#   fn "runif_seed": args = (seed); want = set.seed(seed); runif(1, 0, .Machine$integer.max)
#   fn "grf": args = (sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha, imbalance.penalty,
#                     seed, nnew, hasw, max.depth, decay, 0, 0, y[n], w[n or 0], X (row-major n by p), Xnew (row-major nnew by p))
#   sel: 0 oob predictions, 1 oob debiased.error, 2 oob excess.error, 3 test predictions, 4 test variance.estimates, 5 oob variance.estimates,
#        6 variable_importance. Vectors are position-weighted checksums (sum of (i + 1) * value, NA skipped).
suppressMessages(library(grf))
cases <- list()
cs <- function(v) { v <- as.numeric(v); ok <- !is.na(v); sum((seq_along(v) * v)[ok]) }
# A case after the first on the same arguments is written as fn "sel" with just the selector: the fixture keeps the last full run's outputs, so the
# data goes into the file once per dataset.
last_fn <- ""; last_key <- NULL
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) {
  if (fn == last_fn && identical(args[-1], last_key)) {
    cases[[length(cases) + 1]] <<- case("sel", args[1], want, rel = rel, abs = abs)
  } else {
    last_fn <<- fn; last_key <<- args[-1]
    cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
  }
}
# every element of v, as its own case at selectors base, base + 1, ...: the elementwise comparison with R (a full vector, NA skipped)
el <- function(fn, a, base, v, lim = 999) { v <- as.numeric(v)[seq_len(min(length(v), lim))]; if (length(v)) add(fn, a(base), paste(ifelse(is.na(v), "NA", sprintf("%.13g", v)), collapse = ",")) }

set.seed(517)
for (s in c(1, 7, 123, 2026, 99999)) {
  set.seed(s)
  cases[[length(cases) + 1]] <- case("runif_seed", s, runif(1, 0, .Machine$integer.max), rel = 0, abs = 0)
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
  vi <- variable_importance(f, decay.exponent = decay, max.depth = max.depth)
  add("grf", a(6), cs(vi))
  el("grf", a, 1000, oob$predictions); el("grf", a, 3000, pt$predictions); el("grf", a, 5000, oob$debiased.error); el("grf", a, 6000, oob$excess.error)
  el("grf", a, 7000, vi)
  if (ci.group.size > 1) { el("grf", a, 4000, pt$variance.estimates); el("grf", a, 2000, ov$variance.estimates) }
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
                    nnew = 6, max.depth = 4, decay = 2, ate = TRUE, nclust = 0, equalize = FALSE) {
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
  if (nclust > 0) { cl <- ceiling(runif(n)^1.5 * nclust) * 7; common$clusters <- cl; common$equalize.cluster.weights <- equalize }
  f <- if (iv) do.call(instrumental_forest, c(list(X = X, Y = Y, W = W, Z = Z, reduced.form.weight = rfw), common))
       else do.call(causal_forest, c(list(X = X, Y = Y, W = W), common))
  oob <- predict(f)
  pt <- predict(f, Xnew, estimate.variance = ci.group.size > 1)
  nm <- if (iv) "grf_iv" else "grf_causal"
  head <- function(sel) c(sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha,
                          imbalance.penalty, seed, nnew, weights, max.depth, decay, stabilize.splits, rfw, if (nclust > 0) 1 + equalize else 0, 0, 0, 0)
  a <- function(sel) c(head(sel), Y, W, if (iv) Z else numeric(0), if (weights) w else numeric(0), if (nclust > 0) cl else numeric(0), as.vector(t(X)), as.vector(t(Xnew)))
  add(nm, a(0), cs(oob$predictions)); add(nm, a(1), cs(oob$debiased.error)); if (!iv) add(nm, a(2), cs(oob$excess.error))
  add(nm, a(3), cs(pt$predictions))
  ov <- NULL
  if (ci.group.size > 1) {
    add(nm, a(4), cs(pt$variance.estimates))
    ov <- predict(f, estimate.variance = TRUE)
    add(nm, a(5), cs(ov$variance.estimates))
  }
  vi <- variable_importance(f, decay.exponent = decay, max.depth = max.depth)
  add(nm, a(6), cs(vi))
  add(nm, a(9), cs(f$Y.hat)); add(nm, a(10), cs(f$W.hat))
  if (iv) add(nm, a(13), cs(f$Z.hat))
  el(nm, a, 1000, oob$predictions); el(nm, a, 3000, pt$predictions); el(nm, a, 5000, oob$debiased.error); if (!iv) el(nm, a, 6000, oob$excess.error)
  el(nm, a, 7000, vi); el(nm, a, 8000, f$Y.hat); el(nm, a, 9000, f$W.hat); if (iv) el(nm, a, 9500, f$Z.hat)
  if (ci.group.size > 1) { el(nm, a, 4000, pt$variance.estimates); el(nm, a, 2000, ov$variance.estimates) }
  if (ate) {
    r <- suppressWarnings(average_treatment_effect(f))
    add(nm, a(11), r[["estimate"]]); add(nm, a(12), r[["std.err"]])
    if (!iv) {
      # sel 14 + 2k (estimate) and 15 + 2k (std.err): treated AIPW, control AIPW, overlap, all TMLE, treated TMLE, control TMLE
      combos <- list(c("treated", "AIPW"), c("control", "AIPW"), c("overlap", "AIPW"), c("all", "TMLE"), c("treated", "TMLE"), c("control", "TMLE"))
      for (k in seq_along(combos)) {
        if ((weights || nclust > 0) && combos[[k]][2] == "TMLE") next
        r2 <- suppressWarnings(average_treatment_effect(f, target.sample = combos[[k]][1], method = combos[[k]][2]))
        add(nm, a(14 + 2 * (k - 1)), r2[["estimate"]]); add(nm, a(15 + 2 * (k - 1)), r2[["std.err"]])
      }
    }
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
# clusters: sampling by cluster, with and without equalize.cluster.weights, and the cluster-robust average effects
set.seed(5179)
emit_cf(70, 3, nclust = 12)
emit_cf(80, 4, nclust = 10, equalize = TRUE)
emit_cf(70, 3, nclust = 14, ci.group.size = 1, num.trees = 60, honesty = FALSE)
emit_cf(75, 3, nclust = 9, weights = TRUE, num.trees = 70)
emit_cf(70, 3, iv = TRUE, nclust = 11, equalize = TRUE, num.trees = 70)

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
  el("grf_quantile", a, 1000, as.vector(oob)); el("grf_quantile", a, 3000, as.vector(pt))
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
  el("grf_ll", a, 1000, oob$predictions); el("grf_ll", a, 2000, oob$variance.estimates)
  el("grf_ll", a, 3000, pt$predictions); el("grf_ll", a, 4000, pt$variance.estimates)
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
emit_ll(100, 3, enable.ll.split = TRUE, cutoff = 5, ll.split.lambda = 0.1, num.trees = 40)
emit_ll(40, 3, enable.ll.split = TRUE, cutoff = 40, num.trees = 4, honesty = FALSE)
emit_ll(40, 3, enable.ll.split = TRUE, cutoff = 8, num.trees = 4, honesty = FALSE)

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
  el("grf_surv", a, 20000, as.vector(t(oob))); el("grf_surv", a, 3000, as.vector(t(pt)))
}

set.seed(5174)
emit_s(100, 3)
emit_s(120, 4, num.trees = 80, nelson = TRUE)
emit_s(90, 5, honesty = FALSE)
emit_s(110, 3, min.node.size = 15, honesty.fraction = 0.6)
emit_s(100, 4, weights = TRUE, nelson = TRUE)
emit_s(100, 6, mtry = 2, alpha = 0.1, honesty.prune.leaves = FALSE, sample.fraction = 0.6)

#   fn "grf_prob": args = (sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha,
#                     imbalance.penalty, seed, nnew, hasw, max.depth, decay, nclass, 0, Y class index [n], w, X, Xnew)
#   sel 0 oob predictions, 1 oob variance.estimates, 2 test predictions, 3 test variance.estimates, 4 variable_importance, 5 the first oob row summed; matrices are
#   row-major checksums
emit_prob <- function(n, p, nclass = 3, num.trees = 60, mtry = NULL, min.node.size = 5, sample.fraction = 0.5, honesty = TRUE, honesty.fraction = 0.5,
                      honesty.prune.leaves = TRUE, ci.group.size = 2, alpha = 0.05, imbalance.penalty = 0, weights = FALSE, nnew = 6, max.depth = 4, decay = 2) {
  X <- matrix(round(rnorm(n * p), 3), n, p)
  Y <- pmin(pmax(floor(nclass / 2 + X[, 1] * 1.2 + rnorm(n, sd = 0.8)), 0), nclass - 1)
  Y[1:nclass] <- 0:(nclass - 1)
  Xnew <- matrix(round(rnorm(nnew * p), 3), nnew, p)
  w <- if (weights) round(runif(n, 0.5, 2), 3) else NULL
  if (is.null(mtry)) mtry <- min(ceiling(sqrt(p) + 20), p)
  seed <- sample(1:1000000, 1)
  f <- probability_forest(X, factor(Y, levels = 0:(nclass - 1)), num.trees = num.trees, mtry = mtry, min.node.size = min.node.size, sample.fraction = sample.fraction,
                          honesty = honesty, honesty.fraction = honesty.fraction, honesty.prune.leaves = honesty.prune.leaves, ci.group.size = ci.group.size,
                          alpha = alpha, imbalance.penalty = imbalance.penalty, sample.weights = w, seed = seed, num.threads = 1)
  oob <- predict(f, estimate.variance = ci.group.size > 1)
  pt <- predict(f, Xnew, estimate.variance = ci.group.size > 1)
  head <- function(sel) c(sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha,
                          imbalance.penalty, seed, nnew, weights, max.depth, decay, nclass, 0)
  a <- function(sel) c(head(sel), Y, if (weights) w else numeric(0), as.vector(t(X)), as.vector(t(Xnew)))
  add("grf_prob", a(0), cs(as.vector(t(oob$predictions)))); add("grf_prob", a(2), cs(as.vector(t(pt$predictions))))
  add("grf_prob", a(5), sum(oob$predictions[1, ]))
  if (ci.group.size > 1) {
    add("grf_prob", a(1), cs(as.vector(t(oob$variance.estimates)))); add("grf_prob", a(3), cs(as.vector(t(pt$variance.estimates))))
  }
  vi <- variable_importance(f, decay.exponent = decay, max.depth = max.depth)
  add("grf_prob", a(4), cs(vi))
  el("grf_prob", a, 1000, as.vector(t(oob$predictions))); el("grf_prob", a, 3000, as.vector(t(pt$predictions))); el("grf_prob", a, 7000, vi)
  if (ci.group.size > 1) { el("grf_prob", a, 2000, as.vector(t(oob$variance.estimates))); el("grf_prob", a, 4000, as.vector(t(pt$variance.estimates))) }
}

set.seed(5180)
emit_prob(70, 3)
emit_prob(80, 4, nclass = 2, num.trees = 80, min.node.size = 3)
emit_prob(70, 4, nclass = 4, honesty = FALSE)
emit_prob(75, 3, honesty.fraction = 0.7, honesty.prune.leaves = FALSE, ci.group.size = 4, sample.fraction = 0.4, num.trees = 80)
emit_prob(70, 5, mtry = 2, alpha = 0.1, imbalance.penalty = 0.5)
emit_prob(70, 3, weights = TRUE, ci.group.size = 1)

#   fn "grf_boost": args as "grf" with slot 18 = boost.steps (0 for the automatic stopping rule) and slot 19 = boost.max.steps; sel 0 oob predictions, 1 the number of
#   forests, 2 the per-step mean debiased errors, 3 test predictions
emit_boost <- function(n, p, num.trees = 60, mtry = NULL, min.node.size = 5, sample.fraction = 0.5, honesty = TRUE, honesty.fraction = 0.5,
                       honesty.prune.leaves = TRUE, ci.group.size = 2, alpha = 0.05, imbalance.penalty = 0, weights = FALSE, nnew = 8, steps = 0, max.steps = 5,
                       noise = 1) {
  X <- matrix(round(rnorm(n * p), 3), n, p)
  Y <- round(2 * X[, 1] + sin(3 * X[, 2 %% p + 1]) * 2 + rnorm(n, sd = noise), 3)
  Xnew <- matrix(round(rnorm(nnew * p), 3), nnew, p)
  w <- if (weights) round(runif(n, 0.5, 2), 3) else NULL
  if (is.null(mtry)) mtry <- min(ceiling(sqrt(p) + 20), p)
  seed <- sample(1:1000000, 1)
  f <- boosted_regression_forest(X, Y, num.trees = num.trees, mtry = mtry, min.node.size = min.node.size, sample.fraction = sample.fraction, honesty = honesty,
                                 honesty.fraction = honesty.fraction, honesty.prune.leaves = honesty.prune.leaves, ci.group.size = ci.group.size, alpha = alpha,
                                 imbalance.penalty = imbalance.penalty, sample.weights = w, seed = seed, num.threads = 1,
                                 boost.steps = if (steps > 0) steps else NULL, boost.max.steps = max.steps)
  head <- function(sel) c(sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha,
                          imbalance.penalty, seed, nnew, weights, 0, 0, steps, max.steps)
  a <- function(sel) c(head(sel), Y, if (weights) w else numeric(0), as.vector(t(X)), as.vector(t(Xnew)))
  add("grf_boost", a(0), cs(f$predictions)); add("grf_boost", a(1), length(f$forests), rel = 0, abs = 0)
  tp <- predict(f, Xnew)$predictions
  add("grf_boost", a(2), cs(unlist(f$error))); add("grf_boost", a(3), cs(tp))
  el("grf_boost", a, 1000, f$predictions); el("grf_boost", a, 2000, unlist(f$error)); el("grf_boost", a, 3000, tp)
}

set.seed(5181)
emit_boost(70, 3, steps = 3)
emit_boost(80, 4, num.trees = 80, steps = 2, honesty.fraction = 0.7)
emit_boost(90, 3, max.steps = 5, noise = 0.3)
emit_boost(80, 5, max.steps = 4, weights = TRUE, noise = 0.5)
emit_boost(70, 3, steps = 4, honesty = FALSE)

#   fn "grf_multi": multi_arm_causal_forest. args = (sel, n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size,
#                     alpha, imbalance.penalty, seed, nnew, hasw, max.depth, decay, stabilize.splits, nlevels(W), nout, 0, 0, 0, Y (n by nout, row-major), W level index (n), (w), X, Xnew)
#   sel 0 oob effects (n by K by nout, the order of the R array with the sample slowest), 1 oob variance.estimates, 2 test effects, 3 test variance.estimates, 4 variable_importance,
#   5 Y.hat, 6 W.hat (checksums); 1000 oob effects, 2000 oob variances, 3000 test effects, 4000 test variances, 7000 variable_importance, 8000 Y.hat, 9000 W.hat elementwise
emit_multi <- function(n, p, nl = 3, nout = 1, num.trees = 80, mtry = NULL, min.node.size = 5, sample.fraction = 0.5, honesty = TRUE, honesty.fraction = 0.5,
                       honesty.prune.leaves = TRUE, ci.group.size = 2, alpha = 0.05, imbalance.penalty = 0, stabilize.splits = TRUE, weights = FALSE,
                       nnew = 6, max.depth = 4, decay = 2) {
  X <- matrix(round(rnorm(n * p), 3), n, p)
  lev <- sample(0:(nl - 1), n, replace = TRUE); lev[1:nl] <- 0:(nl - 1)
  W <- factor(lev, levels = 0:(nl - 1))
  Y <- sapply(seq_len(nout), function(o) round(X[, o] + rowSums(sapply(seq_len(nl - 1), function(k) k * (lev == k) * pmax(X[, 1 + o %% 2], 0))) + rnorm(n), 3))
  Y <- matrix(Y, n, nout)
  Xnew <- matrix(round(rnorm(nnew * p), 3), nnew, p)
  w <- if (weights) round(runif(n, 0.5, 2), 3) else NULL
  if (is.null(mtry)) mtry <- min(ceiling(sqrt(p) + 20), p)
  seed <- sample(1:1000000, 1)
  f <- multi_arm_causal_forest(X, if (nout == 1) as.vector(Y) else Y, W, num.trees = num.trees, mtry = mtry, min.node.size = min.node.size, sample.fraction = sample.fraction,
                               honesty = honesty, honesty.fraction = honesty.fraction, honesty.prune.leaves = honesty.prune.leaves, ci.group.size = ci.group.size,
                               alpha = alpha, imbalance.penalty = imbalance.penalty, stabilize.splits = stabilize.splits, sample.weights = w, seed = seed, num.threads = 1)
  wantv <- ci.group.size > 1 && nout == 1
  oob <- predict(f, estimate.variance = wantv)
  pt <- predict(f, Xnew, estimate.variance = wantv)
  flat <- function(arr) if (length(dim(arr)) == 3) as.vector(aperm(arr, c(2, 3, 1))) else as.vector(t(arr))
  head <- c(n, p, num.trees, mtry, min.node.size, sample.fraction, honesty, honesty.fraction, honesty.prune.leaves, ci.group.size, alpha, imbalance.penalty, seed, nnew,
            weights, max.depth, decay, stabilize.splits, nl, nout, 0, 0, 0)
  a <- function(sel) c(sel, head, as.vector(t(Y)), as.integer(W) - 1, if (weights) w else numeric(0), as.vector(t(X)), as.vector(t(Xnew)))
  vi <- variable_importance(f, decay.exponent = decay, max.depth = max.depth)
  add("grf_multi", a(0), sum(seq_along(flat(oob$predictions)) * flat(oob$predictions)))
  add("grf_multi", a(2), sum(seq_along(flat(pt$predictions)) * flat(pt$predictions)))
  add("grf_multi", a(4), cs(vi))
  add("grf_multi", a(5), cs(as.vector(t(f$Y.hat)))); add("grf_multi", a(6), cs(as.vector(t(f$W.hat))))
  el("grf_multi", a, 1000, flat(oob$predictions)); el("grf_multi", a, 3000, flat(pt$predictions)); el("grf_multi", a, 7000, vi)
  el("grf_multi", a, 8000, as.vector(t(f$Y.hat))); el("grf_multi", a, 9000, as.vector(t(f$W.hat)))
  if (wantv) {
    el("grf_multi", a, 2000, flat(oob$variance.estimates)); el("grf_multi", a, 4000, flat(pt$variance.estimates))
    add("grf_multi", a(1), sum(seq_along(flat(oob$variance.estimates)) * flat(oob$variance.estimates)))
    add("grf_multi", a(3), sum(seq_along(flat(pt$variance.estimates)) * flat(pt$variance.estimates)))
  }
}

set.seed(5190)
emit_multi(80, 3)
emit_multi(90, 4, nl = 3, num.trees = 100, ci.group.size = 4)
emit_multi(80, 3, nl = 2)
emit_multi(85, 5, nl = 4, honesty = FALSE)
# stabilize.splits = FALSE is checked with a large min.node.size only: its splitting rule has no minimum node size on the treatment, so nodes of a handful of samples tie exactly between
# isolating one sample from either side, and the winner depends on Eigen's summation order in the relabelling (an ulp), which this port does not reproduce.
emit_multi(80, 4, weights = TRUE, num.trees = 80)
emit_multi(80, 3, nout = 2)
emit_multi(75, 6, mtry = 2, alpha = 0.1, imbalance.penalty = 0.5)
emit_multi(80, 4, honesty.fraction = 0.7, honesty.prune.leaves = FALSE, nl = 3, min.node.size = 3)
emit_multi(150, 3, stabilize.splits = FALSE, min.node.size = 20, num.trees = 40)
emit_multi(200, 4, stabilize.splits = FALSE, min.node.size = 30, nl = 2, num.trees = 40, honesty = FALSE)
emit_multi(120, 3, stabilize.splits = FALSE, min.node.size = 15, nl = 3, nout = 2, num.trees = 40)

emit("grf", "grf", list(cases))
