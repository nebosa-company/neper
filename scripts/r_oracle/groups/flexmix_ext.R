# flexmix beyond the first group: every family under EM, CEM, SEM and random classification, random and matrix starts (initFlexmix), stepFlexmix, concomitant
# multinomial priors (FLXPmultinom), minprior removal, multi-covariate and factor designs, and the post-fit methods (posterior, predict, fitted, prior, clusters,
# logLik on new data, KLdiv, relabel). The data are drawn in the oracle and again in the fixture from R's stream (set.seed(seed), sequential runif, sample,
# rnorm, rpois, rbinom, rgamma), so a case holds only the header. Case "fm" args (46 values): 0 seed, 1 n, 2 design (0: 1 + x1; 1: 1 + x1 + x2; 2: 1 + x1 + factor f of 3 levels),
# 3 family (0 gaussian, 1 poisson, 2 binomial, 3 Gamma), 4 k, 5 q (concomitant columns, 0 none, 2: 1 + w), 6 flip fraction of the given start, 7 nnew, 8 seed2,
# 9 mode (0 flexmix, 1 stepFlexmix k..k2, 2 initFlexmix k..k2), 10 classify (0 weighted, 1 CEM, 2 SEM, 3 random), 11 start (0 cluster, 1 random under seed2),
# 12 minprior, 13 tolerance, 14 iter.max, 15 k2, 16 nrep, 17 init method (0 tol.em, 1 cem.em, 2 sem.em), 18 what, 19 idx, 20 kg, 21 kq; then pr[3], beta[3][4], sg[3], gc[3][2].
# slots 20 and 21: the generating number of components and the k a stepFlexmix / initFlexmix result is asked for. what: 0 logLik, 1 iter, 2 k, 3 prior[idx], 4 coef checksum, 5 sigma checksum, 6 cluster checksum, 7 AIC, 8 BIC, 9 ICL, 10 posterior checksum, 11 concomitant coef checksum,
# 12 predict(newdata) checksum, 13 posterior(newdata) checksum, 14 logLik(newdata), 15 stepFlexmix logLiks[idx], 16 KLdiv continuous[idx], 17 KLdiv discrete[idx],
# 18 prior(newdata) checksum, 19 fitted checksum, 20 converged, 21..24 the relabel of 'prior' (coef, cluster, post, conc checksums), 25 relabel by model x1 coef checksum,
# 26 relabel by the permutation (2,1,...) coef checksum, 27 relabel by concomitant w coef checksum, 28 predict(newdata, aggregate = TRUE) checksum, 29 clusters(newdata) checksum.
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

