# strucchange Fstats (from = 0.15) and breakpoints (h = 0.15) of y on x with a constant.
#   args: (n, p, m, y[n], x[n*p] row-major with the constant first)
#   fn "fsum" (sum of the F statistics weighted by position), "supf", "rss" (m breaks), "bp" (breakpoints weighted by position)
suppressMessages(library(strucchange))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-9)
set.seed(20261206)
for (rep in 1:20) {
  n <- sample(40:90, 1); p <- sample(1:2, 1); m <- sample(1:3, 1)
  x <- cbind(1, matrix(rnorm(n * (p - 1)), n)); nb <- sample(1:2, 1)
  cut <- sort(sample(12:(n - 12), nb)); seg <- findInterval(seq_len(n), cut + 1) + 1
  beta <- matrix(rnorm(p * (nb + 1), 0, 2), p)
  y <- sapply(seq_len(n), function(i) sum(x[i, ] * beta[, seg[i]])) + rnorm(n, 0, .5)
  a <- c(n, p, m, y, as.vector(t(x)))
  f <- Fstats(y ~ x - 1, from = 0.15)
  add("fsum", a, sum(as.vector(f$Fstats) * seq_along(f$Fstats))); add("supf", a, max(f$Fstats))
  b <- breakpoints(y ~ x - 1, h = 0.15, breaks = m)
  bm <- breakpoints(b, breaks = m)
  e <- efp(y ~ x - 1, type = "OLS-CUSUM"); s <- sctest(e)
  add("cus", a, unname(s$statistic)); add("cusp", a, unname(s$p.value))
  add("rss", a, summary(b)$RSS["RSS", m + 1]); add("bp", a, sum(bm$breakpoints * seq_along(bm$breakpoints)))
}
emit("strucchange", "strucchange", list(cases))
