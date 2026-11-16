# gsDesign: alpha spending functions.
#   args: (kind, alpha, t, p1, p2)   fn "spend"
#   kind 0 sfHSD 1 sfPower 2 sfExponential 3 sfLogistic 4 sfNormal 5 sfCauchy 6 sfExtremeValue 7 sfBetaDist 8 sfLDOF 9 sfLDPocock
suppressMessages(library(gsDesign))
cases <- list()
add <- function(args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("spend", args, want, rel = 1e-9, abs = 1e-14)
set.seed(20261224)
for (rep in 1:12) {
  alpha <- c(0.025, 0.05, 0.0125, 0.1)[rep %% 4 + 1]
  for (t in c(0.05, 0.2, 0.5, 0.75, 0.99, 1)) {
    g <- c(-4, -2, 1, 3, 5)[rep %% 5 + 1]; rho <- c(0.5, 1, 2, 3)[rep %% 4 + 1]; nu <- c(0.2, 0.5, 1)[rep %% 3 + 1]
    a <- runif(1, -1, 1); b <- runif(1, 0.4, 2.5)
    add(c(0, alpha, t, g, 0), sfHSD(alpha, t, g)$spend)
    add(c(1, alpha, t, rho, 0), sfPower(alpha, t, rho)$spend)
    add(c(2, alpha, t, nu, 0), sfExponential(alpha, t, nu)$spend)
    add(c(3, alpha, t, a, b), sfLogistic(alpha, t, c(a, b))$spend)
    add(c(4, alpha, t, a, b), sfNormal(alpha, t, c(a, b))$spend)
    add(c(5, alpha, t, a, b), sfCauchy(alpha, t, c(a, b))$spend)
    add(c(6, alpha, t, a, b), sfExtremeValue(alpha, t, c(a, b))$spend)
    add(c(7, alpha, t, abs(a) + 0.3, b), sfBetaDist(alpha, t, c(abs(a) + 0.3, b))$spend)
    add(c(8, alpha, t, rho, 0), sfLDOF(alpha, t, rho)$spend)
    add(c(9, alpha, t, 0, 0), sfLDPocock(alpha, t)$spend)
  }
}
emit("gsdesign", "gsDesign", list(cases))
