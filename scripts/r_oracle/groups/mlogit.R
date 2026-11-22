# mlogit: conditional, multinomial, nested, heteroskedastic and mixed logit, tests and predictions.
#   Data: set.seed(s); x = rnorm(n J kx) chooser-major, then alternative, then covariate; z = rnorm(n kz) chooser-major.
#   The design is R's model.matrix: the constants of alternatives 2..J (asc), x1..xkx, then for each z the alternatives 2..J.
#   args: (s, n, J, kx, kz, asc, ne, extra[ne], choice[n] 0-based); a vector answer is weighted by position.
#   R is run to its optimum (ftol = 0, tol = 1e-20), so the comparisons are 1e-9 relative.
suppressMessages({library(mlogit); library(dfidx)})
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(v))
gen <- function(s, n, J, kx, kz, T = 1) {
  set.seed(s); xv <- rnorm(n * J * kx); zv <- rnorm(n * kz)
  d <- data.frame(chid = rep(1:n, each = J), id = rep((0:(n - 1)) %/% T + 1, each = J), alt = factor(rep(1:J, n)))
  for (c in seq_len(kx)) d[[paste0("x", c)]] <- xv[seq(c, by = kx, length.out = n * J)]
  for (l in seq_len(kz)) d[[paste0("z", l)]] <- rep(zv[seq(l, by = kz, length.out = n)], each = J)
  d
}
fml <- function(kx, kz, asc, drop = 0) {
  r1 <- if (kx - drop > 0) paste(paste0("x", 1:(kx - drop)), collapse = " + ") else "0"
  r2 <- c(if (!asc) "0", if (kz) paste0("z", 1:kz))
  as.formula(paste("choice ~", r1, if (length(r2)) paste("|", paste(r2, collapse = " + ")) else ""))
}
# systematic utilities n x J from constants a0, x coefficients b and z coefficients g (kz x J, first column 0)
util <- function(d, n, J, kx, kz, a0, b, g) {
  V <- matrix(a0, n, J, byrow = TRUE)
  for (c in seq_len(kx)) V <- V + b[c] * matrix(d[[paste0("x", c)]], n, J, byrow = TRUE)
  for (l in seq_len(kz)) V <- V + outer(d[[paste0("z", l)]][seq(1, by = J, length.out = n)], g[l, ])
  V
}
gumbel <- function(n, J) matrix(-log(-log(runif(n * J))), n)
withch <- function(d, ch, J) { d$choice <- as.vector(t(outer(ch, 1:J, "=="))); d }
# scoretest and predict re-evaluate the call outside this frame: the call carries a global data set and literal arguments
fit <- function(fm, m, ...) {
  assign("m_fit", m, globalenv())
  f <- tryCatch(suppressWarnings(do.call("mlogit", c(list(fm, quote(m_fit)), list(...), list(tol = 1e-20, ftol = 0, iterlim = 2000)))), error = function(e) NULL)
  # a fit whose line search gave up short of the optimum (mlogit's code 3 with a large gradient) is no answer to compare with
  if (is.null(f) || is.null(tryCatch(vcov(f), error = function(e) NULL)) || max(abs(colSums(f$gradient))) > 1e-6) NULL else f
}
good <- function(ch, J) all(tabulate(ch, J) >= 3)

