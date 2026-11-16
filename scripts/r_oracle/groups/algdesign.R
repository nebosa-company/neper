# AlgDesign: gen.factorial and eval.design on a model matrix.
#   gen: (nf, levels[nf], center, q)  fn "gen_sum" "gen_w": sum and position-weighted sum (row-major) of the grid
#   eval: (n, k, nc, X[n*k], C[nc*k], q) fn "ev": q 0 determinant 1 A 2 I 3 Geff 4 Deffbound 5 diagonality 6 gmean.variances
suppressMessages(library(AlgDesign))
cases <- list()
add <- function(fn, args, want, tol = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = tol)
set.seed(20261116)
for (rep in 1:30) {
  nf <- sample(1:3, 1); lv <- sample(2:5, nf, TRUE); ce <- rbinom(1, 1, 0.5)
  g <- if (nf == 1) gen.factorial(lv, nVars = 1, center = ce == 1) else gen.factorial(lv, center = ce == 1)
  v <- as.vector(t(as.matrix(g)))
  add("gen_sum", c(nf, lv, ce, 0), sum(v)); add("gen_w", c(nf, lv, ce, 0), sum(seq_along(v) * v))
}
for (rep in 1:20) {
  cand <- gen.factorial(c(3, 3, 3), center = TRUE); dc <- data.frame(cand)
  n <- sample(8:20, 1); des <- dc[sort(sample(nrow(dc), n)), ]
  f <- if (rep %% 2 == 0) ~ X1 + X2 + X3 else ~ X1 + X2 + X3 + X1:X2
  X <- model.matrix(f, des); C <- model.matrix(f, dc)
  if (qr(crossprod(X))$rank < ncol(X)) next
  e <- eval.design(f, des, X = dc)
  k <- ncol(X); a <- c(nrow(X), k, nrow(C), as.vector(X), as.vector(C))
  vals <- c(e$determinant, e$A, e$I, e$Geff, e$Deffbound, e$diagonality, e$gmean.variances)
  for (q in seq_along(vals)) add("ev", c(a, q - 1), vals[q], if (q %in% c(4, 5, 6)) 2e-3 else 1e-9)
}
#   optFederov: fn "fed", args (seed, N, k, nTrials, crit 0 D 1 A 2 I, approximate, nullify, nRepeats, X[N * k] row-major, what): the design is
#   what 0 D, 1 A, 2 I (crit 2), 3 Ge, 4 + j the j-th sorted row number (exact designs)
cand_fed <- function(kind) {
  if (kind == 0) { g <- expand.grid(a = c(-1, 0, 1), b = c(-1, 0, 1)); cbind(1, g$a, g$b, g$a * g$b, g$a^2, g$b^2) }
  else if (kind == 1) { g <- expand.grid(a = c(-1, 0, 1), b = c(-1, 0, 1), c = c(-1, 0, 1)); cbind(1, g$a, g$b, g$c, g$a * g$b) }
  else { a <- round(runif(40, -1, 1), 3); b <- round(runif(40, -1, 1), 3); cbind(1, a, b, a * b, a^2) }
}
for (rep in 1:48) {
  X <- cand_fed(rep %% 3); N <- nrow(X); k <- ncol(X)
  df <- as.data.frame(X); colnames(df) <- paste0("c", 0:(k - 1)); frml <- as.formula(paste("~ -1 +", paste(colnames(df), collapse = "+")))
  crit <- c("D", "A", "I")[(rep - 1) %% 3 + 1]; cc <- (rep - 1) %% 3
  appr <- rep > 36; nul <- if (rep %% 4 == 0) 1 else 0; nrep <- sample(c(3, 5), 1)
  n <- if (appr) k + 5 else sample((k + 1):(min(N, 2 * k + 4)), 1)
  seed <- sample(1e6, 1); set.seed(seed)
  r <- tryCatch(suppressWarnings(optFederov(frml, df, nTrials = n, criterion = crit, approximate = appr, nullify = nul, nRepeats = nrep, evaluateI = FALSE)), error = function(e) NULL)
  if (is.null(r)) next
  # equal D to the last bit across repeats but different designs: which one is kept is decided by libm rounding in log(), so such cases are not a test
  if (!appr && nul == 0) {
    tie <- FALSE
    for (m in seq_len(nrep - 1)) {
      set.seed(seed); q <- suppressWarnings(optFederov(frml, df, nTrials = n, criterion = crit, nRepeats = m))
      if (abs(q[[if (cc == 2) "I" else if (cc == 1) "A" else "D"]] - r[[if (cc == 2) "I" else if (cc == 1) "A" else "D"]]) < 1e-12 && !identical(q$rows, r$rows)) tie <- TRUE
    }
    if (tie) next
  }
  a <- c(seed, N, k, n, cc, as.numeric(appr), nul, nrep, as.vector(t(X)))
  add("fed", c(a, 0), r$D, 1e-7); add("fed", c(a, 1), r$A, 1e-7); if (cc == 2) add("fed", c(a, 2), r$I, 1e-7)
  add("fed", c(a, 3), r$Ge, 7e-4)
  if (!appr) for (j in seq_along(r$rows)) add("fed", c(a, 3 + j), r$rows[j], 1e-9)
}
#   optMonteCarlo: fn "mc", args (seed, id, approx, crit, nTrials, nRepeats, nCand, nvar, mixsum, [lo, hi, center, nlevels, digits, mixflag] per variable, what)
#   id 0 ~ x1 + x2 + x1:x2, id 1 ~ x1 + x2 + x3, id 2 mixture ~ m1 + m2 + m3 + m1:m2 (no intercept); what 0 D, 1 A, 2 I, 3 Ge, 4 the number of design rows, 5 + i the design values row-major
mc_vars <- function(id) {
  if (id == 0) data.frame(name = c("x1", "x2"), low = c(-1, 0), high = c(1, 10), center = c(0, 5), nLevels = c(5, 4), round = c(2, 1), isFactor = c(0, 0))
  else if (id == 1) data.frame(name = c("x1", "x2", "x3"), low = c(-1, -2, 0), high = c(1, 2, 6), center = c(0, 0, 3), nLevels = c(3, 5, 4), round = c(2, 2, 1), isFactor = c(0, 0, 0))
  else data.frame(name = c("m1", "m2", "m3"), low = c(0, 0, 0), high = c(1, 1, 1), center = c(0, 0, 0), nLevels = c(5, 5, 5), round = c(2, 2, 2), isFactor = c(0, 0, 0), mix = c(1, 1, 1))
}
mc_frml <- function(id) if (id == 0) ~ x1 + x2 + x1:x2 else if (id == 1) ~ x1 + x2 + x3 else ~ m1 + m2 + m3 + m1:m2
for (rep in 1:36) {
  id <- (rep - 1) %% 3; crit <- c("D", "A", "I")[((rep - 1) %/% 3) %% 3 + 1]; cc <- ((rep - 1) %/% 3) %% 3
  appr <- rep > 27; nrep <- sample(2:4, 1); nt <- if (appr) 0 else sample(8:14, 1); nc <- sample(c(30, 50, 70), 1)
  vd <- mc_vars(id); seed <- sample(1e6, 1); set.seed(seed)
  r <- tryCatch(suppressWarnings(optMonteCarlo(mc_frml(id), vd, nTrials = if (appr) NULL else nt, approximate = appr, criterion = crit, nRepeats = nrep, nCand = nc)), error = function(e) NULL)
  if (is.null(r)) next
  nv <- nrow(vd); mixf <- if (ncol(vd) == 8) vd$mix else rep(0, nv)
  a <- c(seed, id, as.numeric(appr), cc, nt, nrep, nc, nv, 1, as.vector(rbind(vd$low, vd$high, vd$center, vd$nLevels, vd$round, mixf)))
  add("mc", c(a, 0), r$D, 1e-7); add("mc", c(a, 1), r$A, 1e-7); if (cc == 2) add("mc", c(a, 2), r$I, 1e-7)
  add("mc", c(a, 3), r$Ge, 7e-4); add("mc", c(a, 4), nrow(r$design), 1e-9)
  if (!appr) { dm <- as.matrix(r$design); for (j in seq_len(nrow(dm))) for (c2 in seq_len(nv)) add("mc", c(a, 4 + (j - 1) * nv + c2), dm[j, c2], 1e-9) }
}
emit("algdesign", "AlgDesign", list(cases))
