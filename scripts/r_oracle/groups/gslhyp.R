# gsl: the hypergeometric functions with the error estimate.
#   "h" (code, part, p1, p2, p3, p4): part 0 value, 1 error.
#   code 0 hyperg_0F1(c = p1, x = p2); 1 hyperg_1F1(a, b, x); 2 hyperg_1F1_int(m, n, x); 3 hyperg_U(a, b, x);
#   4 hyperg_U_int(m, n, x); 5 hyperg_2F0(a, b, x); 6 hyperg_2F1(a, b, c, x); 7 hyperg_2F1_conj(aR, aI, c, x);
#   8 hyperg_2F1_renorm(a, b, c, x); 9 hyperg_2F1_conj_renorm(aR, aI, c, x).
suppressMessages(library(gsl))
cases <- list()
set.seed(20263120)
g <- function(f, ...) tryCatch(f(..., give = TRUE, strict = FALSE), error = function(e) NULL)
loose <- list()
# ill-conditioned: R's own err exceeds 1e-7*|val|; the port's cancellation differs from R's libm rounding there (about 1e-5 relative), so these go to the loose set at the end
add <- function(code, p, r, vrel = 1e-9, erel = 1e-8) {
  if (is.null(r) || r$status != 0 || !is.finite(r$val) || r$val == 0 || !is.finite(r$err)) return()
  if (r$err > 1e-7 * abs(r$val)) { loose[[length(loose) + 1]] <<- list(code, p, r); return() }
  cases[[length(cases) + 1]] <<- case("h", c(code, 0, p), r$val, rel = vrel, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("h", c(code, 1, p), r$err, rel = erel, abs = 1e-300)
}
pick <- function(...) { l <- list(...); l[[sample(length(l), 1)]] }
for (i in 1:200) {
  cc <- c(runif(1, 0.05, 1), runif(1, 1, 6), runif(1, 6, 60), -runif(1, 0.05, 0.95), -(runif(1, 1.05, 1.95) + sample(0:4, 1)))[sample(1:5, 1)]
  x <- c(runif(1, 1e-3, 1), runif(1, 1, 30), runif(1, 30, 400), -runif(1, 1e-3, 1), -runif(1, 1, 30), -runif(1, 30, 400))[sample(1:6, 1)]
  add(0, c(cc, x), g(hyperg_0F1, cc, x))
}
xs <- function() c(runif(1, 1e-3, 1), runif(1, 1, 8), runif(1, 8, 60), runif(1, 60, 400), -runif(1, 1e-3, 1), -runif(1, 1, 8), -runif(1, 8, 60), -runif(1, 60, 400))[sample(1:8, 1)]
for (i in 1:600) {
  a <- c(runif(1, 0.05, 1), runif(1, 1, 6), runif(1, 6, 40), -runif(1, 0.05, 6), -runif(1, 6, 40))[sample(1:5, 1)]
  b <- c(runif(1, 0.05, 1), runif(1, 1, 6), runif(1, 6, 40), runif(1, 40, 800), -(runif(1, 0.05, 6) + 0.5))[sample(1:5, 1)]
  x <- xs()
  add(1, c(a, b, x), g(hyperg_1F1, a, b, x))
}
for (i in 1:250) {
  m <- sample(c(-12:12), 1); n <- sample(c(-12:20), 1); x <- xs()
  add(2, c(m, n, x), g(hyperg_1F1_int, m, n, x))
}
for (i in 1:600) {
  a <- c(runif(1, 0.05, 1), runif(1, 1, 6), runif(1, 6, 40), -runif(1, 0.05, 6), -runif(1, 6, 40))[sample(1:5, 1)]
  b <- c(runif(1, 0.05, 1), runif(1, 1, 6), runif(1, 6, 40), runif(1, 40, 800), -runif(1, 0.05, 6))[sample(1:5, 1)]
  x <- c(runif(1, 1e-2, 1), runif(1, 1, 8), runif(1, 8, 60), runif(1, 60, 400))[sample(1:4, 1)]
  add(3, c(a, b, x), g(hyperg_U, a, b, x))
}
for (i in 1:300) {
  a <- runif(1, -8, 8); b <- runif(1, -3, 9); x <- runif(1, 0.02, 1.9)
  add(3, c(a, b, x), g(hyperg_U, a, b, x))
}
for (i in 1:250) {
  m <- sample(c(-12:12), 1); n <- sample(c(-12:20), 1)
  x <- c(runif(1, 1e-2, 1), runif(1, 1, 8), runif(1, 8, 60), runif(1, 60, 400))[sample(1:4, 1)]
  add(4, c(m, n, x), g(hyperg_U_int, m, n, x))
}
for (i in 1:200) {
  a <- c(runif(1, 0.05, 1), runif(1, 1, 6), runif(1, 6, 20))[sample(1:3, 1)]
  b <- c(runif(1, 0.05, 1), runif(1, 1, 6), runif(1, 6, 20), -runif(1, 0.05, 3))[sample(1:4, 1)]
  x <- -c(runif(1, 1e-2, 1), runif(1, 1, 8), runif(1, 8, 60))[sample(1:3, 1)]
  add(5, c(a, b, x), g(hyperg_2F0, a, b, x))
}
x2 <- function() c(runif(1, 0, 0.5), runif(1, 0.5, 0.99), -runif(1, 0, 0.25), -runif(1, 0.25, 0.99), 1 - 1e-7 * runif(1))[sample(1:5, 1)]
ab <- function() c(runif(1, 0.05, 4), runif(1, 4, 12), -runif(1, 0.05, 4), -runif(1, 4, 14), -sample(0:6, 1), sample(1:6, 1))[sample(1:6, 1)]
cc2 <- function() c(runif(1, 0.05, 4), runif(1, 4, 20), runif(1, 20, 60), -runif(1, 0.05, 4) - 0.5, -sample(1:8, 1))[sample(1:5, 1)]
for (i in 1:500) { a <- ab(); b <- ab(); cv <- cc2(); x <- x2(); add(6, c(a, b, cv, x), g(hyperg_2F1, a, b, cv, x)) }
for (i in 1:250) { a <- ab(); b <- ab(); cv <- cc2(); x <- x2(); add(8, c(a, b, cv, x), g(hyperg_2F1_renorm, a, b, cv, x)) }
for (i in 1:300) { a <- ab(); b <- runif(1, 0, 8); cv <- cc2(); x <- x2(); add(7, c(a, b, cv, x), g(hyperg_2F1_conj, a, b, cv, x)) }
for (i in 1:200) { a <- ab(); b <- runif(1, 0, 8); cv <- cc2(); x <- x2(); add(9, c(a, b, cv, x), g(hyperg_2F1_conj_renorm, a, b, cv, x)) }
# c - a - b an integer (reflect degenerate branch), both signs and zero
xd <- function() c(runif(1, 0.5, 0.99), runif(1, 0.9, 0.999), runif(1, 0.1, 0.5))[sample(1:3, 1)]
for (i in 1:400) {
  a <- c(runif(1, 0.1, 4), runif(1, 4, 9), -runif(1, 0.1, 4) - 0.05)[sample(1:3, 1)]
  b <- c(runif(1, 0.1, 4), runif(1, 4, 9), -runif(1, 0.1, 4) - 0.05)[sample(1:3, 1)]
  cv <- a + b + sample(-3:4, 1); x <- xd()
  add(6, c(a, b, cv, x), g(hyperg_2F1, a, b, cv, x))
  add(8, c(a, b, cv, x), g(hyperg_2F1_renorm, a, b, cv, x))
}
# loose set: value within max(1e-4, 100*err/|val|) relative; error estimate within a factor of two (rel 1)
for (k in seq_along(loose)) {
  if (k > 400) break
  l <- loose[[k]]; r <- l[[3]]
  cases[[length(cases) + 1]] <- case("h", c(l[[1]], 0, l[[2]]), r$val, rel = min(1, max(1e-4, 100 * r$err / abs(r$val))), abs = 1e-300)
  cases[[length(cases) + 1]] <- case("h", c(l[[1]], 1, l[[2]]), r$err, rel = 1, abs = 1e-300)
}
emit("gslhyp", "gsl", list(cases))
