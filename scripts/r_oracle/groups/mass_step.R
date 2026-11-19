# MASS: stepAIC on lm with single-column terms. Args: (n, p, direction 0 both 1 backward 2 forward, startfull, x row-major n * p, y[n], stat 0 final AIC 1 sum(2^(j-1) * in-model))
suppressMessages(library(MASS))
cases <- list()
set.seed(20262382)
for (rep in 1:60) {
  n <- sample(40:100, 1); p <- sample(4:8, 1); X <- matrix(rnorm(n * p), n, p); colnames(X) <- paste0("X", 1:p)
  b <- c(rnorm(3, 0, 1), rep(0, p - 3))[sample(p)]; y <- 1 + as.vector(X %*% b) + rnorm(n, 0, 1.5)
  d <- data.frame(y = y, X); dir <- c("both", "backward", "forward")[rep %% 3 + 1]
  full <- if (dir == "forward") FALSE else (rep %% 2 == 0)
  if (dir == "backward") full <- TRUE
  f0 <- if (full) lm(y ~ ., data = d) else lm(y ~ 1, data = d)
  up <- as.formula(paste("~", paste(colnames(X), collapse = " + ")))
  r <- tryCatch(stepAIC(f0, scope = list(lower = ~1, upper = up), direction = dir, trace = 0), error = function(e) NULL)
  if (is.null(r)) next
  inm <- as.numeric(colnames(X) %in% attr(terms(r), "term.labels"))
  a <- c(n, p, match(dir, c("both", "backward", "forward")) - 1, as.numeric(full), as.vector(t(X)), y)
  cases[[length(cases) + 1]] <- case("step", c(a, 0), extractAIC(r)[2], rel = 1e-9, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("step", c(a, 1), sum(2^(seq_len(p) - 1) * inm), rel = 0, abs = 0)
}
emit("mass_step", "MASS", list(cases))
