# readr's parsers and read_delim field splitting. A scalar parser case holds the string (and the
# format) in "in" and answers a number (NA when it fails): parse_number, parse_double,
# parse_integer, parse_logical, parse_date (days), parse_time (seconds) and parse_datetime
# (seconds since the epoch, UTC). A "delim" case holds the text and answers the fields, rows
# joined by U+0001 and fields by U+0002; args are (delimiter, quote, comment, backslash escape,
# doubled-quote escape, trim_ws) with 0 for none.
library(readr)
set.seed(20261115)

quiet <- function(x) suppressWarnings(suppressMessages(x))
na0 <- function(x) if (length(x) == 0 || is.na(x)) NA_real_ else as.numeric(x)
cases <- list()
add <- function(fn, args, input, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, input = input)

# parse_number: args are (decimal, grouping) as byte codes.
num_pool <- c("1", "-1", "12.5", "1,234.5", "$1,234.56", "abc12def", "12abc", "-.5", ".5", "5.", "1e3", "1E-3",
              "1.5e+2", "1,2,3", "1,,2", "  42  ", "(7)", "--3", "-", "", "a", "1e", "e5", "3.14.15", "1 000",
              "0.000123", "-0.5e1x", "100%", "1,000,000", "12,34,56.78", "x-5", "5-", "1.2.3", "1e+", "1e-x",
              "9999999999999999", "0.1", "007", "-007.50", "1,5", "1.234,56")
for (d in list(c(46, 44), c(44, 46))) for (s in num_pool) {
  loc <- locale(decimal_mark = intToUtf8(d[1]), grouping_mark = intToUtf8(d[2]))
  add("number", d, s, na0(quiet(parse_number(s, locale = loc))))
}

dbl_pool <- c("1", "-1", "+1", "1.5", ".5", "5.", "-.5", "1e3", "1E3", "1e-3", "1e+3", "1.5e2", "1d3", "1D3", "1s2", "1f2",
              "1l2", "1L2", " 12 ", "\t3.5", "", "-", "+", ".", "e5", "1e", "1e+", "1.2.3", "1,5", "abc", "12abc", "0x10",
              "1e400", "1e-400", "123456789012345678", "0.1", "0.30000000000000004", "4.9e-324", "1.7976931348623157e308",
              "--1", "+-1", "1 2", "007", "00.5", "1e03", "1e0003")
for (dm in c(".", ",")) for (s in dbl_pool) {
  loc <- locale(decimal_mark = dm, grouping_mark = if (dm == ".") "," else ".")
  add("double", c(utf8ToInt(dm)), s, na0(quiet(parse_double(s, locale = loc))))
}

int_pool <- c("0", "1", "-1", "+1", "12345", "2147483647", "2147483648", "-2147483647", "-2147483648", "99999999999", "",
              "-", "+", "1.5", "1e3", "abc", "12a", " 7 ", "007", "--1", "1 2", "0x10", "1,000")
for (s in int_pool) add("integer", 0, s, na0(quiet(parse_integer(s))))

lgl_pool <- c("TRUE", "FALSE", "T", "F", "true", "false", "True", "False", "1", "0", "t", "f", "TRUE ", " false", "yes", "no",
              "", "2", "tRUE", "TRUEE", "Y", "N")
for (s in lgl_pool) add("logical", 0, s, na0(quiet(as.numeric(parse_logical(s)))))

date_fmts <- c("%AD", "%Y-%m-%d", "%Y/%m/%d", "%d/%m/%Y", "%m/%d/%y", "%d %b %Y", "%B %d, %Y", "%e %B %Y", "%y%m%d",
               "%Y%m%d", "%d.%m.%Y", "%b %d %Y", "%Y-%m-%d %H:%M", "%D", "%F", "%x")
date_pool <- c("2024-03-15", "2024/03/15", "2024-3-5", "15/03/2024", "03/15/24", "03/15/69", "03/15/68", "15 Mar 2024",
               "15 march 2024", "March 15, 2024", "mar 15 2024", " 5 January 2020", "5 January 2020", "240315", "20240315",
               "15.03.2024", "2024-02-29", "2023-02-29", "2024-13-01", "2024-00-10", "2024-01-32", "2000-02-29", "1900-02-29",
               "1970-01-01", "1969-12-31", "0001-01-01", "9999-12-31", "2024-03-15 10:30", "2024-03-15x", "", "x", "2024-03",
               "24-03-15", "2024-3-15", "2024 03 15", " 2024-03-15 ", "2024-03-15T10:00:00", "15/3/2024", "1/1/00", "12/31/99")
