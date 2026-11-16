# hdrcdepkg: hdrcde::hdr on a sample with a given bandwidth and its default density.
#   args: (what 0 falpha 1 number of ends 2 end k, k, prob, bw, nx, x...). falpha is exact; the ends are roots found by uniroot (tolerance about 1e-4), so they are compared at abs 5e-4.
suppressMessages(library(hdrcde))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20262016)
for (rep in 1:25) {
  n <- sample(100:400, 1); x <- round(if (rep %% 3 == 0) c(rnorm(n / 2, -2), rnorm(n - n / 2, 2)) else rnorm(n, 0, runif(1, 0.5, 2)), 5); bw <- runif(1, 0.2, 0.7); pr <- sample(c(0.5, 0.8, 0.95), 1)
  n <- length(x); den <- density(x, bw = bw); h <- hdr(x, prob = pr, den = den)
  add("hdr", c(0, 0, pr, bw, n, x), h$falpha[[1]])
  ends <- h$hdr[1, ]; ends <- ends[!is.na(ends)]
  add("hdr", c(1, 0, pr, bw, n, x), length(ends), 0, 0)
  for (k in seq_along(ends)) add("hdr", c(2, k - 1, pr, bw, n, x), ends[k], 0, 5e-4)
}
emit("hdrcdepkg", "hdrcde", list(cases))
