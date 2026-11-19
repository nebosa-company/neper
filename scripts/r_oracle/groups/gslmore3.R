# gsl: sn_cn_dn of a real argument, strictify, legendre_check_args and the deprecated legendre wrappers (which only return the deprecation text).
#   "w" (code, a, b, c, d): 0 sn_cn_dn(z=a, m=b) sn, 1 cn, 2 dn; 3 strictify(val = a, status = b), -999 for NaN; 4 legendre_check_args(lmax = a, norm = b, csphase = c), 1 TRUE and 0 for an error;
#   5 byte checksum (sum of position times byte) of the text of legendre_Plm_array (b = 0), legendre_Plm_deriv_array (1), legendre_sphPlm_array (2), legendre_sphPlm_deriv_array (3),
#   legendre_array_size (4) and deprecated_legendre (5); 6 its length
suppressMessages(library(gsl))
cases <- list()
add <- function(args, want, rel = 1e-11, abs = 1e-14) cases[[length(cases) + 1]] <<- case("w", args, want, rel = rel, abs = abs)
set.seed(20262957)
for (i in 1:40) {
  z <- runif(1, -4, 4); m <- runif(1, 0, 1)
  for (k in 1:3) add(c(k - 1, z, m, 0, 0), sn_cn_dn(z, m, c("sn", "cn", "dn")[k]), rel = 1e-10, abs = 1e-12)
}
add(c(0, 0.5, 1, 0, 0), sn_cn_dn(0.5, 1, "sn"), rel = 1e-10); add(c(1, 0.5, 1, 0, 0), sn_cn_dn(0.5, 1, "cn"), rel = 1e-10); add(c(2, 0.5, 0, 0, 0), sn_cn_dn(0.5, 0, "dn"))
for (v in c(1.5, -2, 0)) for (s in c(0, 1, 3)) { r <- strictify(v, s); add(c(3, v, s, 0, 0), if (is.nan(r)) -999 else r) }
for (a in c(0, 3, 10)) for (n in 1:4) for (cs in c(-1, 1)) add(c(4, a, n, cs, 0), as.numeric(legendre_check_args(0.3, a, n, cs)), abs = 0)
for (bad in list(c(-1, 1, 1), c(3, 5, 1), c(3, 0, 1), c(3, 2, 0), c(3, 2, 2))) {
  r <- tryCatch(as.numeric(legendre_check_args(0.3, bad[1], bad[2], bad[3])), error = function(e) 0)
  add(c(4, bad[1], bad[2], bad[3], 0), r, abs = 0)
}
cs <- function(s) sum(seq_along(utf8ToInt(s)) * utf8ToInt(s))
texts <- suppressWarnings(list(legendre_Plm_array(4, 1, 0.3), legendre_Plm_deriv_array(4, 1, 0.3), legendre_sphPlm_array(4, 1, 0.3), legendre_sphPlm_deriv_array(4, 1, 0.3), legendre_array_size(5, 2), deprecated_legendre()))
for (k in 1:6) { add(c(5, k - 1, 0, 0, 0), cs(texts[[k]]), rel = 0, abs = 0); add(c(6, k - 1, 0, 0, 0), nchar(texts[[k]]), rel = 0, abs = 0) }
emit("gslmore3", "gsl", list(cases))
