# boot: studentized intervals of the mean and abc.ci of the weighted mean and variance.
#   stud: (seed, R, conf, n, x...) fn "stud_lo", "stud_hi";  abc: (kind 0 mean 1 variance, conf, n, x...) fn "abc_lo", "abc_hi"
suppressMessages(library(boot))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261118)
xs <- list(round(rnorm(25, 10, 3), 3), round(rexp(18) * 4, 3), round(runif(40, 0, 50), 2), round(rnorm(12), 3), round(rexp(60), 3))
for (x in xs) {
  for (R in c(99, 199, 499)) for (conf in c(0.9, 0.95, 0.99)) {
    seed <- sample(1:1e6, 1); set.seed(seed)
    b <- boot(x, function(d, i) c(mean(d[i]), var(d[i]) / length(i)), R)
    ci <- tryCatch(suppressWarnings(boot.ci(b, conf = conf, type = "stud")), error = function(e) NULL)
    if (is.null(ci)) next
    a <- c(seed, R, conf, length(x), x)
    add("stud_lo", a, ci$student[4]); add("stud_hi", a, ci$student[5])
  }
  for (conf in c(0.9, 0.95, 0.99)) {
    r <- abc.ci(x, function(d, w) sum(d * w) / sum(w), conf = conf)
    a <- c(0, conf, length(x), x); add("abc_lo", a, r[2]); add("abc_hi", a, r[3])
    r <- abc.ci(x, function(d, w) { m <- sum(d * w) / sum(w); sum(w * (d - m)^2) / sum(w) }, conf = conf)
    a <- c(1, conf, length(x), x); add("abc_lo", a, r[2]); add("abc_hi", a, r[3])
  }
}
# boot(sim = "antithetic", L = given): (seed, stat, R, n, x..., L...) fn "anti_t0", "anti_t" (position), "anti_tsum", "anti_idx" (row-major position)
for (x in xs) for (st in 0:3) for (R in c(20, 21, 60)) {
  Lv <- round(rnorm(length(x)), 5)
  seed <- sample(1:1e6, 1); set.seed(seed)
  fsi <- list(function(d, i) mean(d[i]), function(d, i) median(d[i]), function(d, i) sd(d[i]), function(d, i) var(d[i]))
  b <- boot(x, fsi[[st + 1]], R, sim = "antithetic", L = Lv)
  a <- c(seed, st, R, length(x), x, Lv)
  add("anti_t0", a, b$t0)
  for (i in c(1, 2, R %/% 2, R)) add("anti_t", c(a, i - 1), b$t[i, 1])
  add("anti_tsum", a, sum(b$t))
  ba <- boot.array(b, indices = TRUE)
  for (i in c(1, R %/% 2 + 1, R)) add("anti_idx", c(a, (i - 1) * length(x) + 1), ba[i, 2])
}
# censboot(sim = "ordinary"): the statistic of the sorted resample of a (time, status) matrix; (seed, stat, R, n, x...) fn "cens_t0", "cens_t", "cens_tsum"
for (x in xs) for (st in 0:3) for (R in c(19, 99)) {
  seed <- sample(1:1e6, 1); set.seed(seed)
  fcs <- list(function(d) mean(d[, 1]), function(d) median(d[, 1]), function(d) sd(d[, 1]), function(d) var(d[, 1]))
  dat <- cbind(x, rbinom(length(x), 1, 0.7)); set.seed(seed)
  b <- censboot(dat, fcs[[st + 1]], R)
  a <- c(seed, st, R, length(x), x)
  add("cens_t0", a, b$t0)
  for (i in c(1, 2, R %/% 2, R)) add("cens_t", c(a, i - 1), b$t[i, 1])
  add("cens_tsum", a, sum(b$t))
}
# censboot(sim = "weird"): (seed, stat, R, n, x..., status...) fn "weird_t0", "weird_t", "weird_tsum"
library(survival)
for (x in xs) for (st in 0:3) for (R in c(19, 99)) {
  seed <- sample(1:1e6, 1); set.seed(seed)
  fcs <- list(function(d) mean(d[, 1]), function(d) median(d[, 1]), function(d) sd(d[, 1]), function(d) var(d[, 1]))
  sv <- rbinom(length(x), 1, 0.7); if (sum(sv) == 0) next; dat <- cbind(x, sv); F <- survfit(Surv(x, sv) ~ 1); set.seed(seed)
  b <- censboot(dat, fcs[[st + 1]], R, F.surv = F, sim = "weird")
  a <- c(seed, st, R, length(x), x, sv)
  add("weird_t0", a, b$t0)
  for (i in c(1, 2, R %/% 2, R)) add("weird_t", c(a, i - 1), b$t[i, 1])
  add("weird_tsum", a, sum(b$t))
}
emit("boot3", "boot", list(cases))
