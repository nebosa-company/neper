# scales label formatters: number (every option, scale cuts), comma, percent, dollar, bytes,
# ordinal, scientific, and label_date/label_time in UTC. A case holds the options as numbers
# (args) and strings (in) and the values; the answer is the strings joined by U+0001.
#   number:     args (accuracy, scale, positive, negative, cut, n, x...), in (prefix, suffix, big, dec, unit)
#   comma:      args (accuracy, n, x...)           percent: args (accuracy, n, x...)
#   dollar:     args (accuracy, largest, n, x...)  bytes:   args (accuracy, scale, n, x...), in (units)
#   ordinal:    args (n, x...), in (prefix, suffix, big)
#   scientific: args (digits, scale, n, x...), in (prefix, suffix, dec)
#   date:       args (n, seconds...), in (format): label_time of a POSIXct; day: label_date of its Date
library(scales)
set.seed(20261115)

joined <- function(x) paste(as.character(x), collapse = "\001")
na0 <- function(v) if (is.na(v)) NULL else v
cases <- list()
add <- function(fn, args, input, want) cases[[length(cases) + 1]] <<- case(fn, args, want, input = input)

pool <- c(1234.5678, 0.5, -3.25, 1e6, 123456789, 0.000123, 42, 1e-5, 999, 1000, 1500, 15.2, 0, -1, -1500.5,
          2.5, 99.995, 0.1, 0.25, 1e9, 3.2e10, 7e12, 123456.789, 50, 12, 0.07, 1e15, 4.5e-7)
vecs <- c(lapply(pool, function(v) v),
          lapply(1:120, function(i) sample(pool, sample(2:6, 1))),
          list(c(0.1, 0.25, 0.5), c(1, 2, 3), c(10, 20, 30), c(1000, 2000, 3500), c(0.001, 0.002), c(5, 15, 25),
               c(1e3, 1e6, 1e9), c(-1, 1), c(-5.5, 5.5, 0), c(Inf, 1, -Inf), c(100, 200, 350.5)))

cuts <- list(NULL, cut_short_scale(), cut_long_scale(), cut_time_scale(), cut_si("g"))
accs <- c(NA, 1, 0.01, 0.1, 5, 1000, 0.001)
scales_ <- c(1, 100, 0.001, 1e-6, 2.5)
strs <- list(c("", "", " ", "."), c("$", "", ",", "."), c("", " units", ".", ","), c("<", ">", "'", ","),
             c("", "%", "", "."), c("a", "b", "xx", "::"))
for (k in seq_len(900)) {
  v <- vecs[[sample(length(vecs), 1)]]
  acc <- sample(accs, 1); sc <- sample(scales_, 1); pos <- sample(0:2, 1); neg <- sample(0:2, 1)
  cu <- sample(5, 1); st <- strs[[sample(length(strs), 1)]]
  want <- tryCatch(number(v, accuracy = na0(acc), scale = sc, prefix = st[1], suffix = st[2], big.mark = st[3],
                          decimal.mark = st[4], style_positive = c("none", "plus", "space")[pos + 1],
                          style_negative = c("hyphen", "minus", "parens")[neg + 1], scale_cut = cuts[[cu]]),
                   error = function(e) NULL)
  if (is.null(want)) next
  add("number", c(acc, sc, pos, neg, cu - 1, length(v), v), c(st, "g"), joined(want))
}
for (v in vecs) {
  for (acc in c(NA, 1, 0.01, 0.5)) {
    add("comma", c(acc, length(v), v), character(), joined(comma(v, accuracy = na0(acc))))
    add("percent", c(acc, length(v), v), character(), joined(percent(v, accuracy = na0(acc))))
    add("dollar", c(acc, 1e5, length(v), v), character(), joined(dollar(v, accuracy = na0(acc))))
  }
  add("dollar", c(NA, 100, length(v), v), character(), joined(dollar(v, largest_with_cents = 100)))
  for (u in c("auto_si", "auto_binary", "kB", "MB", "GiB", "TB"))
    add("bytes", c(1, 1, length(v), v), u, joined(label_bytes(units = u)(v)))
  add("bytes", c(0.1, 1, length(v), v), "auto_si", joined(label_bytes(accuracy = 0.1)(v)))
  vi <- round(v)
  add("ordinal", c(length(vi), vi), c("", "", " "), joined(ordinal(vi)))
  add("ordinal", c(length(vi), vi), c("#", "!", ","), joined(ordinal(vi, prefix = "#", suffix = "!", big.mark = ",")))
  for (d in c(3, 1, 5)) {
    add("scientific", c(d, 1, length(v), v), c("", "", "."), joined(scientific(v, digits = d)))
    add("scientific", c(d, 1000, length(v), v), c("<", ">", ","), joined(scientific(v, digits = d, scale = 1000, prefix = "<", suffix = ">", decimal.mark = ",")))
  }
}
secs <- c(0, 86400 * 365, 1700000000, 1234567890, 951782400, 86399, -86400, 1e9 + 0.5, 4102444800, 1582934400)
fmts <- c("%Y-%m-%d", "%H:%M:%S", "%d %b %Y", "%A %B %e", "%j %U %W %u %w", "%y/%m/%d %I:%M %p", "%F %T %Z %z", "%D %R", "%a, %d %h", "%% %Y")
for (f in fmts) for (s in secs) {
  add("day", c(1, s), f, joined(label_date(format = f)(as.Date(as.POSIXct(s, origin = "1970-01-01", tz = "UTC")))))
  add("date", c(1, s), f, joined(label_time(format = f)(as.POSIXct(s, origin = "1970-01-01", tz = "UTC"))))
}
emit("labels", "scales", list(cases))
