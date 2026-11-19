# flexmix with FLXMRglmfix: fixed, nested and varying coefficients (one joint weighted fit over the stacked components), varFix, the nested argument, under every family,
# EM / CEM / SEM, minprior component removal (FLXremoveComponent), concomitant priors and stepFlexmix. Data as in flexmix_ext (drawn again in the fixture from the seed).
# Case "fx" args (58 values): 0 seed, 1 n, 2 design (0: 1 + x1, 1: 1 + x1 + x2, 2: 1 + x1 + factor f), 3 family, 4 generating components, 5 k, 6 flip fraction, 7 unused,
# 8 seed2, 9 classify (0 weighted, 1 CEM, 2 SEM, 3 random), 10 start (0 cluster, 1 random), 11 minprior, 12 tolerance, 13 iter.max, 14 random-column mask over the design
# columns (bit 0 the intercept), 15 fixed-column mask, 16 nested groups, 17..19 their sizes, 20..22 their column masks, 23 varFix (0 FALSE, 1 TRUE, 2 explicit sizes in
# 24..26), 27 concomitant columns (0 or 2), 28 what, 29 idx, 30 mode (0 flexmix, 1 stepFlexmix k..k2), 31 k2, 32 nrep, 33 kq, then pr[3], beta[3][4], sg[3], gc[3][2] from 34 (slots 34..57).
# what: 0 logLik, 1 iter, 2 k, 3 prior[idx], 4 coefficient checksum (components by the final design columns), 5 sigma / shape checksum, 6 cluster checksum, 7 AIC, 8 BIC, 9 ICL,
# 10 posterior checksum, 19 fitted checksum, 20 final number of design columns, 21 design checksum, 15 stepFlexmix logLiks[idx], 22 converged.
suppressMessages(library(flexmix))
cases <- list()
cs <- function(v) sum(seq_along(v) * as.vector(v))

gen <- function(n, dtype, fam, k, q, pr, beta, sg, gc) {
  x1 <- runif(n, -1, 1)
  x2 <- if (dtype == 1) runif(n, -1, 1) else NULL
  f <- if (dtype == 2) sample(3, n, TRUE) else NULL
  w <- if (q > 0) runif(n, -1, 1) else NULL
  size <- if (fam == 2) sample(8:20, n, TRUE) else NULL
  z <- integer(n)
  if (q > 0) {
    for (i in seq_len(n)) {
      e <- exp(gc[seq_len(k), 1] + gc[seq_len(k), 2] * w[i])
      z[i] <- sample(seq_len(k), 1, prob = e / sum(e))
    }
  } else z <- sample(seq_len(k), n, TRUE, pr[seq_len(k)])
  y <- numeric(n)
  for (i in seq_len(n)) {
    b <- beta[z[i], ]
    mu <- b[1] + b[2] * x1[i]
    if (dtype == 1) mu <- mu + b[3] * x2[i]
    if (dtype == 2) mu <- mu + b[3] * (f[i] == 2) + b[4] * (f[i] == 3)
    y[i] <- if (fam == 0) rnorm(1, mu, sg[z[i]]) else if (fam == 1) rpois(1, exp(mu)) else if (fam == 2) rbinom(1, size[i], plogis(mu))
            else rgamma(1, shape = sg[z[i]], scale = (1 / mu) / sg[z[i]])
  }
  d <- data.frame(x1 = x1)
  if (dtype == 1) d$x2 <- x2
  if (dtype == 2) d$f <- factor(f)
  if (q > 0) d$w <- w
  if (fam == 2) d$y <- cbind(y, size - y) else d$y <- y
  list(d = d, z = z)
}

