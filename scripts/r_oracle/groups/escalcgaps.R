# escalcgaps: the escalc measures and options escalcfull leaves out (lib/e/algo/stat/escalcgap.e and the vtype, to and drop00 corners of escalcmore.e).
#   Same case layout as escalcfull: fn "escalc" with args = [measure, vtype, add, to (0 none 1 all 2 only0 3 if0all), drop00, correct, k, ncol, data (k * ncol, row-major)] and its "o" cases;
#   a column the R call does not pass is NaN. The measure and vtype codes are listed at the top of escalcmore.e and escalcgap.e.
#   RTET and ZTET variances come from a finite-difference Hessian of a likelihood that mvtnorm evaluates, so they are compared at 1e-9 (a one-ulp libm difference moves them by about 5e-10); every other value is at 1e-10.
suppressMessages(library(metafor))
cases <- list()
add_vec <- function(args, yi, vi, rel = 1e-10, relv = rel) {
  v <- as.vector(rbind(yi, vi))
  rl <- rep(c(rel, relv), length(yi))
  cases[[length(cases) + 1]] <<- case("escalc", args, v[1], rel = rl[1], abs = 1e-12)
  for (j in 2:length(v)) cases[[length(cases) + 1]] <<- case("o", j - 1, v[j], rel = rl[j], abs = 1e-12)
}
tonames <- c("none", "all", "only0", "if0all")
vnames <- c("LS", "UB", "AV", "H0", "HO", "LS2", "LS3", "CS", "ST", "AVHO", "H0a", "H0b", "AV2", "MAX")
run <- function(measure, code, vtype, add, to, drop00, correct, cols, args_list, rel = 1e-10, relv = rel) {
  a <- c(args_list[!vapply(args_list, is.null, TRUE)], list(measure = measure, add = add, to = tonames[to + 1], drop00 = drop00 == 1))
  if (vtype != 0) a$vtype <- vnames[vtype + 1]
  if (!correct) a$correct <- FALSE
  r <- tryCatch(suppressWarnings(do.call(escalc, a)), error = function(e) NULL)
  if (is.null(r)) return(invisible())
  k <- nrow(r)
  d <- as.vector(t(sapply(cols, function(cn) if (is.null(args_list[[cn]])) rep(NaN, k) else as.numeric(args_list[[cn]]))))
  add_vec(c(code, vtype, add, to, drop00, as.integer(correct), k, length(cols), d), as.numeric(r$yi), as.numeric(r$vi), rel, relv)
}
sweep <- function(measure, code, cols, d, vts = 0, adds = 0.5, tos = 0, drops = 0, crs = TRUE, rel = 1e-10, relv = rel) {
  for (vt in vts) for (to in tos) for (add in adds) for (dr in drops) for (cr in crs) run(measure, code, vt, add, to, dr, cr, cols, d, rel, relv)
}
set.seed(20263031)
k <- 4
tab <- function(lo = 0.05, hi = 0.5) {
  n1 <- sample(15:80, k, replace = TRUE); n2 <- sample(15:80, k, replace = TRUE)
  ai <- rbinom(k, n1, runif(k, lo, hi)); ci <- rbinom(k, n2, runif(k, lo, hi))
  list(ai = ai, bi = n1 - ai, ci = ci, di = n2 - ci)
}
abcd <- c("ai", "bi", "ci", "di")
t2 <- c(RR = 0, OR = 1, RD = 2, AS = 3, PETO = 4, PHI = 5, ZPHI = 6, YUQ = 7, YUY = 8, PBIT = 9, OR2D = 10, OR2DN = 11, OR2DL = 12, MPRD = 120, MPRR = 121, MPOR = 122, MPORC = 123, MPPETO = 124)
v2 <- function(m) if (m == "RD") c(0, 1, 2, 3) else if (m %in% c("RR", "OR", "OR2D", "OR2DN", "OR2DL")) c(0, 2, 3) else if (m %in% c("PHI", "ZPHI")) c(0, 7, 8) else 0
# every variance type of the 2x2 measures, with the continuity correction options
for (rep in 1:2) {
  d <- tab()
  for (m in names(t2)) sweep(m, t2[[m]], abcd, d, vts = v2(m), tos = 0:3, adds = if (rep == 1) 0.5 else 0.1)
}
# zero cells, dropped 0/0 rows and if0all after drop00
d <- tab(); d$ai[1] <- 0; d$ci[1] <- 0; d$bi[2] <- 0; d$di[2] <- 0; d$ci[3] <- 0
for (m in names(t2)) sweep(m, t2[[m]], abcd, d, vts = v2(m)[1:min(2, length(v2(m)))], tos = 0:3, drops = 0:1)
d <- tab(); d$ai[2] <- 0; d$ci[2] <- 0; d$bi[4] <- 0; d$di[4] <- 0
for (m in names(t2)) sweep(m, t2[[m]], abcd, d, tos = 3, drops = 0:1, adds = c(0.5, 1))
# MPORM from ri, from pi and from both
for (rep in 1:2) {
  d <- tab(0.2, 0.6)
  d$ri <- round(runif(k, -0.3, 0.7), 3)
  sweep("MPORM", 15, c(abcd, "ri", "pi"), d, vts = c(0, 2, 3), tos = 0:3)
  e <- d; e$ri <- NULL; e$pi <- round(runif(k, 0.1, 0.9), 3)
  sweep("MPORM", 15, c(abcd, "ri", "pi"), e, vts = c(0, 2), tos = c(0, 2))
  f <- d; f$ri[2] <- NA; f$pi <- round(runif(k, 0.1, 0.9), 3)
  sweep("MPORM", 15, c(abcd, "ri", "pi"), f, tos = c(0, 1))
  g <- d; g$ai[1] <- 0; g$ci[1] <- 0; g$bi[2] <- 0
  sweep("MPORM", 15, c(abcd, "ri", "pi"), g, vts = c(0, 2), tos = 0:3, drops = 0:1)
}
# RTET and ZTET: the rows with an empty margin or an empty diagonal are decided without the optimiser; a single empty cell makes the likelihood flat, so those rows get the correction
for (rep in 1:2) {
  d <- tab(0.15, 0.6)
  for (m in c("RTET", "ZTET")) sweep(m, c(RTET = 13, ZTET = 14)[[m]], abcd, d, tos = 0, adds = 0, rel = 1e-10, relv = 1e-9)
  d <- list(ai = c(12, 0, 9, 0), bi = c(0, 10, 7, 0), ci = c(0, 0, 11, 6), di = c(15, 12, 14, 0))
  for (m in c("RTET", "ZTET")) sweep(m, c(RTET = 13, ZTET = 14)[[m]], abcd, d, tos = 0, adds = 0, rel = 1e-10, relv = 1e-9)
  d <- tab(0.15, 0.6); d$ai[2] <- 0; d$di[3] <- 0; d$bi[4] <- 0
  for (m in c("RTET", "ZTET")) sweep(m, c(RTET = 13, ZTET = 14)[[m]], abcd, d, tos = 1:3, adds = 0.5, rel = 1e-10, relv = 1e-9)
}
d <- list(ai = c(12, 0, 9, 8), bi = c(0, 10, 7, 9), ci = c(0, 0, 11, 6), di = c(15, 12, 14, 10))
sweep("RTET", 13, abcd, d, tos = 0, drops = 0:1, adds = 0, rel = 1e-10, relv = 1e-9)
sweep("RTET", 13, abcd, d, tos = 3, drops = 0:1, adds = 0.5, rel = 1e-10, relv = 1e-9)
# incidence-rate pair with if0all and drop00
for (rep in 1:2) {
  t1i <- round(runif(k, 5, 60), 2); t2i <- round(runif(k, 5, 60), 2)
  d <- list(x1i = rpois(k, 2 * t1i / 10), x2i = rpois(k, 2 * t2i / 10), t1i = t1i, t2i = t2i)
  d$x1i[1] <- 0; d$x2i[1] <- 0; d$x1i[2] <- 0; d$x2i[3] <- 0
  for (m in c("IRR", "IRD", "IRSD")) sweep(m, c(IRR = 40, IRD = 41, IRSD = 42)[[m]], c("x1i", "x2i", "t1i", "t2i"), d, tos = 0:3, drops = 0:1, adds = if (rep == 1) 0.5 else 0.1)
  d$x1i[2] <- 3; d$x2i[3] <- 2
  for (m in c("IRR", "IRD", "IRSD")) sweep(m, c(IRR = 40, IRD = 41, IRSD = 42)[[m]], c("x1i", "x2i", "t1i", "t2i"), d, tos = 3, drops = 0:1)
}
# the measures that take no drop00 ignore it
ni <- sample(20:100, k, replace = TRUE)
d <- list(xi = rbinom(k, ni, 0.1), mi = NULL); d$mi <- ni - d$xi; d$xi[2] <- 0; d$mi[2] <- ni[2]
for (m in c("PR", "PLN", "PLO")) sweep(m, c(PR = 60, PLN = 61, PLO = 62)[[m]], c("xi", "mi"), d, vts = c(0, 1, 2), tos = c(0, 2, 3), drops = 0:1)
d <- list(ri = round(runif(k, -0.6, 0.8), 3), ni = sample(15:100, k, replace = TRUE))
sweep("COR", 50, c("ri", "ni"), d, vts = c(0, 2, 3, 10, 11), drops = 0:1)
# two-group measures: the variance types escalcfull does not try
for (rep in 1:2) {
  n1i <- sample(10:60, k, replace = TRUE); n2i <- sample(10:60, k, replace = TRUE)
  d <- list(m1i = round(rnorm(k, 10, 2), 3), m2i = round(rnorm(k, 9, 2), 3), sd1i = round(runif(k, 1, 4), 3), sd2i = round(runif(k, 1, 4), 3), n1i = n1i, n2i = n2i)
  cols6 <- c("m1i", "m2i", "sd1i", "sd2i", "n1i", "n2i")
  sweep("MD", 20, cols6, d, vts = c(1, 4))
  sweep("SMD1", 23, cols6, d, vts = c(1, 2, 3, 5, 6), crs = c(TRUE, FALSE))
  sweep("SMD", 21, cols6, d, vts = c(1, 2, 3), crs = FALSE)
  for (m in c("RPB", "ZPB")) sweep(m, c(RPB = 26, ZPB = 27)[[m]], cols6, d, vts = c(8, 7))
  for (m in c("RBIS", "ZBIS", "D2ORL")) sweep(m, c(RBIS = 32, ZBIS = 33, D2ORL = 34)[[m]], cols6, d)
  d$mini <- rep(0, k); d$maxi <- rep(30, k)
  d$m1i <- d$m1i + 3; d$m2i <- d$m2i + 3
  sweep("POMPMD", 35, c(cols6, "mini", "maxi"), d, vts = c(0, 1, 4))
  d$sd1i <- d$sd1i * 0.3; d$sd2i <- d$sd2i * 0.3
  for (m in c("CLESN", "AUCN")) sweep(m, 95, cols6, d, vts = c(0, 3, 4, 5, 6))
}
# POMPMN
d <- list(mi = round(runif(k, 3, 20), 3), sdi = round(runif(k, 1, 5), 3), ni = sample(10:80, k, replace = TRUE), mini = rep(0, k), maxi = rep(30, k))
sweep("POMPMN", 85, c("mi", "sdi", "ni", "mini", "maxi"), d, vts = c(0, 4))
# paired measures
for (rep in 1:2) {
  ni <- sample(15:80, k, replace = TRUE)
  d <- list(m1i = round(rnorm(k, 12, 2), 3), m2i = round(rnorm(k, 10, 2), 3), sd1i = round(runif(k, 1, 4), 3), sd2i = round(runif(k, 1, 4), 3), ni = ni, ri = round(runif(k, 0.1, 0.8), 3))
  cols6 <- c("m1i", "m2i", "sd1i", "sd2i", "ni", "ri")
  for (m in c("CLESCN", "AUCCN")) sweep(m, 106, cols6, d)
  d$mini <- rep(0, k); d$maxi <- rep(30, k)
  sweep("POMPMC", 110, c(cols6, "mini", "maxi"), d)
  sweep("SMCR", 102, c("m1i", "m2i", "sd1i", "ni", "ri"), d, vts = c(0, 1, 3, 5), crs = c(TRUE, FALSE))
}
# correlations that need the hypergeometric function
for (rep in 1:2) {
  d <- list(ri = round(runif(k, -0.7, 0.8), 3), ni = sample(15:100, k, replace = TRUE))
  sweep("UCOR", 52, c("ri", "ni"), d, vts = c(0, 1, 2))
  sweep("ZCOR", 51, c("ri", "ni"), d)
}
d <- list(ri = c(0.4, -0.3, 0.2, 0.5), ni = c(4, 5, 20, 3)); sweep("UCOR", 52, c("ri", "ni"), d, vts = c(0, 1, 2)); sweep("COR", 50, c("ri", "ni"), d, vts = c(0, 2, 3, 10, 11)); sweep("ZCOR", 51, c("ri", "ni"), d)
d <- list(m1i = c(4, 5, 6, 7), m2i = c(3, 5, 5, 6), sd1i = c(1, 1.5, 2, 1), ni = c(3, 4, 5, 30), ri = c(0.3, 0.5, -0.2, 0.6))
sweep("SMCR", 102, c("m1i", "m2i", "sd1i", "ni", "ri"), d, vts = c(0, 1, 3, 5))
d <- list(m1i = c(4, 5, 6, 7), m2i = c(3, 5, 5, 6), sd1i = c(1, 1.5, 2, 1), sd2i = c(1, 1, 1, 1), n1i = c(2, 2, 3, 20), n2i = c(2, 3, 20, 20))
sweep("SMD", 21, c("m1i", "m2i", "sd1i", "sd2i", "n1i", "n2i"), d, vts = c(0, 3))
# partial, semi-partial, ICC, R2
for (rep in 1:2) {
  ni <- sample(25:120, k, replace = TRUE); mi <- sample(1:5, k, replace = TRUE)
  d <- list(ri = round(runif(k, -0.6, 0.7), 3), mi = mi, ni = ni, r2i = round(runif(k, 0.3, 0.8), 3))
  for (m in c("PCOR", "ZPCOR")) sweep(m, c(PCOR = 53, ZPCOR = 54)[[m]], c("ri", "mi", "ni"), d, vts = c(0, 2))
  for (m in c("SPCOR", "ZSPCOR")) sweep(m, c(SPCOR = 55, ZSPCOR = 56)[[m]], c("ri", "mi", "ni", "r2i"), d, vts = c(0, 2))
  d$mi <- mi + 1
  for (m in c("ICC", "ZICC")) sweep(m, c(ICC = 57, ZICC = 58)[[m]], c("ri", "mi", "ni"), d)
  for (m in c("R2", "ZR2")) sweep(m, c(R2 = 90, ZR2 = 91)[[m]], c("r2i", "mi", "ni"), d, vts = c(0, 2, 5, 12))
}
d <- list(r2i = c(0.25, 0.5, 0.1, 0.7), mi = c(2, 3, 1, 4), ni = c(40, 60, 35, 80))
for (m in c("R2F", "ZR2F")) sweep(m, c(R2F = 92, ZR2F = 93)[[m]], c("r2i", "mi", "ni"), d)
# CLES and AUC
for (rep in 1:2) {
  d <- list(ai = round(runif(k, 0.3, 0.9), 3), n1i = sample(10:60, k, replace = TRUE), n2i = sample(10:60, k, replace = TRUE), mi = round(runif(k, 0, 0.5), 3))
  for (m in c("CLES", "AUC")) sweep(m, 94, c("ai", "n1i", "n2i", "mi"), d, vts = c(0, 5, 3, 13))
  d$mi <- NULL
  sweep("CLES", 94, c("ai", "n1i", "n2i", "mi"), d, vts = c(0, 5, 3, 13))
}
emit("escalcgaps", "metafor", list(cases))
