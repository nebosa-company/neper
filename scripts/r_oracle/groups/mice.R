# mice: norm.nob, norm, norm.predict and pmm (method 3) after set.seed; args (n, p, m, maxit, method (0 norm.nob, 1 norm, 2 norm.predict), seed, data[n*p] column-major with NaN, idx): imp values in the order of columns with missing values, imputations, rows
suppressMessages(library(mice))
cases <- list()
set.seed(20261116)
meths <- c("norm.nob", "norm", "norm.predict", "pmm", "norm.boot")
for (rep in 1:100) {
  n <- sample(20:60, 1); p <- sample(3:5, 1); m <- sample(1:3, 1); maxit <- sample(1:4, 1); me <- (rep - 1) %% 5
  B <- matrix(rnorm(p * p), p, p); X <- round(matrix(rnorm(n * p), n, p) %*% B + 5 * rep(1, n) %o% runif(p, 1, 3), 4)
  nmc <- sample(1:min(2, p), 1); cols <- sample(p, nmc)
  for (j in cols) X[sample(n, sample(2:max(3, n %/% 5), 1)), j] <- NA
  df <- as.data.frame(X); seed <- sample(1:100000, 1)
  imp <- tryCatch(suppressWarnings(mice(df, m = m, maxit = maxit, method = meths[me + 1], seed = seed, printFlag = FALSE)), error = function(e) NULL)
  if (is.null(imp) || !is.null(imp$loggedEvents)) next
  flat <- unlist(lapply(seq_len(p), function(j) if (!is.null(imp$imp[[j]]) && nrow(imp$imp[[j]]) > 0) as.vector(as.matrix(imp$imp[[j]])) else NULL))
  xa <- ifelse(is.na(X), NaN, X)
  for (q in seq_along(flat)) cases[[length(cases) + 1]] <- case("imp", c(n, p, m, maxit, c(0, 1, 2, 3, 5)[me + 1], seed, as.vector(xa), q - 1), flat[q], rel = 1e-6, abs = 1e-8)
}
# logreg (method 4): binary 0/1 factor columns with incomplete cases, continuous predictors
for (rep in 1:40) {
  n <- sample(40:100, 1); pc <- sample(2:3, 1); m <- sample(1:3, 1); maxit <- sample(1:3, 1)
  X <- matrix(round(rnorm(n * pc), 4), n, pc); lin <- X[, 1] - 0.5 * X[, 2] + rnorm(n, 0, 0.7); yb <- as.numeric(lin > 0)
  df <- as.data.frame(X); df$B <- factor(yb); df <- df[, c(ncol(df), seq_len(pc))]
  miss <- sample(n, sample(4:max(5, n %/% 6), 1)); df$B[miss] <- NA
  if (rep %% 2 == 0) { mc <- sample(n, 5); df$V1[mc] <- NA }
  seed <- sample(1:100000, 1)
  meth <- c("logreg", if (rep %% 2 == 0) "norm.nob" else NULL, rep("", pc - (rep %% 2 == 0))); meth <- c("logreg", rep("", pc)); if (rep %% 2 == 0) meth[2] <- "norm.nob"
  imp <- tryCatch(suppressWarnings(mice(df, m = m, maxit = maxit, method = meth, seed = seed, printFlag = FALSE)), error = function(e) NULL)
  if (is.null(imp) || !is.null(imp$loggedEvents)) next
  flat <- unlist(lapply(seq_len(ncol(df)), function(j) if (!is.null(imp$imp[[j]]) && nrow(imp$imp[[j]]) > 0) { v <- imp$imp[[j]]; as.vector(as.matrix(as.data.frame(lapply(v, function(cc) as.numeric(as.character(cc)))))) } else NULL))
  num <- data.frame(B = yb, X); num <- num[, c("B", paste0("X", seq_len(pc)))]; num[miss, "B"] <- NA; names(num) <- names(df)
  if (rep %% 2 == 0) num$V1[mc] <- NA
  xa <- as.matrix(num); xa[is.na(xa)] <- NaN
  for (q in seq_along(flat)) cases[[length(cases) + 1]] <- case("imp", c(n, ncol(df), m, maxit, 4, seed, as.vector(xa), q - 1), flat[q], rel = 1e-5, abs = 1e-7)
}
# pool.scalar ("pool": (m, n, Q[m], U[m], field): qbar ubar b t df r fmi); n = Inf is the large-sample df
for (rep in 1:60) {
  m <- sample(2:12, 1); qs <- round(rnorm(m, 1, 0.3), 4); us <- round(runif(m, 0.05, 0.5), 4); nn <- c(Inf, 25, 60, 200)[sample(4, 1)]
  r <- pool.scalar(qs, us, n = nn, k = 1); vals <- c(r$qbar, r$ubar, r$b, r$t, r$df, r$r, r$fmi)
  for (f in 0:6) cases[[length(cases) + 1]] <- case("pool", c(m, nn, qs, us, f), vals[f + 1], rel = 1e-9, abs = 1e-10)
}
emit("mice", "mice", list(cases))
