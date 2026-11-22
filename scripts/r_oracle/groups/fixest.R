# fixest: feols (fixed effects, IV), fepois, feglm (logit), femlm, the vcov families, wald, predict and sunab.
#   args header: (fam, n, nx, ne, nz, nf, vk, ncl, lag, x1, x2) then y[n], x[n*nx], en[n*ne], z[n*nz], fe[n*nf] (0-based), cl[n*ncl]
#   row-major, then kind-specific tail. fn = coef | se | t | p | df | kfull | kcl | wald_stat | wald_p | pred | sunab_coef | sunab_se
#   (vectors enter as sum(value * position)). vk: 0 iid, 1 hetero, 2 cluster (1 or 2 variables), 3 NW (unit, time), 4 DK (time).
#   Data are rounded to multiples of 1/64 so the JSON stays short; R fits the rounded data. fixef.tol 3e-12, glm.tol 3e-13.
suppressMessages(library(fixest))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(v))
r64 <- function(v) round(v * 64) / 64
LAGD <- 1000000
mat <- function(d, cols, sub = 0) if (length(cols)) as.matrix(d[, cols, drop = FALSE]) - sub else matrix(0, nrow(d), 0)
pack <- function(d, fam, xs, ens, zs, fes, vk, cls, lag, x1 = 0, x2 = 0, tail = NULL, cl_sub = 1) {
  n <- nrow(d)
  c(fam, n, length(xs), length(ens), length(zs), length(fes), vk, length(cls), lag, x1, x2, d$y,
    as.vector(t(mat(d, xs))), as.vector(t(mat(d, ens))), as.vector(t(mat(d, zs))), as.vector(t(mat(d, fes, 1))),
    as.vector(t(mat(d, cls, cl_sub))), tail)
}
# the vcov specs: name -> list(vk, rv (R vcov), cls (columns), sub (cluster code offset), lag)
specs <- function(has_panel, cl_cols) {
  s <- list(iid = list(0, "iid", character(), 1, 0), het = list(1, "hetero", character(), 1, 0))
  for (nm in names(cl_cols)) s[[nm]] <- list(2, cl_cols[[nm]]$rv, cl_cols[[nm]]$cols, 1, 0)
  if (has_panel) {
    s$nw <- list(3, NW ~ id + tt, c("id", "tt"), 0, LAGD); s$nw2 <- list(3, NW(2) ~ id + tt, c("id", "tt"), 0, 2)
    s$dk <- list(4, DK ~ tt, "tt", 0, LAGD); s$dk1 <- list(4, DK(1) ~ tt, "tt", 0, 1)
  }
  s
}
fitols <- function(d, xs, fes, ens = character(), zs = character()) {
  rhs <- paste(xs, collapse = " + "); fe <- paste(fes, collapse = " + ")
  f <- if (length(ens)) paste0("y ~ ", rhs, " | ", fe, " | ", paste(ens, collapse = " + "), " ~ ", paste(zs, collapse = " + ")) else paste0("y ~ ", rhs, " | ", fe)
  feols(as.formula(f), d, fixef.tol = 3e-12, fixef.iter = 100000, panel.id = if (all(c("id", "tt") %in% names(d))) ~id + tt else NULL)
}
ordcoef <- function(v, xs, ens) v[c(xs, if (length(ens)) paste0("fit_", ens))]
# every cheap check of one fitted model under every vcov spec
suite <- function(d, m, fam, xs, ens, zs, fes, sp, kinds = c("se", "t", "p"), wald = TRUE) {
  stat <- function(x) as.numeric(x)
  add("coef", pack(d, fam, xs, ens, zs, fes, 0, character(), 0), ws(ordcoef(coef(m), xs, ens)))
  for (nm in names(sp)) {
    s <- sp[[nm]]; sm <- summary(m, vcov = s[[2]]); ct <- sm$coeftable; rn <- rownames(ct)
    ix <- match(c(xs, if (length(ens)) paste0("fit_", ens)), rn)
    a <- pack(d, fam, xs, ens, zs, fes, s[[1]], s[[3]], s[[5]], cl_sub = s[[4]])
    if ("se" %in% kinds) add("se", a, ws(ct[ix, 2]))
    if ("t" %in% kinds) add("t", a, ws(ct[ix, 3]))
    if ("p" %in% kinds) add("p", a, ws(ct[ix, 4]))
    if (nm %in% c("iid", "cl") && length(ens) == 0 && wald) {
      for (kk in c("stat", "p")) {
        w <- wald(m, keep = "^x[0-9]", vcov = s[[2]], print = FALSE)
        a2 <- pack(d, fam, xs, ens, zs, fes, s[[1]], s[[3]], s[[5]], x1 = 0, x2 = length(xs), cl_sub = s[[4]])
        add(paste0("wald_", kk), a2, w[[kk]])
      }
    }
  }
}
mk_fe <- function(n, G) sample(rep_len(seq_len(G), n))

