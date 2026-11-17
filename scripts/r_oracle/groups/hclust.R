# hclust: merge matrix, order, heights, cutree and cophenetic distances for every linkage.
#   args: (method, n, k, x row-major n by 2...)   method 1 ward.D 2 single 3 complete 4 average 5 mcquitty 6 median 7 centroid 8 ward.D2
#   fn "height" "merge" "order" (each the sum of value * (position + 1)), "cut" (cutree(k) weighted by observation), "coph" (the sum of the cophenetic distances weighted by pair)
#   median and centroid are given the squared distances, as the documentation asks
suppressMessages(library(stats)); suppressMessages(library(dendextend)); suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-9)
meth <- c("ward.D", "single", "complete", "average", "mcquitty", "median", "centroid", "ward.D2")
set.seed(20261214)
for (rep in 1:8) for (mi in 1:8) {
  n <- sample(8:25, 1); X <- matrix(round(rnorm(n * 2) * 3, 3), n, 2); k <- sample(2:5, 1)
  d <- dist(X); if (mi %in% c(6, 7)) d <- d^2
  h <- hclust(d, method = meth[mi])
  a <- c(mi, n, k, as.vector(t(X)))
  add("height", a, sum(h$height * seq_along(h$height)))
  add("merge", a, sum(as.vector(t(h$merge)) * seq_len(length(h$merge))))
  add("order", a, sum(h$order * seq_along(h$order)))
  add("cut", a, sum(cutree(h, k = k) * seq_len(n)))
  if (!is.unsorted(h$height)) { hh <- sort(h$height); hq <- (hh[-1] + hh[-length(hh)]) / 2; hc0 <- sample(hq, 1); add("cuth", c(a, hc0), sum(cutree(h, h = hc0) * seq_len(n))) }
  cp <- as.vector(cophenetic(h))
  add("coph", a, sum(cp * seq_along(cp)))
}
for (rep in 1:10) {
  n <- sample(10:25, 1); X <- matrix(round(rnorm(n * 2) * 3, 3), n, 2); k <- sample(2:5, 1)
  m1 <- sample(c(2, 3, 4, 8), 1); m2 <- sample(c(2, 3, 4, 8), 1); d <- dist(X)
  h1 <- hclust(d, method = meth[m1]); h2 <- hclust(d, method = meth[m2])
  a <- c(m1, m2, n, k, as.vector(t(X)))
  fm <- dendextend::FM_index_R(cutree(h1, k), cutree(h2, k))
  add("fm", a, as.numeric(fm)); add("fmE", a, attr(fm, "E_FM")); add("fmV", a, attr(fm, "V_FM"))
  add("corcoph", a, dendextend::cor_cophenetic(h1, h2))
  Xl <- X; rownames(Xl) <- paste0("o", seq_len(n)); dl <- dist(Xl); g1 <- hclust(dl, method = meth[m1]); g2 <- hclust(dl, method = meth[m2])
  bg <- tryCatch(dendextend::cor_bakers_gamma(g1, g2, warn = FALSE), error = function(e) NA); add("bakers", c(a, 1), as.numeric(bg))
  Lx <- c(1, 1.5, 2, 0.5)[sample(4, 1)]; add("entang", c(a, Lx), dendextend::entanglement(h1, h2, L = Lx))
}
for (rep in 1:10) {
  n <- sample(8:25, 1); X <- matrix(round(rnorm(n * 2) * 3, 3), n, 2); mi <- sample(c(2, 3, 4, 5, 8), 1)
  nm <- c("single", "complete", "average", "weighted", "ward")[match(mi, c(2, 3, 4, 5, 8))]
  ag <- agnes(dist(X), method = nm)
  add("ac", c(mi, n, 2, as.vector(t(X))), ag$ac)
  add("agh", c(mi, n, 2, as.vector(t(X))), sum(sort(ag$height) * seq_along(ag$height)))
}
emit("hclust", "stats", list(cases))
