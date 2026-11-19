# armextra: arm's display and sigma.hat (lm, glm), corrplot's matrix, contr.bayes, discrete.hist, coefplot, mcplot, balance, matching and binnedplot's numbers. Every case is one number of a result.
#   "dispm" (n, k, icpt, y, X row-major, index) into c(sigma.hat, r.squared, n, k, coef, se, t, p)
#   "corr" (n, p, abs, x row-major with NA, i, j); "contrb" (n, kind 0 unordered 1 ordered 2 ordered without contrasts, scores, i, j)
#   "dhist" (m, numeric, freq, bar.width or NA, has prob2, has prob3, x, prob, prob2, prob3, index) into c(bar.width, xlo, xhi, ymax, 3 offsets, nine numbers per bar)
#   "cplot" (m, CI, has lower, has upper, coefs, sds, lower, upper, index) into c(coefs.h, coefs.l, est1 low, est1 high, est2 low, est2 high, CI)
#   "mcp" (nr, ind, alpha, which, object row-major, i, j); "balance" (n, K, estimand 0 ATT 1 ATC 2 ATE, which 0 raw 1 matched 2 binary, treat, matched, x row-major, r, c)
#   "matchn" (n, which, z, score, index); "matchr" (seed, n, which, z, score, i, j); "bpl" (n, y, x, index) into the plot ranges of binnedplot and its bin count
suppressMessages(library(arm))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
addv <- function(fn, pre, v, rel = 1e-9, abs = 1e-11) for (i in seq_along(v)) if (!is.na(v[i]) || fn == "corr") add(fn, c(pre, i - 1), v[i], rel, abs)
# blocks: a block of `sizes[b]` entries is one case whose answer is the weighted sum 1 * v[1] + 2 * v[2] + ..., from index `from` for `len`
addb <- function(fn, pre, v, sizes, rel = 1e-9, abs = 1e-11) {
  from <- 0
  for (len in sizes) { blk <- v[from + seq_len(len)]; add(fn, c(pre, from, len), sum(seq_len(len) * blk), rel, abs); from <- from + len }
}
quiet <- function(e) { r <- NULL; capture.output(r <- suppressWarnings(e)); r }
nograph <- list(par = function(...) c(5.1, 4.1, 4.1, 2.1), axis = function(...) NULL, abline = function(...) NULL, points = function(...) NULL, lines = function(...) NULL,
                text = function(...) NULL, title = function(...) NULL, box = function(...) NULL, image = function(...) NULL, plot = function(...) NULL, polygon = function(...) NULL,
                segments = function(...) NULL)
