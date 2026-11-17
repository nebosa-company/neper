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
  dr <- order.dendrogram(ladderize(as.dendrogram(h), right = TRUE)); dl <- order.dendrogram(ladderize(as.dendrogram(h), right = FALSE))
  add("ladr", a, sum(dr * seq_along(dr))); add("ladl", a, sum(dl * seq_along(dl)))
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
#   d_* cases: dendrogram objects and dendextend untangling. args: (m1, m2, n, p1, p2, p3, p4, p5, X1 (n by 2), X2 (n by 2), perm1 (n), perm2 (n))
#   d1 = as.dendrogram(hclust(dist(X1), m1)), d2 likewise from X2, m2; p3 = 1 when the observations carry names (character labels), 0 for numeric labels;
#   perm1 and perm2 scramble the leaf values (order.dendrogram<-) or are the permutations given to rotate. Answers are sums of value * position.
dendextend::dendextend_options("warn", FALSE)
dw <- function(x) sum(x * seq_along(x))
dpre <- function(d) if (is.leaf(d)) list(d) else c(list(d), dpre(d[[1]]), dpre(d[[2]]))
mkdend <- function(X, mi, lab) {
  if (lab) rownames(X) <- paste0("o", seq_len(nrow(X)))
  d <- dist(X); if (mi %in% c(6, 7)) d <- d^2
  as.dendrogram(hclust(d, method = meth[mi]))
}
scr <- function(d, perm) { order.dendrogram(d) <- perm; d }
dnodes <- function(d) {
  pre <- dpre(d); int <- Filter(function(x) !is.leaf(x), pre)
  list(h = dw(sapply(int, attr, "height")), k = dw(sapply(pre, function(x) if (is.leaf(x)) as.numeric(x) else -attr(x, "members"))),
       mid = dw(sapply(int, attr, "midpoint")))
}
hpk_fn <- dendextend:::heights_per_k.dendrogram
set.seed(20270111)
dblock <- function(n, m1, m2, X1, X2, lab) {
  perm1 <- sample(n); perm2 <- sample(n)
  d1 <- mkdend(X1, m1, lab); d2 <- mkdend(X2, m2, lab)
  hd <- function(p1 = 0, p2 = 0, p4 = 0, p5 = 0) c(m1, m2, n, p1, p2, lab, p4, p5, as.vector(t(X1)), as.vector(t(X2)), perm1, perm2)
  addd <- function(fn, a, want) add(fn, a, want)
  addd("d_ord", hd(), dw(order.dendrogram(d1)))
  nd <- dnodes(d1); addd("d_h", hd(), nd$h); addd("d_k", hd(), nd$k); addd("d_mid", hd(), nd$mid)
  dr <- rotate(d1, perm1); addd("d_rot", hd(), dw(order.dendrogram(dr)))
  nr <- dnodes(dr); addd("d_rotk", hd(), nr$k); addd("d_rotmid", hd(), nr$mid)
  hh <- hpk_fn(d1); addd("d_hpk", hd(), dw(hh)); addd("d_hpkn", hd(), dw(as.numeric(names(hh))))
  for (j in 1:2) {
    k <- sample(2:n, 1); lst <- suppressWarnings(all_couple_rotations_at_k(dr, k, hpk_fn(dr)))
    if (!is.list(lst)) lst <- list(lst)
    addd("d_all", hd(k), sum(vapply(seq_along(lst), function(i) i * dw(order.dendrogram(lst[[i]])), 0))); addd("d_alln", hd(k), length(lst))
  }
  addd("d_mbl", hd(), dw(order.dendrogram(dendextend:::match_order_by_labels(d2, scr(d1, perm1)))))
  for (j in 1:2) {
    L <- c(1, 1.5, 2, 0.5)[sample(4, 1)]; mo <- sample(0:1, 1)
    addd("d_ent", hd(L, mo), dendextend::entanglement(scr(d1, perm1), scr(d2, perm2), L = L, leaves_matching_method = c("labels", "order")[mo + 1]))
  }
  addd("d_ulab", hd(), dw(order.dendrogram(untangle(d1, d2, method = "labels")[[2]])))
  for (j in 1:2) {
    L <- c(1, 1.5, 2)[sample(3, 1)]; dir <- sample(0:1, 1); mo <- sample(0:1, 1)
    d2s <- if (mo == 1) scr(d2, perm2) else d2
    r <- untangle(d1, d2s, method = "step1side", L = L, direction = c("forward", "backward")[dir + 1], leaves_matching_method = c("labels", "order")[mo + 1])
    a <- hd(L, dir, mo)
    addd("d_u1a", a, dw(order.dendrogram(r[[1]]))); addd("d_u1b", a, dw(order.dendrogram(r[[2]])))
    addd("d_u1e", a, dendextend::entanglement(r[[1]], r[[2]], L = L, leaves_matching_method = c("labels", "order")[mo + 1]))
  }
  for (j in 1:2) {
    L <- c(1, 1.5, 2)[sample(3, 1)]; dir <- sample(0:1, 1); mi <- sample(2:10, 1)
    r <- untangle(d1, d2, method = "step2side", L = L, direction = c("forward", "backward")[dir + 1], max_n_iterations = mi)
    a <- hd(L, dir, mi)
    addd("d_u2a", a, dw(order.dendrogram(r[[1]]))); addd("d_u2b", a, dw(order.dendrogram(r[[2]])))
    addd("d_u2e", a, dendextend::entanglement(r[[1]], r[[2]], L = L))
  }
  for (j in 1:2) {
    L <- c(1, 1.5, 2)[sample(3, 1)]; mo <- sample(0:1, 1); R <- sample(5:40, 1); seed <- sample(1:100000, 1)
    d2s <- if (mo == 1) scr(d2, perm2) else d2
    set.seed(seed)
    r <- untangle(d1, d2s, method = "random", R = R, L = L, leaves_matching_method = c("labels", "order")[mo + 1])
    a <- hd(L, mo, R, seed)
    addd("d_ura", a, dw(order.dendrogram(r[[1]]))); addd("d_urb", a, dw(order.dendrogram(r[[2]])))
    addd("d_ure", a, dendextend::entanglement(r[[1]], r[[2]], L = L, leaves_matching_method = c("labels", "order")[mo + 1]))
  }
}
# smooth data of every linkage, then the linkages with inversions (median, centroid) and data on a coarse grid, whose merges tie in height
for (rep in 1:16) {
  n <- sample(8:16, 1); m1 <- sample(1:8, 1); m2 <- sample(1:8, 1)
  dblock(n, m1, m2, matrix(round(rnorm(n * 2) * 3, 3), n, 2), matrix(round(rnorm(n * 2) * 3, 3), n, 2), sample(0:1, 1))
}
for (rep in 1:14) {
  n <- sample(7:14, 1); m1 <- sample(6:7, 1); m2 <- sample(6:7, 1)
  dblock(n, m1, m2, matrix(round(rnorm(n * 2) * 3, 3), n, 2), matrix(round(rnorm(n * 2) * 3, 3), n, 2), sample(0:1, 1))
}
for (rep in 1:14) {
  n <- sample(7:14, 1); m1 <- sample(1:8, 1); m2 <- sample(1:8, 1)
  dblock(n, m1, m2, matrix(round(rnorm(n * 2) * 1.5), n, 2), matrix(round(rnorm(n * 2) * 1.5), n, 2), sample(0:1, 1))
}
emit("hclust", "stats", list(cases))
