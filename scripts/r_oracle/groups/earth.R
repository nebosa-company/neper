# earth (Milborrow): earth(x, y) on numeric matrices drawn from R's own generator, so the fixture regenerates them from the seed.
# Data: x = matrix(runif(n * p), n, p); z = rnorm(n); y1 = 4 * (x1 - .5)^2 + 3 x2 - 2 x2 x3 + .3 z (plus a second response 2 x1 x2 - x3 + .2 z2 when nr = 2);
#   glm family 1 (binomial) turns y1 into 1 * (y1 > 1.3), family 2 (poisson) into floor(2.5 * abs(y)).
# args: 0 seed, 1 n, 2 p, 3 nr, 4 degree, 5 penalty (-99 default), 6 nk (0 default), 7 thresh, 8 minspan, 9 endspan, 10 pmethod
#   (0 backward, 1 none, 2 exhaustive, 3 forward, 4 seqrep, 5 cv), 11 nprune (0 none), 12 newvar.penalty, 13 fast.k, 14 fast.beta, 15 linpreds bit mask,
#   16 Adjust.endspan, 17 Auto.linpreds, 18 Scale.y (-1 default), 19 glm family (0 gaussian, 1 binomial, 2 poisson, 3 no glm), 20 nfold (0 none),
#   21 ncross, 22 stratify, 23 keepxy, 24 quantity, 25 i, 26 j
# quantities: 1 nterms, 2 termcond, 3 nselected, 4 selected.terms[i], 5 dirs[i, j], 6 cuts[i, j], 7 rss, 8 gcv, 9 rsq, 10 grsq, 11 coefficients[i, j],
#   12 fitted[i, j], 13 residuals[i, j], 14 rss.per.subset[i], 15 gcv.per.subset[i], 16 prune.terms[i, j], 17 bx[i, j], 18 rss.per.response[j],
#   19 gcv.per.response[j], 20 rsq.per.response[j], 21 grsq.per.response[j]
#   22 predict(f, xn)[i, j], 23 model.matrix(f, xn)[i, k], 24 ncol of the terms matrix, 25 predict(type = "terms")[i, k],
#   30 nrow(evimp(f)), 31 evimp(f)[i, j], 32 evimp(f, trim = FALSE, sqrt. = FALSE)[i, j]
#   40 glm.coefficients[i, j], 41 glm.stats[i, j], 49 predict(f, xn, type = "response")[i, j], 50 type = "link", 51 type = "class"[i], 52 predict(f, type = "response")[i, j]
#   60 nrow(cv.rsq.tab), 61 cv.rsq.tab[i, j], 62 cv.maxerr.tab, 63 cv.nterms.selected.by.gcv[i], 64 cv.nvars.selected.by.gcv[i], 65 cv.groups[i, j],
#   66 cv.oof.rsq.tab[i, j], 67 cv.infold.rsq.tab[i, j], 68 cv.deviance.tab, 69 cv.calib.int.tab, 70 cv.calib.slope.tab, 71 cv.auc.tab or cv.cor.tab
# tolerance: 1e-9 relative (1e-10 absolute) everywhere; integers (dirs, terms, termcond, groups) exact.
suppressMessages(library(earth))

gen <- function(seed, n, p, nr, fam) {
  set.seed(seed)
  x <- matrix(runif(n * p), n, p)
  colnames(x) <- paste0("x", seq_len(p))
  z <- rnorm(n)
  t <- x[, 1] - 0.5
  y1 <- 4 * t * t + 3 * x[, 2] - 2 * x[, 2] * x[, 3] + 0.3 * z
  y <- matrix(y1, n, 1)
  if (nr == 2) { z2 <- rnorm(n); y <- cbind(y1, 2 * x[, 1] * x[, 2] - x[, 3] + 0.2 * z2) }
  if (fam == 1) y <- 1 * (y > 1.3)
  if (fam == 2) y <- floor(2.5 * abs(y))
  colnames(y) <- paste0("y", seq_len(nr))
  list(x = x, y = y)
}

run <- function(a) {
  d <- gen(a[1], a[2], a[3], a[4], a[20])
  args <- list(x = d$x, y = d$y, degree = a[5], pmethod = c("backward", "none", "exhaustive", "forward", "seqrep", "cv")[a[11] + 1],
               thresh = a[8], minspan = a[9], endspan = a[10], newvar.penalty = a[13], fast.k = a[14], fast.beta = a[15],
               Adjust.endspan = a[17], Auto.linpreds = a[18] == 1)
  if (a[6] != -99) args$penalty <- a[6]
  if (a[7] != 0) args$nk <- a[7]
  if (a[12] != 0) args$nprune <- a[12]
  if (a[16] != 0) args$linpreds <- which(bitwAnd(a[16], 2^(0:(a[3] - 1))) != 0)
  if (a[19] != -1) args$Scale.y <- a[19] == 1
  if (a[20] == 0) args$glm <- list(family = gaussian)
  if (a[20] == 1) args$glm <- list(family = binomial)
  if (a[20] == 2) args$glm <- list(family = poisson)
  if (a[21] > 0) { args$nfold <- a[21]; args$ncross <- a[22]; args$stratify <- a[23] == 1 }
  if (a[24] == 1) args$keepxy <- TRUE
  suppressWarnings(do.call(earth, args))
}

