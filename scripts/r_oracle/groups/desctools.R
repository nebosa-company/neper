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
emit("desctools", "DescTools", list(cases))
