# gamlssdist: gamlss.dist densities of GU, LO, GA, IG, BCCG, PE and p, q of GU and LO.
#   args: (x or p, mu, sigma, nu) for the family named by fn: dGU dLO dGA dIG dBCCG dPE pLO qGU qLO. pGU is not tested: this version of gamlss.dist sets every pGU value to 0 (cdf[q >= -Inf] <- 0).
suppressMessages(library(gamlss.dist))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
set.seed(20262010)
for (rep in 1:30) {
  mu <- runif(1, 0.5, 3); sg <- runif(1, 0.2, 1.5); nu <- runif(1, 0.3, 3) * sample(c(-1, 1), 1)
  for (x in runif(4, 0.05, 6)) {
    add("dGU", c(x, mu, sg, 0), dGU(x, mu, sg)); add("dLO", c(x, mu, sg, 0), dLO(x, mu, sg)); add("dGA", c(x, mu, sg, 0), dGA(x, mu, sg)); add("dIG", c(x, mu, sg, 0), dIG(x, mu, sg))
    add("dBCCG", c(x, mu, sg, nu), dBCCG(x, mu, sg, nu)); add("dPE", c(x, mu, sg, abs(nu)), dPE(x, mu, sg, abs(nu)))
    add("pLO", c(x, mu, sg, 0), pLO(x, mu, sg))
  }
  for (p in runif(3, 0.02, 0.98)) { add("qGU", c(p, mu, sg, 0), qGU(p, mu, sg)); add("qLO", c(p, mu, sg, 0), qLO(p, mu, sg)) }
}
for (rep in 1:30) {
  mu <- runif(1, 0.5, 3); sg <- runif(1, 0.2, 1.5); nu <- runif(1, 0.3, 2.5) * sample(c(-1, 1), 1); tau <- runif(1, 0.5, 3); df <- runif(1, 2, 20)
  for (x in runif(4, 0.05, 6)) {
    add("dWEI", c(x, mu, sg, 0, 0), dWEI(x, mu, sg)); add("dLOGNO", c(x, mu, sg, 0, 0), dLOGNO(x, mu, sg))
    add("dJSU", c(x, mu, sg, nu, tau), dJSU(x, mu, sg, nu, tau)); add("dSHASH", c(x, mu, sg, abs(nu), tau), dSHASH(x, mu, sg, abs(nu), tau))
    add("dBCT", c(x, mu, sg, nu, df), dBCT(x, mu, sg, nu, df))
  }
  for (k in sample(0:12, 4)) { add("dNBI", c(k, mu * 3, sg, 0, 0), dNBI(k, mu * 3, sg)); add("dZIP", c(k, mu * 3, min(sg, 0.9) / 2, 0, 0), dZIP(k, mu * 3, min(sg, 0.9) / 2)) }
}
emit("gamlssdist", "gamlss.dist", list(cases))
