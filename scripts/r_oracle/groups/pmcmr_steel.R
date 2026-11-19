# PMCMRplus: steelTest (balanced many-to-one rank test, critical values from the package's table). Args: (n, k dose levels, alt 0 two.sided 1 greater, j, what 0 rank sum 1 critical value, x[n * (k + 1)] by group).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262342)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("sl", args, want, rel = 0, abs = 1e-12)
for (rep in 1:30) {
  n <- sample(4:12, 1); k <- sample(2:ifelse(n == 4, 6, 9), 1); alt <- sample(0:1, 1)
  g <- factor(rep(0:k, each = n)); x <- round(rnorm(n * (k + 1)) + as.numeric(g) * runif(1, 0, 0.4), if (rep %% 3 == 0) 1 else 4)
  r <- tryCatch(suppressWarnings(steelTest(x, g, alternative = c("two.sided", "greater")[alt + 1])), error = function(e) NULL); if (is.null(r)) next
  for (j in 1:k) { a <- function(w) c(n, k, alt, j, w, x); add(a(0), unname(r$statistic[j, 1])); add(a(1), unname(r$crit.value[j, 1])) }
}
emit("pmcmr_steel", "PMCMRplus", list(cases))
