# glmnet beyond the first group: cox, multinomial, and the cv, relax and predict pieces.
# Common head of every case (the fixture parses it): (n, p, alpha, std, nl, hw, hb, ho, lambda[nl], vf[p]) then the family data,
# X[n p] column-major, w[n * hw], lower[p * hb], upper[p * hb], offset[n * ho * (cols)], and the query.
suppressMessages({library(glmnet); library(survival)})
cases <- list()
head_ <- function(n, p, al, std, lam, hw, hb, ho, vf) c(n, p, al, std, length(lam), hw, hb, ho, lam, vf)
cq <- function(fn, hd, dat, X, w, lo, up, off, qy, want, rel = 1e-5, abs = 1e-6) case(fn, c(hd, dat, X, w, lo, up, off, qy), want, rel = rel, abs = abs)
brk <- function() "breslow"

only <- Sys.getenv("GLM_ONLY")
want_ <- function(s) !nzchar(only) || s %in% strsplit(only, ",")[[1]]
# cox: data = (time[n], status[n]); query = (k, j); coefficient j (0-based, no intercept) at lambda k
set.seed(20261117)
for (rep in if (want_("cox")) 1:14 else integer(0)) {
  n <- sample(50:110, 1); p <- sample(3:6, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  tm <- round(rexp(n, exp(0.5 * X[, 1] - 0.5 * X[, 2])), 1) + 0.1; st <- rbinom(n, 1, 0.8)
  alpha <- c(1, 0.5, 0.2, 0.9, 0)[(rep %% 5) + 1]; std <- rep %% 3 != 0
  vf <- if (rep %% 4 == 0) round(runif(p, 0.3, 2), 2) else rep(1, p)
  hw <- as.integer(rep %% 5 == 1); w <- if (hw) round(runif(n, 0.3, 3), 2) else numeric(0)
  ho <- as.integer(rep %% 5 == 2); off <- if (ho) round(rnorm(n, 0, 0.4), 2) else numeric(0)
  hb <- as.integer(rep %% 5 == 3); lo <- if (hb) round(-runif(p, 0, 1), 2) else numeric(0); up <- if (hb) round(runif(p, 0, 1), 2) else numeric(0)
  y <- Surv(tm, st)
  a0 <- list(x = X, y = y, family = "cox", alpha = alpha, standardize = std, penalty.factor = vf, cox.ties = "breslow")
  if (hw) a0$weights <- w; if (ho) a0$offset <- off; if (hb) { a0$lower.limits <- lo; a0$upper.limits <- up }
  f0 <- suppressWarnings(do.call(glmnet, a0)); L <- length(f0$lambda)
  lam <- f0$lambda[unique(round(seq(1, L, length.out = 7)))]
  a1 <- a0; a1$lambda <- lam; a1$thresh <- 1e-14
  f <- suppressWarnings(do.call(glmnet, a1)); cf <- as.matrix(coef(f))
  hd <- head_(n, p, alpha, std, lam, hw, hb, ho, vf)
  for (k in c(2, 4, length(lam))) for (j in 1:p) cases[[length(cases) + 1]] <- cq("cox", hd, c(tm, st), X, w, lo, up, off, c(k - 1, j), cf[j, k])
  # the automatic path and its length
  cases[[length(cases) + 1]] <- cq("coxlen", hd, c(tm, st), X, w, lo, up, off, 0, L, rel = 0, abs = 0.5)
  for (k in c(1, 2, 7, L)) cases[[length(cases) + 1]] <- cq("coxlam", hd, c(tm, st), X, w, lo, up, off, k - 1, f0$lambda[k], rel = 1e-9, abs = 1e-12)
}

# multinomial: data = (class[n] 0-based, K, grouped); the offset (when ho) is the n by K matrix column-major; query = (k, c, j): class c's coefficient j (0 the intercept) at lambda k
set.seed(20261118)
for (rep in if (want_("mult") || want_("multlen")) 1:16 else integer(0)) {
  n <- sample(90:160, 1); p <- sample(3:5, 1); K <- sample(3:4, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  B <- matrix(round(rnorm(p * K), 1), p, K); eta <- X %*% B * 0.8; pr <- exp(eta) / rowSums(exp(eta))
  cl <- apply(pr, 1, function(r) sample(K, 1, prob = r)); while (min(tabulate(cl, K)) < 10) cl <- sample(K, n, TRUE)
  alpha <- c(1, 0.5, 0.2, 0.9, 0)[(rep %% 5) + 1]; std <- rep %% 3 != 0; grouped <- rep %% 4 == 3
  vf <- if (rep %% 4 == 0) round(runif(p, 0.3, 2), 2) else rep(1, p)
  hw <- as.integer(rep %% 5 == 1); w <- if (hw) round(runif(n, 0.3, 3), 2) else numeric(0)
  ho <- as.integer(rep %% 5 == 2 && !grouped); off <- if (ho) matrix(round(rnorm(n * K, 0, 0.3), 2), n, K) else matrix(0, 0, 0)
  hb <- as.integer(rep %% 5 == 3 && !grouped); lo <- if (hb) round(-runif(p, 0, 1), 2) else numeric(0); up <- if (hb) round(runif(p, 0, 1), 2) else numeric(0)
  a0 <- list(x = X, y = factor(cl), family = "multinomial", alpha = alpha, standardize = std, penalty.factor = vf, type.multinomial = if (grouped) "grouped" else "ungrouped")
  if (hw) a0$weights <- w; if (ho) a0$offset <- off; if (hb) { a0$lower.limits <- lo; a0$upper.limits <- up }
  f0 <- suppressWarnings(do.call(glmnet, a0)); L <- length(f0$lambda)
  lam <- f0$lambda[unique(round(seq(2, L, length.out = 6)))]
  a1 <- a0; a1$lambda <- lam; a1$thresh <- 1e-14
  f <- suppressWarnings(do.call(glmnet, a1)); cf <- coef(f)
  hd <- head_(n, p, alpha, std, lam, hw, hb, ho, vf)
  if (want_("mult")) for (k in c(2, length(lam))) for (c in unique(c(1, K))) for (j in 0:p) cases[[length(cases) + 1]] <- cq("mult", hd, c(cl - 1, K, grouped), X, w, lo, up, off, c(k - 1, c - 1, j), as.matrix(cf[[c]])[j + 1, k], rel = 1e-5, abs = 1e-6)
  hd0 <- head_(n, p, alpha, std, numeric(0), hw, hb, ho, vf)
  if (nzchar(Sys.getenv("GLM_DEBUG"))) message("mult rep ", rep, " n ", n, " alpha ", alpha, " hw ", hw, " ho ", ho, " hb ", hb, " grouped ", grouped, " L ", L)
  if (!grouped && want_("multlen")) cases[[length(cases) + 1]] <- cq("multlen", hd0, c(cl - 1, K, grouped), X, w, lo, up, off, 0, L, rel = 0, abs = 1.5)  # glmnet stops at thresh 1e-7, so a step whose gain is within its noise of the 1e-5 limit can fall either side: one lambda
  if (want_("multlen")) for (k in c(1, 2, 5, L)) cases[[length(cases) + 1]] <- cq("multlam", hd0, c(cl - 1, K, grouped), X, w, lo, up, off, k - 1, f0$lambda[k], rel = 1e-9, abs = 1e-12)
}

# binomial and poisson: data = (y[n]); the automatic path (binlam / poislam, query = k) and its length (binlen / poislen)
set.seed(20261119)
for (fam in c("binomial", "poisson")) for (rep in 1:12) {
  if (!want_("glm")) break
  n <- sample(60:150, 1); p <- sample(3:6, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  y <- if (fam == "binomial") rbinom(n, 1, plogis(1.2 * X[, 1] - 0.8 * X[, 2])) else rpois(n, exp(0.5 + 0.5 * X[, 1] - 0.4 * X[, 2]))
  alpha <- c(1, 0.5, 0.2, 0.9, 0.05)[(rep %% 5) + 1]; std <- rep %% 3 != 0
  vf <- if (rep %% 4 == 0) round(runif(p, 0.3, 2), 2) else rep(1, p)
  hw <- as.integer(rep %% 5 == 1); w <- if (hw) round(runif(n, 0.3, 3), 2) else numeric(0)
  ho <- as.integer(rep %% 5 == 2); off <- if (ho) round(rnorm(n, 0, 0.4), 2) else numeric(0)
  a0 <- list(x = X, y = y, family = fam, alpha = alpha, standardize = std, penalty.factor = vf)
  if (hw) a0$weights <- w; if (ho) a0$offset <- off
  f0 <- suppressWarnings(do.call(glmnet, a0)); L <- length(f0$lambda)
  hd0 <- head_(n, p, alpha, std, numeric(0), hw, 0, ho, vf); nm <- if (fam == "binomial") "bin" else "pois"
  cases[[length(cases) + 1]] <- cq(paste0(nm, "len"), hd0, y, X, w, numeric(0), numeric(0), off, 0, L, rel = 0, abs = 0.5)
  for (k in c(1, 2, 5, L)) cases[[length(cases) + 1]] <- cq(paste0(nm, "lam"), hd0, y, X, w, numeric(0), numeric(0), off, k - 1, f0$lambda[k], rel = 1e-9, abs = 1e-12)
}

# cv.glmnet with the default lambda (every fold finds its own automatic sequence and is read at the full fit's lambdas by interpolation): data = (y[n], foldid[n] 0-based, nfolds, measure)
set.seed(20261120)
for (fam in c("gaussian", "binomial", "poisson")) for (rep in 1:10) {
  if (!want_("cvauto")) break
  n <- sample(70:140, 1); p <- sample(3:6, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  y <- switch(fam, gaussian = round(X[, 1] * 2 - X[, 2] + rnorm(n), 3), binomial = rbinom(n, 1, plogis(1.2 * X[, 1] - 0.8 * X[, 2])), poisson = rpois(n, exp(0.5 + 0.5 * X[, 1] - 0.4 * X[, 2])))
  alpha <- c(1, 0.5, 0.2, 0.9, 0.05)[(rep %% 5) + 1]; std <- rep %% 3 != 0; nf <- sample(3:7, 1); fid <- sample(rep(1:nf, length.out = n))
  vf <- if (rep %% 4 == 0) round(runif(p, 0.3, 2), 2) else rep(1, p)
  ms <- if (fam == "gaussian") 0 else sample(if (fam == "binomial") c(0, 1, 2, 3) else c(0, 2, 3), 1)
  tm <- if (fam == "gaussian") "deviance" else c("deviance", "class", "mse", "mae")[ms + 1]
  cv <- suppressWarnings(cv.glmnet(X, y, family = fam, alpha = alpha, standardize = std, penalty.factor = vf, foldid = fid, type.measure = tm)); L <- length(cv$lambda)
  nm <- c(gaussian = "cvgA", binomial = "cvbA", poisson = "cvpA")[[fam]]; hd0 <- head_(n, p, alpha, std, numeric(0), 0, 0, 0, vf)
  dat <- c(y, fid - 1, nf, ms)
  cases[[length(cases) + 1]] <- cq(nm, hd0, dat, X, numeric(0), numeric(0), numeric(0), numeric(0), c(0, 4), L, rel = 0, abs = 0.5)
  for (k in unique(c(1, L %/% 2, L))) {
    cases[[length(cases) + 1]] <- cq(nm, hd0, dat, X, numeric(0), numeric(0), numeric(0), numeric(0), c(k - 1, 0), cv$cvm[k], rel = 1e-4, abs = 1e-7)
    cases[[length(cases) + 1]] <- cq(nm, hd0, dat, X, numeric(0), numeric(0), numeric(0), numeric(0), c(k - 1, 1), cv$cvsd[k], rel = 1e-3, abs = 1e-7)
  }
  cases[[length(cases) + 1]] <- cq(nm, hd0, dat, X, numeric(0), numeric(0), numeric(0), numeric(0), c(0, 2), cv$lambda.min, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- cq(nm, hd0, dat, X, numeric(0), numeric(0), numeric(0), numeric(0), c(0, 3), cv$lambda.1se, rel = 1e-9, abs = 1e-12)
}

# cv.glmnet for the multinomial family: data = (class[n] 0-based, K, grouped, foldid[n] 0-based, nfolds, measure, auto); measure 0 deviance 1 class 2 mse 3 mae. Sections "cvmult" (ungrouped) and "cvmultg" (grouped, the slow one)
set.seed(20261121)
for (rep in 1:8) {
  n <- sample(90:150, 1); p <- sample(3:5, 1); K <- sample(3:4, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  B <- matrix(round(rnorm(p * K), 1), p, K); eta <- X %*% B * 0.8; pr <- exp(eta) / rowSums(exp(eta))
  cl <- apply(pr, 1, function(r) sample(K, 1, prob = r)); while (min(tabulate(cl, K)) < 12) cl <- sample(K, n, TRUE)
  alpha <- c(1, 0.5, 0.2, 0.9)[(rep %% 4) + 1]; std <- rep %% 3 != 0; grouped <- rep %% 4 == 3; nf <- sample(3:5, 1); fid <- sample(rep(1:nf, length.out = n))
  vf <- rep(1, p); ms <- (rep - 1) %% 4; tm <- c("deviance", "class", "mse", "mae")[ms + 1]; tmu <- if (grouped) "grouped" else "ungrouped"
  if (!want_(if (grouped) "cvmultg" else "cvmult")) next
  for (au in c(0, 1)) {
    a0 <- list(x = X, y = factor(cl), family = "multinomial", alpha = alpha, standardize = std, foldid = fid, type.measure = tm, type.multinomial = tmu)
    if (!au) { f0 <- suppressWarnings(glmnet(X, factor(cl), family = "multinomial", alpha = alpha, standardize = std, type.multinomial = tmu)); lam <- f0$lambda[unique(round(seq(2, length(f0$lambda), length.out = 6)))]; a0$lambda <- lam; a0$thresh <- 1e-14 } else lam <- numeric(0)
    cv <- suppressWarnings(do.call(cv.glmnet, a0)); L <- length(cv$lambda)
    hd0 <- head_(n, p, alpha, std, lam, 0, 0, 0, vf); dat <- c(cl - 1, K, grouped, fid - 1, nf, ms, au)
    qq <- function(k, w, want, rel, abs) cases[[length(cases) + 1]] <<- cq("cvmult", hd0, dat, X, numeric(0), numeric(0), numeric(0), numeric(0), c(k, w), want, rel = rel, abs = abs)
    # with its default lambda, glmnet's thresh leaves the near-null first fits with class probabilities that differ in the last places, and the misclassification count (a step function) follows: the class measure is compared from the middle of the path on, within four observations; the last lambda is taken one short of the end so that a path length one off (see multlen) cannot leave the index out of range
    mid <- L %/% 2
    if (au) {
      qq(0, 4, L, 0, 1.5)
      if (ms == 1) { qq(mid - 1, 0, cv$cvm[mid], 0, 4 / n); qq(mid - 1, 1, cv$cvsd[mid], 0, 0.05) }
      else { qq(mid - 1, 0, cv$cvm[mid], 5e-4, 1e-6); qq(mid - 1, 1, cv$cvsd[mid], 5e-3, 1e-6); qq(L - 2, 0, cv$cvm[L - 1], 5e-4, 1e-6) }
    } else {
      if (ms != 1) qq(0, 0, cv$cvm[1], 1e-5, 1e-6)  # the class measure at the near-null first lambda turns on classes whose fitted probabilities differ by less than the fit can tell
      qq(mid - 1, 0, cv$cvm[mid], 1e-5, 1e-6); qq(mid - 1, 1, cv$cvsd[mid], 1e-4, 1e-6)
      qq(0, 2, cv$lambda.min, 1e-9, 1e-12); qq(0, 3, cv$lambda.1se, 1e-9, 1e-12)
    }
  }
}

# cv.glmnet for the Cox family: data = (time[n], status[n], foldid[n] 0-based, nfolds, measure 0 deviance 1 C, auto)
set.seed(20261122)
for (rep in if (want_("cvcox")) 1:8 else integer(0)) {
  n <- sample(80:140, 1); p <- sample(3:5, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  tm <- round(rexp(n, exp(0.5 * X[, 1] - 0.5 * X[, 2])), 2) + 0.01; st <- rbinom(n, 1, 0.8)
  alpha <- c(1, 0.5, 0.2, 0.9)[(rep %% 4) + 1]; std <- rep %% 3 != 0; nf <- sample(3:5, 1); fid <- sample(rep(1:nf, length.out = n)); vf <- rep(1, p)
  ms <- (rep - 1) %% 2; tmn <- c("deviance", "C")[ms + 1]
  for (au in c(0, 1)) {
    a0 <- list(x = X, y = Surv(tm, st), family = "cox", alpha = alpha, standardize = std, foldid = fid, type.measure = tmn, cox.ties = "breslow")
    if (!au) { f0 <- suppressWarnings(glmnet(X, Surv(tm, st), family = "cox", alpha = alpha, standardize = std, cox.ties = "breslow")); lam <- f0$lambda[unique(round(seq(2, length(f0$lambda), length.out = 6)))]; a0$lambda <- lam; a0$thresh <- 1e-14 } else lam <- numeric(0)
    cv <- suppressWarnings(do.call(cv.glmnet, a0)); L <- length(cv$lambda)
    hd0 <- head_(n, p, alpha, std, lam, 0, 0, 0, vf); dat <- c(tm, st, fid - 1, nf, ms, au)
    if (au) cases[[length(cases) + 1]] <- cq("cvcox", hd0, dat, X, numeric(0), numeric(0), numeric(0), numeric(0), c(0, 4), L, rel = 0, abs = 0.5)
    # the C-index ranks the linear predictors, and glmnet's thresh of 1e-7 leaves near-null coefficient vectors (the first lambdas) with a direction error that reorders them: with its default lambda only the middle and last lambdas are compared, at the looser tolerance
    for (k in if (au && ms == 1) unique(c(L %/% 2, L - 1)) else if (au) unique(c(1, L %/% 2, L - 1)) else unique(c(1, L %/% 2, L))) {
      cases[[length(cases) + 1]] <- cq("cvcox", hd0, dat, X, numeric(0), numeric(0), numeric(0), numeric(0), c(k - 1, 0), cv$cvm[k], rel = if (au && ms == 1) 5e-3 else if (au) 1e-4 else 1e-5, abs = 1e-6)
      cases[[length(cases) + 1]] <- cq("cvcox", hd0, dat, X, numeric(0), numeric(0), numeric(0), numeric(0), c(k - 1, 1), cv$cvsd[k], rel = if (au && ms == 1) 0.15 else if (au) 2e-3 else 1e-4, abs = if (au && ms == 1) 5e-3 else 1e-6)
    }
    if (!au) {
      cases[[length(cases) + 1]] <- cq("cvcox", hd0, dat, X, numeric(0), numeric(0), numeric(0), numeric(0), c(0, 2), cv$lambda.min, rel = 1e-9, abs = 1e-12)
      cases[[length(cases) + 1]] <- cq("cvcox", hd0, dat, X, numeric(0), numeric(0), numeric(0), numeric(0), c(0, 3), cv$lambda.1se, rel = 1e-9, abs = 1e-12)
    }
  }
}

# exclude (gaussian "excg", binomial "excb"): data = (y[n], exclude[p] 0/1); query = (k, j); and the box constraints for binomial "binb" / poisson "poisb" (lower and upper in the bounds slots)
set.seed(20261123)
for (fam in c("gaussian", "binomial", "poisson")) for (rep in if (want_("exclude")) 1:8 else integer(0)) {
  n <- sample(60:120, 1); p <- sample(4:7, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  y <- switch(fam, gaussian = round(X[, 1] * 2 - X[, 3] + rnorm(n), 3), binomial = rbinom(n, 1, plogis(1.2 * X[, 1] - 0.8 * X[, 3])), poisson = rpois(n, exp(0.5 + 0.5 * X[, 1] - 0.4 * X[, 3])))
  alpha <- c(1, 0.5, 0.2, 0.9)[(rep %% 4) + 1]; std <- rep %% 3 != 0; vf <- if (rep %% 2 == 0) round(runif(p, 0.3, 2), 2) else rep(1, p)
  if (fam != "poisson") {
    ex <- sort(sample(2:p, sample(1:2, 1))); exv <- as.numeric(1:p %in% ex)
    f0 <- suppressWarnings(glmnet(X, y, family = fam, alpha = alpha, standardize = std, penalty.factor = vf, exclude = ex)); lam <- f0$lambda[unique(round(seq(2, length(f0$lambda), length.out = 5)))]
    f <- suppressWarnings(glmnet(X, y, family = fam, alpha = alpha, standardize = std, penalty.factor = vf, exclude = ex, lambda = lam, thresh = 1e-14)); cf <- as.matrix(coef(f))
    hd <- head_(n, p, alpha, std, lam, 0, 0, 0, vf)
    for (k in c(2, length(lam))) for (j in 0:p) cases[[length(cases) + 1]] <- cq(if (fam == "gaussian") "excg" else "excb", hd, c(y, exv), X, numeric(0), numeric(0), numeric(0), numeric(0), c(k - 1, j), cf[j + 1, k])
  }
  if (fam != "gaussian") {
    lo <- round(-runif(p, 0, 1), 2); up <- round(runif(p, 0, 1), 2)
    f0 <- suppressWarnings(glmnet(X, y, family = fam, alpha = alpha, standardize = std, penalty.factor = vf, lower.limits = lo, upper.limits = up)); lam <- f0$lambda[unique(round(seq(2, length(f0$lambda), length.out = 5)))]
    f <- suppressWarnings(glmnet(X, y, family = fam, alpha = alpha, standardize = std, penalty.factor = vf, lower.limits = lo, upper.limits = up, lambda = lam, thresh = 1e-14)); cf <- as.matrix(coef(f))
    hd <- head_(n, p, alpha, std, lam, 0, 1, 0, vf)
    for (k in c(2, length(lam))) for (j in 0:p) cases[[length(cases) + 1]] <- cq(if (fam == "binomial") "binb" else "poisb", hd, y, X, numeric(0), lo, up, numeric(0), c(k - 1, j), cf[j + 1, k])
  }
}

# relax = TRUE: "rlxg" gaussian, "rlxb" binomial, "rlxp" poisson, "rlxc" Cox; data = y[n] (Cox: time, status); query = (k, j, gamma): coef(fit, s = lambda_k, gamma) row j (0 the intercept)
set.seed(20261124)
for (fam in c("gaussian", "binomial", "poisson", "cox")) for (rep in if (want_("relax")) 1:3 else integer(0)) {
  n <- sample(70:130, 1); p <- sample(4:7, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  y <- switch(fam, gaussian = round(X[, 1] * 2 - X[, 3] + rnorm(n), 3), binomial = rbinom(n, 1, plogis(1.2 * X[, 1] - 0.8 * X[, 3])), poisson = rpois(n, exp(0.5 + 0.5 * X[, 1] - 0.4 * X[, 3])), cox = NA)
  if (fam == "cox") { tm <- round(rexp(n, exp(0.5 * X[, 1] - 0.5 * X[, 3])), 2) + 0.01; st <- rbinom(n, 1, 0.8); y <- Surv(tm, st) }
  alpha <- c(1, 0.5, 0.9)[(rep %% 3) + 1]; std <- rep %% 2 == 0; vf <- rep(1, p)
  hw <- as.integer(rep %% 3 == 1 && fam != "poisson"); w <- if (hw) round(runif(n, 0.3, 3), 2) else numeric(0)
  ho <- as.integer(rep %% 3 == 2 && fam %in% c("binomial", "poisson", "cox")); off <- if (ho) round(rnorm(n, 0, 0.3), 2) else numeric(0)
  a0 <- list(x = X, y = y, family = fam, alpha = alpha, standardize = std)
  if (fam == "cox") a0$cox.ties <- "breslow"
  if (hw) a0$weights <- w; if (ho) a0$offset <- off
  f0 <- suppressWarnings(do.call(glmnet, a0)); lam <- f0$lambda[unique(round(seq(3, length(f0$lambda), length.out = 6)))]
  a1 <- a0; a1$lambda <- lam; a1$relax <- TRUE; a1$thresh <- 1e-14
  f <- suppressWarnings(do.call(glmnet, a1))
  hd <- head_(n, p, alpha, std, lam, hw, 0, ho, vf); nm <- c(gaussian = "rlxg", binomial = "rlxb", poisson = "rlxp", cox = "rlxc")[[fam]]
  dat <- if (fam == "cox") c(tm, st) else y
  for (k in c(2, length(lam))) for (g in c(0, 0.5)) { cf <- as.numeric(as.matrix(coef(f, s = lam[k], gamma = g))); if (fam == "cox") cf <- c(0, cf)
    for (j in 0:p) cases[[length(cases) + 1]] <- cq(nm, hd, dat, X, w, numeric(0), numeric(0), off, c(k - 1, j, g), cf[j + 1], rel = 1e-5, abs = 1e-6) }
}

# predict types, from the coefficients R reports at one lambda: "prd" data = (family, type, nc, rows[nc (p + 1)]); newx (n rows) then the offset; query = (observation, class)
set.seed(20261125)
for (fam in c("gaussian", "binomial", "poisson", "cox", "multinomial")) for (rep in if (want_("predict")) 1:2 else integer(0)) {
  n <- 100; p <- 5; X <- matrix(round(rnorm(n * p), 3), n, p); m <- 5; NX <- matrix(round(rnorm(m * p), 3), m, p)
  K <- 3
  y <- switch(fam, gaussian = round(X[, 1] * 2 - X[, 3] + rnorm(n), 3), binomial = rbinom(n, 1, plogis(1.2 * X[, 1] - 0.8 * X[, 3])), poisson = rpois(n, exp(0.5 + 0.5 * X[, 1] - 0.4 * X[, 3])), cox = NA, multinomial = factor(sample(K, n, TRUE, prob = plogis(c(0, X[1, 1], 1)))))
  if (fam == "cox") { tm <- round(rexp(n, exp(0.5 * X[, 1])), 2) + 0.01; y <- Surv(tm, rbinom(n, 1, 0.8)) }
  if (fam == "multinomial") { cl <- apply(exp(X[, 1:3] %*% matrix(c(1, 0, -1, 0, 1, 0, -1, 0, 1), 3, 3)), 1, function(r) sample(3, 1, prob = r)); y <- factor(cl) }
  ho <- rep == 2 && fam %in% c("gaussian", "binomial", "poisson"); off <- round(rnorm(n, 0, 0.3), 2); noff <- round(rnorm(m, 0, 0.3), 2)
  a0 <- list(x = X, y = y, family = fam, alpha = 0.7); if (fam == "cox") a0$cox.ties <- "breslow"; if (ho) a0$offset <- off
  f <- suppressWarnings(do.call(glmnet, a0)); s <- f$lambda[10]
  hd <- head_(m, p, 0.7, 1, numeric(0), 0, 0, as.integer(ho), rep(1, p))
  fm <- c(gaussian = 2, binomial = 0, poisson = 1, cox = 3, multinomial = 4)[[fam]]
  cfl <- coef(f, s = s)
  rows <- if (fam == "multinomial") unlist(lapply(cfl, function(z) as.numeric(as.matrix(z)))) else { v <- as.numeric(as.matrix(cfl)); if (fam == "cox") c(0, v) else v }
  nc <- if (fam == "multinomial") K else 1
  pr <- function(type) if (ho) predict(f, NX, s = s, type = type, newoffset = noff) else predict(f, NX, s = s, type = type)
  types <- c("link", "response", "class")
  for (kd in 0:2) {
    if (kd == 2 && !(fam %in% c("binomial", "multinomial"))) next
    if (kd == 1 && fam == "cox") next
    v <- pr(types[kd + 1])
    if (fam == "multinomial" && kd < 2) v <- array(v, c(m, K)) else v <- as.vector(v)
    for (i in 1:m) { if (fam == "multinomial" && kd < 2) { for (cc in 1:K) cases[[length(cases) + 1]] <- cq("prd", hd, c(fm, kd, nc, rows), NX, numeric(0), numeric(0), numeric(0), if (ho) noff else numeric(0), c(i - 1, cc - 1), v[i, cc], rel = 1e-9, abs = 1e-12) }
      else cases[[length(cases) + 1]] <- cq("prd", hd, c(fm, kd, nc, rows), NX, numeric(0), numeric(0), numeric(0), if (ho) noff else numeric(0), c(i - 1, 0), if (kd == 2) as.numeric(v[i]) else v[i], rel = 1e-9, abs = 1e-12) }
  }
  nz <- predict(f, NX, s = s, type = "nonzero"); nzl <- if (fam == "multinomial") lapply(nz, function(z) z[[1]]) else list(nz[[1]])
  for (cc in seq_along(nzl)) { idx <- as.numeric(nzl[[cc]])
    cases[[length(cases) + 1]] <- cq("prd", hd, c(fm, 3, nc, rows), NX, numeric(0), numeric(0), numeric(0), if (ho) noff else numeric(0), c(0, cc - 1), length(idx), rel = 0, abs = 0.5)
    for (q in seq_along(idx)) cases[[length(cases) + 1]] <- cq("prd", hd, c(fm, 4, nc, rows), NX, numeric(0), numeric(0), numeric(0), if (ho) noff else numeric(0), c(q - 1, cc - 1), idx[q], rel = 0, abs = 0.5) }
}

# nlambda and lambda.min.ratio (gaussian): "lseq" data = y[n]; query = (k, nlambda, ratio)
set.seed(20261126)
for (rep in if (want_("lseq")) 1:12 else integer(0)) {
  n <- sample(50:100, 1); p <- sample(3:7, 1); X <- matrix(round(rnorm(n * p), 3), n, p); y <- round(X[, 1] * 2 - X[, 3] + rnorm(n), 3)
  alpha <- c(1, 0.5, 0.2, 0.9)[(rep %% 4) + 1]; std <- rep %% 3 != 0; nl <- sample(c(10, 20, 50, 100), 1); ratio <- sample(c(0.5, 0.1, 0.01, 0.001), 1)
  f <- suppressWarnings(glmnet(X, y, alpha = alpha, standardize = std, nlambda = nl, lambda.min.ratio = ratio)); L <- length(f$lambda)
  hd <- head_(n, p, alpha, std, numeric(0), 0, 0, 0, rep(1, p))
  for (k in unique(c(1, 2, L %/% 2, L))) cases[[length(cases) + 1]] <- cq("lseq", hd, y, X, numeric(0), numeric(0), numeric(0), numeric(0), c(k - 1, nl, ratio), f$lambda[k], rel = 1e-9, abs = 1e-12)
}

# glmnet at its default thresh (1e-7) over a user lambda sequence, against the exact solutions this port answers: gaussian "cfg", binomial "cfb", poisson "cfp" (data = y; query = (k, j)), Cox "cox" and multinomial "mult" in their layouts. glmnet stops each lambda once the objective gains less than thresh of the null deviance, which leaves its coefficients a few 1e-5 from the minimiser; these cases fix that gap
set.seed(20261127)
for (rep in if (want_("thresh7")) 1:3 else integer(0)) {
  n <- sample(80:140, 1); p <- sample(4:6, 1); X <- matrix(round(rnorm(n * p), 3), n, p); alpha <- c(1, 0.5, 0.2)[(rep %% 3) + 1]; std <- TRUE; vf <- rep(1, p)
  for (fam in c("gaussian", "binomial", "poisson", "cox", "multinomial")) {
    K <- 3
    y <- switch(fam, gaussian = round(X[, 1] * 2 - X[, 3] + rnorm(n), 3), binomial = rbinom(n, 1, plogis(1.2 * X[, 1] - 0.8 * X[, 3])), poisson = rpois(n, exp(0.5 + 0.5 * X[, 1] - 0.4 * X[, 3])), cox = NA, multinomial = NA)
    if (fam == "cox") { tm <- round(rexp(n, exp(0.5 * X[, 1] - 0.5 * X[, 3])), 2) + 0.01; st <- rbinom(n, 1, 0.8); y <- Surv(tm, st) }
    if (fam == "multinomial") { cl <- apply(exp(X[, 1:3] %*% matrix(c(1, 0, -1, 0, 1, 0, -1, 0, 1), 3, 3)), 1, function(r) sample(3, 1, prob = r)); y <- factor(cl) }
    a0 <- list(x = X, y = y, family = fam, alpha = alpha, standardize = std); if (fam == "cox") a0$cox.ties <- "breslow"
    f0 <- suppressWarnings(do.call(glmnet, a0)); lam <- f0$lambda[unique(round(seq(3, length(f0$lambda), length.out = 5)))]
    a1 <- a0; a1$lambda <- lam; f <- suppressWarnings(do.call(glmnet, a1)); hd <- head_(n, p, alpha, std, lam, 0, 0, 0, vf)
    for (k in c(2, length(lam))) {
      if (fam %in% c("gaussian", "binomial", "poisson")) { cf <- as.matrix(coef(f)); for (j in 0:p) cases[[length(cases) + 1]] <- cq(c(gaussian = "cfg", binomial = "cfb", poisson = "cfp")[[fam]], hd, y, X, numeric(0), numeric(0), numeric(0), numeric(0), c(k - 1, j), cf[j + 1, k], rel = 1e-3, abs = 1e-4) }
      if (fam == "cox") { cf <- as.matrix(coef(f)); for (j in 1:p) cases[[length(cases) + 1]] <- cq("cox", hd, c(tm, st), X, numeric(0), numeric(0), numeric(0), numeric(0), c(k - 1, j), cf[j, k], rel = 1e-3, abs = 1e-4) }
      if (fam == "multinomial") { cf <- coef(f); for (cc in c(1, 3)) for (j in 0:p) cases[[length(cases) + 1]] <- cq("mult", hd, c(cl - 1, K, 0), X, numeric(0), numeric(0), numeric(0), numeric(0), c(k - 1, cc - 1, j), as.matrix(cf[[cc]])[j + 1, k], rel = 1e-2, abs = 5e-4) }
    }
  }
}

emit("glmnet_ext", "glmnet", list(cases))
