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
emit("epi", "Epi", list(cases))
