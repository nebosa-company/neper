# nlminb: R's stats::nlminb (PORT) against lib/e/algo/stat/nlminb.e, tests/selfhost/fixtures/link/oracle_nlminb.
#   A case is fn "nlminb" with args = [fid (the test function, see below), eval.max, iter.max, abs.tol, rel.tol (NA keeps R's default), gradient (0 finite differences, 1 the analytic gradient),
#   n, start (n), m, data (m)]. Its want is the objective; the cases after it, fn "o", are the values of the result at an index: 1 the PORT code (3 X-convergence, 4 relative, 5 both, 6 absolute,
#   7 singular, 8 false, 9 and 10 the evaluation and iteration limits), 2 iterations, 3 function evaluations, 4 gradient evaluations (the finite differences), 5.. the parameter vector.
#   The counts are compared exactly, the parameters and the objective to 1e-10 (the parameters of fid 3 and 13, which call exp and log, to 1e-7: Neper's exp and log are not R's libm, and a finite-difference gradient amplifies the last bit).
#   Sums are loops because R's sum() accumulates in long double; powers are products because R's ^ is pow.
cases <- list()
objs <- list(); grads <- list()
objs[[1]] <- function(x, d) { a <- x[2] - x[1] * x[1]; b <- 1 - x[1]; 100 * a * a + b * b }
grads[[1]] <- function(x, d) { a <- x[2] - x[1] * x[1]; b <- 1 - x[1]; c(-400 * x[1] * a - 2 * b, 200 * a) }
objs[[2]] <- function(x, d) { s <- 0; for (i in seq_along(x)) { dd <- x[i] - i; s <- s + i * dd * dd }; s }
grads[[2]] <- function(x, d) { g <- numeric(length(x)); for (i in seq_along(x)) g[i] <- 2 * i * (x[i] - i); g }
objs[[3]] <- function(x, d) { s2 <- exp(x[1]); m <- length(d) / 2; s <- 0; for (i in 1:m) { w <- s2 + d[m + i]; s <- s + 0.5 * (log(w) + d[i] * d[i] / w) }; s }
objs[[4]] <- function(x, d) { a <- x[1] - 1; b <- x[2] + 2; c <- x[4] - x[1]; a * a + b * b + c * c }
objs[[5]] <- function(x, d) { if (x[1] > 2.5) return(Inf); a <- x[1] - 3; b <- x[2] + 1; a * a + b * b }
objs[[6]] <- function(x, d) abs(x[1] - 1) + abs(x[2] - 2)
objs[[7]] <- function(x, d) { a <- x[1] + 10 * x[2]; b <- x[3] - x[4]; c <- x[2] - 2 * x[3]; e <- x[1] - x[4]; a * a + 5 * b * b + c * c * c * c + 10 * e * e * e * e }
objs[[8]] <- function(x, d) { a <- 1.5 - x[1] + x[1] * x[2]; b <- 2.25 - x[1] + x[1] * (x[2] * x[2]); c <- 2.625 - x[1] + x[1] * (x[2] * x[2] * x[2]); a * a + b * b + c * c }
objs[[9]] <- function(x, d) { a <- x[1] * x[1] + x[2] - 11; b <- x[1] + x[2] * x[2] - 7; a * a + b * b }
grads[[9]] <- function(x, d) { a <- x[1] * x[1] + x[2] - 11; b <- x[1] + x[2] * x[2] - 7; c(4 * x[1] * a + 2 * b, 2 * a + 4 * x[2] * b) }
objs[[10]] <- function(x, d) { a <- x[2] - x[1] * x[1]; b <- 1 - x[1]; c <- x[4] - x[3] * x[3]; e <- 1 - x[3]; 100 * a * a + b * b + 90 * c * c + e * e + 10.1 * ((x[2] - 1) * (x[2] - 1) + (x[4] - 1) * (x[4] - 1)) + 19.8 * (x[2] - 1) * (x[4] - 1) }
objs[[11]] <- function(x, d) { s <- 0; for (i in 1:(length(x) - 1)) { a <- x[i + 1] - x[i] * x[i]; b <- 1 - x[i]; s <- s + 100 * a * a + b * b }; s }
objs[[12]] <- function(x, d) { if (x[1] < -0.5) return(NaN); a <- x[1] - 1; b <- x[2] - 1; a * a + b * b }
objs[[13]] <- function(x, d) exp(x[1]) - 2 * x[1] + x[2] * x[2]
objs[[14]] <- function(x, d) { a <- x[1]; a * a * a * a - 3 * a * a + a }
objs[[15]] <- function(x, d) { s <- 0; for (i in seq_along(x)) { s <- s + (x[i] - 0.5 * i) * (x[i] - 0.5 * i) }; a <- 0; for (i in seq_along(x)) a <- a + x[i]; s + 0.01 * a * a }
objs[[16]] <- function(x, d) { a <- x[1]; 1 + (a - 1) * (a - 1) * (a - 1) * (a - 1) }

# data for fid 3: m/2 values of y then m/2 of v
yv <- c(0.31, -0.42, 0.15, 0.9, -0.63, 0.22, 0.05, -0.18, 0.47, -0.39)
vv <- c(0.05, 0.11, 0.08, 0.2, 0.06, 0.15, 0.09, 0.04, 0.12, 0.07)

run <- function(fid, x0, data = numeric(), ctl = list(), grad = FALSE) {
  cl <- list(); ev <- NA; it <- NA; at <- NA; rt <- NA
  if (!is.null(ctl$eval.max)) ev <- ctl$eval.max
  if (!is.null(ctl$iter.max)) it <- ctl$iter.max
  if (!is.null(ctl$abs.tol)) at <- ctl$abs.tol
  if (!is.null(ctl$rel.tol)) rt <- ctl$rel.tol
  f <- function(x) objs[[fid]](x, data)
  g <- if (grad) function(x) grads[[fid]](x, data) else NULL
  r <- suppressWarnings(nlminb(x0, f, g, control = ctl))
  code <- as.numeric(sub(".*\\((\\d+)\\)$", "\\1", r$message))
  args <- c(fid, ev, it, at, rt, as.integer(grad), length(x0), x0, length(data), data)
  vals <- c(r$objective, code, r$iterations, r$evaluations[["function"]], r$evaluations[["gradient"]], r$par)
  cases[[length(cases) + 1]] <<- case("nlminb", args, vals[1], rel = 1e-10, abs = 1e-12)
  for (j in 2:length(vals)) {
    exact <- j <= 5
    cases[[length(cases) + 1]] <<- case("o", j - 1, vals[j], rel = if (exact) 0 else if (fid %in% c(3, 13)) 1e-7 else 1e-10, abs = if (exact) 0 else 1e-12)
  }
}

run(1, c(-1.2, 1))
run(1, c(-1.2, 1), grad = TRUE)
run(1, c(0, 0))
run(1, c(3, -2))
run(1, c(-1.2, 1), ctl = list(iter.max = 3))
run(1, c(-1.2, 1), ctl = list(eval.max = 10))
run(1, c(-1.2, 1), ctl = list(rel.tol = 1e-6))
run(1, c(-1.2, 1), ctl = list(abs.tol = 1e-3))
run(1, c(10, 10), grad = TRUE)
run(2, c(0, 0, 0))
run(2, c(5, -3, 8, 1), grad = TRUE)
run(2, c(0, 0, 0, 0, 0))
run(2, c(100, -100))
run(2, c(1, 2, 3), ctl = list(abs.tol = 1e-3))
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
run(9, c(0, 0), grad = TRUE)
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
emit("nlminb", character(), list(cases))
