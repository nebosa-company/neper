# TTR: SMA, EMA, WMA, DEMA, RSI, MACD, BBands, ROC, OBV, ATR.
#   args: (id, n, p2, p3, flag, len, x[len], y[len], z[len], stat)  stat 0 length 1 sum 2 position-weighted sum 3 first 4 last 5 NA count
#   id 0 SMA(n) 1 EMA(n, wilder flag) 2 WMA(n) 3 DEMA(n, v = p2, wilder flag) 4 RSI(n) 5 MACD macd(n fast, p2 slow, p3 signal)
#   6 MACD signal 7-10 BBands dn mavg up pctB (n, sd = p2) 11 ROC continuous(n) 12 ROC discrete(n) 13 OBV(x price, y volume)
#   14 ATR(n; x high, y low, z close) 15 TR 16 ZLEMA(n) 17 CCI(n; x high, y low, z close) 18-20 stoch fastK fastD slowD (n fastK, p2 fastD, p3 slowD)
#   21-24 ADX DIp DIn DX ADX(n)
library(TTR)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
set.seed(20261115)
vec <- function(a, v) {
  ok <- !is.na(v); w <- seq_along(v)
  st <- c(length(v), sum(v[ok]), sum(w[ok] * v[ok]), if (length(v)) v[1] else 0, if (length(v)) v[length(v)] else 0, sum(!ok))
  for (j in 0:5) add("stat", c(a, j), st[j + 1])
}
for (rep in 1:6) {
  len <- c(60, 90, 45, 120, 70, 80)[rep]
  px <- round(100 + cumsum(rnorm(len)), 3); vol <- round(runif(len, 100, 1000)); hi <- px + round(runif(len, 0, 2), 3); lo <- px - round(runif(len, 0, 2), 3)
  xl <- if (rep %% 2 == 0) c(rep(NA, 3), px[-(1:3)]) else px
  mk <- function(id, n, p2, p3, flag, x, y = rep(0, len), z = rep(0, len)) c(id, n, p2, p3, flag, len, x, y, z)
  for (n in c(3, 10, 20)) {
    vec(mk(0, n, 0, 0, 0, xl), as.numeric(SMA(xl, n)))
    for (w in 0:1) vec(mk(1, n, 0, 0, w, xl), as.numeric(EMA(xl, n, wilder = w == 1)))
    vec(mk(2, n, 0, 0, 0, px), as.numeric(WMA(px, n)))
    vec(mk(3, n, 1, 0, 0, px), as.numeric(DEMA(px, n)))
    vec(mk(3, n, 0.5, 0, 1, px), as.numeric(DEMA(px, n, v = 0.5, wilder = TRUE)))
    vec(mk(4, n, 0, 0, 0, px), as.numeric(RSI(px, n)))
    bb <- BBands(px, n, sd = 2)
    for (k in 1:4) vec(mk(6 + k, n, 2, 0, 0, px), as.numeric(bb[, k]))
    vec(mk(11, n, 0, 0, 0, px), as.numeric(ROC(px, n)))
    vec(mk(12, n, 0, 0, 0, px), as.numeric(ROC(px, n, type = "discrete")))
    hlc <- cbind(hi, lo, px); at <- ATR(hlc, n)
    vec(mk(14, n, 0, 0, 0, hi, lo, px), as.numeric(at[, "atr"]))
  }
  for (n in c(3, 5, 10, 14)) {
    vec(mk(16, n, 0, 0, 0, px), as.numeric(ZLEMA(px, n)))
    vec(mk(17, n, 0, 0, 0, hi, lo, px), as.numeric(CCI(cbind(hi, lo, px), n)))
    st <- stoch(cbind(hi, lo, px), nFastK = n, nFastD = 3, nSlowD = 3)
    for (k in 1:3) vec(mk(17 + k, n, 3, 3, 0, hi, lo, px), as.numeric(st[, k]))
    ax <- ADX(cbind(hi, lo, px), n)
    for (k in 1:4) vec(mk(20 + k, n, 0, 0, 0, hi, lo, px), as.numeric(ax[, k]))
  }
  m <- MACD(px, 12, 26, 9, percent = TRUE); vec(mk(5, 12, 26, 9, 1, px), as.numeric(m[, 1])); vec(mk(6, 12, 26, 9, 1, px), as.numeric(m[, 2]))
  m2 <- MACD(px, 5, 12, 4, percent = FALSE); vec(mk(5, 5, 12, 4, 0, px), as.numeric(m2[, 1])); vec(mk(6, 5, 12, 4, 0, px), as.numeric(m2[, 2]))
  vec(mk(13, 1, 0, 0, 0, px, vol), as.numeric(OBV(px, vol)))
  vec(mk(15, 1, 0, 0, 0, hi, lo, px), as.numeric(TR(cbind(hi, lo, px))[, "tr"]))
}
emit("ttr", "TTR", list(cases))
