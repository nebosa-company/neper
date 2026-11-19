# nlm: R's stats::nlm (uncmin.c optif9) against lib/e/algo/stat/nlm.e, tests/selfhost/fixtures/link/oracle_nlm.
#   A case is fn "nlm" with args = [fid (the test function of oracle_nlminb), iterlim (NA keeps 100), n, start (n), m, data (m)]. Its want is the minimum; the cases after it, fn "o", are the values of the
#   result at an index: 1 the termination code, 2 iterations, 3.. the estimate. Code and iterations are compared exactly, the rest to 1e-8 (1e-6 for fid 3 and 13, which call exp and log).
cases <- list()
objs <- list()
objs[[1]] <- function(x, d) { a <- x[2] - x[1] * x[1]; b <- 1 - x[1]; 100 * a * a + b * b }
objs[[2]] <- function(x, d) { s <- 0; for (i in seq_along(x)) { dd <- x[i] - i; s <- s + i * dd * dd }; s }
objs[[3]] <- function(x, d) { s2 <- exp(x[1]); m <- length(d) / 2; s <- 0; for (i in 1:m) { w <- s2 + d[m + i]; s <- s + 0.5 * (log(w) + d[i] * d[i] / w) }; s }
objs[[4]] <- function(x, d) { a <- x[1] - 1; b <- x[2] + 2; c <- x[4] - x[1]; a * a + b * b + c * c }
objs[[5]] <- function(x, d) { if (x[1] > 2.5) return(Inf); a <- x[1] - 3; b <- x[2] + 1; a * a + b * b }
objs[[6]] <- function(x, d) abs(x[1] - 1) + abs(x[2] - 2)
objs[[7]] <- function(x, d) { a <- x[1] + 10 * x[2]; b <- x[3] - x[4]; c <- x[2] - 2 * x[3]; e <- x[1] - x[4]; a * a + 5 * b * b + c * c * c * c + 10 * e * e * e * e }
objs[[8]] <- function(x, d) { a <- 1.5 - x[1] + x[1] * x[2]; b <- 2.25 - x[1] + x[1] * (x[2] * x[2]); c <- 2.625 - x[1] + x[1] * (x[2] * x[2] * x[2]); a * a + b * b + c * c }
objs[[9]] <- function(x, d) { a <- x[1] * x[1] + x[2] - 11; b <- x[1] + x[2] * x[2] - 7; a * a + b * b }
objs[[10]] <- function(x, d) { a <- x[2] - x[1] * x[1]; b <- 1 - x[1]; c <- x[4] - x[3] * x[3]; e <- 1 - x[3]; 100 * a * a + b * b + 90 * c * c + e * e + 10.1 * ((x[2] - 1) * (x[2] - 1) + (x[4] - 1) * (x[4] - 1)) + 19.8 * (x[2] - 1) * (x[4] - 1) }
objs[[11]] <- function(x, d) { s <- 0; for (i in 1:(length(x) - 1)) { a <- x[i + 1] - x[i] * x[i]; b <- 1 - x[i]; s <- s + 100 * a * a + b * b }; s }
objs[[12]] <- function(x, d) { if (x[1] < -0.5) return(NaN); a <- x[1] - 1; b <- x[2] - 1; a * a + b * b }
objs[[13]] <- function(x, d) exp(x[1]) - 2 * x[1] + x[2] * x[2]
objs[[14]] <- function(x, d) { a <- x[1]; a * a * a * a - 3 * a * a + a }
objs[[15]] <- function(x, d) { s <- 0; for (i in seq_along(x)) { s <- s + (x[i] - 0.5 * i) * (x[i] - 0.5 * i) }; a <- 0; for (i in seq_along(x)) a <- a + x[i]; s + 0.01 * a * a }
objs[[16]] <- function(x, d) { a <- x[1]; 1 + (a - 1) * (a - 1) * (a - 1) * (a - 1) }

yv <- c(0.31, -0.42, 0.15, 0.9, -0.63, 0.22, 0.05, -0.18, 0.47, -0.39)
vv <- c(0.05, 0.11, 0.08, 0.2, 0.06, 0.15, 0.09, 0.04, 0.12, 0.07)

run <- function(fid, x0, data = numeric(), iterlim = NA) {
  f <- function(x) objs[[fid]](x, data)
  r <- suppressWarnings(if (is.na(iterlim)) nlm(f, x0) else nlm(f, x0, iterlim = iterlim))
  args <- c(fid, iterlim, length(x0), x0, length(data), data)
  vals <- c(r$minimum, r$code, r$iterations, r$estimate)
  cases[[length(cases) + 1]] <<- case("nlm", args, vals[1], rel = 1e-9, abs = 1e-11)
  for (j in 2:length(vals)) {
    exact <- j <= 3
    cases[[length(cases) + 1]] <<- case("o", j - 1, vals[j], rel = if (exact) 0 else if (fid %in% c(3, 13)) 1e-6 else 1e-8, abs = if (exact) 0 else 1e-9)
  }
}

run(1, c(-1.2, 1))
run(1, c(0, 0))
run(1, c(3, -2))
run(1, c(-1.2, 1), iterlim = 3)
run(2, c(0, 0, 0))
run(2, c(0, 0, 0, 0, 0))
run(2, c(100, -100))
run(3, 0, c(yv, vv))
run(3, -3, c(yv, vv))
run(3, 2, c(yv[1:5], vv[1:5]))
run(4, c(0, 0, 0, 0, 0))
run(4, c(1, 1, 1, 1, 1))
run(4, c(0, 0, 7, 0, -3))
run(5, c(0, 0))
run(6, c(5, -3))
run(6, c(0, 0))
run(7, c(3, -1, 0, 1))
run(7, c(1, 1, 1, 1))
run(8, c(1, 1))
run(8, c(0, 0))
run(9, c(0, 0))
run(9, c(-3, 3))
run(10, c(-3, -1, -3, -1))
run(11, c(-1.2, 1, -1.2, 1, -1.2, 1, -1.2, 1, -1.2, 1))
run(12, c(3, 3))
run(12, c(-0.4, 5))
run(13, c(0, 0))
run(13, c(2, 2))
run(14, 0.5)
run(14, -2)
run(15, c(0, 0, 0))
run(15, rep(0, 6))
run(16, 0)
run(16, 3)
run(1, c(-1.2, 1), iterlim = 1)
run(7, c(3, -1, 0, 1), iterlim = 5)
emit("nlm", character(), list(cases))
