# quantreg anova.rq; args (n, p, tau, mode, drop, y..., X...) with X the n x (p-1) covariates (the intercept is added)
#   drop: bit mask over the covariates dropped by the reduced model (bit k = covariate k + 1)
#   mode = 100 kind + 4 row + i with i = 0..3 the ndf, ddf, F value and p value of: kind 0 test Wald (nid), 1 test rank, 2 test rank with iid = FALSE,
#   3 equality of slopes over tau = 0.25, 0.5, 0.75 (joint, row 0), 4 the same slope by slope (row = slope - 1)
suppressMessages(library(quantreg))
cases <- list()
set.seed(20261123)
for (rep in 1:8) {
  n <- sample(30:60, 1); p <- sample(3:4, 1)
  X <- matrix(round(rnorm(n * (p - 1)), 3), n, p - 1)
  y <- round(1 + X %*% c(1, 0.5, 0.3)[seq_len(p - 1)] + rt(n, 3), 3)
  df <- data.frame(y = y, X); names(df) <- c("y", paste0("x", seq_len(p - 1)))
  mask <- sample(1:(2^(p - 1) - 1), 1)
  dropped <- which(bitwAnd(mask, 2^(0:(p - 2))) > 0)
  keep <- setdiff(seq_len(p - 1), dropped)
  f_full <- as.formula(paste("y ~", paste0("x", seq_len(p - 1), collapse = "+")))
  f_red <- as.formula(paste("y ~", if (length(keep)) paste0("x", keep, collapse = "+") else "1"))
  add <- function(kind, tau, tab) for (r in seq_len(nrow(tab))) for (i in 1:4) cases[[length(cases) + 1]] <<- case("rq", c(n, p, tau, 100 * kind + 4 * (r - 1) + i - 1, mask, y, X), tab[r, i], rel = 1e-9, abs = 1e-12)
  for (tau in c(0.25, 0.5)) {
    f1 <- rq(f_full, tau = tau, data = df); f0 <- rq(f_red, tau = tau, data = df)
    add(0, tau, suppressWarnings(anova(f1, f0))$table)
    add(1, tau, suppressWarnings(anova(f1, f0, test = "rank"))$table)
    add(2, tau, suppressWarnings(anova(f1, f0, test = "rank", iid = FALSE))$table)
  }
  fs <- lapply(c(0.25, 0.5, 0.75), function(t) rq(f_full, tau = t, data = df))
  add(3, 0.5, suppressWarnings(anova(fs[[1]], fs[[2]], fs[[3]]))$table)
  add(4, 0.5, suppressWarnings(anova(fs[[1]], fs[[2]], fs[[3]], joint = FALSE))$table)
}
emit("quantreg_anova", "quantreg", list(cases))
