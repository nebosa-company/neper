# pracma: trapz, cumtrapz, polyval, polyfit, findpeaks, rref, primes, factors, gcd, nchoosek, cross.
#   args vary by fn:
#   "trapz" "cumtrapz" (cumulative values weighted by position): (n, x..., y...)
#   "polyfit" (deg, n, x..., y...) -> coefficient index k = c(0..) in the first slot after: args (deg, k, n, x..., y...)   "polyval": (x, coefficients...)
#   "fp_count" "fp_sum" (findpeaks): (nups, ndowns, minh, mindist, thr, npeaks, sortstr, n, x...); sum is as.vector(t(X)) weighted by 1..len
#   "rref" (nr, nc, A row-major...) -> weighted sum of the result; "primes" (n) -> count; "factors" (n) -> sum and count as two cases "fsum" "fcnt"
#   "gcd" (a, b, which: 0 g, 1 c, 2 d); "nchoosek" (n, k); "cross" (x1..3, y1..3, component)
suppressMessages(library(pracma))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-10)
set.seed(20261206)
for (rep in 1:10) {
  n <- sample(8:25, 1); x <- sort(runif(n, 0, 10)); y <- sin(x) + 0.3 * rnorm(n)
  add("trapz", c(n, x, y), trapz(x, y))
  add("cumtrapz", c(n, x, y), sum(as.vector(cumtrapz(x, y)) * seq_len(n)))
  deg <- sample(1:4, 1); co <- polyfit(x, y, deg)
  for (k in seq_along(co)) add("polyfit", c(deg, k - 1, n, x, y), co[k], rel = 1e-7)
  add("polyval", c(1.7, co), polyval(co, 1.7))
  nu <- sample(1:2, 1); nd <- sample(1:2, 1); mp <- sample(1:3, 1)
  z <- round(cumsum(rnorm(40)), 1)
  for (ss in 0:1) {
    pk <- findpeaks(z, nups = nu, ndowns = nd, minpeakheight = -1, minpeakdistance = mp, threshold = 0, npeaks = 0, sortstr = ss == 1)
    a <- c(nu, nd, -1, mp, 0, 0, ss, 40, z)
    add("fp_count", a, if (is.null(pk)) 0 else nrow(pk))
    if (!is.null(pk)) add("fp_sum", a, sum(as.vector(t(pk)) * seq_len(length(pk))))
  }
  A <- matrix(sample(-4:6, 12, replace = TRUE), 3, 4)
  if (rep %% 2 == 0) A[3, ] <- A[1, ] + A[2, ]
  R <- rref(A); add("rref", c(3, 4, as.vector(t(A))), sum(as.vector(t(R)) * seq_len(12)))
  nn <- sample(10:3000, 1)
  add("primes", nn, length(primes(nn)))
  m <- sample(4:100000, 1); f <- factors(m)
  add("fsum", m, sum(f)); add("fcnt", m, length(f))
  a1 <- sample(-60:200, 1); b1 <- sample(1:150, 1); g <- gcd(a1, b1, extended = TRUE)
  add("gcd", c(a1, b1, 0), g$g); add("gcd", c(a1, b1, 1), g$c); add("gcd", c(a1, b1, 2), g$d)
  nk <- sample(5:30, 1); add("nchoosek", c(nk, sample(0:nk, 1)), 0)
  xx <- rnorm(3); yy <- rnorm(3); cr <- cross(xx, yy)
  for (c3 in 0:2) add("cross", c(xx, yy, c3), cr[c3 + 1])
}
# nchoosek reference values are filled from R directly
cases <- lapply(cases, function(cs) { if (cs$fn == "nchoosek") cs$want <- choose(cs$args[1], cs$args[2]); cs })
emit("pracma", "pracma", list(cases))
