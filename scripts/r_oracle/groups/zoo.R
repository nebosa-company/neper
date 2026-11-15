# zoo: rollapply (fixed, by, align, partial, fill), na.locf, na.approx, na.spline, na.fill, yearmon and
# yearqtr, merge by index. A vector answer is one case per element (fn "v:<name>") plus a length
# case (fn "len:<name>"); the last argument of an element case is its position.
#   rollapply: (kind 0 mean 1 sum 2 median 3 max 4 min, width, by, align 0 center 1 left 2 right, partial (-1 FALSE),
#               fillmode 0 none 1 fill, code1, val1, code2, val2, code3, val3 (code 0 value 1 extend), len, x...)
#   locf:      (from_last, maxgap (-1 Inf), na_rm, len, x...)
#   approx:    (rule, maxgap, na_rm, len, idx..., x...)      spline: (method 0 fmm 1 natural, maxgap, na_rm, len, idx..., x...)
#   fill:      (code1, val1, code2, val2, code3, val3, len, x...)
#   ym_parts:  (kind 0 yearmon 1 yearqtr, value)  ->  year, month or quarter         ym_add: (kind, value, delta) -> value
#   ym_format: "text" case, args (kind, value), in [format]
#   merge:     (all, n1, idx1..., x1..., n2, idx2..., x2..., fillvalue)  -> columns; "idx" "a" "b"
library(zoo)
set.seed(20261115)
cases <- list()
add <- function(fn, args, want, text = FALSE) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-11, abs = 1e-12)
addt <- function(fn, args, input, want) cases[[length(cases) + 1]] <<- case(fn, args, want, input = input)
vec <- function(name, args, v) {
  add(paste0("len:", name), args, length(v))
  for (i in seq_along(v)) add(paste0("v:", name), c(args, i - 1), v[i])
}
quiet <- function(f) tryCatch(suppressWarnings(suppressMessages(f)), error = function(e) NULL)

xs <- list(c(1, 2, 3, 4, 5, 6, 7), c(1, 2, NA, 4, 5, 6, 7), c(5, 3, 8, 1, 9, 2), c(NA, NA, 3, 4, NA), c(2, 2, 2, 2),
           c(7), c(-1.5, 0.25, 8, NA, NA, 4.5, 0, NA), c(NA, 5, NA, NA, NA, 9, NA, 1, NA), c(4, 9, 1, 7, 3, 8, 2, 6, 5, 0))
fills <- list(NULL, NA, 0, c("extend", NA, "extend"), c(NA, "extend", NA), c(-1, 99, -2))
fcode <- function(f) if (is.null(f)) c(0, 0, 0, 0, 0, 0, 0) else {
  f <- rep(as.list(f), length.out = 3)
  c(1, unlist(lapply(f, function(v) if (identical(v, "extend")) c(1, 0) else c(0, as.numeric(v)))))
}
funs <- list(mean, sum, median, max, min)
anon <- list(function(v) mean(v), function(v) sum(v), function(v) median(v), function(v) max(v), function(v) min(v))
aligns <- c("center", "left", "right")
combos <- expand.grid(xi = seq_along(xs), width = 1:6, by = 1:3, align = 1:3, partial = c(-1, 1, 2), fill = seq_along(fills), kind = 1:5)
for (r in sample(nrow(combos), 2600)) {
  g <- combos[r, ]
  x <- xs[[g$xi]]
  p <- if (g$partial < 0) FALSE else if (g$partial == 1) TRUE else 2
  fl <- fills[[g$fill]]
  args <- c(g$kind - 1, g$width, g$by, g$align - 1, g$partial, fcode(fl), length(x), x)
  f <- if (runif(1) < 0.15) funs[[g$kind]] else anon[[g$kind]]
  res <- quiet(if (is.null(fl)) rollapply(zoo(x), g$width, f, by = g$by, align = aligns[g$align], partial = p)
               else rollapply(zoo(x), g$width, f, by = g$by, align = aligns[g$align], partial = p, fill = fl))
  if (!is.null(res)) vec("rollapply", args, as.numeric(coredata(res)))
}

