# agricolae: LSD.test, HSD.test and scheffe.test pairwise comparisons (no grouping letters).
#   args: (kind, n, k, y[n]..., group labels 1..k [n]...)   kind 0 LSD (p.adj none), 1 HSD, 2 Scheffe, 3 SNK, 4 Duncan
#   fn "diff" "lcl" "ucl" (the sums of the column over the pairs weighted by pair position) and "p" (the p values, which the package rounds to 4 decimals)
suppressMessages(library(agricolae))
cases <- list()
add <- function(fn, args, want, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = abs)
set.seed(20261220)
for (rep in 1:14) {
  k <- sample(3:6, 1); sz <- sample(4:9, k, replace = TRUE); n <- sum(sz)
  g <- factor(rep(1:k, sz)); y <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.8), 4)
  m <- aov(y ~ g)
  for (kind in 0:4) {
    r <- switch(kind + 1, LSD.test(m, "g", group = FALSE, p.adj = "none"), HSD.test(m, "g", group = FALSE), scheffe.test(m, "g", group = FALSE), SNK.test(m, "g", group = FALSE), duncan.test(m, "g", group = FALSE))$comparison
    a <- c(kind, n, k, y, as.numeric(g))
    pv <- r[[2]]; w <- seq_len(nrow(r))
    add("diff", a, sum(r[[1]] * w)); add("p", a, sum(pv * w), abs = 1e-4 * nrow(r) * (nrow(r) + 1) / 2)
    add("lcl", a, sum(r$LCL * w)); add("ucl", a, sum(r$UCL * w))
  }
}
emit("agricolae", "agricolae", list(cases))