# conditional / multinomial logit: coef se ll wald wald_p shares effects lrt lrt_p score score_p pred; extras (s2, n2) for pred (newdata from gen(s2, n2, ...))
# every rep reseeds the parameter stream: gen() and the mixed logit (seed = 10) reset it
for (rep in 1:24) {
  set.seed(20270100 + rep); ty <- rep %% 4; n <- sample(80:200, 1); J <- sample(3:5, 1)
  kx <- if (ty == 2) 0 else sample(1:3, 1); kz <- if (ty >= 2) sample(1:2, 1) else 0; asc <- as.numeric(ty != 0)
  b <- rnorm(kx, 0, 0.8); a0 <- c(0, rnorm(J - 1, 0, 0.4)) * asc; g <- if (kz) cbind(0, matrix(rnorm(kz * (J - 1), 0, 0.7), kz))
  s <- sample.int(1e6, 1); s2 <- sample.int(1e6, 1); n2 <- sample(5:12, 1)
  d <- gen(s, n, J, kx, kz); ch <- apply(util(d, n, J, kx, kz, a0, b, g) + gumbel(n, J), 1, which.max)
  if (!good(ch, J)) next
  m <- dfidx(withch(d, ch, J), idx = c("chid", "alt"))
  f <- fit(fml(kx, kz, asc), m); if (is.null(f)) next
  cf <- coef(f); q <- length(cf); a <- c(s, n, J, kx, kz, asc, 0, ch - 1)
  add("coef", a, ws(cf)); add("se", a, ws(sqrt(diag(vcov(f))))); add("ll", a, as.numeric(logLik(f)))
  sel <- if (q >= 2) c(q - 1, q) else q
  wv <- as.numeric(t(cf[sel]) %*% solve(vcov(f)[sel, sel, drop = FALSE]) %*% cf[sel])
  add("wald", a, wv); add("wald_p", a, pchisq(wv, length(sel), lower.tail = FALSE))
  add("shares", a, ws(colMeans(fitted(f, outcome = FALSE))))
  # the rows and columns of the effects sum to zero, so the weights grow with the square of the position; mlogit's forward difference (step 1e-5) of the probabilities
  # magnifies their rounding 1e5 times, hence 1e-8
  if (kx >= 1) { ef <- as.vector(t(effects(f, covariate = "x1"))); add("effects", a, sum(ef * seq_along(ef)^2), rel = 1e-8) }
  if (kx >= 2) {
    f0 <- fit(fml(kx, kz, asc, 1), m)
    if (!is.null(f0)) {
      lr <- lmtest::lrtest(f0, f); add("lrt", a, lr$Chisq[2]); add("lrt_p", a, lr$`Pr(>Chisq)`[2])
      sc <- scoretest(f0, fml(kx, kz, asc)); add("score", a, as.numeric(sc$statistic)); add("score_p", a, sc$p.value)
    }
  }
  d2 <- gen(s2, n2, J, kx, kz); d2$choice <- rep(c(TRUE, rep(FALSE, J - 1)), n2)
  p2 <- predict(f, newdata = dfidx(d2, idx = c("chid", "alt")))
  add("pred", c(s, n, J, kx, kz, asc, 2, s2, n2, ch - 1), ws(as.vector(t(p2))))
}

# nested logit (every nest of two or more alternatives): nl_coef (covariates then iv) nl_se (OPG, as mlogit) nl_ll nl_prob nl_pred; extras (s2, n2, L, nest[J] 0-based)
nestsets <- list(`4` = c(0, 0, 1, 1), `5` = c(0, 0, 1, 1, 1), `6` = c(0, 0, 1, 1, 2, 2))
for (rep in 1:12) {
  set.seed(20270200 + rep); n <- sample(250:450, 1); J <- sample(4:6, 1); nv <- nestsets[[as.character(J)]]; L <- max(nv) + 1
  kx <- sample(1:2, 1); kz <- rep %% 2; asc <- 1
  b <- rnorm(kx, 0, 0.8); a0 <- c(0, rnorm(J - 1, 0, 0.4)); g <- if (kz) cbind(0, matrix(rnorm(kz * (J - 1), 0, 0.5), kz)); lam <- runif(L, 0.4, 0.9)
  # predict refits with iterlim = 0, and the BFGS start inverts the outer product of the gradients: n2 must exceed the parameter count
  s <- sample.int(1e6, 1); s2 <- sample.int(1e6, 1); n2 <- sample(30:40, 1)
  d <- gen(s, n, J, kx, kz); V <- util(d, n, J, kx, kz, a0, b, g)
  P <- matrix(0, n, J)
  for (i in 1:n) {
    Nm <- sapply(0:(L - 1), function(m) sum(exp(V[i, nv == m] / lam[m + 1])))
    D <- sum(Nm ^ lam); for (a1 in 1:J) { m <- nv[a1] + 1; P[i, a1] <- exp(V[i, a1] / lam[m]) * Nm[m] ^ (lam[m] - 1) / D }
  }
  ch <- apply(P, 1, function(p) which(runif(1) < cumsum(p))[1])
  if (!good(ch, J)) next
  m <- dfidx(withch(d, ch, J), idx = c("chid", "alt"))
  nl <- lapply(0:(L - 1), function(g) as.character(which(nv == g))); names(nl) <- paste0("n", 0:(L - 1))
  f <- fit(fml(kx, kz, asc), m, nests = nl); if (is.null(f)) next
  a <- c(s, n, J, kx, kz, asc, 3 + J, s2, n2, L, nv, ch - 1)
  add("nl_coef", a, ws(coef(f))); add("nl_se", a, ws(sqrt(diag(vcov(f))))); add("nl_ll", a, as.numeric(logLik(f)))
  add("nl_prob", a, ws(as.vector(t(fitted(f, type = "probabilities")))))
  d2 <- gen(s2, n2, J, kx, kz); d2$choice <- rep(c(TRUE, rep(FALSE, J - 1)), n2)
  add("nl_pred", a, ws(as.vector(t(predict(f, newdata = dfidx(d2, idx = c("chid", "alt")))))))
}

