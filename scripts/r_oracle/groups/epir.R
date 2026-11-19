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
  # 21..23 score risk ratio, 33..35 attributable fraction in the exposed
  for (i in 1:3) add(20 + i, base, unlist(r$RR.strata.score[1, ])[i])
  for (i in 1:3) add(32 + i, base, unlist(r$AFRisk.strata.wald[1, ])[i])
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
emit("epir", "epiR", list(cases))
