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
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("cfa", c(n, p, as.vector(t(S)), q - 1), v[q], rel = 1e-4, abs = 1e-6)
}
emit("lavaan_cfa", "lavaan", list(cases))
