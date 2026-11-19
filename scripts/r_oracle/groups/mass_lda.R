# MASS lda, qda, their CV and predict methods.
#   "lda" / "qda" (seed, n, p, ng, method 0 moment 1 mle 2 mve 3 t, tol, nu, use.prior, m, dimen, mode, prior[ng], prior2[ng], X[n p], g[n] 0-based, Xnew[m p])
#   lda modes 0 scaling, 1 svd, 2 means, 3 prior, 4 counts, 5 rank, 6 CV posterior, 7 CV class (1-based); 10 + 3 * pm + w with pm 0 plug-in 1 predictive 2 debiased
#     and w 0 posterior, 1 class (1-based), 2 LD scores, of predict(fit, Xnew, prior = prior2, dimen)
#   qda modes 0 scaling array, 1 ldet, 2 means, 3 prior, 4 counts, 6 CV posterior, 7 CV class; 10 + 3 * pm + w with pm 0 plug-in 1 predictive 2 debiased (w 0 posterior, 1 class)
#     of predict(fit, Xnew, prior = prior2); 20, 21 the looCV posterior and class on the training data
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-8, abs = 1e-9) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(seq_along(v) * as.numeric(v))
quiet <- function(expr) { r <- NULL; invisible(capture.output(r <- suppressWarnings(expr))); r }
set.seed(20262406)
pmn <- c("plug-in", "predictive", "debiased")
for (rep in 1:15) {
  ng <- sample(2:4, 1); p <- sample(2:4, 1); n <- sample(c(30, 45, 60), 1); m <- 6
  g <- sample(0:(ng - 1), n, TRUE); g[1:(2 * ng)] <- rep(0:(ng - 1), 2)
  shift <- matrix(rnorm(ng * p, 0, 1.5), ng, p)
  X <- shift[g + 1, ] + matrix(rnorm(n * p), n, p) %*% matrix(rnorm(p * p, 0, 0.5) + diag(p), p)
  Xn <- matrix(rnorm(m * p, 0, 1.5), m, p)
  method <- c(0, 1, 0, 2, 3)[rep %% 5 + 1]; nu <- 5; tol <- 1e-4
  cnt <- as.vector(table(factor(g, levels = 0:(ng - 1)))); use.prior <- as.numeric(rep %% 3 == 0)
  pr <- if (use.prior == 1) { v <- runif(ng, 0.5, 2); v / sum(v) } else cnt / n
  pr2 <- { v <- runif(ng, 0.5, 2); v / sum(v) }; dimen <- sample(1:(min(p, ng - 1)), 1)
  mname <- c("moment", "mle", "mve", "t")[method + 1]; gf <- factor(g, levels = 0:(ng - 1)); seed <- sample(1:1000000, 1)
  a <- c(seed, n, p, ng, method, tol, nu, use.prior, m, dimen); tail <- c(pr, pr2, as.vector(X), g, as.vector(Xn))
  set.seed(seed)
  f <- tryCatch(quiet(if (use.prior == 1) lda(X, gf, prior = pr, tol = tol, method = mname, nu = nu) else lda(X, gf, tol = tol, method = mname, nu = nu)), error = function(e) NULL)
  if (!is.null(f)) {
    add("lda", c(a, 0, tail), wsum(f$scaling)); add("lda", c(a, 1, tail), wsum(f$svd)); add("lda", c(a, 2, tail), wsum(f$means))
    add("lda", c(a, 3, tail), wsum(f$prior)); add("lda", c(a, 4, tail), wsum(f$counts)); add("lda", c(a, 5, tail), length(f$svd), 0, 0)
    for (pm in 0:2) {
      pp <- tryCatch(predict(f, Xn, prior = pr2, dimen = dimen, method = pmn[pm + 1]), error = function(e) NULL)
      if (is.null(pp)) next
      add("lda", c(a, 10 + 3 * pm, tail), wsum(pp$posterior)); add("lda", c(a, 11 + 3 * pm, tail), wsum(as.integer(pp$class)), 0, 0)
      add("lda", c(a, 12 + 3 * pm, tail), wsum(pp$x))
    }
  }
  if (method <= 1) {
    set.seed(seed)
    cv <- tryCatch(quiet(if (use.prior == 1) lda(X, gf, prior = pr, tol = tol, method = mname, CV = TRUE) else lda(X, gf, tol = tol, method = mname, CV = TRUE)), error = function(e) NULL)
    if (!is.null(cv)) { add("lda", c(a, 6, tail), wsum(cv$posterior)); add("lda", c(a, 7, tail), wsum(as.integer(cv$class)), 0, 0) }
  }
}
for (rep in 1:15) {
  ng <- sample(2:3, 1); p <- sample(2:3, 1); n <- sample(c(36, 54, 72), 1); m <- 6
  g <- sample(0:(ng - 1), n, TRUE); g[1:(6 * ng)] <- rep(0:(ng - 1), 6)
  shift <- matrix(rnorm(ng * p, 0, 1.5), ng, p)
  X <- shift[g + 1, ] + matrix(rnorm(n * p), n, p) * (1 + g %% 2)
  Xn <- matrix(rnorm(m * p, 0, 1.5), m, p)
  method <- c(0, 1, 0, 2, 3)[rep %% 5 + 1]; nu <- 5
  cnt <- as.vector(table(factor(g, levels = 0:(ng - 1)))); use.prior <- as.numeric(rep %% 3 == 0)
  pr <- if (use.prior == 1) { v <- runif(ng, 0.5, 2); v / sum(v) } else cnt / n
  pr2 <- { v <- runif(ng, 0.5, 2); v / sum(v) }
  mname <- c("moment", "mle", "mve", "t")[method + 1]; gf <- factor(g, levels = 0:(ng - 1)); seed <- sample(1:1000000, 1)
  a <- c(seed, n, p, ng, method, 0, nu, use.prior, m, 0); tail <- c(pr, pr2, as.vector(X), g, as.vector(Xn))
  set.seed(seed)
  f <- tryCatch(quiet(if (use.prior == 1) qda(X, gf, prior = pr, method = mname, nu = nu) else qda(X, gf, method = mname, nu = nu)), error = function(e) NULL)
  if (!is.null(f)) {
    add("qda", c(a, 0, tail), wsum(f$scaling)); add("qda", c(a, 1, tail), wsum(f$ldet)); add("qda", c(a, 2, tail), wsum(f$means))
    add("qda", c(a, 3, tail), wsum(f$prior)); add("qda", c(a, 4, tail), wsum(f$counts))
    for (pm in 0:2) {
      pp <- tryCatch(predict(f, Xn, prior = pr2, method = pmn[pm + 1]), error = function(e) NULL)
      if (is.null(pp)) next
      add("qda", c(a, 10 + 3 * pm, tail), wsum(pp$posterior)); add("qda", c(a, 11 + 3 * pm, tail), wsum(as.integer(pp$class)), 0, 0)
    }
    if (method <= 1) {
      pl <- tryCatch(predict(f, method = "looCV"), error = function(e) NULL)
      if (!is.null(pl)) { add("qda", c(a, 20, tail), wsum(pl$posterior)); add("qda", c(a, 21, tail), wsum(as.integer(pl$class)), 0, 0) }
    }
  }
  if (method <= 1) {
    cv <- tryCatch(quiet(if (use.prior == 1) qda(X, gf, prior = pr, method = mname, CV = TRUE) else qda(X, gf, method = mname, CV = TRUE)), error = function(e) NULL)
    if (!is.null(cv)) { add("qda", c(a, 6, tail), wsum(cv$posterior)); add("qda", c(a, 7, tail), wsum(as.integer(cv$class)), 0, 0) }
  }
}
emit("mass_lda", "MASS", list(cases))
