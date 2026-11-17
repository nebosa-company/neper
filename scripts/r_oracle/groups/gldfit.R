# gldfit: starship (fkml, rs, fm5, gpd), fit.fkml.moments and fit.fkml (ML, MPS, TM, SM, TL, LMOM, DLA, MOM), the optimiser-driven fits.
#   "star" (param, n, x.., q) q 0..4 = lambda1 .. lambda5 (the fit), 5 = optim value;  "fkml" (method, t1, t2, n, x.., q) q 0..3 = lambda1 .. lambda4;  "fmom" (n, x.., q) q 0..3
#   method: 1 ML 2 MPS 3 TM 4 SM 5 TL/LMOM 6 DLA 7 MOM.  Compared at 1e-7 (relative): the fits stop on Nelder-Mead's relative tolerance 1.5e-8 on the objective.
suppressMessages(library(gld))
cases <- list()
pn <- c("fkml", "rs", "fm5", "gpd")
add <- function(fn, args, want, rel = 1e-7, abs = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261122)
for (rep in 1:20) {
  pm <- rep %% 4; param <- pn[pm + 1]
  lam <- switch(pm + 1, c(0, 1, round(runif(1, 0.1, 0.5), 2), round(runif(1, 0.1, 0.5), 2)), c(0, 1, round(runif(1, 0.1, 0.4), 2), round(runif(1, 0.1, 0.4), 2)),
    c(0, 1, round(runif(1, 0.1, 0.5), 2), round(runif(1, 0.1, 0.5), 2), round(runif(1, -0.3, 0.3), 2)), c(0, 1, round(runif(1, 0.3, 0.7), 2), round(runif(1, 0.1, 0.5), 2)))
  x <- round(rgl(sample(40:80, 1), lam, param = param), 4); n <- length(x)
  fit <- tryCatch(suppressWarnings(starship(x, param = param)), error = function(e) NULL); if (is.null(fit)) next
  for (q in seq_along(fit$lambda)) add("star", c(pm, n, x, q - 1), fit$lambda[q])
  add("star", c(pm, n, x, 5), fit$optim.results$value, rel = 1e-6)
}
for (rep in 1:12) {
  x <- round(rgl(sample(40:90, 1), 0, 1, runif(1, 0.05, 0.5), runif(1, 0.05, 0.5), param = "fkml"), 4); n <- length(x)
  f <- tryCatch(suppressWarnings(fit.fkml.moments(x)), error = function(e) NULL); if (is.null(f)) next
  for (q in 1:4) add("fmom", c(n, x, q - 1), f$lambda[q])
}
meths <- c("ML", "MPS", "TM", "SM", "TL", "DLA", "MOM")
for (rep in 1:21) {
  mi <- rep %% 7 + 1; m <- meths[mi]; tr <- if (m == "TL") c(1, 1) else c(0, 0)
  x <- round(rgl(sample(30:60, 1), c(0, 1, runif(1, 0.05, 0.5), runif(1, 0.05, 0.5)), param = "fkml"), 4); n <- length(x)
  f <- tryCatch(suppressWarnings(fit.fkml(x, method = if (m == "TL" && rep %% 2 == 0) "TL" else if (m == "TL") "LMOM" else m, t1 = if (m == "TL" && rep %% 2 == 0) 1 else 0, t2 = if (m == "TL" && rep %% 2 == 0) 1 else 0, record.cpu.time = FALSE)), error = function(e) NULL)
  if (is.null(f)) next
  t1 <- if (m == "TL" && rep %% 2 == 0) 1 else 0
  for (q in 1:4) add("fkml", c(mi, t1, t1, n, x, q - 1), f$lambda[q])
}
emit("gldfit", "gld", list(cases))
