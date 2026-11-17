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
# erf (23, |x| below 6), log 2 (24), Catalan (25)
for (rep in 1:60) {
  op <- sample(23:25, 1); prec <- sample(c(53, 80, 100, 128, 200), 1); m1 <- sample(1:(2^50), 1); e1 <- sample(-56:-46, 1); if (runif(1) < 0.5) m1 <- -m1
  x <- mpfr(m1, prec) * 2^e1; if (op == 23 && abs(asNumeric(x)) > 6) next
  z <- switch(op - 22, erf(x), Const("log2", prec), Const("catalan", prec)); if (!is.finite(z) || z == 0) next
  hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(op, prec, m1, e1, 1, 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
# zeta (26) for real s in (1.05, 12)
for (rep in 1:14) {
  prec <- sample(c(53, 80), 1); m1 <- sample(1:(2^50), 1); e1 <- sample(-49:-46, 1)
  x <- mpfr(m1, prec) * 2^e1; xv <- asNumeric(x); if (xv < 1.05 || xv > 12) next
  z <- zeta(x); hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(26, prec, m1, e1, 1, 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
# besselJ (27) of integer order 0 .. 3 for |x| below 12 (the order in the m2 slot)
for (rep in 1:40) {
  prec <- sample(c(53, 80, 128), 1); m1 <- sample(1:(2^50), 1); e1 <- sample(-52:-46, 1); nn <- sample(0:3, 1); if (runif(1) < 0.5) m1 <- -m1
  x <- mpfr(m1, prec) * 2^e1; if (abs(asNumeric(x)) > 12) next
  z <- jn(nn, x); if (!is.finite(z) || z == 0) next
  hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(27, prec, m1, e1, nn, 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
# Euler's constant (28)
for (prec in c(53, 64, 100, 128, 200)) { z <- Const("gamma", prec); hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(28, prec, 1, 0, 1, 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0); cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0) }
# directed rounding (100 + op 0 add 1 sub 2 mul 3 div 4 sqrt, prec, m1, e1, m2, e2, mode 0 N 1 Z 2 U 3 D 4 A, which 0 hi 1 lo)
modes <- c("N", "Z", "U", "D", "A")
for (rep in 1:200) {
  op <- sample(0:4, 1); prec <- sample(c(53, 60, 80, 100, 128), 1); md <- sample(0:4, 1)
  m1 <- sample(1:(2^50), 1); m2 <- sample(1:(2^50), 1); if (runif(1) < 0.5) m1 <- -m1; if (runif(1) < 0.5 && op != 4) m2 <- -m2
  if (op == 4) m1 <- abs(m1)
  e1 <- sample(-30:30, 1); e2 <- sample(-30:30, 1)
  x <- mpfr(m1, 3000) * 2^e1; y <- mpfr(m2, 3000) * 2^e2
  zz <- switch(op + 1, x + y, x - y, x * y, x / y, sqrt(x))
  z <- roundMpfr(zz, prec, rnd.mode = modes[md + 1])
  if (is.finite(z) && z != 0) { hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(100 + op, prec, m1, e1, m2, e2, md)
    cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0) }
}
# mpfr_get_str "str" (99, prec, m, e, base, ndigits, which -1 exponent or the digit index)
for (rep in 1:60) {
  prec <- sample(c(53, 80, 128), 1); m1 <- sample(1:(2^50), 1); if (runif(1) < 0.4) m1 <- -m1; e1 <- sample(-120:80, 1); base <- sample(c(2, 8, 10, 16, 36), 1); nd <- sample(c(5, 12, 20, 30), 1)
  x <- mpfr(m1, prec) * 2^e1; r <- .mpfr2str(x, digits = nd, base = base); st <- strsplit(r$str, "")[[1]]; st <- sub("-", "", r$str); ch <- strsplit(st, "")[[1]]
  dv <- match(tolower(ch), c(0:9, letters)) - 1
  a <- c(99, prec, m1, e1, base, nd)
  cases[[length(cases) + 1]] <- case("op", c(a, -1), r$exp, rel = 0, abs = 0)
  for (i in seq_along(dv)) cases[[length(cases) + 1]] <- case("op", c(a, i - 1), dv[i], rel = 0, abs = 0)
}
# mpfr("N e k", prec, rnd.mode) (98, prec, N high, N low (12 digits), k, mode, which): N = high * 10^12 + low
for (rep in 1:80) {
  prec <- sample(c(53, 80, 128), 1); hi_ <- sample(0:999999, 1); lo_ <- sample(0:999999999999, 1); k <- sample(-40:30, 1); md <- sample(0:4, 1)
  txt <- paste0(hi_, formatC(lo_, width = 12, flag = "0", format = "f", digits = 0), "e", k)
  if (hi_ == 0 && lo_ == 0) next
  z <- mpfr(txt, prec, rnd.mode = c("N", "Z", "U", "D", "A")[md + 1]); hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(98, prec, hi_, lo_, k, md)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
# directed rounding of exp, log, sin, cos, tan, atan, pow (97, prec, m1, e1, m2, e2, mode, fn 0..6, which)
for (rep in 1:140) {
  prec <- sample(c(53, 80, 128), 1); md <- sample(0:4, 1); fn <- sample(0:6, 1); m1 <- sample(1:(2^50), 1); m2 <- sample(1:(2^50), 1); e1 <- sample(-60:-48, 1); e2 <- sample(-52:-48, 1)
  if (fn != 1 && fn != 6 && runif(1) < 0.5) m1 <- -m1
  x <- mpfr(m1, 3000) * 2^e1; y <- mpfr(m2, 3000) * 2^e2
  if (fn == 1) { e1 <- sample(-20:20, 1); x <- mpfr(m1, 3000) * 2^e1 }
  zz <- switch(fn + 1, exp(x), log(x), sin(x), cos(x), tan(x), atan(x), x^y)
  z <- roundMpfr(zz, prec, rnd.mode = c("N", "Z", "U", "D", "A")[md + 1]); if (!is.finite(z) || z == 0) next
  hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(97, prec, m1, e1, m2, e2, md, fn)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
# besselY of integer order 0 .. 3 for 0.1 < x < 12 (96, prec, m1, e1, order, 0, which)
for (rep in 1:40) {
  prec <- sample(c(53, 80, 128), 1); m1 <- sample(1:(2^50), 1); e1 <- sample(-52:-46, 1); nn <- sample(0:3, 1)
  x <- mpfr(m1, prec) * 2^e1; xv <- asNumeric(x); if (xv < 0.1 || xv > 12) next
  z <- yn(nn, x); if (!is.finite(z) || z == 0) next
  hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(96, prec, m1, e1, nn, 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
# zeta (26) for real s in (-6, 1) apart from the pole
for (rep in 1:40) {
  prec <- sample(c(53, 80), 1); m1 <- sample(1:(2^50), 1); e1 <- sample(-49:-46, 1); if (runif(1) < 0.5) m1 <- -m1
  x <- mpfr(m1, prec) * 2^e1; xv <- asNumeric(x); if (xv < -6 || xv > 0.95) next
  z <- zeta(x); if (!is.finite(z) || z == 0) next
  hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(26, prec, m1, e1, 1, 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
# mpfr("N@k", base = b) in the bases 2, 8, 16, 36 (95, prec, N, k, base, mode, which)
for (rep in 1:60) {
  prec <- sample(c(53, 80, 128), 1); nv <- sample(1:(2^40), 1); k <- sample(-30:20, 1); base <- sample(c(2, 8, 16, 36), 1); md <- sample(0:4, 1)
  digs <- c(0:9, letters)[1:36]; v <- nv; sdig <- character(0); while (v > 0) { sdig <- c(digs[(v %% base) + 1], sdig); v <- v %/% base }
  txt <- paste0(paste(sdig, collapse = ""), "@", k)
  z <- mpfr(txt, prec, base = base, rnd.mode = c("N", "Z", "U", "D", "A")[md + 1]); if (!is.finite(z) || z == 0) next
  hi <- asNumeric(z); lo <- asNumeric(z - mpfr(hi, 2000)); a <- c(95, prec, nv, k, base, md)
  cases[[length(cases) + 1]] <- case("op", c(a, 0), hi, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("op", c(a, 1), lo, rel = 1e-9, abs = 0)
}
emit("mpfr", "Rmpfr", list(cases))
