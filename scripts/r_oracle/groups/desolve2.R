# deSolve, second group: dede (delay equations, lsoda with the Hermite history).
#   fn "dede": args (system, rtol, atol, tau, nt, times[nt], y0...); want: sum over rows r and states i of r * i * out[r, i]
#   systems 10 Hutchinson, 11 Mackey-Glass, 12 neutral with lagderiv; the history before t = tau is the constant y0.
suppressMessages(library(deSolve))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
wsum <- function(out) { st <- out[, -1, drop = FALSE]; sum(outer(seq_len(nrow(st)), seq_len(ncol(st))) * st) }
dfs <- list(
  function(t, y, p) { yt <- if (t < p$tau) p$h0[1] else lagvalue(t - p$tau, 1); list(c(1.5 * y[1] * (1 - yt / 2))) },
  function(t, y, p) { yt <- if (t < p$tau) p$h0[1] else lagvalue(t - p$tau, 1); list(c(0.2 * yt / (1 + yt^10) - 0.1 * y[1])) },
  function(t, y, p) {
    if (t < p$tau) { l <- p$h0; dl <- c(0, 0) } else { l <- lagvalue(t - p$tau); dl <- lagderiv(t - p$tau) }
    list(c(-y[1] + 0.5 * l[1] - 0.2 * dl[2], y[1] - 0.5 * y[2] + 0.3 * l[2])) })
for (sy in 10:12) {   # lag never reached: the one-step lsoda stepping alone
  y0 <- if (sy == 12) c(1, 0.5) else 0.5; times <- c(0, 0.7, 1.9, 3.1, 4.4)
  out <- suppressWarnings(dede(y0, times, dfs[[sy - 9]], list(tau = 1000, h0 = y0), method = "lsoda", rtol = 1e-8, atol = 1e-8))
  add("dede", c(sy, 1e-8, 1e-8, 1000, 5, times, y0), wsum(out))
}
set.seed(20261230)
for (rep in 1:24) {
  sy <- (rep - 1) %% 3 + 10
  rt <- 10^-sample(5:9, 1); at <- rt * 10^-sample(0:2, 1)
  tau <- runif(1, 0.4, 1.6) * (if (sy == 11) 3 else 1)
  nt <- sample(5:10, 1); times <- c(0, cumsum(runif(nt - 1, 0.5, 2.5)))
  y0 <- if (sy == 12) c(1, 0.5) * runif(2, 0.8, 1.2) else (if (sy == 11) 1.1 else 0.5) * runif(1, 0.8, 1.2)
  out <- suppressWarnings(dede(y0, times, dfs[[sy - 9]], list(tau = tau, h0 = y0), method = "lsoda", rtol = rt, atol = at))
  add("dede", c(sy, rt, at, tau, nt, times, y0), wsum(out))
}
#   fn "radau": args (system, rtol, atol, nt, times[nt], y0...); systems 0 Lotka-Volterra, 1 Lorenz, 2 logistic, 3 oscillator,
#   4 Van der Pol mu = 50, 5 Robertson, 6 Robertson as an index-1 DAE (mass diag(1,1,0)), 7 y1' = -y1 + y2^2 with 0 = 1 - y1^2 - y2 (mass diag(1,0)).
rfs <- list(
  function(t, y, p) list(c(1.1 * y[1] - 0.4 * y[1] * y[2], 0.1 * y[1] * y[2] - 0.4 * y[2])),
  function(t, y, p) list(c(10 * (y[2] - y[1]), y[1] * (28 - y[3]) - y[2], y[1] * y[2] - 8 / 3 * y[3])),
  function(t, y, p) list(c(0.7 * y[1] * (1 - y[1] / 10))),
  function(t, y, p) list(c(y[2], -4 * y[1] - 0.2 * y[2])),
  function(t, y, p) list(c(y[2], 50 * (1 - y[1]^2) * y[2] - y[1])),
  function(t, y, p) list(c(-0.04 * y[1] + 1e4 * y[2] * y[3], 0.04 * y[1] - 1e4 * y[2] * y[3] - 3e7 * y[2]^2, 3e7 * y[2]^2)),
  function(t, y, p) list(c(-0.04 * y[1] + 1e4 * y[2] * y[3], 0.04 * y[1] - 1e4 * y[2] * y[3] - 3e7 * y[2]^2, y[1] + y[2] + y[3] - 1)),
  function(t, y, p) list(c(-y[1] + y[2]^2, 1 - y[1]^2 - y[2])))
