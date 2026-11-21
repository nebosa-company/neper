# marginaleffects end to end: the fit is done by Neper (glm.fit port) from the data in the case, then slopes, comparisons, predictions, hypotheses over estimates and joint tests are taken from it.
# "mfit" args: (n, model 0 ~x+w 1 ~f+x 2 ~f*x 3 ~x+I(x^2)+f 4 ~x*w+f, coding 0 treatment 1 sum 2 Helmert, nf, fl 0 gaussian 1 logit 2 poisson log 3 probit 4 cloglog 6 poisson sqrt, op, a, b, kind, which, y[n], f[n] (0 based), x[n], w[n], extra[2 nf + 2]).
# op 0 avg_slopes(x) (a 0 all rows, a > 0 by = "f" level a - 1); op 1 avg_comparisons of f level a against level b, kind 0 difference 1 ratio 2 lnratio 3 lift; op 2 avg_predictions(by = "f") level a;
# op 3 avg_predictions by group of the average x quantile... unused; op 4 hypothesis ~pairwise (kind 0) ~revpairwise (1) ~sequential (2) ~reference (3) row a over avg_predictions(by = "f");
# op 5 the same over avg_slopes(x, by = "f"); op 6 hypothesis = c("r1 = q1", "r2 = q2") over avg_predictions(by = "f"), row a (extra = r1[nf], q1, r2[nf], q2); op 7 joint test of the factor coefficients, which 0 F 1 its p-value 2 chi-square 3 its p-value;
# which for ops 0-6: 0 estimate 1 standard error 2 z 3 p.
suppressMessages(library(marginaleffects))
options(marginaleffects_safe = FALSE)
cases <- list()
set.seed(20262601)
cmpn <- c("differenceavg", "ratioavg", "lnratioavg", "liftavg")
hyps <- c("pairwise", "revpairwise", "sequential", "reference")
fst <- function(model) c(NA, 1, 1, 3, 4)[model + 1]
specs <- list(c(2, 1, 3, 0), c(1, 0, 3, 1), c(3, 2, 2, 0), c(4, 3, 3, 2), c(2, 6, 4, 1), c(1, 1, 3, 0), c(0, 1, 2, 0), c(3, 0, 3, 1), c(4, 2, 3, 2), c(2, 0, 4, 0), c(1, 4, 3, 1), c(3, 1, 3, 0))
nfit <- 0
for (sp in specs) {
  model <- sp[1]; fl <- sp[2]; nf <- sp[3]; coding <- sp[4]
  n <- 30
  f0 <- sample(rep(0:(nf - 1), length.out = n)); f <- factor(letters[f0 + 1], levels = letters[1:nf])
  x <- round(rnorm(n), 3); w <- round(rnorm(n), 3)
  eta <- 0.1 + 0.4 * (f0 == 1) - 0.3 * (f0 == 2) + 0.5 * x - 0.3 * w
  y <- switch(fl + 1, eta + rnorm(n), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)), rbinom(n, 1, pnorm(eta)), rbinom(n, 1, 1 - exp(-exp(eta))), NA, rpois(n, (1 + 0.2 * eta)^2 * 3))
  d <- data.frame(y = y, f = f, x = x, w = w, g = factor(w > 0, levels = c(FALSE, TRUE)))
  fo <- as.formula(c("y ~ x + w", "y ~ f + x", "y ~ f * x", "y ~ x + I(x^2) + f", "y ~ x * w + f")[model + 1])
  ct <- list(f = c("contr.treatment", "contr.sum", "contr.helmert")[coding + 1])
  fam <- list(gaussian(), binomial(), poisson(), binomial(link = "probit"), binomial(link = "cloglog"), NA, poisson(link = "sqrt"))[[fl + 1]]
  m <- tryCatch(suppressWarnings(if (fl == 0 && nfit %% 2 == 0) lm(fo, d, contrasts = if (model > 0) ct) else glm(fo, fam, d, contrasts = if (model > 0) ct)), error = function(e) NULL)
  if (is.null(m) || (inherits(m, "glm") && !m$converged)) next
  nfit <- nfit + 1
  dfr <- df.residual(m)
  ext <- rep(0, 2 * nf + 2)
  hdr <- function(op, a, b, kind, which, extra = numeric(0)) c(n, model, coding, nf, fl, op, a, b, kind, which, y, f0, x, w, extra)
  add <- function(args, v, tol = 1e-9) if (is.finite(v)) cases[[length(cases) + 1]] <<- case("mfit", args, v, rel = tol, abs = 1e-10)
  pull <- function(r, row, which) if (which == 0) r$estimate[row] else if (which == 1) r$std.error[row] else if (which == 2) r$statistic[row] else r$p.value[row]
  grp <- function(r, a) { if (nrow(r) == 1) 1 else match(letters[a + 1], as.character(r$f)) }
  # slopes of x
  r <- as.data.frame(avg_slopes(m, variables = "x"))
  for (wh in 0:1) add(hdr(0, 0, 0, 0, wh), pull(r, 1, wh))
  if (model >= 1) {
    rb <- as.data.frame(avg_slopes(m, variables = "x", by = "f"))
    for (a in unique(c(0, nf - 1))) for (wh in 0:1) add(hdr(0, a + 1, 0, 0, wh), pull(rb, grp(rb, a), wh))
    # comparisons of factor levels
    for (pr in list(c(1, 0), c(nf - 1, 1))) {
      kinds <- if (fl %in% c(1, 2, 3, 4, 6)) 0:3 else 0
      for (kd in kinds) {
        rc <- tryCatch(as.data.frame(avg_comparisons(m, variables = list(f = c(letters[pr[2] + 1], letters[pr[1] + 1])), comparison = cmpn[kd + 1])), error = function(e) NULL)
        if (is.null(rc) || nrow(rc) != 1) next
        for (wh in 0:1) add(hdr(1, pr[1], pr[2], kd, wh), pull(rc, 1, wh))
      }
    }
    # comparisons by group: op 3 unit change of x by f level a, op 8 factor level pair (a over b) by g = (w > 0) (extra[1] is g's group, 0 / 1)
    for (a in unique(c(0, nf - 1))) {
      rcx <- as.data.frame(avg_comparisons(m, variables = list(x = 1), by = "f"))
      for (wh in 0:1) add(hdr(3, a, 0, 0, wh), pull(rcx, grp(rcx, a), wh))
    }
    for (kd in (if (fl %in% c(1, 2, 3, 4, 6)) 0:3 else 0)) {
      rg <- tryCatch(as.data.frame(avg_comparisons(m, variables = list(f = c("a", letters[nf])), by = "g", comparison = cmpn[kd + 1])), error = function(e) NULL)
      if (is.null(rg)) next
      for (gr in 0:1) for (wh in 0:1) add(hdr(8, nf - 1, 0, kd, wh, gr), pull(rg, match(as.character(gr == 1), as.character(rg$g)), wh))
    }
    # predictions by group
    rp <- as.data.frame(avg_predictions(m, by = "f"))
    for (a in 0:(nf - 1)) for (wh in 0:1) add(hdr(2, a, 0, 0, wh), pull(rp, grp(rp, a), wh))
    # hypotheses over the estimates
    for (hk in 0:3) {
      hf <- as.formula(paste0("~", hyps[hk + 1]))
      rh <- tryCatch(as.data.frame(avg_predictions(m, by = "f", hypothesis = hf)), error = function(e) NULL)
      if (!is.null(rh)) for (row in seq_len(nrow(rh))) for (wh in 0:(if (hk == 0) 3 else 1)) add(hdr(4, row - 1, 0, hk, wh), pull(rh, row, wh))
      rs <- tryCatch(as.data.frame(avg_slopes(m, variables = "x", by = "f", hypothesis = hf)), error = function(e) NULL)
      if (!is.null(rs) && hk %in% c(0, 2)) for (row in seq_len(nrow(rs))) for (wh in 0:1) add(hdr(5, row - 1, 0, hk, wh), pull(rs, row, wh))
    }
    # two-row hypothesis strings with free weights
    rw1 <- sample(c(-2, -1, 0, 1, 2), nf, TRUE); rw1[1] <- 1; rw2 <- sample(c(-1, 0, 1, 2), nf, TRUE); rw2[nf] <- -1; q1 <- 0.5; q2 <- 0
    hs <- function(rv, q) paste0(paste0(ifelse(rv < 0, "-", "+"), abs(rv), "*b", seq_along(rv), collapse = ""), "=", q)
    rh2 <- tryCatch(as.data.frame(avg_predictions(m, by = "f", hypothesis = c(hs(rw1, q1), hs(rw2, q2)))), error = function(e) NULL)
    if (!is.null(rh2) && nrow(rh2) == 2) for (row in 1:2) for (wh in 0:3) add(hdr(6, row - 1, 0, 0, wh, c(rw1, q1, rw2, q2)), pull(rh2, row, wh))
    # joint test of the factor's own coefficients
    nm <- names(coef(m)); jn <- nm[grepl("^f", nm) & !grepl(":", nm)]
    jF <- as.data.frame(hypotheses(m, joint = jn)); jC <- as.data.frame(hypotheses(m, joint = jn, joint_test = "chisq"))
    add(hdr(7, 0, 0, 0, 0), jF$statistic[1]); add(hdr(7, 0, 0, 0, 1), jF$p.value[1]); add(hdr(7, 0, 0, 0, 2), jC$statistic[1]); add(hdr(7, 0, 0, 0, 3), jC$p.value[1])
  }
}
emit("margeff2", "marginaleffects", list(cases))
