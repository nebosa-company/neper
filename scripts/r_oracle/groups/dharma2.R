# DHARMa part two: simulate() of fitted models and simulateResiduals, the traditional method and rotation, the bootstrap outlier test, the exact
# dwtest p value, recalculateResiduals, one-sided KS, the Pearson dispersion test, testCategorical, testGeneric, Moran alternatives.
# Layouts (n obs, ns simulations, sd the seed):
#   H = (n, ns, sd, obs[n], sims row-major n by ns)
#   M = (n, ns, sd, kind, method, integer, rot, p1, p2, obs[n], mu[n], w[n]) for the model cases; kind 1 lm, 2 weighted gaussian glm, 3 poisson,
#       4 binomial 0/1, 5 binomial proportion with weights, 6 binomial cbind, 7 Gamma, 8 lmer, 9 glmer poisson; a rotation matrix or the
#       extras (nboot, margin, alt, seed2) of "mboot_*" follow
suppressMessages({ library(DHARMa); library(lmtest); library(lme4) })
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-12)
wsum <- function(m) sum(m * (1 + (outer(1:nrow(m), 1:ncol(m), function(i, j) i * 7 + j * 3) %% 11)))
posw <- function(v) sum(v * seq_along(v))
quiet <- function(e) suppressMessages(suppressWarnings(e))
ALT <- c("two.sided", "greater", "less")
HH <- function(n, ns, sd, obs, sims) c(n, ns, sd, obs, as.vector(t(sims)))
gen <- function(n, ns, type) {
  sd <- sample(1:10000, 1)
  if (type == "norm") { mu <- rnorm(n); y <- mu + rnorm(n) * sample(c(0.7, 1, 1.6), 1); sims <- matrix(rnorm(n * ns, rep(mu, ns)), n, ns); int <- FALSE }
  else if (type == "round") { mu <- rnorm(n) * 2; y <- round(mu + rnorm(n)); sims <- matrix(round(rnorm(n * ns, rep(mu, ns))), n, ns); int <- FALSE }
  else { mu <- rexp(n) * 3; y <- rpois(n, mu); sims <- matrix(rpois(n * ns, rep(mu, ns)), n, ns); int <- TRUE }
  list(n = n, ns = ns, sd = sd, y = y, sims = sims, mu = mu, int = int)
}
mkd <- function(o, ...) quiet(createDHARMa(o$sims, o$y, fittedPredictedResponse = o$mu, integerResponse = o$int, seed = o$sd, ...))
HO <- function(o) HH(o$n, o$ns, o$sd, o$y, o$sims)

# ---- dwtest p value, exact (n < 100) and normal approximation ----
for (n in c(4, 8, 20, 45, 60, 100, 140)) {
  o <- gen(n, 12, "norm"); r <- mkd(o); tm <- sample(n)
  for (al in 0:2) {
    d <- quiet(testTemporalAutocorrelation(r, time = tm, alternative = ALT[al + 1], plot = FALSE))
    add("dw_pD", c(HO(o), tm, al), d$p.value, rel = 1e-8)
  }
}

# Pan's routine run on the closed-form eigenvalues (R amplifies the 1e-15 difference to its own LAPACK eigenvalues into 1e-8 to 1e-4 past n of about 45)
for (n in c(5, 12, 30, 45, 60, 70, 80, 90, 99)) for (rep in 1:2) {
  dw <- runif(1, 0.5, 3.5)
  evc <- 2 - 2 * cos(pi * (n - 1):1 / n)
  add("pan_cl", c(n, dw), .Fortran("pan", as.double(c(dw, evc)), as.integer(n - 1), as.double(0), as.integer(15), x = double(1), PACKAGE = "lmtest")$x, rel = if (n <= 70) 1e-9 else 1e-6)
}

