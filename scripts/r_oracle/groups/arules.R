# arules apriori on a transaction-by-item 0/1 matrix.
#   args: (nt, nitems, supp, conf, maxlen, 0/1 matrix[nt*nitems] row-major)
#   fn "nfreq" "sfreq" (frequent itemsets: count, sum of supports), "nrule" "srule" "sconf" "slift" (rules with at least two items)
suppressMessages(library(arules))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20261214)
for (rep in 1:24) {
  nt <- sample(40:150, 1); ni <- sample(5:12, 1); pr <- runif(ni, 0.15, 0.6)
  m <- sapply(pr, function(p) as.numeric(runif(nt) < p)); m[m[, 1] == 1 & runif(nt) < 0.5, 2] <- 1
  supp <- runif(1, 0.03, 0.2); conf <- runif(1, 0.1, 0.7); ml <- sample(2:5, 1)
  tr <- as(m == 1, "transactions")
  fi <- apriori(tr, parameter = list(supp = supp, target = "frequent itemsets", minlen = 1, maxlen = ml), control = list(verbose = FALSE))
  ru <- apriori(tr, parameter = list(supp = supp, conf = conf, minlen = 2, maxlen = ml), control = list(verbose = FALSE))
  a <- c(nt, ni, supp, conf, ml, as.vector(t(m)))
  add("nfreq", a, length(fi)); add("sfreq", a, if (length(fi)) sum(quality(fi)$support) else 0)
  add("nrule", a, length(ru))
  q <- if (length(ru)) quality(ru) else data.frame(support = 0, confidence = 0, lift = 0)
  add("srule", a, sum(q$support)); add("sconf", a, sum(q$confidence)); add("slift", a, sum(q$lift))
  cl <- apriori(tr, parameter = list(supp = supp, target = "closed frequent itemsets", minlen = 1, maxlen = ni), control = list(verbose = FALSE))
  mx <- apriori(tr, parameter = list(supp = supp, target = "maximally frequent itemsets", minlen = 1, maxlen = ni), control = list(verbose = FALSE))
  add("c0", a, length(cl)); add("c1", a, if (length(cl)) sum(quality(cl)$support) else 0)
  add("c2", a, length(mx)); add("c3", a, if (length(mx)) sum(quality(mx)$support) else 0)
  if (length(ru)) {
    bm <- c("precision", "recall", "fScore", "accuracy", "balancedAccuracy", "conviction", "gini", "rulePowerFactor", "relativeRisk", "netconf", "zhang", "collectiveStrength", "importance", "imbalance", "kappa", "lambda", "mutualInformation", "maxconfidence", "jMeasure", "laplace", "certainty", "ralambondrainy", "sebag", "counterexample", "confirmedConfidence", "causalSupport", "causalConfidence", "leastContradiction", "centeredConfidence", "varyingLiaison", "yuleQ", "yuleY", "lerman", "implicationIndex", "doc", "chiSquared", "rhsSupport", "count")
    for (k in seq_along(bm)) {
      v <- as.numeric(interestMeasure(ru, bm[k], transactions = tr)); v <- v[is.finite(v)]
      add(paste0("b", k - 1), a, sum(v))
    }
  }
  if (length(ru)) {
    ms <- c("leverage", "coverage", "cosine", "jaccard", "kulczynski", "phi", "addedValue", "conviction", "oddsRatio")
    for (k in seq_along(ms)) {
      v <- as.numeric(interestMeasure(ru, ms[k], transactions = tr)); v <- v[is.finite(v)]
      add(paste0("m", k - 1), a, sum(v))
    }
  }
}
emit("arules", "arules", list(cases))
