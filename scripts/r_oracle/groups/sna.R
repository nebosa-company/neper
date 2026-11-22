# sna indices of random digraphs.
#   args: (n, g[n*n] row-major, extras...); every answer is a position-weighted sum of the vector or matrix R returns (weights 1, 2, 3, ... in row-major order), or a scalar
#   fn: "outdeg" "indeg" "degree" "between" "stress" "closeness" "graphcent" "evcent" "gden" "cent_degree" "cent_between" "cent_closeness"
#       "dyad_m" "dyad_a" "dyad_n" "mutuality" "triad" "triad2" "connectedness" "hier_rec" "hier_krack"
#       "pr_indeg" "pr_rownorm" "pr_eigen" "pr_domain" "pr_prox" "infocent"
#       "sedist" (extras: method 0 correlation 1 euclidean 2 hamming 3 gamma 4 exact)
#       "eq_height" "eq_order" "eq_merge" (extras: sedist method, hclust method code 1 ward.D 2 single 3 complete 4 average 5 mcquitty 6 median 7 centroid 8 ward.D2)
#       "bm" "bm_order" "bm_member" (extras: sedist method, hclust method, k, content 0 density 1 sum 2 median 3 min 4 max 5 meanrowsum 6 meancolsum)
suppressMessages(library(sna))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
ws <- function(v) sum(as.vector(v) * seq_along(v))
rg <- function(n) { g <- matrix(rbinom(n * n, 1, runif(1, 0.12, 0.4)), n); diag(g) <- 0; if (sum(g) == 0) g[1, 2] <- 1; g }
hm <- c("ward.D", "single", "complete", "average", "mcquitty", "median", "centroid", "ward.D2")
sm <- c("correlation", "euclidean", "hamming", "gamma", "exact")
set.seed(20261229)
for (rep in 1:24) {
  n <- sample(5:20, 1); g <- rg(n)
  a <- c(n, as.vector(t(g)))
  add("outdeg", a, ws(degree(g, cmode = "outdegree"))); add("indeg", a, ws(degree(g, cmode = "indegree"))); add("degree", a, ws(degree(g)))
  add("between", a, ws(betweenness(g))); add("stress", a, ws(stresscent(g))); add("closeness", a, ws(closeness(g))); add("graphcent", a, ws(graphcent(g)))
  mv <- sort(Mod(eigen(g)$values), decreasing = TRUE)
  if (connectedness(g) == 1 && mv[1] - mv[2] > 1e-6) { ec <- evcent(g); if (all(is.finite(ec))) add("evcent", a, ws(ec)) }
  add("gden", a, gden(g)); add("cent_degree", a, centralization(g, degree)); add("cent_between", a, centralization(g, betweenness)); add("cent_closeness", a, centralization(g, closeness))
}
for (rep in 1:30) {
  n <- sample(6:16, 1); g <- rg(n); a <- c(n, as.vector(t(g)))
  dc <- dyad.census(g)
  add("dyad_m", a, dc[1]); add("dyad_a", a, dc[2]); add("dyad_n", a, dc[3]); add("mutuality", a, mutuality(g))
  tc <- as.vector(triad.census(g)); add("triad", a, ws(tc)); add("triad2", a, sum(tc * seq_along(tc)^2))
  add("connectedness", a, connectedness(g)); add("hier_rec", a, hierarchy(g))
  hk <- hierarchy(g, measure = "krackhardt"); if (is.finite(hk)) add("hier_krack", a, hk)
  add("pr_indeg", a, ws(prestige(g))); add("pr_rownorm", a, ws(prestige(g, cmode = "indegree.rownorm")))
  add("pr_domain", a, ws(prestige(g, cmode = "domain"))); add("pr_prox", a, ws(prestige(g, cmode = "domain.proximity")))
  mv <- sort(Mod(eigen(t(g))$values), decreasing = TRUE)
  if (connectedness(g) == 1 && mv[1] - mv[2] > 1e-6 && all(rowSums(g) > 0) && all(colSums(g) > 0)) {
    pe <- tryCatch(prestige(g, cmode = "eigenvector"), error = function(e) NULL)
    if (!is.null(pe) && all(is.finite(pe))) add("pr_eigen", a, ws(pe))
  }
  ic <- tryCatch(infocent(g), error = function(e) NULL)
  if (!is.null(ic) && all(is.finite(ic))) add("infocent", a, ws(ic))
  for (m in 0:4) {
    D <- tryCatch(sedist(g, method = sm[m + 1], joint.analysis = TRUE, code.diss = TRUE), error = function(e) NULL)
    if (!is.null(D) && all(is.finite(D))) add("sedist", c(a, m), ws(t(D)))
  }
  for (trial in 1:3) {
    m <- sample(c(0, 1, 2, 3), 1); h <- sample(1:8, 1)
    ec <- tryCatch(equiv.clust(g, method = sm[m + 1], cluster.method = hm[h]), error = function(e) NULL)
    if (is.null(ec) || !all(is.finite(ec$cluster$height))) next
    # correlations come from long-double sums in R: a merge decided by a tie or a gap under 1e-8 could go either way, so such inputs are not asked
    if (m == 0) { dv <- sort(as.vector(as.dist(sedist(g, method = "correlation", joint.analysis = TRUE, code.diss = TRUE)))); if (min(diff(dv)) < 1e-8) next }
    b <- c(a, m, h)
    add("eq_height", b, ws(ec$cluster$height)); add("eq_order", b, ws(ec$cluster$order)); add("eq_merge", b, ws(t(ec$cluster$merge)))
    k <- sample(2:min(4, n - 2), 1)
    for (ct in 0:6) {
      cn <- c("density", "sum", "median", "min", "max", "meanrowsum", "meancolsum")[ct + 1]
      bmo <- tryCatch(suppressWarnings(blockmodel(g, ec, k = k, block.content = cn)), error = function(e) NULL)
      if (is.null(bmo) || !all(is.finite(bmo$block.model))) next
      add("bm", c(b, k, ct), ws(t(bmo$block.model)))
      if (ct == 0) { add("bm_order", c(b, k, ct), ws(bmo$order.vector)); add("bm_member", c(b, k, ct), ws(bmo$block.membership)) }
    }
  }
}
# QAP regressions: netlm (kinds 0 t-value, 1 beta) and netlogit (2 z-value, 3 beta); the seed is set just before the call so the permutations are R's
nullh <- c("qap", "qapy", "qapx", "qapallx", "classical")
for (rep in 1:3) {
  n <- sample(8:10, 1); y <- rg(n)
  mk <- function(sig) { x <- matrix(rbinom(n * n, 1, 0.3), n); x[y == 1 & runif(n * n) < sig] <- 1; diag(x) <- 0; x }
  xs <- list(mk(0.4), matrix(round(rnorm(n * n), 3), n) + y * 0.8, mk(0.1))
  for (nx0 in c(1, 2, 3)) for (hyp in 0:4) for (kind in 0:3) {
    if (hyp == 4 && (kind == 1 || kind == 3)) next
    if (nx0 == 3 && rep > 1) next
    xl <- xs[seq_len(nx0)]; xarg <- if (nx0 == 1) xl[[1]] else simplify2array(xl) |> aperm(c(3, 1, 2))
    set.seed(4000 + rep * 100 + hyp * 10 + kind)
    w <- FALSE
    fit <- tryCatch(withCallingHandlers(
      if (kind <= 1) netlm(y, xarg, nullhyp = nullh[hyp + 1], test.statistic = c("t-value", "beta")[kind + 1], reps = 60)
      else netlogit(y, xarg, nullhyp = nullh[hyp + 1], test.statistic = c("z-value", "beta")[kind - 1], reps = 60),
      warning = function(cw) { w <<- TRUE; invokeRestart("muffleWarning") }), error = function(e) NULL)
    if (is.null(fit) || w || !all(is.finite(fit$tstat))) next
    if (!is.null(fit$dist)) {
      if (any(!is.finite(fit$dist))) next
      # qapx permutes the intercept column too, which changes nothing: that column's null distribution equals the statistic up to rounding, so its p-values are not asked
      tie <- FALSE; for (j in seq_along(fit$tstat)) if (!(hyp == 2 && j == 1) &&any(abs(fit$dist[, j] - fit$tstat[j]) < 1e-9 * (1 + abs(fit$tstat[j])))) tie <- TRUE
      if (tie) next
    }
    ext <- if (kind <= 1) sum(fit$residuals^2) + 100 * fit$df.residual else fit$deviance + 10 * fit$null.deviance + 100 * fit$df.residual
    a <- c(n, as.vector(t(y)), nx0, hyp, 60, kind, 4000 + rep * 100 + hyp * 10 + kind, unlist(lapply(xl, function(x) as.vector(t(x)))))
    add("net_coef", a, ws(fit$coefficients)); add("net_stat", a, ws(fit$tstat)); add("net_ext", a, ext)
    sel <- if (hyp == 2) -1 else seq_along(fit$pleeq)
    add("net_pleeq", a, ws(fit$pleeq[sel])); add("net_pgreq", a, ws(fit$pgreq[sel])); add("net_pgreqabs", a, ws(fit$pgreqabs[sel]))
  }
}
# qaptest with gcor and hdist
for (rep in 1:20) {
  n <- sample(6:12, 1); g1 <- rg(n); g2 <- rg(n); g2[g1 == 1 & runif(n * n) < 0.3] <- 1; diag(g2) <- 0
  for (fun in 0:1) {
    sd <- 9000 + rep * 10 + fun
    set.seed(sd)
    q <- qaptest(list(g1, g2), if (fun == 0) gcor else hdist, g1 = 1, g2 = 2, reps = 100)
    if (fun == 0 && any(abs(q$dist - q$testval) < 1e-9)) next
    a <- c(n, as.vector(t(g1)), as.vector(t(g2)), 100, fun, sd)
    add("qap_test", a, q$testval); add("qap_pgreq", a, q$pgreq); add("qap_pleeq", a, q$pleeq); add("qap_dist", a, ws(q$dist))
  }
}
emit("sna", "sna", list(cases))
