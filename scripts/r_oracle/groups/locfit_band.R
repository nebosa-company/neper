# locfit confidence bands, one predictor.
#   crit(const, d = 1, cov, rdf): args (k0, k1, m, cov, rdf), fn "crit"; the gaussian (rdf 0) and t process critical values.
#   scb(y ~ lp(x, ...), kern, family): args (n, kern, deg, fam, nn, h, 3, 0, mg, quasi, 0, x[n] sorted, y[n]);
#   fn k0 k1 (kappa0 constants), cr (the 95% simultaneous critical value), cf sd lo up (coef, sd, lower, upper of the
#   scb object at its 20 grid points, summed by rank).
# Tolerance: the critical value is Newton-iterated to a relative tail error of 1e-10, so 1e-9; the tube constant and
# the band share the fit's libm sensitivity (see locfit.R): 1e-8 for the gaussian kernel and non-gaussian families.
suppressMessages(library(locfit))
cases <- list()
set.seed(20261231)
wsum <- function(v) sum(v * seq_along(v))
for (i in 1:60) {
  m <- if (i %% 3 == 0) 1 else 2
  k0 <- exp(runif(1, log(0.05), log(18)))
  k1 <- if (i %% 5 == 0) runif(1, 0.3, 2) else 1
  cov <- c(0.8, 0.9, 0.95, 0.99)[i %% 4 + 1]
  rdf <- c(0, 0, 3.5, 10, 40, 250)[i %% 6 + 1]
  const <- if (m == 1) k0 else c(k0, k1)
  cr <- crit(const = const, d = 1, cov = cov, rdf = rdf)$crit.val
  cases[[length(cases) + 1]] <- case("crit", c(k0, if (m == 2) k1 else 0, m, cov, rdf), cr, rel = 1e-9, abs = 1e-12)
}
cases[[length(cases) + 1]] <- case("crit", c(0, 1, 2, 0.95, 0), crit(const = c(0, 1), d = 1, cov = 0.95)$crit.val, rel = 1e-9, abs = 1e-12)
kerns <- c(1, 2, 3, 4, 5, 6, 7, 11)
knames <- c("rect", "epan", "bisq", "tcub", "triw", "gauss", "tria", "expl")
fnames <- c("gaussian", "binomial", "poisson")
for (cfg in 1:30) {
  ki <- (cfg - 1) %% 8 + 1; kern <- kerns[ki]
  fam <- c(0, 0, 0, 1, 2)[(cfg * 7 - 1) %% 5 + 1]
  deg <- c(2, 1, 2, 3, 0, 1, 2)[(cfg * 3) %% 7 + 1]
  n <- sample(30:50, 1)
  x <- sort(unique(round(runif(n), 5))); n <- length(x)
  mode <- cfg %% 3
  nn <- if (mode == 1) 0 else runif(1, 0.4, 0.8)
  h <- if (mode == 1) runif(1, 0.18, 0.4) else if (mode == 2) runif(1, 0.05, 0.3) else 0
  if (fam == 1) { nn <- max(nn, 0.5); if (mode == 1) h <- max(h, 0.3); deg <- min(deg, 2) }
  mu <- sin(4 * x)
  y <- if (fam == 0) round(mu + rnorm(n, 0, 0.3), 6) else if (fam == 1) rbinom(n, 1, 1 / (1 + exp(-2 * mu))) else rpois(n, exp(0.8 * mu + 0.5))
  quasi <- (cfg %% 2 == 0) * 1
  fam_name <- paste0(if (quasi) "q" else "", fnames[fam + 1])
  sc <- tryCatch(suppressWarnings(scb(y ~ lp(x, nn = nn, h = h, deg = deg), family = fam_name, kern = knames[ki])), error = function(e) NULL)
  if (is.null(sc) || any(!is.finite(c(sc$coef, sc$sd, sc$lower, sc$upper, sc$kap[1:2])))) { message("skip ", cfg, " kern ", kern, " fam ", fam, " deg ", deg, " nn ", round(nn,2), " h ", round(h,2)); next }
  a <- c(n, kern, deg, fam, nn, h, 3, 0, 20, quasi, 0, 0, 0, 0, x, y)
  trel <- if (kern == 6 || fam != 0) 1e-8 else 1e-9
  add <- function(fn, want) cases[[length(cases) + 1]] <<- case(fn, a, want, rel = trel, abs = 1e-11)
  add("k0", sc$kap[1]); add("k1", sc$kap[2])
  add("cr", crit(const = sc$kap[1:2], d = 1, cov = 0.95)$crit.val)
  add("cf", wsum(sc$coef)); add("sd", wsum(sc$sd)); add("lo", wsum(sc$lower)); add("up", wsum(sc$upper))
}
# which kernels scb accepts: R's Wd is defined for epan, bisq, tcub, triw and gauss only ("Invalid kernel in Wd" for the
# rest); fn kok, want 1 when scb answers
set.seed(20261232)
allk <- c(1, 2, 3, 4, 5, 6, 7, 8, 9, 11)
allnames <- c("rect", "epan", "bisq", "tcub", "triw", "gauss", "tria", "quqt", "6cub", "expl")
for (ki in seq_along(allk)) for (rep in 1:2) {
  n <- 40; x <- sort(unique(round(runif(n), 5))); n <- length(x)
  y <- round(sin(4 * x) + rnorm(n, 0, 0.3), 6)
  nn <- runif(1, 0.5, 0.8); deg <- c(1, 2)[rep]
  sc <- tryCatch(suppressWarnings(scb(y ~ lp(x, nn = nn, h = 0, deg = deg), kern = allnames[ki])), error = function(e) NULL)
  cases[[length(cases) + 1]] <- case("kok", c(n, allk[ki], deg, 0, nn, 0, 3, 0, 20, 0, 0, 0, 0, 0, x, y), as.numeric(!is.null(sc)), rel = 0, abs = 0)
}
emit("locfit_band", "locfit", list(cases))
