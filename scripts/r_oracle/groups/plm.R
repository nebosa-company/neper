# plm on a balanced panel: within, between and random (Swamy-Arora) estimators with their variance components.
#   args: (N, T, K, y[N*T], x[N*T*K] row-major), rows ordered by individual
#   fn: "wcoef" "wse" (weighted by position), "s2e", "bcoef" (constant first), "rcoef", "rse" (constant first), "s2mu", "theta"
suppressMessages(library(plm))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-9)
ws <- function(v) sum(v * seq_along(v))
set.seed(20261213)
for (rep in 1:24) {
  N <- sample(6:30, 1); T <- sample(3:8, 1); K <- sample(1:3, 1); n <- N * T
  id <- rep(seq_len(N), each = T); tm <- rep(seq_len(T), N)
  x <- matrix(rnorm(n * K), n) + rep(rnorm(N), each = T) * 0.5; u <- rep(rnorm(N, 0, sample(c(0.1, 1, 2), 1)), each = T)
  y <- 1 + as.vector(x %*% rnorm(K)) + u + rnorm(n)
  d <- data.frame(id, tm, y, x); names(d)[4:(3 + K)] <- paste0("x", seq_len(K))
  fm <- as.formula(paste("y ~", paste0("x", seq_len(K), collapse = " + ")))
  w <- plm(fm, d, index = c("id", "tm"), model = "within"); b <- plm(fm, d, index = c("id", "tm"), model = "between")
  r <- plm(fm, d, index = c("id", "tm"), model = "random", random.method = "swar")
  a <- c(N, T, K, y, as.vector(t(x)))
  sw <- summary(w)$coefficients; sr <- summary(r)$coefficients
  add("wcoef", a, ws(sw[, 1])); add("wse", a, ws(sw[, 2])); add("s2e", a, sum(resid(w)^2) / (n - N - K))
  add("bcoef", a, ws(coef(b))); add("rcoef", a, ws(sr[, 1])); add("rse", a, ws(sr[, 2]))
  add("s2mu", a, r$ercomp$sigma2[["id"]]); add("theta", a, as.numeric(r$ercomp$theta))
}
emit("plm", "plm", list(cases))
