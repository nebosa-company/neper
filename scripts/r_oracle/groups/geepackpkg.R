# geepackpkg: geeglm gaussian with independence or exchangeable working correlation, equal clusters. geepack stops its iteration at tol 1e-5, so the exchangeable cases are compared at rel 1e-4 and the independence cases (one step) at 1e-8.
#   args: (what 0 beta 1 vbeta 2 phi 3 alpha, index (beta, or row * p + col), exch 0/1, k, m, p, y (k m), x row-major (k m) by p with the intercept column)
suppressMessages(library(geepack))
cases <- list()
add <- function(fn, args, want, rel = 1e-8) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-9)
set.seed(20262014)
for (rep in 1:20) {
  k <- sample(15:40, 1); m <- sample(3:6, 1); p <- sample(2:3, 1); id <- rep(1:k, each = m)
  X <- cbind(1, matrix(round(rnorm(k * m * (p - 1)), 4), k * m, p - 1)); y <- round(as.vector(X %*% runif(p, -1, 1)) + rep(rnorm(k, 0, 0.8), each = m) + rnorm(k * m), 4)
  d <- data.frame(y = y, id = id); for (j in 2:p) d[[paste0("x", j)]] <- X[, j]
  f <- as.formula(paste("y ~", paste(paste0("x", 2:p), collapse = " + ")))
  for (ex in 0:1) {
    g <- geeglm(f, id = id, data = d, family = gaussian, corstr = if (ex == 1) "exchangeable" else "independence")
    a <- c(k, m, p, y, as.vector(t(X)))
    rl <- if (ex == 1) 1e-4 else 1e-8
    for (j in 1:p) add("gee", c(0, j - 1, ex, a), unname(coef(g))[j], rl)
    for (u in 1:p) for (v in 1:p) add("gee", c(1, (u - 1) * p + v - 1, ex, a), g$geese$vbeta[u, v], rl)
    add("gee", c(2, 0, ex, a), g$geese$gamma[[1]], rl); if (ex == 1) add("gee", c(3, 0, ex, a), g$geese$alpha[[1]], rl)
  }
}
# geeglm_glm "geg" (what 0 beta 1 vbeta 2 phi 3 alpha, index, family 0 gaussian 1 binomial 2 poisson, corstr 0 indep 1 exch 2 ar1, k, m, p, y, X row-major)
set.seed(20262099)
for (rep in 1:24) {
  fam <- (rep - 1) %% 3; cs <- ((rep - 1) %/% 3) %% 3
  k <- sample(25:50, 1); m <- sample(3:5, 1); p <- 2; id <- rep(1:k, each = m)
  x1 <- round(rnorm(k * m), 3); X <- cbind(1, x1); re <- rep(rnorm(k, 0, 0.5), each = m); eta <- 0.3 + 0.4 * x1 + re
  y <- switch(fam + 1, round(eta + rnorm(k * m), 4), rbinom(k * m, 1, plogis(eta)), rpois(k * m, exp(eta * 0.6)))
  d <- data.frame(y = y, id = id, x1 = x1)
  g <- tryCatch(geeglm(y ~ x1, id = id, data = d, family = list(gaussian, binomial, poisson)[[fam + 1]], corstr = c("independence", "exchangeable", "ar1")[cs + 1]), error = function(e) NULL, warning = function(w) NULL)
  if (is.null(g)) next
  a <- c(fam, cs, k, m, p, y, as.vector(t(X))); rl <- 1e-4
  for (j in 1:p) cases[[length(cases) + 1]] <- case("geg", c(0, j - 1, a), unname(coef(g))[j], rel = rl, abs = 2e-5)
  for (u in 1:p) for (v in 1:p) cases[[length(cases) + 1]] <- case("geg", c(1, (u - 1) * p + v - 1, a), g$geese$vbeta[u, v], rel = 1e-3, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("geg", c(2, 0, a), g$geese$gamma[[1]], rel = 1e-3, abs = 1e-6)
  if (cs > 0) cases[[length(cases) + 1]] <- case("geg", c(3, 0, a), g$geese$alpha[[1]], rel = 1e-3, abs = 3e-5)
}
# gee_fit "gx": (what 0 beta 1 vbeta 2 vnaive 3 vj1s 4 vfij 5 phi 6 alpha, index, fam 0 gaussian 1 binomial 2 poisson 3 Gamma, link 0 identity 1 logit 2 probit 3 cloglog 4 log 5 inverse,
#   corstr 0 indep 1 exch 2 ar1 3 unstructured 4 fixed, dofij, k, p, maxm, sizes (k), y, X row-major, zc (maxm by maxm table))
famobj <- function(f, l) switch(f + 1, gaussian("identity"), binomial(c("logit", "probit", "cloglog")[l]), poisson("log"), Gamma(if (l == 5) "inverse" else "log"))
gx_configs <- list(c(0, 0, 0), c(0, 0, 1), c(0, 0, 2), c(0, 0, 3), c(0, 0, 4), c(1, 1, 1), c(1, 2, 2), c(1, 3, 0), c(1, 1, 3), c(2, 4, 1), c(2, 4, 3), c(2, 4, 4), c(3, 4, 1), c(3, 5, 2))
set.seed(20262301)
for (ci in seq_along(gx_configs)) {
  cf <- gx_configs[[ci]]; fam <- cf[1]; lnk <- cf[2]; cs <- cf[3]
  g <- NULL
  for (tries in 1:6) {
    k <- sample(26:40, 1); sz <- sample(2:5, k, replace = TRUE); p <- sample(2:3, 1); N <- sum(sz); id <- rep(1:k, sz); maxm <- max(sz)
    X <- cbind(1, matrix(round(runif(N * (p - 1), -1, 1), 3), N, p - 1))
    re <- rep(rnorm(k, 0, 0.4), sz)
    eta <- if (fam == 3 && lnk == 5) 1.4 + 0.3 * X[, 2] + 0.1 * re else 0.3 + 0.4 * X[, 2] + (if (p == 3) -0.3 * X[, 3] else 0) + re
    fobj <- famobj(fam, lnk)
    mu <- fobj$linkinv(eta)
    y <- switch(fam + 1, round(eta + rnorm(N), 4), rbinom(N, 1, mu), rpois(N, mu), round(rgamma(N, shape = 4, scale = mu / 4), 4))
    zc <- outer(1:maxm, 1:maxm, function(s, t) 0.5^abs(s - t))
    zcv <- unlist(lapply(sz, function(m) if (m > 1) unlist(lapply(1:(m - 1), function(s) zc[s, (s + 1):m])) else NULL))
    d <- data.frame(y = y, id = id); for (j in 2:p) d[[paste0("x", j)]] <- X[, j]
    f <- as.formula(paste("y ~", paste(paste0("x", 2:p), collapse = " + ")))
    corn <- c("independence", "exchangeable", "ar1", "unstructured", "fixed")[cs + 1]
    g <- tryCatch(geese(f, id = id, data = d, family = fobj, corstr = corn, zcor = if (cs == 4) matrix(zcv, ncol = 1) else NULL, control = geese.control(j1s = TRUE, fij = TRUE)), error = function(e) NULL, warning = function(w) NULL)
    if (!is.null(g) && all(is.finite(g$beta)) && g$error == 0) break
    g <- NULL
  }
  if (is.null(g)) next
  dofij <- if (ci %% 2 == 0) 1 else 0
  a <- c(fam, lnk, cs, dofij, k, p, maxm, sz, y, as.vector(t(X)), as.vector(t(zc)))
  add2 <- function(what, idx, want, rl, ab) cases[[length(cases) + 1]] <<- case("gx", c(what, idx, a), want, rel = rl, abs = ab)
  for (j in 1:p) add2(0, j - 1, unname(g$beta)[j], 1e-4, 2e-5)
  for (u in 1:p) for (v in 1:p) {
    add2(1, (u - 1) * p + v - 1, g$vbeta[u, v], 1e-3, 1e-6)
    add2(2, (u - 1) * p + v - 1, g$vbeta.naiv[u, v], 1e-3, 1e-6)
    add2(3, (u - 1) * p + v - 1, g$vbeta.j1s[u, v], 2e-3, 1e-6)
    if (dofij == 1) add2(4, (u - 1) * p + v - 1, g$vbeta.fij[u, v], 3e-3, 1e-6)
  }
  add2(5, 0, g$gamma[[1]], 1e-3, 1e-6)
  for (q in seq_along(g$alpha)) add2(6, q - 1, g$alpha[[q]], 1e-3, 3e-5)
}
# "gw" (what 0 df 1 X2 2 p of the sequential Wald table, 3 Wald 4 p of a coefficient, 5 its Wald with the one-step jackknife, 6 with the fully iterated jackknife; index, fam, link, corstr, k, p, maxm, nvars, sizes, y, X, zc, assign)
# "gq" (QIC 0 QIC 1 QICu 2 quasi 3 CIC 4 params 5 QICC, fam, link, corstr, k, p, maxm, sizes, y, X, zc)
set.seed(20262302)
gw_configs <- list(c(0, 0, 1, 2), c(0, 0, 2, 1), c(0, 0, 0, 0), c(1, 1, 1, 1), c(1, 2, 2, 2), c(1, 1, 3, 0), c(2, 4, 1, 2), c(2, 4, 0, 1), c(2, 4, 2, 2), c(3, 4, 1, 2), c(3, 5, 2, 1), c(0, 0, 4, 2))
for (ci in seq_along(gw_configs)) {
  cf <- gw_configs[[ci]]; fam <- cf[1]; lnk <- cf[2]; cs <- cf[3]; vt <- cf[4]
  g <- NULL
  for (tries in 1:6) {
    k <- sample(26:40, 1); sz <- sample(2:5, k, replace = TRUE); N <- sum(sz); id <- rep(1:k, sz); maxm <- max(sz)
    d <- data.frame(y = 0, id = id, x2 = round(runif(N, -1, 1), 3), x3 = round(runif(N, -1, 1), 3), fc = factor(sample(c("a", "b", "c"), N, replace = TRUE)))
    f <- switch(vt + 1, y ~ x2, y ~ x2 + x3, y ~ x2 + fc + x3)
    X <- model.matrix(f, d); p <- ncol(X); asg <- attr(X, "assign")
    re <- rep(rnorm(k, 0, 0.4), sz)
    fobj <- famobj(fam, lnk)
    cf0 <- if (fam == 3 && lnk == 5) c(1.4, 0.2, 0.1, -0.1, 0.1)[seq_len(p)] else c(0.3, 0.5, -0.4, 0.3, -0.3)[seq_len(p)]
    eta <- as.vector(X %*% cf0) + (if (fam == 3 && lnk == 5) 0.1 else 1) * re
    mu <- fobj$linkinv(eta)
    d$y <- switch(fam + 1, round(eta + rnorm(N), 4), rbinom(N, 1, mu), rpois(N, mu), round(rgamma(N, shape = 4, scale = mu / 4), 4))
    zc <- outer(1:maxm, 1:maxm, function(s, t) 0.5^abs(s - t))
    zcv <- unlist(lapply(sz, function(m) if (m > 1) unlist(lapply(1:(m - 1), function(s) zc[s, (s + 1):m])) else NULL))
    corn <- c("independence", "exchangeable", "ar1", "unstructured", "fixed")[cs + 1]
    zarg <- if (cs == 4) matrix(zcv, ncol = 1) else NULL
    g <- tryCatch(geeglm(f, id = id, data = d, family = fobj, corstr = corn, zcor = zarg), error = function(e) NULL, warning = function(w) NULL)
    if (!is.null(g) && all(is.finite(coef(g))) && g$geese$error == 0) break
    g <- NULL
  }
  if (is.null(g)) next
  ge <- geese(f, id = id, data = d, family = fobj, corstr = corn, zcor = zarg, control = geese.control(j1s = TRUE, fij = TRUE))
  an <- if (cs == 4) NULL else anova(g); nv <- length(unique(asg[asg > 0])); y <- d$y
  a <- c(fam, lnk, cs, k, p, maxm, nv, sz, y, as.vector(t(X)), as.vector(t(zc)), asg)
  for (i in if (is.null(an)) integer(0) else 1:nv) {
    cases[[length(cases) + 1]] <- case("gw", c(0, i - 1, a), an$Df[i], rel = 1e-9, abs = 1e-9)
    cases[[length(cases) + 1]] <- case("gw", c(1, i - 1, a), an$X2[i], rel = 2e-3, abs = 3e-4)
    cases[[length(cases) + 1]] <- case("gw", c(2, i - 1, a), an[["P(>|Chi|)"]][i], rel = 5e-3, abs = 1e-4)
  }
  se <- sqrt(diag(ge$vbeta)); wd <- (ge$beta / se)^2
  for (j in 1:p) {
    cases[[length(cases) + 1]] <- case("gw", c(3, j - 1, a), wd[j], rel = 2e-3, abs = 3e-4)
    cases[[length(cases) + 1]] <- case("gw", c(4, j - 1, a), 1 - pchisq(wd[j], 1), rel = 5e-3, abs = 1e-4)
    cases[[length(cases) + 1]] <- case("gw", c(5, j - 1, a), (ge$beta[j]^2 / ge$vbeta.j1s[j, j]), rel = 4e-3, abs = 3e-4)
    if (ci %% 3 == 0) cases[[length(cases) + 1]] <- case("gw", c(6, j - 1, a), (ge$beta[j]^2 / ge$vbeta.fij[j, j]), rel = 6e-3, abs = 3e-4)
  }
  qq <- tryCatch(QIC(g), error = function(e) NULL)
  if (!is.null(qq)) for (w in 0:5) cases[[length(cases) + 1]] <- case("gq", c(w, fam, lnk, cs, k, p, maxm, sz, y, as.vector(t(X)), as.vector(t(zc))), unname(qq[w + 1]), rel = 2e-3, abs = 1e-5)
}
# "go" ordgee with independence (what 0 beta 1 robust 2 naive 3 one-step jackknife, index, link 1 logit 2 probit 3 cloglog, k, px, nlev, sizes, y levels 1..nlev, x row-major)
set.seed(20262303)
for (ci in 1:8) {
  lnk <- (ci - 1) %% 3 + 1; nlev <- 3 + (ci %% 2); px <- 1 + (ci %% 3 == 0)
  g <- NULL
  for (tries in 1:6) {
    k <- sample(30:45, 1); sz <- sample(2:4, k, replace = TRUE); N <- sum(sz); id <- rep(1:k, sz)
    xx <- matrix(round(rnorm(N * px), 3), N, px); re <- rep(rnorm(k, 0, 0.6), sz)
    lat <- as.vector(xx %*% c(0.6, -0.4)[1:px]) + re + (if (lnk == 1) rlogis(N) else if (lnk == 2) rnorm(N) else -log(-log(runif(N))))
    cuts <- c(-0.8, 0.4, 1.3)[1:(nlev - 1)]
    yv <- cut(lat, c(-Inf, cuts, Inf), labels = 1:nlev, ordered_result = TRUE)
    if (length(unique(yv)) < nlev) next
    d <- data.frame(y = yv, id = id); for (j in 1:px) d[[paste0("x", j)]] <- xx[, j]
    f <- as.formula(paste("y ~", paste(paste0("x", 1:px), collapse = " + ")))
    g <- tryCatch(ordgee(f, id = id, data = d, corstr = "independence", mean.link = c("logit", "probit", "cloglog")[lnk], control = geese.control(j1s = TRUE)), error = function(e) NULL, warning = function(w) NULL)
    if (!is.null(g) && g$error == 0 && max(abs(g$beta)) < 20) break
    g <- NULL
  }
  if (is.null(g)) next
  p <- length(g$beta); a <- c(lnk, k, px, nlev, sz, as.integer(yv), as.vector(t(xx)))
  for (j in 1:p) cases[[length(cases) + 1]] <- case("go", c(0, j - 1, a), unname(g$beta)[j], rel = 1e-4, abs = 2e-5)
  for (u in 1:p) for (v in 1:p) {
    cases[[length(cases) + 1]] <- case("go", c(1, (u - 1) * p + v - 1, a), g$vbeta[u, v], rel = 1e-3, abs = 1e-6)
    cases[[length(cases) + 1]] <- case("go", c(2, (u - 1) * p + v - 1, a), g$vbeta.naiv[u, v], rel = 1e-3, abs = 1e-6)
  }
}
# "gp" ordgee with the exchangeable or unstructured odds ratios (what 0 beta 1 robust 2 naive 3 alpha 4 robust of alpha 5 naive of alpha, index, corstr 1 exch 3 unstructured, link, k, px, nlev, sizes, y, x row-major)
set.seed(20262304)
for (ci in 1:10) {
  cs <- if (ci %% 2 == 1) 1 else 3; lnk <- (ci - 1) %% 3 + 1; nlev <- 3 + (ci %% 3 == 0); px <- 1 + (ci %% 4 == 0)
  g <- NULL
  for (tries in 1:8) {
    k <- sample(40:60, 1); sz <- sample(2:4, k, replace = TRUE); N <- sum(sz); id <- rep(1:k, sz)
    xx <- matrix(round(rnorm(N * px), 3), N, px); re <- rep(rnorm(k, 0, 0.6), sz)
    lat <- as.vector(xx %*% c(0.6, -0.4)[1:px]) + re + (if (lnk == 1) rlogis(N) else if (lnk == 2) rnorm(N) else -log(-log(runif(N))))
    yv <- cut(lat, c(-Inf, c(-0.8, 0.4, 1.3)[1:(nlev - 1)], Inf), labels = 1:nlev, ordered_result = TRUE)
    if (length(unique(yv)) < nlev) next
    d <- data.frame(y = yv, id = id); for (j in 1:px) d[[paste0("x", j)]] <- xx[, j]
    f <- as.formula(paste("y ~", paste(paste0("x", 1:px), collapse = " + ")))
    g <- tryCatch(ordgee(f, id = id, data = d, corstr = c("independence", "exchangeable", "unstructured")[if (cs == 1) 2 else 3], mean.link = c("logit", "probit", "cloglog")[lnk]), error = function(e) NULL, warning = function(w) NULL)
    if (!is.null(g) && g$error == 0 && max(abs(g$beta)) < 20 && all(is.finite(g$valpha))) break
    g <- NULL
  }
  if (is.null(g)) next
  p <- length(g$beta); q <- length(g$alpha); a <- c(cs, lnk, k, px, nlev, sz, as.integer(yv), as.vector(t(xx)))
  ad <- function(w, i, want, rl, ab) cases[[length(cases) + 1]] <<- case("gp", c(w, i, a), want, rel = rl, abs = ab)
  for (j in 1:p) ad(0, j - 1, unname(g$beta)[j], 1e-5, 1e-7)
  for (u in 1:p) for (v in 1:p) { ad(1, (u - 1) * p + v - 1, g$vbeta[u, v], 1e-5, 1e-8); ad(2, (u - 1) * p + v - 1, g$vbeta.naiv[u, v], 1e-5, 1e-8) }
  for (j in 1:q) ad(3, j - 1, unname(g$alpha)[j], 1e-5, 1e-7)
  for (u in 1:q) for (v in 1:q) { ad(4, (u - 1) * q + v - 1, g$valpha[u, v], 1e-5, 1e-8); ad(5, (u - 1) * q + v - 1, g$valpha.naiv[u, v], 1e-5, 1e-8) }
}
emit("geepackpkg", "geepack", list(cases))
