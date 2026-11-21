# nlme::nlme with a user-written model function (a Weibull growth curve with its gradient from deriv()), pdMat classes for the random effects (pdSymm,
# pdDiag, pdIdent) and two nested grouping levels (random = list(Plot = ..., Subject = ...)), self-start (SSlogis) and user models, ML and REML.
# The reference is the fixed point of nlme's alternating algorithm (scripts/r_oracle/nlme_multi.R), which is checked against nlme(pnlsTol = 1e-7) before a case is kept
# (estimates, sigma, logLik to 2e-5 relative, se to 2e-4; in the oracle run they agreed to 1.4e-8); the fixed point is located to ~1e-9, so every output carries
# rel 1e-8 / abs 1e-8 (the absolute floor is for correlations near zero). pdCompSymm is not here: nlme itself has not written that class for nlme() ("Haven't written the compound symmetry case").
# case: c(kind, q_out, reml, n, ng1, ng2, gs1[ng1], gs2[ng2], x[n], y[n], nr1, rs1[nr1], pd1, nr2, rs2[nr2], pd2, start[np]); kind 0 is the user model, 1 SSlogis;
# ng2 = 0 is one level. Output vector as in nlme_multi.R (mfix_out).
suppressMessages(library(nlme))
cases <- list()
set.seed(20261124)
source(file.path(root, "scripts", "r_oracle", "nlme_multi.R"))
fw <- deriv(~ A - B * exp(-exp(lk) * x^pw), c("A", "B", "lk", "pw"), function(x, A, B, lk, pw) NULL)
mfu <- function(x, p) fw(x, p[1], p[2], p[3], p[4])
mfl <- function(x, p) { Asym <- p[1]; xmid <- p[2]; scal <- p[3]; SSlogis(x, Asym, xmid, scal) }
assign("fw", fw, envir = globalenv())
# one level: ng groups of m observations
mk1 <- function(kind, ng, m, sdr, sde, rs) {
  tru <- if (kind == 0) c(10, 8, -2.5, 1.4) else c(10, 6, 1.5)
  x <- rep(if (kind == 0) round(seq(1, 12, length.out = m), 3) else round(seq(1, 12, length.out = m), 3), ng); g1 <- rep(seq_len(ng), each = m)
  mf <- if (kind == 0) mfu else mfl
  RE <- matrix(rnorm(ng * length(rs)), ng, length(rs)) * rep(sdr, each = ng)
  y <- numeric(length(x))
  for (t in seq_along(x)) { p <- tru; p[rs] <- p[rs] + RE[g1[t], ]; y[t] <- as.numeric(mf(x[t], p)) + rnorm(1, 0, sde) }
  data.frame(y = round(y, 4), x = x, g1 = g1, g2 = 0L, Plot = factor(g1))
}
# two nested levels: ng1 plots, k subjects per plot, m observations per subject
mk2 <- function(kind, ng1, k, m, sdr1, sdr2, sde, rs1, rs2) {
  tru <- if (kind == 0) c(10, 8, -2.5, 1.4) else c(10, 6, 1.5)
  g1 <- rep(seq_len(ng1), each = k * m); g2 <- rep(seq_len(ng1 * k), each = m); x <- rep(round(seq(1, 12, length.out = m), 3), ng1 * k)
  mf <- if (kind == 0) mfu else mfl
  R1 <- matrix(rnorm(ng1 * length(rs1)), ng1, length(rs1)) * rep(sdr1, each = ng1); R2 <- matrix(rnorm(ng1 * k * length(rs2)), ng1 * k, length(rs2)) * rep(sdr2, each = ng1 * k)
  y <- numeric(length(x))
  for (t in seq_along(x)) { p <- tru; p[rs1] <- p[rs1] + R1[g1[t], ]; p[rs2] <- p[rs2] + R2[g2[t], ]; y[t] <- as.numeric(mf(x[t], p)) + rnorm(1, 0, sde) }
  data.frame(y = round(y, 4), x = x, g1 = g1, g2 = g2, Plot = factor(g1), Subject = factor(g2))
}
pnm <- list(c("A", "B", "lk", "pw"), c("Asym", "xmid", "scal"))
pdf <- function(pd, f) switch(pd + 1, pdSymm(f), pdDiag(f), pdIdent(f), pdCompSymm(f))
run <- function(kind, d, rs1, pd1, rs2 = integer(0), pd2 = 0, reml = 0, start, label) {
  if (nzchar(Sys.getenv("ONLY")) && Sys.getenv("ONLY") != label) return(NULL)
  message(label, " ", format(Sys.time()))
  nm <- pnm[[kind + 1]]; npm <- length(nm)
  fxl <- lapply(nm, function(s) as.formula(paste(s, "~ 1")))
  mdl <- if (kind == 0) y ~ fw(x, A, B, lk, pw) else y ~ SSlogis(x, Asym, xmid, scal)
  rf <- function(rs) as.formula(paste(paste(nm[rs], collapse = " + "), "~ 1"))
  two <- length(rs2) > 0
  rnd <- if (two) { l <- list(pdf(pd1, rf(rs1)), pdf(pd2, rf(rs2))); names(l) <- c("Plot", "Subject"); l } else pdf(pd1, rf(rs1))
  ctl <- nlmeControl(pnlsTol = 1e-7, tolerance = 1e-9, msTol = 1e-12, pnlsMaxIter = 50, maxIter = 100, returnObject = TRUE)
  f <- tryCatch(suppressWarnings(nlme(mdl, data = d, fixed = fxl, random = rnd, groups = if (two) ~ Plot / Subject else ~ Plot, start = start, method = if (reml) "REML" else "ML", control = ctl)),
                error = function(e) { message(label, ": nlme failed: ", conditionMessage(e)); NULL })
  if (is.null(f)) return(NULL)
  mf <- if (kind == 0) mfu else mfl
  r <- tryCatch(mfix(mf, d, npm, rs1, pd1, rs2, pd2, reml, as.numeric(fixef(f))), error = function(e) { message(label, ": mfix failed: ", conditionMessage(e)); NULL })
  if (is.null(r) || !r$conv) { message(label, ": no convergence"); return(NULL) }
  # a second fixed point from the supplied start values (what Neper starts from)
  r0 <- tryCatch(mfix(mf, d, npm, rs1, pd1, rs2, pd2, reml, start), error = function(e) NULL)
  message(label, ": start fixpoint ", if (is.null(r0)) "failed" else paste(r0$conv, signif(max(abs(r0$beta - r$beta) / pmax(abs(r$beta), 1e-3)), 3)))
  ref <- c(as.numeric(fixef(f)), f$sigma, as.numeric(logLik(f)))
  mine <- c(r$beta, r$sigma, r$ll)
  dev <- max(abs(ref - mine) / pmax(abs(ref), 1e-3)); dse <- max(abs(sqrt(diag(vcov(f))) - sqrt(diag(solve(r$xvx))) * r$sigma) / (sqrt(diag(solve(r$xvx))) * r$sigma))
  message(label, ": vs nlme ", signif(dev, 3), " se ", signif(dse, 3))
  if (dev > 2e-5 || dse > 2e-4) { message(label, ": differs from nlme, dropped"); return(NULL) }
  ov <- mfix_out(r); if (nzchar(Sys.getenv("ONLY"))) { vcs <- lapply(f$modelStruct$reStruct, function(z) as.numeric(pdMatrix(z))); message("nlme sds ", paste(format(sqrt(unlist(lapply(f$modelStruct$reStruct, function(z) diag(pdMatrix(z)))))*f$sigma, digits = 12), collapse = " "), "  fix ", paste(format(ov[npm + 4 + seq_len(length(rs1) + length(rs2))], digits = 12), collapse = " ")) }
  args0 <- c(reml, nrow(d), max(d$g1), if (two) max(d$g2) else 0, as.vector(table(d$g1)), if (two) as.vector(table(d$g2)), d$x, d$y, length(rs1), rs1, pd1, length(rs2), rs2, pd2, start)
  q1 <- length(rs1); q2 <- length(rs2); c0 <- npm + 4 + q1 + q2; nc <- q1 * (q1 - 1) / 2 + q2 * (q2 - 1) / 2
  for (j in seq_along(ov)) {
    cor <- j > c0 && j <= c0 + nc
    cases[[length(cases) + 1]] <<- case("nlme", c(kind, j - 1, args0), ov[j], rel = 1e-8, abs = 1e-8)
  }
  # nlme's own returned fixed effects, sigma and logLik (pnlsTol = 1e-7 stopping point), output index + 1000
  for (j in seq_along(ref)) cases[[length(cases) + 1]] <<- case("nlme", c(kind, 1000 + j - 1, args0), ref[j], rel = 2e-5, abs = 1e-6)
  NULL
}
su <- c(10, 8, -2.5, 1.4); sl <- c(10, 6, 1.5)
# user-written model function
d <- mk1(0, 10, 9, c(1.2, 0.25), 0.25, c(1, 3)); run(0, d, c(1, 3), 0, start = su, label = "user symm")
d <- mk1(0, 10, 9, c(1.2, 0.25), 0.25, c(1, 3)); run(0, d, c(1, 3), 0, reml = 1, start = su, label = "user symm reml")
d <- mk1(0, 10, 9, c(1.0, 0.8), 0.25, c(1, 2)); run(0, d, c(1, 2), 1, start = su, label = "user diag")
# pdMat classes on SSlogis
d <- mk1(1, 10, 8, c(1.2, 0.8, 0.5), 0.3, c(1, 2, 3)); run(1, d, c(1, 2, 3), 0, start = sl, label = "logis symm")
run(1, d, c(1, 2, 3), 1, start = sl, label = "logis diag")
d <- mk1(1, 10, 8, c(0.4, 0.4, 0.4), 0.3, c(1, 2, 3)); run(1, d, c(1, 2, 3), 2, start = sl, label = "logis ident")
run(1, d, c(1, 2, 3), 1, reml = 1, start = sl, label = "logis diag reml")
# two nested levels
d <- mk2(1, 5, 3, 8, 1.2, c(0.8, 0.5), 0.3, 1, c(1, 2)); run(1, d, 1, 0, c(1, 2), 0, start = sl, label = "nest logis")
d <- mk2(1, 5, 3, 8, 1.2, c(0.8, 0.5), 0.3, 1, c(1, 2)); run(1, d, 1, 0, c(1, 2), 1, reml = 1, start = sl, label = "nest logis diag reml")
d <- mk2(0, 5, 3, 9, 1.2, c(0.8, 0.2), 0.25, 1, c(1, 3)); run(0, d, 1, 0, c(1, 3), 0, start = su, label = "nest user")
emit("nlmeext", "nlme", list(cases))
