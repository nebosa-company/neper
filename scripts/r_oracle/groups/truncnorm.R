# truncnorm: d, p, q, e, v and r of the truncated normal.
#   args: (x or p or q, a, b, mean, sd)   fn "d" "p" "q";  "e" "v": (a, b, mean, sd);  "r": (seed, a, b, mean, sd, pos) the pos-th of 8 draws
library(truncnorm)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-12)
set.seed(20261115)
ab <- list(c(-Inf, Inf), c(0, Inf), c(-Inf, 1.5), c(-1, 2), c(0.5, 3), c(2, 2.4), c(3, 8), c(-6, -2), c(-0.2, 0.2), c(1, 1.001), c(-3, 0), c(5, Inf), c(-Inf, -4), c(8, 9))
ms <- list(c(0, 1), c(1.5, 2), c(-2, 0.5), c(0.3, 3))
for (r in ab) for (m in ms) {
  a <- r[1]; b <- r[2]; mu <- m[1]; sd <- m[2]
  xs <- c(-5, -1, 0, 0.7, 2, 4, 9); xs <- xs[xs >= a & xs <= b]
  if (is.finite(a) && is.finite(b)) xs <- c(xs, a, b, (a + b) / 2)
  for (x in xs) { add("d", c(x, a, b, mu, sd), dtruncnorm(x, a, b, mu, sd)); add("p", c(x, a, b, mu, sd), ptruncnorm(x, a, b, mu, sd)) }
  for (p in c(0, 0.01, 0.25, 0.5, 0.9, 0.999, 1)) {
    q <- tryCatch(qtruncnorm(p, a, b, mu, sd), error = function(e) NA, warning = function(w) NA)
    if (is.finite(q)) add("q", c(p, a, b, mu, sd), q)
  }
  e <- etruncnorm(a, b, mu, sd); v <- vtruncnorm(a, b, mu, sd)
  if (is.finite(e)) add("e", c(a, b, mu, sd), e)
  if (is.finite(v)) add("v", c(a, b, mu, sd), v)
  seed <- sample(1e6, 1); set.seed(seed)
  rv <- tryCatch(rtruncnorm(8, a, b, mu, sd), error = function(e) NULL)
  if (!is.null(rv) && all(is.finite(rv))) for (i in 1:8) add("r", c(seed, a, b, mu, sd, i - 1), rv[i])
}
emit("truncnorm", "truncnorm", list(cases))
