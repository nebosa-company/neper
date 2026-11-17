# mclust, fifth part: sim under set.seed, predict.Mclust / cdens / estep / dens at new data, and one M step.
# model index: E 0 V 1 EII 2 VII 3 EEI 4 VEI 5 EVI 6 VVI 7 EEE 8 EVE 9 VEE 10 VVE 11 EEV 12 VEV 13 EVV 14 VVV 15
# "sim" (model, d, G, n, seed, id, Ls, Lh, Lo, Lg, pro[G], mu[d G], scale[Ls], shape[Lh], orientation[Lo], sigma[Lg]): id 0 sum(i * group[i]), 1 sum(q * x[q]) over the n by d draws column-major
# "pred" (model, n, d, G, id, pro[G], mu[d G], sigma[G d d], X[n d]): id 0 sum(q * log cdens), 1 sum(q * predict z), 2 sum(i * classification), 3 estep loglik, 4 sum(i * dens)
# "mstp" (model, n, d, G, id, X[n d], z[n G]): id 0 sum(q * pro), 1 sum(q * mean), 2 sum(q * sigma)
suppressMessages(library(mclust))
cases <- list()
set.seed(20261203)
tbl <- c("E", "V", "EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EVE", "VEE", "VVE", "EEV", "VEV", "EVV", "VVV")
rorth <- function(d) qr.Q(qr(matrix(rnorm(d * d), d)))
for (rep in 1:48) {
  mi <- (rep - 1) %% 16; mn <- tbl[mi + 1]
  d <- if (mi <= 1) 1 else sample(2:4, 1); G <- sample(1:4, 1); n <- sample(5:60, 1); sd <- sample(1:100000, 1)
  pro <- runif(G); pro <- pro / sum(pro); if (rep > 32) pro <- rep(1 / G, G)
  mu <- matrix(rnorm(d * G), d, G)
  sc1 <- runif(1, 0.5, 2); scG <- runif(G, 0.5, 2); sh1 <- runif(d, 0.5, 2); shG <- matrix(runif(d * G, 0.5, 2), d, G)
  Sig <- crossprod(matrix(rnorm(d * d), d)) + diag(d) * 0.5; SigG <- array(0, c(d, d, G)); for (k in 1:G) SigG[, , k] <- crossprod(matrix(rnorm(d * d), d)) + diag(d) * 0.5
  O1 <- rorth(d); OG <- array(0, c(d, d, G)); for (k in 1:G) OG[, , k] <- rorth(d)
  v <- switch(mn,
    E = list(sigmasq = sc1), V = list(sigmasq = scG), EII = list(sigmasq = sc1), VII = list(sigmasq = scG),
    EEI = list(scale = sc1, shape = sh1), VEI = list(scale = scG, shape = sh1), EVI = list(scale = sc1, shape = shG), VVI = list(scale = scG, shape = shG),
    EEE = list(Sigma = Sig), VVV = list(sigma = SigG),
    EEV = list(scale = sc1, shape = sh1, orientation = OG), VEV = list(scale = scG, shape = sh1, orientation = OG), EVV = list(scale = sc1, shape = shG, orientation = OG),
    VEE = list(scale = scG, shape = sh1, orientation = O1), EVE = list(scale = sc1, shape = shG, orientation = O1), VVE = list(scale = scG, shape = shG, orientation = O1))
  par <- list(pro = pro, mean = if (d == 1) as.vector(mu) else mu, variance = v)
  s <- sim(mn, par, n, seed = sd)
  sig <- if (!is.null(v$Sigma)) v$Sigma else if (!is.null(v$sigma)) v$sigma else numeric(0)
  # the sigma slot of the layout carries sigmasq for E, V, EII and VII
  sg <- if (mn %in% c("E", "V", "EII", "VII")) v$sigmasq else as.vector(sig)
  sc <- if (mn %in% c("E", "V", "EII", "VII", "EEE", "VVV")) numeric(0) else v$scale
  sh <- if (is.null(v$shape)) numeric(0) else as.vector(v$shape)
  or <- if (is.null(v$orientation)) numeric(0) else as.vector(v$orientation)
  args <- c(mi, d, G, n, sd)
  tail <- c(length(sc), length(sh), length(or), length(sg), pro, mu, sc, sh, or, sg)
  xs <- as.vector(s[, -1, drop = FALSE])
  cases[[length(cases) + 1]] <- case("sim", c(args, 0, tail), sum(seq_len(n) * s[, 1]), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("sim", c(args, 1, tail), sum(seq_along(xs) * xs), rel = 1e-9, abs = 1e-9)
}
for (rep in 1:32) {
  mi <- (rep - 1) %% 16; mn <- tbl[mi + 1]
  d <- if (mi <= 1) 1 else sample(2:3, 1); n <- sample(60:100, 1); cl <- sample(2, n, TRUE)
  X <- matrix(rnorm(n * d), n, d) * rep(runif(d, 0.6, 1.5), each = n) + 2.5 * (cl - 1)
  m <- tryCatch(suppressWarnings(Mclust(X, G = 2:3, modelNames = mn, verbose = FALSE)), error = function(e) NULL)
  if (is.null(m) || m$modelName != mn) next
  G <- m$G; nn <- sample(5:20, 1); Xn <- matrix(rnorm(nn * d) * 1.5 + 1, nn, d)
  P <- m$parameters; sg <- P$variance$sigma; if (mn == "E") sg <- rep(sg, G)
  pr <- predict(m, Xn); cd <- cdens(modelName = mn, data = Xn, logarithm = TRUE, parameters = P); es <- estep(Xn, mn, P); dn <- dens(modelName = mn, data = Xn, parameters = P)
  args <- c(mi, nn, d, G); tail <- c(P$pro, P$mean, sg, Xn)
  cases[[length(cases) + 1]] <- case("pred", c(args, 0, tail), sum(seq_along(cd) * as.vector(cd)), rel = 1e-9, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("pred", c(args, 1, tail), sum(seq_along(pr$z) * as.vector(pr$z)), rel = 1e-9, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("pred", c(args, 2, tail), sum(seq_len(nn) * pr$classification), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("pred", c(args, 3, tail), es$loglik, rel = 1e-9, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("pred", c(args, 4, tail), sum(seq_len(nn) * dn), rel = 1e-9, abs = 1e-9)
}
for (rep in 1:48) {
  mi <- (rep - 1) %% 16; mn <- tbl[mi + 1]
  d <- if (mi <= 1) 1 else sample(2:3, 1); G <- sample(2:3, 1); n <- sample(50:90, 1); cl <- sample(G, n, TRUE)
  X <- matrix(rnorm(n * d), n, d) * rep(runif(d, 0.6, 1.5), each = n) + 2.5 * (cl - 1)
  z <- 0.7 * unmap(cl) + 0.3 * matrix(runif(n * G), n, G); z <- z / rowSums(z)
  ms <- tryCatch(suppressWarnings(mstep(X, mn, z)), error = function(e) NULL)
  if (is.null(ms) || attr(ms, "returnCode") < 0) next
  P <- ms$parameters; sg <- P$variance$sigma; if (mn == "E") sg <- rep(sg, G)
  args <- c(mi, n, d, G); tail <- c(X, z)
  cases[[length(cases) + 1]] <- case("mstp", c(args, 0, tail), sum(seq_along(P$pro) * P$pro), rel = 1e-6, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("mstp", c(args, 1, tail), sum(seq_along(P$mean) * as.vector(P$mean)), rel = 1e-6, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("mstp", c(args, 2, tail), sum(seq_along(sg) * as.vector(sg)), rel = 1e-6, abs = 1e-9)
}
emit("mclust5", "mclust", list(cases))
