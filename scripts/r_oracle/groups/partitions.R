# partitions: P, Q counts; parts, restrictedparts and diffparts as matrices (column-major sum and position-weighted sum).
#   args: (kind, n, m)  kind 0 P(n)  1 Q(n)  2 parts(n)  3 restrictedparts(n, m)  4 diffparts(n)
#   fn "val" (P, Q), "cols" "sum" "w"
suppressMessages(library(partitions))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
for (n in c(1:40, 50, 60)) { add("val", c(0, n, 0), as.numeric(P(n))); add("val", c(1, n, 0), as.numeric(Q(n))) }
summ <- function(a, M) { M <- as.matrix(M); v <- as.vector(M); add("cols", a, ncol(M)); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v)) }
for (n in 2:18) {
  summ(c(2, n, 0), parts(n))
  summ(c(4, n, 0), diffparts(n))
  for (m in 1:min(5, n)) summ(c(3, n, m), restrictedparts(n, m))
}
for (n in 2:9) for (m in 2:5) for (z in c(TRUE, FALSE)) { if (!z && n < m) next; summ(c(if (z) 5 else 6, n, m), compositions(n, m, include.zero = z)) }
# blockparts: ("bp") args (m, n, f[m]) -> columns, sum, position-weighted sum as fn "bpc", "bps", "bpw"
set.seed(11)
for (rep in 1:60) { m <- sample(2:5, 1); f <- sample(0:4, m, TRUE); if (sum(f) == 0) next; n <- sample(1:sum(f), 1)
  M <- tryCatch(as.matrix(blockparts(f, n)), error = function(e) NULL); if (is.null(M)) next; v <- as.vector(M); a <- c(m, n, f)
  add("bpc", a, ncol(M)); add("bps", a, sum(v)); add("bpw", a, sum(seq_along(v) * v)) }
# setparts: ("spc" columns, "sps" sum, "spw" position-weighted sum) args (m, sizes...) for a block-size vector or (0, n) for setparts(n)
sp <- function(a, M) { M <- as.matrix(M); v <- as.vector(M); add("zpc", a, ncol(M)); add("zps", a, sum(v)); add("zpw", a, sum(seq_along(v) * v)) }
for (n in 1:7) sp(c(0, n), setparts(n))
set.seed(12)
for (rep in 1:40) { m <- sample(2:4, 1); f <- sample(1:4, m, TRUE); if (sum(f) > 9) next; sp(c(m, f), setparts(f)) }
emit("partitions", "partitions", list(cases))
