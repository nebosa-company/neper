# rpart.control (defaults, derived minbucket and minsplit, out-of-range repairs) and the awkward trees: no splits, depth 1, heavy ties, zero weights, a factor with many levels, heavy missingness.
# Layout of the cases: scripts/r_oracle/rpartfull_lib.R. A control case is (80, minsplit, minbucket, cp, maxcompete, maxsurrogate, usesurrogate, surrogatestyle, maxdepth, xval), NaN for a missing argument.
source(file.path(root, "scripts", "r_oracle", "rpartfull_lib.R"))
cases <- list()
set.seed(20266104)
nms <- c("minsplit", "minbucket", "cp", "maxcompete", "maxsurrogate", "usesurrogate", "surrogatestyle", "maxdepth", "xval")
ctlsum <- function(cs) cs$minsplit + 10 * cs$minbucket + 100 * cs$cp + 1000 * cs$maxcompete + 10000 * cs$maxsurrogate + 100000 * cs$usesurrogate +
  1e6 * cs$surrogatestyle + 1e7 * cs$maxdepth + 1e8 * cs$xval
pool <- list(minsplit = c(2, 5, 7.5, 10, 15, 22.5, 25, 30, 1), minbucket = c(1, 2, 3, 4, 7, 10), cp = c(0, 0.001, 0.01, 0.1), maxcompete = c(-2, 0, 1, 4, 8),
             maxsurrogate = c(0, 2, 5, 9), usesurrogate = c(-1, 0, 1, 2, 5), surrogatestyle = c(-1, 0, 1, 3), maxdepth = c(1, 4, 30), xval = c(-3, 0, 1, 5, 10))
for (i in 1:60) {
  have <- runif(9) < 0.45
  args <- lapply(seq_along(nms), function(j) if (have[j]) sample(pool[[j]], 1) else NULL); names(args) <- nms
  args <- args[!vapply(args, is.null, TRUE)]
  cs <- suppressWarnings(do.call(rpart.control, args))
  a <- c(80, vapply(nms, function(nm) if (is.null(args[[nm]])) NaN else args[[nm]], 1))
  cases[[length(cases) + 1]] <- case("rc", a, ctlsum(cs), rel = 1e-12)
}
cases[[length(cases) + 1]] <- case("rc", c(80, rep(NaN, 9)), ctlsum(rpart.control()), rel = 1e-12)
mkX <- function(n, p, fl = 0.3, dec = 3, maxL = 6) {
  X <- data.frame(row.names = seq_len(n))
  for (j in seq_len(p)) {
    if (runif(1) < fl) X[[paste0("x", j)]] <- rp_fac(sample.int(L <- sample(2:maxL, 1), n, replace = TRUE), L)
    else X[[paste0("x", j)]] <- round(runif(n), dec)
  }
  X
}
signal <- function(X, K = 0) { s <- rnorm(nrow(X)) * 0.6; for (j in seq_along(X)) s <- s + if (is.factor(X[[j]])) (as.integer(X[[j]]) %% 3) * 0.9 else 2 * X[[j]]; s }
newd <- function(X, nn = 20) { fx <- vapply(X, is.factor, TRUE); nd <- X[sample(nrow(X), nn, replace = TRUE), , drop = FALSE]; for (j in seq_along(X)) if (!fx[j]) nd[[j]] <- round(nd[[j]] + rnorm(nn) * 0.03, 3)
  if (ncol(X) > 1) nd[sample(nn, 4), sample(ncol(X), 1)] <- NA; nd[rowSums(is.na(nd)) < ncol(X), , drop = FALSE] }
