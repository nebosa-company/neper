# ghyphess: GeneralizedHyperbolic hyperbHessian, nigHessian, gigHessian and the standard errors summary.* derives from them (e.algo.stat.ghyphess).
# "hess": (seed, n, family 0 hyperb / 1 nig, parametrization set 1..5, method 0 exact / 1 tsHessian, i, j, param (4 values, in the set's coordinates),
#          generating mu, delta, alpha, beta); the data are set.seed(seed); rhyperb / rnig(n, generating). i < 4: element [i, j] of the hessian; i = 4: the
#          standard error sqrt(diag(solve(-H)))[j]. Exact hessians are checked to 1e-8, tsHessian ones to 2e-3 (second differences of a sum of logs at a step of 6e-6: the last bit of the density shows).
# "gighess": (seed, n, i, j, log chi, log psi, lambda, generating chi, psi, lambda); i < 3 the element [i, j], i = 3 the standard error j.
suppressMessages(library(GeneralizedHyperbolic))
cases <- list()
setpar <- function(gen, set) {
  if (set == 2) return(gen)
  if (set == 5) { p1 <- as.numeric(hyperbChangePars(2, 1, gen)); return(c(p1[1], log(p1[2]), p1[3], log(p1[4]))) }
  as.numeric(hyperbChangePars(2, set, gen))
}
set.seed(20262106)
hpart <- if (exists("hess_part")) hess_part else "ghyphess"
for (rep in 1:6) {
  ncase0 <- length(cases)
  n <- sample(100:200, 1); sd0 <- sample(1:100000, 1)
  gen <- c(rnorm(1), runif(1, 0.5, 2), runif(1, 1.2, 3)); gen <- c(gen, runif(1, -0.6, 0.6) * gen[3])
  for (fam in 0:1) {
    set.seed(sd0); x <- if (fam == 0) rhyperb(n, param = gen) else rnig(n, param = gen)
    for (set in 1:5) for (hm in 0:1) {
      if (hm == 0 && (fam == 1 || set %in% c(3, 4))) next
      H <- tryCatch(if (fam == 0) hyperbHessian(x, setpar(gen, set), hessianMethod = c("exact", "tsHessian")[hm + 1], whichParam = set)
                    else nigHessian(x, setpar(gen, set), hessianMethod = "tsHessian", whichParam = set), error = function(e) NULL)
      if (is.null(H)) next
      rl <- if (hm == 0) 1e-9 else 5e-3
      pr <- setpar(gen, set)
      for (i in 1:4) for (j in i:4) cases[[length(cases) + 1]] <- case("hess", c(sd0, n, fam, set, hm, i - 1, j - 1, pr, gen), H[i, j], rel = rl, abs = if (hm == 0) rl * 1e-1 else 0.05)
      se <- if (min(eigen(-H, symmetric = TRUE)$values) > 0 && rcond(-H) > 1e-3) tryCatch(sqrt(diag(solve(-H))), error = function(e) NULL, warning = function(w) NULL) else NULL
      if (!is.null(se) && all(is.finite(se))) for (j in 1:4) cases[[length(cases) + 1]] <- case("hess", c(sd0, n, fam, set, hm, 4, j - 1, pr, gen), se[j], rel = if (hm == 0) rl else 2e-2, abs = rl)
    }
  }
  chi <- runif(1, 0.5, 3); psi <- runif(1, 0.5, 3); lam <- runif(1, -1.5, 2)
  set.seed(sd0); x <- rgig(n, chi, psi, lam)
  pr <- c(log(chi), log(psi), lam)
  H <- tryCatch(gigHessian(x, pr), error = function(e) NULL)
  if (!is.null(H)) {
    # R hessian is optimHess (finite differences, step 1e-3 of the parameter), whose error is ~1e-3 relative and is not reproduced bit for bit: 5e-3 (se 2e-2)
    for (i in 1:3) for (j in i:3) cases[[length(cases) + 1]] <- case("gighess", c(sd0, n, i - 1, j - 1, pr, chi, psi, lam), H[i, j], rel = 5e-3, abs = 0.05)
    se <- if (min(eigen(-H, symmetric = TRUE)$values) > 0 && rcond(-H) > 1e-3) tryCatch(sqrt(diag(solve(-H))), error = function(e) NULL, warning = function(w) NULL) else NULL
    if (!is.null(se) && all(is.finite(se))) for (j in 1:3) cases[[length(cases) + 1]] <- case("gighess", c(sd0, n, 3, j - 1, pr, chi, psi, lam), se[j], rel = 2e-2, abs = 1e-4)
  }
  if ((hpart == "ghyphess2") != (rep > 3)) cases <- cases[seq_len(ncase0)]
}
emit(hpart, "GeneralizedHyperbolic", list(cases))
