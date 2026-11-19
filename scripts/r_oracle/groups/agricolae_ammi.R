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
emit("agricolae_ammi", "agricolae", list(cases))
