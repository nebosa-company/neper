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
emit("epir", "epiR", list(cases))