cases <- list()
add <- function(a, q, i, j, v) cases[[length(cases) + 1]] <<- case("r", c(a, q, i, j), v, rel = 1e-9, abs = 1e-10)

# every quantity of a model: sizes first, then the tables
full <- function(a) {
  f <- run(a)
  nt <- nrow(f$dirs); ns <- length(f$selected.terms); nr <- ncol(f$fitted.values); n <- nrow(f$fitted.values); np <- ncol(f$dirs); nall <- length(f$rss.per.subset)
  add(a, 1, 0, 0, nt); add(a, 2, 0, 0, f$termcond); add(a, 3, 0, 0, ns)
  add(a, 7, 0, 0, f$rss); add(a, 8, 0, 0, f$gcv); add(a, 9, 0, 0, f$rsq); add(a, 10, 0, 0, f$grsq)
  for (i in 0:(ns - 1)) add(a, 4, i, 0, f$selected.terms[i + 1])
  for (i in 0:(nt - 1)) for (j in 0:(np - 1)) { add(a, 5, i, j, f$dirs[i + 1, j + 1]); add(a, 6, i, j, f$cuts[i + 1, j + 1]) }
  for (i in 0:(ns - 1)) for (j in 0:(nr - 1)) add(a, 11, i, j, f$coefficients[i + 1, j + 1])
  for (i in c(0, n %/% 2, n - 1)) for (j in 0:(nr - 1)) { add(a, 12, i, j, f$fitted.values[i + 1, j + 1]); add(a, 13, i, j, f$residuals[i + 1, j + 1]) }
  for (i in 0:(nall - 1)) { add(a, 14, i, 0, f$rss.per.subset[i + 1]); add(a, 15, i, 0, f$gcv.per.subset[i + 1]) }
  for (i in 0:(nall - 1)) for (j in 0:i) add(a, 16, i, j, f$prune.terms[i + 1, j + 1])
  for (j in 0:(ns - 1)) add(a, 17, n %/% 3, j, f$bx[n %/% 3 + 1, j + 1])
  for (j in 0:(nr - 1)) { add(a, 18, 0, j, f$rss.per.response[j + 1]); add(a, 19, 0, j, f$gcv.per.response[j + 1])
                          add(a, 20, 0, j, f$rsq.per.response[j + 1]); add(a, 21, 0, j, f$grsq.per.response[j + 1]) }
}

mk <- function(seed, n, p, nr = 1, degree = 1, penalty = -99, nk = 0, thresh = 0.001, minspan = 0, endspan = 0, pmethod = 0, nprune = 0,
               newvar = 0, fastk = 20, fastbeta = 1, linmask = 0, adjend = 2, autolin = 1, scaley = -1, fam = 3, nfold = 0, ncross = 1, stratify = 1, keepxy = 0)
  c(seed, n, p, nr, degree, penalty, nk, thresh, minspan, endspan, pmethod, nprune, newvar, fastk, fastbeta, linmask, adjend, autolin, scaley, fam, nfold, ncross, stratify, keepxy)

full(mk(101, 80, 3))
full(mk(102, 100, 4, degree = 2))
full(mk(103, 70, 3, nk = 11))
full(mk(104, 90, 5, penalty = 3, minspan = 3, endspan = 5))
emit("earth", "earth", list(cases))

cases <- list()
full(mk(111, 60, 3, nk = 3))
full(mk(112, 60, 3, nk = 1))
full(mk(113, 80, 4, degree = 3))
full(mk(114, 80, 4, thresh = 0))
full(mk(115, 80, 4, thresh = 0.02))
full(mk(116, 90, 4, minspan = -2))
full(mk(117, 90, 4, minspan = 1, endspan = 3))
full(mk(118, 80, 4, fastk = 5, fastbeta = 0))
full(mk(119, 80, 4, fastk = 0))
full(mk(120, 80, 4, fastk = 3, fastbeta = 2))
full(mk(121, 80, 4, linmask = 2))
full(mk(122, 80, 4, degree = 2, linmask = 5))
full(mk(123, 80, 4, degree = 2, newvar = 0.1))
full(mk(124, 80, 4, newvar = 0.5))
emit("earth_opts", "earth", list(cases))

