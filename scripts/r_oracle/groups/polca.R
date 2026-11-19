# poLCA latent class analysis from given starting probabilities, run to a tight tolerance.
#   args: (n, J, R, ncat[J], start probs R x sum(ncat) row-major, data[n*J] 1-based categories row-major)
#   fn "ll" "prior" "probs" (weighted by position), "bic"
suppressMessages(library(poLCA))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-4, abs = 1e-6)
set.seed(20270106)
for (rep in 1:20) {
  n <- sample(150:400, 1); J <- sample(3:5, 1); R <- sample(2:3, 1); ncat <- sample(2:3, J, TRUE)
  cl <- sample(1:R, n, TRUE, runif(R, 0.3, 1))
  th <- lapply(seq_len(J), function(j) t(sapply(seq_len(R), function(r) { p <- rgamma(ncat[j], 1.2); p / sum(p) })))
  d <- as.data.frame(sapply(seq_len(J), function(j) sapply(cl, function(c) sample(ncat[j], 1, prob = th[[j]][c, ]))))
  names(d) <- paste0("y", seq_len(J))
  st <- lapply(seq_len(J), function(j) { m <- t(sapply(seq_len(R), function(r) { p <- runif(ncat[j], 0.2, 1); p / sum(p) })); m })
  f <- tryCatch(suppressMessages(poLCA(as.formula(paste("cbind(", paste(names(d), collapse = ","), ") ~ 1")), d, nclass = R, probs.start = st, tol = 1e-13, maxiter = 20000, verbose = FALSE)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, J, R, ncat, unlist(lapply(st, function(m) as.vector(t(m)))), as.vector(t(as.matrix(d))))
  pr <- unlist(lapply(f$probs, function(m) as.vector(t(m))))
  add("ll", a, f$llik); add("prior", a, sum(f$P * seq_along(f$P))); add("probs", a, sum(pr * seq_along(pr))); add("bic", a, f$bic)
  add("npar", a, f$npar); add("aic", a, f$aic); add("gsq", a, f$Gsq); add("chisq", a, f$Chisq); add("rdf", a, f$resid.df)
  add("pred", a, sum(f$predclass * 1))
  if (f$npar <= prod(ncat) - 4 && min(unlist(f$probs)) > 0.02 && min(f$P) > 0.05) {  # the information matrix needs an identified model away from the boundary
  fs <- suppressMessages(poLCA(as.formula(paste("cbind(", paste(names(d), collapse = ","), ") ~ 1")), d, nclass = R, probs.start = st, tol = 1e-13, maxiter = 20000, verbose = FALSE, calc.se = TRUE))
  se <- unlist(lapply(fs$probs.se, function(m) as.vector(t(m))))
  cases[[length(cases) + 1]] <- case("se_probs", a, sum(se * seq_along(se)), rel = 1e-3, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("se_prior", a, sum(fs$P.se * seq_along(fs$P.se)), rel = 1e-3, abs = 1e-6)
  }
}
# standard errors of well-identified two-class fits away from the boundary: "se_probs" "se_prior" with the same arguments as "ll"
for (rep in 1:40) {
  n <- sample(250:500, 1); J <- sample(4:6, 1); R <- 2; ncat <- sample(2:3, J, TRUE)
  cl <- sample(1:R, n, TRUE, c(0.45, 0.55))
  th <- lapply(seq_len(J), function(j) t(sapply(seq_len(R), function(r) { p <- runif(ncat[j], 0.25, 1); if (r == 2) p <- rev(p); p / sum(p) })))
  d <- as.data.frame(sapply(seq_len(J), function(j) sapply(cl, function(c) sample(ncat[j], 1, prob = th[[j]][c, ])))); names(d) <- paste0("y", seq_len(J))
  st <- lapply(seq_len(J), function(j) { m <- t(sapply(seq_len(R), function(r) { p <- runif(ncat[j], 0.2, 1); p / sum(p) })); m })
  fs <- tryCatch(suppressMessages(poLCA(as.formula(paste("cbind(", paste(names(d), collapse = ","), ") ~ 1")), d, nclass = R, probs.start = st, tol = 1e-13, maxiter = 20000, verbose = FALSE, calc.se = TRUE)), error = function(e) NULL)
  if (is.null(fs) || min(unlist(fs$probs)) < 0.01 || min(fs$P) < 0.05) next
  a <- c(n, J, R, ncat, unlist(lapply(st, function(m) as.vector(t(m)))), as.vector(t(as.matrix(d))))
  se <- unlist(lapply(fs$probs.se, function(m) as.vector(t(m))))
  cases[[length(cases) + 1]] <- case("se_probs", a, sum(se * seq_along(se)), rel = 1e-3, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("se_prior", a, sum(fs$P.se * seq_along(fs$P.se)), rel = 1e-3, abs = 1e-6)
}
# random restarts under set.seed: "rs" args (n, J, R, ncat[J], nrep, seed, data[n*J] row-major 1-based, q) q 0 log-likelihood, 1 sum(P * class), 2 sum(probs * position)
for (rep in 1:12) {
  n <- sample(150:350, 1); J <- sample(3:5, 1); R <- 2; ncat <- sample(2:3, J, TRUE)
  cl <- sample(1:R, n, TRUE)
  th <- lapply(seq_len(J), function(j) t(sapply(seq_len(R), function(r) { p <- rgamma(ncat[j], 1.0); p / sum(p) })))
  d <- as.data.frame(sapply(seq_len(J), function(j) sapply(cl, function(c) sample(ncat[j], 1, prob = th[[j]][c, ])))); names(d) <- paste0("y", seq_len(J))
  nrep <- sample(2:4, 1); seed <- sample(1000:99999, 1)
  set.seed(seed)
  f <- tryCatch(suppressMessages(poLCA(as.formula(paste("cbind(", paste(names(d), collapse = ","), ") ~ 1")), d, nclass = R, nrep = nrep, verbose = FALSE)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, J, R, ncat, nrep, seed, as.vector(t(as.matrix(d))))
  pr <- unlist(lapply(f$probs, function(m) as.vector(t(m))))
  cases[[length(cases) + 1]] <- case("rs", c(a, 0), f$llik, rel = 1e-6, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("rs", c(a, 1), sum(f$P^2), rel = 1e-4, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("rs", c(a, 2), sum(pr^2), rel = 1e-4, abs = 1e-6)
}
emit("polca", "poLCA", list(cases))
