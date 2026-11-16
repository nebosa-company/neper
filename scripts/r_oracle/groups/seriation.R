# seriation: criteria of a permutation.
#   "dc" args (n, D[n*n] row-major, order[n] 1-based, code, param): code 1 Path_length 2 Lazy_path_length 3 Least_squares 4 Inertia 5 AR_events
#        6 AR_deviations 7 Gradient_raw 8 Gradient_weighted 9 BAR (b = param) 10 RGAR relative (w = param) 11 RGAR count (w = param)
#   "mc" args (nr, nc, X[nr*nc] row-major, row order[nr], col order[nc], code) code 0 ME 1 Moore_stress 2 Neumann_stress
suppressMessages(library(seriation))
cases <- list()
set.seed(20261116)
rowm <- function(M) as.vector(t(M))
for (rep in 1:60) {
  n <- sample(5:12, 1); x <- matrix(round(runif(n * 3), 3), n, 3); d <- dist(x)
  if (rep %% 4 == 0) d <- dist(round(x * 3))  # ties
  o <- sample(n); ord <- ser_permutation_vector(o)
  Dm <- as.matrix(d)
  vals <- list(
    criterion(d, ord, "Path_length"), criterion(d, ord, "Lazy_path_length"), criterion(d, ord, "Least_squares"), criterion(d, ord, "Inertia"),
    criterion(d, ord, "AR_events"), criterion(d, ord, "AR_deviations"), criterion(d, ord, "Gradient_raw"), criterion(d, ord, "Gradient_weighted"))
  for (code in 1:8) cases[[length(cases) + 1]] <- case("dc", c(n, rowm(Dm), o, code, 0), as.numeric(vals[[code]]), rel = 1e-9, abs = 1e-10)
  b <- sample(1:(n - 1), 1); cases[[length(cases) + 1]] <- case("dc", c(n, rowm(Dm), o, 9, b), as.numeric(criterion(d, ord, "BAR", b = b)), rel = 1e-9, abs = 1e-10)
  w <- sample(2:(n - 1), 1)
  cases[[length(cases) + 1]] <- case("dc", c(n, rowm(Dm), o, 10, w), as.numeric(criterion(d, ord, "RGAR", w = w)), rel = 1e-9, abs = 1e-10)
  cases[[length(cases) + 1]] <- case("dc", c(n, rowm(Dm), o, 11, w), as.numeric(criterion(d, ord, "RGAR", w = w, relative = FALSE)), rel = 1e-9, abs = 1e-10)
}
for (rep in 1:40) {
  nr <- sample(4:9, 1); nc <- sample(4:9, 1); X <- matrix(round(runif(nr * nc), 3), nr, nc)
  ro <- sample(nr); co <- sample(nc); ord <- ser_permutation(ser_permutation_vector(ro), ser_permutation_vector(co))
  for (code in 0:2) {
    v <- criterion(X, ord, c("ME", "Moore_stress", "Neumann_stress")[code + 1])
    cases[[length(cases) + 1]] <- case("mc", c(nr, nc, rowm(X), ro, co, code), as.numeric(v), rel = 1e-9, abs = 1e-10)
  }
}
emit("seriation", "seriation", list(cases))
