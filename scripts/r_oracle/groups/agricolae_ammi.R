# agricolae::AMMI on a complete genotype by environment table of means with REP = 3 and a given error mean square.
#   args: (ngen, nenv, nrep, mse, what, idx, y[ngen nenv] genotype-major); what 0 percent[idx], 1 acum, 2 Df, 3 Sum Sq, 4 Mean Sq, 5 F value, 6 Pr(F),
#   7 genotype score at idx (genotype * m + axis), 8 environment score at idx (env * m + axis), 9 the genotype mean, 10 the environment mean, 11 the number of table rows
suppressMessages(library(agricolae))
cases <- list()
set.seed(20262001)
add <- function(args, want, rel = 1e-8, abs = 1e-9) cases[[length(cases) + 1]] <<- case("am", args, want, rel = rel, abs = abs)
for (rep in 1:8) {
  ng <- sample(4:7, 1); ne <- sample(4:6, 1); nrp <- 3; mse <- round(runif(1, 0.2, 1.5), 3)
  gen <- 1:ng; env <- 1:ne
  mu <- outer(rnorm(ng, 0, 1.5), rnorm(ne, 0, 1.5), "+") + outer(rnorm(ng), rnorm(ne))
  y <- mu + matrix(rnorm(ng * ne, 0, 0.3), ng, ne)
  d <- data.frame(ENV = factor(rep(paste0("E", env), each = ng)), GEN = factor(rep(paste0("G", gen), ne)), Y = as.vector(y))
  r <- AMMI(d$ENV, d$GEN, nrp, d$Y, MSE = mse)
  a <- r$analysis; m <- min(ng, ne); nss <- nrow(a)
  hdr <- function(w, i) c(ng, ne, nrp, mse, w, i, as.vector(t(y)))
  add(hdr(11, 0), nss, 0, 0)
  for (i in seq_len(nss)) {
    add(hdr(0, i - 1), a$percent[i]); add(hdr(1, i - 1), a$acum[i]); add(hdr(2, i - 1), a$Df[i]); add(hdr(3, i - 1), a$Sum.Sq[i])
    add(hdr(4, i - 1), a$Mean.Sq[i]); add(hdr(5, i - 1), a$F.value[i]); add(hdr(6, i - 1), a$Pr.F[i], abs = 1e-4 + 1e-9)
  }
  b <- r$biplot
  for (gi in seq_len(ng)) { add(hdr(9, gi - 1), b[[2]][gi]); for (c in seq_len(nss)) add(hdr(7, (gi - 1) * m + c - 1), b[gi, 2 + c]) }
  for (ei in seq_len(ne)) { add(hdr(10, ei - 1), b[[2]][ng + ei]); for (c in seq_len(nss)) add(hdr(8, (ei - 1) * m + c - 1), b[ng + ei, 2 + c]) }
}
# stability.nonpar: fn "sn" args (k, n, what, idx, y[k n] genotype-major); what 0 Mean, 1 Rank, 2 s1, 3 Z1, 4 s2, 5 Z2 (idx a genotype), 6 es1, 7 es2, 8 vs1, 9 vs2, 10 chi.ind, 11 chi.sum, 12 sum Z1, 13 sum Z2
for (rep in 1:8) {
  k <- sample(4:9, 1); n <- sample(4:8, 1)
  y <- outer(rnorm(k, 5, 1.5), rep(1, n)) + matrix(rnorm(k * n, 0, 1), k, n) + outer(rep(1, k), rnorm(n))
  if (rep %% 3 == 0) y <- round(y)
  d <- data.frame(G = paste0("G", seq_len(k)), y); colnames(d)[-1] <- paste0("E", seq_len(n))
  r <- stability.nonpar(d)
  st <- r$ranking; sx <- r$statistics
  addn <- function(w, i, v) cases[[length(cases) + 1]] <<- case("sn", c(k, n, w, i, as.vector(t(y))), v, rel = 1e-9, abs = 1e-10)
  for (i in seq_len(k)) for (w in 0:5) addn(w, i - 1, st[i, w + 1])
  addn(6, 0, sx$es1); addn(7, 0, sx$es2); addn(8, 0, sx$vs1); addn(9, 0, sx$vs2); addn(10, 0, sx$chi.ind); addn(11, 0, sx$chi.sum)
  addn(12, 0, sum(st$Z1)); addn(13, 0, sum(st$Z2))
}
# stability.par without a covariate: fn "sp" args (A, M, rep, mse, alpha, what, idx, y[A M] genotype-major); what 0 Df (the 7 rows), 1 Sum Sq (rows 1 to 6), 2 Mean Sq (rows 2 to 7 as idx 0 to 5), 3 F value (rows 2 to 6 as idx 0 to 4), then per genotype idx:
# 10 Mean, 11 Sigma-square, 12 its signif. code, 13 s-square, 14 its code, 15 Ecovalence, 16 Rank, 17 Adj.rank, 18 Adjusted, 19 Stab.rating, 20 YSi, 21 selected
for (rep in 1:8) {
  A <- sample(4:8, 1); M <- sample(4:7, 1); nrp <- sample(3:4, 1); mse <- round(runif(1, 0.1, 0.8), 3); alp <- c(0.1, 0.05)[rep %% 2 + 1]
  y <- outer(rnorm(A, 8, 1.2), rep(1, M)) + outer(rep(1, A), rnorm(M)) + matrix(rnorm(A * M, 0, 0.6), A, M)
  d <- as.data.frame(y); rownames(d) <- paste0("G", seq_len(A)); colnames(d) <- paste0("E", seq_len(M))
  r <- stability.par(d, nrp, mse, alpha = alp, main = "t")
  code <- function(x) c("ns" = 0, "*" = 1, "**" = 2)[as.character(x)]
  hdr <- function(w, i) c(A, M, nrp, mse, alp, w, i, as.vector(t(y)))
  adds <- function(w, i, v, rel = 1e-8, abs = 1e-8) if (is.finite(v)) cases[[length(cases) + 1]] <<- case("sp", hdr(w, i), v, rel = rel, abs = abs)
  an <- r$analysis; num <- function(z) suppressWarnings(as.numeric(as.character(z)))
  for (i in 1:7) adds(0, i - 1, an[i, 1])
  for (i in 1:6) adds(1, i - 1, num(an[i, 2]), abs = 1e-3)
  for (i in 2:7) adds(2, i - 2, num(an[i, 3]), abs = 1e-3)
  for (i in 2:6) adds(3, i - 2, num(an[i, 4]), abs = 0.011)
  st <- r$statistics; sb <- r$stability
  for (i in seq_len(A)) {
    adds(10, i - 1, st[i, 1], abs = 1e-6); adds(11, i - 1, st[i, 2], abs = 1e-6); adds(12, i - 1, code(st[i, 3]), 0, 0)
    adds(13, i - 1, st[i, 4], abs = 1e-6); adds(14, i - 1, code(st[i, 5]), 0, 0); adds(15, i - 1, st[i, 6], abs = 1e-6)
    adds(16, i - 1, sb[i, 2], 0, 0); adds(17, i - 1, sb[i, 3], 0, 0); adds(18, i - 1, sb[i, 4], 0, 0); adds(19, i - 1, sb[i, 6], 0, 0)
    adds(20, i - 1, sb[i, 7], 0, 0); adds(21, i - 1, as.numeric(as.character(sb[i, 8]) == "+"), 0, 0)
  }
}
emit("agricolae_ammi", "agricolae", list(cases))
