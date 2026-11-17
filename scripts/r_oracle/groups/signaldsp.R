# signal, part two: the general designs, windows, remez, fir1/fir2 with windows, freqz, grpdelay, impz, specgram, resample, decimate, interp, interp1, sgolay, unwrap, levinson and the order estimators.
#   Every case is a weighted sum of a returned vector (weights by 1-based position) unless its fn says otherwise; args are documented per block.
suppressMessages(library(signal)); sinc <- signal:::sinc
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

# remez: args (n, ftype 1 bandpass 2 differentiator 3 hilbert, density, nf, f..., a..., w...)
set.seed(20270103)
nrem <- 0
for (rep in 1:60) {
  ft <- c("bandpass", "differentiator", "hilbert")[(rep - 1) %% 3 + 1]; n <- sample(c(10:40), 1); dens <- sample(c(16, 20, 32), 1)
  if (ft == "bandpass") {
    nb <- sample(1:2, 1)
    f <- sort(c(0, runif(2 * nb - 2, 0.05, 0.9), 1)); a <- rep(c(1, 0), length.out = length(f) / 2)[rep(1:(length(f) / 2), each = 2)]; w <- round(runif(length(f) / 2, 0.5, 3), 2)
  } else { f <- c(0, runif(1, 0.8, 0.98)); a <- if (ft == "differentiator") c(0, f[2] / 2) else c(1, 1); w <- 1 }
  # the C routine overruns its grid when the band rounding disagrees with its size prediction; keep only the cases where they agree
  nt <- n + 1; rr <- nt %/% 2; if (nt %% 2 == 1 && ft == "bandpass") rr <- rr + 1
  bd <- f / 2; pred <- sum(trunc(2 * rr * dens * (bd[seq(2, length(bd), 2)] - bd[seq(1, length(bd), 2)]) + 0.5)) - (ft != "bandpass")
  delf <- 0.5 / (dens * rr); g0 <- if (ft != "bandpass" && delf > bd[1]) delf else bd[1]; act <- 0
  for (bb in seq_len(length(bd) / 2)) { lo <- if (bb == 1) g0 else bd[2 * bb - 1]; act <- act + trunc((bd[2 * bb] - lo) / delf + 0.5) }
  if (act != pred) next
  b <- try(remez(n, f, a, w, ft, dens), silent = TRUE)
  if (inherits(b, "try-error")) next
  nrem <- nrem + 1
  add("rmz", c(n, which(c("bandpass", "differentiator", "hilbert") == ft), dens, length(f) / 2, f, a, w), wsum(b))
}
cat("remez cases:", nrem, "\n")

# fir1 with a window: args (n, ty, kind, par, scale, nw, w...); fn "f1" the taps, "f1n" their number
kinds <- c(0, 1, 2, 6, 7, 8, 9)
for (rep in 1:60) {
  ty <- (rep - 1) %% 6; tys6 <- c("low", "high", "stop", "pass", "DC-0", "DC-1")[ty + 1]
  n <- sample(c(10, 11, 20, 21, 30, 31), 1); kind <- sample(kinds, 1); par <- switch(match(kind, kinds), 0, 0, 0, runif(1, 1, 8), runif(1, 40, 90), runif(1, 1, 3), 0)
  nw <- if (ty %in% c(2, 3)) 2 else if (ty >= 4) sample(1:3, 1) else 1
  w <- sort(runif(nw, 0.1, 0.9)); sc <- sample(c(0, 1), 1)
  win <- switch(match(kind, kinds), hamming(n + 1), hanning(n + 1), blackman(n + 1), kaiser(n + 1, par), chebwin(n + 1, par), gausswin(n + 1, par), flattopwin(n + 1))
  b <- suppressWarnings(fir1(n, w, tys6, window = win, scale = sc == 1))
  add("f1", c(n, ty, kind, par, sc, nw, w), wsum(b)); add("f1n", c(n, ty, kind, par, sc, nw, w), length(b))
}

# fir2 with a window: args (n, grid_n, ramp_n, kind, par, nf, f..., m...)
for (rep in 1:30) {
  n <- sample(c(8, 15, 16, 21, 30, 41), 1); gridn <- sample(c(256, 512), 1); rn <- c(0, 2, gridn / 20)[rep %% 3 + 1]; kind <- sample(c(0, 1, 2, 6), 1); par <- if (kind == 6) runif(1, 1, 8) else 0
  c1 <- sort(runif(2, 0.1, 0.9)); f <- c(0, c1[1], c1[1], c1[2], 1); m <- c(1, 1, 0.2, 0.2, 0.6)
  win <- switch(match(kind, c(0, 1, 2, 6)), hamming(n + 1), hanning(n + 1), blackman(n + 1), kaiser(n + 1, par))
  b <- fir2(n, f, m, gridn, rn, win)
  add("f2", c(n, gridn, rn, kind, par, length(f), f, m), wsum(as.numeric(b)))
}

