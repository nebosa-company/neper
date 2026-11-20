# flexmix(weights = w) and FLXMRglm / FLXMRglmfix(offset = o): integer case weights (a weighted EM and a CEM fit, with component removal) and a numeric offset, under
# every family, for the plain regression model and for FLXMRglmfix (fixed x2, random intercept and x1), plus the AIC / BIC / ICL / EIC of each fit. The data are drawn as in
# flexmix_ext (the group draws them, the fixture draws them again from the seed), then the weights sample(3, n, TRUE) and the offset runif(n, -0.4, 0.4) from the same stream,
# then set.seed(seed2).
# Case "fw" args (33 values): 0 seed, 1 n, 2 design (always 1: 1 + x1 + x2), 3 family, 4 generating components, 5 k, 6 flip fraction, 7 seed2, 8 classify (0 weighted, 1 CEM),
# 9 minprior, 10 weights (0 none, 1 drawn), 11 offset (0 none, 1 drawn), 12 model (0 FLXMRglm, 1 FLXMRglmfix), 13 what, 14 idx, then pr[3], beta[3][4], sg[3] from 15.
# what: 0 logLik, 1 iter, 2 k, 3 prior[idx], 4 coefficient checksum, 5 sigma / shape checksum, 6 cluster checksum, 7 AIC, 8 BIC, 9 ICL, 10 posterior checksum, 19 fitted checksum,
# 20 converged, 30 EIC.
suppressMessages(library(flexmix))
cases <- list()
cs <- function(v) sum(seq_along(v) * as.vector(v))

gen <- function(n, fam, k, pr, beta, sg) {
  x1 <- runif(n, -1, 1)
  x2 <- runif(n, -1, 1)
  size <- if (fam == 2) sample(8:20, n, TRUE) else NULL
  z <- sample(seq_len(k), n, TRUE, pr[seq_len(k)])
  y <- numeric(n)
  for (i in seq_len(n)) {
    b <- beta[z[i], ]
    mu <- b[1] + b[2] * x1[i] + b[3] * x2[i]
    y[i] <- if (fam == 0) rnorm(1, mu, sg[z[i]]) else if (fam == 1) rpois(1, exp(mu)) else if (fam == 2) rbinom(1, size[i], plogis(mu))
            else rgamma(1, shape = sg[z[i]], scale = (1 / mu) / sg[z[i]])
  }
  d <- data.frame(x1 = x1, x2 = x2)
  if (fam == 2) d$y <- cbind(y, size - y) else d$y <- y
  list(d = d, z = z)
}

