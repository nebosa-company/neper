# PerformanceAnalytics: single-series return and risk measures.
#   args: (p1, p2, n, returns...)   fn "annual" (p1 scale, p2 geometric) "maxdd" (p2 geometric) "dd" (p1 mar, p2 0 full 1 subset 2 potential) "sortino" (p1 mar)
#   "calmar" (p1 scale) "sharpe" (p1 rf) "var" (p1 p, p2 0 historical 1 gaussian 2 modified) "es" (p1 p, p2 0 historical 1 gaussian)
suppressMessages(library(PerformanceAnalytics))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261207)
for (rep in 1:14) {
  n <- sample(30:120, 1); r <- round(rnorm(n, 0.004, 0.03), 4)
  if (rep %% 3 == 0) r <- round(r + 0.05 * (rexp(n) - 1), 4)
  a <- function(p1, p2) c(p1, p2, n, r)
  sc <- c(12, 252, 52)[rep %% 3 + 1]
  add("annual", a(sc, 1), as.numeric(Return.annualized(r, scale = sc, geometric = TRUE)))
  add("annual", a(sc, 0), as.numeric(Return.annualized(r, scale = sc, geometric = FALSE)))
  add("maxdd", a(0, 1), as.numeric(maxDrawdown(r, geometric = TRUE)))
  add("maxdd", a(0, 0), as.numeric(maxDrawdown(r, geometric = FALSE)))
  mar <- c(0, 0.002, -0.01)[rep %% 3 + 1]
  add("dd", a(mar, 0), as.numeric(DownsideDeviation(r, MAR = mar)))
  add("dd", a(mar, 1), as.numeric(DownsideDeviation(r, MAR = mar, method = "subset")))
  add("dd", a(mar, 2), as.numeric(DownsideDeviation(r, MAR = mar, potential = TRUE)))
  add("sortino", a(mar, 0), as.numeric(SortinoRatio(r, MAR = mar)))
  add("calmar", a(sc, 0), as.numeric(CalmarRatio(r, scale = sc)))
  rf <- c(0, 0.001)[rep %% 2 + 1]
  add("sharpe", a(rf, 0), as.numeric(SharpeRatio(r, Rf = rf, FUN = "StdDev")[1, 1]))
  for (p in c(0.95, 0.99)) {
    add("var", a(p, 0), as.numeric(VaR(r, p = p, method = "historical", invert = FALSE)))
    add("var", a(p, 1), as.numeric(VaR(r, p = p, method = "gaussian", invert = FALSE)))
    add("var", a(p, 2), as.numeric(VaR(r, p = p, method = "modified", invert = FALSE)))
    add("es", a(p, 0), as.numeric(ES(r, p = p, method = "historical", invert = FALSE)))
    add("es", a(p, 1), as.numeric(ES(r, p = p, method = "gaussian", invert = FALSE)))
  }
}
for (rep in 1:10) {
  n <- sample(30:100, 1); rb <- round(rnorm(n, 0.003, 0.025), 4); ra <- round(0.002 + 0.8 * rb + rnorm(n, 0, 0.015), 4)
  b <- function(p1, p2) c(p1, p2, n, ra, rb)
  rf <- c(0, 0.001)[rep %% 2 + 1]; sc <- c(12, 52, 252)[rep %% 3 + 1]
  add("beta", b(rf, 0), as.numeric(CAPM.beta(ra, rb, Rf = rf)))
  add("alpha", b(rf, 0), as.numeric(CAPM.alpha(ra, rb, Rf = rf)))
  add("te", b(sc, 0), as.numeric(TrackingError(ra, rb, scale = sc)))
  dts <- as.Date("2000-01-01") + seq_len(n); add("ir", b(sc, 0), as.numeric(InformationRatio(xts::xts(ra, dts), xts::xts(rb, dts), scale = sc)))
  mar <- c(0, 0.002)[rep %% 2 + 1]
  add("omega", b(mar, 0), as.numeric(OmegaSharpeRatio(ra, MAR = mar)))
  for (m in 0:2) for (s in 0:1) for (g in 0:1) {
    if (m > 0 && g == 1) next
    add("updown", b(m * 10 + s, g), as.numeric(UpDownRatios(ra, rb, method = c("Capture", "Number", "Percent")[m + 1], side = c("Up", "Down")[s + 1], geometric = g == 1)))
  }
}
emit("perfanalytics", "PerformanceAnalytics", list(cases))
