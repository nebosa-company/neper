# gamlss diagnostics and centiles on design-matrix fits (RS, no smoothers, unit weights), families 0 NO 1 GA 3 WEI 4 BCCG.
# A scenario opens with a case whose args are the 20-number header (as the gamlss_fit group) followed by y (n), w (n), X0, X1, X2 (column-major), then xvar (n), newx (5),
# yval (5), the number of cut points and the cut points; the cases after it carry the header with fam 99 and read the same fit.
# header: fam, algo (0), n, p0, p1, p2, link kinds (4 identity, 5 log), out kind, out index, c.crit, n.cyc, 1, 20, autostep, n.inter, mu.step, sigma.step, nu.step
# out kinds: 30 residual summary (mean, var, skewness, kurtosis, Filliben), 31 wp() cubic coefficient, 32 worm band at z = -4 + 0.25 idx, 33 wp classes by n.inter (row * 2 + end),
#            34 wp panel coefficients by n.inter (row * 4 + k), 35 wp classes by cut points, 36 wp panel coefficients by cut points, 37 Q.stats z matrix (row * 6 + col),
#            38 Q.stats Q matrix, 39 Q.stats from residuals alone (row * 4 + col), 40 Q.stats z matrix by cut points, 41 centiles curve (cent * n + sorted i),
#            42 centiles percentage below, 43 centiles.pred centiles (cent * 5 + sorted j), 44 centiles.pred z-scores, 45 centiles.pred standard centiles (dev * 5 + sorted j)
suppressMessages(library(gamlss))
pdf(NULL)
cases <- list()
famobj <- list(NO, GA, PO, WEI, BCCG)
np_of <- c(2, 2, 1, 2, 3)
cent <- c(0.4, 2, 10, 25, 50, 75, 90, 98, 99.6)
dev <- c(-4, -3, -2, -1, 0, 1, 2, 3, 4)
mk <- function(fam, y, d, rhs, links, ninter, cuts, newx, rel = 1e-9) {
  n <- length(y)
  d$y <- y
  assign("dd", d, envir = globalenv())
  np <- np_of[fam + 1]
  ctl <- gamlss.control(trace = FALSE)
  lk <- c("identity", "log")[links - 3]
  fo <- do.call(famobj[[fam + 1]], as.list(lk[seq_len(np)]))
  a <- list(formula = as.formula(paste("y ~", rhs[1])), family = fo, data = quote(dd), control = ctl, trace = FALSE)
  if (np > 1) a$sigma.formula <- as.formula(paste("~", rhs[2]))
  if (np > 2) a$nu.formula <- as.formula(paste("~", rhs[3]))
  m <- suppressWarnings(eval(as.call(c(list(as.name("gamlss")), a))))
  X <- lapply(seq_len(np), function(k) model.matrix(as.formula(paste("~", rhs[k])), d))
  p <- c(vapply(X, ncol, 1), rep(0, 3 - np))
  lks <- c(links, 4)[1:3]
  xv <- d$x1
  yval <- y[c(3, 9, 15, 21, 27)]
  hdr <- function(f, kind, idx) c(f, 0, n, p, lks, kind, idx, 0.001, 20, 1, 20, 1, ninter, 1, 1, 1)
  data <- c(y, rep(1, n), unlist(lapply(X, as.vector)), xv, newx, yval, length(cuts), cuts)
  first <- TRUE
  add <- function(kind, idx, want, r = rel) {
    h <- hdr(if (first) fam else 99, kind, idx)
    cases[[length(cases) + 1]] <<- case("diag", if (first) c(h, data) else h, want, rel = r, abs = 1e-11)
    first <<- FALSE
  }
  rs <- resid(m)
  qq <- as.data.frame(qqnorm(rs, plot = FALSE))
  m1 <- mean(rs); m2 <- var(rs); m3 <- sum((rs - m1)^3) / n; m4 <- sum((rs - m1)^4) / n
  sm <- c(m1, m2, sign(m3) * sqrt(abs(m3^2 / m2^3)), m4 / m2^2, cor(qq$y, qq$x))
  for (j in 1:5) add(30, j - 1, sm[j])
  cf <- wp(m)
  for (j in 1:4) add(31, j - 1, unname(cf[j]))
  z <- seq(-4, 4, 0.25)
  pz <- pnorm(z)
  low <- qnorm(0.025) * (1 / dnorm(z)) * sqrt(pz * (1 - pz) / n)
  for (j in c(1, 5, 9, 17, 25, 33)) add(32, j - 1, low[j])
  for (ct in 0:1) {
    o <- if (ct == 0) wp(m, xvar = x1, n.inter = ninter) else wp(m, xvar = x1, xcut.points = cuts)
    cl <- o$classes
    for (i in seq_len(nrow(cl))) for (j in 1:2) add(33 + 2 * ct, (i - 1) * 2 + j - 1, unname(cl[i, j]))
    for (i in seq_len(nrow(o$coef))) for (j in 1:4) add(34 + 2 * ct, (i - 1) * 4 + j - 1, o$coef[i, j])
  }
  zq <- Q.stats(m, xvar = xv, n.inter = ninter, plot = FALSE)
  xq <- Q.stats(m, xvar = xv, n.inter = ninter, zvals = FALSE, plot = FALSE)
  for (i in seq_len(nrow(zq))) for (j in 1:6) add(37, (i - 1) * 6 + j - 1, zq[i, j])
  for (i in seq_len(nrow(xq))) for (j in 1:6) add(38, (i - 1) * 6 + j - 1, xq[i, j])
  rq <- Q.stats(resid = rs, xvar = xv, n.inter = ninter + 1, plot = FALSE)
  for (i in seq_len(nrow(rq))) for (j in 1:4) add(39, (i - 1) * 4 + j - 1, rq[i, j])
  cq <- Q.stats(m, xvar = xv, xcut.points = cuts, plot = FALSE)
  for (i in seq_len(nrow(cq))) for (j in 1:6) add(40, (i - 1) * 6 + j - 1, cq[i, j])
  ce <- centiles(m, xv, cent = cent, save = TRUE, plot = FALSE)
  o <- order(xv)
  fv <- lapply(seq_len(np), function(k) fitted(m, c("mu", "sigma", "nu")[k]))
  qf <- get(paste0("q", m$family[1]))
  for (ci in seq_along(cent)) {
    ll <- do.call(qf, c(list(cent[ci] / 100), lapply(fv, function(v) v[o])))
    for (j in c(1, 7, 30, 31, 60)) add(41, (ci - 1) * n + j - 1, ll[j])
    add(42, ci - 1, ce[ci, 2])
  }
  cp <- centiles.pred(m, xname = "x1", xvalues = newx, type = "centiles", cent = cent)
  for (ci in seq_along(cent)) for (j in 1:5) add(43, (ci - 1) * 5 + j - 1, cp[j, ci + 1])
  zp <- centiles.pred(m, xname = "x1", xvalues = newx, type = "z-scores", yval = yval)
  for (j in 1:5) add(44, j - 1, zp[j])
  sp <- centiles.pred(m, xname = "x1", xvalues = newx, type = "standard-centiles", dev = dev)
  for (ci in seq_along(dev)) for (j in 1:5) add(45, (ci - 1) * 5 + j - 1, sp[j, ci + 1])
}
n <- 60
set.seed(20261701)
x1 <- round(runif(n, 0.01, 5), 3)
x2 <- round(rnorm(n), 3)
d0 <- data.frame(x1 = x1, x2 = x2)
cuts <- c(0.8, 1.9, 3.1, 4)
newx <- c(2.6, 0.3, 4.5, 1.7, 3.4)
yno <- round(2 + 0.7 * x1 - 0.5 * x2 + exp(-0.5 + 0.2 * x1) * rnorm(n), 4)
mk(0, yno, d0, c("x1", "x1"), c(4, 5, 4), 6, cuts, newx)
yga <- round(rgamma(n, shape = 4, scale = exp(0.5 + 0.2 * x1) / 4) + 0.01, 4)
mk(1, yga, d0, c("x1", "1"), c(5, 5, 4), 8, cuts, newx)
ywe <- round(rweibull(n, shape = 2.2, scale = exp(0.8 + 0.1 * x1)), 4)
mk(3, ywe, d0, c("x1", "x1"), c(5, 5, 4), 7, cuts, newx)
ybc <- round(exp(1 + 0.15 * x1 + 0.2 * rnorm(n)), 4)
mk(4, ybc, d0, c("x1", "1", "1"), c(5, 5, 4), 6, cuts, newx)
emit("gamlss_diag", c("gamlss", "gamlss.dist"), list(cases))
