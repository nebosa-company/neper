# multcomp glht on a linear model: estimates, standard errors, t, raw, Bonferroni and Holm p values for a contrast matrix.
#   args: (n, p, m, x[n*p] row-major with constant, y[n], K[m*p] row-major)
#   fn "est" "se" "t" "p" "bonf" "holm" (weighted by position over the contrasts)
suppressMessages(library(multcomp))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-11)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20261224)
for (rep in 1:24) {
  n <- sample(30:120, 1); p <- sample(3:5, 1); m <- sample(2:5, 1)
  x <- cbind(1, matrix(rnorm(n * (p - 1)), n)); y <- as.vector(x %*% rnorm(p)) + rnorm(n)
  K <- matrix(sample(c(-1, 0, 1), m * p, TRUE), m); K[cbind(seq_len(m), sample(p, m, TRUE))] <- 1
  d <- data.frame(y, x[, -1, drop = FALSE]); names(d)[-1] <- paste0("x", seq_len(p - 1))
  f <- lm(y ~ ., d); colnames(K) <- names(coef(f)); rownames(K) <- paste0("c", seq_len(m))
  g <- glht(f, linfct = K)
  s0 <- summary(g, test = adjusted("none"))$test; sb <- summary(g, test = adjusted("bonferroni"))$test; sh <- summary(g, test = adjusted("holm"))$test
  a <- c(n, p, m, as.vector(t(x)), y, as.vector(t(K)))
  add("est", a, ws(s0$coefficients)); add("se", a, ws(s0$sigma)); add("t", a, ws(s0$tstat)); add("p", a, ws(s0$pvalues))
  add("bonf", a, ws(sb$pvalues)); add("holm", a, ws(sh$pvalues))
}
emit("multcomp", "multcomp", list(cases))
