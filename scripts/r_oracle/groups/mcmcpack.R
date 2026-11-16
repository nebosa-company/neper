# MCMCpack density functions: dwish, diwish, dinvgamma, ddirichlet.
#   args: dwish/diwish: (p, v, W[p*p], S[p*p]); dinvgamma: (x, shape, scale); ddirichlet: (k, x[k], alpha[k])
#   fn "dwish" "diwish" "dinvgamma" "ddirichlet"
suppressMessages(library(MCMCpack))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-14)
rpd <- function(p) { B <- matrix(rnorm(p * p), p); crossprod(B) + diag(p) * 0.5 }
set.seed(20270110)
for (rep in 1:30) {
  p <- sample(1:4, 1); v <- p + runif(1, 0.5, 6); W <- rpd(p); S <- rpd(p); a <- c(p, v, as.vector(t(W)), as.vector(t(S)))
  add("dwish", a, dwish(W, v, S)); add("diwish", a, diwish(W, v, S))
  x <- runif(1, 0.1, 4); sh <- runif(1, 0.5, 5); sc <- runif(1, 0.3, 4); add("dinvgamma", c(x, sh, sc), dinvgamma(x, sh, sc))
  k <- sample(2:5, 1); al <- runif(k, 0.5, 5); xx <- rgamma(k, 2); xx <- xx / sum(xx); add("ddirichlet", c(k, xx, al), ddirichlet(xx, al))
}
emit("mcmcpack", "MCMCpack", list(cases))
