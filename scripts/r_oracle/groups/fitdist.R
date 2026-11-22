# fitdistrplus: fitdist (mle, mme, qme, mge), gofstat, quantile and bootdist.
#   args: (kind, n, x..., extras...) kind 0 norm 1 lnorm 2 exp 3 gamma 4 weibull 5 logis
#   fn: m_p1 m_p2 m_s1 m_s2 m_ll m_aic m_bic m_conv   (mle)
#       e_p1 e_p2 e_ll                                 (mme, kinds 0 1 2 3 5)
#       q_p1 q_p2        extras: probs (one per parameter)           (qme)
#       g_p1 g_p2        extras: gof code 0 CvM 1 KS 2 AD 3 ADR 4 ADL 5 AD2R 6 AD2L 7 AD2   (mge)
#       gs_ks gs_cvm gs_ad gs_kstest gs_adtest gs_cvmtest gs_chisq gs_df gs_pvalue gs_ncell  (gofstat of the mle fit)
#       gs_obs gs_theo   extras: cell index
#       qt               extras: probs..., index                      (quantile of the mle fit)
#       b_*              extras: method (0 mle 1 qme 2 mme), param (1) or nonparam (0), niter, seed, probs for qme(np), then the index
#   Every value is compared at 1e-9 relative (the optimisers are ports of R's own Nelder-Mead and BFGS), the standard errors at 1e-8 (5e-8 for the mme ones): optimHess differences the gradient twice, which amplifies the rounding of dgamma.
suppressMessages(library(fitdistrplus))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) {
  if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, as.numeric(want), rel = rel, abs = abs)
}
nm <- c("norm", "lnorm", "exp", "gamma", "weibull", "logis")
gofn <- c("CvM", "KS", "AD", "ADR", "ADL", "AD2R", "AD2L", "AD2")
code <- function(s) if (is.null(s) || is.na(s) || s == "not computed") 0 else if (s == "rejected") 1 else 2
set.seed(20261121 %% 100000)
par1 <- runif(20)
draw <- function(kind, n) switch(kind + 1, rnorm(n, 5, 2), rlnorm(n, 1, 0.5), rexp(n, 0.4), rgamma(n, 3, 0.5), rweibull(n, 1.7, 4), rlogis(n, 2, 1.5))
for (rep in 1:24) {
  kind <- (rep - 1) %% 6; n <- sample(25:70, 1); x <- round(draw(kind, n), 4); a <- c(kind, n, x)
  d <- nm[kind + 1]; np <- if (kind == 2) 1 else 2
  f <- suppressWarnings(fitdist(x, d)); g <- suppressWarnings(gofstat(f))
  add("m_p1", a, f$estimate[1]); if (np == 2) add("m_p2", a, f$estimate[2])
  add("m_s1", a, f$sd[1], 1e-8); if (np == 2) add("m_s2", a, f$sd[2], 1e-8)
  add("m_ll", a, f$loglik); add("m_aic", a, f$aic); add("m_bic", a, f$bic); add("m_conv", a, f$convergence)
  vc <- f$vcov
  add("m_v11", a, vc[1, 1], 1e-8); if (np == 2) { add("m_v12", a, vc[1, 2], 1e-8, 1e-10); add("m_v22", a, vc[2, 2], 1e-8) }
  if (np == 2) add("m_cor", a, f$cor[1, 2], 1e-8, 1e-6)
  ci <- confint(f); for (k in 1:np) { add("m_lo", c(a, k - 1), ci[k, 1], 1e-8); add("m_up", c(a, k - 1), ci[k, 2], 1e-8) }
  add("gs_ks", a, g$ks); add("gs_cvm", a, g$cvm); add("gs_ad", a, g$ad)
  add("gs_kstest", a, code(g$kstest)); add("gs_adtest", a, code(g$adtest)); add("gs_cvmtest", a, code(g$cvmtest))
  if (!is.null(g$chisq)) {
    add("gs_chisq", a, g$chisq); add("gs_df", a, g$chisqdf); add("gs_ncell", a, nrow(g$chisqtable))
    if (!is.null(g$chisqpvalue)) add("gs_pvalue", a, g$chisqpvalue)
    for (k in unique(c(1, 2, nrow(g$chisqtable)))) { add("gs_obs", c(a, k - 1), g$chisqtable[k, 1]); add("gs_theo", c(a, k - 1), g$chisqtable[k, 2]) }
  }
  pr <- c(0.1, 0.35, 0.5, 0.8, 0.95)
  qq <- quantile(f, probs = pr)$quantiles
  for (j in 1:5) add("qt", c(a, pr, j - 1), as.numeric(qq[1, j]))
  if (kind != 4) {
    fe <- suppressWarnings(fitdist(x, d, method = "mme"))
    add("e_p1", a, fe$estimate[1]); if (np == 2) add("e_p2", a, fe$estimate[2]); add("e_ll", a, fe$loglik)
    add("e_s1", a, fe$sd[1], 5e-8); if (np == 2) add("e_s2", a, fe$sd[2], 5e-8)
  }
  pq <- if (np == 1) 0.5 else c(0.25, 0.75)
  fq <- suppressWarnings(try(fitdist(x, d, method = "qme", probs = pq), silent = TRUE))
  if (!inherits(fq, "try-error")) { add("q_p1", c(a, pq), fq$estimate[1]); if (np == 2) add("q_p2", c(a, pq), fq$estimate[2]) }
  gc <- (rep - 1) %% 8
  fg <- suppressWarnings(try(fitdist(x, d, method = "mge", gof = gofn[gc + 1]), silent = TRUE))
  if (!inherits(fg, "try-error")) { add("g_p1", c(a, gc), fg$estimate[1]); if (np == 2) add("g_p2", c(a, gc), fg$estimate[2]) }
}
# mledist from a given start (a path that really walks the Nelder-Mead simplex)
for (rep in 1:12) {
  kind <- (rep - 1) %% 6; n <- sample(25:60, 1); x <- round(draw(kind, n), 4); a <- c(kind, n, x)
  d <- nm[kind + 1]; np <- if (kind == 2) 1 else 2
  f <- suppressWarnings(fitdist(x, d)); st <- as.numeric(f$estimate) * runif(np, 0.7, 1.4)
  ml <- suppressWarnings(mledist(x, d, start = as.list(setNames(st, names(f$estimate))), checkstartfix = TRUE))
  add("s_p1", c(a, st), ml$estimate[1]); if (np == 2) add("s_p2", c(a, st), ml$estimate[2])
  add("s_ll", c(a, st), ml$loglik)
}
# bootdist: parametric and non-parametric, mle, qme and mme
for (rep in 1:18) {
  kind <- (rep - 1) %% 6; n <- sample(25:50, 1); x <- round(draw(kind, n), 4); a <- c(kind, n, x)
  d <- nm[kind + 1]; np <- if (kind == 2) 1 else 2
  meth <- c(0, 1, 2)[(rep - 1) %/% 6 + 1]; if (meth == 2 && kind == 4) meth <- 0
  param <- rep %% 2; niter <- 40; seed <- 100 + rep
  pq <- if (np == 1) 0.5 else c(0.25, 0.75)
  f <- suppressWarnings(if (meth == 1) fitdist(x, d, method = "qme", probs = pq) else fitdist(x, d, method = c("mle", "qme", "mme")[meth + 1]))
  tl <- if (kind == 2) 1e-8 else 1e-9  # exp has one parameter: R BFGS from a far start differs at 3e-9 in some iteration (line-search rounding)
  set.seed(seed)
  e1 <- f$estimate[1]; e2 <- f$estimate[2]
  rr <- if (param == 1) switch(kind + 1, rnorm(niter * n, e1, e2), rlnorm(niter * n, e1, e2), rexp(niter * n, e1), rgamma(niter * n, e1, e2), rweibull(niter * n, e1, e2), rlogis(niter * n, e1, e2)) else sample(x, niter * n, replace = TRUE)
  add("b_dfirst", c(a, meth, param, niter, seed, pq, 0), sum(rr[1:n])); add("b_dlast", c(a, meth, param, niter, seed, pq, 0), sum(rr[((niter - 1) * n + 1):(niter * n)]))
  if (meth == 0) { m1 <- mledist(rr[1:n], d, start = as.list(f$estimate), checkstartfix = TRUE); add("b_s1", c(a, meth, param, niter, seed, pq, 0), m1$estimate[1]) }
  set.seed(seed)
  b <- suppressWarnings(bootdist(f, bootmethod = if (param == 1) "param" else "nonparam", niter = niter))
  ex <- c(meth, param, niter, seed, pq)
  est <- as.matrix(b$estim)
  for (k in 1:np) {
    ak <- c(a, ex, k - 1)
    add("b_first", ak, est[1, k], tl); add("b_last", ak, est[niter, k], tl); add("b_mean", ak, mean(est[, k]), tl)
    ci <- if (np == 1) b$CI else b$CI[k, ]
    add("b_med", ak, ci[1], tl); add("b_lo", ak, ci[2], tl); add("b_up", ak, ci[3], tl)
  }
  add("b_conv", c(a, ex, 0), sum(b$converg))
  pr <- c(0.1, 0.5, 0.9)
  bq <- quantile(b, probs = pr)
  for (j in 1:3) {
    aj <- c(a, ex, pr, j - 1)
    add("bq_med", aj, bq$quantmedian[1, j], tl); add("bq_lo", aj, bq$quantCI[1, j], tl); add("bq_up", aj, bq$quantCI[2, j], tl)
  }
}
# fitdistcens and bootdistcens: left, right (NA coded -1) after the kind and n
cdata <- function(kind, n) {
  x <- round(draw(kind, n), 4); u <- runif(n)
  left <- x; right <- x
  il <- u < 0.2; left[il] <- NA                       # left censored: only the upper bound is known
  ir <- u >= 0.2 & u < 0.4; right[ir] <- NA           # right censored
  ii <- u >= 0.4 & u < 0.65; left[ii] <- round(x[ii] * 0.85, 4); right[ii] <- round(x[ii] * 1.15, 4)  # interval censored
  data.frame(left = left, right = right)
}
enc <- function(v) ifelse(is.na(v), -1, v)
for (rep in 1:18) {
  kind <- (rep - 1) %% 6; n <- sample(30:60, 1); cd <- cdata(kind, n); a <- c(kind, n, enc(cd$left), enc(cd$right))
  d <- nm[kind + 1]; np <- if (kind == 2) 1 else 2
  f <- suppressWarnings(try(fitdistcens(cd, d), silent = TRUE)); if (inherits(f, "try-error")) next
  add("c_p1", a, f$estimate[1]); if (np == 2) add("c_p2", a, f$estimate[2])
  add("c_s1", a, f$sd[1], 1e-8); if (np == 2) add("c_s2", a, f$sd[2], 1e-8)
  add("c_ll", a, f$loglik); add("c_aic", a, f$aic); add("c_bic", a, f$bic)
  if (rep <= 12) {
    niter <- 30; seed <- 300 + rep; set.seed(seed)
    b <- suppressWarnings(bootdistcens(f, niter = niter)); est <- as.matrix(b$estim)
    tl <- if (kind == 2) 1e-8 else 1e-9
    for (k in 1:np) {
      ak <- c(a, niter, seed, k - 1); ci <- if (np == 1) b$CI else b$CI[k, ]
      add("cb_first", ak, est[1, k], tl); add("cb_last", ak, est[niter, k], tl); add("cb_mean", ak, mean(est[, k]), tl)
      add("cb_med", ak, ci[1], tl); add("cb_lo", ak, ci[2], tl); add("cb_up", ak, ci[3], tl)
    }
  }
}
# descdist (both moment methods) with the bootstrap points of the Cullen and Frey graph
for (rep in 1:8) {
  kind <- (rep - 1) %% 6; n <- sample(15:60, 1); x <- round(draw(kind, n), 4)
  for (mt in 0:1) {
    a <- c(kind, n, x, mt); dd <- descdist(x, method = c("unbiased", "sample")[mt + 1], graph = FALSE, print = FALSE)
    add("d_min", a, dd$min); add("d_max", a, dd$max); add("d_median", a, dd$median); add("d_mean", a, dd$mean)
    add("d_sd", a, dd$sd); add("d_skew", a, dd$skewness); add("d_kurt", a, dd$kurtosis)
  }
  if (rep <= 4) {
    boot <- 20; seed <- 500 + rep; a <- c(kind, n, x, 0, boot, seed)
    set.seed(seed); db <- matrix(sample(x, n * boot, replace = TRUE), nrow = n)
    sk <- function(v) { m <- mean(v); mo <- function(k) sum((v - m)^k) / length(v); nn <- length(v); sqrt(nn * (nn - 1)) * (mo(3) / sqrt(mo(2))^3) / (nn - 2) }
    ku <- function(v) { m <- mean(v); mo <- function(k) sum((v - m)^k) / length(v); nn <- length(v); (nn - 1) / ((nn - 2) * (nn - 3)) * ((nn + 1) * mo(4) / mo(2)^2 - 3 * (nn - 1)) + 3 }
    s2 <- apply(db, 2, function(v) sk(v)^2); kb <- apply(db, 2, ku)
    add("d_bs2_first", a, s2[1]); add("d_bs2_last", a, s2[boot]); add("d_bk_first", a, kb[1]); add("d_bk_last", a, kb[boot])
  }
}
# denscomp data: histogram (Sturges) and the fitted density on 101 points
pdf(NULL)
for (rep in 1:9) {
  kind <- (rep - 1) %% 6; n <- sample(25:70, 1); x <- round(draw(kind, n), 4); a <- c(kind, n, x)
  f <- suppressWarnings(fitdist(x, nm[kind + 1])); dc <- denscomp(f, plotstyle = "graphics")
  h <- dc$hist; add("dc_nbreaks", a, length(h$breaks))
  for (i in unique(c(1, 2, length(h$breaks)))) add("dc_break", c(a, i - 1), h$breaks[i])
  for (i in unique(c(1, 2, length(h$counts)))) { add("dc_count", c(a, i - 1), h$counts[i]); add("dc_dens", c(a, i - 1), h$density[i]) }
  for (i in c(1, 26, 51, 101)) add("dc_fit", c(a, i - 1), dc$densities[i, 1])
}
emit("fitdist", "fitdistrplus", list(cases))
