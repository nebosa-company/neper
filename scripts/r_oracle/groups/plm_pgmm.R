# plm::pgmm: difference and system GMM, one and two steps, individual and two-way effects, collapsed and full instrument sets, gmm instruments for y and x, exogenous instruments, unbalanced panels (padded by plm); Sargan, m1/m2, Wald, vcov and vcovHC.
#   args: (nid, nt, kx, p, xq, gx, ya, yb, xa, xb, collapse, twoways, twosteps, ld, fsm, which, y[nid*nt], x[nid*nt*kx] row-major), a missing value is -99999
#   formula: y ~ lag(y,1:p) + lag(x_j,0:xq) | lag(y,ya:yb) + lag(x_j,xa:xb) for j <= gx; fsm 0 I, 1 G (difference), 2 GI, 3 full (system)
#   which: 0 coef 1 robust se 2 classical se (position-weighted sums) 3 sargan 4 sargan df 5 sargan one-step weights 6 m1 robust 7 m2 robust 8 m1 classical 9 m2 classical
#          10 wald coef robust 11 wald coef classical 12 wald time robust 13 step-1 coef 14 sargan p 15 wald coef robust p
suppressMessages(library(plm))
cases <- list()
ws <- function(v) sum(as.numeric(v) * seq_along(v))
set.seed(20261121)
sim <- function(N, T, kx, drop) {
  d <- expand.grid(t = 1:T, id = 1:N)[, c("id", "t")]
  a <- rnorm(N)
  X <- matrix(rnorm(N * (T + 5) * kx), N * (T + 5), kx)
  y <- matrix(0, N, T + 5)
  for (s in 2:(T + 5)) for (i in 1:N)
    y[i, s] <- 0.5 * y[i, s - 1] + 0.6 * sum(X[(i - 1) * (T + 5) + s, ]) + a[i] + rnorm(1)
  yy <- round(as.vector(t(y[, 6:(T + 5)])), 4)
  xx <- round(do.call(rbind, lapply(1:N, function(i) X[(i - 1) * (T + 5) + 6:(T + 5), , drop = FALSE])), 4)
  d$y <- yy
  for (j in 1:kx) d[[paste0("x", j)]] <- xx[, j]
  keep <- rep(TRUE, nrow(d))
  if (drop > 0) {
    keep <- runif(nrow(d)) > drop
    keep[d$id == 1] <- TRUE
  }
  list(full = d, d = d[keep, ], keep = keep, N = N, T = T, kx = kx)
}
run <- function(cf, S, tag) {
  with(cf, {
    xs <- if (kx > 0) paste0("x", 1:kx) else character()
    mainx <- vapply(xs, function(v) if (xq == 0) v else sprintf("lag(%s, 0:%d)", v, xq), "")
    ml <- if (p == 1) "lag(y, 1)" else sprintf("lag(y, 1:%d)", p)
    gm <- sprintf("lag(y, %d:%d)", ya, yb)
    if (gx > 0) gm <- c(gm, sprintf("lag(%s, %d:%d)", xs[1:gx], xa, xb))
    fm <- as.formula(paste("y ~", paste(c(ml, mainx), collapse = " + "), "|", paste(gm, collapse = " + ")))
    fsmn <- c("I", "G", "GI", "full")[fsm + 1]
    m <- withCallingHandlers(
      pgmm(fm, S$d, index = c("id", "t"), effect = if (twoways) "twoways" else "individual", model = if (twosteps) "twosteps" else "onestep",
           collapse = as.logical(collapse), transformation = if (ld) "ld" else "d", fsm = fsmn),
      warning = function(w) stop(paste("warning in", tag, conditionMessage(w))))
    vr <- vcovHC(m); vn <- vcov(m)
    cf2 <- coef(m)
    sg <- sargan(m, "twosteps"); sg1 <- sargan(m, "onestep")
    wc <- pwaldtest(m, "coef", vcov = vr); wcn <- pwaldtest(m, "coef")
    vals <- c(ws(cf2), ws(sqrt(diag(vr))), ws(sqrt(diag(vn))), sg$statistic, sg$parameter, sg1$statistic,
              mtest(m, 1, vr)$statistic, mtest(m, 2, vr)$statistic, mtest(m, 1)$statistic, mtest(m, 2)$statistic,
              wc$statistic, wcn$statistic, if (twoways) pwaldtest(m, "time", vcov = vr)$statistic else 0,
              if (twosteps) ws(m$coefficients[[1]]) else 0, sg$p.value, wc$p.value)
    pad <- function(v) { v[is.na(v)] <- -99999; v }
    full <- S$full; full[!S$keep, c("y", paste0("x", seq_len(kx)))] <- NA
    yv <- pad(full$y); xv <- pad(as.vector(t(as.matrix(full[, paste0("x", seq_len(kx)), drop = FALSE]))))
    for (w in 0:15) {
      if ((w == 12 && !twoways) || (w == 13 && !twosteps)) next
      hdr <- c(S$N, S$T, kx, p, xq, gx, ya, yb, xa, xb, collapse, twoways, twosteps, ld, fsm, w)
      cases[[length(cases) + 1]] <<- case("pgmm", c(hdr, yv, xv), vals[w + 1], rel = 1e-9, abs = 1e-11)
    }
  })
}
cfg <- function(...) { l <- list(kx = 1, p = 1, xq = 0, gx = 0, ya = 2, yb = 99, xa = 2, xb = 99, collapse = 0, twoways = 0, twosteps = 0, ld = 0, fsm = 1); u <- list(...); l[names(u)] <- u; l }
S6 <- sim(40, 6, 1, 0); S6b <- sim(40, 6, 2, 0); S7 <- sim(40, 7, 1, 0); S7b <- sim(40, 7, 2, 0)
U6 <- sim(40, 6, 1, 0.08); U7 <- sim(40, 7, 2, 0.06)
run(cfg(), S6, "d1")
run(cfg(twosteps = 1), S6, "d2")
run(cfg(kx = 2, p = 2, xq = 1, twoways = 1, twosteps = 1), S7b, "d3")
run(cfg(gx = 1, xa = 2, xb = 99, collapse = 1, twosteps = 1), S7, "d4")
run(cfg(fsm = 0, yb = 3), S6, "d5")
run(cfg(ld = 1, fsm = 3), S6, "s1")
run(cfg(ld = 1, fsm = 2, twoways = 1, twosteps = 1), S6, "s2")
run(cfg(ld = 1, fsm = 3, gx = 1, collapse = 1, twosteps = 1), S6, "s3")
run(cfg(p = 2, ya = 3, ld = 1, fsm = 3, twoways = 1, twosteps = 1, kx = 2), S7b, "s4")
run(cfg(twosteps = 1, kx = 2, twoways = 1, collapse = 1), U7, "u1")
run(cfg(ld = 1, fsm = 3, twosteps = 1), U6, "u2")
emit("plm_pgmm", "plm", list(cases))
