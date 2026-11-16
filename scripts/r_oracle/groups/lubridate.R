# lubridate and timeDate, the date part. Dates are day counts since 1970-01-01.
#   fn "easter" (year); "madd" (day, months, mode 0 %m+% and add_with_rollback, 2 roll_to_first);
#   "quarter" "semester" "decimal" "epiweek" "epiyear" "isoweek" "isoyear" (day);
#   "floor_<u>" "ceil_<u>" (day, week_start) with u in week month quarter semester year
suppressMessages({ library(lubridate); library(timeDate) })
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-9)
set.seed(20261116)
for (y in c(1900:2100)) add("easter", c(y, 0, 0), as.numeric(as.Date(format(Easter(y)))))
days <- c(as.numeric(as.Date(c("2020-02-29", "2021-01-31", "2023-12-31", "2024-01-01", "2020-12-31", "2021-01-03", "2027-01-01", "2026-01-01"))),
          sample(as.numeric(as.Date("1950-01-01")):as.numeric(as.Date("2060-12-31")), 160))
nm <- c("week", "month", "quarter", "semester", "year"); un <- c("week", "month", "quarter", "6 months", "year")
for (dn in days) {
  d <- as.Date(dn, origin = "1970-01-01")
  for (mo in c(-14, -1, 1, 2, 13)) {
    add("madd", c(dn, mo, 0), as.numeric(d %m+% months(mo)))
    add("madd", c(dn, mo, 2), as.numeric(add_with_rollback(d, months(mo), roll_to_first = TRUE)))
  }
  add("quarter", c(dn, 0, 0), quarter(d)); add("semester", c(dn, 0, 0), semester(d)); add("decimal", c(dn, 0, 0), decimal_date(d))
  add("epiweek", c(dn, 0, 0), epiweek(d)); add("epiyear", c(dn, 0, 0), epiyear(d))
  add("isoweek", c(dn, 0, 0), isoweek(d)); add("isoyear", c(dn, 0, 0), isoyear(d))
  for (u in 1:5) for (ws in if (u == 1) c(1, 7, 3) else 1) {
    add(paste0("floor_", nm[u]), c(dn, ws, 0), as.numeric(floor_date(d, un[u], week_start = ws)))
    add(paste0("ceil_", nm[u]), c(dn, ws, 0), as.numeric(ceiling_date(d, un[u], week_start = ws, change_on_boundary = FALSE)))
  }
}
emit("lubridate", c("lubridate", "timeDate"), list(cases))