# spec: random formula (rhs), fixed formula, nested list(k, formula) or NULL, masks as documented
run <- function(seed, n, dtype, fam, kg, rhs, fixed, rmask, fmask, nested = NULL, gmask = c(0, 0, 0), varfix = 0, vsz = c(0, 0, 0), k = kg, pr, beta, sg,
                gc = matrix(0, 3, 2), q = 0, flip = 0.15, seed2 = seed + 1, cls = 0, start = 0, minprior = 0.05, tol = 1e-6, itermax = 200, mode = 0, k2 = k, nrep = 3) {
  set.seed(seed)
  tr <- gen(n, dtype, fam, kg, q, pr, beta, sg, gc)
  init <- tr$z
  if (start == 0) { fl <- sample(n, round(flip * n)); init[fl] <- sample(seq_len(kg), length(fl), TRUE) }
  set.seed(seed2)
  fam_name <- c("gaussian", "poisson", "binomial", "Gamma")[fam + 1]
  vf <- if (varfix == 0) FALSE else if (varfix == 1) TRUE else vsz[vsz > 0]
  mk <- function() FLXMRglmfix(fixed = fixed, nested = nested, varFix = vf, family = fam_name)
  conc <- if (q > 0) FLXPmultinom(~ w) else NULL
  ctl <- list(classify = c("weighted", "CEM", "SEM", "random")[cls + 1], minprior = minprior, tolerance = tol, iter.max = itermax)
  form <- as.formula(paste("y ~", rhs))
  ng <- if (is.null(nested)) 0 else length(nested$k)
  gs <- c(if (ng) nested$k else NULL, rep(0, 3))[1:3]
  kcur <- k
  hdr <- function(what, idx) c(seed, n, dtype, fam, kg, k, flip, 0, seed2, cls, start, minprior, tol, itermax, rmask, fmask, ng, gs, gmask, varfix, vsz, q, what, idx,
                               mode, k2, nrep, kcur, c(pr, rep(0, 3 - length(pr)))[1:3], as.vector(t(cbind(beta, matrix(0, nrow(beta), 4 - ncol(beta))))),
                               c(sg, rep(0, 3 - length(sg)))[1:3], as.vector(t(cbind(gc, matrix(0, nrow(gc), 2 - ncol(gc))))))
  add <- function(what, idx, v, rel = if (q > 0) 1e-6 else 1e-9, abs = if (q > 0) 1e-6 else 1e-9) {
    if (!is.finite(v) && !is.nan(v)) return(invisible())
    cases[[length(cases) + 1]] <<- case("fx", hdr(what, idx), v, rel = rel, abs = abs)
  }
  describe <- function(fit) {
    kk <- fit@k
    des <- fit@model[[1]]@design
    cf <- vapply(seq_len(kk), function(j) {
      v <- numeric(ncol(des)); v[des[j, ] == 1] <- unname(fit@components[[j]][[1]]@parameters$coef); v }, numeric(ncol(des)))
    add(0, 0, as.numeric(logLik(fit))); add(1, 0, fit@iter, 0, 0); add(2, 0, kk, 0, 0)
    add(7, 0, AIC(fit)); add(8, 0, BIC(fit)); add(9, 0, ICL(fit))
    for (j in seq_len(kk)) add(3, j - 1, fit@prior[j])
    add(4, 0, cs(cf))
    if (fam == 0) add(5, 0, cs(vapply(fit@components, function(cp) cp[[1]]@parameters$sigma, 0)))
    if (fam == 3) add(5, 0, cs(vapply(fit@components, function(cp) cp[[1]]@parameters$shape, 0)))
    add(6, 0, cs(fit@cluster), 0, 0)
    add(10, 0, cs(t(posterior(fit))))
    add(19, 0, cs(t(fitted(fit))))
    add(20, 0, ncol(des), 0, 0)
    add(21, 0, cs(t(des)), 0, 0)
    add(22, 0, as.numeric(fit@converged), 0, 0)
  }
  if (mode == 0) {
    fit <- tryCatch(flexmix(form, data = tr$d, k = k, cluster = if (start == 0) init else NULL, model = mk(), concomitant = conc, control = ctl), error = function(e) NULL)
    if (is.null(fit)) return(invisible(NULL))
    describe(fit)
  } else {
    st <- tryCatch(stepFlexmix(form, data = tr$d, k = k:k2, nrep = nrep, model = mk(), concomitant = conc, control = ctl, verbose = FALSE, drop = FALSE), error = function(e) NULL)
    if (is.null(st)) return(invisible(NULL))
    for (kk in k:k2) {
      fit <- st@models[[as.character(kk)]]
      if (is.null(fit)) next
      kcur <- kk
      ll <- st@logLiks[as.character(kk), ]
      for (m in seq_along(ll)) if (is.finite(ll[m])) add(15, m - 1, ll[m])
      describe(fit)
    }
  }
}

