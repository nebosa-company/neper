# gmp: big integer arithmetic checked through the result modulo 1e9 and its digit count.
#   args: (op, ca, cb, cc, extra, chunks of a..., chunks of b..., chunks of c...) with the chunks base 1e6 little-endian; fn "mod9" and "ndig"
#   op: 0 a+b  1 a*b  2 a%/%b  3 a%%b  4 gcd  5 lcm  6 powm(a, b, c)  7 inverse(a, b)  8 isprime(a)  9 nextprime(a)  10 chooseZ(extra, b small)
#   11 fibnum(extra)  12 lucnum(extra)  13 factorialZ(extra)   (for 8 the want is 1 or 0 under mod9)
suppressMessages(library(gmp))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-9)
chunks <- function(z) { s <- as.character(z); if (s == "0") return(0); out <- c(); while (nchar(s) > 0) { k <- nchar(s); out <- c(out, as.numeric(substr(s, max(1, k - 5), k))); s <- if (k > 6) substr(s, 1, k - 6) else "" }; out }
rnd <- function(digits) { s <- paste0(sample(1:9, 1), paste(sample(0:9, digits - 1, replace = TRUE), collapse = "")); as.bigz(s) }
pack <- function(op, a, b = as.bigz(0), cc = as.bigz(0), extra = 0) { ca <- chunks(a); cb <- chunks(b); ccc <- chunks(cc); c(op, length(ca), length(cb), length(ccc), extra, ca, cb, ccc) }
emitcase <- function(args, r) { add("mod9", args, as.numeric(r %% 1e9)); add("ndig", args, nchar(as.character(r))) }
set.seed(20261213)
for (rep in 1:12) {
  a <- rnd(sample(10:60, 1)); b <- rnd(sample(5:30, 1)); m <- nextprime(rnd(sample(10:30, 1)))
  emitcase(pack(0, a, b), a + b); emitcase(pack(1, a, b), a * b)
  emitcase(pack(2, a, b), a %/% b); emitcase(pack(3, a, b), a %% b)
  emitcase(pack(4, a, b), gcd.bigz(a, b)); emitcase(pack(5, a, b), lcm.bigz(a, b))
  emitcase(pack(6, a, b, m), powm(a, b, m))
  emitcase(pack(7, a, m), inv.bigz(a, m))
  p <- if (rep %% 2 == 0) nextprime(rnd(sample(8:40, 1))) else rnd(sample(8:40, 1))
  add("mod9", pack(8, p), as.numeric(isprime(p) > 0))
  emitcase(pack(9, a), nextprime(a))
  n <- sample(20:200, 1); k <- sample(2:n, 1)
  emitcase(pack(10, as.bigz(0), as.bigz(k), as.bigz(0), n), chooseZ(n, k))
  emitcase(pack(11, as.bigz(0), as.bigz(0), as.bigz(0), n), fibnum(n))
  emitcase(pack(12, as.bigz(0), as.bigz(0), as.bigz(0), n), lucnum(n))
  emitcase(pack(13, as.bigz(0), as.bigz(0), as.bigz(0), sample(5:120, 1)), 1)
}
cases <- Filter(function(cs) !(cs$args[1] == 13), cases)
for (n in c(5, 20, 60, 120)) emitcase(c(13, 1, 1, 1, n, 0, 0, 0), factorialZ(n))
emit("gmp", "gmp", list(cases))
