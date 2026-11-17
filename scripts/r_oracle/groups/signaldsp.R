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
emit("signaldsp", "signal", list(cases))
