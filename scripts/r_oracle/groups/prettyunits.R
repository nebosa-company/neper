# prettyunits: pretty_bytes, pretty_num, pretty_ms/sec/dt and vague_dt. A vectorised case is
# (style or compact flag, values...) and answers the strings joined by "|", so the padding the
# default styles apply across the vector is part of the answer; vague_dt is scalar in R.
library(prettyunits)
set.seed(20261115)

styles <- c("default", "nopad", "6")
joined <- function(x) paste(x, collapse = "|")

bytes_pool <- c(0, 1, 5, 12, 999, 1000, 1023, 1024, 1500, 15000, 99999, 999949, 999950, 1e6, 1.5e6, 2^30, 1e9,
                3.2e10, 999950e6, 1e12, 5e15, 1e18, 1e21, 1.2e24, 1e27, 0.5, 2.5)
num_pool <- c(0, 1, 12, 999, 1000, 1500, 999949, 999950, 1e6, 123456789, 1e9, 1e12, 1e15, 1e18, 1e24, 1e26,
              0.5, 0.001, 0.0015, 1e-6, 2.5e-9, 1e-12, 1e-15, 1e-18, 1e-21, 1e-24, 1e-26, 123.456, 99.995, 9.995, 99.9951)
ms_pool <- c(0.4, 1, 999, 999.1, 1000, 1500, 59999, 59950, 60000, 61000, 3599999, 3600000, 3661001, 86399999,
             86400000, 90061001, 1e9, 2.5e10, 8.64e12, 8.64e13, 1.234e11, 5e9)
vague_pool <- c(-5, 0, 9.9, 10, 44, 45, 89, 90, 100, 150, 210, 2699, 2700, 5399, 5400, 18000, 64800, 86399,
                77760, 41 * 3600, 42 * 3600, 86400 * 29, 86400 * 30, 45 * 86400 - 1, 45 * 86400, 86400 * 100,
                86400 * 334, 335 * 86400, 365.25 * 86400 * 1.4, 365.25 * 86400 * 1.5, 365.25 * 86400 * 7.5, 1e10)

vectors <- function(pool, nvec = 40) c(lapply(pool, function(v) v),
                                       lapply(seq_len(nvec), function(i) sample(pool, sample(2:7, 1))))

num_cases <- function(fn, pool, f, flags) unlist(lapply(seq_along(flags), function(k) lapply(vectors(pool), function(v)
  case(fn, c(k - 1, v), joined(f(v, flags[[k]]))))), recursive = FALSE)

signed <- function(pool) c(pool, -pool[pool > 0][seq(1, sum(pool > 0), 2)])

vague <- unlist(lapply(1:3, function(k) lapply(vague_pool, function(s)
  case("vague", c(k - 1, s), vague_dt(as.difftime(s, units = "secs"), c("default", "short", "terse")[k])))),
  recursive = FALSE)

emit("prettyunits", "prettyunits", list(
  num_cases("bytes", signed(bytes_pool), function(v, s) pretty_bytes(v, s), styles),
  num_cases("num", signed(num_pool), function(v, s) pretty_num(v, s), styles),
  num_cases("ms", ms_pool, function(v, compact) pretty_ms(v, compact), c(FALSE, TRUE)),
  num_cases("sec", ms_pool / 1000, function(v, compact) pretty_sec(v, compact), c(FALSE, TRUE)),
  vague
))
