# glmnet beyond the gaussian first group: cox (Breslow, Efron, strata, start-stop), multinomial, mgaussian, relax, exclude, bounds, cv.glmnet with weights, offsets
# and relax, automatic lambda sequences, predict types and glmnet at its default thresh. Most cases answer a checksum (the sum over every coefficient, or over a range of
# cvm, of weight(i) times its value, weight(i) = 1 + ((7 i) mod 13) / 13 for the 0-based position i) so that one case checks a whole fit.
# Common head of every case (the fixture parses it): (n, p, alpha, std, nl, hw, hb, ho, lambda[nl], vf[p]); for "fit", "lam" and "cv" then
# (fam, relax, gamma, efron, grouped, nc, hasExcl, hasStrata, hasStart), the response, exclude[p] when hasExcl, X[n p] column-major, w[n * hw], lower[p * hb], upper[p * hb], offset[n * ho * nc] and the query.
# fam: 0 binomial, 1 poisson, 2 gaussian, 3 cox, 4 multinomial, 5 mgaussian. The response is y[n] (cox: time, status, strata, start; multinomial: class 0-based; mgaussian: the n by nc matrix).
suppressMessages({library(glmnet); library(survival)})
# numbers are written with the fewest digits that read back to the same double, which keeps this golden small (the shared num() always writes 17)
.oldnum <- get("num", envir = globalenv())
assign("num", function(x) { if (is.na(x) || is.infinite(x)) return(.oldnum(x)); s15 <- sprintf("%.15g", x); if (as.numeric(s15) == x) s15 else sprintf("%.17g", x) }, envir = globalenv())
cases <- list()
only <- Sys.getenv("GLM_ONLY")
want_ <- function(s) !nzchar(only) || s %in% strsplit(only, ",")[[1]]
wfun <- function(i) 1 + ((i * 7) %% 13) / 13
ck <- function(v) sum(wfun(seq_along(v) - 1) * v)
head_ <- function(n, p, al, std, lam, hw, hb, ho, vf) c(n, p, al, std, length(lam), hw, hb, ho, lam, vf)
famcode <- c(binomial = 0, poisson = 1, gaussian = 2, cox = 3, multinomial = 4, mgaussian = 5)

