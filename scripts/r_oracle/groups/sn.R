# sn: dsn (with tau), psn through T.Owen, qsn (tau = 0, solver NR) and dst.
#   args: (xi, omega, alpha, tau_or_nu, v)   fn "dsn" "psn" "qsn" "dst"
suppressMessages(library(sn))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261203)
for (rep in 1:12) {
  xi <- runif(1, -1, 1); om <- runif(1, 0.5, 2.5); al <- c(runif(1, -6, 6), runif(1, 0.1, 3), runif(1, -3, -0.1), 12)[(rep - 1) %% 4 + 1]
  xs <- xi + om * c(-1.4, -0.4, 0.2, 0.9, 1.7, 2.6)
  tau <- c(0, 0.7, -0.5)[(rep - 1) %% 3 + 1]
  for (x in xs) add("dsn", c(xi, om, al, tau, x), dsn(x, xi, om, al, tau))
  pp <- xi + om * c(0.2, 0.5, 0.8, 1.1, 1.6, 2.2)
  if (all((pp - xi) / om * al > -5)) for (x in pp) add("psn", c(xi, om, al, 0, x), psn(c(pp), xi, om, al)[match(x, pp)])
  for (p in c(0.02, 0.2, 0.5, 0.8, 0.97)) add("qsn", c(xi, om, al, 0, p), qsn(p, xi, om, al), rel = 1e-6)
  nu <- c(2.5, 4, 7, 15)[(rep - 1) %% 4 + 1]
  for (x in xs) add("dst", c(xi, om, al, nu, x), dst(x, xi, om, al, nu))
}
# rsn (tau = 0 and tau != 0) and rst after set.seed: args (xi, omega, alpha, tau or nu, n, seed, index)
for (rep in 1:20) {
  xi <- round(rnorm(1), 2); om <- c(0.5, 1, 2)[sample(3, 1)]; al <- c(-3, -0.5, 0, 1, 4)[sample(5, 1)]; n <- sample(5:25, 1); sd <- sample(1:100000, 1)
  tau <- if (rep %% 3 == 0) c(-0.5, 0.7, 1.5)[sample(3, 1)] else 0
  set.seed(sd); r <- as.numeric(rsn(n, xi, om, al, tau)); for (k in seq_len(n)) add("rsn", c(xi, om, al, tau, n, sd, k - 1), r[k])
  nu <- c(3, 7.5, 30, Inf)[sample(4, 1)]
  set.seed(sd); r2 <- as.numeric(rst(n, xi, om, al, nu)); for (k in seq_len(n)) add("rst", c(xi, om, al, nu, n, sd, k - 1), r2[k])
}
# st.cumulants "cum" (xi, omega, alpha, nu, k)
for (rep in 1:20) { xi <- round(rnorm(1), 2); om <- c(0.5, 1, 2)[sample(3, 1)]; al <- c(-3, -0.5, 0, 1, 4)[sample(5, 1)]; nu <- c(5.5, 7, 12, 40, Inf)[(rep - 1) %% 5 + 1]
  cm <- st.cumulants(xi, om, al, nu); for (k in 1:4) add("cum", c(xi, om, al, nu, k), unname(cm[k])) }
# dp2cp proper "cp" (xi, omega, alpha, nu, which 0 mean 1 sd 2 skewness 3 kurtosis)
for (rep in 1:20) { xi <- round(rnorm(1), 2); om <- c(0.5, 1, 2)[sample(3, 1)]; al <- c(-3, -0.5, 1, 4)[sample(4, 1)]; nu <- c(5.5, 7, 12, 40, Inf)[(rep - 1) %% 5 + 1]
  cp <- if (is.finite(nu)) dp2cp(c(xi, om, al, nu), "ST") else dp2cp(c(xi, om, al), "SN"); for (w in seq_along(cp)) add("cp", c(xi, om, al, nu, w - 1), unname(cp[w])) }
