# polspline lspec: fits (knots, atoms, coefficients, log-likelihood) and the evaluators dlspec, plspec, clspec.
#   "lspec" args: ny, odd, penalty (-1 default), minmass (user scale), maxknots (-1 missing), maxatoms (-1), maxdim (0 missing),
#   updown, nknots_in, natoms_in, knots_in.., atoms_in.., nx, period[nx].., what, x
#   what: 0 nknots 1 natoms 2 logl 3 thetap[x] 4 knots[x] 5 thetak[x] 6 atoms[x] 7 mass[x] 8 minmass 9 penalty
#         11 dlspec(x) 12 mass at freq x 13 plspec(x) 14 clspec(lag x) 15 clspec(lag x, cov = FALSE)
#   "pgram" args: n, data[n].., k  ->  Mod(fft(data))^2 / (n 2 pi) at index k
suppressMessages(library(polspline))
cases <- list()
set.seed(20261122)
nreps <- 0
ar1 <- function(n, phi) as.numeric(filter(rnorm(n + 50), phi, method = "recursive"))[51:(n + 50)]
configs <- list(
  list(n = 128, kind = "ar", phi = 0.7),
  list(n = 129, kind = "ar", phi = -0.5),
  list(n = 200, kind = "sin", phi = 0.3),
  list(n = 180, kind = "ar", phi = 0.8, maxknots = 3),
  list(n = 150, kind = "ar", phi = 0.5, maxdim = 7),
  list(n = 160, kind = "ar", phi = 0.6, updown = 1),
  list(n = 140, kind = "ar", phi = 0.4, penalty = 2),
  list(n = 256, kind = "sin2", phi = 0.5),
  list(n = 100, kind = "ar", phi = 0.9),
  list(n = 120, kind = "ar", phi = 0.6, knots = c(0.4, 1.2)),
  list(n = 210, kind = "sin", phi = 0.2, atoms = 1.2566370614359172),
  list(n = 300, kind = "ar", phi = 0.7, maxatoms = 0),
  list(n = 160, kind = "ar", phi = 0.7, route = "period"),
  list(n = 157, kind = "sin2", phi = 0.1, route = "period")
)
add <- function(pre, what, x, v, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("lspec", c(pre, what, x), as.numeric(v), rel = rel, abs = abs)
for (cf in configs) {
  n <- cf$n
  tt <- 1:n
  x <- switch(cf$kind, ar = ar1(n, cf$phi), sin = ar1(n, cf$phi) + 2 * sin(2 * pi * tt * 0.2), sin2 = ar1(n, cf$phi) + 1.5 * sin(2 * pi * tt * 0.13) + sin(pi * tt))
  args <- list()
  per <- NULL
  if (identical(cf$route, "period")) {
    p0 <- Mod(fft(x))^2 / (n * 2 * pi)
    p0 <- p0[1:floor((n + 2) / 2)]
    args$period <- p0[-1]
    odd <- n %% 2 == 1
    args$odd <- odd
  } else args$data <- x
  for (nm in c("maxknots", "maxatoms", "maxdim", "updown", "penalty", "knots", "atoms")) if (!is.null(cf[[nm]])) args[[nm]] <- cf[[nm]]
  f <- tryCatch(do.call(lspec, args), error = function(e) NULL)
  if (is.null(f)) next
  # a fit that R itself changes under a 1e-13 relative nudge of the periodogram is a numerical coin flip: skip it
  p1 <- if (identical(cf$route, "period")) c(1, args$period) else { q <- Mod(fft(x))^2 / (n * 2 * pi); q[1:floor((length(q) + 2) / 2)] }
  odd1 <- if (identical(cf$route, "period")) isTRUE(args$odd) else n %% 2 == 1
  stable <- TRUE
  for (s in 1:3) {
    a2 <- args
    a2$data <- NULL
    a2$period <- (p1 * (1 + 1e-13 * sin(s * 7.3 * seq_along(p1))))[-1]
    a2$odd <- odd1
    a2$minmass <- f$minmass
    g <- tryCatch(do.call(lspec, a2), error = function(e) NULL)
    if (is.null(g) || g$nknots != f$nknots || g$natoms != f$natoms || abs(g$logl - f$logl) > 1e-6 * abs(f$logl)) stable <- FALSE
  }
  if (!stable) { message("unstable fit skipped: n=", n, " kind=", cf$kind); next }
  if (identical(cf$route, "period")) {
    ny <- 2 * length(args$period); if (isTRUE(args$odd)) ny <- ny + 1
    pp <- c(1, args$period)
  } else {
    ny <- n
    pp <- Mod(fft(x))^2 / (n * 2 * pi); pp <- pp[1:floor((length(pp) + 2) / 2)]
  }
  odd <- ny %% 2 == 1
  nx <- length(pp)
  nreps <- nreps + 1
  pre <- c(ny, as.numeric(odd), if (is.null(cf$penalty)) -1 else cf$penalty,
           if (is.null(args$minmass)) { if (!is.null(args$data)) var(x) * (-log(1 - 0.95^(1 / nx)) - 1) / ny else mean(pp[2:nx]) * 2 * pi * (-log(1 - 0.95^(1 / nx)) - 1) / ny } else args$minmass,
           if (is.null(cf$maxknots)) -1 else cf$maxknots, if (is.null(cf$maxatoms)) -1 else cf$maxatoms, if (is.null(cf$maxdim)) 0 else cf$maxdim,
           if (is.null(cf$updown)) 3 else cf$updown,
           length(cf$knots), length(cf$atoms), cf$knots, cf$atoms, nx, pp)
  add(pre, 0, 0, f$nknots, 0, 0); add(pre, 1, 0, f$natoms, 0, 0)
  add(pre, 2, 0, f$logl); add(pre, 8, 0, f$minmass); add(pre, 9, 0, f$penalty)
  for (i in 1:4) add(pre, 3, i - 1, f$thetap[i])
  if (f$nknots > 0) for (i in 1:f$nknots) { add(pre, 4, i - 1, f$knots[i]); add(pre, 5, i - 1, f$thetak[i]) }
  if (f$natoms > 0) for (i in 1:f$natoms) { add(pre, 6, i - 1, f$atoms[i]); add(pre, 7, i - 1, f$mass[i]) }
  fr <- c(0, 0.3, 1, 2.2, pi, 4, -0.7, 7)
  if (f$natoms > 0) fr <- c(fr, f$atoms[1])
  for (q in fr) add(pre, 11, q, dlspec(q, f)$d)
  for (q in fr) { mm <- dlspec(q, f)$m; if (!is.na(mm)) add(pre, 12, q, mm, 1e-12, 0) }
  for (q in c(-3, -1.2, -0.2, 0, 0.5, 1.5, 3)) add(pre, 13, q, plspec(q, f), 1e-9, 1e-12)
  if (f$natoms > 0) add(pre, 13, -f$atoms[1], plspec(-f$atoms[1], f), 1e-9, 1e-12)
  c0 <- clspec(0:6, f)
  for (l in 0:6) add(pre, 14, l, c0[l + 1], 1e-9, 1e-11 * abs(c0[1]))
  c1 <- clspec(0:6, f, cov = FALSE)
  for (l in 0:6) add(pre, 15, l, c1[l + 1], 1e-9, 1e-11)
}
# the periodogram the data route builds
for (n in c(64, 65, 100, 129)) {
  x <- rnorm(n) + sin(1:n)
  p0 <- Mod(fft(x))^2 / (n * 2 * pi)
  p0 <- p0[1:floor((n + 2) / 2)]
  for (k in seq(0, length(p0) - 1, by = 3))
    cases[[length(cases) + 1]] <- case("pgram", c(n, x, k), p0[k + 1], rel = 1e-9, abs = 1e-12 * max(p0))
}
message("fits: ", nreps)
emit("polspline_lspec", "polspline", list(cases))
