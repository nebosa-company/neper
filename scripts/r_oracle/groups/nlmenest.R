# nlme::lme with nested random intercepts, random = ~ 1 | g1 / g2 (two levels, full model matrix on the fixed side), REML and ML.
# case: c(q_out, reml, n, p, n1, g1 observation count[n1], n2, g2 observation count[n2], y[n], X[n*p] column-major); outer groups g1 are contiguous and each holds whole inner groups g2.
# Output vector: coef (p), sigma, logLik, AIC, BIC, sd of the level-1 intercept, sd of the level-2 intercept, se (p), level-1 BLUPs (n1), level-2 BLUPs (n2).
# R's lme (nlminb, msTol 1e-12) stops ~1e-6 from the optimum of the likelihood, so the reference is lme's fit polished to the optimum of the same likelihood:
# the objective is rebuilt from the variance components (V = I + s1 J(g1) + s2 J(g2) relative to sigma^2), checked equal to logLik(f) at lme's estimates (1e-9),
# then minimised by Newton steps on Richardson derivatives; the BLUPs are recomputed at the polished estimates and checked against ranef(f) to 1e-3.
# Estimates and BLUPs carry rel 1e-7 / abs 1e-8, logLik, AIC and BIC rel 1e-9 (the likelihood is flat at its optimum: second order in the location error).
suppressMessages(library(nlme))
suppressMessages(library(numDeriv))
cases <- list()
set.seed(20261123)
mk <- function(n1, p) {
  g1s <- integer(0); g2s <- integer(0); i1 <- integer(0); i2 <- integer(0); k2 <- 0
  for (i in seq_len(n1)) {
    nj <- sample(2:4, 1); g1s <- c(g1s, 0)
    for (j in seq_len(nj)) { m <- sample(3:5, 1); k2 <- k2 + 1; g2s <- c(g2s, m); g1s[i] <- g1s[i] + 1; i1 <- c(i1, rep(i, m)); i2 <- c(i2, rep(k2, m)) }
  }
  n <- length(i1)
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 3), n, p - 1))
  b1 <- rnorm(n1, 0, 2.5); b2 <- rnorm(k2, 0, 1.5)
  y <- round(drop(X %*% seq_len(p)) + b1[i1] + b2[i2] + rnorm(n, 0, 1), 3)
  d <- data.frame(y = y, g1 = factor(i1), g2 = factor(i2))
  for (k in 2:p) d[[paste0("x", k)]] <- X[, k]
  list(d = d, X = X, n = n, n1 = n1, n2 = k2, g1 = as.numeric(table(i1)), g2 = g2s, i1 = i1, i2 = i2, p = p)
}
polish <- function(f, D, reml) {
  n <- D$n; X <- D$X; y <- D$d$y; px <- D$p; nobs <- n - reml * px
  J1 <- outer(D$i1, D$i1, "=="); J2 <- outer(D$i2, D$i2, "==")
  core <- function(th) {
    V <- diag(n) + exp(2 * th[1]) * J1 + exp(2 * th[2]) * J2; Vi <- solve(V)
    xvx <- t(X) %*% Vi %*% X; beta <- solve(xvx, t(X) %*% Vi %*% y); r <- y - X %*% beta; rss <- drop(t(r) %*% Vi %*% r)
    list(V = V, Vi = Vi, xvx = xvx, beta = beta, rss = rss, val = -nobs / 2 * log(rss) - as.numeric(determinant(V)$modulus) / 2 - reml / 2 * as.numeric(determinant(xvx)$modulus))
  }
  obj <- function(th) -core(th)$val
  sdr <- sqrt(sapply(as.matrix(f$modelStruct$reStruct), function(m) m[1, 1]))
  th <- log(sdr)
  const <- as.numeric(logLik(f)) - core(th)$val
  if (abs(const - nobs * (log(nobs) - (1 + log(2 * pi))) / 2) > 1e-6) stop("constant differs: ", const)
  c0 <- core(th); if (abs(sqrt(c0$rss / nobs) - f$sigma) > 1e-5 * f$sigma) stop("sigma differs")
  for (it in 1:40) {
    gr <- numDeriv::grad(obj, th, method = "Richardson"); H <- numDeriv::hessian(obj, th, method = "Richardson")
    st <- solve(H, gr); tn <- th - st; if (obj(tn) > obj(th) + 1e-13) break
    th <- tn; if (max(abs(st)) < 1e-12) break
  }
  cr <- core(th); sg <- sqrt(cr$rss / nobs); ll <- cr$val + const; npar <- px + 3
  res <- cr$Vi %*% (y - X %*% cr$beta)
  b1 <- exp(2 * th[1]) * as.numeric(tapply(res, D$i1, sum)); b2 <- exp(2 * th[2]) * as.numeric(tapply(res, D$i2, sum))
  if (max(abs(b1 - as.matrix(ranef(f, level = 1))[, 1])) > 1e-3 * (1 + max(abs(b1))) || max(abs(b2 - as.matrix(ranef(f, level = 2))[, 1])) > 1e-3 * (1 + max(abs(b2)))) stop("BLUPs differ from ranef")
  c(cr$beta, sg, ll, -2 * ll + 2 * npar, -2 * ll + npar * log(nobs), sg * exp(th), sg * sqrt(diag(solve(cr$xvx))), b1, b2)
}
for (cf in list(list(6, 3, 1), list(6, 3, 0), list(7, 2, 1), list(5, 3, 0))) {
  D <- mk(cf[[1]], cf[[2]]); reml <- cf[[3]]
  fx <- as.formula(paste("y ~", paste(paste0("x", 2:D$p), collapse = " + ")))
  f <- tryCatch(lme(fx, data = D$d, random = ~ 1 | g1 / g2, method = if (reml) "REML" else "ML",
    control = lmeControl(opt = "nlminb", msTol = 1e-12, tolerance = 1e-10, msMaxIter = 500, msMaxEval = 1000, maxIter = 200, niterEM = 25, returnObject = FALSE)),
    error = function(e) { message("lme failed: ", conditionMessage(e)); NULL })
  if (is.null(f)) next
  ov <- tryCatch(polish(f, D, reml), error = function(e) { message("polish failed: ", conditionMessage(e)); NULL })
  if (is.null(ov)) next
  args0 <- c(reml, D$n, D$p, D$n1, D$g1, D$n2, D$g2, D$d$y, D$X)
  for (q in seq_along(ov)) cases[[length(cases) + 1]] <- case("nest", c(q - 1, args0), ov[q], rel = if (q %in% (D$p + 2:4)) 1e-9 else 1e-7, abs = 1e-8)
}
emit("nlmenest", "nlme", list(cases))
