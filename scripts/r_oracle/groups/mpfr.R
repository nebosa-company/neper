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
# exp (op 5, |x| below 40) and log (op 6, x > 0) correctly rounded
for (rep in 1:120) {
  op <- sample(5:6, 1); prec <- sample(c(53, 80, 100, 128, 200), 1); m1 <- sample(1:(2^50), 1)
  e1 <- if (op == 5) sample(-60:-45, 1) else sample(-80:40, 1); if (op == 5 && runif(1) < 0.5) m1 <- -m1
  x <- mpfr(m1, prec) * 2^e1; if (op == 5 && abs(asNumeric(x)) > 40) next
  z <- if (op == 5) exp(x) else log(x); if (z == 0 || !is.finite(z)) next
  hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(op, prec, m1, e1, 1, 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
# sin (7), cos (8) for |x| below 100, pow (9) for x > 0 and moderate y, pi (10)
for (rep in 1:150) {
  op <- sample(7:10, 1); prec <- sample(c(53, 80, 100, 128, 200), 1); m1 <- sample(1:(2^50), 1); e1 <- sample(-49:-44, 1)
  m2 <- sample(1:(2^50), 1); e2 <- sample(-52:-46, 1)
  if (op %in% c(7, 8) && runif(1) < 0.5) m1 <- -m1
  if (op == 9) { e1 <- sample(-52:-48, 1) }
  x <- mpfr(m1, prec) * 2^e1; y <- mpfr(m2, prec) * 2^e2
  z <- switch(op - 6, sin(x), cos(x), x^y, Const("pi", prec))
  if (!is.finite(z) || z == 0) next
  hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(op, prec, m1, e1, m2, e2)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
# tan (11), sinh (12), cosh (13), tanh (14), atan (15)
for (rep in 1:150) {
  op <- sample(11:15, 1); prec <- sample(c(53, 80, 100, 128, 200), 1); m1 <- sample(1:(2^50), 1); e1 <- sample(-60:-49, 1)
  if (runif(1) < 0.5) m1 <- -m1
  x <- mpfr(m1, prec) * 2^e1; if (op %in% c(12, 13, 14) && abs(asNumeric(x)) > 20) next
  z <- switch(op - 10, tan(x), sinh(x), cosh(x), tanh(x), atan(x)); if (!is.finite(z) || z == 0) next
  hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(op, prec, m1, e1, 1, 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
# asin (16), acos (17), asinh (18), acosh (19), atanh (20)
for (rep in 1:150) {
  op <- sample(16:20, 1); prec <- sample(c(53, 80, 100, 128, 200), 1); m1 <- sample(1:(2^50), 1); e1 <- sample(-62:-51, 1)
  if (op %in% c(16, 17, 18, 20) && runif(1) < 0.5) m1 <- -m1
  if (op == 19) { m1 <- 2^50 + sample(1:(2^50), 1); e1 <- -50 }
  x <- mpfr(m1, prec) * 2^e1
  if (op %in% c(16, 17, 20) && abs(asNumeric(x)) >= 0.9) next
  z <- switch(op - 15, asin(x), acos(x), asinh(x), acosh(x), atanh(x)); if (!is.finite(z) || z == 0) next
  hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000))
  a <- c(op, prec, m1, e1, 1, 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
# lgamma (21) and gamma (22) for x in (0.3, 25), away from the zeros of lgamma
for (rep in 1:14) {
  op <- sample(21:22, 1); prec <- sample(c(53, 80, 100, 128), 1); e1 <- sample(-48:-46, 1); m1 <- sample(1:(2^50), 1)
  x <- mpfr(m1, prec) * 2^e1; xv <- asNumeric(x); if (xv < 0.3 || xv > 25) next
  if (op == 21 && abs(xv - 1) < 0.05 || abs(xv - 2) < 0.05) next
  z <- if (op == 21) lgamma(x) else gamma(x); if (!is.finite(z) || z == 0) next
  hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(op, prec, m1, e1, 1, 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
emit("mpfr", "Rmpfr", list(cases))
