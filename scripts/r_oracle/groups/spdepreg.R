# spatialreg and spdep regression: lagsarlm, errorsarlm (method "eigen"), impacts, lm.RStests, lm.morantest on random point sets.
# lag, err and impacts compare at rel 1e-6 / abs 1e-7, sac at 1e-5 / 1e-6: R optimize and nlminb stop at xtol 1.5e-8 and the last digits of rho and lambda follow the rounding of its qr.Q (sac worst seen 6e-7)
#   args: n, m, style, W (n * n row-major), X (n * m column-major, first column 1), y (n), then k (and for imp_t mt before k).
#   families (fn): lag (k indexes rho, LL, s2, SSE, rho.se, LMtest, logLik(lm), coef[m], se[m]), err (lambda, LL, s2, SSE, lambda.se, logLik(lm), coef[m], se[m]),
#   imp_e (k = 0..3p-1: direct, indirect, total from the eigenvalues), imp_t (same with trW m = mt), rs (k: RSerr, RSlag, adjRSerr, adjRSlag, SARMA, then their p values), mor (alt, k: I, E, Var, z, p)
suppressMessages({library(spdep); library(spatialreg)})
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
styles <- c("W", "B", "C")
alts <- c("greater", "less", "two.sided")
set.seed(20261223)
for (rep in 1:6) {
  n <- sample(16:22, 1); co <- matrix(runif(2 * n), n)
  kk <- sample(3:5, 1)
  nb <- make.sym.nb(knn2nb(knearneigh(co, k = kk)))
  if (rep %% 2 == 0) nb <- knn2nb(knearneigh(co, k = kk))
  sty <- c(0, 0, 1, 0, 2, 0, 0, 1)[rep]
  lw <- nb2listw(nb, style = styles[sty + 1])
  W <- listw2mat(lw)
  m <- 3
  X <- cbind(1, matrix(rnorm(n * (m - 1)), n))
  beta <- c(1, 2, -1.5)
  rho <- c(0.5, -0.3, 0.15, 0.4)[(rep - 1) %% 4 + 1]
  if (sty >= 1) rho <- rho / 4
  ee <- rnorm(n)
  if (rep %% 2 == 1) y <- as.vector(solve(diag(n) - rho * W, X %*% beta + ee)) else y <- as.vector(X %*% beta + solve(diag(n) - rho * W, ee))
  H <- c(n, m, sty, as.vector(t(W)), as.vector(X), y)
  dat <- list(y = y, X = X)
  fl <- lagsarlm(y ~ X - 1, data = dat, listw = lw, method = "eigen")
  out <- c(fl$rho, fl$LL, fl$s2, fl$SSE, fl$rho.se, fl$LMtest, fl$logLik_lm.model, fl$coefficients, fl$rest.se)
  for (k in seq_along(out)) add("lag", c(H, k - 1), out[k], rel = 1e-6, abs = 1e-7)
  fe <- errorsarlm(y ~ X - 1, data = dat, listw = lw, method = "eigen")
  out <- c(fe$lambda, fe$LL, fe$s2, fe$SSE, fe$lambda.se, fe$logLik_lm.model, fe$coefficients, fe$rest.se)
  for (k in seq_along(out)) add("err", c(H, k - 1), out[k], rel = 1e-6, abs = 1e-7)
  if (sty == 0 && rep <= 4) {
    B <- diag(n) - 0.3 * W
    ys <- as.vector(solve(diag(n) - rho * W, X %*% beta + solve(B, rnorm(n))))
    fs <- suppressWarnings(sacsarlm(ys ~ X - 1, data = list(ys = ys, X = X), listw = lw, method = "eigen"))
    out <- c(fs$rho, fs$lambda, fs$LL, fs$s2, fs$SSE, fs$rho.se, fs$lambda.se, fs$logLik_lm.model, fs$coefficients, fs$rest.se)
    Hs <- c(n, m, sty, as.vector(t(W)), as.vector(X), ys)
    for (k in seq_along(out)) add("sac", c(Hs, k - 1), out[k], rel = 1e-5, abs = 1e-6)
  }
  if (sty == 0) {
  ev <- eigenw(lw)
  im <- impacts(fl, evalues = ev)
  out <- c(im$res$direct, im$res$indirect, im$res$total)
  for (k in seq_along(out)) add("imp_e", c(H, k - 1), out[k], rel = 1e-6, abs = 1e-7)
  mt <- 30
  tr <- trW(as(lw, "CsparseMatrix"), m = mt, type = "mult")
  im <- impacts(fl, tr = tr)
  out <- c(im$res$direct, im$res$indirect, im$res$total)
  for (k in seq_along(out)) add("imp_t", c(H, mt, k - 1), out[k], rel = 1e-6, abs = 1e-7)
  }
  ols <- lm(y ~ X - 1)
  rs <- lm.RStests(ols, lw, test = "all")
  out <- c(sapply(rs, function(z) z$statistic), sapply(rs, function(z) z$p.value))
  for (k in seq_along(out)) add("rs", c(H, k - 1), out[k])
  for (al in 0:2) {
    mo <- lm.morantest(ols, lw, alternative = alts[al + 1])
    out <- c(mo$estimate, mo$statistic, mo$p.value)
    for (k in 0:4) add("mor", c(H, al, k), out[k + 1])
  }
}
emit("spdepreg", c("spdep", "spatialreg"), list(cases))
