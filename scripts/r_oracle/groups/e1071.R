# e1071: skewness and kurtosis (types 1 to 3) and countpattern.
#   skew, kurt: (type, n, x...)         pattern: (nrow, nvar, k, x row-wise...) -> the count of pattern k
library(e1071)
set.seed(20261115)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-11, abs = 1e-12)
for (k in 1:12) {
  x <- switch(k %% 4 + 1, round(rnorm(30), 3), round(rexp(25) * 3, 3), round(runif(11, -2, 9), 2), round(rlnorm(40), 3))
  if (k == 5) x <- c(1, 2, 7)
  if (k == 6) x <- c(0.5, 4, 4, 9, 10, 13)
  for (ty in 1:3) {
    s <- tryCatch(skewness(x, type = ty), error = function(e) NA)
    if (!is.na(s)) add("skew", c(ty, length(x), x), s)
    q <- tryCatch(kurtosis(x, type = ty), error = function(e) NA)
    if (!is.na(q)) add("kurt", c(ty, length(x), x), q)
  }
}
for (nv in 2:5) for (rep in 1:3) {
  nr <- sample(5:40, 1)
  m <- matrix(rbinom(nr * nv, 1, 0.5), nr, nv)
  p <- countpattern(m)
  for (kk in seq_along(p)) add("pattern", c(nr, nv, kk - 1, t(m)), p[kk])
}
emit("e1071", "e1071", list(cases))
