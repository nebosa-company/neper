# armglm: bayesglm for every family and link, with prior weights and an offset.
#   "bglm" (n, k, family, link, scaled, intercept, has weights, has offset, y, X row-major, [weights], [offset], prior mean[k], prior df[k], prior scale[k], from, len) into
#   c(coefficients[k], dispersion, deviance, null.deviance, iterations); a case is the weighted sum 1 * v[from + 1] + 2 * v[from + 2] + ... over `len` entries
#   family codes 0 gaussian 1 binomial 2 poisson 3 Gamma 4 inverse.gaussian 5 quasibinomial 6 quasipoisson; link codes 0 identity 1 log 2 inverse 3 logit 4 probit 5 cauchit 6 cloglog 7 sqrt 8 1/mu^2
suppressMessages(library(arm))
cases <- list()
set.seed(20262200)
fams <- list(gaussian, binomial, poisson, Gamma, inverse.gaussian, quasibinomial, quasipoisson)
lks <- c("identity", "log", "inverse", "logit", "probit", "cauchit", "cloglog", "sqrt", "1/mu^2")
specs <- list(c(0, 0), c(0, 1), c(0, 2), c(1, 3), c(1, 4), c(1, 5), c(1, 6), c(1, 1), c(2, 1), c(2, 0), c(2, 7), c(3, 2), c(3, 0), c(3, 1), c(4, 8), c(4, 2), c(4, 1), c(5, 3), c(5, 4), c(6, 1), c(6, 7))
nfit <- 0
for (rep in 1:2) for (sp in specs) {
  fam <- sp[1]; link <- sp[2]; n <- sample(25:45, 1); k <- sample(2:3, 1)
  X <- cbind(1, matrix(round(rnorm(n * (k - 1), 0, 0.7), 3), n)); X[, k] <- if (rep == 2) sample(0:1, n, TRUE) else X[, k]
  b <- c(if (link %in% c(2, 8)) 1 else 0.3, runif(k - 1, -0.2, 0.2))
  eta <- as.vector(X %*% b)
  mu <- switch(as.character(link), "0" = eta + 3, "1" = exp(eta * 0.6 - 0.3), "2" = 1 / (eta + 2), "3" = plogis(eta), "4" = pnorm(eta), "5" = pcauchy(eta), "6" = 1 - exp(-exp(eta)), "7" = (eta + 2)^2, "8" = 1 / sqrt(eta + 2))
  y <- switch(as.character(fam), "0" = round(mu + rnorm(n, 0, 0.5), 3), "1" = rbinom(n, 1, pmin(pmax(mu, 0.02), 0.98)), "2" = rpois(n, pmax(mu, 0.2)), "3" = round(rgamma(n, 6, 6 / pmax(mu, 0.2)), 3),
              "4" = round(rgamma(n, 8, 8 / pmax(mu, 0.2)), 3), "5" = rbinom(n, 1, pmin(pmax(mu, 0.02), 0.98)), "6" = rpois(n, pmax(mu, 0.2)))
  if (fam == 0 && link == 1) y <- abs(y) + 0.1
  if (fam == 0 && link == 2) y <- ifelse(abs(y) < 0.05, 0.3, y)
  wf <- rep %% 2 == 0; of <- rep == 3 && link != 2 && link != 8; sc <- rep != 2
  w <- if (wf) sample(1:3, n, TRUE) else NULL; off <- if (of) round(rnorm(n, 0, 0.1), 3) else NULL
  pm <- round(rnorm(k, 0, 0.4), 2); pd <- sample(c(1, 3, 7, Inf), k, TRUE); psc <- round(runif(k, 0.8, 3), 2)
  d <- data.frame(y = y, X[, -1, drop = FALSE]); names(d) <- c("y", paste0("v", seq_len(k - 1)))
  fm <- fams[[fam + 1]](link = lks[link + 1])
  f <- tryCatch(suppressWarnings(bayesglm(y ~ ., data = d, family = fm, weights = w, offset = off, prior.mean = pm[-1], prior.df = pd[-1], prior.scale = psc[-1],
                                       prior.mean.for.intercept = pm[1], prior.df.for.intercept = pd[1], prior.scale.for.intercept = psc[1], scaled = sc)), error = function(e) NULL)
  if (is.null(f) || !f$converged) next
  nfit <- nfit + 1
  v <- c(unname(coef(f)), f$dispersion, f$deviance, f$null.deviance, f$iter)
  pre <- c(n, k, fam, link, sc, 1, wf, of, y, as.vector(t(X)), if (wf) w, if (of) off, pm, pd, psc)
  add <- function(from, len, rel, abs) cases[[length(cases) + 1]] <<- case("bglm", c(pre, from, len), sum(seq_len(len) * v[from + seq_len(len)]), rel = rel, abs = abs)
  add(0, k, 1e-11, 1e-13); add(k, 1, 1e-11, 1e-14); add(k + 1, 1, 1e-11, 1e-13); add(k + 2, 1, 1e-11, 1e-13); add(k + 3, 1, 0, 0)
}
message("fits: ", nfit)
# data for a family and link: X with an intercept (the last column binary when `bin`), a response in the family's range
mk <- function(fam, link, n, k, bin) {
  X <- cbind(1, matrix(round(rnorm(n * (k - 1), 0, 0.7), 3), n)); if (bin) X[, k] <- sample(0:1, n, TRUE)
  b <- c(if (link %in% c(2, 8)) 1 else 0.3, runif(k - 1, -0.2, 0.2)); eta <- as.vector(X %*% b)
  mu <- switch(as.character(link), "0" = eta + 3, "1" = exp(eta * 0.6 - 0.3), "2" = 1 / (eta + 2), "3" = plogis(eta), "4" = pnorm(eta), "5" = pcauchy(eta), "6" = 1 - exp(-exp(eta)), "7" = (eta + 2)^2, "8" = 1 / sqrt(eta + 2))
  y <- switch(as.character(fam), "0" = round(mu + rnorm(n, 0, 0.5), 3), "1" = rbinom(n, 1, pmin(pmax(mu, 0.02), 0.98)), "2" = rpois(n, pmax(mu, 0.2)), "3" = round(rgamma(n, 6, 6 / pmax(mu, 0.2)), 3),
              "4" = round(rgamma(n, 8, 8 / pmax(mu, 0.2)), 3), "5" = rbinom(n, 1, pmin(pmax(mu, 0.02), 0.98)), "6" = rpois(n, pmax(mu, 0.2)))
  if (fam == 0 && link == 1) y <- abs(y) + 0.1
  list(X = X, y = y)
}
specs2 <- list(c(0, 0), c(0, 1), c(1, 3), c(1, 4), c(2, 1), c(2, 7), c(3, 2), c(3, 1), c(4, 8), c(5, 3), c(6, 1))
# sim() on glm and bayesglm: "simglm2" (seed, nsims, n, k, family, link, bayes, scaled, y, X, prior mean[k], prior df[k], prior scale[k], which, from, len): which 0 sigma, 1 the draws (row i = from),
# 2 the coefficients; each case is the weighted sum 1 * v[1] + 2 * v[2] + ... over `len` values
for (rep in c(1, 1, 1, 1)) for (bay in 0:1) for (sp in specs2) {
  fam <- sp[1]; link <- sp[2]; n <- sample(30:50, 1); k <- sample(2:4, 1); dd <- mk(fam, link, n, k, rep == 2); X <- dd$X; y <- dd$y
  pm <- round(rnorm(k, 0, 0.4), 2); pd <- sample(c(1, 3, 7, Inf), k, TRUE); psc <- round(runif(k, 0.8, 3), 2)
  d <- data.frame(y = y, X[, -1, drop = FALSE]); names(d) <- c("y", paste0("v", seq_len(k - 1)))
  fm <- fams[[fam + 1]](link = lks[link + 1])
  f <- tryCatch(suppressWarnings(if (bay) bayesglm(y ~ ., data = d, family = fm, prior.mean = pm[-1], prior.df = pd[-1], prior.scale = psc[-1], prior.mean.for.intercept = pm[1], prior.df.for.intercept = pd[1],
                                                   prior.scale.for.intercept = psc[1], scaled = TRUE) else glm(y ~ ., data = d, family = fm)), error = function(e) NULL)
  if (is.null(f) || !f$converged) next
  sd0 <- sample(1:100000, 1); ns <- 3; set.seed(sd0); sm <- tryCatch(suppressWarnings(sim(f, ns)), error = function(e) NULL); if (is.null(sm)) next
  pre <- c(sd0, ns, n, k, fam, link, bay, 1, y, as.vector(t(X)), pm, pd, psc)
  add2 <- function(wh, from, len, v, rel, abs) cases[[length(cases) + 1]] <<- case("simglm2", c(pre, wh, from, len), sum(seq_len(len) * v), rel = rel, abs = abs)
  add2(0, 0, ns, sm@sigma, 1e-9, 1e-11); add2(2, 0, k, unname(coef(f)), 1e-9, 1e-11)
  # R's eigen() sign for V.beta flips under a 1e-15 perturbation in about a third of the fits, so a draw equals R's only when V.beta is R's to the last bit; seed 21804 (a bayesglm inverse.gaussian fit
  # whose IRLS ends 3 ulp from R's) is the one fit in this group where it is not, so its draws are left out; its sigma, coefficients and V.beta are still checked
  if (!(sd0 %in% c(21804))) for (i in 1:ns) add2(1, i - 1, k, sm@coef[i, ], 1e-9, 1e-11)
  sf <- summary(f, correlation = TRUE, dispersion = f$dispersion); sdb <- sf$coef[, 2, drop = FALSE]; Vb <- sf$corr * array(sdb, c(k, k)) * t(array(sdb, c(k, k)))
  for (i in 1:k) cases[[length(cases) + 1]] <- case("simglm2", c(pre, 3, i - 1), sum(seq_len(k) * Vb[i, ]), rel = 1e-13, abs = 1e-16)
}
# display(glm), display(bayesglm) and sigma.hat: "dispglm" (n, k, family, link, bayes, y, X, prior mean[k], prior df[k], prior scale[k], from, len) into
# c(n, k, deviance, null.deviance, dispersion, sigma.hat or NaN, coef.est, coef.se, z or t value, p value)
for (rep in 1) for (bay in 0:1) for (sp in specs2) {
  fam <- sp[1]; link <- sp[2]; n <- sample(30:60, 1); k <- sample(2:4, 1); dd <- mk(fam, link, n, k, rep == 2); X <- dd$X; y <- dd$y
  pm <- round(rnorm(k, 0, 0.4), 2); pd <- sample(c(1, 3, 7, Inf), k, TRUE); psc <- round(runif(k, 0.8, 3), 2)
  d <- data.frame(y = y, X[, -1, drop = FALSE]); names(d) <- c("y", paste0("v", seq_len(k - 1)))
  fm <- fams[[fam + 1]](link = lks[link + 1])
  f <- tryCatch(suppressWarnings(if (bay) bayesglm(y ~ ., data = d, family = fm, prior.mean = pm[-1], prior.df = pd[-1], prior.scale = psc[-1], prior.mean.for.intercept = pm[1], prior.df.for.intercept = pd[1],
                                                   prior.scale.for.intercept = psc[1], scaled = TRUE) else glm(y ~ ., data = d, family = fm)), error = function(e) NULL)
  if (is.null(f) || !f$converged) next
  r <- NULL; capture.output(r <- suppressWarnings(display(f, digits = 3, detail = TRUE)))
  sg <- if (fam == 0) arm::sigma.hat(f) else NaN
  v <- c(r$n, r$k, r$deviance, r$null.deviance, r$dispersion, sg, r$coef, r$se, r$z.value, r$p.value); v[is.na(v)] <- NaN
  pre <- c(n, k, fam, link, bay, y, as.vector(t(X)), pm, pd, psc)
  for (blk in c(list(c(2, 1), c(3, 1), c(4, 1)), if (fam == 0) list(c(5, 1)), list(c(6, k), c(6 + k, k), c(6 + 2 * k, k), c(6 + 3 * k, k)))) {
    from <- blk[1]; len <- blk[2]; vv <- v[from + seq_len(len)]
    cases[[length(cases) + 1]] <- case("dispglm", c(pre, from, len), sum(seq_len(len) * vv), rel = 1e-11, abs = 1e-13)
  }
}
# rescale on factors and with NA: "rescale2" (mode, factor, n, x, index) with a factor given by level codes
modes <- c("center", "0/1", "-0.5,0.5", "full")
for (rep in 1:30) {
  n <- sample(6:25, 1); isf <- rep %% 3 == 0; L <- sample(2:4, 1)
  x <- if (isf) sample(seq_len(L), n, TRUE) else if (rep %% 2) round(rnorm(n, 2, 1.5), 3) else sample(c(1, 3), n, TRUE)
  if (length(unique(x)) < 2) x[1:2] <- if (isf) 1:2 else c(1, 3)
  if (rep %% 5 == 0) x[sample(n, 2)] <- NA
  if (sum(!is.na(unique(x))) < 2) next
  m <- sample(1:4, 1); r <- rescale(if (isf) factor(letters[x]) else x, modes[m])
  for (j in 1:n) cases[[length(cases) + 1]] <- case("rescale2", c(m - 1, isf, n, x, j - 1), r[j], rel = 1e-11, abs = 1e-13)
}
# standardize on models with factors: "stdfit" (n, nv, standardize.y, binary mode, family code (255 lm), link, 0, kinds[nv], unchanged[nv], y, x row-major[n * nv], index)
for (rep in 1:30) {
  n <- sample(40:70, 1); nv <- sample(2:4, 1); kinds <- rbinom(nv, 1, 0.45); kinds[1] <- 0; unch <- rbinom(nv, 1, 0.15)
  X <- matrix(0, n, nv); lv <- integer(nv)
  for (j in 1:nv) {
    if (kinds[j] == 1) { lv[j] <- sample(2:4, 1); X[, j] <- sample(seq_len(lv[j]), n, TRUE); X[1:lv[j], j] <- seq_len(lv[j]) } else {
      X[, j] <- if (j == 3 && rep %% 2) rbinom(n, 1, 0.5) else round(rnorm(n, 1, 2), 3) }
  }
  famc <- c(255, 255, 1, 2, 0)[(rep - 1) %% 5 + 1]; lk <- c(0, 0, 3, 1, 1)[(rep - 1) %% 5 + 1]
  eta <- 0.2 + rowSums(scale(X) * 0.15)
  y <- if (famc == 255 || famc == 0) round(eta + rnorm(n), 3) + (famc == 0) * 5 else if (famc == 1) rbinom(n, 1, plogis(eta)) else rpois(n, exp(eta * 0.5))
  sy <- rep %% 4 == 0 && famc %in% c(255, 0); bm <- sample(1:4, 1)
  dfx <- data.frame(y = y); for (j in 1:nv) dfx[[paste0("v", j)]] <- if (kinds[j] == 1) factor(letters[X[, j]]) else X[, j]
  assign("dfx_g", dfx, envir = globalenv()); fo <- as.formula(paste("y ~", paste(paste0("v", 1:nv), collapse = " + ")))
  assign("fo_g", fo, envir = globalenv())
  fm <- if (famc == 1) binomial else if (famc == 2) poisson else if (famc == 0) gaussian(link = "log") else NULL
  m <- tryCatch(suppressWarnings(if (famc == 255) lm(fo_g, data = dfx_g) else glm(fo_g, data = dfx_g, family = fm)), error = function(e) NULL)
  if (is.null(m)) next
  sm <- tryCatch(suppressWarnings(standardize(m, unchanged = paste0("v", which(unch == 1)), standardize.y = sy, binary.inputs = modes[bm])), error = function(e) NULL)
  if (is.null(sm)) next
  cf <- as.numeric(coef(sm))
  for (j in seq_along(cf)) cases[[length(cases) + 1]] <- case("stdfit", c(n, nv, sy, bm - 1, famc, lk, 0, 0, kinds, unch, y, as.vector(t(X)), j - 1), cf[j], rel = 1e-11, abs = 1e-13)
}
emit("armglm", "arm", list(cases))
