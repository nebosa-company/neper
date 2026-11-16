# gstatpkg: gstat's variogram models, the empirical variogram and ordinary kriging.
#   "vgm" (model 0 Sph 1 Exp 2 Gau 3 Lin, psill, range, nugget, h); "ev" (n, cutoff, width, bin, part 0 np 1 dist 2 gamma, x y z...);
#   "uk" and "sk" (n, model, psill, range, nugget, px, py, ndrift 3 or the known mean, part, x y z...) are universal kriging on (1, x, y) and simple kriging;
#   "ok" (n, model, psill, range, nugget, px, py, part 0 prediction 1 variance, x y z...)
suppressMessages(library(gstat)); suppressMessages(library(sp))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-11)
set.seed(20262008)
mn <- c("Sph", "Exp", "Gau", "Lin")
for (rep in 1:20) {
  md <- sample(0:3, 1); ps <- runif(1, 0.3, 3); rg <- runif(1, 0.2, 1.2); nu <- runif(1, 0, 0.8)
  for (h in runif(4, 0.01, 2)) add("vgm", c(md, ps, rg, nu, h), variogramLine(vgm(ps, mn[md + 1], rg, nu), dist_vector = h)$gamma)
}
for (rep in 1:15) {
  n <- sample(25:70, 1); d <- data.frame(x = runif(n), y = runif(n)); d$z <- round(sin(3 * d$x) + d$y + rnorm(n, 0, 0.3), 4)
  cutoff <- runif(1, 0.3, 0.7); width <- cutoff / sample(4:8, 1)
  v <- variogram(z ~ 1, ~x + y, data = d, cutoff = cutoff, width = width); xyz <- as.vector(t(as.matrix(d[, c("x", "y", "z")])))
  for (b in seq_len(nrow(v))) {
    bin <- floor(v$dist[b] / width)
    for (pt in 0:2) add("ev", c(n, cutoff, width, bin, pt, xyz), c(v$np[b], v$dist[b], v$gamma[b])[pt + 1])
  }
}
for (rep in 1:15) {
  n <- sample(12:35, 1); d <- data.frame(x = runif(n), y = runif(n)); d$z <- round(sin(3 * d$x) + d$y + rnorm(n, 0, 0.3), 4)
  md <- sample(0:3, 1); ps <- runif(1, 0.3, 2); rg <- runif(1, 0.3, 1.2); nu <- runif(1, 0.01, 0.5)
  nd <- data.frame(x = runif(1, 0.1, 0.9), y = runif(1, 0.1, 0.9)); xyz <- as.vector(t(as.matrix(d[, c("x", "y", "z")])))
  k <- krige(z ~ 1, ~x + y, d, nd, model = vgm(ps, mn[md + 1], rg, nu), debug.level = 0)
  add("ok", c(n, md, ps, rg, nu, nd$x, nd$y, 0, xyz), k$var1.pred, 1e-8); add("ok", c(n, md, ps, rg, nu, nd$x, nd$y, 1, xyz), k$var1.var, 1e-8)
}
for (rep in 1:15) {
  n <- sample(15:40, 1); d <- data.frame(x = runif(n), y = runif(n)); d$z <- round(2 * d$x - d$y + sin(4 * d$x) + rnorm(n, 0, 0.2), 4)
  md <- sample(0:3, 1); ps <- runif(1, 0.1, 1); rg <- runif(1, 0.3, 1.2); nu <- runif(1, 0.01, 0.3)
  nd <- data.frame(x = runif(1, 0.1, 0.9), y = runif(1, 0.1, 0.9)); xyz <- as.vector(t(as.matrix(d[, c("x", "y", "z")]))); mu <- runif(1, -0.5, 1)
  ku <- krige(z ~ x + y, ~x + y, d, nd, model = vgm(ps, mn[md + 1], rg, nu), debug.level = 0)
  add("uk", c(n, md, ps, rg, nu, nd$x, nd$y, 3, 0, xyz), ku$var1.pred, 1e-8); add("uk", c(n, md, ps, rg, nu, nd$x, nd$y, 3, 1, xyz), ku$var1.var, 1e-8)
  ks <- krige(z ~ 1, ~x + y, d, nd, model = vgm(ps, mn[md + 1], rg, nu), beta = mu, debug.level = 0)
  add("sk", c(n, md, ps, rg, nu, nd$x, nd$y, mu, 0, xyz), ks$var1.pred, 1e-8); add("sk", c(n, md, ps, rg, nu, nd$x, nd$y, mu, 1, xyz), ks$var1.var, 1e-8)
}
emit("gstatpkg", "gstat", list(cases))
