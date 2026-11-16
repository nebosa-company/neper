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
emit("pwr", "pwr", list(cases))
