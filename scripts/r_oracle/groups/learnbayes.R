# LearnBayes: pbetap, discint, mnormt.onesided, normal.select, beta.select and bfexch.
#   args by fn: "pbetap" (a, b, n, s)   "discint" (prob, k, which, p...) -> eprob (which 0) or the size of the set (which 1), p the probabilities in value order
#   "bf" (m0, pm, psd, xbar, n, s)   "nsel" (p1, x1, p2, x2, which)   "bsel" (p1, x1, p2, x2, which)   "bfexch" (theta, K, n, y..., nn...)
suppressMessages(library(LearnBayes))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-10)
set.seed(20261209)
for (rep in 1:20) {
  a <- runif(1, 0.5, 6); b <- runif(1, 0.5, 6); n <- sample(5:30, 1); s <- sample(0:n, 1)
  add("pbetap", c(a, b, n, s), pbetap(c(a, b), n, s))
  k <- sample(4:12, 1); p <- runif(k); p <- p / sum(p); pr <- sample(c(0.5, 0.8, 0.9, 0.95), 1)
  d <- discint(cbind(seq_len(k), p), pr)
  add("discint", c(pr, k, 0, p), d$prob); add("discint", c(pr, k, 1, p), length(d$set))
  m0 <- runif(1, 0, 2); pm <- runif(1, -1, 2); psd <- runif(1, 0.5, 2); xbar <- runif(1, 0, 3); nn <- sample(5:50, 1); s0 <- runif(1, 0.5, 3)
  add("bf", c(m0, pm, psd, xbar, nn, s0), mnormt.onesided(m0, c(pm, psd), c(xbar, nn, s0))$BF)
  q1 <- list(p = 0.5, x = runif(1, 0.2, 0.4)); q2 <- list(p = runif(1, 0.8, 0.95), x = runif(1, 0.5, 0.7))
  ns <- normal.select(list(p = 0.5, x = 100 * q1$x), list(p = q2$p, x = 100 * q2$x))
  add("nsel", c(0.5, 100 * q1$x, q2$p, 100 * q2$x, 0), ns$mu); add("nsel", c(0.5, 100 * q1$x, q2$p, 100 * q2$x, 1), ns$sigma)
  bs <- beta.select(q1, q2)
  add("bsel", c(q1$p, q1$x, q2$p, q2$x, 0), bs[1], 1e-6); add("bsel", c(q1$p, q1$x, q2$p, q2$x, 1), bs[2], 1e-6)
  g <- sample(4:9, 1); yy <- sample(0:20, g, replace = TRUE); nnn <- yy + sample(1:20, g, replace = TRUE)
  th <- runif(1, -2, 2); K <- runif(1, 0.5, 20)
  add("bfexch", c(th, K, g, yy, nnn), bfexch(th, list(data = cbind(yy, nnn), K = K)))
}
# rwmetrop "rwm" and indepmetrop "ind": (seed, kind 0 normals 1 banana, pb, m, scale, index (-1 acceptance rate), par[4], [mu[pb]], var[pb^2] column-major, start[pb])
lp <- function(th, par) { th <- as.vector(th); if (par[5] == 0) -0.5 * sum(((th - par[c(1, 3)]) / par[c(2, 4)])^2) else { u <- th[2] - par[1] * th[1]^2; -0.5 * (th[1]^2 / 4 + u^2) } }
for (rep in 1:20) {
  kd <- rep %% 2; pb <- 2; m <- sample(15:40, 1); vv <- matrix(c(1, 0.3, 0.3, 1.5), 2) * runif(1, 0.5, 2); sc <- runif(1, 0.5, 2); st <- rnorm(2); sd <- sample(1:100000, 1)
  par <- if (kd == 0) c(0.2, 1.3, -0.4, 0.8) else c(0.3, 0, 0, 0); pp <- c(par[1:4], 0); if (kd == 1) pp[5] <- 1
  parv <- if (kd == 0) c(0.2, 1.3, -0.4, 0.8) else c(0.3, 0, 0, 0)
  set.seed(sd); r1 <- rwmetrop(lp, list(var = vv, scale = sc), st, m, c(parv, kd)); 
  for (idx in c(-1, 0:(m * pb - 1))) add("rwm", c(sd, kd, pb, m, sc, idx, parv, as.vector(vv), st), if (idx < 0) r1$accept else as.vector(r1$par)[idx + 1], 1e-9)
  mu <- rnorm(2); set.seed(sd); r2 <- indepmetrop(lp, list(mu = mu, var = vv), st, m, c(parv, kd))
  for (idx in c(-1, 0:(m * pb - 1))) add("ind", c(sd, kd, pb, m, sc, idx, parv, mu, as.vector(vv), st), if (idx < 0) r2$accept else as.vector(r2$par)[idx + 1], 1e-9)
}
emit("learnbayes", "LearnBayes", list(cases))
