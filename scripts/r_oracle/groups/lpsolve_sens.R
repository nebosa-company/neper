# lpSolve: lp(compute.sens = 1) on bounded non-degenerate programs. Args: (n, m, maximise, c[n], A row-major [m * n], b[m], geq[m], field, index): field 0 duals, 1 duals.from, 2 duals.to, 3 sens.coef.from, 4 sens.coef.to
suppressMessages(library(lpSolve))
cases <- list()
set.seed(20262360)
for (rep in 1:60) {
  n <- sample(2:4, 1); m <- sample(2:4, 1); mx <- rep %% 2
  A <- matrix(round(runif(m * n, 0.5, 5), 2), m, n); b <- round(runif(m, 5, 30), 2); cc <- round(runif(n, 0.5, 6), 2)
  r <- tryCatch(lp(if (mx == 1) "max" else "min", cc, A, rep(if (mx == 1) "<=" else ">=", m), b, compute.sens = 1), error = function(e) NULL)
  if (is.null(r) || r$status != 0) next
  a <- c(n, m, mx, cc, as.vector(t(A)), b, rep(1 - mx, m))
  for (k in seq_len(m + n)) {
    cases[[length(cases) + 1]] <- case("sd", c(a, 0, k), r$duals[k], rel = 1e-8, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 1, k), r$duals.from[k], rel = 1e-8, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 2, k), r$duals.to[k], rel = 1e-8, abs = 1e-9)
  }
  for (k in seq_len(n)) {
    cases[[length(cases) + 1]] <- case("sd", c(a, 3, k), r$sens.coef.from[k], rel = 1e-8, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 4, k), r$sens.coef.to[k], rel = 1e-8, abs = 1e-9)
  }
}
# mixed row directions: max with <= rows and a few >= rows with small right-hand sides, min with >= rows and a few <= rows with large ones
for (rep in 1:60) {
  n <- sample(2:4, 1); m <- sample(3:5, 1); mx <- rep %% 2
  A <- matrix(round(runif(m * n, 0.5, 5), 2), m, n); cc <- round(runif(n, 0.5, 6), 2)
  g <- sample(c(TRUE, FALSE), m, TRUE, prob = c(0.35, 0.65))
  if (mx == 1) { dir <- ifelse(g, ">=", "<="); b <- ifelse(g, round(runif(m, 0.5, 2), 2), round(runif(m, 10, 30), 2)) } else { dir <- ifelse(g, "<=", ">="); b <- ifelse(g, round(runif(m, 40, 90), 2), round(runif(m, 4, 20), 2)) }
  r <- tryCatch(lp(if (mx == 1) "max" else "min", cc, A, dir, b, compute.sens = 1), error = function(e) NULL)
  if (is.null(r) || r$status != 0) next
  a <- c(n, m, mx, cc, as.vector(t(A)), b, as.numeric(dir == ">="))
  for (k in seq_len(m + n)) {
    cases[[length(cases) + 1]] <- case("sd", c(a, 0, k), r$duals[k], rel = 1e-8, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 1, k), r$duals.from[k], rel = 1e-8, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 2, k), r$duals.to[k], rel = 1e-8, abs = 1e-9)
  }
  for (k in seq_len(n)) {
    cases[[length(cases) + 1]] <- case("sd", c(a, 3, k), r$sens.coef.from[k], rel = 1e-8, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 4, k), r$sens.coef.to[k], rel = 1e-8, abs = 1e-9)
  }
}
emit("lpsolve_sens", "lpSolve", list(cases))
