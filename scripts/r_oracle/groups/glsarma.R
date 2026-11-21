# nlme::gls with corARMA(p, q) of orders other than (1, 1), REML and ML, with and without a variance function.
# Case args: c(q, spec); spec = c(reml, n, p, ck, nv, ng, gs[ng], t[n], y[n], X[n*p] column-major, then per variance term c(kind, nstr, v[n])).
# ck = 1000 + 10 p + q for corARMA(p, q). Output vector as in groups/gls.R: coef (p), sigma, logLik, AIC, BIC, natural correlation
# parameters (phi then theta), natural variance parameters, se (p), lower (p), upper (p).
# R-side limit (measured, see groups/gls.R): rerunning gls with another start value of the same corARMA moves its estimates by up to 4e-5 relative (3.9e-5 for ARMA(1,1)).
# Tolerance 1e-6 relative (1e-8 absolute): gls stops nlminb at its default tolerance and the same path is followed here. The corARMA(3, 0) fit with varPower has a flat likelihood along the coefficients, so both stop up to 3e-5 apart: 1e-4 relative or 1e-5 absolute for that fit.
suppressMessages(library(nlme))
cases <- list()
set.seed(20261121)
mk <- function(ng, m, p) {
  n <- ng * m
  g <- rep(seq_len(ng), each = m)
  pos <- rep(seq_len(m), ng)
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 3), n, p - 1))
  v <- round(runif(n, 0.5, 3), 3)
  e <- unlist(lapply(seq_len(ng), function(i) as.numeric(arima.sim(list(ar = c(0.5, -0.3), ma = 0.4), m))))
  y <- round(drop(X %*% (1:p)) + e * exp(0.2 * v) + rnorm(ng)[g] * 0.5, 3)
  d <- data.frame(y = y, t = pos, g = factor(g), v = v)
  for (k in 2:p) d[[paste0("x", k)]] <- X[, k]
  list(d = d, X = X, n = n, ng = ng, m = m, p = p)
}
for (cf in list(c(2, 0, 0), c(0, 2, 1), c(2, 1, 0), c(1, 2, 1), c(3, 0, 1), c(2, 2, 0), c(1, 0, 1), c(0, 1, 0), c(0, 3, 1), c(1, 1, 0))) {
  pq <- cf[1:2]; vp <- cf[3]
  D <- mk(4, 12, 3)
  reml <- (pq[1] + pq[2]) %% 2
  ck <- 1000 + 10 * pq[1] + pq[2]
  fm <- y ~ x2 + x3
  wts <- if (vp) varPower(form = ~ v) else NULL
  f <- tryCatch(gls(fm, data = D$d, correlation = corARMA(form = ~ t | g, p = pq[1], q = pq[2]), weights = wts,
                    method = if (reml) "REML" else "ML"), error = function(e) { message("skip ", ck, ": ", conditionMessage(e)); NULL })
  if (is.null(f)) next
  cs <- f$modelStruct$corStruct
  vn <- if (vp) as.numeric(unlist(coef(f$modelStruct$varStruct, unconstrained = FALSE))) else numeric(0)
  iv <- intervals(f, which = "coef")$coef
  ov <- c(coef(f), f$sigma, as.numeric(logLik(f)), AIC(f), BIC(f), as.numeric(coef(cs, unconstrained = FALSE)), vn,
          sqrt(diag(vcov(f))), iv[, 1], iv[, 3])
  vstr <- if (vp) c(2, 0, D$d$v) else numeric(0)
  args0 <- c(reml, D$n, D$p, ck, as.integer(vp), D$ng, rep(D$m, D$ng), D$d$t, D$d$y, D$X, vstr)
  for (q in seq_along(ov)) cases[[length(cases) + 1]] <- case("glsarma", c(q - 1, args0), ov[q], rel = if (ck == 1030 && vp) 1e-4 else 1e-6, abs = if (ck == 1030 && vp) 1e-5 else 1e-8)
}
# variance functions of the fitted values, varPower/varExp/varConstPower(form = ~ fitted(.)): kind 12, 13, 14 (variance kind + 10).
# Tolerance 1e-5 relative / 1e-7 absolute for these: the weights depend on the fitted values, so gls iterates its coefficients inside the nlminb objective and stops at
# its own msTol 1e-5 / 1e-6-level coefficient change; R's value is not the optimum to better than that, and no R-side rebuild of the objective exists for them.
# nlme refits until the relative change of the coefficients and parameters is <= 1e-6, so those cases carry tolerance 1e-5 (1e-7 absolute).
mk2 <- function(ng, m, p) {
  D <- mk(ng, m, p)
  D$d$y <- round(10 + drop(D$X %*% (1:p)) + (D$d$y - drop(D$X %*% (1:p))) * 1, 3)
  D
}
for (cf in list(c(1, 12), c(0, 13), c(1, 14), c(4, 12), c(1011, 13), c(0, 12), c(2, 12))) {
  ck <- cf[1]; vk <- cf[2]
  D <- mk2(4, 12, 3)
  reml <- (ck + vk) %% 2
  cs <- switch(as.character(ck), "0" = NULL, "1" = corAR1(form = ~ t | g), "2" = corCompSymm(form = ~ 1 | g), "4" = corARMA(form = ~ t | g, p = 1, q = 1),
               "1011" = corARMA(form = ~ t | g, p = 1, q = 1))
  wt <- switch(as.character(vk), "12" = varPower(form = ~ fitted(.)), "13" = varExp(form = ~ fitted(.)), "14" = varConstPower(form = ~ fitted(.)))
  f <- tryCatch(gls(y ~ x2 + x3, data = D$d, correlation = cs, weights = wt, method = if (reml) "REML" else "ML"),
                error = function(e) { message("skip ", ck, "/", vk, ": ", conditionMessage(e)); NULL })
  if (is.null(f)) next
  cn <- if (ck == 0) numeric(0) else as.numeric(coef(f$modelStruct$corStruct, unconstrained = FALSE))
  vn <- as.numeric(unlist(coef(f$modelStruct$varStruct, unconstrained = FALSE)))
  iv <- intervals(f, which = "coef")$coef
  ov <- c(coef(f), f$sigma, as.numeric(logLik(f)), AIC(f), BIC(f), cn, vn, sqrt(diag(vcov(f))), iv[, 1], iv[, 3])
  args0 <- c(reml, D$n, D$p, ck, 1, D$ng, rep(D$m, D$ng), D$d$t, D$d$y, D$X, c(vk, 0, D$d$v))
  for (q in seq_along(ov)) cases[[length(cases) + 1]] <- case("glsarma", c(q - 1, args0), ov[q], rel = 1e-5, abs = 1e-7)
}
emit("glsarma", "nlme", list(cases))
