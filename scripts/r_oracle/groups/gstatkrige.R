# gstatkrige: gstat's krige(), krige.cv() and the conditional simulation of krige(nsim =).
#   header (all three): mode (0 universal or ordinary, 1 simple), n, p (drift columns), nst, nmax (0: all), maxdist (-1: none), nmin, then
#   "krige": part (0 prediction, 1 variance), px, py, x0 (p), beta (p), model (6 per structure: code, psill, range, kappa, angle, ratio), data rows (x y z X (p));
#   "cv": part, row, 0, 0 (unused), fold (n), beta (p), model, data rows;
#   "sim": nsim, nnew, seed, known (0/1), index (realisation * nnew + row), beta (p), model, data rows, new rows (x y X (p)).
suppressMessages(library(gstat)); suppressMessages(library(sp))
cases <- list()
set.seed(20262103)
codes <- c(Nug = 1, Exp = 2, Sph = 3, Gau = 4, Exc = 5, Mat = 6, Ste = 7, Cir = 8, Lin = 9, Bes = 10, Pen = 11, Per = 12, Wav = 13, Hol = 14, Log = 15, Pow = 16, Spl = 17, Err = 19, Int = 20)
build <- function(st) {
  m <- NULL
  for (i in seq_len(nrow(st))) {
    anis <- c(st$ang[i], st$ratio[i])
    one <- vgm(st$psill[i], as.character(st$model[i]), st$range[i], kappa = st$kappa[i], anis = anis)
    m <- if (is.null(m)) one else vgm(st$psill[i], as.character(st$model[i]), st$range[i], kappa = st$kappa[i], anis = anis, add.to = m)
  }
  m
}
flat <- function(st) as.vector(rbind(codes[as.character(st$model)], st$psill, st$range, st$kappa, st$ang, st$ratio))
rstruct <- function(mod, aniso) {
  rg <- runif(1, 0.2, 1.2); if (mod == "Nug") rg <- 0
  data.frame(model = mod, psill = runif(1, 0.1, 1.5), range = rg, kappa = runif(1, 0.5, 3), ang = if (aniso) sample(c(0, 30, 60, 90, 135), 1) else 0, ratio = if (aniso) runif(1, 0.3, 0.9) else 1)
}
fam <- c("Sph", "Exp", "Gau", "Cir", "Pen", "Mat", "Ste", "Lin")
rmodel <- function(nug, aniso) {
  st <- rstruct(sample(fam, 1), aniso)
  if (st$model == "Lin") st$range <- runif(1, 0.5, 1.5)
  if (nug) st <- rbind(rstruct("Nug", FALSE), st, if (runif(1) < 0.4) rstruct(sample(c("Sph", "Exp", "Gau"), 1), FALSE))
  st
}
forms <- list(z ~ 1, z ~ x + y, z ~ w + x, z ~ x + y + I(x^2) + I(x * y) + I(y^2))
dat <- function(n) { d <- data.frame(x = runif(n), y = runif(n)); d$w <- round(runif(n), 3); d$z <- round(1 + 2 * d$x - d$y + 0.5 * d$w + sin(4 * d$y) + rnorm(n, 0, 0.3), 4); d }
rows <- function(d, X) as.vector(t(cbind(d$x, d$y, d$z, X)))
newrows <- function(nd, X) as.vector(t(cbind(nd$x, nd$y, X)))
hdr <- function(mode, n, p, st, nmax, maxdist, nmin) c(mode, n, p, nrow(st), nmax, maxdist, nmin)
add <- function(fn, args, want, rel = 1e-9) { if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-11) }
# krige: universal, ordinary and simple, with neighbourhoods
for (rep in 1:32) {
  fi <- (rep - 1) %% 4 + 1; f <- forms[[fi]]; n <- sample(20:36, 1); d <- dat(n)
  st <- rmodel(TRUE, rep %% 2 == 0); m <- build(st)
  nmax <- if (rep %% 3 == 0) sample(8:15, 1) else Inf; maxdist <- if (rep %% 5 == 0) runif(1, 0.3, 0.6) else Inf; nmin <- if (is.finite(maxdist)) sample(0:4, 1) else 0
  nd <- data.frame(x = runif(3, 0.1, 0.9), y = runif(3, 0.1, 0.9), w = round(runif(3), 3))
  X <- model.matrix(f, d); X0 <- model.matrix(delete.response(terms(f)), nd); p <- ncol(X)
  beta <- if (rep %% 4 == 1) NULL else rnorm(p, 0, 0.5)
  mode <- if (is.null(beta)) 0 else 1
  args <- list(f, ~x + y, d, nd, model = m, debug.level = 0)
  if (is.finite(nmax)) args$nmax <- nmax
  if (is.finite(maxdist)) { args$maxdist <- maxdist; args$nmin <- nmin }
  if (!is.null(beta)) args$beta <- beta
  k <- do.call(krige, args)
  for (r in 1:2) for (pt in 0:1) {
    want <- c(k$var1.pred[r], k$var1.var[r])[pt + 1]
    add("krige", c(hdr(mode, n, p, st, if (is.finite(nmax)) nmax else 0, if (is.finite(maxdist)) maxdist else -1, nmin), pt, nd$x[r], nd$y[r], X0[r, ], if (is.null(beta)) rep(0, p) else beta, flat(st), rows(d, X)), want)
  }
}
# krige.cv: leave one out and folds
for (rep in 1:12) {
  fi <- (rep - 1) %% 4 + 1; f <- forms[[fi]]; n <- sample(18:30, 1); d <- dat(n)
  st <- rmodel(TRUE, rep %% 2 == 0); m <- build(st); X <- model.matrix(f, d); p <- ncol(X)
  nfold <- if (rep %% 2 == 0) n else sample(3:5, 1)
  fold <- if (nfold == n) 1:n else sample(nfold, n, replace = TRUE)
  nmax <- if (rep %% 3 == 0) sample(8:12, 1) else Inf
  beta <- if (rep %% 4 == 1) NULL else rnorm(p, 0, 0.5); mode <- if (is.null(beta)) 0 else 1
  args <- list(f, ~x + y, d, model = m, nfold = fold, debug.level = 0)
  if (is.finite(nmax)) args$nmax <- nmax
  if (!is.null(beta)) args$beta <- beta
  cv <- do.call(krige.cv, args)
  for (r in unique(round(seq(1, n, length.out = 4)))) for (pt in 0:1) {
    want <- c(cv$var1.pred[r], cv$var1.var[r])[pt + 1]
    add("cv", c(hdr(mode, n, p, st, if (is.finite(nmax)) nmax else 0, -1, 0), pt, r - 1, 0, 0, fold, if (is.null(beta)) rep(0, p) else beta, flat(st), rows(d, X)), want)
  }
}
# conditional simulation under set.seed
for (rep in 1:12) {
  fi <- (rep - 1) %% 4 + 1; f <- forms[[fi]]; n <- sample(12:22, 1); d <- dat(n)
  st <- rmodel(TRUE, rep %% 2 == 0); m <- build(st)
  nnew <- sample(6:10, 1); nd <- data.frame(x = runif(nnew, 0.05, 0.95), y = runif(nnew, 0.05, 0.95), w = round(runif(nnew), 3))
  X <- model.matrix(f, d); X0 <- model.matrix(delete.response(terms(f)), nd); p <- ncol(X)
  nsim <- c(1, 3, 4)[rep %% 3 + 1]; seed <- sample(1:100000, 1)
  known <- rep %% 2 == 0; beta <- if (known) rnorm(p, 0, 0.5) else NULL
  nmax <- if (rep %% 4 == 3) sample(8:12, 1) else Inf
  args <- list(f, ~x + y, d, nd, model = m, nsim = nsim, debug.level = 0)
  if (is.finite(nmax)) args$nmax <- nmax
  if (known) args$beta <- beta
  set.seed(seed)
  s <- suppressMessages(do.call(krige, args))
  sims <- as.matrix(s[, grep("sim", names(s)), drop = FALSE])
  for (j in seq_len(nsim)) for (r in seq_len(nnew)) add("sim", c(hdr(0, n, p, st, if (is.finite(nmax)) nmax else 0, -1, 0), nsim, nnew, seed, as.numeric(known), (j - 1) * nnew + r - 1, if (known) beta else rep(0, p), flat(st), rows(d, X), newrows(nd, X0)), sims[r, j], rel = 1e-9)
}
emit("gstatkrige", "gstat", list(cases))