# heteroskedastic logit (Gauss-Laguerre with 40 nodes): hl_coef (covariates then sp.2..sp.J) hl_se (OPG) hl_ll hl_prob
for (rep in 1:16) {
  set.seed(20270300 + rep); n <- sample(300:450, 1); J <- sample(3:4, 1); kx <- sample(1:2, 1); kz <- 0; asc <- 1
  b <- rnorm(kx, 0, 0.8); a0 <- c(0, rnorm(J - 1, 0, 0.4)); th <- c(1, runif(J - 1, 0.5, 2))
  s <- sample.int(1e6, 1)
  d <- gen(s, n, J, kx, kz); ch <- apply(util(d, n, J, kx, kz, a0, b, NULL) + t(t(gumbel(n, J)) * th), 1, which.max)
  if (!good(ch, J)) next
  m <- dfidx(withch(d, ch, J), idx = c("chid", "alt"))
  f <- fit(fml(kx, kz, asc), m, heterosc = TRUE); if (is.null(f)) next
  a <- c(s, n, J, kx, kz, asc, 0, ch - 1)
  add("hl_coef", a, ws(coef(f))); add("hl_se", a, ws(sqrt(diag(vcov(f))))); add("hl_ll", a, as.numeric(logLik(f)))
  add("hl_prob", a, ws(as.vector(t(fitted(f, type = "probabilities")))))
}
gq <- micsr::gauss_laguerre(40)
add("gl_node", 40, ws(gq$nodes), rel = 1e-12); add("gl_wlog", 40, ws(log(gq$weights)), rel = 1e-11)

# mixed logit, normal random coefficients on x columns, Halton draws (halton = NA: primes 2, 3, drop 100), panel when T > 1:
#   mx_coef (covariates then sd) mx_se (OPG over choice situations, as mlogit) mx_ll mx_prob; extras (R, T, nr, design column of each random coefficient, 0-based)
for (rep in 1:8) {
  set.seed(20270400 + rep); T <- if (rep %% 2 == 0) 5 else 1; n <- T * sample(40:60, 1) * (if (T == 1) 5 else 1); J <- sample(3:4, 1); kx <- sample(2:3, 1); kz <- 0; asc <- 1
  nr <- sample(1:2, 1); Rd <- sample(c(40, 50), 1)
  b <- rnorm(kx, 0, 0.8); a0 <- c(0, rnorm(J - 1, 0, 0.4)); sdv <- runif(nr, 0.8, 1.5)
  s <- sample.int(1e6, 1)
  d <- gen(s, n, J, kx, kz, T); V <- util(d, n, J, kx, kz, a0, b, NULL)
  ni <- n / T; eta <- matrix(rnorm(ni * nr), ni)
  for (r in 1:nr) V <- V + sdv[r] * eta[(0:(n - 1)) %/% T + 1, r] * matrix(d[[paste0("x", r)]], n, J, byrow = TRUE)
  ch <- apply(V + gumbel(n, J), 1, which.max)
  if (!good(ch, J)) next
  rp <- setNames(rep("n", nr), paste0("x", 1:nr))
  if (T > 1) {
    m <- dfidx(withch(d, ch, J), idx = list(c("chid", "id"), "alt"))
    f <- fit(fml(kx, kz, asc), m, rpar = rp, R = Rd, halton = NA, panel = TRUE)
  } else {
    m <- dfidx(withch(d, ch, J), idx = c("chid", "alt"))
    f <- fit(fml(kx, kz, asc), m, rpar = rp, R = Rd, halton = NA)
  }
  if (is.null(f)) next
  a <- c(s, n, J, kx, kz, asc, 3 + nr, Rd, T, nr, J - 1 + 0:(nr - 1), ch - 1)
  add("mx_coef", a, ws(coef(f))); add("mx_se", a, ws(sqrt(diag(vcov(f))))); add("mx_ll", a, as.numeric(logLik(f)))
  add("mx_prob", a, ws(as.vector(t(fitted(f, type = "probabilities")))))
}
emit("mlogit", "mlogit", list(cases))