run <- function(seed, n, dtype, fam, k, q, pr, beta, sg, gc, kg = k, flip = 0.15, nnew = 0, seed2 = seed + 1, mode = 0, cls = 0, start = 0, minprior = 0.05,
                tol = 1e-6, itermax = 200, k2 = k, nrep = 3, method = 0, relab = FALSE, ctol = 1e-7) {
  set.seed(seed)
  tr <- gen(n, dtype, fam, kg, q, pr, beta, sg, gc)
  init <- tr$z
  if (start == 0) { fl <- sample(n, round(flip * n)); init[fl] <- sample(seq_len(kg), length(fl), TRUE) }
  nw <- if (nnew > 0) gen(nnew, dtype, fam, kg, q, pr, beta, sg, gc)$d else NULL
  set.seed(seed2)
  form <- y ~ x1
  if (dtype == 1) form <- y ~ x1 + x2
  if (dtype == 2) form <- y ~ x1 + f
  fam_name <- c("gaussian", "poisson", "binomial", "Gamma")[fam + 1]
  conc <- if (q > 0) FLXPmultinom(~ w) else NULL
  cl <- c("weighted", "CEM", "SEM", "random")[cls + 1]
  ctl <- list(classify = cl, minprior = minprior, tolerance = tol, iter.max = itermax)
  mdl <- FLXMRglm(family = fam_name)
  kcur <- k
  hdr <- function(what, idx) c(seed, n, dtype, fam, k, q, flip, nnew, seed2, mode, cls, start, minprior, tol, itermax, k2, nrep, method, what, idx, kg, kcur,
                               c(pr, rep(0, 3 - length(pr)))[1:3], as.vector(t(cbind(beta, matrix(0, nrow(beta), 4 - ncol(beta))))), c(sg, rep(0, 3 - length(sg)))[1:3],
                               as.vector(t(cbind(gc, matrix(0, nrow(gc), 2 - ncol(gc))))))
  # a concomitant prior is nnet BFGS (reltol 1e-8, at most 100 iterations), so its fits agree to the optimiser tolerance, not to rounding; where the k = 3 prior fit runs into
  # the iteration cap its path is chaotic at the rounding level of exp (ctol 1e-3; the other concomitant cases are held to 1e-7)
  add <- function(what, idx, v, rel = if (q > 0) ctol else 1e-9, abs = if (q > 0) ctol else 1e-9) {
    if (!is.finite(v) && !is.nan(v)) return(invisible())
    cases[[length(cases) + 1]] <<- case("fm", hdr(what, idx), v, rel = rel, abs = abs)
  }
  describe <- function(fit) {
    kk <- fit@k; prm <- parameters(fit)
    add(0, 0, as.numeric(logLik(fit))); add(1, 0, fit@iter, 0, 0); add(2, 0, kk, 0, 0)
    add(7, 0, AIC(fit)); add(8, 0, BIC(fit)); add(9, 0, ICL(fit))
    for (j in seq_len(kk)) add(3, j - 1, fit@prior[j])
    P <- ncol(prm) # components
    cf <- if (fam == 0 || fam == 3) prm[seq_len(nrow(prm) - 1), , drop = FALSE] else prm
    add(4, 0, cs(cf))
    if (fam == 0 || fam == 3) add(5, 0, cs(prm[nrow(prm), ]))
    add(6, 0, cs(fit@cluster), 0, 0)
    add(10, 0, cs(t(posterior(fit))))
    add(20, 0, as.numeric(fit@converged), 0, 0)
    if (q > 0) add(11, 0, cs(fit@concomitant@coef))
    add(19, 0, cs(t(fitted(fit))))
    if (kk > 1) {
      if (fam != 3) { kc <- KLdiv(fit); for (u in seq_len(kk * kk)) add(16, u - 1, as.vector(t(kc))[u]) }
      kd <- KLdiv(fit, method = "discrete")
      for (u in seq_len(kk * kk)) { v <- as.vector(t(kd))[u]; if (is.finite(v)) add(17, u - 1, v) }
    }
    if (!is.null(nw)) {
      pn <- predict(fit, newdata = nw)
      add(12, 0, cs(t(do.call(cbind, lapply(pn, function(m) as.vector(m))))))
      add(28, 0, cs(predict(fit, newdata = nw, aggregate = TRUE)[[1]]))
      add(13, 0, cs(t(posterior(fit, newdata = nw))))
      add(14, 0, as.numeric(logLik(fit, newdata = nw)))
      add(29, 0, cs(clusters(fit, newdata = nw)), 0, 0)
      add(18, 0, cs(t(prior(fit, newdata = nw))))
    }
    if (relab && kk > 1) {
      rl <- relabel(fit)
      prm2 <- parameters(rl); cf2 <- if (fam == 0 || fam == 3) prm2[seq_len(nrow(prm2) - 1), , drop = FALSE] else prm2
      add(21, 0, cs(cf2)); add(22, 0, cs(rl@cluster), 0, 0); add(23, 0, cs(t(posterior(rl))))
      if (q > 0) add(24, 0, cs(rl@concomitant@coef))
      rm <- relabel(fit, "model", "x1"); pm <- parameters(rm); add(25, 0, cs(if (fam == 0 || fam == 3) pm[seq_len(nrow(pm) - 1), , drop = FALSE] else pm))
      rp <- relabel(fit, rev(seq_len(kk))); pp <- parameters(rp); add(26, 0, cs(if (fam == 0 || fam == 3) pp[seq_len(nrow(pp) - 1), , drop = FALSE] else pp))
      if (q > 0) { rc <- relabel(fit, "concomitant", "w"); pc <- parameters(rc); add(27, 0, cs(if (fam == 0 || fam == 3) pc[seq_len(nrow(pc) - 1), , drop = FALSE] else pc)) }
    }
  }
  if (mode == 0) {
    fit <- tryCatch(flexmix(form, data = tr$d, k = k, cluster = if (start == 0) init else NULL, model = mdl, concomitant = conc, control = ctl),
                    error = function(e) NULL)
    if (is.null(fit)) return(invisible(NULL))
    describe(fit)
  } else if (mode == 1) {
    st <- tryCatch(stepFlexmix(form, data = tr$d, k = k:k2, nrep = nrep, model = mdl, concomitant = conc, control = ctl, verbose = FALSE, drop = FALSE),
                   error = function(e) NULL)
    if (is.null(st)) return(invisible(NULL))
    for (kk in k:k2) {
      fit <- st@models[[as.character(kk)]]
      if (is.null(fit)) next
      kcur <- kk
      ll <- st@logLiks[as.character(kk), ]
      for (m in seq_along(ll)) if (is.finite(ll[m])) add(15, m - 1, ll[m])
      describe(fit)
    }
  } else {
    st <- tryCatch(initFlexmix(form, data = tr$d, k = k:k2, nrep = nrep, model = mdl, concomitant = conc, init = list(name = c("tol.em", "cem.em", "sem.em")[method + 1]),
                               control = ctl, verbose = FALSE, drop = FALSE), error = function(e) NULL)
    if (is.null(st)) return(invisible(NULL))
    for (kk in k:k2) {
      fit <- st@models[[as.character(kk)]]
      kcur <- kk
      ll <- st@logLiks[as.character(kk), ]
      for (m in seq_along(ll)) if (is.finite(ll[m])) add(15, m - 1, ll[m])
      describe(fit)
    }
  }
}

