# interpmesh: interp tri.mesh / voronoi.mosaic / voronoi.area / interpp (linear) and bilinear (interp and fields::interp.surface).
#   "tri" case args c(op, idx, n, nq, x, y, z, xq, yq); "bil" case args c(op, idx, nx, ny, x, y, z, nq, xq, yq); ops are at the top of lib/e/algo/stat/interpmesh.e
.libPaths(c(Sys.getenv("R_ORACLE_LIB"), .libPaths()))
suppressMessages({ library(interp); library(fields) }); options(warn = -1)
cases <- list()
set.seed(20262012)
for (rep in 1:10) {
  n <- sample(8:30, 1); x <- runif(n); y <- runif(n); z <- sin(3 * x) + y^2 + rnorm(n, 0, 0.1)
  nq <- 12; xq <- runif(nq, -0.1, 1.1); yq <- runif(nq, -0.1, 1.1)
  base <- c(n, nq, x, y, z, xq, yq)
  add <- function(op, idx, want) cases[[length(cases) + 1]] <<- case("tri", c(op, idx, base), want, rel = 1e-9, abs = 1e-12)
  tm <- tri.mesh(x, y); vm <- voronoi.mosaic(tm); va <- voronoi.area(vm)
  add(13, 0, length(vm$dummy.x)); add(14, 0, sum(vm$dummy.x)); add(15, 0, sum(vm$dummy.y))
  add(0, 0, tm$nt); add(1, 0, tm$narcs); add(2, 0, tm$nchull)
  add(3, 0, sum(tm$cclist[, "area"])); add(4, 0, sum(tm$cclist[, "r"])); add(5, 0, sum(tm$cclist[, "x"])); add(6, 0, sum(tm$cclist[, "y"]))
  tr <- t(apply(tm$trlist[, 1:3, drop = FALSE], 1, sort))
  add(7, 0, sum((tr[, 1] * 131 + tr[, 2]) * 131 + tr[, 3]))
  add(8, 0, sum(!is.na(va))); add(9, 0, sum(va, na.rm = TRUE))
  ip <- interpp(x, y, z, xq, yq, linear = TRUE)
  for (j in seq_len(nq)) {
    ok <- !is.na(ip$z[j])
    add(10, j - 1, as.numeric(ok))
    if (ok) add(11, j - 1, ip$z[j])
  }
}
# Akima / local-polynomial quintic interpolation (interp(method = "akima"), op 12): points path (interpp) and the grid path (interp with xo, yo)
for (rep in 1:8) {
  n <- sample(14:36, 1); x <- runif(n); y <- runif(n); z <- sin(3 * x) + y^2 + rnorm(n, 0, 0.1)
  if (rep <= 5) {
    nq <- 14; xq <- runif(nq, -0.05, 1.05); yq <- runif(nq, -0.05, 1.05)
    ip <- interp(x, y, z, xq, yq, input = "points", output = "points", method = "akima"); want <- ip$z
  } else {
    xo <- seq(0.1, 0.9, length = 4); yo <- seq(0.12, 0.88, length = 4)
    gz <- interp(x, y, z, xo, yo, method = "akima")$z
    xq <- rep(xo, times = 4); yq <- rep(yo, each = 4); nq <- 16; want <- as.vector(gz)
  }
  base <- c(n, nq, x, y, z, xq, yq)
  add <- function(op, idx, w) cases[[length(cases) + 1]] <<- case("tri", c(op, idx, base), w, rel = 1e-9, abs = 1e-11)
  for (j in seq_len(nq)) {
    ok <- !is.na(want[j])
    add(10, j - 1, as.numeric(ok))
    if (ok) add(12, j - 1, want[j])
  }
}
# tri.mesh and voronoi.mosaic in R's own order (the s_hull_pro.cpp port): trlist, arcs, chull, cclist, the neighbour slots after the dummy nodes, the dummy nodes and the vertex lists of
# voronoi.findvertices, each as a position-weighted sum (sum of position * value); ops 8, 9 and 16-40 of tri_answer
wsum <- function(v) sum(seq_along(v) * v)
for (rep in 1:8) {
  n <- sample(8:26, 1); x <- runif(n); y <- runif(n)
  base <- c(n, 0, x, y, x)
  add <- function(op, want) cases[[length(cases) + 1]] <<- case("tri", c(op, 0, base), want, rel = 1e-9, abs = 1e-9)
  tm <- tri.mesh(x, y); vm <- voronoi.mosaic(tm)
  for (cl in 1:9) add(23 + cl, wsum(tm$trlist[, cl]))
  add(33, wsum(tm$arcs[, 1])); add(34, wsum(tm$arcs[, 2])); add(35, wsum(tm$chull))
  for (cl in 1:5) add(35 + cl, wsum(tm$cclist[, cl]))
  add(16, wsum(vm$n1)); add(17, wsum(vm$n2)); add(18, wsum(vm$n3))
  add(19, wsum(vm$dummy.x)); add(20, wsum(vm$dummy.y))
  hv <- 0; hx <- 0; hy <- 0; nc <- 0; ar <- 0
  for (i in seq_len(n)) {
    vs <- interp:::voronoi.findvertices(i, vm)
    if (length(vs) > 0) {
      nc <- nc + 1; hv <- hv + i * wsum(vs); hx <- hx + i * wsum(vm$x[vs]); hy <- hy + i * wsum(vm$y[vs])
      ar <- ar + interp:::voronoi.polyarea(vm$x[vs], vm$y[vs])
    }
  }
  add(8, nc); add(9, ar); add(21, hv); add(22, hx); add(23, hy)
}
for (rep in 1:6) {
  nx <- sample(4:9, 1); ny <- sample(4:9, 1)
  x <- sort(runif(nx, 0, 10)); y <- sort(runif(ny, -3, 3)); z <- outer(x, y, function(a, b) sin(a) * b + a)
  z <- z + matrix(rnorm(nx * ny, 0, .2), nx, ny)
  nq <- 10; xq <- runif(nq, -0.5, 10.5); yq <- runif(nq, -3.5, 3.5)
  # queries on and 0.005 either side of each grid edge (the inside test must be sharp)
  xq[1:6] <- c(x[1], x[nx], x[1] - 0.005, x[nx] + 0.005, x[1] + 0.005, x[nx] - 0.005); yq[1:6] <- runif(6, y[1], y[ny])
  yq[7:10] <- c(y[1], y[ny], y[1] - 0.005, y[ny] + 0.005); xq[7:10] <- runif(4, x[1], x[nx])
  base <- c(nx, ny, x, y, z, nq, xq, yq)
  add <- function(op, idx, want) cases[[length(cases) + 1]] <<- case("bil", c(op, idx, base), want, rel = 1e-9, abs = 1e-12)
  fi <- interp.surface(list(x = x, y = y, z = z), cbind(xq, yq))
  for (j in seq_len(nq)) {
    ok <- !is.na(fi[j])
    add(0, j - 1, as.numeric(ok))
    if (ok) {
      add(1, j - 1, fi[j])
      b <- bilinear(x, y, z, xq[j], yq[j])$z
      if (!is.na(b)) add(1, j - 1, b)
    }
  }
}
# circles(): the polylines it hands to lines(), captured by replacing lines in a copy of the function's environment; ops of circles_answer
for (rep in 1:4) {
  n <- sample(1:4, 1); x <- rnorm(n); y <- rnorm(n); r <- runif(n, 0.1, 2)
  px <- numeric(0); py <- numeric(0)
  cf <- interp::circles
  environment(cf) <- list2env(list(lines = function(x, y, ...) { px <<- c(px, x); py <<- c(py, y) }), parent = environment(interp::circles))
  cf(x, y, r)
  w <- seq_along(px)
  base <- c(n, x, y, r)
  add <- function(op, want) cases[[length(cases) + 1]] <<- case("circ", c(op, base), want, rel = 1e-9, abs = 1e-9)
  add(0, sum(w * px)); add(1, sum(w * py)); add(2, length(px))
}
emit("interpmesh", "interp", list(cases))
