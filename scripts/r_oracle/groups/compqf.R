# CompQuadForm: davies and farebrother (Ruben).
#   davies: (r, sigma, q, lim, acc, lambda[r], h[r], delta[r], what) fn "davies" what 0 Qq 1 ifault 2..8 trace[0..6]
#   farebrother: (r, q, maxit, eps, mode, lambda[r], h[r], delta[r], what) fn "fare" what 0 Qq 1 dnsty 2 ifault
suppressMessages(library(CompQuadForm))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261118)
for (rep in 1:80) {
  r <- sample(1:6, 1); lam <- if (rep %% 2 == 0) round(runif(r, 0.1, 3), 3) else round(runif(r, -1.5, 3), 3)
  h <- sample(1:3, r, TRUE); dl <- if (rep %% 3 == 0) round(runif(r, 0, 2), 2) else rep(0, r)
  mu <- sum(lam * (h + dl)); sg <- sqrt(2 * sum(lam^2 * (h + 2 * dl)))
  sigma <- if (rep %% 5 == 0) 0.5 else 0
  for (zq in c(-1, -0.3, 0.2, 1, 2.5)) {
    q <- round(mu + zq * sg, 3)
    r1 <- tryCatch(suppressWarnings(davies(q, lam, h, dl, sigma = sigma, lim = sample(c(1000, 10000), 1), acc = 1e-4)), error = function(e) NULL)
    if (is.null(r1)) next
    a <- c(r, sigma, q, 10000, 1e-4, lam, h, dl)
    r1 <- suppressWarnings(davies(q, lam, h, dl, sigma = sigma, lim = 10000, acc = 1e-4))
    add("davies", c(a, 0), r1$Qq); add("davies", c(a, 1), r1$ifault); for (t in 1:7) add("davies", c(a, 1 + t), r1$trace[t])
  }
  if (all(lam > 0)) for (zq in c(-0.5, 0.3, 1.5)) {
    q <- round(mu + zq * sg, 3); if (q <= 0) next
    r2 <- tryCatch(suppressWarnings(farebrother(q, lam, h, dl)), error = function(e) NULL)
    if (is.null(r2)) next
    a <- c(r, q, 100000, 1e-10, 1, lam, h, dl)
    add("fare", c(a, 0), r2$Qq); add("fare", c(a, 1), r2$dnsty); add("fare", c(a, 2), r2$ifault)
  }
  if (all(lam > 0)) for (zq in c(-1, 0, 1, 3)) {
    q <- round(mu + zq * sg, 3); if (q <= 0) next
    add("liu", c(r, q, lam, h, dl), liu(q, lam, h, dl))
  }
  for (zq in c(-1, 0, 1, 2.5)) {
    q <- round(mu + zq * sg, 3)
    r3 <- tryCatch(suppressWarnings(imhof(q, lam, h, dl)), error = function(e) NULL)
    if (is.null(r3)) next
    a <- c(r, q, 1e-6, 1e-6, 10000, lam, h, dl)
    add("imh", c(a, 0), r3$Qq); add("imh", c(a, 1), r3$abserr)
  }
}
for (th in c(0, 0.5, 5, 30, 79, 80, 120, 500, 3000)) for (df in c(0.5, 1, 3, 10, 60, 400)) for (zq in c(-2.5, -1, 0, 1, 2.5, 6)) {
  m <- df + th; x <- max(0.01, m + zq * sqrt(2 * (df + 2 * th)))
  for (lt in c(TRUE, FALSE)) { w <- suppressWarnings(pchisq(x, df, th, lower.tail = lt)); add("pnc", c(x, df, th, if (lt) 1 else 0), w) }
}
emit("compqf", "CompQuadForm", list(cases))
