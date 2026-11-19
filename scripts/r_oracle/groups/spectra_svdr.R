# irlba::svdr under set.seed: the singular values (the matrix after the iterations, tol 1e-5 so the values equal R's iterate, not the exact singular values). Args: (m, n, k, extra, seed, j, x[m * n] row-major): the j-th singular value.
suppressMessages(library(irlba))
cases <- list()
set.seed(20262351)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("sr", args, want, rel = 1e-8, abs = 1e-10)
for (rep in 1:20) {
  m <- sample(20:40, 1); n <- sample(10:18, 1); k <- sample(2:4, 1); ex <- sample(3:8, 1); sd <- sample(1:100000, 1); X <- matrix(round(rnorm(m * n), 4), m)
  set.seed(sd); r <- svdr(X, k, extra = ex)
  for (j in 1:k) add(c(m, n, k, ex, sd, j - 1, as.vector(t(X))), r$d[j])
}
emit("spectra_svdr", "irlba", list(cases))
