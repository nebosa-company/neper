# geosphere: spherical and ellipsoidal distances and the rhumb-line formulas.
#   args: (lon1, lat1, lon2, lat2, p5, p6)   fn "haversine" "vsphere" "cosine" "meeus" "vellipsoid" "bearing_rhumb" "dist_rhumb" "dest_lon" "dest_lat"
#   p5 is the radius (haversine, vsphere, cosine, dist_rhumb); for dest_* the args are (lon1, lat1, radius, 0, bearing, distance)
suppressMessages(library(geosphere))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-9)
set.seed(20261202)
for (i in 1:60) {
  p1 <- c(runif(1, -179, 179), runif(1, -80, 80)); p2 <- c(runif(1, -179, 179), runif(1, -80, 80))
  if (i %% 3 == 0) p2 <- p1 + c(runif(1, -2, 2), runif(1, -2, 2))
  r <- c(6378137, 6371000, 1)[i %% 3 + 1]
  a <- c(p1, p2, r, 0)
  add("haversine", a, distHaversine(p1, p2, r = r)); add("vsphere", a, distVincentySphere(p1, p2, r = r))
  add("cosine", a, distCosine(p1, p2, r = r)); add("meeus", a, distMeeus(p1, p2)); add("vellipsoid", a, distVincentyEllipsoid(p1, p2))
  add("bearing_rhumb", a, bearingRhumb(p1, p2)); add("dist_rhumb", a, distRhumb(p1, p2, r = r))
  b <- runif(1, 0, 360); d <- runif(1, 1e3, 3e6) * r / 6378137
  dp <- destPointRhumb(p1, b, d, r = r)
  ad <- c(p1, r, 0, b, d)
  add("dest_lon", ad, dp[1, "lon"]); add("dest_lat", ad, dp[1, "lat"])
}
emit("geosphere", "geosphere", list(cases))
