# gstatfit: gstat's fit.variogram.
#   "fit" (method, nst, nev, kgrid, 6 numbers per structure: code, psill, range, kappa, angle, ratio (an unset psill or range is -1), fit.sills (nst), fit.ranges (nst),
#   np (nev), dist (nev), gamma (nev), part): part 0..nst-1 the fitted partial sills, nst..2nst-1 the ranges, 2nst the weighted error SSErr, 2nst+1 the singular flag.
suppressMessages(library(gstat)); suppressMessages(library(sp))
cases <- list()
set.seed(20262102)
codes <- c(Nug = 1, Exp = 2, Sph = 3, Gau = 4, Exc = 5, Mat = 6, Ste = 7, Cir = 8, Lin = 9, Bes = 10, Pen = 11, Per = 12, Wav = 13, Hol = 14, Log = 15, Pow = 16, Spl = 17, Err = 19, Int = 20)
flat <- function(m) { v <- as.vector(rbind(codes[as.character(m$model)], m$psill, m$range, m$kappa, m$ang1, m$anis1)); v[is.na(v)] <- -1; v }
dat <- function(n, sdn = 0.3) { d <- data.frame(x = runif(n), y = runif(n)); d$z <- round(sin(3 * d$x) + d$y + rnorm(n, 0, sdn), 4); d }
nfit <- 0
addfit <- function(v, m, method, fs = TRUE, fr = TRUE, kgrid = FALSE, rel = 1e-8) {
  nst <- nrow(m); warn <- character()
  fit <- tryCatch(withCallingHandlers(fit.variogram(v, m, fit.sills = fs, fit.ranges = fr, fit.method = method, debug.level = 0, fit.kappa = kgrid),
    warning = function(w) { warn <<- c(warn, conditionMessage(w)); invokeRestart("muffleWarning") }), error = function(e) NULL)
  if (is.null(fit) || any(grepl("No convergence", warn)) || !all(is.finite(c(fit$psill, fit$range)))) return(invisible())
  if (any(abs(fit$psill) > 50) || any(fit$range > 50)) return(invisible())
  # a fit that moves when the start is nudged by 1e-11 is chaotic: rounding differences would decide it, not the algorithm
  m2 <- m; m2$psill <- m2$psill * (1 + 1e-11); m2$range <- m2$range * (1 - 1e-11)
  fit2 <- tryCatch(suppressWarnings(fit.variogram(v, m2, fit.sills = fs, fit.ranges = fr, fit.method = method, debug.level = 0, fit.kappa = kgrid)), error = function(e) NULL)
  if (is.null(fit2) || any(abs(c(fit2$psill, fit2$range) - c(fit$psill, fit$range)) > 1e-8 * (1 + abs(c(fit$psill, fit$range)))) || abs(attr(fit2, "SSErr") - attr(fit, "SSErr")) > 1e-8 * attr(fit, "SSErr")) return(invisible())
  nfit <<- nfit + 1
  head <- c(method, nst, nrow(v), as.numeric(kgrid), flat(m), rep(fs, length.out = nst), rep(fr, length.out = nst), v$np, v$dist, v$gamma)
  want <- c(fit$psill, fit$range, attr(fit, "SSErr"), as.numeric(attr(fit, "singular")))
  for (p in seq_along(want)) cases[[length(cases) + 1]] <<- case("fit", c(head, p - 1), want[p], rel = rel, abs = 1e-10)
}
fams <- c("Sph", "Exp", "Gau", "Lin", "Cir", "Pen", "Mat", "Ste", "Bes", "Exc", "Wav", "Hol", "Pow", "Spl", "Log", "Per")
meths <- c(1, 2, 6, 7)
start <- function(v, fam, nug = TRUE) {
  ps <- mean(tail(v$gamma, 4)); rg <- max(v$dist) / 3
  kap <- switch(fam, Mat = 1.5, Ste = 1.5, Exc = 1.5, 0.5)
  if (fam == "Pow") return(vgm(0.5, "Pow", 1.2, nugget = 0.05))
  if (fam == "Log") return(vgm(0.5, "Log", 0.3, nugget = 0.05))
  if (fam == "Spl") return(vgm(0.5, "Spl", 1, nugget = 0.05))
  if (nug) vgm(ps, fam, rg, v$gamma[1] / 2, kappa = kap) else vgm(ps, fam, rg, kappa = kap)
}
for (ds in 1:32) {
  n <- sample(45:90, 1); d <- dat(n); cutoff <- runif(1, 0.55, 0.8)
  v <- variogram(z ~ 1, ~x + y, d, cutoff = cutoff, width = cutoff / 12)
  fam <- fams[(ds - 1) %% length(fams) + 1]; me <- meths[(ds - 1) %/% length(fams) * 2 + 1]
  addfit(v, start(v, fam), meths[(ds - 1) %% 4 + 1])
  addfit(v, start(v, fam, FALSE), meths[ds %% 4 + 1])
}
# every family against every weighting on one shared sample variogram
d <- dat(70); v <- variogram(z ~ 1, ~x + y, d, cutoff = 0.7, width = 0.7 / 14)
for (fam in c("Sph", "Exp", "Gau", "Mat", "Cir", "Pen")) for (me in meths) addfit(v, start(v, fam), me)
# fixed sills or ranges, and unset starting values
for (me in meths) {
  addfit(v, start(v, "Sph"), me, fs = FALSE, fr = TRUE)
  addfit(v, start(v, "Exp"), me, fs = TRUE, fr = FALSE)
  addfit(v, vgm("Sph"), me)
  addfit(v, vgm("Gau"), me)
  addfit(v, vgm(model = "Exp", psill = NA, range = 0.4), me)
}
# nested structures, nugget fits, and an anisotropic start
for (rep in 1:6) {
  d <- dat(sample(60:90, 1)); v <- variogram(z ~ 1, ~x + y, d, cutoff = 0.7, width = 0.7 / 12); me <- meths[rep %% 4 + 1]
  addfit(v, vgm(0.3, "Exp", 0.15, add.to = vgm(0.4, "Sph", 0.6, nugget = 0.05)), me)
  addfit(v, vgm(0.5, "Sph", 0.5, nugget = 0.05, anis = c(30, 0.5)), me)
  addfit(v, vgm(0.4, "Gau", 0.3, add.to = vgm(0.3, "Exp", 0.8)), me, fr = c(TRUE, FALSE))
}
# smooth data: negative partial sills are fixed at zero and the fit repeated
for (rep in 1:8) {
  d <- dat(sample(60:90, 1), 0.02); v <- variogram(z ~ 1, ~x + y, d, cutoff = 0.7, width = 0.7 / 12); me <- meths[rep %% 4 + 1]
  addfit(v, vgm(0.8, "Gau", 0.5, nugget = 0.1), me)
  addfit(v, vgm(0.8, "Sph", 0.9, nugget = 0.2), me)
}
# the grid search over kappa
for (rep in 1:3) {
  d <- dat(sample(60:90, 1)); v <- variogram(z ~ 1, ~x + y, d, cutoff = 0.7, width = 0.7 / 12)
  addfit(v, vgm(0.5, "Mat", 0.3, nugget = 0.05, kappa = 1), meths[rep], kgrid = TRUE)
  addfit(v, vgm(0.5, "Ste", 0.3, nugget = 0.05, kappa = 1), meths[rep + 1], kgrid = TRUE)
}
# a directional variogram
for (rep in 1:4) {
  d <- dat(sample(70:100, 1)); v <- variogram(z ~ 1, ~x + y, d, cutoff = 0.7, width = 0.7 / 10, alpha = c(0, 90), tol.hor = 45)
  addfit(v[v$dir.hor == 0, ], vgm(0.5, "Sph", 0.5, nugget = 0.05), meths[rep])
}
message("fits kept: ", nfit)
emit("gstatfit", "gstat", list(cases))
