# sf (GEOS): convex hull area and vertex count, polygon area, point-in-polygon counts, Delaunay triangle count.
#   args: (n, xs[n], ys[n], m, qx[m], qy[m])
#   "hull_area" "hull_n" use all n points; "poly_area" and "pip" use the n points as a star-shaped polygon ordered by angle about their centroid; "del_n" the triangle count of the Delaunay triangulation
suppressMessages(library(sf))
sf_use_s2(FALSE)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-9)
set.seed(20261116)
for (rep in 1:30) {
  n <- sample(5:40, 1); x <- round(runif(n, 0, 100), 3); y <- round(runif(n, 0, 100), 3)
  m <- 25; qx <- round(runif(m, -10, 110), 3); qy <- round(runif(m, -10, 110), 3)
  a <- c(n, x, y, m, qx, qy)
  mp <- st_multipoint(cbind(x, y)); h <- st_convex_hull(mp)
  add("hull_area", a, as.numeric(st_area(h))); add("hull_n", a, nrow(st_coordinates(h)) - 1)
  cx <- mean(x); cy <- mean(y); o <- order(atan2(y - cy, x - cx)); ring <- cbind(x[o], y[o]); ring <- rbind(ring, ring[1, ])
  poly <- st_polygon(list(ring))
  ao <- c(n, x[o], y[o], m, qx, qy)
  add("poly_area", ao, as.numeric(st_area(poly)))
  if (isTRUE(st_is_valid(poly))) add("pip", ao, sum(lengths(st_intersects(st_sfc(lapply(seq_len(m), function(i) st_point(c(qx[i], qy[i])))), poly))))
  tri <- st_triangulate(st_sfc(mp)); add("del_n", a, length(tri[[1]]))
}
emit("sf", "sf", list(cases))
