# PMCMRplus: steelsKSampleTest (kSamples' Steel.test, asymptotic). Args: (n, k, alt 0 greater 1 less 2 two.sided, what 0 statistic 1 p, x[n], group labels 1..k [n]).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262347)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("sk", args, want, rel = 1e-6, abs = 1e-8)
for (rep in 1:30) {
  k <- sample(3:5, 1); sz <- sample(5:10, k, replace = TRUE); n <- sum(sz); g <- factor(rep(1:k, sz)); alt <- (rep - 1) %% 3
  x <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.5), if (rep %% 2 == 0) 0 else 4)
  r <- tryCatch(suppressWarnings(suppressMessages(steelsKSampleTest(x, g, alternative = c("greater", "less", "two.sided")[alt + 1]))), error = function(e) NULL); if (is.null(r)) next
  a <- function(w) c(n, k, alt, w, x, as.numeric(g)); add(a(0), unname(r$statistic)); add(a(1), unname(r$p.value))
}
emit("pmcmr_steelk", "PMCMRplus", list(cases))
