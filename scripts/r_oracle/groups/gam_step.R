# gam::step.Gam over variables x1..x_nv each with the regimen 1 / xj / s(xj, df = a) / s(xj, df = b) or, in the second half of the cases, 1 / xj / s(xj, df = a) / lo(xj, span = b) (kind 0 none, 1 linear, 2 smooth, 3 loess).
# Args: (fam 0 gaussian 1 binomial 2 poisson, n, nv, maxopt, direction 0 both 1 backward 2 forward, steps, start[nv], nopt[nv], kind[nv * maxopt], df[nv * maxopt] (the span for kind 3), x[nv * n], y[n], what, idx)
# what 0 the number of models on the path, 1 items[idx = s * nv + v] (the 1-based option of variable v after s steps), 2 AIC[s], 3 Resid. Dev[s], 4 Resid. Df[s], 5 final coefficient[idx], 6 final additive predictor[idx]
# The continuous values carry tolerance 1e-7: the df-matching Brent search of each term stops on a criterion flat to rounding (observed last-bit moves of 4e-9 in the fits, as in the gam group); the path and its items are exact.
suppressMessages(library(gam))
cases <- list()
set.seed(20261121)
add <- function(args, want, tol = 1e-7) cases[[length(cases) + 1]] <<- case("gam_step", args, want, rel = tol, abs = 1e-10)
stepcase <- function(rep, uselo) {
  if (uselo) set.seed(20262000 + rep)
  fam <- rep %% 3; n <- sample(30:40, 1); nv <- 3; direction <- c(0, 1, 2)[1 + (rep %/% 3) %% 3]
  x <- matrix(round(runif(n * nv, -2, 3), 3), n, nv)
  eta <- 0.2 + sin(x[, 1]) * 0.8 + 0.4 * x[, 2]
  y <- switch(fam + 1, round(eta + rnorm(n, 0, 0.4), 4), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta)))
  dfa <- sample(c(2.5, 3), nv, replace = TRUE); dfb <- if (uselo) sample(c(0.5, 0.7, 0.9), nv, replace = TRUE) else sample(c(4, 5), nv, replace = TRUE)
  maxopt <- 4; kind <- rep(c(0, 1, 2, 2 + uselo), nv); dfv <- as.vector(rbind(0, 0, dfa, dfb)); nopt <- rep(4, nv)
  start <- sample(1:4, nv, replace = TRUE)
  opts <- lapply(seq_len(nv), function(i) c("1", sprintf("x%d", i), sprintf("s(x%d, df = %g)", i, dfa[i]), if (uselo) sprintf("lo(x%d, span = %g)", i, dfb[i]) else sprintf("s(x%d, df = %g)", i, dfb[i])))
  d <- data.frame(y = y); for (i in seq_len(nv)) d[[paste0("x", i)]] <- x[, i]
  tm <- unlist(lapply(seq_len(nv), function(i) if (start[i] > 1) opts[[i]][start[i]]))
  assign(".gd", d, globalenv())
  start.fit <- eval(parse(text = sprintf("gam(y ~ %s, family = %s, data = .gd)", if (length(tm)) paste(tm, collapse = " + ") else "1", c("gaussian", "binomial", "poisson")[fam + 1])), globalenv())
  scope <- lapply(opts, function(o) as.formula(paste("~", paste(o, collapse = " + "))))
  names(scope) <- paste0("x", seq_len(nv))
  r <- suppressWarnings(step.Gam(start.fit, scope, trace = FALSE, direction = c("both", "backward", "forward")[direction + 1], steps = 20))
  an <- r$anova; nmod <- nrow(an)
  items <- matrix(0, nmod, nv); items[1, ] <- start
  for (s in seq_len(nmod)[-1]) {
    items[s, ] <- items[s - 1, ]
    fr <- as.character(an$From[s]); to <- as.character(an$To[s])
    for (i in seq_len(nv)) {
      o <- opts[[i]]; o[o == "1"] <- ""
      if (fr %in% o && to %in% o) { items[s, i] <- match(to, o); break }
    }
  }
  hdr <- function(what, idx) c(fam, n, nv, maxopt, direction, 20, start, nopt, kind, dfv, as.vector(x), y, what, idx)
  add(hdr(0, 0), nmod, 0)
  # df matching leaves spar to Brent's search on a criterion flat to rounding: the tolerance of the continuous values is 100 times the move a last-bit change of the weights makes in the start and the final fit (at least 1e-7)
  sens <- function(fit) {
    mv <- 0
    for (k in 1:4) {
      d$pw <- 1 + c(1e-13, 1e-11, 1e-12, 3e-11)[k] * sin(k * seq_len(n)); assign(".gd", d, globalenv())
      g <- eval(bquote(gam(.(formula(fit)), family = .(list(gaussian, binomial, poisson)[[fam + 1]]), data = .gd, weights = pw)), globalenv())
      u <- c(fit$deviance, fit$df.residual, fit$aic, fit$additive.predictors); v <- c(g$deviance, g$df.residual, g$aic, g$additive.predictors)
      mv <- max(mv, abs(v - u) / (1 + abs(u)))
    }
    mv
  }
  tl <- max(1e-7, 100 * max(sens(start.fit), sens(r)))
  for (s in seq_len(nmod)) {
    for (i in seq_len(nv)) add(hdr(1, (s - 1) * nv + i - 1), items[s, i], 0)
    add(hdr(2, s - 1), an$AIC[s], tl); add(hdr(3, s - 1), an[["Resid. Dev"]][s], tl); add(hdr(4, s - 1), an[["Resid. Df"]][s], tl)
  }
  for (i in seq_along(r$coefficients)) add(hdr(5, i - 1), r$coefficients[i], tl)
  add(hdr(6, 0), r$additive.predictors[1], tl); add(hdr(6, n - 1), r$additive.predictors[n], tl)
}
# The package Fortran corrupts memory now and then (a segfault, often cases later), so the loess cases run each in its own R process and a crashed one is skipped.
if (nzchar(Sys.getenv("GAM_CHILD"))) {
  stepcase(as.integer(Sys.getenv("GAM_CHILD")), 1)
  saveRDS(cases, Sys.getenv("GAM_OUT"))
  quit(save = "no")
}
for (rep in 1:9) stepcase(rep, 0)
for (rep in 1:9) {
  of <- tempfile(fileext = ".rds")
  Sys.setenv(GAM_CHILD = as.character(rep), GAM_OUT = of)
  suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c("scripts/r_oracle/generate.R", "gam_step"), stdout = FALSE, stderr = FALSE))
  Sys.unsetenv(c("GAM_CHILD", "GAM_OUT"))
  if (file.exists(of)) cases <- c(cases, readRDS(of)) else message("a loess case crashed in the package and is skipped")
}
emit("gam_step", "gam", list(cases))
