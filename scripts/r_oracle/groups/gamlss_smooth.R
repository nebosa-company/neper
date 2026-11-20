# gamlss fitting with smoothers: RS, CG and mixed with pb() terms (more smoothers are added to this group), families 0 NO 1 GA 2 PO 3 WEI 4 BCCG.
# A scenario opens with a case whose args are the 23-number header, 8 numbers per smoother, then the data; the cases after it carry the header with fam 99 and read the same fit.
# header: fam, algo (0 RS 1 CG 2 mixed), n, p0, p1, p2 (design columns, the smoothers' linear columns included), link kinds of mu, sigma, nu (4 identity, 5 log), out kind,
#         out index, c.crit, n.cyc, mixed n1, n2, autostep, centile p, mu.step, sigma.step, nu.step, then the number of smoothers of mu, sigma, nu
# smoother: type (1 pb 2 cs 3 lo), a, b, c, df (-1 none), lambda (-1 none), method (0 ML 1 GAIC 2 GCV), start
# data: y (n), w (n), X0 (n * p0), X1 (n * p1), X2 (n * p2) column-major, then the smoothers' x vectors (n each) in order
# out kinds: 0 coefficient, 1 G.deviance, 2 iter, 3 converged, 4 fitted parameter (k * n + i), 5 df.fit, 6 aic, 7 sbc, 8 working variable, 9 working weight,
#            10 linear predictor, 13 nl.df of parameter idx, 14 pen, 15 lambda of smoother idx, 16 smooth term (smoother idx * n + i), 17 P.deviance
suppressMessages(library(gamlss))
cases <- list()
famobj <- list(NO, GA, PO, WEI, BCCG)
pnames <- c("mu", "sigma", "nu")
mk <- function(fam, algo, y, w, d, sp, links, steps, cc, ncyc, n1, n2, auto, rel = 1e-9) {
  n <- length(y)
  d$y <- y; d$w <- w
  np <- c(2, 2, 1, 2, 3)[fam + 1]
  ctl <- gamlss.control(trace = FALSE, c.crit = cc, n.cyc = ncyc, mu.step = steps[1], sigma.step = steps[2], nu.step = steps[3], autostep = auto)
  fa <- famobj[[fam + 1]]
  lk <- c("identity", "log")[links - 3]
  fo <- do.call(fa, as.list(lk[seq_len(np)]))
  method <- if (algo == 0) quote(RS()) else if (algo == 1) quote(CG()) else bquote(mixed(.(n1), .(n2)))
  fml <- function(k) {
    s <- sp[[k]]
    terms <- c(s$lin, vapply(s$sm, function(z) z$call, ""))
    rhs <- if (length(terms)) paste(terms, collapse = " + ") else "1"
    if (k == 1) paste("y ~", rhs) else paste("~", rhs)
  }
  args <- list(formula = as.formula(fml(1)), family = fo, data = d, weights = d$w, method = method, control = ctl, trace = FALSE)
  if (np > 1) args$sigma.formula <- as.formula(fml(2))
  if (np > 2) args$nu.formula <- as.formula(fml(3))
  m <- tryCatch(suppressWarnings(do.call(gamlss, args)), error = function(e) { message("ERR ", conditionMessage(e)); NULL })
  if (is.null(m)) { message("SKIP fam ", fam, " algo ", algo, " ", fml(1)); return(invisible()) }
  X <- list(); p <- c(0, 0, 0)
  smx <- list(); smhdr <- list(); nsm <- c(0, 0, 0)
  for (k in seq_len(np)) {
    s <- sp[[k]]
    vars <- c(s$lin, vapply(s$sm, function(z) z$vcol, ""))
    X[[k]] <- cbind(1, as.matrix(d[, vars, drop = FALSE]))
    p[k] <- ncol(X[[k]])
    nsm[k] <- length(s$sm)
    for (z in s$sm) {
      smx[[length(smx) + 1]] <- d[[z$var]]
      smhdr[[length(smhdr) + 1]] <- c(z$type, z$a, z$b, z$c, z$df, z$lambda, z$method, z$start)
    }
  }
  lks <- c(links, 4)[1:3]
  hdr <- function(f, kind, idx) c(f, algo, n, p, lks, kind, idx, cc, ncyc, n1, n2, as.numeric(auto), 0, steps, nsm)
  data <- c(unlist(smhdr), y, w, unlist(lapply(X, as.vector)), unlist(smx))
  first <- TRUE
  add <- function(kind, idx, want, r = rel) {
    h <- hdr(if (first) fam else 99, kind, idx)
    cases[[length(cases) + 1]] <<- case("fit", if (first) c(h, data) else h, want, rel = r, abs = if (r == 0) 0 else 1e-12)
    first <<- FALSE
  }
  par <- list(m$mu.fv, if (np > 1) m$sigma.fv, if (np > 2) m$nu.fv)
  co <- c(coef(m, "mu"), if (np > 1) coef(m, "sigma"), if (np > 2) coef(m, "nu"))
  for (j in seq_along(co)) if (!is.na(co[j])) add(0, j - 1, unname(co[j]))
  add(1, 0, m$G.deviance)
  add(2, 0, m$iter, r = 0)
  add(3, 0, as.numeric(m$converged), r = 0)
  add(5, 0, m$df.fit)
  add(6, 0, m$aic)
  add(7, 0, m$sbc)
  add(14, 0, m$pen)
  add(17, 0, m$P.deviance)
  si <- 0
  for (k in seq_len(np)) {
    nm <- pnames[k]
    add(13, k - 1, m[[paste0(nm, ".nl.df")]])
    lam <- m[[paste0(nm, ".lambda")]]
    sm <- m[[paste0(nm, ".s")]]
    for (j in seq_len(nsm[k])) {
      add(15, si, lam[j])
      for (i in c(1, n %/% 3, n %/% 2, n)) add(16, si * n + i - 1, sm[i, j])
      si <- si + 1
    }
    for (i in c(1, n %/% 2, n)) {
      add(4, (k - 1) * n + i - 1, par[[k]][i])
      add(8, (k - 1) * n + i - 1, m[[paste0(nm, ".wv")]][i])
      add(9, (k - 1) * n + i - 1, m[[paste0(nm, ".wt")]][i])
      add(10, (k - 1) * n + i - 1, m[[paste0(nm, ".lp")]][i])
    }
  }
}
pbs <- function(var, df = -1, lambda = -1, inter = 20, degree = 3, order = 2, start = 10) {
  extra <- c(if (df >= 0) paste0("df=", df), if (lambda >= 0) paste0("lambda=", lambda), if (inter != 20) paste0("control=pb.control(inter=", inter, ")"))
  list(var = var, vcol = var, call = paste0("pb(", paste(c(var, extra), collapse = ", "), ")"), type = 1, a = inter, b = degree, c = order, df = df, lambda = lambda, method = 0, start = start)
}
n <- 60
set.seed(20261601)
x1 <- round(runif(n, 0, 5), 3); x2 <- round(rnorm(n), 3)
d0 <- data.frame(x1 = x1, x2 = x2, z0 = 0)
one <- rep(1, n)
fx <- sin(x1 * 1.3) + 0.3 * x1
yno <- round(1 + fx - 0.4 * x2 + exp(-0.7 + 0.15 * x1) * rnorm(n), 4)
spmu <- list(list(lin = "x2", sm = list(pbs("x1"))), list(lin = "x1", sm = list()))
for (a in 0:2) mk(0, a, yno, one, d0, spmu, c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
# pb(x1, df = 4): R finds lambda with uniroot (tolerance eps^0.25 on log lambda), so R itself moves lambda by 3e-5 relative when y changes by 1e-12; coefficients are compared at 1e-4, the log lambda root cannot be matched closer
mk(0, 0, yno, one, d0, list(list(lin = character(0), sm = list(pbs("x1", df = 4))), list(lin = character(0), sm = list())), c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, 1e-4)
mk(0, 1, yno, one, d0, list(list(lin = character(0), sm = list(pbs("x1", lambda = 50))), list(lin = character(0), sm = list(pbs("x2")))), c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
mk(0, 0, yno, sample(1:3, n, TRUE), d0, list(list(lin = character(0), sm = list(pbs("x1", inter = 8))), list(lin = character(0), sm = list())), c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
yga <- round(rgamma(n, shape = 4, scale = exp(0.4 + 0.5 * sin(x1)) / 4) + 0.01, 4)
for (a in 0:1) mk(1, a, yga, one, d0, list(list(lin = character(0), sm = list(pbs("x1"))), list(lin = "x2", sm = list())), c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
ypo <- rpois(n, exp(0.5 + 0.6 * sin(x1)))
for (a in 0:1) mk(2, a, ypo, one, d0, list(list(lin = "x2", sm = list(pbs("x1")))), c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
ywe <- round(rweibull(n, shape = 2.2, scale = exp(0.8 + 0.3 * sin(x1))), 4)
for (a in 0:1) mk(3, a, ywe, one, d0, list(list(lin = character(0), sm = list(pbs("x1"))), list(lin = character(0), sm = list())), c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
# gamlss.pb called directly: [88, out kind, out index, n, inter, degree, order, df, lambda, start, y, w, x]; kinds 0 lambda, 1 nl.df, 2 fitted value
gamlss_pbcall <- function(x, y, w, df, lambda, inter, degree, order, start) {
  ctl <- pb.control(inter = inter, degree = degree, order = order, start = start)
  xv <- pb(x, df = if (df >= 0) df else NULL, lambda = if (lambda >= 0) lambda else NULL, control = ctl)
  gamlss:::gamlss.pb(xv, y, w)
}
dpb <- function(y, w, x, df = -1, lambda = -1, inter = 20, degree = 3, order = 2, start = 10, rel = 1e-9) {
  n <- length(y)
  f <- gamlss_pbcall(x, y, w, df, lambda, inter, degree, order, start)
  first <- TRUE
  add <- function(kind, idx, want) {
    h <- c(88, kind, idx, n, inter, degree, order, df, lambda, start)
    cases[[length(cases) + 1]] <<- case("pb", if (first) c(h, y, w, x) else h, want, rel = rel, abs = 1e-12)
    first <<- FALSE
  }
  add(0, 0, f$lambda)
  add(1, 0, f$nl.df)
  for (i in c(1, n %/% 4, n %/% 2, n)) add(2, i - 1, f$fitted.values[i])
}
ys <- round(sin(x1 * 1.3) + 0.3 * x1 + rnorm(n, 0, 0.4), 4)
dpb(ys, one, x1)
dpb(ys, one, x1, df = 4)
dpb(ys, one, x1, df = 8)
dpb(ys, one, x1, lambda = 30)
dpb(ys, one, x1, inter = 8)
dpb(ys, one, x1, order = 1)
dpb(ys, one, x1, degree = 2, inter = 12)
dpb(ys, sample(1:3, n, TRUE), x1)
dpb(ys, sample(1:3, n, TRUE), x1, df = 5)
# lo(): loess smoother, type 3 (a span, b degree, df the enp.target or -1); its design column is the zero vector lo() returns, and the aliased coefficient is left out
los <- function(var, span = 0.75, degree = 2, df = -1) {
  extra <- c(if (span != 0.75) paste0("span=", span), if (degree != 2) paste0("degree=", degree), if (df >= 0) paste0("df=", df))
  list(var = var, vcol = "z0", call = paste0("lo(~", paste(c(var, extra), collapse = ", "), ")"), type = 3, a = span, b = degree, c = 0, df = df, lambda = -1, method = 0, start = 0)
}
nolin <- character(0)
sg0 <- list(lin = nolin, sm = list())
for (a in 0:2) mk(0, a, yno, one, d0, list(list(lin = "x2", sm = list(los("x1"))), sg0), c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
mk(0, 0, yno, one, d0, list(list(lin = nolin, sm = list(los("x1", df = 4))), list(lin = "x1", sm = list())), c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
mk(0, 0, yno, one, d0, list(list(lin = nolin, sm = list(los("x1", span = 0.5, degree = 1))), list(lin = nolin, sm = list(los("x2", span = 0.8)))), c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
mk(0, 0, yno, sample(1:3, n, TRUE), d0, list(list(lin = nolin, sm = list(los("x1"))), sg0), c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
for (a in 0:1) mk(1, a, yga, one, d0, list(list(lin = nolin, sm = list(los("x1"))), list(lin = "x2", sm = list())), c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
mk(3, 0, ywe, one, d0, list(list(lin = nolin, sm = list(los("x1"))), sg0), c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
mk(2, 0, ypo, one, d0, list(list(lin = "x2", sm = list(los("x1")))), c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE)
# loess as gamlss.lo calls it: [87, out kind, out index, n, span, degree, enp.target, y, w, x]; kinds 0 span, 1 nl.df, 2 fitted value
dlo <- function(y, w, x, span = 0.75, degree = 2, enp = -1) {
  n <- length(y)
  D <- data.frame(x = x, Y.var = y, W.var = w)
  ctl <- loess.control(surface = "interpolate", statistics = "approximate", trace.hat = "exact", iterations = 4)
  fit <- if (enp < 0) loess(Y.var ~ x, data = D, weights = W.var, span = span, degree = degree, family = "gaussian", control = ctl) else loess(Y.var ~ x, data = D, weights = W.var, enp.target = enp, degree = degree, family = "gaussian", control = ctl)
  first <- TRUE
  add <- function(kind, idx, want) {
    h <- c(87, kind, idx, n, span, degree, enp)
    cases[[length(cases) + 1]] <<- case("lo", if (first) c(h, y, w, x) else h, want, rel = 1e-9, abs = 1e-12)
    first <<- FALSE
  }
  add(0, 0, fit$pars[["span"]])
  add(1, 0, fit$trace.hat - 1)
  for (i in c(1, n %/% 4, n %/% 2, n)) add(2, i - 1, fitted(fit)[i])
}
dlo(ys, one, x1)
dlo(ys, one, x1, span = 0.5)
dlo(ys, one, x1, degree = 1)
dlo(ys, one, x1, enp = 5)
dlo(ys, sample(1:3, n, TRUE), x1, span = 0.6)
dlo(ys, sample(1:3, n, TRUE), x2, span = 0.9, degree = 2)
# cs(): smooth.spline smoother, type 2 (df the target extra df of cs(), -1 with a spar, lambda the spar or -1); its design column is x itself
stopifnot(length(unique(x1)) == n, length(unique(x2)) == n)
css <- function(var, df = 3, spar = -1) {
  call <- if (spar >= 0) paste0("cs(", var, ", df=NULL, spar=", spar, ")") else if (df != 3) paste0("cs(", var, ", df=", df, ")") else paste0("cs(", var, ")")
  list(var = var, vcol = var, call = call, type = 2, a = 0, b = 0, c = 0, df = if (spar >= 0) -1 else df, lambda = spar, method = 0, start = 0)
}
# cs(): the df target is met by the sbart spar search (golden section and Brent steps stopping on a spar tolerance), so scenarios with df/GCV spar reproduce R to about 3e-9, not machine precision; compared at 1e-8
for (a in 0:2) mk(0, a, yno, one, d0, list(list(lin = "x2", sm = list(css("x1"))), sg0), c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, 1e-8)
mk(0, 0, yno, one, d0, list(list(lin = nolin, sm = list(css("x1", df = 5))), list(lin = "x1", sm = list())), c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, 1e-8)
mk(0, 1, yno, one, d0, list(list(lin = nolin, sm = list(css("x1", spar = 0.7))), list(lin = nolin, sm = list(css("x2", df = 2)))), c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, 1e-8)
mk(0, 0, yno, sample(1:3, n, TRUE), d0, list(list(lin = nolin, sm = list(css("x1"))), sg0), c(4, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, 1e-8)
for (a in 0:1) mk(1, a, yga, one, d0, list(list(lin = nolin, sm = list(css("x1"))), list(lin = "x2", sm = list())), c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, 1e-8)
mk(3, 0, ywe, one, d0, list(list(lin = nolin, sm = list(css("x1"))), sg0), c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, 1e-8)
mk(2, 0, ypo, one, d0, list(list(lin = "x2", sm = list(css("x1")))), c(5, 5, 4), c(1, 1, 1), 0.001, 20, 1, 20, TRUE, 1e-8)
# gamlss.cs called directly: [86, out kind, out index, n, df, spar, y, w, x] with df -1 for none; kinds 0 lambda, 1 nl.df, 2 fitted value
dcs <- function(y, w, x, df = -1, spar = -1) {
  n <- length(y)
  xv <- cs(x, df = if (spar >= 0) NULL else if (df >= 0) df else 3, spar = if (spar >= 0) spar else NULL)
  f <- gamlss:::gamlss.cs(xv, y, w, df = if (spar >= 0) NULL else if (df >= 0) df else 3, spar = if (spar >= 0) spar else NULL)
  first <- TRUE
  add <- function(kind, idx, want) {
    h <- c(86, kind, idx, n, if (spar < 0 && df < 0) 3 else df, spar)
    cases[[length(cases) + 1]] <<- case("cs", if (first) c(h, y, w, x) else h, want, rel = 1e-9, abs = 1e-12)
    first <<- FALSE
  }
  add(0, 0, f$lambda)
  add(1, 0, f$nl.df)
  for (i in c(1, n %/% 4, n %/% 2, n)) add(2, i - 1, f$fitted.values[i])
}
dcs(ys, one, x1)
dcs(ys, one, x1, df = 5)
dcs(ys, one, x1, df = 8)
dcs(ys, one, x1, spar = 0.6)
dcs(ys, sample(1:3, n, TRUE), x1, df = 4)
dcs(ys, sample(1:3, n, TRUE), x2, spar = 0.9)
emit("gamlss_smooth", c("gamlss", "gamlss.dist"), list(cases))
