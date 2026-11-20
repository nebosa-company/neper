# ipred: bagging (class and regression trees, three aggregations, out-of-bag predictions and error), errorest (cv, boot, 632plus, both) for the models rpart,
# bagging and ipredknn, ipredknn; every draw under set.seed, so the streams must agree value for value.
# Cases: "ds" opens a dataset (the args are its header and data), "bl" (slot) is a result's length and "bq" (slot, j) its j-th value (0-based).
#   scenario 1 bagging: (1, n, p, k, nbagg, ns, coob, minsplit, minbucket, cp, maxdepth, seed, nnew, ncat[p], y[n], x[n*p], newx[nnew*p])
#     slots, class: 1 bindx, 2 frame rows per tree, 3 oob error, 4/5 newdata majority class/prob, 6/7 average class/prob, 8/9 weighted class/prob, 10-15 the same oob
#     slots, regression: 1 bindx, 2 frame rows, 3 oob error, 4 newdata average, 5 weighted, 6 oob average, 7 oob weighted
#   scenario 2 errorest: (2, n, p, k, est, model, nk, strat, random, nbagg, minsplit, minbucket, cp, maxdepth, xval, knnk, seed, ncat[p], y[n], x[n*p])
#     est 1 cv, 2 boot, 3 632plus, 4 both; model 1 rpart, 2 bagging, 3 ipredknn; slots 1 error, 2 k or nboot, 3 sd, 4 predictions, 5 632plus error
#   scenario 3 ipredknn: (3, n, p, k, knnk, nnew, seed, ncat[p], y[n], x[n*p], newx[nnew*p]); slots 1 class, 2 prob
suppressMessages(library(ipred)); suppressMessages(library(rpart))
cases <- list()
slot <- function(s, v, rel = 1e-9, ex = FALSE) {
  v <- as.numeric(v)
  tol <- if (ex) 0 else rel
  c(list(case("bl", s, length(v), rel = 0, abs = 0)), lapply(seq_along(v), function(j) case("bq", c(s, j - 1), v[j], rel = tol, abs = if (ex) 0 else 1e-12)))
}
mkdata <- function(n, p, k, na = FALSE, grid = FALSE, nofac = FALSE) {
  X <- data.frame(row.names = seq_len(n))
  for (j in seq_len(p)) {
    if (!nofac && runif(1) < 0.35) X[[paste0("x", j)]] <- factor(sample.int(L <- sample(2:5, 1), n, replace = TRUE), levels = seq_len(L))
    else X[[paste0("x", j)]] <- if (grid) sample(0:4, n, replace = TRUE) else round(runif(n), 3)
  }
  num1 <- which(!vapply(X, is.factor, TRUE))[1]
  sig <- if (is.na(num1)) 0 else 2 * (X[[num1]] > median(X[[num1]]))
  fx <- vapply(X, is.factor, TRUE)
  eff <- 0; for (j in which(fx)) eff <- eff + (as.integer(X[[j]]) %% 2) * 1.2
  lin <- sig + eff + rnorm(n) * 1.1
  if (k > 0) {
    y <- cut(lin, breaks = quantile(lin, seq(0, 1, length.out = k + 1)), include.lowest = TRUE, labels = FALSE)
    y <- factor(y, levels = seq_len(k))
  } else y <- round(lin, 4)
  if (na) X[[sample(p, 1)]][sample(n, round(n * 0.1))] <- NA
  list(X = X, y = y)
}
flat <- function(X, n) as.vector(do.call(cbind, lapply(X, as.numeric)))
ncats <- function(X) ifelse(vapply(X, is.factor, TRUE), vapply(X, nlevels, 1L), 0L)
newrows <- function(X, nn, p, grid = FALSE) {
  nd <- X[sample(nrow(X), nn, replace = TRUE), , drop = FALSE]
  for (j in seq_len(p)) if (!is.factor(nd[[j]])) nd[[j]] <- if (grid) sample(0:4, nn, replace = TRUE) else round(nd[[j]] + rnorm(nn) * 0.03, 3)
  nd
}
ctlargs <- function() list(ms = sample(c(2, 4, 8), 1), mb = sample(c(1, 2, 3), 1), cp = sample(c(0, 0.01, 0.03), 1), md = sample(c(4, 30), 1))
rc <- function(h) rpart.control(minsplit = h$ms, minbucket = h$mb, cp = h$cp, maxdepth = h$md, xval = 0)
pf <- function(obj, newdata) predict(obj, newdata, type = "class")