for (f in date_fmts) for (s in date_pool) {
  r <- quiet(parse_date(s, format = f))
  add("date", 0, c(s, f), na0(as.numeric(r)))
}

time_fmts <- c("%AT", "%H:%M:%S", "%H:%M", "%I:%M %p", "%I:%M:%S %p", "%H%M", "%T", "%R", "%X", "%H:%M:%OS", "%I%p")
time_pool <- c("10:30:15", "00:00:00", "23:59:59", "24:00:00", "12:00:00", "12:30 AM", "12:30 PM", "1:05 pm", "01:05 AM",
               "13:00 PM", "0:00 AM", "10:30", "1030", "10:30:15.5", "10:30:15.25", "7:3:9", "07:03:09", "23:60:00",
               "10:30:60", "10:30:61", "", "x", "10", "10pm", "10 PM", "10:30:15 PM", "00:30:15 AM", "-1:00:00", "100:00:00",
               "5pm", "11AM", "9:5", "10:30 pm", "10:30 Pm")
for (f in time_fmts) for (s in time_pool) {
  r <- quiet(parse_time(s, format = f))
  add("time", 0, c(s, f), na0(as.numeric(r)))
}

dt_fmts <- c("", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%d/%m/%Y %H:%M", "%Y-%m-%d %I:%M %p", "%Y%m%d%H%M%S",
             "%Y-%m-%d %H:%M:%OS", "%Y-%m-%d %H:%M:%S %z", "%AD %AT", "%Y-%m-%d%.%H", "%Y-%m-%d%*%H")
dt_pool <- c("2024-03-15T10:30:15", "2024-03-15 10:30:15", "2024-03-15", "2024-03-15T10", "2024-03-15T10:30", "2024-03-15T10:30:15Z",
             "2024-03-15T10:30:15+02:00", "2024-03-15T10:30:15-0530", "2024-03-15T10:30:15+02", "20240315T103015", "20240315",
             "2024-03-15T10:30:15.75", "2024-03-15T10:30:15.75Z", "2024-03-15 10:30:15 +0200", "2024-03-15 10:30:15 -01:30",
             "15/03/2024 10:30", "2024-03-15 10:30 PM", "2024-03-15 12:30 AM", "20240315103015", "2024-03-15 10:30:15.123456",
             "2024-02-30T10:00:00", "2024-03-15T25:00:00", "2024-03-15T24:00:00", "2024-03-15T23:59:60", "1970-01-01T00:00:00Z",
             "1969-12-31T23:59:59Z", "2038-01-19T03:14:08Z", "0001-01-01T00:00:00Z", "", "x", "2024-03-15X10:00", "2024-03-15 10",
             "2024-03-15T10:30:15 ", " 2024-03-15T10:30:15", "2024-3-5T1:2:3")
for (f in dt_fmts) for (s in dt_pool) {
  r <- quiet(if (nchar(f) == 0) parse_datetime(s) else parse_datetime(s, format = f))
  add("datetime", 0, c(s, f), na0(as.numeric(r)))
}

# read_delim: a short row is padded with empty fields, a long row's last column takes the rest of the row.
q <- "\""
delim_texts <- list(
  "a,b,c\n1,2,3\n4,5,6\n", "a,b\n1,2\n", "a,b", "a,b\n\n1,2\n", "a,b\r\n1,2\r\n", "a,,c\n,,\n", "\"x,y\",b\n1,2\n",
  "\"he said \"\"hi\"\"\",b\n1,2\n", "\"a\nb\",c\n1,2\n", " a , b \n 1 , 2 \n", "\" a \",b\n1,2\n", "a,b\n1,2\n\n\n",
  "\"a\"\"\",\"b\"\n1,2\n", "x\\,y,b\n1,2\n", "a,b # c\n1,2\n", "# top\na,b\n1,2\n", "a,b\n1,2 # tail\n",
  "a,b\n\"q\"x,2\n", "é,日本\n1,2\n", "a,b\n1,\n", "a,b\n,2\n", "\"\",b\n1,2\n", "a,b\n\"1\",\"2\"\n", "1\n2\n3\n",
  "a\n1,2\n3\n", "a,b\n1\n3,4,5\n6,7\n", "a,b\n1,2,3\n", "a\n\"x,y\",2\n", "a,b\n1,2,3,4\n", "a,b\n1,\"x,y\",3\n",
  "a,b\n1,\"x\"\"y\",3\n", "a,b\n1, 2 , 3 \n", "a,b\n1,2,\n", "a,b\n1,2,,\n", "a,b\n1,2,3 # c\n", "a,b\n1,\"q\"x,3\n",
  "a,b\n1,2\\,3,4\n", "a,b,c\n1\n", "a,b,c\n1,2\n", "a\n\"x\ny\",2\n3\n", "a,b\n\n1,2,3\n\n4,5\n",
  "a,b\n\"1,2\n", "a,b\n1,\"2\n3,4\n", "a,b\n1,\"x", "a,b\n1,2,\"x,y\n", "a,b\n1,\"x\n")