B2 <- rbind(c(0, 2), c(3, -1.5), c(-2, 0.5))
B3 <- rbind(c(0, 2, 1), c(3, -1.5, -1), c(-2, 0.5, 0.8))
B4 <- rbind(c(0, 2, 1, -1), c(3, -1.5, -1, 1), c(-2, 0.5, 0.8, 0.5))
BP <- rbind(c(1, 1.5), c(2.5, -1.2), c(0.3, 1.2))
BP3 <- rbind(c(1, 1.2, 0.5), c(2.3, -1, -0.5), c(0.3, 1.2, 0.4))
BP4 <- rbind(c(1, 1.2, 0.4, -0.3), c(2.3, -1, -0.5, 0.3), c(0.3, 1.2, 0.4, 0.2))
BB <- rbind(c(-1, 2), c(1, -2), c(0, 1))
BB3 <- rbind(c(-1, 2, 0.8), c(1, -2, -0.7), c(0, 1, 0.5))
BG <- rbind(c(3, 1.5), c(4, -1.2), c(2.5, 0.8))
BG3 <- rbind(c(3, 1.5, 0.4), c(4, -1.2, -0.3), c(2.5, 0.8, 0.3))
BG4 <- rbind(c(3, 1.5, 0.4, -0.3), c(4, -1.2, -0.3, 0.3), c(2.5, 0.8, 0.3, 0.2))
BB4 <- rbind(c(-1, 2, 0.8, -0.5), c(1, -2, -0.7, 0.6), c(0, 1, 0.5, 0.4))
GC <- rbind(c(0, 0), c(0.3, 2), c(-0.2, -1.5))
sgG <- c(0.5, 0.7, 0.5); shG <- c(7, 9, 8)

