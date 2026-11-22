# kernlab kmmd (matrix input): mmd1, mmd3, the Rademacher bound and the bootstrap bound of the asymptotic test, on R's stream.
#   args: (m, n, p, kind, par1, par2, par3, alpha, ntimes, frac, replace, seed, x[m*p] row-major, y[n*p] row-major); kinds 0 rbfdot(par1), 2 vanilladot, 4 laplacedot(par1)
#   fn "mmd1" "mmd3" "rad" "boot"
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-11, abs = 1e-13) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261303)
kinds <- c(0, 2, 4)
for (rep in 1:18) {
  kind <- kinds[(rep - 1) %% 3 + 1]
  m <- sample(40:60, 1); n <- sample(40:60, 1); p <- sample(2:4, 1)
  x <- matrix(rnorm(m * p), m); y <- matrix(rnorm(n * p, 0.4), n)
  s1 <- runif(1, 0.1, 1); alpha <- c(0.05, 0.1, 0.2)[(rep - 1) %/% 3 %% 3 + 1]; ntimes <- c(100, 150)[rep %% 2 + 1]
  frac <- c(1, 0.8)[(rep - 1) %/% 2 %% 2 + 1]; repl <- if (rep %% 4 == 0) 0 else 1; sd <- sample(1:100000, 1)
  kn <- switch(as.character(kind), "0" = rbfdot(s1), "2" = vanilladot(), "4" = laplacedot(s1))
  set.seed(sd)
  res <- kmmd(x, y, kernel = kn, alpha = alpha, asymptotic = TRUE, replace = repl == 1, ntimes = ntimes, frac = frac)
  a <- c(m, n, p, kind, s1, 0, 0, alpha, ntimes, frac, repl, sd, as.vector(t(x)), as.vector(t(y)))
  add("mmd1", a, mmdstats(res)[1]); add("mmd3", a, mmdstats(res)[2]); add("rad", a, Radbound(res)); add("boot", a, Asymbound(res))
}
# automatic sigma (kpar = "automatic": sigest(rbind(x, y), scaled = FALSE)[2], drawn from the stream before the bootstrap): kind 100 rbfdot (kernlab fails for the string "laplacedot")
for (rep in 1:8) {
  kind <- 100
  m <- sample(40:60, 1); n <- sample(40:60, 1); p <- sample(2:4, 1)
  x <- matrix(rnorm(m * p), m); y <- matrix(rnorm(n * p, 0.4), n)
  alpha <- c(0.05, 0.1)[rep %% 2 + 1]; ntimes <- 100; frac <- 1; sd <- sample(1:100000, 1)
  set.seed(sd)
  res <- suppressMessages(kmmd(x, y, kernel = "rbfdot", alpha = alpha, asymptotic = TRUE, replace = TRUE, ntimes = ntimes, frac = frac))
  a <- c(m, n, p, kind, 0, 0, 0, alpha, ntimes, frac, 1, sd, as.vector(t(x)), as.vector(t(y)))
  add("mmd1", a, mmdstats(res)[1]); add("mmd3", a, mmdstats(res)[2]); add("rad", a, Radbound(res)); add("boot", a, Asymbound(res))
}
emit("kernlabmmd", "kernlab", list(cases))
