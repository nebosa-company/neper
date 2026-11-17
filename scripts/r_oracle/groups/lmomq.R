# lmomq: lmrq, the L-moments of a quantile function by quadrature, plain and trimmed, ratios or not.
#   "lmrq" (kind, np, para.., symm, maxord, ratios, t1, t2, acc, q) q = 0 .. maxord-1.  kind as in the lmomfull group: 0 exp 2 gev 3 glo 4 gno 5 gpa 6 gum 8 ln3 9 nor 10 pe3 13 wei
suppressMessages(library(lmom))
cases <- list()
nms <- c("exp", "gam", "gev", "glo", "gno", "gpa", "gum", "kap", "ln3", "nor", "pe3", "wak", "wa0", "wei")
add <- function(args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("lmrq", args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261123)
for (kind in c(0, 2, 3, 4, 5, 6, 8, 9, 10, 13)) for (rep in 1:5) {
  xi <- round(rnorm(1), 2); al <- round(runif(1, 0.5, 3), 2); k <- round(sample(c(-1, 1), 1) * runif(1, 0.05, 0.4), 3)
  par <- switch(match(kind, c(0, 2, 3, 4, 5, 6, 8, 9, 10, 13)), c(xi, al), c(xi, al, k), c(xi, al, k), c(xi, al, k), c(xi, al, k), c(xi, al), c(xi, round(rnorm(1), 2), round(runif(1, 0.2, 0.8), 2)), c(xi, al),
    c(xi, al, round(runif(1, 0.3, 2), 2) * c(1, -1)[1 + rep %% 2]), c(xi, al, round(runif(1, 0.5, 3), 2)))
  tr <- list(c(0, 0), c(1, 1), c(1, 0), c(0, 2), c(0, 0))[[rep]]; ra <- rep %% 2 == 1; maxord <- sample(3:7, 1)
  f <- tryCatch(suppressWarnings(lmrq(get(paste0("qua", nms[kind + 1])), par, order = 1:maxord, ratios = ra, trim = tr)), error = function(e) NULL); if (is.null(f)) next
  for (q in seq_len(maxord)) add(c(kind, length(par), par, 0, maxord, as.integer(ra), tr, 1e-6, q - 1), f[q])
}
for (rep in 1:4) {
  mu <- round(rnorm(1), 2); sg <- round(runif(1, 0.5, 3), 2); maxord <- 6; tr <- list(c(0, 0), c(1, 1), c(2, 2), c(0, 0))[[rep]]; ra <- rep %% 2 == 0
  f <- suppressWarnings(lmrq(quanor, c(mu, sg), symm = TRUE, order = 1:maxord, ratios = ra, trim = tr))
  for (q in seq_len(maxord)) add(c(9, 2, mu, sg, 1, maxord, as.integer(ra), tr, 1e-6, q - 1), f[q])
}
emit("lmomq", "lmom", list(cases))
