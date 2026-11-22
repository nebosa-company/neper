# geometry (n-dimensional Qhull functions) on seeded normal points, 2 to 6 dimensions.
#   convhull   (n, d, p[n*d] row-major)                     facets boundary enclosed  = convhulln(p, "FA")
#   delaunay   (n, d, p)                                    dcount dvol dhash dvorsum dvorsq  = delaunayn(p): simplices, volume, hash of the 1-based sorted vertex tuples (sum_k v_k 41^k), circumcentre coordinate sum and sum of squares (the Voronoi vertices)
#   tsearchn   (n, d, p, nt, t[nt*(d+1)], nq, q[nq*d])      tsidx = sum_i i*idx_i (0 for NA), tsbary = sum_i i sum_k k b_ik; d = 2 goes through tsearch
#   cart2bary  (d, X[(d+1)*d], nq, P[nq*d])                 cbsum = sum_i i sum_k k beta_ik
#   inhulln    (n, d, p, nq, q)                             insum = sum_i i * inhulln_i
#   intersectn (n1, n2, d, p1, p2, fp)                      ivert ivol iarea  (fp = feasible.point of the two hulls, an input)
#   surftri    (n, p[n*3], nt, t[nt*4])                     sfcount sfhash = sum of a + 100 b + 10000 c over the rows of surf.tri
#   dot        (m, n, dsel, x[m*n], y[m*n])                 dotsum = sum_k k * dot(x, y, dsel)_k
suppressMessages(library(geometry))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
rowm <- function(m) as.vector(t(m))
set.seed(20270107)
sizes <- list(c(2, 6, 30), c(3, 6, 26), c(4, 9, 18), c(5, 10, 14), c(6, 12, 14))
pts <- function(n, d) matrix(rnorm(n * d), n)

# convhulln, three measures; 30 sets in the plane and in space as before, then 4 to 6 dimensions
for (rep in 1:20) {
  d <- 2 + rep %% 2; n <- sample(6:40, 1); p <- pts(n, d)
  h <- convhulln(p, "FA"); a <- c(n, d, rowm(p))
  add("facets", a, nrow(h$hull)); add("boundary", a, h$area); add("enclosed", a, h$vol)
}
for (rep in 1:9) {
  s <- sizes[[3 + rep %% 3]]; d <- s[1]; n <- sample(s[2]:s[3], 1); p <- pts(n, d)
  h <- convhulln(p, "FA"); a <- c(n, d, rowm(p))
  add("facets", a, nrow(h$hull)); add("boundary", a, h$area); add("enclosed", a, h$vol)
}

simplex_stats <- function(p, t) {
  d <- ncol(p); hash <- 0; cs <- 0; cq <- 0
  for (i in seq_len(nrow(t))) {
    v <- sort(t[i, ]); hash <- hash + sum(v * 41^(0:d))
    X <- p[v, , drop = FALSE]
    A <- 2 * (X[-1, , drop = FALSE] - matrix(X[1, ], d, d, byrow = TRUE))
    b <- rowSums(X[-1, , drop = FALSE]^2) - sum(X[1, ]^2)
    x <- solve(A, b); cs <- cs + sum(x); cq <- cq + sum(x^2)
  }
  c(hash, cs, cq)
}

# delaunayn, tsearchn, surf.tri
for (rep in 1:10) {
  s <- sizes[[1 + (rep - 1) %% 5]]; d <- s[1]; n <- sample(s[2]:s[3], 1); p <- pts(n, d)
  t <- if (d < 4) delaunayn(p) else delaunayn(p, options = "Qt Qc Qx"); a <- c(n, d, rowm(p)); st <- simplex_stats(p, t)
  vol <- 0
  for (i in seq_len(nrow(t))) vol <- vol + abs(det(p[t[i, -1], , drop = FALSE] - matrix(p[t[i, 1], ], d, d, byrow = TRUE))) / factorial(d)
  add("dcount", a, nrow(t)); add("dvol", a, vol); add("dhash", a, st[1], rel = 0, abs = 0)
  add("dvorsum", a, st[2]); add("dvorsq", a, st[3])
  nq <- 8; q <- pts(nq, d) * 0.5
  ts <- tsearchn(p, t, q)
  idx <- ifelse(is.na(ts$idx), 0, ts$idx)
  bsum <- 0
  for (i in 1:nq) if (!is.na(ts$idx[i])) bsum <- bsum + i * sum((1:(d + 1)) * ts$p[i, ])
  ta <- c(n, d, rowm(p), nrow(t), rowm(t), nq, rowm(q))
  add("tsidx", ta, sum((1:nq) * idx), rel = 0, abs = 0); add("tsbary", ta, bsum)
  if (d == 2) {
    ts2 <- tsearch(p[, 1], p[, 2], t, q[, 1], q[, 2])
    add("tsidx", ta, sum((1:nq) * ifelse(is.na(ts2), 0, ts2)), rel = 0, abs = 0)
  }
  if (d == 3) {
    sf <- surf.tri(p, t)
    add("sfcount", c(n, rowm(p), nrow(t), rowm(t)), nrow(sf), rel = 0, abs = 0)
    add("sfhash", c(n, rowm(p), nrow(t), rowm(t)), sum(sf[, 1] + 100 * sf[, 2] + 10000 * sf[, 3]), rel = 0, abs = 0)
  }
  # inhulln against the hull of the same points
  hl <- convhulln(p)
  q2 <- pts(nq, d) * 0.7
  add("insum", c(n, d, rowm(p), nq, rowm(q2)), sum((1:nq) * as.numeric(inhulln(hl, q2))), rel = 0, abs = 0)
}

# cart2bary on random simplices
for (rep in 1:10) {
  d <- 2 + rep %% 5; X <- pts(d + 1, d); nq <- 6; P <- pts(nq, d)
  b <- cart2bary(X, P)
  add("cbsum", c(d, rowm(X), nq, rowm(P)), sum((1:nq) * (b %*% (1:(d + 1)))))
}

# intersectn of two overlapping hulls
for (rep in 1:10) {
  d <- 2 + (rep - 1) %% 5; n1 <- sample(9:14, 1); n2 <- sample(9:14, 1)
  p1 <- pts(n1, d); p2 <- pts(n2, d) + matrix(0.4 * rnorm(d), n2, d, byrow = TRUE)
  r <- tryCatch(suppressWarnings({ fp <- feasible.point(convhulln(p1, "n FA"), convhulln(p2, "n FA")); intersectn(p1, p2, fp = fp) }), error = function(e) NULL)
  if (is.null(r)) next  # R's own Qhull call failed on this draw
  a <- c(n1, n2, d, rowm(p1), rowm(p2), fp)
  add("ivert", a, nrow(r$ps), rel = 0, abs = 0); add("ivol", a, r$ch$vol); add("iarea", a, r$ch$area)
}

# dot along rows and columns
for (rep in 1:6) {
  m <- 3 + rep; n <- 2 + rep %% 4; x <- matrix(rnorm(m * n), m); y <- matrix(rnorm(m * n), m)
  for (dsel in 1:2) {
    r <- dot(x, y, dsel)
    add("dotsum", c(m, n, dsel, rowm(x), rowm(y)), sum((seq_along(r)) * r))
  }
}
emit("geometry", "geometry", list(cases))
