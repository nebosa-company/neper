# MuMIn: AICc, Akaike weights and the full model average of linear-model coefficients.
#   args: (n, m, p, then per model: k, loglik, then est and se of each of the p coefficients, 0 when absent)   fn "aicc" "w" "est" "se"
#   outputs weighted sums over models (aicc, w) or over coefficients (est, se)
suppressMessages(library(MuMIn))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261223)
for (rep in 1:12) {
  n <- sample(25:80, 1); d <- data.frame(y = rnorm(n), a = rnorm(n), b = rnorm(n), c = rnorm(n)); d$y <- d$y + 0.5 * d$a
  forms <- list(y ~ 1, y ~ a, y ~ a + b, y ~ a + b + c, y ~ b + c)
  mods <- lapply(forms, function(f) lm(f, d)); nm <- c("(Intercept)", "a", "b", "c")
  ic <- sapply(mods, function(m) AICc(m)); w <- as.numeric(Weights(ic))
  th <- sapply(mods, function(m) sapply(nm, function(z) if (z %in% names(coef(m))) coef(m)[[z]] else 0))
  se <- sapply(mods, function(m) sapply(nm, function(z) if (z %in% names(coef(m))) summary(m)$coefficients[z, 2] else 0))
  ma <- model.avg(mods); cf <- summary(ma)$coefmat.full
  per <- unlist(lapply(seq_along(mods), function(i) c(length(coef(mods[[i]])) + 1, as.numeric(logLik(mods[[i]])), as.vector(rbind(th[, i], se[, i])))))
  a <- c(n, length(mods), length(nm), per)
  add("aicc", a, sum(ic * seq_along(ic))); add("w", a, sum(w * seq_along(w)))
  add("est", a, sum(cf[nm, 1] * seq_along(nm))); add("se", a, sum(cf[nm, 2] * seq_along(nm)))
  add("ase", a, sum(cf[nm, 3] * seq_along(nm)))
}
for (rep in 1:12) {
  n <- sample(25:80, 1); d <- data.frame(y = rnorm(n), a = rnorm(n), b = rnorm(n), c = rnorm(n)); d$y <- d$y + 0.5 * d$a
  forms <- list(y ~ 1, y ~ a, y ~ a + b, y ~ a + b + c, y ~ b + c)
  mods <- lapply(forms, function(f) lm(f, d)); nm <- c("(Intercept)", "a", "b", "c")
  ic <- sapply(mods, function(m) AICc(m))
  th <- sapply(mods, function(m) sapply(nm, function(z) if (z %in% names(coef(m))) coef(m)[[z]] else 0))
  se <- sapply(mods, function(m) sapply(nm, function(z) if (z %in% names(coef(m))) summary(m)$coefficients[z, 2] else 0))
  ma <- model.avg(mods); cs <- summary(ma)$coefmat.subset; im <- sw(ma)
  per <- unlist(lapply(seq_along(mods), function(i) c(length(coef(mods[[i]])) + 1, as.numeric(logLik(mods[[i]])), as.vector(rbind(th[, i], se[, i])))))
  a <- c(n, length(mods), length(nm), per)
  add("cest", a, sum(cs[nm, 1] * seq_along(nm))); add("cse", a, sum(cs[nm, 2] * seq_along(nm)))
  add("case", a, sum(cs[nm, 3] * seq_along(nm)))
  add("imp", a, sum(as.numeric(im[nm[-1]]) * seq_along(nm[-1])))
}
# QAIC and QAICc of a Poisson glm: "qaic" (loglik, k, n, chat, corrected)
for (rep in 1:30) {
  n <- sample(15:80, 1); x <- rnorm(n); y <- rpois(n, exp(0.3 * x)); m <- glm(y ~ x, poisson); ch <- runif(1, 1, 3); ll <- logLik(m)
  add("qaic", c(as.numeric(ll), attr(ll, "df"), n, ch, 0), QAIC(m, chat = ch)); add("qaic", c(as.numeric(ll), attr(ll, "df"), n, ch, 1), QAICc(m, chat = ch))
}
emit("mumin", "MuMIn", list(cases))