# cp2dp "SN" "cp2" (mean, sd, skewness, which 0 xi 1 omega 2 alpha)
for (rep in 1:30) { mn <- round(rnorm(1), 2); sdv <- runif(1, 0.5, 3); sk <- runif(1, -0.95, 0.95)
  dp <- cp2dp(c(mn, sdv, sk), "SN"); if (is.null(dp)) next; for (w in 1:3) add("cp2", c(mn, sdv, sk, w - 1), unname(dp[w])) }
# pst (xi, omega, alpha, nu, x), one point per call as the package's scalar path runs it
for (rep in 1:40) {
  xi <- round(rnorm(1), 2); om <- c(0.5, 1, 2)[sample(3, 1)]; al <- c(-4, -1, 0, 0.8, 3, 9)[sample(6, 1)]
  nu <- c(1, 2, 3, 5, 6, 9, 15, 2.5, 7.5, 30.5, 400)[(rep - 1) %% 11 + 1]
  for (z in c(-40, -12, -3, -0.5, 0.3, 1.5, 4, 11, 45)) { x <- xi + om * z; add("pst", c(xi, om, al, nu, x), pst(x, xi, om, al, nu), rel = 1e-6) }
}
# qst (xi, omega, alpha, nu, p)
for (rep in 1:30) {
  xi <- round(rnorm(1), 2); om <- c(0.5, 1, 2)[sample(3, 1)]; al <- c(-4, -1, 0, 0.8, 3, 9)[sample(6, 1)]
  nu <- c(1, 2, 3, 5, 9, 2.5, 7.5, 30.5)[(rep - 1) %% 8 + 1]
  for (pr in c(0.001, 0.05, 0.3, 0.5, 0.75, 0.95, 0.999)) add("qst", c(xi, om, al, nu, pr), qst(pr, xi, om, al, nu), rel = 1e-5)
}
# cp2dp "ST" "cp2st" (mean, sd, gamma1, gamma2, which 0 xi 1 omega 2 alpha 3 nu), from proper centred parameters of known dp
for (rep in 1:40) { xi <- round(rnorm(1), 2); om <- c(0.5, 1, 2)[sample(3, 1)]; al <- c(-3, -0.5, 1, 4, 25)[sample(5, 1)]; nu <- c(4.5, 5.5, 7, 12, 40)[sample(5, 1)]
  cp <- dp2cp(c(xi, om, al, nu), "ST"); dp <- tryCatch(cp2dp(cp, "ST"), error = function(e) NULL); if (is.null(dp)) next
  for (w in 1:4) add("cp2st", c(cp[1], cp[2], cp[3], cp[4], w - 1), unname(dp[w]), rel = 1e-6) }
# psn scalar calls (bivariate normal engine) with tau: (xi, omega, alpha, tau, x)
for (rep in 1:40) { xi <- round(rnorm(1), 2); om <- c(0.5, 1, 2)[sample(3, 1)]; al <- c(-8, -3, -0.5, 0.3, 1, 5, 20)[sample(7, 1)]; tau <- c(0, 0.7, -0.5, 1.8, -2)[sample(5, 1)]
  for (z in c(-6, -2.5, -0.4, 0.2, 1, 2.8, 6)) { x <- xi + om * z; add("psnb", c(xi, om, al, tau, x), psn(x, xi, om, al, tau), rel = 1e-8) } }
# zeta (k, x) and the extended skew-normal cumulants "cumn" (xi, omega, alpha, tau, k)
for (k in 0:4) for (x in c(-60, -9, -2, -0.3, 0, 0.8, 2.5, 7)) add("zeta", c(k, x), zeta(k, x), rel = 1e-9)
for (rep in 1:20) { xi <- round(rnorm(1), 2); om <- c(0.5, 1, 2)[sample(3, 1)]; al <- c(-3, -0.5, 1, 4)[sample(4, 1)]; tau <- c(0, 0.7, -1.2, 2.5)[sample(4, 1)]
  cm <- sn.cumulants(xi, om, al, tau); for (k in 1:4) add("cumn", c(xi, om, al, tau, k), unname(cm[k]), rel = 1e-9) }
