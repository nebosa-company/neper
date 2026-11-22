# rootsolvefull: rootSolve::steady (stode) and jacobian.full on five ODE systems written with products and quotients only, so Neper evaluates the same operations in the same order.
#   "stode_y"     (sid, j, positive, rtol, atol, ctol, maxiter, np, parms (np), y0 (n)): coordinate j of steady(y0, func = f, parms)$y   1e-9 relative: the Newton iterates are deterministic, the tolerance covers libm-free rounding only
#   "stode_iter"  the same arguments: length(attr(out, "precis")), exact
#   "stode_ok"    the same arguments: attr(out, "steady") as 0 or 1, exact
#   "stode_prec"  the same arguments: the last element of attr(out, "precis"), absolute 1e-9 (a residual of rounding size)
#   "jacfull"     (sid, row, col, pert, np, parms (np), y (n)): jacobian.full(y, f, parms = parms, pert = pert)[row, col]   1e-9 relative
suppressMessages(library(rootSolve))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 0) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
fs <- list(
  function(t, y, p) list(c(p[1] * y[1] * (1 - y[1] / p[2]) - p[3] * y[1] * y[2], p[4] * p[3] * y[1] * y[2] - p[5] * y[2])),
  function(t, y, p) list(c(p[1] - (p[2] + 1) * y[1] + y[1] * y[1] * y[2], p[2] * y[1] - y[1] * y[1] * y[2])),
  function(t, y, p) list(c(p[1] - p[2] * y[1], p[2] * y[1] - p[3] * y[2] * y[2], p[3] * y[2] * y[2] - p[4] * y[3])),
  function(t, y, p) list(c(p[1] * (y[2] - y[1]), p[2] * y[1] - y[2] - y[1] * y[3], y[1] * y[2] - p[3] * y[3])),
  function(t, y, p) list(c(p[1] - p[3] * y[1], p[3] * y[1] - p[1] * y[2] / (p[2] + y[2]),
                           p[1] * y[2] / (p[2] + y[2]) - p[3] * y[3] - y[3] * y[4], y[3] * y[4] - p[3] * y[4] + 0.05)))
nd <- c(2, 2, 3, 3, 4)
mkp <- function(s) switch(s + 1,
  c(1.2, 10, 0.4, 0.6, 0.5) * runif(5, 0.8, 1.2), c(1, 2.5) * runif(2, 0.8, 1.2), c(2, 1, 0.5, 0.8) * runif(4, 0.8, 1.2),
  c(10, 28, 8 / 3) * runif(3, 0.9, 1.1), c(1.5, 0.7, 0.6) * runif(3, 0.8, 1.2))
