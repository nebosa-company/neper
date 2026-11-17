# pracma: trapz, cumtrapz, polyval, polyfit, findpeaks, rref, primes, factors, gcd, nchoosek, cross.
#   args vary by fn:
#   "trapz" "cumtrapz" (cumulative values weighted by position): (n, x..., y...)
#   "polyfit" (deg, n, x..., y...) -> coefficient index k = c(0..) in the first slot after: args (deg, k, n, x..., y...)   "polyval": (x, coefficients...)
#   "fp_count" "fp_sum" (findpeaks): (nups, ndowns, minh, mindist, thr, npeaks, sortstr, n, x...); sum is as.vector(t(X)) weighted by 1..len
#   "rref" (nr, nc, A row-major...) -> weighted sum of the result; "primes" (n) -> count; "factors" (n) -> sum and count as two cases "fsum" "fcnt"
#   "gcd" (a, b, which: 0 g, 1 c, 2 d); "nchoosek" (n, k); "cross" (x1..3, y1..3, component)
suppressMessages(library(pracma))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-10)
set.seed(20261206)
for (rep in 1:10) {
  n <- sample(8:25, 1); x <- sort(runif(n, 0, 10)); y <- sin(x) + 0.3 * rnorm(n)
  add("trapz", c(n, x, y), trapz(x, y))
  add("cumtrapz", c(n, x, y), sum(as.vector(cumtrapz(x, y)) * seq_len(n)))
  deg <- sample(1:4, 1); co <- polyfit(x, y, deg)
  for (k in seq_along(co)) add("polyfit", c(deg, k - 1, n, x, y), co[k], rel = 1e-7)
  add("polyval", c(1.7, co), polyval(co, 1.7))
  nu <- sample(1:2, 1); nd <- sample(1:2, 1); mp <- sample(1:3, 1)
  z <- round(cumsum(rnorm(40)), 1)
  for (ss in 0:1) {
    pk <- findpeaks(z, nups = nu, ndowns = nd, minpeakheight = -1, minpeakdistance = mp, threshold = 0, npeaks = 0, sortstr = ss == 1)
    a <- c(nu, nd, -1, mp, 0, 0, ss, 40, z)
    add("fp_count", a, if (is.null(pk)) 0 else nrow(pk))
    if (!is.null(pk)) add("fp_sum", a, sum(as.vector(t(pk)) * seq_len(length(pk))))
  }
  A <- matrix(sample(-4:6, 12, replace = TRUE), 3, 4)
  if (rep %% 2 == 0) A[3, ] <- A[1, ] + A[2, ]
  R <- rref(A); add("rref", c(3, 4, as.vector(t(A))), sum(as.vector(t(R)) * seq_len(12)))
  nn <- sample(10:3000, 1)
  add("primes", nn, length(primes(nn)))
  m <- sample(4:100000, 1); f <- factors(m)
  add("fsum", m, sum(f)); add("fcnt", m, length(f))
  a1 <- sample(-60:200, 1); b1 <- sample(1:150, 1); g <- gcd(a1, b1, extended = TRUE)
  add("gcd", c(a1, b1, 0), g$g); add("gcd", c(a1, b1, 1), g$c); add("gcd", c(a1, b1, 2), g$d)
  nk <- sample(5:30, 1); add("nchoosek", c(nk, sample(0:nk, 1)), 0)
  xx <- rnorm(3); yy <- rnorm(3); cr <- cross(xx, yy)
  for (c3 in 0:2) add("cross", c(xx, yy, c3), cr[c3 + 1])
}
for (rep in 1:12) {
  n <- sample(5:14, 1); xs <- sort(runif(n, 0, 10)); ys <- cumsum(rnorm(n))
  if (rep %% 3 == 0) ys <- sort(ys)
  xq <- runif(4, min(xs), max(xs))
  for (q in xq) add("pchip", c(n, xs, ys, q), pchip(xs, ys, q))
  id <- (rep - 1) %% 5
  f <- list(sin, function(x) exp(-x^2), function(x) 1 / (1 + x^2), sqrt, function(x) cos(5 * x) * exp(-x))[[id + 1]]
  lo <- if (id == 3) 0 else runif(1, -2, 0); hi <- runif(1, 0.5, 3)
  add("quadgk", c(id, lo, hi, 1e-8), quadgk(f, lo, hi, tol = 1e-8))
  add("quadgk", c(id, hi, lo, 1e-5), quadgk(f, hi, lo, tol = 1e-5))
  add("integral", c(id, lo, hi), integral(f, lo, hi))
}
for (rep in 1:12) {
  n <- sample(1:7, 1); xx <- runif(1, -0.95, 0.95)
  add("legendre", c(n, xx), sum(as.vector(legendre(n, xx)) * seq_len(n + 1)))
  add("chebval", c(n, xx), chebPoly(n, xx))
  ch <- chebPoly(n); for (k in 1:(n + 1)) add("cheb", c(n, k - 1), ch[n + 1, k])
  rts <- sort(runif(3, -3, 3)); 
  pcf <- Reduce(function(a, r) c(a, 0) - r * c(0, a), rts, 1)
  x0 <- runif(1, -4, 4)
  lg <- tryCatch(laguerre(pcf, x0), error = function(e) NA, warning = function(w) NA)
  if (is.finite(lg)) add("laguerre", c(length(pcf), x0, pcf), lg)
}
for (rep in 1:20) {
  n <- sample(2:7, 1); rt <- sort(round(runif(n, -3, 3), 3)); co <- Reduce(function(a, r) c(a, 0) - r * c(0, a), rt, 1) * runif(1, 0.5, 3)
  rr <- sort(Re(roots(co)))
  add("roots", c(length(co), co), sum(rr * seq_along(rr)))
}
for (rep in 1:20) {
  na <- sample(2:6, 1); nb <- sample(2:5, 1); pa <- round(rnorm(na), 3); pb <- round(rnorm(nb), 3); pb[1] <- pb[1] + 2 * sign(pb[1] + 0.01)
  cv <- conv(pa, pb); add("conv", c(na, nb, pa, pb), sum(cv * seq_along(cv)))
  if (na >= nb) { dv <- deconv(pa, pb); add("deconvq", c(na, nb, pa, pb), sum(dv$q * seq_along(dv$q))); add("deconvr", c(na, nb, pa, pb), sum(dv$r * seq_along(dv$r))) }
  pi_ <- polyint(pa, 1.5); add("polyint", c(na, nb, pa, pb), sum(pi_ * seq_along(pi_)))
}
fs <- list(function(x) x^3 - 2*x - 5, function(x) cos(x) - x, function(x) exp(x) - 3, function(x) x*exp(x) - 1, function(x) log(x) + x - 2)
for (rep in 1:20) {
  id <- (rep - 1) %% 5; x0 <- c(2, 1, 0.5, 1, 1.5)[id + 1] + runif(1, 0, 1)
  nr <- newtonRaphson(fs[[id + 1]], x0)
  add("nr_root", c(id, x0), nr$root); add("nr_iter", c(id, x0), nr$niter); add("nr_prec", c(id, x0), nr$estim.prec)
}
fq <- list(sin, function(x) exp(-x^2), function(x) 1 / (1 + x^2), sqrt, function(x) cos(5 * x) * exp(-x))
for (rep in 1:15) {
  id <- (rep - 1) %% 5; lo <- if (id == 3) 0 else runif(1, -2, 0); hi <- runif(1, 0.5, 3)
  rb <- suppressWarnings(romberg(fq[[id + 1]], lo, hi, maxit = 12))
  add("romb_v", c(id, lo, hi), rb$value); add("romb_it", c(id, lo, hi), rb$iter)
}
for (rep in 1:20) {
  id <- (rep - 1) %% 5; lo <- if (id == 3) 0 else runif(1, -2, 0); hi <- runif(1, 0.5, 3)
  add("quadl", c(id, lo, hi, 1e-8), quadl(fq[[id + 1]], lo, hi, tol = 1e-8))
  add("quadl", c(id, hi, lo, 1e-6), quadl(fq[[id + 1]], hi, lo, tol = 1e-6))
}
fzs <- list(function(x) cos(x) - x, function(x) x^3 - 2 * x - 5, function(x) exp(x) - 3, function(x) x * exp(-x) - 0.2, function(x) sin(x) - 0.5 * x)
fzb <- list(c(0, 1), c(2, 3), c(0, 2), c(0, 1), c(1, 3))
for (rep in 1:10) { id <- (rep - 1) %% 5; b <- fzb[[id + 1]] + c(-1, 1) * runif(1, 0, 0.1) * (rep > 5); add("fzero", c(id, b, 1e-12), fzero(fzs[[id + 1]], b, tol = 1e-12)$x) }
for (rep in 1:18) {
  n <- sample(4:12, 1); xs <- sort(runif(n, 0, 10)); ys <- cumsum(rnorm(n)); xq <- c(min(xs), max(xs), runif(4, min(xs), max(xs)))
  for (q in xq) for (m in 0:4) add("interp1", c(m, n, xs, ys, q), interp1(xs, ys, q, method = c("linear", "nearest", "spline", "constant", "cubic")[m + 1]), rel = 1e-8)
}
# nchoosek reference values are filled from R directly
cases <- lapply(cases, function(cs) { if (cs$fn == "nchoosek") cs$want <- choose(cs$args[1], cs$args[2]); cs })
for (rep in 1:30) {
  n <- sample(20:60, 1); tt <- round(cumsum(rnorm(n)), 4); fl <- sample(c(5, 7, 9, 11), 1); fo <- sample(2:4, 1); dord <- sample(0:min(2, fo), 1)
  s <- savgol(tt, fl, fo, dord)
  for (i in sample(n, 5)) add("savgol", c(fl, fo, dord, i - 1, n, tt), s[i])
}
for (rep in 1:25) {
  ra <- sample(1:4, 1); ca <- sample(1:4, 1); rb <- sample(1:3, 1); cb <- sample(1:4, 1)
  A <- matrix(round(rnorm(ra * ca), 3), ra, ca); B <- matrix(round(rnorm(rb * cb), 3), rb, cb); K <- kron(A, B)
  for (i in sample(nrow(K), min(3, nrow(K)))) for (j in sample(ncol(K), min(2, ncol(K)))) add("kron", c(ra, ca, rb, cb, i - 1, j - 1, as.vector(t(A)), as.vector(t(B))), K[i, j])
  m <- sample(2:7, 1); n <- sample(2:7, 1); M <- matrix(round(rnorm(m * n), 3), m, n); P <- pinv(M)
  for (i in sample(n, min(2, n))) for (j in sample(m, min(2, m))) add("pinv", c(m, n, i - 1, j - 1, as.vector(t(M))), P[i, j])
}
for (rep in 1:30) {
  m <- sample(2:8, 1); n <- sample(2:8, 1); M <- matrix(round(rnorm(m * n), 3), m, n); sv <- svd(M)$d
  for (k in seq_along(sv)) add("sval", c(m, n, k - 1, as.vector(t(M))), sv[k])
  if (m == n) add("cond", c(m, n, 0, as.vector(t(M))), cond(M))
}
for (rep in 1:30) {
  n <- sample(2:6, 1); m <- n + sample(0:3, 1); r <- sample(1:n, 1)
  L <- matrix(round(rnorm(m * r), 2), m, r); R <- matrix(round(rnorm(r * n), 2), r, n); M <- L %*% R
  nl <- null(M); N <- if (is.null(nl)) matrix(0, n, n) else nl %*% t(nl); PN <- N
  oM <- orth(M); PO <- oM %*% t(oM)
  for (i in sample(n, min(2, n))) for (j in sample(n, min(2, n))) add("nullproj", c(m, n, i - 1, j - 1, as.vector(t(M))), PN[i, j])
  for (i in sample(m, min(2, m))) for (j in sample(m, min(2, m))) add("orthproj", c(m, n, i - 1, j - 1, as.vector(t(M))), PO[i, j])
}
# expm: (n, i, j, A row-major...) -> element (i, j) of expm(A) (zapsmall to 7 digits)
for (rep in 1:25) {
  n <- sample(2:5, 1); A <- matrix(round(rnorm(n * n, 0, 0.8), 2), n, n); E <- expm(A)
  for (i in sample(n, min(2, n))) for (j in sample(n, min(2, n))) cases[[length(cases) + 1]] <- case("expm", c(n, i - 1, j - 1, as.vector(t(A))), E[i, j], rel = 1e-9, abs = 1e-9)
}
# polyroots: (n, p...) -> count of distinct roots, total multiplicity, sum(mult Re), sum(mult Im^2)
set.seed(7)
for (rep in 1:25) {
  nr <- sample(1:3, 1); rts <- sample(c(-2, -1, 0.5, 1, 2, 3), nr + 1, TRUE); mu <- sample(1:3, length(rts), TRUE); p <- 1
  for (i in seq_along(rts)) for (m in seq_len(mu[i])) p <- conv(p, c(1, -rts[i]))
  if (rep %% 3 == 0) p <- conv(p, c(1, 0, 1))
  p <- p * sample(c(1, 2, -3), 1); pr <- polyroots(p); a <- c(length(p), p)
  cases[[length(cases) + 1]] <- case("pr_cnt", a, nrow(pr), rel = 1e-6, abs = 1e-6); cases[[length(cases) + 1]] <- case("pr_mult", a, sum(pr$mult), rel = 1e-6, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("pr_re", a, sum(pr$mult * Re(pr$root)), rel = 1e-6, abs = 1e-6); cases[[length(cases) + 1]] <- case("pr_im2", a, sum(pr$mult * Im(pr$root)^2), rel = 1e-6, abs = 1e-6)
}
# pinv by the singular value decomposition, matrices of any rank (a repeated column or row, or a zero one): "pinvs" args as "pinv"
for (rep in 1:30) {
  m <- sample(3:7, 1); n <- sample(3:7, 1); M <- matrix(round(rnorm(m * n), 3), m, n)
  if (rep %% 3 == 0 && n > 2) M[, n] <- M[, 1] + M[, 2] else if (rep %% 3 == 1 && m > 2) M[m, ] <- M[1, ] - M[2, ] else M[, 1] <- 0
  P <- pinv(M)
  for (i in sample(n, min(3, n))) for (j in sample(m, min(3, m))) add("pinvs", c(m, n, i - 1, j - 1, as.vector(t(M))), P[i, j])
}
# polyroot (R's cpoly, its root order): "prre"/"prim" args (length, root index, coefficients increasing powers)
for (rep in 1:60) {
  dg <- sample(2:9, 1); co <- round(rnorm(dg + 1), 3); if (rep %% 5 == 0) co[sample(dg, 1)] <- 0; if (co[dg + 1] == 0) co[dg + 1] <- 1
  rt <- tryCatch(polyroot(co), error = function(e) NULL); if (is.null(rt)) next
  for (k in seq_along(rt)) { add("prre", c(length(co), k - 1, co), Re(rt[k]), rel = 1e-8); cases[[length(cases) + 1]] <- case("prim", c(length(co), k - 1, co), Im(rt[k]), rel = 1e-8, abs = 1e-9) }
}
emit("pracma", "pracma", list(cases))
