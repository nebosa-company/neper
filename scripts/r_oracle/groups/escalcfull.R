# escalcfull: metafor escalc for the 2x2, two-group, correlation, proportion, incidence-rate and single-mean measures (lib/e/algo/stat/escalcmore.e).
#   A case is fn "escalc" with args = [measure, vtype, add, to (0 none 1 all 2 only0 3 if0all), drop00, correct, k, ncol, data (k * ncol, row-major)]; its want is yi[0] and the "o" cases after
#   it are values of the result vector: index 2 i yi of row i, 2 i + 1 vi of row i. The measure and vtype codes are listed at the top of escalcmore.e.
suppressMessages(library(metafor))
cases <- list()
add_vec <- function(args, yi, vi, rel = 1e-10) {
  v <- as.vector(rbind(yi, vi))
  cases[[length(cases) + 1]] <<- case("escalc", args, v[1], rel = rel, abs = 1e-12)
  for (j in 2:length(v)) cases[[length(cases) + 1]] <<- case("o", j - 1, v[j], rel = rel, abs = 1e-12)
}
tonames <- c("none", "all", "only0", "if0all")
vnames <- c("LS", "UB", "AV", "H0", "HO", "LS2", "LS3", "CS", "ST", "AVHO")
run <- function(measure, code, vtype, add, to, drop00, correct, cols, args_list, rel = 1e-10) {
  a <- c(args_list, list(measure = measure, add = add, to = tonames[to + 1], drop00 = drop00 == 1))
  if (vtype != 0) a$vtype <- vnames[vtype + 1]
  if (!correct) a$correct <- FALSE
  r <- tryCatch(suppressWarnings(do.call(escalc, a)), error = function(e) NULL)
  if (is.null(r)) return(invisible())
  d <- as.vector(t(as.matrix(as.data.frame(args_list[cols]))))
  k <- nrow(r)
  add_vec(c(code, vtype, add, to, drop00, as.integer(correct), k, length(cols), d), as.numeric(r$yi), as.numeric(r$vi), rel)
}
set.seed(20263030)
k <- 7
tab <- function() {
  n1 <- sample(15:80, k, replace = TRUE); n2 <- sample(15:80, k, replace = TRUE)
  ai <- rbinom(k, n1, runif(k, 0.03, 0.5)); ci <- rbinom(k, n2, runif(k, 0.03, 0.5))
  list(ai = ai, bi = n1 - ai, ci = ci, di = n2 - ci)
}
t2 <- list(RR = 0, OR = 1, RD = 2, AS = 3, PETO = 4, PHI = 5, ZPHI = 6, YUQ = 7, YUY = 8, PBIT = 9, OR2D = 10, OR2DN = 11, OR2DL = 12)
for (rep in 1:3) {
  d <- tab()
  for (m in names(t2)) {
    for (to in 0:3) for (add in c(0.5, 0.1)) for (vt in (if (m %in% c("RR", "OR", "RD")) c(0, 2, 3) else 0)) {
      if (to == 0 && add != 0.5) next
      run(m, t2[[m]], vt, add, to, 0, TRUE, c("ai", "bi", "ci", "di"), d)
    }
    run(m, t2[[m]], 0, 0.5, 2, 1, TRUE, c("ai", "bi", "ci", "di"), replace(d, "ai", list(c(0, d$ai[-1]))))
  }
  run("RD", 2, 1, 0.5, 2, 0, TRUE, c("ai", "bi", "ci", "di"), d)
}
d <- tab(); d$ai[1:2] <- 0; d$ci[1] <- 0; d$bi[3] <- 0; d$di[3] <- 0
for (m in names(t2)) for (to in 1:3) run(m, t2[[m]], 0, 0.5, to, 0, TRUE, c("ai", "bi", "ci", "di"), d)
t4 <- list(MD = 20, SMD = 21, SMDH = 22, SMD1 = 23, SMD1H = 24, ROM = 25, RPB = 26, ZPB = 27, D2OR = 28, VR = 29, CVR = 30, D2ORN = 31)
vt4 <- list(MD = c(0, 4), SMD = c(0, 5, 6, 1, 2, 3), SMDH = c(0, 5, 6), SMD1 = c(0, 5), SMD1H = 0, ROM = c(0, 4, 2, 9, 5), RPB = c(0, 7), ZPB = c(0, 7), D2OR = 0, VR = c(0, 5), CVR = c(0, 5), D2ORN = 0)
for (rep in 1:3) {
  n1i <- sample(10:60, k, replace = TRUE); n2i <- sample(10:60, k, replace = TRUE)
  d <- list(m1i = round(rnorm(k, 10, 2), 3), m2i = round(rnorm(k, 9, 2), 3), sd1i = round(runif(k, 1, 4), 3), sd2i = round(runif(k, 1, 4), 3), n1i = n1i, n2i = n2i)
  for (m in names(t4)) for (vt in vt4[[m]]) for (cr in c(TRUE, FALSE)) run(m, t4[[m]], vt, 0.5, 0, 0, cr, c("m1i", "m2i", "sd1i", "sd2i", "n1i", "n2i"), d)
}
for (rep in 1:2) {
  t1i <- round(runif(k, 5, 60), 2); t2i <- round(runif(k, 5, 60), 2)
  d <- list(x1i = rpois(k, 2 * t1i / 10), x2i = rpois(k, 2 * t2i / 10), t1i = t1i, t2i = t2i)
  d$x1i[1] <- 0; d$x2i[2] <- 0; d$x1i[3] <- 0; d$x2i[3] <- 0
  for (m in c("IRR", "IRD", "IRSD")) for (to in 0:3) for (dr in 0:1) run(m, c(IRR = 40, IRD = 41, IRSD = 42)[[m]], 0, 0.5, to, dr, TRUE, c("x1i", "x2i", "t1i", "t2i"), d)
  d <- list(xi = rpois(k, 3), ti = round(runif(k, 5, 60), 2)); d$xi[2] <- 0
  for (m in c("IR", "IRLN", "IRS", "IRFT")) for (to in 0:3) run(m, c(IR = 70, IRLN = 71, IRS = 72, IRFT = 73)[[m]], 0, 0.5, to, 0, TRUE, c("xi", "ti"), d)
  ni <- sample(20:100, k, replace = TRUE)
  d <- list(xi = rbinom(k, ni, 0.1), mi = NULL); d$mi <- ni - d$xi; d$xi[2] <- 0; d$mi[2] <- ni[2]; d$mi[4] <- 0; d$xi[4] <- ni[4]
  for (m in c("PR", "PLN", "PLO", "PRZ", "PAS", "PFT")) for (to in 0:3) for (vt in (if (m %in% c("PR", "PLN", "PLO")) c(0, 2) else 0)) run(m, c(PR = 60, PLN = 61, PLO = 62, PRZ = 63, PAS = 64, PFT = 65)[[m]], vt, 0.5, to, 0, TRUE, c("xi", "mi"), d)
  d <- list(ri = round(runif(k, -0.6, 0.8), 3), ni = sample(15:100, k, replace = TRUE))
  for (vt in c(0, 2, 3, 8)) run("COR", 50, vt, 0.5, 0, 0, TRUE, c("ri", "ni"), d)
  run("ZCOR", 51, 0, 0.5, 0, 0, TRUE, c("ri", "ni"), d)
  d <- list(mi = round(runif(k, 3, 20), 3), sdi = round(runif(k, 1, 5), 3), ni = sample(10:80, k, replace = TRUE))
  for (m in c("MN", "SMN", "MNLN", "SDLN", "CVLN")) for (cr in c(TRUE, FALSE)) for (vt in (if (m == "MN") c(0, 4) else 0)) run(m, c(MN = 80, SMN = 81, MNLN = 82, SDLN = 83, CVLN = 84)[[m]], vt, 0.5, 0, 0, cr, c("mi", "sdi", "ni"), d)
}
for (rep in 1:2) {
  d <- tab(); d$bi[1] <- 0
  for (m in c("MPRD", "MPRR", "MPOR", "MPORC", "MPPETO")) for (to in 0:3) run(m, c(MPRD = 120, MPRR = 121, MPOR = 122, MPORC = 123, MPPETO = 124)[[m]], 0, 0.5, to, 0, TRUE, c("ai", "bi", "ci", "di"), d)
  ni <- sample(15:80, k, replace = TRUE)
  d <- list(m1i = round(rnorm(k, 12, 2), 3), m2i = round(rnorm(k, 10, 2), 3), sd1i = round(runif(k, 1, 4), 3), sd2i = round(runif(k, 1, 4), 3), ni = ni, ri = round(runif(k, 0.1, 0.8), 3))
  pm <- list(MC = c(100, 0), SMCC = c(101, 0, 5, 1, 3), SMCRH = c(103, 0, 5), SMCRP = c(104, 0), SMCRPH = c(105, 0, 5), CLESCN = c(106, 0), ROMC = c(107, 0, 5), VRC = c(108, 0, 5), CVRC = c(109, 0, 5))
  for (m in names(pm)) for (vt in pm[[m]][-1]) for (cr in c(TRUE, FALSE)) run(m, pm[[m]][1], vt, 0.5, 0, 0, cr, c("m1i", "m2i", "sd1i", "sd2i", "ni", "ri"), d)
  d <- list(ai = round(runif(k, 0.5, 0.95), 3), mi = sample(3:20, k, replace = TRUE), ni = sample(20:150, k, replace = TRUE))
  for (m in c("ARAW", "AHW", "ABT")) run(m, c(ARAW = 130, AHW = 131, ABT = 132)[[m]], 0, 0.5, 0, 0, TRUE, c("ai", "mi", "ni"), d)
  d <- list(ai = sample(5:40, k, replace = TRUE), bi = sample(5:40, k, replace = TRUE), ci = sample(5:40, k, replace = TRUE))
  run("REH", 133, 0, 0.5, 0, 0, TRUE, c("ai", "bi", "ci"), d)
}
emit("escalcfull", "metafor", list(cases))
