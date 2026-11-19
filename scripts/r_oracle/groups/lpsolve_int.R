# lpSolve: integer and binary programs, lp("max", ..., int.vec). Args: (m, n, c[n], A row-major m by n, rel[m] (0 <=, 1 >=), b[m], isint[n]); fn "ip": the optimal value.
suppressMessages(library(lpSolve))
cases <- list()
set.seed(20262201)
ok <- 0
for (rep in 1:300) {
  n <- sample(2:5, 1); m <- sample(2:4, 1)
  cc <- round(runif(n, 0.5, 5), 1)
  A <- matrix(round(runif(m * n, 0.5, 4), 1), m, n); b <- round(runif(m, 8, 25), 1); rel <- rep("<=", m)
  bin <- rep %% 3 == 0
  if (bin) { A <- rbind(A, diag(n)); b <- c(b, rep(1, n)); rel <- c(rel, rep("<=", n)) }
  ints <- if (bin) seq_len(n) else sort(sample(seq_len(n), sample(1:n, 1)))
  if (rep %% 5 == 0 && !bin) { A <- rbind(A, rep(1, n)); b <- c(b, 2); rel <- c(rel, ">=") }
  s <- lp("max", cc, A, rel, b, int.vec = ints)
  if (s$status != 0) next
  # lpSolve's branch and bound stops early on some mixed problems (a value below the true optimum), so the expected value is the true optimum,
  # found here by enumerating the integer variables and solving the continuous remainder with lp(); lpSolve's own value is checked to be a lower bound
  ub <- vapply(ints, function(j) { r <- A[, j] > 0 & rel == "<="; if (any(r)) floor(min(b[r] / A[r, j]) + 1e-9) else 0 }, 0)
  grid <- as.matrix(expand.grid(lapply(ub, function(u) 0:u)))
  best <- -Inf
  cont <- setdiff(seq_len(n), ints)
  for (g in seq_len(nrow(grid))) {
    xi <- grid[g, ]; bb <- b - as.vector(A[, ints, drop = FALSE] %*% xi); base <- sum(cc[ints] * xi)
    if (length(cont) == 0) { ok2 <- all(ifelse(rel == "<=", bb >= -1e-9, bb <= 1e-9)); if (ok2) best <- max(best, base); next }
    sg <- lp("max", cc[cont], A[, cont, drop = FALSE], rel, bb)
    if (sg$status == 0) best <- max(best, base + sg$objval)
  }
  stopifnot(s$objval <= best + 1e-7)
  nsub <- if (exists("nsub")) nsub else 0
  if (s$objval < best - 1e-7) nsub <- nsub + 1
  isint <- as.numeric(seq_len(n) %in% ints)
  cases[[length(cases) + 1]] <- case("ip", c(nrow(A), n, cc, as.vector(t(A)), as.numeric(rel == ">="), b, isint), best, rel = 1e-8, abs = 1e-8)
  ok <- ok + 1
  if (ok >= 60) break
}
cat("lpSolve below the true optimum in", nsub, "of", ok, "problems
")
emit("lpsolve_int", "lpSolve", list(cases))