# a data set for a family: X, the response block, and what the glmnet call needs
mk <- function(fam, n, p, K = 3, ties = FALSE, strata = FALSE, start = FALSE) {
  X <- matrix(round(rnorm(n * p), 3), n, p); d <- list(fam = fam, n = n, p = p, X = X, K = K)
  if (fam == "gaussian") d$y <- round(X[, 1] * 2 - X[, 3] + rnorm(n), 3)
  if (fam == "binomial") d$y <- rbinom(n, 1, plogis(1.2 * X[, 1] - 0.8 * X[, 3]))
  if (fam == "poisson") d$y <- rpois(n, exp(0.5 + 0.5 * X[, 1] - 0.4 * X[, 3]))
  if (fam == "cox") {
    d$time <- round(rexp(n, exp(0.5 * X[, 1] - 0.5 * X[, 3])), if (ties) 1 else 2) + (if (ties) 0.1 else 0.01); d$status <- rbinom(n, 1, 0.8)
    d$strata <- if (strata) sample(1:2, n, TRUE) else numeric(0); d$start <- if (start) round(runif(n, 0, 0.8) * d$time, 2) else numeric(0)
    if (start) d$start <- pmin(d$start, d$time - 0.01)
  }
  if (fam == "multinomial") { B <- matrix(round(rnorm(p * K), 1), p, K); pr <- exp(X %*% B * 0.8); pr <- pr / rowSums(pr); d$cl <- apply(pr, 1, function(r) sample(K, 1, prob = r)); while (min(tabulate(d$cl, K)) < 8) d$cl <- sample(K, n, TRUE) }
  if (fam == "mgaussian") d$Y <- round(X[, 1:2] %*% matrix(rnorm(2 * K), 2, K) + matrix(rnorm(n * K), n, K), 3)
  d
}
respblock <- function(d) switch(d$fam, cox = c(d$time, d$status, d$strata, d$start), multinomial = d$cl - 1, mgaussian = as.vector(d$Y), d$y)
# the glmnet call's arguments for a data set and options o (alpha, std, vf, w, off, lo, up, excl, efron, grouped)
gargs <- function(d, o) {
  y <- switch(d$fam, cox = { s <- if (length(d$start)) Surv(d$start, d$time, d$status) else Surv(d$time, d$status); if (length(d$strata)) stratifySurv(s, d$strata) else s },
              multinomial = factor(d$cl), mgaussian = d$Y, d$y)
  a0 <- list(x = d$X, y = y, family = d$fam, alpha = o$alpha, standardize = o$std, penalty.factor = o$vf)
  if (length(o$w)) a0$weights <- o$w; if (length(o$off)) a0$offset <- if (d$fam == "multinomial") matrix(o$off, d$n, d$K) else o$off
  if (length(o$lo)) { a0$lower.limits <- o$lo; a0$upper.limits <- o$up }; if (length(o$excl)) a0$exclude <- o$excl
  if (d$fam == "cox") a0$cox.ties <- if (isTRUE(o$efron)) "efron" else "breslow"
  if (d$fam == "multinomial") a0$type.multinomial <- if (isTRUE(o$grouped)) "grouped" else "ungrouped"
  a0
}
defopt <- function(d, ...) { o <- list(alpha = 1, std = TRUE, vf = rep(1, d$p), w = numeric(0), off = numeric(0), lo = numeric(0), up = numeric(0), excl = integer(0), efron = FALSE, grouped = FALSE, relax = NA); mo <- list(...); o[names(mo)] <- mo; o }
hdrv <- function(d, o) c(famcode[[d$fam]], !is.na(o$relax), if (is.na(o$relax)) 0 else o$relax, isTRUE(o$efron), isTRUE(o$grouped), if (d$fam == "multinomial") d$K else if (d$fam == "mgaussian") ncol(d$Y) else 1, length(o$excl) > 0, length(d$strata) > 0, length(d$start) > 0)
exclmask <- function(d, o) if (length(o$excl)) as.numeric(seq_len(d$p) %in% o$excl) else numeric(0)
mkcase <- function(nm, d, o, lam, qy, want, rel, abs) {
  hd <- head_(d$n, d$p, o$alpha, o$std, lam, length(o$w) > 0, length(o$lo) > 0, length(o$off) > 0, o$vf)
  r <- case(nm, c(hd, hdrv(d, o), respblock(d), exclmask(d, o), d$X, o$w, o$lo, o$up, o$off, qy), want, rel = rel, abs = abs); r$tag <- .v; r
}
.v <- 0
# the coefficient vector of a fit (or its relaxed blend) in the fixture's order: lambda, class, then intercept and slopes
cvec <- function(f, d, lam, gamma = NA) {
  cf <- if (is.na(gamma)) coef(f) else coef(f, s = lam, gamma = gamma)
  if (d$fam %in% c("multinomial", "mgaussian")) return(unlist(lapply(seq_along(lam), function(k) unlist(lapply(cf, function(z) as.numeric(as.matrix(z)[, k]))))))
  m <- as.matrix(cf); if (d$fam == "cox") m <- rbind(0, m); as.numeric(m)
}
pickl <- function(a0, d) { f0 <- suppressWarnings(do.call(glmnet, a0)); L <- length(f0$lambda); list(L = L, lam = f0$lambda[unique(round(seq(2, L, length.out = 6)))], f0 = f0) }
# one coefficient case: the fit at thresh 1e-14 (or the default thresh when thresh7) over six lambdas of the default path
addfit <- function(d, o, rel = 1e-5, abs = 1e-5, thresh7 = FALSE, nm = "fit") {
  a0 <- gargs(d, o); pl <- pickl(a0, d); lam <- pl$lam
  a1 <- a0; a1$lambda <- lam; if (!thresh7) a1$thresh <- 1e-14; if (!is.na(o$relax)) a1$relax <- TRUE
  f <- suppressWarnings(do.call(glmnet, a1))
  if (nzchar(Sys.getenv("GLM_DEBUG")) && isTRUE(o$relax == 0)) message("R relaxed k=3: ", paste(signif(cvec(f, d, lam, 0), 5), collapse = " "))
  cases[[length(cases) + 1]] <<- mkcase(nm, d, o, lam, 0, ck(cvec(f, d, lam, o$relax)), rel, abs)
}

