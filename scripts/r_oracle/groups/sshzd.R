# gss sshzd (cubic marginals, sampled id.basis at failure cases). One case per scalar: "hz" (model, n, nb, seed, skip, m, TIME[n], STATUS[n], X[n], TO[m], XO[m], idx),
# model 1 Surv(time, status) ~ time, 2 ~ time + x, 3 ~ time * x with x a numeric covariate (model 1 carries no X, so X is not in args then); id.basis is
# sample((1:n)[status], nb) after set.seed(seed); idx 0 lambda, 1 .. nq theta, then c (nb), d, cv, the m hazard rates, nb and the id.basis checksums.
suppressMessages(library(gss))
cases <- list()
# R keeps the c and d of the last point nlm evaluated, which is not always its estimate: record that point (the p of the last call of the objective)
trace("nlm", tracer = quote({ .f0 <- f; f <- function(p, ...) { assign(".hzlast", p, globalenv()); .f0(p, ...) } }), where = asNamespace("gss"), print = FALSE)
add <- function(args, want, tol, ab) cases[[length(cases) + 1]] <<- case("hz", args, want, rel = tol, abs = ab)
nqof <- c(1, 2, 5)
run <- function(model, n, seed, skip) {
  x <- round(runif(n, 0, 3) * 2) / 2
  tt <- rweibull(n, 1.6, 2) * exp(-0.25 * x)
  cens <- runif(n, 0.8, 4)
  status <- as.numeric(tt <= cens)
  time <- pmin(tt, cens)
  df <- data.frame(time = time, status = status, x = x)
  nT <- sum(status)
  nb <- max(30, ceiling(10 * n^(2/9))); if (nb > nT) nb <- nT
  fo <- switch(model, Surv(time, status) ~ time, Surv(time, status) ~ time + x, Surv(time, status) ~ time * x)
  assign(".hzlast", NULL, globalenv())
  fit <- tryCatch(suppressWarnings(sshzd(fo, data = df, seed = seed, skip.iter = skip > 0)), error = function(e) NULL)
  if (is.null(fit)) return(invisible(FALSE))
  m <- 6
  to <- runif(m, 0.1, max(time) * 0.9); xo <- round(runif(m, 0, 3) * 2) / 2
  pr <- hzdrate.sshzd(fit, if (model == 1) data.frame(time = to) else data.frame(time = to, x = xo))
  nq <- nqof[model]; idb <- fit$id.basis
  fixmode <- nq > 1 && skip == 0
  args <- c(model, n, nb, seed, if (fixmode) 2 else skip, m, time, status, if (model > 1) x, to, if (model > 1) xo, if (fixmode) c(fit$lambda, fit$theta, get(".hzlast", globalenv())))
  vals <- c(fit$lambda, fit$theta, fit$c, fit$d, fit$cv, pr, nb, sum(idb), sum(idb * seq_along(idb)), idb[1], idb[nb])
  nv <- length(vals)
  tol <- rep(1e-6, nv); ab <- rep(1e-9, nv)
  ab[1] <- 1e-3
  # skip 2 (several theta, searching): [lambda, theta, nlm last point] follow the new rows; the nlm search stops where the score is flat to its own Newton precision (prec 1e-7), so R's converged lambda and theta follow the new rows and the fit is taken at them with no search
  if (fixmode) { ab[1] <- 1e-9; kcv <- 1 + nq + length(fit$c) + length(fit$d) + 1; tol[kcv] <- 5e-6 }
  tol[(nv - 4):nv] <- 0; ab[(nv - 4):nv] <- 0
  for (k in seq_along(vals)) add(c(args, k - 1), vals[k], tol[k], ab[k])
  invisible(TRUE)
}
set.seed(20261125)
for (n in c(100, 150, 220)) for (t in 1:10) if (!isFALSE(run(1, n, 200 + n + t, 0))) break
for (model in 2:3) for (t in 1:10) if (!isFALSE(run(model, 120, 600 + model * 10 + t, 1))) break
for (t in 1:10) if (!isFALSE(run(2, 130, 800 + t, 0))) break
emit("sshzd", "gss", list(cases))
