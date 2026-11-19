# the link functions kept in the family objects of all 116 gamlss.dist families: "fl" args (fam, parameter j of mu, sigma, nu, tau as 0 to 3, what, x) with fam the alphabetical index of e.algo.stat.gamlssr and what
# 3 the link kind of gamlsslink (0 logit, 4 identity, 5 log, 10 logshiftto2), 0 the family's <par>.linkfun at x, 1 its <par>.linkinv at x, 2 its <par>.dr (derivative of the inverse link) at x
suppressMessages(library(gamlss.dist))
f <- readLines("D:/Temp/claude/gl_fams.txt"); f <- f[nzchar(f)]
kind <- c(logit = 0, identity = 4, log = 5, logshiftto2 = 10)
cases <- list()
set.seed(20269404)
for (fi in seq_along(f)) {
  o <- get(f[fi])()
  pn <- c("mu", "sigma", "nu", "tau")[seq_len(o$nopar)]
  for (j in seq_along(pn)) {
    lk <- o[[paste0(pn[j], ".link")]]; if (is.null(lk)) next
    cases[[length(cases) + 1]] <- case("fl", c(fi - 1, j - 1, 3, 0), kind[[lk]], rel = 0, abs = 0)
    for (rep in 1:2) {
      mu <- switch(lk, logit = runif(1, 0.05, 0.95), identity = rnorm(1), log = runif(1, 0.2, 6), logshiftto2 = 2 + runif(1, 0.1, 5))
      eta <- rnorm(1, 0, 1.5)
      cases[[length(cases) + 1]] <- case("fl", c(fi - 1, j - 1, 0, mu), o[[paste0(pn[j], ".linkfun")]](mu), rel = 1e-10, abs = 1e-12)
      cases[[length(cases) + 1]] <- case("fl", c(fi - 1, j - 1, 1, eta), o[[paste0(pn[j], ".linkinv")]](eta), rel = 1e-10, abs = 1e-12)
      cases[[length(cases) + 1]] <- case("fl", c(fi - 1, j - 1, 2, eta), o[[paste0(pn[j], ".dr")]](eta), rel = 1e-10, abs = 1e-12)
    }
  }
}
emit("gamlss_famlink", "gamlss.dist", list(cases))
