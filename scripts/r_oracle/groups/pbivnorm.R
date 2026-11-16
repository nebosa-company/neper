# pbivnorm: P(X <= x, Y <= y).   args: (x, y, rho); infinite limits are given as +-Inf
library(pbivnorm)
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("pbivnorm", args, want, rel = 1e-12, abs = 1e-15)
xs <- c(-Inf, -6, -3, -1.5, -0.5, 0, 0.3, 1, 2.2, 4, 9, Inf)
rhos <- c(-1, -0.999, -0.95, -0.9, -0.74, -0.5, -0.29, 0, 0.1, 0.3, 0.6, 0.76, 0.91, 0.93, 0.999, 1)
for (x in xs) for (y in xs) for (r in rhos) add(c(x, y, r), pbivnorm(x, y, r))
emit("pbivnorm", "pbivnorm", list(cases))
