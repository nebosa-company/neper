# kernlab ksvm multi-class C-svc / nu-svc (voting, class weights, scaled data, probability models with the couplers) and the regression probability model.
#   class args: (n, p, K, ktype, svm, C, nu, gamma, degree, coef0, scaled, prob, weighted, seed, nt, w[K], cls[n] 1-based, x[n*p] row-major, xt[nt*p] row-major)
#     fn "coef" (all pairs' signed coefficients concatenated, position-weighted) "b" "obj" "dec" "votes" "resp" "prob" "prob_pkpd" "prob_vote" "ab" (A, B per pair)
#   regression args: (n, p, ktype, svm, C, nu, eps, gamma, degree, coef0, scaled, prob, seed, nt, y[n], x[n*p], xt[nt*p]); fn "r_coef" "r_b" "r_pred" "r_pm"
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(v))
kinds <- c(2, 1, 0, 3, 5, 7)
mk <- function(kt, sg, dg, off) switch(as.character(kt), "0" = vanilladot(), "1" = polydot(dg, sg, off), "2" = rbfdot(sg), "3" = tanhdot(sg * 0.3, off - 0.5),
                                    "5" = laplacedot(sg), "7" = anovadot(sg, dg))
gm <- function(kt, sg) switch(as.character(kt), "0" = 0, "1" = sg, "2" = sg, "3" = sg * 0.3, "5" = sg, "7" = sg)
cf <- function(kt, off) switch(as.character(kt), "1" = off, "3" = off - 0.5, 0)
set.seed(20261403)
for (rep in 1:48) {
  kt <- kinds[(rep - 1) %% 6 + 1]; K <- c(2, 3, 4)[(rep - 1) %/% 6 %% 3 + 1]; sv <- if (rep %% 4 == 0) 1 else 0
  p <- sample(2:4, 1); per <- sample(8:14, 1); n <- K * per
  ctr <- matrix(rnorm(K * p, 0, 1.2), K)
  cls <- rep(1:K, per)[sample(n)]
  x <- ctr[cls, , drop = FALSE] + matrix(rnorm(n * p, 0, 1), n)
  xt <- matrix(rnorm(8 * p, 0, 1.5), 8)
  C <- runif(1, 0.5, 8); nu <- runif(1, 0.1, 0.4); sg <- runif(1, 0.1, 1.0); dg <- sample(2:3, 1); off <- runif(1, 0, 1)
  sc <- rep %% 3 != 0; pm <- rep %% 2 == 0; wt <- !pm && sv == 0 && rep %% 5 == 0
  w <- if (wt) runif(K, 0.3, 3) else rep(1, K)
  sd0 <- sample(100000, 1)
  set.seed(sd0)
  y <- factor(cls)
  m <- tryCatch(ksvm(x, y, type = if (sv == 0) "C-svc" else "nu-svc", kernel = mk(kt, sg, dg, off), C = C, nu = nu, scaled = sc, prob.model = pm, cross = 0,
                     class.weights = if (wt) setNames(w, levels(y)) else NULL), error = function(e) NULL)
  if (is.null(m)) next
  a <- c(n, p, K, kt, sv, C, nu, gm(kt, sg), if (kt %in% c(1, 7)) dg else 1, cf(kt, off), sc, pm, wt, sd0, nrow(xt), w, cls, as.vector(t(x)), as.vector(t(xt)))
  full <- unlist(lapply(seq_along(alphaindex(m)), function(q) { f <- numeric(n); f[alphaindex(m)[[q]]] <- coef(m)[[q]]; f }))
  add("coef", a, ws(full)); add("b", a, ws(b(m))); add("obj", a, ws(obj(m)))
  add("dec", a, ws(t(predict(m, xt, type = "decision"))))
  add("votes", a, ws(as.vector(t(predict(m, xt, type = "votes")))))
  add("resp", a, ws(as.integer(predict(m, xt))))
  if (pm) {
    add("ab", a, ws(unlist(lapply(prob.model(m), function(l) c(l$A, l$B)))))
    add("prob", a, ws(t(predict(m, xt, type = "probabilities"))))
    add("prob_pkpd", a, ws(t(predict(m, xt, type = "probabilities", coupler = "pkpd"))))
    add("prob_vote", a, ws(t(predict(m, xt, type = "probabilities", coupler = "vote"))))
  }
}
for (rep in 1:20) {
  kt <- kinds[(rep - 1) %% 6 + 1]; sv <- c(3, 4)[rep %% 2 + 1]
  n <- sample(25:45, 1); p <- sample(2:3, 1)
  x <- matrix(rnorm(n * p), n); xt <- matrix(rnorm(8 * p), 8); y <- 2 + 3 * sin(x[, 1]) + 0.3 * rnorm(n)
  C <- runif(1, 0.5, 8); nu <- runif(1, 0.1, 0.5); pe <- runif(1, 0.05, 0.3); sg <- runif(1, 0.1, 1.0); dg <- sample(2:3, 1); off <- runif(1, 0, 1)
  sc <- rep %% 3 != 0; pm <- rep %% 2 == 0; sd0 <- sample(100000, 1)
  set.seed(sd0)
  m <- ksvm(x, y, type = if (sv == 3) "eps-svr" else "nu-svr", kernel = mk(kt, sg, dg, off), C = C, nu = nu, epsilon = pe, scaled = sc, prob.model = pm, cross = 0)
  a <- c(n, p, kt, sv, C, nu, pe, gm(kt, sg), if (kt %in% c(1, 7)) dg else 1, cf(kt, off), sc, pm, sd0, nrow(xt), y, as.vector(t(x)), as.vector(t(xt)))
  full <- numeric(n); full[alphaindex(m)] <- coef(m)
  add("r_coef", a, ws(full)); add("r_b", a, b(m)); add("r_pred", a, ws(predict(m, xt)))
  if (pm) add("r_pm", a, prob.model(m)[[1]])
}
emit("kernlabclass", "kernlab", list(cases))