# ---- fitted models ----
modelcase <- function(kind, m, mu, w, p1, p2, ns, sd, method = "PIT", rot = NULL, extra = NULL, boot = NULL) {
  r <- quiet(simulateResiduals(m, n = ns, seed = sd, method = method, rotation = rot))
  rotc <- if (is.null(rot)) 0 else if (is.matrix(rot)) 2 else 1
  a <- c(length(mu), ns, sd, kind, if (method == "PIT") 0 else 1, as.numeric(r$integerResponse), rotc, p1, p2, r$observedResponse, mu, w)
  if (rotc == 2) a <- c(a, as.vector(t(rot)))
  add("sim", a, wsum(r$simulatedResponse)); add("sr", a, posw(r$scaledResiduals))
  if (!is.null(boot)) {
    b <- c(a, boot$nboot, boot$margin, boot$alt, boot$seed2)
    set.seed(boot$seed2)
    to <- quiet(testOutliers(r, type = "bootstrap", nBoot = boot$nboot, margin = c("both", "upper", "lower")[boot$margin + 1], alternative = ALT[boot$alt + 1], plot = FALSE))
    add("mboot_stat", b, as.numeric(to$statistic)); add("mboot_p", b, to$p.value)
    add("mboot_lo", b, as.numeric(to$conf.int[1])); add("mboot_hi", b, as.numeric(to$conf.int[2]))
  }
  r
}
for (rep in 1:3) {
  n <- sample(c(25, 40, 60), 1); ns <- sample(c(100, 250), 1); sd <- sample(1:10000, 1)
  x <- rnorm(n); y <- 1 + 2 * x + rnorm(n) * 1.5; m <- lm(y ~ x)
  modelcase(1, m, fitted(m), rep(1, n), deviance(m), df.residual(m), ns, sd)
  modelcase(1, m, fitted(m), rep(1, n), deviance(m), df.residual(m), ns, sd, method = "traditional")
  w <- sample(1:4, n, TRUE); y2 <- 1 + x + rnorm(n) / sqrt(w); m2 <- glm(y2 ~ x, weights = w)
  modelcase(2, m2, fitted(m2), w, deviance(m2), df.residual(m2), ns, sd)
  y3 <- rpois(n, exp(0.3 + 0.5 * x)); m3 <- glm(y3 ~ x, family = poisson)
  modelcase(3, m3, fitted(m3), rep(1, n), 0, 0, ns, sd)
  modelcase(3, m3, fitted(m3), rep(1, n), 0, 0, ns, sd, method = "traditional")
  modelcase(3, m3, fitted(m3), rep(1, n), 0, 0, ns, sd, boot = list(nboot = 50, margin = rep %% 3, alt = rep - 1, seed2 = 100 + rep))
  modelcase(3, m3, fitted(m3), rep(1, n), 0, 0, ns, sd, method = "traditional", boot = list(nboot = 40, margin = 0, alt = 0, seed2 = 200 + rep))
  y4 <- rbinom(n, 1, plogis(0.2 + x)); m4 <- glm(y4 ~ x, family = binomial)
  modelcase(4, m4, fitted(m4), rep(1, n), 0, 0, ns, sd)
  sz <- sample(3:12, n, TRUE); pr <- rbinom(n, sz, plogis(0.1 + 0.7 * x)) / sz
  m5 <- glm(pr ~ x, family = binomial, weights = sz)
  modelcase(5, m5, fitted(m5), sz, 0, 0, ns, sd)
  m6 <- glm(cbind(round(pr * sz), sz - round(pr * sz)) ~ x, family = binomial)
  modelcase(6, m6, fitted(m6), sz, 0, 0, ns, sd)
  modelcase(6, m6, fitted(m6), sz, 0, 0, ns, sd, method = "traditional")
  y7 <- rgamma(n, shape = 3, rate = 3 / exp(0.5 + 0.3 * x)); gw <- sample(1:2, n, TRUE); m7 <- glm(y7 ~ x, family = Gamma(link = "log"), weights = gw)
  modelcase(7, m7, fitted(m7), gw, deviance(m7), df.residual(m7), ns, sd)
  m7b <- glm(y7 ~ x, family = Gamma(link = "log"))
  modelcase(7, m7b, fitted(m7b), rep(1, n), deviance(m7b), df.residual(m7b), ns, sd)
  g <- factor(rep(1:5, length.out = n)); u <- rnorm(5)[g]
  y8 <- 1 + x + u + rnorm(n); d8 <- data.frame(y8, x, g)
  m8 <- quiet(lmer(y8 ~ x + (1 | g), data = d8))
  modelcase(8, m8, as.vector(fitted(m8)), rep(1, n), sigma(m8), 0, ns, sd)
  y9 <- rpois(n, exp(0.2 + 0.4 * x + u * 0.5)); d9 <- data.frame(y9, x, g)
  m9 <- quiet(glmer(y9 ~ x + (1 | g), family = poisson, data = d9))
  modelcase(9, m9, as.vector(fitted(m9)), rep(1, n), 0, 0, ns, sd)
}
# rotation: estimated (more simulations than observations) and a given covariance matrix
for (rep in 1:3) {
  n <- sample(8:14, 1); ns <- 300; sd <- sample(1:10000, 1)
  x <- rnorm(n); y <- 1 + x + rnorm(n); m <- lm(y ~ x)
  S <- crossprod(matrix(rnorm(n * n), n)) + diag(n) * 2
  modelcase(1, m, fitted(m), rep(1, n), deviance(m), df.residual(m), ns, sd, rot = "estimated")
  modelcase(1, m, fitted(m), rep(1, n), deviance(m), df.residual(m), ns, sd, rot = S)
  y3 <- rpois(n, exp(0.3 + 0.5 * x)); m3 <- glm(y3 ~ x, family = poisson)
  modelcase(3, m3, fitted(m3), rep(1, n), 0, 0, ns, sd, rot = "estimated")
}

