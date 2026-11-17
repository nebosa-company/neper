# Hmisc: binconf (three methods), wtd.mean, wtd.var, somers2.
#   binconf: (x, n, alpha, method 0 exact 1 wilson 2 asymptotic)  fn "bc_lo" "bc_hi"
#   wtd: (n, x..., w...)  fn "wmean" "wvar"        somers2: (n, x..., y...)  fn "c" "dxy"
suppressMessages(library(Hmisc))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
mth <- c("exact", "wilson", "asymptotic")
for (n in c(5, 20, 100, 1000)) for (x in unique(c(0, 1, 2, n %/% 3, n %/% 2, n - 2, n - 1, n))) for (al in c(0.05, 0.01, 0.2)) for (m in 0:2) {
  b <- binconf(x, n, alpha = al, method = mth[m + 1])
  add("bc_lo", c(x, n, al, m), b[2]); add("bc_hi", c(x, n, al, m), b[3])
}
set.seed(20261115)
for (rep in 1:10) {
  n <- sample(8:40, 1); x <- round(rnorm(n), 3); w <- round(runif(n, 0.5, 3), 2)
  add("wmean", c(n, x, w), wtd.mean(x, w)); add("wvar", c(n, x, w), wtd.var(x, w))
  y <- rbinom(n, 1, 0.5); xs <- round(x + y * 0.8, 1)
  if (length(unique(y)) == 2) { s <- somers2(xs, y); add("c", c(n, xs, y), s[["C"]]); add("dxy", c(n, xs, y), s[["Dxy"]]) }
}
# wtd.quantile "wq" (n, k, index, x[n], w[n], probs[k]); wtd.rank "wrk" (n, index, x, w); rcspline.eval "rcs" (n, nk, norm, column-major index, x[n], knots[nk])
for (rep in 1:30) {
  n <- sample(6:40, 1); x <- if (rep %% 2 == 0) round(rnorm(n), 1) else rnorm(n); w <- round(runif(n, 0.5, 3), 2); pr <- sort(runif(sample(2:5, 1)))
  q <- wtd.quantile(x, w, probs = pr); for (j in seq_along(pr)) add("wq", c(n, length(pr), j - 1, x, w, pr), q[[j]])
  r <- wtd.rank(x, w); for (i in seq_len(n)) add("wrk", c(n, i - 1, x, w), r[i])
  nk <- sample(3:6, 1); kn <- sort(sample(x, nk)); if (length(unique(kn)) < nk) next; nm <- sample(0:2, 1)
  B <- rcspline.eval(x, knots = kn, norm = nm); for (j in seq_along(as.vector(B))) add("rcs", c(n, nk, nm, j - 1, x, kn), as.vector(B)[j])
}
# hdquantile "hdq" (n, p, x[n]); rcorr "rc" (n, spearman, index 0 r 1 P, x[n], y[n])
for (rep in 1:40) {
  n <- sample(5:40, 1); x <- rnorm(n); y <- 0.4 * x + rnorm(n); if (rep %% 2 == 0) { x <- round(x, 1); y <- round(y, 1) }
  for (p in c(0.1, 0.5, 0.87)) add("hdq", c(n, p, x), hdquantile(x, p)[[1]])
  for (sp in 0:1) { r <- rcorr(x, y, type = c("pearson", "spearman")[sp + 1]); add("rc", c(n, sp, 0, x, y), r$r[1, 2]); add("rc", c(n, sp, 1, x, y), r$P[1, 2]) }
}
# cut2(x, g, onlycuts = TRUE): "cut" (n, g, index, x[n]); index -1 the number of cuts
for (rep in 1:40) {
  n <- sample(10:60, 1); x <- if (rep %% 2 == 0) round(rnorm(n), 1) else sample(1:5, n, TRUE) + 0; g <- sample(2:6, 1)
  ct <- cut2(x, g = g, onlycuts = TRUE, m = 1); add("cut", c(n, g, -1, x), length(ct)); for (j in seq_along(ct)) add("cut", c(n, g, j - 1, x), ct[j])
}
# approxExtrap "axt" (n, xout, x[n] ascending distinct, y[n]); rcorr.cens "rcc" (n, index 0 C 1 Dxy 2 n 3 uncensored 4 relevant 5 concordant 6 uncertain, x, time, event)
suppressMessages(library(survival))
for (rep in 1:40) {
  n <- sample(5:12, 1); xs <- sort(runif(n, -1, 1)); ys <- rnorm(n); xo <- c(runif(3, min(xs) - 1, max(xs) + 1), xs[2], (xs[1] + xs[2]) / 2)
  r <- approxExtrap(xs, ys, xout = xo)$y; for (j in seq_along(xo)) add("axt", c(n, xo[j], xs, ys), r[j])
  m <- sample(10:40, 1); tt <- round(rexp(m), 2); ee <- rbinom(m, 1, 0.7); xx <- round(runif(m), 1); if (sum(ee) < 2) next
  rc <- rcorr.cens(xx, Surv(tt, ee)); for (j in 0:6) add("rcc", c(m, j, xx, tt, ee), unname(rc[c(1, 2, 4, 6, 7, 8, 9)[j + 1]])); add("rcc", c(m, 7, xx, tt, ee), unname(rc[["S.D."]]))
}
# smean.cl.normal "scn", smean.sdl "ssd", smedian.hilow "smh": (n, conf or mult, j, x[n])
for (rep in 1:25) {
  n <- sample(5:80, 1); x <- if (rep %% 2) rnorm(n, 3, 2) else round(rexp(n), 1); cf <- sample(c(0.8, 0.9, 0.95, 0.99), 1); ml <- sample(c(1, 2, 3), 1)
  a1 <- smean.cl.normal(x, conf.int = cf); a2 <- smean.sdl(x, mult = ml); a3 <- smedian.hilow(x, conf.int = cf)
  for (j in 1:3) { cases[[length(cases) + 1]] <- case("scn", c(n, cf, j - 1, x), a1[[j]], rel = 1e-10, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("ssd", c(n, ml, j - 1, x), a2[[j]], rel = 1e-10, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("smh", c(n, cf, j - 1, x), a3[[j]], rel = 1e-10, abs = 1e-12) }
}
# varclus "vc": (n, k, which 0 height 1 order 2 merge a 3 merge b, index, spearman, trans 0 square 1 abs 2 none, method (hclust codes 2 single 3 complete 4 average), x[n k])
for (rep in 1:15) {
  n <- sample(20:60, 1); k <- sample(4:8, 1); Z <- matrix(rnorm(n * 3), n, 3); x <- sapply(1:k, function(j) Z[, (j %% 3) + 1] * runif(1, 0.5, 1.5) + rnorm(n, 0, runif(1, 0.3, 1.5)))
  sp <- rep %% 2; tr <- c("square", "abs", "none")[rep %% 3 + 1]; me <- c("single", "complete", "average")[rep %% 3 + 1]; mc <- c(2, 3, 4)[rep %% 3 + 1]
  v <- varclus(x, similarity = if (sp) "spearman" else "pearson", trans = tr, method = me); h <- v$hclust
  for (q in seq_len(k - 1)) { cases[[length(cases) + 1]] <- case("vc", c(n, k, 0, q - 1, sp, rep %% 3, mc, x), h$height[q], rel = 1e-9, abs = 1e-11)
    cases[[length(cases) + 1]] <- case("vc", c(n, k, 2, q - 1, sp, rep %% 3, mc, x), h$merge[q, 1], rel = 0, abs = 0.5)
    cases[[length(cases) + 1]] <- case("vc", c(n, k, 3, q - 1, sp, rep %% 3, mc, x), h$merge[q, 2], rel = 0, abs = 0.5) }
  for (q in seq_len(k)) cases[[length(cases) + 1]] <- case("vc", c(n, k, 1, q - 1, sp, rep %% 3, mc, x), h$order[q], rel = 0, abs = 0.5)
}
# GiniMd "gmd" and the Info of describe "info": (n, x[n])
for (rep in 1:30) { n <- sample(5:80, 1); x <- if (rep %% 2) rnorm(n) else round(rnorm(n), 1); tb <- table(x)
  cases[[length(cases) + 1]] <- case("gmd", c(n, x), GiniMd(x), rel = 1e-10, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("info", c(n, x), 1 - sum(tb^3 - tb) / (n^3 - n), rel = 1e-10, abs = 1e-12) }
# smean.cl.boot "scb": (seed, B, conf, which 0 mean 1 lower 2 upper, n, x[n])
for (rep in 1:10) { n <- sample(5:40, 1); x <- rnorm(n, 3, 2); sd <- sample(1:100000, 1); B <- sample(c(100, 300, 1000), 1); cf <- sample(c(0.9, 0.95), 1)
  set.seed(sd); r <- smean.cl.boot(x, conf.int = cf, B = B); for (w in 0:2) cases[[length(cases) + 1]] <- case("scb", c(sd, B, cf, w, n, x), unname(r[w + 1]), rel = 1e-10, abs = 1e-12) }
# redun linear "red": (n, p, r2, k, which 0 column removed at step k 1 its R^2 2 number removed, X[n p])
for (rep in 1:12) {
  n <- sample(40:100, 1); p <- sample(4:7, 1); X <- matrix(rnorm(n * p), n, p); X[, 2] <- X[, 1] + rnorm(n, 0, runif(1, 0.1, 0.5)); X[, 4] <- X[, 2] + X[, 3] + rnorm(n, 0, runif(1, 0.1, 0.4))
  D <- as.data.frame(X); names(D) <- paste0("v", 1:p); r2 <- sample(c(0.7, 0.8, 0.9), 1)
  rd <- redun(as.formula(paste("~", paste(names(D), collapse = " + "))), data = D, r2 = r2, nk = 0); out <- rd$Out; rq <- rd$rsquared
  cases[[length(cases) + 1]] <- case("red", c(n, p, r2, 0, 2, X), length(out), rel = 0, abs = 0.5)
  for (k in seq_along(out)) { cases[[length(cases) + 1]] <- case("red", c(n, p, r2, k - 1, 0, X), match(out[k], names(D)) - 1, rel = 0, abs = 0.5)
    cases[[length(cases) + 1]] <- case("red", c(n, p, r2, k - 1, 1, X), unname(rq[k]), rel = 1e-8, abs = 1e-10) }
}
# spearman2 "sp2": (n, p, which 0 rho2 1 F 2 adjusted, x[n], y[n])
for (rep in 1:20) { n <- sample(8:80, 1); x <- if (rep %% 2) rnorm(n) else round(rnorm(n), 1); y <- round(x^2 + rnorm(n), 1 + rep %% 2); pp <- 1 + rep %% 2
  r <- spearman2(x, y, p = pp); for (w in 0:2) cases[[length(cases) + 1]] <- case("sp2", c(n, pp, w, x, y), unname(r[c(1, 2, 7)[w + 1]]), rel = 1e-8, abs = 1e-10) }
# spearman2 factor "sp2f": (n, ng, which, g[n] 0-based, y[n])
for (rep in 1:20) { ng <- sample(3:6, 1); n <- sample(ng * 4:ng * 12, 1); g <- c(0:(ng - 1), sample(0:(ng - 1), n - ng, TRUE)); y <- round(rnorm(n) + g * 0.3, 1 + rep %% 2)
  r <- spearman2(factor(g), y); for (w in 0:2) cases[[length(cases) + 1]] <- case("sp2f", c(n, ng, w, g, y), unname(r[c(1, 2, 7)[w + 1]]), rel = 1e-8, abs = 1e-10) }
# bpower "bpw" (p1, p2, n1, n2, alpha) and bsamsize "bss" (p1, p2, fraction, alpha, power, which 0 n1 1 n2)
for (rep in 1:40) { p1 <- runif(1, 0.05, 0.6); p2 <- min(0.95, p1 + runif(1, 0.05, 0.3)); n1 <- sample(30:300, 1); n2 <- sample(30:300, 1); al <- sample(c(0.01, 0.05, 0.1), 1); fr <- runif(1, 0.3, 0.7); pw <- sample(c(0.8, 0.9), 1)
  cases[[length(cases) + 1]] <- case("bpw", c(p1, p2, n1, n2, al), unname(bpower(p1, p2, n1 = n1, n2 = n2, alpha = al)), rel = 1e-10, abs = 1e-12)
  b <- bsamsize(p1, p2, fr, al, pw); for (w in 0:1) cases[[length(cases) + 1]] <- case("bss", c(p1, p2, fr, al, pw, w), unname(b[w + 1]), rel = 1e-10, abs = 1e-12) }
# samplesize.bin "ssb" (alpha, beta, pit, pic, rho) and ballocation "bal" (p1, p2, n, alpha, which 0..3)
for (rep in 1:30) { pic <- runif(1, 0.05, 0.5); pit <- pic + runif(1, 0.1, 0.4); al <- sample(c(0.025, 0.05), 1); be <- sample(c(0.8, 0.9), 1); rho <- runif(1, 0.3, 0.7); n <- sample(50:400, 1)
  cases[[length(cases) + 1]] <- case("ssb", c(al, be, pit, pic, rho), samplesize.bin(al, be, pit, pic, rho), rel = 0, abs = 0.5)
  b <- ballocation(pic, pit, n, al); for (w in 0:3) cases[[length(cases) + 1]] <- case("bal", c(pic, pit, n, al, w), unname(b[w + 1]), rel = 1e-10, abs = 1e-12) }
# cpower "cpw" (tref, n, mc, r, accrual, tmin, noncomp.c, noncomp.i, alpha)
for (rep in 1:30) { tr <- sample(3:5, 1); n <- sample(500:3000, 1); mc <- runif(1, 0.1, 0.5); r <- sample(c(15, 25, 35), 1); ac <- sample(c(0, 1.5, 2.5), 1); tm <- sample(c(1, 2, 3), 1); nc <- sample(c(0, 5), 1); ni <- sample(c(0, 10), 1); al <- sample(c(0.05, 0.01), 1)
  cases[[length(cases) + 1]] <- case("cpw", c(tr, n, mc, r, ac, tm, nc, ni, al), unname(cpower(tr, n, mc, r, ac, tm, nc, ni, al, pr = FALSE)), rel = 1e-10, abs = 1e-12) }
# ciapower "cia" (tref, n1, n2, m1c, m2c, r1, r2, accrual, tmin, alpha)
for (rep in 1:30) { tr <- sample(3:5, 1); n1 <- sample(500:3000, 1); n2 <- sample(500:3000, 1); m1 <- runif(1, 0.1, 0.5); m2 <- runif(1, 0.1, 0.5); r1 <- sample(c(10, 25, 40), 1); r2 <- sample(c(5, 15, 30), 1); ac <- sample(c(1.5, 2.5), 1); tm <- sample(c(1, 2, 3), 1); al <- sample(c(0.05, 0.01), 1)
  cases[[length(cases) + 1]] <- case("cia", c(tr, n1, n2, m1, m2, r1, r2, ac, tm, al), unname(ciapower(tr, n1, n2, m1, m2, r1, r2, ac, tm, al, pr = FALSE)), rel = 1e-10, abs = 1e-12) }
# popower "pop" (k, odds, n1, n2, alpha, which 0 power 1 eff 2 se, p[k]) and posamsize "pos" (k, odds, fraction, alpha, power, p[k], which 0 n 1 eff)
for (rep in 1:30) { k <- sample(3:6, 1); pr <- runif(k); pr <- pr / sum(pr); orr <- runif(1, 1.3, 3); n1 <- sample(40:300, 1); n2 <- sample(40:300, 1); al <- sample(c(0.05, 0.01), 1); fr <- runif(1, 0.3, 0.7); pw <- sample(c(0.8, 0.9), 1)
  r <- popower(pr, orr, n1 = n1, n2 = n2, alpha = al); v <- c(r$power, r$eff, r$approx.se); for (w in 0:2) cases[[length(cases) + 1]] <- case("pop", c(k, orr, n1, n2, al, w, pr), v[w + 1], rel = 1e-10, abs = 1e-12)
  r <- posamsize(pr, orr, fr, al, pw); v <- c(r$n, r$eff); for (w in 0:1) cases[[length(cases) + 1]] <- case("pos", c(k, orr, fr, al, pw, pr, w), v[w + 1], rel = 1e-10, abs = 1e-12) }
emit("hmisc", "Hmisc", list(cases))