set.seed(20261120)
# ---- scenario 1
for (rep in 1:12) {
  k <- c(0, 2, 3, 4)[rep %% 4 + 1]; n <- sample(30:46, 1); p <- sample(2:4, 1)
  dd <- mkdata(n, p, k, na = rep %% 3 == 0); X <- dd$X; y <- dd$y
  h <- ctlargs(); nbagg <- sample(c(10, 25), 1); ns <- if (rep %% 5 == 0) sample(floor(n / 2):floor(0.8 * n), 1) else 0
  coob <- rep %% 2 == 0
  nd <- newrows(X, 20, p); if (p > 1) nd[sample(20, 4), sample(p, 1)] <- NA
  for (r in which(rowSums(is.na(nd)) == p)) nd[r, 1] <- X[[1]][!is.na(X[[1]])][1]
  seed <- sample(1:100000, 1)
  d <- X; d$y__ <- y
  set.seed(seed)
  b <- if (ns > 0) bagging(y__ ~ ., data = d, nbagg = nbagg, ns = ns, coob = coob, control = rc(h)) else bagging(y__ ~ ., data = d, nbagg = nbagg, coob = coob, control = rc(h))
  head <- c(1, n, p, k, nbagg, ns, as.integer(coob), h$ms, h$mb, h$cp, h$md, seed, nrow(nd))
  cases[[length(cases) + 1]] <- case("ds", c(head, ncats(X), as.numeric(y), flat(X), flat(nd)), nbagg, rel = 0, abs = 0)
  sl <- vector("list", 15); ex <- logical(15)
  put <- function(i, v, e) { if (!is.null(v)) sl[[i]] <<- v; ex[i] <<- e }
  put(1, unlist(lapply(b$mtrees, function(t) t$bindx)), TRUE); put(2, vapply(b$mtrees, function(t) nrow(t$btree$frame), 1), TRUE)
  if (coob) put(3, b$err, FALSE)
  at <- 4
  if (k > 0) {
    for (oob in c(FALSE, TRUE)) for (agg in c("majority", "average", "weighted")) {
      if (oob && nbagg < 10) next
      put(at, as.integer(if (oob) predict(b, type = "class", aggregation = agg) else predict(b, nd, type = "class", aggregation = agg)), TRUE)
      put(at + 1, as.vector(t(if (oob) predict(b, type = "prob", aggregation = agg) else predict(b, nd, type = "prob", aggregation = agg))), FALSE)
      at <- at + 2
    }
  } else {
    for (oob in c(FALSE, TRUE)) for (agg in c("average", "weighted")) {
      put(at, if (oob) predict(b, aggregation = agg) else predict(b, nd, aggregation = agg), FALSE)
      at <- at + 1
    }
  }
  for (s in seq_along(sl)) if (!is.null(sl[[s]])) cases <- c(cases, slot(s, sl[[s]], ex = isTRUE(ex[s])))
}
# ---- scenario 2
for (rep in 1:24) {
  est <- c(1, 2, 3, 4)[rep %% 4 + 1]
  model <- c(1, 2, 3)[(rep %/% 4) %% 3 + 1]
  k <- if (model == 3) sample(2:3, 1) else c(0, 2, 3)[sample(3, 1)]
  if (est >= 3 && k == 0) k <- 2
  n <- sample(30:60, 1); p <- sample(2:4, 1)
  dd <- mkdata(n, p, k, grid = model == 3); X <- dd$X; y <- dd$y
  h <- ctlargs(); nbagg <- sample(c(3, 5, 8), 1); xval <- if (model == 1) sample(c(0, 4), 1) else 0; knnk <- sample(c(1, 3, 5), 1)
  nk <- if (est == 1) sample(c(3, 5, 10), 1) else sample(c(5, 10), 1)
  strat <- if (est == 1 && k > 0) rep %% 2 == 0 else FALSE; random <- !(rep %% 7 == 0 && est == 1)
  seed <- sample(1:100000, 1)
  d <- X; d$y__ <- y
  ec <- control.errorest(k = nk, nboot = nk, strat = strat, random = random, predictions = TRUE)
  rcx <- rpart.control(minsplit = h$ms, minbucket = h$mb, cp = h$cp, maxdepth = h$md, xval = xval)
  estim <- list("cv", "boot", "632plus", c("boot", "632plus"))[[est]]
  set.seed(seed)
  r <- if (model == 1) errorest(y__ ~ ., data = d, model = rpart, predict = if (k > 0) pf else NULL, estimator = estim, est.para = ec, control = rcx)
       else if (model == 2) errorest(y__ ~ ., data = d, model = bagging, estimator = estim, est.para = ec, nbagg = nbagg, control = rc(h))
       else errorest(y__ ~ ., data = d, model = function(formula, data) ipredknn(formula, data, k = knnk), predict = pf, estimator = estim, est.para = ec)
  head <- c(2, n, p, k, est, model, nk, as.integer(strat), as.integer(random), nbagg, h$ms, h$mb, h$cp, h$md, xval, knnk, seed)
  cases[[length(cases) + 1]] <- case("ds", c(head, ncats(X), as.numeric(y), flat(X)), est, rel = 0, abs = 0)
  pv <- function(q) if (is.data.frame(q)) as.vector(t(sapply(q, as.integer))) else if (is.matrix(q)) as.vector(t(q)) else as.numeric(q)
  main <- if (est == 4) r$boot else r
  sl <- list(main$error, if (est == 1) r$k else main$nboot, if ((est == 2 || est == 4) && k > 0) main$sd else NaN, pv(main$predictions), if (est == 4) r$`632plus`$error else NaN)
  if (est >= 2) { pvv <- sl[[4]]; okp <- !is.na(pvv); sl[[4]] <- sum(pvv[okp] * which(okp)); sl[[6]] <- sum(!okp) }
  for (s in seq_along(sl)) cases <- c(cases, slot(s, sl[[s]], ex = (s == 2 || s == 6 || (s == 4 && k > 0))))
}
# ---- scenario 3
for (rep in 1:12) {
  k <- sample(2:3, 1); n <- sample(25:60, 1); p <- sample(2:4, 1)
  dd <- mkdata(n, p, k, grid = TRUE); X <- dd$X; y <- dd$y
  kk <- sample(c(1, 3, 5, 7), 1); nd <- newrows(X, 25, p, grid = TRUE); seed <- sample(1:100000, 1)
  d <- X; d$y__ <- y
  set.seed(seed)
  m <- ipredknn(y__ ~ ., data = d, k = kk)
  cl <- as.integer(predict(m, nd, type = "class")); pr <- predict(m, nd, type = "prob")
  cases[[length(cases) + 1]] <- case("ds", c(3, n, p, k, kk, nrow(nd), seed, ncats(X), as.numeric(y), flat(X), flat(nd)), 1, rel = 0, abs = 0)
  cases <- c(cases, slot(1, cl, ex = TRUE), slot(2, pr))
}
# ---- scenario 4: inbagg
for (rep in 1:12) {
  k <- sample(2:3, 1); n <- sample(36:56, 1); p <- sample(2:3, 1); q <- sample(1:2, 1)
  wkind <- c(1, 2)[rep %% 2 + 1]; X <- mkdata(n, p, 0, nofac = wkind == 1)$X
  nx <- vapply(X, function(v) as.numeric(v), numeric(n))
  W <- vapply(seq_len(q), function(j) round(1.5 * nx[, 1] + 0.8 * nx[, p] + rnorm(n) * 0.4, 4), numeric(n))
  lin <- W[, 1] + (if (q > 1) 0.5 * W[, 2] else 0) + rnorm(n) * 0.6
  y <- factor(cut(lin, breaks = quantile(lin, seq(0, 1, length.out = k + 1)), include.lowest = TRUE, labels = FALSE), levels = seq_len(k))
  h <- ctlargs(); wkind <- c(1, 2)[rep %% 2 + 1]; wxval <- if (wkind == 2) sample(c(0, 4), 1) else 0; wms <- sample(c(5, 20), 1)
  nbagg <- sample(c(5, 8), 1); nsfrac <- c(0.5, 0.7, 1)[sample(3, 1)]; replace <- nsfrac == 1
  wtr <- sample(0:2, 1)
  nd <- newrows(X, 20, p); seed <- sample(1:100000, 1)
  xn <- paste0("x", seq_len(p)); wn <- paste0("w", seq_len(q))
  d <- data.frame(y = y, X, W); colnames(d) <- c("y", xn, wn)
  fo <- as.formula(paste("y ~", paste(wn, collapse = "+"), "~", paste(xn, collapse = "+")))
  wmodel <- if (wkind == 1) lm else function(formula, data) rpart(formula, data, control = rpart.control(minsplit = wms, xval = wxval))
  pF <- list(list(model = wmodel), training.set = c("oob", "bag", "all")[wtr + 1])
  cF <- list(model = function(formula, data) rpart(formula, data, control = rc(h)), predict = function(object, newdata) predict(object, newdata, type = "class"),
             training.set = "fitted.bag")
  set.seed(seed)
  ib <- inbagg(fo, data = d, pFUN = pF, cFUN = cF, nbagg = nbagg, ns = nsfrac, replace = replace)
  pr <- predict(ib, nd)
  head <- c(4, n, p, k, q, nbagg, nsfrac, as.integer(replace), wkind, wxval, wms, wtr, h$ms, h$mb, h$cp, h$md, seed, nrow(nd))
  cases[[length(cases) + 1]] <- case("ds", c(head, ncats(X), as.numeric(y), flat(X), as.vector(W), flat(nd)), 1, rel = 0, abs = 0)
  cases <- c(cases, slot(1, unlist(lapply(ib$mtrees, function(t) t$bindx)), ex = TRUE),
             slot(2, vapply(ib$mtrees, function(t) nrow(t$btree$model$frame), 1), ex = TRUE),
             slot(3, unlist(lapply(ib$mtrees, function(t) as.vector(as.matrix(t$bfct(nd)))))),
             slot(4, match(as.character(pr), levels(y)), ex = TRUE))
}
emit("ipredbag", c("ipred", "rpart"), list(cases))
