# pwr: the normal-based power calculations.
#   args: (kind 0 pwr.p.test/pwr.norm.test 1 pwr.2p.test 2 pwr.2p2n.test, side 1 less 2 two.sided 3 greater, unknown 0 h 1 n 2 sig 3 n2 (-1 none: power), h, n, n2, sig, power)
#   fn "val": the value of the unknown (or the power)    "rpow": (n, r, sig, side) pwr.r.test power      "esh": (p1, p2)
library(pwr)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
alts <- c("less", "two.sided", "greater")
run <- function(kind, side, unknown, h, n, n2, sig, power) {
  al <- alts[side]
  f <- switch(kind + 1, function(...) pwr.p.test(..., alternative = al), function(...) pwr.2p.test(..., alternative = al), function(...) pwr.2p2n.test(..., alternative = al))
  args <- list(h = h, n = n, sig.level = sig, power = power)
  if (kind == 2) { args$n1 <- n; args$n2 <- n2; args$n <- NULL }
  if (unknown == 0) args$h <- NULL; if (unknown == 1) args[[if (kind == 2) "n1" else "n"]] <- NULL
  if (unknown == 2) args["sig.level"] <- list(NULL); if (unknown == 3) args["n2"] <- list(NULL)
  if (unknown == -1) args["power"] <- list(NULL)
  r <- tryCatch(do.call(f, args), error = function(e) NULL)
  if (is.null(r)) return(NA)
  switch(as.character(unknown), "0" = r$h, "1" = if (kind == 2) r$n1 else r$n, "2" = r$sig.level, "3" = r$n2, "-1" = r$power)
}
for (kind in 0:2) for (side in 1:3) {
  for (h in c(0.2, 0.5, -0.4, 0.8)) {
    if (side == 1 && h > 0) hh <- -h else if (side == 3 && h < 0) hh <- -h else hh <- h
    for (n in c(20, 50, 120)) for (sig in c(0.01, 0.05, 0.1)) {
      n2 <- n + 15
      pw <- run(kind, side, -1, hh, n, n2, sig, NULL)
      if (is.na(pw)) next
      add("val", c(kind, side, -1, hh, n, n2, sig, 0), pw)
      if (pw > 0.2 && pw < 0.99) {
        for (u in c(0, 1, 2, if (kind == 2) 3)) {
          v <- run(kind, side, u, hh, n, n2, sig, pw)
          if (!is.na(v)) add("val", c(kind, side, u, hh, n, n2, sig, pw), v)
        }
      }
    }
  }
}
for (n in c(10, 25, 60, 200)) for (r in c(0.1, 0.3, -0.5)) for (sig in c(0.05, 0.01)) for (side in 1:3) {
  rr <- if (side == 1 && r > 0) -r else r
  add("rpow", c(n, rr, sig, side), pwr.r.test(n = n, r = rr, sig.level = sig, alternative = alts[side])$power)
}
for (p in list(c(0.5, 0.3), c(0.9, 0.1), c(0.25, 0.25))) add("esh", p, ES.h(p[1], p[2]))
#   non-central designs: fn "nc" args (kind 0 pwr.t.test one-sample 1 two-sample 2 pwr.t2n.test 3 pwr.chisq.test 4 pwr.anova.test 5 pwr.f2.test, side, unknown -1 power 0 es
#   1 n 2 sig 3 n2 4 k, es, n, n2, k, sig, power); pwr.chisq.test df is n2, pwr.f2.test u is k and v is n
runnc <- function(kind, side, unknown, es, n, n2, k, sig, power) {
  al <- alts[side]
  nul <- function(l, nm) { l[nm] <- list(NULL); l }
  r <- tryCatch({
    if (kind <= 1) {
      args <- list(n = n, d = es, sig.level = sig, power = power, type = if (kind == 0) "one.sample" else "two.sample", alternative = al)
      args <- switch(as.character(unknown), "0" = nul(args, "d"), "1" = nul(args, "n"), "2" = nul(args, "sig.level"), "-1" = nul(args, "power"))
      do.call(pwr.t.test, args)
    } else if (kind == 2) {
      args <- list(n1 = n, n2 = n2, d = es, sig.level = sig, power = power, alternative = al)
      args <- switch(as.character(unknown), "0" = nul(args, "d"), "1" = nul(args, "n1"), "2" = nul(args, "sig.level"), "3" = nul(args, "n2"), "-1" = nul(args, "power"))
      do.call(pwr.t2n.test, args)
    } else if (kind == 3) {
      args <- list(w = es, N = n, df = n2, sig.level = sig, power = power)
      args <- switch(as.character(unknown), "0" = nul(args, "w"), "1" = nul(args, "N"), "2" = nul(args, "sig.level"), "-1" = nul(args, "power"))
      do.call(pwr.chisq.test, args)
    } else if (kind == 4) {
      args <- list(k = k, n = n, f = es, sig.level = sig, power = power)
      args <- switch(as.character(unknown), "0" = nul(args, "f"), "1" = nul(args, "n"), "2" = nul(args, "sig.level"), "4" = nul(args, "k"), "-1" = nul(args, "power"))
      do.call(pwr.anova.test, args)
    } else {
      args <- list(u = k, v = n, f2 = es, sig.level = sig, power = power)
      args <- switch(as.character(unknown), "0" = nul(args, "f2"), "1" = nul(args, "v"), "2" = nul(args, "sig.level"), "4" = nul(args, "u"), "-1" = nul(args, "power"))
      do.call(pwr.f2.test, args)
    }
  }, error = function(e) NULL)
  if (is.null(r)) return(NA)
  switch(as.character(unknown), "0" = (if (kind <= 2) r$d else if (kind == 3) r$w else if (kind == 4) r$f else r$f2),
         "1" = (if (kind == 2) r$n1 else if (kind == 3) r$N else if (kind == 5) r$v else r$n),
         "2" = r$sig.level, "3" = r$n2, "4" = (if (kind == 4) r$k else r$u), "-1" = r$power)
}
grid <- function(kind) switch(kind + 1,
  list(es = c(0.3, 0.6, -0.4), n = c(15, 40, 100), n2 = 0, k = 0), list(es = c(0.3, 0.6, -0.4), n = c(15, 40, 100), n2 = 0, k = 0),
  list(es = c(0.4, 0.7, -0.5), n = c(15, 40), n2 = c(20, 60), k = 0), list(es = c(0.1, 0.3, 0.5), n = c(50, 200), n2 = c(1, 3, 6), k = 0),
  list(es = c(0.1, 0.25, 0.4), n = c(10, 30), n2 = 0, k = c(3, 5)), list(es = c(0.02, 0.15, 0.35), n = c(40, 120), n2 = 0, k = c(2, 5)))
