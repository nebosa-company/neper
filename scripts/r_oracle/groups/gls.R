# nlme::gls with a fixed correlation (AR1, compound symmetry, exponential) for one group.
#   args: (n, p, kind, par, reml, t[n], y[n], X[n*p] column-major, q)  q in 0..p-1 coefficient, p sigma, p+1 logLik
suppressMessages(library(nlme))
cases <- list()
set.seed(20261116)
for (rep in 1:16) {
  n <- sample(12:40, 1); p <- sample(2:4, 1)
  tt <- sort(sample(1:(2 * n), n)); X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 3), n, p - 1))
  y <- round(drop(X %*% (1:p)) + as.numeric(arima.sim(list(ar = 0.5), n)) , 3)
  d <- data.frame(y = y, t = tt); for (k in 2:p) d[[paste0("x", k)]] <- X[, k]
  fm <- as.formula(paste("y ~", paste(paste0("x", 2:p), collapse = " + ")))
  for (kind in 0:2) for (reml in c(1, 0)) {
    par <- c(0.6, 0.3, 4)[kind + 1] * (1 + 0.2 * (rep %% 3))
    cs <- switch(kind + 1, corAR1(value = par, form = ~ t, fixed = TRUE), corCompSymm(value = par, form = ~ 1, fixed = TRUE), corExp(value = par, form = ~ t, fixed = TRUE))
    if (kind == 0) { tt1 <- seq_len(n); d$t <- tt1; tt <- tt1 }
    f <- tryCatch(gls(fm, data = d, correlation = cs, method = if (reml) "REML" else "ML"), error = function(e) NULL)
    if (is.null(f)) next
    out <- c(coef(f), f$sigma, as.numeric(logLik(f)))
    for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("gls", c(n, p, kind, par, reml, tt, y, X, q - 1), out[q], rel = 1e-6, abs = 1e-8)
  }
}
emit("gls", "nlme", list(cases))
