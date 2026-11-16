# colorspace's HCL palettes, contrast ratio and colour-vision-deficiency simulation. A palette case answers its
# colours as text, "#RRGGBB" joined by commas, NA as "NA".
#   hcl_seq / hcl_div / hcl_qual: args (n, h1, h2, c1, c2, l1, l2, p1, p2, cmax, fixup)
#   hcl_divx: args (n, fixup, h1, h2, h3, c1, c2, c3, l1, l2, l3, p1, p2, p3, p4, cmax1, cmax2)
#   hcl_named: args (n), in [palette name]
#   contrast_wcag / contrast_apca_n / contrast_apca_r: in [col, col2], a number
#   cvd: args (kind 0 deutan 1 protan 2 tritan, severity, linear), in [col], text
library(colorspace)
set.seed(20261116)
cases <- list()
txt <- function(x) paste(ifelse(is.na(x), "NA", x), collapse = ",")
addt <- function(fn, args, want, input = NULL) cases[[length(cases) + 1]] <<- case(fn, args, want, input = input)
addn <- function(fn, input, want) cases[[length(cases) + 1]] <<- case(fn, numeric(0), want, rel = 1e-12, abs = 1e-13, input = input)

pal <- as.data.frame(hcl_palettes())
ns <- c(1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 16, 25)
for (i in seq_len(nrow(pal))) {
  type <- as.character(pal$type[i]); name <- rownames(pal)[i]
  for (n in ns) {
    v <- if (grepl("^Qual", type)) qualitative_hcl(n, palette = name) else if (grepl("^Div", type)) diverging_hcl(n, palette = name) else sequential_hcl(n, palette = name)
    addt("hcl_named", n, txt(v), input = name)
  }
}
dx <- as.data.frame(divergingx_palettes())
dnames <- if (!is.null(dx$palette)) as.character(dx$palette) else rownames(dx)
for (name in dnames) for (n in ns) for (fx in c(TRUE, FALSE)) addt("hcl_divx_named", c(n, fx), txt(divergingx_hcl(n, palette = name, fixup = fx)), input = name)
# divergingx from its coordinates: the 15 numbers of each palette
dcols <- c("h1", "h2", "h3", "c1", "c2", "c3", "l1", "l2", "l3", "p1", "p2", "p3", "p4", "cmax1", "cmax2")
for (k in seq_len(nrow(dx))) for (n in c(2, 5, 8)) for (fx in c(TRUE, FALSE)) {
  v <- as.numeric(unlist(dx[k, dcols]))
  addt("hcl_divx", c(n, fx, v), txt(divergingx_hcl(n, palette = dnames[k], fixup = fx)))
}

rnd <- function(lo, hi) round(runif(1, lo, hi), 1)
maybe <- function(x, p = 0.3) if (runif(1) < p) NA else x
for (k in 1:900) {
  n <- sample(c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 20, 31), 1)
  h1 <- rnd(-40, 400); h2 <- maybe(rnd(-40, 400)); c1 <- rnd(0, 140); c2 <- maybe(rnd(0, 140)); l1 <- rnd(5, 95); l2 <- rnd(5, 99)
  p1 <- rnd(0.1, 3); p2 <- maybe(rnd(0.1, 3)); cmax <- maybe(rnd(0, 200)); fx <- runif(1) < 0.8
  a <- c(n, h1, h2, c1, c2, l1, l2, p1, p2, cmax, fx)
  addt("hcl_seq", a, txt(sequential_hcl(n, h1 = h1, h2 = h2, c1 = c1, c2 = c2, l1 = l1, l2 = l2, p1 = p1, p2 = p2, cmax = cmax, fixup = fx)))
  a2 <- c(n, h1, if (is.na(h2)) rnd(0, 360) else h2, c1, NA, l1, l2, p1, p2, cmax, fx)
  addt("hcl_div", a2, txt(diverging_hcl(n, h1 = a2[2], h2 = a2[3], c1 = c1, l1 = l1, l2 = l2, p1 = p1, p2 = p2, cmax = cmax, fixup = fx)))
  h2q <- h2
  a3 <- c(n, h1, h2q, c1, NA, l1, NA, NA, NA, NA, fx)
  addt("hcl_qual", a3, txt(qualitative_hcl(n, h1 = h1, h2 = h2q, c1 = c1, l1 = l1, fixup = fx)))
}
# the named wrappers
for (n in ns) {
  addt("hcl_seq", c(n, 0, 90, 100, 30, 50, 90, 1/5, 1, NA, 1), txt(heat_hcl(n)))
  addt("hcl_seq", c(n, 130, 0, 80, 0, 60, 95, 1/10, 1, NA, 1), txt(terrain_hcl(n)))
  addt("hcl_qual", c(n, 0, 360 * (n - 1) / n, 50, NA, 70, NA, NA, NA, NA, 1), txt(rainbow_hcl(n)))
  addt("hcl_qual", c(n, 0, NA, 80, NA, 60, NA, NA, NA, NA, 1), txt(qualitative_hcl(n)))
  addt("hcl_seq", c(n, 260, NA, 80, 0, 30, 90, 1.5, NA, NA, 1), txt(sequential_hcl(n)))
  addt("hcl_div", c(n, 260, 0, 80, NA, 30, 90, 1.5, NA, NA, 1), txt(diverging_hcl(n)))
}

randhex <- function(k) sprintf("#%02X%02X%02X", sample(0:255, k, TRUE), sample(0:255, k, TRUE), sample(0:255, k, TRUE))
fixedhex <- c("#000000", "#FFFFFF", "#FF0000", "#00FF00", "#0000FF", "#808080", "#FFFF00", "#00FFFF", "#FF00FF", "#0A0A0A", "#F5F5F5", "#123456", "#FEDCBA", "#7F7F7F", "#010101", "#FDFDFD")
cols <- c(fixedhex, randhex(184))
for (i in seq_along(cols)) {
  other <- if (i <= 16) fixedhex[(i * 7) %% 16 + 1] else cols[(i * 13) %% length(cols) + 1]
  addn("contrast_wcag", c(cols[i], other), as.numeric(contrast_ratio(cols[i], other)))
  r <- contrast_ratio(cols[i], other, algorithm = "APCA")
  addn("contrast_apca_n", c(cols[i], other), as.numeric(r[, 1]))
  addn("contrast_apca_r", c(cols[i], other), as.numeric(r[, 2]))
}
for (cc in cols) for (sv in c(0, 0.1, 0.25, 0.5, 0.73, 1)) for (lin in c(TRUE, FALSE)) {
  addt("cvd", c(0, sv, lin), deutan(cc, sv, linear = lin), input = cc)
  addt("cvd", c(1, sv, lin), protan(cc, sv, linear = lin), input = cc)
  addt("cvd", c(2, sv, lin), tritan(cc, sv, linear = lin), input = cc)
}
emit("colorspace", "colorspace", list(cases))
