# lavaan cfa of one factor: "cfa" args (n, p, S[p*p] row-major (divisor n - 1), q) q 0..p-1 loading, p..2p-1 residual variance, 2p factor variance, 2p+1 chi-square, 2p+2 df, 2p+3 p value
suppressMessages(library(lavaan))
cases <- list()
set.seed(20271101)
for (rep in 1:14) {
  n <- sample(150:400, 1); p <- sample(4:6, 1); f <- rnorm(n); X <- sapply(1:p, function(j) 0.7 * f * runif(1, 0.6, 1.2) + rnorm(n, 0, 0.6)); colnames(X) <- paste0("x", 1:p)
  d <- as.data.frame(X)
  fit <- tryCatch(suppressWarnings(cfa(paste("f =~", paste(colnames(X), collapse = " + ")), d)), error = function(e) NULL)
  if (is.null(fit) || !lavInspect(fit, "converged")) next
  pe <- parameterEstimates(fit); ld <- pe$est[pe$op == "=~"]; th <- pe$est[pe$op == "~~" & pe$lhs != "f"]; ps <- pe$est[pe$op == "~~" & pe$lhs == "f"]
  fm <- fitMeasures(fit, c("chisq", "df", "pvalue"))
  v <- c(ld, th, ps, as.numeric(fm))
  S <- cov(X)
  se <- pe$se[pe$op == "=~"][-1]; se <- c(se, pe$se[pe$op == "~~" & pe$lhs != "f"], pe$se[pe$op == "~~" & pe$lhs == "f"])
  for (q in seq_along(se)) cases[[length(cases) + 1]] <- case("cfa_se", c(n, p, as.vector(t(S)), q - 1), se[q], rel = 1e-3, abs = 1e-6)
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("cfa", c(n, p, as.vector(t(S)), q - 1), v[q], rel = 1e-4, abs = 1e-6)
}
# two or three correlated factors of simple structure: "cfmf" args (n, p, nf, fac[p] 0-based, S[p*p] row-major, q) q: loadings (p, fixed first ones 1), residual variances (p), factor (co)variances lower triangle row-major, chi-square, df, p value
for (rep in 1:6) {
  nf <- sample(2:3, 1); per <- sample(3:4, nf, TRUE); p <- sum(per); fac <- rep(0:(nf - 1), per); n <- sample(200:500, 1)
  Ph <- diag(nf); Ph[lower.tri(Ph)] <- runif(nf * (nf - 1) / 2, 0.2, 0.6); Ph[upper.tri(Ph)] <- t(Ph)[upper.tri(Ph)]
  Fm <- matrix(rnorm(n * nf), n, nf) %*% chol(Ph); X <- sapply(1:p, function(j) 0.8 * runif(1, 0.7, 1.2) * Fm[, fac[j] + 1] + rnorm(n, 0, 0.6)); colnames(X) <- paste0("x", 1:p)
  mod <- paste(sapply(1:nf, function(g) paste0("f", g, " =~ ", paste(colnames(X)[fac == g - 1], collapse = " + "))), collapse = "\n")
  fit <- tryCatch(suppressWarnings(cfa(mod, as.data.frame(X))), error = function(e) NULL)
  if (is.null(fit) || !lavInspect(fit, "converged")) next
  pe <- parameterEstimates(fit); ld <- numeric(p); for (j in 1:p) ld[j] <- if (j == which(fac == fac[j])[1]) 1 else pe$est[pe$op == "=~" & pe$rhs == colnames(X)[j]]
  th <- sapply(1:p, function(j) pe$est[pe$op == "~~" & pe$lhs == colnames(X)[j] & pe$rhs == colnames(X)[j]])
  phv <- c(); for (u in 1:nf) for (v in 1:u) phv <- c(phv, pe$est[pe$op == "~~" & ((pe$lhs == paste0("f", u) & pe$rhs == paste0("f", v)) | (pe$lhs == paste0("f", v) & pe$rhs == paste0("f", u)))][1])
  fm <- fitMeasures(fit, c("chisq", "df", "pvalue")); v <- c(ld, th, phv, as.numeric(fm)); S <- cov(X)
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("cfmf", c(n, p, nf, fac, as.vector(t(S)), q - 1), v[q], rel = 2e-4, abs = 1e-6)
}
emit("lavaan_cfa", "lavaan", list(cases))
