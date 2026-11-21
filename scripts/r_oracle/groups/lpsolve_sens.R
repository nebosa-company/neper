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
    cases[[length(cases) + 1]] <- case("sd", c(a, 0, k), r$duals[k], rel = 1e-9, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 1, k), r$duals.from[k], rel = 1e-9, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 2, k), r$duals.to[k], rel = 1e-9, abs = 1e-9)
  }
  for (k in seq_len(n)) {
    cases[[length(cases) + 1]] <- case("sd", c(a, 3, k), r$sens.coef.from[k], rel = 1e-9, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 4, k), r$sens.coef.to[k], rel = 1e-9, abs = 1e-9)
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
    cases[[length(cases) + 1]] <- case("sd", c(a, 0, k), r$duals[k], rel = 1e-9, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 1, k), r$duals.from[k], rel = 1e-9, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 2, k), r$duals.to[k], rel = 1e-9, abs = 1e-9)
  }
  for (k in seq_len(n)) {
    cases[[length(cases) + 1]] <- case("sd", c(a, 3, k), r$sens.coef.from[k], rel = 1e-9, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("sd", c(a, 4, k), r$sens.coef.to[k], rel = 1e-9, abs = 1e-9)
  }
}
# equality rows: a random mix of <=, >= and = rows built around a feasible point, either direction
addsens <- function(r, n, m, mx, cc, A, dirs, b) {
  code <- match(dirs, c("<=", ">=", "=")) - 1
  a <- c(n, m, mx, cc, as.vector(t(A)), b, code)
  for (k in seq_len(m + n)) {
    cases[[length(cases) + 1]] <<- case("sd", c(a, 0, k), r$duals[k], rel = 1e-9, abs = 1e-9)
    cases[[length(cases) + 1]] <<- case("sd", c(a, 1, k), r$duals.from[k], rel = 1e-9, abs = 1e-9)
    cases[[length(cases) + 1]] <<- case("sd", c(a, 2, k), r$duals.to[k], rel = 1e-9, abs = 1e-9)
  }
  for (k in seq_len(n)) {
    cases[[length(cases) + 1]] <<- case("sd", c(a, 3, k), r$sens.coef.from[k], rel = 1e-9, abs = 1e-9)
    cases[[length(cases) + 1]] <<- case("sd", c(a, 4, k), r$sens.coef.to[k], rel = 1e-9, abs = 1e-9)
  }
}
neq <- 0
for (rep in 1:30) {
  n <- sample(3:5, 1); m <- sample(2:4, 1); mx <- rep %% 2
  A <- matrix(round(runif(m * n, 0.5, 5), 2), m, n); cc <- round(runif(n, 0.5, 6), 2)
  x0 <- round(runif(n, 0.5, 4), 2)
  dirs <- sample(c("<=", ">=", "="), m, TRUE, prob = c(0.35, 0.2, 0.45))
  if (!any(dirs == "=")) dirs[1] <- "="
  b <- round(as.vector(A %*% x0) + ifelse(dirs == "<=", runif(m, 0.5, 8), ifelse(dirs == ">=", -runif(m, 0.5, 3), 0)), 2)
  r <- tryCatch(lp(if (mx == 1) "max" else "min", cc, A, dirs, b, compute.sens = 1), error = function(e) NULL)
  if (is.null(r) || r$status != 0) next
  neq <- neq + 1
  addsens(r, n, m, mx, cc, A, dirs, b)
}
# degenerate programs: a redundant row (the sum of two binding rows) is tight at the optimum
ndeg <- 0
for (rep in seq_len(if (Sys.getenv("NODEG") == "1") 0 else 40)) {
  n <- sample(2:4, 1); m <- sample(3:4, 1); mx <- rep %% 2
  A <- matrix(round(runif(m * n, 0.5, 5), 2), m, n); b <- round(runif(m, 5, 30), 2); cc <- round(runif(n, 0.5, 6), 2)
  r0 <- lp(if (mx == 1) "max" else "min", cc, A, rep(if (mx == 1) "<=" else ">=", m), b, compute.sens = 1)
  if (r0$status != 0) next
  tight <- which(r0$duals[seq_len(m)] != 0)
  if (length(tight) < 2) next
  pr <- sample(tight, 2)
  A2 <- rbind(A, A[pr[1], ] + A[pr[2], ]); b2 <- c(b, b[pr[1]] + b[pr[2]])
  r <- lp(if (mx == 1) "max" else "min", cc, A2, rep(if (mx == 1) "<=" else ">=", m + 1), b2, compute.sens = 1)
  if (r$status != 0) next
  ndeg <- ndeg + 1
  addsens(r, n, m + 1, mx, cc, A2, rep(if (mx == 1) "<=" else ">=", m + 1), b2)
}
message("eq programs ", neq, " degenerate programs ", ndeg)
emit("lpsolve_sens", "lpSolve", list(cases))
