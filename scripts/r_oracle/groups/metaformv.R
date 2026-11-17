# metaformv: metafor rma.mv (lib/e/algo/stat/metaformv.e).
#   A case is fn "rmamv" with args = [reml, test (0 z, 1 t), optimizer (0 Nelder-Mead, 1 BFGS, 2 the default nlminb, answered by a tight BFGS), k, p, ns (random intercepts), gk (structure of an
#   inner | outer term: 0 none 1 CS 2 HCS 3 DIAG 4 ID 5 AR 6 HAR), nin (inner levels), vmode (0 vi, 1 full V), yi (k), X (k * p, row-major), V (k or k * k), ids (ns * k), inner (k), outer (k)].
#   Its want is sigma2[1] (or tau2[1]); the cases after it, fn "o", are values of the result vector at an index: 0.. sigma2, 8.. tau2, 16 rho, 24 beta, 32 se, 40 zval, 48 pval, 56 ci.lb, 64 ci.ub,
#   72 vb (row-major p x p), 136 QE, 137 QEp, 138 QM, 139 QMp, 140 and 141 the log-likelihood (ML and REML). Nelder-Mead and BFGS are R's optim and are compared to 1e-7; the default
#   optimizer (nlminb) is not ported and its cases are compared to 1e-4, which is the optimizer's own tolerance.
suppressMessages(library(metafor))
cases <- list()
put <- function(v, i, x) { v[[as.character(i)]] <- if (is.null(x) || length(x) == 0) NA_real_ else as.numeric(x)[1]; v }
add_vec <- function(args, vals, rel, abs) {
  idx <- as.integer(names(vals))
  cases[[length(cases) + 1]] <<- case("rmamv", args, vals[[1]], rel = rel, abs = abs)
  if (length(vals) > 1) for (j in 2:length(vals)) cases[[length(cases) + 1]] <<- case("o", idx[j], vals[[j]], rel = rel, abs = abs)
}
set.seed(20263131)
gen <- function(nstudy, ncl) {
  study <- rep(seq_len(nstudy), times = sample(2:3, nstudy, replace = TRUE))
  k <- length(study)
  outcome <- unlist(lapply(table(study), function(n) sample(seq_len(ncl), n)))
  vi <- round(runif(k, 0.02, 0.2), 4)
  x <- round(rnorm(k), 3)
  u <- rnorm(nstudy, 0, 0.3)[study]
  yi <- round(0.2 + 0.3 * x + u + rnorm(k, 0, sqrt(vi + 0.04)), 4)
  data.frame(study = study, outcome = factor(outcome), esid = seq_len(k), yi = yi, vi = vi, x = x)
}
one <- function(d, reml, test, optim_code, ns_terms, struct, mods, vfull = FALSE) {
  k <- nrow(d)
  rand <- list()
  for (t in ns_terms) rand[[length(rand) + 1]] <- as.formula(paste("~ 1 |", t))
  gk <- c(CS = 1, HCS = 2, DIAG = 3, ID = 4, AR = 5, HAR = 6)[struct]
  if (is.na(gk)) gk <- 0
  if (gk > 0) rand[[length(rand) + 1]] <- ~ outcome | study
  V <- d$vi
  if (vfull) { V <- diag(d$vi); for (s in unique(d$study)) { ix <- which(d$study == s); for (i in ix) for (j in ix) if (i != j) V[i, j] <- 0.4 * sqrt(d$vi[i] * d$vi[j]) } }
  args <- list(yi = d$yi, V = V, random = rand, data = d, method = if (reml) "REML" else "ML", test = c("z", "t")[test + 1])
  if (mods) args$mods <- ~ x
  if (gk > 0) args$struct <- struct
  args$control <- list(optimizer = c("Nelder-Mead", "BFGS", "nlminb")[optim_code + 1])
  if (optim_code == 2) args$control <- list()
  r <- tryCatch(suppressWarnings(do.call(rma.mv, args)), error = function(e) NULL)
  if (is.null(r)) return(invisible())
  X <- if (mods) cbind(1, d$x) else matrix(1, k, 1)
  p <- ncol(X)
  ids <- unlist(lapply(ns_terms, function(t) as.numeric(factor(d[[t]]))))
  nin <- if (gk > 0) nlevels(d$outcome) else 0
  inner <- if (gk > 0) as.integer(d$outcome) - 1 else rep(0, k)
  outer <- if (gk > 0) d$study else rep(1, k)
  a <- c(as.integer(reml), test, optim_code, k, p, length(ns_terms), gk, nin, as.integer(vfull), d$yi, as.vector(t(X)), if (vfull) as.vector(t(V)) else d$vi, ids, inner, outer)
  v <- list()
  ns <- length(ns_terms)
  first <- if (ns > 0) r$sigma2[1] else NA_real_
  v <- put(v, 0, first)
  for (j in seq_len(ns)) v <- put(v, j - 1, r$sigma2[j])
  if (gk > 0) { for (j in seq_along(r$tau2)) v <- put(v, 8 + j - 1, r$tau2[j]); if (!is.null(r$rho) && length(r$rho)) v <- put(v, 16, r$rho[1]) }
  for (j in 1:p) { v <- put(v, 24 + j - 1, r$beta[j]); v <- put(v, 32 + j - 1, r$se[j]); v <- put(v, 40 + j - 1, r$zval[j]); v <- put(v, 48 + j - 1, r$pval[j]); v <- put(v, 56 + j - 1, r$ci.lb[j]); v <- put(v, 64 + j - 1, r$ci.ub[j])
    for (b in 1:p) v <- put(v, 72 + (j - 1) * p + b - 1, r$vb[j, b]) }
  v <- put(v, 136, r$QE); v <- put(v, 137, r$QEp); v <- put(v, 138, r$QM); v <- put(v, 139, r$QMp)
  v <- put(v, 140, r$fit.stats["ll", "ML"]); v <- put(v, 141, r$fit.stats["ll", "REML"])
  v <- v[order(as.integer(names(v)))]
  rel <- if (optim_code == 2) 1e-4 else 1e-7
  add_vec(a, v, rel, if (optim_code == 2) 1e-5 else 1e-8)
}
for (rep in 1:3) try({
  d <- gen(sample(10:14, 1), 3)
  for (oc in 0:2) {
    one(d, TRUE, 0, oc, "study", "none", FALSE)
    one(d, TRUE, 0, oc, "study", "none", TRUE)
    one(d, FALSE, 1, oc, c("study", "esid"), "none", TRUE)
    one(d, TRUE, 0, oc, character(0), "CS", TRUE)
    if (oc != 2) one(d, TRUE, 0, oc, "study", "CS", FALSE)
    if (oc != 2) one(d, TRUE, 0, oc, "study", "HCS", TRUE)
    one(d, TRUE, 0, oc, character(0), "DIAG", FALSE)
    one(d, FALSE, 0, oc, character(0), "ID", FALSE)
    one(d, TRUE, 0, oc, character(0), "AR", FALSE)
    one(d, TRUE, 0, oc, character(0), "HAR", FALSE)
    one(d, TRUE, 0, oc, "study", "none", TRUE, vfull = TRUE)
  }
}, silent = TRUE)
emit("metaformv", "metafor", list(cases))