# ---- traditional and rotated residuals from given simulations ----
for (rep in 1:8) {
  type <- c("norm", "round", "pois")[rep %% 3 + 1]; n <- sample(15:40, 1); ns <- sample(c(30, 60), 1)
  o <- gen(n, ns, type)
  for (meth in c("PIT", "traditional")) for (int in unique(c(o$int, TRUE))) {
    o2 <- o; o2$int <- int
    r <- mkd(o2, method = meth)
    add("q_sr", c(HO(o2), if (meth == "PIT") 0 else 1, as.numeric(int), 0), posw(r$scaledResiduals))
  }
  if (rep %% 2 == 0) {
    n2 <- sample(6:12, 1); o3 <- gen(n2, 200, type); S <- crossprod(matrix(rnorm(n2 * n2), n2)) + diag(n2)
    o3$int <- FALSE
    r1 <- mkd(o3, rotation = "estimated"); r2 <- mkd(o3, rotation = S)
    add("q_sr", c(HO(o3), 0, 0, 1), posw(r1$scaledResiduals)); add("q_sr", c(HO(o3), 0, 0, 2, as.vector(t(S))), posw(r2$scaledResiduals))
  }
}

# ---- outliers: binomial margins and alternatives, bootstrap ----
for (rep in 1:4) {
  type <- c("norm", "pois", "round")[rep %% 3 + 1]; n <- sample(30:50, 1); ns <- sample(c(40, 60), 1)
  o <- gen(n, ns, type); o$y[sample(n, 3)] <- max(o$sims) + 5; o$y[sample(n, 2)] <- min(o$sims) - 5
  r <- mkd(o)
  for (mg in 0:2) for (al in unique(c((mg + rep) %% 3, 0))) {
    to <- quiet(testOutliers(r, type = "binomial", margin = c("both", "upper", "lower")[mg + 1], alternative = ALT[al + 1], plot = FALSE))
    add("nout_m", c(HO(o), mg, al), as.numeric(to$statistic)); add("pout_m", c(HO(o), mg, al), to$p.value)
  }
  for (mg in 0:2) {
    al <- (rep + mg) %% 3; s2 <- sample(1:10000, 1); nb <- sample(c(30, ns), 1)
    set.seed(s2)
    tb <- quiet(testOutliers(r, type = "bootstrap", nBoot = nb, margin = c("both", "upper", "lower")[mg + 1], alternative = ALT[al + 1], plot = FALSE))
    a <- c(HO(o), nb, mg, al, s2)
    add("boot_p", a, tb$p.value)
    add("boot_lo", a, as.numeric(tb$conf.int[1])); add("boot_hi", a, as.numeric(tb$conf.int[2]))
  }
}

# ---- recalculateResiduals ----
for (rep in 1:12) {
  type <- c("norm", "pois", "round")[rep %% 3 + 1]; n <- sample(24:40, 1); ns <- 60
  o <- gen(n, ns, type); r <- mkd(o)
  ng0 <- sample(4:10, 1); grp <- sample(1:ng0, n, TRUE) * 3; sel <- rep(TRUE, n)
  if (rep %% 2 == 0) sel <- runif(n) < 0.75
  if (rep %% 4 == 0) grp <- seq_len(n)
  agg <- (rep - 1) %% 4; aggf <- list(sum, mean, max, min)[[agg + 1]]
  meth <- if (rep %% 3 == 0) "traditional" else "PIT"; s3 <- sample(1:10000, 1)
  rot <- NULL; rotc <- 0; sg <- NULL
  ngv <- length(unique(grp[sel]))
  if (rep == 5 || rep == 10) { rot <- "estimated"; rotc <- 1; meth <- "PIT"; ns2 <- ns }
  if (rotc == 1 && ngv >= ns) next
  rc <- quiet(recalculateResiduals(r, group = grp, sel = sel, aggregateBy = aggf, seed = s3, method = meth, rotation = rot))
  a <- c(HO(o), s3, agg, if (meth == "PIT") 0 else 1, as.numeric(o$int), rotc, grp, as.numeric(sel), o$mu)
  add("rc_ng", a, length(rc$scaledResiduals)); add("rc_sr", a, posw(rc$scaledResiduals)); add("rc_obs", a, posw(rc$observedResponse))
  add("rc_sim", a, wsum(rc$simulatedResponse))
}
# a rotation matrix and the aggregation without grouping (sel only)
for (rep in 1:2) {
  n <- 20; ns <- 100; o <- gen(n, ns, "norm"); r <- mkd(o)
  grp <- rep(1:6, length.out = n); S <- crossprod(matrix(rnorm(36), 6)) + diag(6); s3 <- sample(1:10000, 1)
  rc <- quiet(recalculateResiduals(r, group = grp, aggregateBy = sum, seed = s3, rotation = S))
  a <- c(HO(o), s3, 0, 0, 0, 2, grp, rep(1, n), o$mu, as.vector(t(S)))
  add("rc_sr", a, posw(rc$scaledResiduals))
  sel <- seq_len(n) %% 3 != 0
  rc <- quiet(recalculateResiduals(r, sel = sel, seed = s3))
  a <- c(HO(o), s3, 0, 0, 0, 0, rep(NA, 0), as.numeric(sel), o$mu)
  add("rc_nogroup_sr", a, posw(rc$scaledResiduals)); add("rc_nogroup_ng", a, length(rc$scaledResiduals))
}

