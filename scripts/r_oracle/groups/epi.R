# Epi: twoby2 on a 2 by 2 table.
#   args: (a, b, c, d, which)   fn "m"; which 0..2 row-1 risk (est, lower, upper), 3..5 row-2 risk, 6..8 risk ratio, 9..11 odds ratio, 12..14 probability difference, 15 asymptotic p, 16 exact p
suppressMessages(library(Epi))
cases <- list()
add <- function(which, base, want) cases[[length(cases) + 1]] <<- case("m", c(base, which), want, rel = 1e-8, abs = 1e-10)
set.seed(20261230)
for (rep in 1:25) {
  a <- sample(3:150, 1); b <- sample(30:2500, 1); cc <- sample(2:120, 1); d <- sample(30:3000, 1)
  r <- twoby2(matrix(c(a, cc, b, d), 2), print = FALSE)
  base <- c(a, b, cc, d)
  tb <- r$table; me <- r$measures
  for (i in 1:3) add(i - 1, base, tb[1, 2 + i]); for (i in 1:3) add(2 + i, base, tb[2, 2 + i])
  for (i in 1:3) add(5 + i, base, me[1, i]); for (i in 1:3) add(8 + i, base, me[2, i])
  for (i in 1:3) add(11 + i, base, me[nrow(me), i])
  add(15, base, r$p.value[1]); add(16, base, r$p.value[2])
}
# ROC (test, stat): "roc" args (n, test..., stat..., kind, k, col) with kind 0 table entry (k row from 0, col 0 sens 1 spec 2 pvp 3 pvn 4 cut), 1 AUC, 2 the maximising cutpoint
for (rep in 1:15) {
  n <- sample(20:60, 1); stat <- rbinom(n, 1, 0.4); if (length(unique(stat)) < 2) next
  test <- round(rnorm(n, stat * 0.9, 1), 1)
  r <- suppressWarnings(ROC(test = test, stat = stat, plot = "none"))
  res <- r$res; nr <- nrow(res)
  for (k in sample(0:(nr - 1), min(5, nr))) for (col in 0:4) {
    v <- res[k + 1, col + 1]; if (is.nan(v) || is.infinite(v)) next
    cases[[length(cases) + 1]] <- case("roc", c(n, test, stat, 0, k, col), v, rel = 1e-9, abs = 1e-12)
  }
  cases[[length(cases) + 1]] <- case("roc", c(n, test, stat, 1, 0, 0), r$AUC, rel = 1e-9, abs = 1e-12)
  mxf <- res[which((res[, 1] + res[, 2]) == max(res[, 1] + res[, 2]))[1], 5]
  cases[[length(cases) + 1]] <- case("roc", c(n, test, stat, 2, 0, 0), mxf, rel = 1e-9, abs = 1e-12)
}
emit("epi", "Epi", list(cases))
