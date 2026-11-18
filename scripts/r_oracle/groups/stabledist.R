# stabledist::dstable (name "d") and pstable (name "p") in the S0 parametrisation. args: (alpha, beta, gamma, delta, x)
suppressMessages(library(stabledist))
cases <- list()
set.seed(20261801)
for (rep in 1:60) {
  al <- c(runif(1, 0.3, 0.98), runif(1, 1.02, 1.99))[sample(1:2, 1)]
  be <- c(0, runif(1, -1, 1), runif(1, -0.999, 0.999))[sample(1:3, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  for (x in de + ga * c(rnorm(2, 0, 1.5), runif(1, 0.05, 6) * c(-1, 1)[sample(1:2, 1)])) {
    d <- dstable(x, al, be, ga, de)
    if (is.finite(d) && d > 1e-12) cases[[length(cases) + 1]] <- case("d", c(al, be, ga, de, x), d, rel = 1e-8, abs = 1e-14)
  }
}
for (rep in 1:60) {
  al <- c(runif(1, 0.3, 0.98), runif(1, 1.02, 1.99))[sample(1:2, 1)]
  be <- c(0, runif(1, -1, 1), runif(1, -0.999, 0.999))[sample(1:3, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  for (x in de + ga * c(rnorm(2, 0, 1.5), runif(1, 0.05, 6) * c(-1, 1)[sample(1:2, 1)])) {
    pv <- suppressWarnings(pstable(x, al, be, ga, de, silent = TRUE))
    if (is.finite(pv)) cases[[length(cases) + 1]] <- case("p", c(al, be, ga, de, x), pv, rel = 1e-8, abs = 1e-12)
  }
}
for (rep in 1:25) {
  al <- c(runif(1, 0.5, 0.98), runif(1, 1.05, 1.95))[sample(1:2, 1)]
  be <- c(0, runif(1, -0.9, 0.9))[sample(1:2, 1)]
  ga <- runif(1, 0.4, 2.5); de <- rnorm(1)
  for (pp in runif(2, 0.05, 0.95)) {
    qv <- tryCatch(suppressWarnings(qstable(pp, al, be, ga, de)), error = function(e) NA_real_)
    if (is.finite(qv)) cases[[length(cases) + 1]] <- case("q", c(al, be, ga, de, pp), qv, rel = 1e-3, abs = 1e-4)
  }
}
emit("stabledist", "stabledist", list(cases))
