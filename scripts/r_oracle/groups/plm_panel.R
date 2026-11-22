# plm on unbalanced and balanced panels: the pooling, within, between, random (swar, walhus, amemiya, nerlove) and fd models,
# phtest, pFtest, plmtest, pbgtest, pdwtest, vcovHC (arellano, white1, white2) and vcovSCC.
#   args: (n, k, p1..p7, id[n], tm[n], y[n], x[n*k] row-major), rows ordered by individual then period; id and tm are 1-based
#   p6 = 1: effect "time" (fit only; the periods play the groups)
#   fn "fit" p1 model (0 pooling 1 within 2 between 3 random 4 fd) p2 method (0 swar 1 walhus 2 amemiya 3 nerlove) p3 which
#      (0 coef, 1 se, 2 sigma2 idiosyncratic, 3 sigma2 individual, 4 theta by individual; position-weighted sums)
#   fn "ph" p1 method p2 which (0 stat 1 p 2 df)     fn "pf" p1 which (0 F 1 p)
#   fn "lm" p1 effect (0 individual 1 time 2 twoways) p2 type (0 honda 1 bp 2 kw 3 ghm) p3 which (0 stat 1 p)
#   fn "bg" p1 model p2 method p3 order p4 which (0 LM 1 p)     fn "dw" p1 model p2 method p3 which (0 statistic 1 p value)
#   fn "vg" p1 model p2 method p3 type (0 HC0 1 sss 2 HC1 3 HC2 4 HC3 5 HC4) p4 cluster (0 group 1 time) p5 inner (0 arellano 1 white1 2 white2)
#   fn "scc" p1 model p2 method p3 type p4 maxlag (-1 default) p5 inner (0 cluster 1 white 2 diagavg)
suppressMessages(library(plm))
cases <- list()
types <- c("HC0", "sss", "HC1", "HC2", "HC3", "HC4")
models <- c("pooling", "within", "between", "random", "fd")
meths <- c("swar", "walhus", "amemiya", "nerlove")
ws <- function(v) sum(v * seq_along(v))
set.seed(20261120)
mk <- function(N, Ti, K) {
  id <- rep(seq_len(N), Ti); tm <- unlist(lapply(Ti, seq_len)); n <- sum(Ti)
  x <- round(matrix(rnorm(n * K), n) + rep(rnorm(N), Ti) * 0.5, 4)
  u <- rep(rnorm(N, 0, 1), Ti)
  y <- round(1 + as.vector(x %*% rnorm(K)) + u + rnorm(n), 4)
  list(n = n, K = K, id = id, tm = tm, y = y, x = x)
}
add <- function(fn, h, dat, want, rel = 1e-9, abs = 1e-11) {
  hh <- c(h, rep(0, 7 - length(h)))
  cases[[length(cases) + 1]] <<- case(fn, c(dat$n, dat$K, hh, dat$id, dat$tm, dat$y, as.vector(t(dat$x))), want, rel = rel, abs = abs)
}
for (rep in 1:7) {
  N <- sample(6:9, 1); K <- sample(1:2, 1)
  Ti <- if (rep <= 2) rep(sample(3:4, 1), N) else sample(3:5, N, TRUE)
  if (rep > 2) Ti[1] <- 5
  dat <- mk(N, Ti, K)
  d <- data.frame(id = dat$id, tm = dat$tm, y = dat$y, dat$x); names(d)[4:(3 + K)] <- paste0("x", seq_len(K))
  fm <- as.formula(paste("y ~", paste0("x", seq_len(K), collapse = " + ")))
  P <- function(m, meth = 0) plm(fm, d, index = c("id", "tm"), model = models[m + 1], random.method = meths[meth + 1])
  for (mi in 0:4) for (me in if (mi == 3) 0:3 else 0) {
    p <- P(mi, me); s <- summary(p)$coefficients
    add("fit", c(mi, me, 0), dat, ws(s[, 1])); add("fit", c(mi, me, 1), dat, ws(s[, 2]))
    if (mi == 3) {
      add("fit", c(mi, me, 2), dat, p$ercomp$sigma2[["idios"]]); add("fit", c(mi, me, 3), dat, p$ercomp$sigma2[["id"]])
      add("fit", c(mi, me, 4), dat, ws(tapply(rep_len(as.numeric(p$ercomp$theta), nrow(d)), d$id, function(v) v[1])))
    }
  }
  # effect = "time": the same models with the periods as the groups (p6 = 1 in the argument layout)
  Pt <- function(m, meth = 0) plm(fm, d, index = c("id", "tm"), model = models[m + 1], effect = "time", random.method = meths[meth + 1])
  addt <- function(fn, h, dat, want) add(fn, c(h, rep(0, 3 - length(h)), 0, 0, 1), dat, want)
  for (mi in 1:3) for (me in if (mi == 3) 0:3 else 0) {
    p <- Pt(mi, me); s <- summary(p)$coefficients
    addt("fit", c(mi, me, 0), dat, ws(s[, 1])); addt("fit", c(mi, me, 1), dat, ws(s[, 2]))
    if (mi == 3) {
      addt("fit", c(mi, me, 2), dat, p$ercomp$sigma2[["idios"]]); addt("fit", c(mi, me, 3), dat, p$ercomp$sigma2[["time"]])
      addt("fit", c(mi, me, 4), dat, ws(tapply(rep_len(as.numeric(p$ercomp$theta), nrow(d)), d$tm, function(v) v[1])))
    }
  }
  for (me in 0:3) {
    h <- phtest(P(1), P(3, me))
    add("ph", c(me, 0), dat, h$statistic); add("ph", c(me, 1), dat, h$p.value, rel = 1e-8)
  }
  f <- pFtest(P(1), P(0)); add("pf", 0, dat, f$statistic); add("pf", 1, dat, f$p.value, rel = 1e-8)
  pl <- P(0)
  for (ef in 0:2) for (ty in 0:3) {
    if (ef < 2 && ty == 3) next
    t <- plmtest(pl, effect = c("individual", "time", "twoways")[ef + 1], type = c("honda", "bp", "kw", "ghm")[ty + 1])
    add("lm", c(ef, ty, 0), dat, t$statistic); add("lm", c(ef, ty, 1), dat, t$p.value, rel = 1e-8)
  }
  for (mi in c(0, 1, 3, 4)) for (o in 1:2) {
    b <- pbgtest(P(mi), order = o)
    add("bg", c(mi, 0, o, 0), dat, b$statistic); add("bg", c(mi, 0, o, 1), dat, b$p.value, rel = 1e-8)
  }
  for (mi in c(0, 1, 3, 4)) {
    dwr <- pdwtest(P(mi)); add("dw", c(mi, 0, 0), dat, dwr$statistic); add("dw", c(mi, 0, 1), dat, dwr$p.value, rel = 1e-9)
  }
  for (mi in c(0, 1, 3, 4)) {
    p <- P(mi)
    for (ty in 0:5) add("vg", c(mi, 0, ty, 0, 0), dat, ws(as.vector(vcovHC(p, type = types[ty + 1]))))
    add("vg", c(mi, 0, 0, 1, 0), dat, ws(as.vector(vcovHC(p, cluster = "time"))))
    add("vg", c(mi, 0, 0, 0, 1), dat, ws(as.vector(vcovHC(p, method = "white1"))))
    add("vg", c(mi, 0, 0, 0, 2), dat, ws(as.vector(vcovHC(p, method = "white2"))))
    {
      add("scc", c(mi, 0, 0, -1, 0), dat, ws(as.vector(vcovSCC(p))))
      add("scc", c(mi, 0, 2, 1, 0), dat, ws(as.vector(vcovSCC(p, type = "HC1", maxlag = 1))))
    }
  }
}
# n >= 100: dwtest takes the normal approximation
dat <- mk(25, rep(4, 25), 2)
d <- data.frame(id = dat$id, tm = dat$tm, y = dat$y, dat$x); names(d)[4:5] <- c("x1", "x2")
for (mi in c(0, 1, 3)) {
  dwr <- pdwtest(plm(y ~ x1 + x2, d, index = c("id", "tm"), model = models[mi + 1])); add("dw", c(mi, 0, 0), dat, dwr$statistic); add("dw", c(mi, 0, 1), dat, dwr$p.value, rel = 1e-9)
}
emit("plm_panel", "plm", list(cases))
