# ggdist: qi, hdci, hdi and Mode of a sample (default bandwidth_dpi, bounder_cdf, no weights). ggdist is not installed in the default library:
# its CRAN source (3.3.3, pure R plus a binning routine these functions do not use) is installed with the compiled part dropped;
# put that library first in R_ORACLE_LIB.
#   args (n, x[n], width [, row])   fn "qi_lo" "qi_hi" "hdci_lo" "hdci_hi" "hdi_n" "hdi_lo" "hdi_hi" (row zero-based) "mode"
suppressMessages(library(ggdist))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261220)
for (rep in 1:18) {
  n <- sample(c(80, 150, 300), 1)
  x <- switch(rep %% 6 + 1, rgamma(n, 2), rnorm(n), c(rnorm(n %/% 2, -2, 0.6), rnorm(n - n %/% 2, 2, 0.8)), rexp(n), runif(n), rt(n, 4))
  w <- sample(c(0.5, 0.8, 0.9, 0.95), 1); a <- c(n, x, w)
  q <- qi(x, .width = w); add("qi_lo", a, q[1, 1]); add("qi_hi", a, q[1, 2])
  h <- hdci(x, .width = w); add("hdci_lo", a, h[1, 1]); add("hdci_hi", a, h[1, 2])
  hd <- hdi(x, .width = w); add("hdi_n", a, nrow(hd))
  for (j in seq_len(nrow(hd))) { add("hdi_lo", c(a, j - 1), hd[j, 1]); add("hdi_hi", c(a, j - 1), hd[j, 2]) }
  add("mode", a, Mode(x))
}
xi <- rpois(120, 3); add("mode", c(120, xi, 0.9), Mode(xi))
emit("ggdist", "ggdist", list(cases))
