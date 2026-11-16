# pROC: auc, DeLong variance and interval, and the paired DeLong test.
#   args: (n, y[n]..., x1[n]..., x2[n]...)   fn "auc" "var" "cilo" "cihi" (of x1), "z" "p" (roc.test of x1 against x2)
suppressMessages(library(pROC))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261216)
for (rep in 1:20) {
  n <- sample(20:80, 1); y <- rbinom(n, 1, 0.4); if (sum(y) < 3 || sum(y) > n - 3) next
  s <- c(0.8, 1.5, -0.7, 0.3)[rep %% 4 + 1]
  x1 <- round(rnorm(n) + s * y, if (rep %% 3 == 0) 1 else 4); x2 <- round(rnorm(n) + 0.4 * y + 0.3 * x1, if (rep %% 3 == 0) 1 else 4)
  r1 <- roc(y, x1, quiet = TRUE); r2 <- roc(y, x2, quiet = TRUE)
  a <- c(n, y, x1, x2)
  add("auc", a, as.numeric(auc(r1))); add("var", a, var(r1))
  ci <- ci.auc(r1); add("cilo", a, ci[1]); add("cihi", a, ci[3])
  rt <- roc.test(r1, r2, method = "delong", paired = TRUE)
  add("z", a, as.numeric(rt$statistic)); add("p", a, rt$p.value)
}
emit("proc", "pROC", list(cases))
