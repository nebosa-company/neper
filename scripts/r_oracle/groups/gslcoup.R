# gsl: coupling_3j, coupling_6j and coupling_9j (twice the angular momenta) with error estimates.
#   "j" (n, part, args...): n = 3, 6 or 9 symbols' arity (3j has six arguments, padded to nine); part 0 value, 1 error
suppressMessages(library(gsl))
cases <- list()
set.seed(20262956)
ok <- function(a, b, c) (a + b + c) %% 2 == 0 && a + b >= c && a + c >= b && b + c >= a
add <- function(n, args, r) {
  if (r$status != 0 || r$val == 0) return()
  a9 <- c(args, rep(0, 9 - length(args)))
  cases[[length(cases) + 1]] <<- case("j", c(n, 0, a9), r$val, rel = 1e-11, abs = 1e-15)
  cases[[length(cases) + 1]] <<- case("j", c(n, 1, a9), r$err, rel = 1e-8, abs = 1e-300)
}
g <- function(f, ...) f(..., give = TRUE, strict = FALSE)
k <- 0
while (k < 80) {
  j <- sample(0:14, 3, TRUE); if (!ok(j[1], j[2], j[3])) next
  m1 <- sample(seq(-j[1], j[1], by = 2), 1); m2 <- sample(seq(-j[2], j[2], by = 2), 1); m3 <- -m1 - m2
  if (abs(m3) > j[3] || (j[3] + m3) %% 2 != 0) next
  add(3, c(j, m1, m2, m3), g(coupling_3j, j[1], j[2], j[3], m1, m2, m3)); k <- k + 1
}
k <- 0
while (k < 80) {
  j <- sample(0:12, 6, TRUE)
  if (!(ok(j[1], j[2], j[3]) && ok(j[1], j[5], j[6]) && ok(j[4], j[2], j[6]) && ok(j[4], j[5], j[3]))) next
  add(6, j, g(coupling_6j, j[1], j[2], j[3], j[4], j[5], j[6])); k <- k + 1
}
k <- 0
while (k < 40) {
  j <- sample(0:6, 9, TRUE)
  if (!(ok(j[1], j[2], j[3]) && ok(j[4], j[5], j[6]) && ok(j[7], j[8], j[9]) && ok(j[1], j[4], j[7]) && ok(j[2], j[5], j[8]) && ok(j[3], j[6], j[9]))) next
  add(9, j, g(coupling_9j, j[1], j[2], j[3], j[4], j[5], j[6], j[7], j[8], j[9])); k <- k + 1
}
emit("gslcoup", "gsl", list(cases))
