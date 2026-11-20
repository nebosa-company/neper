# lpSolveAPI sensitivity and dual readers on models of real variables in [0, Inf): get.sensitivity.rhs, get.sensitivity.obj, get.dual.solution and get.primal.solution(orig = TRUE).
#   args: (sense 0 min 1 max, m, n, c[n], A row-major, rel[m] (0 <=, 1 >=, 2 =), b[m], field, index) with field 0 duals, 1 dualsfrom, 2 dualstill (index over m + n),
#   3 objfrom, 4 objtill (index over n), 5 get.dual.solution (index over 1 + m + n), 6 get.primal.solution (index over m + n)
#   Programs with <=, >= and = rows built around a feasible point; "degenerate" programs add a redundant row (the sum of two binding rows) last.
suppressMessages(library(lpSolveAPI))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-9)
relstr <- c("<=", ">=", "=")
build <- function(sense, A, relc, b, cc) {
  lpm <- make.lp(0, ncol(A))
  invisible(lp.control(lpm, sense = if (sense == 1) "max" else "min"))
  set.objfn(lpm, cc)
  for (i in seq_len(nrow(A))) add.constraint(lpm, A[i, ], relstr[relc[i] + 1], b[i])
  lpm
}
record <- function(sense, A, relc, b, cc) {
  lpm <- build(sense, A, relc, b, cc)
  if (solve(lpm) != 0) return(FALSE)
  m <- nrow(A); n <- ncol(A)
  a <- c(sense, m, n, cc, as.vector(t(A)), relc, b)
  so <- get.sensitivity.obj(lpm); sr <- get.sensitivity.rhs(lpm); ds <- get.dual.solution(lpm); ps <- get.primal.solution(lpm, orig = TRUE)
  for (k in seq_len(m + n)) {
    add("sens", c(a, 0, k), sr$duals[k]); add("sens", c(a, 1, k), sr$dualsfrom[k]); add("sens", c(a, 2, k), sr$dualstill[k])
    add("sens", c(a, 6, k), ps[k])
  }
  for (k in seq_len(n)) { add("sens", c(a, 3, k), so$objfrom[k]); add("sens", c(a, 4, k), so$objtill[k]) }
  for (k in seq_len(1 + m + n)) add("sens", c(a, 5, k), ds[k])
  TRUE
}
set.seed(20262470)
got <- 0
for (rep in 1:200) {
  n <- sample(2:5, 1); m <- sample(2:4, 1); sense <- rep %% 2
  A <- matrix(round(runif(m * n, 0.5, 5), 2), m, n); cc <- round(runif(n, 0.5, 6), 2)
  x0 <- round(runif(n, 0.5, 4), 2)
  relc <- sample(0:2, m, TRUE, prob = c(0.4, 0.2, 0.4))
  b <- round(as.vector(A %*% x0) + ifelse(relc == 0, runif(m, 0.5, 8), ifelse(relc == 1, -runif(m, 0.5, 3), 0)), 2)
  if (record(sense, A, relc, b, cc)) got <- got + 1
  if (got >= 40) break
}
degen <- 0; DEG <- as.numeric(Sys.getenv("DEG", "4"))
for (rep in 1:200) {
  n <- sample(2:4, 1); m <- sample(3:4, 1); sense <- rep %% 2
  A <- matrix(round(runif(m * n, 0.5, 5), 2), m, n); b <- round(runif(m, 5, 30), 2); cc <- round(runif(n, 0.5, 6), 2)
  relc <- rep(1 - sense, m)
  lpm <- build(sense, A, relc, b, cc)
  if (solve(lpm) != 0) next
  tight <- which(get.sensitivity.rhs(lpm)$duals[seq_len(m)] != 0)
  if (length(tight) < 2) next
  pr <- sample(tight, 2)
  if (record(sense, rbind(A, A[pr[1], ] + A[pr[2], ]), c(relc, 1 - sense), c(b, b[pr[1]] + b[pr[2]]), cc)) degen <- degen + 1
  if (degen >= DEG) break
}
message("lpsolveapi_sens programs ", got, " degenerate ", degen)
emit("lpsolveapi_sens", "lpSolveAPI", list(cases))
