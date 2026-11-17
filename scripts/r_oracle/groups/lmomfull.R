# lmomfull: lmr, qua, cdf, pel for every lmom distribution, and samlmu with trimming.
#   kind: 0 exp 1 gam 2 gev 3 glo 4 gno 5 gpa 6 gum 7 kap 8 ln3 9 nor 10 pe3 11 wak 12 wa0 13 wei
#   "lmr" (kind, nmom, np, para.., q)  "qua" (kind, f, np, para..)  "cdf" (kind, x, np, para..)
#   "pel" (kind, hasbound, bound, nl, lmom.., q)  "sam" (nmom, t1, t2, ratios, n, x.., q)
suppressMessages(library(lmom))
cases <- list()
nms <- c("exp", "gam", "gev", "glo", "gno", "gpa", "gum", "kap", "ln3", "nor", "pe3", "wak", "wa0", "wei")
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261120)
rk <- function() sample(c(-1, 1), 1) * runif(1, 0.05, 0.6)
mkpar <- function(kind, rep) {
  xi <- round(rnorm(1), 2); al <- round(runif(1, 0.5, 3), 2)
  k <- if (rep %% 5 == 0) 0 else round(rk(), 3)
  switch(kind + 1,
    c(xi, al), c(round(runif(1, 0.3, 8), 2), al), c(xi, al, k), c(xi, al, k), c(xi, al, k * 2), c(xi, al, k), c(xi, al),
    c(xi, al, round(rk(), 3), if (rep %% 4 == 0) 0 else round(sample(c(-0.4, 1), 1) * runif(1, 0.1, 1.2), 3)),
    c(xi, round(rnorm(1), 2), round(runif(1, 0.2, 1.2), 2)), c(xi, al),
    c(xi, al, if (rep %% 5 == 0) 0 else round(rk() * 5, 2)), c(xi, al, round(runif(1, 0.1, 3), 2), round(runif(1, 0.1, 2), 2), round(runif(1, -0.5, 0.5), 2)), NULL,
    c(xi, round(runif(1, 0.5, 3), 2), round(runif(1, 0.4, 4), 2)))
}
for (kind in c(0:11, 13)) for (rep in 1:7) {
  par <- mkpar(kind, rep); nm <- nms[kind + 1]; np <- length(par)
  ml <- get(paste0("lmr", nm)); maxm <- c(20, 4, 20, 20, 20, 20, 20, 20, 20, 20, 4, 20, 0, 20)[kind + 1]
  lmv <- tryCatch(suppressWarnings(ml(par, nmom = maxm)), error = function(e) NULL); if (is.null(lmv) || any(!is.finite(lmv))) next
  # the gev and kappa recurrences lose digits with the order (R itself: they depend on the libm), so orders 7 to 10 get a loose bound and beyond 10 they are not compared
  for (q in seq_along(lmv)) if (!(kind %in% c(2, 7, 13) && q > 10)) add("lmr", c(kind, maxm, np, par, q - 1), lmv[q], rel = if (kind %in% c(2, 7, 13) && q > 6) 1e-4 else 1e-9)
  qf <- get(paste0("qua", nm)); cf <- get(paste0("cdf", nm))
  for (f in c(0.02, 0.2, 0.5, 0.8, 0.97)) {
    qv <- tryCatch(qf(f, par), error = function(e) NA); add("qua", c(kind, f, np, par, 0), qv)
    cv <- tryCatch(cf(qv, par), error = function(e) NA); add("cdf", c(kind, qv, np, par, 0), cv)
  }
  nl <- c(2, 2, 3, 3, 3, 3, 2, 4, 3, 2, 3, 5, 4, 3)[kind + 1]
  pe <- tryCatch(suppressWarnings(get(paste0("pel", nm))(lmv[1:nl])), error = function(e) NULL)
  if (!is.null(pe)) for (q in seq_along(pe)) add("pel", c(kind, 0, 0, nl, lmv[1:nl], q - 1), pe[q], rel = if (kind == 7) 1e-5 else 1e-9, abs = if (kind == 7) 1e-6 else 1e-11)
}
# the cdf at points around and beyond the support, incl. the clipped sides
for (kind in c(0, 2, 3, 4, 5, 7, 8, 10, 13)) for (rep in 1:4) {
  par <- mkpar(kind, rep + 1); cf <- get(paste0("cdf", nms[kind + 1]))
  for (x in par[1] + c(-2, -0.5, 0.3, 1, 3, 9)) add("cdf", c(kind, x, length(par), par, 0), tryCatch(cf(x, par), error = function(e) NA))
}
# wakeby cdf by iteration, over the support
for (rep in 1:10) { par <- mkpar(11, rep); for (x in par[1] + c(0.01, 0.3, 1, 3, 8, 30, 200)) add("cdf", c(11, x, 5, par, 0), tryCatch(suppressWarnings(cdfwak(x, par)), error = function(e) NA)) }
# parameters from arbitrary L-moments: the gev iteration branches, kappa, wakeby, the pareto-fallback of the wakeby
for (rep in 1:60) {
  l1 <- round(rnorm(1), 2); l2 <- round(runif(1, 0.2, 3), 2)
  t3 <- c(runif(1, -0.99, -0.8), runif(1, -0.8, 0), runif(1, 0, 0.98), runif(1, -0.5, 0.5), -0.9999)[rep %% 5 + 1]
  for (kind in c(2, 3, 5, 4, 10, 8, 13)) {
    ok <- (kind != 8 || t3 > 0) && (kind != 13 || t3 > -0.1699); if (kind == 4 && abs(t3) >= 0.95) ok <- FALSE; if (!ok) next
    lm3 <- c(l1, l2, t3); pe <- tryCatch(suppressWarnings(get(paste0("pel", nms[kind + 1]))(lm3)), error = function(e) NULL)
    if (!is.null(pe)) for (q in 1:3) add("pel", c(kind, 0, 0, 3, lm3, q - 1), pe[q], rel = if (kind == 2) 1e-8 else 1e-9)
  }
  t4 <- runif(1, (5 * t3^2 - 1) / 4, (5 * t3^2 + 1) / 6); lm4 <- c(l1, l2, t3, t4)
  pe <- tryCatch(suppressWarnings(pelkap(lm4)), error = function(e) NULL); if (!is.null(pe)) for (q in 1:4) add("pel", c(7, 0, 0, 4, lm4, q - 1), pe[q], rel = 1e-5, abs = 1e-6)
  lm5 <- c(l1 + 3, l2, runif(1, -0.2, 0.7), runif(1, -0.3, 0.5), runif(1, -0.3, 0.4))
  pe <- tryCatch(suppressWarnings(pelwak(lm5)), error = function(e) NULL); if (!is.null(pe)) for (q in 1:5) add("pel", c(11, 0, 0, 5, lm5, q - 1), pe[q])
  bd <- round(runif(1, -1, 0.5), 2); lmb <- c(l1 + 4, l2 * 0.6, runif(1, -0.1, 0.6), runif(1, -0.1, 0.4))
  pe <- tryCatch(suppressWarnings(pelwak(lmb, bound = bd)), error = function(e) NULL); if (!is.null(pe)) for (q in 1:5) add("pel", c(11, 1, bd, 4, lmb, q - 1), pe[q])
  for (kind in c(5, 8, 13)) { lmb2 <- c(l1 + 4, l2 * 0.5); pe <- tryCatch(suppressWarnings(get(paste0("pel", nms[kind + 1]))(lmb2, bound = bd)), error = function(e) NULL)
    if (!is.null(pe)) for (q in 1:3) add("pel", c(kind, 1, bd, 2, lmb2, q - 1), pe[q]) }
}
# sample L-moments, trimmed and not
for (rep in 1:50) {
  n <- sample(c(8:40, 100), 1); x <- round(rexp(n) * 3 + rnorm(n), 3); nmom <- sample(1:8, 1); tr <- list(c(0, 0), c(1, 0), c(0, 1), c(1, 2), c(2, 2), c(2, 0))[[sample(6, 1)]]
  rt <- sample(c(TRUE, FALSE), 1)
  s <- suppressWarnings(samlmu(x, nmom, ratios = rt, trim = tr))
  for (q in seq_len(nmom)) add("sam", c(nmom, tr[1], tr[2], as.integer(rt), n, x, q - 1), s[q])
}
emit("lmomfull", "lmom", list(cases))
