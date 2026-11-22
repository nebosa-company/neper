# nleqslvfull: nleqslv with every method and global strategy (Newton and Broyden; none, cline, qline, gline, dbldog, pwldog), xscalm fixed and auto, allowSingular,
# on eleven fixed systems (libm-free: exp, sin and cos differ by an ulp between R and Neper and the finite-difference Jacobian amplifies that by 1e8) from random starts: the root, the termination code and the iteration, function and Jacobian counts, and scalex under auto scaling.
#   args: (system, method (0 Newton, 1 Broyden), global (0 none ... 5 pwldog), xscalm (0 fixed, 1 auto), allowSingular, index, x0 (n));
#   fn "x", "termcd", "iter", "nfcnt", "njcnt", "scalex".
suppressMessages(library(nleqslv))
s5 <- sqrt(5); s10 <- sqrt(10)
fs <- list(
  function(x) c(x[1] * x[1] + x[2] * x[2] - 4, exp(x[1]) + x[2] - 1),
  function(x) c(x[1] + x[2] + x[3] - 3, x[1] * x[1] + x[2] * x[2] + x[3] * x[3] - 5, exp(x[1]) + x[1] * x[2] - x[3] - 1),
  function(x) c(sin(x[1]) + x[2] - 1.2, x[1] - cos(x[2]) + 0.3),
  function(x) c(-400 * x[1] * (x[2] - x[1] * x[1]) - 2 * (1 - x[1]), 200 * (x[2] - x[1] * x[1])),
  function(x) c(1 / (1 + exp(-x[1])) + x[2] - 1.5, x[1] * x[2] - 0.5 - exp(-x[2])),
  function(x) { t <- x[2] - 2 * x[3]; u <- x[1] - x[4]; c(x[1] + 10 * x[2], s5 * (x[3] - x[4]), t * t, s10 * (u * u)) },
  function(x) c(x[1] + x[2] - 1, 2 * x[1] + 2 * x[2] - 2),
  function(x) { s <- x[1] + x[2] + x[3]; c(x[1] + s - 4, x[2] + s - 4, x[1] * x[2] * x[3] - 1) },
  function(x) c(10 * (x[2] - x[1] * x[1]), 1 - x[1]),
  function(x) c(-13 + x[1] + ((5 - x[2]) * x[2] - 2) * x[2], -29 + x[1] + ((x[2] + 1) * x[2] - 14) * x[2]),
  function(x) c(x[1] * x[1] + x[2] * x[2] - 4, x[1] * x[2] - 1),
  function(x) c(x[1] + x[2] + x[3] - 3, x[1] * x[1] + x[2] * x[2] + x[3] * x[3] - 5, x[1] * x[2] * x[3] - 1),
  function(x) c(1 / (1 + x[1] * x[1]) + x[2] - 1.5, x[1] * x[2] - 0.5 - x[2] * x[2]),
  function(x) c(1, 2))
nd <- c(2, 3, 2, 2, 2, 4, 2, 3, 2, 2, 2, 3, 2, 2)
rng <- c(1.5, 1.5, 1.5, 1.5, 1.5, 3, 2, 2, 3, 8, 2.5, 2.5, 2.5, 1)
gl <- c("none", "cline", "qline", "gline", "dbldog", "pwldog")
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = if (fn == "x" || fn == "scalex") 1e-10 else 0)
set.seed(20262107)
for (s in c(3, 5:13)) for (method in 0:1) for (g in 0:5) for (rep in 1:3) {
  xscalm <- if (rep == 3) 1 else 0
  allow <- if (s == 6 || s == 5 || s == 13) rep %% 2 else 0
  x0 <- runif(nd[s + 1], -rng[s + 1], rng[s + 1])
  r <- tryCatch(suppressWarnings(nleqslv(x0, fs[[s + 1]], method = c("Newton", "Broyden")[method + 1], global = gl[g + 1],
          xscalm = c("fixed", "auto")[xscalm + 1], control = list(allowSingular = allow == 1))), error = function(e) NULL)
  if (is.null(r) || any(!is.finite(r$x))) next
  hd <- c(s, method, g, xscalm, allow)
  for (j in seq_along(r$x)) add("x", c(hd, j - 1, x0), r$x[j])
  add("termcd", c(hd, 0, x0), r$termcd); add("iter", c(hd, 0, x0), r$iter)
  add("nfcnt", c(hd, 0, x0), r$nfcnt); add("njcnt", c(hd, 0, x0), r$njcnt)
  if (xscalm == 1) for (j in seq_along(r$x)) add("scalex", c(hd, j - 1, x0), r$scalex[j])
}
emit("nleqslvfull", "nleqslv", list(cases))
