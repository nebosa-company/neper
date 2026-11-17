# geosphere on the ellipsoid (Karney's geodesic): distGeo, bearing, finalBearing, destPoint, midPoint, areaPolygon, perimeter, centroid.
#   pair functions "dist" "brg" "fbrg" "mid_lon" "mid_lat": args (lon1, lat1, lon2, lat2, a, f)
#   "dest_lon" "dest_lat": args (lon1, lat1, bearing, distance, a, f)
#   polygons "area" "perim_geo" "perim_mat" "cent_x" "cent_y": args (n, lon[n], lat[n], a, f)
suppressMessages(library(geosphere))
cases <- list()
wgs <- c(6378137, 1 / 298.257223563)
ells <- list(wgs, c(6378137, 0), c(6371000, 1 / 250), c(6356752.314245, 1 / 150), c(6378137, -1 / 300))
okang <- function(x) is.finite(x) && abs(x) < 179.9999999
add <- function(fn, args, want, abs = 1e-6) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = abs)
addlon <- function(fn, args, want) if (okang(want)) add(fn, args, want, 1e-9)
pair <- function(p1, p2, e) {
  a <- c(p1, p2, e)
  add("dist", a, distGeo(p1, p2, a = e[1], f = e[2]))
  add("brg", a, bearing(p1, p2, a = e[1], f = e[2]), 1e-9)
  add("fbrg", a, finalBearing(p1, p2, a = e[1], f = e[2]), 1e-9)
  m <- midPoint(p1, p2, a = e[1], f = e[2])
  addlon("mid_lon", a, m[1, 1]); add("mid_lat", a, m[1, 2], 1e-9)
}
set.seed(20261203)
for (i in 1:120) {
  e <- if (i %% 4 == 0) ells[[sample(2:5, 1)]] else wgs
  p1 <- c(runif(1, -179, 179), runif(1, -89, 89)); p2 <- c(runif(1, -179, 179), runif(1, -89, 89))
  if (i %% 5 == 0) p2 <- p1 + c(runif(1, -0.5, 0.5), runif(1, -0.5, 0.5))
  if (i %% 7 == 0) p2 <- c(p1[1] + 180 - runif(1, 0, 1), -p1[2] + runif(1, -1, 1))
  p2[2] <- max(-90, min(90, p2[2])); p2[1] <- max(-180, min(180, p2[1]))
  pair(p1, p2, e)
}
sp <- list(c(0, 90), c(0, -90), c(10, 0), c(-10, 0), c(180, 0), c(-180, 20), c(179.5, 30), c(-179.5, 30), c(0, 0), c(90, 45), c(-90, -45), c(100, 89.9), c(0, 0.0001))
for (p1 in sp) for (p2 in sp) if (!(all(p1 == p2) && runif(1) < 0.7)) pair(p1, p2, wgs)
for (e in ells) { pair(c(0, 0), c(179.5, 0.5), e); pair(c(0, 0), c(180, 0), e); pair(c(20, 30), c(-160, -30), e); pair(c(5, 85), c(-175, 85), e); pair(c(0, 10), c(0, -10), e) }
# destPoint
for (i in 1:150) {
  e <- if (i %% 4 == 0) ells[[sample(2:5, 1)]] else wgs
  p <- c(runif(1, -180, 180), runif(1, -90, 90)); if (i %% 10 == 0) p[2] <- sample(c(-90, 90, 0), 1)
  b <- runif(1, -180, 360); d <- 10^runif(1, 0, 7.3)
  if (i %% 9 == 0) d <- sample(c(0, 1e7, 2e7, 1.99e7), 1)
  dp <- destPoint(p, b, d, a = e[1], f = e[2]); a <- c(p, b, d, e)
  addlon("dest_lon", a, dp[1, 1]); add("dest_lat", a, dp[1, 2], 1e-9)
}
# polygons
poly <- function(x, e) {
  n <- nrow(x); a <- c(n, x[, 1], x[, 2], e)
  add("area", a, areaPolygon(x, a = e[1], f = e[2]), 1e-3)
  add("perim_geo", a, sum(distGeo(x[-n, , drop = FALSE], x[-1, , drop = FALSE], a = e[1], f = e[2])))
  add("perim_mat", a, perimeter(x, a = e[1], f = e[2]), 1e-9)
}
cent <- function(x, e) {
  n <- nrow(x); a <- c(n, x[, 1], x[, 2], e)
  cc <- suppressWarnings(centroid(x)); addlon("cent_x", a, cc[1, 1]); add("cent_y", a, cc[1, 2], 1e-9)
}
for (i in 1:90) {
  e <- if (i %% 5 == 0) ells[[sample(2:4, 1)]] else wgs
  n <- sample(3:9, 1); clon <- runif(1, -170, 170); clat <- runif(1, -65, 65); if (i %% 6 == 0) clon <- sample(c(179, -179, 175, 180), 1)
  sz <- 10^runif(1, -1, 1.5); ang <- sort(runif(n, 0, 2 * pi)); r <- sz * runif(n, 0.4, 1)
  lon <- clon + r * cos(ang); lat <- clat + r * sin(ang)
  lon <- ((lon + 180) %% 360) - 180; lat <- pmax(-85, pmin(85, lat))
  if (i %% 3 == 0) ang <- rev(ang)
  x <- cbind(lon, lat); if (i %% 2 == 0) x <- rbind(x, x[1, ])
  poly(x, e)
  if (nrow(x) >= 4 && !any(duplicated(x))) cent(x, e)
  if (nrow(x) >= 4 && i %% 2 == 1) cent(rbind(x, x[1, ]), e)
}
# rings that enclose a pole, and a few exact rectangles
for (lat in c(80, 85, -70, -88)) { lon <- seq(-170, 170, length.out = 8); x <- cbind(lon, lat); poly(x, wgs); poly(x[8:1, ], wgs); poly(rbind(x, x[1, ]), wgs) }
poly(rbind(c(0, 0), c(10, 0), c(10, 10), c(0, 10), c(0, 0)), wgs); cent(rbind(c(0, 0), c(10, 0), c(10, 10), c(0, 10), c(0, 0)), wgs)
poly(rbind(c(170, 0), c(-170, 0), c(-170, 10), c(170, 10)), wgs); cent(rbind(c(170, 0), c(-170, 0), c(-170, 10), c(170, 10)), wgs)
emit("geosphere_geod", "geosphere", list(cases))
