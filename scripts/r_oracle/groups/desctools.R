# DescTools: Skew, Kurt, Gini, MeanAD, Gmean, Hmean, Entropy and CoefVar of positive samples.
#   args: (n, x...)   fn "skew1" "skew2" "skew3" "kurt1" "kurt2" "kurt3" "gini" "ginib" (biased) "meanad" "gmean" "hmean" "entropy" "cv"
suppressMessages(library(DescTools))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261231)
for (rep in 1:20) {
  n <- sample(6:60, 1); x <- round(rexp(n) * 10 + 0.1, 4); a <- c(n, x)
  for (m in 1:3) { add(paste0("skew", m), a, Skew(x, method = m)); add(paste0("kurt", m), a, Kurt(x, method = m)) }
  add("gini", a, Gini(x)); add("ginib", a, Gini(x, unbiased = FALSE)); add("meanad", a, MeanAD(x)); add("gmean", a, Gmean(x)); add("hmean", a, Hmean(x))
  add("entropy", a, Entropy(x)); add("cv", a, CoefVar(x))
}
for (rep in 1:20) {
  r <- sample(2:5, 1); cc <- sample(2:5, 1); tab <- matrix(sample(1:30, r * cc, TRUE), r, cc); a <- c(r, cc, as.vector(t(tab)))
  add("cramer", a, CramerV(tab)); add("phi", a, Phi(tab)); add("cont", a, ContCoef(tab)); add("tschuprow", a, TschuprowT(tab))
  add("gamma", a, GoodmanKruskalGamma(tab)); add("taub", a, KendallTauB(tab)); add("tauc", a, StuartTauC(tab))
  add("somersr", a, SomersDelta(tab, direction = "row")); add("somersc", a, SomersDelta(tab, direction = "column"))
}
for (rep in 1:20) {
  r <- sample(2:5, 1); tab <- matrix(sample(1:30, r * r, TRUE), r, r); a <- c(r, r, as.vector(t(tab)))
  add("kappa", a, CohenKappa(tab))
  for (d in c("symmetric", "row", "column")) add(paste0("lambda_", d), a, Lambda(tab, direction = d))
  add("tau_row", a, GoodmanKruskalTau(tab, direction = "row")); add("tau_col", a, GoodmanKruskalTau(tab, direction = "column"))
  t2 <- matrix(sample(1:30, 4, TRUE), 2); a2 <- c(2, 2, as.vector(t(t2))); add("or", a2, OddsRatio(t2)); add("yq", a2, YuleQ(t2))
}
ms <- c("wald", "waldcc", "wilson", "wilsoncc", "agresti-coull", "jeffreys", "modified wilson", "modified jeffreys", "clopper-pearson", "arcsine", "logit")
for (rep in 1:30) {
  n <- sample(c(8:30, 60, 120), 1); x <- sample(c(1:(n - 1), 1, n - 1), 1); cl <- sample(c(0.9, 0.95, 0.99), 1)
  for (m in seq_along(ms)) { r <- BinomCI(x, n, conf.level = cl, method = ms[m]); add("binomci", c(m - 1, x, n, cl, 0), r[1, 1]); add("binomci", c(m - 1, x, n, cl, 1), r[1, 2]); add("binomci", c(m - 1, x, n, cl, 2), r[1, 3]) }
}
for (rep in 1:25) {
  n <- sample(12:40, 1); x <- round(rnorm(n, 3, 2), 5); y <- round(rnorm(sample(5:15, 1), 2, 2), 5); cl <- sample(c(0.9, 0.95, 0.99), 1); p1 <- runif(1, 0.01, 0.2); p2 <- runif(1, 0.8, 0.99); tr <- runif(1, 0.02, 0.4)
  add("winsor", c(n, p1, p2, x), sum(Winsorize(x, quantile(x, c(p1, p2))) * seq_len(n)))
  add("hl1", c(n, 0, 0, x), HodgesLehmann(x)); add("hl2", c(n, length(y), 0, x, y), HodgesLehmann(x, y))
  mc <- MedianCI(x, conf.level = cl); add("medci", c(n, cl, 0, x), mc[1]); add("medci", c(n, cl, 1, x), mc[2]); add("medci", c(n, cl, 2, x), mc[3]); add("medci", c(n, cl, 3, x), attr(mc, "conf.level"))
  tx <- as.numeric(Trim(x, tr)); add("trim", c(n, tr, 0, x), sum(tx * seq_along(tx)))
}
for (rep in 1:20) {
  r <- sample(3:6, 1); tb <- matrix(rpois(2 * r, 20) + 3, r, 2); tb[, 1] <- tb[, 1] + round(seq_len(r) * runif(1, 0, 4))
  ca <- CochranArmitageTest(tb); add("catz", c(r, 0, 0, as.vector(t(tb))), ca$statistic); add("catp", c(r, 0, 0, as.vector(t(tb))), ca$p.value)
  K <- sample(2:5, 1); arr <- array(rpois(4 * K, 25) + 4, c(2, 2, K)); sv <- as.vector(sapply(1:K, function(j) c(arr[1, 1, j], arr[1, 2, j], arr[2, 1, j], arr[2, 2, j])))
  add("mhor", c(K, 0, 0, sv), mantelhaen.test(arr)$estimate)
  bd <- BreslowDayTest(arr); add("bdx", c(K, 0, 0, sv), bd$statistic); add("bdp", c(K, 0, 0, sv), bd$p.value)
  bt <- BreslowDayTest(arr, correct = TRUE); add("bdtx", c(K, 0, 0, sv), bt$statistic); add("bdtp", c(K, 0, 0, sv), bt$p.value)
}
pm <- c("exact", "score", "wald", "byar"); mm <- c("goodman", "wald", "waldcc", "wilson")
for (rep in 1:25) {
  x <- sample(c(1:40, 100), 1); tt <- sample(c(1, 2.5, 10), 1); cl <- sample(c(0.9, 0.95, 0.99), 1)
  for (m in 1:4) { r <- PoissonCI(x, tt, conf.level = cl, method = pm[m]); for (pt in 0:2) add("poisci", c(m - 1, x, tt, cl, pt), r[1, pt + 1]) }
  k <- sample(3:6, 1); cnt <- rpois(k, 15) + 2; i <- sample(k, 1)
  for (m in 1:4) { r <- MultinomCI(cnt, conf.level = cl, method = mm[m]); for (pt in 0:2) add("multici", c(m - 1, i - 1, cl, pt, k, cnt), r[i, pt + 1]) }
}
for (rep in 1:15) {
  ns <- sample(6:20, 1); nr <- sample(3:5, 1); subj <- rnorm(ns, 0, 2); rt <- round(outer(subj, rep(1, nr)) + matrix(rnorm(ns * nr), ns, nr) + rep(rnorm(nr, 0, 0.5), each = ns), 5)
  cl <- sample(c(0.9, 0.95), 1); ty <- c("ICC1", "ICC2", "ICC3", "ICC1k", "ICC2k", "ICC3k")
  for (m in 1:6) { r <- ICC(rt, type = ty[m], conf.level = cl); for (pt in 0:2) add("icc", c(m - 1, pt, ns, nr, cl, as.vector(t(rt))), r[pt + 1]) }
}
for (rep in 1:20) {
  ns <- sample(8:30, 1); nr <- sample(3:5, 1); nl <- sample(3:4, 1); base <- sample(1:nl, ns, TRUE); rt <- matrix(sapply(1:nr, function(j) ifelse(runif(ns) < 0.7, base, sample(1:nl, ns, TRUE))), ns, nr)
  if (length(unique(as.vector(rt))) < nl) next
  cl <- sample(c(0.9, 0.95), 1)
  f <- KappaM(rt, method = "Fleiss", conf.level = cl); cg <- KappaM(rt, method = "Conger")
  for (pt in 0:2) add("kappam", c(0, pt, ns, nr, nl, cl, as.vector(t(rt - 1))), f[pt + 1])
  add("kappam", c(1, 0, ns, nr, nl, cl, as.vector(t(rt - 1))), cg)
}
emit("desctools", "DescTools", list(cases))
