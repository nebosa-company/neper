# matrixStats row and column kernels. A case is
#   (op, by_row, na_rm, p1, p2, nrow, ncol, data..., nrows_sel, rows..., ncols_sel, cols..., element)
# with the matrix column-major, selections 1-based (0 selected = all), and the answer's `element`-th
# value (a "len:" case holds the length). ops: 0 sums, 1 means, 2 vars, 3 sds, 4 medians, 5 mads,
# 6 quantiles (p1 = probs set), 7 ranks (p1 = ties), 8 cumsums, 9 diffs (p1 = lag, p2 = differences),
# 10 order stats (p1 = which), 11 ranges (min vector then max vector), 12 weighted mean (data = x then w;
# nrow = length), 13 weighted median (p1 = interpolate), 14 bin counts (p1 = right; data = x then edges, p2 = length of x).
library(matrixStats)
set.seed(20261115)
options(matrixStats.check.ties_method = FALSE)

cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-13)
vec <- function(args_head, x, rows, cols, v) {
  base <- c(args_head, nrow(x), ncol(x), as.vector(x), length(rows), rows, length(cols), cols)
  add("len", c(args_head[1], base), length(v))
  for (e in seq_along(v)) add("v", c(base, e - 1), v[e])
}
mats <- list(
  matrix(c(3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8), 3), matrix(c(1, 2, 3, 4, 5, 6), 2), matrix(1:12 + 0.5, 4),
  matrix(c(3, NA, 4, 1, 5, NA, 2, 6, 5, 3, 5, 8), 3), matrix(c(2, 2, 2, 2, 7, 7), 2), matrix(c(1e10, 1, -1e10, 1, 3, 4), 2),
  matrix(c(Inf, 1, -Inf, 2, 3, 4), 2), matrix(c(NA, NA, NA, 1, 2, 3), 3), matrix(5, 1, 1), matrix(c(1, 2), 1, 2),
  matrix(c(0.1, 0.2, 0.3, 0.7, 0.9, 0.1, 0.2, 0.3), 2), matrix(rnorm(35), 5), matrix(round(rnorm(24), 1), 6),
  matrix(sample(c(1:6, NA), 30, replace = TRUE), 5), matrix(c(1e-300, 1e300, 5, 6, 7, 8), 3), matrix(numeric(0), 0, 3),
  matrix(rnorm(21) * 1e6, 3), matrix(c(-1, -1, 1, 1, 0, 0), 2)
)
subsets <- list(list(integer(), integer()), list(c(2, 1), integer()), list(integer(), c(2, 1)), list(c(1, 2), c(1, 2)))
probs <- list(c(0, 0.25, 0.5, 0.75, 1), c(0.1, 0.9), c(0.33))
ties <- c("max", "average", "min", "first", "last", "dense")

for (m in mats[c(1, 4, 5, 6, 7, 8, 13, 14, 15, 17)]) for (sub in subsets[c(1, 4)]) for (by_row in c(1, 0)) for (na in c(0, 1)) {
  rows <- sub[[1]]; cols <- sub[[2]]
  if ((length(rows) && max(rows) > nrow(m)) || (length(cols) && max(cols) > ncol(m))) next
  if (length(rows) == 0) rows_ <- NULL else rows_ <- rows
  if (length(cols) == 0) cols_ <- NULL else cols_ <- cols
  pick <- function(r, c) if (by_row) get(paste0("row", r)) else get(paste0("col", c))
  run <- function(op, p1, p2, f) {
    v <- tryCatch(suppressWarnings(f()), error = function(e) NULL)
    if (!is.null(v)) vec(c(op, by_row, na, p1, p2), m, rows, cols, as.numeric(v))
  }
  nm <- as.logical(na)
  sel <- function(name) get(paste0(if (by_row) "row" else "col", name))
  run(0, 0, 0, function() sel("Sums2")(m, rows_, cols_, na.rm = nm))
  run(1, 0, 0, function() sel("Means2")(m, rows_, cols_, na.rm = nm))
  run(2, 0, 0, function() sel("Vars")(m, rows_, cols_, na.rm = nm))
  run(3, 0, 0, function() sel("Sds")(m, rows_, cols_, na.rm = nm))
  run(4, 0, 0, function() sel("Medians")(m, rows_, cols_, na.rm = nm))
  run(5, 0, 0, function() sel("Mads")(m, rows_, cols_, na.rm = nm))
  for (pi in seq_along(probs)) run(6, pi - 1, 0, function() sel("Quantiles")(m, rows_, cols_, probs = probs[[pi]], na.rm = nm, drop = FALSE))
  for (ti in seq_along(ties)) run(7, ti - 1, 0, function() sel("Ranks")(m, rows_, cols_, ties.method = ties[ti]))
  run(8, 0, 0, function() sel("Cumsums")(m, rows_, cols_))
  for (lag in 1:2) for (d in 1:2) run(9, lag, d, function() sel("Diffs")(m, rows_, cols_, lag = lag, differences = d))
  for (w in 1:3) run(10, w, 0, function() sel("OrderStats")(m, rows_, cols_, which = w))
  run(11, 0, 0, function() as.vector(sel("Ranges")(m, rows_, cols_, na.rm = nm)))
}

xs <- list(c(1, 2, 3, 4), c(5, 1, NA, 7, 2), c(0.5, 0.25, 4), c(3, 3, 3), c(-2, 8))
for (x in xs) for (na in c(FALSE, TRUE)) {
  w <- seq_along(x) / 2
  v <- tryCatch(weightedMean(x, w, na.rm = na), error = function(e) NA); add("wmean", c(na, length(x), x, w), v)
  for (interp in c(0, 1)) {
    ww <- c(1, 2, 1, 3, 1)[seq_along(x)]
    v <- tryCatch(weightedMedian(x, ww, na.rm = na, interpolate = as.logical(interp)), error = function(e) NA)
    add("wmedian", c(na, interp, length(x), x, ww), v)
  }
}
for (x in list(c(0.5, 1.5, 2.5, 3, 4, 7), c(1, 1, 2, 2, 3, 3), c(-1, 0, 10)))
  for (bx in list(c(0, 2, 4, 6), c(1, 2, 3), c(0, 5, 10))) for (right in c(FALSE, TRUE)) {
    v <- binCounts(x, bx = bx, right = right)
    add("bins", c(right, length(x), length(bx), x, bx, length(v)), sum(v * seq_along(v)))
    for (k in seq_along(v)) add("binsk", c(right, length(x), length(bx), x, bx, k - 1), v[k])
  }
emit("matrixstats", "matrixStats", list(cases))
