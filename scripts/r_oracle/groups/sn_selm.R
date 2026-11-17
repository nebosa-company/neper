# sn_selm: selm fits (maximum and penalised likelihood) against sn, split from the sn group because they are slow.
suppressMessages(library(sn))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
# selm fits, one response: args (family 0 SN / 1 ST, penalised 0/1, n, p, which, y(n), x(n*p)); which 0..p-1 beta, p omega, p+1 alpha, p+2 nu (ST), p+2+(ST) the log-likelihood
selm_case <- function(fam, pen, n, p, sd) {
  set.seed(sd); x1 <- round(rnorm(n), 2)
  e <- if (fam == 0) rsn(n, 0, 1.2, c(3, -3, 5)[sample(3, 1)]) else rst(n, 0, 1.2, c(3, -3, 5)[sample(3, 1)], c(4, 5, 6)[sample(3, 1)])
  y <- round(1 + (if (p == 2) 0.5 * x1 else 0) + e, 4)
  X <- if (p == 2) cbind(1, x1) else matrix(1, n, 1)
  fit <- tryCatch(selm(if (p == 2) y ~ x1 else y ~ 1, family = if (fam == 0) "SN" else "ST", method = if (pen) "MPLE" else "MLE"), error = function(e) NULL)
  if (is.null(fit)) return(invisible())
  dp <- coef(fit, "DP"); ll <- as.numeric(logLik(fit))
  k <- length(dp)
  if (fam == 1 && pen) { dp0 <- tryCatch(coef(selm(if (p == 2) y ~ x1 else y ~ 1, family = "ST", method = "MLE"), "DP"), error = function(e) NULL)
    if (is.null(dp0) || abs(dp[p + 3] / dp0[p + 3] - 1) > 0.5) return(invisible()) }
  if (fam == 1) { re <- tryCatch(selm(if (p == 2) y ~ x1 else y ~ 1, family = "ST", method = if (pen) "MPLE" else "MLE", start = c(dp[1:(p + 1)], 0.5 * dp[p + 2], 5)), error = function(e) NULL)
    if (!is.null(re) && as.numeric(logLik(re)) > ll + 1e-4) return(invisible()) }
  if (abs(dp[p + 2]) < 1 ||(fam == 1 && dp[p + 3] > 30) || abs(dp[p + 2]) > 30) return(invisible())
  for (w in seq_len(k)) add("selm", c(fam, pen, n, p, w - 1, y, as.numeric(t(X))), unname(dp[w]), rel = 1e-3)
  add("selm", c(fam, pen, n, p, k, y, as.numeric(t(X))), ll, rel = 1e-6)
}
for (rep in 1:6) for (fam in 0:1) for (pen in 0:1) selm_case(fam, pen, 300, c(1, 2)[(rep %% 2) + 1], 7000 + rep * 10 + fam * 2 + pen)
# matrix-response selm: args (family 0 SN / 1 ST, penalised, n, d, p, which, y(n*d row-major), x(n*p row-major)); the output is beta (row j, comp k), Omega, alpha, nu (ST), log-likelihood
mvsel_case <- function(fam, pen, n, d, p, sd) {
  set.seed(sd); x1 <- round(rnorm(n), 2)
  A <- matrix(round(rnorm(d * d, sd = 0.4), 2), d, d); Om <- crossprod(A) + diag(d); al <- c(3, -2.5, 2)[seq_len(d)]
  z <- if (fam == 0) rmsn(n, rep(0, d), Om, al) else rmst(n, rep(0, d), Om, al, c(5, 7)[sample(2, 1)])
  y <- round(z + 1 + (if (p == 2) outer(x1, c(0.5, -0.3, 0.2)[seq_len(d)]) else 0), 4)
  colnames(y) <- paste0("y", seq_len(d)); X <- if (p == 2) cbind(1, x1) else matrix(1, n, 1)
  frm <- if (p == 2) y ~ x1 else y ~ 1
  fit <- tryCatch(selm(frm, family = if (fam == 0) "SN" else "ST", method = if (pen) "MPLE" else "MLE"), error = function(e) NULL)
  if (is.null(fit)) return(invisible())
  dp <- coef(fit, "DP", vector = FALSE); ll <- as.numeric(logLik(fit))
  flat <- c(as.numeric(t(as.matrix(dp$beta))), as.numeric(t(dp$Omega)), dp$alpha, if (fam == 1) dp$nu)
  if (fam == 1 && dp$nu > 30) return(invisible())
  for (k in unique(c(1, p * d + d * d + 1))) add("mvselm", c(fam, pen, n, d, p, k - 1, as.numeric(t(y)), as.numeric(t(X))), flat[k], rel = if (fam == 1 && pen) 3e-2 else 5e-3, abs = 2e-3)
  add("mvselm", c(fam, pen, n, d, p, length(flat), as.numeric(t(y)), as.numeric(t(X))), ll, rel = if (fam == 1 && pen) 5e-5 else 1e-4)
}
for (rep in 1:3) for (fam in 0:1) for (pen in 0:1) mvsel_case(fam, pen, 300, 2, c(1, 2)[rep %% 2 + 1], 8000 + rep * 10 + fam * 2 + pen)
emit("sn_selm", "sn", list(cases))