set.seed(20261217)
# ---- 1. least squares, 1 to 3 fixed effects, cross-section clusters (one a fixed effect), two-way
for (rep in 1:6) {
  nf <- c(1, 2, 3)[(rep - 1) %% 3 + 1]; nx <- sample(1:3, 1); n <- sample(70:110, 1)
  G <- sample(5:9, nf, TRUE)
  d <- data.frame(y = 0, mk = 0)[rep(1, n), ]; rownames(d) <- NULL
  for (j in seq_len(nf)) d[[paste0("f", j)]] <- mk_fe(n, G[j])
  X <- matrix(rnorm(n * nx), n); for (k in 1:nx) d[[paste0("x", k)]] <- r64(X[, k] + 0.3 * rnorm(G[1])[d$f1])
  d$c1 <- mk_fe(n, sample(6:10, 1)); d$c2 <- mk_fe(n, sample(4:6, 1))
  yy <- 0; for (k in 1:nx) yy <- yy + d[[paste0("x", k)]] * (k - 1.5)
  d$y <- r64(yy + rnorm(G[1])[d$f1] + rnorm(n)); d$mk <- NULL
  xs <- paste0("x", 1:nx); fes <- paste0("f", 1:nf)
  m <- fitols(d, xs, fes)
  stopifnot(nobs(m) == n)
  cc <- list(cl = list(rv = ~c1, cols = "c1"), clf = list(rv = ~f1, cols = "f1"), tw = list(rv = ~c1 + c2, cols = c("c1", "c2")),
             twf = list(rv = ~f1 + c2, cols = c("f1", "c2")))
  suite(d, m, 0, xs, character(), character(), fes, specs(FALSE, cc), kinds = if (rep %% 3 == 1) c("se", "t", "p") else "se")
  add("df", pack(d, 0, xs, character(), character(), fes, 0, character(), 0), degrees_freedom(summary(m, vcov = "iid"), "t"))
  add("kfull", pack(d, 0, xs, character(), character(), fes, 0, character(), 0), m$nparams)
  if (rep == 1) {
    # predict
    rows <- c(3, 11, 25, 40, 60); nd <- d[rows, ]; nd[xs] <- nd[xs] + 0.5
    pr <- predict(m, nd)
    nx2 <- as.vector(t(as.matrix(nd[, xs]))); nf2 <- as.vector(t(as.matrix(nd[, fes]) - 1))
    add("pred", pack(d, 0, xs, character(), character(), fes, 0, character(), 0, x1 = length(rows), x2 = 1, tail = c(nx2, nf2)), ws(pr))
  }
}
# ---- 2. panels: Newey-West, Driscoll-Kraay (balanced and unbalanced), clustered by unit and two-way
for (rep in 1:4) {
  G <- sample(c(8, 12, 6, 10), 1); T <- sample(c(7, 9, 12, 20), 1); unb <- rep %% 2 == 0
  d <- data.frame(id = rep(seq_len(G), each = T), tt = rep(seq_len(T), G))
  if (unb) d <- d[sort(sample(nrow(d), round(nrow(d) * 0.85))), ]
  n <- nrow(d); rownames(d) <- NULL
  d$f1 <- d$id; d$f2 <- d$tt
  d$x1 <- r64(rnorm(n) + 0.3 * rnorm(G)[d$id]); d$x2 <- r64(rnorm(n))
  d$y <- r64(d$x1 - 0.7 * d$x2 + rnorm(G)[d$id] + 0.3 * rnorm(T)[d$tt] + 0.5 * rnorm(n))
  d$c2 <- mk_fe(n, 5)
  xs <- c("x1", "x2"); fes <- c("f1", "f2")
  m <- fitols(d, xs, fes)
  cc <- list(cl = list(rv = ~id, cols = "id"), tw = list(rv = ~id + c2, cols = c("id", "c2")))
  suite(d, m, 0, xs, character(), character(), fes, specs(TRUE, cc), kinds = c("se", "p"), wald = (rep == 1))
}
# ---- 3. instrumental variables
for (rep in 1:5) {
  nf <- c(1, 2)[rep %% 2 + 1]; ne <- if (rep >= 4) 2 else 1; nz <- ne + sample(1:2, 1); n <- sample(90:130, 1)
  G <- sample(6:9, 2, TRUE)
  d <- data.frame(f1 = mk_fe(n, G[1]), f2 = mk_fe(n, G[2]), c1 = mk_fe(n, 8))
  d$x1 <- r64(rnorm(n)); u <- rnorm(n)
  zs <- paste0("z", 1:nz); ens <- paste0("en", 1:ne)
  for (z in zs) d[[z]] <- r64(rnorm(n))
  for (k in 1:ne) d[[ens[k]]] <- r64(0.6 * d[[zs[k]]] - 0.4 * d[[zs[nz]]] + 0.4 * u + rnorm(n) + 0.3 * rnorm(G[1])[d$f1])
  d$y <- r64(d$x1 + 1.5 * d$en1 + (if (ne == 2) -d$en2 else 0) + u + rnorm(G[1])[d$f1])
  xs <- "x1"; fes <- paste0("f", 1:nf)
  m <- fitols(d, xs, fes, ens, zs)
  stopifnot(nobs(m) == n)
  cc <- list(cl = list(rv = ~c1, cols = "c1"), tw = list(rv = ~c1 + f1, cols = c("c1", "f1")))
  suite(d, m, 0, xs, ens, zs, fes, specs(FALSE, cc), kinds = c("se", "t", "p"))
}
# ---- 4. fepois, feglm (logit), femlm
glm_data <- function(n, nf, G, fam) {
  d <- data.frame(x1 = r64(rnorm(n)), x2 = r64(rnorm(n)))
  for (j in seq_len(nf)) d[[paste0("f", j)]] <- mk_fe(n, G[j])
  d$c1 <- mk_fe(n, 9); d$c2 <- mk_fe(n, 5)
  eta <- 0.3 * d$x1 - 0.2 * d$x2 + 0.3 * rnorm(G[1])[d$f1] + (if (nf > 1) 0.3 * rnorm(G[2])[d$f2] else 0) + (if (fam == 1) 0.4 else 0)
  d$y <- if (fam == 1) rpois(n, exp(eta)) else rbinom(n, 1, plogis(eta))
  d
}
for (rep in 1:6) {
  fam <- c(1, 2)[rep %% 2 + 1]; nf <- c(1, 2, 3)[(rep - 1) %% 3 + 1]; n <- sample(100:150, 1); G <- sample(5:8, 3, TRUE)
  repeat {
    d <- glm_data(n, nf, G, fam); xs <- c("x1", "x2"); fes <- paste0("f", 1:nf)
    fm <- as.formula(paste("y ~ x1 + x2 |", paste(fes, collapse = " + ")))
    m <- tryCatch(suppressWarnings(if (fam == 1) fepois(fm, d, fixef.tol = 3e-12, glm.tol = 3e-13, glm.iter = 500) else
      feglm(fm, d, family = "binomial", fixef.tol = 3e-12, glm.tol = 3e-13, glm.iter = 500)), error = function(e) NULL)
    if (!is.null(m) && nobs(m) == n && m$iterations < 30) break
  }
  cc <- list(cl = list(rv = ~c1, cols = "c1"), tw = list(rv = ~c1 + c2, cols = c("c1", "c2")))
  sp <- specs(FALSE, cc); sp$tw <- NULL
  suite(d, m, fam, xs, character(), character(), fes, sp, kinds = c("se", "t", "p"))
  add("kfull", pack(d, fam, xs, character(), character(), fes, 0, character(), 0), m$nparams)
  add("dev", pack(d, fam, xs, character(), character(), fes, 0, character(), 0), m$deviance, rel = 1e-9)
  if (rep <= 2) {
    rows <- c(2, 17, 33, 50, 71); nd <- d[rows, ]; nd[xs] <- nd[xs] + 0.5
    nx2 <- as.vector(t(as.matrix(nd[, xs]))); nf2 <- as.vector(t(as.matrix(nd[, fes]) - 1))
    for (lk in 0:1) add("pred", pack(d, fam, xs, character(), character(), fes, 0, character(), 0, x1 = length(rows), x2 = lk, tail = c(nx2, nf2)),
                        ws(predict(m, nd, type = if (lk) "link" else "response")), rel = 1e-9)
  }
  if (rep <= 4) {
    # femlm maximises the same likelihood with its own optimiser (R's own convergence tolerance, looser than 1e-9)
    ml <- femlm(fm, d, family = if (fam == 1) "poisson" else "logit")
    a0 <- pack(d, fam, xs, character(), character(), fes, 0, character(), 0)
    add("coef", a0, ws(coef(ml)), rel = 1e-6, abs = 1e-8)
    add("se", a0, ws(se(ml, vcov = "iid")), rel = 1e-6, abs = 1e-8)
    a1 <- pack(d, fam, xs, character(), character(), fes, 1, character(), 0)
    add("se", a1, ws(se(ml, vcov = "hetero")), rel = 1e-6, abs = 1e-8)
  }
}
# ---- 5. Sun-Abraham
for (rep in 1:3) {
  N <- c(36, 40, 30)[rep]; T <- c(9, 10, 8)[rep]; cohs <- list(c(3, 5, 7), c(4, 6, 8), c(3, 5))[[rep]]
  d <- data.frame(id = rep(seq_len(N), each = T), tt = rep(seq_len(T), N))
  n <- nrow(d); d$coh <- sample(c(cohs, 1000), N, TRUE)[d$id]
  d$x1 <- r64(rnorm(n)); rel <- d$tt - d$coh
  d$y <- r64(0.5 * d$x1 + rnorm(N)[d$id] + 0.2 * d$tt + ifelse(d$coh < 1000 & rel >= 0, 1 + 0.3 * rel + 0.2 * (d$coh == cohs[2]), 0) + rnorm(n))
  d$f1 <- d$id; d$f2 <- d$tt
  m <- feols(y ~ x1 + sunab(coh, tt) | f1 + f2, d, fixef.tol = 3e-12, fixef.iter = 100000, panel.id = ~id + tt)
  mn <- feols(y ~ x1 + sunab(coh, tt, no_agg = TRUE) | f1 + f2, d, fixef.tol = 3e-12, fixef.iter = 100000)
  stopifnot(length(mn$collin.var) == 0)
  for (nm in c("iid", "het", "cl")) {
    rv <- list(iid = "iid", het = "hetero", cl = ~id)[[nm]]; vk <- c(iid = 0, het = 1, cl = 2)[[nm]]
    a <- c(0, n, 1, 0, 0, 2, vk, if (vk == 2) 1 else 0, 0, 1000, 0, d$y, d$x1, d$coh, d$tt, as.vector(t(cbind(d$f1, d$f2) - 1)), if (vk == 2) d$id - 1)
    add("sunab_coef", a, ws(coef(m)))
    add("sunab_se", a, ws(se(m, vcov = rv)))
  }
}
emit("fixest", "fixest", list(cases))