run <- function(seed, n, fam, kg, k, pr, beta, sg, wmode = 0, omode = 0, model = 0, cls = 0, minprior = 0.05, flip = 0.15, seed2 = seed + 1) {
  set.seed(seed)
  tr <- gen(n, fam, kg, pr, beta, sg)
  init <- tr$z
  if (k == kg) { fl <- sample(n, round(flip * n)); init[fl] <- sample(seq_len(kg), length(fl), TRUE) }
  wt <- if (wmode == 1) sample(3, n, TRUE) else NULL
  off <- if (omode == 1) runif(n, -0.4, 0.4) else NULL
  set.seed(seed2)
  fam_name <- c("gaussian", "poisson", "binomial", "Gamma")[fam + 1]
  mdl <- if (model == 0) FLXMRglm(family = fam_name, offset = off) else FLXMRglmfix(fixed = ~ x2, family = fam_name, offset = off)
  form <- if (model == 0) y ~ x1 + x2 else y ~ x1
  ctl <- list(classify = c("weighted", "CEM")[cls + 1], minprior = minprior, tolerance = 1e-6, iter.max = 200)
  fit <- tryCatch(flexmix(form, data = tr$d, k = k, cluster = if (k == kg) init else NULL, model = mdl, control = ctl, weights = wt), error = function(e) { message("skip ", seed, ": ", conditionMessage(e)); NULL })
  if (is.null(fit)) return(invisible(NULL))
  hdr <- function(what, idx) c(seed, n, 1, fam, kg, k, flip, seed2, cls, minprior, wmode, omode, model, what, idx, c(pr, rep(0, 3 - length(pr)))[1:3],
                               as.vector(t(cbind(beta, matrix(0, nrow(beta), 4 - ncol(beta))))), c(sg, rep(0, 3 - length(sg)))[1:3])
  add <- function(what, idx, v, tol = 1e-9) {
    if (!is.finite(v) && !is.nan(v)) return(invisible())
    cases[[length(cases) + 1]] <<- case("fw", hdr(what, idx), v, rel = tol, abs = tol)
  }
  kk <- fit@k
  add(0, 0, as.numeric(logLik(fit))); add(1, 0, fit@iter, 0); add(2, 0, kk, 0)
  add(7, 0, AIC(fit)); add(8, 0, BIC(fit)); add(9, 0, ICL(fit))
  if (kk > 1) add(30, 0, EIC(fit))
  for (j in seq_len(kk)) add(3, j - 1, fit@prior[j])
  if (model == 0) {
    prm <- parameters(fit)
    cf <- if (fam == 0 || fam == 3) prm[seq_len(nrow(prm) - 1), , drop = FALSE] else prm
    add(4, 0, cs(cf))
    if (fam == 0 || fam == 3) add(5, 0, cs(prm[nrow(prm), ]))
  } else {
    des <- fit@model[[1]]@design
    cf <- vapply(seq_len(kk), function(j) {
      v <- numeric(ncol(des)); v[des[j, ] == 1] <- unname(fit@components[[j]][[1]]@parameters$coef); v }, numeric(ncol(des)))
    add(4, 0, cs(cf))
    if (fam == 0) add(5, 0, cs(vapply(fit@components, function(cp) cp[[1]]@parameters$sigma, 0)))
    if (fam == 3) add(5, 0, cs(vapply(fit@components, function(cp) cp[[1]]@parameters$shape, 0)))
  }
  add(6, 0, cs(fit@cluster), 0)
  add(10, 0, cs(t(posterior(fit))))
  add(19, 0, cs(t(fitted(fit))))
  add(20, 0, as.numeric(fit@converged), 0)
}

B3 <- rbind(c(0, 2, 1), c(3, -1.5, 1), c(-2, 0.5, 1))
BP3 <- rbind(c(1, 1.2, 0.5), c(2.3, -1, 0.5), c(0.3, 1.2, 0.5))
BB3 <- rbind(c(-1, 2, 0.8), c(1, -2, 0.8), c(0, 1, 0.8))
BG3 <- rbind(c(3, 1.5, 0.4), c(4, -1.2, 0.4), c(2.5, 0.8, 0.4))
fam <- list(list(f = 0, b = B3, sg = c(0.5, 0.7, 0.5)), list(f = 1, b = BP3, sg = c(0, 0, 0)), list(f = 2, b = BB3, sg = c(0, 0, 0)), list(f = 3, b = BG3, sg = c(7, 9, 8)))
PR <- c(0.4, 0.3, 0.3)
pr2 <- PR[1:2] / sum(PR[1:2])
sd <- 700
for (F in fam) for (model in 0:1) {
  # weights only: the weighted EM, the CEM, and a removal of a component under minprior
  sd <- sd + 1; run(sd, 150, F$f, 2, 2, pr2, F$b, F$sg, wmode = 1, model = model)
  sd <- sd + 1; run(sd, 150, F$f, 2, 2, pr2, F$b, F$sg, wmode = 1, model = model, cls = 1)
  sd <- sd + 1; run(sd, 150, F$f, 2, 3, pr2, F$b, F$sg, wmode = 1, model = model, minprior = 0.25)
  # offset only, and both
  sd <- sd + 1; run(sd, 150, F$f, 2, 2, pr2, F$b, F$sg, omode = 1, model = model)
  sd <- sd + 1; run(sd, 150, F$f, 2, 2, pr2, F$b, F$sg, wmode = 1, omode = 1, model = model)
}
emit("flexmix_wo", "flexmix", list(cases))
