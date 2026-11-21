# hdrcdepkg: hdrcde 3.5.0. Every case is fn "hdrcde" and args[1] is the kind.
#   hdr kinds (1 sample + density(bw), 2 hdr(x, prob, h = bw, lambda), 3 hdr(den = ) with x NULL / hdr.den(den = ), 6 hdr(x, prob) with the default hdrbw):
#     (kind, what, ri, k, p1, p2, ...). what 0 falpha[ri], 1 number of ends of row ri, 2 end k of row ri, 3 number of modes, 4 mode k, 5 number of all.modes modes, 6 all.modes mode k.
#     rows are the probabilities in decreasing order (alpha = sort(1 - prob)).
#     1: (.., bw, n, x...)  2: (.., bw, lambda, n, x...)  3: (.., seed, nn, m, den$x..., den$y...)  6: (.., lambda, seed, n, x...)
#   5 hdrbw: (5, seed, level, n, x...)
#   7 cdeband.rules0 a (what 0) or b (what 1): (7, what, n, x..., y...)
#   8 cde z with given bandwidths and margins: (8, ix, iy, nx, ny, n, a, b, x..., y..., xm..., ym...)
#   9 default cde(x, y) z[ix, iy]: (9, ix, iy, n, x..., y...); 10 cde.bandwidths(method 3) a / b: (10, what, n, x..., y...)
#   11 hdr.cde row: (11, row, what, ri, k, seed, n, x..., y...), what 0 falpha, 1 count, 2 end k
#   12 modalreg given a, b: (12, what, p, i, deg, P, start (0 e, 1 q), nxfix, a, b, n, x..., y...); what 0 fitted.values[p, i], 1 density, 2 threshold
# The ends of a region are roots of uniroot (zeroin, ported), so they are compared at 1e-9 like the rest.
suppressMessages(library(hdrcde))
cases <- list()
add <- function(args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case("hdrcde", args, want, rel = rel, abs = abs)
add_hdr <- function(kind, h, p, extra, modes = TRUE) {
  hdr_rows <- h$hdr; ends_of <- function(ri) { e <- hdr_rows[ri, ]; e[!is.na(e)] }
  for (ri in seq_len(nrow(hdr_rows))) {
    add(c(kind, 0, ri - 1, 0, p, extra), h$falpha[[ri]])
    e <- ends_of(ri)
    add(c(kind, 1, ri - 1, 0, p, extra), length(e), 0, 0)
    for (k in seq_along(e)) add(c(kind, 2, ri - 1, k - 1, p, extra), e[k])
  }
  if (modes) {
    add(c(kind, 3, 0, 0, p, extra), length(h$mode), 0, 0)
    add(c(kind, 4, 0, 0, p, extra), h$mode[1])
  }
}
probs <- list(c(0.5, 0.95), c(0.8, 0.99), c(0.9, 0.5), c(0.75, 0.25))

# 1. a sample with the default 512-point density
set.seed(20262016)
for (rep in 1:6) {
  n <- sample(100:250, 1); x <- round(if (rep %% 3 == 0) c(rnorm(n / 2, -2), rnorm(n - n / 2, 2)) else rnorm(n, 0, runif(1, 0.5, 2)), 5); bw <- runif(1, 0.2, 0.7); p <- probs[[rep %% 4 + 1]]
  n <- length(x); den <- density(x, bw = bw)
  h <- hdr(x, prob = p, den = den)
  add_hdr(1, h, p, c(bw, n, x))
  if (rep %% 3 == 0) { h2 <- hdr(x, prob = p, den = den, all.modes = TRUE); add(c(1, 5, 0, 0, p, bw, n, x), length(h2$mode), 0, 0); for (k in seq_along(h2$mode)) add(c(1, 6, 0, k - 1, p, bw, n, x), h2$mode[k]) }
}
# hdr.den returns hdr
pdf(NULL); x <- round(rnorm(120, 1, 1.3), 5); den <- density(x, bw = 0.4); hd <- hdr.den(x, prob = c(0.5, 0.95), den = den, h = 0.4); invisible(dev.off())
add_hdr(1, hd, c(0.5, 0.95), c(0.4, 120, x))

# 2. tdensity with a bandwidth and Box-Cox
set.seed(20262017)
for (rep in 1:6) {
  n <- sample(100:200, 1); x <- round(rgamma(n, shape = runif(1, 2, 6), rate = 1), 5); bw <- runif(1, 0.1, 0.5); lam <- c(1, 0.5, 0, 0.25)[rep %% 4 + 1]; p <- probs[[rep %% 4 + 1]]
  h <- hdr(x, prob = p, h = bw, lambda = lam)
  add_hdr(2, h, p, c(bw, lam, n, x))
}

# 3. hdr(den = ) with x NULL (a sample of the density), and hdr.den(den = ) with its 500 draws
set.seed(20262018)
for (rep in 1:5) {
  m <- if (rep <= 3) 100 else 300
  x0 <- c(rnorm(200, -1.5, 0.8), rnorm(150, 1.5, 0.6)); dd <- density(x0, bw = runif(1, 0.2, 0.4), n = m); den <- list(x = dd$x, y = dd$y)
  p <- probs[[rep %% 4 + 1]]; seed <- 100 + rep
  if (rep %% 2 == 1) { set.seed(seed); h <- hdr(den = den, prob = p, nn = 1000); nn <- 1000 }
  else { pdf(NULL); set.seed(seed); h <- hdr.den(prob = p, den = den); invisible(dev.off()); nn <- 500 }
  stopifnot(m < 200 || sum(m * den$y / sum(den$y) > 0.1) > 200)
  add_hdr(3, h, p, c(seed, nn, m, den$x, den$y), modes = TRUE)
}

# 5. hdrbw
set.seed(20262019)
for (rep in 1:6) {
  n <- sample(80:200, 1); x <- round(if (rep %% 2 == 0) c(rnorm(n / 2, -2), rnorm(n - n / 2, 2)) else rnorm(n, 0, runif(1, 0.5, 2)), 5); n <- length(x); lev <- c(0.5, 0.8, 0.95)[rep %% 3 + 1]; seed <- 7000 + rep
  set.seed(seed); b <- hdrbw(x, lev)
  add(c(5, seed, lev, n, x), b)
  if (rep <= 3) {
    p <- probs[[rep]]; set.seed(seed); h <- hdr(x, prob = p)
    add_hdr(6, h, p, c(1, seed, n, x), modes = TRUE)
  }
}
set.seed(20262020)
x <- round(rgamma(150, 3), 5); set.seed(77); h <- hdr(x, prob = c(0.5, 0.9), lambda = 0.5); add_hdr(6, h, c(0.5, 0.9), c(0.5, 77, 150, x))

# 7, 8, 9, 10 cde
set.seed(20262021)
for (rep in 1:5) {
  n <- sample(70:120, 1); x <- round(rnorm(n), 5); y <- round(if (rep %% 2) 1 + 0.8 * x + rnorm(n, 0, 0.5) else sin(x) + rnorm(n, 0, 0.3 + 0.1 * abs(x)), 5)
  r <- hdrcde:::cdeband.rules0(x, y); add(c(7, 0, n, x, y), r$a); add(c(7, 1, n, x, y), r$b)
  cd <- cde(x, y, deg = 0)
  for (t in 1:6) { ix <- sample(15, 1); iy <- sample(100, 1); add(c(9, ix - 1, iy - 1, n, x, y), cd$z[ix, iy]) }
  add(c(9, 6, 49, n, x, y), cd$z[7, 50])
  a <- runif(1, 0.2, 0.6); b <- runif(1, 0.2, 0.5); xm <- sort(runif(6, min(x), max(x))); ym <- seq(min(y) - 1, max(y) + 1, length.out = 40)
  cd2 <- cde(x, y, a = a, b = b, x.margin = xm, y.margin = ym)
  for (t in 1:5) { ix <- sample(6, 1); iy <- sample(40, 1); add(c(8, ix - 1, iy - 1, 6, 40, n, a, b, x, y, xm, ym), cd2$z[ix, iy]) }
  bw <- if (rep <= 3) try(cde.bandwidths(x, y, method = 3), silent = TRUE) else NULL
  if (is.list(bw)) { add(c(10, 0, n, x, y), bw$a); add(c(10, 1, n, x, y), bw$b) }
}

# 11. hdr.cde
set.seed(20262022)
for (rep in 1:2) {
  n <- 80; x <- round(rnorm(n), 5); y <- round(0.5 * x + rnorm(n, 0, 0.6), 5); seed <- 500 + rep
  cd <- cde(x, y, deg = 0)
  set.seed(seed); hc <- hdr.cde(cd, prob = c(0.5, 0.95), plot = FALSE)
  for (row in c(2, 8, 14)) {
    h <- hc[[row]]
    for (ri in 1:2) {
      add(c(11, row - 1, 0, ri - 1, 0, seed, n, x, y), h$falpha[[ri]])
      e <- h$hdr[ri, ]; e <- e[!is.na(e)]
      add(c(11, row - 1, 1, ri - 1, 0, seed, n, x, y), length(e), 0, 0)
      for (k in seq_along(e)) add(c(11, row - 1, 2, ri - 1, k - 1, seed, n, x, y), e[k])
    }
  }
}

# 12. modalreg
set.seed(20262023)
for (rep in 1:4) {
  n <- 90; x <- round(runif(n, 0, 3), 5); y <- round(ifelse(runif(n) < 0.5, 1 + x, 4 - x) + rnorm(n, 0, 0.3), 5)
  a <- runif(1, 0.2, 0.5); b <- runif(1, 0.2, 0.5); deg <- rep %% 2; P <- 2 + (rep > 2); st <- if (rep %% 2) "e" else "q"
  mr <- modalreg(x, y, a = a, b = b, deg = deg, P = P, start = st, xfix = seq(min(x), max(x), l = 20), plot.type = "n")
  for (t in 1:6) { p <- sample(P, 1); i <- sample(20, 1)
    add(c(12, 0, p - 1, i - 1, deg, P, rep %% 2 == 0, 20, a, b, n, x, y), mr$fitted.values[p, i])
    add(c(12, 1, p - 1, i - 1, deg, P, rep %% 2 == 0, 20, a, b, n, x, y), mr$density[p, i]) }
  add(c(12, 2, 0, 0, deg, P, rep %% 2 == 0, 20, a, b, n, x, y), mr$threshold)
}

# 13, 14, 15. the bootstrap bandwidths (methods 1 and 4) and modalreg with them
set.seed(20262024)
for (rep in 1:3) {
  n <- sample(70:100, 1); x <- round(rnorm(n), 5); y <- round(if (rep %% 2) 1 + 0.8 * x + rnorm(n, 0, 0.5) else sin(x) + rnorm(n, 0, 0.3 + 0.1 * abs(x)), 5); seed <- 900 + rep
  set.seed(seed); b1 <- try(cde.bandwidths(x, y, method = 1), silent = TRUE)
  if (is.list(b1)) { add(c(13, 0, seed, n, x, y), b1$a); add(c(13, 1, seed, n, x, y), b1$b) }
  set.seed(seed); b4 <- try(cde.bandwidths(x, y, method = 4), silent = TRUE)
  if (is.list(b4)) { add(c(14, 0, seed, n, x, y), b4$a); add(c(14, 1, seed, n, x, y), b4$b) }
}
set.seed(20262025)
n <- 90; x <- round(runif(n, 0, 3), 5); y <- round(ifelse(runif(n) < 0.5, 1 + x, 4 - x) + rnorm(n, 0, 0.3), 5)
set.seed(321); mr <- modalreg(x, y, P = 2, xfix = seq(min(x), max(x), l = 20), plot.type = "n")
add(c(15, 0, 0, 0, 0, 2, 0, 20, 321, 0, n, x, y), mr$fitted.values[1, 1]); add(c(15, 0, 1, 12, 0, 2, 0, 20, 321, 0, n, x, y), mr$fitted.values[2, 13])
add(c(15, 1, 0, 7, 0, 2, 0, 20, 321, 0, n, x, y), mr$density[1, 8]); add(c(15, 2, 0, 0, 0, 2, 0, 20, 321, 0, n, x, y), mr$threshold)
add(c(13, 0, 321, n, x, y), mr$bandwidths[["a"]]); add(c(13, 1, 321, n, x, y), mr$bandwidths[["b"]])
emit("hdrcdepkg", "hdrcde", list(cases))
