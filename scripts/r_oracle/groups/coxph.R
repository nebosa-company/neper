# survival::coxph, Breslow and Efron ties, one stratum.
#   args: (n, p, efron, time[n], status[n], X[n*p] column-major, q)  q in 0..p-1 coefficient, p..2p-1 se, 2p loglik at 0, 2p+1 loglik at the fit
suppressMessages(library(survival))
cases <- list()
set.seed(20261116)
for (rep in 1:14) {
  n <- sample(25:70, 1); p <- sample(1:3, 1)
  X <- matrix(round(rnorm(n * p), 2), n, p)
  tm <- ceiling(rexp(n, exp(0.5 * X[, 1])) * 5) + ifelse(rep %% 2 == 0, 0, round(runif(n), 3))
  st <- rbinom(n, 1, 0.75); if (sum(st) < 5) st[1:6] <- 1
  for (ef in c(1, 0)) {
    f <- coxph(Surv(tm, st) ~ X, ties = if (ef) "efron" else "breslow", control = coxph.control(eps = 1e-12, iter.max = 50))
    a <- c(n, p, ef, tm, st, X)
    out <- c(coef(f), sqrt(diag(vcov(f))), f$loglik)
    for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("cox", c(a, q - 1), out[q], rel = 1e-6, abs = 1e-8)
  }
}
# strata, an offset and the robust variance: "coxs" args (n, p, efron, robust, time, status, strata (0-based), offset, X column-major, q) q in 0..p-1 coefficient, p..2p-1 se, 2p loglik at the fit
for (rep in 1:14) {
  n <- sample(30:60, 1); p <- sample(1:2, 1); X <- matrix(round(rnorm(n * p), 2), n, p)
  tm <- ceiling(rexp(n, exp(0.5 * X[, 1])) * 5) + ifelse(rep %% 2 == 0, 0, round(runif(n), 3)); st <- rbinom(n, 1, 0.75); if (sum(st) < 6) st[1:8] <- 1
  sg <- sample(0:2, n, TRUE); off <- round(rnorm(n, 0, 0.3), 2)
  for (cfg in list(c(1, 0), c(0, 0), c(0, 1))) {
    ef <- cfg[1]; rb <- cfg[2]
    f <- coxph(Surv(tm, st) ~ X + strata(sg) + offset(off), ties = if (ef) "efron" else "breslow", robust = rb == 1, control = coxph.control(eps = 1e-12, iter.max = 50))
    a <- c(n, p, ef, rb, tm, st, sg, off, X)
    se <- if (rb == 1) sqrt(diag(f$var)) else sqrt(diag(vcov(f)))
    out <- c(coef(f), se, f$loglik[2])
    for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("coxs", c(a, q - 1), out[q], rel = 1e-6, abs = 1e-8)
  }
}
# cox.zph with distinct times: "zph" args (n, p, transform 0 identity / 1 rank / 2 log / 3 km, time, status, X column-major, q) q 0..p-1 the term chi-squares, p the global chi-square, p + 1.. the p values
for (rep in 1:14) {
  n <- sample(30:60, 1); p <- sample(1:3, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  tm <- round(rexp(n, exp(0.4 * X[, 1])) * 5, 4) + runif(n) * 1e-3; st <- rbinom(n, 1, 0.8); if (sum(st) < 8) st[1:10] <- 1
  dz <- as.data.frame(X); names(dz) <- paste0("v", 1:p); dz$tm <- tm; dz$st <- st
  f <- coxph(as.formula(paste("Surv(tm, st) ~", paste0("v", 1:p, collapse = " + "))), data = dz, control = coxph.control(eps = 1e-12, iter.max = 50))
  for (tr in 0:3) {
    z <- cox.zph(f, transform = c("identity", "rank", "log", "km")[tr + 1])
    out <- c(z$table[, "chisq"], z$table[, "p"])
    ntab <- nrow(z$table)
    for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("zph", c(n, p, tr, tm, st, X, if (q <= ntab) q - 1 else q - 1), out[q], rel = 1e-5, abs = 1e-8)
  }
}
# residuals of a Breslow fit with strata and an offset: "cres" args (n, p, kind 0 martingale / 1 deviance, time, status, strata, offset, X column-major, row)
for (rep in 1:14) {
  n <- sample(30:60, 1); p <- sample(1:2, 1); X <- matrix(round(rnorm(n * p), 2), n, p)
  tm <- ceiling(rexp(n, exp(0.5 * X[, 1])) * 5) + round(runif(n), 3); st <- rbinom(n, 1, 0.75); if (sum(st) < 6) st[1:8] <- 1
  sg <- sample(0:1, n, TRUE); off <- round(rnorm(n, 0, 0.3), 2)
  dz <- as.data.frame(X); names(dz) <- paste0("v", 1:p); dz$tm <- tm; dz$st <- st; dz$sg <- sg; dz$off <- off
  f <- coxph(as.formula(paste("Surv(tm, st) ~", paste0("v", 1:p, collapse = " + "), "+ strata(sg) + offset(off)")), data = dz, ties = "breslow", control = coxph.control(eps = 1e-12, iter.max = 50))
  mr <- residuals(f, type = "martingale"); dr <- residuals(f, type = "deviance")
  for (r in sample(n, 6)) {
    cases[[length(cases) + 1]] <- case("cres", c(n, p, 0, tm, st, sg, off, X, r - 1), mr[r], rel = 1e-6, abs = 1e-8)
    cases[[length(cases) + 1]] <- case("cres", c(n, p, 1, tm, st, sg, off, X, r - 1), dr[r], rel = 1e-6, abs = 1e-8)
  }
}
# counting-process data: "coxcp" args (n, p, efron, start, stop, status, strata (0-based), X column-major, q) q in 0..p-1 coefficient, p..2p-1 se, 2p loglik at 0, 2p+1 loglik at the fit
for (rep in 1:16) {
  n <- sample(30:70, 1); p <- sample(1:2, 1); X <- matrix(round(rnorm(n * p), 2), n, p)
  st0 <- ceiling(runif(n, 0, 6)); if (rep %% 2 == 0) st0 <- st0 + round(runif(n), 2)
  stp <- st0 + 1 + ceiling(rexp(n, exp(0.4 * X[, 1])) * 4) + (if (rep %% 3 == 0) round(runif(n), 2) else 0)
  ev <- rbinom(n, 1, 0.75); if (sum(ev) < 6) ev[1:8] <- 1; sg <- sample(0:1, n, TRUE)
  for (ef in c(1, 0, 2)) {
    f <- tryCatch(coxph(Surv(st0, stp, ev) ~ X + strata(sg), ties = c("breslow", "efron", "exact")[ef + 1], control = coxph.control(eps = 1e-12, iter.max = 50)), error = function(e) NULL)
    if (is.null(f)) next
    a <- c(n, p, ef, st0, stp, ev, sg, X)
    out <- c(as.numeric(f$coefficients), sqrt(diag(as.matrix(f$var))), f$loglik)
    for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("coxcp", c(a, q - 1), out[q], rel = 1e-6, abs = 1e-8)
    if (ef == 0) {
      rs <- residuals(f, type = "schoenfeld"); rs <- as.matrix(rs)
      for (j in seq_len(p)) cases[[length(cases) + 1]] <- case("coxcp", c(a, 200 + j - 1), sum(rs[, j]^2), rel = 1e-6, abs = 1e-8)
    }
    if (ef == 0) {
      fr <- coxph(Surv(st0, stp, ev) ~ X + strata(sg) + cluster(seq_len(n)), ties = "breslow", robust = TRUE, control = coxph.control(eps = 1e-12, iter.max = 50))
      rse <- sqrt(diag(as.matrix(fr$var)))
      for (j in seq_len(p)) cases[[length(cases) + 1]] <- case("coxcp", c(a, 100 + j - 1), rse[j], rel = 1e-6, abs = 1e-8)
    }
  }
}
# tmerge: "tmg" args (kind 0 tdc 1 cumevent, nsub, m, futime[nsub], status[nsub], sid[m] 0-based, tm[m], val[m], stat) stat 0 rows, 1 sum(i tstart), 2 sum(i tstop), 3 sum(i x) with NA as -1, 4 sum(i death)
for (rep in 1:24) {
  ns <- sample(4:9, 1); ft <- sample(5:15, ns, TRUE); stt <- rbinom(ns, 1, 0.6); m <- sample(6:18, 1); sid <- sample(ns, m, TRUE)
  tmv <- sample(c(0:(max(ft) + 2)), m, TRUE); vv <- round(rnorm(m), 2); kind <- rep %% 2
  d1 <- data.frame(id = 1:ns, futime = ft, status = stt); d2 <- data.frame(id = sid, time = tmv, value = vv)
  t1 <- tmerge(d1, d1, id = id, death = event(futime, status))
  t2 <- if (kind == 0) tmerge(t1, d2, id = id, x = tdc(time, value)) else tmerge(t1, d2, id = id, x = cumevent(time))
  xv <- t2$x; xv[is.na(xv)] <- -1; ii <- seq_len(nrow(t2))
  st <- c(nrow(t2), sum(ii * t2$tstart), sum(ii * t2$tstop), sum(ii * xv), sum(ii * t2$death))
  a <- c(kind, ns, m, ft, stt, sid - 1, tmv, vv)
  for (q in 0:3) cases[[length(cases) + 1]] <- case("tmg", c(a, q), st[q + 1], rel = 1e-9, abs = 1e-9)
}
emit("coxph", "survival", list(cases))