# ---- fit: Cox -------------------------------------------------------------------------------------------------------------------------------------------------------------
if (want_("cox")) { set.seed(20261201)
  for (v in 1:12) {
    .v <- v
    d <- mk("cox", 50, 4, ties = v %in% c(5, 6, 7, 8), strata = v %in% c(7, 10), start = v %in% c(8, 11)); p <- d$p
    o <- defopt(d, alpha = c(1, 0.5, 0.2)[(v %% 3) + 1], std = v != 4)
    if (v == 2) o$w <- round(runif(d$n, 0.3, 3), 2); if (v == 3) o$off <- round(rnorm(d$n, 0, 0.4), 2); if (v == 4) { o$lo <- round(-runif(p, 0, 1), 2); o$up <- round(runif(p, 0, 1), 2) }
    if (v == 9) o$excl <- c(2, 4); if (v == 12) o$relax <- 0.5
    if (v %in% c(5, 6, 7, 8)) o$efron <- TRUE
    if (v == 6) o$w <- round(runif(d$n, 0.3, 3), 2)
    if (v == 1) o$vf <- round(runif(p, 0.3, 2), 2)
    addfit(d, o)
    # the automatic path: its checksum and length
    a0 <- gargs(d, o); f0 <- suppressWarnings(do.call(glmnet, a0))
    if (nzchar(Sys.getenv("GLM_DEBUG"))) { dv <- f0$dev.ratio; L <- length(dv); a2 <- a0; a2$thresh <- 1e-14; f2 <- suppressWarnings(do.call(glmnet, a2)); L2 <- length(f2$lambda); message("cox v ", v, " L ", L, " L(1e-14) ", L2, " rule at L-3..L: ", paste(signif((dv[(L-3):L] - dv[(L-7):(L-4)])/dv[(L-3):L], 4), collapse = " ")) }
    cases[[length(cases) + 1]] <- mkcase("lam", d, o, numeric(0), 0, ck(f0$lambda), 1e-9, 1e-12); cases[[length(cases) + 1]] <- mkcase("lam", d, o, numeric(0), 1, length(f0$lambda), 0, 0.5)
  } }

# ---- fit: multinomial -------------------------------------------------------------------------------------------------------------------------------------------------------
if (want_("mult")) { set.seed(20261202)
  for (v in 1:11) {
    .v <- v
    d <- mk("multinomial", 70, 4, K = if (v == 8) 4 else 3)
    okm <- TRUE
    if (v >= 10) for (try_ in 1:300) {   # relaxed multinomial: keep a data set only when glmnet's own relaxed fit sits at the lasso limit (median class at zero), see below
      o <- defopt(d, alpha = c(1, 0.5, 0.2)[(v %% 3) + 1], std = v != 4); a1 <- gargs(d, o); pl <- pickl(a1, d); a1$lambda <- pl$lam; a1$thresh <- 1e-14; a1$relax <- TRUE; f <- suppressWarnings(do.call(glmnet, a1))
      okm <- all(sapply(seq_along(pl$lam), function(k) { b <- sapply(f$relaxed$beta, function(z) as.matrix(z)[, k]); act <- rowSums(abs(b)) > 0; !any(act) || max(abs(apply(b[act, , drop = FALSE], 1, median))) < 1e-6 }))
      if (okm) break; d <- mk("multinomial", 70, 4, K = 3)
    }
    if (!okm) next
    p <- d$p; o <- defopt(d, alpha = c(1, 0.5, 0.2)[(v %% 3) + 1], std = v != 4, grouped = v %in% c(5, 9))
    if (v == 2) o$w <- round(runif(d$n, 0.3, 3), 2); if (v == 3) o$off <- round(rnorm(d$n * d$K, 0, 0.3), 2); if (v == 4) { o$lo <- round(-runif(p, 0, 1), 2); o$up <- round(runif(p, 0, 1), 2) }
    if (v == 6) o$excl <- c(1, 3); if (v == 7) o$grouped <- FALSE; if (v == 1) o$vf <- round(runif(p, 0.3, 2), 2)
    if (v == 8) { o$alpha <- 0.5 }
    if (v == 5) o$w <- round(runif(d$n, 0.3, 3), 2)
    # relaxed multinomial fits: the answer of glmnet is flat along one added vector per variable and it settles on the lasso limit (the median class at zero) on most data sets but not all, so only these two are compared
    if (v == 10) { o$relax <- 0; o$grouped <- FALSE }; if (v == 11) { o$relax <- 0.5; o$grouped <- FALSE }
    addfit(d, o, rel = 1e-4, abs = 1e-4)
    a0 <- gargs(d, o); f0 <- suppressWarnings(do.call(glmnet, a0)); a1 <- a0; a1$thresh <- 1e-14; f1 <- suppressWarnings(do.call(glmnet, a1))
    if (!(isTRUE(o$grouped) && length(o$w))) {
    cases[[length(cases) + 1]] <- mkcase("lam", d, o, numeric(0), 0, ck(f1$lambda), 1e-9, 1e-12)
    cases[[length(cases) + 1]] <- mkcase("lam", d, o, numeric(0), 1, length(f1$lambda), 0, 0.5)   # at thresh 1e-14 the length is exact
    if (!length(o$w)) cases[[length(cases) + 1]] <- mkcase("lam", d, o, numeric(0), 1, length(f0$lambda), 0, 1.5)    # at the default thresh glmnet's own noise can move it by one (by several with weights: skipped)
    }
  } }

