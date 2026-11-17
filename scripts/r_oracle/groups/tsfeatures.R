# tsfeatures: the closed-form features of one series.
#   args: (n, m, width, x[n], j) with m the frequency; fn "acf" (j 0..6) "pacf" (j 0..3) "mlshift" "mvshift" (j 0 value 1 index) and the single-valued
#   "cross" "flat" "lump" "stab" "firstmin" "firstzero" "std1st" "trev" "walker" "motif" "zeroprop" "embed1" "embed2" "ac9"
suppressMessages(library(tsfeatures))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20261128)
for (rep in 1:10) {
  n <- c(60, 80, 120, 48, 200)[(rep - 1) %% 5 + 1]; m <- c(1, 4, 12, 1, 7)[(rep - 1) %% 5 + 1]
  x0 <- as.numeric(arima.sim(list(ar = c(0.6, -0.2)), n)) + 0.03 * seq_len(n) + (if (m > 1) sin(2 * pi * seq_len(n) / m) else 0)
  if (rep %% 3 == 0) x0 <- round(x0, 1)
  x <- ts(x0, frequency = m); w <- if (m > 1) m else 10
  a <- function(j) c(n, m, w, x0, j)
  af <- acf_features(x); for (j in seq_along(af)) add("acf", a(j - 1), af[j])
  pf <- pacf_features(x); for (j in seq_along(pf)) add("pacf", a(j - 1), pf[j])
  ml <- max_level_shift(x, w); add("mlshift", a(0), ml[1]); add("mlshift", a(1), ml[2])
  mv <- max_var_shift(x, w); add("mvshift", a(0), mv[1]); add("mvshift", a(1), mv[2])
  add("cross", a(0), crossing_points(x)); add("flat", a(0), flat_spots(x)); add("lump", a(0), lumpiness(x, w)); add("stab", a(0), stability(x, w))
  add("firstmin", a(0), firstmin_ac(x0)); add("firstzero", a(0), firstzero_ac(x0)); add("std1st", a(0), std1st_der(x0)); add("trev", a(0), trev_num(x0))
  add("walker", a(0), walker_propcross(x0)); add("motif", a(0), motiftwo_entro3(x0)); add("zeroprop", a(0), zero_proportion(round(x0)))
  add("embed1", a(0), suppressWarnings(embed2_incircle(x0, boundary = 1))); add("embed2", a(0), suppressWarnings(embed2_incircle(x0, boundary = 2)))
  add("ac9", a(0), ac_9(x0))
  add("kpss", a(0), unitroot_kpss(x0))
}
emit("tsfeatures", "tsfeatures", list(cases))
