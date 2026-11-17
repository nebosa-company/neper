# drdid_full: every DRDID estimator (panel, repeated cross-section, improved, twfe) with its influence function and either the analytic standard error or the
# multiplier / weighted bootstrap under set.seed. One case per fit: want is 0 (the number of mismatches the fixture counts) and the args carry everything:
#   kind, boot (0 none, 1 multiplier, 2 weighted), nboot, seed, trim.level, n, p, y_a (n), y_b (n), D (n), covariates row-major (n by p), i.weights (n), expected (11)
# y_a, y_b are y1 and y0 for the panel kinds and y and post for the cross-section kinds. expected: ATT, se, lci, uci, inf[1], inf[n/2], inf[n], sum(inf * i) / n,
# boots[1], boots[B], sum(boots * i) / B. Fits where DRDID falls back on its secondary IPT algorithm or fails are left out.
suppressMessages(library(DRDID))
cases <- list()
fns <- list(
  "0" = reg_did_panel, "1" = ipw_did_panel, "2" = std_ipw_did_panel, "3" = drdid_panel, "4" = drdid_imp_panel, "5" = twfe_did_panel,
  "10" = reg_did_rc, "11" = ipw_did_rc, "12" = std_ipw_did_rc, "13" = drdid_rc, "14" = drdid_rc1, "15" = drdid_imp_rc, "16" = drdid_imp_rc1, "17" = twfe_did_rc)
panel <- function(k) k < 10
add_case <- function(kind, boot, nboot, seed, trim, n, p, ya, yb, D, X, iw, f) {
  fit <- tryCatch({
    set.seed(seed)
    if (panel(kind)) {
      a <- list(y1 = ya, y0 = yb, D = D, covariates = X, i.weights = iw)
    } else {
      a <- list(y = ya, post = yb, D = D, covariates = X, i.weights = iw)
    }
    a$boot <- boot > 0; a$boot.type <- c("weighted", "multiplier", "weighted")[boot + 1]; a$nboot <- nboot; a$inffunc <- TRUE
    if (!kind %in% c(0, 5, 10, 17)) a$trim.level <- trim
    withCallingHandlers(do.call(f, a), warning = function(w) if (grepl("secondary IPT", conditionMessage(w))) stop("flag"))
  }, error = function(e) NULL)
  if (is.null(fit)) return(invisible())
  inf <- as.vector(fit$att.inf.func); b <- fit$boots
  if (boot == 0) b <- c(0, 0, 0)
  bm <- length(b)
  exp <- c(fit$ATT, fit$se, fit$lci, fit$uci, inf[1], inf[ceiling(n / 2)], inf[n], sum(inf * seq_len(n)) / n,
           b[1], b[bm], sum(b * seq_len(bm)) / bm)
  if (boot == 0) exp[9:11] <- 0
  if (!all(is.finite(exp))) return(invisible())
  cases[[length(cases) + 1]] <<- case("run", c(kind, boot, nboot, seed, trim, n, p, ya, yb, D, as.vector(t(X)), iw, exp), 0, rel = 0, abs = 0)
}
gen <- function(kind, n, p, weighted, seed) {
  set.seed(seed)
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 4), n, p - 1))
  D <- rbinom(n, 1, plogis(0.3 * X[, p] - 0.2)); if (p == 1) D <- rbinom(n, 1, 0.4)
  iw <- if (weighted) round(runif(n, 0.4, 2.2), 3) else rep(1, n)
  if (panel(kind)) {
    y0 <- round(rnorm(n, X %*% rep(1, p)), 4)
    y1 <- round(y0 + 0.5 + 0.3 * X[, p] + 0.8 * D + rnorm(n, 0, 0.5), 4)
    list(n = n, p = p, ya = y1, yb = y0, D = D, X = X, iw = iw)
  } else {
    post <- rbinom(n, 1, 0.5)
    y <- round(as.vector(X %*% rep(1, p)) + 0.4 * post + 0.2 * D + 0.9 * D * post + 0.2 * X[, p] * D + rnorm(n, 0, 0.6), 4)
    list(n = n, p = p, ya = y, yb = post, D = D, X = X, iw = iw)
  }
}
seed <- 6000
for (kn in names(fns)) {
  kind <- as.numeric(kn)
  for (cfg in 1:4) {
    seed <- seed + 1
    n <- c(90, 120, 70, 150)[cfg]; p <- c(2, 3, 1, 3)[cfg]
    d <- gen(kind, n, p, cfg %% 2 == 0, seed)
    add_case(kind, 0, 0, 0, 0.995, n, p, d$ya, d$yb, d$D, d$X, d$iw, fns[[kn]])
  }
  seed <- seed + 1
  d <- gen(kind, 110, 2, TRUE, seed)
  set.seed(seed + 900); d$D <- rbinom(110, 1, plogis(1.6 * d$X[, 2]))
  add_case(kind, 0, 0, 0, 0.8, 110, 2, d$ya, d$yb, d$D, d$X, d$iw, fns[[kn]])
  for (bt in 1:2) {
    seed <- seed + 1
    n <- 60; p <- 2
    d <- gen(kind, n, p, bt == 2, seed)
    add_case(kind, bt, 30, seed + 500, 0.995, n, p, d$ya, d$yb, d$D, d$X, d$iw, fns[[kn]])
  }
}
emit("drdid_full", c("DRDID", "fastglm", "trust"), list(cases))