# ---- glmnet's own multinomial algorithm (ported from its C++ source) at the DEFAULT thresh: coefficients over six lambdas, and the automatic path's lambdas and length --------------------
if (want_("gmn")) { set.seed(20261301)
  for (v in 1:10) {
    .v <- v
    d <- mk("multinomial", 70, 4, K = if (v == 8) 4 else 3); p <- d$p; o <- defopt(d, alpha = c(1, 0.5, 0.2)[(v %% 3) + 1], std = v != 4)
    if (v == 2) o$w <- round(runif(d$n, 0.3, 3), 2); if (v == 3) o$off <- round(rnorm(d$n * d$K, 0, 0.3), 2); if (v == 4) { o$lo <- round(-runif(p, 0, 1), 2); o$up <- round(runif(p, 0, 1), 2) }
    if (v == 5) o$excl <- c(1, 3); if (v == 1) o$vf <- round(runif(p, 0.3, 2), 2); if (v == 7) o$w <- round(runif(d$n, 0.3, 3), 2)
    if (v >= 6) o$grouped <- TRUE
    if (v == 9) { o$lo <- round(-runif(p, 0, 1), 2); o$up <- round(runif(p, 0, 1), 2) }
    addfit(d, o, rel = 1e-6, abs = 1e-6, thresh7 = TRUE, nm = "gfit")
    if (v != 5) { f0 <- suppressWarnings(do.call(glmnet, gargs(d, o)))
      cases[[length(cases) + 1]] <- mkcase("glam", d, o, numeric(0), 1, length(f0$lambda), 0, 0.5); cases[[length(cases) + 1]] <- mkcase("glam", d, o, numeric(0), 0, ck(f0$lambda), 1e-9, 1e-12) }
  } }

if (want_("gbp")) { set.seed(20261302)
  for (fam in c("binomial", "poisson")) for (v in 1:6) {
    .v <- v
    d <- mk(fam, 80, 5); p <- d$p; o <- defopt(d, alpha = c(1, 0.5, 0.2)[(v %% 3) + 1], std = v != 4)
    if (v == 2) o$w <- round(runif(d$n, 0.3, 3), 2); if (v == 3) o$off <- round(rnorm(d$n, 0, 0.3), 2); if (v == 4) { o$lo <- round(-runif(p, 0, 1), 2); o$up <- round(runif(p, 0, 1), 2) }
    if (v == 5) { o$excl <- c(2, 4); o$vf <- round(runif(p, 0.3, 2), 2) }; if (v == 6) { o$w <- round(runif(d$n, 0.3, 3), 2); o$off <- round(rnorm(d$n, 0, 0.3), 2) }
    addfit(d, o, rel = 1e-6, abs = 1e-6, thresh7 = TRUE, nm = "gfit")
    if (v != 5) { f0 <- suppressWarnings(do.call(glmnet, gargs(d, o)))
      cases[[length(cases) + 1]] <- mkcase("glam", d, o, numeric(0), 1, length(f0$lambda), 0, 0.5); cases[[length(cases) + 1]] <- mkcase("glam", d, o, numeric(0), 0, ck(f0$lambda), 1e-9, 1e-12) }
  } }