fixna <- function(X, frac) { p <- ncol(X); for (j in sample(p, max(1, p - 1))) X[[j]][sample(nrow(X), round(nrow(X) * frac))] <- NA; for (r in which(rowSums(is.na(X)) == p)) X[r, 1] <- X[1, 1][!is.na(X[1, 1])][1]; X }
one <- function(y, X, ...) rp_cases(y, X, seed = sample(1:100000, 1), newX = newd(X), ...)
# defaults throughout (xval = 10), anova, 200 rows, 6 predictors
X <- mkX(200, 6); y <- round(signal(X), 4)
cases <- c(cases, one(y, X, prunes = c(0.02, 0.05), ctl = list()))
# no splits: a cp nothing reaches; and depth one
X <- mkX(60, 3); y <- round(signal(X), 4)
cases <- c(cases, one(y, X, ctl = list(cp = 0.9, xval = 5)), one(y, X, ctl = list(maxdepth = 1, xval = 5)), one(y, X, ctl = list(maxdepth = 2, minsplit = 4, minbucket = 2, cp = 0, xval = 6), prunes = c(0.01, 0.1)))
# heavy ties: predictors on a grid of 0.1 and a binary one
X <- mkX(150, 4, fl = 0, dec = 1); X$x4 <- rp_fac(sample.int(2, 150, replace = TRUE), 2); y <- round(signal(X), 3)
cases <- c(cases, one(y, X, ctl = list(minsplit = 8, minbucket = 3, cp = 0.002, xval = 8), prunes = 0.03))
# zero weights
X <- mkX(90, 4); y <- round(signal(X), 4); w <- round(runif(90, 0, 2), 2); w[sample(90, 20)] <- 0
cases <- c(cases, one(y, X, wt = w, ctl = list(minsplit = 8, minbucket = 3, cp = 0.005, xval = 5), prunes = 0.04))
# a factor with ten levels, class with 3 classes (gray code over subsets) and its Poisson twin
X <- mkX(130, 3, fl = 0); X$x4 <- rp_fac(sample.int(10, 130, replace = TRUE), 10); sc <- signal(X) + (as.integer(X$x4) %% 4) * 1.2
y3 <- factor(letters[as.integer(cut(sc, quantile(sc, c(0, 1/3, 2/3, 1)), include.lowest = TRUE))], levels = letters[1:3])
cases <- c(cases, one(y3, X, ctl = list(minsplit = 10, minbucket = 4, cp = 0.005, xval = 5), prunes = 0.02),
           one(y3, X, parms = list(split = "information", loss = matrix(c(0, 2, 1, 1, 0, 3, 2, 1, 0), 3, 3)), ctl = list(minsplit = 10, minbucket = 4, cp = 0.005, xval = 5)))
tm <- round(runif(130, 0.3, 3), 2); ev <- rpois(130, tm * exp((as.integer(X$x4) %% 4) * 0.5 + X$x1))
cases <- c(cases, one(cbind(tm, ev), X, method = "poisson", ctl = list(minsplit = 10, minbucket = 4, cp = 0.005, xval = 5), prunes = 0.02))
# heavy missingness (40%) with each use of surrogates
for (us in 0:2) {
  X <- fixna(mkX(110, 5), 0.4); y <- round(signal(mkX(110, 5)), 3) + rnorm(110)
  X$x1[is.na(X$x1) & !is.na(X$x2)] <- NA
  cases <- c(cases, one(y, X, ctl = list(minsplit = 8, minbucket = 3, cp = 0.005, usesurrogate = us, maxsurrogate = 5, xval = 5), prunes = 0.03))
}
# one predictor
X <- mkX(80, 1, fl = 0); y <- round(2 * X$x1 + rnorm(80) * 0.3, 3)
cases <- c(cases, rp_cases(y, X, seed = 5, newX = X[1:10, , drop = FALSE], ctl = list(xval = 5), prunes = 0.05))
# explicit folds: rpart.control(xval = a vector with one fold number per row)
X <- mkX(100, 4); y <- round(signal(X), 4)
cases <- c(cases, one(y, X, ctl = list(minsplit = 8, minbucket = 3, cp = 0.004, xval = sample(rep(1:6, length.out = 100))), prunes = 0.03))
yc <- factor(letters[1 + (y > median(y)) + (y > quantile(y, 0.8))], levels = letters[1:3])
cases <- c(cases, one(yc, X, ctl = list(minsplit = 8, minbucket = 3, cp = 0.004, xval = sample(rep(1:4, length.out = 100)))))
emit("rpartfull_d", c("rpart", "survival"), list(cases))
