# dbscan: extractDBSCAN(optics(x, eps, minPts), eps_cl). Args: (n, eps_cl, order[n] 1-based, reachdist[n], coredist[n] (Inf as 1e300)); the answer is sum(position * cluster id) (noise 0) and, second case, the number of clusters
suppressMessages(library(dbscan))
cases <- list()
set.seed(20262498)
fin <- function(v) { v[!is.finite(v)] <- 1e300; v }
for (rep in 1:40) {
  n <- sample(40:150, 1); x <- rbind(matrix(rnorm(n, 0, 0.4), ncol = 2), matrix(rnorm(n, 3, 0.4), ncol = 2), matrix(rnorm(n %/% 2, 1.5, 1.5), ncol = 2)); x <- x[sample(nrow(x)), , drop = FALSE]
  eps <- 1.5; mp <- sample(3:6, 1); ecl <- runif(1, 0.2, 1.2)
  o <- optics(x, eps = eps, minPts = mp); e <- extractDBSCAN(o, ecl)
  nn <- nrow(x); a <- c(nn, ecl, o$order, fin(o$reachdist), fin(o$coredist))
  cases[[length(cases) + 1]] <- case("ex", c(a, 0), sum(seq_len(nn) * e$cluster), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("ex", c(a, 1), max(e$cluster), rel = 0, abs = 0)
}
emit("dbscan_ext", "dbscan", list(cases))
