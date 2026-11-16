# urca: ur.df and ur.kpss.
#   df: (type 0 none 1 drift 2 trend, lags, select 0 Fixed 1 AIC 2 BIC, n, y...)  fn "df_tau" "df_phia" "df_phib" "df_lags" "df_c<level>_<which>"
#   kpss: (type 0 mu 1 tau, lags 0 short 1 long 2 nil, n, y...)                    fn "kpss"
library(urca)
set.seed(20261115)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-9)
series <- list(
  cumsum(rnorm(80)), cumsum(rnorm(120, 0.1)), arima.sim(list(ar = 0.6), 100) + 3, arima.sim(list(ar = c(0.5, -0.3)), 140),
  cumsum(rnorm(60)) + 0.05 * (1:60), round(cumsum(rnorm(200, 0.05)), 3), arima.sim(list(ar = 0.9), 70))
series <- lapply(series, function(v) as.numeric(round(v, 4)))
for (y in series) {
  n <- length(y)
  for (ty in c("none", "drift", "trend")) for (lg in c(0, 1, 3)) {
    r <- tryCatch(ur.df(y, type = ty, lags = lg), error = function(e) NULL)
    if (is.null(r)) next
    tyi <- match(ty, c("none", "drift", "trend")) - 1
    a <- c(tyi, lg, 0, n, y); ts <- as.numeric(r@teststat)
    add("df_tau", a, ts[1]); if (length(ts) > 1) add("df_phia", a, ts[2]); if (length(ts) > 2) add("df_phib", a, ts[3])
    add("df_lags", a, nrow(coef(r@testreg)) - 1 - (ty != "none") - (ty == "trend"))
    for (lv in 1:3) for (w in seq_len(nrow(r@cval))) add(paste0("df_c", lv - 1, "_", w - 1), a, r@cval[w, lv])
  }
  for (ty in c("drift", "trend")) for (sel in c("AIC", "BIC")) {
    r <- tryCatch(ur.df(y, type = ty, lags = 6, selectlags = sel), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(match(ty, c("none", "drift", "trend")) - 1, 6, match(sel, c("Fixed", "AIC", "BIC")) - 1, n, y); ts <- as.numeric(r@teststat)
    add("df_tau", a, ts[1]); add("df_phia", a, ts[2]); if (length(ts) > 2) add("df_phib", a, ts[3]); add("df_lags", a, nrow(coef(r@testreg)) - 1 - (ty != "none") - (ty == "trend"))
  }
  for (ty in c("mu", "tau")) for (lg in c("short", "long", "nil")) {
    r <- ur.kpss(y, type = ty, lags = lg)
    add("kpss", c(match(ty, c("mu", "tau")) - 1, match(lg, c("short", "long", "nil")) - 1, n, y), r@teststat)
  }
}
emit("urca", "urca", list(cases))
