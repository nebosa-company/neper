# TSA::arimax with transfer-function (intervention) terms, user regressors and innovative-outlier columns. Fn "arx".
#   args: (n, p, d, q, P, D, Q, per, ncu, mean, nt, method, [tp, tq] * nt, iof * ncu, y[n], xreg (ncu columns, n each), xtransf (nt columns, n each), which, idx)
#   method 0 CSS-ML, 1 ML. xreg columns are the user columns first and then the innovative-outlier pulses (iof 1); transfer = list(c(tp, tq), ...) as in arimax.
#   which 0 coef[idx + 1] (ar, ma, sar, sma, intercept, xreg columns, each transfer term's AR then MA), 1 sigma2, 2 loglik, 3 aic, 4 sqrt(var.coef[idx, idx]), 5 residuals[idx + 1]
suppressMessages(library(TSA))
cases <- list()
add <- function(args, want, rel, abs) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("arx", args, want, rel = rel, abs = abs)
one <- function(n, o, so, per, mean, method, y, xu, iof, io, tf, tr, tol) {
  yy <- ts(y, frequency = per); ncu <- length(iof)
  nuser <- ncu - length(io); nt <- length(tr)
  xreg_txt <- if (nuser > 0) ", xreg = data.frame(xu[, seq_len(nuser), drop = FALSE])" else ""
  io_txt <- if (length(io) > 0) sprintf(", io = c(%s)", paste(io, collapse = ", ")) else ""
  tf_txt <- if (nt > 0) ", xtransf = data.frame(tf), transfer = tr" else ""
  txt <- sprintf("arimax(yy, order = o, seasonal = list(order = so, period = per)%s, include.mean = mean%s%s, method = c('CSS-ML', 'ML')[method + 1])", xreg_txt, io_txt, tf_txt)
  fit <- tryCatch(suppressWarnings(eval(parse(text = txt))), error = function(e) NULL)
  if (is.null(fit) || fit$code != 0) return(invisible())
  # arimax's own pulse for io: the column of that name sits after the user columns, at the io positions
  base <- c(n, o[1], o[2], o[3], so[1], so[2], so[3], per, ncu, mean, nt, method, unlist(lapply(tr, function(z) z[1:2])), iof, y, as.numeric(xu), if (nt > 0) as.numeric(as.matrix(tf)) else numeric(0))
  ncoef <- length(fit$coef); se <- sqrt(diag(fit$var.coef)); ri <- sort(sample(seq_len(n), 3))
  for (i in seq_len(ncoef)) {
    add(c(base, 0, i - 1), fit$coef[i], tol, tol * 1e-3)
    add(c(base, 4, i - 1), se[i], tol * 10, tol * 1e-2)
  }
  add(c(base, 1, 0), fit$sigma2, tol, tol * 1e-3); add(c(base, 2, 0), fit$loglik, 1e-9, 1e-9); add(c(base, 3, 0), fit$aic, 1e-9, 1e-9)
  for (i in ri) add(c(base, 5, i - 1), as.numeric(fit$residuals)[i], tol, tol * 1e-3)
}
# Tolerances looser than 1e-9 are measured, not guessed. Cases 1, 3, 6, 7, 8 equal R at 1e-9. The rest sit on flat likelihoods where optim BFGS (reltol 1e-8, finite-difference gradient) stops on the last bits of libm and of the gradient: case 2 CSS-ML worst 2.2e-6 (coefficient), 1.4e-6 (se), checked at 5e-6; its ML twin (case 9, own draw) checked at 1e-8; case 4 ML 4.5e-9 coefficient, 2.8e-8 se, checked at 1e-8 (se at 10x); airmiles case 5 3.2e-8 coefficient, 4.8e-6 se (finite-difference Hessian), checked at 5e-7 (se 5e-6). loglik and aic agree at 1e-9 in every case.
pulse <- function(n, k) as.numeric(seq_len(n) == k)
step <- function(n, k) as.numeric(seq_len(n) >= k)
set.seed(20262661)
# 1. AR(1) with a mean and one pulse input (0, 0), ML
n <- 90; k <- 40; y <- round(as.numeric(arima.sim(list(ar = 0.5), n)) + 2 + 4 * pulse(n, k), 4)
one(n, c(1, 0, 0), c(0, 0, 0), 1, TRUE, 1, y, numeric(0), numeric(0), numeric(0), cbind(I = pulse(n, k)), list(c(0, 0)), 1e-9)
# 2. ARMA(1, 1), a step input with an AR part (1, 0), CSS-ML
n <- 110; k <- 55; y <- round(as.numeric(arima.sim(list(ar = 0.4, ma = 0.3), n)) + 3 * filter(step(n, k), 0.5, "recursive"), 4)
one(n, c(1, 0, 1), c(0, 0, 0), 1, TRUE, 0, y, numeric(0), numeric(0), numeric(0), cbind(S = step(n, k)), list(c(1, 0)), 5e-6)
# 3. numerator of two terms (0, 1): the first filtered value is missing
n <- 100; k <- 30; y <- round(as.numeric(arima.sim(list(ar = 0.5), n)) + 3 * pulse(n, k) + 2 * pulse(n, k + 1), 4)
one(n, c(1, 0, 0), c(0, 0, 0), 1, TRUE, 1, y, numeric(0), numeric(0), numeric(0), cbind(I = pulse(n, k)), list(c(0, 1)), 1e-9)
# 4. two inputs, (1, 0) and (2, 1), AR(2) without mean
n <- 120; y <- round(as.numeric(arima.sim(list(ar = c(0.5, -0.2)), n)) + 3 * filter(pulse(n, 40), 0.6, "recursive") + 2 * pulse(n, 80), 4)
one(n, c(2, 0, 0), c(0, 0, 0), 1, FALSE, 1, y, numeric(0), numeric(0), numeric(0), cbind(A = pulse(n, 40), B = pulse(n, 80)), list(c(1, 0), c(2, 1)), 1e-8)
# 5. the TSA airmiles intervention: (0, 1, 1)(0, 1, 1)[12], three dummies, a pulse input twice (0, 0) and (1, 0)
data(airmiles, package = "TSA"); ly <- log(as.numeric(airmiles)); n <- length(ly)
d911 <- pulse(n, 69)
xu <- cbind(Dec96 = pulse(n, 12), Jan97 = pulse(n, 13), Dec02 = pulse(n, 84))
one(n, c(0, 1, 1), c(0, 1, 1), 12, FALSE, 1, ly, xu, c(0, 0, 0), numeric(0), cbind(I911 = d911, I911b = d911), list(c(0, 0), c(1, 0)), 5e-7)
# 6. innovative outliers: AR(1) with a mean and two io columns (their pulses are filtered through the ARMA), ML and CSS-ML
n <- 100; y <- round(as.numeric(arima.sim(list(ar = 0.6), n)) + 1 + 6 * filter(pulse(n, 30), 0.6, "recursive") - 5 * pulse(n, 70), 4)
for (m in 0:1) one(n, c(1, 0, 0), c(0, 0, 0), 1, TRUE, m, y, cbind(pulse(n, 30), pulse(n, 70)), c(1, 1), c(30, 70), NULL, list(), 1e-9)
# 7. ARMA(1, 1) with a user regressor, an io column and a transfer step, CSS-ML
n <- 130; u <- round(rnorm(n), 4); y <- round(as.numeric(arima.sim(list(ar = 0.5, ma = 0.2), n)) + 1.5 * u + 4 * pulse(n, 50) + 3 * filter(step(n, 90), 0.5, "recursive"), 4)
one(n, c(1, 0, 1), c(0, 0, 0), 1, TRUE, 0, y, cbind(u, pulse(n, 50)), c(0, 1), c(50), cbind(S = step(n, 90)), list(c(1, 0)), 1e-9)
# 8. seasonal AR with differencing, period 4, a pulse input
n <- 96; y <- round(cumsum(as.numeric(arima.sim(list(ar = 0.4), n))) + 5 * pulse(n, 48) + sin(2 * pi * seq_len(n) / 4), 4)
one(n, c(1, 1, 0), c(1, 0, 0), 4, TRUE, 1, y, numeric(0), numeric(0), numeric(0), cbind(I = pulse(n, 48)), list(c(0, 0)), 1e-9)
# 9. the case-2 model by ML (separate draw, placed last so the other series keep their data)
n <- 110; k <- 55; y <- round(as.numeric(arima.sim(list(ar = 0.4, ma = 0.3), n)) + 3 * filter(step(n, k), 0.5, "recursive"), 4)
one(n, c(1, 0, 1), c(0, 0, 0), 1, TRUE, 1, y, numeric(0), numeric(0), numeric(0), cbind(S = step(n, k)), list(c(1, 0)), 1e-8)
emit("tsa_arimax", "TSA", list(cases))