for (x in xs) for (fl in c(FALSE, TRUE)) for (mg in c(-1, 0, 1, 2, 3)) for (nr in c(FALSE, TRUE)) {
  res <- quiet(na.locf(zoo(x), na.rm = nr, fromLast = fl, maxgap = if (mg < 0) Inf else mg))
  if (!is.null(res)) vec("locf", c(fl, mg, nr, length(x), x), as.numeric(coredata(res)))
}

idxs <- function(n) list(seq_len(n), cumsum(sample(1:4, n, replace = TRUE)), sort(round(runif(n, 0, 20), 2)) + seq_len(n) * 0.001)
for (x in xs) for (ix in idxs(length(x))) for (rule in 1:2) for (mg in c(-1, 1, 2)) for (nr in c(FALSE, TRUE)) {
  res <- quiet(na.approx(zoo(x, ix), rule = rule, maxgap = if (mg < 0) Inf else mg, na.rm = nr))
  if (!is.null(res)) vec("approx", c(rule, mg, nr, length(x), ix, x), as.numeric(coredata(res)))
}
for (x in xs) for (ix in idxs(length(x))) for (m in 0:1) for (mg in c(-1, 1, 2)) for (nr in c(FALSE, TRUE)) {
  res <- quiet(na.spline(zoo(x, ix), method = c("fmm", "natural")[m + 1], maxgap = if (mg < 0) Inf else mg, na.rm = nr))
  if (!is.null(res)) vec("spline", c(m, mg, nr, length(x), ix, x), as.numeric(coredata(res)))
}

for (x in xs) for (fl in fills[-1]) {
  res <- quiet(na.fill(zoo(x), fl))
  if (!is.null(res)) vec("fill", c(fcode(fl)[-1], length(x), x), as.numeric(coredata(res)))
}

vals <- c(2024, 2024.25, 2024.5, 2023.9166666666667, 1999.75, 2000, 1969.1666666666667, 2100.5, 1900, 2024.0833333333333)
for (v in vals) {
  ym <- as.yearmon(v); yq <- as.yearqtr(v)
  add("ym_parts", c(0, v, 0), as.numeric(format(ym, "%Y"))); add("ym_parts", c(0, v, 1), as.numeric(format(ym, "%m")))
  add("ym_parts", c(1, v, 0), as.numeric(format(yq, "%Y"))); add("ym_parts", c(1, v, 1), as.numeric(format(yq, "%q")))
  for (d in c(0, 1/12, -1/12, 5/12, 1, -2.5, 0.25, -0.25, 11/12)) {
    add("ym_add", c(0, v, d), as.numeric(ym + d)); add("ym_add", c(1, v, d), as.numeric(yq + d))
  }
  for (f in c("%b %Y", "%B %Y", "%Y-%m", "%m/%y", "%Y", "%y %b", "%B", "%b-%Y-%m", "%%Y", "x%Yy")) addt("ym_format", c(0, v), f, format(ym, f))
  for (f in c("%Y Q%q", "%Y-Q%q", "%q", "%Y", "%y Q%q", "%C", "%%Y", "x%qy", "%q%q")) addt("ym_format", c(1, v), f, format(yq, f))
}
addt("ym_format", c(0, 2024.5), "%b %Y", "Jul 2024")

for (all in c(FALSE, TRUE)) for (k in 1:60) {
  n1 <- sample(1:6, 1); n2 <- sample(1:6, 1)
  i1 <- sample(1:12, n1); i2 <- sample(1:12, n2)
  x1 <- round(runif(n1, -5, 5), 3); x2 <- round(runif(n2, -5, 5), 3)
  if (k %% 5 == 0) { x1[1] <- NA; x2[n2] <- NA }
  fillv <- if (k %% 3 == 0) 0 else NA
  res <- quiet(merge(zoo(x1, i1), zoo(x2, i2), all = all, fill = fillv))
  if (is.null(res) || length(dim(coredata(res))) != 2 || nrow(res) == 0) next
  a <- c(all, n1, i1, x1, n2, i2, x2, if (is.na(fillv)) NaN else fillv)
  vec("merge_idx", a, as.numeric(index(res)))
  vec("merge_a", a, as.numeric(coredata(res)[, 1]))
  vec("merge_b", a, as.numeric(coredata(res)[, 2]))
}
emit("zoo", "zoo", list(cases))
