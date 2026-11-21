# fixed point of nlme's alternating algorithm (Lindstrom-Bates): PNLS for (beta, b) at fixed D, then an ML or REML fit of D on the linearisation
ssmod <- list(
  function(x, p) { Asym <- p[1]; xmid <- p[2]; scal <- p[3]; SSlogis(x, Asym, xmid, scal) },
  function(x, p) { Asym <- p[1]; R0 <- p[2]; lrc <- p[3]; SSasymp(x, Asym, R0, lrc) },
  function(x, p) { Vm <- p[1]; K <- p[2]; SSmicmen(x, Vm, K) },
  function(x, p) { A <- p[1]; B <- p[2]; xmid <- p[3]; scal <- p[4]; SSfpl(x, A, B, xmid, scal) },
  function(x, p) { Asym <- p[1]; b2 <- p[2]; b3 <- p[3]; SSgompertz(x, Asym, b2, b3) })
fixpoint <- function(kind, d, rset, reml, beta0, b0 = NULL, maxit = 100) {
  n <- nrow(d); gi <- as.integer(d$g); ng <- max(gi); np <- length(beta0); q <- length(rset)
  mf <- ssmod[[kind]]
  phis <- function(beta, B) { P <- matrix(beta, n, np, byrow = TRUE); P[, rset] <- P[, rset] + B[gi, , drop = FALSE]; P }
  evalf <- function(beta, B) {
    P <- phis(beta, B); v <- numeric(n); G <- matrix(0, n, np)
    for (t in 1:n) { r <- mf(d$x[t], P[t, ]); v[t] <- as.numeric(r); G[t, ] <- attr(r, "gradient") }
    list(f = v, G = G)
  }
  pnls <- function(beta, B, Pm) {
    ev <- evalf(beta, B); S <- function(ev, B) sum((d$y - ev$f)^2) + sum(rowSums((B %*% Pm) * B))
    s0 <- S(ev, B)
    for (it in 1:200) {
      J <- matrix(0, n, np + ng * q); J[, 1:np] <- ev$G
      for (t in 1:n) J[t, np + (gi[t] - 1) * q + 1:q] <- ev$G[t, rset]
      Pf <- matrix(0, np + ng * q, np + ng * q)
      for (k in 1:ng) { ix <- np + (k - 1) * q + 1:q; Pf[ix, ix] <- Pm }
      u <- c(beta, as.vector(t(B)))
      gr <- crossprod(J, d$y - ev$f) - Pf %*% c(rep(0, np), as.vector(t(B)))
      dl <- solve(crossprod(J) + Pf, gr)
      h <- 1
      repeat {
        un <- u + h * dl; bn <- un[1:np]; Bn <- matrix(un[-(1:np)], ng, q, byrow = TRUE)
        evn <- evalf(bn, Bn); sn <- S(evn, Bn)
        if (is.finite(sn) && sn <= s0 + 1e-15 * abs(s0)) break
        h <- h / 2; if (h < 1e-12) stop("step halving")
      }
      beta <- bn; B <- Bn; ev <- evn; s0 <- sn
      if (max(abs(h * dl)) < 1e-14 * (1 + max(abs(un)))) break
    }
    list(beta = beta, B = B)
  }
  lin <- function(beta, B) { ev <- evalf(beta, B); list(A = ev$G, Bz = ev$G[, rset, drop = FALSE], w = d$y - ev$f + ev$G %*% beta + rowSums(ev$G[, rset, drop = FALSE] * B[gi, , drop = FALSE])) }
  gl <- split(seq_len(n), gi); nobs <- n - reml * np
  dmat <- function(th) { L <- matrix(0, q, q); k <- 1; for (j in 1:q) { L[j, j] <- exp(th[k]); k <- k + 1; if (j < q) for (i in (j + 1):q) { L[i, j] <- th[k]; k <- k + 1 } }; L %*% t(L) }
  core <- function(th, ln) {
    Dm <- dmat(th); xvx <- matrix(0, np, np); xvy <- numeric(np); ld <- 0; Vi <- list()
    for (k in seq_along(gl)) { ix <- gl[[k]]; Bz <- ln$Bz[ix, , drop = FALSE]; V <- diag(length(ix)) + Bz %*% Dm %*% t(Bz); Vinv <- solve(V); Vi[[k]] <- Vinv
      xvx <- xvx + t(ln$A[ix, ]) %*% Vinv %*% ln$A[ix, ]; xvy <- xvy + t(ln$A[ix, ]) %*% Vinv %*% ln$w[ix]; ld <- ld + as.numeric(determinant(V)$modulus) }
    bg <- solve(xvx, xvy); rss <- 0
    for (k in seq_along(gl)) { ix <- gl[[k]]; r <- ln$w[ix] - ln$A[ix, ] %*% bg; rss <- rss + drop(t(r) %*% Vi[[k]] %*% r) }
    list(Dm = Dm, xvx = xvx, bg = bg, rss = rss, val = -nobs / 2 * log(rss) - ld / 2 - reml / 2 * as.numeric(determinant(xvx)$modulus))
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
  beta <- beta0; B <- if (is.null(b0)) matrix(0, ng, q) else b0
  th <- c(); for (j in 1:q) { th <- c(th, 0); if (j < q) th <- c(th, rep(0, q - j)) }
  conv <- FALSE
  for (it in 1:maxit) {
    ln <- lin(beta, B)
    thn <- optim(th, function(p) tryCatch(if (max(abs(p)) > 12) 1e10 else -core(p, ln)$val, error = function(e) 1e10), method = "BFGS", control = list(reltol = 1e-14, maxit = 500))$par
    thn <- polish(thn, ln)
    pn <- pnls(beta, B, solve(dmat(thn)))
    ch <- max(abs(c(pn$beta - beta, thn - th, as.vector(pn$B - B))) / pmax(1, abs(c(pn$beta, thn, as.vector(pn$B)))))
    beta <- pn$beta; B <- pn$B; th <- thn; if (getOption("fptrace", FALSE)) cat(it, ch, "
")
    if (ch < 3e-9) { conv <- TRUE; break }
  }
  ln <- lin(beta, B); cr <- core(th, ln)
  list(beta = beta, B = B, th = th, Dm = cr$Dm, sigma = sqrt(cr$rss / nobs), val = cr$val, xvx = cr$xvx, nobs = nobs, conv = conv, iters = it, core = core, lin = lin)
}