for (txt in delim_texts) for (dl in c(",", ";", "\t")) for (qt in c(q, "")) for (cm in c("", "#")) for (flags in list(c(0, 1, 1), c(1, 0, 0), c(0, 0, 0), c(0, 1, 0))) {
  if (grepl("\\\"", txt, fixed = TRUE) && nchar(qt) && flags[1] == 0) next # readr 2.2.0 crashes on a quote left open in the first field (not generated)
  t2 <- if (dl == ",") txt else gsub(",", dl, txt, fixed = TRUE)
  if (dl != ",") t2 <- gsub("\\;", ";", t2, fixed = TRUE)
  r <- tryCatch(quiet(read_delim(I(t2), delim = dl, quote = qt, comment = cm, col_names = FALSE, col_types = cols(.default = "c"),
                                 escape_backslash = flags[1] == 1, escape_double = flags[2] == 1, trim_ws = flags[3] == 1,
                                 na = character(), skip_empty_rows = TRUE, progress = FALSE)), error = function(e) NULL)
  if (is.null(r)) next
  m <- as.matrix(r)
  if (any(is.na(m))) next
  rows <- apply(m, 1, function(x) paste(x, collapse = "\002"))
  add("delim", c(utf8ToInt(dl), if (nchar(qt)) utf8ToInt(qt) else 0, if (nchar(cm)) utf8ToInt(cm) else 0, flags), t2, paste(rows, collapse = "\001"))
}

# guess_parser over a column: args (guess_integer), in the strings; the answer is the type code
#   0 logical 1 integer 2 double 3 number 4 time 5 date 6 datetime 7 character
codes <- c(logical = 0, integer = 1, double = 2, number = 3, time = 4, date = 5, datetime = 6, character = 7)
gpool <- c("TRUE", "T", "true", "True", "t", "F", "FALSE", "false", "False", "f", "1", "0", "12", "-5", "+7", "007", "0012", "1.5", ".5", "5.", "1e5",
           "1E-3", "Inf", "-Inf", "NaN", "NA", "", "1,234", "1,234.56", "$1,234", "$1", "12%", "1 000", "1.234,56", "2024-03-15", "2024/03/15",
           "2024-3-5", "15/03/2024", "20240315", "2024-03-15 10:30:00", "2024-03-15T10:30:00", "2024-03-15T10:30:00Z", "2024-03-15 10:30", "10:30",
           "10:30:15", "10:30:15.5", "1:05", "24:00:00", "abc", "12abc", "1.2.3", "--1", "1e", "0x10", "2147483647", "2147483648", "99999999999",
           "-2147483647", "1d5", "12 ", " 12", "TRUE ", "(1)", "3.14", "1,5", "0", "-0", "0.5", "00.5", "1e+5", "1E5", "+.5", "-.5e3", "7:3", "23:59:59",
           "2024-02-30", "2024-13-01", "T ", "yes", "2024-03-15 25:00:00", "1,234,567", "12,34", "1.5e3")