set.seed(20262611)
for (rep in 1:150) {
  s <- (rep - 1) %% 5; p <- round(mkp(s), 4); n <- nd[s + 1]
  y0 <- switch(s + 1, runif(2, 0.5, 6), runif(2, 0.5, 3), runif(3, 0.2, 3), runif(3, 2, 12) * c(1, 1, 2), runif(4, 0.2, 3))
  y0 <- round(y0, 3)
  pos <- rep %% 3 == 0; rt <- c(1e-6, 1e-8, 1e-4)[rep %% 3 + 1]; at <- c(1e-8, 1e-10, 1e-6)[(rep %/% 3) %% 3 + 1]; ct <- c(1e-8, 1e-10, 1e-6)[(rep %/% 9) %% 3 + 1]
  mi <- c(100, 20, 6)[(rep %/% 5) %% 3 + 1]
  r <- tryCatch(suppressWarnings(steady(y0, func = fs[[s + 1]], parms = p, method = "stode", positive = pos, rtol = rt, atol = at, ctol = ct, maxiter = mi)), error = function(e) NULL)
  if (is.null(r) || any(!is.finite(r$y))) next
  pre <- attr(r, "precis"); a <- c(s, 0, as.numeric(pos), rt, at, ct, mi, length(p), p, y0)
  for (j in seq_len(n)) { a[2] <- j - 1; add("stode_y", a, r$y[j]) }
  add("stode_iter", a, length(pre), 0, 0); add("stode_ok", a, as.numeric(attr(r, "steady")), 0, 0)
  add("stode_prec", a, pre[length(pre)], 0, 1e-9)
  pert <- c(1e-8, 1e-6, 1e-4)[rep %% 3 + 1]
  J <- jacobian.full(y0, fs[[s + 1]], parms = p, pert = pert)
  for (i in seq_len(n)) for (j in seq_len(n)) add("jacfull", c(s, i - 1, j - 1, pert, length(p), p, y0), J[i, j])
}
# multiroot(f, start) is steady on dy = f(x): sid 5 + s is the s-th system of nleqslvpkg (sin, cos and exp inside, so the libm of R and Neper meet in a finite-difference Jacobian):
#   "stode_y", "stode_iter", "stode_prec" as above on multiroot's root, iter and estim.precis; "mroot_f" (same args): f.root[j], absolute 1e-8
#   the root carries 1e-7 relative and 1e-7 absolute: the 1e-8 perturbation turns a last-bit libm difference into a 1e-8 relative difference in the Jacobian, and the stop (ctol 1e-8) leaves that in the root
mfs <- list(
  function(x) c(x[1]^2 + x[2]^2 - 4, exp(x[1]) + x[2] - 1),
  function(x) c(x[1] + x[2] + x[3] - 3, x[1]^2 + x[2]^2 + x[3]^2 - 5, exp(x[1]) + x[1] * x[2] - x[3] - 1),
  function(x) c(sin(x[1]) + x[2] - 1.2, x[1] - cos(x[2]) + 0.3),
  function(x) c(-400 * x[1] * (x[2] - x[1]^2) - 2 * (1 - x[1]), 200 * (x[2] - x[1]^2)),
  function(x) c(1 / (1 + exp(-x[1])) + x[2] - 1.5, x[1] * x[2] - 0.5 - exp(-x[2])))
mnd <- c(2, 3, 2, 2, 2)
set.seed(20262612)
for (rep in 1:120) {
  s <- (rep - 1) %% 5; n <- mnd[s + 1]; x0 <- round(runif(n, -1.5, 1.5), 3)
  rt <- c(1e-6, 1e-8, 1e-4)[rep %% 3 + 1]; at <- c(1e-8, 1e-10, 1e-6)[(rep %/% 3) %% 3 + 1]; ct <- c(1e-8, 1e-10, 1e-6)[(rep %/% 9) %% 3 + 1]; mi <- c(100, 30, 8)[(rep %/% 5) %% 3 + 1]
  r <- tryCatch(suppressWarnings(multiroot(mfs[[s + 1]], x0, rtol = rt, atol = at, ctol = ct, maxiter = mi)), error = function(e) NULL)
  if (is.null(r) || any(!is.finite(r$root)) || any(!is.finite(r$f.root))) next
  # keep only runs R itself reproduces under last-bit noise in f (a relative 2e-16 pseudo-random change): where the iteration is chaotic the libm of Neper cannot be expected to follow it
  fn2 <- function(x) mfs[[s + 1]](x) * (1 + 2.2e-16 * sin(1e3 * sum(x)))
  r2 <- tryCatch(suppressWarnings(multiroot(fn2, x0, rtol = rt, atol = at, ctol = ct, maxiter = mi)), error = function(e) NULL)
  if (r$iter >= mi || is.null(r2) || r2$iter != r$iter || max(abs(r2$root - r$root)) > 1e-9 * (1 + max(abs(r$root)))) next
  a <- c(5 + s, 0, 0, rt, at, ct, mi, 0, x0)
  for (j in seq_len(n)) { a[2] <- j - 1; add("stode_y", a, r$root[j], 1e-7, 1e-7); add("mroot_f", a, r$f.root[j], 0, 1e-8) }
  add("stode_iter", a, r$iter, 0, 0); add("stode_prec", a, r$estim.precis, 0, 1e-8)
}
emit("rootsolvefull", "rootSolve", list(cases))
