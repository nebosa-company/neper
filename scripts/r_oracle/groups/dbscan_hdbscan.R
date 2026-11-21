# dbscan: hdbscan(x, minPts, cluster_selection_epsilon). Args: (n, d, minPts, sel_eps, q, x row-major n*d); q picks one checksum of the result:
# 0 sum(i*cluster) 1 max cluster 2 sum(i*membership_prob) 3 sum(i*outlier_scores) 4 sum(k*cluster_scores[k]) 5 sum(i*coredist) 6 sum(j*hc$height)
# 7 sum(j*merge[j,1]) 8 sum(j*merge[j,2]) 9 tree clusters 10 sum(id*stability) 11 sum((id+1)*eps_birth) 12 sum((id+1)*eps_death) 13 sum((id+1)*n_children)
# 14 sum((id+1)*sum(eps)) 15 sum((id+1)*sum(contains)) 16 sum(id*(7*child1+child2)) 17 sum(k*salient[k]) 18 sum((id+1)*length(contains)) 19 hc$order sum(j*order[j])
suppressMessages(library(dbscan))
cases <- list()
set.seed(20262611)
sig <- function(x, mp, se) {
  h <- hdbscan(x, mp, cluster_selection_epsilon = se)
  res <- attr(h, "hdbscan"); ids <- names(res); ids <- ids[order(as.integer(ids))]
  hier <- attr(res, "cl_hierarchy"); sl <- attr(res, "salient_clusters")
  nn <- nrow(x); idn <- as.integer(ids)
  f <- function(g) vapply(ids, function(i) g(res[[i]]), 0)
  hk <- names(hier)
  v <- c(sum(seq_len(nn) * h$cluster), max(h$cluster), sum(seq_len(nn) * h$membership_prob), sum(seq_len(nn) * h$outlier_scores),
         sum(seq_along(h$cluster_scores) * h$cluster_scores), sum(seq_len(nn) * h$coredist), sum(seq_len(nn - 1) * h$hc$height),
         sum(seq_len(nn - 1) * h$hc$merge[, 1]), sum(seq_len(nn - 1) * h$hc$merge[, 2]), length(res),
         sum(idn * f(function(r) r$stability)), sum((idn + 1) * f(function(r) r$eps_birth)), sum((idn + 1) * f(function(r) r$eps_death)),
         sum((idn + 1) * f(function(r) r$n_children)), sum((idn + 1) * f(function(r) sum(r$eps))), sum((idn + 1) * f(function(r) sum(r$contains))),
         sum(as.integer(hk) * vapply(hk, function(k) 7 * hier[[k]][1] + hier[[k]][2], 0)), sum(seq_along(sl) * sl),
         sum((idn + 1) * f(function(r) length(r$contains))), sum(seq_len(nn) * h$hc$order))
  v
}
reps <- 0
while (reps < 16) {
  n1 <- sample(16:32, 1); d <- sample(2:3, 1)
  x <- rbind(matrix(rnorm(n1 * d, 0, 0.5), ncol = d), matrix(rnorm(n1 * d, 3, 0.5), ncol = d), matrix(rnorm((n1 %/% 2) * d, 1.5, 1.8), ncol = d))
  x <- x[sample(nrow(x)), , drop = FALSE]
  mp <- sample(3:9, 1)
  se <- if (reps %% 4 == 3) runif(1, 0.05, 0.6) else 0
  v <- tryCatch(sig(x, mp, se), error = function(e) NULL)
  if (is.null(v) || any(!is.finite(v))) next
  reps <- reps + 1
  a <- c(nrow(x), d, mp, se)
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("hd", c(a, q - 1, as.vector(t(x))), v[q], rel = 1e-9)
}
emit("dbscan_hdbscan", "dbscan", list(cases))
