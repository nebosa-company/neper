# diptest::dip on a sorted sample: the statistic and the modal interval (1-based indices).
#   args: (n, x[n] sorted)   fn "dip" "low" "high"
suppressMessages(library(diptest))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261116)
for (rep in 1:60) {
  n <- if (rep %% 10 == 0) sample(c(100, 250, 3000), 1) else sample(4:80, 1)
  x <- switch(rep %% 4 + 1, rnorm(n), c(rnorm(n %/% 2, 0), rnorm(n - n %/% 2, 4)), runif(n), rexp(n))
  x <- sort(round(x, 3)); a <- c(n, x)
  r <- dip(x, full.result = TRUE)
  add("dip", a, r$dip); add("low", a, r$lo.hi[1]); add("high", a, r$lo.hi[2]); add("p", a, dip.test(x)$p.value); if (n <= 80) { set.seed(rep); add("psim", c(a, rep), dip.test(x, simulate.p.value = TRUE, B = 100)$p.value) }
}
emit("diptest", "diptest", list(cases))
