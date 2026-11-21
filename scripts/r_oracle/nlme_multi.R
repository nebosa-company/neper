# Fixed point of nlme's alternating algorithm (Lindstrom and Bates) with one or two nested grouping levels, any pdMat class (0 pdSymm/pdLogChol, 1 pdDiag,
# 2 pdIdent, 3 pdCompSymm) per level and any model function mf(x, p) that returns the value with a "gradient" attribute (self-start or user-written).
# d has x, y and integer columns g1 (outer group, 1..ng1) and g2 (inner group, 1..ng2, globally numbered; 0 columns of g2 for a single level).
# PNLS for (beta, b) at the relative precision of the current D, then the ML fit of D on the linearisation; iterated until both reproduce each other.
suppressMessages(library(numDeriv))
npd <- function(q, pd) if (pd == 0) q * (q + 1) / 2 else if (pd == 1) q else if (pd == 2) 1 else 2
dmat <- function(th, q, pd) {
  if (pd == 0) { L <- matrix(0, q, q); k <- 1; for (j in 1:q) { L[j, j] <- exp(th[k]); k <- k + 1; if (j < q) for (i in (j + 1):q) { L[i, j] <- th[k]; k <- k + 1 } }; return(L %*% t(L)) }
  if (pd == 1) return(diag(exp(2 * th), q))
  if (pd == 2) return(diag(exp(2 * th[1]), q))
  e <- exp(th[2]); rho <- (e - 1 / (q - 1)) / (e + 1)
  exp(2 * th[1]) * (diag(1 - rho, q) + rho)
}
mfix <- function(mf, d, npm, rs1, pd1, rs2 = integer(0), pd2 = 0, reml = 0, beta0, maxit = 200) {
  n <- nrow(d); g1 <- d$g1; ng1 <- max(g1); q1 <- length(rs1); two <- length(rs2) > 0
  g2 <- if (two) d$g2 else rep(1L, n); ng2 <- if (two) max(g2) else 0; q2 <- length(rs2)
  np <- npm; nb <- ng1 * q1 + ng2 * q2
  th1n <- npd(q1, pd1); th2n <- if (two) npd(q2, pd2) else 0
  pen <- function(th) { P <- matrix(0, nb, nb); D1 <- dmat(th[1:th1n], q1, pd1); P1 <- solve(D1); for (k in 1:ng1) { ix <- (k - 1) * q1 + 1:q1; P[ix, ix] <- P1 }
    if (two) { P2 <- solve(dmat(th[th1n + 1:th2n], q2, pd2)); for (k in 1:ng2) { ix <- ng1 * q1 + (k - 1) * q2 + 1:q2; P[ix, ix] <- P2 } }; P }
  bvec <- function(b) b
  evalf <- function(beta, b) {
    v <- numeric(n); G <- matrix(0, n, npm)
    for (t in 1:n) {
      p <- beta
      p[rs1] <- p[rs1] + b[(g1[t] - 1) * q1 + 1:q1]
      if (two) p[rs2] <- p[rs2] + b[ng1 * q1 + (g2[t] - 1) * q2 + 1:q2]
      r <- mf(d$x[t], p); v[t] <- as.numeric(r); G[t, ] <- attr(r, "gradient")
    }
    Z <- matrix(0, n, nb)
    for (t in 1:n) { Z[t, (g1[t] - 1) * q1 + 1:q1] <- G[t, rs1]; if (two) Z[t, ng1 * q1 + (g2[t] - 1) * q2 + 1:q2] <- G[t, rs2] }
    list(f = v, A = G, Z = Z)
  }
  pnls <- function(beta, b, P) {
    ev <- evalf(beta, b); S <- function(ev, b) sum((d$y - ev$f)^2) + drop(t(b) %*% P %*% b)
    s0 <- S(ev, b); PF <- matrix(0, np + nb, np + nb); PF[np + 1:nb, np + 1:nb] <- P
    for (it in 1:200) {
      J <- cbind(ev$A, ev$Z); u <- c(beta, b)
      gr <- crossprod(J, d$y - ev$f) - PF %*% c(rep(0, np), b)
      dl <- solve(crossprod(J) + PF, gr); h <- 1
      repeat {
        un <- u + h * dl; bn <- un[1:np]; bbn <- un[np + 1:nb]
        evn <- evalf(bn, bbn); sn <- S(evn, bbn)
        if (is.finite(sn) && sn <= s0 + 1e-15 * abs(s0)) break
        h <- h / 2; if (h < 1e-12) stop("step halving")
      }
      beta <- bn; b <- bbn; ev <- evn; s0 <- sn
      if (max(abs(h * dl)) < 1e-14 * (1 + max(abs(un)))) break
    }
    list(beta = beta, b = b)
  }
  lin <- function(beta, b) { ev <- evalf(beta, b); list(A = ev$A, Z = ev$Z, w = d$y - ev$f + ev$A %*% beta + ev$Z %*% b) }
  nobs <- n
  core <- function(th, ln) {
    Df <- matrix(0, nb, nb); D1 <- dmat(th[1:th1n], q1, pd1)
    for (k in 1:ng1) { ix <- (k - 1) * q1 + 1:q1; Df[ix, ix] <- D1 }
    if (two) { D2 <- dmat(th[th1n + 1:th2n], q2, pd2); for (k in 1:ng2) { ix <- ng1 * q1 + (k - 1) * q2 + 1:q2; Df[ix, ix] <- D2 } }
    V <- diag(n) + ln$Z %*% Df %*% t(ln$Z); Vi <- solve(V); ld <- as.numeric(determinant(V)$modulus)
    xvx <- t(ln$A) %*% Vi %*% ln$A; bg <- solve(xvx, t(ln$A) %*% Vi %*% ln$w); r <- ln$w - ln$A %*% bg; rss <- drop(t(r) %*% Vi %*% r)
    list(xvx = xvx, bg = bg, rss = rss, val = -nobs / 2 * log(rss) - ld / 2 )
  }
  polish <- function(th, ln) {
    obj <- function(p) -core(p, ln)$val
    for (it in 1:30) {
      gr <- numDeriv::grad(obj, th, method = "Richardson"); H <- numDeriv::hessian(obj, th, method = "Richardson")
      st <- tryCatch(solve(H, gr), error = function(e) NULL); if (is.null(st)) break
      tn <- th - st; if (obj(tn) > obj(th) + 1e-13) break
      th <- tn; if (max(abs(st)) < 1e-12) break
    }
    th
  }
  beta <- beta0; b <- rep(0, nb); th <- rep(0, th1n + th2n); if (pd1 == 3) th[2] <- 0
  if (two && pd2 == 3) th[th1n + 2] <- 0
  conv <- FALSE
  for (it in 1:maxit) {
    ln <- lin(beta, b)
    thn <- optim(th, function(p) tryCatch(if (max(abs(p)) > 12) 1e10 else -core(p, ln)$val, error = function(e) 1e10), method = "BFGS", control = list(reltol = 1e-14, maxit = 500))$par
    thn <- polish(thn, ln)
    pn <- pnls(beta, b, pen(thn))
    ch <- max(abs(c(pn$beta - beta, thn - th, pn$b - b)) / pmax(1, abs(c(pn$beta, thn, pn$b))))
    beta <- pn$beta; b <- pn$b; th <- thn
    if (ch < 3e-9) { conv <- TRUE; break }
  }
  ln <- lin(beta, b); cr <- core(th, ln); nf <- np
  rss <- cr$rss; val <- cr$val; xvx <- cr$xvx
  if (reml) { rss0 <- rss; val <- val + nf / 2 * log(rss0) - 0.5 * as.numeric(determinant(xvx)$modulus) ; nobs <- n - nf; rss <- rss0 }
  sigma <- sqrt(rss / nobs)
  ll <- val + nobs * (log(nobs) - (1 + log(2 * pi))) / 2
  D1 <- dmat(th[1:th1n], q1, pd1); D2 <- if (two) dmat(th[th1n + 1:th2n], q2, pd2) else matrix(0, 0, 0)
  list(beta = beta, b = b, th = th, D1 = D1, D2 = D2, sigma = sigma, ll = ll, xvx = xvx, nobs = nobs, conv = conv, np = np, th1n = th1n, th2n = th2n)
}
# output vector for the Neper side: beta, sigma, logLik, AIC, BIC, sd1, sd2, cor1, cor2, se
mfix_out <- function(r) {
  q1 <- nrow(r$D1); q2 <- nrow(r$D2); npar <- r$np + r$th1n + r$th2n + 1
  cr <- function(D) if (nrow(D) > 1) { s <- cov2cor(D); s[lower.tri(s)] } else numeric(0)
  c(r$beta, r$sigma, r$ll, -2 * r$ll + 2 * npar, -2 * r$ll + npar * log(r$nobs), r$sigma * sqrt(diag(r$D1)), if (q2) r$sigma * sqrt(diag(r$D2)), cr(r$D1), cr(r$D2), r$sigma * sqrt(diag(solve(r$xvx))))
}