# ---- fit: mgaussian ---------------------------------------------------------------------------------------------------------------------------------------------------------
if (want_("mgauss")) { set.seed(20261203)
  for (v in 1:6) {
    d <- mk("mgaussian", 60, 4, K = if (v == 5) 3 else 2); p <- d$p; o <- defopt(d, alpha = c(1, 0.5, 0.2)[(v %% 3) + 1], std = v != 4)
    if (v == 2) o$w <- round(runif(d$n, 0.3, 3), 2); if (v == 3) { o$lo <- round(-runif(p, 0, 1), 2); o$up <- round(runif(p, 0, 1), 2) }; if (v == 4) o$excl <- c(2, 3)
    if (v == 5) o$relax <- 0.5; if (v == 6) o$vf <- round(runif(p, 0.3, 2), 2)
    addfit(d, o, rel = 1e-4, abs = 1e-4)
  } }

# ---- fit: gaussian, binomial, poisson with bounds, exclude and relax -----------------------------------------------------------------------------------------------------
if (want_("glm")) { set.seed(20261204)
  for (fam in c("gaussian", "binomial", "poisson")) for (v in 1:5) {
    d <- mk(fam, 60, 5); p <- d$p; o <- defopt(d, alpha = c(1, 0.5, 0.2, 0.9, 1)[v], std = v != 3)
    if (v == 1) { o$lo <- round(-runif(p, 0, 1), 2); o$up <- round(runif(p, 0, 1), 2) }; if (v == 2) o$excl <- c(2, 5); if (v == 3) { o$relax <- 0; if (fam == "gaussian") o$w <- round(runif(d$n, 0.3, 3), 2) }
    if (v == 4) { o$relax <- 0.5; o$off <- round(rnorm(d$n, 0, 0.3), 2) }; if (v == 5) { o$vf <- round(runif(p, 0.3, 2), 2); o$excl <- c(1, 3); o$w <- round(runif(d$n, 0.3, 3), 2) }
    addfit(d, o)
    a0 <- gargs(d, o); f0 <- suppressWarnings(do.call(glmnet, a0)); a2 <- a0; a2$thresh <- 1e-14; f2 <- suppressWarnings(do.call(glmnet, a2))
    if (v %in% c(3, 4)) { cases[[length(cases) + 1]] <- mkcase("lam", d, o, numeric(0), 0, ck(f2$lambda), 1e-9, 1e-12); cases[[length(cases) + 1]] <- mkcase("lam", d, o, numeric(0), 1, length(f2$lambda), 0, 0.5)
      cases[[length(cases) + 1]] <- mkcase("lam", d, o, numeric(0), 1, length(f0$lambda), 0, 1.5) }   # at the default thresh glmnet's own noise can move the length by one
  } }

# ---- the default thresh: glmnet stops a lambda once the objective gains less than 1e-7 of the null deviance, which leaves its coefficients near 1e-4 from the minimiser --------------
if (want_("thresh7")) { set.seed(20261205)
  for (fam in c("gaussian", "binomial", "poisson", "cox", "multinomial", "mgaussian")) for (v in 1:2) {
    d <- mk(fam, 70, 5); o <- defopt(d, alpha = c(1, 0.4)[v]); addfit(d, o, rel = 2e-3, abs = 2e-3, thresh7 = TRUE)
  } }