# multivariate: args (d, extra, n, seed, index, xi(d), Omega(d*d), alpha(d), x(d)); extra is tau for dmsn/rmsn, nu for dmst/rmst
mvcase <- function(d) { A <- matrix(round(rnorm(d * d), 2), d, d); Om <- round(crossprod(A) + diag(0.5, d), 4); Om <- (Om + t(Om)) / 2
  list(xi = round(rnorm(d), 2), Om = Om, al = round(runif(d, -3, 3), 2), x = round(rnorm(d), 2)) }
mvpack <- function(d, ex, n, sd, idx, p) c(d, ex, n, sd, idx, p$xi, as.numeric(t(p$Om)), p$al, p$x)
for (rep in 1:30) { d <- c(1, 2, 3, 4)[(rep - 1) %% 4 + 1]; p <- mvcase(d)
  tau <- c(0, 0.6, -1)[sample(3, 1)]; nu <- c(2.5, 5, 9, 40)[sample(4, 1)]
  add("dmsn", mvpack(d, tau, 0, 0, 0, p), dmsn(p$x, p$xi, p$Om, p$al, tau), rel = 1e-9)
  add("dmst", mvpack(d, nu, 0, 0, 0, p), dmst(p$x, p$xi, p$Om, p$al, nu), rel = 1e-9)
  n <- sample(3:8, 1); sd <- sample(1:100000, 1)
  set.seed(sd); r <- as.numeric(t(matrix(rmsn(n, p$xi, p$Om, p$al, tau), n, d))); for (k in seq_len(n * d)) add("rmsn", mvpack(d, tau, n, sd, k - 1, p), r[k], rel = 1e-9)
  nu2 <- c(3, 7.5, 30, Inf)[sample(4, 1)]
  set.seed(sd); r <- as.numeric(t(matrix(rmst(n, p$xi, p$Om, p$al, nu2), n, d))); for (k in seq_len(n * d)) add("rmst", mvpack(d, nu2, n, sd, k - 1, p), r[k], rel = 1e-9) }
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
# multivariate centred parameters "mvcp": args (kind 0 dp2cp SN / 1 dp2cp ST / 2 cp2dp SN, d, extra (tau or nu), index, v1(d), mat(d*d), v2(d)); the output is the flattened list
# (mean, var.cov, gamma1) for kinds 0 and 1, (xi, Omega, alpha) for kind 2
for (rep in 1:36) { d <- c(2, 3, 4)[(rep - 1) %% 3 + 1]; p <- mvcase(d); kind <- (rep - 1) %/% 3 %% 3
  if (kind == 0) { tau <- c(0, 0.6, -1)[sample(3, 1)]; cp <- dp2cp(list(xi = p$xi, Omega = p$Om, alpha = p$al, tau = tau), "SN"); flat <- c(cp$mean, as.numeric(t(cp$var.cov)), cp$gamma1); ex <- tau }
  if (kind == 1) { nu <- c(5.5, 8, 30)[sample(3, 1)]; cp <- dp2cp(list(xi = p$xi, Omega = p$Om, alpha = p$al, nu = nu), "ST"); flat <- c(cp$mean, as.numeric(t(cp$var.cov)), cp$gamma1); ex <- nu }
  if (kind == 2) { cp <- dp2cp(list(xi = p$xi, Omega = p$Om, alpha = p$al), "SN"); dp <- cp2dp(list(mean = cp$mean, var.cov = cp$var.cov, gamma1 = cp$gamma1), "SN"); if (is.null(dp)) next
    flat <- c(dp$xi, as.numeric(t(dp$Omega)), dp$alpha); ex <- 0; p <- list(xi = cp$mean, Om = cp$var.cov, al = cp$gamma1) }
  for (k in seq_along(flat)) add("mvcp", c(kind, d, ex, k - 1, p$xi, as.numeric(t(p$Om)), p$al), flat[k], rel = 1e-8) }
