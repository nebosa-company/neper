# deSolve: the fixed-step methods euler and rk4 against e.math.ode.
#   args: (system, h, steps, y0...)   system 0 Lotka-Volterra, 1 Lorenz, 2 logistic, 3 harmonic oscillator; fn "euler" "rk4": the final state weighted by component
suppressMessages(library(deSolve))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
fs <- list(
  function(t, y, p) list(c(1.1 * y[1] - 0.4 * y[1] * y[2], 0.1 * y[1] * y[2] - 0.4 * y[2])),
  function(t, y, p) list(c(10 * (y[2] - y[1]), y[1] * (28 - y[3]) - y[2], y[1] * y[2] - 8 / 3 * y[3])),
  function(t, y, p) list(c(0.7 * y[1] * (1 - y[1] / 10))),
  function(t, y, p) list(c(y[2], -4 * y[1] - 0.2 * y[2])))
y0s <- list(c(10, 5), c(1, 1, 1), c(0.5), c(1, 0))
set.seed(20261224)
for (rep in 1:24) {
  sy <- (rep - 1) %% 4 + 1; h <- c(0.01, 0.02, 0.05, 0.1)[sample(1:4, 1)]; steps <- sample(5:60, 1)
  y0 <- y0s[[sy]] * runif(length(y0s[[sy]]), 0.8, 1.2); times <- seq(0, steps * h, length.out = steps + 1)
  for (m in c("euler", "rk4")) {
    out <- ode(y0, times, fs[[sy]], NULL, method = m)
    last <- out[nrow(out), -1]
    add(m, c(sy - 1, h, steps, y0), sum(last * seq_along(last)))
  }
}
#   fn "ode23" "ode45" "rkf45" (rk45f) "rk45ck" "rk45dp6" "rk45e" "rk23" "rk34f": adaptive rk, output at requested times.
#   args: (system, rtol, atol, nt, times[nt]..., y0...); want: sum over rows r and states i of (r) * (i) * out[r, i] (1-based)
rkm <- list(ode23 = "ode23", ode45 = "ode45", rkf45 = rkMethod("rk45f"), rk45ck = rkMethod("rk45ck"),
            rk45dp6 = rkMethod("rk45dp6"), rk45e = rkMethod("rk45e"), rk23 = rkMethod("rk23"), rk34f = rkMethod("rk34f"))
set.seed(20261225)
for (rep in 1:16) {
  sy <- (rep - 1) %% 4 + 1
  rt <- 10^-sample(5:9, 1); at <- rt * 10^-sample(0:2, 1)
  nt <- sample(4:12, 1); times <- c(0, cumsum(runif(nt - 1, 0.2, 1.5))) * (if (sy == 2) 0.25 else 1)
  y0 <- y0s[[sy]] * runif(length(y0s[[sy]]), 0.8, 1.2)
  for (m in c(names(rkm), "lsoda", "lsode", "adams", "bdf")) {
    out <- suppressWarnings(ode(y0, times, fs[[sy]], NULL, method = if (m %in% c("lsoda", "lsode", "adams", "bdf")) m else rkm[[m]], rtol = rt, atol = at))
    st <- out[, -1, drop = FALSE]
    wt <- sum(outer(seq_len(nrow(st)), seq_len(ncol(st))) * st)
    add(m, c(sy - 1, rt, at, nt, times, y0), wt)
  }
}
#   stiff systems 4 (Van der Pol mu = 50) and 5 (Robertson) with lsoda only: exercises the Adams/BDF switch
fs2 <- list(function(t, y, p) list(c(y[2], 50 * (1 - y[1]^2) * y[2] - y[1])),
            function(t, y, p) list(c(-0.04 * y[1] + 1e4 * y[2] * y[3], 0.04 * y[1] - 1e4 * y[2] * y[3] - 3e7 * y[2]^2, 3e7 * y[2]^2)))
