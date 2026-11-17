# lme4 lmer with one random intercept: "lmer" (n, p, ng, reml, which, X[n p] column-major, group codes 0-based[n], y[n]);
# which 0 deviance (the REML criterion or the ML deviance) 1 theta 2 sigma 3 sigma_b 4 + j fixef[j] 5 + p + g ranef[g]
suppressMessages(library(lme4)); suppressMessages(library(lmerTest))
cases <- list()
add <- function(fn, args, want, tol) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-5)
set.seed(20261120)
for (rep in 1:24) {
  ng <- sample(5:12, 1); per <- sample(3:8, ng, TRUE); n <- sum(per); g <- rep(seq_len(ng) - 1, per); p <- sample(1:3, 1)
  X <- cbind(1, matrix(rnorm(n * (p - 1)), n, p - 1)); sb <- runif(1, 0.3, 2); b <- rnorm(ng, 0, sb); y <- as.vector(X %*% rnorm(p)) + b[g + 1] + rnorm(n)
  reml <- rep %% 2 == 0; d <- data.frame(y = y, g = factor(g)); for (j in seq_len(p - 1)) d[[paste0("x", j)]] <- X[, j + 1]
  f <- if (p == 1) y ~ 1 + (1 | g) else as.formula(paste("y ~", paste0("x", seq_len(p - 1), collapse = " + "), "+ (1 | g)"))
  m <- suppressWarnings(suppressMessages(lmer(f, d, REML = reml)))
  dv <- if (reml) REMLcrit(m) else deviance(m); th <- getME(m, "theta")[[1]]; sg <- sigma(m); fe <- fixef(m); re <- ranef(m)$g[[1]]
  a <- function(w) c(n, p, ng, as.numeric(reml), w, as.vector(X), g, y)
  add("lmer", a(0), dv, 1e-6); add("lmer", a(2), sg, 1e-4); add("lmer", a(3), th * sg, 1e-3)
  for (j in seq_len(p)) add("lmer", a(3 + j), fe[[j]], 1e-4)
  for (k in seq_len(ng)) add("lmer", a(3 + p + k), re[k], 1e-3)
  if (th > 0.05) { m2 <- suppressWarnings(suppressMessages(lmerTest::lmer(f, d, REML = reml))); sm <- coef(summary(m2)); th2 <- getME(m2, "theta")[[1]]; sg2 <- sigma(m2)
    for (j in seq_len(p)) { add("lmer", c(n, p, ng, as.numeric(reml), 1000 + j - 1, as.vector(X), g, y, th2, sg2), sm[j, "df"], 1e-4)
      add("lmer", c(n, p, ng, as.numeric(reml), 2000 + j - 1, as.vector(X), g, y, th2, sg2), sm[j, "t value"], 1e-4)
      add("lmer", c(n, p, ng, as.numeric(reml), 3000 + j - 1, as.vector(X), g, y, th2, sg2), sm[j, "Pr(>|t|)"], 1e-3) } 
    Lc <- rnorm(p); ct <- lmerTest::contest(m2, matrix(Lc, 1), joint = FALSE, confint = FALSE)
    for (k in 1:5) add("lmer", c(n, p, ng, as.numeric(reml), 4000 + k - 1, as.vector(X), g, y, th2, sg2, Lc), as.numeric(ct[1, c("Estimate", "Std. Error", "df", "t value", "Pr(>|t|)")][k]), c(1e-6, 1e-4, 1e-4, 1e-4, 1e-3)[k]) }
}
emit("lmer", "lme4", list(cases))
