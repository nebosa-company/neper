# gstatvgm: gstat's variogram model catalogue and sample variograms.
#   "gam" (nst, 6 numbers per structure: code, psill, range, kappa, angle, ratio; then dx, dy) is variogramLine at the lag (dx, dy);
#   "ev" (kind 0 direct 1 cross 2 pseudo cross, cloud, na, nb, cutoff, width, alpha, tol, part 0 np 1 dist 2 gamma 3 count, index, ndrift 1 or 3, xa ya za.. [xb yb zb..]) is variogram().
suppressMessages(library(gstat)); suppressMessages(library(sp))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20262101)
codes <- c(Nug = 1, Exp = 2, Sph = 3, Gau = 4, Exc = 5, Mat = 6, Ste = 7, Cir = 8, Lin = 9, Bes = 10, Pen = 11, Per = 12, Wav = 13, Hol = 14, Log = 15, Pow = 16, Spl = 17, Err = 19, Int = 20)
# structures: data.frame(model, psill, range, kappa, ang, ratio)
build <- function(st) {
  m <- NULL
  for (i in seq_len(nrow(st))) {
    anis <- if (st$ratio[i] == 1 && st$ang[i] == 0) c(0, 0, 0, 1, 1) else c(st$ang[i], 0, 0, st$ratio[i], 1)
    one <- vgm(st$psill[i], as.character(st$model[i]), st$range[i], kappa = st$kappa[i], anis = anis[c(1, 4)])
    m <- if (is.null(m)) one else vgm(st$psill[i], as.character(st$model[i]), st$range[i], kappa = st$kappa[i], anis = anis[c(1, 4)], add.to = m)
  }
  m
}
flat <- function(st) as.vector(rbind(codes[as.character(st$model)], st$psill, st$range, st$kappa, st$ang, st$ratio))
rstruct <- function(mod, aniso) {
  rg <- runif(1, 0.2, 1.5); k <- runif(1, 0.3, 4)
  if (mod == "Pow") rg <- runif(1, 0.2, 1.8)
  if (mod == "Log") rg <- runif(1, 0.1, 1)
  if (mod %in% c("Nug", "Err", "Int")) { rg <- 0; aniso <- FALSE }
  data.frame(model = mod, psill = runif(1, 0.1, 2), range = rg, kappa = k, ang = if (aniso) sample(c(0, 30, 45, 90, 135, 200, 300), 1) else 0, ratio = if (aniso) runif(1, 0.2, 1) else 1)
}
# every family alone, isotropic and anisotropic, at several lags
for (mod in names(codes)) for (aniso in c(FALSE, TRUE)) for (rep in 1:3) {
  st <- rstruct(mod, aniso)
  if (mod %in% c("Mat", "Ste")) st$kappa <- c(0.5, 1.3, 2.7)[rep]
  if (mod == "Exc") st$kappa <- c(0.7, 1.4, 2)[rep]
  m <- build(st)
  for (q in 1:4) {
    h <- runif(1, 0.05, 3); th <- runif(1, 0, 2 * pi); lag <- h * c(sin(th), cos(th))
    if (q == 4) lag <- c(0, 0)
    g <- variogramLine(m, dist_vector = 1, dir = c(lag, 0))$gamma
    add("gam", c(1, flat(st), lag), g)
  }
}
# nested models: nugget + two structures with anisotropy
fam <- c("Sph", "Exp", "Gau", "Cir", "Pen", "Lin", "Mat", "Ste", "Wav", "Hol")
for (rep in 1:30) {
  st <- rbind(rstruct("Nug", FALSE), rstruct(sample(fam, 1), TRUE), rstruct(sample(fam, 1), rep %% 2 == 0))
  m <- build(st)
  for (q in 1:3) {
    lag <- runif(2, -2, 2)
    add("gam", c(3, flat(st), lag), variogramLine(m, dist_vector = 1, dir = c(lag, 0))$gamma)
  }
}
dat <- function(n) { d <- data.frame(x = runif(n), y = runif(n)); d$z <- round(sin(3 * d$x) + d$y + rnorm(n, 0, 0.3), 4); d$z2 <- round(0.5 * d$z + cos(2 * d$y) + rnorm(n, 0, 0.2), 4); d }
flatxy <- function(d, z) as.vector(t(cbind(d$x, d$y, z)))
bins <- function(v, width) floor(v$dist / width)
# omnidirectional and directional variograms
for (rep in 1:6) {
  n <- sample(18:26, 1); d <- dat(n); cutoff <- runif(1, 0.4, 0.8); width <- cutoff / sample(5:9, 1)
  alphas <- if (rep %% 2 == 0) c(0, 45, 90, 135) else c(sample(0:179, 1))
  tol <- if (rep %% 2 == 0) 22.5 else runif(1, 10, 40)
  nd <- if (rep > 5) 3 else 1; v <- variogram(if (nd == 3) z ~ x + y else z ~ 1, ~x + y, d, cutoff = cutoff, width = width, alpha = alphas, tol.hor = tol)
  for (r in seq_len(nrow(v))) for (pt in 0:2) add("ev", c(0, 0, n, n, cutoff, width, v$dir.hor[r], tol, pt, bins(v, width)[r], nd, flatxy(d, d$z)), c(v$np[r], v$dist[r], v$gamma[r])[pt + 1])
}
# clouds
for (rep in 1:4) {
  n <- sample(12:18, 1); d <- dat(n); cutoff <- runif(1, 0.4, 0.9)
  alpha <- if (rep > 2) 60 else 0; tol <- if (rep > 2) 30 else 90
  v <- variogram(z ~ 1, ~x + y, d, cutoff = cutoff, cloud = TRUE, alpha = alpha, tol.hor = tol)
  add("ev", c(0, 1, n, n, cutoff, 0.1, alpha, tol, 3, 0, 1, flatxy(d, d$z)), nrow(v))
  for (k in unique(round(seq(1, nrow(v), length.out = 12)))) for (pt in 1:2) add("ev", c(0, 1, n, n, cutoff, 0.1, alpha, tol, pt, k - 1, 1, flatxy(d, d$z)), c(NA, v$dist[k], v$gamma[k])[pt + 1])
}
# cross variograms at shared locations, and the cloud of one
for (rep in 1:4) {
  n <- sample(16:24, 1); d <- dat(n); cutoff <- runif(1, 0.4, 0.8); width <- cutoff / 6
  g <- gstat(NULL, "a", z ~ 1, ~x + y, d); g <- gstat(g, "b", z2 ~ 1, ~x + y, d)
  alpha <- if (rep > 2) 30 else 0; tol <- if (rep > 2) 30 else 90
  v <- variogram(g, cutoff = cutoff, width = width, alpha = alpha, tol.hor = tol); v <- v[v$id == "a.b", ]
  for (r in seq_len(nrow(v))) for (pt in 0:2) add("ev", c(1, 0, n, n, cutoff, width, alpha, tol, pt, bins(v, width)[r], 1, flatxy(d, d$z), flatxy(d, d$z2)), c(v$np[r], v$dist[r], v$gamma[r])[pt + 1])
}
# pseudo cross variograms: the two variables at different locations
for (rep in 1:4) {
  n1 <- sample(16:24, 1); n2 <- sample(16:24, 1); d1 <- dat(n1); d2 <- dat(n2); cutoff <- runif(1, 0.4, 0.8); width <- cutoff / 6
  nd <- if (rep > 2) 3 else 1
  g <- gstat(NULL, "a", if (nd == 3) z ~ x + y else z ~ 1, ~x + y, d1); g <- gstat(g, "b", if (nd == 3) z2 ~ x + y else z2 ~ 1, ~x + y, d2)
  v <- variogram(g, cutoff = cutoff, width = width); v <- v[v$id == "a.b", ]
  for (r in seq_len(nrow(v))) for (pt in 0:2) add("ev", c(2, 0, n1, n2, cutoff, width, 0, 90, pt, bins(v, width)[r], nd, flatxy(d1, d1$z), flatxy(d2, d2$z2)), c(v$np[r], v$dist[r], v$gamma[r])[pt + 1])
}
# Cressie's estimator, the pairwise relative semivariogram and the covariogram
for (rep in 1:6) {
  n <- sample(16:24, 1); d <- dat(n); d$zp <- round(exp(d$z / 2), 4); cutoff <- runif(1, 0.4, 0.8); width <- cutoff / 6; nest <- floor(cutoff / width) + 2
  alpha <- if (rep > 4) 45 else 0; tol <- if (rep > 4) 30 else 90
  v <- variogram(z ~ 1, ~x + y, d, cutoff = cutoff, width = width, cressie = TRUE, alpha = alpha, tol.hor = tol)
  for (r in seq_len(nrow(v))) for (pt in 0:2) add("ev", c(3, 0, n, n, cutoff, width, alpha, tol, pt, bins(v, width)[r], 1, flatxy(d, d$z)), c(v$np[r], v$dist[r], v$gamma[r])[pt + 1])
  v <- suppressWarnings(variogram(zp ~ 1, ~x + y, d, cutoff = cutoff, width = width, PR = TRUE, alpha = alpha, tol.hor = tol))
  for (r in seq_len(nrow(v))) for (pt in 0:2) add("ev", c(4, 0, n, n, cutoff, width, alpha, tol, pt, bins(v, width)[r], 1, flatxy(d, d$zp)), c(v$np[r], v$dist[r], v$gamma[r])[pt + 1])
  nd <- if (rep %% 2 == 0) 3 else 1
  v <- variogram(if (nd == 3) z ~ x + y else z ~ 1, ~x + y, d, cutoff = cutoff, width = width, covariogram = TRUE, alpha = alpha, tol.hor = tol)
  bi <- ifelse(v$dist == 0, nest - 1, bins(v, width))
  for (r in seq_len(nrow(v))) for (pt in 0:2) add("ev", c(5, 0, n, n, cutoff, width, alpha, tol, pt, bi[r], nd, flatxy(d, d$z)), c(v$np[r], v$dist[r], v$gamma[r])[pt + 1])
}
# the default cutoff
for (rep in 1:6) {
  n <- sample(20:36, 1); d <- dat(n); v <- variogram(z ~ 1, ~x + y, d)
  add("cutoff", c(n, flatxy(d, d$z)), attr(v, "boundaries")[length(attr(v, "boundaries"))])
  add("ev", c(0, 0, n, n, attr(v, "boundaries")[length(attr(v, "boundaries"))], diff(attr(v, "boundaries"))[1], 0, 90, 2, floor(v$dist[2] / diff(attr(v, "boundaries"))[1]), 1, flatxy(d, d$z)), v$gamma[2])
}
emit("gstatvgm", "gstat", list(cases))
