# metaformv2: metafor rma.mv, the rest of it (lib/e/algo/stat/metaformv2.e; metaformv.R is the first half).
#   A case is fn "rmamv2" with args = [reml, test (0 z, 1 t, 2 knha, 3 adhoc), optimizer (0 Nelder-Mead, 1 BFGS), k, p, ns, gk, hk, vmode, hasa, maxit, cvvc (0 none, 1 natural scale, 2 transf,
#   3 varcov), dfs (0 residual, 1 numeric, 2 contain), dfsval, dist method G, dist method H, y, X, V, [A], ids, sigma2 fixed, then the G and H terms (see the header of metaformv2.e)].
#   Its want is sigma2[1]; the cases after it, fn "o", are values of the result vector at an index (layout in the header of metaformv2.e: 0 sigma2, 8 tau2, 16 rho, 24 gamma2, 32 phi, 40 beta,
#   48 se, 56 zval, 64 pval, 72 ci.lb, 80 ci.ub, 88 vb, 104 QE, 105 QEp, 106 QM, 107 QMp, 108 ll ML, 109 ll REML, 110 .. 117 dev AIC BIC AICc (ML, REML), 118 parms, 121 s2w, 122 QM df2,
#   124 order of vvc, 125 vvc, 270 ddf). Nelder-Mead and BFGS are R's optim; every case is compared to 1e-7 except the Hessian based vvc.
suppressMessages(library(metafor))
cases <- list()
put <- function(v, i, x) { v[[as.character(i)]] <- if (is.null(x) || length(x) == 0) NA_real_ else as.numeric(x)[1]; v }
add_vec <- function(args, vals, rel, abs, vvc_rel) {
  idx <- as.integer(names(vals))
  cases[[length(cases) + 1]] <<- case("rmamv2", args, vals[[1]], rel = rel, abs = abs)
  if (length(vals) > 1) for (j in 2:length(vals)) {
    isv <- idx[j] >= 124 && idx[j] < 270
    cases[[length(cases) + 1]] <<- case("o", idx[j], vals[[j]], rel = if (isv) vvc_rel else rel, abs = if (isv) 1e-5 else abs)
  }
}
codes <- c(CS = 1, HCS = 2, DIAG = 3, ID = 4, AR = 5, HAR = 6, UN = 7, CAR = 8, SPEXP = 9, SPGAU = 10, SPLIN = 11, SPRAT = 12, SPSPH = 13, GEN = 14, GDIAG = 15)
sps <- c("SPEXP", "SPGAU", "SPLIN", "SPRAT", "SPSPH")
set.seed(20269911)
gen <- function(nstudy) {
  study <- rep(seq_len(nstudy), times = sample(2:3, nstudy, replace = TRUE))
  k <- length(study)
  outcome <- unlist(lapply(table(study), function(n) sample(1:3, n)))
  vi <- round(runif(k, 0.02, 0.2), 4)
  x <- round(rnorm(k), 3)
  u <- rnorm(nstudy, 0, 0.3)[study]
  yi <- round(0.2 + 0.3 * x + u + rnorm(k, 0, sqrt(vi + 0.04)), 4)
  data.frame(study = study, outcome = factor(outcome), esid = seq_len(k), yi = yi, vi = vi, x = x,
             t1 = round(runif(k, 0, 4), 2), t2 = round(runif(k, 0, 4), 2), tm = c(1, 2, 3.5)[outcome], loc = factor(letters[outcome + 3 * (study %% 2)]),
             cluster = (study + 1) %/% 2, item = factor(sample(1:3, k, replace = TRUE)), w = round(runif(k, 0.5, 2), 3))
}
dmat <- as.matrix(dist(cbind(c(0, 1.1, 2.3, 3.0, 4.2, 5.5), c(0, 0.7, 0.2, 1.5, 0.9, 2.2)))); dimnames(dmat) <- list(letters[1:6], letters[1:6])
# a term: struct, inner (a variable or the coordinate columns), outer, dmethod (0 euclidean, 1 maximum, 2 manhattan, 3 matrix)
tm <- function(struct, inner = "outcome", outer = "study", dist = "euclidean") list(struct = struct, inner = inner, outer = outer, dist = dist)
formula_of <- function(t) {
  if (t$struct == "GDIAG") return(as.formula(paste("~", t$inner, "||", t$outer)))
  as.formula(paste("~", paste(t$inner, collapse = " + "), "|", t$outer))
}
dcode <- function(t) if (is.matrix(t$dist)) 3 else match(t$dist, c("euclidean", "maximum", "manhattan")) - 1
block <- function(d, t, r, g) {
  outer <- as.numeric(factor(d[[t$outer]]))
  if (t$struct %in% sps) {
    b <- if (is.matrix(t$dist)) c(outer, as.vector(t(t$dist[as.character(d[[t$inner]]), as.character(d[[t$inner]])]))) else { C <- as.matrix(d[, t$inner, drop = FALSE]); c(outer, ncol(C), as.vector(t(C))) }
  } else if (t$struct %in% c("GEN", "GDIAG")) {
    Z <- model.matrix(as.formula(paste("~", t$inner)), d)
    b <- c(outer, ncol(Z), as.vector(t(Z)), rep(0, ncol(Z)))
  } else {
    f <- factor(d[[t$inner]])
    Z <- model.matrix(~ 0 + f)
    vals <- if (t$struct == "CAR") sort(unique(round(d[[t$inner]], 8))) else rep(0, nlevels(f))
    b <- c(outer, ncol(Z), as.vector(t(Z)), vals)
  }
  fx <- function(fixed, val) ifelse(fixed, val, 99)
  if (g) c(b, fx(r$vc.fix$tau2, r$tau2), fx(r$vc.fix$rho, r$rho)) else c(b, fx(r$vc.fix$gamma2, r$gamma2), fx(r$vc.fix$phi, r$phi))
}
# cfg: reml, test, oc, s (random intercept variables), G, H (terms or NULL), mods, vfull, A (use weights), cvvc (0 none, 1 TRUE, 2 transf, 3 varcov), dfs ("residual", a number or "contain"), fixed (list of sigma2, tau2, rho, gamma2, phi), maxit
one <- function(d, reml = TRUE, test = "z", oc = 0, s = character(0), G = NULL, H = NULL, mods = FALSE, vfull = FALSE, A = FALSE, cvvc = 0, dfs = "residual", fixed = list(), maxit = 0) {
  k <- nrow(d)
  rand <- list()
  for (t in s) rand[[length(rand) + 1]] <- as.formula(paste("~ 1 |", t))
  if (!is.null(G)) rand[[length(rand) + 1]] <- formula_of(G)
  if (!is.null(H)) rand[[length(rand) + 1]] <- formula_of(H)
  V <- d$vi
  if (vfull) { V <- diag(d$vi); for (st in unique(d$study)) { ix <- which(d$study == st); for (i in ix) for (j in ix) if (i != j) V[i, j] <- 0.4 * sqrt(d$vi[i] * d$vi[j]) } }
  args <- list(yi = d$yi, V = V, random = rand, data = d, method = if (reml) "REML" else "ML", test = test, dfs = dfs)
  if (mods) args$mods <- ~ x
  if (!is.null(G)) args$struct <- if (is.null(H)) G$struct else c(G$struct, H$struct)
  if (!is.null(G) && any(G$struct %in% sps) || !is.null(H) && H$struct %in% sps) {
    dl <- list(if (!is.null(G) && G$struct %in% sps) G$dist else "euclidean", if (!is.null(H) && H$struct %in% sps) H$dist else "euclidean")
    args$dist <- dl
  }
  ctrl <- list(optimizer = c("Nelder-Mead", "BFGS")[oc + 1])
  if (maxit > 0) ctrl$maxit <- maxit
  args$control <- ctrl
  if (cvvc == 1) args$cvvc <- TRUE
  if (cvvc == 2) args$cvvc <- "transf"
  if (cvvc == 3) args$cvvc <- "varcov"
  if (A) args$W <- d$w
  for (nm in names(fixed)) args[[nm]] <- fixed[[nm]]
  r <- tryCatch(suppressWarnings(do.call(rma.mv, args)), error = function(e) NULL)
  if (is.null(r)) return(invisible())
  # the same fit with yi moved by 1e-12 .. 1e-10 relative: a case whose answer moves by more than 1e-6 is a flat ridge on which the path of Nelder-Mead is a coin flip (R itself lands on one
  # of two attractors 1.6e-4 apart), not a case to compare
  if (!is.null(G) && G$struct %in% sps && r$rho[1] > 1000) return(invisible())
  est <- function(x) c(x$sigma2, x$tau2, x$rho, x$gamma2, x$phi, x$beta)
  vvc_ok <- cvvc > 0 && is.matrix(r$vvc)
  for (eps in c(1e-13, 3e-13, 1e-12, 3e-12, 1e-11, 3e-11, 1e-10)) {
    args2 <- args
    args2$yi <- d$yi * (1 + eps)
    r2 <- tryCatch(suppressWarnings(do.call(rma.mv, args2)), error = function(e) NULL)
    if (is.null(r2)) return(invisible())
    if (max(abs(est(r) - est(r2)) / pmax(abs(est(r)), 1e-3)) > 1e-6) return(invisible())
    if (vvc_ok) vvc_ok <- is.matrix(r2$vvc) && all(dim(r$vvc) == dim(r2$vvc)) && max(abs(r$vvc - r2$vvc) / max(abs(r$vvc))) < 1e-5
  }
  X <- if (mods) cbind(1, d$x) else matrix(1, k, 1)
  p <- ncol(X)
  ns <- length(s)
  ids <- unlist(lapply(s, function(t) as.numeric(factor(d[[t]]))))
  teff <- if (test == "z" && !identical(dfs, "residual")) "t" else test
  tcode <- match(teff, c("z", "t", "knha", "adhoc")) - 1
  dfsmode <- if (identical(dfs, "residual")) 0 else if (identical(dfs, "contain")) 2 else 1
  sfix <- if (ns > 0) ifelse(r$vc.fix$sigma2, r$sigma2, 99) else 99
  a <- c(as.integer(reml), tcode, oc, k, p, ns, if (is.null(G)) 0 else codes[[G$struct]], if (is.null(H)) 0 else codes[[H$struct]], as.integer(vfull), as.integer(A), maxit, cvvc, dfsmode,
         if (dfsmode == 1) dfs else 0, if (is.null(G)) 0 else dcode(G), if (is.null(H)) 0 else dcode(H), d$yi, as.vector(t(X)), if (vfull) as.vector(t(V)) else d$vi,
         if (A) as.vector(diag(d$w)) else NULL, ids, sfix, if (!is.null(G)) block(d, G, r, TRUE), if (!is.null(H)) block(d, H, r, FALSE))
  v <- list()
  v <- put(v, 0, if (ns > 0) r$sigma2[1] else NA_real_)
  for (j in seq_len(ns)) v <- put(v, j - 1, r$sigma2[j])
  if (!is.null(G)) { for (j in seq_along(r$tau2)) v <- put(v, 8 + j - 1, r$tau2[j]); for (j in seq_along(r$rho)) v <- put(v, 16 + j - 1, r$rho[j]) }
  if (!is.null(H)) { for (j in seq_along(r$gamma2)) v <- put(v, 24 + j - 1, r$gamma2[j]); for (j in seq_along(r$phi)) v <- put(v, 32 + j - 1, r$phi[j]) }
  for (j in 1:p) {
    v <- put(v, 40 + j - 1, r$beta[j]); v <- put(v, 48 + j - 1, r$se[j]); v <- put(v, 56 + j - 1, r$zval[j]); v <- put(v, 64 + j - 1, r$pval[j])
    v <- put(v, 72 + j - 1, r$ci.lb[j]); v <- put(v, 80 + j - 1, r$ci.ub[j])
    for (b in 1:p) v <- put(v, 88 + (j - 1) * p + b - 1, r$vb[j, b])
    if (tcode >= 1) v <- put(v, 270 + j - 1, r$ddf[j])
  }
  v <- put(v, 104, r$QE); v <- put(v, 105, r$QEp); v <- put(v, 106, r$QM); v <- put(v, 107, r$QMp)
  v <- put(v, 108, r$fit.stats["ll", "ML"]); v <- put(v, 109, r$fit.stats["ll", "REML"])
  fs <- r$fit.stats
  v <- put(v, 110, fs["dev", "ML"]); v <- put(v, 111, fs["AIC", "ML"]); v <- put(v, 112, fs["BIC", "ML"]); v <- put(v, 113, fs["AICc", "ML"])
  v <- put(v, 114, fs["dev", "REML"]); v <- put(v, 115, fs["AIC", "REML"]); v <- put(v, 116, fs["BIC", "REML"]); v <- put(v, 117, fs["AICc", "REML"])
  v <- put(v, 118, r$parms); v <- put(v, 121, r$s2w)
  if (tcode >= 1) v <- put(v, 122, r$QMdf[2])
  if (vvc_ok) {
    n <- nrow(r$vvc)
    v <- put(v, 124, n)
    for (i in seq_len(n)) for (j in seq_len(n)) v <- put(v, 125 + (i - 1) * n + j - 1, r$vvc[i, j])
  }
  v <- v[order(as.integer(names(v)))]
  add_vec(a, v, 1e-7, 1e-8, 1e-4)
}
suite <- function(d, oc) {
  # the Hessian based vvc on the structures of the first half
  one(d, TRUE, "z", oc, "study", cvvc = 1)
  one(d, TRUE, "z", oc, "study", mods = TRUE, cvvc = 2)
  one(d, FALSE, "z", oc, c("study", "esid"), mods = TRUE, cvvc = 1)
  one(d, TRUE, "z", oc, character(0), G = tm("CS"), mods = TRUE, cvvc = 1)
  one(d, TRUE, "z", oc, "study", G = tm("CS"), cvvc = 2)
  one(d, TRUE, "z", oc, character(0), G = tm("HAR"), cvvc = 1)
  one(d, TRUE, "z", oc, character(0), G = tm("DIAG"), cvvc = 1)
  one(d, TRUE, "z", oc, character(0), G = tm("ID"), cvvc = 2)
  one(d, FALSE, "z", oc, character(0), G = tm("AR"), mods = TRUE, cvvc = 1)
  # UN, CAR, GEN, GDIAG
  one(d, TRUE, "z", oc, character(0), G = tm("UN"), cvvc = 1)
  one(d, TRUE, "z", oc, character(0), G = tm("UN"), cvvc = 2)
  one(d, FALSE, "z", oc, character(0), G = tm("UN"), mods = TRUE, cvvc = 3)
  one(d, TRUE, "z", oc, "study", G = tm("UN"))
  one(d, TRUE, "z", oc, character(0), G = tm("CAR", "tm"), cvvc = 1)
  one(d, FALSE, "z", oc, "study", G = tm("CAR", "tm"), mods = TRUE)
  one(d, TRUE, "z", oc, character(0), G = tm("GEN", "x"), cvvc = 1)
  one(d, TRUE, "z", oc, character(0), G = tm("GEN", "x"), cvvc = 3)
  one(d, TRUE, "z", oc, character(0), G = tm("GDIAG", "x"), cvvc = 1)
  # spatial
  for (sp in sps) {
    one(d, TRUE, "z", oc, character(0), G = tm(sp, c("t1", "t2")), cvvc = 1)
    one(d, FALSE, "z", oc, character(0), G = tm(sp, c("t1", "t2")), mods = TRUE)
  }
  one(d, TRUE, "z", oc, character(0), G = tm("SPEXP", c("t1", "t2"), dist = "manhattan"))
  one(d, TRUE, "z", oc, character(0), G = tm("SPGAU", c("t1", "t2"), dist = "maximum"))
  one(d, TRUE, "z", oc, character(0), G = tm("SPEXP", "loc", dist = dmat), cvvc = 1)
  # the second term
  one(d, TRUE, "z", oc, character(0), G = tm("CS"), H = tm("CS", "item", "cluster"), maxit = 5000, cvvc = 1)
  one(d, TRUE, "z", oc, "study", G = tm("HCS"), H = tm("ID", "item", "cluster"), maxit = 5000)
  one(d, TRUE, "z", oc, character(0), G = tm("UN"), H = tm("DIAG", "item", "cluster"), maxit = 5000)
  one(d, TRUE, "z", oc, character(0), G = tm("AR"), H = tm("HAR", "item", "cluster"), maxit = 5000)
  one(d, TRUE, "z", oc, character(0), G = tm("DIAG"), H = tm("UN", "item", "cluster"), maxit = 5000)
  one(d, TRUE, "z", oc, character(0), G = tm("SPEXP", c("t1", "t2")), H = tm("CS", "item", "cluster"), maxit = 5000)
  one(d, TRUE, "z", oc, character(0), G = tm("CS"), H = tm("SPGAU", c("t1", "t2"), "cluster"), maxit = 5000)
  # weights, tests, full V
  one(d, TRUE, "z", oc, "study", mods = TRUE, A = TRUE)
  one(d, TRUE, "z", oc, character(0), G = tm("CS"), mods = TRUE, A = TRUE)
  one(d, TRUE, "knha", oc, "study", mods = TRUE)
  one(d, TRUE, "adhoc", oc, "study", mods = TRUE)
  one(d, TRUE, "knha", oc, "study", G = tm("CS"), mods = TRUE, A = TRUE)
  one(d, TRUE, "t", oc, "study", mods = TRUE)
  one(d, TRUE, "z", oc, "study", mods = TRUE, dfs = 7)
  one(d, TRUE, "t", oc, c("study", "esid"), mods = TRUE, dfs = "contain")
  one(d, TRUE, "z", oc, "study", G = tm("CS"), mods = TRUE, dfs = "contain")
  one(d, TRUE, "knha", oc, "study", mods = TRUE, dfs = "contain")
  one(d, TRUE, "z", oc, "study", mods = TRUE, vfull = TRUE, A = TRUE, cvvc = 1)
  # fixed variance components
  one(d, TRUE, "z", oc, c("study", "esid"), mods = TRUE, fixed = list(sigma2 = c(0.03, NA)))
  one(d, TRUE, "z", oc, "study", G = tm("CS"), fixed = list(rho = 0.3), cvvc = 1)
  one(d, TRUE, "z", oc, "study", G = tm("HCS"), fixed = list(tau2 = c(0.05, NA, NA)))
  one(d, FALSE, "z", oc, character(0), G = tm("UN"), fixed = list(tau2 = c(NA, 0.05, NA)))
  one(d, TRUE, "z", oc, "study", fixed = list(sigma2 = 0.04))
}
# every component fixed: nothing is optimised, the case is the log-likelihood and its derived values at a given point of the parameters
fixed_suite <- function(d) {
  one(d, FALSE, "z", 0, c("study", "esid"), mods = TRUE, fixed = list(sigma2 = c(0.0375617, 1.9e-9)))
  one(d, TRUE, "z", 0, c("study", "esid"), mods = TRUE, fixed = list(sigma2 = c(0.05, 0.02)), cvvc = 0)
  one(d, TRUE, "z", 0, "study", G = tm("CS"), fixed = list(sigma2 = 0.03, tau2 = 0.2, rho = 0.3))
  one(d, FALSE, "z", 0, character(0), G = tm("HCS"), mods = TRUE, fixed = list(tau2 = c(0.2, 0.1, 0.3), rho = -0.2))
  one(d, TRUE, "z", 0, character(0), G = tm("HAR"), fixed = list(tau2 = c(0.2, 0.1, 0.3), rho = 0.4))
  one(d, TRUE, "z", 0, character(0), G = tm("UN"), fixed = list(tau2 = c(0.2, 0.1, 0.3), rho = c(0.3, -0.2, 0.1)))
  one(d, FALSE, "z", 0, "study", G = tm("UN"), mods = TRUE, fixed = list(sigma2 = 0.02, tau2 = c(0.2, 0.1, 0.3), rho = c(0.3, -0.2, 0.1)))
  one(d, TRUE, "z", 0, character(0), G = tm("CAR", "tm"), fixed = list(tau2 = 0.2, rho = 0.4))
  one(d, TRUE, "z", 0, character(0), G = tm("GEN", "x"), fixed = list(tau2 = c(0.2, 0.1), rho = 0.3))
  one(d, TRUE, "z", 0, character(0), G = tm("GDIAG", "x"), fixed = list(tau2 = c(0.2, 0.1)))
  one(d, TRUE, "z", 0, character(0), G = tm("SPEXP", c("t1", "t2")), fixed = list(tau2 = 0.2, rho = 1.3))
  one(d, FALSE, "z", 0, character(0), G = tm("SPGAU", c("t1", "t2")), fixed = list(tau2 = 0.2, rho = 1.3))
  one(d, TRUE, "z", 0, character(0), G = tm("SPLIN", c("t1", "t2")), fixed = list(tau2 = 0.2, rho = 2.3))
  one(d, TRUE, "z", 0, character(0), G = tm("SPRAT", c("t1", "t2")), fixed = list(tau2 = 0.2, rho = 1.3))
  one(d, TRUE, "z", 0, character(0), G = tm("SPSPH", c("t1", "t2")), fixed = list(tau2 = 0.2, rho = 2.3))
  one(d, TRUE, "z", 0, character(0), G = tm("SPEXP", "loc", dist = dmat), fixed = list(tau2 = 0.2, rho = 1.3))
  one(d, TRUE, "z", 0, character(0), G = tm("CS"), H = tm("CS", "item", "cluster"), fixed = list(tau2 = 0.2, rho = 0.3, gamma2 = 0.1, phi = 0.2))
  one(d, TRUE, "z", 0, "study", G = tm("UN"), H = tm("HCS", "item", "cluster"), fixed = list(sigma2 = 0.01, tau2 = c(0.2, 0.1, 0.3), rho = c(0.3, -0.2, 0.1), gamma2 = c(0.1, 0.2, 0.05), phi = 0.2))
  one(d, FALSE, "z", 0, character(0), G = tm("SPEXP", c("t1", "t2")), H = tm("UN", "item", "cluster"), fixed = list(tau2 = 0.2, rho = 1.3, gamma2 = c(0.1, 0.2, 0.05), phi = c(0.1, -0.1, 0.2)))
  one(d, TRUE, "knha", 0, "study", G = tm("CS"), mods = TRUE, A = TRUE, vfull = TRUE, fixed = list(sigma2 = 0.02, tau2 = 0.1, rho = 0.2))
}
for (rep in 1:2) try({
  d <- gen(sample(10:12, 1))
  for (oc in 0:1) suite(d, oc)
  fixed_suite(d)
}, silent = TRUE)
emit("metaformv2", "metafor", list(cases))
