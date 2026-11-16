# DiceDesign: discrepancy criteria and the distance measures of a design in the unit cube.
#   args: (n, d, p, design row-major...)   fn "C2" "L2" "L2star" "M2" "S2" "W2" "Mix2" "mindist" "phip" "coverage"
suppressMessages(library(DiceDesign))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261204)
for (rep in 1:8) {
  d <- c(2, 3, 4, 5)[(rep - 1) %% 4 + 1]; n <- c(8, 12, 20)[(rep - 1) %% 3 + 1]
  X <- matrix(runif(n * d), n, d)
  p <- c(5, 10, 50)[(rep - 1) %% 3 + 1]
  a <- c(n, d, p, as.vector(t(X)))
  dc <- discrepancyCriteria(X, type = "all")
  for (k in c("C2", "L2", "L2star", "M2", "S2", "W2", "Mix2")) add(k, a, dc[[paste0("Dis", k)]])
  add("mindist", a, mindist(X)); add("phip", a, phiP(X, p)); add("coverage", a, coverage(X))
}
for (rep in 1:12) {
  n <- sample(5:30, 1); d <- sample(1:5, 1); sd <- sample(1:100000, 1); rz <- rep %% 3 != 0
  L <- lhsDesign(n, d, randomized = rz, seed = sd)$design
  add("lhs", c(n, d, sd, as.numeric(rz)), sum(as.vector(t(L)) * seq_len(length(L))))
  lv <- sample(2:4, d, replace = TRUE); Fd <- factDesign(d, lv)$design
  add("fact", c(length(lv), d, 0, 0, lv), sum(as.vector(t(Fd)) * seq_len(length(Fd))))
  d2 <- max(d, 2); Fa <- runif.faure(n, d2)$design
  add("faure", c(n, d2, 0, 0), sum(as.vector(t(Fa)) * seq_len(length(Fa))))
}
emit("dicedesign", "DiceDesign", list(cases))