cases <- list()
full(mk(131, 80, 4, autolin = 0))
full(mk(132, 80, 4, scaley = 0))
full(mk(133, 80, 4, penalty = 0))
full(mk(134, 80, 4, penalty = -1))
full(mk(135, 80, 4, degree = 2, penalty = 4))
full(mk(136, 80, 4, degree = 2, adjend = 0))
full(mk(137, 80, 4, nprune = 6))
full(mk(138, 30, 3))
full(mk(139, 80, 4, nr = 2, degree = 2))
full(mk(140, 80, 4, nr = 2, pmethod = 1))
full(mk(141, 80, 4, pmethod = 2, nk = 11))
full(mk(142, 80, 4, pmethod = 3, nk = 15))
full(mk(143, 80, 4, pmethod = 4, nk = 15))
full(mk(144, 80, 4, pmethod = 2, nk = 13, nprune = 5))
full(mk(145, 80, 4, pmethod = 1))
emit("earth_prune", "earth", list(cases))

# predict, model.matrix, predict(type = "terms") and evimp; the 15 new rows are runif(15 p) drawn right after the data
cases <- list()
getx <- function(a) {
  f <- run(a)
  m <- 15; p <- a[3]
  xn <- matrix(runif(m * p), m, p); colnames(xn) <- paste0("x", seq_len(p))
  list(f = f, xn = xn)
}
fullx <- function(a) {
  o <- getx(a); f <- o$f; xn <- o$xn
  ns <- length(f$selected.terms); nr <- ncol(f$fitted.values)
  pr <- predict(f, xn); mm <- model.matrix(f, xn)
  ev <- evimp(f); ev2 <- evimp(f, trim = FALSE, sqrt. = FALSE)
  for (i in c(0, 7, 14)) for (j in 0:(nr - 1)) add(a, 22, i, j, pr[i + 1, j + 1])
  for (i in c(3, 11)) for (k in 0:(ns - 1)) add(a, 23, i, k, mm[i + 1, k + 1])
  if (nr == 1) {
    tm <- predict(f, xn, type = "terms")
    add(a, 24, 0, 0, ncol(tm))
    if (ncol(tm) > 0) for (i in c(1, 9)) for (k in 0:(ncol(tm) - 1)) add(a, 25, i, k, tm[i + 1, k + 1])
  }
  add(a, 30, 0, 0, nrow(ev))
  for (i in seq_len(nrow(ev))) for (j in 0:6) add(a, 31, i - 1, j, ev[i, j + 1])
  for (i in seq_len(nrow(ev2))) for (j in 0:6) add(a, 32, i - 1, j, ev2[i, j + 1])
}
fullx(mk(151, 80, 3))
fullx(mk(152, 100, 4, degree = 2))
fullx(mk(153, 80, 5, degree = 2, linmask = 2))
fullx(mk(154, 80, 4, nr = 2, degree = 2))
fullx(mk(155, 90, 3, nk = 7))
fullx(mk(156, 70, 4, pmethod = 1))
emit("earth_pred", "earth", list(cases))

# glm responses: coefficients, stats and the three predict types; family 1 binomial, 2 poisson, 0 gaussian
cases <- list()
fullg <- function(a) {
  full(a)
  o <- getx(a); f <- o$f; xn <- o$xn
  ns <- length(f$selected.terms); nr <- ncol(f$fitted.values); n <- nrow(f$fitted.values)
  for (i in 0:(ns - 1)) for (j in 0:(nr - 1)) add(a, 40, i, j, f$glm.coefficients[i + 1, j + 1])
  for (i in 0:(nr - 1)) for (j in 0:7) add(a, 41, i, j, f$glm.stats[i + 1, j + 1])
  pr <- predict(f, xn, type = "response"); pl <- predict(f, xn, type = "link"); p0 <- predict(f, type = "response")
  for (i in c(0, 5, 14)) for (j in 0:(nr - 1)) { add(a, 49, i, j, pr[i + 1, j + 1]); add(a, 50, i, j, pl[i + 1, j + 1]) }
  for (i in c(0, n %/% 2, n - 1)) for (j in 0:(nr - 1)) add(a, 52, i, j, p0[i + 1, j + 1])
  if (a[20] == 1) { pc <- predict(f, xn, type = "class"); for (i in 0:14) add(a, 51, i, 0, as.numeric(pc[i + 1, 1])) }
}
fullg(mk(161, 100, 3, fam = 1))
fullg(mk(162, 120, 4, degree = 2, fam = 1))
fullg(mk(163, 100, 3, fam = 2))
fullg(mk(164, 100, 4, nr = 2, fam = 2))
fullg(mk(165, 90, 3, fam = 0))
fullg(mk(166, 100, 3, fam = 1, pmethod = 1))
emit("earth_glm", "earth", list(cases))