# resample, decimate, interp: args (p, q, d, len, x...) ; (ftype, q, n, len, x...) ; (q, n, Wc, len, x...)
for (rep in 1:30) {
  len <- sample(30:80, 1); x <- round(cumsum(rnorm(len)), 3); p <- sample(1:5, 1); q <- sample(1:5, 1); d <- sample(c(3, 5, 7), 1)
  y <- resample(x, p, q, d)
  add("rs", c(p, q, d, len, x), wsum(y)); add("rsn", c(p, q, d, len, x), length(y))
}
for (rep in 1:30) {
  len <- sample(80:200, 1); x <- round(cumsum(rnorm(len)), 3); q <- sample(2:5, 1); ft <- rep %% 2
  n <- if (ft == 1) sample(c(10, 20, 30), 1) else sample(c(4, 6, 8), 1)
  y <- decimate(x, q, n, if (ft == 1) "fir" else "iir")
  add("dcm", c(ft, q, n, len, x), wsum(y))
}
for (rep in 1:15) {
  len <- sample(10:40, 1); x <- round(rnorm(len), 3); q <- sample(2:4, 1); n <- sample(2:5, 1); wc <- sample(c(0.5, 0.8, 1), 1)
  y <- interp(x, q, n, wc)
  add("ipo", c(q, n, wc, len, x), wsum(y))
}

# interp1: args (method 0 linear 1 nearest 2 pchip 3 cubic 4 spline, nx, nxi, x..., y..., xi...); NA counts as 0
for (rep in 1:50) {
  method <- (rep - 1) %% 5; nx <- sample(5:15, 1); x <- cumsum(runif(nx, 0.3, 2)); y <- round(rnorm(nx), 3)
  nxi <- sample(5:25, 1); xi <- runif(nxi, min(x) - 0.5, max(x) + 0.5); xi[1] <- x[2]; xi[2] <- max(x); xi[3] <- min(x)
  r <- interp1(x, y, xi, c("linear", "nearest", "pchip", "cubic", "spline")[method + 1])
  r[is.na(r)] <- 0
  add("i1", c(method, nx, nxi, x, y, xi), wsum(r), rel = 1e-9, abs = 1e-10)
}

# sgolay: args (p, n, m, ts); "sgm" the matrix by rows, "sfl" filter: args (p, n, m, ts, len, x...)
for (rep in 1:30) {
  n <- sample(c(5, 7, 9, 11, 13, 15), 1); p <- sample(1:min(4, n - 2), 1); m <- sample(0:min(2, p), 1); ts <- sample(c(1, 0.5, 2), 1)
  F <- unclass(sgolay(p, n, m, ts))
  add("sgm", c(p, n, m, ts), wsum(t(F)))
  len <- sample(30:60, 1); x <- round(rnorm(len), 3)
  add("sfl", c(p, n, m, ts, len, x), wsum(sgolayfilt(x, p, n, m, ts)))
}
for (rep in 1:10) { len <- sample(30:60, 1); x <- round(rnorm(len), 3); add("sfd", c(len, x), wsum(sgolayfilt(x))) }

# order estimators: args (nw, wp..., ws..., rp, rs); fn "bo*" buttord, "co*" cheb1ord, "eo*" ellipord
tyc <- function(s) match(s, c("low", "high", "stop", "pass")) - 1
for (rep in 1:30) {
  two <- rep %% 3 == 0; high <- rep %% 2 == 0
  if (two) { w1 <- runif(1, 0.3, 0.5); w2 <- w1 + runif(1, 0.1, 0.2); wp <- c(w1, w2); ws <- c(w1 - runif(1, 0.1, 0.25), w2 + runif(1, 0.05, 0.2)) }
  else { wp <- runif(1, 0.3, 0.6); ws <- if (high) wp - runif(1, 0.1, 0.25) else wp + runif(1, 0.1, 0.3) }
  rp <- runif(1, 0.5, 3); rs <- runif(1, 20, 60)
  ar <- c(length(wp), wp, ws, rp, rs)
  b <- suppressWarnings(buttord(wp, ws, rp, rs)); add("bon", ar, b$n); add("boc", ar, wsum(b$Wc)); add("bot", ar, tyc(b$type))
  cc <- try(cheb1ord(wp, ws, rp, rs), silent = TRUE)
  if (!inherits(cc, "try-error")) { add("con", ar, cc$n); add("cot", ar, tyc(cc$type)) }
  ee <- try(ellipord(wp, ws, rp, rs), silent = TRUE)
  if (!inherits(ee, "try-error")) { add("eon", ar, ee$n); add("eot", ar, tyc(ee$type)) }
}
for (rep in 1:20) {
  kind <- rep %% 4; dev <- runif(1, 0.001, 0.1); fs <- sample(c(2, 8000), 1)
  if (kind == 0) { f <- c(0.2, 0.3) * fs / 2; m <- c(1, 0) } else if (kind == 1) { f <- c(0.2, 0.3) * fs / 2; m <- c(0, 1) }
  else if (kind == 2) { f <- c(0.1, 0.2, 0.4, 0.5) * fs / 2; m <- c(0, 1, 0) } else { f <- c(0.1, 0.2, 0.4, 0.5) * fs / 2; m <- c(1, 0, 1) }
  k <- kaiserord(f, m, dev, fs)
  add("kon", c(fs, length(f), f, m, dev), k$n); add("kob", c(fs, length(f), f, m, dev), k$beta)
  add("kow", c(fs, length(f), f, m, dev), wsum(k$Wc)); add("kot", c(fs, length(f), f, m, dev), match(k$type, c("low", "high", "stop", "pass", "DC-0", "DC-1")) - 1)
}

