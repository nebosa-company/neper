# R's streams. A case is the i-th value of a family drawn after set.seed(seed); the fixture
# re-seeds and advances i draws. Arguments are (seed, i, parameters...); sample() is
# (seed, i, n, size, replace) and answers the i-th element.
seeds <- c(1, 42, 12345, 20261115, -7, 2147483647, 0)

stream <- function(fn, draw, params = numeric(), count = 40, tol = 0) {
  unlist(lapply(seeds, function(s) {
    set.seed(s)
    x <- draw(count)
    lapply(seq_len(count), function(i) case(fn, c(s, i, params), x[i], rel = tol, abs = 0))
  }), recursive = FALSE)
}

sampled <- function(n, size, replace) {
  unlist(lapply(seeds, function(s) {
    set.seed(s)
    x <- sample(n, size, replace)
    lapply(seq_len(size), function(i) case("sample", c(s, i, n, size, replace), x[i], rel = 0, abs = 0))
  }), recursive = FALSE)
}

emit("rng", character(), list(
  stream("runif", function(k) runif(k, -2, 3), c(-2, 3)),
  stream("rnorm", function(k) rnorm(k, 1.5, 2.5), c(1.5, 2.5), tol = 1e-14),
  stream("rexp", function(k) rexp(k, 1 / 3), 3),
  stream("rnorm", function(k) rnorm(k), c(0, 1), 400, tol = 1e-14),
  sampled(10, 10, FALSE),
  sampled(100, 30, FALSE),
  sampled(7, 40, TRUE),
  sampled(1000000, 20, TRUE),
  sampled(2^20, 20, FALSE),
  sampled(5, 1, FALSE),
  sampled(2^33, 10, TRUE),
  sampled(2^40, 6, TRUE),
  sampled(2e7, 20, FALSE),
  sampled(2^34, 10, FALSE)
))
