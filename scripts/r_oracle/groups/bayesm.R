# bayesm: log densities (lndMvn, lndMvst, lndIWishart, lndIChisq, llmnl, condMom) and the samplers rdirichlet, rtrun, rwishart, breg under set.seed.
#   fn "mvn" (k, x, mu, rooti) "mvst" (k, nu, normc, x, mu, rooti) "iw" (k, nu, V, IW) "ic" (nu, ssq, x) "mn" (k, p, n, beta, y, X) "cm" (id, k, i, x, mu, sigi) id 0 mean 1 var
#   "dir" (seed, m, alpha, index) "trun" (seed, mu, sigma, a, b) "wish" (seed, k, nu, V, block * k^2 + position) blocks W IW C CI "breg" (seed, n, k, y, X, betabar, A, index)
suppressMessages(library(bayesm))
cases <- list()
add <- function(fn, args, want, tol = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-12)
set.seed(20261117)
rspd <- function(k) { M <- matrix(rnorm(k * k), k); crossprod(M) + diag(k) * 0.5 }
for (rep in 1:25) {
  k <- sample(2:5, 1); S <- rspd(k); rooti <- backsolve(chol(S), diag(k)); x <- rnorm(k); mu <- rnorm(k); nu <- sample(3:20, 1)
  add("mvn", c(k, x, mu, rooti), lndMvn(x, mu, rooti)); add("mvst", c(k, nu, 0, x, mu, rooti), lndMvst(x, nu, mu, rooti)); add("mvst", c(k, nu, 1, x, mu, rooti), lndMvst(x, nu, mu, rooti, TRUE))
  IW <- rspd(k); add("iw", c(k, nu + k, S, IW), lndIWishart(nu + k, S, IW))
  add("ic", c(nu, 1.3, 0.8 + rep / 10), lndIChisq(nu, 1.3, matrix(0.8 + rep / 10))); 
  si <- solve(S); i <- sample(k, 1); cmo <- condMom(x, mu, si, i); add("cm", c(0, k, i - 1, x, mu, si), cmo$cmean); add("cm", c(1, k, i - 1, x, mu, si), cmo$cvar)
  p <- sample(2:4, 1); kb <- sample(1:3, 1); n <- sample(5:30, 1); y <- sample(p, n, TRUE); X <- matrix(rnorm(n * p * kb), n * p, kb); beta <- rnorm(kb)
  add("mn", c(kb, p, n, beta, y, X), llmnl(beta, y, X))
  sd <- sample(1:100000, 1); m <- sample(2:6, 1); al <- runif(m, 0.3, 4); set.seed(sd); d <- rdirichlet(al); for (j in 1:m) add("dir", c(sd, m, al, j - 1), d[j], 1e-12)
  mu1 <- rnorm(1); s1 <- runif(1, 0.5, 2); a <- mu1 - runif(1, 0.2, 2); b <- mu1 + runif(1, 0.2, 2); set.seed(sd); add("trun", c(sd, mu1, s1, a, b), rtrun(mu1, s1, a, b), 1e-9)
  nuw <- k + sample(1:8, 1); V <- rspd(k); set.seed(sd); w <- rwishart(nuw, V)
  for (b in 1:4) { M <- w[[b]]; for (q in seq_len(k * k)) add("wish", c(sd, k, nuw, V, (b - 1) * k * k + q - 1), as.vector(M)[q], 1e-9) }
  nb <- sample(10:40, 1); kb2 <- sample(1:4, 1); Xb <- matrix(rnorm(nb * kb2), nb, kb2); yb <- rnorm(nb); bb <- rnorm(kb2); Ab <- rspd(kb2)
  set.seed(sd); bd <- breg(yb, Xb, bb, Ab); for (q in 1:kb2) add("breg", c(sd, nb, kb2, yb, Xb, bb, Ab, q - 1), bd[q], 1e-9)
}
emit("bayesm", "bayesm", list(cases))
