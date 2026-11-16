# geometry convhulln(..., "FA") on random points in the plane and in space.
#   args: (n, d, points[n*d] row-major)
#   fn "facets" "boundary" "enclosed" (planar: perimeter, area; space: surface area, volume)
suppressMessages(library(geometry))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20270107)
for (rep in 1:30) {
  d <- 2 + rep %% 2; n <- sample(6:40, 1); p <- matrix(rnorm(n * d), n)
  h <- convhulln(p, "FA")
  a <- c(n, d, as.vector(t(p)))
  add("facets", a, nrow(h$hull)); add("boundary", a, h$area); add("enclosed", a, h$vol)
}
emit("geometry", "geometry", list(cases))
