# gsl: the Coulomb wave functions with gsl's error estimates (strict = FALSE, give = TRUE).
#   "fg"  (code, eta, x, lam_F, k): code 0..3 val_F val_Fp val_G val_Gp, 4 err_F, 5 err_Fp, 6 err_Gp (R's err_G is a copy of err_Gp), 7 exp_F, 8 exp_G, 9 status
#   "cl"  (code, lam, eta): code 0 value, 1 error, 2 status
#   "fga" (kind, idx, lam_min, kmax, eta, x): kind 0 F_array, 1 FG_array F, 2 FG_array G, 3 FGp F, 4 FGp Fp, 5 FGp G, 6 FGp Gp, 7 sphF, 8 CL_array; idx = element, or -1 = F_exp (kinds 0-7)
suppressMessages(library(gsl))
cases <- list()
add <- function(fn, args, want, rel = 1e-11, abs = 1e-300) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20262911)
pars <- list()
for (i in 1:50) pars[[length(pars) + 1]] <- c(runif(1, -3, 3), runif(1, 0.05, 1.15), sample(c(0, 0.5, 1, 1.5, 2, 3, runif(1, 0, 4), runif(1, 0, 4)), 1))   # series region
for (i in 1:50) pars[[length(pars) + 1]] <- c(runif(1, -6, 20), runif(1, 1.3, 40), sample(c(0, 0.5, 1, 2.5, runif(1, 0, 6)), 1))                                   # oscillatory (Steed)
for (i in 1:40) { e <- runif(1, 2, 25); pars[[length(pars) + 1]] <- c(e, runif(1, 1.3, 1.9 * e), sample(c(0, 1, 2.5, runif(1, 0, 5)), 1)) }                  # below the turning point (WKB)
for (i in 1:15) pars[[length(pars) + 1]] <- c(runif(1, -4, -0.2), runif(1, 0.1, 1.1), sample(c(0, 1, 2), 1))                                                     # negative eta
for (p in pars) {
  eta <- p[1]; x <- p[2]; lam <- p[3]; kk <- max(0, min(3, ceiling(lam + 0.5) - 1)); k <- (0:kk)[sample.int(kk + 1, 1)]
  r <- tryCatch(coulomb_wave_FG(eta, x, lam, k, give = TRUE, strict = FALSE), error = function(e) NULL)
  if (is.null(r) || r$status != 0 || !all(is.finite(c(r$val_F, r$val_G, r$val_Fp, r$val_Gp)))) next
  a <- c(eta, x, lam, k)
  v <- c(r$val_F, r$val_Fp, r$val_G, r$val_Gp)
  for (j in 1:4) add("fg", c(j - 1, a), v[j])
  add("fg", c(4, a), r$err_F, rel = 1e-9); add("fg", c(5, a), r$err_Fp, rel = 1e-9); add("fg", c(6, a), r$err_Gp, rel = 1e-9)
  add("fg", c(7, a), r$exp_F); add("fg", c(8, a), r$exp_G, abs = 1e-9); add("fg", c(9, a), r$status, abs = 0.5)
}
# the special positions: x = 0 (a domain error, F' at lambda 0 and G' reported) and large k
for (lam in c(0, 1)) { r <- coulomb_wave_FG(0.7, 0, lam, 0, give = TRUE, strict = FALSE); for (j in 1:4) add("fg", c(j - 1, 0.7, 0, lam, 0), c(r$val_F, r$val_Fp, r$val_G, r$val_Gp)[j], abs = 1e-12); add("fg", c(9, 0.7, 0, lam, 0), r$status, abs = 0.5) }
for (lam in c(-0.5, -1, 1)) { r <- coulomb_wave_FG(1, 2, lam, 2, give = TRUE, strict = FALSE); add("fg", c(9, 1, 2, lam, 2), r$status, abs = 0.5); add("fg", c(0, 1, 2, lam, 2), r$val_F, abs = 1e-12) }
for (i in 1:60) {
  lam <- c(runif(1, -0.9, 8), sample(c(0, 0.5, 1, 2), 1))[sample(1:2, 1)]; eta <- runif(1, -5, 8)
  r <- tryCatch(coulomb_CL(lam, eta, give = TRUE, strict = FALSE), error = function(e) NULL)
  if (is.null(r) || r$status != 0) next
  add("cl", c(0, lam, eta), r$val, rel = 1e-12); add("cl", c(1, lam, eta), r$err, rel = 1e-9)
}
# the array forms
for (i in 1:40) {
  kmax <- sample(1:6, 1); lm <- c(0, 0.5, 1, runif(1, -0.45, 3))[sample(1:4, 1)]; eta <- runif(1, -3, 6); x <- runif(1, 0.1, 25)
  a <- c(lm, kmax, eta, x)
  g <- tryCatch(coulomb_wave_FG_array(lm, kmax, eta, x, give = TRUE, strict = FALSE), error = function(e) NULL)
  if (is.null(g) || g$status != 0 || !all(is.finite(c(g$val_F, g$val_G)))) next
  gp <- coulomb_wave_FGp_array(lm, kmax, eta, x, give = TRUE, strict = FALSE)
  f <- coulomb_wave_F_array(lm, kmax, eta, x, give = TRUE, strict = FALSE)
  sf <- coulomb_wave_sphF_array(lm, kmax, eta, x, give = TRUE, strict = FALSE)
  for (j in 0:kmax) {
    add("fga", c(0, j, a), f$val[j + 1]); add("fga", c(1, j, a), g$val_F[j + 1]); add("fga", c(2, j, a), g$val_G[j + 1])
    add("fga", c(3, j, a), gp$val_F[j + 1]); add("fga", c(4, j, a), gp$val_Fp[j + 1]); add("fga", c(5, j, a), gp$val_G[j + 1]); add("fga", c(6, j, a), gp$val_Gp[j + 1])
    add("fga", c(7, j, a), sf$val[j + 1])
  }
  add("fga", c(0, -1, a), f$F_exp, abs = 1e-9); add("fga", c(7, -1, a), sf$F_exp, abs = 1e-9)
}
for (i in 1:20) {
  kmax <- sample(1:6, 1); lm <- runif(1, -0.9, 3); eta <- runif(1, -3, 6); a <- c(lm, kmax, eta, 0)
  cl <- coulomb_CL_array(lm, kmax, eta, give = TRUE, strict = FALSE)
  for (j in 0:kmax) add("fga", c(8, j, a), cl$val[j + 1], rel = 1e-12)
}
emit("gslcoulomb", "gsl", list(cases))
