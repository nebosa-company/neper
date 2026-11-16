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
for (rep in 1:8) {
  n <- sample(6:14, 1); d <- sample(2:4, 1); sd <- sample(1:100000, 1); prof <- c("GEOM", "LINEAR")[rep %% 2 + 1]
  L <- lhsDesign(n, d, seed = sd)$design
  S <- maximinSA_LHS(L, T0 = 5, c = 0.9, it = 60, p = 15, profile = prof)
  add("sa", c(n, d, sd, rep %% 2), sum(as.vector(t(S$design)) * seq_len(length(S$design))))
  add("sa_phi", c(n, d, sd, rep %% 2), tail(S$critValues, 1))
}
for (rep in 1:8) {
  n <- sample(6:14, 1); d <- sample(2:4, 1); sd <- sample(1:100000, 1); prof <- c("GEOM", "LINEAR")[rep %% 2 + 1]
  L <- lhsDesign(n, d, seed = sd)$design
  S <- discrepSA_LHS(L, T0 = 0.05, c = 0.9, it = 60, criterion = "C2", profile = prof)
  add("dsa", c(n, d, sd, rep %% 2), sum(as.vector(t(S$design)) * seq_len(length(S$design))))
  add("dsa_c2", c(n, d, sd, rep %% 2), tail(S$critValues, 1))
}
for (itn in 1:6) {
  n <- 8; d <- 4; sd <- 63366
  L <- lhsDesign(n, d, seed = sd)$design
  S <- discrepSA_LHS(L, T0 = 0.05, c = 0.9, it = itn, criterion = "C2", profile = "GEOM")
  add("dsa_it", c(n, d, sd, 0, itn), tail(S$critValues, 1))
}
for (rep in 1:12) {
  n <- sample(8:30, 1); d <- sample(2:4, 1); sd <- sample(1:100000, 1); dm <- c(0.1, 0.2, 0.3)[rep %% 3 + 1]
  L <- lhsDesign(n, d, seed = sd)$design
  w <- wspDesign(L, dm)
  x <- match(apply(w$design, 1, paste, collapse = ","), apply(L, 1, paste, collapse = ","))
  add("wsp_n", c(n, d, sd, dm), length(x)); add("wsp", c(n, d, sd, dm), sum(x * seq_along(x)))
}
for (rep in 1:6) {
  n <- sample(6:25, 1); d <- sample(2:4, 1); X <- matrix(runif(n * d), n, d)
  add("mesh", c(n, d, 0, as.vector(t(X))), meshRatio(X))
}
for (rep in 1:8) {
  n <- sample(6:12, 1); d <- sample(2:4, 1); sd <- sample(1:100000, 1); itn <- sample(1:2, 1)
  L <- lhsDesign(n, d, seed = sd)$design
  S <- maximinESE_LHS(L, it = itn, inner_it = 20, J = 5, p = 15, T0 = 0.005 * phiP(L, p = 50))
  add("ese", c(n, d, sd, itn), sum(as.vector(t(S$design)) * seq_len(length(S$design))))
  add("ese_phi", c(n, d, sd, itn), phiP(S$design, p = 15))
}
for (rep in 1:8) {
  n <- sample(6:12, 1); d <- sample(2:4, 1); sd <- sample(1:100000, 1); itn <- sample(1:2, 1)
  L <- lhsDesign(n, d, seed = sd)$design
  S <- discrepESE_LHS(L, it = itn, inner_it = 20, J = 5, T0 = 0.005 * discrepancyCriteria(L, type = "C2")[[1]], criterion = "C2")
  add("dese", c(n, d, sd, itn), sum(as.vector(t(S$design)) * seq_len(length(S$design))))
  add("dese_c2", c(n, d, sd, itn), discrepancyCriteria(S$design, type = "C2")[[1]])
}
emit("dicedesign", "DiceDesign", list(cases))
