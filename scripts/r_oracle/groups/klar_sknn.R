# klaR::sknn (simple k-nearest-neighbour classifier) fit and predict.
#   args: (n, p, k, kn, gamma, m, x row-major n by p, labels[n] (1..k), test row-major m by p)
#   fn "post" (posterior, row by row then class) and "cls" (predicted class), each weighted by position
suppressMessages(library(klaR))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
wsum <- function(v) { s <- 0; for (i in seq_along(v)) s <- s + v[i] * i; s }
set.seed(20261231)
for (rep in 1:30) {
  n <- sample(30:60, 1); p <- sample(2:5, 1); k <- sample(2:4, 1); kn <- sample(1:7, 1); m <- 12
  gam <- c(0, 0.5)[(rep %% 2) + 1]
  g <- factor(sample(1:k, n, replace = TRUE))
  X <- matrix(rnorm(n * p), n, p) + as.integer(as.integer(g)) * 0.6
  Tt <- matrix(rnorm(m * p), m, p) + sample(1:k, m * p, replace = TRUE) * 0.6
  fit <- sknn(X, g, kn = kn, gamma = gam)
  # max.col breaks a tie at random, so keep only draws where every row has exactly one largest posterior
  pr <- predict(fit, Tt)
  tied <- rowSums(t(apply(pr$posterior, 1, function(r) r == max(r)))) > 1
  if (any(tied)) next
  a <- c(n, p, k, kn, gam, m, as.vector(t(X)), as.integer(g), as.vector(t(Tt)))
  add("post", a, wsum(as.vector(t(pr$posterior))))
  add("cls", a, wsum(as.numeric(pr$class)))
}
emit("klar_sknn", "klaR", list(cases))
