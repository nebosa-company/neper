# gbm: boosted trees, the whole fit compared with R's. The fixture rebuilds each data set from its seed with the same draws (rnorm, runif, rexp) and fits it, so a case carries
# only the configuration.
#   args: (data_seed, dist, n, p, ntrees, shrinkage, depth, minobs, bag, train.fraction, fit_seed, par, wflag, mono, cv, na, more, out, a, b, c)
#   dist: 0 gaussian 1 bernoulli 2 poisson 3 adaboost 4 laplace 5 quantile(par = alpha) 6 huberized 7 tdist(par = df) 8 coxph 9 multinomial 10 pairwise conc 11 ndcg 12 map 13 mrr
#   out:  1 fit[a] (class c) 2 train.error[a] 3 valid.error[a] 4 oobag.improve[a] 5 relative.influence var a over b trees 6 initF 7 predict(link) row a, b trees, class c
#         8 predict(response) 9 sum(train.error) 10 sum(valid.error) 11 sum(oobag.improve) 12 cv.error[a] 13 cv.fitted[a] 14 gbm.perf (a = 1 test, 2 cv)
#         17 predict(f, the training data, n.trees = b) at data row a
#         15 relative.influence var a at the default tree count 16 predict row a at the default tree count
#         30 plot.gbm(i.var = vars of c, n.trees = b, return.grid)$y[a], 7 per variable for two, 4 for three, 20 for one; 31 the same on the response scale
#         20..27 tree b (1-based, over classes) node a: SplitVar SplitCodePred LeftNode RightNode MissingNode ErrorReduction Weight Prediction
suppressMessages({ library(gbm); library(survival) })
r3 <- function(x, d = 3) floor(x * 10^d + 0.5) / 10^d
mk <- function(seed, dist, n, p, wflag, na = 0) {
  set.seed(seed)
  X <- matrix(r3(rnorm(n * p)), n, p)
  lin <- 1.5 * X[, 1] - X[, 2]
  st <- NULL
  y <- switch(as.character(dist),
    "0" = r3(sin(2 * X[, 1]) + X[, 2] * X[, 2] * 0.5 + rnorm(n, 0, 0.3)),
    "1" = , "3" = , "6" = as.numeric(runif(n) < 1 / (1 + exp(-lin))),
    "2" = floor(runif(n) * 3 * exp(0.6 * X[, 1])),
    "4" = , "5" = r3(2 * X[, 1] + rexp(n), 4),
    "10" = , "11" = , "12" = , "13" = 0,
    "7" = { u <- r3(sin(2 * X[, 1]) + X[, 2] * X[, 2] * 0.5 + rnorm(n, 0, 0.3)); u + 4 * as.numeric(runif(n) < 0.1) },
    "8" = { tm <- r3(rexp(n) / exp(0.7 * X[, 1])) + 0.001; st <- as.numeric(runif(n) < 0.8); tm },
    "9" = { u <- X[, 1] + rnorm(n) * 0.7; factor(ifelse(u < -0.5, "a", ifelse(u < 0.5, "b", "c"))) },
    stop("dist"))
  grp <- NULL
  if (dist >= 10) {
    grp <- floor(runif(n) * 12) + 1
    lat <- 1.2 * X[, 1] + rnorm(n) * 0.8
    y <- if (dist <= 11) pmin(3, pmax(0, floor(lat + 1))) else as.numeric(lat > 0.6)
  }
  w <- if (wflag == 1 && dist >= 10) { wg <- 0.5 * (1 + floor(4 * runif(12))); wg[grp] } else if (wflag == 1) 0.5 * (1 + floor(4 * runif(n))) else NULL
  if (na == 1) { miss <- matrix(runif(n * p) < 0.08, n, p); X[miss] <- NA }
  list(X = X, y = y, st = st, w = w, grp = grp)
}
gcfg <- function(seed, dist, n = 120, p = 3, nt = 30, sh = 0.1, d = 2, mo = 5, bag = 0.5, tf = 1, fseed = 1, par = 0, wflag = 0, mono = 0, cv = 0, na = 0, more = 0) list(seed = seed, dist = dist, n = n, p = p, nt = nt, sh = sh, d = d, mo = mo, bag = bag, tf = tf, fseed = fseed, par = par, wflag = wflag, mono = mono, cv = cv, na = na, more = more)
run_gbm <- function(g) {
  dat <- mk(g$seed, g$dist, g$n, g$p, g$wflag, g$na)
  df <- data.frame(y = dat$y, dat$X); names(df) <- c("y", paste0("V", 1:g$p))
  fo <- y ~ .
  if (g$dist >= 10) { df$grp <- sprintf("g%02d", dat$grp); fo <- as.formula(paste("y ~", paste0("V", 1:g$p, collapse = " + "))) }
  if (g$dist == 8) { df$st <- dat$st; names(df)[1] <- "tm"; fo <- Surv(tm, st) ~ . }
  dist <- switch(as.character(g$dist), "0" = "gaussian", "1" = "bernoulli", "2" = "poisson", "3" = "adaboost", "4" = "laplace", "5" = list(name = "quantile", alpha = g$par), "6" = "huberized", "7" = list(name = "tdist", df = g$par), "8" = "coxph", "9" = "multinomial", { d <- list(name = "pairwise", metric = c("conc", "ndcg", "map", "mrr")[g$dist - 9], group = "grp"); if (g$par > 0) d$max.rank <- g$par; d })
  args <- list(formula = fo, distribution = dist, data = df, n.trees = g$nt, shrinkage = g$sh, interaction.depth = g$d, n.minobsinnode = g$mo, bag.fraction = g$bag, train.fraction = g$tf, cv.folds = g$cv, n.cores = 1, keep.data = TRUE, verbose = FALSE)
  if (g$wflag == 1) args$weights <- dat$w
  if (g$mono == 1) args$var.monotone <- c(1, -1, rep(0, g$p - 2))
  set.seed(g$fseed)
  f <- suppressWarnings(suppressMessages(do.call(gbm, args)))
  if (g$more > 0) f <- suppressWarnings(suppressMessages(gbm.more(f, n.new.trees = g$more)))
  nn <- 12
  set.seed(g$seed + 1000003)
  Xn <- matrix(r3(rnorm(nn * g$p)), nn, g$p)
  if (g$na == 1) Xn[matrix(runif(nn * g$p) < 0.15, nn, g$p)] <- NA
  dn <- data.frame(Xn); names(dn) <- paste0("V", 1:g$p)
  list(f = f, dn = dn, df = df)
}
gcases <- function(g, outs, rel = 1e-9, abs = 1e-12) {
  r <- run_gbm(g)
  f <- r$f; dn <- r$dn
  pre <- c(g$seed, g$dist, g$n, g$p, g$nt, g$sh, g$d, g$mo, g$bag, g$tf, g$fseed, g$par, g$wflag, g$mono, g$cv, g$na, g$more)
  out <- list()
  nc <- if (g$dist == 9) 3 else 1
  add <- function(code, a, b, cc, want, tol = rel) out[[length(out) + 1]] <<- case("g", c(pre, code, a, b, cc), want, rel = tol, abs = abs)
  for (o in outs) {
    code <- o[[1]]; a <- o[[2]]; b <- if (length(o) > 2) o[[3]] else 0; cc <- if (length(o) > 3) o[[4]] else 0
    want <- switch(as.character(code),
      "1" = if (nc > 1) f$fit[a + 1, cc + 1] else f$fit[a + 1],
      "2" = f$train.error[a + 1], "3" = f$valid.error[a + 1], "4" = f$oobag.improve[a + 1],
      "5" = as.numeric(relative.influence(f, n.trees = b)[a + 1]),
      "6" = f$initF,
      "17" = { pr <- suppressWarnings(predict(f, r$df, n.trees = b)); if (nc > 1) pr[a + 1, cc + 1, 1] else pr[a + 1] },
      "7" = { pr <- suppressWarnings(predict(f, r$dn, n.trees = b)); if (nc > 1) pr[a + 1, cc + 1, 1] else pr[a + 1] },
      "8" = { pr <- suppressWarnings(predict(f, r$dn, n.trees = b, type = "response")); if (nc > 1) pr[a + 1, cc + 1, 1] else pr[a + 1] },
      "9" = sum(f$train.error), "10" = sum(f$valid.error), "11" = sum(f$oobag.improve),
      "12" = f$cv.error[a + 1], "13" = f$cv.fitted[a + 1],
      "14" = as.numeric(suppressMessages(gbm.perf(f, method = if (a == 1) "test" else "cv", plot.it = FALSE))),
      "30" = , "31" = {
        iv <- if (cc < 10) cc else if (cc < 100) c(cc %/% 10, cc %% 10) else c(cc %/% 100, (cc %/% 10) %% 10, cc %% 10)
        res <- c(20, 7, 4)[length(iv)]
        gr <- suppressWarnings(plot(f, i.var = iv, n.trees = b, continuous.resolution = res, return.grid = TRUE, type = if (code == 31) "response" else "link"))
        gr$y[a + 1] },
      "15" = as.numeric(suppressMessages(relative.influence(f))[a + 1]),
      "16" = { pr <- suppressMessages(suppressWarnings(predict(f, r$dn))); pr[a + 1] },
      { fld <- code - 20; tr <- pretty.gbm.tree(f, b); if (a >= nrow(tr)) NULL else as.numeric(tr[[fld + 1]][a + 1]) })
    if (is.null(want)) next
    add(code, a, b, cc, want)
  }
  out
}
cases <- list()
G <- function(g, outs) cases[[length(cases) + 1]] <<- gcases(g, outs)
# every output for a fit: the fit, the three error sequences, the importance, predictions and the first trees
std <- function(nt, nrow = 120, tf = 1, bag = 0.5, nodes = 4) {
  o <- list(list(1, 0), list(1, 7), list(1, nrow - 1), list(2, 0), list(2, nt %/% 2 - 1), list(2, nt - 1), list(9, 0), list(6, 0))
  if (tf < 1) o <- c(o, list(list(3, 0), list(3, nt %/% 2 - 1), list(3, nt - 1), list(10, 0)))
  if (bag < 1) o <- c(o, list(list(4, 0), list(4, 1), list(4, nt %/% 2 - 1), list(4, nt - 1), list(11, 0)))
  o <- c(o, lapply(0:2, function(j) list(5, j, nt)), lapply(0:2, function(j) list(5, j, nt %/% 3)))
  o <- c(o, list(list(7, 0, nt), list(7, 5, nt), list(7, 11, nt), list(7, 3, nt %/% 3), list(8, 2, nt), list(15, 1), list(16, 4)))
  for (tr in c(1, nt)) for (fld in c(20, 21, 22, 23, 25, 27)) for (nd in 0:(nodes - 1)) o[[length(o) + 1]] <- list(fld, nd, tr)
  o
}
# multinomial: the class column of the fit and predictions, and the trees of every class
stdm <- function(nt, nrow = 120, tf = 1, bag = 0.5, nodes = 4) {
  o <- list(list(2, 0), list(2, nt %/% 2 - 1), list(2, nt - 1), list(9, 0), list(6, 0))
  for (k in 0:2) o <- c(o, list(list(1, 0, 0, k), list(1, 9, 0, k), list(1, nrow - 1, 0, k), list(7, 0, nt, k), list(7, 6, nt, k), list(8, 3, nt, k), list(8, 10, nt %/% 2, k)))
  if (tf < 1) o <- c(o, list(list(3, 0), list(3, nt %/% 2 - 1), list(3, nt - 1), list(10, 0)))
  if (bag < 1) o <- c(o, list(list(4, 0), list(4, nt %/% 2 - 1), list(4, nt - 1), list(11, 0)))
  o <- c(o, lapply(0:2, function(j) list(5, j, nt)), lapply(0:2, function(j) list(5, j, nt %/% 3)))
  for (tr in c(1, 2, 3, 3 * nt - 2, 3 * nt)) for (fld in c(20, 21, 22, 23, 25, 27)) for (nd in 0:(nodes - 1)) o[[length(o) + 1]] <- list(fld, nd, tr)
  o
}
cat("gaussian
")
G(gcfg(11, 0, bag = 1), std(30, bag = 1))
G(gcfg(12, 0), std(30))
G(gcfg(13, 0, d = 3, mo = 3, nt = 40), std(40, nodes = 7))
G(gcfg(14, 0, tf = 0.7, nt = 40, fseed = 5), std(40, tf = 0.7))
G(gcfg(15, 0, wflag = 1, nt = 30, fseed = 9), std(30))
G(gcfg(16, 0, mono = 1, p = 4, bag = 0.7, fseed = 4), std(30, bag = 0.7))
G(gcfg(17, 0, d = 1, nt = 50, sh = 0.3, mo = 10, n = 200, p = 5, bag = 0.6, fseed = 21), std(50, nrow = 200, bag = 0.6))
G(gcfg(18, 0, d = 5, nt = 20, sh = 0.05, mo = 2, n = 150, bag = 0.8, tf = 0.8, wflag = 1, fseed = 33), std(20, nrow = 150, bag = 0.8, tf = 0.8, nodes = 6))
cat("losses
")
for (dd in c(1, 2, 3, 4, 6, 7, 8)) {
  pr <- if (dd == 7) 4 else 0
  G(gcfg(20 + dd, dd, par = pr), std(30))
  G(gcfg(30 + dd, dd, bag = 1, d = 3, mo = 3, par = pr, fseed = 3), std(30, bag = 1, nodes = 7))
  G(gcfg(40 + dd, dd, tf = 0.75, nt = 40, fseed = 7, par = pr), std(40, tf = 0.75))
  G(gcfg(50 + dd, dd, wflag = 1, par = pr, fseed = 11, bag = 0.65), std(30, bag = 0.65))
}
G(gcfg(61, 5, par = 0.2), std(30)); G(gcfg(62, 5, par = 0.8, bag = 1, d = 3, mo = 3), std(30, bag = 1, nodes = 7)); G(gcfg(63, 5, par = 0.5, tf = 0.75, nt = 40, fseed = 7), std(40, tf = 0.75)); G(gcfg(64, 5, par = 0.9, wflag = 1, fseed = 11, bag = 0.65), std(30, bag = 0.65))
G(gcfg(65, 7, par = 2.5, nt = 40, d = 3, n = 150), std(40, nrow = 150, nodes = 7))
cat("multinomial
")
G(gcfg(71, 9, n = 150), stdm(20, nrow = 150))
G(gcfg(72, 9, n = 150, bag = 1, d = 3, mo = 3, fseed = 2), stdm(20, nrow = 150, bag = 1, nodes = 7))
G(gcfg(73, 9, n = 150, tf = 0.7, nt = 25, fseed = 7), stdm(25, nrow = 150, tf = 0.7))
G(gcfg(74, 9, n = 150, wflag = 1, bag = 0.65, fseed = 11), stdm(20, nrow = 150, bag = 0.65))
cat("missing values, gbm.more, cross-validation, partial dependence
")
cvo <- function(nt, nrow = 120, nclass = 1) c(list(list(12, 0), list(12, nt - 1), list(12, nt %/% 2), list(14, 2), list(15, 0), list(15, 1), list(16, 0), list(16, 7)), lapply(c(0, 20, 50, 80), function(i) list(13, i)))
plots <- function(nt) c(lapply(c(0, 5, 11, 19), function(r) list(30, r, nt, 1)), lapply(c(0, 3, 9, 16), function(r) list(30, r, nt %/% 2, 2)), lapply(c(0, 6, 17, 40, 48), function(r) list(30, r, nt, 21)), list(list(30, 12, nt, 123), list(30, 40, nt, 123), list(30, 63, nt, 123)))
G(gcfg(91, 0, na = 1, bag = 0.6), std(30, bag = 0.6))
G(gcfg(92, 1, na = 1, wflag = 1, d = 3), std(30, nodes = 7))
G(gcfg(93, 7, na = 1, par = 4, tf = 0.8, nt = 30, fseed = 3), std(30, tf = 0.8))
G(gcfg(94, 8, na = 1, bag = 0.7), std(30, bag = 0.7))
G(gcfg(95, 9, na = 1, n = 150), stdm(20, nrow = 150))
G(gcfg(96, 0, more = 15, bag = 0.6, fseed = 2), std(45, bag = 0.6, nodes = 4))
G(gcfg(97, 2, more = 12, tf = 0.75, nt = 20, fseed = 6), std(32, tf = 0.75))
G(gcfg(98, 8, more = 10, nt = 20), std(30))
G(gcfg(99, 9, more = 8, nt = 12, n = 150), stdm(20, nrow = 150))
G(gcfg(100, 5, par = 0.3, more = 9, nt = 15, wflag = 1), std(24))
G(gcfg(101, 0, cv = 3, nt = 25, fseed = 3), c(std(25), cvo(25)))
G(gcfg(102, 1, cv = 4, nt = 25, fseed = 4, n = 100), c(std(25, nrow = 100), cvo(25, 100)))
G(gcfg(103, 8, cv = 3, nt = 20, fseed = 5, bag = 0.7), c(std(20, bag = 0.7), cvo(20)))
G(gcfg(104, 0, cv = 3, nt = 25, tf = 0.8, fseed = 6, wflag = 1), c(std(25, tf = 0.8), cvo(25)))
G(gcfg(105, 9, cv = 3, nt = 15, n = 150, fseed = 7), c(stdm(15, nrow = 150), list(list(12, 0), list(12, 14), list(12, 7), list(14, 2), list(15, 0), list(15, 2), list(16, 0, 0, 0), list(13, 0), list(13, 30), list(13, 149), list(13, 200))))
G(gcfg(106, 5, par = 0.7, cv = 3, nt = 20, fseed = 8, wflag = 1, mo = 3), c(std(20), cvo(20)))
G(gcfg(111, 0, nt = 20), c(std(20), plots(20)))
G(gcfg(112, 1, nt = 20, wflag = 1, d = 3), c(std(20, nodes = 7), plots(20), list(list(31, 0, 20, 1), list(31, 7, 20, 1), list(31, 5, 10, 21))))
G(gcfg(113, 2, nt = 20, na = 1), c(std(20), plots(20), list(list(31, 3, 20, 1), list(31, 10, 20, 21))))
G(gcfg(114, 8, nt = 20, bag = 0.7), c(std(20, bag = 0.7), plots(20)))
cat("pairwise
")
for (dd in 10:13) {
  mr <- if (dd == 11 || dd == 13) 4 else 0
  G(gcfg(220 + dd, dd, n = 150, nt = 25, mo = 3, bag = 0.6), std(25, nrow = 150, bag = 0.6))
  G(gcfg(230 + dd, dd, n = 150, nt = 25, mo = 3, bag = 1, d = 3, fseed = 3, par = mr), std(25, nrow = 150, bag = 1, nodes = 7))
  G(gcfg(240 + dd, dd, n = 150, nt = 30, mo = 3, tf = 0.75, fseed = 7, bag = 0.7), std(30, nrow = 150, tf = 0.75, bag = 0.7))
  G(gcfg(250 + dd, dd, n = 150, nt = 25, mo = 3, wflag = 1, bag = 0.65, fseed = 11, par = mr), std(25, nrow = 150, bag = 0.65))
}
# two data sets whose fits have exactly tied splits (the same partition from two variables): they agree only with an exp and log rounded the way the C runtime rounds them
G(gcfg(130, 10, n = 150, nt = 25, mo = 3, bag = 0.6), c(std(25, nrow = 150, bag = 0.6), lapply(c(51, 68, 120), function(i) list(17, i, 8))))
G(gcfg(251, 11, n = 150, nt = 30, mo = 3, tf = 0.75, fseed = 7, bag = 0.7, par = 0), c(std(30, nrow = 150, tf = 0.75, bag = 0.7), lapply(c(51, 68, 140), function(i) list(17, i, 8))))
G(gcfg(161, 11, n = 150, nt = 20, mo = 3, cv = 3, bag = 0.7, fseed = 5, par = 3), c(std(20, nrow = 150, bag = 0.7), cvo(20), list(list(13, 120), list(13, 140))))
G(gcfg(162, 10, n = 150, nt = 15, mo = 3, more = 10, bag = 0.7, fseed = 6), std(25, nrow = 150, bag = 0.7))
G(gcfg(163, 12, n = 150, nt = 20, mo = 3, tf = 0.7, cv = 3, fseed = 8, na = 1), c(std(20, nrow = 150, tf = 0.7, bag = 0.5), cvo(20)))
emit("gbm", c("gbm", "survival"), cases)
