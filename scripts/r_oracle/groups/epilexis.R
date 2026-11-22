# Epi: Lexis tools. splitLexis (two time scales, per then age), cutLexis (numeric states, precursor states, progressive, the new time scale), and the
# Poisson rate model on the person-years cells of a split Lexis object with ci.lin.
#   data block: n, then n rows of (per entry, age entry, lex.dur, lex.Cst, lex.Xst, lex.id); time scales per (index 0) and age (index 1)
#   "split"  args (n, data, kind, idx, s1, nb1, brk1, s2, nb2, brk2)  kind 0 row count, 1 entry idx = row * 6 + col of (id, per, age, dur, cst, xst), 2 column sum col idx
#   "cut"    args (n, data, kind, idx, scale, newscale, progressive, nprec, prec, cut[n], new.state[n]) nprec -1 is the default transient(data); kind as split, with a 7th column
#            lex.new.scale (kind 1 only asked of the rows where it is not NA)
#   "rate"   args (n, data, nA, brkA, nP, brkP, kind, r, c, nctr, ctr)  kind 0 cell r person-years, 1 cell r events, 2 ci.lin(fit, Exp = TRUE)[r + 1, c + 1] (7 columns: est, se, z, P, exp(est), exp lo, exp hi), 3 the same for ctr.mat = ctr
suppressMessages(library(Epi))
cases <- list()
mk <- function(n) {
  cst <- sample(1:2, n, TRUE)
  xst <- cst + sample(c(0, 0, 1, 2), n, TRUE)
  data.frame(per = round(runif(n, 2000, 2010), 2), age = round(runif(n, 60, 80), 2), dur = round(runif(n, 0.3, 14), 2), cst = cst, xst = xst, id = sample(1:(n + 3), n, TRUE))
}
mkL <- function(d) Lexis(entry = list(per = d$per, age = d$age), duration = d$dur, id = d$id, entry.status = d$cst, exit.status = d$xst)
blk <- function(d) as.vector(t(as.matrix(d[, c("per", "age", "dur", "cst", "xst", "id")])))
flat <- function(x, cols) as.matrix(x[, cols])
rel <- 1e-12
set.seed(20261501)
for (rep in 1:22) {
  n <- sample(3:8, 1); d <- mk(n); L <- mkL(d)
  nb1 <- sample(1:4, 1); s1 <- sample(0:1, 1)
  rg <- if (s1 == 0) c(2000, 2024) else c(60, 94)
  brk1 <- round(sort(runif(nb1, rg[1] + 1, rg[2] - 1)), 1)
  s2 <- 1 - s1; nb2 <- sample(0:3, 1)
  rg2 <- if (s2 == 0) c(2000, 2024) else c(60, 94)
  brk2 <- if (nb2 > 0) round(sort(runif(nb2, rg2[1] + 1, rg2[2] - 1)), 1) else numeric(0)
  X <- splitLexis(L, brk1, c("per", "age")[s1 + 1])
  if (nb2 > 0) X <- splitLexis(X, brk2, c("per", "age")[s2 + 1])
  M <- as.matrix(as.data.frame(X)[, c("lex.id", "per", "age", "lex.dur", "lex.Cst", "lex.Xst")])
  base <- c(n, blk(d))
  tail <- c(s1, nb1, brk1, s2, nb2, brk2)
  cases[[length(cases) + 1]] <- case("split", c(base, 0, 0, tail), nrow(M), rel = 0)
  for (col in 1:6) cases[[length(cases) + 1]] <- case("split", c(base, 2, col - 1, tail), sum(M[, col]), rel = 1e-12, abs = 1e-12)
  for (k in 1:min(10, nrow(M) * 6)) {
    r <- sample(nrow(M), 1); col <- sample(6, 1)
    cases[[length(cases) + 1]] <- case("split", c(base, 1, (r - 1) * 6 + col - 1, tail), M[r, col], rel = rel, abs = 1e-12)
  }
}
set.seed(20261502)
for (rep in 1:30) {
  n <- sample(3:8, 1); d <- mk(n); L <- mkL(d)
  sc <- sample(0:1, 1); scn <- c("per", "age")[sc + 1]
  ex <- L[[scn]] + L$lex.dur
  cut <- round(L[[scn]] + runif(n, -3, 1.3) * L$lex.dur, 2)
  ns <- sample(2:4, n, TRUE)
  prog <- sample(0:1, 1); newsc <- sample(0:1, 1)
  np <- sample(c(-1, 0, 1, 2), 1)
  prec <- if (np > 0) sort(sample(1:3, np)) else numeric(0)
  if (prog == 1) { d$xst <- pmax(d$xst, d$cst); L <- mkL(d) }
  r <- if (np < 0) cutLexis(L, cut, timescale = scn, new.state = ns, new.scale = as.logical(newsc), progressive = as.logical(prog))
       else cutLexis(L, cut, timescale = scn, new.state = ns, new.scale = as.logical(newsc), progressive = as.logical(prog), precursor.states = prec)
  X <- as.data.frame(r)
  cn <- c("lex.id", "per", "age", "lex.dur", "lex.Cst", "lex.Xst"); nsc <- names(X)[grep("^tf", names(X))]
  M <- as.matrix(X[, cn])
  base <- c(n, blk(d)); tail <- c(sc, newsc, prog, if (np < 0) -1 else np, prec, cut, ns)
  cases[[length(cases) + 1]] <- case("cut", c(base, 0, 0, tail), nrow(M), rel = 0)
  for (col in 1:6) cases[[length(cases) + 1]] <- case("cut", c(base, 2, col - 1, tail), sum(M[, col]), rel = 1e-12, abs = 1e-12)
  if (newsc == 1) {
    v <- X[[nsc]]; ok <- which(!is.na(v))
    cases[[length(cases) + 1]] <- case("cut", c(base, 3, 0, tail), sum(v[ok]), rel = 1e-12, abs = 1e-12)
    for (r0 in head(ok, 3)) cases[[length(cases) + 1]] <- case("cut", c(base, 1, (r0 - 1) * 7 + 6, tail), v[r0], rel = rel, abs = 1e-12)
  }
  for (k in 1:min(10, nrow(M) * 6)) {
    r0 <- sample(nrow(M), 1); col <- sample(6, 1)
    cases[[length(cases) + 1]] <- case("cut", c(base, 1, (r0 - 1) * 7 + col - 1, tail), M[r0, col], rel = rel, abs = 1e-12)
  }
}
set.seed(20261503)
got <- 0
while (got < 7) {
  n <- sample(25:45, 1); d <- mk(n); d$cst <- 1; d$xst <- sample(c(1, 2, 3), n, TRUE, prob = c(0.3, 0.5, 0.2))
  L <- mkL(d)
  nA <- sample(2:4, 1); nP <- sample(1:2, 1)
  brkA <- c(60, sort(round(runif(nA - 1, 63, 85), 1))); brkP <- c(2000, if (nP > 1) round(runif(nP - 1, 2002, 2012), 1) else NULL)
  X <- splitLexis(splitLexis(L, brkA, "age"), brkP, "per")
  X$A <- findInterval(X$age, brkA); X$P <- findInterval(X$per, brkP)
  stopifnot(all(timeBand(X, "age", "integer") == X$A), all(timeBand(X, "per", "integer") == X$P))
  X$D <- as.numeric(X$lex.Xst == 2)
  ce <- aggregate(cbind(Y = X$lex.dur, D = X$D) ~ A + P, data = as.data.frame(X), FUN = sum)
  if (length(unique(ce$A)) < 2 || nrow(ce) < 4) next
  fit <- try(suppressWarnings(glm(D ~ factor(A) + factor(P) + offset(log(Y)), family = poisson, data = ce)), silent = TRUE)
  if (inherits(fit, "try-error") || !fit$converged || any(is.na(coef(fit))) || fit$iter > 12) next
  if (length(coef(fit)) >= nrow(ce)) next
  got <- got + 1
  tb <- ci.lin(fit, Exp = TRUE); p <- nrow(tb)
  ctr <- sample(c(-1, 0, 0, 1, 2), p, TRUE); if (all(ctr == 0)) ctr[1] <- 1
  ct <- ci.lin(fit, ctr.mat = matrix(ctr, 1), Exp = TRUE)
  base <- c(n, blk(d), nA, brkA, nP, brkP)
  for (k in seq_len(nrow(ce))) {
    cases[[length(cases) + 1]] <- case("rate", c(base, 0, k - 1, 0, 0), ce$Y[k], rel = 1e-12, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("rate", c(base, 1, k - 1, 0, 0), ce$D[k], rel = 0)
  }
  for (r in sort(sample(p, min(p, 4)))) for (cc in 1:7) {
    if (is.nan(tb[r, cc]) || is.infinite(tb[r, cc])) next
    cases[[length(cases) + 1]] <- case("rate", c(base, 2, r - 1, cc - 1, 0), tb[r, cc], rel = 1e-9, abs = 1e-12)
  }
  for (cc in 1:7) cases[[length(cases) + 1]] <- case("rate", c(base, 3, 0, cc - 1, p, ctr), ct[1, cc], rel = 1e-9, abs = 1e-12)
}
emit("epilexis", "Epi", list(cases))