# matrix-response selm: args (family 0 SN / 1 ST, penalised, n, d, p, which, y(n*d row-major), x(n*p row-major)); the output is beta (row j, comp k), Omega, alpha, nu (ST), log-likelihood
mvsel_case <- function(fam, pen, n, d, p, sd) {
  set.seed(sd); x1 <- round(rnorm(n), 2)
  A <- matrix(round(rnorm(d * d, sd = 0.4), 2), d, d); Om <- crossprod(A) + diag(d); al <- c(3, -2.5, 2)[seq_len(d)]
  z <- if (fam == 0) rmsn(n, rep(0, d), Om, al) else rmst(n, rep(0, d), Om, al, c(5, 7)[sample(2, 1)])
  y <- round(z + 1 + (if (p == 2) outer(x1, c(0.5, -0.3, 0.2)[seq_len(d)]) else 0), 4)
  colnames(y) <- paste0("y", seq_len(d)); X <- if (p == 2) cbind(1, x1) else matrix(1, n, 1)
  frm <- if (p == 2) y ~ x1 else y ~ 1
  if (fam == 1 && pen) return(invisible())
  fit <- tryCatch(selm(frm, family = if (fam == 0) "SN" else "ST", method = if (pen) "MPLE" else "MLE"), error = function(e) NULL)
  if (is.null(fit)) return(invisible())
  dp <- coef(fit, "DP", vector = FALSE); ll <- as.numeric(logLik(fit))
  flat <- c(as.numeric(t(as.matrix(dp$beta))), as.numeric(t(dp$Omega)), dp$alpha, if (fam == 1) dp$nu)
  if (fam == 1 && dp$nu > 30) return(invisible())
  for (k in unique(c(1, p * d + d * d + 1))) add("mvselm", c(fam, pen, n, d, p, k - 1, as.numeric(t(y)), as.numeric(t(X))), flat[k], rel = 5e-3, abs = 2e-3)
  add("mvselm", c(fam, pen, n, d, p, length(flat), as.numeric(t(y)), as.numeric(t(X))), ll, rel = 1e-4)
}
for (rep in 1:3) for (fam in 0:1) for (pen in 0:1) mvsel_case(fam, pen, 300, 2, c(1, 2)[rep %% 2 + 1], 8000 + rep * 10 + fam * 2 + pen)
# skew-Cauchy: dsc (xi, omega, alpha, 0, x) and rsc (xi, omega, alpha, 0, n, seed, index), plus dmsc / rmsc through the multivariate layout
for (rep in 1:20) { xi <- round(rnorm(1), 2); om <- c(0.5, 1, 2)[sample(3, 1)]; al <- c(-3, -0.5, 1, 4, 9)[sample(5, 1)]
  for (x in xi + om * c(-8, -1.5, -0.2, 0.4, 1.3, 6)) add("dsc", c(xi, om, al, 0, x), dsc(x, xi, om, al), rel = 1e-10)
  n <- sample(4:9, 1); sd <- sample(1:100000, 1); set.seed(sd); r <- as.numeric(rsc(n, xi, om, al)); for (k in seq_len(n)) add("rsc", c(xi, om, al, 0, n, sd, k - 1), r[k], rel = 1e-9) }
for (rep in 1:8) { d <- c(2, 3)[rep %% 2 + 1]; p <- mvcase(d); n <- sample(3:6, 1); sd <- sample(1:100000, 1)
  add("dmsc", mvpack(d, 1, 0, 0, 0, p), dmsc(p$x, p$xi, p$Om, p$al), rel = 1e-9)
  set.seed(sd); r <- as.numeric(t(matrix(rmsc(n, p$xi, p$Om, p$al), n, d))); for (k in seq_len(n * d)) add("rmsc", mvpack(d, 1, n, sd, k - 1, p), r[k], rel = 1e-9) }
emit("sn", "sn", list(cases))
