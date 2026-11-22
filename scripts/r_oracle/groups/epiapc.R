# Epi: apc.fit with model = "factor", "ns" (npar knots on the quantiles of the cases), "bs" and "ls" (npar = df), the Poisson distribution, all eight parametrizations.
#   "apc" args (n, A[n], P[n], D[n], Y[n], parm, drmode, drk, hasp, refp, hasc, refc, alpha, scale, model, nka, nkp, nkc, kind, i, j)   model 0 factor, 1 ns, 2 bs, 3 ls (npar = df)
#   parm 0..7 = ACP, APC, AdCP, AdPC, Ad-P-C, Ad-C-P, AC-P, AP-C; drmode 0 "1", 1 "D", 2 "R" (Y^2/D), 3 "Y", 4 numeric k = drk
#   kind 0/1/2 Age/Per/Coh table entry (row i, column j of value, estimate, lower, upper), 3 drift (row i, column j of estimate, lower, upper),
#   4 model table (row i, column j of residual df, residual deviance, AIC, test df, test deviance), 5/6/7 column j sum of Age/Per/Coh, 8 column j sum of the model table, 9 Ref (j 0 period, 1 cohort)
suppressMessages(library(Epi))
cases <- list()
pn <- c("ACP", "APC", "AdCP", "AdPC", "Ad-P-C", "Ad-C-P", "AC-P", "AP-C")
set.seed(20261701)
sm <- function(x) sum(x)
reps <- c(0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7, 1, 4, 3, 0, 0, 1, 2, 3, 4, 5, 6, 7, 3, 1, 0, 1, 2, 3, 4, 5, 6, 7)
mods <- c(rep(0, 20), rep(1, 10), rep(2, 4), rep(3, 4))
for (rep in seq_along(reps)) {
  parm <- reps[rep]
  model <- mods[rep]
  na <- if (model >= 1) 7 else sample(5:7, 1); np <- if (model >= 1) 5 else sample(4:5, 1); half <- sample(c(0, 2.5), 1)
  g <- expand.grid(A = 40 + half + 5 * (seq_len(na) - 1), P = 1960 + 5 * (seq_len(np) - 1))
  ra <- runif(na, -6, -4); rp <- rnorm(np, 0, 0.15)
  Y <- round(runif(nrow(g), 600, 6000)); D <- 1 + rpois(nrow(g), Y * exp(ra[match(g$A, unique(g$A))] + rp[match(g$P, unique(g$P))]) * 3)
  drmode <- sample(0:4, 1); drk <- round(runif(1, 0.001, 0.05), 3)
  dre <- switch(drmode + 1, "1", "D", "R", "Y", drk)
  hasp <- sample(0:1, 1); hasc <- sample(0:1, 1); refp <- sample(unique(g$P), 1) + sample(c(0, 2), 1); refc <- sample(unique(g$P - g$A), 1)
  alpha <- sample(c(0.05, 0.1), 1); sc <- sample(c(1, 1000), 1)
  dat <- data.frame(A = g$A, P = g$P, D = D, Y = Y)
  nk <- if (model == 1) sample(4:5, 3, TRUE) else if (model == 2) sample(5:6, 3, TRUE) else if (model == 3) sample(5:7, 3, TRUE) else c(5, 5, 5)
  if (model >= 2) nk[2] <- 5
  call <- list(data = dat, model = c("factor", "ns", "bs", "ls")[model + 1], npar = c(A = nk[1], P = nk[2], C = nk[3]), parm = pn[parm + 1], dr.extr = dre, alpha = alpha, scale = sc, print.AOV = FALSE)
  if (hasp) call$ref.p <- refp
  if (hasc) call$ref.c <- refc
  r <- suppressMessages(capture.output(res <- do.call(apc.fit, call)))
  base <- c(nrow(g), g$A, g$P, D, Y, parm, drmode, drk, hasp, refp, hasc, refc, alpha, sc, model, nk)
  add <- function(kind, i, j, v, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case("apc", c(base, kind, i, j), v, rel = rel, abs = abs)
  tabs <- list(res$Age, res$Per, res$Coh)
  for (t in 1:3) {
    tb <- as.matrix(tabs[[t]])
    for (j in 1:4) add(4 + t, 0, j - 1, sum(tb[, j]))
    for (k in 1:2) { i <- sample(nrow(tb), 1); j <- sample(4, 1); add(t - 1, i - 1, j - 1, tb[i, j]) }
  }
  dr <- as.matrix(res$Drift)
  for (i in 1:nrow(dr)) for (j in 1:3) add(3, i - 1, j - 1, dr[i, j])
  ao <- res$Anova
  an <- cbind(as.numeric(ao[["Mod. df."]]), as.numeric(ao[["Mod. dev."]]), as.numeric(ao$AIC), as.numeric(ao[["Test df."]]), as.numeric(ao[["Test dev."]]))
  for (j in 1:3) for (i in 1:6) add(4, i - 1, j - 1, an[i, j])
  add(8, 0, 3, sum(an[-1, 4])); add(8, 0, 4, sum(an[-1, 5]))
  rf <- res$Ref
  if (!is.na(rf["Per"])) add(9, 0, 0, rf["Per"]); if (!is.na(rf["Coh"])) add(9, 0, 1, rf["Coh"])
}
emit("epiapc", "Epi", list(cases))
