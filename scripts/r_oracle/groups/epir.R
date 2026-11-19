# epiR: epi.2by2 (cohort.count) measures of association.
#   args: (a, b, c, d, units, which)   fn "m": which 0..2 risk ratio (est, lower, upper), 3..5 odds ratio, 6..8 risk difference per units, 9..11 number needed to treat,
#   12 population attributable risk, 13 14 Wald test of the risk ratio (z, p two-sided), 15 16 of the odds ratio, 17 18 Pearson chi2 (statistic, p), 19 20 Yates chi2
suppressMessages(library(epiR))
cases <- list()
add <- function(which, a, want) cases[[length(cases) + 1]] <<- case("m", c(a, which), want, rel = 1e-8, abs = 1e-10)
set.seed(20261221)
for (rep in 1:25) {
  a <- sample(3:200, 1); b <- sample(50:3000, 1); cc <- sample(2:150, 1); d <- sample(50:4000, 1); un <- c(100, 1000, 1)[rep %% 3 + 1]
  dat <- as.table(matrix(c(a, b, cc, d), nrow = 2, byrow = TRUE))
  r <- epi.2by2(dat = dat, method = "cohort.count", conf.level = 0.95, units = un, interpret = FALSE, outcome = "as.columns")$massoc.detail
  base <- c(a, b, cc, d, un)
  for (i in 1:3) add(i - 1, base, unlist(r$RR.strata.taylor[1, ])[i])
  for (i in 1:3) add(2 + i, base, unlist(r$OR.strata.wald[1, ])[i])
  for (i in 1:3) add(5 + i, base, unlist(r$ARisk.strata.wald[1, ])[i])
  nn <- unlist(r$NNT.strata.wald[1, ]); for (i in 1:3) add(8 + i, base, nn[i])
  add(12, base, r$PARisk.strata.wald$est)
  add(13, base, r$wald.strata.rr$test.statistic); add(14, base, r$wald.strata.rr$p.value.2s)
  add(15, base, r$wald.strata.or$test.statistic); add(16, base, r$wald.strata.or$p.value.2s)
  add(17, base, r$chi2.strata.uncor$test.statistic); add(18, base, r$chi2.strata.uncor$p.value.2s)
  add(19, base, r$chi2.strata.yates$test.statistic); add(20, base, r$chi2.strata.yates$p.value.2s)
  # 21..23 score risk ratio, 33..35 attributable fraction in the exposed, 36..38 Koopman risk ratio
  for (i in 1:3) add(20 + i, base, unlist(r$RR.strata.score[1, ])[i])
  for (i in 1:3) add(32 + i, base, unlist(r$AFRisk.strata.wald[1, ])[i])
  for (i in 1:3) add(35 + i, base, unlist(r$RR.strata.koopman[1, ])[i])
  # 24..26 population attributable fraction, 27..29 population attributable risk (Wald), 30..32 (Pirikahu)
  {
    for (i in 1:3) add(23 + i, base, unlist(r$PAFRisk.strata.wald[1, ])[i])
  }
  for (i in 1:3) add(26 + i, base, unlist(r$PARisk.strata.wald[1, ])[i])
  for (i in 1:3) add(29 + i, base, unlist(r$PARisk.strata.piri[1, ])[i])
}
# epi.tests (exact intervals): fn "dt" args (a, b, c, d, stat * 3 + part): stat 0 ap, 1 tp, 2 se, 3 sp, 4 diag.ac, 5 diag.or, 6 nndx, 7 youden, 8 pv.pos, 9 pv.neg, 10 lr.pos, 11 lr.neg; part 0 est 1 lower 2 upper
for (rep in 1:25) {
  a <- sample(20:400, 1); b <- sample(10:300, 1); cc <- sample(5:150, 1); d <- sample(30:600, 1)
  dat <- as.table(matrix(c(a, b, cc, d), 2, byrow = TRUE))
  r <- epi.tests(dat, conf.level = 0.95)$detail
  nm <- c("ap", "tp", "se", "sp", "diag.ac", "diag.or", "nndx", "youden", "pv.pos", "pv.neg", "lr.pos", "lr.neg")
  for (i in seq_along(nm)) { row <- r[r$statistic == nm[i], ]; for (j in 1:3) cases[[length(cases) + 1]] <- case("dt", c(a, b, cc, d, (i - 1) * 3 + j - 1), as.numeric(row[1, j + 1]), rel = 1e-8, abs = 1e-12) }
  for (mi in 1:3) {
    rm <- epi.tests(dat, method = c("wilson", "agresti", "jeffreys")[mi], conf.level = 0.95)$detail
    for (i in seq_along(nm)) { row <- rm[rm$statistic == nm[i], ]; for (j in 1:3) cases[[length(cases) + 1]] <- case("dt", c(a, b, cc, d, mi * 100 + (i - 1) * 3 + j - 1), as.numeric(row[1, j + 1]), rel = 1e-8, abs = 1e-12) }
  }
}
# epi.conf proportions: "pc" args (x, n, method 0 exact 1 wilson 2 agresti 3 jeffreys, part 0 est 1 lower 2 upper)
for (rep in 1:30) {
  n <- sample(10:500, 1); x <- sample(1:(n - 1), 1)
  for (mi in 0:3) {
    r <- epi.conf(as.matrix(cbind(x, n)), ctype = "prevalence", method = c("exact", "wilson", "agresti", "jeffreys")[mi + 1], conf.level = 0.95)
    v <- c(r$est, r$lower, r$upper)
    for (pt in 0:2) cases[[length(cases) + 1]] <- case("pc", c(x, n, mi, pt), v[pt + 1], rel = 1e-8, abs = 1e-12)
  }
}
# epi.2by2 case.control: "cc" args (a, b, c, d, which 0..2 score odds ratio (est, lower, upper), 3..5 attributable fraction)
for (rep in 1:25) {
  a <- sample(10:200, 1); b <- sample(10:200, 1); cc <- sample(10:300, 1); d <- sample(10:300, 1)
  dat <- as.table(matrix(c(a, b, cc, d), 2, byrow = TRUE))
  r <- epi.2by2(dat, method = "case.control", interpret = FALSE, outcome = "as.columns")$massoc.detail
  for (i in 1:3) cases[[length(cases) + 1]] <- case("cc", c(a, b, cc, d, i - 1), unlist(r$OR.strata.score[1, ])[i], rel = 1e-8, abs = 1e-12)
  for (i in 1:3) cases[[length(cases) + 1]] <- case("cc", c(a, b, cc, d, 2 + i), unlist(r$AFest.strata.wald[1, ])[i], rel = 1e-8, abs = 1e-12)
}
# epi.ccc: "ccc" args (n, x[n], y[n], which 0 rho_c, 1 2 asymptotic lower upper, 3 4 z-transform lower upper, 5 s.shift, 6 l.shift, 7 C.b, 8 mean difference, 9 sd of differences)
for (rep in 1:30) {
  n <- sample(8:60, 1); x <- rnorm(n, 5, 2); y <- x * runif(1, 0.7, 1.2) + rnorm(n, runif(1, -0.5, 0.8), runif(1, 0.3, 1.5))
  ra <- epi.ccc(x, y, ci = "asymptotic", conf.level = 0.95); rz <- epi.ccc(x, y, ci = "z-transform", conf.level = 0.95)
  v <- c(ra$rho.c$est, ra$rho.c$lower, ra$rho.c$upper, rz$rho.c$lower, rz$rho.c$upper, ra$s.shift, ra$l.shift, ra$C.b, ra$sblalt$est, ra$sblalt$delta.sd)
  for (w in 0:9) cases[[length(cases) + 1]] <- case("ccc", c(n, x, y, w), v[w + 1], rel = 1e-8, abs = 1e-12)
}
# epi.sscohortc: "sc" args (irexp1, irexp0, r, design, N (0 for none), sided, frac, power or n, which 0 n.exp1, 1 n.exp0, 2 n.total, 3 power from n)
for (rep in 1:40) {
  i0 <- runif(1, 0.05, 0.3); i1 <- i0 * runif(1, 1.4, 2.5); r <- sample(c(1, 2, 3), 1); des <- sample(c(1, 1.5, 2), 1); NN <- if (rep %% 2 == 0) NA else sample(2000:20000, 1); sd <- sample(1:2, 1); fr <- rep %% 3 == 0; pw <- runif(1, 0.7, 0.95)
  res <- epi.sscohortc(N = NN, irexp1 = i1, irexp0 = i0, pexp = NA, power = pw, r = r, design = des, sided.test = sd, nfractional = fr, n = NA)
  for (w in 0:2) cases[[length(cases) + 1]] <- case("sc", c(i1, i0, r, des, if (is.na(NN)) 0 else NN, sd, as.numeric(fr), pw, w), c(res$n.exp1, res$n.exp0, res$n.total)[w + 1], rel = 1e-9, abs = 1e-9)
  nn <- sample(100:900, 1)
  rp <- epi.sscohortc(N = NN, irexp1 = i1, irexp0 = i0, pexp = NA, n = nn, power = NA, r = r, design = des, sided.test = sd)
  cases[[length(cases) + 1]] <- case("sc", c(i1, i0, r, des, if (is.na(NN)) 0 else NN, sd, 0, nn, 3), rp$power, rel = 1e-8, abs = 1e-10)
}
# epi.sscc unmatched: "ss" args (OR, p0, r, design, N (0 none), sided, frac, power or n, which 0 cases 1 controls 2 total 3 power from n)
for (rep in 1:40) {
  orr <- runif(1, 1.5, 4); p0 <- runif(1, 0.1, 0.5); r <- sample(1:3, 1); des <- sample(c(1, 1.5), 1); NN <- if (rep %% 2 == 0) NA else sample(2000:20000, 1); sd <- sample(1:2, 1); fr <- rep %% 3 == 0; pw <- runif(1, 0.7, 0.95)
  res <- epi.sscc(N = NN, OR = orr, p1 = NA, p0 = p0, power = pw, n = NA, r = r, design = des, sided.test = sd, nfractional = fr)
  for (w in 0:2) cases[[length(cases) + 1]] <- case("ss", c(orr, p0, r, des, if (is.na(NN)) 0 else NN, sd, as.numeric(fr), pw, w), c(res$n.case, res$n.control, res$n.total)[w + 1], rel = 1e-9, abs = 1e-9)
  nn <- sample(100:900, 1)
  rp <- epi.sscc(N = NA, OR = orr, p1 = NA, p0 = p0, n = nn, power = NA, r = r, design = 1, sided.test = sd)
  cases[[length(cases) + 1]] <- case("ss", c(orr, p0, r, 1, 0, sd, 0, nn, 3), rp$power, rel = 1e-8, abs = 1e-10)
}
# epi.dsl (odds ratios): "dsl" args (k, ev_t[k], n_t[k], ev_c[k], n_c[k], which 0 tau2, 1 pooled OR, 2 lower, 3 upper, 4 Q, 5 p, 6 I2)
for (rep in 1:25) {
  k <- sample(4:10, 1); nt <- sample(60:300, k); nc <- sample(60:300, k); evt <- rbinom(k, nt, runif(1, 0.05, 0.2)); evc <- rbinom(k, nc, runif(1, 0.1, 0.3))
  m <- suppressWarnings(epi.dsl(evt, nt, evc, nc, names = as.character(1:k), method = "odds.ratio"))
  v <- c(m$tau.sq, m$OR.summary$est, m$OR.summary$lower, m$OR.summary$upper, unname(m$heterogeneity["Q"]), unname(m$heterogeneity["p.value"]), m$Isq$est)
  if (any(!is.finite(v))) next
  for (w in 0:6) cases[[length(cases) + 1]] <- case("dsl", c(k, evt, nt, evc, nc, w), v[w + 1], rel = 1e-8, abs = 1e-10)
}
# epi.iv (odds ratios): "iv" args (k, ev_t[k], n_t[k], ev_c[k], n_c[k], which 0 OR 1 2 interval, 3 Q, 4 p, 5 I2, 6 7 8 H2 (est, lower, upper), 9 10 I2 (lower, upper), 11 z, 12 p)
for (rep in 1:25) {
  k <- sample(4:10, 1); nt <- sample(60:300, k); nc <- sample(60:300, k); evt <- rbinom(k, nt, runif(1, 0.05, 0.2)); evc <- rbinom(k, nc, runif(1, 0.1, 0.3))
  m <- suppressWarnings(epi.iv(evt, nt, evc, nc, names = as.character(1:k), method = "odds.ratio"))
  v <- c(m$OR.summary$est, m$OR.summary$lower, m$OR.summary$upper, unname(m$heterogeneity["Q"]), unname(m$heterogeneity["p.value"]), m$Isq$est, m$Hsq$est, m$Hsq$lower, m$Hsq$upper, m$Isq$lower, m$Isq$upper, unname(m$effect["z"]), unname(m$effect["p.value"]))
  if (any(!is.finite(v))) next
  for (w in 0:12) cases[[length(cases) + 1]] <- case("iv", c(k, evt, nt, evc, nc, w), v[w + 1], rel = 1e-8, abs = 1e-10)
}
# epi.sssimpleestb: "sb" args (N (0 none), Py, epsilon, absolute, se, sp, frac)
for (rep in 1:40) {
  NN <- if (rep %% 2 == 0) NA else sample(5000:90000, 1); py <- runif(1, 0.05, 0.5); ab <- rep %% 3 == 0; eps <- if (ab) runif(1, 0.02, 0.1) else runif(1, 0.1, 0.3); se <- runif(1, 0.7, 0.99); sp <- runif(1, 0.7, 0.99); fr <- rep %% 4 == 0
  v <- epi.sssimpleestb(N = NN, Py = py, epsilon = eps, error = if (ab) "absolute" else "relative", se = se, sp = sp, nfractional = fr)
  cases[[length(cases) + 1]] <- case("sb", c(if (is.na(NN)) 0 else NN, py, eps, as.numeric(ab), se, sp, as.numeric(fr)), v, rel = 1e-9, abs = 1e-9)
}
# epi.2by2 cross.sectional: the same measures under the prevalence-ratio names ("m" which 0..20, 24..32 as for cohort.count)
for (rep in 1:20) {
  a <- sample(3:200, 1); b <- sample(50:3000, 1); cc <- sample(2:150, 1); d <- sample(50:4000, 1); un <- c(100, 1000, 1)[rep %% 3 + 1]
  dat <- as.table(matrix(c(a, b, cc, d), nrow = 2, byrow = TRUE))
  r <- epi.2by2(dat = dat, method = "cross.sectional", conf.level = 0.95, units = un, interpret = FALSE, outcome = "as.columns")$massoc.detail
  base <- c(a, b, cc, d, un)
  for (i in 1:3) add(i - 1, base, unlist(r$PR.strata.taylor[1, ])[i])
  for (i in 1:3) add(2 + i, base, unlist(r$OR.strata.wald[1, ])[i])
  for (i in 1:3) add(5 + i, base, unlist(r$ARisk.strata.wald[1, ])[i])
  nn <- unlist(r$NNT.strata.wald[1, ]); for (i in 1:3) add(8 + i, base, nn[i])
  add(12, base, r$PARisk.strata.wald$est)
  add(13, base, r$wald.strata.rr$test.statistic); add(14, base, r$wald.strata.rr$p.value.2s)
  add(15, base, r$wald.strata.or$test.statistic); add(16, base, r$wald.strata.or$p.value.2s)
  add(17, base, r$chi2.strata.uncor$test.statistic); add(18, base, r$chi2.strata.uncor$p.value.2s)
  add(19, base, r$chi2.strata.yates$test.statistic); add(20, base, r$chi2.strata.yates$p.value.2s)
  for (i in 1:3) add(26 + i, base, unlist(r$PARisk.strata.wald[1, ])[i])
  for (i in 1:3) add(29 + i, base, unlist(r$PARisk.strata.piri[1, ])[i])
  for (i in 1:3) add(23 + i, base, unlist(r$PAFRisk.strata.wald[1, ])[i])
  for (i in 1:3) add(20 + i, base, unlist(r$PR.strata.score[1, ])[i])
  for (i in 1:3) add(32 + i, base, unlist(r$AFRisk.strata.wald[1, ])[i])
}
# epi.iv (risk ratios): "ivr" as "iv"
for (rep in 1:25) {
  k <- sample(4:10, 1); nt <- sample(60:300, k); nc <- sample(60:300, k); evt <- rbinom(k, nt, runif(1, 0.05, 0.2)); evc <- rbinom(k, nc, runif(1, 0.1, 0.3))
  m <- suppressWarnings(epi.iv(evt, nt, evc, nc, names = as.character(1:k), method = "risk.ratio"))
  v <- c(m$RR.summary$est, m$RR.summary$lower, m$RR.summary$upper, unname(m$heterogeneity["Q"]), unname(m$heterogeneity["p.value"]), m$Isq$est, m$Hsq$est, m$Hsq$lower, m$Hsq$upper, m$Isq$lower, m$Isq$upper, unname(m$effect["z"]), unname(m$effect["p.value"]))
  if (any(!is.finite(v))) next
  for (w in 0:12) cases[[length(cases) + 1]] <- case("ivr", c(k, evt, nt, evc, nc, w), v[w + 1], rel = 1e-8, abs = 1e-10)
}
# epi.dsl (risk ratios): "dslr" as "dsl"
for (rep in 1:25) {
  k <- sample(4:10, 1); nt <- sample(60:300, k); nc <- sample(60:300, k); evt <- rbinom(k, nt, runif(1, 0.05, 0.2)); evc <- rbinom(k, nc, runif(1, 0.1, 0.3))
  m <- suppressWarnings(epi.dsl(evt, nt, evc, nc, names = as.character(1:k), method = "risk.ratio"))
  v <- c(m$tau.sq, m$RR.summary$est, m$RR.summary$lower, m$RR.summary$upper, unname(m$heterogeneity["Q"]), unname(m$heterogeneity["p.value"]), m$Isq$est)
  if (any(!is.finite(v))) next
  for (w in 0:6) cases[[length(cases) + 1]] <- case("dslr", c(k, evt, nt, evc, nc, w), v[w + 1], rel = 1e-8, abs = 1e-10)
}
# epi.2by2 stratified cohort.count: "mh" args (K, a[K], b[K], c[K], d[K], which 0..2 MH RR, 3..5 MH OR, 6 MH chi2, 7 Woolf RR homogeneity, 8 Woolf OR homogeneity)
for (rep in 1:25) {
  K <- sample(2:5, 1); a <- sample(8:120, K, TRUE); b <- sample(40:600, K, TRUE); cc <- sample(5:100, K, TRUE); d <- sample(40:700, K, TRUE)
  arr <- array(0, dim = c(2, 2, K)); for (s in 1:K) arr[, , s] <- matrix(c(a[s], b[s], cc[s], d[s]), 2, byrow = TRUE)
  r <- suppressWarnings(epi.2by2(as.table(arr), method = "cohort.count", interpret = FALSE, outcome = "as.columns"))$massoc.detail
  v <- c(unlist(r$RR.mh.wald[1, ]), unlist(r$OR.mh.wald[1, ]), r$chi2.mh$test.statistic, r$wRR.homog$test.statistic, r$wOR.homog$test.statistic)
  for (w in 0:8) cases[[length(cases) + 1]] <- case("mh", c(K, a, b, cc, d, w), unname(v[w + 1]), rel = 1e-8, abs = 1e-10)
}
# epi.2by2 stratified: Mantel-Haenszel risk difference and NNT: "mr" args (K, units, a[K], b[K], c[K], d[K], which 0..2 RD, 3..5 NNT)
for (rep in 1:25) {
  K <- sample(2:5, 1); a <- sample(8:120, K, TRUE); b <- sample(40:600, K, TRUE); cc <- sample(5:100, K, TRUE); d <- sample(40:700, K, TRUE); un <- c(100, 1000, 1)[rep %% 3 + 1]
  arr <- array(0, dim = c(2, 2, K)); for (s in 1:K) arr[, , s] <- matrix(c(a[s], b[s], cc[s], d[s]), 2, byrow = TRUE)
  r <- suppressWarnings(epi.2by2(as.table(arr), method = "cohort.count", interpret = FALSE, outcome = "as.columns", units = un))$massoc.detail
  v <- c(unlist(r$ARisk.mh.wald[1, ]), unlist(r$NNT.mh.wald[1, ]))
  for (w in 0:5) cases[[length(cases) + 1]] <- case("mr", c(K, un, a, b, cc, d, w), unname(v[w + 1]), rel = 1e-8, abs = 1e-10)
}
# Sato and Greenland-Robins Mantel-Haenszel risk differences: "ms" args (K, units, a[K], b[K], c[K], d[K], which 0..2 Sato, 3..5 Greenland-Robins)
for (rep in 1:25) {
  K <- sample(2:5, 1); a <- sample(8:120, K, TRUE); b <- sample(40:600, K, TRUE); cc <- sample(5:100, K, TRUE); d <- sample(40:700, K, TRUE); un <- c(100, 1000, 1)[rep %% 3 + 1]
  arr <- array(0, dim = c(2, 2, K)); for (s in 1:K) arr[, , s] <- matrix(c(a[s], b[s], cc[s], d[s]), 2, byrow = TRUE)
  r <- suppressWarnings(epi.2by2(as.table(arr), method = "cohort.count", interpret = FALSE, outcome = "as.columns", units = un))$massoc.detail
  v <- c(unlist(r$ARisk.mh.sato[1, ]), unlist(r$ARisk.mh.green[1, ]))
  for (w in 0:5) cases[[length(cases) + 1]] <- case("ms", c(K, un, a, b, cc, d, w), unname(v[w + 1]), rel = 1e-8, abs = 1e-10)
}
# Breslow-Day: "bd" args (K, a[K], b[K], c[K], d[K])
for (rep in 1:30) {
  K <- sample(2:5, 1); a <- sample(8:120, K, TRUE); b <- sample(40:600, K, TRUE); cc <- sample(5:100, K, TRUE); d <- sample(40:700, K, TRUE)
  arr <- array(0, dim = c(2, 2, K)); for (s in 1:K) arr[, , s] <- matrix(c(a[s], b[s], cc[s], d[s]), 2, byrow = TRUE)
  r <- suppressWarnings(epi.2by2(as.table(arr), method = "cohort.count", interpret = FALSE, outcome = "as.columns"))$massoc.detail
  cases[[length(cases) + 1]] <- case("bd", c(K, a, b, cc, d), r$bOR.homog$test.statistic, rel = 1e-8, abs = 1e-10)
}
# crude tables of stacked strata: the collapsed table through the "m" measures
for (rep in 1:20) {
  K <- sample(2:5, 1); a <- sample(8:120, K, TRUE); b <- sample(40:600, K, TRUE); cc <- sample(5:100, K, TRUE); d <- sample(40:700, K, TRUE); un <- c(100, 1000, 1)[rep %% 3 + 1]
  arr <- array(0, dim = c(2, 2, K)); for (s in 1:K) arr[, , s] <- matrix(c(a[s], b[s], cc[s], d[s]), 2, byrow = TRUE)
  r <- suppressWarnings(epi.2by2(as.table(arr), method = "cohort.count", interpret = FALSE, outcome = "as.columns", units = un))$massoc.detail
  base <- c(sum(a), sum(b), sum(cc), sum(d), un)
  for (i in 1:3) add(i - 1, base, unlist(r$RR.crude.wald[1, ])[i])
  for (i in 1:3) add(2 + i, base, unlist(r$OR.crude.wald[1, ])[i])
  for (i in 1:3) add(5 + i, base, unlist(r$ARisk.crude.wald[1, ])[i])
  for (i in 1:3) add(20 + i, base, unlist(r$RR.crude.score[1, ])[i])
  add(17, base, r$chi2.crude.uncor$test.statistic); add(18, base, r$chi2.crude.uncor$p.value.2s)
}
# fisher.test's conditional MLE and exact interval (epiR OR.strata.mle): "mle" args (a, b, c, d, which 0 est 1 lower 2 upper)
for (rep in 1:30) {
  a <- sample(3:60, 1); b <- sample(3:80, 1); cc <- sample(3:50, 1); d <- sample(3:90, 1)
  fi <- suppressWarnings(fisher.test(matrix(c(a, cc, b, d), 2), conf.int = TRUE, conf.level = 0.95))
  v <- c(as.numeric(fi$estimate), as.numeric(fi$conf.int))
  for (w in 0:2) cases[[length(cases) + 1]] <- case("mle", c(a, b, cc, d, w), v[w + 1], rel = 1e-9, abs = 1e-12)
}
# Cornfield (epiR OR.strata.cfield, zORcfield): "cf" args (a, b, c, d, which 0 est 1 lower 2 upper); this needs BiasedUrn
for (rep in 1:25) {
  a <- sample(4:60, 1); b <- sample(4:80, 1); cc <- sample(4:50, 1); d <- sample(4:90, 1)
  dat <- as.table(matrix(c(a, b, cc, d), 2, byrow = TRUE))
  r <- tryCatch(epi.2by2(dat, method = "case.control", interpret = FALSE, outcome = "as.columns")$massoc.detail$OR.strata.cfield, error = function(e) NULL)
  if (is.null(r) || any(is.na(unlist(r[1, ])))) next
  for (w in 0:2) cases[[length(cases) + 1]] <- case("cf", c(a, b, cc, d, w), unlist(r[1, ])[w + 1], rel = 1e-7, abs = 1e-10)
}
# epi.conf closed forms: "cm" args (kind, which, n1, n2, data...): kind 0 mean.single (x1), 1 mean.unpaired (x1, x2), 2 mean.paired (x1, x2 equal length); which 0 est 1 se 2 lower 3 upper
for (rep in 1:30) {
  kd <- rep %% 3; n1 <- sample(5:40, 1); n2 <- if (kd == 2) n1 else sample(5:40, 1); x1 <- rnorm(n1, 5, 2); x2 <- rnorm(n2, 6, 3)
  r <- switch(kd + 1, epi.conf(x1, ctype = "mean.single"), epi.conf(data.frame(g = factor(rep(1:2, c(n1, n2))), v = c(x1, x2)), ctype = "mean.unpaired"), epi.conf(data.frame(a = x1, b = x2), ctype = "mean.paired"))
  v <- c(r$est, r$se, r$lower, r$upper)
  for (w in 0:3) cases[[length(cases) + 1]] <- case("cm", c(kd, w, n1, n2, x1, x2), v[w + 1], rel = 1e-9, abs = 1e-12)
}
# "cr" incidence rate (a, pt, method 0 exact 1 byar, which 0 est 1 lower 2 upper), "cs" smr (k, i, obs[k], pt[k], which 0 est 1 se 2 lower 3 upper), "co" odds (a, b, which 0 est 1 lower 2 upper)
for (rep in 1:30) {
  a <- sample(1:60, 1); pt <- runif(1, 50, 900); mth <- rep %% 2
  r <- epi.conf(as.matrix(cbind(a, pt)), ctype = "inc.rate", method = c("exact", "byar")[mth + 1])
  v <- c(r$est, r$lower, r$upper)
  for (w in 0:2) cases[[length(cases) + 1]] <- case("cr", c(a, pt, mth, w), v[w + 1], rel = 1e-9, abs = 1e-12)
  k <- sample(2:5, 1); obs <- sample(0:40, k, TRUE); ptt <- runif(k, 100, 1000); i <- sample(k, 1)
  s <- epi.conf(as.matrix(cbind(obs, ptt)), ctype = "smr"); vs <- c(s$est[i], s$se[i], s$lower[i], s$upper[i])
  for (w in 0:3) cases[[length(cases) + 1]] <- case("cs", c(k, i - 1, obs, ptt, w), vs[w + 1], rel = 1e-9, abs = 1e-12)
  aa <- sample(2:80, 1); bb <- sample(2:90, 1)
  o <- epi.conf(as.matrix(cbind(aa, bb)), ctype = "odds"); vo <- c(o$est, o$lower, o$upper)
  for (w in 0:2) cases[[length(cases) + 1]] <- case("co", c(aa, bb, w), vo[w + 1], rel = 1e-9, abs = 1e-12)
}
# epi.conf proportions: "pp" args (kind 0 prop.single (r, m), 1 prop.unpaired (r1, m1, r2, m2), 2 prop.paired (r, s, t, u), which 0 est 1 se 2 lower 3 upper, then the counts)
for (rep in 1:30) {
  kd <- rep %% 3
  if (kd == 0) { r <- sample(2:40, 1); m <- sample(2:60, 1); res <- epi.conf(matrix(c(r, m), ncol = 2), ctype = "prop.single"); cnt <- c(r, m) }
  if (kd == 1) { cnt <- sample(2:50, 4, TRUE); res <- epi.conf(matrix(cnt, ncol = 4), ctype = "prop.unpaired") }
  if (kd == 2) { cnt <- sample(2:40, 4, TRUE); res <- epi.conf(matrix(cnt, ncol = 4), ctype = "prop.paired") }
  v <- c(res$est, res$se, res$lower, res$upper)
  for (w in 0:3) cases[[length(cases) + 1]] <- case("pp", c(kd, w, cnt), v[w + 1], rel = 1e-9, abs = 1e-12)
}
# epi.2by2 cohort.time: "ct" args (a, b, c, d, units, which 0..2 IRR, 3..5 ARate, 6..8 AFRate, 9..11 PARate, 12..14 PAFRate); a and c are cases, b and d person-time
for (rep in 1:30) {
  a <- sample(5:80, 1); b <- runif(1, 5000, 40000); cc <- sample(5:80, 1); d <- runif(1, 5000, 40000); un <- c(100, 1000, 1)[rep %% 3 + 1]
  dat <- as.table(matrix(c(a, b, cc, d), 2, byrow = TRUE))
  r <- epi.2by2(dat, method = "cohort.time", interpret = FALSE, outcome = "as.columns", units = un)$massoc.detail
  v <- c(unlist(r$IRR.strata.wald[1, ]), unlist(r$ARate.strata.wald[1, ]), unlist(r$AFRate.strata.wald[1, ]), unlist(r$PARate.strata.wald[1, ]), unlist(r$PAFRate.strata.wald[1, ]))
  for (w in 0:14) cases[[length(cases) + 1]] <- case("ct", c(a, b, cc, d, un, w), unname(v[w + 1]), rel = 1e-8, abs = 1e-11)
}
# case-control PAFest (epi.2by2 PAFest.strata.wald): "pe" args (a, b, c, d, which 0 est 1 lower 2 upper)
for (rep in 1:25) {
  a <- sample(10:200, 1); b <- sample(10:200, 1); cc <- sample(10:300, 1); d <- sample(10:300, 1)
  dat <- as.table(matrix(c(a, b, cc, d), 2, byrow = TRUE))
  r <- epi.2by2(dat, method = "case.control", interpret = FALSE, outcome = "as.columns")$massoc.detail$PAFest.strata.wald
  for (w in 0:2) cases[[length(cases) + 1]] <- case("pe", c(a, b, cc, d, w), unlist(r[1, ])[w + 1], rel = 1e-8, abs = 1e-11)
}
# the score risk-ratio interval on boundary tables (a zero cell or a full row): "rb" args (a, b, c, d, which 0 est 1 lower 2 upper)
bt <- list(c(0, 40, 12, 100), c(5, 40, 0, 100), c(0, 30, 0, 50), c(20, 0, 8, 60), c(10, 30, 15, 0), c(25, 0, 12, 0), c(0, 35, 14, 0), c(18, 0, 0, 40), c(0, 0, 9, 60), c(7, 33, 10, 0))
for (v in bt) {
  dat <- as.table(matrix(v, 2, byrow = TRUE))
  r <- tryCatch(suppressWarnings(epiR:::zRRscore(c(v[1], v[3], v[2], v[4]), 0.95)), error = function(e) NULL)
  if (is.null(r) || any(is.nan(r))) next
  for (w in 0:2) cases[[length(cases) + 1]] <- case("rb", c(v, w), r[w + 1], rel = 1e-8, abs = 1e-11)
}
emit("epir", "epiR", list(cases))
