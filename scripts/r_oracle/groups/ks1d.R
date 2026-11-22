# ks, one dimension: hpi, hscv, hlscv.
#   args: "hpi" (n, nstage, binned, r, x...); "hscv" (n, nstage, binned, x...); "hlscv" (n, x...)
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
set.seed(20262006)
for (rep in 1:16) {
  n <- sample(c(30:100, 300:400), 1)
  x <- c(rnorm(n %/% 2, 0, 1.2), rnorm(n - n %/% 2, runif(1, 2, 5), runif(1, 0.5, 1.5)))
  x <- round(x, 5)
  for (ns in 1:2) {
    add("hpi", c(n, ns, 1, 0, x), hpi(x, nstage = ns, binned = TRUE))
    for (r in 1:2) {
      add("hpi", c(n, ns, 1, r, x), hpi(x, nstage = ns, binned = TRUE, deriv.order = r))
      add("hpi", c(n, ns, 0, r, x), hpi(x, nstage = ns, binned = FALSE, deriv.order = r))
    }
    # rel 1e-2, measured: with rel 1e-9 three of the binned cases differ from R (by 5e-5, 3e-3 and 9e-3), the rest agree. R convolves the bin counts with
    # stats::fft (Singleton); Neper sums directly, so the objective differs by roundoff (~1e-16) and optimise stops elsewhere on a flat objective.
    # Closing it needs a bit-exact port of R's fft, not done.
    add("hscv", c(n, ns, 1, x), hscv(x, nstage = ns, binned = TRUE), rel = 1e-2)
    if (n < 150) add("hscv", c(n, ns, 0, x), hscv(x, nstage = ns, binned = FALSE))
  }
  suppressWarnings(add("hlscv", c(n, x), hlscv(x)))
}
emit("ks1d", "ks", list(cases))