runin <- function(f, over, ...) { env <- list2env(modifyList(nograph, over), parent = asNamespace("arm")); environment(f) <- env; f(...) }
set.seed(20262100)
# display for lm
for (rep in 1:14) {
  n <- sample(15:40, 1); k <- sample(2:4, 1); icpt <- rep %% 3 != 0
  X <- matrix(round(rnorm(n * k), 4), n, k); if (icpt) X[, 1] <- 1
  y <- round(rnorm(n, X %*% rnorm(k)), 4)
  d <- data.frame(y = y, X[, if (icpt) -1 else seq_len(k), drop = FALSE]); names(d) <- c("y", paste0("v", seq_len(ncol(d) - 1)))
  fit <- if (icpt) lm(y ~ ., d) else lm(y ~ . - 1, d)
  r <- quiet(display(fit, digits = 3, detail = TRUE))
  v <- c(arm::sigma.hat(fit), r$r.squared, r$n, r$k, r$coef, r$se, r$t.value, r$p.value)
  addb("dispm", c(n, k, icpt, y, as.vector(t(X))), v, c(1, 1, 1, 1, k, k, k, k))
}
# corrplot's matrix
for (rep in 1:10) {
  n <- sample(15:30, 1); p <- sample(3:5, 1); x <- matrix(round(rnorm(n * p), 3), n, p); x[, 2] <- x[, 2] + x[, 1]
  if (rep %% 2 == 0) x[sample(n * p, round(n * p * 0.12))] <- NA
  if (rep == 9) x[, p] <- 1
  ab <- rep %% 4 < 2
  z <- suppressWarnings(if (ab) abs(cor(x, x, use = "pairwise.complete.obs")) else cor(x, x, use = "pairwise.complete.obs"))
  for (i in 1:p) add("corr", c(n, p, ab, as.vector(t(x)), i - 1, 0), sum(1:p * z[i, ]), rel = 1e-12, abs = 1e-14)
}
# contr.bayes
for (spec in list(c(2, 0), c(3, 0), c(5, 0), c(2, 1), c(3, 1), c(4, 1), c(5, 1), c(6, 1), c(7, 1), c(4, 2), c(6, 2), c(4, 3), c(5, 3))) {
  n <- spec[1]; kind <- spec[2]
  sc <- if (kind == 3) sort(round(runif(n, 0, 10), 2)) else 1:n
  z <- if (kind == 0) contr.bayes.unordered(n) else if (kind == 3) contr.bayes.ordered(n, scores = sc) else contr.bayes.ordered(n, contrasts = kind == 1)
  kk <- if (kind == 3) 1 else kind
  for (i in 1:n) for (j in 1:n) add("contrb", c(n, kk, sc, i - 1, j - 1), z[i, j], rel = 1e-9, abs = 1e-11)
}
# discrete.hist: arm's own code with the drawing calls recorded
for (rep in 1:10) {
  m <- sample(3:7, 1); numeric <- rep %% 3 != 0; xs <- if (numeric) sort(sample(1:30, m)) else 1:m
  pr <- round(runif(m, 1, 9)); has2 <- rep %% 2 == 0; has3 <- rep %% 4 == 0; pr2 <- round(runif(m, 1, 9)); pr3 <- round(runif(m, 1, 9)); fr <- rep %% 5 == 0
  bw <- if (rep %% 3 == 1) 0.15 else NA
  a <- list(x = if (numeric) xs else letters[1:m], prob = pr, freq = fr)
  if (has2) a$prob2 <- pr2
  if (has3) a$prob3 <- pr3
  if (!is.na(bw)) a$bar.width <- bw
  rec <- list(); pl <- list()
  do.call(runin, c(list(arm::discrete.hist, list(polygon = function(x, y, ...) rec[[length(rec) + 1]] <<- list(x = x, y = y), plot = function(x, y, ...) pl[[length(pl) + 1]] <<- list(x = x, y = y))), a))
  # R draws three polygons per bar (an absent series has an NA height) unless freq is set, then only the series given; the edges of a series never drawn are not compared
  nser <- if (fr) 1 + has2 + has3 else 3; centre <- if (numeric) xs else 1:m; bwv <- rec[[1]]$x[3] - rec[[1]]$x[1]
  ofs <- sapply(1:3, function(s) if (s <= nser) rec[[s]]$x[1] + bwv / 2 - centre[1] else NA)
  v <- c(bwv, pl[[1]]$x, pl[[1]]$y[2], ofs)
  for (i in 1:m) {
    row <- rep(NA, 9)
    for (s in seq_len(nser)) { p <- rec[[(i - 1) * nser + s]]; row[s] <- if (is.na(p$y[2])) NA else p$y[2]; row[3 + 2 * s - 1] <- p$x[1]; row[3 + 2 * s] <- p$x[3] }
    v <- c(v, row)
  }
  addv("dhist", c(m, numeric, fr, if (is.na(bw)) NA else bw, has2, has3, centre, pr, if (has2) pr2 else rep(0, m), if (has3) pr3 else rep(0, m)), v, rel = 1e-12, abs = 1e-14)
}
# coefplot (horizontal, so segments(idx, low, idx, high))
for (rep in 1:10) {
  m <- sample(3:7, 1); co <- round(rnorm(m), 3); sd <- round(runif(m, 0.1, 0.6), 3); ci <- if (rep %% 2) 2 else 1
  hl <- rep %% 3 == 0; hu <- rep %% 4 == 0; lo <- round(co - runif(m, 0.2, 1), 3); up <- round(co + runif(m, 0.2, 1), 3)
  a <- list(coefs = co, sds = sd, CI = ci, vertical = FALSE)
  if (hl) a$lower.conf.bounds <- lo
  if (hu) a$upper.conf.bounds <- up
  seg <- list(); pw <- NULL
  do.call(runin, c(list(arm::coefplot.default, list(plot = function(x, y, ...) if (is.null(pw)) pw <<- y, segments = function(x0, y0, x1, y1, ...) seg[[length(seg) + 1]] <<- cbind(y0, y1))), a))
  v <- c(pw[(m + 1):(2 * m)], pw[1:m], seg[[1]][, 1], seg[[1]][, 2], if (length(seg) > 1) c(seg[[2]][, 1], seg[[2]][, 2]) else rep(NA, 2 * m), length(seg))
  addv("cplot", c(m, ci, hl, hu, co, sd, lo, up), v, rel = 1e-12, abs = 1e-14)
}
# mcplot
for (rep in 1:8) {
  nr <- sample(25:40, 1); ind <- sample(3:5, 1); ob <- as.data.frame(matrix(round(rnorm(nr * ind, rep(seq_len(ind) / 3, each = nr)), 2), nr, ind)); names(ob) <- paste0("p", seq_len(ind))
  al <- c(0.05, 0.1, 0.2, 0.3)[(rep - 1) %% 4 + 1]
  res <- runin(arm::mcplot, list(), ob, alpha = al)
  for (i in 1:ind) {
    add("mcp", c(nr, ind, al, 0, as.vector(t(as.matrix(ob))), i - 1, 0), sum(1:ind * res$pvalue[i, ]), rel = 1e-12, abs = 1e-14)
    add("mcp", c(nr, ind, al, 1, as.vector(t(as.matrix(ob))), i - 1, 0), sum(1:ind * res$significant[i, ]), rel = 1e-12, abs = 1e-14)
  }
}
# balance
for (rep in 1:8) {
  n <- sample(30:50, 1); K <- sample(2:4, 1); x <- matrix(round(rnorm(n * K), 3), n, K); x[, 1] <- rbinom(n, 1, 0.5); colnames(x) <- paste0("c", seq_len(K))
  treat <- rbinom(n, 1, 0.45); treat[1:2] <- c(0, 1); wts <- ifelse(treat == 1, 1, sample(0:3, n, TRUE)); wts[which(treat == 0)[1]] <- 1
  est <- c("ATT", "ATC", "ATE")[(rep - 1) %% 3 + 1]
  r <- quiet(balance(x, treat, wts, estimand = est))
  for (i in 1:K) {
    add("balance", c(n, K, (rep - 1) %% 3, 0, treat, wts, as.vector(t(x)), i - 1, 0), sum(1:5 * r$diff.means.raw[i, ]), rel = 1e-10, abs = 1e-12)
    add("balance", c(n, K, (rep - 1) %% 3, 1, treat, wts, as.vector(t(x)), i - 1, 0), sum(1:5 * r$diff.means.matched[i, ]), rel = 1e-10, abs = 1e-12)
  }
  for (i in 1:K) add("balance", c(n, K, (rep - 1) %% 3, 2, treat, wts, as.vector(t(x)), i - 1, 0), r$binary[i], rel = 0, abs = 0)
}
# matching
for (rep in 1:14) {
  n <- sample(12:30, 1); z <- rbinom(n, 1, 0.4); z[1:2] <- c(1, 0); if (sum(z) > n / 2) z <- 1 - z; z[1:2] <- c(1, 0)
  sc <- if (rep %% 2) round(runif(n), 2) else round(runif(n), 6)
  mt <- matching(z, sc, replace = FALSE)
  pr <- mt$pairs; pr[is.na(pr)] <- 0
  add("matchn", c(n, 0, z, sc, 0), sum(1:n * mt$match.ind), rel = 0, abs = 0); add("matchn", c(n, 1, z, sc, 0), sum(1:n * mt$cnts), rel = 0, abs = 0)
  add("matchn", c(n, 2, z, sc, 0), sum(1:n * pr), rel = 0, abs = 0)
}
for (rep in 1:10) {
  n <- sample(12:30, 1); z <- rbinom(n, 1, 0.4); z[1:2] <- c(1, 0); sc <- if (rep %% 2) round(runif(n), 1) else round(runif(n), 6)
  sd0 <- sample(1:100000, 1); set.seed(sd0); mt <- matching(z, sc, replace = TRUE)
  nt <- sum(z); nc <- n - nt
  for (i in 1:nt) {
    add("matchr", c(sd0, n, 0, z, sc, i - 1, 0), sum(1:nc * mt$matches[i, ]), rel = 0, abs = 0)
    add("matchr", c(sd0, n, 2, z, sc, i - 1, 0), mt$match.ind[nt + i], rel = 0, abs = 0)
  }
  for (i in 1:n) add("matchr", c(sd0, n, 1, z, sc, i - 1, 0), mt$cnts[i], rel = 0, abs = 0)
}
# binnedplot
for (n in c(8, 10, 12, 40, 99, 100, 150)) {
  x <- round(runif(n), 4); y <- round(rnorm(n), 4); pl <- NULL; nl <- 0
  runin(arm::binnedplot, list(plot = function(x, y, ...) pl <<- c(x, y), lines = function(x, y, ...) nl <<- length(x)), x, y)
  for (i in 1:5) add("bpl", c(n, y, x, i - 1), c(pl, nl)[i], rel = 1e-10, abs = 1e-12)
}
emit("armextra", "arm", list(cases))