# ---- cv.glmnet: weights, offsets, relax, the default lambda --------------------------------------------------------------------------------------------------------------------
# data of "cv": hdr, response, X, ..., query = (which, kfrom, nfolds, measure, auto, foldid[n] 0-based, gamma index); which 0 mean cvm, 1 mean cvsd over k = kfrom .. (the end; less the last lambda when auto), 2 lambda.min, 3 lambda.1se, 4 length, 5 gamma.min, 6 relaxed lambda.min
addcv <- function(d, o, ms, au, relax = FALSE, nf = 4) {
  a0 <- gargs(d, o); n <- d$n; fid <- sample(rep(1:nf, length.out = n)); fam <- d$fam
  tmn <- if (fam == "cox") c("deviance", "C")[ms + 1] else if (fam == "gaussian") c("deviance", "class", "mse", "mae")[ms + 1] else c("deviance", "class", "mse", "mae", "auc")[ms + 1]
  if (fam == "gaussian") tmn <- c("mse", "mse", "mse", "mae")[ms + 1]
  if (fam == "cox" && ms == 0) tmn <- "deviance"
  cargs <- c(a0, list(foldid = fid, type.measure = tmn, relax = relax))
  if (!au) { pl <- pickl(a0, d); cargs$lambda <- pl$lam; cargs$control <- list(thresh = 1e-14); lam <- pl$lam } else lam <- numeric(0)
  cv <- suppressWarnings(do.call(cv.glmnet, cargs)); L <- length(cv$lambda); kfrom <- if (au) max(1, L %/% 3) else 1
  if (au && (ms == 1 || (fam == "binomial" && ms == 4))) kfrom <- max(1, L %/% 2)
  kend <- if (au) L - 1 else L; ks <- kfrom:kend
  wm <- function(v) sum(wfun(ks - 1) * v[ks]) / sum(wfun(ks - 1))
  hd <- o; hd$relax <- if (relax) 0 else NA
  noisy <- au && (ms == 1 || (fam == "binomial" && ms == 4)); tol <- function(a, b) if (au) a else b
  q <- function(w, k, want, rel, abs, gi = 4) cases[[length(cases) + 1]] <<- mkcase("cv", d, hd, lam, c(w, k - 1, nf, ms, au, fid - 1, gi), want, rel, abs)
  cm <- if (relax) cv$relaxed$statlist[["g:0.5"]]$cvm else cv$cvm; cs <- if (relax) cv$relaxed$statlist[["g:0.5"]]$cvsd else cv$cvsd
  gi <- if (relax) 2 else 4
  if (au) q(4, 1, L, 0, 1.5)
  # glmnet does not pass its thresh on to the refits of relax = TRUE, so a relaxed cross-validation carries its default-thresh noise
  q(0, kfrom, wm(cm), if (noisy) 0 else if (relax) 5e-4 else tol(if (fam == "multinomial") 3e-3 else 5e-4, 1e-4), if (noisy) 0.04 else 1e-6, gi); q(1, kfrom, wm(cs), if (noisy) 0 else if (relax) 2e-2 else tol(2e-2, 1e-3), if (noisy) 0.05 else 1e-6, gi)
  if (!au) { q(2, 1, cv$lambda.min, 1e-9, 1e-12); q(3, 1, cv$lambda.1se, 1e-9, 1e-12) }
  if (relax && !au) { q(5, 1, cv$relaxed$gamma.min, 0, 1e-9); q(6, 1, cv$relaxed$lambda.min, 1e-9, 1e-12) }
}
if (want_("cv")) { set.seed(20261206)
  for (fam in c("gaussian", "binomial", "poisson", "cox")) for (v in 1:4) {
    d <- mk(fam, 60, 4); p <- d$p; o <- defopt(d, alpha = c(1, 0.5, 0.2, 0.9)[v], std = v != 3)
    ms <- if (fam == "gaussian") c(0, 2, 3, 0)[v] else if (fam == "binomial") c(0, 1, 4, 2)[v] else if (fam == "poisson") c(0, 2, 3, 0)[v] else c(0, 1, 0, 1)[v]
    if (v == 2) o$w <- round(runif(d$n, 0.3, 3), 2); if (v == 3 && fam != "gaussian") o$off <- round(rnorm(d$n, 0, 0.3), 2); if (v == 3 && fam == "gaussian") o$off <- round(rnorm(d$n, 0, 0.3), 2)
    if (v == 4) { o$w <- round(runif(d$n, 0.3, 3), 2); o$off <- round(rnorm(d$n, 0, 0.3), 2) }
    if (fam == "binomial" && ms == 4) o$w <- numeric(0)
    addcv(d, o, ms, au = FALSE)
    addcv(d, o, ms, au = TRUE)
    if (v %in% c(1, 4)) addcv(d, o, if (fam == "binomial") 0 else ms, au = FALSE, relax = TRUE)
  } }
