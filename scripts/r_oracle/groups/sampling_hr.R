# sampling: Hajekstrata and rhg. "hs" args (n, ns, mean, y[n], pik[n], strata[n], N[ns]); "rh" args (n, c, i, status[n], sel[n * c] row-major): prob_resp of unit i
suppressMessages(library(sampling))
cases <- list()
set.seed(20262350)
for (rep in 1:30) {
  ns <- sample(2:4, 1); n <- sample(8:30, 1); st <- c(1:ns, sample(1:ns, n - ns, TRUE)); y <- round(rnorm(n, 10, 3), 3); pik <- round(runif(n, 0.1, 0.9), 3)
  N <- sample(30:100, ns); mean <- rep %% 2
  r <- Hajekstrata(y, pik, st, N, type = if (mean == 1) "mean" else "total")
  cases[[length(cases) + 1]] <- case("hs", c(n, ns, mean, y, pik, st, N), r, rel = 1e-10, abs = 1e-12)
}
for (rep in 1:30) {
  n <- sample(8:30, 1); cc <- 2
  sel <- matrix(sample(1:3, n * cc, TRUE), n, cc, dimnames = list(NULL, paste0("v", 1:cc))); status <- rbinom(n, 1, 0.7)
  X <- data.frame(ID_unit = 1:n, status = status, sel)
  r <- rhg(X, paste0("v", 1:cc))$prob_resp
  for (i in sample(n, min(n, 4))) cases[[length(cases) + 1]] <- case("rh", c(n, cc, i, status, as.vector(t(sel))), r[i], rel = 1e-12, abs = 1e-12)
}
emit("sampling_hr", "sampling", list(cases))
