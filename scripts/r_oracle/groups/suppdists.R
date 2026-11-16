# SuppDists: inverse Gaussian d/p/q, Kendall d/p, Spearman d/p (exact, small N), Johnson SN, SL, SB, SU d/p/q.
#   args: (kind, a, b, c, d, e, x)  see each fn
#   "ig_d" "ig_p" "ig_q": (nu, lambda, x)   "ken_d" "ken_p": (N, tau)   "sp_d" "sp_p": (N, rho)   "jo_d" "jo_p" "jo_q": (type 0 SN 1 SL 2 SB 3 SU, gamma, delta, xi, lambda, x)
suppressMessages(library(SuppDists))
cases <- list()
add <- function(fn, args, want, tol = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-12)
set.seed(20261116)
for (rep in 1:25) {
  nu <- round(runif(1, 0.5, 4), 2); la <- round(runif(1, 0.5, 6), 2); x <- round(runif(1, 0.2, 4), 2); pr <- round(runif(1, 0.05, 0.95), 3)
  add("ig_d", c(nu, la, x), dinvGauss(x, nu, la)); add("ig_p", c(nu, la, x), pinvGauss(x, nu, la)); add("ig_q", c(nu, la, pr), qinvGauss(pr, nu, la), 1e-7)
}
for (N in 3:9) for (tau in seq(-1, 1, by = 0.13)) { add("ken_d", c(N, tau), dKendall(tau, N)); add("ken_p", c(N, tau), pKendall(tau, N)) }
for (N in 3:9) for (rep in 1:12) { rho <- cor(1:N, sample(N)); if (rho < 1) { add("sp_d", c(N, rho), dSpearman(rho, N)); add("sp_p", c(N, rho), pSpearman(rho, N)) } }
tn <- c("SN", "SL", "SB", "SU")
for (rep in 1:20) {
  ty <- sample(0:3, 1); g <- round(rnorm(1), 2); de <- round(runif(1, 0.6, 2), 2); xi <- round(runif(1, -1, 1), 2); la <- if (ty == 1) 1 else round(runif(1, 0.8, 3), 2)
  pr <- list(gamma = g, delta = de, xi = xi, lambda = la, type = tn[ty + 1])
  x <- if (ty == 2) xi + la * runif(1, 0.05, 0.95) else xi + la * runif(1, 0.1, 2); p <- round(runif(1, 0.05, 0.95), 3)
  a <- c(ty, g, de, xi, la)
  add("jo_d", c(a, x), dJohnson(x, pr)); add("jo_p", c(a, x), pJohnson(x, pr)); add("jo_q", c(a, p), qJohnson(p, pr), 1e-8)
}
# ghyper: "gh_d" "gh_p" "gh_q" args (a, k, N, x)
for (rep in 1:10) { N <- sample(10:40, 1); a <- sample(2:(N - 2), 1); k <- sample(2:(N - 2), 1); for (xx in seq(max(0, k + a - N), min(a, k))) { add("gh_d", c(a, k, N, xx), dghyper(xx, a, k, N)); add("gh_p", c(a, k, N, xx), pghyper(xx, a, k, N)) }
  for (pr in c(0.1, 0.5, 0.9)) add("gh_q", c(a, k, N, pr), qghyper(pr, a, k, N)) }
# Pearson correlation: "pc_d" "pc_p" "pc_q": args (rho, N, x or p)
for (rep in 1:40) {
  N <- sample(5:60, 1); rho <- round(runif(1, -0.9, 0.9), 2); r <- round(runif(1, -0.95, 0.95), 3); pr <- round(runif(1, 0.05, 0.95), 3)
  add("pc_d", c(rho, N, r), dPearson(r, N, rho)); add("pc_p", c(rho, N, r), pPearson(r, N, rho), 1e-7); add("pc_q", c(rho, N, pr), qPearson(pr, N, rho), 1e-6)
}
# Kruskal-Wallis (ns 0) and normal scores (ns 1): "kw_p" "kw_u" "kw_q" "kw_d", args (ns, c, N, U, x or p)
for (rep in 1:40) {
  ns <- rep %% 2; cc <- sample(3:6, 1); ni <- sample(4:15, cc, TRUE); N <- sum(ni); U <- sum(1 / ni)
  h <- round(runif(1, 0.3, 9), 2); pr <- round(runif(1, 0.05, 0.95), 3)
  P <- if (ns == 0) pKruskalWallis else pNormScore; Q <- if (ns == 0) qKruskalWallis else qNormScore; D <- if (ns == 0) dKruskalWallis else dNormScore
  add("kw_p", c(ns, cc, N, U, h), P(h, cc, N, U), 1e-8); add("kw_u", c(ns, cc, N, U, h), P(h, cc, N, U, lower.tail = FALSE), 1e-8)
  add("kw_q", c(ns, cc, N, U, pr), Q(pr, cc, N, U), 1e-8); add("kw_d", c(ns, cc, N, U, h), D(h, cc, N, U), 1e-6)
}
emit("suppdists", "SuppDists", list(cases))
