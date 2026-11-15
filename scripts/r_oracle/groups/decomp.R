# base R's decompositions: qr (LINPACK, limited pivoting), lm.fit, svd, eigen of a general matrix,
# chol, det, solve, and an LDL' built from chol. Matrices are column-major in the arguments.
#   qr_*:   (n, p, x...)           ->  "qr_qr" (n*rank: the columns past the rank are rounding noise), "qr_aux" (rank), "qr_pivot" (p, 0-based), "qr_rank" (one value)
#   lmfit_*: (n, p, x..., y...)    ->  "lmfit_coef" (p, NaN aliased), "lmfit_res" (n), "lmfit_eff" (n)
#   svd_*:  (m, n, x...)           ->  "svd_d" (min), "svd_u" (|U|, m*k), "svd_v" (|V|, n*k): U and V only when the values are separated
#   eig:    (n, x..., i, re, im)   ->  "eig_match" 0 when a computed eigenvalue is within tolerance, "eig_resid" 0 for residuals
#   linear: (n, x..., b...)        ->  "chol" (upper R), "solve", "det", "ldlt_l", "ldlt_d" (SPD matrices)
set.seed(20261115)
cases <- list()
add <- function(fn, args, want, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = abs)
vec <- function(name, args, v, abs = 1e-12) {
  add(paste0("len:", name), args, length(v))
  for (i in seq_along(v)) add(paste0("v:", name), c(args, i - 1), v[i], abs)
}
shapes <- list(c(3, 1), c(4, 2), c(5, 3), c(6, 3), c(8, 5), c(2, 2), c(7, 4), c(5, 5), c(10, 2))
mats <- list()
for (s in shapes) for (k in 1:3) {
  x <- matrix(round(rnorm(s[1] * s[2]), 4), s[1], s[2])
  if (k == 2 && s[2] >= 3) x[, 3] <- x[, 1] + x[, 2]
  if (k == 3 && s[2] >= 2) x[, 2] <- 0
  mats[[length(mats) + 1]] <- x
}
for (x in mats) {
  n <- nrow(x); p <- ncol(x)
  q <- qr(x)
  a <- c(n, p, x)
  vec("qr_qr", a, c(q$qr[, seq_len(q$rank), drop = FALSE])); vec("qr_aux", a, q$qraux[seq_len(q$rank)]); vec("qr_pivot", a, q$pivot - 1)
  add("qr_rank", c(a, 0), q$rank)
  y <- round(rnorm(n), 4)
  f <- lm.fit(x, y)
  a2 <- c(n, p, x, y)
  vec("lmfit_coef", a2, as.numeric(ifelse(is.na(f$coefficients), NaN, f$coefficients)))
  vec("lmfit_res", a2, as.numeric(f$residuals)); vec("lmfit_eff", a2, as.numeric(f$effects))
}
for (x in mats) {
  m <- nrow(x); n <- ncol(x)
  sv <- svd(x)
  a <- c(m, n, x)
  vec("svd_d", a, sv$d)
  gaps <- if (length(sv$d) > 1) min(abs(diff(sv$d)) / sv$d[-length(sv$d)]) else 1
  if (min(sv$d) > 1e-8 && gaps > 1e-4) { vec("svd_u", a, abs(c(sv$u))); vec("svd_v", a, abs(c(sv$v))) }
}
sq <- list()
for (n in c(1, 2, 3, 4, 5, 6, 8)) for (k in 1:3) sq[[length(sq) + 1]] <- matrix(round(rnorm(n * n), 4), n, n)
sq[[length(sq) + 1]] <- matrix(c(0, 1, -1, 0), 2, 2)
sq[[length(sq) + 1]] <- matrix(c(0, 1, 0, 0, 0, 1, 1, 0, 0), 3, 3)
sq[[length(sq) + 1]] <- matrix(c(2, 0, 0, 0, 3, 0, 0, 0, 5), 3, 3)
sq[[length(sq) + 1]] <- matrix(c(1, 2, 3, 4, 5, 6, 7, 8, 10), 3, 3)
for (x in sq) {
  n <- nrow(x)
  ev <- eigen(x, only.values = TRUE)$values
  for (i in seq_along(ev)) add("eig_match", c(n, x, i - 1, Re(ev[i]), Im(ev[i])), 0, 1e-8)
  add("eig_resid", c(n, x, 0), 0, 1e-8)
}
for (n in c(1, 2, 3, 4, 6, 8)) for (k in 1:3) {
  g <- matrix(round(rnorm(n * n), 3), n, n)
  spd <- crossprod(g) + diag(n)
  b <- round(rnorm(n), 3)
  a <- c(n, spd, b)
  vec("chol", a, c(chol(spd))); vec("solve", a, solve(spd, b)); add("det", c(a, 0), det(spd))
  gen <- matrix(round(rnorm(n * n), 3), n, n)
  vec("solve_gen", c(n, gen, b), solve(gen, b)); add("det_gen", c(n, gen, b, 0), det(gen))
  ch <- chol(spd); L <- t(ch) / rep(diag(ch), each = n); D <- diag(ch)^2
  vec("ldlt_l", a, c(L)); vec("ldlt_d", a, D)
}
emit("decomp", character(), list(cases))