for (kind in 0:5) for (side in (if (kind <= 2) 1:3 else 2)) {
  g <- grid(kind)
  for (es in g$es) for (n in g$n) for (n2 in g$n2) for (k in g$k) for (sig in c(0.01, 0.05)) {
    if (kind <= 2) { if (side == 1 && es > 0) es <- -es else if (side == 3 && es < 0) es <- -es }
    pw <- runnc(kind, side, -1, es, n, n2, k, sig, NULL)
    if (is.na(pw)) next
    add("nc", c(kind, side, -1, es, n, n2, k, sig, 0), pw)
    if (pw > 0.2 && pw < 0.99) for (u in c(0, 1, 2, if (kind == 2) 3, if (kind >= 4) 4)) {
      v <- runnc(kind, side, u, es, n, n2, k, sig, pw)
      if (!is.na(v)) add("nc", c(kind, side, u, es, n, n2, k, sig, pw), v)
    }
  }
}
#   pwr.r.test solved: fn "rsolve" (side, unknown 0 r 1 n 2 sig, r, n, sig, power); cohen.ES: fn "cohen" (test 0..5, size 0..2); ES.w1 (n, P0, P1); ES.w2 (nr, nc, P row-major)
for (side in 1:3) for (r in c(0.2, 0.4, -0.3)) for (n in c(20, 60, 150)) for (sig in c(0.01, 0.05)) {
  rr <- if (side == 1 && r > 0) -r else if (side == 3 && r < 0) -r else r
  pw <- pwr.r.test(n = n, r = rr, sig.level = sig, alternative = alts[side])$power
  if (pw > 0.2 && pw < 0.99) for (u in 0:2) {
    s <- tryCatch(switch(u + 1, pwr.r.test(n = n, sig.level = sig, power = pw, alternative = alts[side])$r, pwr.r.test(r = rr, sig.level = sig, power = pw, alternative = alts[side])$n,
                         pwr.r.test(n = n, r = rr, power = pw, alternative = alts[side])$sig.level), error = function(e) NA)
    if (!is.na(s)) add("rsolve", c(side, u, rr, n, sig, pw), s)
  }
}
tests <- c("p", "t", "r", "anov", "chisq", "f2"); sizes <- c("small", "medium", "large")
for (t in 0:5) for (s in 0:2) add("cohen", c(t, s), cohen.ES(test = tests[t + 1], size = sizes[s + 1])$effect.size)
for (rep in 1:8) {
  k <- sample(3:6, 1); P0 <- runif(k); P0 <- P0 / sum(P0); P1 <- runif(k); P1 <- P1 / sum(P1)
  add("w1", c(k, P0, P1), ES.w1(P0, P1))
  nr <- sample(2:4, 1); nc <- sample(2:4, 1); P <- matrix(runif(nr * nc), nr, nc); P <- P / sum(P)
  add("w2", c(nr, nc, as.numeric(t(P))), ES.w2(P))
}
emit("pwr", "pwr", list(cases))