gl <- function(x, gi) as.numeric(codes[[guess_parser(x, guess_integer = gi)]])
for (gi in c(FALSE, TRUE)) {
  for (v in gpool) add("guess", gi, v, gl(v, gi))
  for (k in 1:700) {
    n <- sample(2:5, 1)
    x <- sample(gpool, n, replace = TRUE)
    x <- x[nzchar(x) | runif(n) < 0.5]
    if (length(x) == 0) next
    add("guess", gi, x, gl(x, gi))
  }
}
# locale names: args (), in [string, format, names], names = "months;abbreviated months;days;abbreviated days;am|pm"
for (lang in c("en", "de", "fr", "es", "it", "nl", "pt", "ru", "sv", "pl")) {
  dn <- date_names_lang(lang)
  names_str <- paste(c(paste(dn$mon, collapse = "|"), paste(dn$mon_ab, collapse = "|"), paste(dn$day, collapse = "|"), paste(dn$day_ab, collapse = "|"), paste(dn$am_pm, collapse = "|")), collapse = ";")
  loc <- locale(date_names = lang)
  for (m in c(1, 2, 5, 8, 12)) for (d in c(1, 15, 31)) for (wd in c(1, 4, 7)) {
    cand <- list(
      c(sprintf("%s %02d %d", dn$mon[m], d, 2024), "%B %d %Y"), c(sprintf("%02d %s %d", d, dn$mon_ab[m], 2023), "%d %b %Y"),
      c(sprintf("%s, %02d %s %d", dn$day_ab[wd], d, dn$mon_ab[m], 2021), "%a, %d %b %Y"),
      c(sprintf("%s %s", dn$mon[m], "x"), "%B %d"))
    for (cc in cand) {
      r <- quiet(parse_date(cc[1], cc[2], locale = loc))
      cases[[length(cases) + 1]] <- case("date_loc", 0, na0(as.numeric(r)), input = c(cc, names_str))
    }
  }
  for (h in c(1, 9, 12)) for (ap in 1:2) {
    str <- sprintf("%02d:30 %s", h, dn$am_pm[ap])
    r <- quiet(parse_time(str, "%I:%M %p", locale = loc))
    cases[[length(cases) + 1]] <- case("time_loc", 0, na0(as.numeric(r)), input = c(str, "%I:%M %p", names_str))
    str2 <- sprintf("%s 2024 %02d:15 %s", dn$mon_ab[3], h, dn$am_pm[ap])
    r2 <- quiet(parse_datetime(str2, "%b %Y %I:%M %p", locale = loc))
    cases[[length(cases) + 1]] <- case("datetime_loc", 0, na0(as.numeric(r2)), input = c(str2, "%b %Y %I:%M %p", names_str))
  }
}
# time zones: a naive time is local to locale(tz); an offset in the text wins; a repeated hour is the earlier instant, a skipped one NA.
# in [string, format, zone]; the zones are those of e.tz.builtin
zones <- c("UTC", "America/New_York", "America/Los_Angeles", "America/Sao_Paulo", "Asia/Kathmandu", "Asia/Kolkata", "Asia/Tokyo",
           "Australia/Lord_Howe", "Australia/Sydney", "Europe/Berlin", "Europe/London", "Europe/Sofia", "Pacific/Auckland")
tzcase <- function(s, f, z) {
  l <- locale(tz = z)
  r <- quiet(if (nchar(f) == 0) parse_datetime(s, locale = l) else parse_datetime(s, f, locale = l))
  cases[[length(cases) + 1]] <<- case("datetime_tz", 0, na0(as.numeric(r)), input = c(s, f, z))
}
fixed <- c("2024-06-15T12:00:00", "2024-06-15T12:00:00Z", "2024-06-15T12:00:00+0200", "2024-06-15 12:00:00-05:30", "1950-06-15T12:00:00",
           "1900-01-01T00:00:00", "1999-12-31T23:59:59", "2000-02-29T12:00:00", "2100-07-01T00:00:00", "2100-01-01T00:00:00",
           "2200-03-15T08:00:00", "2024-06-15T12:00:00.5", "2024-06-15T23:59:60", "2024-06-15T24:00:00", "2024-06-15", "2024-06-15T12", "x", "")
for (z in zones) {
  for (s in fixed) tzcase(s, "", z)
  tzcase("2024-06-15 12:00:00", "%Y-%m-%d %H:%M:%S", z); tzcase("15/06/2024", "%d/%m/%Y", z); tzcase("2024-06-15 12:00:00 +0100", "%Y-%m-%d %H:%M:%S %z", z)
  for (mo in c(3, 4, 9, 10, 11)) for (d in 1:31) for (hm in c("00:30", "01:30", "02:15", "03:30")) {
    if (mo %in% c(4, 9, 10) && d > 30) next
    tzcase(sprintf("2024-%02d-%02dT%s:00", mo, d, hm), "", z)
  }
}
emit("readr", "readr", list(cases))
