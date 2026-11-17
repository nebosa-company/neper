# lmom: samlmu, lmr, qua and pel for exp, gum, glo, gpa, nor (and gev lmr/qua).
#   samlmu: (nmom, n, x[n], q) fn "sam" q = 0..nmom-1 the ratio-form L-moments
#   lmr: (kind, xi, alpha, k, q) fn "lmr" q 0..3;  qua: (kind, xi, alpha, k, f) fn "qua";  pel: (kind, l1, l2, t3, q) fn "pel" q 0..2 (xi, alpha, k)
suppressMessages(library(lmom))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20261116)
nm <- c("exp", "gum", "glo", "gpa", "nor", "gev")
for (rep in 1:25) {
  n <- sample(10:120, 1); x <- round(rexp(n) * 3 + rnorm(n), 3); nmom <- sample(3:5, 1)
  s <- samlmu(x, nmom)
  for (q in seq_len(nmom)) add("sam", c(nmom, n, x, q - 1), s[q])
}
for (kind in 0:5) for (rep in 1:8) {
  xi <- round(rnorm(1), 2); al <- round(runif(1, 0.5, 3), 2); k <- if (kind %in% c(0, 1, 4)) 0 else round(runif(1, 0.05, 0.4) * c(1, -1)[rep %% 2 + 1], 3)
  par <- switch(kind + 1, c(xi, al), c(xi, al), c(xi, al, k), c(xi, al, k), c(xi, al), c(xi, al, k))
  lm <- get(paste0("lmr", nm[kind + 1]))(par, 4)
  for (q in 1:4) add("lmr", c(kind, xi, al, k, q - 1), lm[q])
  for (xx in xi + al * c(-1.5, -0.3, 0.2, 0.9, 2.5, 6)) add("cdf", c(kind, xi, al, k, xx), get(paste0("cdf", nm[kind + 1]))(xx, par))
  for (f in c(0.05, 0.3, 0.5, 0.9, 0.99)) add("qua", c(kind, xi, al, k, f), get(paste0("qua", nm[kind + 1]))(f, par))
  if (kind <= 4) { pp <- get(paste0("pel", nm[kind + 1]))(lm[1:(if (kind <= 1 || kind == 4) 2 else 3)]); full <- c(pp, rep(0, 3 - length(pp)))
    for (q in 1:3) add("pel", c(kind, lm[1], lm[2], lm[3], q - 1), full[q]) }
}
emit("lmom", "lmom", list(cases))