B3 <- rbind(c(0, 2, 1), c(3, -1.5, 1), c(-2, 0.5, 1))
B3b <- rbind(c(0, 2, 1), c(3, -1.5, 1), c(-2, 0.5, -0.6))
BP3 <- rbind(c(1, 1.2, 0.5), c(2.3, -1, 0.5), c(0.3, 1.2, 0.5))
BB3 <- rbind(c(-1, 2, 0.8), c(1, -2, 0.8), c(0, 1, 0.8))
BG3 <- rbind(c(3, 1.5, 0.4), c(4, -1.2, 0.4), c(2.5, 0.8, 0.4))
fam <- list(list(f = 0, b = B3, sg = c(0.5, 0.7, 0.5)), list(f = 1, b = BP3, sg = c(0, 0, 0)), list(f = 2, b = BB3, sg = c(0, 0, 0)), list(f = 3, b = BG3, sg = c(7, 9, 8)))
PR <- c(0.4, 0.3, 0.3)
pr2 <- PR[1:2] / sum(PR[1:2])
sd <- 500
for (F in fam) {
  # fixed x2: random intercept and x1 per component
  sd <- sd + 1; run(sd, 150, 1, F$f, 2, "x1", ~ x2, 3, 4, pr = pr2, beta = F$b, sg = F$sg)
  # common slope: random intercepts, fixed x1
  sd <- sd + 1; run(sd, 150, 0, F$f, 2, "1", ~ x1, 1, 2, pr = pr2, beta = F$b[, 1:2], sg = F$sg)
  # CEM, SEM and random classification, random start
  for (cls in 1:3) { sd <- sd + 1; run(sd, 150, 1, F$f, 2, "x1", ~ x2, 3, 4, pr = pr2, beta = F$b, sg = F$sg, cls = cls, start = if (cls >= 2) 1 else 0) }
  # nested coefficients: components 2 and 3 share an x2 effect, component 1 has none; and the other grouping
  sd <- sd + 1; run(sd, 200, 1, F$f, 3, "x1", ~ 0, 3, 0, nested = list(k = c(1, 2), formula = c(~0, ~x2)), gmask = c(0, 4, 0), pr = PR, beta = F$b, sg = F$sg, k = 3)
  sd <- sd + 1; run(sd, 200, 1, F$f, 3, "x1", ~ 0, 3, 0, nested = list(k = c(2, 1), formula = c(~x2, ~0)), gmask = c(4, 0, 0), pr = PR, beta = F$b, sg = F$sg, k = 3)
  # fixed and nested together, with the factor design
  sd <- sd + 1; run(sd, 200, 1, F$f, 3, "x1", ~ 0, 3, 0, nested = list(k = c(1, 1, 1), formula = c(~x2, ~0, ~x2)), gmask = c(4, 0, 4), pr = PR, beta = F$b, sg = F$sg, k = 3)
  # component removal (minprior) through the stacked design
  sd <- sd + 1; run(sd, 150, 1, F$f, 2, "x1", ~ x2, 3, 4, k = 3, pr = pr2, beta = F$b, sg = F$sg, minprior = 0.25, start = 1)
  sd <- sd + 1; run(sd, 200, 1, F$f, 2, "x1", ~ 0, 3, 0, k = 3, nested = list(k = c(1, 2), formula = c(~0, ~x2)), gmask = c(0, 4, 0), pr = pr2, beta = F$b, sg = F$sg, minprior = 0.3, start = 1)
  # concomitant prior
  sd <- sd + 1; run(sd, 200, 1, F$f, 2, "x1", ~ x2, 3, 4, pr = pr2, beta = F$b, sg = F$sg, q = 2, gc = rbind(c(0, 0), c(0.3, 2), c(-0.2, -1.5)))
  # stepFlexmix over k = 2:3
  sd <- sd + 1; run(sd, 150, 1, F$f, 2, "x1", ~ x2, 3, 4, pr = pr2, beta = F$b, sg = F$sg, start = 1, mode = 1, k2 = 3, nrep = 2)
}
# the variance structure (Gaussian)
G <- fam[[1]]
sd <- sd + 1; run(sd, 150, 1, 0, 2, "x1", ~ x2, 3, 4, varfix = 1, pr = pr2, beta = G$b, sg = G$sg)
sd <- sd + 1; run(sd, 200, 1, 0, 3, "x1", ~ x2, 3, 4, varfix = 2, vsz = c(2, 1, 0), pr = PR, beta = G$b, sg = G$sg, k = 3)
sd <- sd + 1; run(sd, 200, 1, 0, 3, "x1", ~ 0, 3, 0, varfix = 1, nested = list(k = c(1, 2), formula = c(~0, ~x2)), gmask = c(0, 4, 0), pr = PR, beta = G$b, sg = G$sg, k = 3)
sd <- sd + 1; run(sd, 200, 1, 0, 2, "x1", ~ 0, 3, 0, varfix = 2, vsz = c(2, 1, 0), k = 3, nested = list(k = c(1, 2), formula = c(~0, ~x2)), gmask = c(0, 4, 0), pr = pr2, beta = G$b, sg = G$sg, minprior = 0.3, start = 1)
# the factor design: the fixed factor shared by all components
sd <- sd + 1; run(sd, 200, 2, 0, 2, "x1", ~ f, 3, 12, pr = pr2, beta = rbind(c(0, 2, 1, -1), c(3, -1.5, 1, -1), c(-2, 0.5, 1, -1)), sg = G$sg)
emit("flexmix_fix", "flexmix", list(cases))
