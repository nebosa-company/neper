# carets_vi: caret preProcess(method = "ica") (fastICA on the centred and scaled columns, w.init = rnorm(e^2) after set.seed(sd)) and predict.
#   "ica": (n, p, e, sd, tol, maxit, nx, deflation, exp, alpha, id, X[n p], X2[nx p]) column-major; id 0 position-weighted sum of K, 1 of W, 2 K[1], then
#   3 the checksum sum(position * score) and the sum of squared scores of predict(pp, X2)
# A start for which the FastICA iteration never reaches its tolerance wanders chaotically (a 1e-12 change in w.init changes the
# sources), so no two libms agree on it: those draws are skipped.
suppressMessages(library(caret))
suppressMessages(library(fastICA))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261121)
for (rep in 1:36) {
  n <- sample(40:90, 1); p <- sample(3:6, 1); e <- sample(2:p, 1); sd <- sample(1:100000, 1); nx <- sample(3:9, 1)
  S <- cbind(runif(n, -1, 1), rexp(n) - 1, rt(n, 5), sign(rnorm(n)) * runif(n, 0.5, 1), rnorm(n) * runif(n), runif(n))[, 1:p]
  A <- matrix(round(runif(p * p, -1, 1), 2), p, p) + diag(p)
  X <- round(S %*% A, 4); X2 <- round(matrix(rnorm(nx * p), nx, p) %*% A, 4); colnames(X) <- colnames(X2) <- paste0("v", 1:p)
  tol <- c(1e-4, 1e-6, 1e-3)[rep %% 3 + 1]; maxit <- c(200, 500, 100)[rep %% 3 + 1]
  at <- c("parallel", "deflation")[rep %% 2 + 1]; fn <- c("logcosh", "exp")[(rep %/% 2) %% 2 + 1]; alpha <- c(1, 1.5, 1.2)[rep %% 3 + 1]
  set.seed(sd); wi <- matrix(rnorm(e^2), e, e)
  chk <- tryCatch({
    f1 <- fastICA(scale(X), e, tol = tol, maxit = maxit, w.init = wi, alg.typ = at, fun = fn, alpha = alpha)
    f2 <- fastICA(scale(X), e, tol = tol, maxit = maxit, w.init = wi + 1e-12, alg.typ = at, fun = fn, alpha = alpha)
    max(abs(f1$S - f2$S)) }, error = function(e) Inf)
  if (!is.finite(chk) || chk > 1e-9) next
  set.seed(sd)
  pp <- tryCatch(suppressWarnings(preProcess(as.data.frame(X), method = "ica", n.comp = e, tol = tol, maxit = maxit, alg.typ = at, fun = fn, alpha = alpha)), error = function(e) NULL)
  if (is.null(pp)) next
  sc <- as.matrix(predict(pp, as.data.frame(X2))[, paste0("ICA", 1:e), drop = FALSE])
  Km <- as.vector(pp$ica$K); Wm <- as.vector(pp$ica$W); v <- c(sum(seq_along(Km) * Km), sum(seq_along(Wm) * Wm), Km[1], sum(seq_along(sc) * sc), sum(sc^2))
  if (any(!is.finite(v))) next
  a <- c(n, p, e, sd, tol, maxit, nx, as.numeric(at == "deflation"), as.numeric(fn == "exp"), alpha)
  for (q in seq_along(v)) add("ica", c(a, q - 1, X, X2), v[q])
}
# varImp(glm(family = f(link = l))): "vig" (family, link, n, p, 0, X[n p] intercept first, y); family 0 binomial 1 poisson 2 gaussian 3 Gamma 4 inverse.gaussian,
# link 0 logit 1 probit 2 cauchit 3 cloglog 4 log 5 identity 6 inverse 7 sqrt 8 1/mu^2. A fit with a warning or an error in R is skipped.
fams <- list(binomial, poisson, gaussian, Gamma, inverse.gaussian)
lnks <- c("logit", "probit", "cauchit", "cloglog", "log", "identity", "inverse", "sqrt", "1/mu^2")
combos <- list(c(0, 0), c(0, 1), c(0, 2), c(0, 3), c(1, 4), c(1, 5), c(1, 7), c(2, 5), c(2, 4), c(2, 6), c(3, 4), c(3, 6), c(3, 5), c(4, 8), c(4, 6), c(4, 4), c(4, 5))
set.seed(20261122)
for (rep in 1:2) for (cb in combos) {
  fam <- cb[1]; lk <- cb[2]
  n <- sample(60:130, 1); k <- sample(2:4, 1); Xm <- matrix(round(rnorm(n * k), 3), n, k); bb <- c(0.5, -0.4, 0.3, 0.2)[1:k]; xb <- as.vector(Xm %*% bb)
  fm <- fams[[fam + 1]](link = lnks[lk + 1]); lp <- fm$linkinv
  mu <- switch(as.character(lk),
    "0" = , "1" = , "2" = , "3" = if (fam == 0) lp(0.2 + xb) else NA,
    "4" = exp(0.8 + xb), "5" = 4 + 1.2 * xb, "6" = 1 / (0.6 + 0.12 * xb), "7" = (2 + 0.4 * xb)^2, "8" = 1 / (0.5 + 0.1 * xb)^2)
  if (any(!is.finite(mu)) || any(mu <= 0)) next
  y <- switch(as.character(fam), "0" = rbinom(n, 1, mu), "1" = rpois(n, mu), "2" = mu + rnorm(n, 0, 0.5), rgamma(n, shape = 6, scale = mu / 6))
  if (fam == 2 && any(y <= 0)) y <- abs(y) + 0.1
  d <- data.frame(y = y, Xm)
  m <- tryCatch(withCallingHandlers(glm(y ~ ., fm, d), warning = function(w) stop("warn")), error = function(e) NULL)
  if (is.null(m) || !m$converged) next
  vi <- varImp(m)$Overall
  add("vig", c(fam, lk, n, k + 1, 0, cbind(1, Xm), y), sum(seq_along(vi) * vi), 1e-9, 1e-11)
}
# varImp(rpart): "vir" (n, p, method 1 anova 3 class, k, minsplit, minbucket, cp, maxcompete, maxsurrogate, usesurrogate, surrogatestyle, maxdepth, ncat[p], y[n], X[n p] with NaN missing),
# answered as the position-weighted sum of the four vectors varImp(fit, surrogates = s, competes = c) for (s, c) = (F, T), (F, F), (T, T), (T, F), predictors in column order
suppressMessages(library(rpart))
set.seed(20261123)
for (rep in 1:24) {
  n <- sample(50:110, 1); p <- sample(3:5, 1)
  X <- data.frame(row.names = seq_len(n)); ncat <- integer(p)
  for (j in seq_len(p)) {
    if (runif(1) < 0.3) { L <- sample(2:5, 1); ncat[j] <- L; X[[paste0("x", j)]] <- factor(sample.int(L, n, replace = TRUE), levels = 1:L) }
    else X[[paste0("x", j)]] <- round(runif(n), 3)
  }
  num1 <- which(ncat == 0)[1]; sig <- if (is.na(num1)) 0 else 3 * (X[[num1]] > 0.5)
  eff <- 0; for (j in which(ncat > 0)) eff <- eff + (as.integer(X[[j]]) %% 2) * 1.5
  lat <- sig + eff + rnorm(n) * 0.8
  isc <- rep %% 2 == 0
  y <- if (isc) factor(cut(lat, c(-Inf, quantile(lat, c(1/3, 2/3)), Inf), labels = FALSE), levels = 1:3) else round(lat, 4)
  if (rep %% 3 != 1) for (j in sample(p, p - 1)) X[[j]][sample(n, round(n * 0.12))] <- NA
  for (r in which(rowSums(is.na(X)) == p)) X[r, 1] <- X[which(!is.na(X[, 1]))[1], 1]
  ctl <- list(minsplit = sample(c(6, 10, 20), 1), minbucket = sample(c(2, 4, 7), 1), cp = sample(c(0.003, 0.01, 0.03), 1), maxcompete = sample(0:4, 1),
              maxsurrogate = sample(1:5, 1), usesurrogate = sample(0:2, 1), surrogatestyle = sample(0:1, 1), maxdepth = sample(c(3, 5, 30), 1), xval = 0)
  d <- X; d$y__ <- y
  fit <- rpart(y__ ~ ., d, method = if (isc) "class" else "anova", control = do.call(rpart.control, ctl))
  v <- c(); for (sc in list(c(FALSE, TRUE), c(FALSE, FALSE), c(TRUE, TRUE), c(TRUE, FALSE))) { vi <- varImp(fit, surrogates = sc[1], competes = sc[2]); v <- c(v, vi[colnames(X), "Overall"]) }
  xm <- do.call(cbind, lapply(X, as.numeric))
  add("vir", c(n, p, if (isc) 3 else 1, if (isc) 3 else 0, ctl$minsplit, ctl$minbucket, ctl$cp, ctl$maxcompete, ctl$maxsurrogate, ctl$usesurrogate, ctl$surrogatestyle, ctl$maxdepth, ncat, as.numeric(y), xm), sum(v * seq_along(v)), 1e-9, 1e-11)
}
# varImp(nnet) (caret's GarsonWeights): "vin" (p, h, k, skip, wts[nw]) from the weights R's fit ended with, and "vns" (n, p, h, k, mode, decay, maxit, skip, seed, rang, x[n p] row-major,
# y[n k] row-major, case weights) where Neper's own nnet fit from the seeded start feeds the importance;
# the answer is the position-weighted sum of the data frame varImp(fit) gives (Overall, then one column per output when there are several), column-major
suppressMessages(library(nnet))
set.seed(20261124)
for (rep in 1:40) {
  n <- sample(40:90, 1); p <- sample(2:5, 1); h <- sample(1:5, 1); dc <- c(0, 0.01, 0.1)[rep %% 3 + 1]; sk <- rep %% 2 == 0; mode <- (rep - 1) %% 4; rg <- c(0.7, 0.5, 1)[rep %% 3 + 1]
  k <- if (mode == 0) sample(1:2, 1) else if (mode == 3) sample(2:3, 1) else sample(1:3, 1)
  x <- matrix(rnorm(n * p), n)
  y <- switch(mode + 1,
    matrix(sin(x[, 1]) + 0.5 * rowSums(x) + rnorm(n * k, 0, 0.2), n, k),
    matrix(1 / (1 + exp(-(x[, 1] + rnorm(n * k, 0, 0.5)))), n, k),
    matrix(rbinom(n * k, 1, 1 / (1 + exp(-(x[, 1])))), n, k),
    class.ind(sample(k, n, TRUE, prob = seq_len(k))))
  sd <- sample(1:100000, 1); set.seed(sd)
  f <- tryCatch(suppressWarnings(nnet(x, y, size = h, linout = (mode == 0), entropy = (mode == 2), softmax = (mode == 3), skip = sk, rang = rg, decay = dc, maxit = 100, trace = FALSE)), error = function(e) NULL)
  if (is.null(f) || f$convergence != 0) next
  vi <- tryCatch(suppressWarnings(varImp(f)), error = function(e) NULL)
  if (is.null(vi) || any(!is.finite(as.matrix(vi)))) next
  v <- as.vector(as.matrix(vi))
  add("vin", c(p, h, k, as.numeric(sk), f$wts), sum(v * seq_along(v)), 1e-9, 1e-11)
  if (rep %% 2 == 0) add("vns", c(n, p, h, k, mode, dc, 100, as.numeric(sk), sd, rg, as.vector(t(x)), as.vector(t(y)), rep(1, n)), sum(v * seq_along(v)), 1e-9, 1e-11)
}
# varImp(randomForest): "vrf" (kind 0 class 1 regression, n, p, ntree, mtry, nodesize, sampsize, replace, nclass, seed, y[n] (class codes 1-based), X[n p] row-major), importance = TRUE;
# the answer is the position-weighted sum of the data frame varImp(fit) gives, column-major (Overall for regression, one column per class for classification)
suppressMessages(library(randomForest))
set.seed(20261125)
for (rep in 1:24) {
  n <- sample(40:80, 1); p <- sample(3:6, 1); kind <- rep %% 2; K <- if (kind == 0) sample(2:4, 1) else 1
  X <- matrix(round(rnorm(n * p), 3), n, p); colnames(X) <- paste0("V", 1:p)
  lat <- X[, 1] + 0.7 * X[, 2] + rnorm(n) * 0.5
  y <- if (kind == 0) factor(cut(lat, c(-Inf, quantile(lat, seq_len(K - 1) / K), Inf), labels = FALSE), levels = 1:K) else round(lat, 4)
  ntree <- sample(15:40, 1); mtry <- sample(1:p, 1); ns <- sample(1:5, 1); rp <- rep %% 3 != 0; ss <- if (rp) n else sample(round(n * 0.5):n, 1); sd <- sample(1:100000, 1)
  set.seed(sd)
  fit <- suppressWarnings(randomForest(x = X, y = y, ntree = ntree, mtry = mtry, nodesize = ns, sampsize = ss, replace = rp, importance = TRUE))
  vi <- varImp(fit); v <- as.vector(as.matrix(vi))
  if (any(!is.finite(v))) next
  add("vrf", c(kind, n, p, ntree, mtry, ns, ss, rp, K, sd, if (kind == 0) as.integer(y) else y, as.vector(t(X))), sum(v * seq_along(v)), 1e-9, 1e-11)
}
# varImp(multinom): "vmn" (n, p, K, 0, y[n] 0-based class, x[n p] row-major with the constant first, case weights[n]) as the "dev" cases of the nnet group; the answer is the position-weighted sum of
# varImp(fit)$Overall. nnet's optimiser (BFGS) stops at reltol 1e-14 here, so the two optimisers agree to about 1e-8 and the case allows 1e-7.
suppressMessages(library(nnet))
set.seed(20261126)
for (rep in 1:14) {
  n <- sample(80:150, 1); p <- sample(2:4, 1); K <- sample(2:4, 1)
  x <- cbind(1, matrix(rnorm(n * (p - 1)), n))
  B <- matrix(rnorm(p * K, 0, 1), p); B[, 1] <- 0
  eta <- x %*% B; pr <- exp(eta) / rowSums(exp(eta))
  y <- apply(pr, 1, function(q) sample(0:(K - 1), 1, prob = q))
  if (length(unique(y)) < K) next
  d <- as.data.frame(x[, -1, drop = FALSE]); names(d) <- paste0("v", seq_len(p - 1)); d$y <- factor(y)
  f <- multinom(y ~ ., data = d, trace = FALSE, maxit = 5000, reltol = 1e-14, abstol = 1e-14)
  v <- varImp(f)$Overall
  add("vmn", c(n, p, K, 0, y, as.vector(t(x)), rep(1, n)), sum(v * seq_along(v)), 1e-7, 1e-8)
}
emit("carets_vi", c("caret", "fastICA"), list(cases))
