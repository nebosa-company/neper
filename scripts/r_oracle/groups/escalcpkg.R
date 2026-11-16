# escalcpkg: metafor escalc for MD, SMD, ROM, RR, OR, RD, COR and ZCOR.
#   args: (measure 0 MD 1 SMD 2 ROM 3 RR 4 OR 5 RD 6 COR 7 ZCOR, part 0 yi 1 vi, the inputs: six for the first three, four for RR OR RD, two for COR ZCOR)
suppressMessages(library(metafor))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20262027)
nm <- c("MD", "SMD", "ROM", "RR", "OR", "RD", "COR", "ZCOR")
for (rep in 1:40) {
  m1 <- round(runif(1, 5, 15), 2); m2 <- round(runif(1, 5, 15), 2); s1 <- round(runif(1, 1, 4), 2); s2 <- round(runif(1, 1, 4), 2); n1 <- sample(10:80, 1); n2 <- sample(10:80, 1)
  for (m in 0:2) { e <- escalc(measure = nm[m + 1], m1i = m1, m2i = m2, sd1i = s1, sd2i = s2, n1i = n1, n2i = n2); add("es", c(m, 0, m1, m2, s1, s2, n1, n2), e$yi[1]); add("es", c(m, 1, m1, m2, s1, s2, n1, n2), e$vi[1]) }
  ai <- sample(3:40, 1); bi <- sample(3:40, 1); ci <- sample(3:40, 1); di <- sample(3:40, 1)
  for (m in 3:5) { e <- escalc(measure = nm[m + 1], ai = ai, bi = bi, ci = ci, di = di); add("es", c(m, 0, ai, bi, ci, di), e$yi[1]); add("es", c(m, 1, ai, bi, ci, di), e$vi[1]) }
  r <- round(runif(1, -0.8, 0.8), 3); n <- sample(10:100, 1)
  for (m in 6:7) { e <- escalc(measure = nm[m + 1], ri = r, ni = n); add("es", c(m, 0, r, n), e$yi[1]); add("es", c(m, 1, r, n), e$vi[1]) }
}
emit("escalcpkg", "metafor", list(cases))
