# sn_selm: selm fits (maximum and penalised likelihood) against sn, split from the sn group because they are slow.
suppressMessages(library(sn))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
# selm fits, one response: args (family 0 SN / 1 ST, penalised 0/1, n, p, which, fixed nu or -1, alpha fixed at 0 (0/1), weighted 0/1, y(n), x(n*p), w(n));
# which 0.. the dp (beta, omega, alpha, nu), then the log-likelihood, then the standard errors of the free parameters
selm_case <- function(fam, pen, n, p, sd, fnu = -1, symm = 0, weighted = 0) {
  set.seed(sd); x1 <- round(rnorm(n), 2)
  e <- if (fam == 0) rsn(n, 0, 1.2, c(3, -3, 5)[sample(3, 1)]) else rst(n, 0, 1.2, c(3, -3, 5)[sample(3, 1)], c(4, 5, 6)[sample(3, 1)])
  y <- round(1 + (if (p == 2) 0.5 * x1 else 0) + e, 4)
  X <- if (p == 2) cbind(1, x1) else matrix(1, n, 1)
  w <- if (weighted) sample(1:3, n, TRUE) else rep(1, n)
  fp <- list(); if (fnu > 0) fp$nu <- fnu; if (symm) fp$alpha <- 0
  frm <- if (p == 2) y ~ x1 else y ~ 1
  call <- function(...) if (weighted) selm(frm, family = if (fam == 0) "SN" else "ST", method = if (pen) "MPLE" else "MLE", fixed.param = fp, weights = w, ...) else selm(frm, family = if (fam == 0) "SN" else "ST", method = if (pen) "MPLE" else "MLE", fixed.param = fp, ...)
  fit <- tryCatch(call(), error = function(e) NULL)
  if (is.null(fit)) return(invisible())
  cf <- coef(fit, "DP"); ll <- as.numeric(logLik(fit)); tab <- summary(fit, "DP")@param.table
  dp <- c(cf[1:(p + 1)], if (symm) 0 else cf[p + 2], if (fam == 1) (if (fnu > 0) fnu else cf[length(cf)]))
  se <- tab[, 2]
  k <- length(dp)
  alpha <- dp[p + 2]
  if (!symm && abs(alpha) < 1) return(invisible())
  if (fam == 1 && fnu <= 0 && dp[k] > 30) return(invisible())
  if (fam == 1 && pen && !symm && fnu <= 0) { dp0 <- tryCatch(coef(selm(frm, family = "ST", method = "MLE"), "DP"), error = function(e) NULL)
    if (is.null(dp0) || abs(dp[k] / dp0[length(dp0)] - 1) > 0.5) return(invisible()) }
  if (fam == 1 && !symm && fnu <= 0 && !weighted) { re <- tryCatch(selm(frm, family = "ST", method = if (pen) "MPLE" else "MLE", start = c(dp[1:(p + 1)], 0.5 * dp[p + 2], 5)), error = function(e) NULL)
    if (!is.null(re) && as.numeric(logLik(re)) > ll + 1e-4) return(invisible()) }
  head <- c(fam, pen, n, p)
  tail <- c(fnu, symm, weighted, y, as.numeric(t(X)), w)
  for (j in seq_len(k)) add("selm", c(head, j - 1, tail), unname(dp[j]), rel = 1e-3, abs = 1e-4)
  add("selm", c(head, k, tail), ll, rel = 1e-6)
  for (j in seq_along(se)) add("selm", c(head, k + j, tail), unname(se[j]), rel = 2e-2, abs = 1e-4)
}
for (rep in 1:4) for (fam in 0:1) for (pen in 0:1) selm_case(fam, pen, 300, c(1, 2)[(rep %% 2) + 1], 7000 + rep * 10 + fam * 2 + pen)
# the family options: fixed nu, alpha fixed at 0, integer weights
for (rep in 1:2) { selm_case(1, 0, 250, c(1, 2)[rep %% 2 + 1], 7100 + rep, fnu = 6)
  selm_case(1, 0, 250, c(1, 2)[rep %% 2 + 1], 7110 + rep, symm = 1)
  selm_case(0, 0, 250, c(1, 2)[rep %% 2 + 1], 7120 + rep, symm = 1)
  selm_case(1, 0, 250, c(1, 2)[rep %% 2 + 1], 7130 + rep, weighted = 1)
  selm_case(0, 0, 250, c(1, 2)[rep %% 2 + 1], 7140 + rep, weighted = 1)
  selm_case(0, 1, 250, c(1, 2)[rep %% 2 + 1], 7150 + rep, weighted = 1) }
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
for (rep in 1:2) for (fam in 0:1) for (pen in 0:1) mvsel_case(fam, pen, 300, 2, c(1, 2)[rep %% 2 + 1], 8000 + rep * 10 + fam * 2 + pen)
emit("sn_selm", "sn", list(cases))
