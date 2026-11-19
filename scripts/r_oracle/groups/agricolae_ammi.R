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
emit("agricolae_ammi", "agricolae", list(cases))
