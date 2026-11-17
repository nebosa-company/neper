# signal, part two: the general designs, windows, remez, fir1/fir2 with windows, freqz, grpdelay, impz, specgram, resample, decimate, interp, interp1, sgolay, unwrap, levinson and the order estimators.
#   Every case is a weighted sum of a returned vector (weights by 1-based position) unless its fn says otherwise; args are documented per block.
suppressMessages(library(signal))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(as.numeric(v) * seq_along(v))

# design: args (kind 0 butter 1 cheby1 2 cheby2 3 ellip, ty 0 low 1 high 2 stop 3 pass, n, rp, rs, nw, w...); fn "db" is the numerator, "da" the denominator
set.seed(20270101)
tys <- c("low", "high", "stop", "pass")
for (kind in 0:3) for (ty in 0:3) for (rep in 1:5) {
  n <- sample(if (ty >= 2) 1:4 else 2:6, 1)
  if (kind >= 2 && n < 2) n <- 2
  two <- ty >= 2
  w <- if (two) { w1 <- runif(1, 0.1, 0.5); c(w1, w1 + runif(1, 0.1, 0.4)) } else runif(1, 0.1, 0.8)
  rp <- runif(1, 0.3, 3); rs <- runif(1, 25, 60)
  f <- switch(kind + 1, butter(n, w, tys[ty + 1]), cheby1(n, rp, w, tys[ty + 1]), cheby2(n, rs, w, tys[ty + 1]), ellip(n, rp, rs, w, tys[ty + 1]))
  add("db", c(kind, ty, n, rp, rs, length(w), w), wsum(f$b)); add("da", c(kind, ty, n, rp, rs, length(w), w), wsum(f$a))
}

# window: args (kind 0 hamming 1 hanning 2 blackman 3 bartlett 4 boxcar 5 triang 6 kaiser 7 chebwin 8 gausswin 9 flattopwin 10 flattopwin periodic, n, par)
set.seed(20270102)
for (rep in 1:60) {
  kind <- (rep - 1) %% 11; n <- sample(c(2:12, 15, 16, 31, 32, 63, 64), 1); par <- switch(kind + 1, 0, 0, 0, 0, 0, 0, runif(1, 1, 10), runif(1, 40, 100), runif(1, 1, 4), 0, 0)
  w <- switch(kind + 1, hamming(n), hanning(n), blackman(n), bartlett(n), boxcar(n), triang(n), kaiser(n, par), chebwin(n, par), gausswin(n, par), flattopwin(n), flattopwin(n, "periodic"))
  add("win", c(kind, n, par), wsum(w))
}
add("win", c(0, 1, 0), 1); add("win", c(6, 1, 3), 1); add("win", c(7, 1, 60), 1)

# freqz and freqs: args (mode 0 half-circle grid 1 whole-circle grid 2 listed w 3 analog freqs, nb, na, n, b..., a..., w...)
for (rep in 1:40) {
  mode <- (rep - 1) %% 4; nb <- sample(1:6, 1); na <- sample(1:5, 1)
  b <- round(rnorm(nb), 3); a <- c(1, round(runif(na - 1, -0.3, 0.3), 3)); n <- sample(c(8, 16, 33), 1)
  w <- sort(runif(5, 0.05, 3)); b[1] <- b[1] + 2
  if (mode == 3) { a <- c(1, round(runif(na - 1, 0.5, 2), 3)); h <- freqs(b, a, w)$H }
  else if (mode == 2) h <- freqz(b, a, n = w, Fs = 2 * pi)$h
  else h <- freqz(b, a, n = n, region = if (mode == 0) "half" else "whole")$h
  nw <- if (mode >= 2) length(w) else n
  add("fzr", c(mode, nb, na, n, b, a, w), wsum(Re(h))); add("fzi", c(mode, nb, na, n, b, a, w), wsum(Im(h)))
}