# chirp, spencer, roots, Zpg to Arma
for (rep in 1:15) {
  form <- (rep - 1) %% 3; len <- sample(10:50, 1); tt <- seq(0, 1, length.out = len); f0 <- runif(1, 0, 20); f1 <- f0 + runif(1, 5, 60); ph <- runif(1, 0, 90)
  add("chp", c(form, f0, 1, f1, ph, len, tt), wsum(chirp(tt, f0, 1, f1, c("linear", "quadratic", "logarithmic")[form + 1], ph)))
  len <- sample(20:60, 1); x <- round(rnorm(len), 3); s <- spencer(x); s[is.na(s)] <- 0
  add("spc", c(len, x), wsum(s))
  d <- sample(2:8, 1); cf <- round(rnorm(d + 1), 3); cf[1] <- cf[1] + 2
  r <- roots(cf)
  add("rtr", c(d + 1, cf), wsum(Re(r))); add("rti", c(d + 1, cf), wsum(Im(r)))
  nz <- sample(0:3, 1); npp <- sample(1:4, 1)
  zr <- round(runif(nz, -0.9, 0.9), 3); zi <- round(runif(nz, 0.1, 0.9), 3); pr <- round(runif(npp, -0.9, 0.9), 3); pim <- round(runif(npp, 0.1, 0.9), 3); g <- runif(1, 0.5, 2)
  z <- c(complex(real = zr, imaginary = zi), complex(real = zr, imaginary = -zi)); p <- c(complex(real = pr, imaginary = pim), complex(real = pr, imaginary = -pim))
  ar <- as.Arma(Zpg(zero = z, pole = p, gain = g))
  add("zb", c(nz, npp, g, zr, zi, pr, pim), wsum(ar$b)); add("za", c(nz, npp, g, zr, zi, pr, pim), wsum(ar$a))
}

# analog designs (plane "s"): args as design, fn "sb"/"sa"
set.seed(20270104)
for (kind in 0:3) for (ty in 0:3) for (rep in 1:3) {
  n <- sample(if (ty >= 2) 2:4 else 2:6, 1); two <- ty >= 2
  w <- if (two) { w1 <- runif(1, 0.5, 2); c(w1, w1 + runif(1, 0.5, 3)) } else runif(1, 0.5, 4)
  rp <- runif(1, 0.3, 3); rs <- runif(1, 25, 60)
  f <- switch(kind + 1, butter(n, w, tys[ty + 1], "s"), cheby1(n, rp, w, tys[ty + 1], "s"), cheby2(n, rs, w, tys[ty + 1], "s"), ellip(n, rp, rs, w, tys[ty + 1], "s"))
  add("sb", c(kind, ty, n, rp, rs, length(w), w), wsum(f$b)); add("sa", c(kind, ty, n, rp, rs, length(w), w), wsum(f$a))
}
# higher orders, single cut-off
for (kind in 0:3) for (ty in 0:1) for (rep in 1:3) {
  n <- sample(7:10, 1); w <- runif(1, 0.1, 0.8); rp <- runif(1, 0.3, 3); rs <- runif(1, 25, 60)
  f <- switch(kind + 1, butter(n, w, tys[ty + 1]), cheby1(n, rp, w, tys[ty + 1]), cheby2(n, rs, w, tys[ty + 1]), ellip(n, rp, rs, w, tys[ty + 1]))
  add("db", c(kind, ty, n, rp, rs, 1, w), wsum(f$b)); add("da", c(kind, ty, n, rp, rs, 1, w), wsum(f$a))
}
# filtfilt with any coefficients: args (nb, na, len, b..., a..., x...); sinc and polyval: args (n)/(nb, zr, zi, b...)
for (rep in 1:25) {
  nb <- sample(1:6, 1); na <- sample(1:4, 1); len <- sample(10:50, 1)
  b <- round(rnorm(nb), 3); a <- c(1, round(runif(na - 1, -0.25, 0.25), 3)); x <- round(rnorm(len), 3)
  add("ffl", c(nb, na, len, b, a, x), wsum(filtfilt(b, a, x)))
  zr <- runif(1, -1.5, 1.5); zi <- runif(1, -1.5, 1.5); pv <- polyval(b, complex(real = zr, imaginary = zi))
  add("pvr", c(nb, zr, zi, b), Re(pv)); add("pvi", c(nb, zr, zi, b), Im(pv))
  v <- runif(1, -4, 4); add("snc", v, sinc(v))
}
add("snc", 0, 1)
emit("signaldsp", "signal", list(cases))