if (want_("cvm")) { set.seed(20261207)
  for (v in 1:5) {
    d <- mk("multinomial", 70, 4); p <- d$p; o <- defopt(d, alpha = c(1, 0.5, 0.2, 0.9, 1)[v], std = v != 3, grouped = v == 5)
    if (v == 2) o$w <- round(runif(d$n, 0.3, 3), 2); if (v == 4) o$off <- round(rnorm(d$n * 3, 0, 0.3), 2)
    ms <- c(0, 1, 2, 3, 0)[v]
    addcv(d, o, ms, au = FALSE); if (v != 5) addcv(d, o, ms, au = TRUE)
    if (v == 1) addcv(d, o, 0, au = FALSE, relax = TRUE)
  } }

# ---- nlambda and lambda.min.ratio (gaussian): "lseq" data = y[n], X; query = (nlambda, ratio, the number of lambdas R reports) ---------------------------------------------------
if (want_("lseq")) { set.seed(20261208)
  for (rep in 1:6) {
    n <- sample(50:80, 1); p <- sample(3:6, 1); X <- matrix(round(rnorm(n * p), 3), n, p); y <- round(X[, 1] * 2 - X[, 3] + rnorm(n), 3)
    alpha <- c(1, 0.5, 0.2)[(rep %% 3) + 1]; std <- rep %% 2 == 0; nl <- sample(c(10, 20, 50, 100), 1); ratio <- sample(c(0.5, 0.1, 0.01, 0.001), 1)
    f <- suppressWarnings(glmnet(X, y, alpha = alpha, standardize = std, nlambda = nl, lambda.min.ratio = ratio))
    cases[[length(cases) + 1]] <- case("lseq", c(head_(n, p, alpha, std, numeric(0), 0, 0, 0, rep(1, p)), y, X, nl, ratio, length(f$lambda)), ck(f$lambda), rel = 1e-9, abs = 1e-12)
  } }

# ---- predict types, from the coefficients R reports at one lambda: "prd" data = (family, nc, rows[nc (p + 1)]), newx, offset, query = type -------------------------------------
if (want_("predict")) { set.seed(20261209)
  for (fam in c("gaussian", "binomial", "poisson", "cox", "multinomial")) for (rep in 1:2) {
    d <- mk(fam, 80, 4); m <- 6; NX <- matrix(round(rnorm(m * d$p), 3), m, d$p); K <- 3
    ho <- rep == 2 && fam %in% c("gaussian", "binomial", "poisson"); off <- round(rnorm(80, 0, 0.3), 2); noff <- round(rnorm(m, 0, 0.3), 2)
    o <- defopt(d, alpha = 0.7); if (ho) o$off <- off
    f <- suppressWarnings(do.call(glmnet, gargs(d, o))); s <- f$lambda[10]
    cfl <- coef(f, s = s); rows <- if (fam == "multinomial") unlist(lapply(cfl, function(z) as.numeric(as.matrix(z)))) else { v <- as.numeric(as.matrix(cfl)); if (fam == "cox") c(0, v) else v }
    nc <- if (fam == "multinomial") K else 1
    pr <- function(type) if (ho) predict(f, NX, s = s, type = type, newoffset = noff) else predict(f, NX, s = s, type = type)
    for (kd in 0:3) {
      if ((kd == 2 && !(fam %in% c("binomial", "multinomial"))) || (kd == 1 && fam == "cox")) next
      if (kd == 3) { nz <- predict(f, NX, s = s, type = "nonzero"); nzl <- if (fam == "multinomial") lapply(nz, function(z) z[[1]]) else list(nz[[1]]); v <- unlist(lapply(nzl, function(z) c(length(z), as.numeric(z)))) }
      else { v <- pr(c("link", "response", "class")[kd + 1]); v <- if (kd == 2) as.numeric(v) else as.numeric(v) }
      cases[[length(cases) + 1]] <- case("prd", c(head_(m, d$p, 0.7, 1, numeric(0), 0, 0, ho, rep(1, d$p)), famcode[[fam]], nc, rows, NX, if (ho) noff else numeric(0), kd), ck(v), rel = 1e-9, abs = 1e-12)
    }
  } }

if (nzchar(Sys.getenv("GLM_V"))) cases <- Filter(function(z) identical(as.character(z$tag), Sys.getenv("GLM_V")), cases)
emit("glmnet_ext", "glmnet", list(cases))
assign("num", .oldnum, envir = globalenv())
