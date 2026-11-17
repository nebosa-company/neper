# Rmpfr: correctly rounded + - * / and sqrt at a chosen precision.
#   args: (op 0 add 1 sub 2 mul 3 div 4 sqrt, prec, m1, e1, m2, e2, which 0 hi 1 lo): x = m1 2^e1, y = m2 2^e2 (integers m below 2^53),
#   answered as the value rounded to a double (hi) and the remainder rounded to a double (lo)
suppressMessages(library(Rmpfr))
cases <- list()
set.seed(20261203)
for (rep in 1:200) {
  op <- sample(0:4, 1); prec <- sample(c(53, 60, 80, 100, 128, 200, 300), 1)
  m1 <- sample(1:(2^50), 1); m2 <- sample(1:(2^50), 1); if (runif(1) < 0.5) m1 <- -m1; if (runif(1) < 0.5 && op != 4) m2 <- -m2
  if (op == 4) m1 <- abs(m1)
  e1 <- sample(-30:30, 1); e2 <- sample(-30:30, 1)
  x <- mpfr(m1, prec) * 2^e1; y <- mpfr(m2, prec) * 2^e2
  z <- switch(op + 1, x + y, x - y, x * y, x / y, sqrt(x))
  if (is.finite(z) && z != 0) { hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000))
    a <- c(op, prec, m1, e1, m2, e2)
    cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0) }
}
emit("mpfr", "Rmpfr", list(cases))