for (rep in 1:8) {
  sy <- (rep - 1) %% 2 + 5
  rt <- 10^-sample(4:8, 1); at <- rt * 10^-sample(0:3, 1)
  if (sy == 5) { y0 <- c(2, 0) * runif(1, 0.9, 1.1); times <- c(0, cumsum(runif(sample(4:9, 1), 5, 40))) }
  else { y0 <- c(1, 0, 0); times <- c(0, 10^seq(-1, sample(2:4, 1), length.out = sample(4:9, 1))) }
  nt <- length(times)
  for (m in c("lsoda", "lsode", "bdf")) {
    out <- suppressWarnings(ode(y0, times, fs2[[sy - 4]], NULL, method = m, rtol = rt, atol = at))
    st <- out[, -1, drop = FALSE]
    add(m, c(sy - 1, rt, at, nt, times, y0), sum(outer(seq_len(nrow(st)), seq_len(ncol(st))) * st))
  }
}
#   fn "lsoda_ev" "lsode_ev" "adams_ev": data-frame events (replace/add/multiply) merged into the output times.
#   args: (system, rtol, atol, hmax, nt, times[nt] merged, y0..., ne, (time, var, method, value) x ne); want as above
set.seed(20261226)
for (rep in 1:24) {
  sy <- (rep - 1) %% 4 + 1
  rt <- 10^-sample(5:8, 1); at <- rt * 10^-sample(0:2, 1)
  nt <- sample(5:9, 1); times <- c(0, cumsum(runif(nt - 1, 0.3, 1.2))) * (if (sy == 2) 0.25 else 1)
  y0 <- y0s[[sy]] * runif(length(y0s[[sy]]), 0.8, 1.2); ny <- length(y0)
  names(y0) <- paste0("y", seq_len(ny))
  ne <- sample(2:4, 1)
  et <- sort(unique(c(sample(times[-1], 1), runif(ne - 1, 0.1, 0.9) * max(times))))
  ev <- do.call(rbind, lapply(et, function(tt) { k <- sample(1:min(2, ny), 1); v <- sample(1:ny, k)
    data.frame(var = v, time = tt, value = NA_real_, method = sample(1:3, k, replace = TRUE)) }))
  for (r in seq_len(nrow(ev))) ev$value[r] <- c(y0[ev$var[r]] * runif(1, 0.5, 1.5), runif(1, -0.3, 0.3) * abs(y0[ev$var[r]]), runif(1, 0.6, 1.4))[ev$method[r]]
  hm <- max(diff(times))
  for (m in c("lsoda", "lsode", "adams", "vode")) {
    out <- suppressWarnings(ode(y0, times, fs[[sy]], NULL, method = m, rtol = rt, atol = at, events = list(data = ev)))
    st <- out[, -1, drop = FALSE]
    add(paste0(m, "_ev"), c(sy - 1, rt, at, hm, nrow(out), out[, 1], y0, nrow(ev), as.vector(t(as.matrix(ev[, c("time", "var", "method", "value")])))),
        sum(outer(seq_len(nrow(st)), seq_len(ncol(st))) * st))
  }
}
#   fn "lsodar_rows" "lsodar_troot" "lsodar_ind" "lsodar_nroot" "lsodar_val": lsodar with root functions g_k = y[idx_k] - level_k.
#   mode 0 stops at the first root; mode 1 events = list(func, root = TRUE); mode 2 adds terminalroot = 2.
#   args: (system, rtol, atol, nt, times[nt], y0..., mode, ng, (idx, level) x ng, evvar, eva, evb); the event is y[evvar] <- eva * y[evvar] + evb
set.seed(20261227)
nr <- 0
for (rep in 1:60) {
  if (nr >= 36) break
  sy <- (rep - 1) %% 4 + 1; mode <- ((rep - 1) %/% 4) %% 3
  rt <- 10^-sample(5:8, 1); at <- rt * 10^-sample(0:2, 1)
  nt <- sample(5:9, 1); times <- c(0, cumsum(runif(nt - 1, 0.3, 1.2))) * (if (sy == 2) 0.25 else 1)
  y0 <- y0s[[sy]] * runif(length(y0s[[sy]]), 0.8, 1.2); ny <- length(y0); names(y0) <- paste0("y", seq_len(ny))
  ng <- if (mode == 2) 2 else sample(1:2, 1)
  idx <- sample(1:ny, ng, replace = TRUE)
  base <- suppressWarnings(ode(y0, seq(0, max(times), length.out = 60), fs[[sy]], NULL, method = "lsoda"))
  level <- sapply(idx, function(i) runif(1, min(base[, i + 1]), max(base[, i + 1])) * 0.5 + 0.5 * mean(base[, i + 1]))
  evvar <- sample(1:ny, 1); eva <- runif(1, 0.6, 1.0); evb <- runif(1, -0.05, 0.05) * abs(y0[evvar])
  gfun <- function(t, y, p) y[idx] - level
  efun <- function(t, y, p) { y[evvar] <- eva * y[evvar] + evb; y }
  out <- tryCatch(suppressWarnings(
    if (mode == 0) ode(y0, times, fs[[sy]], NULL, method = "lsodar", rootfunc = gfun, rtol = rt, atol = at)
    else ode(y0, times, fs[[sy]], NULL, method = "lsodar", rootfunc = gfun, rtol = rt, atol = at,
             events = if (mode == 1) list(func = efun, root = TRUE) else list(func = efun, root = TRUE, terminalroot = 2))),
    error = function(e) NULL)
  if (is.null(out)) next
  st <- out[, -1, drop = FALSE]
  args <- c(sy - 1, rt, at, nt, times, y0, mode, ng, as.vector(rbind(idx, level)), evvar, eva, evb)
  tr <- attr(out, "troot"); ir <- if (mode == 0) attr(out, "iroot") else attr(out, "indroot")
  nrt <- if (mode == 0) (if (is.null(tr)) 0 else 1) else (if (is.null(attr(out, "nroot"))) 0 else attr(out, "nroot"))
  if (nrt > 100) next  # chattering root events: thousands of restarts, not a useful case
  nr <- nr + 1
  vr <- attr(out, "valroot"); nv <- length(vr) / ny
  add("lsodar_rows", args, sum(outer(seq_len(nrow(st)), seq_len(ncol(st))) * st))
  add("lsodar_troot", args, if (is.null(tr)) 0 else sum(seq_along(tr) * tr))
  add("lsodar_ind", args, if (is.null(ir)) 0 else if (mode == 0) max(which(ir == 1)) else sum(seq_along(ir) * ir))
  add("lsodar_nroot", args, nrt)
  add("lsodar_val", args, if (is.null(vr)) 0 else sum(outer(seq_len(ny), seq_len(min(nv, 100)), "*") * matrix(vr[seq_len(ny * min(nv, 100))], ny)))
}
emit("desolve", "deSolve", list(cases))
