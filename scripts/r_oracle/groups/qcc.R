# qcc: Shewhart charts, rules, cusum, ewma and process capability.
#   chart: (kind 0 xbar 1 R 2 S 3 xbar.one 10 p 11 np 12 c 13 u, ng, m, conf, method 0..4 or 9 for the package default, sd given or -1, data (ng by m row-major, NaN as -999),
#           sizes[ng] for the attribute kinds, j) j 0 center 1 std.dev 2 sum(stat) 3 position-weighted sum 4 lcl[1] 5 ucl[1] 6 sum(lcl) 7 sum(ucl) 8 #beyond 9 sum(beyond)
#           10 #runs 11 sum(runs) over the groups (a single-row limits matrix stands for every group)
#   cusum: (ng, m, head, di, shift, data, j) j 0 sum(pos) 1 sum(neg) 2 #upper 3 #lower;  ewma: (ng, m, lambda, nsigmas, data, j) j 0 sum(y) 1 sum(lcl) 2 sum(ucl) 3 #violations
#   capability: (ng, m, lsl, usl, target, conf, data, j) j 0..14 the Cp, Cp_l, Cp_u, Cp_k, Cpm rows of the table (value, low, high)
suppressMessages(library(qcc))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261124)
flat <- function(m) { v <- as.vector(t(m)); v[is.na(v)] <- -999; v }
methods <- c("UWAVE-R", "UWAVE-SD", "MVLUE-R", "MVLUE-SD", "RMSDF")
summ <- function(kind, ch, ng, a) {
  st <- as.numeric(ch$statistics); L <- ch$limits; if (nrow(L) == 1) L <- L[rep(1, ng), , drop = FALSE]
  bl <- beyond.limits(ch); vr <- violating.runs(ch)
  vals <- c(ch$center[1], if (length(ch$std.dev) == 1) ch$std.dev else ch$std.dev[1], sum(st), sum(seq_along(st) * st), L[1, 1], L[1, 2], sum(L[, 1]), sum(L[, 2]), length(bl), sum(bl), length(vr), sum(vr))
  for (j in 0:11) add("chart", c(a, j), vals[j + 1])
}
for (rep in 1:6) {
  ng <- c(20, 25, 30)[(rep - 1) %% 3 + 1]; m <- c(4, 5, 6)[(rep - 1) %% 3 + 1]
  X <- matrix(round(rnorm(ng * m, 10, 1.5), 2), ng, m); X[ng - 2, ] <- X[ng - 2, ] + 3; X[8:14, ] <- X[8:14, ] + 0.9
  Xm <- X; Xm[sample(length(Xm), 6)] <- NA; Xm[, 1][is.na(Xm[, 1])] <- 10   # unequal group sizes
  for (conf in c(3, 2.5, 0.99)) for (dat in list(X, Xm)) {
    unequal <- anyNA(dat)
    for (kind in 0:2) {
      if (kind == 1 && conf < 1) next
      for (me in (if (kind == 0) c(9, 0, 1, 2, 3, 4) else 9)) {
        sdp <- if (me == 9) NULL else methods[me + 1]
        ch <- tryCatch(suppressWarnings(if (is.null(sdp)) qcc(dat, type = c("xbar", "R", "S")[kind + 1], nsigmas = conf, plot = FALSE) else qcc(dat, type = c("xbar", "R", "S")[kind + 1], nsigmas = conf, std.dev = sdp, plot = FALSE)), error = function(e) NULL)
        if (is.null(ch)) next
        summ(kind, ch, ng, c(kind, ng, m, conf, me, -1, flat(dat)))
      }
    }
  }
  x1 <- round(rnorm(ng * 2, 50, 4), 2); x1[ng - 3] <- 75
  for (conf in c(3, 0.997)) for (me in 0:1) {
    ch <- suppressWarnings(qcc(x1, type = "xbar.one", nsigmas = conf, std.dev = c("MR", "SD")[me + 1], plot = FALSE))
    summ(3, ch, length(x1), c(3, length(x1), 1, conf, me, -1, x1))
  }
  sz <- sample(40:80, ng, TRUE); cnt <- rbinom(ng, sz, 0.1); cnt[3] <- cnt[3] + 14
  for (conf in c(3, 2, 0.99)) {
    ch <- suppressWarnings(qcc(cnt, sizes = sz, type = "p", nsigmas = conf, plot = FALSE)); summ(10, ch, ng, c(10, ng, 0, conf, 9, -1, cnt, sz))
    ch <- suppressWarnings(qcc(cnt, sizes = rep(60, ng), type = "np", nsigmas = conf, plot = FALSE)); summ(11, ch, ng, c(11, ng, 0, conf, 9, -1, cnt, rep(60, ng)))
    cc <- rpois(ng, 7); cc[5] <- 19; ch <- suppressWarnings(qcc(cc, sizes = rep(1, ng), type = "c", nsigmas = conf, plot = FALSE)); summ(12, ch, ng, c(12, ng, 0, conf, 9, -1, cc, rep(1, ng)))
    uu <- rpois(ng, 3 * sz / 10); ch <- suppressWarnings(qcc(uu, sizes = sz / 10, type = "u", nsigmas = conf, plot = FALSE)); summ(13, ch, ng, c(13, ng, 0, conf, 9, -1, uu, sz / 10))
  }
  q <- qcc(X, type = "xbar", plot = FALSE)
  for (hs in c(0, 1)) for (sh in c(1, 0.5)) {
    cu <- cusum(X, head.start = hs, se.shift = sh, plot = FALSE); a <- c(ng, m, hs, 5, sh, flat(X))
    add("cusum", c(a, 0), sum(cu$pos)); add("cusum", c(a, 1), sum(cu$neg)); add("cusum", c(a, 2), length(cu$violations$upper)); add("cusum", c(a, 3), length(cu$violations$lower))
  }
  for (la in c(0.2, 0.4)) for (ns in c(3, 2)) {
    ew <- ewma(X, lambda = la, nsigmas = ns, plot = FALSE); a <- c(ng, m, la, ns, flat(X))
    add("ewma", c(a, 0), sum(ew$y)); add("ewma", c(a, 1), sum(ew$limits[, 1])); add("ewma", c(a, 2), sum(ew$limits[, 2])); add("ewma", c(a, 3), length(ew$violations))
  }
  pc <- tryCatch({ pdf(NULL); r <- process.capability(q, spec.limits = c(6, 14), target = 10.3, confidence.level = 0.9, add.stats = FALSE); dev.off(); r }, error = function(e) NULL)
  if (!is.null(pc)) {
    tb <- pc$indices; vals <- as.vector(t(tb))
    for (j in 0:14) add("capability", c(ng, m, 6, 14, 10.3, 0.9, flat(X), j), vals[j + 1])
  }
}
#   pareto: (n, data, col, j) j 0 sum 1 position-weighted sum of the column col of the table (Frequency, Cum.Freq., Percentage, Cum.Percent.)
for (rep in 1:5) {
  nn <- c(5, 8, 12, 6, 9)[rep]; fr <- sample(1:60, nn, TRUE)
  tb <- unclass(pareto.chart(fr, plot = FALSE))
  for (col in 1:4) { v <- as.numeric(tb[, col]); add("pareto", c(nn, fr, col - 1, 0), sum(v)); add("pareto", c(nn, fr, col - 1, 1), sum(seq_along(v) * v)) }
}
emit("qcc", "qcc", list(cases))