# grpdelay: args (nb, na, n, whole, b..., a...)
for (rep in 1:30) {
  nb <- sample(1:6, 1); na <- sample(1:4, 1); whole <- rep %% 2
  b <- round(rnorm(nb), 3) + c(1.5, rep(0, nb - 1)); a <- c(1, round(runif(na - 1, -0.3, 0.3), 3)); n <- sample(c(8, 16, 32), 1)
  g <- suppressWarnings(grpdelay(b, a, n = n, whole = whole == 1))$gd
  add("gd", c(nb, na, n, whole, b, a), wsum(g))
}

# impz: args (nb, na, n (0 = default), b..., a...); fn "imz" the response, "imzn" its length
for (rep in 1:30) {
  nb <- sample(1:5, 1); na <- sample(1:4, 1); n <- if (rep %% 3 == 0) 0 else sample(5:40, 1)
  b <- round(rnorm(nb), 3); a <- c(1, round(runif(na - 1, -0.4, 0.4), 3))
  r <- if (n == 0) impz(b, a) else impz(b, a, n)
  add("imz", c(nb, na, n, b, a), wsum(r$x)); add("imzn", c(nb, na, n, b, a), length(r$x))
}

# specgram: args (len, n, wkind (hanning 1, hamming 0), ws, overlap, Fs, x...); fn "sgr" Re(S), "sgi" Im(S), "sgf" f, "sgt" t, "sgd" dimensions weighted
for (rep in 1:20) {
  len <- sample(60:160, 1); n <- sample(c(8, 16, 32, 12, 15), 1); ws <- sample(c(6, 8, 16), 1); ws <- min(ws, n)
  ov <- sample(0:(ws - 1), 1); fs <- sample(c(1, 2, 8000), 1); x <- round(rnorm(len), 3); wk <- rep %% 2
  win <- if (wk == 1) hanning(ws) else hamming(ws)
  sp <- specgram(x, n, fs, win, ov)
  add("sgr", c(len, n, wk, ws, ov, fs, x), wsum(Re(sp$S))); add("sgi", c(len, n, wk, ws, ov, fs, x), wsum(Im(sp$S)))
  add("sgf", c(len, n, wk, ws, ov, fs, x), wsum(sp$f)); add("sgt", c(len, n, wk, ws, ov, fs, x), wsum(sp$t))
  add("sgd", c(len, n, wk, ws, ov, fs, x), nrow(sp$S) * 1000 + ncol(sp$S))
}

# unwrap with a tolerance: args (tol, len, x...); levinson: args (p, len, x...) fn "lva" a, "lvv" v, "lvr" ref
for (rep in 1:20) {
  len <- sample(20:80, 1); tol <- runif(1, 1, 3.2); x <- round(cumsum(rnorm(len, 0, 2)), 4)
  add("unw", c(tol, len, x), wsum(unwrap(x, tol)))
  r <- as.numeric(acf(rnorm(len), lag.max = 10, plot = FALSE)$acf); p <- sample(2:8, 1)
  lv <- levinson(r, p)
  add("lva", c(p, length(r), r), wsum(lv$a)); add("lvv", c(p, length(r), r), lv$v); add("lvr", c(p, length(r), r), wsum(lv$ref))
}

# filter with initial state, conv, fftfilt: args (nb, na, len, nix, niy, b..., a..., x..., init.x..., init.y...)
for (rep in 1:30) {
  nb <- sample(1:5, 1); na <- sample(1:4, 1); len <- sample(8:40, 1)
  b <- round(rnorm(nb), 3); a <- c(runif(1, 0.5, 2), round(runif(na - 1, -0.3, 0.3), 3)); x <- round(rnorm(len), 3)
  ix <- round(rnorm(nb - 1), 3); iy <- round(rnorm(na - 1), 3)
  y <- as.numeric(filter(b, a, x, init.x = ix, init.y = iy))
  add("fli", c(nb, na, len, nb - 1, na - 1, b, a, x, ix, iy), wsum(y))
  c1 <- as.numeric(conv(b, x)); add("cnv", c(nb, len, b, x), wsum(c1))
  ff <- as.numeric(fftfilt(b, x)); add("fft", c(nb, len, b, x), wsum(ff))
}
emit("signaldsp", "signal", list(cases))