# cross-validation: the tables of earth(nfold, ncross, stratify, keepxy) and pmethod = "cv"
cases <- list()
cvq <- function(a) {
  f <- run(a)
  fam <- a[20]; nr <- ncol(f$fitted.values); n <- nrow(f$fitted.values)
  nrow1 <- nrow(f$cv.oof.rsq.tab); if (is.null(nrow1)) nrow1 <- nrow(f$cv.rsq.tab)
  add(a, 60, 0, 0, nrow1)
  ntab <- nrow1
  maxn <- ncol(f$cv.oof.rsq.tab)
  if (a[11] != 5) {
    for (i in 0:(ntab - 1)) for (j in 0:nr) { add(a, 61, i, j, f$cv.rsq.tab[i + 1, j + 1]); add(a, 62, i, j, f$cv.maxerr.tab[i + 1, j + 1]) }
  }
  if (!is.null(f$cv.groups)) for (i in 0:(ntab - 1)) { add(a, 63, i, 0, f$cv.nterms.selected.by.gcv[i + 1]); add(a, 64, i, 0, f$cv.nvars.selected.by.gcv[i + 1]) }
  if (!is.null(f$cv.groups)) for (i in 0:(nrow(f$cv.groups) - 1)) for (j in 0:(ncol(f$cv.groups) - 1)) add(a, 65, i, j, f$cv.groups[i + 1, j + 1])
  if (!is.null(f$cv.oof.rsq.tab)) {
    for (i in 0:(ntab - 1)) for (j in 0:(ncol(f$cv.oof.rsq.tab) - 1)) { add(a, 66, i, j, f$cv.oof.rsq.tab[i + 1, j + 1]); add(a, 67, i, j, f$cv.infold.rsq.tab[i + 1, j + 1]) }
  }
  if (a[11] != 5 && (fam == 1 || fam == 2))
    for (i in 0:(ntab - 1)) for (j in 0:nr) {
      add(a, 68, i, j, f$cv.deviance.tab[i + 1, j + 1]); add(a, 69, i, j, f$cv.calib.int.tab[i + 1, j + 1]); add(a, 70, i, j, f$cv.calib.slope.tab[i + 1, j + 1])
      add(a, 71, i, j, if (fam == 1) f$cv.auc.tab[i + 1, j + 1] else f$cv.cor.tab[i + 1, j + 1])
    }
  full(a)
}
cvq(mk(171, 80, 3, nfold = 5))
cvq(mk(172, 90, 4, degree = 2, nfold = 4, ncross = 2))
cvq(mk(173, 80, 3, nfold = 5, keepxy = 1))
cvq(mk(174, 80, 3, nr = 2, nfold = 4, keepxy = 1))
cvq(mk(175, 80, 4, nfold = 5, pmethod = 5))
cvq(mk(176, 100, 3, nfold = 5, pmethod = 5, nprune = 7))
cvq(mk(177, 80, 3, nfold = 5, stratify = 0))
cvq(mk(178, 120, 3, nfold = 5, fam = 1))
cvq(mk(179, 100, 3, nfold = 4, fam = 2))
cvq(mk(180, 100, 3, nfold = 5, fam = 1, pmethod = 5))
emit("earth_cv", "earth", list(cases))

# format.earth: the text of every response (and glm) in the styles h, pmax, max, bf; each string is answered by its length (80), a position-weighted byte sum (81)
# and a base-257 hash mod 1000003 (82), exact integers. i = style * 100 + digits, j = response (nr + r for the glm of response r)
cases <- list()
hsh <- function(s) {
  b <- utf8ToInt(s); n <- length(b); h <- 0
  for (v in b) h <- (h * 257 + v) %% 1000003
  c(n, sum(b * seq_len(n)), h)
}
fullf <- function(a) {
  f <- run(a)
  for (sty in 0:3) for (dg in c(7, 4)) {
    s <- format(f, style = c("h", "pmax", "max", "bf")[sty + 1], digits = dg)
    for (j in seq_along(s)) { h <- hsh(s[j]); for (q in 0:2) add(a, 80 + q, sty * 100 + dg, j - 1, h[q + 1]) }
  }
}
fullf(mk(191, 80, 3))
fullf(mk(192, 100, 4, degree = 2))
fullf(mk(193, 90, 3, nr = 2))
fullf(mk(194, 100, 4, nr = 2, degree = 2))
fullf(mk(195, 100, 3, fam = 1))
fullf(mk(196, 100, 3, fam = 2, degree = 2))
fullf(mk(197, 100, 5, degree = 3, nk = 31))
fullf(mk(198, 80, 3, linmask = 3))
fullf(mk(199, 80, 4, pmethod = 1))
emit("earth_fmt", "earth", list(cases))
