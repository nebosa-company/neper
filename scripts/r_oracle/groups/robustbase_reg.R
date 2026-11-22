# robustbase regression: glmrob (Mqle).
#   "glmrob" args (fam 1 binomial / 2 poisson, hat 0/1, tcc, n, p, X[n*p] row-major, y[n], ni[n], which, idx)
#   which 0 coefficient idx, 1 iterations, 2 cov entry idx (row-major), 3 robustness weight w.r idx
suppressMessages(library(robustbase))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)

glm_cases <- function(fam, hat, tcc, X, y, ni, r) {
  n <- nrow(X); p <- ncol(X); a0 <- c(fam, hat, tcc, n, p, as.vector(t(X)), y, ni)
  for (j in seq_len(p)) add("glmrob", c(a0, 0, j - 1), r$coefficients[j])
  add("glmrob", c(a0, 1, 0), r$iter)
  for (k in seq_len(p * p)) add("glmrob", c(a0, 2, k - 1), as.vector(t(r$cov))[k])
  for (i in sample(n, min(n, 4))) add("glmrob", c(a0, 3, i - 1), r$w.r[i])
}

set.seed(20261301)
for (rep in 1:24) {
  n <- sample(25:70, 1); p <- sample(2:3, 1)
  Z <- matrix(round(rnorm(n * (p - 1)), 3), n, p - 1); X <- cbind(1, Z)
  beta <- round(rnorm(p, 0, 0.8), 2)
  tcc <- c(1.345, 1.345, 1.0, 2.0)[1 + rep %% 4]; hat <- as.integer(rep %% 3 == 0)
  wx <- if (hat) "hat" else "none"
  if (rep %% 2 == 0) {
    # binomial: 0/1 responses (ni = 1) and, every fourth, grouped responses
    if (rep %% 4 == 0) {
      ni <- sample(2:6, n, TRUE); pr <- plogis(X %*% beta); s <- rbinom(n, ni, pr)
      s[sample(n, 3)] <- ni[sample(n, 3)] - s[sample(n, 3)]
      df <- data.frame(s = s, f = ni - s, Z); colnames(df)[3:(2 + p - 1)] <- paste0("z", seq_len(p - 1))
      fo <- as.formula(paste("cbind(s, f) ~", paste(colnames(df)[3:ncol(df)], collapse = "+")))
      r <- tryCatch(suppressWarnings(glmrob(fo, family = binomial, data = df, weights.on.x = wx, control = glmrobMqle.control(tcc = tcc))), error = function(e) NULL)
      y <- s / ni
    } else {
      ni <- rep(1, n); y <- rbinom(n, 1, plogis(X %*% beta)); y[sample(n, 3)] <- 1 - y[sample(n, 3)]
      df <- data.frame(y = y, Z); colnames(df)[2:ncol(df)] <- paste0("z", seq_len(p - 1))
      fo <- as.formula(paste("y ~", paste(colnames(df)[-1], collapse = "+")))
      r <- tryCatch(suppressWarnings(glmrob(fo, family = binomial, data = df, weights.on.x = wx, control = glmrobMqle.control(tcc = tcc))), error = function(e) NULL)
    }
    fam <- 1
  } else {
    y <- rpois(n, exp(0.5 + X %*% beta * 0.5)); y[sample(n, 2)] <- y[sample(n, 2)] + 15
    ni <- rep(1, n); df <- data.frame(y = y, Z); colnames(df)[2:ncol(df)] <- paste0("z", seq_len(p - 1))
    fo <- as.formula(paste("y ~", paste(colnames(df)[-1], collapse = "+")))
    r <- tryCatch(suppressWarnings(glmrob(fo, family = poisson, data = df, weights.on.x = wx, control = glmrobMqle.control(tcc = tcc))), error = function(e) NULL)
    fam <- 2
  }
  if (is.null(r) || !isTRUE(r$converged)) next
  glm_cases(fam, hat, tcc, X, as.numeric(y), ni, r)
}
# nlrob(method "M", doCov = TRUE): "nlrob" args (model 1 a*exp(b*x) / 2 a*x/(b+x) / 3 a+b*exp(-c*x), np, cc, n, x[n], y[n], start[np], which, idx)
#   which 0 coefficient idx, 1 Scale, 2 iterations, 3 cov entry idx (row-major), 4 robustness weight idx, 5 working residual idx
set.seed(20261302)
# model 4 is a/(1+b*x*x); the exp models 1 and 3 are compared at 1e-4: R exp differs from a correctly rounded one by an ulp in about 1 of 3000 arguments, and the forward-difference gradient (step 1.5e-8) turns that into 1e-8..1e-5 in the fit (the exp-free models 2 and 4 agree at 1e-9)
for (rep in 1:48) {
  m <- 1 + (rep - 1) %% 4; n <- sample(20:50, 1); x <- if (m == 2) round(runif(n, 0.2, 5), 3) else round(runif(n, 0, 2), 3)
  tr <- list(c(1.5, 0.8), c(4, 1.2), c(1, 2, 1.3), c(3, 1.5))[[m]]; np <- length(tr)
  mu <- switch(m, tr[1] * exp(tr[2] * x), tr[1] * x / (tr[2] + x), tr[1] + tr[2] * exp(-tr[3] * x), tr[1] / (1 + tr[2] * x * x))
  tl <- if (m %in% c(1, 3)) 1e-5 else 1e-9
  y <- round(mu + rnorm(n, 0, 0.15), 4); o <- sample(n, max(2, n %/% 10)); y[o] <- y[o] + sample(c(-1, 1), length(o), TRUE) * runif(length(o), 1, 3)
  st <- tr * (1 + c(0.15, -0.1, 0.1)[seq_len(np)]); cc <- c(1.345, 1.345, 1.0, 2.0)[1 + (rep %/% 4) %% 4]
  df <- data.frame(x = x, y = y)
  fo <- switch(m, y ~ p1 * exp(p2 * x), y ~ p1 * x / (p2 + x), y ~ p1 + p2 * exp(-p3 * x), y ~ p1 / (1 + p2 * x * x))
  sl <- as.list(setNames(st, paste0("p", seq_len(np))))
  r <- tryCatch(suppressWarnings(nlrob(fo, data = df, start = sl, psi = robustbase:::.Mwgt.psi1("huber", cc = cc), doCov = TRUE)), error = function(e) NULL)
  if (is.null(r) || !identical(r$status, "converged")) next
  a0 <- c(m, np, cc, n, x, y, st)
  for (j in 1:np) add("nlrob", c(a0, 0, j - 1), unname(r$coefficients[j]), tl)
  add("nlrob", c(a0, 1, 0), r$Scale, tl); add("nlrob", c(a0, 2, 0), r$iter)
  for (k in 1:(np * np)) add("nlrob", c(a0, 3, k - 1), as.vector(t(r$cov))[k], tl)
  for (i in sample(n, 4)) { add("nlrob", c(a0, 4, i - 1), r$rweights[i], tl); add("nlrob", c(a0, 5, i - 1), r$working.residuals[i], tl) }
}
emit("robustbase_reg", "robustbase", list(cases))