# ---- one-sided KS (testUniformity), n < 100 exact and n >= 100 asymptotic ----
for (n in c(12, 30, 60, 99, 100, 150)) for (al in 1:2) {
  o <- gen(n, 12, c("norm", "round")[al]); r <- mkd(o)
  u <- quiet(testUniformity(r, alternative = c("two.sided", "greater", "less")[al + 1], plot = FALSE))
  add("ksalt_stat", c(HO(o), al), as.numeric(u$statistic)); add("ksalt_p", c(HO(o), al), u$p.value)
}

# ---- Pearson dispersion ----
for (rep in 1:5) {
  n <- sample(30:80, 1); x <- rnorm(n); y <- rpois(n, exp(0.5 + 0.4 * x) * c(1, 1, 2, 3, 1)[rep]); m <- glm(y ~ x, family = poisson)
  for (al in 0:2) {
    t <- quiet(testDispersion(m, type = "PearsonChisq", alternative = ALT[al + 1], plot = FALSE))
    a <- c(df.residual(m), al, residuals(m, "pearson"))
    add("pc_ratio", a, as.numeric(t$statistic)); add("pc_p", a, t$p.value)
  }
}

# ---- testCategorical and testGeneric ----
for (rep in 1:3) {
  type <- c("norm", "pois", "round")[rep %% 3 + 1]; n <- sample(40:60, 1); o <- gen(n, 25, type); r <- mkd(o)
  k <- sample(2:5, 1); cat <- sample(1:k, n, TRUE) * 2
  tc <- quiet(testCategorical(r, cat, plot = FALSE))
  a <- c(HO(o), cat)
  for (i in seq_len(k)) { add("cat_p", c(a, i - 1), tc$uniformity$p.value[i]); add("cat_padj", c(a, i - 1), tc$uniformity$p.value.cor[i]) }
  add("cat_lev_F", a, tc$homogeneity$`F value`[1]); add("cat_lev_p", a, tc$homogeneity$`Pr(>F)`[1])
  for (kind in 0:2) for (al in (if (kind == rep - 1) 0:2 else 0)) {
    f <- list(mean, max, stats::sd)[[kind + 1]]
    tg <- quiet(testGeneric(r, summary = f, alternative = ALT[al + 1], plot = FALSE))
    add("gen_ratio", c(a, kind, al), as.numeric(tg$statistic)); add("gen_p", c(a, kind, al), tg$p.value)
  }
}

# ---- Moran alternatives and a distance matrix ----
for (rep in 1:3) {
  n <- sample(20:40, 1); o <- gen(n, 20, "norm"); r <- mkd(o)
  xs <- round(runif(n, 0, 10), 4); ys <- round(runif(n, 0, 10), 4); D <- as.matrix(dist(cbind(xs, ys)))
  for (al in 0:2) {
    mi <- quiet(testSpatialAutocorrelation(r, x = xs, y = ys, alternative = ALT[al + 1], plot = FALSE))
    add("mi_alt_p", c(HO(o), xs, ys, al), mi$p.value)
    md <- quiet(testSpatialAutocorrelation(r, distMat = D, alternative = ALT[al + 1], plot = FALSE))
    add("mi_dm_p", c(HO(o), as.vector(t(D)), al), md$p.value); add("mi_dm_obs", c(HO(o), as.vector(t(D)), al), as.numeric(md$statistic["observed"]))
  }
}
emit("dharma2", c("DHARMa", "lmtest", "lme4"), list(cases))
