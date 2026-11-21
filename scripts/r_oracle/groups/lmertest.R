# lmerTest on lmer models with one random intercept (anova type 1 and 3, summary, ranova, difflsmeans, contest, step), Satterthwaite and Kenward-Roger: "lmertest"
# args: n, p, ng, reml, op, sub, ddf (0 Satterthwaite, 1 Kenward-Roger), theta, sigma, nterm, r (columns of rdX), nextra, then X[n p] column-major, group codes 0-based[n], y[n], assign[p], rdX[n r], xmap[p] (0-based column of rdX named like each column of X),
# order[nterm], contain[nterm nterm] (row k, column s: term s contains term k), extra[nextra]
# op 1 summary table column sub (Estimate, Std. Error, df, t value, Pr(>|t|)); 2 anova column sub (Sum Sq, Mean Sq, NumDF, DenDF, F value, Pr(>F)), extra[0] the type; 3 difflsmeans column sub (Estimate, Std. Error, df, t value, lower, upper, Pr(>|t|)), extra[0] the term;
# 4 ranova entry sub (full npar, logLik, AIC, reduced npar, logLik, AIC, LRT, Df, p); 5 step entry sub (see lmer_step in lmerpkg.e); 6 contest1D column sub, extra = L; 7 joint contest column sub, extra = q, L (q by p, row-major)
# a table's rows are folded into one case by sum(value * row number); R's optimiser stops at its own tolerance, so the step cases (which refit) are judged at 1e-4
suppressMessages(library(lme4)); suppressMessages(library(lmerTest))
cases <- list()
chk <- function(v) sum(v * seq_along(v))
add <- function(args, want, tol) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("lmertest", args, want, rel = tol, abs = 1e-9)
set.seed(20261121)
mk <- function(form, K = 3, K2 = 0, ng = 6, beta = c(1, 0.8, -0.6, 0.5), sb = 1, nobs = NULL) {
  per <- if (is.null(nobs)) sample(3:5, ng, TRUE) else rep(nobs, ng); n <- sum(per); g <- rep(seq_len(ng), per)
  d <- data.frame(g = factor(g), x1 = rnorm(n), x2 = rnorm(n), f = factor(sample(rep_len(letters[1:K], n))))
  if (K2 > 0) d$f2 <- factor(sample(rep_len(LETTERS[1:K2], n)))
  X <- model.matrix(nobars(form[-2]), d); b <- rep_len(beta, ncol(X))
  d$y <- as.vector(X %*% b) + rnorm(ng, 0, sb)[g] + rnorm(n); d
}
pack <- function(m, op, sub, ddf, extra = numeric(0)) {
  X <- getME(m, "X"); n <- nrow(X); p <- ncol(X); ng <- nlevels(getME(m, "flist")[[1]]); reml <- as.numeric(isREML(m))
  Tm <- terms(m); nt <- length(attr(Tm, "term.labels")); asg <- attr(X, "assign")
  rd <- if (nt > 0) lmerTest:::get_rdX(m, do.warn = FALSE) else matrix(0, n, 0); xmap <- match(colnames(X), colnames(rd)) - 1
  cm <- lmerTest:::containment(m); cont <- matrix(0, nt, nt); for (k in seq_len(nt)) cont[k, match(cm[[k]], attr(Tm, "term.labels"))] <- 1
  c(n, p, ng, reml, op, sub, ddf, getME(m, "theta")[[1]], sigma(m), nt, ncol(rd), length(extra), as.vector(X), as.integer(getME(m, "flist")[[1]]) - 1, getME(m, "y"), asg, as.vector(rd), xmap, attr(Tm, "order"), as.vector(t(cont)), extra)
}
fit <- function(form, d, reml = TRUE) suppressWarnings(suppressMessages(eval(bquote(lmerTest::lmer(.(form), data = .(d), REML = .(reml))))))
ddfname <- c("Satterthwaite", "Kenward-Roger")
tab <- function(m, kr, typ) {
  dd <- ddfname[kr + 1]; sm <- coef(summary(m, ddf = dd)); an <- anova(m, type = typ, ddf = dd)
  list(sm = sm, an = an)
}
# every model: summary, anova, ranova, (difflsmeans of a factor term), contests
run <- function(form, d, reml, krs, diffterm = NULL, typs = 3, tol = 1e-9) {
  m <- fit(form, d, reml); th <- getME(m, "theta")[[1]]; if (th < 0.1) return(invisible())
  for (kr in krs) {
    tb <- tab(m, kr, typs[1])
    for (s in 0:4) { v <- tb$sm[, s + 1]; add(pack(m, 1, s, kr), chk(v), tol) }
    for (typ in typs) { an <- anova(m, type = typ, ddf = ddfname[kr + 1]); for (s in 0:5) add(pack(m, 2, s, kr, typ), chk(an[, s + 1]), tol) }
    if (!is.null(diffterm)) { dl <- difflsmeans(m, which = attr(terms(m), "term.labels")[diffterm], ddf = ddfname[kr + 1])
      for (s in 0:6) add(pack(m, 3, s, kr, diffterm - 1), chk(as.numeric(dl[, s + 1])), tol) }
    p <- length(fixef(m)); Lc <- rnorm(p); ct <- lmerTest::contest(m, matrix(Lc, 1), joint = FALSE, confint = FALSE, ddf = ddfname[kr + 1])
    for (s in 0:4) add(pack(m, 6, s, kr, Lc), as.numeric(ct[1, c("Estimate", "Std. Error", "df", "t value", "Pr(>|t|)")][s + 1]), tol)
    if (p >= 3) { q <- 2; Lm <- matrix(rnorm(q * p), q, p); cj <- lmerTest::contest(m, Lm, joint = TRUE, ddf = ddfname[kr + 1])
      for (s in 0:5) add(pack(m, 7, s, kr, c(q, as.vector(t(Lm)))), as.numeric(cj[1, s + 1]), tol) }
  }
  ra <- ranova(m); r1 <- as.numeric(ra[1, c("npar", "logLik", "AIC")]); r2 <- as.numeric(ra[2, c("npar", "logLik", "AIC", "LRT", "Df", "Pr(>Chisq)")])
  w <- c(r1, r2[1:3], r2[4:6])
  for (s in 0:8) add(pack(m, 4, s, 0), w[s + 1], 1e-8)
}
d1 <- mk(y ~ x1 + f + (1 | g), 3); run(y ~ x1 + f + (1 | g), d1, TRUE, 0:1, diffterm = 2, typs = c(3, 1))
d2 <- mk(y ~ f + (1 | g), 4, beta = c(1, 1, 0.5, -0.5), ng = 7); run(y ~ f + (1 | g), d2, TRUE, 0:1, diffterm = 1)
d3 <- mk(y ~ x1 + x2 + f + f2 + (1 | g), 3, 2, ng = 7); run(y ~ x1 + x2 + f + f2 + (1 | g), d3, TRUE, 0:1, diffterm = 3)
d4 <- mk(y ~ x1 + f + (1 | g), 3, ng = 6, beta = c(0.5, 0.7, 0.4, -0.4)); run(y ~ x1 + f + (1 | g), d4, FALSE, 0, diffterm = 2)
d5 <- mk(y ~ x1 * f + (1 | g), 3, ng = 7, beta = c(1, 0.8, 0.5, -0.5, 0.6, -0.4)); run(y ~ x1 * f + (1 | g), d5, TRUE, 0:1, typs = c(3, 1))
# step
stepcase <- function(form, d, reml, sb, tol = 1e-7) {
  m <- fit(form, d, reml); s <- suppressWarnings(suppressMessages(step(m))); Tm <- terms(m); tl <- attr(Tm, "term.labels"); nt <- length(tl)
  fx <- as.data.frame(s$fixed); fx$term <- rownames(fx); fx$term <- sub("^[0-9]+\\.", "", fx$term)
  el <- fx[fx$Eliminated > 0, ]; el <- el[order(el$Eliminated), ]; fin <- fx[fx$Eliminated == 0, ]
  rd <- as.data.frame(s$random); rr <- ranova(m)
  kept <- inherits(get_model(s), "lmerMod"); idx <- function(nm) match(sub("^[0-9]+\\.", "", nm), tl)
  elp <- if (nrow(el)) el[["Pr(>F)"]] else numeric(0); eli <- idx(el$term)
  fcol <- function(nm) { v <- rep(NA, nt); v[idx(fin$term)] <- fin[[nm]]; v }
  ddv <- if (kept) fcol("DenDF") else rep(df.residual(get_model(s)), nt)
  pcol <- fcol("Pr(>F)"); fc <- fcol("F value")
  want <- c(as.numeric(kept), nrow(el), chk(eli), chk(elp), chk(fc[!is.na(fc)]), chk(ddv[!is.na(fc)]), chk(pcol[!is.na(fc)]), rr[2, "Pr(>Chisq)"], rr[2, "LRT"])
  for (sb in 0:8) add(pack(m, 5, sb, 0, c(0.1, 0.05)), want[sb + 1], if (sb < 2 || sb == 2) 1e-12 else tol)
}
s1 <- mk(y ~ x1 + x2 + f + (1 | g), 3, ng = 8, beta = c(1, 1.2, 0, 0, 0), sb = 1.5); stepcase(y ~ x1 + x2 + f + (1 | g), s1, TRUE)
s2 <- mk(y ~ x1 + x2 + f + (1 | g), 3, ng = 8, beta = c(1, 1.2, 0.5, 0, 0), sb = 0.05); stepcase(y ~ x1 + x2 + f + (1 | g), s2, TRUE)
emit("lmertest", c("lme4", "lmerTest", "pbkrtest"), list(cases))
