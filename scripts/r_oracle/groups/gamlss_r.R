# gamlss.dist random numbers of every family: "gr" args (fam, seed, mu, sigma, nu, tau, bd); the want is the position-weighted checksum sum((1:5) * v) of r<FAM>(5, ...) under set.seed(seed), where an NA, NaN or Inf
# value counts as -1 (the integer families return as.integer, so a value that is Inf is NA); fam indexes the families alphabetically as in e.algo.stat.gamlssr.
suppressMessages(library(gamlss.dist))
fams <- c("BB", "BCCG", "BCCGo", "BCPE", "BCPEo", "BCT", "BCTo", "BE", "BEINF", "BEINF0", "BEINF1", "BEo", "BEOI", "BEZI", "BI", "BNB", "DBI", "DBURR12", "DEL", "DPO", "EGB2", "EXP", "GA", "GAF", "GB1", "GB2", "GEOM", "GEOMo", "GG", "GIG", "GP", "GPO", "GT", "GU", "IG", "IGAMMA", "JSU", "JSUo", "LG", "LNO", "LO", "LOGITNO", "LOGNO", "LOGNO2", "LOGSHASH", "LQNO", "MN3", "MN4", "MN5", "NBF", "NBI", "NBII", "NET", "NO", "NO2", "NOF", "PARETO", "PARETO1", "PARETO1o", "PARETO2", "PARETO2o", "PE", "PE2", "PIG", "PIG2", "PO", "RG", "RGE", "SEP", "SEP1", "SEP2", "SEP3", "SEP4", "SHASH", "SHASHo", "SHASHo2", "SI", "SICHEL", "SIMPLEX", "SN1", "SN2", "SST", "ST1", "ST2", "ST3", "ST3C", "ST4", "ST5", "TF", "TF2", "WARING", "WEI", "WEI2", "WEI3", "YULE", "ZABB", "ZABI", "ZABNB", "ZAGA", "ZAIG", "ZALG", "ZANBI", "ZAP", "ZAPIG", "ZASICHEL", "ZAZIPF", "ZIBB", "ZIBI", "ZIBNB", "ZINBF", "ZINBI", "ZIP", "ZIP2", "ZIPF", "ZIPIG", "ZISICHEL")
stopifnot(length(fams) == 116)
U <- function(a, b) runif(1, a, b)
# a parameter set per family: mu, sigma, nu, tau, bd
gen <- function(f) {
  mu <- U(0.5, 4); sg <- U(0.3, 1.5); nu <- 1; tau <- 1; bd <- sample(5:15, 1)
  z <- U(0.05, 0.5); b01 <- U(0.2, 0.8)
  switch(f,
    BB = list(mu = b01, sigma = U(0.1, 1.5), bd = bd),
    BCCG = , BCCGo = list(mu = U(1, 4), sigma = U(0.1, 0.5), nu = U(-1, 2)),
    BCPE = , BCPEo = list(mu = U(1, 4), sigma = U(0.1, 0.4), nu = U(-1, 2), tau = U(1, 3)),
    BCT = , BCTo = list(mu = U(1, 4), sigma = U(0.1, 0.4), nu = U(-1, 2), tau = U(3, 15)),
    BE = list(mu = b01, sigma = U(0.2, 0.7)),
    BEINF = list(mu = b01, sigma = U(0.2, 0.6), nu = U(0.1, 0.5), tau = U(0.1, 0.5)),
    BEINF0 = , BEINF1 = list(mu = b01, sigma = U(0.2, 0.6), nu = U(0.1, 0.5)),
    BEo = list(mu = U(0.5, 3), sigma = U(0.5, 3)),
    BEOI = , BEZI = list(mu = b01, sigma = U(0.3, 2), nu = U(0.05, 0.5)),
    BI = list(mu = b01, bd = bd),
    BNB = , DEL = list(mu = mu, sigma = U(0.2, 1.5), nu = U(0.1, 0.9)),
    DBI = list(mu = b01, sigma = U(0.5, 2), bd = bd),
    DBURR12 = list(mu = U(2, 6), sigma = U(1, 3), nu = U(0.5, 2)),
    DPO = list(mu = mu, sigma = U(0.5, 2)),
    EGB2 = list(mu = rnorm(1), sigma = U(0.5, 2), nu = U(0.5, 3), tau = U(0.5, 3)),
    EXP = , GEOM = , PARETO = , PARETO1 = , PO = , YULE = , ZIPF = list(mu = mu),
    GA = , IG = list(mu = mu, sigma = U(0.2, 1)),
    GAF = list(mu = mu, sigma = U(0.2, 1), nu = U(1, 3)),
    GB1 = list(mu = b01, sigma = U(0.2, 0.7), nu = U(0.5, 3), tau = U(0.5, 3)),
    GB2 = list(mu = mu, sigma = U(0.5, 3), nu = U(0.5, 3), tau = U(0.5, 3)),
    GEOMo = , LG = list(mu = U(0.1, 0.9)),
    GG = list(mu = mu, sigma = U(0.3, 1.5), nu = U(0.5, 2)),
    GIG = list(mu = mu, sigma = U(0.3, 1.5), nu = U(-1, 2)),
    GP = list(mu = mu, sigma = U(0.5, 3)),
    GPO = , PIG = , PIG2 = list(mu = mu, sigma = U(0.2, 1)),
    GT = list(mu = rnorm(1), sigma = U(0.5, 2), nu = U(1, 5), tau = U(1, 3)),
    GU = , LO = , LOGNO = , RG = , NO = list(mu = rnorm(1), sigma = U(0.3, 2)),
    IGAMMA = list(mu = U(1, 4), sigma = U(0.1, 0.5)),
    JSU = , JSUo = list(mu = rnorm(1), sigma = U(0.5, 2), nu = U(-1, 1), tau = U(0.5, 2)),
    LNO = list(mu = mu, sigma = U(0.1, 0.8), nu = U(-0.5, 1)),
    LOGITNO = list(mu = b01, sigma = U(0.3, 1.5)),
    LOGNO2 = , NO2 = list(mu = mu, sigma = U(0.3, 3)),
    LOGSHASH = , SHASH = list(mu = rnorm(1), sigma = U(0.5, 2), nu = U(0.3, 2), tau = U(0.3, 2)),
    LQNO = list(mu = mu, sigma = U(0.1, 1)),
    MN3 = list(mu = U(0.3, 3), sigma = U(0.3, 3)),
    MN4 = list(mu = U(0.3, 3), sigma = U(0.3, 3), nu = U(0.3, 3)),
    MN5 = list(mu = U(0.3, 3), sigma = U(0.3, 3), nu = U(0.3, 3), tau = U(0.3, 3)),
    NBF = list(mu = mu, sigma = U(0.1, 1), nu = U(1, 3)),
    NBI = , NBII = list(mu = mu, sigma = U(0.2, 1.5)),
    NET = { n1 <- U(0.5, 2); list(mu = rnorm(1), sigma = U(0.3, 2), nu = n1, tau = n1 + U(0.8, 3)) },
    NOF = list(mu = mu, sigma = U(0.3, 2), nu = U(0, 2)),
    PARETO1o = list(mu = mu, sigma = U(1, 3)),
    PARETO2 = , PARETO2o = list(mu = mu, sigma = U(0.5, 3)),
    PE = , PE2 = list(mu = rnorm(1), sigma = U(0.5, 2), nu = U(1, 3)),
    RGE = list(mu = mu, sigma = U(0.1, 0.8), nu = U(0.5, 3)),
    SEP = , SEP1 = , SEP2 = list(mu = rnorm(1), sigma = U(0.3, 2), nu = rnorm(1), tau = U(1, 3)),
    SEP3 = list(mu = rnorm(1), sigma = U(0.3, 2), nu = U(0.5, 2), tau = U(1, 3)),
    SEP4 = list(mu = rnorm(1), sigma = U(0.3, 2), nu = U(1, 3), tau = U(1, 3)),
    SHASHo = , SHASHo2 = list(mu = rnorm(1), sigma = U(0.5, 2), nu = rnorm(1), tau = U(0.5, 2)),
    SI = list(mu = U(0.5, 3), sigma = U(0.01, 0.1), nu = U(-1, -0.2)),
    SICHEL = list(mu = mu, sigma = U(0.2, 1.5), nu = U(-1, 1)),
    SIMPLEX = list(mu = b01, sigma = U(0.5, 3)),
    SN1 = list(mu = rnorm(1), sigma = U(0.3, 2), nu = rnorm(1)),
    SN2 = list(mu = rnorm(1), sigma = U(0.3, 2), nu = U(0.5, 2)),
    SST = list(mu = rnorm(1), sigma = U(0.3, 2), nu = U(0.5, 2), tau = U(3, 10)),
    ST1 = , ST2 = list(mu = rnorm(1), sigma = U(0.3, 2), nu = rnorm(1), tau = U(2, 8)),
    ST3 = , ST3C = list(mu = rnorm(1), sigma = U(0.3, 2), nu = U(0.5, 2), tau = U(3, 15)),
    ST4 = list(mu = rnorm(1), sigma = U(0.3, 2), nu = U(1, 5), tau = U(1, 5)),
    ST5 = list(mu = rnorm(1), sigma = U(0.3, 2), nu = rnorm(1), tau = U(0.5, 3)),
    TF = , TF2 = list(mu = rnorm(1), sigma = U(0.3, 2), nu = U(3, 15)),
    WARING = list(mu = U(0.5, 3), sigma = U(0.1, 0.7)),
    WEI = , WEI2 = , WEI3 = list(mu = mu, sigma = U(0.8, 3)),
    ZABB = , ZIBB = list(mu = b01, sigma = U(0.1, 1.5), nu = z, bd = bd),
    ZABI = , ZIBI = list(mu = b01, sigma = U(0.05, 0.5), bd = bd),
    ZABNB = , ZIBNB = list(mu = mu, sigma = U(0.2, 1.5), nu = U(0.1, 0.9), tau = z),
    ZAGA = , ZAIG = , ZANBI = , ZAPIG = , ZIPIG = , ZINBI = list(mu = mu, sigma = U(0.3, 1), nu = z),
    ZALG = list(mu = U(0.2, 0.8), sigma = U(0.05, 0.5)),
    ZAP = , ZIP = , ZIP2 = list(mu = mu, sigma = U(0.05, 0.5)),
    ZASICHEL = , ZISICHEL = list(mu = mu, sigma = U(0.3, 1), nu = U(-1, 1), tau = z),
    ZAZIPF = list(mu = U(0.5, 3), sigma = U(0.05, 0.5)),
    ZINBF = list(mu = mu, sigma = U(0.1, 1), nu = U(1, 3), tau = z),
    stop(paste("no generator for", f)))
}
cases <- list()
set.seed(20269202)
for (fi in seq_along(fams)) for (rep in 1:8) {
  f <- fams[fi]
  pr <- gen(f)
  sd0 <- sample(1:1000000, 1)
  fn <- get(paste0("r", f))
  fm <- names(formals(fn))
  set.seed(sd0)
  # rZIPIG fails for n > 1 (its nu is recycled to a vector and lands on a scalar test), so it is drawn one value at a time
  if (f == "ZIPIG") v <- tryCatch(suppressWarnings(sapply(1:5, function(i) do.call(fn, c(list(1), pr[names(pr) %in% fm])))), error = function(e) NULL)
  else v <- tryCatch(suppressWarnings(do.call(fn, c(list(5), pr[names(pr) %in% fm]))), error = function(e) NULL)
  if (is.null(v)) { message("SKIP ", f); next }
  v <- as.numeric(v); v[!is.finite(v)] <- -1
  all <- c(mu = 0, sigma = 0, nu = 0, tau = 0, bd = 0)
  for (nm in names(pr)) all[nm] <- pr[[nm]]
  cases[[length(cases) + 1]] <- case("gr", c(fi - 1, sd0, all["mu"], all["sigma"], all["nu"], all["tau"], all["bd"]), sum((1:5) * v), rel = 1e-8, abs = 1e-9 * max(1, abs(v)))
}
emit("gamlss_r", "gamlss.dist", list(cases))