ry0 <- list(c(10, 5), c(1, 1, 1), c(0.5), c(1, 0), c(2, 0), c(1, 0, 0), c(1, 0, 0), c(0.6, 0.64))
set.seed(20261231)
for (rep in 1:40) {
  sy <- (rep - 1) %% 8 + 1
  rt <- 10^-sample(5:9, 1); at <- rt * 10^-sample(0:2, 1)
  nt <- sample(4:10, 1)
  times <- if (sy %in% c(6, 7)) c(0, 10^seq(-1, sample(2:4, 1), length.out = nt - 1)) else if (sy == 5) c(0, cumsum(runif(nt - 1, 5, 40))) else c(0, cumsum(runif(nt - 1, 0.2, 1.5))) * (if (sy == 2) 0.25 else 1)
  y0 <- ry0[[sy]] * (if (sy >= 6) 1 else runif(length(ry0[[sy]]), 0.9, 1.1))
  if (sy == 8) y0 <- c(0.6 * runif(1, 0.9, 1.1), 0); if (sy == 8) y0[2] <- 1 - y0[1]^2
  mass <- if (sy == 7) diag(c(1, 1, 0)) else if (sy == 8) diag(c(1, 0)) else NULL
  out <- suppressWarnings(radau(y0, times, rfs[[sy]], NULL, rtol = rt, atol = at, mass = mass))
  add("radau", c(sy - 1, rt, at, length(times), times, y0), wsum(out))
}
#   fn "vode22" (mf = 22, BDF with the internal Jacobian) and "vode10" (mf = 10, Adams, functional iteration, systems 0-3 only):
#   args as "radau" with systems 0-5
set.seed(20270101)
for (rep in 1:36) {
  sy <- (rep - 1) %% 6 + 1
  rt <- 10^-sample(5:9, 1); at <- rt * 10^-sample(0:2, 1)
  nt <- sample(4:10, 1)
  times <- if (sy == 6) c(0, 10^seq(-1, sample(2:4, 1), length.out = nt - 1)) else if (sy == 5) c(0, cumsum(runif(nt - 1, 5, 40))) else c(0, cumsum(runif(nt - 1, 0.2, 1.5))) * (if (sy == 2) 0.25 else 1)
  y0 <- ry0[[sy]] * (if (sy == 6) 1 else runif(length(ry0[[sy]]), 0.9, 1.1))
  for (mf in c(22, 10)) {
    if (mf == 10 && sy > 4) next
    out <- suppressWarnings(vode(y0, times, rfs[[sy]], NULL, rtol = rt, atol = at, mf = mf))
    add(paste0("vode", mf), c(sy - 1, rt, at, length(times), times, y0), wsum(out))
  }
}
#   fn "daspk": F(t, y, y') = 0 as y' - f(y) (systems 0-5) or the index-1 DAEs 6 and 7 of "radau" (algebraic rows 0 = f);
#   args (system, rtol, atol, nt, times[nt], y0..., dy0...) with dy0 = f(y0) (0 for algebraic components)
set.seed(20270102)
for (rep in 1:40) {
  sy <- (rep - 1) %% 8 + 1
  rt <- 10^-sample(5:9, 1); at <- rt * 10^-sample(0:2, 1)
  nt <- sample(4:9, 1)
  times <- if (sy %in% c(6, 7)) c(0, 10^seq(-1, sample(1:3, 1), length.out = nt - 1)) else if (sy == 5) c(0, cumsum(runif(nt - 1, 3, 20))) else c(0, cumsum(runif(nt - 1, 0.2, 1.5))) * (if (sy == 2) 0.25 else 1)
  y0 <- ry0[[sy]] * (if (sy >= 6) 1 else runif(length(ry0[[sy]]), 0.9, 1.1))
  if (sy == 8) { y0 <- c(0.6 * runif(1, 0.9, 1.1), 0); y0[2] <- 1 - y0[1]^2 }
  f0 <- rfs[[sy]](0, y0, NULL)[[1]]
  dy0 <- f0; if (sy == 7) dy0[3] <- 0; if (sy == 8) dy0[2] <- 0
  resf <- function(t, y, dy, p) { f <- rfs[[sy]](t, y, p)[[1]]; r <- dy - f; if (sy == 7) r[3] <- f[3]; if (sy == 8) r[2] <- f[2]; list(r) }
  out <- suppressWarnings(daspk(y0, times, parms = NULL, dy = dy0, res = resf, rtol = rt, atol = at))
  if (nrow(out) != length(times)) next   # DASPK itself gave up (singular iteration matrix): no oracle
  add("daspk", c(sy - 1, rt, at, length(times), times, y0, dy0), wsum(out))
}
emit("desolve2", "deSolve", list(cases))
