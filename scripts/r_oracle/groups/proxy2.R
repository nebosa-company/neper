# proxy: Gower and Levenshtein.
#   gower: (n, p, x[n*p] row-major with NaN for missing, i, j) -> fn "gower" the (i, j) distance
#   lev: (la, lb, a codes..., b codes...) -> fn "lev"
suppressMessages(library(proxy))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-10, abs = 1e-12)
set.seed(20261116)
for (rep in 1:15) {
  n <- sample(4:12, 1); p <- sample(2:6, 1); x <- matrix(round(rnorm(n * p), 2), n, p)
  if (rep %% 2 == 0) x[sample(n * p, 4)] <- NA
  if (any(rowSums(!is.na(x)) < 1)) next
  d <- as.matrix(dist(x, "Gower"))
  xs <- as.vector(t(x)); xs[is.na(xs)] <- NaN
  for (i in 1:n) for (j in 1:n) if (i != j && is.finite(d[i, j])) add("gower", c(n, p, xs, i - 1, j - 1), d[i, j])
}
al <- c("a", "b", "c")
for (rep in 1:200) {
  a <- paste(sample(al, sample(0:9, 1), TRUE), collapse = ""); b <- paste(sample(al, sample(0:9, 1), TRUE), collapse = "")
  d <- as.matrix(proxy::dist(c(a, b), "Levenshtein"))[1, 2]
  add("lev", c(nchar(a), nchar(b), utf8ToInt(a), utf8ToInt(b)), d)
}
emit("proxy2", c("proxy", "cba"), list(cases))