fams <- list(
  list(f = 0, b = B2, b3 = B3, b4 = B4, sg = sgG, pr = c(0.4, 0.3, 0.3)),
  list(f = 1, b = BP, b3 = BP3, b4 = BP4, sg = c(0, 0, 0), pr = c(0.4, 0.3, 0.3)),
  list(f = 2, b = BB, b3 = BB3, b4 = BB4, sg = c(0, 0, 0), pr = c(0.4, 0.3, 0.3)),
  list(f = 3, b = BG, b3 = BG3, b4 = BG4, sg = shG, pr = c(0.4, 0.3, 0.3)))
bsel <- function(F, dtype) if (dtype == 0) F$b else if (dtype == 1) F$b3 else F$b4
GCz <- GC

# EM and CEM and SEM from a given or random start, every family, the three designs
sd <- 100
for (F in fams) for (dtype in 0:2) {
  for (cls in 0:2) {
    sd <- sd + 1
    run(sd, 140, dtype, F$f, 2, 0, F$pr[1:2] / sum(F$pr[1:2]), bsel(F, dtype), F$sg, GCz, cls = cls, start = if (cls == 2) 1 else 0, nnew = 60, relab = TRUE)
  }
}
# random start EM, classify random, k = 3
for (F in fams) { sd <- sd + 1; run(sd, 170, 0, F$f, 3, 0, F$pr, bsel(F, 0), F$sg, GCz, start = 1, nnew = 40, relab = TRUE)
                  sd <- sd + 1; run(sd, 150, 1, F$f, 2, 0, F$pr[1:2] / sum(F$pr[1:2]), bsel(F, 1), F$sg, GCz, cls = 3, start = 1) }
# stepFlexmix
for (F in fams) { sd <- sd + 1; run(sd, 150, 0, F$f, 2, 0, F$pr[1:2] / sum(F$pr[1:2]), bsel(F, 0), F$sg, GCz, mode = 1, k2 = 3, nrep = 3, start = 1, nnew = 30) }
# one component, k = 1 .. 2
for (F in fams) { sd <- sd + 1; run(sd, 120, 0, F$f, 1, 0, 1, bsel(F, 0), F$sg, GCz, mode = 1, k2 = 2, nrep = 2, start = 1) }
# initFlexmix
for (m in 0:2) for (F in fams[1:2]) { sd <- sd + 1; run(sd, 150, 0, F$f, 2, 0, F$pr[1:2] / sum(F$pr[1:2]), bsel(F, 0), F$sg, GCz, mode = 2, k2 = 3, nrep = 3, method = m, start = 1) }
# concomitant variables
for (F in fams) for (cls in 0:1) { sd <- sd + 1; run(sd, 200, 0, F$f, 2, 2, F$pr[1:2], bsel(F, 0), F$sg, GCz, cls = cls, nnew = 50, relab = TRUE) }
for (F in fams[c(1, 2)]) { sd <- sd + 1; run(sd, 240, 0, F$f, 3, 2, F$pr, bsel(F, 0), F$sg, GCz, nnew = 50, relab = TRUE)
                         sd <- sd + 1; run(sd, 200, 0, F$f, 2, 2, F$pr[1:2], bsel(F, 0), F$sg, GCz, mode = 1, k2 = 3, nrep = 2, start = 1, ctol = 1e-3) }
# minprior removal, loose tolerance, few iterations
for (F in fams) { sd <- sd + 1; run(sd, 150, 0, F$f, 3, 0, c(0.5, 0.45, 0.05), bsel(F, 0), F$sg, GCz, minprior = 0.2, start = 1)
                  sd <- sd + 1; run(sd, 150, 0, F$f, 4, 0, c(0.5, 0.5), bsel(F, 0), F$sg, GCz, kg = 2, minprior = 0.3, start = 1)
                  sd <- sd + 1; run(sd, 120, 0, F$f, 2, 0, F$pr[1:2] / sum(F$pr[1:2]), bsel(F, 0), F$sg, GCz, tol = 1e-3, itermax = 5, start = 1) }
emit("flexmix_ext", "flexmix", list(cases))
