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
emit("dicedesign", "DiceDesign", list(cases))
