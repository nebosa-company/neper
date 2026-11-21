# Shared by the coxme oracle groups. A dataset is a function of a seed returning list(tm, st, X, strata, offset, weights, terms, efron, mk, w0);
# mk(w) refits with case weights w, which the stability test perturbs by 1e-13. coxme's iteration (a fixed number of Newton steps per theta, then
# optim's BFGS with a 1e-3 central-difference gradient) is chaotic in that noise for some data, so add_spec walks the seed upward until the fit is
# unchanged (iteration counts and every variance parameter to 1e-9) under two such perturbations.
suppressMessages(library(coxme))
suppressMessages(library(survival))
expand <- coxme:::expand.nested
options(warn = -1)
fit <- coxme
cases <- list()
lev1 <- function(g) matrix(as.integer(factor(g)) - 1L, ncol = 1)
rtime <- function(n, lp, scale = 5) round(rexp(n, exp(lp)) * scale, 2) + 0.01

is_stable <- function(f, s, need_counts = TRUE) {
  n <- length(s$tm)
  vc0 <- unlist(f$vcoef)
  for (sd in 1:2) {
    set.seed(sd)
    f2 <- s$mk(s$w0 * (1 + 1e-13 * rnorm(n)))
    if (need_counts && !identical(as.numeric(f2$iter), as.numeric(f$iter))) return(FALSE)
    if (max(abs(unlist(f2$vcoef) - vc0) / abs(vc0)) > 1e-9) return(FALSE)
    if (max(abs(unlist(f2$frail) - unlist(f$frail))) > 1e-8) return(FALSE)
  }
  TRUE
}

# Outputs: q = kind * 100000 + i; layout at the top of groups/coxme.R. light keeps the fixed effects, the variance parameters and the scalars.
add_model <- function(f, s, light = FALSE, count_rel = 0, summ = FALSE) {
  tm <- s$tm; st <- s$st; X <- s$X
  n <- length(tm)
  p <- if (is.null(X)) 0 else ncol(X)
  head <- c(n, p, as.numeric(s$efron), !is.null(s$strata), !is.null(s$offset), !is.null(s$weights), length(s$terms))
  body <- c(tm, st, if (!is.null(s$strata)) s$strata, if (!is.null(s$offset)) s$offset, if (!is.null(s$weights)) s$weights, if (p > 0) c(X))
  for (t in s$terms) body <- c(body, as.numeric(t$icpt), ncol(t$codes), t$nvar, c(t$codes), if (t$nvar > 0) c(t$z))
  fr <- unlist(lapply(f$frail, as.vector))
  nf <- length(fr)
  vc <- unlist(lapply(f$vcoef, function(v) if (is.matrix(v)) c(v[1, 1], v[2, 1], v[2, 2]) else as.vector(v)))
  V <- as.matrix(f$var)
  stopifnot(nrow(V) == nf + p)
  out <- list()
  push <- function(q, v) out[[length(out) + 1]] <<- list(q = q, v = v)
  for (i in seq_len(p)) push(i - 1, f$coefficients[i])
  fi <- if (light) 1:min(nf, 3) else if (nf > 20) c(1:6, nf - 1, nf) else seq_len(nf)
  for (i in fi) push(100000 + i - 1, fr[i])
  for (i in seq_along(vc)) push(200000 + i - 1, vc[i])
  rs <- if (light) c(1, if (p > 0) nf + seq_len(p)) else unique(c(1, 2, nf, if (p > 0) nf + seq_len(p)))
  for (r in rs) push(300000 + (r - 1) * 100 + r - 1, V[r, r])
  if (!light) push(300000 + 0 * 100 + 1, V[1, 2])
  if (!light && nf > 3) push(300000 + 2 * 100 + 0, V[3, 1])
  if (p > 0) push(300000 + nf * 100 + 0, V[nf + 1, 1])
  if (p > 1) push(300000 + (nf + 1) * 100 + nf, V[nf + 2, nf + 1])
  sc <- c(f$loglik, f$penalty, f$df, f$iter)
  for (i in seq_along(sc)) push(400000 + i - 1, sc[i])
  if (summ) {
    # summary.coxme / print.coxme without the rounding: kind 5 integrated then penalized (chisq, df, p, AIC, BIC), kind 6 the fixed table (se, z, p)
    ev <- f$n[1]
    ll <- f$loglik + c(0, 0, f$penalty)
    chi <- c(2 * (ll[2] - ll[1]), 2 * (ll[3] - ll[1]))
    for (k in 1:2) {
      dfk <- f$df[k]
      push(500000 + (k - 1) * 10 + 0, chi[k])
      push(500000 + (k - 1) * 10 + 1, 1 - pchisq(chi[k], dfk))
      push(500000 + (k - 1) * 10 + 2, chi[k] - 2 * dfk)
      push(500000 + (k - 1) * 10 + 3, chi[k] - log(ev) * dfk)
    }
    if (p > 0) for (k in 1:p) {
      se <- sqrt(V[nf + k, nf + k]); z <- f$coefficients[k] / se
      push(600000 + (k - 1) * 10 + 0, se)
      push(600000 + (k - 1) * 10 + 1, z)
      push(600000 + (k - 1) * 10 + 2, pchisq(z^2, 1, lower.tail = FALSE))
    }
  }
  # The penalised coefficients are where Newton iterations stop at a relative change of 1e-8 in the log likelihood: 1e-9 absolute.
  for (o in out) {
    kind <- o$q %/% 100000
    isct <- kind == 4 && o$q %% 100000 >= 6
    r <- if (isct) count_rel else if (kind == 5 || kind == 6) 1e-8 else 1e-9
    a <- if (isct) 0 else if (kind == 1) 1e-9 else 1e-12
    cases[[length(cases) + 1]] <<- case("coxme", c(o$q, head, body), o$v, rel = r, abs = a)
  }
}

add_spec <- function(gen, seed, need_counts = TRUE, ...) {
  repeat {
    s <- gen(seed)
    f <- s$mk(s$w0)
    if (is_stable(f, s, need_counts)) break
    seed <- seed + 1
  }
  message(sprintf("seed %d: iter %s", seed, paste(f$iter, collapse = " ")))
  add_model(f, s, ...)
}
