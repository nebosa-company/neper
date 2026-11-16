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
emit("desctools", "DescTools", list(cases))
